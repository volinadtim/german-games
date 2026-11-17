extends "res://scripts/player/player_base.gd"
# Часть player.gd: модель тела, кулаки, кости, хват оружия.


func _build_body() -> void:
	var jacket := _mat(Color(0.24, 0.27, 0.21))
	var pants := _mat(Color(0.14, 0.14, 0.16))
	var skin := _mat(Color(0.78, 0.6, 0.48))
	var boots := _mat(Color(0.13, 0.1, 0.075))
	var sole := _mat(Color(0.05, 0.045, 0.04))
	var cuffs := _mat(Color(0.18, 0.2, 0.16))

	var body := Node3D.new()
	add_child(body)

	var torso := CapsuleMesh.new()
	torso.radius = 0.19
	torso.height = 0.74
	_part(body, torso, Vector3(0, 1.13, 0.14), jacket)

	# голова и шея только для тени — камера внутри них не нужна
	var hm := SphereMesh.new()
	hm.radius = 0.12
	hm.height = 0.25
	var h := _part(body, hm, Vector3(0, 1.68, 0.08), skin)
	h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	head_parts.append(h)
	var neck := CylinderMesh.new()
	neck.top_radius = 0.06
	neck.bottom_radius = 0.075
	neck.height = 0.24
	var n := _part(body, neck, Vector3(0, 1.53, 0.1), skin)
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	head_parts.append(n)
	# плечевой пояс — закрывает щели между торсом и руками
	var yoke := CapsuleMesh.new()
	yoke.radius = 0.075
	yoke.height = 0.5
	var y := _part(body, yoke, Vector3(0, 1.42, 0.13), jacket)
	y.rotation.z = PI / 2

	for side in [-1.0, 1.0]:
		# нога: бедро -> колено -> голень -> голеностоп -> ботинок (позу считает IK, см. _leg_ik)
		var hip := Node3D.new()
		hip.position = Vector3(0.1 * side, HIP_Y, 0.08)
		body.add_child(hip)
		var thigh := CapsuleMesh.new()
		thigh.radius = 0.085
		thigh.height = 0.44
		_part(hip, thigh, Vector3(0, -LEG_L1 / 2, 0), pants)
		var knee := Node3D.new()
		knee.position = Vector3(0, -LEG_L1, 0)
		hip.add_child(knee)
		var shin := CapsuleMesh.new()
		shin.radius = 0.072
		shin.height = 0.44
		_part(knee, shin, Vector3(0, -LEG_L2 / 2, 0), pants)
		var ankle := Node3D.new()
		ankle.position = Vector3(0, -LEG_L2, 0)
		knee.add_child(ankle)
		_build_shoe(ankle, boots, sole)
		legs.append(hip)
		knees.append(knee)
		ankles.append(ankle)

		# рука: плечо -> плечевая кость -> локоть -> предплечье -> кулак
		var sh := Node3D.new()
		sh.position = Vector3(0.215 * side, 1.43, 0.13)
		body.add_child(sh)
		var upper := CapsuleMesh.new()
		upper.radius = 0.052
		upper.height = 0.34
		_part(sh, upper, Vector3(0, -0.15, 0), jacket)
		var el := Node3D.new()
		el.position = Vector3(0, -0.3, 0)
		sh.add_child(el)
		var fore := CapsuleMesh.new()
		fore.radius = 0.044
		fore.height = 0.3
		_part(el, fore, Vector3(0, -0.13, 0), jacket)
		# манжета рукава
		var cuff := CylinderMesh.new()
		cuff.top_radius = 0.048
		cuff.bottom_radius = 0.05
		cuff.height = 0.035
		_part(el, cuff, Vector3(0, -0.265, 0), cuffs)
		_build_fist(el, skin, side)
		shoulders.append(sh)
		elbows.append(el)


## Ботинок: подошва с каблуком, вытянутый верх, скруглённый носок, голенище.
func _build_shoe(ankle: Node3D, leather: Material, sole_mat: Material) -> void:
	var sole := BoxMesh.new()
	sole.size = Vector3(0.1, 0.025, 0.27)
	_part(ankle, sole, Vector3(0, -0.077, -0.05), sole_mat)
	var heel := BoxMesh.new()
	heel.size = Vector3(0.09, 0.02, 0.07)
	_part(ankle, heel, Vector3(0, -0.06, 0.05), sole_mat)
	var upper := CapsuleMesh.new()
	upper.radius = 0.047
	upper.height = 0.25
	var u := _part(ankle, upper, Vector3(0, -0.042, -0.055), leather)
	u.rotation.x = PI / 2
	u.scale = Vector3(1.05, 1.0, 0.8)
	var toe := SphereMesh.new()
	toe.radius = 0.05
	toe.height = 0.07
	_part(ankle, toe, Vector3(0, -0.05, -0.15), leather)
	var collar := CylinderMesh.new()
	collar.top_radius = 0.06
	collar.bottom_radius = 0.052
	collar.height = 0.09
	_part(ankle, collar, Vector3(0, 0.0, 0.0), leather)


## Кулак из нескольких частей: ладонь, ряд костяшек, подогнутые пальцы снизу, большой палец сверху.
## В локальных осях предплечья: -Y — вперёд по руке, -Z — тыльная сторона (в стойке смотрит вверх).
func _build_fist(el: Node3D, skin: Material, side: float) -> void:
	var hand := Node3D.new()
	hand.position = Vector3(0, -0.3, 0)
	el.add_child(hand)
	var palm := BoxMesh.new()
	palm.size = Vector3(0.072, 0.07, 0.05)
	var p := _part(hand, palm, Vector3(0, -0.04, 0), skin)
	p.rotation.x = 0.08
	# костяшки: четыре согнутых пальца, видны как бугорки спереди
	for k in 4:
		var x := (k - 1.5) * 0.019
		var knuckle := CapsuleMesh.new()
		knuckle.radius = 0.0115
		knuckle.height = 0.05
		var kn := _part(hand, knuckle, Vector3(x, -0.078 + absf(k - 1.5) * 0.004, -0.004), skin)
		kn.rotation.x = PI / 2
		# средние фаланги, подогнутые к ладони снизу
		var tip := CapsuleMesh.new()
		tip.radius = 0.0105
		tip.height = 0.04
		var t := _part(hand, tip, Vector3(x, -0.06, 0.026), skin)
		t.rotation.x = 0.3
	# большой палец поперёк поверх согнутых пальцев
	var thumb := CapsuleMesh.new()
	thumb.radius = 0.012
	thumb.height = 0.06
	var th := _part(hand, thumb, Vector3(-0.012 * side, -0.06, -0.03), skin)
	th.rotation.z = PI / 2 - 0.35 * side
	# запястье
	var wrist := CylinderMesh.new()
	wrist.top_radius = 0.03
	wrist.bottom_radius = 0.034
	wrist.height = 0.04
	_part(hand, wrist, Vector3(0, -0.005, 0), skin)
	var fx := CPUParticles3D.new()
	fx.emitting = false
	fx.amount = 24
	fx.lifetime = 0.22
	fx.local_coords = false
	fx.position = Vector3(0, -0.06, 0)
	fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	fx.emission_sphere_radius = 0.05
	fx.direction = Vector3(0, 1, 0)
	fx.spread = 20.0
	fx.initial_velocity_min = 0.5
	fx.initial_velocity_max = 1.3
	fx.gravity = Vector3.ZERO
	fx.particle_flag_align_y = true
	fx.scale_amount_min = 0.6
	fx.scale_amount_max = 1.3
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.35))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	fx.color_ramp = ramp
	var q := QuadMesh.new()
	q.size = Vector2(0.006, 0.1)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.9, 0.88, 0.8, 0.5)
	q.material = m
	fx.mesh = q
	hand.add_child(fx)
	fist_fx.append(fx)


## Тело — модель BaseHuman. Невидимый риг из узлов (legs/knees/ankles/shoulders/elbows/hands)
## считает позы как раньше, а кости модели каждый кадр поворачиваются так же (_apply_bones).
func _build_model() -> void:
	# от старого тела оставляем только узлы-драйверы, меши убираем
	for mi in find_children("*", "MeshInstance3D", true, false):
		mi.free()
	var model: Node3D = MODEL.instantiate()
	for n in model.find_children("*", "", true, false):
		if n is Light3D or n is Camera3D:
			n.free()
	model.rotation.y = PI                 # в файле модель смотрит на +Z, игрок — на -Z
	model.position.z = MODEL_Z
	add_child(model)
	model_root = model
	skel = model.find_children("*", "Skeleton3D", true, false)[0]
	var rel := global_transform.affine_inverse() * skel.global_transform
	rig_rel = rel.basis.orthonormalized()
	skel_m = rel.basis.get_scale().x
	var rest := func(bone: String) -> Transform3D:
		var t := rel * skel.get_bone_global_rest(skel.find_bone(bone))
		return Transform3D(t.basis.orthonormalized(), t.origin)
	var bp := func(bone: String) -> Vector3: return rest.call(bone).origin

	# размеры ног берём из модели, чтобы IK ставил стопы точно на пол
	HIP_Y = bp.call("thigh_L").y
	LEG_L1 = bp.call("thigh_L").distance_to(bp.call("calf_L"))
	LEG_L2 = bp.call("calf_L").distance_to(bp.call("foot_L"))
	GROUND_Y = bp.call("foot_L").y - HIP_Y
	# в позе покоя модели ноги чуть согнуты/расставлены — по вертикали бедро→стопа короче ноги, и IK сгибал колени
	# всегда. Поднимаем модель так, чтобы стоя нога была почти прямой (98.5% длины), стопа — на том же полу.
	LEG_LIFT = clampf((LEG_L1 + LEG_L2) * 0.997 + GROUND_Y, 0.0, 0.16)   # 18.11: ноги прямее
	GROUND_Y -= LEG_LIFT
	for i in 2:
		foot[i] = Vector3(0, GROUND_Y, 0)

	# в модели левые кости (_L) после разворота оказываются на -X — это рука/нога i = 0
	var suf := ["_L", "_R"]
	for i in 2:
		var s: String = suf[i]
		legs[i].position = bp.call("thigh" + s)
		knees[i].position = Vector3(0, -LEG_L1, 0)
		ankles[i].position = Vector3(0, -LEG_L2, 0)
		shoulders[i].position = bp.call("upperarm" + s)
		var lu: float = bp.call("upperarm" + s).distance_to(bp.call("lowerarm" + s))
		var lf: float = bp.call("lowerarm" + s).distance_to(bp.call("hand" + s))
		elbows[i].position = Vector3(0, -lu, 0)
		var hand := Node3D.new()
		hand.position = Vector3(0, -lf, 0)
		elbows[i].add_child(hand)
		hands.append(hand)
		# драйвер в покое — конечность висит вниз; кость в покое (A-поза) выпрямляем так же
		for e in [["thigh", legs[i], true], ["calf", knees[i], true], ["foot", ankles[i], false],
				["upperarm", shoulders[i], true], ["lowerarm", elbows[i], true], ["hand", hand, true]]:
			var t: Transform3D = rest.call(e[0] + s)
			var ref := t.basis
			if e[2]:
				ref = Basis(Quaternion(t.basis.y.normalized(), Vector3.DOWN)) * ref
			var arm := i if e[0] in ["lowerarm", "hand"] else -1
			bone_map.append([skel.find_bone(e[0] + s), e[1], ref, arm, e[0] == "hand", e[0] in ["thigh", "calf", "foot"]])
		clav_bones[i] = skel.find_bone("clavicle" + s)
		# пальцы: ось сгиба — поперёк пальца, к ладони (ладонь в A-позе смотрит вниз, -Z скелета)
		var nf := finger_bones.size()
		_build_fist_pose(s)
		for _k in finger_bones.size() - nf:
			finger_arm.append(i)
		# точка кулака для следа и попаданий — на кости кисти
		var att := BoneAttachment3D.new()
		att.bone_name = "hand" + s
		skel.add_child(att)
		var fx := fist_fx[i]
		fx.get_parent().remove_child(fx)
		att.add_child(fx)
		# масштаб скелета берём из модели (у новой модели он другой, чем у BaseHuman ×100): fist_fx — в метрах, 8 см по кисти
		fx.transform = Transform3D(Basis.from_scale(Vector3.ONE / skel_m), Vector3(0, 0.08 / skel_m, 0))
	spine_bone = skel.find_bone("spine03")
	for n in ["spine01", "spine02", "spine03"]:
		spine_bones.append(skel.find_bone(n))
	neck_bone = skel.find_bone("neck")
	pelvis_bone = skel.find_bone("pelvis")
	head_bone = skel.find_bone("head")

	# голова и шея: видимый меш со «схлопнутыми» головой и шеей (камера внутри головы),
	# а копия с исходным скином рисует только тень — тень от головы остаётся
	var body_mi: MeshInstance3D = skel.find_children("*", "MeshInstance3D", false, false)[0]
	var shadow := body_mi.duplicate() as MeshInstance3D
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	skel.add_child(shadow)
	shadow.skin = body_mi.skin
	var skin: Skin = body_mi.skin.duplicate()
	for k in skin.get_bind_count():
		var b := skin.get_bind_bone(k)
		if b == -1:
			b = skel.find_bone(skin.get_bind_name(k))
		if b != -1 and skel.get_bone_name(b) in ["head", "neck", "head_end"]:
			var bind := skin.get_bind_pose(k)
			# вершины головы и шеи уходят внутрь груди (к позвонку spine03), а не в точку у шеи —
			# так изнанка шеи не попадает в камеру ни в какой позе
			var inner := skel.get_bone_global_rest(skel.find_bone("spine03")).origin
			skin.set_bind_pose(k, Transform3D(bind.basis.scaled(Vector3.ONE * 0.001), bind * inner))
	_outfit_setup(body_mi, rest)
	body_mi.skin = skin
	body_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if puppet:
		# чужой игрок: голова видна целиком, тень — от самого меша
		body_mi.skin = shadow.skin
		body_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		shadow.queue_free()
	else:
		head_mi = body_mi
		head_shadow = shadow
		head_skin_full = shadow.skin
		head_skin_cut = skin


## Показать голову (камера снаружи — кат-сцены, промпт 16.11 03:48) или снова спрятать для вида из глаз.
func set_head_visible(on: bool) -> void:
	if head_mi and is_instance_valid(head_mi):
		head_mi.skin = head_skin_full if on else head_skin_cut
		head_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if is_instance_valid(head_shadow):
			head_shadow.visible = not on
		for sl in outfit_nodes:
			var o = outfit_nodes[sl]
			if o is MeshInstance3D and is_instance_valid(o):
				(o as MeshInstance3D).skin = head_mi.skin   # шапка — вместе с головой
	for p in head_parts:
		if is_instance_valid(p):
			(p as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY


## Кулак для кисти s ("_L"/"_R"). Нормаль ладони — из геометрии кисти (поперёк костяшек × вдоль кисти),
## каждая фаланга сгибается вокруг оси «палец × нормаль». Большой палец нацеливается на уже сжатые
## средние фаланги указательного и среднего и ложится поперёк них снаружи.
func _build_fist_pose(s: String) -> void:
	var gr := func(bn: String) -> Transform3D: return skel.get_bone_global_rest(skel.find_bone(bn + s))
	var h: Vector3 = gr.call("hand").origin
	var across: Vector3 = (gr.call("index01").origin - gr.call("pinky01").origin).normalized()
	var along: Vector3 = (gr.call("middle01").origin - h).normalized()
	# Для левой руки (_L) across × along смотрит в тыл (нужен минус), для правой (_R) — прямо в ладонь
	var n := across.cross(along).normalized()
	if s == "_L":
		n = -n
	const FIST := [0.0, 88.0, 100.0, 72.0]
	const RELAX := [0.0, 12.0, 18.0, 12.0]
	var fist_of := {}
	for f in ["index", "middle", "ring", "pinky"]:
		for k in [1, 2, 3]:
			var b := skel.find_bone("%s%02d%s" % [f, k, s])
			if b == -1:
				continue
			var g := skel.get_bone_global_rest(b).basis.orthonormalized()
			var axis := (g.inverse() * g.y.normalized().cross(n)).normalized()
			var rest_q := skel.get_bone_rest(b).basis.get_rotation_quaternion()
			var fist_q := rest_q * Quaternion(axis, deg_to_rad(FIST[k] + (4.0 if f == "pinky" else 0.0)))
			finger_bones.append([b, rest_q * Quaternion(axis, deg_to_rad(RELAX[k])), fist_q])
			finger_thumb.append(false)
			finger_index.append(f == "index")
			fist_of[b] = fist_q
	# где окажутся средние фаланги в кулаке: цепочка от покоя кисти с поворотами кулака
	var gp := func(n2: String) -> Vector3:
		var chain: Array[int] = []
		var cb := skel.find_bone(n2 + s)
		var hb := skel.find_bone("hand" + s)
		while cb != -1 and cb != hb:
			chain.push_front(cb)
			cb = skel.get_bone_parent(cb)
		var t := skel.get_bone_global_rest(hb)
		for c in chain:
			var r := skel.get_bone_rest(c)
			var q: Quaternion = fist_of.get(c, r.basis.get_rotation_quaternion())
			t = t * Transform3D(Basis(q).scaled(r.basis.get_scale()), r.origin)
		return t.origin
	var mid: Vector3 = (gp.call("index02") + gp.call("middle02")) * 0.5
	var center: Vector3 = (h + gr.call("middle01").origin) * 0.5
	var unit: float = h.distance_to(gr.call("middle01").origin) / 0.09    # ~9 см от запястья до костяшек
	# большой палец лежит поверх средних фаланг снаружи кулака (раньше цель была почти в фалангах — палец прорезал их)
	var tgt: Vector3 = mid + (mid - center).normalized() * 0.045 * unit
	# большой палец
	var t1 := skel.find_bone("thumb01" + s)
	if t1 == -1:
		return
	var g1 := skel.get_bone_global_rest(t1).basis.orthonormalized()
	var rest1 := skel.get_bone_rest(t1).basis.get_rotation_quaternion()
	var aim := Basis(Quaternion(g1.y.normalized(), (tgt - skel.get_bone_global_rest(t1).origin).normalized()))
	var fist1 := rest1 * (g1.inverse() * aim * g1).get_rotation_quaternion()
	finger_bones.append([t1, rest1.slerp(fist1, 0.15), fist1])
	finger_thumb.append(true)
	finger_index.append(false)
	for k in [2, 3]:
		var b := skel.find_bone("thumb%02d%s" % [k, s])
		if b == -1:
			continue
		var g := skel.get_bone_global_rest(b).basis.orthonormalized()
		# подушечка большого пальца смотрит вбок — гнём его поперёк кулака, к мизинцу
		var axis := (g.inverse() * g.y.normalized().cross(-across)).normalized()
		var rest_q := skel.get_bone_rest(b).basis.get_rotation_quaternion()
		finger_bones.append([b, rest_q * Quaternion(axis, deg_to_rad(8.0)), rest_q * Quaternion(axis, deg_to_rad(THUMB_CURL[k]))])
		finger_thumb.append(true)
		finger_index.append(false)


## Кости модели повторяют повороты узлов-драйверов + выпад плеча, поворот корпуса, кулак.
func _apply_bones() -> void:
	if skel == null:
		return
	var inv := global_basis.orthonormalized().inverse()
	# ноги и таз развёрнуты на leg_off от взгляда, грудь — на torso_off, шея смотрит туда же, куда камера
	var leg_off := angle_difference(rotation.y, feet_yaw)
	var torso_off := angle_difference(rotation.y, torso_yaw)
	var leg_rot := Basis(Vector3.UP, leg_off)
	model_root.rotation.y = PI + leg_off
	model_root.position = leg_rot * (Vector3(0, LEG_LIFT, MODEL_Z) + _hip())
	var rr := (leg_rot * rig_rel).inverse()
	var rest_p := func(b: int) -> Basis: return rig_rel * skel.get_bone_global_rest(b).basis.orthonormalized()
	# idle: дыхание, наклон таза на опорную ногу, покачивание корпуса, редкие движения
	var it := idle_time
	var breath := (0.5 + 0.5 * sin(breath_ph)) * idle_amt
	var box := fist_blend * idle_amt
	var rk := idle_amt * (1.0 - fist_blend)   # расслабленная поза стоя (не в стойке)
	var bounce := (0.5 + 0.5 * sin(it * TAU * 1.8)) * box
	var fk := sin(PI * fidget_t) if fidget != "" else 0.0
	var sway_r := (sin(it * 0.63) * 0.012 + sin(it * 1.37) * 0.006 + sin(it * 0.23 + 0.8) * 0.008) * idle_amt
	var sway_p := (sin(it * 0.41 + 1.0) * 0.012 + sin(it * 0.89 + 2.4) * 0.005) * idle_amt
	# контрапост: таз наклонён и чуть повёрнут к опорной ноге, плечи — в обратную сторону
	var w_r := weight * rk
	var idle_tw := (-0.06 * w_r + (sin(it * 0.19 + 0.5) * 0.03 + sin(it * 0.47) * 0.012) * rk)
	if pelvis_bone != -1:
		_set_global_rot(pelvis_bone, rr * leg_rot * Basis(Vector3.UP, -idle_tw * 0.6 - run_d * run_k * 0.13)
				* Basis(Vector3.BACK, sin(gait * TAU) * 0.04 * run_k)
				* Basis(Vector3.BACK, weight * (0.045 + 0.03 * (1.0 - fist_blend)) * idle_amt) * rest_p.call(pelvis_bone))
	var ck := _crouch_k()
	# бег (промпт 04:05): корпус наклонён вперёд, таз и плечи поворачиваются навстречу друг другу
	# за ногами, лёгкое покачивание из стороны в сторону; голова (шея задаётся в мировых осях) остаётся ровной
	var rn := run_k
	var rtw := run_d * run_k
	var rsway := sin(gait * TAU) * 0.035 * rn
	# в ударе корпус наклоняется туда, куда смотрит камера (вниз — вперёд, вверх — назад)
	var aim_bend := clampf(head.rotation.x, -1.2, 0.8) * maxf(aim_w[0], aim_w[1])
	# расслабленно: грудь чуть ссутулена, а не «грудь колесом»
	var spine_x := [sway_p * 0.5 - box * 0.05 - ck * 0.22 + aim_bend * 0.18 + 0.02 * rk,
			sway_p + breath * 0.012 - box * 0.08 - ck * 0.1 + aim_bend * 0.14 + 0.03 * rk,
			breath * 0.035 - box * 0.06 - bounce * 0.03 - ck * 0.04 + aim_bend * 0.1 + 0.035 * rk]
	var spine_z := [-weight * (0.03 + 0.03 * (1.0 - fist_blend)) * idle_amt + sway_r, sway_r - w_r * 0.025, sway_r * 0.5 - w_r * 0.015]
	for k in 3:
		spine_x[k] -= rn * [0.13, 0.1, 0.05][k]
		spine_z[k] += rsway * [1.0, -0.6, -0.4][k]
	if peek != 0.0:
		# выглядывает: корпус клонится вбок и чуть вперёд (вправо — отрицательный угол вокруг +Z)
		for k in 3:
			spine_z[k] -= peek * [0.1, 0.14, 0.16][k]
			spine_x[k] += absf(peek) * 0.05
	# корпус доворачивается за бьющей рукой, ключица выносит плечо вперёд
	var twist := (reach[1] - reach[0]) * 2.2 + swing_twist + rtw * 0.18
	var dt := torso_off - leg_off
	var spine_a := [leg_off + dt * 0.3 + swing_twist * 0.3 + idle_tw * 0.3 - rtw * 0.06, leg_off + dt * 0.65 + swing_twist * 0.6 + idle_tw * 0.7 + rtw * 0.06,
			torso_off + twist + idle_tw]
	for k in spine_bones.size():
		_set_global_rot(spine_bones[k], rr * Basis(Vector3.UP, spine_a[k]) * Basis(Vector3.RIGHT, spine_x[k])
				* Basis(Vector3.BACK, spine_z[k]) * rest_p.call(spine_bones[k]))
	if neck_bone != -1:
		# разминка шеи: наклон к плечу и поворот
		var nk := Basis.IDENTITY
		if fidget == "neck":
			nk = Basis(Vector3.UP, 0.35 * fidget_side * sin(TAU * fidget_t) * fk) * Basis(Vector3.BACK, 0.3 * fidget_side * fk)
		if peek != 0.0:
			nk = nk * Basis(Vector3.UP, -peek * 0.35) * Basis(Vector3.BACK, -peek * 0.22)   # голова — дальше вбок и чуть к цели
		_set_global_rot(neck_bone, rr * nk * rest_p.call(neck_bone))
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var c := clav_bones[i]
		# дыхание и пружинка стойки поднимают плечи; «поводит плечом» — вверх и назад по кругу
		var up := breath * 0.03 + bounce * 0.025
		var back := 0.0
		if fidget == "shoulder" and (fidget_side > 0.0) == (i == 1):
			up += 0.16 * fk
			back += 0.14 * sin(TAU * fidget_t * 0.5 + 0.3) * fk
		# расслабленно плечи чуть опущены
		up -= 0.03 * rk
		_set_global_rot(c, rr * Basis(Vector3.UP, torso_off + side * (reach[i] + 0.06 * gun_ads_w) * 2.5 + twist + idle_tw - side * back)
				* Basis(Vector3.BACK, side * up) * rest_p.call(c))
	var torso_rot := Basis(Vector3.UP, torso_off)
	for e in bone_map:
		var d: Node3D = e[1]
		var bas := (leg_rot if e[5] else torso_rot) * inv * d.global_basis.orthonormalized()
		var arm: int = e[3]
		if arm >= 0:
			# кисть поворачивается тыльной стороной вверх в стойке (у предплечья — половина)
			var side := -1.0 if arm == 0 else 1.0
			# с оружием (кроме щита) кисть остаётся большим пальцем вверх — молотковый хват, оружие стоит вертикально
			var armed_k := ARMED_TWIST if weapon_ids[arm] != "" and weapon_ids[arm] != "shield" else 1.0
			# голый кулак (промпт 03:33) вывернут меньше — пальцами к другой руке; щит — как раньше
			var fist_k := 0.6 if weapon_ids[arm] == "shield" else 0.22
			var tw := deg_to_rad(90.0) * side * (0.1 + fist_k * fist_blend * armed_k) * (1.0 if e[4] else 0.5)
			if arm == 0 and weapon_ids[0] in ["knife", "shiv"]:
				# нож в левой (промпт 04:48): кисть развёрнута тыльной стороной вверх — лезвие от мизинца лежит поверх предплечья, видно в кадре
				tw = deg_to_rad(90.0) * side * (0.1 + 1.0 * fist_blend) * (1.0 if e[4] else 0.5)
			bas = bas * Basis(Vector3.UP, tw)
		_set_global_rot(e[0], rr * bas * e[2])
	var wig := fk * idle_amt * (1.0 - fist_blend) if fidget == "fingers" else 0.0
	for n in finger_bones.size():
		var f: Array = finger_bones[n]
		# шевелит пальцами — каждый палец сгибается в своём ритме
		var b := clampf(fist_blend + wig * (0.22 + 0.22 * sin(idle_time * 13.0 + float(n) * 1.7)), 0.0, 1.0)
		# заряд удара: на второй руке кулак слегка раскрывается (пальцы полусогнуты) — в ожидании удара
		if n < finger_arm.size() and finger_arm[n] != charge_arm and charge_vis > 0.0:
			# лёгкое расслабление (промпт 19:47): пальцы чуть разжимаются (до 35%), большой палец остаётся
			# в позе кулака поверх пальцев — при полном раскрытии он проходил сквозь них (его поза покоя — вдоль пальцев)
			if not finger_thumb[n]:
				b *= 1.0 - 0.35 * smoothstep(0.0, 1.0, charge_vis)
		# с оружием (промпт 04:49) пальцы всегда обхватывают рукоять по её толщине — не кулак насквозь;
		# большой палец заходит чуть сильнее — сверху/сбоку
		if n < finger_arm.size() and weapon_ids[finger_arm[n]] != "":
			var gk: float = GRIP_CURL.get(weapon_ids[finger_arm[n]], 0.7)
			b = minf(gk + 0.1, 1.0) if finger_thumb[n] else gk
			if weapon_ids[finger_arm[n]] == "pistol" and n < finger_index.size() and finger_index[n]:
				b = 0.42   # указательный — вдоль спуска, не в кулаке
		skel.set_bone_pose_rotation(f[0], (f[1] as Quaternion).slerp(f[2], b))
	_flex_weapons()


## Хлёст кистью в махе: оружие поворачивается от хвата к линии предплечья на wrist_flex
## (0 — как в стойке, торчит вверх; ~1 — продолжает руку; минус — взведено назад).
func _flex_weapons() -> void:
	for i in 2:
		var n = weapon_nodes[i]
		if n == null or not is_instance_valid(n) or not n.is_inside_tree():
			continue
		var w: Node3D = n
		if not w.has_meta("grip"):
			w.set_meta("grip", w.transform)
		var grip: Transform3D = w.get_meta("grip")
		if absf(wrist_flex[i]) < 0.001:
			w.transform = grip
			_melee_stance_rot(i, w)
			continue
		var s: String = ["_L", "_R"][i]
		var sk := skel.global_transform
		var fore := (sk * skel.get_bone_global_pose(skel.find_bone("hand" + s)).origin
				- sk * skel.get_bone_global_pose(skel.find_bone("lowerarm" + s)).origin).normalized()
		var par: Transform3D = w.get_parent().global_transform
		var wy := (par.basis * grip.basis.y).normalized()
		var axis := wy.cross(fore)
		if axis.length() < 0.01:
			continue
		var ax_l := (par.basis.inverse() * axis.normalized()).normalized()
		w.transform = Transform3D(Basis(ax_l, wrist_flex[i]) * grip.basis, grip.origin)
		_melee_stance_rot(i, w)


## Можно ли держать оружие в руке i диагональю стойки (05:50): ближний бой, кроме ножа/заточки в левой (обратный хват).
func _melee_stance_ok(i: int) -> bool:
	var id: String = weapon_ids[i]
	if id in MELEE_ST_SKIP:
		return false
	return not (i == 0 and id in ["knife", "shiv"])


## Стойка с оружием (05:50): вместо «торчит вверх» — ось оружия вперёд-вверх ~68° от вертикали (иначе конец уходит
## выше середины кадра), конец к цели и чуть
## к центру, кромка (ось X модели) — вперёд-вниз к цели. Задаётся в осях тела; в махе вес уходит в 0 (melee_st_w).
func _melee_stance_rot(i: int, w: Node3D) -> void:
	var k := melee_st_w[i] * fist_blend
	if k < 0.001:
		return
	var side := -1.0 if i == 0 else 1.0
	var d := Vector3(-0.14 * side, 0.36, -0.92).normalized()
	var f := Vector3(0, 0, -1)
	var e := (f - d * f.dot(d)).normalized()
	var tb := Basis(e, d, e.cross(d))
	var body := global_basis.orthonormalized() * Basis(Vector3.UP, angle_difference(rotation.y, torso_yaw))
	var par: Basis = w.get_parent().global_basis
	var sc := w.transform.basis.get_scale()
	var target_q := (par.orthonormalized().inverse() * (body * tb)).get_rotation_quaternion()
	var cur_q := w.transform.basis.orthonormalized().get_rotation_quaternion()
	w.transform = Transform3D(Basis(cur_q.slerp(target_q, k)).scaled(sc), w.transform.origin)


## Поворот кости в пространстве скелета -> локальный поворот относительно родителя.
func _set_global_rot(b: int, g: Basis) -> void:
	var pb := skel.get_bone_parent(b)
	var parent := skel.get_bone_global_pose(pb).basis.orthonormalized() if pb != -1 else Basis.IDENTITY
	skel.set_bone_pose_rotation(b, (parent.inverse() * g.orthonormalized()).get_rotation_quaternion())


## Плавность приседа (ease in-out) — для таза, камеры и наклона.
func _crouch_k() -> float:
	return smoothstep(0.0, 1.0, crouch)


## Таз: перенос веса/покачивание стоя + опускание в приседе (чуть назад).
func _hip() -> Vector3:
	var ck := _crouch_k()
	return hip_off + Vector3(0, -CROUCH_HIP * ck + run_bob, 0.13 * ck)   # 18.11: в приседе таз назад, колени не уходят вперёд


## Взять оружие в руку arm (0 — левая, 1 — правая; "" — убрать). Модель крепится к кости кисти.
func set_weapon(id: String, arm := 1) -> void:
	var old = weapon_nodes[arm]
	if old and is_instance_valid(old):
		old.queue_free()
	weapon_nodes[arm] = null
	weapon_ids[arm] = id
	if arm == 1:
		weapon_id = id
		weapon_node = null
	if id == "":
		return
	var n := Weapons.make(id)
	if n.get_child_count() == 0 and Items.ITEMS.has(id):
		n.free()   # не оружие (промпт 18.11 00:27) — в кулаке маленькая модель предмета с пола
		n = Node3D.new()
		var mm := Items.make_mesh(id)
		mm.scale = Vector3.ONE * 0.7
		mm.position = Vector3(0, 0.05, 0)
		n.add_child(mm)
	fist_fx[arm].add_child(n)
	n.transform = _grip(arm, id)
	weapon_nodes[arm] = n
	if arm == 1:
		weapon_node = n


## Хват из костей кисти: ось оружия идёт сквозь кулак (от мизинца к указательному), рукоять в пальцах,
## оружие наклонено вперёд и наружу. Щит — на предплечье, лицевой стороной от тыльной стороны кисти.
func _grip(arm: int, id: String) -> Transform3D:
	var fx := fist_fx[arm]
	if skel == null or not fx.is_inside_tree():
		return WEAPON_GRIP
	var s: String = ["_L", "_R"][arm]
	var inv := fx.global_transform.affine_inverse()
	var pt := func(bone: String) -> Vector3:
		var b := skel.find_bone(bone + s)
		return inv * (skel.global_transform * skel.get_bone_global_pose(b).origin)
	var a: Vector3 = pt.call("index01")
	var b2: Vector3 = pt.call("pinky01")
	var m: Vector3 = pt.call("middle01")
	var h: Vector3 = pt.call("hand")
	var up := (a - b2).normalized()
	var fwd := m - h
	fwd = (fwd - up * fwd.dot(up)).normalized()
	# ладонь в A-позе смотрит вниз (-Z скелета) — переводим это направление в текущую позу кисти
	var hb := skel.find_bone("hand" + s)
	var pose_b := skel.get_bone_global_pose(hb).basis
	var rest_b := skel.get_bone_global_rest(hb).basis
	var palm_w := skel.global_transform.basis * (pose_b * (rest_b.inverse() * Vector3(0, 0, -1)))
	var palm := (inv.basis * palm_w)
	palm = (palm - up * palm.dot(up) - fwd * palm.dot(fwd)).normalized()
	var unit := 1.0 / maxf(fx.global_transform.basis.get_scale().x, 0.0001)   # локальных единиц в метре
	if id == "shield":
		# лицо щита — вперёд (в стойке), верх — вдоль предплечья; висит на предплечье ниже кисти
		var nrm := (palm * 0.6 + fwd * 0.5 - up * 0.4).normalized()
		var y_ax := (fwd - nrm * fwd.dot(nrm)).normalized()
		var x_ax := y_ax.cross(nrm).normalized()
		var o := h - y_ax * 0.17 * unit + nrm * 0.06 * unit
		return Transform3D(Basis(x_ax * unit, y_ax * unit, nrm * unit), o)
	# рукоять — в «тоннеле» сжатых пальцев: ось от мизинца к указательному, наклон к костяшкам на GRIP_TILT.
	# Считаем в осях кости кисти (fist_fx лежит в них же, в метрах, на 8 см дальше по кисти).
	var hr := skel.get_bone_global_rest(hb)
	hr.basis = hr.basis.orthonormalized()
	var hinv := hr.affine_inverse()
	var to_m := skel_m                                # единицы скелета -> метры (из модели)
	var lp := func(bone: String) -> Vector3: return hinv * skel.get_bone_global_rest(skel.find_bone(bone + s)).origin * to_m
	var idx: Vector3 = lp.call("index01")
	var pnk: Vector3 = lp.call("pinky01")
	var mid: Vector3 = lp.call("middle01")
	var across := (idx - pnk).normalized()            # к указательному — туда выходит оружие
	var knuck := (mid - across * mid.dot(across)).normalized()
	var n := across.cross(knuck).normalized()
	# сторона ладони (туда сгибаются пальцы) — как в _build_fist_pose (там она проверена для обеих рук):
	# раньше бралась по знаку z, и у левой руки могла оказаться тыльной — рукоять уходила сквозь пальцы (промпт 05:23)
	var gr_i := skel.get_bone_global_rest(skel.find_bone("index01" + s)).origin
	var gr_p := skel.get_bone_global_rest(skel.find_bone("pinky01" + s)).origin
	var gr_m := skel.get_bone_global_rest(skel.find_bone("middle01" + s)).origin
	var palm_g := (gr_i - gr_p).normalized().cross((gr_m - hr.origin).normalized())
	if s == "_L":
		palm_g = -palm_g
	var palm_l := (hr.basis.inverse() * palm_g).normalized()
	if n.dot(palm_l) < 0.0:
		n = -n
	var c := (idx + pnk) * 0.5 - knuck * 0.016 + n * 0.016 - Vector3(0, 0.08, 0)
	var d2 := (across * cos(GRIP_TILT) + knuck * sin(GRIP_TILT) - n * GRIP_OUT).normalized()
	if id in ["knife", "shiv"] and arm == 0:
		# левая рука, обратный хват (промпты 04:40, 04:52): рукоять в кулаке, клинок выходит со стороны мизинца (низ кулака)
		# и смотрит вперёд-вниз по костяшкам — от камеры, не к игроку и не вдоль предплечья. Остриё ≈ кулак + 0.18 м вперёд.
		# 04:56: ровно среднее между вариантами 5721568 (вниз вдоль предплечья) и 597c7bc (вперёд от мизинца)
		var d_a := (-across * 0.5 - knuck * 0.7 - n * 0.5).normalized()
		var d_b := (-across * 0.7 + knuck * 0.7).normalized()
		d2 = (d_a + d_b).normalized()
		c -= d_b * 0.02   # среднее смещения (0 и 4 см глубже в кулак)
		# 04:59: доводка — клинок не указкой вбок: вниз ~15–20° и вперёд, от камеры (-n в стойке смотрит к камере);
		# нож сдвинут по оси рукояти на 2.5 см в сторону клинка — торец не торчит из кулака с другой стороны
		d2 = (-across * 1.0 - knuck * 0.25 + n * 0.35).normalized()
		c += d2 * 0.025
	if id == "pistol":
		c -= d2 * 0.042   # 05:41: в кулаке середина рукояти (её низ — начало модели), а не её низ; спуск — у указательного
	var xw := (knuck - d2 * knuck.dot(d2)).normalized()   # лезвие ребром к костяшкам — по направлению удара
	var zw := xw.cross(d2).normalized()
	return Transform3D(Basis(xw * unit, d2 * unit, zw * unit), c * unit)


# ---------- одежда на модели (промпт 18.11 00:44) ----------
# Из меша тела вырезаются куски по костям (торс, руки, ноги, стопы, кисти, верх головы), раздуваются по нормали
# и красятся в цвет вещи. Скин тот же, что у тела, — одежда двигается вместе с ним. Рюкзак — коробка на спине.

const OUTFIT_SLOTS := ["head", "body", "legs", "feet", "hands", "back"]


func _outfit_setup(body_mi: MeshInstance3D, rest: Callable) -> void:
	outfit_body = body_mi
	var sk: Skin = body_mi.skin
	outfit_names.resize(sk.get_bind_count())
	var hi := -1
	var he := -1
	for k in sk.get_bind_count():
		var nm := String(sk.get_bind_name(k))
		if sk.get_bind_bone(k) >= 0:
			nm = skel.get_bone_name(sk.get_bind_bone(k))
		outfit_names[k] = nm
		if nm == "head":
			hi = k
		elif nm == "head_end":
			he = k
	var has_end := false
	if hi >= 0:
		outfit_head_a = sk.get_bind_pose(hi).affine_inverse().origin
		if he >= 0:
			outfit_head_d = sk.get_bind_pose(he).affine_inverse().origin - outfit_head_a
			has_end = true
	var tall: float = (rest.call("head_end") as Transform3D).origin.y - (rest.call("foot_L") as Transform3D).origin.y + 0.1
	if body_mi.mesh and tall > 0.3:
		outfit_upm = clampf(body_mi.mesh.get_aabb().size.y / tall, 0.001, 1000.0)
	if not has_end:
		outfit_head_d = Vector3.UP * 0.2 * outfit_upm   # нет head_end — голова ~20 см вверх


## Показать надетое (слот -> id), как inv.equip. Вызывают game._apply_equip и сеть (чужой игрок).
func set_outfit(eq: Dictionary) -> void:
	if skel == null or outfit_body == null:
		return
	for sl in OUTFIT_SLOTS:
		var id := String(eq.get(sl, ""))
		if outfit_ids.has(sl) and String(outfit_ids[sl]) == id:
			continue
		outfit_ids[sl] = id
		var old = outfit_nodes.get(sl)
		if old != null and is_instance_valid(old):
			old.queue_free()
		outfit_nodes.erase(sl)
		if id == "" or not Items.ITEMS.has(id):
			continue
		var n := _make_outfit(sl, id)
		if n:
			outfit_nodes[sl] = n


## [кости-префиксы, толщина в метрах, порог «верх головы» (0 — без порога)]
func _outfit_parts(sl: String, id: String) -> Array:
	match sl:
		"head":
			return [["head"], 0.035 if id == "ushanka" else 0.025, 0.42 if id == "ushanka" else 0.56]
		"body":
			var b := ["spine", "clavicle"]
			if id != "vest":
				b.append("upperarm")
			if id in ["jacket", "kurtka"]:
				b.append("lowerarm")
			return [b, 0.022 if id == "vest" else 0.012, 0.0]
		"legs":
			return [["pelvis", "thigh", "calf"], 0.01, 0.0]
		"feet":
			return [["foot", "toe"], 0.014, 0.0]
		"hands":
			if id == "knuckles":
				return []
			return [["hand", "thumb", "index", "middle", "ring", "pinky"], 0.006, 0.0]
	return []


func _make_outfit(sl: String, id: String) -> Node3D:
	var col: Color = Items.ITEMS[id].get("color", Color(0.5, 0.5, 0.5))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.45 if sl == "head" and id != "ushanka" else 0.9
	if sl == "back":
		var b := skel.find_bone("spine03")
		if b < 0:
			return null
		var att := BoneAttachment3D.new()
		att.bone_name = "spine03"
		skel.add_child(att)
		var rel := global_transform.affine_inverse() * skel.global_transform
		var bt := rel * skel.get_bone_global_rest(b)
		var big := id == "backpack"
		var want := Transform3D(Basis(), bt.origin + Vector3(0, -0.06, 0.17 if big else 0.16))
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.32, 0.42, 0.16) if big else Vector3(0.28, 0.34, 0.15)
		mi.mesh = bm
		mi.material_override = mat
		att.add_child(mi)
		mi.transform = bt.affine_inverse() * want
		return att
	var parts := _outfit_parts(sl, id)
	if parts.is_empty():
		return null
	var key := "%s|%s|%s" % [str(parts[0]), str(parts[1]), str(parts[2])]
	var mesh: ArrayMesh = outfit_cache.get(key)
	if mesh == null:
		mesh = _outfit_mesh(parts[0], float(parts[1]), float(parts[2]))
		if mesh == null:
			return null
		outfit_cache[key] = mesh
	var o := MeshInstance3D.new()
	o.mesh = mesh
	o.material_override = mat
	skel.add_child(o)
	o.transform = outfit_body.transform
	o.skin = head_mi.skin if head_mi and is_instance_valid(head_mi) else outfit_body.skin
	o.skeleton = NodePath("..")
	return o


func _outfit_mesh(bones: Array, thick: float, hat_t: float) -> ArrayMesh:
	var src: Mesh = outfit_body.mesh
	if src == null or src.get_surface_count() == 0:
		return null
	var arr := src.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	if arr[Mesh.ARRAY_BONES] == null or arr[Mesh.ARRAY_WEIGHTS] == null or verts.is_empty():
		return null
	var bi: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var bw: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var idx := PackedInt32Array()
	if arr[Mesh.ARRAY_INDEX] != null:
		idx = arr[Mesh.ARRAY_INDEX]
	if idx.is_empty():
		for i in verts.size():
			idx.append(i)
	@warning_ignore("integer_division")
	var nb: int = bi.size() / verts.size()
	var dd := outfit_head_d.length_squared()
	var inside := PackedByteArray()
	inside.resize(verts.size())
	for v in verts.size():
		var best := -1
		var bwv := -1.0
		for k in nb:
			if bw[v * nb + k] > bwv:
				bwv = bw[v * nb + k]
				best = bi[v * nb + k]
		var nm: String = outfit_names[best] if best >= 0 and best < outfit_names.size() else ""
		var ok := false
		for p in bones:
			if nm.begins_with(String(p)):
				ok = true
				break
		if ok and hat_t > 0.0 and dd > 0.0:
			ok = (verts[v] - outfit_head_a).dot(outfit_head_d) / dd > hat_t
		inside[v] = 1 if ok else 0
	var out := PackedInt32Array()
	for t in range(0, idx.size() - 2, 3):
		if inside[idx[t]] + inside[idx[t + 1]] + inside[idx[t + 2]] >= 2:
			out.append(idx[t])
			out.append(idx[t + 1])
			out.append(idx[t + 2])
	if out.is_empty():
		return null
	var nv := verts.duplicate()
	var d := thick * outfit_upm
	if norms.size() == nv.size():
		for v in nv.size():
			nv[v] += norms[v] * d
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = nv
	if norms.size() == nv.size():
		a[Mesh.ARRAY_NORMAL] = norms
	a[Mesh.ARRAY_BONES] = bi
	a[Mesh.ARRAY_WEIGHTS] = bw
	a[Mesh.ARRAY_INDEX] = out
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a, [], {}, src.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
	return m
