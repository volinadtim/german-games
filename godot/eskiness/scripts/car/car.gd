extends "res://scripts/car/car_drive.gd"
## Старая ржавая легковушка на поляне (промпт 14.11 18:07). Советский седан «копейка»: выцветшая
## голубая краска облуплена до ржавчины (worn_metal.gdshader), дверь в красном грунте, лобовое стекло
## выбито, водительское окно тоже, одна фара разбита, заднее правое колесо спущено — машина осела на угол.
## Ключ (car_key) лежит в сейфе; использованный остаётся в зажигании (ign_key), из инвентаря пропадает. С ключом [E] — кат-сцена (промпт 15.11 23:01): человек подходит,
## открывает дверь, садится, дверь хлопает, стартер «чух-чух» раз не схватывает, со второго мотор
## заводится, машина уезжает по дороге на север, экран темнеет — надпись «заглохла» и игрок уже сидит
## в салоне в деревне (village.gd). В сети кат-сцену видят все; до 4 игроков — каждый на своём месте,
## за рулём тот, кто взял ключ (village_net.gd: v_escape).
## Дальше машина — обычная: двери, места, бензин, вождение (car_drive.gd); положение — в сейве (village).
## Перед машины — +Z, водительская сторона — +X. Интерфейс взаимодействия: get_prompt(game), interact(game).

const BOARD_T := 3.2            # посадка: подойти, открыть дверь, сесть, захлопнуть
const Figure := preload("res://scripts/car/car_figure.gd")
const FIG_S := 0.8              # люди в кат-сцене чуть меньше: салон машины низкий (крыша на 1.37)
const FIG_HIP := 0.55           # где таз сидящего (оси машины): ноги — внутри кузова, голова — под крышей
var order := [0, 0, 0, 0]       # кто на каком месте в кат-сцене (id игроков, 0 — пусто)


func _ready() -> void:
	yaw = rotation.y
	if surface:
		transform = _fit(position, yaw, true)
	start_pos = position
	rig = Node3D.new()
	add_child(rig)
	_build()
	_hollow_collision()
	figures.resize(4)


# ---------- взаимодействие ----------

func get_prompt(g) -> String:
	if state == "idle":
		if g.inv.count("car_key") > 0:
			return "[E] Сесть и уехать"
		return "Заперто. Нужен ключ"
	if state != "parked":
		return ""
	if my_seat >= 0:
		return "[E] Открыть дверь и выйти" if seat_dir == 0 and _looking_at_door() else ""
	if g.inv.count("fuel") > 0 and fuel < 0.9:
		return "[E] Залить бензин (канистра)"
	var s := _free_seat_near(g.player.global_position)
	if s < 0:
		return "Мест нет"
	return ("[E] Сесть за руль" if s == 0 else "[E] Сесть в машину") + ("" if fuel > 0.0 else "  (бак пуст)")


func interact(g) -> void:
	if state == "idle":
		if g.inv.count("car_key") <= 0:
			g.hud.toast("Заперто. Нужен ключ")
			g.play_at("clunk", global_position + global_transform.basis * Vector3(0.8, 0.8, 0.2), -10.0, 1.4)
			return
		# ключ остаётся в зажигании (виден в салоне) и уходит из инвентаря — не занимает слот
		g.inv.remove("car_key", 1)
		var o := [my_id(), 0, 0, 0]
		if g.net:
			var ids: Array = g.net.players.keys()
			ids.sort()
			var k := 1
			for id in ids:
				if id != my_id() and k < 4:
					o[k] = id
					k += 1
		if vnet():
			vnet().rpc("v_escape", o)
		else:
			escape(o)
		return
	if state != "parked":
		return
	if my_seat >= 0:
		if seat_dir == 0 and _looking_at_door():
			exit_local()
		return
	if g.inv.count("fuel") > 0 and fuel < 0.9:
		refuel()
		return
	var s := _free_seat_near(g.player.global_position)
	if s >= 0:
		seat_local(s)


## Кат-сцена отъезда. o — места [водитель, пассажир, сзади, сзади] (id игроков; без сети — [1, 0, 0, 0]).
func escape(o := [1, 0, 0, 0]) -> void:
	if state != "idle":
		return
	order = o
	state = "board"
	if ign_key:
		ign_key.visible = true
	t = 0.0
	fuel = 0.0
	if game:
		game.begin_escape()
	# люди — модель игрока (car_figure.gd): каждый подходит к своей двери
	for i in 4:
		if int(order[i]) == 0:
			continue
		var f := Figure.new()
		rig.add_child(f)
		f.scale = Vector3.ONE * FIG_S
		f.position = _approach(i)
		f.rotation.y = PI / 2.0 * float(DOORS[i][0])   # лицом к машине
		f.wheel = i == 0
		figures[i] = f
	# своё тело (стоит, где нажал E) в кат-сцене не показываем — вместо него идёт фигура
	if game and game.player and game.player.model_root:
		game.player.model_root.visible = false
	# камера сзади-слева и сверху — так её не загораживают враги на поляне
	cam = Camera3D.new()
	cam.fov = 60.0
	cam.top_level = true
	add_child(cam)
	cam.global_position = _cam_want(CAM_OFF * 0.8)
	cam.look_at(_cam_look())
	cam.current = true
	starter = AudioStreamPlayer.new()
	starter.stream = Sfx2.starter()
	starter.volume_db = -10.0
	add_child(starter)
	engine = AudioStreamPlayer.new()
	engine.stream = Sfx2.engine_loop()
	engine.volume_db = -60.0
	add_child(engine)


func _process(delta: float) -> void:
	if state == "parked":
		_drive_tick(delta)
		_seat_tick(delta)
		_doors_tick(delta)
		return
	if state == "idle" or state == "done":
		return
	t += delta
	_doors_tick(delta)
	if state == "board":
		_board(delta)
		return
	var st := t - CRANK_AT
	if starter and not starter.playing and st >= 0.0 and st < 0.2:
		starter.play()
	if state == "start":
		# тряска: при попытках стартера — мелкая дрожь, мотор схватил — рывок, потом ровная вибрация
		var shake := 0.0
		for c in [[0.0, 0.85], [1.25, 0.95]]:
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
		# выруливает на дорогу (она идёт прямо на север)
		yaw = lerp_angle(yaw, 0.0, 1.0 - exp(-0.9 * delta))
		var fwd := Vector3(sin(yaw), 0, cos(yaw))
		var p := position + fwd * speed * delta
		p.x = lerpf(p.x, 31.0, 1.0 - exp(-0.4 * delta))
		var target := _fit(p, yaw, false)
		transform = Transform3D(transform.basis.slerp(target.basis, 1.0 - exp(-8.0 * delta)), target.origin)
		for w in wheels:
			w.rotation.x += speed / WHEEL_R * delta
		var vib := 0.006 + speed * 0.001
		rig.position = Vector3(0, randf_range(-1, 1) * vib, 0)
		rig.rotation.z = randf_range(-1, 1) * vib * 0.5
		for m in worn_mats:
			m.set_shader_parameter("origin_shift", position - start_pos)
		engine.volume_db = lerpf(engine.volume_db, -12.0, 1.0 - exp(-4.0 * delta))
		engine.pitch_scale = 0.85 + speed * 0.09
		# камера едет следом с отставанием — машина понемногу отрывается
		cam.global_position = cam.global_position.lerp(_cam_want(CAM_OFF), 1.0 - exp(-1.2 * delta))
		cam.look_at(_cam_look())
		if t > 2.4 and not win_called:
			win_called = true
			if village:
				village.stall_sequence(order.find(my_id()))
			elif game:
				game.win()
		if t > 3.0:
			engine.volume_db -= delta * 14.0


## Посадка: люди подходят к дверям, двери открываются, они садятся (ноги — вперёд), двери хлопают.
func _board(delta: float) -> void:
	cam.global_position = cam.global_position.lerp(_cam_want(CAM_OFF * 0.75), 1.0 - exp(-0.5 * delta))
	cam.look_at(_cam_look())
	for i in 4:
		var f = figures[i]
		if f == null:
			continue
		var side := float(DOORS[i][0])
		var outside := _ground_local(EXIT[i] + Vector3(-0.2 * side, 0, 0))
		if t < 1.0:
			# подходит к двери (походка — сама, по скорости)
			f.position = _approach(i).lerp(outside, smoothstep(0.0, 1.0, t / 1.0))
			f.rotation.y = lerp_angle(f.rotation.y, PI / 2.0 * side, 1.0 - exp(-8.0 * delta))
		if t > 0.75 and t < 0.9:
			open_door(i, true, false)
		var k := smoothstep(1.1, 2.4, t)
		if k > 0.0:
			# шаг в проём, разворот вперёд и вниз на сиденье
			var seat := Vector3(SEAT_HIP[i].x, FIG_HIP - f.HIP_Y * FIG_S, SEAT_HIP[i].z + 0.06)
			var mid := Vector3(0.95 * side, lerpf(outside.y, seat.y, 0.3), SEAT_HIP[i].z + 0.1)
			f.position = outside.lerp(mid, smoothstep(0.0, 0.45, k)).lerp(seat, smoothstep(0.45, 1.0, k))
			f.rotation.y = lerp_angle(PI / 2.0 * side, PI, smoothstep(0.15, 0.7, k))
			f.sit = smoothstep(0.3, 0.95, k)
		if t > 2.6:
			open_door(i, false, false)
	if t >= BOARD_T:
		state = "start"
		t = 0.0
		if game:
			game.play_at("clunk", global_position + global_transform.basis * Vector3(0.8, 0.8, 0.2), -4.0, 0.8)


## Откуда человек подходит к двери i: сзади-сбоку от машины, на земле (оси машины).
func _approach(i: int) -> Vector3:
	var side := float(DOORS[i][0])
	return _ground_local(EXIT[i] + Vector3(0.9 * side, 0, -1.4))


## Точка на земле под p (p — в осях машины), тоже в осях машины.
func _ground_local(p: Vector3) -> Vector3:
	var w: Vector3 = global_transform * p
	if surface:
		w.y = surface.height(w.x, w.z)
	return Vector3(p.x, (global_transform.affine_inverse() * w).y, p.z)


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
