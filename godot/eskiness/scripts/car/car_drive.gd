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
	_trunk_tick(delta)


## Крышка багажника поднимается и опускается плавно; захлопнулась — щелчок замка.
func _trunk_tick(delta: float) -> void:
	if trunk_lid == null or absf(trunk_k - trunk_want) < 0.001:
		return
	var old := trunk_k
	trunk_k = move_toward(trunk_k, trunk_want, delta / 0.6)
	trunk_lid.rotation.x = TRUNK_OPEN * smoothstep(0.0, 1.0, trunk_k)
	if trunk_well:
		trunk_well.visible = trunk_k > 0.03
	if trunk_want == 0.0 and trunk_k == 0.0 and old > 0.0 and game:
		game.play_at("clunk", trunk_world(), -8.0, 0.95)


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
	var e: Vector3 = SEAT_EYE[i]
	if i == my_seat and lean > 0.001:
		# высунулся из окна (промпт 18.11 01:20): глаза уходят наружу и вверх, за линию борта
		var k := smoothstep(0.0, 1.0, lean)
		e += Vector3(signf(SEAT_EYE[i].x) * LEAN_OUT * k, 0.14 * k, 0.0)
	return global_transform * e


## Посадить своего игрока на место i. instant — без анимации (кат-сцена, загрузка).
func seat_local(i: int, instant := false) -> void:
	var p = game.player
	my_seat = i
	seats[i] = my_id()
	p.active = false
	p.velocity = Vector3.ZERO
	p.process_mode = Node.PROCESS_MODE_DISABLED
	p.col_shape.disabled = true
	p.set_meta("car_seat", i)   # revive.gd: в машине лечение прерывает не скорость, а руль/газ водителя
	seat_from = p.cam.global_position
	look_yaw = vis_yaw()
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
	if broken:
		if game:
			game.hud.toast("Машина сломана — почини молотком", Color(1.0, 0.6, 0.4))
	elif fuel > 0.0:
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
	_lean_tick(delta)
	if my_seat < 0:
		return
	var p = game.player
	# взгляд — в осях машины (промпт 16.11 05:47): машина повернула — повернулся и игрок,
	# мышь задаёт только смещение от «вперёд по машине», не дальше LOOK_MAX.
	# Берём поворот ВИДИМОГО кузова (transform уже обновлён в _drive_tick этого кадра), а не yaw:
	# кузов догоняет yaw плавно, и голова опережала машину (05:51)
	var vy := vis_yaw()
	var dy := angle_difference(look_yaw, vy)
	look_yaw = vy
	if seat_dir == 0 or seat_dir == 2:
		var rel := clampf(angle_difference(vy + PI, p.rotation.y + dy), -LOOK_MAX, LOOK_MAX)
		p.rotation.y = vy + PI + rel
	if seat_dir == 1:
		seat_anim = minf(seat_anim + delta / 0.8, 1.0)
		var k := smoothstep(0.0, 1.0, seat_anim)
		# садясь, поворачиваемся лицом вперёд по машине
		p.rotation.y = lerp_angle(p.rotation.y, vy + PI, 1.0 - exp(-7.0 * delta))
		p.head.rotation.x = lerpf(p.head.rotation.x, -0.12, 1.0 - exp(-5.0 * delta))
		_place_player(seat_from.lerp(seat_eye_world(my_seat), k) + Vector3(0, sin(k * PI) * 0.05, 0))
		if seat_anim >= 1.0:
			seat_dir = 0
			open_door(my_seat, false)
	elif seat_dir == 2:
		# пересадка на соседнее место (за руль — через рычаг передач): пригнувшись
		seat_anim = minf(seat_anim + delta / SWITCH_T, 1.0)
		var k := smoothstep(0.0, 1.0, seat_anim)
		p.rotation.y = lerp_angle(p.rotation.y, vy + PI, 1.0 - exp(-7.0 * delta))
		_place_player(seat_eye_world(switch_from).lerp(seat_eye_world(my_seat), k) - global_transform.basis.y * sin(k * PI) * 0.12)
		if seat_anim >= 1.0:
			seat_dir = 0
			if my_seat == 0:
				_driver_in()
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
		if lean > 0.5:
			game.hud.prompt.call_deferred("Высунулся из окна — отпусти, чтобы сесть ровно")
		elif game.focus == null and can_take_wheel() and not _looking_at_door():
			game.hud.prompt.call_deferred("[E] Пересесть за руль")
		elif game.focus == null and next_seat() >= 0 and not game.window_open():
			game.hud.prompt.call_deferred("[Z] Пересесть %s" % _seat_name(next_seat()))


## Шкала бензина внизу экрана, пока сидишь в машине (промпт 16.11 05:55).
func _fuel_ui_tick() -> void:
	var on := my_seat >= 0 and state == "parked" and game != null
	if fuel_ui == null:
		if not on:
			return
		fuel_ui = CanvasLayer.new()
		fuel_ui.layer = 5
		add_child(fuel_ui)
		var box := Control.new()
		box.anchor_left = 0.5
		box.anchor_right = 0.5
		box.anchor_top = 1.0
		box.anchor_bottom = 1.0
		box.offset_left = -110
		box.offset_right = 110
		box.offset_top = -150
		box.offset_bottom = -118
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fuel_ui.add_child(box)
		var bg := ColorRect.new()
		bg.color = Color(0, 0, 0, 0.55)
		bg.position = Vector2(0, 20)
		bg.size = Vector2(220, 10)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(bg)
		fuel_bar = ColorRect.new()
		fuel_bar.position = Vector2(1, 21)
		fuel_bar.size = Vector2(218, 8)
		fuel_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(fuel_bar)
		fuel_l = Label.new()
		fuel_l.size = Vector2(220, 20)
		fuel_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fuel_l.add_theme_font_size_override("font_size", 14)
		fuel_l.add_theme_color_override("font_outline_color", Color.BLACK)
		fuel_l.add_theme_constant_override("outline_size", 4)
		box.add_child(fuel_l)
	fuel_ui.visible = on
	if not on:
		return
	fuel_bar.size.x = 218.0 * clampf(fuel, 0.0, 1.0)
	fuel_bar.color = Color(0.85, 0.3, 0.2) if fuel < 0.2 else Color(0.85, 0.7, 0.3)
	fuel_l.text = "Бензин %d%%" % roundi(fuel * 100.0) if fuel > 0.0 else "Бак пуст — нужна канистра"
	if car_hp < CAR_MAX_HP:
		fuel_l.text += "   Кузов %d%%" % roundi(car_hp / CAR_MAX_HP * 100.0)


## Высунуться из окна (держать V): голова за бортом, видно дорогу и можно стрелять назад.
## Водитель при этом держит руль одной рукой — машину ведёт и может занести (промпт 18.11 01:20).
func _lean_tick(delta: float) -> void:
	var can: bool = my_seat >= 0 and seat_dir == 0 and game != null and game.alive 			and not game.window_open() and not game.inv.open
	lean_on = can and InputMap.has_action("car_lean") and Input.is_action_pressed("car_lean")
	lean = move_toward(lean, 1.0 if lean_on else 0.0, delta / LEAN_T)


## Руль крутится по steer, на нём — кисти водителя: обе руки, когда просто держит; одна, когда
## другая занята (пистолет, предмет) или пока высунут в окно; руль пустой, если за ним никого.
func _wheel_vis(delta: float) -> void:
	if wheel_rim == null or not is_instance_valid(wheel_rim):
		return
	wheel_rim.rotation.y = -steer * 2.1
	var driver_in: bool = seats[0] != 0
	var busy := false
	if my_seat == 0 and game != null:
		var g = game.get("gun")
		busy = g != null and is_instance_valid(g) and g.armed() 				and (bool(g.get("ads")) or bool(g.get("hip")) or bool(g.get("rmb")) or bool(g.get("reloading")))
	hands_k = move_toward(hands_k, 1.0 if driver_in else 0.0, delta * 6.0)
	for i in wheel_hands.size():
		var n: Node3D = wheel_hands[i]
		if not is_instance_valid(n):
			continue
		# левая кисть (i == 0) остаётся на руле всегда; правая уходит, когда рука занята
		var on := hands_k > 0.5 and (i == 0 or not (busy or (my_seat == 0 and lean > 0.3)))
		n.visible = on
		if on:
			n.position.y = 0.015 + 0.012 * sin(drive_t * 3.0 + i * 2.1) * clampf(absf(speed) / MAX_F, 0.0, 1.0)


## Куда смотрит видимый кузов (поворот вокруг вертикали).
func vis_yaw() -> float:
	var z := global_transform.basis.z
	return atan2(z.x, z.z)


## С переднего пассажирского — за руль, если водительское свободно (промпт 16.11 05:13).
func can_take_wheel() -> bool:
	return my_seat == 1 and seat_dir == 0 and seats[0] == 0


func take_wheel() -> void:
	if not can_take_wheel():
		return
	switch_to(0)


## Свободное соседнее место (промпт 18.11 01:00): из двух соседей — то, куда больше смотришь. -1 — некуда.
## Водитель на ходу не пересаживается (как и не выходит).
func next_seat() -> int:
	if my_seat < 0 or seat_dir != 0 or (my_seat == 0 and absf(speed) > 1.5):
		return -1
	var fwd: Vector3 = -game.player.cam.global_transform.basis.z
	var eye := seat_eye_world(my_seat)
	var best := -1
	var bd := -INF
	for j in NEXT_SEATS[my_seat]:
		if seats[j] != 0:
			continue
		var d := fwd.dot((seat_eye_world(j) - eye).normalized())
		if d > bd:
			bd = d
			best = j
	return best


func _seat_name(i: int) -> String:
	if i == 0:
		return "за руль"
	if (i < 2) == (my_seat < 2):
		return "на соседнее место"
	return "назад" if i >= 2 else "вперёд"


## Пересесть на место i без выхода (занятое — нельзя). Сеть: v_seat переносит игрока на новое место у всех.
func switch_to(i: int) -> void:
	if i < 0 or i > 3 or seats[i] != 0 or my_seat < 0 or seat_dir != 0:
		return
	var p = game.player
	if my_seat == 0:
		speed = 0.0 if absf(speed) < 1.5 else speed
		_engine(false)
	switch_from = my_seat
	seats[my_seat] = 0
	seats[i] = my_id()
	my_seat = i
	p.set_meta("car_seat", i)
	seat_dir = 2
	seat_anim = 0.0
	if i == 0:
		net_drive = false
		speed = 0.0 if absf(speed) < 0.5 else speed
	game.play_at("whoosh", seat_eye_world(i), -20.0, 0.7)
	if vnet():
		vnet().rpc("v_seat", my_id(), i)


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
	p.remove_meta("car_seat")
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
	# пересесть за руль — E, когда не смотришь на дверь (если луч попал в машину, это делает interact)
	if e.is_action_pressed("interact") and not e.is_echo() and game.focus != self and can_take_wheel() 			and not _looking_at_door() and not game.window_open():
		take_wheel()
		get_viewport().set_input_as_handled()
		return
	if InputMap.has_action("seat_switch") and e.is_action_pressed("seat_switch") and not e.is_echo() \
			and not game.window_open() and game.alive:
		var j := next_seat()
		if j >= 0:
			switch_to(j)
		elif seat_dir == 0 and my_seat == 0 and absf(speed) > 1.5:
			game.hud.toast("Сначала останови машину")
		elif seat_dir == 0:
			game.hud.toast("Рядом нет свободного места")
		get_viewport().set_input_as_handled()
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
	if my_seat == 0 and seat_dir == 0 and game.alive and not game.window_open():
		var thr := Input.get_axis("move_back", "move_forward")
		var st_in := Input.get_axis("move_right", "move_left")
		hand = Input.is_action_pressed("handbrake" if InputMap.has_action("handbrake") else "jump")
		if fuel <= 0.0 or broken:
			thr = 0.0
			if engine_on:
				_engine(false)
				game.hud.toast("Машина сломана" if broken else "Бензин кончился", Color(0.95, 0.7, 0.45))
		var v0 := speed
		_physics(delta, thr, st_in)
		_lean_slip(delta)
		if engine_on:
			fuel = maxf(fuel - delta * FUEL_USE * (0.25 + 0.75 * absf(thr_s)), 0.0)
		if absf(speed) > 0.05 or absf(slip) > 0.05 or absf(yaw_rate) > 0.01:
			_move(delta)
		acc_s = lerpf(acc_s, (speed - v0) / maxf(delta, 0.001), 1.0 - exp(-6.0 * delta))
		net_t -= delta
		if vnet() and net_t <= 0.0:
			net_t = 1.0 / 20.0
			vnet().rpc("v_car", position, yaw, speed, fuel, engine_on)
	elif net_drive:
		# машину ведёт другой игрок — плавно к его данным
		var y0 := yaw
		position = position.lerp(net_pos, 1.0 - exp(-10.0 * delta))
		yaw = lerp_angle(yaw, net_yaw, 1.0 - exp(-10.0 * delta))
		yaw_rate = lerpf(yaw_rate, angle_difference(y0, yaw) / maxf(delta, 0.001), 1.0 - exp(-6.0 * delta))
		acc_s = lerpf(acc_s, 0.0, 1.0 - exp(-3.0 * delta))
		var target := _fit(position, yaw, false)
		transform = Transform3D(transform.basis.slerp(target.basis, 1.0 - exp(-8.0 * delta)), target.origin)
	else:
		speed = move_toward(speed, 0.0, BRAKE * delta)
		slip = move_toward(slip, 0.0, A_LAT * delta)
		yaw_rate = 0.0
		acc_s = 0.0
		hand = false
		wheel_spin = 0.0
	for i in wheels.size():
		if not (hand and i >= 2):   # ручник — задние колёса стоят
			# задний привод: под газом задние крутятся быстрее хода (пробуксовка)
			wheels[i].rotation.x += (speed + (wheel_spin if i >= 2 else 0.0)) / WHEEL_R * delta
	for i in 2:
		wheels[i].rotation.y = steer * lerpf(0.6, 0.27, clampf(absf(speed) / MAX_F, 0.0, 1.0))
	_wheel_vis(delta)
	# подвеска: крен в повороте наружу, клевок при торможении, приседание при разгоне
	var roll_want := clampf(speed * yaw_rate * 0.0025, -0.03, 0.03)
	var pitch_want := clampf(-acc_s * 0.002, -0.02, 0.02)
	roll_vis = lerpf(roll_vis, roll_want, 1.0 - exp(-5.0 * delta))
	pitch_vis = lerpf(pitch_vis, pitch_want, 1.0 - exp(-5.0 * delta))
	rig.rotation = Vector3(pitch_vis, 0.0, roll_vis)
	if engine_on and engine:
		engine.volume_db = lerpf(engine.volume_db, minf(-20.0 + absf(speed) * 0.5 + absf(thr_s) * 2.0, -10.0), 1.0 - exp(-4.0 * delta))
		engine.pitch_scale = 0.8 + absf(speed) * 0.07 + absf(thr_s) * 0.08
		var vib := 0.001 + absf(speed) * 0.00015   # лёгкая дрожь мотора (была сильная тряска, 05:44)
		rig.position = Vector3(0, randf_range(-1, 1) * vib, 0)
	_carry()


## Педали, руль, ручник → speed (вдоль), yaw_rate. Разгон слабеет к максимальной скорости,
## угол руля на скорости меньше, поворот — по колёсной базе (велосипедная модель).
func _physics(delta: float, thr: float, st_in: float) -> void:
	thr_s = move_toward(thr_s, thr, delta * (3.0 if absf(thr) > absf(thr_s) else 6.0))
	var v := speed
	if thr_s > 0.01:
		if v < -0.3:
			speed = move_toward(v, 0.0, BRAKE * thr_s * delta)
		else:
			var k := clampf(v / MAX_F, 0.0, 1.0)
			speed = minf(v + ACC * thr_s * (1.0 - 0.7 * k * k) * delta, maxf(MAX_F, v))
	elif thr_s < -0.01:
		if v > 0.3:
			speed = move_toward(v, 0.0, BRAKE * -thr_s * delta)
		else:
			speed = maxf(v - ACC * 0.7 * -thr_s * delta, minf(-MAX_R, v))
	# качение и сопротивление воздуха
	speed = move_toward(speed, 0.0, (ROLL * (1.0 - absf(thr_s)) + 0.004 * v * v) * delta)
	# ручник срывает зад сразу, сцепление возвращается плавно (~1 с) — можно держать дугу рулём и газом
	# (промпт 05:55) скорость заноса — полная, вместе с боковой: машина боком не «теряет» занос
	var vt := Vector2(speed, slip).length()
	# тормоза (S и ручник) — на задней оси (06:04): резкое торможение разгружает зад, он слегка «ведёт»
	brake_k = -thr_s if thr_s < -0.01 and v > 0.3 else 0.0
	var g_want := 1.0
	if hand and vt > 2.0:
		g_want = 0.0
	elif brake_k > 0.0:
		g_want = 1.0 - 0.1 * brake_k * clampf(vt / MAX_F, 0.0, 1.0)
	# задний привод (промпт 18.11 00:25): тяга только на задние колёса — газ в повороте срывает зад
	# (избыточная поворачиваемость), а с места полный газ + руль — пробуксовка и разворот кормой
	# (00:48) на клавиатуре газ всегда полный — срыв только в крутом повороте на скорости и мягче, иначе виляло
	if thr_s > 0.55 and not hand:
		var pk := (thr_s - 0.55) / 0.45
		var lat := absf(speed * yaw_rate)   # боковое ускорение в повороте, м/с²
		var pw := clampf((lat - 11.0) / 8.0, 0.0, 1.0) * pk * clampf(absf(steer) * 1.5 - 0.5, 0.0, 1.0)
		if speed > 5.0 and pw > 0.0:
			g_want = minf(g_want, 1.0 - 0.4 * pw)
		if speed > 0.8 and speed < 5.0:
			var launch := (1.0 - speed / 5.0) * clampf(absf(steer) * 2.0 - 1.0, 0.0, 1.0) * pk
			g_want = minf(g_want, 1.0 - 0.3 * launch)
	# ручник срывает сразу, газ — плавно (00:48: «заносит слишком резко»)
	grip_k = move_toward(grip_k, g_want, delta * ((5.0 if hand else 1.6) if g_want < grip_k else 1.1))
	var spin_want := maxf(thr_s, 0.0) * (1.0 - grip_k) * 9.0
	if thr_s > 0.9 and absf(speed) < 3.0 and not hand:
		spin_want += (1.0 - absf(speed) / 3.0) * 5.0   # старт с пробуксовкой
	wheel_spin = move_toward(wheel_spin, spin_want, delta * 20.0)
	# случайность заноса: на старте — свой коэффициент срыва и небольшой угловой толчок
	if not drift_on and grip_k < 0.85:
		drift_on = true
		drift_mul = randf_range(0.8, 1.2)
		drift_dir = 1.0 if speed >= -0.5 else -1.0
		if hand:   # толчок кормы — только от ручника
			var dn := signf(steer) if absf(steer) > 0.1 else signf(yaw_rate)
			yaw_rate += dn * randf_range(0.15, 0.35) * clampf(vt / 8.0, 0.0, 1.0)
	elif drift_on and grip_k > 0.95:
		drift_on = false
	# сцепление левого и правого заднего колеса плавает по шуму: разница слегка доворачивает корму
	drive_t += delta
	var nl := sin(drive_t * 2.3) * 0.6 + sin(drive_t * 5.7 + 1.3) * 0.4
	var nr := sin(drive_t * 2.9 + 2.0) * 0.6 + sin(drive_t * 6.3) * 0.4
	grip_noise = (nl + nr) * 0.5
	var loose := 1.0 - grip_k   # (00:48) в обычной езде и при торможении не виляет
	yaw_rate += (nl - nr) * 0.5 * loose * clampf(vt / MAX_F, 0.0, 1.0) * delta
	if hand:
		# торможение по общей скорости (а не отдельно вдоль и вбок — так гасло вдвое быстрее): машина катится в заносе
		var dec := lerpf(HB_DECEL, HB_DECEL_GAS, maxf(thr_s, 0.0)) * delta
		if vt > 0.001:
			var kd := maxf(vt - dec, 0.0) / vt
			speed *= kd
			slip *= kd
		if vt < 0.5:
			# стоит на ручнике: газ не сдвинет
			speed = 0.0
			slip = 0.0
	# руль: к центру возвращается быстрее, чем крутится
	var back := st_in == 0.0 or signf(st_in) != signf(steer)
	steer = move_toward(steer, st_in, delta * (4.0 if back else 2.4))   # (00:48) руль плавнее — без виляния
	var ang := steer * lerpf(0.6, 0.27, clampf(absf(speed) / MAX_F, 0.0, 1.0))
	# в заносе руль крутит по полной скорости (иначе боком машина «замирает» на 90°)
	var drift := 1.0 - grip_k
	# (00:44) знак — по направлению на старте заноса, а не по текущей продольной скорости: раньше после ~90°
	# speed уходил в минус, «хочу» меняло знак и вращение гасло — дальше 90–110° не разворачивало
	var vs := lerpf(speed, vt * (drift_dir if drift_on else (1.0 if speed >= -0.5 else -1.0)), drift)
	if drift > 0.05:
		ang = steer * lerpf(0.6, 0.4, clampf(vt / MAX_F, 0.0, 1.0))
	var want := vs * tan(ang) / WHEELBASE
	# зад без сцепления — корму заносит сильнее; газ (задний привод) выталкивает корму ещё дальше
	want *= 1.0 + drift * (0.6 + 1.1 * maxf(thr_s, 0.0)) * (drift_mul if drift_on else 1.0) + 0.2 * brake_k
	want = clampf(want, -lerpf(9.0, DRIFT_YAW, drift), lerpf(9.0, DRIFT_YAW, drift))
	# в заносе вращение по инерции живёт дольше (плавно крутится, а не дёргается)
	yaw_rate = lerpf(yaw_rate, want, 1.0 - exp(-lerpf(2.3, 8.0, grip_k) * delta))
	# задний привод в заносе: тяга вдоль кузова (задние колёса прямые), часть уходит в пробуксовку —
	# скорость держится, но нос по рулю газ не вытягивает: из заноса выходят сбросом газа и контррулём
	if drift > 0.05 and thr_s > 0.01:
		var a := ACC * thr_s * drift * delta
		speed = minf(speed + a * 0.45, maxf(MAX_F, speed))


## Водитель высунулся: руль держит одной рукой — сцепление хуже и машину дёргает в сторону.
func _lean_slip(delta: float) -> void:
	if lean < 0.25 or my_seat != 0:
		return
	var vt := Vector2(speed, slip).length()
	if vt < 2.0:
		return
	var k := lean * clampf(vt / MAX_F, 0.0, 1.0)
	grip_k = minf(grip_k, lerpf(1.0, 0.45, k))
	lean_kick -= delta
	if lean_kick <= 0.0:
		lean_kick = randf_range(0.4, 1.2)
		yaw_rate += randf_range(-1.0, 1.0) * 0.55 * k
	steer = clampf(steer, -0.75, 0.75)   # одной рукой руль до упора не вывернуть


func _move(delta: float) -> void:
	var old_yaw := yaw
	var old := [speed, slip]
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var side := Vector3(cos(yaw), 0, -sin(yaw))
	var vel := fwd * speed + side * slip
	# кузов поворачивается, а скорость по инерции остаётся прежней — появляется боковая (занос);
	# шины гасят её не быстрее предела сцепления
	yaw += yaw_rate * delta
	fwd = Vector3(sin(yaw), 0, cos(yaw))
	side = Vector3(cos(yaw), 0, -sin(yaw))
	speed = vel.dot(fwd)
	# задний привод: буксующие под газом задние колёса держат вбок хуже — газ продлевает занос
	var a_lat := lerpf(A_LAT_HB, A_LAT, grip_k) * (1.0 - 0.35 * maxf(thr_s, 0.0) * (1.0 - grip_k))
	# в заносе: случайный коэффициент срыва этого заноса и плавающее сцепление колёс
	a_lat *= lerpf(1.0, (2.0 - drift_mul if drift_on else 1.0) * (1.0 + 0.12 * grip_noise), 1.0 - grip_k)
	var sl := vel.dot(side)
	# (00:48) велосипедная модель: с полным сцеплением боковой скорости нет у ЗАДНЕЙ оси, а не у центра —
	# центр кузова при повороте смещается внутрь (yaw_rate * WB/2): поворачивает передом, зад идёт следом
	var sl_want := yaw_rate * WHEELBASE * 0.5 * grip_k
	slip = move_toward(sl, sl_want, a_lat * delta)
	# в заносе под газом часть погашенной боковой скорости уходит вперёд (задние толкают) — не тормозит в ноль
	if grip_k < 0.95 and thr_s > 0.01 and speed > -0.5:
		speed += absf(sl - slip) * 0.25 * thr_s * (1.0 - grip_k)
	vel = fwd * speed + side * slip
	car_vel = vel
	var np := position + vel * delta
	# крутой склон впереди — дальше не едет. Уклон меряем по земле на 1.2 м вперёд по ходу (раньше делили
	# разницу высот на шаг кадра — на старте шаг ~1 мм, и любая неровность/осевший угол «бампали» машину: не ехала)
	if vel.length() > 0.05:
		var dir := vel.normalized()
		var h0: float = surface.height(position.x, position.z)
		var h1: float = surface.height(position.x + dir.x * 1.2, position.z + dir.z * 1.2)
		if (h1 - h0) / 1.2 > 0.75:
			yaw = old_yaw
			speed = old[0]
			slip = old[1]
			_bump()
			return
	var target := _fit(np, yaw, true)
	if _blocked(target):
		yaw = old_yaw
		speed = old[0]
		slip = old[1]
		_bump()
		return
	if carried.is_empty() and absf(speed) > 0.3:
		_grab_carried()
	# подвеска: высоту догоняем плавно (кочки не дёргают кузов), но в землю не проваливаемся
	var y := lerpf(position.y, target.origin.y, 1.0 - exp(-7.0 * delta))
	y = clampf(y, target.origin.y - 0.06, target.origin.y + 0.1)
	# поворот кузова — ровно yaw этого кадра (без отставания); сглаживаем только наклон по кочкам
	var yb := Basis(Vector3.UP, yaw)
	var tilt := (Basis(Vector3.UP, -vis_yaw()) * transform.basis).slerp(yb.inverse() * target.basis, 1.0 - exp(-4.0 * delta))
	transform = Transform3D((yb * tilt).orthonormalized(), Vector3(np.x, y, np.z))
	for m in worn_mats:
		m.set_shader_parameter("origin_shift", position - start_pos)


func _bump() -> void:
	var v := Vector2(speed, slip).length()
	if v > 3.0 and bump_cd <= 0.0:
		bump_cd = 0.6
		game.play_at("thud", global_position, -4.0, 0.7)
		game.hud.hurt_flash(0.2)
		# (00:42) удар на скорости ранит всех в машине
		if v > CRASH_MIN:
			_hurt_all((v - CRASH_MIN) * CRASH_DMG)
	speed = -speed * 0.25
	slip = -slip * 0.25
	yaw_rate = 0.0


## Есть ли что-то на пути (стены, дома, камни). Враги — сбиваем (урон по скорости).
func _blocked(xf: Transform3D) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.5, 0.6, 3.7)
	q.shape = bs
	# коробка сдвинута по ходу: то, во что машина уже упёрлась сзади, не держит её на месте
	# в заносе — по направлению скольжения (раньше по знаку speed: после 90° коробка прыгала назад)
	var lv := Vector3(slip, 0.0, speed)
	var off := lv.normalized() * 0.3 if lv.length() > 0.1 else Vector3.ZERO
	q.transform = xf * Transform3D(Basis(), Vector3(off.x, 0.95, off.z))
	q.collision_mask = 1
	var ex: Array[RID] = [get_rid(), game.player.get_rid()]
	q.exclude = ex
	var hits := get_world_3d().direct_space_state.intersect_shape(q, 8)
	var block := false
	for h in hits:
		var c = h.collider
		if c == null or c.has_meta("ground"):
			ex.append(h.rid)
			continue
		if c is CharacterBody3D and c.has_method("take_hit"):
			_ram(c)
			ex.append(h.rid)
			continue
		block = true
	if not block:
		return false
	# (00:42) «врезаюсь в ничего» в заносе: кузов вращается на месте, и угол коробки цеплял стену/забор сбоку,
	# хотя машина от неё отъезжает. Держим только если точка касания движется В препятствие
	# (скорость машины + вращение), а не от него.
	q.exclude = ex
	var pts := get_world_3d().direct_space_state.collide_shape(q, 16)
	if pts.is_empty():
		return true
	for k in range(0, pts.size(), 2):
		var r: Vector3 = pts[k] - xf.origin
		r.y = 0.0
		if r.length() < 0.05:
			return true
		var pv := car_vel + Vector3(r.z, 0.0, -r.x) * yaw_rate
		if pv.dot(r.normalized()) > 0.05:
			return true
	return false


## Сбить моба (промпт 16.11 05:21): урон — по относительной скорости удара (машина минус моб вдоль
## линии удара), отброс — по ходу машины. take_hit сам шлёт урон хосту, если моб — сетевая копия.
func _ram(c) -> void:
	if c.get_meta("car_hit", false) or car_vel.length() < 0.5:
		return
	var n: Vector3 = c.global_position - global_position
	n.y = 0.0
	n = n.normalized() if n.length() > 0.1 else car_vel.normalized()
	var mv: Vector3 = c.velocity
	var rel := (car_vel - Vector3(mv.x, 0, mv.z)).dot(n)
	if rel < HIT_MIN:
		return
	c.set_meta("car_hit", true)
	get_tree().create_timer(0.8).timeout.connect(_unmark.bind(c))
	var dir := (car_vel.normalized() * 0.6 + n * 0.4).normalized()
	c.take_hit(roundf(rel * HIT_DMG), dir + Vector3(0, 0.2, 0))
	if "knock" in c:
		c.knock += dir * rel * 0.7
	game.play_at("thud", c.global_position, -2.0, 0.8)
	speed *= 0.88
	_hurt_all(rel * RAM_SELF)   # (00:42) наезд на врага — немного HP у сидящих


## Урон всем в машине (водитель решает, сидящие получают по сети: VillageNet.v_car_hurt).
func _hurt_all(dmg: float) -> void:
	dmg = roundf(dmg)
	if dmg < 1.0:
		return
	car_hurt(dmg)
	if vnet():
		vnet().rpc("v_car_hurt", dmg)


func car_hurt(dmg: float) -> void:
	if my_seat < 0 or not game.alive:
		return
	game.drain_hp(dmg)
	game.hud.hurt_flash(clampf(dmg / 25.0, 0.2, 0.8))
	game.play_ui("hurt", -9.0, 0.75)


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


# ---------- прочность кузова и ремонт (промпт 18.11 01:25) ----------

## Моб ударил по машине (enemy.gd / mutant.gd): кузов теряет прочность, машину встряхивает.
## Удар рядом с местом сидящего задевает и его (CAR_SEAT_R / CAR_SEAT_DMG).
func enemy_hit(dmg: float, at: Vector3) -> void:
	if game == null or state != "parked" or dmg <= 0.0:
		return
	car_hp = maxf(car_hp - dmg, 0.0)
	game.play_at("thud", at, -2.0, 0.55)
	if rig:
		rig.position += Vector3(randf_range(-1.0, 1.0), randf_range(-0.6, 0.6), randf_range(-1.0, 1.0)) * 0.035
	if my_seat >= 0 and seat_dir == 0 and at.distance_to(seat_eye_world(my_seat)) < CAR_SEAT_R:
		car_hurt(roundf(dmg * CAR_SEAT_DMG))
	elif my_seat >= 0 and game.hud:
		game.hud.hurt_flash(0.12)   # по машине бьют — тряска и вспышка, но урона нет
	if car_hp <= 0.0 and not broken:
		_break_car()


func _break_car() -> void:
	broken = true
	car_hp = 0.0
	_engine(false)
	speed = 0.0
	if smoke:
		smoke.emitting = true   # из-под капота валит пар
	if game == null:
		return
	game.play_at("clunk", global_position + Vector3(0, 0.8, 0), -2.0, 0.55)
	game.hud.toast("Машина сломана! Нужен молоток", Color(1.0, 0.5, 0.35))


## Какой молоток есть в рюкзаке/руках ("" — никакого). Слесарный (магазин «Инструменты») считается молотком.
func hammer_id() -> String:
	if game == null:
		return ""
	for t in Items.tool_ids("hammer"):
		if game.inv.count(t) > 0:
			return String(t)
	return ""


## Можно починить: кузов побит, игрок снаружи и стоит у капота (спереди машины, +Z) — чтобы не мешать посадке.
func can_repair(g) -> bool:
	if state != "parked" or my_seat >= 0 or g == null or g.player == null:
		return false
	if car_hp >= CAR_MAX_HP:
		return false
	var l: Vector3 = global_transform.affine_inverse() * g.player.global_position
	return l.z > 1.2 and l.z < 3.6 and absf(l.x) < 1.6


## Один удар молотком: возвращает часть прочности, тратит прочность молотка.
func repair_hit() -> void:
	var h := hammer_id()
	if h == "":
		game.hud.toast("Нужен молоток", Color(1.0, 0.6, 0.4))
		return
	car_hp = minf(car_hp + CAR_MAX_HP * CAR_REPAIR, CAR_MAX_HP)
	game._wear_tool(h, 1.0)
	game.play_at("thud", global_position + Vector3(0, 0.9, 0), -4.0, 1.5)
	if broken and car_hp > 0.0:
		broken = false
		if smoke:
			smoke.emitting = false
		game.hud.toast("Кузов поправлен: %d%%" % roundi(car_hp / CAR_MAX_HP * 100.0), Color(0.8, 0.9, 0.6))
	else:
		game.hud.toast("Кузов %d%%" % roundi(car_hp / CAR_MAX_HP * 100.0), Color(0.8, 0.9, 0.6))


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
	trunk_want = 0.0
	trunk_k = 0.0
	if trunk_lid:
		trunk_lid.rotation.x = 0.0
	if trunk_well:
		trunk_well.visible = false


func refuel() -> void:
	if game.inv.count("fuel") <= 0:
		return
	game.inv.remove("fuel", 1)
	fuel = minf(fuel + 0.5, 1.0)   # канистра — полбака (05:59)
	game.play_at("pickup", global_position, -6.0, 0.6)
	game.hud.toast("Бензин %d%%. Садись за руль" % roundi(fuel * 100.0), Color(0.75, 0.9, 0.6))
	if vnet():
		vnet().rpc("v_fuel", fuel)


func to_save() -> Dictionary:
	return {"escaped": escaped, "pos": [position.x, position.y, position.z], "yaw": yaw, "fuel": fuel, "hp": car_hp,
		"seat": my_seat if seat_dir == 0 else -1, "trunk": trunk.contents.duplicate(true)}


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
	car_hp = clampf(float(d.get("hp", CAR_MAX_HP)), 0.0, CAR_MAX_HP)
	broken = car_hp <= 0.0
	if broken and smoke:
		smoke.emitting = true
	set_trunk(d.get("trunk", []))
	var s := int(d.get("seat", -1))
	if s >= 0 and s < 4:
		seat_local.call_deferred(s, true)


# ---------- багажник (промпт 18.11 00:47) ----------

## Игрок снаружи стоит у задней части машины.
func at_trunk(g) -> bool:
	if state != "parked" or my_seat >= 0 or g == null or g.player == null:
		return false
	var l: Vector3 = global_transform.affine_inverse() * g.player.global_position
	return l.z < -1.5 and l.z > -3.6 and absf(l.x) < 1.3


## Точка звука багажника — у задней крышки.
func trunk_world() -> Vector3:
	return global_transform * Vector3(0, 0.95, -1.6)


func open_trunk(g) -> void:
	trunk.car = self
	trunk_want = 1.0
	g.play_at("creak", trunk_world(), -7.0, 1.0)
	g.open_loot(trunk)


## Окно закрыто — содержимое остальным игрокам (VillageNet.v_trunk).
func trunk_closed() -> void:
	trunk_want = 0.0
	if game:
		game.play_at("creak_close", trunk_world(), -7.0, 1.0)
	if vnet():
		vnet().rpc("v_trunk", trunk.contents.duplicate(true))


## Содержимое из сейва / от другого игрока (тот же массив — открытое окно увидит изменения).
func set_trunk(items: Array) -> void:
	trunk.car = self
	trunk.contents.clear()
	for it in items:
		if not (it is Array) or it.size() < 2:
			continue
		var e: Array = [String(it[0]), int(it[1])]
		if it.size() > 2:
			e.append(float(it[2]))
		if it.size() > 4:   # ячейка и поворот в сетке
			e.append_array([int(it[3]), bool(it[4])])
		trunk.contents.append(e)
	if game and game.loot_window and game.loot_window.open and game.loot_window.src == trunk:
		game.loot_window.redraw()
