extends CharacterBody3D
## Игрок от первого лица: тело видно, если посмотреть вниз.
## WASD, Shift — бег, пробел — прыжок, ПКМ — режим кулаков (руки в стойку), ЛКМ — удар.

const Sfx := preload("res://sfx.gd")
## Шаг — приглушённый шорох (sfx.gd: step_noise), звучит в момент постановки стопы; по траве — step_grass.
const STEP_DB := -23.0      # громкость шага относительно ходьбы (-10 дБ)

const WALK := 3.4
const SPRINT := 6.4
const GRAVITY := 22.0
const FALL_MULT := 1.35      # вниз падаем быстрее, чем взлетаем — прыжок не «плывёт»
const JUMP := 5.0            # ~0.55 м
const SENS := 0.0022
const CAM_Y := 1.7
const FOV := 75.0
## true — тело игрока: модель models/BaseHuman.fbx, анимированная через кости;
## false — старое тело из капсул (код оставлен, чтобы легко вернуть).
const USE_MODEL := true
const MODEL := preload("res://models/BaseHuman.fbx")
const MODEL_Z := 0.12              # модель чуть позади камеры, чтобы лицо не лезло в кадр
var HIP_Y := 0.88
var LEG_L1 := 0.40              # бедро
var LEG_L2 := 0.40              # голень
var GROUND_Y := 0.09 - 0.88     # высота голеностопа над полом относительно бедра
const ACCEL_WALK := 5.0
const ACCEL_SPRINT := 3.2

# позы руки в градусах: x — подъём плеча вперёд, y — внутрь, z — в сторону, w — сгиб локтя
const REST := Vector4(0, 0, 0, 10)
const GUARDS: Array[Vector4] = [Vector4(66, 12, 4, 80), Vector4(54, 18, 6, 94)]
const PUNCHES := {
	"straight": [Vector4(55, 14, 2, 80), Vector4(100, 6, 0, 4)],
	"hook": [Vector4(82, -30, 8, 40), Vector4(96, 32, 0, 28)],
	"upper": [Vector4(45, 12, 6, 100), Vector4(95, 12, 0, 58)],
}
# кулаки сильно ослаблены (было 18/24/30): без оружия враг падает с ~9 ударов
const PUNCH_DMG := {"straight": 6.0, "hook": 8.0, "upper": 10.0}
const Weapons := preload("res://weapons.gd")

var active := false
var dmg_mult := 1.0           # множитель урона (кастет из сейфа — 1.5)
var speed_mult := 1.0         # замедление (отравление наверху, gasmask.gd)
var weapon_id := ""           # оружие в правой руке (магазин, weapons.gd)
var weapon_node: Node3D
# как оружие лежит в кулаке относительно точки кисти (подобрано по скриншотам)
var WEAPON_GRIP := Transform3D(Basis.from_euler(Vector3(1.5, 0.0, 0.0)), Vector3(0, 0.03, 0))
var cam: Camera3D
var head: Node3D
var legs: Array[Node3D] = []      # тазобедренные шарниры
var knees: Array[Node3D] = []
var ankles: Array[Node3D] = []
var foot: Array[Vector3] = [Vector3(0, -0.79, 0), Vector3(0, -0.79, 0)]  # цель стопы от бедра
var gait := 0.0                   # фаза цикла шага 0..1 (левая нога; правая сдвинута на 0.5)
var gait_prev: Array[float] = [0.0, 0.5]
var move_dir := Vector3(0, 0, -1) # направление движения в локальных осях
var stopping := false
var settle_t: Array[float] = [1.0, 1.0]       # дошагивание при остановке: 0..1, 1 = стоит
var settle_from: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var settle_to: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var land_dip := 0.0
var shoulders: Array[Node3D] = []
var elbows: Array[Node3D] = []
var arm_pose: Array[Vector4] = [REST, REST]
var fist_fx: Array[CPUParticles3D] = []   # точка кулака (частицы больше не испускаются)
# «рисованный» след удара: тонкие штрихи вдоль траектории кулака
var trail_mesh: Array[ImmediateMesh] = []
var trail_pts: Array = [[], []]
var trail_on: Array[bool] = [false, false]
var trail_alpha: Array[float] = [0.0, 0.0]
var trail_mat: StandardMaterial3D
var post_mat: ShaderMaterial          # постобработка (задаёт main.gd)
var foot_pitch: Array[float] = [0.0, 0.0]
var reach: Array[float] = [0.0, 0.0]   # выпад плеча вперёд при ударе
var fists := false
# --- модель с ригом ---
var skel: Skeleton3D
var rig_rel: Basis                 # поворот скелета относительно игрока (без масштаба)
var bone_map: Array = []          # [кость, узел-драйвер, опорный базис, рука (-1 — нет), кисть?]
var finger_bones: Array = []      # [кость, поворот расслабленной кисти, поворот в кулаке]
var spine_bone := -1
var clav_bones: Array[int] = [-1, -1]
var hands: Array[Node3D] = []     # драйверы кистей
var fist_blend := 0.0
var punching := false
var sprint_carry := 0.0   # 1 сразу после бега, плавно падает — от него зависит «занос»
var phase := 0.0
var bob := 0.0
var last_step := -1
var was_on_floor := true
var land_speed := 0.0

var steps: Array[AudioStreamWAV] = []
var whooshes: Array[AudioStreamWAV] = []
var exhales: Array[AudioStreamWAV] = []
var impacts: Array[AudioStreamWAV] = []
var inhale_snd: AudioStreamWAV
var exhale_out_snd: AudioStreamWAV   # опускание рук — тот же вдох задом наперёд
var last_arm := -1
var last_kind := ""
var step_player: AudioStreamPlayer
var step_noise_player: AudioStreamPlayer
var step_noise: AudioStreamWAV
var grass_steps: Array[AudioStreamWAV] = []   # шаги по траве (поверхность)
var step_eq: AudioEffectEQ6
var voice_player: AudioStreamPlayer
var hit_player: AudioStreamPlayer
var step_idx := 0


func _ready() -> void:
	step_player = _audio(3)
	voice_player = _audio(2)
	hit_player = _audio(3)
	for i in 4:
		whooshes.append(Sfx.whoosh(i))
		exhales.append(Sfx.exhale(i))
		impacts.append(Sfx.impact(i))
	inhale_snd = Sfx.inhale()
	exhale_out_snd = Sfx.inhale(true)
	step_noise_player = _audio(3)
	step_noise = Sfx.step_noise()
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

	head = Node3D.new()
	head.position = Vector3(0, CAM_Y, -0.22)
	add_child(head)
	cam = Camera3D.new()
	cam.near = 0.03
	cam.fov = FOV
	head.add_child(cam)

	_build_body()
	if USE_MODEL:
		_build_model()


## Шина «Steps»: компрессор приглушает самый громкий момент (удар), затем случайный эквалайзер.
func _setup_step_bus() -> void:
	var bi := AudioServer.get_bus_index("Steps")
	if bi == -1:
		AudioServer.add_bus()
		bi = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bi, "Steps")
		AudioServer.set_bus_send(bi, "Master")
		var comp := AudioEffectCompressor.new()
		comp.threshold = -16.0
		comp.ratio = 4.0
		comp.attack_us = 300.0
		comp.release_ms = 120.0
		AudioServer.add_bus_effect(bi, comp)
		AudioServer.add_bus_effect(bi, AudioEffectEQ6.new())
	for e in AudioServer.get_bus_effect_count(bi):
		if AudioServer.get_bus_effect(bi, e) is AudioEffectEQ6:
			step_eq = AudioServer.get_bus_effect(bi, e)
	step_player.bus = "Steps"
	step_noise_player.bus = "Steps"


## Каждый шаг слегка «подрезан эквалайзером» в случайных местах: 1–2 полосы глушим, иногда одну чуть поднимаем.
func _randomize_step_eq() -> void:
	if step_eq == null:
		return
	for b in step_eq.get_band_count():
		step_eq.set_band_gain_db(b, 0.0)
	var bands := [1, 2, 3, 4, 5]   # 100 Гц, 320 Гц, 1 кГц, 3.2 кГц, 10 кГц
	bands.shuffle()
	for k in randi_range(1, 2):
		step_eq.set_band_gain_db(bands[k], randf_range(-10.0, -4.0))
	if randf() < 0.35:
		step_eq.set_band_gain_db(bands[2], randf_range(1.0, 3.0))


func _audio(poly: int) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.max_polyphony = poly
	add_child(p)
	return p


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
	var neck := CylinderMesh.new()
	neck.top_radius = 0.06
	neck.bottom_radius = 0.075
	neck.height = 0.24
	var n := _part(body, neck, Vector3(0, 1.53, 0.1), skin)
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
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
	skel = model.find_children("*", "Skeleton3D", true, false)[0]
	var rel := global_transform.affine_inverse() * skel.global_transform
	rig_rel = rel.basis.orthonormalized()
	var rest := func(bone: String) -> Transform3D:
		var t := rel * skel.get_bone_global_rest(skel.find_bone(bone))
		return Transform3D(t.basis.orthonormalized(), t.origin)
	var bp := func(bone: String) -> Vector3: return rest.call(bone).origin

	# размеры ног берём из модели, чтобы IK ставил стопы точно на пол
	HIP_Y = bp.call("thigh_L").y
	LEG_L1 = bp.call("thigh_L").distance_to(bp.call("calf_L"))
	LEG_L2 = bp.call("calf_L").distance_to(bp.call("foot_L"))
	GROUND_Y = bp.call("foot_L").y - HIP_Y
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
			bone_map.append([skel.find_bone(e[0] + s), e[1], ref, arm, e[0] == "hand"])
		clav_bones[i] = skel.find_bone("clavicle" + s)
		# пальцы: ось сгиба — поперёк пальца, к ладони (ладонь в A-позе смотрит вниз, -Z скелета)
		for f in ["thumb", "index", "middle", "ring", "pinky"]:
			for k in [1, 2, 3]:
				var b := skel.find_bone("%s%02d%s" % [f, k, s])
				if b == -1:
					continue
				var g := skel.get_bone_global_rest(b).basis.orthonormalized()
				var v := g.y.normalized()
				var palm := Vector3(0, 0, -1)
				var axis := (g.inverse() * v.cross(palm)).normalized()
				var rest_q := skel.get_bone_rest(b).basis.get_rotation_quaternion()
				var fist_a: float = [0.0, 85.0, 100.0, 70.0][k] if f != "thumb" else [0.0, 0.0, 30.0, 40.0][k]
				var relax_a: float = [0.0, 12.0, 18.0, 12.0][k] if f != "thumb" else [0.0, 0.0, 8.0, 8.0][k]
				var fist_q := rest_q * Quaternion(axis, deg_to_rad(fist_a))
				var relax_q := rest_q * Quaternion(axis, deg_to_rad(relax_a))
				if f == "thumb" and k == 1:
					# основание большого пальца нацеливаем на костяшки указательного и среднего
					# со стороны ладони — палец ложится поперёк сжатых пальцев
					var tgt := (skel.get_bone_global_rest(skel.find_bone("index02" + s)).origin
							+ skel.get_bone_global_rest(skel.find_bone("middle01" + s)).origin) * 0.5 + palm * 0.0002
					var aim := Basis(Quaternion(v, (tgt - skel.get_bone_global_rest(b).origin).normalized()))
					fist_q = rest_q * (g.inverse() * aim * g).get_rotation_quaternion()
					relax_q = rest_q.slerp(fist_q, 0.15)
				finger_bones.append([b, relax_q, fist_q])
		# точка кулака для следа и попаданий — на кости кисти
		var att := BoneAttachment3D.new()
		att.bone_name = "hand" + s
		skel.add_child(att)
		var fx := fist_fx[i]
		fx.get_parent().remove_child(fx)
		att.add_child(fx)
		fx.transform = Transform3D(Basis.from_scale(Vector3.ONE * 0.01), Vector3(0, 0.0008, 0))
	spine_bone = skel.find_bone("spine03")

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
			skin.set_bind_pose(k, Transform3D(bind.basis.scaled(Vector3.ONE * 0.001), bind.origin * 0.001))
	body_mi.skin = skin
	body_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Кости модели повторяют повороты узлов-драйверов + выпад плеча, поворот корпуса, кулак.
func _apply_bones() -> void:
	if skel == null:
		return
	var inv := global_basis.orthonormalized().inverse()
	var rr := rig_rel.inverse()
	# корпус доворачивается за бьющей рукой, ключица выносит плечо вперёд
	var twist := (reach[1] - reach[0]) * 1.6
	_set_global_rot(spine_bone, rr * Basis(Vector3.UP, twist) * rig_rel * skel.get_bone_global_rest(spine_bone).basis.orthonormalized())
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var c := clav_bones[i]
		_set_global_rot(c, rr * Basis(Vector3.UP, side * reach[i] * 2.5 + twist) * rig_rel * skel.get_bone_global_rest(c).basis.orthonormalized())
	for e in bone_map:
		var d: Node3D = e[1]
		var basis := inv * d.global_basis.orthonormalized()
		var arm: int = e[3]
		if arm >= 0:
			# кисть поворачивается тыльной стороной вверх в стойке (у предплечья — половина)
			var side := -1.0 if arm == 0 else 1.0
			var tw := deg_to_rad(90.0) * side * (0.1 + 0.6 * fist_blend) * (1.0 if e[4] else 0.5)
			basis = basis * Basis(Vector3.UP, tw)
		_set_global_rot(e[0], rr * basis * e[2])
	for f in finger_bones:
		skel.set_bone_pose_rotation(f[0], (f[1] as Quaternion).slerp(f[2], fist_blend))


## Поворот кости в пространстве скелета -> локальный поворот относительно родителя.
func _set_global_rot(b: int, g: Basis) -> void:
	var pb := skel.get_bone_parent(b)
	var parent := skel.get_bone_global_pose(pb).basis.orthonormalized() if pb != -1 else Basis.IDENTITY
	skel.set_bone_pose_rotation(b, (parent.inverse() * g.orthonormalized()).get_rotation_quaternion())


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


func _part(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and captured:
		rotate_y(-event.relative.x * SENS)
		head.rotation.x = clampf(head.rotation.x - event.relative.y * SENS, -1.5, 1.4)
	elif event is InputEventMouseButton and event.pressed:
		if not captured:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			toggle_fists()
		elif event.button_index == MOUSE_BUTTON_LEFT and fists:
			punch()


func toggle_fists() -> void:
	if punching:
		return
	fists = not fists
	var tw := create_tween().set_parallel()
	tw.tween_property(self, "fist_blend", 1.0 if fists else 0.0, 0.3).set_trans(Tween.TRANS_SINE)
	for i in 2:
		tw.tween_method(_pose_setter(i), arm_pose[i], GUARDS[i] if fists else REST, 0.3).set_trans(Tween.TRANS_SINE)
	voice_player.stream = inhale_snd if fists else exhale_out_snd
	voice_player.volume_db = -25.0
	voice_player.pitch_scale = randf_range(0.95, 1.05)
	voice_player.play()


func punch() -> void:
	if punching or fist_blend < 0.9:
		return
	punching = true
	# рука: с шансом 75% другая, чем в прошлый раз
	var i := randi() % 2
	if last_arm != -1:
		i = (1 - last_arm) if randf() < 0.75 else last_arm
	last_arm = i
	# вид удара: базовые шансы, но прошлый вид выпадает реже (вес ×0.35)
	var weights := {"straight": 0.45, "hook": 0.3, "upper": 0.25}
	if last_kind != "":
		weights[last_kind] *= 0.35
	var total := 0.0
	for k in weights:
		total += weights[k]
	var r := randf() * total
	var kind := "straight"
	for k in weights:
		r -= weights[k]
		if r <= 0.0:
			kind = k
			break
	last_kind = kind
	var keys: Array = PUNCHES[kind]
	var tw := create_tween()
	tw.tween_method(_pose_setter(i), arm_pose[i], keys[0], 0.08).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(_punch_sound)
	tw.tween_callback(_punch_fx.bind(i, kind, true))
	tw.tween_method(_pose_setter(i), keys[0], keys[1], 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(func(v: float) -> void: reach[i] = v, 0.0, 0.12, 0.09)
	tw.tween_callback(_check_hit.bind(i, kind))
	tw.tween_callback(_punch_fx.bind(i, kind, false))
	tw.tween_method(_pose_setter(i), keys[1], GUARDS[i], 0.22).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_method(func(v: float) -> void: reach[i] = v, 0.12, 0.0, 0.22)
	tw.tween_callback(func(): punching = false)


## Эффекты удара: размытие в движении (прямой — «зум», хук — по горизонтали, апперкот — по вертикали)
## и потоки воздуха за кулаком.
func _punch_fx(i: int, kind: String, on: bool) -> void:
	trail_on[i] = on
	if on:
		trail_pts[i].clear()
		trail_alpha[i] = 1.0
	if not on or post_mat == null:
		return
	# размытие только вокруг кулака и слабее
	var fp := fist_fx[i].global_position
	if not cam.is_position_behind(fp):
		post_mat.set_shader_parameter("blur_center", cam.unproject_position(fp) / get_viewport().get_visible_rect().size)
	var side := -1.0 if i == 0 else 1.0
	var param := "blur_amt"
	var peak := 0.008
	if kind == "straight":
		param = "zoom_amt"
		peak = 0.018
	elif kind == "hook":
		post_mat.set_shader_parameter("blur_dir", Vector2(-side, 0.0))
	else:
		post_mat.set_shader_parameter("blur_dir", Vector2(0.0, 1.0))
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: post_mat.set_shader_parameter(param, v), 0.0, peak, 0.05)
	tw.tween_method(func(v: float) -> void: post_mat.set_shader_parameter(param, v), peak, 0.0, 0.14)


func _pose_setter(i: int) -> Callable:
	return func(p: Vector4) -> void: arm_pose[i] = p


func _punch_sound() -> void:
	_play(hit_player, whooshes, -17.0)
	_play(voice_player, exhales, -14.0)


func _check_hit(arm: int, kind := "straight") -> void:
	var from := cam.global_position
	var armed := arm == 1 and weapon_id != ""
	var reach_len: float = Weapons.WEAPONS[weapon_id]["reach"] if armed else 1.0
	var to := from - cam.global_transform.basis.z * reach_len
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	q.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		_play(hit_player, impacts, -11.0)
		# урон врагам/манекену (тестовые механики, см. game.gd): у цели должен быть take_hit(урон, направление)
		if hit.collider.has_method("take_hit"):
			var mult: float = Weapons.WEAPONS[weapon_id]["mult"] if armed else dmg_mult
			hit.collider.take_hit(PUNCH_DMG.get(kind, 8.0) * mult, -cam.global_transform.basis.z)
		# лёгкая отдача в камеру
		var tw := create_tween()
		var side := -1.0 if arm == 0 else 1.0
		tw.tween_property(cam, "rotation:z", 0.02 * side, 0.04)
		tw.tween_property(cam, "rotation:z", 0.0, 0.15)


## Взять оружие в правую руку ("" — убрать). Модель крепится к кости кисти.
func set_weapon(id: String) -> void:
	if weapon_node and is_instance_valid(weapon_node):
		weapon_node.queue_free()
	weapon_node = null
	weapon_id = id
	if id == "":
		return
	weapon_node = Weapons.make(id)
	fist_fx[1].add_child(weapon_node)
	weapon_node.transform = WEAPON_GRIP


func _play(p: AudioStreamPlayer, set_: Array, db: float) -> void:
	p.stream = set_[randi() % set_.size()]
	p.volume_db = db + randf_range(-1.5, 1.5)
	p.pitch_scale = randf_range(0.92, 1.08)
	p.play()


func _process(delta: float) -> void:
	if trail_mesh.is_empty():
		_make_trails()
	for i in 2:
		var pts: Array = trail_pts[i]
		if trail_on[i]:
			var fp := fist_fx[i].global_position
			if pts.is_empty() or (pts[-1] as Vector3).distance_to(fp) > 0.015:
				pts.append(fp)
				if pts.size() > 7:
					pts.pop_front()
		else:
			trail_alpha[i] = maxf(trail_alpha[i] - delta * 7.0, 0.0)
		_draw_trail(i)


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
	for stroke in [[0.0, 0.01, 0.2], [0.03, 0.004, 0.12]]:
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


func _physics_process(delta: float) -> void:
	var on_floor := is_on_floor()
	if not on_floor:
		velocity.y -= GRAVITY * (FALL_MULT if velocity.y < 0.0 else 1.0) * delta
	elif active and Input.is_action_just_pressed("jump"):
		velocity.y = JUMP
		on_floor = false

	var inp := Vector2.ZERO
	if active:
		inp = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := transform.basis * Vector3(inp.x, 0, inp.y)
	var moving := dir.length() > 0.01
	var sprinting := active and moving and inp.y < -0.1 and Input.is_action_pressed("sprint")

	if sprinting:
		sprint_carry = 1.0
	else:
		sprint_carry = move_toward(sprint_carry, 0.0, delta * 0.7)

	var target := dir * (SPRINT if sprinting else WALK) * speed_mult
	var hv := Vector3(velocity.x, 0, velocity.z)
	var air := 1.0 if on_floor else 0.25
	if moving and target.length() > hv.length() + 0.01:
		# разгон: с места до шага ~0.7 с, с шага до бега ~1 с
		var accel := ACCEL_SPRINT if hv.length() > WALK - 0.2 else ACCEL_WALK
		var spd := move_toward(hv.length(), target.length(), accel * air * delta)
		var d := hv.normalized().slerp(target.normalized(), 1.0 - exp(-10.0 * air * delta)) if hv.length() > 0.1 else target.normalized()
		hv = d * spd
	else:
		# торможение мягкое; после бега — ещё мягче
		var rate := (7.0 if moving else lerpf(6.0, 2.6, sprint_carry)) * air
		hv = hv.lerp(target, 1.0 - exp(-rate * delta))
	velocity.x = hv.x
	velocity.z = hv.z
	move_and_slide()

	if is_on_floor() and not was_on_floor and land_speed < -2.5:
		_play_step(-4.0)
		land_dip = clampf(-land_speed * 0.014, 0.0, 0.09)
	land_speed = velocity.y
	was_on_floor = is_on_floor()

	_animate(delta, global_transform.basis.inverse() * hv, sprinting)


func _animate(delta: float, v_local: Vector3, sprinting: bool) -> void:
	var spd := v_local.length()
	var grounded := is_on_floor()
	_animate_legs(delta, v_local, grounded)
	var amt := clampf(spd / WALK, 0.0, 1.5) if grounded else 0.0
	phase = gait * TAU * 2.0
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var p: Vector4 = arm_pose[i]
		# рука качается навстречу противоположной ноге
		var arm_swing := clampf(-foot[1 - i].z * 1.1, -0.6, 0.6) * (1.0 - fist_blend)
		var guard_bob := deg_to_rad(sin(phase + float(i)) * 3.0 * amt * fist_blend)
		shoulders[i].rotation = Vector3(
			deg_to_rad(p.x) + arm_swing + guard_bob,
			deg_to_rad(p.y) * side,
			deg_to_rad(p.z) * side + 0.08 * side * (1.0 - fist_blend))
		elbows[i].rotation.x = deg_to_rad(p.w)
		if not USE_MODEL:
			shoulders[i].position.z = 0.13 - reach[i]
	bob = lerpf(bob, amt, 1.0 - exp(-8.0 * delta))
	land_dip = move_toward(land_dip, 0.0, delta * 0.35)
	# голова ниже всего в момент постановки стопы (дважды за цикл)
	head.position.y = CAM_Y - (0.5 + 0.5 * cos(phase)) * 0.035 * bob - land_dip
	head.position.x = sin(gait * TAU) * 0.012 * bob
	# в стойке голова чуть назад — к плечам, чтобы кулаки были перед лицом, а не в камере
	head.position.z = lerpf(-0.22, -0.04, fist_blend)
	var want_fov := FOV + (7.0 if sprinting else 0.0)
	cam.fov = lerpf(cam.fov, want_fov, 1.0 - exp(-5.0 * delta))
	_apply_bones()


## Процедурная походка: для каждой стопы считаем точку (опора — стопа едет назад по полу,
## перенос — дугой вперёд), затем двухзвенный IK ставит бедро и колено.
func _animate_legs(delta: float, v_local: Vector3, grounded: bool) -> void:
	var spd := v_local.length()
	if spd > 0.1:
		move_dir = Vector3(v_local.x, 0, v_local.z).normalized()
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
	for i in 2:
		_leg_ik(i, foot[i])


func _leg_ik(i: int, t: Vector3) -> void:
	var roll := atan2(t.x, -t.y)                     # отвод ноги в сторону
	var yy := -sqrt(t.y * t.y + t.x * t.x)
	var zz := t.z
	var d := clampf(sqrt(yy * yy + zz * zz), 0.15, LEG_L1 + LEG_L2 - 0.002)
	var aim := atan2(-zz, -yy)                       # угол на стопу (вперёд — плюс)
	var a_hip := acos(clampf((LEG_L1 * LEG_L1 + d * d - LEG_L2 * LEG_L2) / (2.0 * LEG_L1 * d), -1.0, 1.0))
	var a_knee := PI - acos(clampf((LEG_L1 * LEG_L1 + LEG_L2 * LEG_L2 - d * d) / (2.0 * LEG_L1 * LEG_L2), -1.0, 1.0))
	legs[i].rotation = Vector3(aim + a_hip, 0.0, roll)
	knees[i].rotation.x = -a_knee
	# ботинок параллельно полу + перекат стопы
	ankles[i].rotation.x = -(aim + a_hip - a_knee) + foot_pitch[i]


func _play_step(db: float, _pitch := 1.0) -> void:
	_randomize_step_eq()
	if _ground_kind() == "grass":
		step_noise_player.stream = grass_steps[randi() % grass_steps.size()]
		step_noise_player.volume_db = db + STEP_DB + 3.0
		step_noise_player.pitch_scale = randf_range(0.9, 1.1)
	else:
		step_noise_player.stream = step_noise
		step_noise_player.volume_db = db + STEP_DB
		step_noise_player.pitch_scale = 1.0
	step_noise_player.play()


## Что под ногами: метка "ground" у коллайдера (трава поляны — "grass"), иначе бетон.
func _ground_kind() -> String:
	var from := global_position + Vector3(0, 0.3, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -0.9, 0))
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return ""
	return str(hit.collider.get_meta("ground", ""))
