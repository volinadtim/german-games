extends CharacterBody3D
## Игрок от первого лица: тело видно, если посмотреть вниз.
## WASD, Shift — бег, пробел — прыжок, ПКМ — режим кулаков (руки в стойку), ЛКМ — удар.

const Sfx := preload("res://sfx.gd")
## Шаг — приглушённый шорох (sfx.gd: step_noise), звучит в момент постановки стопы; по траве — step_grass.
const STEP_DB := -23.0      # громкость шага относительно ходьбы (-10 дБ)

const WALK := 3.4
const SPRINT := 5.4          # было 6.4 — слишком быстро
const GRAVITY := 22.0
const FALL_MULT := 1.35      # вниз падаем быстрее, чем взлетаем — прыжок не «плывёт»
const JUMP := 5.0            # ~0.55 м
const SENS := 0.0022
const CAM_Y := 1.7
const FOV := 75.0
## Поле зрения из настроек (menu.gd, ползунок «Поле зрения»); бег прибавляет к нему.
static var fov_base := FOV
## true — тело игрока: модель models/BaseHuman.fbx, анимированная через кости;
## false — старое тело из капсул (код оставлен, чтобы легко вернуть).
const USE_MODEL := true
const MODEL := preload("res://models/BaseHuman.fbx")
const MODEL_Z := 0.12              # модель чуть позади камеры, чтобы лицо не лезло в кадр
var HIP_Y := 0.88
var LEG_L1 := 0.40              # бедро
var LEG_L2 := 0.40              # голень
var GROUND_Y := 0.09 - 0.88     # высота голеностопа над полом относительно бедра
const ACCEL_WALK := 16.0     # с места до шага ~0.2 с (было 5 — разгон «плыл»)
const ACCEL_SPRINT := 10.0   # с шага до бега ~0.2 с
const DECEL_WALK := 40.0     # торможение линейное (м/с²): с шага стоп ~0.09 с
const DECEL_SPRINT := 30.0   # с бега ~0.18 с (~0.5 м)
const DECEL_TURN := 22.0     # смена направления / с бега на шаг

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
# удары оружием — отдельный набор. Каждый мах: замах (wind) -> удар (hit, тут проверка попадания) ->
# проводка по инерции (thru) -> возврат в стойку. tw — поворот корпуса в этих точках (рад, для правой руки),
# t — длительности [замах, удар, проводка, возврат], rc — выпад плеча [замах, удар].
const SWINGS := {
	"heavy": [   # бита, труба, монтировка: широко из-за плеча, всем корпусом, тяжело
		{"wind": Vector4(150, -15, 45, 105), "hit": Vector4(72, 10, 4, 16), "thru": Vector4(28, 48, 0, 26),
			"tw": [-0.45, 0.35, 0.6], "t": [0.24, 0.11, 0.16, 0.36], "rc": [-0.03, 0.06], "blur": "upper"},
		{"wind": Vector4(92, -60, 35, 78), "hit": Vector4(88, 6, 0, 12), "thru": Vector4(80, 62, 0, 34),
			"tw": [-0.6, 0.3, 0.7], "t": [0.22, 0.11, 0.16, 0.34], "rc": [-0.03, 0.05], "blur": "hook"},
		{"wind": Vector4(172, 0, 14, 125), "hit": Vector4(62, 8, 0, 10), "thru": Vector4(25, 12, 0, 22),
			"tw": [-0.18, 0.12, 0.2], "t": [0.26, 0.1, 0.14, 0.36], "rc": [-0.05, 0.1], "blur": "upper"},
	],
	"machete": [   # быстрые рубящие махи
		{"wind": Vector4(140, -10, 35, 95), "hit": Vector4(72, 12, 0, 14), "thru": Vector4(40, 52, 0, 30),
			"tw": [-0.3, 0.25, 0.4], "t": [0.1, 0.07, 0.07, 0.2], "rc": [-0.02, 0.06], "blur": "upper"},
		{"wind": Vector4(86, -52, 30, 62), "hit": Vector4(86, 8, 0, 12), "thru": Vector4(80, 60, 0, 34),
			"tw": [-0.4, 0.25, 0.45], "t": [0.1, 0.07, 0.07, 0.2], "rc": [-0.02, 0.05], "blur": "hook"},
		{"wind": Vector4(92, 58, 0, 92), "hit": Vector4(88, -4, 12, 12), "thru": Vector4(80, -44, 35, 28),
			"tw": [0.35, -0.2, -0.35], "t": [0.1, 0.07, 0.07, 0.2], "rc": [0.0, 0.04], "blur": "hook"},
	],
	"knife": [   # короткий тычок или чирк
		{"wind": Vector4(52, 12, 0, 108), "hit": Vector4(98, 8, 0, 4), "thru": Vector4(100, 8, 0, 2),
			"tw": [-0.12, 0.2, 0.22], "t": [0.06, 0.055, 0.04, 0.17], "rc": [-0.04, 0.17], "blur": "straight"},
		{"wind": Vector4(80, -36, 16, 46), "hit": Vector4(82, 30, 0, 30), "thru": Vector4(80, 50, 0, 40),
			"tw": [-0.25, 0.15, 0.25], "t": [0.06, 0.055, 0.05, 0.17], "rc": [-0.01, 0.05], "blur": "hook"},
	],
	"shield": [   # толчок щитом или удар краем
		{"wind": Vector4(60, 12, 4, 115), "hit": Vector4(92, 10, 0, 26), "thru": Vector4(95, 10, 0, 20),
			"tw": [-0.2, 0.25, 0.28], "t": [0.12, 0.08, 0.06, 0.26], "rc": [-0.05, 0.2], "blur": "straight"},
		{"wind": Vector4(122, -10, 25, 96), "hit": Vector4(56, 24, 0, 40), "thru": Vector4(44, 30, 0, 46),
			"tw": [-0.3, 0.25, 0.35], "t": [0.12, 0.08, 0.08, 0.26], "rc": [-0.03, 0.08], "blur": "upper"},
	],
}
var WRIST_HIT := 1.1   # сгиб кисти в момент удара (рад)
# конец оружия (по длинной оси +Y модели) — по нему тянется след
const WEAPON_TIP := {"bat": 0.67, "pipe": 0.63, "crowbar": 0.62, "machete": 0.52, "knife": 0.25, "shield": 0.28}
const Fx := preload("res://fx.gd")

var active := false
var dmg_mult := 1.0           # множитель урона (кастет из сейфа — 1.5)
var speed_mult := 1.0         # замедление (отравление наверху, gasmask.gd)
var weapon_id := ""           # оружие в правой руке (для совместимости; см. weapon_ids)
var weapon_ids: Array[String] = ["", ""]      # оружие в руках: 0 — левая, 1 — правая (weapons.gd)
var weapon_nodes: Array = [null, null]
var weapon_node: Node3D
# хват (подобрано по замерам в стойке): ось оружия = смесь осей кисти —
# сквозь кулак (мизинец→указательный), к костяшкам и к тыльной стороне. В стойке так выходит
# вверх с наклоном назад к плечу и наружу, рукоять уходит вниз из кулака.
var GRIP_THRU := 0.22
var GRIP_KNUCK := 0.5
var GRIP_BACK := 0.82
var ARMED_TWIST := 0.0
var GRIP_TILT := deg_to_rad(10.0)
var GRIP_OUT := 0.45                  # наклон оружия наружу (от ладони), чтобы не загораживало центр
var WEAPON_GRIP := Transform3D(Basis.IDENTITY, Vector3(0, 0.03, 0))   # запасной хват (модель без скелета)
# руки: левая — чаще крит, но урон чуть ниже; правая — полный урон, крит редкий
const HAND_DMG := [0.85, 1.0]
const HAND_CRIT := [0.25, 0.05]
const CRIT_MULT := 2.0
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
var wrist_flex: Array[float] = [0.0, 0.0]   # сгиб кисти в махе: оружие из «вверх» ложится вдоль руки
var swing_twist := 0.0                  # поворот корпуса в махе оружием (+ — правое плечо вперёд)
var last_swing := [-1, -1]
var fists := false
# --- модель с ригом ---
var skel: Skeleton3D
var rig_rel: Basis                 # поворот скелета относительно игрока (без масштаба)
var bone_map: Array = []          # [кость, узел-драйвер, опорный базис, рука (-1 — нет), кисть?]
var finger_bones: Array = []      # [кость, поворот расслабленной кисти, поворот в кулаке]
var spine_bone := -1
var clav_bones: Array[int] = [-1, -1]
var hands: Array[Node3D] = []     # драйверы кистей
var model_root: Node3D
var spine_bones: Array[int] = []  # spine01..03
var neck_bone := -1
# --- поворот тела за камерой: камера (сам игрок) поворачивается сразу, торс догоняет,
# ноги стоят и переступают, если угол стал большим ---
var yaw_init := false
var feet_yaw := 0.0               # куда смотрят ноги/таз (мировой угол)
var torso_yaw := 0.0              # куда смотрит грудь (мировой угол)
var foot_yaw: Array[float] = [0.0, 0.0]   # разворот стопы относительно таза
var turn_foot := -1               # какая нога сейчас переступает (-1 — никакая)
var turn_t := 0.0
var turn_steps := 0
var turn_hold := 0.0              # сколько времени ноги развёрнуты от взгляда
var turn_from_yaw := 0.0
var turn_to_yaw := 0.0
var turn_from_pos := Vector3.ZERO
var turn_from_fy := 0.0
var fist_blend := 0.0
# --- живая поза стоя (idle): дыхание, перенос веса, покачивание, редкие движения;
# в стойке с кулаками — пружинистое боксёрское покачивание ---
var idle_amt := 0.0               # 0 — идёт/прыгает, 1 — стоит
var idle_time := 0.0
var weight := 0.0                 # перенос веса: -1 — на левую ногу, +1 — на правую
var weight_to := 0.0
var weight_timer := 3.0
var hip_off := Vector3.ZERO       # смещение таза (оси ног), стопы стоят на месте
# --- присед: Ctrl — удерживать, C — переключить ---
const CROUCH_HIP := 0.34          # насколько опускается таз
const CROUCH_CAM := 0.5           # насколько опускается камера
const CROUCH_H := 1.15            # высота капсулы в приседе (стоя 1.8)
const CROUCH_SPEED := 0.45        # скорость ходьбы вприсядку относительно обычной
var crouched := false             # сейчас в приседе (цель)
var crouch_toggled := false
var crouch_hold_block := false    # Ctrl держат, но игрок встал (бег/прыжок) — ждём отпускания
var crouch := 0.0                 # плавный переход 0..1
var col_shape: CollisionShape3D
var col_cap: CapsuleShape3D
var idle_pitch: Array[float] = [0.0, 0.0]   # приподнятая пятка разгруженной ноги
var breath_ph := 0.0              # фаза дыхания (период плавает)
var fidget := ""                  # текущее случайное движение
var fidget_t := 0.0
var fidget_dur := 1.0
var fidget_side := 1.0
var fidget_timer := 5.0
var pelvis_bone := -1
var punching := false
var sprint_carry := 0.0   # 1 сразу после бега, плавно падает — от него зависит «занос»
var phase := 0.0
var bob := 0.0
var last_step := -1
var was_on_floor := true
var land_speed := 0.0

var steps: Array[AudioStreamWAV] = []
var whooshes: Array[AudioStreamWAV] = []
var heavy_whooshes: Array[AudioStreamWAV] = []   # мах тяжёлым оружием — ниже и дольше
var exhales: Array[AudioStreamWAV] = []
var impacts: Array[AudioStreamWAV] = []
var inhale_snd: AudioStreamWAV
var exhale_out_snd: AudioStreamWAV   # опускание рук — тот же вдох задом наперёд
var last_arm := -1
var aim_w: Array[float] = [0.0, 0.0]   # насколько рука в ударе следует за взглядом по вертикали
var head_bone := -1
var THUMB_CURL := [0.0, 0.0, 35.0, 40.0]
var last_kind := ""
var step_player: AudioStreamPlayer
var step_noise_player: AudioStreamPlayer
var step_noise: AudioStreamWAV
var scuff_noise: Array[AudioStreamWAV] = []   # шарканье при повороте на месте
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
	cam.near = 0.06
	cam.fov = fov_base
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
	model_root = model
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
			bone_map.append([skel.find_bone(e[0] + s), e[1], ref, arm, e[0] == "hand", e[0] in ["thigh", "calf", "foot"]])
		clav_bones[i] = skel.find_bone("clavicle" + s)
		# пальцы: ось сгиба — поперёк пальца, к ладони (ладонь в A-позе смотрит вниз, -Z скелета)
		_build_fist_pose(s)
		# точка кулака для следа и попаданий — на кости кисти
		var att := BoneAttachment3D.new()
		att.bone_name = "hand" + s
		skel.add_child(att)
		var fx := fist_fx[i]
		fx.get_parent().remove_child(fx)
		att.add_child(fx)
		fx.transform = Transform3D(Basis.from_scale(Vector3.ONE * 0.01), Vector3(0, 0.0008, 0))
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
	body_mi.skin = skin
	body_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Кулак для кисти s ("_L"/"_R"). Нормаль ладони — из геометрии кисти (поперёк костяшек × вдоль кисти),
## каждая фаланга сгибается вокруг оси «палец × нормаль». Большой палец нацеливается на уже сжатые
## средние фаланги указательного и среднего и ложится поперёк них снаружи.
func _build_fist_pose(s: String) -> void:
	var gr := func(n: String) -> Transform3D: return skel.get_bone_global_rest(skel.find_bone(n + s))
	var h: Vector3 = gr.call("hand").origin
	var across: Vector3 = (gr.call("index01").origin - gr.call("pinky01").origin).normalized()
	var along: Vector3 = (gr.call("middle01").origin - h).normalized()
	var n := across.cross(along).normalized()
	if n.dot(Vector3(0, 0, -1)) < 0.0:
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
	var tgt: Vector3 = mid + (mid - center).normalized() * 0.012 * unit
	# большой палец
	var t1 := skel.find_bone("thumb01" + s)
	if t1 == -1:
		return
	var g1 := skel.get_bone_global_rest(t1).basis.orthonormalized()
	var rest1 := skel.get_bone_rest(t1).basis.get_rotation_quaternion()
	var aim := Basis(Quaternion(g1.y.normalized(), (tgt - skel.get_bone_global_rest(t1).origin).normalized()))
	var fist1 := rest1 * (g1.inverse() * aim * g1).get_rotation_quaternion()
	finger_bones.append([t1, rest1.slerp(fist1, 0.15), fist1])
	for k in [2, 3]:
		var b := skel.find_bone("thumb%02d%s" % [k, s])
		if b == -1:
			continue
		var g := skel.get_bone_global_rest(b).basis.orthonormalized()
		# подушечка большого пальца смотрит вбок — гнём его поперёк кулака, к мизинцу
		var axis := (g.inverse() * g.y.normalized().cross(-across)).normalized()
		var rest_q := skel.get_bone_rest(b).basis.get_rotation_quaternion()
		finger_bones.append([b, rest_q * Quaternion(axis, deg_to_rad(8.0)), rest_q * Quaternion(axis, deg_to_rad(THUMB_CURL[k]))])


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
	model_root.position = leg_rot * (Vector3(0, 0, MODEL_Z) + _hip())
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
		_set_global_rot(pelvis_bone, rr * leg_rot * Basis(Vector3.UP, -idle_tw * 0.6)
				* Basis(Vector3.BACK, weight * (0.045 + 0.03 * (1.0 - fist_blend)) * idle_amt) * rest_p.call(pelvis_bone))
	var ck := _crouch_k()
	# в ударе корпус наклоняется туда, куда смотрит камера (вниз — вперёд, вверх — назад)
	var aim_bend := clampf(head.rotation.x, -1.2, 0.8) * maxf(aim_w[0], aim_w[1])
	# расслабленно: грудь чуть ссутулена, а не «грудь колесом»
	var spine_x := [sway_p * 0.5 - box * 0.05 - ck * 0.22 + aim_bend * 0.18 + 0.02 * rk,
			sway_p + breath * 0.012 - box * 0.08 - ck * 0.1 + aim_bend * 0.14 + 0.03 * rk,
			breath * 0.035 - box * 0.06 - bounce * 0.03 - ck * 0.04 + aim_bend * 0.1 + 0.035 * rk]
	var spine_z := [-weight * (0.03 + 0.03 * (1.0 - fist_blend)) * idle_amt + sway_r, sway_r - w_r * 0.025, sway_r * 0.5 - w_r * 0.015]
	# корпус доворачивается за бьющей рукой, ключица выносит плечо вперёд
	var twist := (reach[1] - reach[0]) * 2.2 + swing_twist
	var dt := torso_off - leg_off
	var spine_a := [leg_off + dt * 0.3 + swing_twist * 0.3 + idle_tw * 0.3, leg_off + dt * 0.65 + swing_twist * 0.6 + idle_tw * 0.7,
			torso_off + twist + idle_tw]
	for k in spine_bones.size():
		_set_global_rot(spine_bones[k], rr * Basis(Vector3.UP, spine_a[k]) * Basis(Vector3.RIGHT, spine_x[k])
				* Basis(Vector3.BACK, spine_z[k]) * rest_p.call(spine_bones[k]))
	if neck_bone != -1:
		# разминка шеи: наклон к плечу и поворот
		var nk := Basis.IDENTITY
		if fidget == "neck":
			nk = Basis(Vector3.UP, 0.35 * fidget_side * sin(TAU * fidget_t) * fk) * Basis(Vector3.BACK, 0.3 * fidget_side * fk)
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
		_set_global_rot(c, rr * Basis(Vector3.UP, torso_off + side * reach[i] * 2.5 + twist + idle_tw - side * back)
				* Basis(Vector3.BACK, side * up) * rest_p.call(c))
	var torso_rot := Basis(Vector3.UP, torso_off)
	for e in bone_map:
		var d: Node3D = e[1]
		var basis := (leg_rot if e[5] else torso_rot) * inv * d.global_basis.orthonormalized()
		var arm: int = e[3]
		if arm >= 0:
			# кисть поворачивается тыльной стороной вверх в стойке (у предплечья — половина)
			var side := -1.0 if arm == 0 else 1.0
			# с оружием (кроме щита) кисть остаётся большим пальцем вверх — молотковый хват, оружие стоит вертикально
			var armed_k := ARMED_TWIST if weapon_ids[arm] != "" and weapon_ids[arm] != "shield" else 1.0
			var tw := deg_to_rad(90.0) * side * (0.1 + 0.6 * fist_blend * armed_k) * (1.0 if e[4] else 0.5)
			basis = basis * Basis(Vector3.UP, tw)
		_set_global_rot(e[0], rr * basis * e[2])
	var wig := fk * idle_amt * (1.0 - fist_blend) if fidget == "fingers" else 0.0
	for n in finger_bones.size():
		var f: Array = finger_bones[n]
		# шевелит пальцами — каждый палец сгибается в своём ритме
		var b := clampf(fist_blend + wig * (0.22 + 0.22 * sin(idle_time * 13.0 + float(n) * 1.7)), 0.0, 1.0)
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
	# мышь, эмулированная из касаний (телефон), — обзор и удары там делает touch_controls.gd
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and captured:
		look(event.relative)
	elif event is InputEventMouseButton and event.pressed and not captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif captured and event.is_action_pressed("fists") and not event.is_echo():
		toggle_fists()
	elif captured and event.is_action_pressed("attack") and fists:
		punch()


## Чувствительность обзора (множитель из настроек меню) и скорость поворота стрелками, рад/с.
static var look_sens := 1.0
const KEY_TURN := 2.4

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


## Плавность приседа (ease in-out) — для таза, камеры и наклона.
func _crouch_k() -> float:
	return smoothstep(0.0, 1.0, crouch)


## Таз: перенос веса/покачивание стоя + опускание в приседе (чуть назад).
func _hip() -> Vector3:
	var ck := _crouch_k()
	return hip_off + Vector3(0, -CROUCH_HIP * ck, 0.05 * ck)


## Встать (по бегу или прыжку): переключатель снимаем, удержание Ctrl игнорируем до отпускания.
func _stand_request() -> void:
	crouch_toggled = false
	if Input.is_action_pressed("crouch"):
		crouch_hold_block = true


func _update_crouch(delta: float) -> void:
	if active and Input.is_action_just_pressed("crouch_toggle"):
		crouch_toggled = not crouch_toggled
	if active and Input.is_action_just_pressed("crouch"):
		crouch_hold_block = false
	if not Input.is_action_pressed("crouch"):
		crouch_hold_block = false
	var want := active and (crouch_toggled or (Input.is_action_pressed("crouch") and not crouch_hold_block))
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


func _key_look(delta: float) -> void:
	if not active:
		return
	var v := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if v == Vector2.ZERO:
		return
	rotate_y(-v.x * KEY_TURN * look_sens * delta)
	head.rotation.x = clampf(head.rotation.x - v.y * KEY_TURN * 0.7 * look_sens * delta, -1.5, 1.4)


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
	# оружие только в одной руке — чаще бьём им
	var armed0 := weapon_ids[0] != ""
	if armed0 != (weapon_ids[1] != "") and randf() < 0.75:
		i = 0 if armed0 else 1
	last_arm = i
	if weapon_ids[i] != "":
		_weapon_swing(i, weapon_ids[i])
		return
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
	var rs := _reach_setter(i)
	# хлёстко: короткий замах (плечо чуть назад) -> очень быстрый выброс с перелётом ->
	# короткая фиксация -> мягкий возврат
	var tw := create_tween()
	tw.tween_method(_pose_setter(i), arm_pose[i], keys[0], 0.06).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_method(rs, reach[i], -0.035, 0.06).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(_punch_sound)
	tw.tween_callback(_punch_fx.bind(i, kind, true))
	tw.tween_method(_pose_setter(i), keys[0], keys[1], 0.07).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(rs, -0.035, 0.15, 0.07).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_check_hit.bind(i, kind))
	tw.tween_interval(0.05)
	tw.tween_callback(_punch_fx.bind(i, kind, false))
	tw.tween_method(_pose_setter(i), keys[1], GUARDS[i], 0.24).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_method(rs, 0.15, 0.0, 0.24).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func(): punching = false)


func _reach_setter(i: int) -> Callable:
	return func(v: float) -> void: reach[i] = v


func _twist_setter(v: float) -> void:
	swing_twist = v


## Мах оружием: свой набор траекторий и таймингов для каждого типа, вариация случайная
## (прошлая повторяется реже).
func _weapon_swing(i: int, wid: String) -> void:
	var group := "heavy"
	if wid in ["machete", "knife", "shield"]:
		group = wid
	var set_: Array = SWINGS[group]
	var v := randi() % set_.size()
	if v == last_swing[i] and randf() < 0.65:
		v = (v + 1 + randi() % maxi(set_.size() - 1, 1)) % set_.size()
	last_swing[i] = v
	var sw: Dictionary = set_[v]
	var side := -1.0 if i == 0 else 1.0
	var t: Array = sw["t"]
	var tws: Array = sw["tw"]
	var rc: Array = sw["rc"]
	var heavy := group == "heavy" or group == "shield"
	var ps := _pose_setter(i)
	var rs := _reach_setter(i)
	# хлёст кистью: в замахе оружие взведено вверх, к удару кисть «выстреливает» и оружие продолжает руку
	var fl: Array = sw.get("wf", [-0.25, WRIST_HIT, WRIST_HIT * 1.1] if group != "shield" else [0.0, 0.0, 0.0])
	var fs := func(v: float) -> void: wrist_flex[i] = v
	var tw := create_tween()
	# замах — с разгоном и торможением в верхней точке
	tw.tween_method(ps, arm_pose[i], sw["wind"], t[0]).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_method(_twist_setter, swing_twist, tws[0] * side, t[0]).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_method(rs, reach[i], rc[0], t[0]).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_method(fs, wrist_flex[i], fl[0], t[0]).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(_swing_sound.bind(heavy))
	tw.tween_callback(_punch_fx.bind(i, sw["blur"], true))
	# удар: тяжёлое разгоняется (ease-in), лезвие срывается сразу (ease-out)
	var ez := Tween.EASE_IN if group == "heavy" else Tween.EASE_OUT
	var trans := Tween.TRANS_QUAD if group == "heavy" else Tween.TRANS_CUBIC
	tw.tween_method(ps, sw["wind"], sw["hit"], t[1]).set_trans(trans).set_ease(ez)
	tw.parallel().tween_method(_twist_setter, tws[0] * side, tws[1] * side, t[1]).set_trans(trans).set_ease(ez)
	tw.parallel().tween_method(rs, rc[0], rc[1], t[1]).set_trans(trans).set_ease(ez)
	tw.parallel().tween_method(fs, fl[0], fl[1], t[1]).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(_check_hit.bind(i, "hook"))
	# проводка по инерции и плавное торможение
	tw.tween_method(ps, sw["hit"], sw["thru"], t[2]).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(_twist_setter, tws[1] * side, tws[2] * side, t[2]).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(fs, fl[1], fl[2], t[2]).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_punch_fx.bind(i, sw["blur"], false))
	# возврат в стойку
	tw.tween_method(ps, sw["thru"], GUARDS[i], t[3]).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_method(_twist_setter, tws[2] * side, 0.0, t[3]).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_method(rs, rc[1], 0.0, t[3]).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_method(fs, fl[2], 0.0, t[3]).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func(): punching = false)


func _swing_sound(heavy: bool) -> void:
	_play(hit_player, heavy_whooshes if heavy else whooshes, -14.0 if heavy else -16.0)
	if not heavy:
		hit_player.pitch_scale = randf_range(1.1, 1.25)   # лезвие свистит выше
	_play(voice_player, exhales, -13.0 if heavy else -15.0)
	if heavy:
		voice_player.pitch_scale = randf_range(0.85, 0.95)


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
	var fp := _trail_point(i)
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
	var wid: String = weapon_ids[arm]
	var armed := wid != ""
	var reach_len: float = Weapons.WEAPONS[wid]["reach"] if armed else 1.0
	# взгляд вниз: удар идёт ниже и тело наклоняется — достаём до низких целей (ящики) и стоя
	reach_len *= 1.0 + 0.75 * clampf(-head.rotation.x, 0.0, 1.0)
	var hit := _hit_scan(from, reach_len)
	if hit:
		_play(hit_player, impacts, -11.0)
		# урон врагам/манекену (тестовые механики, см. game.gd): у цели должен быть take_hit(урон, направление)
		if hit.collider.has_method("take_hit"):
			var mult: float = Weapons.WEAPONS[wid]["mult"] if armed else dmg_mult
			var dmg: float = PUNCH_DMG.get(kind, 8.0) * mult * HAND_DMG[arm]
			# ящик кулаками ломается медленно (~10 ударов)
			if not armed and hit.collider is StaticBody3D and str(hit.collider.get("kind")) == "crate":
				dmg *= 0.45
			if randf() < HAND_CRIT[arm]:
				dmg *= CRIT_MULT
				Fx.popup_text(get_parent(), hit.position + Vector3(0, 0.35, 0), "КРИТ!", Color(1.0, 0.25, 0.15))
			hit.collider.take_hit(dmg, -cam.global_transform.basis.z)
		# лёгкая отдача в камеру
		# короткий «дёрг» камеры: крен в сторону руки и кивок, оружием — сильнее
		var k := 1.6 if armed else 1.0
		var side := -1.0 if arm == 0 else 1.0
		var tw := create_tween()
		tw.tween_property(cam, "rotation:z", 0.022 * side * k, 0.03).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(cam, "rotation:z", 0.0, 0.16).set_trans(Tween.TRANS_SINE)
		var tw2 := create_tween()
		tw2.tween_property(cam, "rotation:x", -0.014 * k, 0.03).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw2.tween_property(cam, "rotation:x", 0.0, 0.14).set_trans(Tween.TRANS_SINE)


## Надёжное попадание: лучи конусом по взгляду (центр, кольцо ~7° и ~15°, и пара ниже — для
## низких целей вроде ящиков). Цель с take_hit важнее стены; из целей — ближайшая к центру.
func _hit_scan(from: Vector3, reach_len: float) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var b := cam.global_transform.basis
	var dirs: Array[Vector3] = [-b.z]
	for ring in [[0.12, 8], [0.26, 8]]:
		for k in int(ring[1]):
			var a := TAU * float(k) / float(ring[1])
			dirs.append((-b.z + (b.x * cos(a) + b.y * sin(a)) * float(ring[0])).normalized())
	for dn in [0.45, 0.7]:
		dirs.append((-b.z - b.y * dn).normalized())
	var best := {}
	var best_score := INF
	var wall := {}
	for k in dirs.size():
		var q := PhysicsRayQueryParameters3D.create(from, from + dirs[k] * reach_len * (1.0 if k == 0 else 1.1))
		q.exclude = [get_rid()]
		q.collision_mask = 1
		var h := space.intersect_ray(q)
		if h.is_empty():
			continue
		if h.collider.has_method("take_hit"):
			var score := float(k) * 0.05 + from.distance_to(h.position)
			if score < best_score:
				best_score = score
				best = h
		elif k == 0:
			wall = h   # стена/пол — только если прямо по центру
	return best if not best.is_empty() else wall


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
		var n := (palm * 0.6 + fwd * 0.5 - up * 0.4).normalized()
		var y_ax := (fwd - n * fwd.dot(n)).normalized()
		var x_ax := y_ax.cross(n).normalized()
		var o := h - y_ax * 0.17 * unit + n * 0.06 * unit
		return Transform3D(Basis(x_ax * unit, y_ax * unit, n * unit), o)
	# рукоять — в «тоннеле» сжатых пальцев: ось от мизинца к указательному, наклон к костяшкам на GRIP_TILT.
	# Считаем в осях кости кисти (fist_fx лежит в них же, в метрах, на 8 см дальше по кисти).
	var hr := skel.get_bone_global_rest(hb)
	hr.basis = hr.basis.orthonormalized()
	var hinv := hr.affine_inverse()
	var to_m := 100.0                                 # единицы скелета -> метры (узел модели ×100)
	var lp := func(bone: String) -> Vector3: return hinv * skel.get_bone_global_rest(skel.find_bone(bone + s)).origin * to_m
	var idx: Vector3 = lp.call("index01")
	var pnk: Vector3 = lp.call("pinky01")
	var mid: Vector3 = lp.call("middle01")
	var across := (idx - pnk).normalized()            # к указательному — туда выходит оружие
	var knuck := (mid - across * mid.dot(across)).normalized()
	var n := across.cross(knuck).normalized()
	if n.z < 0.0:
		n = -n                                         # сторона ладони (туда сгибаются пальцы)
	var c := (idx + pnk) * 0.5 - knuck * 0.016 + n * 0.016 - Vector3(0, 0.08, 0)
	var d2 := (across * cos(GRIP_TILT) + knuck * sin(GRIP_TILT) - n * GRIP_OUT).normalized()
	var xw := (knuck - d2 * knuck.dot(d2)).normalized()   # лезвие ребром к костяшкам — по направлению удара
	var zw := xw.cross(d2).normalized()
	return Transform3D(Basis(xw * unit, d2 * unit, zw * unit), c * unit)


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
			var fp := _trail_point(i)
			if pts.is_empty() or (pts[-1] as Vector3).distance_to(fp) > 0.015:
				pts.append(fp)
				if pts.size() > (10 if weapon_ids[i] != "" else 7):
					pts.pop_front()
		else:
			trail_alpha[i] = maxf(trail_alpha[i] - delta * 7.0, 0.0)
		_draw_trail(i)


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


func _physics_process(delta: float) -> void:
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
	_update_idle(delta, spd, grounded)
	_animate_legs(delta, v_local, grounded)
	var amt := clampf(spd / WALK, 0.0, 1.5) if grounded else 0.0
	phase = gait * TAU * 2.0
	var box_ph := sin(idle_time * TAU * 1.8) * fist_blend * idle_amt
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var p: Vector4 = arm_pose[i]
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


func _play_step(db: float, _pitch := 1.0, turn := false) -> void:
	db -= 9.0 * crouch   # вприсядку шаги тише
	_randomize_step_eq()
	if turn:
		# переступание на месте при повороте: не топот, а тихое шарканье подошвой (−11 дБ, выше)
		step_noise_player.stream = scuff_noise[randi() % scuff_noise.size()]
		step_noise_player.volume_db = db + STEP_DB - 11.0
		step_noise_player.pitch_scale = randf_range(1.12, 1.25)
	elif _ground_kind() == "grass":
		step_noise_player.stream = grass_steps[randi() % grass_steps.size()]
		step_noise_player.volume_db = db + STEP_DB + 3.0
		step_noise_player.pitch_scale = randf_range(0.9, 1.1)
	else:
		step_noise_player.stream = step_noise
		step_noise_player.volume_db = db + STEP_DB
		step_noise_player.pitch_scale = 1.0
	step_noise_player.play()


## Шарканье подошвы: короткий мягкий шорох (полосовой шум, плавная атака, без удара).
static func _scuff(variant: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1200 + variant
	var n := int(Sfx.RATE * 0.16)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var dur := rng.randf_range(0.09, 0.13)
	for i in n:
		var t := float(i) / Sfx.RATE
		var w := rng.randf() * 2.0 - 1.0
		lp += (w - lp) * 0.5
		lp2 += (lp - lp2) * 0.08
		var band := lp - lp2                       # срезаем бас — без «туп»
		var env := sin(PI * clampf(t / dur, 0.0, 1.0))  # нарастает и спадает, без щелчка удара
		buf[i] = band * env * env * (0.8 + 0.2 * sin(t * 140.0))
	return Sfx._wav(buf, 0.5)


## Что под ногами: метка "ground" у коллайдера (трава поляны — "grass"), иначе бетон.
func _ground_kind() -> String:
	var from := global_position + Vector3(0, 0.3, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -0.9, 0))
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return ""
	return str(hit.collider.get_meta("ground", ""))
