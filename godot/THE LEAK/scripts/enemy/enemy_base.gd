extends CharacterBody3D
# Часть enemy.gd: константы, состояние, звуки, примитивы мешей.
@warning_ignore("unused_signal")
const _D_ENEMY := preload("res://data/enemies/enemy.tres")   # настройки — правятся в Инспекторе
signal died(enemy: Node)

const Fx := preload("res://scripts/core/fx.gd")
const Gibs := preload("res://scripts/world/gibs.gd")
const Surface := preload("res://scripts/locations/bunker/surface.gd")

static var SPEED: float = _D_ENEMY.speed
static var SIGHT: float = _D_ENEMY.sight
## Чувства (промпт 16.11 21:54): видит в конусе ±FOV_DEG на SIGHT м, сквозь стены — нет; вприсядку игрока
## видно с SIGHT_CROUCH доли расстояния; ближе NEAR_FEEL замечает в любую сторону. Слышит в радиусе шума
## игрока (player_base.gd noise_r), через стену — вдвое ближе. Потерял — идёт туда, где видел/слышал
## последний раз (last_known), озирается и уходит. Шум издалека — идёт проверить (investigate).
static var FOV_DEG: float = _D_ENEMY.fov_deg
static var SIGHT_CROUCH: float = _D_ENEMY.sight_crouch   # было 0.55 (промпт 18.11 01:06: больше стелса)
static var NEAR_FEEL: float = _D_ENEMY.near_feel
static var NEAR_FEEL_CROUCH: float = _D_ENEMY.near_feel_crouch   # вприсядку сзади/сбоку замечает только вплотную
## Стелс (промпт 18.11 01:06): заметить — не мгновенно, копится подозрение (suspicion 0..1, над головой «?»/«!»):
## чем ближе и чем светлее (фонарик), тем быстрее. Спокойного врага со спины — урон ×BACKSTAB, вприсядку — насмерть.
static var NOTICE_NEAR: float = _D_ENEMY.notice_near   # с за сколько секунд замечает вплотную
static var NOTICE_FAR: float = _D_ENEMY.notice_far   # … и на краю дальности зрения
static var BACKSTAB: float = _D_ENEMY.backstab
var suspicion := 0.0
var sus_label: Label3D
static var MEM_T: float = _D_ENEMY.memory_time
static var ATTACK_RANGE: float = _D_ENEMY.attack_range
static var HIT_RANGE: float = _D_ENEMY.hit_range
static var DAMAGE: float = _D_ENEMY.damage   # было 12 (промпт 19:15: сильнее и крепче, +35%)
static var MAX_HP: float = _D_ENEMY.max_hp   # было 70
static var LEASH: float = _D_ENEMY.leash
static var WANDER_SPEED: float = _D_ENEMY.wander_speed
## проёмы бункера (level.gd: DOOR_W 1.7, DOOR_H 2.3): [центр, нормаль стены]. Через них враг проходит по оси —
## сначала выходит на центр проёма со своей стороны, потом насквозь, не трётся о косяки (промпт 14.11 20:07)
static var DOORS: Array = _D_ENEMY.doors
static var DOOR_HALF: float = _D_ENEMY.door_half
## точки пути по бункеру: коридор, обе стороны каждого проёма, середины комнат, выход к лестнице.
## Между ними ищется кратчайший путь (связи — где точки видят друг друга), так враг находит дорогу в любую комнату.
static var WAYPOINTS: Array = _D_ENEMY.waypoints
@warning_ignore("unused_private_class_variable")
static var _wp_links: Array = []    # для каждой точки — индексы видимых соседей (считаются один раз)

var game  # game.gd
## Цель: game (локальный игрок) или сетевой игрок (net.gd: RemoteTarget) — у обоих есть player, alive, damage_player.
## В сети враги думают только на хосте и выбирают ближайшего живого игрока (game.net.pick_target).
var tg
var net_puppet := false   # клиент сетевой игры: враг — копия вражеского на хосте (позиция, состояние, HP по сети)
var net_pos := Vector3.ZERO
var net_rot := 0.0
var kind := "heavy"   # "heavy" | "fast" — выставить до add_child
## параметры вида (из _apply_kind): скорость погони, дистанции, урон, здоровье, замах, перезарядка, рост
var speed := SPEED
var attack_range := ATTACK_RANGE
var hit_range := HIT_RANGE
var damage := DAMAGE
var max_hp := MAX_HP
var windup_t := 0.55
var cool_t := 1.1
var height := 2.0
var dash_ph := 0.0    # быстрый: фаза рывка (рывок — пауза)
# --- ум и абилки (промпт 19:15) ---
static var ABILITY_CD: float = _D_ENEMY.ability_cd
static var LEAP_DMG: float = _D_ENEMY.leap_dmg   # Шныга: прыжок на игрока
static var ROCK_DMG: float = _D_ENEMY.rock_dmg   # бетонник: брошенный камень
var ability_cd := 0.0
var leap_vel := Vector3.ZERO
var leap_hit := false
var thrown := false
var avoid_angle := 0.0     # обход препятствия: текущий угол отворота
var avoid_on := false      # сейчас обходим (сторона выбрана)
var avoid_clear := 0.0     # сколько путь уже свободен
var avoid_side := 1.0
var stuck_t := 0.0
var stuck_pos := Vector3.ZERO
var in_door := false       # сейчас проходит проём (_through_door) — без «усов», по оси
var throw_vel := Vector3.ZERO
var last_known := Vector3.ZERO   # где последний раз видел / слышал игрока (погоня по памяти)
var mem_t := 0.0                 # сколько уже не чувствует игрока в погоне
var probe := Vector3.ZERO  # камень игрока упал здесь — идёт проверить (hear_stone)
var probe_wait := 0.0
@warning_ignore("unused_private_class_variable")
static var _screech_cache: Array = []
@warning_ignore("unused_private_class_variable")
static var _front_id := 0   # кто из врагов сейчас атакует игрока спереди (окружение)
var home := Vector3.ZERO
var drop_only: Array = []   # если задано — при смерти выпадают ровно эти предметы (вступление: сухарь и вода)
var crawl_stop := 0.0       # заблудший (intro.gd): через столько секунд ползания останавливается (0 — нет)
var crawl_t := 0.0
var crawl_wait := false     # заблудший до кат-сцены (intro.gd): копошится на месте, игрока не замечает
var calm := false           # до конца кат-сцены (intro.gd): не агрится ни на что и неуязвим
var crawl_speed := 0.6      # скорость ползания (intro.gd)
var spawn_rise := false   # выставить до add_child: появляется анимацией подъёма из пола (state "rise")
var rise_thud := false
static var RISE_FADE: float = _D_ENEMY.rise_fade   # проявление
static var RISE_UP: float = _D_ENEMY.rise_up   # всплыл грудью вверх
static var RISE_DROP: float = _D_ENEMY.rise_drop   # резко встал на ноги
static var RISE_T: float = _D_ENEMY.rise_time
var hunter := false   # всегда гонится, спускается в бункер
var hp := MAX_HP   # выставляет _apply_kind
var state := "idle"
var st := 0.0
var knock := Vector3.ZERO
var walk_ph := 0.0
var walk_amt := 0.0
var cool := 0.0
var think := 0.0
var target := Vector3.ZERO
var growl_t := 3.0
var bar_t := 0.0
## на поверхности: бродит по поляне, гонится напрямую (без проёмов), в будку-выход не заходит
var surface := false
## агро: враг с поляны, заметивший игрока, идёт за ним и в будку, и вниз по лестнице в бункер —
## сейвзоны нет. Потерял из виду на LOSE_T секунд — поднимается обратно на поляну (состояние "return").
static var LOSE_T: float = _D_ENEMY.lose_time
static var CHASE_MAX: float = _D_ENEMY.chase_max   # дольше этого без вида игрока — точно сдаётся
var lost_t := 0.0
var blind_t := 0.0
var wander_t := 0.0

var vis: Node3D
var torso: Node3D
var arms: Array[Node3D] = []
var legs: Array[Node3D] = []
var mat: StandardMaterial3D
var bar: Node3D
var bar_fg: MeshInstance3D
var voice: AudioStreamPlayer3D
var body_snd: AudioStreamPlayer3D


func _bar_quad(col: Color, size: Vector2, z: float) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	q.center_offset = Vector3(0, 0, z)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.albedo_color = col
	q.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bar.add_child(mi)
	return mi


func _part(parent: Node3D, mesh: Mesh, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func _set_state(s: String) -> void:
	if state == "rise" and s not in ["idle", "dead"]:
		return   # пока встаёт из пола — не отвлекается
	if s == "chase" and state in ["idle", "return", "investigate", "crawl"] and tg != null and tg.player != null:
		last_known = tg.player.global_position   # заметил / ударили — знает, где игрок
		mem_t = 0.0
	state = s
	st = 0.0


## Шаги врага (промпт 14.11 17:26): тяжёлые, ниже по тону, чем у игрока; шаг — каждые ~0.7 м пройденного пути.
@warning_ignore("unused_private_class_variable")
var _step_dist := 0.0
var vis_step := 0.0   # модель догоняет тело на ступеньках (enemy.gd, core/step_up.gd)
@warning_ignore("unused_private_class_variable")
var _last_ph_step := 0


## Визг быстрого: резкий высокий скрежещущий крик с дрожью и срывом тона вверх (процедурный).
static func _screech(variant: int) -> AudioStreamWAV:
	const Sfx := preload("res://scripts/core/sfx.gd")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1800 + variant
	var dur := rng.randf_range(0.45, 0.7)
	var n := int(Sfx.RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var f0 := rng.randf_range(520.0, 680.0)
	var bp := Sfx.Svf.new(rng.randf_range(2200.0, 2900.0), 2.0)
	var bp2 := Sfx.Svf.new(rng.randf_range(1100.0, 1400.0), 1.5)
	var ph := 0.0
	for i in n:
		var t := float(i) / Sfx.RATE
		var k := t / dur
		var w := rng.randf() * 2.0 - 1.0
		# тон: рывок вверх в начале, дрожь 28–35 Гц, к концу срывается вниз
		var f := f0 * (1.0 + 0.6 * smoothstep(0.0, 0.15, k) - 0.35 * smoothstep(0.6, 1.0, k)) * (1.0 + 0.06 * sin(TAU * 31.0 * t + variant))
		ph = fmod(ph + f / Sfx.RATE, 1.0)
		var x := (ph * 2.0 - 1.0) * 0.7 + w * 0.35 * (0.5 + 0.5 * sin(TAU * 47.0 * t))
		var env := smoothstep(0.0, 0.03, t) * (1.0 - smoothstep(dur * 0.55, dur, t))
		buf[i] = (bp.bp(x) * 0.8 + bp2.bp(x) * 0.5 + x * 0.15) * env
	return Sfx._wav(buf, 0.7)


func _play(p: AudioStreamPlayer3D, set_: Array, db: float, pitch := 1.0) -> void:
	p.stream = set_[randi() % set_.size()]
	p.volume_db = db
	p.pitch_scale = pitch * randf_range(0.95, 1.05)
	p.play()
