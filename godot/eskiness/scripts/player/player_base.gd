extends CharacterBody3D
# Часть player.gd: константы, состояние, звук шагов, материалы.
const Sfx := preload("res://scripts/core/sfx.gd")
const Ambience := preload("res://scripts/core/ambience.gd")
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
const MODEL := preload("res://assets/models/Ch24_nonPBR.fbx")
const MODEL_Z := 0.12              # модель чуть позади камеры, чтобы лицо не лезло в кадр
var HIP_Y := 0.88
var LEG_L1 := 0.40              # бедро
var LEG_L2 := 0.40              # голень
var GROUND_Y := 0.09 - 0.88     # высота голеностопа над полом относительно бедра
var LEG_LIFT := 0.0             # модель поднята на столько, чтобы стоя ноги были прямые (промпт 16.11 02:36)
const ACCEL_WALK := 16.0     # с места до шага ~0.2 с (было 5 — разгон «плыл»)
const ACCEL_SPRINT := 10.0   # с шага до бега ~0.2 с
const DECEL_WALK := 40.0     # торможение линейное (м/с²): с шага стоп ~0.09 с
const DECEL_SPRINT := 30.0   # с бега ~0.18 с (~0.5 м)
const DECEL_TURN := 22.0     # смена направления / с бега на шаг

# позы руки в градусах: x — подъём плеча вперёд, y — внутрь, z — в сторону, w — сгиб локтя
const REST := Vector4(0, 0, 0, 10)
# стойка (промпты 03:30–03:38): плечи отведены от корпуса (локти наружу) и подняты вперёд, локоть открытый,
# кулаки ближе к центру; левая (ведущая) — дальше вперёд, правая — ближе к телу
const GUARDS: Array[Vector4] = [Vector4(66, 18, 30, 56), Vector4(50, 16, 32, 72)]
const PUNCHES := {
	"straight": [Vector4(55, 14, 2, 80), Vector4(100, 6, 0, 4)],
	"hook": [Vector4(82, -30, 8, 40), Vector4(96, 32, 0, 28)],
	"upper": [Vector4(45, 12, 6, 100), Vector4(95, 12, 0, 58)],
}
# кулаки сильно ослаблены (было 18/24/30): без оружия враг падает с ~9 ударов
const PUNCH_DMG := {"straight": 6.0, "hook": 8.0, "upper": 10.0}
const Weapons := preload("res://scripts/weapons.gd")
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
	"pistol": [   # удар рукоятью (промпт 16.11 02:04): короткий рубящий сверху или тычок вперёд
		{"wind": Vector4(128, -8, 22, 112), "hit": Vector4(70, 10, 0, 22), "thru": Vector4(50, 26, 0, 34),
			"tw": [-0.25, 0.2, 0.3], "t": [0.11, 0.07, 0.07, 0.22], "rc": [-0.02, 0.07], "wf": [-0.4, 0.9, 1.0], "blur": "upper"},
		{"wind": Vector4(56, 10, 0, 104), "hit": Vector4(94, 8, 0, 8), "thru": Vector4(96, 8, 0, 6),
			"tw": [-0.12, 0.2, 0.22], "t": [0.07, 0.06, 0.05, 0.2], "rc": [-0.04, 0.15], "wf": [0.0, 0.5, 0.55], "blur": "straight"},
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
const WEAPON_TIP := {"bat": 0.67, "pipe": 0.63, "crowbar": 0.62, "machete": 0.52, "knife": 0.25, "shield": 0.28, "pistol": 0.12, "stone": 0.05}
const Fx := preload("res://scripts/core/fx.gd")

var active := false
var carrying := false   # несёт объект в руках (world/carry.gd): без ударов, бега и прыжков
## Сетевая игра (net.gd): модель другого игрока — без камеры, ввода, звуков и урона; движется по данным из сети.
var puppet := false
var net_hit: Callable    # сеть: удар/пуля по этой модели чужого игрока → net.gd (огонь по своим)
var net_push: Callable   # сеть: мягкое расталкивание с другими игроками (net.gd), до move_and_slide
var net_pos := Vector3.ZERO
var net_yaw := 0.0
var net_pitch := 0.0
var net_vel := Vector3.ZERO
var net_crouch := false
var net_sprint := false
var dmg_mult := 1.0           # множитель урона (кастет из сейфа — 1.5)
var speed_mult := 1.0         # замедление (отравление наверху, gasmask.gd)
var weapon_id := ""           # оружие в правой руке (для совместимости; см. weapon_ids)
var weapon_ids: Array[String] = ["", ""]      # оружие в руках: 0 — левая, 1 — правая (weapons.gd)
var weapon_nodes: Array = [null, null]
var skel_m := 100.0   # метров в единице скелета модели (player_model.gd)
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
var finger_arm: Array[int] = []   # чья это кость пальца: 0 — левая рука, 1 — правая
var finger_thumb: Array[bool] = [] # это кость большого пальца
var spine_bone := -1
var clav_bones: Array[int] = [-1, -1]
var hands: Array[Node3D] = []     # драйверы кистей
var model_root: Node3D
var spine_bones: Array[int] = []  # spine01..03
var neck_bone := -1
var head_mi: MeshInstance3D      # видимый меш тела (голова схлопнута для вида из глаз)
var head_shadow: MeshInstance3D  # копия с головой — только тень
var head_skin_full: Skin
var head_skin_cut: Skin
var head_parts: Array = []        # голова/шея простой модели (только тень)
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
var air_t := 0.0   # сколько секунд не на полу: у стены is_on_floor мигает — короткие «отрывы» не считаем полётом (промпт 23:34)
var land_speed := 0.0

var steps: Array[AudioStreamWAV] = []
var whooshes: Array[AudioStreamWAV] = []
var heavy_whooshes: Array[AudioStreamWAV] = []   # мах тяжёлым оружием — ниже и дольше
var exhales: Array[AudioStreamWAV] = []
var impacts: Array[AudioStreamWAV] = []
var inhale_snd: AudioStreamWAV
var exhale_out_snd: AudioStreamWAV   # опускание рук — тот же вдох задом наперёд
var last_arm := -1
var gun   # gun.gd (ставит game.gd)
# позы с пистолетом (промпт 16.11 02:02, player_anim.gd: _gun_pose): 0 — опущен, 1 — от бедра (ПКМ держат), 2 — прицел.
# Своему ставит gun.gd, чужому — сеть (net_world.gd, флаги 8/16).
var gun_mode := 0
var gun_hip_w := 0.0
var gun_ads_w := 0.0
# перезарядка (промпт 16.11 02:37): gun.gd ставит фазу 0..1 (-1 — нет) и руку с пистолетом; вторая рука вставляет магазин и досылает затвор
var gun_rel_k := -1.0
var gun_rel_h := 1
var gun_rel_w := 0.0
var stone_throw   # stone_throw.gd (ставит game.gd)
var throw_aim := false   # камень в руке, ПКМ держат — замах (своему ставит stone_throw.gd, чужому — сеть, флаг 32)
var throw_w := 0.0
var throw_flick := 0.0   # 1 → 0 после броска: рука выбрасывается вперёд
var _whip_lmb := false   # ЛКМ с пистолетом без ПКМ — удар рукоятью рукой с пистолетом (player_combat.gd)
var game   # game.gd (ставит game.gd): пока открыто окно — клик не захватывает мышь
var aim_w: Array[float] = [0.0, 0.0]   # насколько рука в ударе следует за взглядом по вертикали
var head_bone := -1
var THUMB_CURL := [0.0, 0.0, 22.0, 26.0]   # промпт 03:38: меньше — кончик не уходит в пальцы; обхватывает кулак поперёк, поверх пальцев (цель — снаружи средних фаланг)
var last_kind := ""
var step_player: AudioStreamPlayer
var step_noise_player: AudioStreamPlayer
var step_noise: AudioStreamWAV
var scuff_noise: Array[AudioStreamWAV] = []   # шарканье при повороте на месте
var grass_steps: Array[AudioStreamWAV] = []   # шаги по траве (поверхность)
var gravel_steps: Array[AudioStreamWAV] = []  # шаги по земле/гравию/асфальту снаружи
var step_eq: AudioEffectEQ6
var voice_player: AudioStreamPlayer
var hit_player: AudioStreamPlayer
var step_idx := 0


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


## Чувствительность обзора (множитель из настроек меню) и скорость поворота стрелками, рад/с.
static var look_sens := 1.0
const KEY_TURN := 2.4


@warning_ignore("unused_private_class_variable")
var _queued_arm := -1

# ---------- заряженный удар (промпт 14.11 19:06) ----------
## Зажал ЛКМ/ПКМ — рука отводится назад и копит заряд до CHARGE_MAX с; отпустил — удар.
## Урон без случайности: база × (0.6 + 0.6·з + 0.4·з²) — клик ×0.6, половина заряда ×1.0 (прежний урон оружия,
## промпт 19:15), полный ×1.6.
## Отдача врага считается от урона (enemy.gd) — тоже растёт. Полоска заряда — над хотбаром (_charge_draw).
const CHARGE_MAX := 1.5
const CHARGE_GAIN := 1.5
const TAP_T := 0.12            # короче — обычный удар без заряда
const PUNCH_BASE := 8.0        # урон кулака (вид удара на урон больше не влияет)
var charging := -1             # какая рука копит заряд (-1 — никакая)
var charge_t := 0.0            # сколько копит (с), считается только с поднятыми кулаками
var strike_charge := 0.0       # заряд удара, который сейчас летит (0..1) — для _check_hit
var charge_ui: Control
var charge_ui_a := 0.0         # прозрачность полоски (плавно появляется и гаснет)
var charge_ui_k := 0.0         # что показывает полоска (0..1)
var charge_vis := 0.0          # сколько заряда видно в позе рук (плавно догоняет заряд, после удара плавно уходит)
var charge_arm := -1           # какая рука заряжает (для позы); вторая — раскрытая ладонь впереди
## Поза при полном заряде (добавка к стойке, градусы как у GUARDS: подъём, внутрь, в сторону, локоть).
const CHARGE_POSE := Vector4(-6, -6, 7, 11)       # рука удара: отведена назад-вниз и в сторону, локоть чуть согнут (в кадре — у правого нижнего края)
const CHARGE_OTHER := Vector4(16, -6, 4, -30)      # вторая рука: вперёд и чуть в сторону, локоть почти разогнут


func _play(p: AudioStreamPlayer, set_: Array, db: float) -> void:
	if puppet:
		return
	p.stream = set_[randi() % set_.size()]
	p.volume_db = db + randf_range(-1.5, 1.5)
	p.pitch_scale = randf_range(0.92, 1.08)
	p.play()


func _play_step(db: float, _pitch := 1.0, turn := false) -> void:
	if puppet:
		return
	db -= 9.0 * crouch   # вприсядку шаги тише
	_randomize_step_eq()
	var kind := "" if turn else _ground_kind()
	if turn:
		# переступание на месте при повороте: не топот, а тихое шарканье подошвой (−11 дБ, выше)
		step_noise_player.stream = scuff_noise[randi() % scuff_noise.size()]
		step_noise_player.volume_db = db + STEP_DB - 11.0
		step_noise_player.pitch_scale = randf_range(1.12, 1.25)
	elif kind == "grass":
		step_noise_player.stream = grass_steps[randi() % grass_steps.size()]
		step_noise_player.volume_db = db + STEP_DB + 3.0
		step_noise_player.pitch_scale = randf_range(0.9, 1.1)
	elif Ambience.out_k > 0.5 and kind != "concrete":
		# снаружи под ногами не бетон бункера, а земля/гравий/асфальт (промпт 17.11 02:50)
		if gravel_steps.is_empty():
			for i in 4:
				gravel_steps.append(_gravel(i))
		step_noise_player.stream = gravel_steps[randi() % gravel_steps.size()]
		step_noise_player.volume_db = db + STEP_DB + 1.0
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


## Шаг по земле с гравием: глухой мягкий «туп» + россыпь коротких щелчков камешков (хруст).
static func _gravel(variant: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1400 + variant
	var n := int(Sfx.RATE * 0.3)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp1 := 0.0
	var lp2 := 0.0
	var hp := 0.0
	var crunch := 0.0
	var dur := rng.randf_range(0.14, 0.2)
	for i in n:
		var t := float(i) / Sfx.RATE
		var w := rng.randf() * 2.0 - 1.0
		lp1 += (w - lp1) * 0.06
		lp2 += (lp1 - lp2) * 0.06
		var thud := lp2 * 5.0 * minf(t / 0.006, 1.0) * exp(-t * 32.0)
		# камешки: редкие импульсы, гуще в начале шага, затухают к перекату стопы
		var dens := 0.02 * exp(-t / dur * 2.2)
		if rng.randf() < dens:
			crunch = rng.randf_range(0.4, 1.0) * (1.0 if rng.randf() < 0.5 else -1.0)
		crunch *= 0.86
		hp += (w - hp) * 0.35
		var grit := (w - hp) * crunch
		var hiss := (w - hp) * 0.08 * exp(-t / dur * 3.0)
		buf[i] = thud + grit * 0.9 + hiss
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
