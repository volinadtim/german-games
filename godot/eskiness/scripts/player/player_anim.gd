extends "res://scripts/player/player_model.gd"
# Часть player.gd: анимация тела и ног, повороты, idle, IK, следы ударов, копия игрока в сети.


func _update_crouch(delta: float) -> void:
	if active and Input.is_action_just_pressed("crouch_toggle"):
		crouch_toggled = not crouch_toggled
	if active and Input.is_action_just_pressed("crouch"):
		crouch_hold_block = false
	if not Input.is_action_pressed("crouch"):
		crouch_hold_block = false
	var want := active and (crouch_toggled or (Input.is_action_pressed("crouch") and not crouch_hold_block))
	if puppet:
		want = net_crouch
	if want:
		crouched = true
	elif crouched and not _head_blocked():
		crouched = false
	crouch = move_toward(crouch, 1.0 if crouched else 0.0, delta * 4.0)
	# капсула: верх опускается, низ стоит на полу
	var h := lerpf(1.8, CROUCH_H, crouch)
	if absf(col_cap.height - h) > 0.001:
		col_cap.height = h
		col_shape.position.y = h / 2.0


## Можно ли встать: лучи вверх от верха приседа до роста стоя (центр и 4 точки по краю).
func _head_blocked() -> bool:
	var space := get_world_3d().direct_space_state
	for o in [Vector3.ZERO, Vector3(0.22, 0, 0), Vector3(-0.22, 0, 0), Vector3(0, 0, 0.22), Vector3(0, 0, -0.22)]:
		var from: Vector3 = global_position + o + Vector3(0, CROUCH_H - 0.05, 0)
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, 1.85 - CROUCH_H + 0.05, 0))
		q.exclude = [get_rid()]
		q.collision_mask = 1
		if space.intersect_ray(q):
			return true
	return false


## Точка, за которой тянется след: конец оружия, а без оружия — кулак.
func _trail_point(i: int) -> Vector3:
	var n = weapon_nodes[i]
	if n != null and is_instance_valid(n) and n.is_inside_tree():
		return (n as Node3D).global_transform * Vector3(0, WEAPON_TIP.get(weapon_ids[i], 0.4), 0)
	return fist_fx[i].global_position


func _make_trails() -> void:
	trail_mat = StandardMaterial3D.new()
	trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_mat.vertex_color_use_as_albedo = true
	trail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in 2:
		var im := ImmediateMesh.new()
		var mi := MeshInstance3D.new()
		mi.mesh = im
		mi.material_override = trail_mat
		mi.top_level = true
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.global_transform = Transform3D.IDENTITY
		trail_mesh.append(im)


## След: основной штрих и тонкий параллельный, сужаются к хвосту и прозрачные — как росчерк кистью.
func _draw_trail(i: int) -> void:
	var im := trail_mesh[i]
	im.clear_surfaces()
	var pts: Array = trail_pts[i]
	if pts.size() < 3 or trail_alpha[i] <= 0.0:
		return
	var view := -cam.global_transform.basis.z
	var wide := 1.8 if weapon_ids[i] != "" else 1.0
	for stroke in [[0.0, 0.01 * wide, 0.2], [0.03 * wide, 0.004 * wide, 0.12]]:
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		var n := pts.size()
		for k in n:
			var a: Vector3 = pts[maxi(k - 1, 0)]
			var b: Vector3 = pts[mini(k + 1, n - 1)]
			var side := (b - a).cross(view).normalized()
			var t := float(k) / float(n - 1)          # 0 — хвост, 1 — у кулака
			var w: float = stroke[1] * sin(t * PI * 0.9 + 0.1)
			var c: Vector3 = pts[k] + side * float(stroke[0]) * t
			im.surface_set_color(Color(0.95, 0.92, 0.85, float(stroke[2]) * t * trail_alpha[i]))
			im.surface_add_vertex(c - side * w)
			im.surface_set_color(Color(0.95, 0.92, 0.85, float(stroke[2]) * t * trail_alpha[i]))
			im.surface_add_vertex(c + side * w)
		im.surface_end()


func _animate(delta: float, v_local: Vector3, sprinting: bool) -> void:
	var spd := v_local.length()
	var grounded := is_on_floor()
	_update_idle(delta, spd, grounded)
	_animate_legs(delta, v_local, grounded)
	var amt := clampf(spd / WALK, 0.0, 1.5) if grounded else 0.0
	phase = gait * TAU * 2.0
	var box_ph := sin(idle_time * TAU * 1.8) * fist_blend * idle_amt
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var p: Vector4 = arm_pose[i]
		# заряд удара (промпт 19:32): рука удара оттягивается к щеке, вторая выдвигается вперёд раскрытой ладонью
		if charge_arm >= 0 and charge_vis > 0.0:
			var ck := smoothstep(0.0, 1.0, charge_vis)
			if i == charge_arm:
				var hv := 1.3 if weapon_ids[i] != "" else 1.0   # с оружием замах сильнее
				p += CHARGE_POSE * ck * hv
				if charge_vis > 0.97 and charging >= 0:
					# на максимуме — лёгкая дрожь от напряжения
					p += Vector4(sin(idle_time * 41.0) * 1.6, 0, cos(idle_time * 37.0) * 1.2, sin(idle_time * 47.0) * 1.4)
			else:
				p += CHARGE_OTHER * ck
		# рука качается навстречу противоположной ноге
		var arm_swing := clampf(-foot[1 - i].z * 1.1, -0.6, 0.6) * (1.0 - fist_blend)
		var guard_bob := deg_to_rad(sin(phase + float(i)) * 3.0 * amt * fist_blend + box_ph * 2.5)
		# дыхание чуть разводит руки, в покое они слегка покачиваются
		var rest_sway := (sin(idle_time * 0.9 + float(i) * 2.0) * 0.03 + sin(idle_time * 0.37 + float(i)) * 0.015) * idle_amt * (1.0 - fist_blend)
		# руки не по швам: стоя локти чуть согнуты, руки немного вперёд и в стороны (на ходу — меньше);
		# разгруженная сторона висит свободнее
		var ra := (1.0 - fist_blend) * (0.35 + 0.65 * idle_amt)
		var unl := clampf(-weight * side, 0.0, 1.0) * idle_amt
		var relax_x := deg_to_rad(1.5 + 1.5 * unl) * ra
		var relax_z := deg_to_rad(4.0 + 1.5 * sin(idle_time * 0.31 + float(i) * 1.9)) * ra
		var relax_y := deg_to_rad(6.0) * ra
		var relax_el := deg_to_rad(9.0 - 3.0 * unl + 2.5 * sin(idle_time * 0.53 + float(i) * 2.7)) * ra
		# удар по высоте взгляда: в стойке рука чуть следует за взглядом, в ударе — полностью
		aim_w[i] = move_toward(aim_w[i], 1.0 if (punching and last_arm == i) else 0.0, get_physics_process_delta_time() * 7.0)
		var look_p := clampf(head.rotation.x, -1.2, 1.0)
		var aim_lift := look_p * (0.2 * fist_blend + 0.7 * aim_w[i])
		shoulders[i].rotation = Vector3(
			deg_to_rad(p.x) + arm_swing + guard_bob + rest_sway + aim_lift + relax_x,
			deg_to_rad(p.y) * side + relax_y * side,
			deg_to_rad(p.z) * side + 0.08 * side * (1.0 - fist_blend) + relax_z * side)
		elbows[i].rotation.x = deg_to_rad(p.w) + relax_el
		if not USE_MODEL:
			shoulders[i].position.z = 0.13 - reach[i]
	bob = lerpf(bob, amt, 1.0 - exp(-8.0 * delta))
	land_dip = move_toward(land_dip, 0.0, delta * 0.35)
	# голова ниже всего в момент постановки стопы (дважды за цикл)
	head.position.y = CAM_Y - (0.5 + 0.5 * cos(phase)) * 0.035 * bob * (1.0 - 0.5 * crouch) - land_dip + hip_off.y * 0.6 \
			- CROUCH_CAM * _crouch_k()
	head.position.x = sin(gait * TAU) * 0.012 * bob
	# в стойке голова чуть назад — к плечам, чтобы кулаки были перед лицом, а не в камере
	head.position.z = lerpf(-0.22, -0.04, fist_blend) - 0.06 * _crouch_k()
	# камера всегда на уровне глаз тела и перед шеей (присед, наклон, удары): по кости головы
	if skel != null and head_bone != -1:
		var hb := to_local(skel.global_transform * skel.get_bone_global_pose(head_bone).origin)
		var hd := Basis(Vector3.UP, angle_difference(rotation.y, torso_yaw))
		var eye := hb + hd * Vector3(0, 0.08, -0.1)
		head.position.y = maxf(head.position.y, eye.y)
		head.position.z = minf(head.position.z, eye.z)
	var want_fov := fov_base + (7.0 if sprinting else 0.0)
	cam.fov = lerpf(cam.fov, want_fov, 1.0 - exp(-5.0 * delta))
	_apply_bones()


## Процедурная походка: для каждой стопы считаем точку (опора — стопа едет назад по полу,
## перенос — дугой вперёд), затем двухзвенный IK ставит бедро и колено.
func _animate_legs(delta: float, v_local: Vector3, grounded: bool) -> void:
	var spd := v_local.length()
	if spd > 0.1:
		move_dir = Vector3(v_local.x, 0, v_local.z).normalized()
	_turn_body(delta, spd > 0.4 or not grounded or not stopping or settle_t[0] < 1.0 or settle_t[1] < 1.0)
	if not grounded:
		# в воздухе ноги подогнуты, одна чуть впереди
		stopping = false
		for i in 2:
			var tuck := Vector3(0, GROUND_Y + 0.24 + 0.04 * i, -0.14 + 0.2 * i)
			foot[i] = foot[i].lerp(tuck, 1.0 - exp(-9.0 * delta))
			foot_pitch[i] = lerpf(foot_pitch[i], -0.35, 1.0 - exp(-9.0 * delta))
	elif spd > 0.4:
		stopping = false
		var run := clampf((spd - WALK) / (SPRINT - WALK), 0.0, 1.0)
		var beta := lerpf(0.62, 0.42, run)           # доля опоры в цикле (при беге есть фаза полёта)
		var cycle := 2.0 + 0.1 * spd                 # метров за полный цикл (два шага)
		var amp := clampf(0.06 + 0.045 * spd, 0.0, 0.32)
		var lift := 0.04 + 0.025 * spd
		gait = fmod(gait + spd / cycle * delta, 1.0)
		for i in 2:
			var ph := fmod(gait + 0.5 * i, 1.0)
			var s: float
			var h := 0.0
			if ph < beta:
				s = amp * (1.0 - 2.0 * ph / beta)
			else:
				var u := (ph - beta) / (1.0 - beta)
				s = -amp + 2.0 * amp * smoothstep(0.0, 1.0, u)
				h = lift * sin(PI * u)
			# перекат стопы: удар пяткой (носок вверх) -> плоско -> отрыв с носка (пятка вверх)
			var pitch := 0.0
			if ph < beta:
				var us := ph / beta
				if us < 0.15:
					pitch = 0.25 * (1.0 - us / 0.15)
				elif us > 0.7:
					pitch = -0.55 * (us - 0.7) / 0.3
			else:
				pitch = lerpf(-0.55, 0.25, smoothstep(0.0, 1.0, (ph - beta) / (1.0 - beta)))
			foot_pitch[i] = lerpf(foot_pitch[i], pitch, 1.0 - exp(-25.0 * delta))
			# поднимаем голеностоп, чтобы носок/пятка не уходили в пол
			h += 0.16 * maxf(-sin(foot_pitch[i]), 0.0) + 0.08 * maxf(sin(foot_pitch[i]), 0.0)
			var tgt := Vector3(move_dir.x * s, GROUND_Y + h, move_dir.z * s)
			foot[i] = foot[i].lerp(tgt, 1.0 - exp(-30.0 * delta))
			# стопа встала на пол — звук шага
			if ph < gait_prev[i]:
				_play_step(-6.0 if run > 0.5 else -10.0)
			gait_prev[i] = ph
	else:
		# остановка как у людей: передняя нога остаётся, задняя подтягивается вперёд и встаёт рядом
		if not stopping:
			stopping = true
			var md := Vector2(move_dir.x, move_dir.z)
			var s0 := Vector2(foot[0].x, foot[0].z).dot(md)
			var s1 := Vector2(foot[1].x, foot[1].z).dot(md)
			var front := 0 if s0 >= s1 else 1
			var rear := 1 - front
			settle_from[front] = foot[front]
			settle_to[front] = Vector3(foot[front].x, GROUND_Y, foot[front].z)
			settle_t[front] = 1.0 if foot[front].y <= GROUND_Y + 0.01 else 0.5
			settle_from[rear] = foot[rear]
			settle_to[rear] = Vector3(foot[front].x * 0.3, GROUND_Y, foot[front].z)
			settle_t[rear] = 0.0
		# тело ещё скользит по инерции — стоящие стопы остаются на месте относительно пола
		var slide := Vector3(v_local.x, 0, v_local.z) * delta
		for i in 2:
			foot_pitch[i] = lerpf(foot_pitch[i], 0.0, 1.0 - exp(-12.0 * delta))
			settle_to[i] -= slide
			if settle_t[i] < 1.0:
				settle_t[i] = minf(settle_t[i] + delta / 0.26, 1.0)
				var k := smoothstep(0.0, 1.0, settle_t[i])
				foot[i] = settle_from[i].lerp(settle_to[i], k) + Vector3(0, 0.06 * sin(PI * settle_t[i]), 0)
				if settle_t[i] >= 1.0:
					_play_step(-14.0)
			else:
				foot[i] -= slide
				foot[i].y = move_toward(foot[i].y, GROUND_Y, delta * 0.5)
		# тело проехало дальше стоп (резкий стоп с бега) — дальняя стопа дошагивает под таз
		if settle_t[0] >= 1.0 and settle_t[1] >= 1.0 and turn_foot < 0:
			var d0 := Vector2(foot[0].x, foot[0].z).length()
			var d1 := Vector2(foot[1].x, foot[1].z).length()
			var far := 0 if d0 >= d1 else 1
			if maxf(d0, d1) > 0.13:
				settle_from[far] = foot[far]
				settle_to[far] = Vector3(0.0, GROUND_Y, 0.0)
				settle_t[far] = 0.0
	if turn_foot >= 0:
		_turn_step(delta)
	for i in 2:
		var t := foot[i] - _hip()
		# в приседе стопы чуть шире, левая немного впереди
		var ck := _crouch_k()
		t += Vector3((-1.0 if i == 0 else 1.0) * 0.05, 0.0, -0.07 if i == 0 else 0.05) * ck
		# поза покоя: стопы чуть шире таза, левая чуть впереди, разгруженная выдвинута вперёд,
		# носки слегка развёрнуты наружу; опорная нога прямее, разгруженная — мягче
		var side := -1.0 if i == 0 else 1.0
		var rk := idle_amt * (1.0 - fist_blend) * (1.0 - ck)
		var unl := clampf(-weight * side, 0.0, 1.0)
		t += Vector3(side * (0.03 + 0.01 * unl), -side * weight * 0.004, (-0.025 if i == 0 else 0.01) - 0.02 * unl) * rk
		# разгруженная нога: пятка чуть приподнята, колено подсогнуто
		t.y += 0.16 * maxf(-sin(idle_pitch[i]), 0.0)
		_leg_ik(i, t, idle_pitch[i], -side * deg_to_rad(9.0 + 3.0 * unl) * rk)


## Торс догоняет взгляд с задержкой. На ходу и в прыжке ноги сразу смотрят по взгляду (как раньше);
## стоя — стоят, пока угол не станет большим (или поворот длится), тогда переступают.
func _turn_body(delta: float, busy: bool) -> void:
	var cam_yaw := rotation.y
	if not yaw_init or absf(angle_difference(cam_yaw, feet_yaw)) > 2.6:
		yaw_init = true
		feet_yaw = cam_yaw
		torso_yaw = cam_yaw
	torso_yaw = lerp_angle(torso_yaw, cam_yaw, 1.0 - exp(-7.0 * delta))
	var lag := angle_difference(cam_yaw, torso_yaw)
	if absf(lag) > 0.6:
		torso_yaw = cam_yaw + signf(lag) * 0.6
	if not USE_MODEL:
		feet_yaw = cam_yaw
		torso_yaw = cam_yaw
		return
	if busy:
		turn_foot = -1
		turn_steps = 0
		turn_hold = 0.0
		feet_yaw = lerp_angle(feet_yaw, cam_yaw, 1.0 - exp(-12.0 * delta))
		for i in 2:
			foot_yaw[i] = lerpf(foot_yaw[i], 0.0, 1.0 - exp(-12.0 * delta))
		return
	var off := angle_difference(feet_yaw, cam_yaw)
	turn_hold = turn_hold + delta if absf(off) > deg_to_rad(20.0) else 0.0
	if turn_foot < 0 and (absf(off) > deg_to_rad(55.0) or turn_hold > 0.6):
		turn_steps = 2 if absf(off) > deg_to_rad(45.0) else 1
		# поворот налево (угол растёт) — первой шагает левая нога, направо — правая
		_start_turn_step(0 if off > 0.0 else 1)


func _start_turn_step(i: int) -> void:
	turn_foot = i
	turn_t = 0.0
	turn_from_yaw = feet_yaw
	turn_to_yaw = feet_yaw + angle_difference(feet_yaw, rotation.y) / float(maxi(turn_steps, 1))
	turn_from_pos = foot[i]
	turn_from_fy = foot_yaw[i]


## Шаг на месте с поворотом: таз поворачивается, опорная стопа остаётся на месте на полу,
## шагающая стопа дугой встаёт под бедро и разворачивается носком по тазу.
func _turn_step(delta: float) -> void:
	var i := turn_foot
	var j := 1 - i
	turn_t = minf(turn_t + delta / 0.26, 1.0)
	var k := smoothstep(0.0, 1.0, turn_t)
	var new_yaw := lerp_angle(turn_from_yaw, turn_to_yaw, k)
	var dyaw := angle_difference(feet_yaw, new_yaw)
	feet_yaw = new_yaw
	var hip := Vector3(legs[j].position.x, 0, legs[j].position.z)
	foot[j] = Basis(Vector3.UP, -dyaw) * (hip + foot[j]) - hip
	foot_yaw[j] -= dyaw
	foot[i] = turn_from_pos.lerp(Vector3(0, GROUND_Y, 0), k) + Vector3(0, 0.07 * sin(PI * turn_t), 0)
	foot_yaw[i] = lerpf(turn_from_fy, 0.0, k)
	foot_pitch[i] = -0.25 * sin(PI * turn_t)
	if turn_t >= 1.0:
		_play_step(-14.0, 1.0, true)
		turn_steps -= 1
		var rest_off := absf(angle_difference(feet_yaw, rotation.y))
		# опорная нога осталась развёрнутой или в стороне — подставляем и её
		var j_off := absf(foot_yaw[j]) > deg_to_rad(12.0) or Vector2(foot[j].x, foot[j].z).length() > 0.06
		if turn_steps > 0 or rest_off > deg_to_rad(10.0) or j_off:
			turn_steps = maxi(turn_steps, 1)
			_start_turn_step(j)
		else:
			turn_foot = -1
			turn_hold = 0.0


## Живая поза стоя: таймеры переноса веса и случайных движений, смещение таза.
func _update_idle(delta: float, spd: float, grounded: bool) -> void:
	var still := grounded and spd < 0.3 and settle_t[0] >= 1.0 and settle_t[1] >= 1.0
	idle_amt = move_toward(idle_amt, 1.0 if still else 0.0, delta * (1.5 if still else 4.0))
	idle_time += delta
	var box := fist_blend
	# перенос веса: стоя — раз в 3–7 с на другую ногу; в стойке — пружинит с ноги на ногу
	weight_timer -= delta
	if weight_timer <= 0.0:
		weight_timer = randf_range(3.0, 7.0)
		weight_to = (-1.0 if weight > 0.0 else 1.0) * randf_range(0.6, 1.0)
		if randf() < 0.25:
			weight_to *= 0.2
	var w_target := lerpf(weight_to, sin(idle_time * TAU * 0.9) * 0.5, box)
	weight = lerpf(weight, w_target, 1.0 - exp(-(1.6 + 4.0 * box) * delta))
	var bounce := 0.5 + 0.5 * sin(idle_time * TAU * 1.8)
	var w := weight * idle_amt
	# дыхание: период плавает 3.4–5 с, чтобы цикл не был механическим
	breath_ph = fmod(breath_ph + delta * TAU / (4.2 + 0.55 * sin(idle_time * 0.11) + 0.25 * sin(idle_time * 0.29 + 1.3)), TAU * 100.0)
	var it := idle_time
	var rk := idle_amt * (1.0 - box)   # расслабленная поза (без стойки)
	# еле заметное покачивание таза: несколько некратных частот
	var sx := (sin(it * 0.53) * 0.006 + sin(it * 1.21 + 0.7) * 0.0025 + sin(it * 0.17 + 2.1) * 0.004) * rk
	var sz := (sin(it * 0.37 + 2.0) * 0.006 + sin(it * 0.97) * 0.0025) * rk
	# таз уходит на опорную ногу и чуть опускается (вес = -1 — левая, она на -X); колени мягкие
	var tgt := Vector3(w * 0.045 + sx, -(absf(w) * 0.012 + 0.006 * (0.5 + 0.5 * sin(breath_ph))) - 0.007 * rk
			- box * idle_amt * (0.035 + 0.025 * bounce), sz)
	hip_off = hip_off.lerp(tgt, 1.0 - exp(-10.0 * delta))
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var unload := clampf(-w * side, 0.0, 1.0) * (1.0 - box)   # нога на другой стороне от веса
		idle_pitch[i] = lerpf(idle_pitch[i], -0.18 * unload, 1.0 - exp(-6.0 * delta))
	# редкие случайные движения
	if fidget != "":
		fidget_t += delta / fidget_dur
		if fidget_t >= 1.0:
			fidget = ""
	elif idle_amt > 0.9 and not punching:
		fidget_timer -= delta
		if fidget_timer <= 0.0:
			fidget_timer = randf_range(4.0, 9.0)
			var kinds := ["neck", "shoulder", "shift"] if box > 0.5 else ["neck", "shoulder", "fingers", "shift", "fingers"]
			if box > 0.5:
				kinds = ["shoulder", "shift"]
			fidget = kinds[randi() % kinds.size()]
			fidget_t = 0.0
			fidget_side = -1.0 if randf() < 0.5 else 1.0
			fidget_dur = {"neck": 1.8, "shoulder": 1.1, "fingers": 1.2, "shift": 0.6}[fidget]
			if fidget == "shift" and turn_foot < 0:
				# переминается: одна нога переступает на месте
				turn_steps = 1
				_start_turn_step(0 if fidget_side < 0.0 else 1)


func _leg_ik(i: int, t: Vector3, extra_pitch := 0.0, extra_yaw := 0.0) -> void:
	# разворот стопы — поворот всей ноги вокруг вертикали в бедре; цель считаем в повёрнутых осях
	var fy := foot_yaw[i] + extra_yaw
	t = Basis(Vector3.UP, -fy) * t
	var roll := atan2(t.x, -t.y)                     # отвод ноги в сторону
	var yy := -sqrt(t.y * t.y + t.x * t.x)
	var zz := t.z
	var d := clampf(sqrt(yy * yy + zz * zz), 0.15, LEG_L1 + LEG_L2 - 0.002)
	var aim := atan2(-zz, -yy)                       # угол на стопу (вперёд — плюс)
	var a_hip := acos(clampf((LEG_L1 * LEG_L1 + d * d - LEG_L2 * LEG_L2) / (2.0 * LEG_L1 * d), -1.0, 1.0))
	var a_knee := PI - acos(clampf((LEG_L1 * LEG_L1 + LEG_L2 * LEG_L2 - d * d) / (2.0 * LEG_L1 * LEG_L2), -1.0, 1.0))
	legs[i].rotation = Vector3(aim + a_hip, fy, roll)
	knees[i].rotation.x = -a_knee
	# ботинок параллельно полу + перекат стопы
	ankles[i].rotation.x = -(aim + a_hip - a_knee) + foot_pitch[i] + extra_pitch


## Модель чужого игрока (сеть): догоняет присланную позицию, поворот и наклон головы; походка, присед
## и стойка — той же процедурной анимацией, что и у своего тела.
func _puppet_tick(delta: float) -> void:
	var to := net_pos - global_position
	if to.length() > 3.0:
		global_position = net_pos
		to = Vector3.ZERO
	velocity = Vector3(to.x * 10.0, to.y * 10.0 - 1.0, to.z * 10.0)
	move_and_slide()
	rotation.y = lerp_angle(rotation.y, net_yaw, 1.0 - exp(-14.0 * delta))
	head.rotation.x = lerpf(head.rotation.x, net_pitch, 1.0 - exp(-14.0 * delta))
	_update_crouch(delta)
	var hv := Vector3(net_vel.x, 0, net_vel.z)
	_animate(delta, global_transform.basis.inverse() * hv, net_sprint)
