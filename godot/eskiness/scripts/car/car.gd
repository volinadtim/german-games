extends "res://scripts/car/car_model.gd"
## Старая ржавая легковушка на поляне (промпт 14.11 18:07). Советский седан «копейка»: выцветшая
## голубая краска облуплена до ржавчины (worn_metal.gdshader), дверь в красном грунте, лобовое стекло
## выбито, водительское окно тоже, одна фара разбита, заднее правое колесо спущено — машина осела на угол.
## Ключ (car_key) лежит в сейфе. С ключом [E] — кат-сцена: садишься, стартер «чух-чух» дважды не схватывает,
## на третий раз мотор заводится, фара загорается, машина уезжает с поляны, экран темнеет — победа (game.gd: win).
## Стоит всегда в одном месте (surface.gd: CAR_POS / CAR_YAW), в сейв не пишется.
## Перед машины — +Z, водительская сторона — +X. Интерфейс взаимодействия: get_prompt(game), interact(game).


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
