extends CharacterBody3D
## Враг «Бетонник» (боёвка): сутулая фигура из бетона с тлеющими глазами и торчащей арматурой.
## Заметил игрока (видит и ближе 9 м) — идёт к нему, обходя стены через проёмы, замахивается и бьёт.
## На поверхности (спавн выше уровня земли) — бродит по поляне и гонится напрямую.
## От ударов кулаком отлетает и сбивается, умирая — рассыпает монеты и иногда предмет.
## Интерфейс урона: take_hit(урон, направление) — его вызывает player.gd при попадании.
## Два вида (kind, промпт 14.11 18:08): "heavy" — бетонник, медленный и тяжёлый;
## "fast" — «Шныга»: низкий худой, бегает рывками-прыжками, визжит, бьёт слабее и ближе, хлипкий.

signal died(enemy: Node)

const Fx := preload("res://fx.gd")
const Surface := preload("res://surface.gd")

const SPEED := 2.1
const SIGHT := 9.0
const ATTACK_RANGE := 1.35
const HIT_RANGE := 1.8
const DAMAGE := 12.0
const MAX_HP := 70.0
const LEASH := 14.0
const WANDER_SPEED := 0.85
## проёмы между комнатами и коридором — через них враг обходит стены
const DOORWAYS := [Vector3(-6, 0, -1.6), Vector3(-6, 0, 1.6), Vector3(6, 0, -1.6), Vector3(6, 0, 1.6), Vector3(0, 0, 5.5)]
## точки пути по бункеру: коридор, обе стороны каждого проёма, середины комнат, выход к лестнице.
## Между ними ищется кратчайший путь (связи — где точки видят друг друга), так враг находит дорогу в любую комнату.
const WAYPOINTS := [
	Vector3(-10.5, 0, 0), Vector3(-6, 0, 0), Vector3(0, 0, 0), Vector3(6, 0, 0), Vector3(11.3, 0, 0),
	Vector3(-6, 0, -0.9), Vector3(-6, 0, -2.4), Vector3(6, 0, -0.9), Vector3(6, 0, -2.4),
	Vector3(-6, 0, 0.9), Vector3(-6, 0, 2.4), Vector3(6, 0, 0.9), Vector3(6, 0, 2.4),
	Vector3(-0.9, 0, 5.5), Vector3(0.9, 0, 5.5),
	Vector3(-6, 0, -5.3), Vector3(6, 0, -5.3), Vector3(-6, 0, 5.3), Vector3(6, 0, 5.3),
]
static var _wp_links: Array = []    # для каждой точки — индексы видимых соседей (считаются один раз)

var game  # game.gd
var kind := "heavy"   # "heavy" | "fast" — выставить до add_child
## параметры вида (из _apply_kind): скорость погони, дистанции, урон, здоровье, замах, перезарядка, рост
var speed := SPEED
var attack_range := ATTACK_RANGE
var hit_range := HIT_RANGE
var damage := DAMAGE
var max_hp := MAX_HP
var windup_t := 0.55
var cool_t := 1.1
var height := 2.0
var dash_ph := 0.0    # быстрый: фаза рывка (рывок — пауза)
static var _screech_cache: Array = []
var home := Vector3.ZERO
var hunter := false   # наказание за мухлёж (game.gd: cheat_check): всегда гонится, спускается в бункер
var hp := MAX_HP   # выставляет _apply_kind
var state := "idle"
var st := 0.0
var knock := Vector3.ZERO
var walk_ph := 0.0
var walk_amt := 0.0
var cool := 0.0
var think := 0.0
var target := Vector3.ZERO
var growl_t := 3.0
var bar_t := 0.0
## на поверхности: бродит по поляне, гонится напрямую (без проёмов), в будку-выход не заходит
var surface := false
## агро: враг с поляны, заметивший игрока, идёт за ним и в будку, и вниз по лестнице в бункер —
## сейвзоны нет. Потерял из виду на LOSE_T секунд — поднимается обратно на поляну (состояние "return").
const LOSE_T := 8.0
const CHASE_MAX := 45.0     # дольше этого без вида игрока — точно сдаётся
var lost_t := 0.0
var blind_t := 0.0
var wander_t := 0.0

var vis: Node3D
var torso: Node3D
var arms: Array[Node3D] = []
var legs: Array[Node3D] = []
var mat: StandardMaterial3D
var bar: Node3D
var bar_fg: MeshInstance3D
var voice: AudioStreamPlayer3D
var body_snd: AudioStreamPlayer3D


func _apply_kind() -> void:
	if kind == "fast":
		speed = 4.3          # в среднем: быстрее шага игрока (3.4), медленнее бега (5.4)
		attack_range = 0.95
		hit_range = 1.3
		damage = 6.0
		max_hp = 32.0
		windup_t = 0.3
		cool_t = 0.8
		height = 1.45
	hp = max_hp


func _ready() -> void:
	_apply_kind()
	home = global_position
	target = home
	surface = home.y > Surface.G - 1.0
	wander_t = randf_range(0.0, 3.0)
	floor_snap_length = 0.3
	_build()
	voice = AudioStreamPlayer3D.new()
	voice.unit_size = 4.0
	voice.position.y = height * 0.8
	add_child(voice)
	body_snd = AudioStreamPlayer3D.new()
	body_snd.unit_size = 4.0
	body_snd.position.y = 1.0
	add_child(body_snd)


func _build() -> void:
	if kind == "fast":
		_build_fast()
		return
	mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.29, 0.27)
	mat.roughness = 1.0
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.7)
	mat.emission_energy_multiplier = 0.0
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.2, 0.19, 0.18)
	dark.roughness = 1.0
	var rebar := StandardMaterial3D.new()
	rebar.albedo_color = Color(0.22, 0.13, 0.08)
	rebar.metallic = 0.5
	rebar.roughness = 0.7
	var eye := StandardMaterial3D.new()
	eye.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye.albedo_color = Color(1.0, 0.55, 0.2)

	vis = Node3D.new()
	add_child(vis)

	for side in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(0.14 * side, 0.92, 0)
		vis.add_child(hip)
		var leg := CapsuleMesh.new()
		leg.radius = 0.1
		leg.height = 0.92
		_part(hip, leg, Vector3(0, -0.44, 0), mat)
		var foot := BoxMesh.new()
		foot.size = Vector3(0.16, 0.08, 0.26)
		_part(hip, foot, Vector3(0, -0.88, -0.05), dark)
		legs.append(hip)

	torso = Node3D.new()
	torso.position = Vector3(0, 0.9, 0)
	torso.rotation.x = -0.38
	vis.add_child(torso)
	var chest := CapsuleMesh.new()
	chest.radius = 0.25
	chest.height = 0.9
	var c := _part(torso, chest, Vector3(0, 0.42, 0), mat)
	c.scale = Vector3(1.2, 1.0, 0.8)
	# горб из обломков
	var hump := BoxMesh.new()
	hump.size = Vector3(0.36, 0.22, 0.2)
	var hm := _part(torso, hump, Vector3(0.05, 0.68, 0.14), dark)
	hm.rotation = Vector3(0.4, 0.3, 0.2)
	# торчащая арматура
	for k in 3:
		var rb := CylinderMesh.new()
		rb.top_radius = 0.012
		rb.bottom_radius = 0.012
		rb.height = 0.35 + 0.1 * k
		var r := _part(torso, rb, Vector3(-0.12 + 0.12 * k, 0.8, 0.12), rebar)
		r.rotation = Vector3(0.5 + 0.2 * k, 0.0, -0.4 + 0.35 * k)

	var head := Node3D.new()
	head.position = Vector3(0, 0.92, -0.1)
	torso.add_child(head)
	var hs := SphereMesh.new()
	hs.radius = 0.16
	hs.height = 0.3
	var h := _part(head, hs, Vector3.ZERO, mat)
	h.scale = Vector3(1.0, 0.9, 1.05)
	for side in [-1.0, 1.0]:
		var es := SphereMesh.new()
		es.radius = 0.025
		es.height = 0.05
		_part(head, es, Vector3(0.06 * side, 0.02, -0.15), eye)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.5, 0.2)
	glow.light_energy = 0.25
	glow.omni_range = 0.8
	glow.position = Vector3(0, 0.02, -0.3)
	head.add_child(glow)

	for side in [-1.0, 1.0]:
		var sh := Node3D.new()
		sh.position = Vector3(0.34 * side, 0.72, 0)
		sh.rotation.z = 0.12 * side
		torso.add_child(sh)
		var arm := CapsuleMesh.new()
		arm.radius = 0.08
		arm.height = 0.8
		_part(sh, arm, Vector3(0, -0.36, 0), mat)
		var fist := SphereMesh.new()
		fist.radius = 0.11
		fist.height = 0.2
		_part(sh, fist, Vector3(0, -0.78, 0), dark)
		arms.append(sh)

	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)

	# полоска здоровья над головой
	bar = Node3D.new()
	bar.position.y = 2.0
	bar.visible = false
	add_child(bar)
	_bar_quad(Color(0, 0, 0, 0.7), Vector2(0.62, 0.075), 0.0)
	bar_fg = _bar_quad(Color(0.7, 0.14, 0.08), Vector2(0.6, 0.055), 0.01)


## «Шныга»: ростом ~1.4 м, тощая, сильно сгорбленная, с длинными руками-палками и крупной головой.
## Бледная ржаво-серая кожа, белёсо-зелёные глаза, торчащие рёбра.
func _build_fast() -> void:
	mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.46, 0.38, 0.33)
	mat.roughness = 0.85
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.7)
	mat.emission_energy_multiplier = 0.0
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.22, 0.15, 0.13)
	dark.roughness = 0.9
	var rib := StandardMaterial3D.new()
	rib.albedo_color = Color(0.62, 0.55, 0.48)
	rib.roughness = 0.8
	var eye := StandardMaterial3D.new()
	eye.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye.albedo_color = Color(0.75, 1.0, 0.7)

	vis = Node3D.new()
	add_child(vis)
	for side in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(0.1 * side, 0.66, 0)
		vis.add_child(hip)
		var leg := CapsuleMesh.new()
		leg.radius = 0.05
		leg.height = 0.68
		var lg := _part(hip, leg, Vector3(0, -0.32, 0.03), mat)
		lg.rotation.x = 0.12
		var foot := BoxMesh.new()
		foot.size = Vector3(0.09, 0.05, 0.2)
		_part(hip, foot, Vector3(0, -0.64, -0.04), dark)
		legs.append(hip)

	torso = Node3D.new()
	torso.position = Vector3(0, 0.64, 0)
	torso.rotation.x = -0.75
	vis.add_child(torso)
	var chest := CapsuleMesh.new()
	chest.radius = 0.14
	chest.height = 0.62
	var c := _part(torso, chest, Vector3(0, 0.3, 0), mat)
	c.scale = Vector3(1.0, 1.0, 0.75)
	# рёбра и позвоночник
	for k in 4:
		var rb := BoxMesh.new()
		rb.size = Vector3(0.26 - 0.02 * k, 0.018, 0.04)
		_part(torso, rb, Vector3(0, 0.2 + 0.08 * k, -0.095), rib)
	for k in 5:
		var vb := SphereMesh.new()
		vb.radius = 0.03
		vb.height = 0.05
		_part(torso, vb, Vector3(0, 0.1 + 0.1 * k, 0.1), rib)

	var head := Node3D.new()
	head.position = Vector3(0, 0.66, -0.1)
	head.rotation.x = 0.6   # голова задрана вперёд, морда к игроку
	torso.add_child(head)
	var hs := SphereMesh.new()
	hs.radius = 0.13
	hs.height = 0.26
	var h := _part(head, hs, Vector3.ZERO, mat)
	h.scale = Vector3(0.9, 0.95, 1.2)
	var jaw := BoxMesh.new()
	jaw.size = Vector3(0.14, 0.04, 0.14)
	var jw := _part(head, jaw, Vector3(0, -0.1, -0.07), dark)
	jw.rotation.x = -0.35
	for side in [-1.0, 1.0]:
		var es := SphereMesh.new()
		es.radius = 0.028
		es.height = 0.056
		_part(head, es, Vector3(0.055 * side, 0.02, -0.14), eye)
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.7, 1.0, 0.6)
	glow.light_energy = 0.2
	glow.omni_range = 0.6
	glow.position = Vector3(0, 0.02, -0.25)
	head.add_child(glow)

	for side in [-1.0, 1.0]:
		var sh := Node3D.new()
		sh.position = Vector3(0.18 * side, 0.52, 0)
		sh.rotation.z = 0.2 * side
		torso.add_child(sh)
		var arm := CapsuleMesh.new()
		arm.radius = 0.04
		arm.height = 0.78
		_part(sh, arm, Vector3(0, -0.36, 0), mat)
		# когти
		for k in 3:
			var cl := CylinderMesh.new()
			cl.top_radius = 0.003
			cl.bottom_radius = 0.012
			cl.height = 0.11
			var cm := _part(sh, cl, Vector3((k - 1) * 0.025, -0.8, -0.02), dark)
			cm.rotation.x = 0.4
		arms.append(sh)

	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.24
	cap.height = height
	cs.shape = cap
	cs.position.y = height * 0.5
	add_child(cs)

	bar = Node3D.new()
	bar.position.y = height + 0.15
	bar.visible = false
	add_child(bar)
	_bar_quad(Color(0, 0, 0, 0.7), Vector2(0.5, 0.065), 0.0)
	bar_fg = _bar_quad(Color(0.7, 0.14, 0.08), Vector2(0.48, 0.045), 0.01)


func _bar_quad(col: Color, size: Vector2, z: float) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	q.center_offset = Vector3(0, 0, z)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.albedo_color = col
	q.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bar.add_child(mi)
	return mi


func _part(parent: Node3D, mesh: Mesh, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func _set_state(s: String) -> void:
	state = s
	st = 0.0


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	st += delta
	cool -= delta
	knock = knock.lerp(Vector3.ZERO, 1.0 - exp(-6.0 * delta))
	bar_t -= delta
	bar.visible = state != "dead" and bar_t > 0.0

	var want := Vector3.ZERO
	var ppos: Vector3 = game.player.global_position
	var to := ppos - global_position
	to.y = 0.0
	var d := to.length()
	match state:
		"dead":
			pass
		"idle":
			if hunter and game.alive:
				_set_state("chase")
			elif game.alive and d < SIGHT and (not surface or Surface.on_meadow(ppos)) and _clear(global_position, ppos):
				_set_state("chase")
				_growl()
			elif surface and _zone(global_position) != 0:
				_set_state("return")
			elif surface:
				want = _wander(delta)
			elif Vector2(home.x - global_position.x, home.z - global_position.z).length() > 0.6:
				want = _steer(home, delta) * speed * 0.6
		"chase":
			growl_t -= delta
			if growl_t <= 0.0:
				_growl()
			if surface and not hunter:
				# видит — агро держится; не видит дольше LOSE_T — сдаётся
				# пока идёт в зону игрока (лестница, бункер), «потерю» не считаем — он идёт по следу
				if d < SIGHT * 1.6 and _clear(global_position, ppos):
					lost_t = 0.0
					blind_t = 0.0
				else:
					blind_t += delta
					if _zone(global_position) == _zone(ppos):
						lost_t += delta
			if not game.alive or (not hunter and not surface and global_position.distance_to(home) > LEASH) 					or (surface and not hunter and (lost_t > LOSE_T or blind_t > CHASE_MAX or (_zone(global_position) == 0 and _zone(ppos) == 0 and _from_center(global_position) > Surface.MEADOW_R + 8.0))):
				lost_t = 0.0
				blind_t = 0.0
				_set_state("return" if surface and _zone(global_position) != 0 else "idle")
			elif d < attack_range and cool <= 0.0:
				_set_state("windup")
			elif d > attack_range * 0.8:
				want = _steer(ppos, delta) * speed * _dash(delta)
			else:
				_face(to, delta)
		"windup":
			_face(to, delta)
			if st > windup_t:
				_strike(d, to)
				_set_state("recover")
		"recover":
			if st > (0.7 if kind == "heavy" else 0.45):
				_set_state("chase")
		"stagger":
			if st > (0.4 if kind == "heavy" else 0.3):
				_set_state("chase")
		"return":
			# назад на поляну: через лестницу и будку; увидел игрока — снова в погоню
			if game.alive and d < SIGHT and _clear(global_position, ppos):
				_set_state("chase")
				_growl()
			elif _zone(global_position) == 0:
				wander_t = 0.0
				_set_state("idle")
			else:
				want = _steer(Vector3(25.0, Surface.G, 0.0), delta) * speed * 0.7
	if surface and state == "idle" and want != Vector3.ZERO and Surface.in_hut(global_position + want.normalized() * 0.7, 0.3):
		want = Vector3.ZERO
	velocity.x = want.x + knock.x
	velocity.z = want.z + knock.z
	move_and_slide()
	_animate(delta, want.length())
	_footsteps(delta)


## Быстрый бегает рывками: рывок 0.35 с (×1.35), передышка 0.2 с (×0.38) — в среднем ≈ speed.
func _dash(delta: float) -> float:
	if kind != "fast":
		return 1.0
	dash_ph = fmod(dash_ph + delta / 0.55, 1.0)
	return 1.35 if dash_ph < 0.636 else 0.38


## Шаги врага (промпт 14.11 17:26): тяжёлые, ниже по тону, чем у игрока; шаг — каждые ~0.7 м пройденного пути.
var _step_dist := 0.0
func _footsteps(_delta: float) -> void:
	if not is_on_floor() or game == null or not game.snd.has("estep"):
		return
	var hv := Vector2(velocity.x, velocity.z).length()
	if hv < 0.3:
		_step_dist = 0.35
		return
	_step_dist += hv * get_physics_process_delta_time()
	if kind == "fast":
		# лёгкие частые шлепки: короткий шаг, тише, выше
		if _step_dist >= 0.42:
			_step_dist = 0.0
			game.play_at("estep", global_position + Vector3(0, 0.05, 0), -17.0 + minf(hv, 4.0) * 0.5, randf_range(1.15, 1.4))
		return
	var stride := 0.7 if hv < 3.0 else 0.95
	if _step_dist >= stride:
		_step_dist = 0.0
		game.play_at("estep", global_position + Vector3(0, 0.05, 0), -9.0 + minf(hv, 4.0), randf_range(0.62, 0.78))


## Сделать охотником (наказание за мухлёж): гонится всегда, без привязи к дому и поляне.
func make_hunter() -> void:
	hunter = true
	surface = false
	_set_state("chase")
	_growl()


## Направление движения к цели: напрямую, если видно, иначе через ближайший подходящий проём.
func _steer(goal: Vector3, delta: float) -> Vector3:
	think -= delta
	if think <= 0.0:
		think = 0.3
		target = goal
		# охотник: между поляной/лестницей и бункером ходит через низ лестницы
		var up := global_position.x > 12.4
		if hunter and up != (goal.x > 12.4):
			target = Vector3(11.4, global_position.y, 0.0) if up else Vector3(13.6, 0.0, 0.0)
		elif surface and _zone(global_position) != _zone(goal):
			target = _route(goal)
			if _zone(global_position) == 2 and not _clear(global_position, target):
				target = _doorway_to(target)
		elif (not surface or _zone(global_position) == 2) and not _clear(global_position, goal):
			target = _doorway_to(goal)
	var dir := target - global_position
	dir.y = 0.0
	if dir.length() < 0.05:
		return Vector3.ZERO
	dir = dir.normalized()
	_face(dir, delta)
	return dir


## Где точка: 0 — поляна (поверху, не в будке), 1 — будка и лестница, 2 — бункер.
func _zone(p: Vector3) -> int:
	if p.y > Surface.G - 1.0 and not Surface.in_hut(p):
		return 0
	if p.x < Surface.X_WALL:
		return 2
	return 1


## Промежуточная точка пути между зонами: поляна ↔ вход в будку ↔ лестница ↔ бункер.
func _route(goal: Vector3) -> Vector3:
	var p := global_position
	var gz := _zone(goal)
	match _zone(p):
		0:
			var sz := 1.0 if p.z >= 0.0 else -1.0
			if p.x < 21.4 and absf(p.z) < 3.0:
				return Vector3(p.x, Surface.G, 4.4 * sz)       # сбоку/позади будки — отойти от стены
			if p.x < 21.4:
				return Vector3(24.0, Surface.G, 4.4 * sz)      # обогнуть угол (мимо обломков у входа)
			if p.x < 23.6 and absf(p.z) < 1.0:
				return Vector3(19.6, Surface.G, 0.0)           # у входа — внутрь, на площадку
			return Vector3(23.0, Surface.G, 0.0)               # к входу
		1:
			return Vector3(11.2, 0.0, 0.0) if gz == 2 else Vector3(23.0, Surface.G, 0.0)
		_:
			return Vector3(13.2, 0.0, 0.0)                     # к проёму на лестницу


## Следующая точка пути по бункеру к цели (кратчайший путь по WAYPOINTS, Дейкстра на ~20 точках).
func _doorway_to(goal: Vector3) -> Vector3:
	var n := WAYPOINTS.size()
	if _wp_links.is_empty():
		for i in n:
			var l: Array = []
			for j in n:
				if i != j and _clear(WAYPOINTS[i], WAYPOINTS[j]):
					l.append(j)
			_wp_links.append(l)
	# старт и финиш подключаем к видимым точкам
	var from_me: Array = []
	var to_goal := {}
	for i in n:
		var q: Vector3 = WAYPOINTS[i]
		if Vector2(q.x - global_position.x, q.z - global_position.z).length() > 0.5 and _clear(global_position, q):
			from_me.append(i)
		if _clear(q, goal):
			to_goal[i] = true
	var dist: Array = []
	var prev: Array = []
	var done: Array = []
	for i in n:
		dist.append(INF)
		prev.append(-1)
		done.append(false)
	for i in from_me:
		dist[i] = global_position.distance_to(WAYPOINTS[i])
	var best_end := -1
	var best_cost := INF
	for it in n:
		var u := -1
		for i in n:
			if not done[i] and dist[i] < INF and (u == -1 or dist[i] < dist[u]):
				u = i
		if u == -1:
			break
		done[u] = true
		if to_goal.has(u):
			var c: float = dist[u] + (WAYPOINTS[u] as Vector3).distance_to(goal)
			if c < best_cost:
				best_cost = c
				best_end = u
		for v in _wp_links[u]:
			var nd: float = dist[u] + (WAYPOINTS[u] as Vector3).distance_to(WAYPOINTS[v])
			if nd < dist[v]:
				dist[v] = nd
				prev[v] = u
	if best_end == -1:
		return goal
	var k := best_end
	while prev[k] != -1:
		k = prev[k]
	var t: Vector3 = WAYPOINTS[k]
	return Vector3(t.x, global_position.y, t.z)


## Блуждание по поляне: идёт к случайной точке, постоит, выбирает следующую.
func _wander(delta: float) -> Vector3:
	wander_t -= delta
	if wander_t <= 0.0:
		wander_t = randf_range(5.0, 11.0)
		for i in 20:
			var a := randf() * TAU
			var r := Surface.MEADOW_R * sqrt(randf())
			var p := Surface.CENTER + Vector3(cos(a) * r, 0, sin(a) * r)
			if not Surface.in_hut(p, 2.0):
				target = p
				break
	var dir := target - global_position
	dir.y = 0.0
	if dir.length() < 0.6:
		return Vector3.ZERO
	dir = dir.normalized()
	_face(dir, delta)
	return dir * WANDER_SPEED


func _from_center(p: Vector3) -> float:
	return Vector2(p.x - Surface.CENTER.x, p.z - Surface.CENTER.z).length()


func _clear(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a + Vector3(0, 1.2, 0), b + Vector3(0, 1.2, 0))
	q.collision_mask = 1
	q.exclude = [get_rid(), game.player.get_rid()]
	return game.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _face(dir: Vector3, delta: float) -> void:
	if dir.length() < 0.01:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 1.0 - exp(-7.0 * delta))


func _strike(d: float, to: Vector3) -> void:
	_play(body_snd, game.snd["whoosh"], -6.0 if kind == "heavy" else -9.0, 0.7 if kind == "heavy" else 1.15)
	cool = cool_t
	var fwd := -global_transform.basis.z
	if game.alive and d < hit_range and fwd.dot(to.normalized()) > 0.3:
		game.damage_player(damage, global_position)


func _growl() -> void:
	growl_t = randf_range(4.0, 8.0)
	if kind == "fast":
		growl_t = randf_range(2.5, 5.0)
		if _screech_cache.is_empty():
			for v in 3:
				_screech_cache.append(_screech(v))
		_play(voice, _screech_cache, -7.0, randf_range(0.9, 1.15))
		return
	_play(voice, game.snd["growl"], -8.0, randf_range(0.85, 1.05))


## Визг быстрого: резкий высокий скрежещущий крик с дрожью и срывом тона вверх (процедурный).
static func _screech(variant: int) -> AudioStreamWAV:
	const Sfx := preload("res://sfx.gd")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1800 + variant
	var dur := rng.randf_range(0.45, 0.7)
	var n := int(Sfx.RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var f0 := rng.randf_range(520.0, 680.0)
	var bp := Sfx.Svf.new(rng.randf_range(2200.0, 2900.0), 2.0)
	var bp2 := Sfx.Svf.new(rng.randf_range(1100.0, 1400.0), 1.5)
	var ph := 0.0
	for i in n:
		var t := float(i) / Sfx.RATE
		var k := t / dur
		var w := rng.randf() * 2.0 - 1.0
		# тон: рывок вверх в начале, дрожь 28–35 Гц, к концу срывается вниз
		var f := f0 * (1.0 + 0.6 * smoothstep(0.0, 0.15, k) - 0.35 * smoothstep(0.6, 1.0, k)) * (1.0 + 0.06 * sin(TAU * 31.0 * t + variant))
		ph = fmod(ph + f / Sfx.RATE, 1.0)
		var x := (ph * 2.0 - 1.0) * 0.7 + w * 0.35 * (0.5 + 0.5 * sin(TAU * 47.0 * t))
		var env := smoothstep(0.0, 0.03, t) * (1.0 - smoothstep(dur * 0.55, dur, t))
		buf[i] = (bp.bp(x) * 0.8 + bp2.bp(x) * 0.5 + x * 0.15) * env
	return Sfx._wav(buf, 0.7)


func _play(p: AudioStreamPlayer3D, set_: Array, db: float, pitch := 1.0) -> void:
	p.stream = set_[randi() % set_.size()]
	p.volume_db = db
	p.pitch_scale = pitch * randf_range(0.95, 1.05)
	p.play()


func _animate(delta: float, spd: float) -> void:
	if state == "dead":
		return
	walk_amt = lerpf(walk_amt, clampf(spd / speed, 0.0, 1.0), 1.0 - exp(-8.0 * delta))
	walk_ph += delta * spd * (3.2 if kind == "heavy" else 4.6)
	for i in 2:
		var s := 1.0 if i == 0 else -1.0
		legs[i].rotation.x = sin(walk_ph) * 0.5 * walk_amt * s
	var arm_x := 0.25
	var base := -0.38 if kind == "heavy" else -0.75
	var lean := base
	match state:
		"windup":
			arm_x = lerpf(0.25, 2.7, smoothstep(0.0, windup_t * 0.82, st))
			lean = lerpf(base, 0.05, smoothstep(0.0, windup_t * 0.82, st))
		"recover":
			arm_x = lerpf(0.6, 0.25, smoothstep(0.0, 0.6, st))
			lean = lerpf(base - 0.37, base, smoothstep(0.0, 0.6, st))
		"stagger":
			lean = base + 0.35 * sin(minf(st / 0.4, 1.0) * PI)
	for i in 2:
		var s := 1.0 if i == 0 else -1.0
		var swing := -sin(walk_ph) * 0.35 * walk_amt * s if state == "chase" or state == "idle" else 0.0
		arms[i].rotation.x = lerpf(arms[i].rotation.x, arm_x + swing, 1.0 - exp(-14.0 * delta))
	torso.rotation.x = lerpf(torso.rotation.x, lean, 1.0 - exp(-12.0 * delta))
	vis.position.y = absf(sin(walk_ph)) * 0.04 * walk_amt
	if kind == "fast" and state == "chase" and spd > 0.5:
		# рывок — прыжок: тело подлетает и наклоняется вперёд, в передышке приседает
		var hop := sin(clampf(dash_ph / 0.636, 0.0, 1.0) * PI) if dash_ph < 0.636 else 0.0
		vis.position.y = hop * 0.22 - (0.06 if dash_ph >= 0.636 else 0.0)
		torso.rotation.x = lerpf(torso.rotation.x, base - 0.25 * hop, 1.0 - exp(-14.0 * delta))


## Попадание кулаком игрока.
func take_hit(dmg: float, dir: Vector3) -> void:
	if state == "dead":
		return
	game.weapon_hit()
	hp -= dmg
	bar_t = 4.0
	bar_fg.scale.x = maxf(hp / max_hp, 0.0)
	Fx.damage_number(get_parent(), global_position + Vector3(0, height + 0.1, 0), dmg)
	Fx.dust_burst(get_parent(), global_position + Vector3(0, height * 0.65, 0) - dir * 0.2)
	var flat := Vector3(dir.x, 0, dir.z).normalized()
	knock = flat * (3.0 + dmg * 0.06) * (1.0 if kind == "heavy" else 1.5)   # лёгкого отбрасывает дальше
	mat.emission_energy_multiplier = 0.5
	create_tween().tween_property(mat, "emission_energy_multiplier", 0.0, 0.25)
	if hp <= 0.0:
		_die(flat)
	elif state != "windup":
		_set_state("stagger")


func _die(dir: Vector3) -> void:
	_set_state("dead")
	collision_layer = 0
	knock = dir * 2.0
	bar.visible = false
	_play(body_snd, game.snd["thud"], -4.0, 0.9)
	# падает назад, по направлению удара
	var local_dir := global_transform.basis.inverse() * dir
	var tw := create_tween().set_parallel()
	tw.tween_property(vis, "rotation:x", PI / 2.0 * signf(local_dir.z if absf(local_dir.z) > 0.1 else 1.0), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(vis, "position:y", 0.3, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(torso, "rotation:x", 0.0, 0.4)
	tw.chain().tween_callback(func(): Fx.dust_burst(get_parent(), global_position + Vector3(0, 0.3, 0), Color(0.4, 0.38, 0.35), 30))
	# лут (промпт 14.11 18:08): тяжёлый — 0–2 предмета и 0–6 монет; быстрый — 1–3 предмета и 0–2 монеты
	var pos := global_position + Vector3(0, height * 0.5, 0)
	var coins := randi_range(0, 6) if kind == "heavy" else randi_range(0, 2)
	if coins > 0:
		game.spawn_loot("coin", coins, pos, Vector3(0, 2.5, 0), 1.6)
	var extra: Array = ["bandage", "pills", "choco", "rusk", "battery", "scrap", "nut"]
	for k in (randi_range(0, 2) if kind == "heavy" else randi_range(1, 3)):
		game.spawn_loot(extra[randi() % extra.size()], 1, pos, Vector3(0, 2.5, 0), 1.2)
	if randf() < 0.03:  # кошелёк — редкость (промпт 14.11 17:21)
		game.spawn_loot("wallet", 1, pos, Vector3(0, 2.5, 0), 1.2)
	died.emit(self)
	var tw2 := create_tween()
	tw2.tween_interval(8.0)
	tw2.tween_property(self, "position:y", position.y - 0.8, 3.0)
	tw2.tween_callback(queue_free)
