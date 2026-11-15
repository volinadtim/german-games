extends "res://scripts/player/player_combat.gd"
## Игрок от первого лица: тело видно, если посмотреть вниз.
## WASD, Shift — бег, пробел — прыжок, V или СКМ — боевая стойка (поднять/опустить кулаки),
## ЛКМ — удар левой, ПКМ — удар правой; зажать — заряд до 1.5 с (промпты 18:57, 19:06, 19:09).
## Без стойки ЛКМ/ПКМ только поднимают кулаки, удара нет (промпт 19:08).


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


func _unhandled_input(event: InputEvent) -> void:
	if not active:
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
	elif captured and event.is_action_pressed("fists") and not event.is_echo():
		toggle_fists()
	elif captured and event.is_action_pressed("fists_down") and not event.is_echo():
		charging = -1
		toggle_fists()   # СКМ — второй переключатель стойки, как V (промпт 19:17)
	elif captured and event.is_action_pressed("attack_left") and not event.is_echo():
		charge_begin(0)
	elif captured and event.is_action_pressed("attack_right") and not event.is_echo():
		charge_begin(1)

## Поворот обзора на смещение в пикселях (мышь, тачпад или свайп по экрану).
func look(rel: Vector2) -> void:
	rotate_y(-rel.x * SENS * look_sens)
	head.rotation.x = clampf(head.rotation.x - rel.y * SENS * look_sens, -1.5, 1.4)


## Поворот камеры стрелками — для тачпада, который Windows глушит, пока зажаты клавиши.
## Клавиши приседа (физические, как в main.gd): Ctrl — удерживать, C — переключить.
func _add_crouch_keys() -> void:
	for a in [["crouch", [KEY_CTRL]], ["crouch_toggle", [KEY_C]]]:
		if InputMap.has_action(a[0]):
			continue
		InputMap.add_action(a[0])
		for k in a[1]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(a[0], ev)


## Встать (по бегу или прыжку): переключатель снимаем, удержание Ctrl игнорируем до отпускания.
func _stand_request() -> void:
	crouch_toggled = false
	if Input.is_action_pressed("crouch"):
		crouch_hold_block = true


func _key_look(delta: float) -> void:
	if not active:
		return
	var v := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if v == Vector2.ZERO:
		return
	rotate_y(-v.x * KEY_TURN * look_sens * delta)
	head.rotation.x = clampf(head.rotation.x - v.y * KEY_TURN * 0.7 * look_sens * delta, -1.5, 1.4)


func _process(delta: float) -> void:
	if charge_ui == null and not puppet:
		_make_charge_ui()
	_charge_tick(delta)
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


func _physics_process(delta: float) -> void:
	if puppet:
		_puppet_tick(delta)
		return
	_key_look(delta)
	var on_floor := is_on_floor()
	# прыжок из приседа сначала поднимает игрока
	var jump_now := active and Input.is_action_just_pressed("jump")
	if jump_now and crouched:
		_stand_request()
		jump_now = false
	if not on_floor:
		velocity.y -= GRAVITY * (FALL_MULT if velocity.y < 0.0 else 1.0) * delta
	elif jump_now:
		velocity.y = JUMP
		on_floor = false

	var inp := Vector2.ZERO
	if active:
		inp = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := transform.basis * Vector3(inp.x, 0, inp.y)
	var moving := dir.length() > 0.01
	var sprinting := active and moving and inp.y < -0.1 and Input.is_action_pressed("sprint")
	# бег из приседа сначала поднимает игрока
	if sprinting and crouched:
		_stand_request()
	_update_crouch(delta)
	if crouched:
		sprinting = false

	if sprinting:
		sprint_carry = 1.0
	else:
		sprint_carry = move_toward(sprint_carry, 0.0, delta * 2.0)

	var target := dir * (SPRINT if sprinting else WALK) * speed_mult * lerpf(1.0, CROUCH_SPEED, crouch)
	var hv := Vector3(velocity.x, 0, velocity.z)
	var air := 1.0 if on_floor else 0.25
	if moving and target.length() > hv.length() + 0.01:
		# разгон: с места до шага ~0.2 с, с шага до бега ~0.2 с
		var accel := ACCEL_SPRINT if hv.length() > WALK - 0.2 else ACCEL_WALK
		var spd := move_toward(hv.length(), target.length(), accel * air * delta)
		var d := hv.normalized().slerp(target.normalized(), 1.0 - exp(-10.0 * air * delta)) if hv.length() > 0.1 else target.normalized()
		hv = d * spd
	else:
		# торможение линейное, а не экспоненциальное: экспонента никогда не доходит до нуля
		# и давала «хвост» скольжения ~1 м после бега. Теперь стоп с бега ~0.18 с, с шага ~0.09 с
		var decel := (DECEL_TURN if moving else lerpf(DECEL_WALK, DECEL_SPRINT, sprint_carry)) * air
		hv = hv.move_toward(target, decel * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	if net_push.is_valid():
		net_push.call(self, delta)
	move_and_slide()

	if is_on_floor() and not was_on_floor and land_speed < -2.5:
		_play_step(-4.0)
		land_dip = clampf(-land_speed * 0.014, 0.0, 0.09)
	land_speed = velocity.y
	was_on_floor = is_on_floor()

	_animate(delta, global_transform.basis.inverse() * hv, sprinting)
