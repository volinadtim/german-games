extends "res://scripts/player/player_death.gd"
## Игрок от первого лица: тело видно, если посмотреть вниз.
## WASD, Shift — бег, пробел — прыжок, V или СКМ — боевая стойка (поднять/опустить кулаки),
## ЛКМ — удар левой, ПКМ — удар правой; зажать — заряд до 1.5 с (промпты 18:57, 19:06, 19:09).
## Без стойки ЛКМ/ПКМ только поднимают кулаки, удара нет (промпт 19:08).
const StepUp := preload("res://scripts/core/step_up.gd")

func _ready() -> void:
	step_player = _audio(3)
	voice_player = _audio(2)
	hit_player = _audio(3)
	for i in 4:
		whooshes.append(Sfx.whoosh(i))
		heavy_whooshes.append(Sfx.whoosh(i, true))
		exhales.append(Sfx.exhale(i))
		impacts.append(Sfx.impact(i))
	inhale_snd = Sfx.inhale()
	exhale_out_snd = Sfx.inhale(true)
	step_noise_player = _audio(3)
	step_noise = Sfx.step_noise()
	for i in 3:
		scuff_noise.append(_scuff(i))
	for i in 4:
		grass_steps.append(Sfx.step_grass(i))
	_setup_step_bus()

	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	wall_min_slide_angle = 0.0   # в стену почти в лоб — скользим вдоль, а не застреваем (по умолчанию 15°)
	col_shape = cs
	col_cap = cap
	_add_crouch_keys()

	head = Node3D.new()
	head.position = Vector3(0, CAM_Y, -0.22)
	add_child(head)
	cam = Camera3D.new()
	cam.near = 0.04
	cam.fov = fov_base
	head.add_child(cam)

	_build_body()
	if USE_MODEL:
		_build_model()


## Окно потеряло фокус (Alt+Tab, окно «залипания» Shift, смена раскладки) — отпускания клавиш
## могут не дойти, и бег/шаг «залипали» (промпт 23:34). Отпускаем все действия сами.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		for a in InputMap.get_actions():
			if Input.is_action_pressed(a):
				Input.action_release(a)


## Автобег (промпт 04:38): Windows при долгом Shift (залипание/фильтрация клавиш) может «съесть»
## отпускание W/Shift — действие остаётся нажатым, и персонаж бежит сам. Каждый кадр сверяем
## движение и бег с реальным состоянием клавиш/кнопок мыши; не нажато физически — отпускаем.
## Телефон (touch_controls.gd жмёт действия сам) и действия с геймпадом не трогаем.
const _MOVE_ACTIONS := ["move_forward", "move_back", "move_left", "move_right", "sprint"]

func _unstick_moves() -> void:
	if ia != Input or OS.has_feature("mobile") or "--touch" in OS.get_cmdline_user_args():
		return
	for a in _MOVE_ACTIONS:
		if not InputMap.has_action(a) or not Input.is_action_pressed(a):
			continue
		var held := false
		var known := true
		for ev in InputMap.action_get_events(a):
			if ev is InputEventKey:
				var k := ev as InputEventKey
				if (k.physical_keycode != KEY_NONE and Input.is_physical_key_pressed(k.physical_keycode)) \
						or (k.keycode != KEY_NONE and Input.is_key_pressed(k.keycode)):
					held = true
			elif ev is InputEventMouseButton:
				if Input.is_mouse_button_pressed((ev as InputEventMouseButton).button_index):
					held = true
			else:
				known = false   # геймпад и пр. — не проверяем
		if known and not held:
			Input.action_release(a)


func _unhandled_input(event: InputEvent) -> void:
	if ia != Input:
		return   # игрок 2 в Split-Screen: кнопки шлёт split.gd
	if not active:
		return
	# Пока открыт выбор выброса на G — не бьём, не стреляем и не заряжаем удар
	if game != null and game.get("_drop_mode"):
		# камера при этом крутится как обычно
		if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
				and event.device != InputEvent.DEVICE_ID_EMULATION:
			look(event.relative)
		return
	# мышь, эмулированная из касаний (телефон), — обзор и удары там делает touch_controls.gd
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	# отпустил кнопку удара — удар с накопленным зарядом (отпускание ловим и без захвата мыши)
	if event.is_action_released("attack_left"):
		charge_release(0)
		return
	if event.is_action_released("attack_right"):
		charge_release(1)
		return
	if event is InputEventMouseMotion and captured:
		look(event.relative)
	elif event is InputEventMouseButton and event.pressed and not captured:
		# клик мимо кнопок инвентаря/лута/магазина не должен прятать курсор (баг 14.11 20:05)
		if game == null or not game.window_open():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif carrying and (event.is_action_pressed("fists") or event.is_action_pressed("attack_left") or event.is_action_pressed("attack_right")):
		pass   # руки заняты (carry.gd)
	elif captured and event.is_action_pressed("fists") and not event.is_echo():
		charging = -1
		toggle_fists()   # стойка — СКМ (промпт 16.11 02:15; V больше нет)
	elif captured and event.is_action_pressed("attack_left") and not event.is_echo():
		charge_begin(0)
	elif captured and event.is_action_pressed("attack_right") and not event.is_echo():
		charge_begin(1)

## Поворот обзора на смещение в пикселях (мышь, тачпад или свайп по экрану).
func look(rel: Vector2) -> void:
	rotate_y(-rel.x * SENS * look_sens)
	head.rotation.x = clampf(head.rotation.x - rel.y * SENS * look_sens, -1.5, 1.4)


## Поворот камеры стрелками — для тачпада, который Windows глушит, пока зажаты клавиши.
## Клавиши приседа (Ctrl — удерживать, C — переключить) — из data/controls/bindings.cfg (Controls).
func _add_crouch_keys() -> void:
	pass


## Встать (по бегу или прыжку): переключатель снимаем, удержание Ctrl игнорируем до отпускания.
func _stand_request() -> void:
	crouch_toggled = false
	if ia.is_action_pressed("crouch"):
		crouch_hold_block = true


func _key_look(delta: float) -> void:
	if not active:
		return
	if not InputMap.has_action("look_left"):   # поворот стрелками убран (main.gd больше не создаёт look_*)
		return
	var v: Vector2 = ia.get_vector("look_left", "look_right", "look_up", "look_down")
	if v == Vector2.ZERO:
		return
	rotate_y(-v.x * KEY_TURN * look_sens * delta)
	head.rotation.x = clampf(head.rotation.x - v.y * KEY_TURN * 0.7 * look_sens * delta, -1.5, 1.4)


func _process(delta: float) -> void:
	if charge_ui == null and not puppet:
		_make_charge_ui()
	_charge_tick(delta)
	_aim_kick_tick(delta)
	if trail_mesh.is_empty():
		_make_trails()
	for i in 2:
		var pts: Array = trail_pts[i]
		if trail_on[i]:
			var fp := _trail_point(i)
			if pts.is_empty() or (pts[-1] as Vector3).distance_to(fp) > 0.015:
				pts.append(fp)
				if pts.size() > (10 if weapon_ids[i] != "" else 7):
					pts.pop_front()
		else:
			trail_alpha[i] = maxf(trail_alpha[i] - delta * 7.0, 0.0)
		_draw_trail(i)


## Noclip (консоль /noclip): летим куда смотрит камера, сквозь стены. Пробел — вверх, Ctrl — вниз, Shift — быстрее.
func _noclip_tick(delta: float) -> void:
	velocity = Vector3.ZERO
	if not active:
		nc_vel = Vector3.ZERO
		_animate(delta, Vector3.ZERO, false)
		return
	var inp: Vector2 = ia.get_vector("move_left", "move_right", "move_forward", "move_back")
	var b: Basis = cam.global_transform.basis
	var dir: Vector3 = b.x * inp.x + b.z * inp.y
	if ia.is_action_pressed("jump"):
		dir += Vector3.UP
	if ia.is_action_pressed("crouch"):
		dir += Vector3.DOWN
	if dir.length() > 1.0:
		dir = dir.normalized()
	var spd: float = nc_speed * (3.0 if ia.is_action_pressed("sprint") else 1.0)
	global_position += dir * spd * delta
	nc_vel = nc_vel.lerp(dir * spd, 1.0 - exp(-8.0 * delta))
	_animate(delta, global_transform.basis.inverse() * nc_vel, false)   # поза полёта (player_anim.gd)


func _physics_process(delta: float) -> void:
	if puppet:
		_puppet_tick(delta)
		_death_tick(delta)
		return
	_key_look(delta)
	if noclip:
		_noclip_tick(delta)
		return
	for w in get_tree().get_nodes_in_group("lake_water"):   # в воде озера — плавание (locations/lake/lake_dive.gd)
		if w.swim_tick(self, delta):
			return
	_unstick_moves()
	if stamina == null:
		stamina = preload("res://scripts/player/stamina.gd").new()
		add_child(stamina)
	if dash == null:
		dash = preload("res://scripts/player/dash.gd").new()   # рывок на двойной WASD (18.11 00:27)
		add_child(dash)
	if slide_node == null:
		slide_node = preload("res://scripts/player/slide.gd").new()
		add_child(slide_node)
	var inp := Vector2.ZERO
	if active:
		inp = ia.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := transform.basis * Vector3(inp.x, 0, inp.y)
	var moving := dir.length() > 0.01
	var sprinting: bool = active and not carrying and moving and inp.y < -0.1 \
		and ia.is_action_pressed("sprint") and (dash == null or dash.hold_t > 0.07)
	if sprinting and not stamina.can_sprint():
		sprinting = false

	# Проверяем подкат до прыжка и приседа
	var want_crouch: bool = active and (
		(ia.is_action_pressed("crouch") and not crouch_hold_block)
		or crouch_toggled
		or ia.is_action_just_pressed("crouch_toggle")
	)
	
	slide_node.poll(delta, active and not carrying and has_skill("slide"), sprinting, want_crouch, dir)
	if slide_node.active:
		crouched = true
		sprinting = false

	var on_floor := is_on_floor()
	var jump_now: bool = active and not carrying and ia.is_action_just_pressed("jump") \
		and not (game != null and game.inv != null and game.inv.open and get_viewport().gui_is_dragging())

	if jump_now and slide_node.active:
		slide_node.try_slide_jump()
		_stand_request()
		crouched = false
		if on_floor and stamina.can_jump():
			velocity.y = JUMP * slide_node.JUMP_UP_MULT * cheat_jump
			stamina.jump(stamina.JUMP_COST)
			make_noise(NOISE_JUMP)
			on_floor = false
		jump_now = false


	if on_floor:
		air_jumped = false
	elif jump_now and not air_jumped and has_skill("double_jump") and stamina.can_jump():
		air_jumped = true   # двойной прыжок (древо прокачки)
		velocity.y = JUMP * cheat_jump
		stamina.jump()
		make_noise(NOISE_JUMP)
		jump_now = false
	if not on_floor:
		velocity.y -= GRAVITY * (FALL_MULT if velocity.y < 0.0 else 1.0) * delta
	elif jump_now and stamina.can_jump():
		velocity.y = JUMP * cheat_jump
		stamina.jump()
		make_noise(NOISE_JUMP)
		on_floor = false

	# бег из обычного приседа сначала поднимает игрока
	if sprinting and crouched and not slide_node.active:
		_stand_request()
	_update_crouch(delta)
	if slide_node.active:
		crouched = true


	stamina.tick(delta, sprinting, moving)
	dash.poll(delta, active and not carrying and not crouched, dir)
	_noise_tick(delta, moving and Vector3(velocity.x, 0, velocity.z).length() > 0.4, sprinting)

	if sprinting:
		sprint_carry = 1.0
	else:
		sprint_carry = move_toward(sprint_carry, 0.0, delta * 2.0)

	var target := dir * (SPRINT if sprinting else WALK) * speed_mult * cheat_spd * lerpf(1.0, CROUCH_SPEED, crouch)
	target *= preload("res://scripts/systems/levels.gd").speed_k()   # атрибут «Скорость»
	var hv := Vector3(velocity.x, 0, velocity.z)
	air_t = 0.0 if on_floor else air_t + delta
	var air := 1.0 if (on_floor or (air_t < 0.15 and velocity.y <= 0.0)) else 0.25
	if moving and hv.length() > 0.5 and hv.normalized().dot(target.normalized()) < 0.5:
		hv = hv.move_toward(target, (ACCEL_WALK + DECEL_TURN) * air * delta)
	elif moving and target.length() > hv.length() + 0.01:
		var accel := ACCEL_SPRINT if hv.length() > WALK - 0.2 else ACCEL_WALK
		var spd := move_toward(hv.length(), target.length(), accel * air * delta)
		var d := hv.normalized().slerp(target.normalized(), 1.0 - exp(-10.0 * air * delta)) if hv.length() > 0.1 else target.normalized()
		hv = d * spd
	else:
		var decel := (DECEL_TURN if moving else lerpf(DECEL_WALK, DECEL_SPRINT, sprint_carry)) * air
		hv = hv.move_toward(target, decel * delta)

	hv = dash.apply(hv, delta)
	hv = slide_node.apply(hv, delta)
	velocity.x = hv.x
	velocity.z = hv.z
	if net_push.is_valid():
		net_push.call(self, delta)
	# ступеньки (промпт 03:51): уступ до 0.4 м — переступаем; камера догоняет плавно, нога выше
	var su := StepUp.step_up(self, on_floor or (air_t < 0.15 and velocity.y <= 0.0), delta)
	if su > 0.0:
		cam_step -= su
		step_lift = maxf(step_lift, su * 0.7)
	move_and_slide()
	cam_step += StepUp.step_down(self, on_floor)
	cam_step = clampf(cam_step, -0.5, 0.5) * exp(-11.0 * delta)
	step_lift = move_toward(step_lift, 0.0, delta * 1.2)

	if is_on_floor() and not was_on_floor and land_speed < -2.5:
		_play_step(-4.0)
		land_dip = clampf(-land_speed * 0.014, 0.0, 0.09)
	land_speed = velocity.y
	was_on_floor = is_on_floor()

	_animate(delta, global_transform.basis.inverse() * hv, sprinting)
	_death_tick(delta)   # анимация смерти (player_death.gd)
