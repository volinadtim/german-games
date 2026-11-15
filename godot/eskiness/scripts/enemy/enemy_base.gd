extends CharacterBody3D
# Часть enemy.gd: константы, состояние, звуки, примитивы мешей.
@warning_ignore("unused_signal")
signal died(enemy: Node)

const Fx := preload("res://scripts/core/fx.gd")
const Surface := preload("res://scripts/level/surface.gd")

const SPEED := 2.1
const SIGHT := 9.0
const ATTACK_RANGE := 1.35
const HIT_RANGE := 1.8
const DAMAGE := 16.0       # было 12 (промпт 19:15: сильнее и крепче, +35%)
const MAX_HP := 95.0       # было 70
const LEASH := 14.0
const WANDER_SPEED := 0.85
## проёмы бункера (level.gd: DOOR_W 1.7, DOOR_H 2.3): [центр, нормаль стены]. Через них враг проходит по оси —
## сначала выходит на центр проёма со своей стороны, потом насквозь, не трётся о косяки (промпт 14.11 20:07)
const DOORS := [
	[Vector3(-6, 0, -1.6), Vector3(0, 0, 1)], [Vector3(-6, 0, 1.6), Vector3(0, 0, 1)],
	[Vector3(6, 0, -1.6), Vector3(0, 0, 1)], [Vector3(6, 0, 1.6), Vector3(0, 0, 1)],
	[Vector3(0, 0, 5.5), Vector3(1, 0, 0)], [Vector3(12, 0, 0), Vector3(1, 0, 0)],
]
const DOOR_HALF := 0.85
## точки пути по бункеру: коридор, обе стороны каждого проёма, середины комнат, выход к лестнице.
## Между ними ищется кратчайший путь (связи — где точки видят друг друга), так враг находит дорогу в любую комнату.
const WAYPOINTS := [
	Vector3(-10.5, 0, 0), Vector3(-6, 0, 0), Vector3(0, 0, 0), Vector3(6, 0, 0), Vector3(11.3, 0, 0),
	Vector3(-6, 0, -0.9), Vector3(-6, 0, -2.4), Vector3(6, 0, -0.9), Vector3(6, 0, -2.4),
	Vector3(-6, 0, 0.9), Vector3(-6, 0, 2.4), Vector3(6, 0, 0.9), Vector3(6, 0, 2.4),
	Vector3(-0.9, 0, 5.5), Vector3(0.9, 0, 5.5),
	Vector3(-6, 0, -5.3), Vector3(6, 0, -5.3), Vector3(-6, 0, 5.3), Vector3(6, 0, 5.3),
]
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
const ABILITY_CD := 12.0
const LEAP_DMG := 11.0     # Шныга: прыжок на игрока
const ROCK_DMG := 13.0     # бетонник: брошенный камень
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
var probe := Vector3.ZERO  # камень игрока упал здесь — идёт проверить (hear_stone)
var probe_wait := 0.0
@warning_ignore("unused_private_class_variable")
static var _screech_cache: Array = []
@warning_ignore("unused_private_class_variable")
static var _front_id := 0   # кто из врагов сейчас атакует игрока спереди (окружение)
var home := Vector3.ZERO
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
const LOSE_T := 8.0
const CHASE_MAX := 45.0     # дольше этого без вида игрока — точно сдаётся
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
	state = s
	st = 0.0


## Шаги врага (промпт 14.11 17:26): тяжёлые, ниже по тону, чем у игрока; шаг — каждые ~0.7 м пройденного пути.
@warning_ignore("unused_private_class_variable")
var _step_dist := 0.0
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
