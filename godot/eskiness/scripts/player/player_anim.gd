extends "res://scripts/player/player_model.gd"
# Часть player.gd: анимация тела и ног, повороты, idle, IK, следы ударов, копия игрока в сети.
const GunS := preload("res://scripts/gun.gd")


func _update_crouch(delta: float) -> void:
	if active and Input.is_action_just_pressed("crouch_toggle"):
		crouch_toggled = not crouch_toggled
	if active and Input.is_action_just_pressed("crouch"):
		crouch_hold_block = false
	if not Input.is_action_pressed("crouch"):
		crouch_hold_block = false
	var want := force_crouch or active and (crouch_toggled or (Input.is_action_pressed("crouch") and not crouch_hold_block))
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
## Камера не залезает в стену (промпт 23:29): сфера от центра тела до глаз, при касании голова отъезжает назад.
var _cam_sphere: SphereShape3D

func _cam_wall_pullback() -> void:
	if cam == null or not cam.current:
		return
	if _cam_sphere == null:
		_cam_sphere = SphereShape3D.new()
		_cam_sphere.radius = 0.15
	var from := global_transform * Vector3(0, head.position.y, 0)
	var to := global_transform * head.position
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _cam_sphere
	q.transform = Transform3D(Basis(), from)
	q.motion = to - from
	q.exclude = [get_rid()]
	q.collision_mask = 1
	var r := get_world_3d().direct_space_state.cast_motion(q)
	if r.size() == 2 and r[0] < 1.0:
		head.position.x *= r[0]
		head.position.z *= r[0]


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
	# бег (промпт 04:05): плавный переход шаг↔бег, фаза — по разнице стоп вдоль движения
	var run_t := clampf((spd - WALK - 0.2) / (SPRINT - WALK - 0.2), 0.0, 1.0) if grounded else run_k
	run_k = move_toward(run_k, run_t, delta * (2.5 if run_t > run_k else 3.5))
	var rd_t := clampf((foot[0] - foot[1]).dot(move_dir) / 0.5, -1.0, 1.0) if grounded and spd > 0.4 else 0.0
	run_d = lerpf(run_d, rd_t, 1.0 - exp(-18.0 * delta))
	# таз ниже всего чуть после постановки стопы, выше — в фазе полёта
	run_bob = -run_k * 0.035 * (0.5 + 0.5 * cos(phase - 0.6))
	var box_ph := sin(idle_time * TAU * 1.8) * fist_blend * idle_amt
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var p: Vector4 = arm_pose[i]
		if i == 0:
			# нож в левой (промпт 04:48): в стойке рука выше и ближе к центру, чтобы нож был в кадре; в махе — по траектории
			var want_kr := 1.0 if weapon_ids[0] in ["knife", "shiv"] and not (punching and last_arm == 0) else 0.0
			knife_rev_w = move_toward(knife_rev_w, want_kr, delta * 5.0)
			p += KNIFE_REV_ADD * knife_rev_w * fist_blend
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
		# бег: согнутые ~90° руки машут вдоль корпуса в противофазе ногам. Вперёд — умеренно (кулак на пике
		# не выше груди, не в кадре; промпт 05:06), назад — сильнее; на махе вперёд локоть чуть раскрыт
		var rka := run_k * (1.0 - fist_blend)
		var rs := run_d * (1.0 if i == 1 else -1.0)   # >0 — рука впереди
		arm_swing = lerpf(arm_swing, rs * (0.4 if rs > 0.0 else 0.65), rka)
		var run_el := rka * deg_to_rad(80.0 - 8.0 * rs)
		var guard_bob := deg_to_rad(sin(phase + float(i)) * 1.5 * amt * fist_blend + box_ph * 1.3)   # промпт 03:38: вдвое слабее
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
		# 05:02: взгляд вниз почти не опускает стойку (иначе плечи висят вертикально и руки «складываются»)
		var aim_lift := look_p * ((0.2 if look_p > 0.0 else 0.05) * fist_blend + 0.7 * aim_w[i])
		# 05:06: в стойке на ходу/бегу руки живые — боб в такт шагам, мах вперёд-назад навстречу ногам, на бегу кулаки ниже
		var wk := fist_blend * clampf(amt, 0.0, 1.2)
		var gsw := clampf(-foot[1 - i].z * 1.1, -0.6, 0.6) * 0.22 * wk
		var gbob := sin(phase + float(i) * 0.6) * wk * (1.0 + run_k)
		var g_x := gsw + deg_to_rad(2.5) * gbob - deg_to_rad(10.0) * run_k * fist_blend
		var g_el := deg_to_rad(4.0) * gbob - gsw * 0.5 + deg_to_rad(8.0) * run_k * fist_blend
		shoulders[i].rotation = Vector3(
			deg_to_rad(p.x) + arm_swing + guard_bob + rest_sway + aim_lift + relax_x + g_x,
			deg_to_rad(p.y) * side + relax_y * side,
			deg_to_rad(p.z) * side + 0.08 * side * (1.0 - fist_blend) + relax_z * side + 0.05 * side * rka)
		elbows[i].rotation.x = deg_to_rad(p.w) + relax_el + run_el + g_el
		if not USE_MODEL:
			shoulders[i].position.z = 0.13 - reach[i]
	_gun_pose(delta)
	bob = lerpf(bob, amt, 1.0 - exp(-8.0 * delta))
	land_dip = move_toward(land_dip, 0.0, delta * 0.35)
	# голова ниже всего в момент постановки стопы (дважды за цикл)
	head.position.y = CAM_Y - (0.5 + 0.5 * cos(phase)) * 0.035 * bob * (1.0 - 0.5 * crouch) - land_dip + hip_off.y * 0.6 \
			- CROUCH_CAM * _crouch_k()
	head.position.x = sin(gait * TAU) * 0.012 * bob
	# в стойке голова чуть назад — к плечам, чтобы кулаки были перед лицом, а не в камере
	head.position.z = lerpf(-0.22, 0.0, fist_blend) - 0.06 * _crouch_k()
	# камера всегда на уровне глаз тела и перед шеей (присед, наклон, удары): по кости головы
	if skel != null and head_bone != -1:
		var hb := to_local(skel.global_transform * skel.get_bone_global_pose(head_bone).origin)
		var hd := Basis(Vector3.UP, angle_difference(rotation.y, torso_yaw))
		var eye := hb + hd * Vector3(0, 0.08, -0.1)
		head.position.y = maxf(head.position.y, eye.y)
		head.position.z = minf(head.position.z, eye.z)
	head.position.y += cam_step   # ступеньки: тело уже наверху/внизу, камера догоняет
	_cam_wall_pullback()
	var want_fov: float = fov_base * (gun.fov_mult() if gun else 1.0) + (7.0 if sprinting else 0.0)   # прицел — gun.gd
	cam.fov = lerpf(cam.fov, want_fov, 1.0 - exp(-5.0 * delta))
	_swap_pose(delta)
	_apply_bones()
	if puppet:
		_puppet_gun_aim()


## Позы с пистолетом (промпт 16.11 02:02/02:04): ПКМ держать — рука с пистолетом поднята и смотрит туда, куда летит пуля
## (с двумя — обе); прицел (клик ПКМ) — один пистолет двумя руками у глаза (мушка по центру), два — обе руки вытянуты вперёд.
## Двухзвенный IK на узлах-драйверах плеча и локтя поверх обычной позы, с плавным весом. У чужих игроков — gun_mode из сети.
func _gun_pose(delta: float) -> void:
	var has := [weapon_ids[0] == "pistol", weapon_ids[1] == "pistol"]
	var any: bool = has[0] or has[1]
	gun_hip_w = move_toward(gun_hip_w, 1.0 if any and gun_mode == 1 else 0.0, delta * 6.0)
	gun_ads_w = move_toward(gun_ads_w, 1.0 if any and gun_mode == 2 else 0.0, delta * 6.0)
	var sh_i := 1 if weapon_ids[1] == "stone" else (0 if weapon_ids[0] == "stone" else -1)
	throw_w = move_toward(throw_w, 1.0 if throw_aim and sh_i >= 0 else 0.0, delta * 7.0)
	throw_flick = move_toward(throw_flick, 0.0, delta * 5.0)
	if hands.size() < 2 or skel == null:
		return
	var ct := global_transform.affine_inverse() * cam.global_transform
	var cb := ct.basis.orthonormalized()
	var eye := ct.origin
	var tinv := Basis(Vector3.UP, angle_difference(rotation.y, torso_yaw)).inverse()
	if sh_i >= 0 and (throw_w > 0.0 or throw_flick > 0.0):
		# камень (промпт 16.11 02:13): замах — рука отведена вверх-назад за плечо; бросок — выброс вперёд
		var ss := _shoulder_pos(sh_i)
		var sd := -1.0 if sh_i == 0 else 1.0
		var cock := ss + cb.y * 0.2 + cb.z * 0.12 + cb.x * sd * 0.1
		var out := ss - cb.z * 0.5 + cb.y * 0.05
		var fk := smoothstep(0.0, 1.0, throw_flick)
		_arm_ik(sh_i, cock.lerp(out, fk), ss, tinv, clampf(maxf(throw_w, fk), 0.0, 1.0))
	gun_rel_w = move_toward(gun_rel_w, 1.0 if gun_rel_k >= 0.0 and any else 0.0, delta * 6.0)
	if gun_hip_w <= 0.0 and gun_ads_w <= 0.0 and gun_rel_w <= 0.0:
		return
	var aim_pt := eye - cb.z * 20.0
	var two: bool = has[0] and has[1]
	var tsum := maxf(gun_hip_w + gun_ads_w, 0.0001)
	var k_ads := gun_ads_w / tsum
	var w_all := clampf(gun_hip_w + gun_ads_w, 0.0, 1.0)
	var torso_inv := Basis(Vector3.UP, angle_difference(rotation.y, torso_yaw)).inverse()
	var main := 1 if has[1] else 0
	# прицел: руки догоняют камеру с инерцией (gun.gd: lag_b — в мировых осях, переводим в оси игрока)
	var acb := cb
	if gun != null and not puppet:
		var gb := global_basis.orthonormalized()
		acb = (gb.inverse() * gun.lag_b * gb) * cb
	for i in [main, 1 - main]:
		var sh := _shoulder_pos(i)
		var reach_len := elbows[i].position.length() + hands[i].position.length()
		if has[i]:
			var hip_t := sh + (aim_pt - sh).normalized() * reach_len * 0.92
			# от бедра (промпт 02:36): кисть дальше вперёд на 25% и выше на столько же — пистолет виднее в кадре
			var fwd_d := maxf(-(hip_t - eye).dot(cb.z), 0.0)
			hip_t += (-cb.z + cb.y) * fwd_d * 0.25
			# прицел: пистолет висит на кисти (рукоять в кулаке), поэтому кисть ставим так, чтобы пистолет пришёл в точку прицела
			var ads_t := GunS.ads_point(eye, acb, i, two) - _gun_off(i)
			var t := hip_t.lerp(ads_t, k_ads)
			if w_all > 0.0:
				_arm_ik(i, t, sh, torso_inv, w_all)
		elif i != main and weapon_ids[i] == "" and gun_ads_w > 0.0:
			# прицел с одним пистолетом: вторая рука обхватывает рукоять снизу-сбоку поверх стреляющей
			var side := -1.0 if i == 0 else 1.0
			var gn = weapon_nodes[main]
			if gn != null and is_instance_valid(gn) and (gn as Node3D).is_inside_tree():
				var gp := to_local((gn as Node3D).global_transform * Vector3(-0.005, 0.015, side * 0.035)) - cb.y * 0.015
				_arm_ik(i, gp - _fist_off(i), sh, torso_inv, gun_ads_w)
	if gun_rel_w > 0.0:
		_reload_pose(eye, cb, torso_inv)


## Перезарядка (промпт 16.11 02:37): пистолет перед грудью, вторая рука берёт магазин с пояса, вставляет в рукоять
## снизу и досылает затвор (тянет назад и отпускает). Фазы — gun_rel_k (gun.gd), точки — в осях пистолета.
func _reload_pose(eye: Vector3, cb: Basis, torso_inv: Basis) -> void:
	var h := gun_rel_h
	var j := 1 - h
	var w := smoothstep(0.0, 1.0, gun_rel_w)
	var side := -1.0 if h == 0 else 1.0
	var gun_pos := eye - cb.z * 0.36 - cb.y * 0.24 - cb.x * side * 0.03
	_arm_ik(h, gun_pos - _gun_off(h), _shoulder_pos(h), torso_inv, w)
	if weapon_ids[j] != "":
		return
	var gn = weapon_nodes[h]
	if gn == null or not is_instance_valid(gn) or not (gn as Node3D).is_inside_tree():
		return
	var g: Transform3D = (gn as Node3D).global_transform
	var gl := func(p: Vector3) -> Vector3: return to_local(g * p)
	var sj := _shoulder_pos(j)
	var belt := sj - cb.y * 0.5 + cb.x * side * 0.02 - cb.z * 0.08
	var under: Vector3 = gl.call(Vector3(-0.02, -0.07, 0))       # магазин под рукоятью
	var inside: Vector3 = gl.call(Vector3(-0.02, -0.015, 0))     # вставлен, ладонь подбивает снизу
	var slide: Vector3 = gl.call(Vector3(-0.015, 0.14, 0))       # пальцы на задней части затвора
	var back: Vector3 = gl.call(Vector3(-0.065, 0.14, 0))
	var k := clampf(gun_rel_k, 0.0, 1.0)
	var keys := [[0.0, belt], [0.28, belt], [0.5, under], [0.6, inside], [0.66, inside], [0.76, slide],
			[0.84, back], [0.9, back], [1.0, belt]]
	var p: Vector3 = belt
	for n in keys.size() - 1:
		var a: Array = keys[n]
		var b: Array = keys[n + 1]
		if k <= float(b[0]):
			var f := smoothstep(0.0, 1.0, (k - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001))
			p = (a[1] as Vector3).lerp(b[1], f)
			break
	# к поясу рука идёт плавно из текущей позы, назад — уходит с весом
	var wj := w * (1.0 - smoothstep(0.9, 1.0, k))
	_arm_ik(j, p - _fist_off(j), sj, torso_inv, wj)


## Смещение точки кулака (fist_fx, 8 см по кисти) от кости кисти руки i, оси игрока.
func _fist_off(i: int) -> Vector3:
	var b := skel.find_bone(["hand_L", "hand_R"][i])
	if b == -1:
		return Vector3.ZERO
	return to_local(fist_fx[i].global_position) - to_local(skel.global_transform * skel.get_bone_global_pose(b).origin)


## Смещение пистолета в руке i (его начала — рукояти) от кости кисти, оси игрока.
func _gun_off(i: int) -> Vector3:
	var n = weapon_nodes[i]
	var b := skel.find_bone(["hand_L", "hand_R"][i])
	if n == null or not is_instance_valid(n) or not (n as Node3D).is_inside_tree() or b == -1:
		return Vector3.ZERO
	return to_local((n as Node3D).global_position) - to_local(skel.global_transform * skel.get_bone_global_pose(b).origin)


## Плечо руки i в осях игрока (по кости модели, с наклоном корпуса и приседом).
func _shoulder_pos(i: int) -> Vector3:
	var b := skel.find_bone(["upperarm_L", "upperarm_R"][i])
	if b == -1:
		return shoulders[i].position
	return to_local(skel.global_transform * skel.get_bone_global_pose(b).origin)


## Двухзвенный IK руки i: кисть в точку t (оси игрока), локоть вниз и наружу; смешивается с текущей позой на w.
## Драйвер плеча висит вдоль -Y, локоть сгибается вокруг X вперёд (-Z); кости повторяют драйвер, повёрнутый на корпус.
func _arm_ik(i: int, t: Vector3, sh: Vector3, torso_inv: Basis, w: float) -> void:
	var side := -1.0 if i == 0 else 1.0
	var lu: float = elbows[i].position.length()
	var lf: float = hands[i].position.length()
	var v := torso_inv * (t - sh)
	if v.length() < 0.01:
		return
	var d := clampf(v.length(), absf(lu - lf) + 0.02, (lu + lf) * 0.995)
	var ca := clampf((lu * lu + lf * lf - d * d) / (2.0 * lu * lf), -1.0, 1.0)
	var bend := PI - acos(ca)
	var h_l := Vector3(0, -lu - lf * cos(bend), -lf * sin(bend)).normalized()
	var n_l := Vector3.RIGHT
	var h_w := v.normalized()
	var e := Vector3(0.45 * side, -1.0, 0.2)
	e = e - h_w * e.dot(h_w)
	if e.length() < 0.01:
		e = Vector3(side, 0, 0) - h_w * h_w.x * side
	e = e.normalized()
	var n_w := e.cross(h_w).normalized()
	var lb := Basis(h_l, n_l, h_l.cross(n_l))
	var wb := Basis(h_w, n_w, h_w.cross(n_w))
	var q := Quaternion((wb * lb.transposed()).orthonormalized())
	shoulders[i].quaternion = shoulders[i].quaternion.slerp(q, w)
	elbows[i].rotation.x = lerpf(elbows[i].rotation.x, bend, w)


## Чужой игрок: пистолет в поднятой руке доворачивается стволом по взгляду (своему это делает gun.gd).
func _puppet_gun_aim() -> void:
	var w := clampf(gun_hip_w + gun_ads_w, 0.0, 1.0)
	if w <= 0.0:
		return
	var cb := cam.global_transform.basis.orthonormalized()
	var b := Basis(-cb.z, cb.y, cb.x)
	for i in 2:
		var n = weapon_nodes[i]
		if weapon_ids[i] != "pistol" or n == null or not is_instance_valid(n) or not (n as Node3D).is_inside_tree():
			continue
		var gt: Transform3D = (n as Node3D).global_transform
		var sc := gt.basis.get_scale()
		var r := gt.basis.orthonormalized().slerp(b, w)
		gt.basis = Basis(r.x * sc.x, r.y * sc.y, r.z * sc.z)
		(n as Node3D).global_transform = gt


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
		var lift := 0.04 + 0.025 * spd + step_lift
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
		# боевая стойка (05:02): стопы на ширине плеч, левая впереди, правая сзади и носком наружу — ноги не сведены
		var bk := fist_blend * (1.0 - ck) * (0.4 + 0.6 * idle_amt)
		t += Vector3(side * 0.075, 0.0, -0.12 if i == 0 else 0.09) * bk
		# разгруженная нога: пятка чуть приподнята, колено подсогнуто
		t.y += 0.16 * maxf(-sin(idle_pitch[i]), 0.0)
		_leg_ik(i, t, idle_pitch[i], -side * deg_to_rad(9.0 + 3.0 * unl) * rk - side * deg_to_rad(6.0 if i == 0 else 18.0) * bk)


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
			- box * idle_amt * (0.022 + 0.014 * bounce), sz)   # 05:02: в стойке колени лишь чуть согнуты
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


# ---------- смена рук колесом (промпт 04:53) ----------
const SWAP_DUR := 0.36
var swap_t := 0.0          # >0 — идёт смена: сколько осталось
var _swap_cb := Callable()  # что сделать в нижней точке (game.gd меняет оружие местами)

## Начать: обе руки уходят вниз из кадра, в нижней точке вызывается cb, руки поднимаются. false — уже идёт.
func start_swap(cb: Callable) -> bool:
	if swap_t > 0.0:
		return false
	swap_t = SWAP_DUR
	_swap_cb = cb
	return true


func _swap_pose(delta: float) -> void:
	if swap_t <= 0.0:
		return
	swap_t = maxf(swap_t - delta, 0.0)
	var k := 1.0 - swap_t / SWAP_DUR
	if k >= 0.5 and _swap_cb.is_valid():
		var cb := _swap_cb
		_swap_cb = Callable()
		cb.call()
	if hands.size() < 2 or skel == null:
		return
	var w := smoothstep(0.0, 1.0, 1.0 - absf(k * 2.0 - 1.0) * 1.15)   # в середине — руки полностью внизу
	if w <= 0.0:
		return
	var cb := (global_transform.affine_inverse() * cam.global_transform).basis.orthonormalized()
	var tinv := Basis(Vector3.UP, angle_difference(rotation.y, torso_yaw)).inverse()
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var sh := _shoulder_pos(i)
		# вниз по взгляду и чуть назад — из кадра при любом наклоне головы
		var t := sh - cb.y * 0.62 + cb.z * 0.18 + cb.x * side * 0.06
		_arm_ik(i, t, sh, tinv, w)
