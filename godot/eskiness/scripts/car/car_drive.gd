extends "res://scripts/car/car_model.gd"
# Часть car.gd: двери, места в салоне, посадка/выход, вождение, сеть машины, сейв (промпт 15.11 23:01).
# Свой игрок в салоне «припаркован»: его физика выключена, камера стоит на месте глаз, мышь крутит обзор.
# Выход: посмотреть на свою дверь и E — дверь открывается, камера выходит наружу, игрок снова ходит.
# Водитель (место 0) с бензином: W/S — газ/тормоз/назад, A/D — руль, пробел — ручник.


func my_id() -> int:
	return game.net.multiplayer.get_unique_id() if game and game.net else 1


func vnet():
	return game.get_tree().root.get_node_or_null("VillageNet") if game and game.net else null


# ---------- двери ----------

func _doors_tick(delta: float) -> void:
	for i in 4:
		var w: float = door_want[i]
		if absf(door_k[i] - w) < 0.001:
			continue
		var old: float = door_k[i]
		door_k[i] = move_toward(door_k[i], w, delta / 0.45)
		var e := smoothstep(0.0, 1.0, door_k[i])
		doors[i].rotation.y = -float(DOORS[i][0]) * DOOR_OPEN * e
		door_gaps[i].visible = door_k[i] > 0.02
		if w == 0.0 and door_k[i] == 0.0 and old > 0.0 and game:
			game.play_at("clunk", door_world(i), -6.0, 1.1)


func open_door(i: int, on: bool, sync := true) -> void:
	if door_want[i] == (1.0 if on else 0.0):
		return
	door_want[i] = 1.0 if on else 0.0
	if on and game:
		game.play_at("creak", door_world(i), -12.0, 1.3)
	if sync and vnet():
		vnet().rpc("v_door", i, on)


func door_world(i: int) -> Vector3:
	return global_transform * Vector3(0.82 * float(DOORS[i][0]), 0.75, float(DOORS[i][1]) - float(DOORS[i][2]) / 2.0)


## Свой игрок смотрит на свою дверь (из салона): взгляд в сторону двери.
func _looking_at_door() -> bool:
	if my_seat < 0 or game == null:
		return false
	var fwd: Vector3 = -game.player.cam.global_transform.basis.z
	var loc := global_transform.basis.inverse() * fwd
	return loc.x * float(DOORS[my_seat][0]) > 0.45


# ---------- места ----------

func seat_eye_world(i: int) -> Vector3:
	return global_transform * SEAT_EYE[i]


## Посадить своего игрока на место i. instant — без анимации (кат-сцена, загрузка).
func seat_local(i: int, instant := false) -> void:
	var p = game.player
	my_seat = i
	seats[i] = my_id()
	p.active = false
	p.velocity = Vector3.ZERO
	p.process_mode = Node.PROCESS_MODE_DISABLED
	p.col_shape.disabled = true
	seat_from = p.cam.global_position
	_body_visible(false)
	if instant:
		seat_dir = 0
		seat_anim = 1.0
		# сразу лицом вперёд по машине, взгляд чуть вниз — на руль и дорогу
		p.rotation.y = yaw + PI
		p.head.rotation.x = -0.12
		_place_player(seat_eye_world(i))
	else:
		seat_dir = 1
		seat_anim = 0.0
		open_door(i, true)
	if vnet():
		vnet().rpc("v_seat", my_id(), i)
	if i == 0:
		net_drive = false
		_driver_in()


func _driver_in() -> void:
	if fuel > 0.0:
		_engine(true)
	elif game:
		game.hud.toast("Бак пуст — нужен бензин", Color(0.95, 0.7, 0.45))


func _engine(on: bool) -> void:
	if on == engine_on:
		return
	engine_on = on
	if engine == null:
		engine = AudioStreamPlayer.new()
		engine.stream = Sfx2.engine_loop()
		add_child(engine)
	if on:
		engine.volume_db = -22.0
		engine.pitch_scale = 0.8
		engine.play()
		smoke.emitting = true
		tail_mat.emission_energy_multiplier = 1.4
		if head_l:
			head_l.light_energy = 3.2
			lens_mat.emission_energy_multiplier = 2.5
	else:
		engine.stop()
		smoke.emitting = false
		tail_mat.emission_energy_multiplier = 0.1
		if head_l:
			head_l.light_energy = 0.0
			lens_mat.emission_energy_multiplier = 0.0


## Выйти: открыть дверь, камера наружу, потом игрок снова ходит.
func exit_local() -> void:
	if my_seat < 0 or seat_dir != 0:
		return
	if my_seat == 0 and absf(speed) > 1.5:
		game.hud.toast("Сначала останови машину")
		return
	seat_dir = -1
	seat_anim = 1.0
	open_door(my_seat, true)
	if my_seat == 0:
		speed = 0.0
		_engine(false)


func _exit_point(i: int) -> Vector3:
	var p: Vector3 = global_transform * EXIT[i]
	if surface:
		p.y = surface.height(p.x, p.z) + 0.05
	return p


## Свой игрок: камера в точке eye (тело игрока стоит так, чтобы голова была там).
func _place_player(eye: Vector3) -> void:
	var p = game.player
	p.global_position = eye - Basis(Vector3.UP, p.rotation.y) * p.head.position


func _seat_tick(delta: float) -> void:
	if my_seat < 0:
		return
	var p = game.player
	if seat_dir == 1:
		seat_anim = minf(seat_anim + delta / 0.8, 1.0)
		var k := smoothstep(0.0, 1.0, seat_anim)
		# садясь, поворачиваемся лицом вперёд по машине
		p.rotation.y = lerp_angle(p.rotation.y, yaw + PI, 1.0 - exp(-7.0 * delta))
		p.head.rotation.x = lerpf(p.head.rotation.x, -0.12, 1.0 - exp(-5.0 * delta))
		_place_player(seat_from.lerp(seat_eye_world(my_seat), k) + Vector3(0, sin(k * PI) * 0.05, 0))
		if seat_anim >= 1.0:
			seat_dir = 0
			open_door(my_seat, false)
	elif seat_dir == -1:
		seat_anim = maxf(seat_anim - delta / 0.9, 0.0)
		var k := smoothstep(0.0, 1.0, seat_anim)
		var out: Vector3 = _exit_point(my_seat) + (p.head.position as Vector3).rotated(Vector3.UP, p.rotation.y)
		# сначала дверь открывается (первые 30%), потом выходим
		var kk := clampf(k / 0.75, 0.0, 1.0)
		_place_player(out.lerp(seat_eye_world(my_seat), kk))
		if seat_anim <= 0.0:
			_stand_up()
	else:
		_place_player(seat_eye_world(my_seat))


## Своё тело в салоне прячем: оно стоит в позе «стоя» и торчало бы сквозь пол и крышу перед камерой.
func _body_visible(on: bool) -> void:
	var p = game.player
	if p.model_root:
		p.model_root.visible = on


func _stand_up() -> void:
	var p = game.player
	var i := my_seat
	p.global_position = _exit_point(i)
	p.velocity = Vector3.ZERO
	p.process_mode = Node.PROCESS_MODE_INHERIT
	p.col_shape.disabled = false
	p.active = true
	_body_visible(true)
	seats[i] = 0
	my_seat = -1
	seat_dir = 0
	open_door(i, false)
	if vnet():
		vnet().rpc("v_seat", my_id(), -1)
	if village:
		village.on_exit_car()


## Свободное место, к двери которого ближе всего игрок (водительское — если игрок с той стороны).
func _free_seat_near(pos: Vector3) -> int:
	var best := -1
	var bd := INF
	for i in 4:
		if seats[i] != 0:
			continue
		var d := pos.distance_to(_exit_point(i)) - (0.5 if i == 0 else 0.0)
		if d < bd:
			bd = d
			best = i
	return best


## Мышь в салоне: игрок «выключен», обзор крутим сами.
func _unhandled_input(e: InputEvent) -> void:
	if my_seat < 0 or game == null:
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if e is InputEventMouseMotion and captured:
		if e.device == InputEvent.DEVICE_ID_EMULATION:
			return
		game.player.look(e.relative)
	elif e is InputEventMouseButton and e.pressed and not captured and not game.window_open():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ---------- вождение ----------

func _drive_tick(delta: float) -> void:
	bump_cd -= delta
	var yaw0 := yaw
	if my_seat == 0 and seat_dir == 0 and game.alive and not game.window_open():
		var thr := Input.get_axis("move_back", "move_forward")
		var st_in := Input.get_axis("move_right", "move_left")
		if fuel <= 0.0:
			thr = 0.0
			if engine_on:
				_engine(false)
				game.hud.toast("Бензин кончился", Color(0.95, 0.7, 0.45))
		if thr > 0.0:
			speed = move_toward(speed, MAX_F, (ACC if speed >= -0.1 else BRAKE) * thr * delta)
		elif thr < 0.0:
			speed = move_toward(speed, -MAX_R, (BRAKE if speed > 0.1 else ACC * 0.7) * -thr * delta)
		else:
			speed = move_toward(speed, 0.0, ROLL * delta)
		if Input.is_action_pressed("jump"):
			speed = move_toward(speed, 0.0, BRAKE * 1.4 * delta)
		steer = move_toward(steer, st_in, delta * 3.0)
		if engine_on:
			fuel = maxf(fuel - delta * FUEL_USE * (0.25 + 0.75 * absf(thr)), 0.0)
		if absf(speed) > 0.05:
			_move(delta)
		net_t -= delta
		if vnet() and net_t <= 0.0:
			net_t = 1.0 / 20.0
			vnet().rpc("v_car", position, yaw, speed, fuel, engine_on)
	elif net_drive:
		# машину ведёт другой игрок — плавно к его данным
		position = position.lerp(net_pos, 1.0 - exp(-10.0 * delta))
		yaw = lerp_angle(yaw, net_yaw, 1.0 - exp(-10.0 * delta))
		var target := _fit(position, yaw, false)
		transform = Transform3D(transform.basis.slerp(target.basis, 1.0 - exp(-8.0 * delta)), target.origin)
	else:
		speed = move_toward(speed, 0.0, BRAKE * delta)
	for w in wheels:
		w.rotation.x += speed / WHEEL_R * delta
	for i in 2:
		wheels[i].rotation.y = steer * 0.45
	if engine_on and engine:
		engine.volume_db = lerpf(engine.volume_db, minf(-20.0 + absf(speed) * 0.5, -10.0), 1.0 - exp(-4.0 * delta))
		engine.pitch_scale = 0.8 + absf(speed) * 0.07
		var vib := 0.004 + absf(speed) * 0.0008
		rig.position = Vector3(0, randf_range(-1, 1) * vib, 0)
	_carry()


func _move(delta: float) -> void:
	var old_yaw := yaw
	yaw += steer * TURN * clampf(speed / 6.0, -1.0, 1.0) * delta
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var np := position + fwd * speed * delta
	# крутой склон впереди — дальше не едет. Уклон меряем по земле на 1.2 м вперёд по ходу (раньше делили
	# разницу высот на шаг кадра — на старте шаг ~1 мм, и любая неровность/осевший угол «бампали» машину: не ехала)
	var dir := fwd * signf(speed)
	var h0: float = surface.height(position.x, position.z)
	var h1: float = surface.height(position.x + dir.x * 1.2, position.z + dir.z * 1.2)
	if (h1 - h0) / 1.2 > 0.75:
		yaw = old_yaw
		_bump()
		return
	var target := _fit(np, yaw, true)
	if _blocked(target):
		yaw = old_yaw
		_bump()
		return
	if carried.is_empty() and absf(speed) > 0.3:
		_grab_carried()
	transform = Transform3D(transform.basis.slerp(target.basis, 1.0 - exp(-10.0 * delta)), target.origin)
	for m in worn_mats:
		m.set_shader_parameter("origin_shift", position - start_pos)


func _bump() -> void:
	if absf(speed) > 3.0 and bump_cd <= 0.0:
		bump_cd = 0.6
		game.play_at("thud", global_position, -4.0, 0.7)
		game.hud.hurt_flash(0.2)
	speed = -speed * 0.25


## Есть ли что-то на пути (стены, дома, камни). Враги — сбиваем (урон по скорости).
func _blocked(xf: Transform3D) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.5, 0.6, 3.7)
	q.shape = bs
	# коробка сдвинута по ходу: то, во что машина уже упёрлась сзади, не держит её на месте
	q.transform = xf * Transform3D(Basis(), Vector3(0, 0.95, 0.3 * signf(speed)))
	q.collision_mask = 1
	var ex: Array[RID] = [get_rid(), game.player.get_rid()]
	q.exclude = ex
	var hits := get_world_3d().direct_space_state.intersect_shape(q, 8)
	var block := false
	for h in hits:
		var c = h.collider
		if c == null or c.has_meta("ground"):
			continue
		if c is CharacterBody3D and c.has_method("take_hit"):
			if absf(speed) > 3.0 and not c.get_meta("car_hit", false):
				c.set_meta("car_hit", true)
				c.take_hit(absf(speed) * 7.0, Vector3(sin(yaw), 0.2, cos(yaw)) * signf(speed))
				get_tree().create_timer(0.8).timeout.connect(_unmark.bind(c))
			continue
		block = true
	return block


func _unmark(c) -> void:
	if is_instance_valid(c):
		c.set_meta("car_hit", false)


## Предметы в салоне: при трогании запоминаем, где они лежат, и дальше везём с собой.
func _grab_carried() -> void:
	var inv_xf := global_transform.affine_inverse()
	for p in get_tree().get_nodes_in_group("pickup"):
		if p.taken:
			continue
		var l: Vector3 = inv_xf * p.global_position
		if absf(l.x) < 0.75 and l.y > 0.8 and l.y < 1.4 and l.z > -1.1 and l.z < 0.8:
			p.freeze = true
			carried.append([p, inv_xf * p.global_transform])


func _carry() -> void:
	if carried.is_empty():
		return
	var keep: Array = []
	for c in carried:
		var p = c[0]
		if not is_instance_valid(p) or p.taken or p.is_queued_for_deletion():
			continue
		p.global_transform = global_transform * (c[1] as Transform3D)
		keep.append(c)
	carried = keep


# ---------- после кат-сцены ----------

## Поставить машину (заглохшую) в точку: для деревни после кат-сцены и для загрузки.
func park_at(p: Vector3, a: float) -> void:
	escaped = true
	if ign_key:
		ign_key.visible = true
	state = "parked"
	yaw = a
	speed = 0.0
	position = p
	transform = _fit(p, a, true)
	rig.position = Vector3.ZERO
	rig.rotation = Vector3.ZERO
	for i in figures.size():
		if figures[i] != null and is_instance_valid(figures[i]):
			figures[i].queue_free()
		figures[i] = null
	driver.visible = false
	if cam:
		cam.current = false
		cam.queue_free()
		cam = null
	if engine:
		engine.stop()
	engine_on = false
	smoke.emitting = false
	tail_mat.emission_energy_multiplier = 0.1
	if head_l:
		head_l.light_energy = 0.0
		lens_mat.emission_energy_multiplier = 0.0
	if game and game.player:
		game.player.cam.current = true
	for m in worn_mats:
		m.set_shader_parameter("origin_shift", position - start_pos)
	for i in 4:
		door_want[i] = 0.0
		door_k[i] = 0.0
		doors[i].rotation.y = 0.0
		door_gaps[i].visible = false


func refuel() -> void:
	if game.inv.count("fuel") <= 0:
		return
	game.inv.remove("fuel", 1)
	fuel = 1.0
	game.play_at("pickup", global_position, -6.0, 0.6)
	game.hud.toast("Бак полный. Садись за руль", Color(0.75, 0.9, 0.6))
	if vnet():
		vnet().rpc("v_fuel", fuel)


func to_save() -> Dictionary:
	return {"escaped": escaped, "pos": [position.x, position.y, position.z], "yaw": yaw, "fuel": fuel,
		"seat": my_seat if seat_dir == 0 else -1}


func from_save(d: Dictionary) -> void:
	if not bool(d.get("escaped", false)):
		return
	var a: Array = d.get("pos", [position.x, position.y, position.z])
	var pz := float(a[2])
	if pz > 430.0:   # старые сейвы: деревня была на 360 м дальше
		pz -= 360.0
	park_at(Vector3(float(a[0]), float(a[1]), pz), float(d.get("yaw", 0.0)))
	# ключ остался в зажигании (старые сейвы: ключ ещё в рюкзаке — убираем)
	if game and game.inv.count("car_key") > 0:
		game.inv.remove("car_key", game.inv.count("car_key"))
	fuel = float(d.get("fuel", 0.0))
	var s := int(d.get("seat", -1))
	if s >= 0 and s < 4:
		seat_local.call_deferred(s, true)
