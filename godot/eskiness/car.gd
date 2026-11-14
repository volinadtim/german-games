extends StaticBody3D
## Старая ржавая легковушка на поляне (промпт 14.11 18:07). Советский седан «копейка»: выцветшая
## голубая краска облуплена до ржавчины (worn_metal.gdshader), дверь в красном грунте, лобовое стекло
## выбито, водительское окно тоже, одна фара разбита, заднее правое колесо спущено — машина осела на угол.
## Ключ (car_key) лежит в сейфе. С ключом [E] — кат-сцена: садишься, стартер «чух-чух» дважды не схватывает,
## на третий раз мотор заводится, фара загорается, машина уезжает с поляны, экран темнеет — победа (game.gd: win).
## Стоит всегда в одном месте (surface.gd: CAR_POS / CAR_YAW), в сейв не пишется.
## Перед машины — +Z, водительская сторона — +X. Интерфейс взаимодействия: get_prompt(game), interact(game).

const Surface := preload("res://surface.gd")
const WornMetal := preload("res://worn_metal.gdshader")
const Sfx2 := preload("res://sfx_extra.gd")

const WHEEL_R := 0.29
const WHEELS := [Vector3(0.69, WHEEL_R, 1.22), Vector3(-0.69, WHEEL_R, 1.22), Vector3(0.69, WHEEL_R, -1.22), Vector3(-0.69, WHEEL_R, -1.22)]
const FLAT := 3                 # спущенное колесо — заднее правое
const FLAT_SAG := 0.08          # насколько осел угол
const CRANK_AT := 0.5           # через сколько после «сел» включается стартер
const DRIVE_AT := CRANK_AT + Sfx2.STARTER_CATCH + 1.5
const CAM_OFF := Vector3(1.4, 2.7, -6.6)   # камера кат-сцены: сзади-слева, сверху

var game                        # game.gd
var surface: Node               # surface.gd — высота земли
var rig: Node3D                 # всё видимое (трясётся при заводке, корпус-коллизия — сам StaticBody)
var wheels: Array[Node3D] = []
var worn_mats: Array[ShaderMaterial] = []
var head_l: SpotLight3D
var lens_mat: StandardMaterial3D
var tail_mat: StandardMaterial3D
var smoke: CPUParticles3D
var driver: Node3D
var cam: Camera3D
var starter: AudioStreamPlayer
var engine: AudioStreamPlayer
var _noise_tex: NoiseTexture2D

var state := "idle"             # idle → start → drive → done
var t := 0.0
var speed := 0.0
var start_pos := Vector3.ZERO
var yaw := 0.0
var caught := false
var win_called := false


func _ready() -> void:
	yaw = rotation.y
	if surface:
		transform = _fit(position, yaw, true)
	start_pos = position
	rig = Node3D.new()
	add_child(rig)
	_build()
	_collide(Vector3(1.64, 0.7, 4.12), Vector3(0, 0.55, 0))
	_collide(Vector3(1.42, 0.52, 1.95), Vector3(0, 1.14, -0.22))


# ---------- взаимодействие ----------

func get_prompt(g) -> String:
	if state != "idle":
		return ""
	if g.inv.count("car_key") > 0:
		return "[E] Завести и уехать"
	return "Заперто. Нужен ключ"


func interact(g) -> void:
	if state != "idle":
		return
	if g.inv.count("car_key") <= 0:
		g.hud.toast("Заперто. Нужен ключ")
		g.play_at("clunk", global_position + global_transform.basis * Vector3(0.8, 0.8, 0.2), -10.0, 1.4)
		return
	escape()


## Кат-сцена отъезда. Можно вызвать и без ключа (проверочный скрипт).
func escape() -> void:
	if state != "idle":
		return
	state = "start"
	t = 0.0
	if game:
		game.begin_escape()
		game.play_at("clunk", global_position + global_transform.basis * Vector3(0.8, 0.8, 0.2), -4.0, 0.8)
	driver.visible = true
	# камера сзади-слева и сверху — так её не загораживают враги на поляне
	cam = Camera3D.new()
	cam.fov = 60.0
	cam.top_level = true
	add_child(cam)
	cam.global_position = _cam_want(CAM_OFF)
	cam.look_at(_cam_look())
	cam.current = true
	starter = AudioStreamPlayer.new()
	starter.stream = Sfx2.starter()
	starter.volume_db = -3.0
	add_child(starter)
	engine = AudioStreamPlayer.new()
	engine.stream = Sfx2.engine_loop()
	engine.volume_db = -60.0
	add_child(engine)


func _process(delta: float) -> void:
	if state == "idle" or state == "done":
		return
	t += delta
	var st := t - CRANK_AT
	if starter and not starter.playing and st >= 0.0 and st < 0.2:
		starter.play()
	if state == "start":
		# тряска: при попытках стартера — мелкая дрожь, мотор схватил — рывок, потом ровная вибрация
		var shake := 0.0
		for c in [[0.0, 0.85], [1.25, 0.95], [2.55, 1.0]]:
			if st > float(c[0]) and st < float(c[0]) + float(c[1]):
				shake = 0.004
		if st >= Sfx2.STARTER_CATCH:
			if not caught:
				caught = true
				_on_catch()
			var k := st - Sfx2.STARTER_CATCH
			shake = 0.004 + 0.02 * exp(-k * 3.0)
			if head_l:
				# лампа старая: сперва моргает, потом горит ровно
				var flick := 1.0 if k > 0.6 or fmod(k * 13.0, 1.0) > 0.4 else 0.15
				head_l.light_energy = 3.2 * flick
				lens_mat.emission_energy_multiplier = 2.5 * flick
		rig.position = Vector3(randf_range(-1, 1) * shake * 0.5, randf_range(-1, 1) * shake, randf_range(-1, 1) * shake * 0.3)
		rig.rotation.z = randf_range(-1, 1) * shake * 0.6
		# камера медленно наезжает
		cam.global_position = cam.global_position.lerp(_cam_want(CAM_OFF * 0.85), 1.0 - exp(-0.12 * delta))
		cam.look_at(_cam_look())
		if t >= DRIVE_AT:
			state = "drive"
			t = 0.0
			engine.play()
	elif state == "drive":
		speed = minf(speed + 3.6 * delta, 12.0)
		var fwd := Vector3(sin(yaw), 0, cos(yaw))
		var p := position + fwd * speed * delta
		var target := _fit(p, yaw, false)
		transform = Transform3D(transform.basis.slerp(target.basis, 1.0 - exp(-8.0 * delta)), target.origin)
		for w in wheels:
			w.rotation.x += speed / WHEEL_R * delta
		var vib := 0.006 + speed * 0.001
		rig.position = Vector3(0, randf_range(-1, 1) * vib, 0)
		rig.rotation.z = randf_range(-1, 1) * vib * 0.5
		for m in worn_mats:
			m.set_shader_parameter("origin_shift", position - start_pos)
		engine.volume_db = lerpf(engine.volume_db, -4.0, 1.0 - exp(-4.0 * delta))
		engine.pitch_scale = 0.85 + speed * 0.09
		# камера едет следом с отставанием — машина понемногу отрывается
		cam.global_position = cam.global_position.lerp(_cam_want(CAM_OFF), 1.0 - exp(-1.2 * delta))
		cam.look_at(_cam_look())
		if t > 1.3 and not win_called:
			win_called = true
			if game:
				game.win()
		if t > 8.0:
			state = "done"
			engine.stop()
		elif t > 5.0:
			engine.volume_db -= delta * 12.0


## Где должна стоять камера: смещение в осях машины (без наклона), не ниже земли.
func _cam_want(off: Vector3) -> Vector3:
	var p := position + Basis(Vector3.UP, yaw) * off
	if surface:
		p.y = maxf(p.y, surface.height(p.x, p.z) + 1.4)
	return p


func _cam_look() -> Vector3:
	return position + Basis(Vector3.UP, yaw) * Vector3(0, 0.7, 2.0)


func _on_catch() -> void:
	smoke.emitting = true
	_smoke_burst()
	tail_mat.emission_energy_multiplier = 1.4
	if game:
		game.play_at("thud", global_position, -14.0, 0.6)


## Чёрный клуб из выхлопной трубы, когда мотор схватил.
func _smoke_burst() -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = 24
	p.lifetime = 1.6
	p.direction = Vector3(0, 0.3, -1)
	p.spread = 35.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.5
	p.gravity = Vector3(0, 0.6, 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.6
	p.mesh = _smoke_mesh(Color(0.06, 0.06, 0.06, 0.65))
	_smoke_fade(p)
	p.position = smoke.position
	rig.add_child(p)
	p.emitting = true
	get_tree().create_timer(2.5).timeout.connect(p.queue_free)


## Положение машины на неровной земле: высота — средняя по колёсам, наклон — по разнице спереди/сзади
## и слева/справа; угол со спущенным колесом ниже (sag).
func _fit(p: Vector3, a: float, sag: bool) -> Transform3D:
	var yb := Basis(Vector3.UP, a)
	var h: Array[float] = []
	for i in 4:
		var w: Vector3 = p + yb * Vector3(WHEELS[i].x, 0, WHEELS[i].z)
		h.append(surface.height(w.x, w.z) - (FLAT_SAG if sag and i == FLAT else 0.0))
	var front := (h[0] + h[1]) / 2.0
	var rear := (h[2] + h[3]) / 2.0
	var left := (h[0] + h[2]) / 2.0
	var right := (h[1] + h[3]) / 2.0
	var pitch := -atan((front - rear) / 2.44)
	var roll := atan((left - right) / 1.38)
	var b := yb * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, roll)
	return Transform3D(b, Vector3(p.x, (front + rear) / 2.0 - 0.01, p.z))


# ---------- модель ----------

func _build() -> void:
	var paint := _worn(Color(0.3, 0.44, 0.46), false, 0.22, 0.9, 0.45)      # выцветшая «морская волна»
	var primer := _worn(Color(0.42, 0.17, 0.12), false, 0.12, 0.6, 0.35)    # дверь от другой машины, в грунте
	var chrome := _worn(Color(0.62, 0.61, 0.58), true, 0.0, 0.8, 0.6)
	var steel := _worn(Color(0.2, 0.2, 0.19), false, 0.2, 0.7, 0.4)        # крашеные диски
	var dark := _mat(Color(0.035, 0.033, 0.03), 0.0, 0.95)
	var rubber := _mat(Color(0.05, 0.048, 0.045), 0.0, 0.95)
	var rust := _mat(Color(0.24, 0.1, 0.045), 0.3, 1.0)
	var seat := _mat(Color(0.3, 0.17, 0.1), 0.0, 0.65)                      # коричневый дерматин
	var glass := _mat(Color(0.12, 0.15, 0.14, 0.5), 0.3, 0.12)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var dirty := _mat(Color(0.3, 0.28, 0.22, 0.75), 0.0, 0.8)               # заднее стекло в грязи
	dirty.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	# колёса
	for i in 4:
		var w := Node3D.new()
		w.position = WHEELS[i]
		rig.add_child(w)
		wheels.append(w)
		var side := signf(WHEELS[i].x)
		_cyl(w, WHEEL_R, 0.18, Vector3.ZERO, rubber, 18)
		_cyl(w, 0.175, 0.19, Vector3(0.002 * side, 0, 0), steel, 14)
		if i != 1:   # переднего правого колпака нет
			_cyl(w, 0.11, 0.2, Vector3(0.004 * side, 0, 0), chrome, 14)
		# протектор — поперечные полоски, видно, как крутится колесо
		for k in 8:
			var a := TAU * k / 8.0
			var tb := _box(Vector3(0.185, 0.03, 0.05), Vector3(0, sin(a), cos(a)) * WHEEL_R, rubber, Vector3(PI / 2 - a, 0, 0), w)
			tb.material_override = dark
		if i == FLAT:
			# спущенная резина распласталась по земле
			_box(Vector3(0.24, 0.07, 0.42), Vector3(0, -WHEEL_R + 0.04, 0), rubber, Vector3.ZERO, w)

	# кузов: низ, пороги, фартуки под бамперами
	_box(Vector3(1.6, 0.44, 4.0), Vector3(0, 0.64, 0), paint)
	_box(Vector3(1.56, 0.16, 1.55), Vector3(0, 0.34, 0), paint)
	_box(Vector3(1.56, 0.12, 0.42), Vector3(0, 0.36, 1.79), paint)
	_box(Vector3(1.56, 0.12, 0.42), Vector3(0, 0.36, -1.79), paint)
	# капот и багажник — чуть выпуклые крышки с зазором
	_box(Vector3(1.46, 0.035, 1.1), Vector3(0, 0.875, 1.42), paint, Vector3(0.012, 0, 0))
	_box(Vector3(1.46, 0.035, 0.84), Vector3(0, 0.875, -1.55), paint, Vector3(-0.02, 0, 0.01))
	_box(Vector3(1.5, 0.006, 0.02), Vector3(0, 0.861, 0.86), dark)
	_box(Vector3(1.5, 0.006, 0.02), Vector3(0, 0.861, -1.13), dark)
	# колёсные арки — тёмные выемки над колёсами, по краю рыжая гниль
	for wp in WHEELS:
		var sx := signf(wp.x)
		_box(Vector3(0.008, 0.2, 0.72), Vector3(0.802 * sx, 0.5, wp.z), dark)
		_box(Vector3(0.01, 0.05, 0.78), Vector3(0.803 * sx, 0.61, wp.z), rust)
	# дыры от ржавчины на порогах и низу дверей
	_box(Vector3(0.01, 0.07, 0.3), Vector3(0.803, 0.39, -0.45), rust)
	_box(Vector3(0.01, 0.05, 0.18), Vector3(0.804, 0.38, -0.47), dark)
	_box(Vector3(0.01, 0.09, 0.22), Vector3(-0.803, 0.47, 0.55), rust)
	_box(Vector3(0.01, 0.06, 0.4), Vector3(-0.803, 0.36, -0.3), rust)

	# двери: швы, ручки, правая передняя — в красном грунте
	for sx in [1.0, -1.0]:
		for z in [0.86, -0.24, -1.1]:
			_box(Vector3(0.006, 0.42, 0.012), Vector3(0.802 * sx, 0.65, z), dark)
		_box(Vector3(0.006, 0.012, 1.96), Vector3(0.802 * sx, 0.44, -0.12), dark)
		_box(Vector3(0.02, 0.03, 0.12), Vector3(0.81 * sx, 0.8, -0.1), chrome)
		_box(Vector3(0.02, 0.03, 0.12), Vector3(0.81 * sx, 0.8, -0.96), chrome)
		# молдинг вдоль борта
		_box(Vector3(0.015, 0.02, 3.9), Vector3(0.806 * sx, 0.72, 0), chrome)
	_box(Vector3(0.012, 0.4, 1.08), Vector3(-0.805, 0.645, 0.31), primer)

	# салон: пол-«ванна» по линии окон, сиденья, торпедо, руль
	_box(Vector3(1.4, 0.02, 1.95), Vector3(0, 0.865, -0.22), dark)
	for sx in [1.0, -1.0]:
		_box(Vector3(0.52, 0.1, 0.5), Vector3(0.36 * sx, 0.92, -0.02), seat)
		_box(Vector3(0.5, 0.4, 0.1), Vector3(0.36 * sx, 1.08, -0.3), seat, Vector3(-0.15, 0, 0))
		_box(Vector3(0.26, 0.1, 0.08), Vector3(0.36 * sx, 1.27, -0.34), seat, Vector3(-0.15, 0, 0))
	_box(Vector3(1.24, 0.1, 0.5), Vector3(0, 0.92, -0.78), seat)
	_box(Vector3(1.24, 0.44, 0.1), Vector3(0, 1.1, -1.02), seat, Vector3(-0.2, 0, 0))
	_box(Vector3(1.38, 0.14, 0.26), Vector3(0, 0.94, 0.68), dark)
	var tor := TorusMesh.new()
	tor.inner_radius = 0.15
	tor.outer_radius = 0.18
	tor.rings = 16
	tor.ring_segments = 6
	var wheel_mi := MeshInstance3D.new()
	wheel_mi.mesh = tor
	wheel_mi.material_override = dark
	wheel_mi.position = Vector3(0.36, 1.04, 0.46)
	wheel_mi.rotation.x = -1.05
	rig.add_child(wheel_mi)
	_box(Vector3(0.03, 0.03, 0.22), Vector3(0.36, 1.0, 0.56), dark, Vector3(-0.5, 0, 0))
	# водитель — тёмный силуэт, появляется в кат-сцене
	driver = Node3D.new()
	driver.visible = false
	rig.add_child(driver)
	var who := _mat(Color(0.06, 0.055, 0.05), 0.0, 0.9)
	_box(Vector3(0.42, 0.32, 0.24), Vector3(0.36, 1.02, -0.14), who, Vector3.ZERO, driver)
	var hs := SphereMesh.new()
	hs.radius = 0.1
	hs.height = 0.22
	var head := MeshInstance3D.new()
	head.mesh = hs
	head.material_override = who
	head.position = Vector3(0.36, 1.23, -0.12)
	driver.add_child(head)

	# крыша, стойки, стёкла
	_box(Vector3(1.38, 0.06, 1.48), Vector3(0, 1.37, -0.22), paint)
	_box(Vector3(1.4, 0.02, 0.03), Vector3(0, 1.335, 0.52), chrome)   # водосток над лобовым
	for sx in [1.0, -1.0]:
		_beam(Vector3(0.7 * sx, 0.87, 0.86), Vector3(0.67 * sx, 1.36, 0.51), 0.07, 0.06, paint)    # A
		_beam(Vector3(0.71 * sx, 0.87, -0.22), Vector3(0.68 * sx, 1.36, -0.22), 0.07, 0.1, paint)  # B
		_beam(Vector3(0.7 * sx, 0.87, -1.13), Vector3(0.67 * sx, 1.36, -0.94), 0.07, 0.16, paint)  # C
	# лобовое выбито: снизу торчит неровная кромка с осколками
	var wa := Vector3(0, 0.88, 0.85)
	var wb := Vector3(0, 1.34, 0.52)
	_beam(wa, wa.lerp(wb, 0.16), 0.01, 1.34, glass)
	var shard_rng := RandomNumberGenerator.new()
	shard_rng.seed = 18
	for k in 9:
		var x := -0.62 + k * 0.155 + shard_rng.randf_range(-0.04, 0.04)
		var hgt := shard_rng.randf_range(0.04, 0.16) if k != 2 and k != 7 else shard_rng.randf_range(0.2, 0.32)
		var pm := PrismMesh.new()
		pm.size = Vector3(shard_rng.randf_range(0.08, 0.16), hgt, 0.006)
		pm.left_to_right = shard_rng.randf()
		var base := wa.lerp(wb, 0.15)
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		mi.material_override = glass
		var up := (wb - wa).normalized()
		mi.transform = Transform3D(Basis(Vector3.RIGHT, up, Vector3.RIGHT.cross(up)), base + Vector3(x, 0, 0) + up * hgt * 0.5)
		rig.add_child(mi)
	# боковые стёкла: водительского нет — только огрызок у двери
	_box(Vector3(0.01, 0.42, 0.68), Vector3(-0.69, 1.1, 0.16), glass)
	_box(Vector3(0.01, 0.07, 0.68), Vector3(0.69, 0.9, 0.16), glass)
	_box(Vector3(0.01, 0.42, 0.66), Vector3(0.69, 1.1, -0.6), glass)
	_box(Vector3(0.01, 0.42, 0.66), Vector3(-0.69, 1.1, -0.6), dirty)
	_beam(Vector3(0, 0.88, -1.12), Vector3(0, 1.34, -0.95), 0.01, 1.3, dirty)
	# зеркало только водительское
	_box(Vector3(0.12, 0.02, 0.02), Vector3(0.82, 0.93, 0.76), chrome)
	_box(Vector3(0.05, 0.08, 0.12), Vector3(0.88, 0.97, 0.76), chrome, Vector3(0, 0.2, 0))

	# перед: решётка, фары (левая разбита), бампер с клыками, номер
	_box(Vector3(1.0, 0.17, 0.03), Vector3(0, 0.7, 2.005), dark)
	for y in [0.79, 0.61]:
		_box(Vector3(1.04, 0.02, 0.035), Vector3(0, y, 2.01), chrome)
	for y in [0.66, 0.7, 0.74]:
		_box(Vector3(0.98, 0.01, 0.03), Vector3(0, y, 2.012), chrome)
	lens_mat = _mat(Color(0.75, 0.72, 0.6), 0.0, 0.2)
	lens_mat.emission_enabled = true
	lens_mat.emission = Color(1.0, 0.85, 0.55)
	lens_mat.emission_energy_multiplier = 0.0
	for sx in [1.0, -1.0]:
		var hp := Vector3(0.64 * sx, 0.71, 2.0)
		_cyl_z(Vector3(hp.x, hp.y, hp.z + 0.01), 0.108, 0.035, chrome)
		if sx > 0:
			_cyl_z(Vector3(hp.x, hp.y, hp.z + 0.022), 0.09, 0.02, dark)      # пустая глазница
			var pm := PrismMesh.new()
			pm.size = Vector3(0.07, 0.06, 0.005)
			var sh := MeshInstance3D.new()
			sh.mesh = pm
			sh.material_override = glass
			sh.position = Vector3(hp.x + 0.03, hp.y - 0.05, hp.z + 0.035)
			rig.add_child(sh)
		else:
			_cyl_z(Vector3(hp.x, hp.y, hp.z + 0.024), 0.09, 0.02, lens_mat)
	_box(Vector3(1.66, 0.08, 0.06), Vector3(0, 0.45, 2.04), chrome)
	for sx in [1.0, -1.0]:
		_box(Vector3(0.05, 0.15, 0.05), Vector3(0.33 * sx, 0.47, 2.08), chrome)
	_plate(Vector3(0, 0.34, 2.05))

	# зад: фонари (правый треснул), гнутый бампер, номер, выхлопная труба
	tail_mat = _mat(Color(0.5, 0.06, 0.04), 0.0, 0.3)
	tail_mat.emission_enabled = true
	tail_mat.emission = Color(0.9, 0.08, 0.03)
	tail_mat.emission_energy_multiplier = 0.1
	_box(Vector3(0.28, 0.14, 0.03), Vector3(0.6, 0.7, -2.005), tail_mat)
	_box(Vector3(0.28, 0.14, 0.03), Vector3(-0.6, 0.7, -2.005), tail_mat)
	_box(Vector3(0.12, 0.08, 0.034), Vector3(-0.66, 0.68, -2.006), dark, Vector3(0, 0, 0.3))
	_box(Vector3(1.66, 0.08, 0.06), Vector3(0, 0.43, -2.04), chrome, Vector3(0, 0.04, -0.07))
	_plate(Vector3(0, 0.6, -2.025), true)
	_cyl_z(Vector3(-0.45, 0.25, -1.96), 0.03, 0.25, rust)
	smoke = CPUParticles3D.new()
	smoke.position = Vector3(-0.45, 0.25, -2.1)
	smoke.amount = 26
	smoke.lifetime = 2.2
	smoke.direction = Vector3(0, 0.4, -1)
	smoke.spread = 25.0
	smoke.initial_velocity_min = 0.5
	smoke.initial_velocity_max = 1.1
	smoke.gravity = Vector3(0, 0.35, 0)
	smoke.damping_min = 0.4
	smoke.damping_max = 0.8
	smoke.scale_amount_min = 0.8
	smoke.scale_amount_max = 2.2
	smoke.local_coords = false
	smoke.mesh = _smoke_mesh(Color(0.2, 0.2, 0.2, 0.3))
	_smoke_fade(smoke)
	smoke.emitting = false
	rig.add_child(smoke)
	head_l = SpotLight3D.new()
	head_l.position = Vector3(-0.64, 0.71, 2.1)
	head_l.rotation = Vector3(-0.08, PI, 0)
	head_l.light_color = Color(1.0, 0.86, 0.6)
	head_l.light_energy = 0.0
	head_l.spot_range = 22.0
	head_l.spot_angle = 28.0
	head_l.shadow_enabled = true
	rig.add_child(head_l)

	# осколки водительского стекла в траве у двери
	for k in 6:
		var pm := PrismMesh.new()
		pm.size = Vector3(shard_rng.randf_range(0.04, 0.09), shard_rng.randf_range(0.05, 0.1), 0.004)
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		mi.material_override = glass
		mi.position = Vector3(shard_rng.randf_range(0.95, 1.5), 0.02, shard_rng.randf_range(-0.2, 0.6))
		mi.rotation = Vector3(-PI / 2 + shard_rng.randf_range(-0.2, 0.2), shard_rng.randf() * TAU, 0)
		add_child(mi)


## Номерной знак: грязно-белая табличка с чёрными знаками (старого образца: «буква цифры буквы»).
func _plate(pos: Vector3, rear := false) -> void:
	var z := 1.0 if not rear else -1.0
	_box(Vector3(0.52, 0.12, 0.012), pos, _mat(Color(0.62, 0.6, 0.52), 0.0, 0.8))
	var ink := _mat(Color(0.04, 0.04, 0.04), 0.0, 0.9)
	var xs := [-0.2, -0.13, -0.06, 0.01, 0.08, 0.15, 0.21]
	for k in xs.size():
		var tall := k >= 1 and k <= 4
		_box(Vector3(0.035, 0.07 if tall else 0.05, 0.004), pos + Vector3(float(xs[k]) * z, -0.005 if not tall else 0.0, 0.008 * z), ink)


# ---------- помощники ----------

func _noise() -> NoiseTexture2D:
	if _noise_tex == null:
		var n := FastNoiseLite.new()
		n.seed = 2101
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 0.05
		n.fractal_octaves = 3
		_noise_tex = NoiseTexture2D.new()
		_noise_tex.width = 128
		_noise_tex.height = 128
		_noise_tex.seamless = true
		_noise_tex.noise = n
	return _noise_tex


func _worn(c: Color, chrome := false, wear := 0.3, rust := 0.6, dust := 0.6) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WornMetal
	m.set_shader_parameter("n_px", _noise())
	m.set_shader_parameter("n_lin", _noise())
	m.set_shader_parameter("paint_color", c)
	m.set_shader_parameter("chrome", 1.0 if chrome else 0.0)
	m.set_shader_parameter("wear", wear)
	m.set_shader_parameter("rust", rust)
	m.set_shader_parameter("dust", dust)
	m.set_shader_parameter("rust_color", Color(0.36, 0.16, 0.06))
	m.set_shader_parameter("base_y", position.y)
	worn_mats.append(m)
	return m


func _mat(c: Color, metal := 0.0, rough := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m


func _box(size: Vector3, pos: Vector3, m: Material, rot := Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	(parent if parent else rig).add_child(mi)
	return mi


## Брусок от точки a до точки b (стойки, наклонные стёкла): толщина thick, ширина вдоль X — wide.
func _beam(a: Vector3, b: Vector3, thick: float, wide: float, m: Material) -> MeshInstance3D:
	var d := b - a
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(wide, d.length(), thick)
	mi.mesh = bm
	mi.material_override = m
	var up := d.normalized()
	var fwd := Vector3.RIGHT.cross(up).normalized()
	mi.transform = Transform3D(Basis(Vector3.RIGHT, up, fwd).orthonormalized(), (a + b) / 2.0)
	rig.add_child(mi)
	return mi


## Цилиндр поперёк машины (ось X) — колёса.
func _cyl(parent: Node3D, r: float, h: float, pos: Vector3, m: Material, segs := 16) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = segs
	cm.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = m
	mi.position = pos
	mi.rotation.z = PI / 2
	parent.add_child(mi)
	return mi


## Цилиндр вдоль машины (ось Z) — фары, труба.
func _cyl_z(pos: Vector3, r: float, h: float, m: Material) -> MeshInstance3D:
	var mi := _cyl(rig, r, h, pos, m, 16)
	mi.rotation = Vector3(PI / 2, 0, 0)
	return mi


func _smoke_mesh(c: Color) -> Mesh:
	var bm := BoxMesh.new()
	bm.size = Vector3(0.1, 0.1, 0.1)
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 1.0
	m.metallic_specular = 0.0
	bm.material = m
	return bm


## Дым тает и чуть растёт к концу жизни.
func _smoke_fade(p: CPUParticles3D) -> void:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = g
	var cv := Curve.new()
	cv.add_point(Vector2(0, 0.6))
	cv.add_point(Vector2(1, 1.6))
	p.scale_amount_curve = cv


func _collide(size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	add_child(cs)
