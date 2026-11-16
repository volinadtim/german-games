extends Node
## Начало новой игры (промпт 16.11 03:13). Только новая игра / новый сейв; в сети — только у хоста.
##   1. Игрок просыпается полулёжа у западной стены северо-западной комнаты, рядом битое стекло
##      и разбитая бутылка; веки моргают, он садится и встаёт (камера — без управления).
##   2. Почти дошёл до проёма в коридор — короткая сцена: камера сама поворачивается, из-за угла
##      выползает заблудший мелкий монстрик («Шныга», половина здоровья) и ползёт прочь по коридору.
##      Единственная подсказка эпизода — «Красться — C». Добить его — сзади на E (world/takedown.gd).
##   3. Монстрик умер — по коридору эхом звенит игровой автомат, камера плавно поворачивается
##      в сторону комнаты с KILLBOX, потом управление полностью возвращается.
const Enemy := preload("res://scripts/enemy/enemy.gd")
const Sfx := preload("res://scripts/core/sfx.gd")
const SlotM := preload("res://scripts/slot/slot_machine.gd")
const WAKE_POS := Vector3(-11.25, 0.05, -4.3)   # у западной стены; game_base.gd CHEST_AVOID и glass_floor.gd AVOID обходят это место

const DOOR := Vector3(-6.0, 0.0, -1.6)          # проём из северо-западной комнаты в коридор
const TRIGGER_R := 2.3                          # «почти подошёл к выходу»
const CRAWL_FROM := Vector3(-7.4, 0.0, 0.35)    # из-за угла коридора; заворачивает в комнату KILLBOX (промпт 16.11 03:49)
const SIDE_CAM := Vector3(-4.6, 1.8, -8.4)       # ракурс — из той же комнаты, с противоположной стороны, через проём (промпт 16.11 03:48)
const SIDE_T := 3.0                              # потом за 1.2 с камера плавно возвращается в глаза
# по коридору к проёму комнаты с автоматом (x = -6, z = 1.6), по оси проёма внутрь; конец пути — стоп (~4 с)
const CRAWL_PATH := [Vector3(-6.15, 0, 0.6), Vector3(-6.0, 0, 1.6), Vector3(-6.0, 0, 2.9)]
const CRAWL_SPEED := 0.85
const WAKE_T := 7.6
const CUT_T := 4.2
const CUE_T := 3.0

var game
var stage := "wake"     # wake → free → cut → hunt → cue_wait → cue → конец
var t := 0.0
var crawler: Node3D
var cut_cam: Camera3D
var layer: CanvasLayer
var fade: ColorRect
var hint: Label
var hint_t := 0.0
var crouch_t := 0.0
var hidden: Array = []
var echo_snd: AudioStreamWAV
var groaned := false
var stood := false


func start() -> void:
	var p = game.player
	p.global_position = WAKE_POS
	p.rotation.y = -PI / 2.0          # лицом в комнату (+X)
	p.head.rotation.x = 0.0
	_lock(true)
	# тело не показываем, пока камера «лежит» у пола (иначе видно модель изнутри)
	for c in p.get_children():
		if c is Node3D and c != p.head and not c is CollisionShape3D and (c as Node3D).visible:
			(c as Node3D).visible = false
			hidden.append(c)
	layer = CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 1)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(fade)
	_decor()
	echo_snd = _slot_echo()
	game.intro_done = false
	if game.slot and is_instance_valid(game.slot):
		game.slot.set_powered(false)   # KILLBOX выключен до убийства монстрика
	_wake_pose(0.0)


func _lock(on: bool) -> void:
	var p = game.player
	p.active = not on
	game.inv.enabled = not on
	game.hud.set_cinematic(on)
	if not on:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	if game == null or not is_instance_valid(game.player):
		queue_free()
		return
	t += delta
	var p = game.player
	if stage != "wake" and not game.alive:
		_finish()
		return
	_hint_tick(delta)
	match stage:
		"wake":
			_wake_pose(t)
			if t > 1.7 and not groaned:
				groaned = true
				if not p.exhales.is_empty():
					p.voice_player.stream = p.exhales[0]
					p.voice_player.volume_db = -24.0
					p.voice_player.pitch_scale = 0.82
					p.voice_player.play()
			if t > 7.1 and not stood:
				stood = true
				p._play_step(-22.0)
			if t >= WAKE_T:
				_wake_pose(WAKE_T)
				for c in hidden:
					if is_instance_valid(c):
						(c as Node3D).visible = true
				hidden.clear()
				fade.visible = false
				_lock(false)
				stage = "free"
		"free":
			var pp: Vector3 = p.global_position
			if Vector2(pp.x - DOOR.x, pp.z - DOOR.z).length() < TRIGGER_R or pp.z > DOOR.z:
				_begin_cut()
		"cut":
			if is_instance_valid(crawler):
				_aim(crawler.global_position + Vector3(0, 0.45, 0), 1.0 - exp(-3.0 * delta))
				var side := Transform3D(Basis(), SIDE_CAM).looking_at(crawler.global_position + Vector3(0, 0.4, 0))
				var kb := smoothstep(SIDE_T, CUT_T - 0.05, t)
				cut_cam.global_transform = side.interpolate_with(p.cam.global_transform, kb)
				p.set_head_visible(kb < 0.8)   # голова видна, пока камера снаружи
			if t >= CUT_T:
				_end_side_cam()
				_lock(false)
				_show_hint()
				stage = "hunt"
		"hunt":
			if not is_instance_valid(crawler):
				_finish()
			elif String(crawler.get("state")) == "dead":
				_on_crawler_died(crawler)   # подстраховка, если сигнал died не дошёл
		"cue_wait":
			if t >= 0.1:   # сразу после убийства (промпт 16.11 03:39)
				game.intro_done = true
				if game.slot and is_instance_valid(game.slot):
					game.slot.set_powered(true, true)   # KILLBOX загорается со звуком
				_play_echo()
				p.active = false
				game.inv.enabled = false
				t = 0.0
				stage = "cue"
		"cue":
			var at := Vector3(-6.0, 1.4, 8.5)
			if game.slot and is_instance_valid(game.slot):
				at = game.slot.global_position + Vector3(0, 1.4, 0)
			_aim(at, 1.0 - exp(-2.2 * delta))
			if t >= CUE_T:
				p.active = true
				game.inv.enabled = true
				_finish()


## Поза «просыпается»: камера у пола, голова завалена набок → садится → встаёт; веки моргают (fade).
func _wake_pose(tt: float) -> void:
	var p = game.player
	var poses := [
		[Vector3(0, -1.08, 0.42), Vector3(-0.42, 0.28, 0.24)],   # полулёжа, голова к плечу
		[Vector3(0, -1.04, 0.40), Vector3(-0.3, -0.18, 0.16)],   # огляделся
		[Vector3(0, -0.78, 0.22), Vector3(-0.08, 0.0, 0.07)],    # сел
		[Vector3.ZERO, Vector3.ZERO],                            # встал
	]
	var k1 := smoothstep(3.4, 4.6, tt)
	var k2 := smoothstep(4.9, 6.0, tt)
	var k3 := smoothstep(6.0, 7.3, tt)
	var pos: Vector3 = (poses[0][0] as Vector3).lerp(poses[1][0], k1).lerp(poses[2][0], k2).lerp(poses[3][0], k3)
	var rot: Vector3 = (poses[0][1] as Vector3).lerp(poses[1][1], k1).lerp(poses[2][1], k2).lerp(poses[3][1], k3)
	p.cam.position = pos
	p.cam.rotation = rot
	# веки: темно → приоткрыл → моргнул → открыл → моргнул → открыл
	var a := 1.0
	if tt < 0.7:
		a = 1.0
	elif tt < 1.5:
		a = lerpf(1.0, 0.5, smoothstep(0.7, 1.5, tt))
	elif tt < 1.8:
		a = lerpf(0.5, 1.0, smoothstep(1.5, 1.8, tt))
	elif tt < 2.8:
		a = lerpf(1.0, 0.2, smoothstep(1.8, 2.8, tt))
	elif tt < 3.0:
		a = lerpf(0.2, 0.85, smoothstep(2.8, 3.0, tt))
	else:
		a = lerpf(0.85, 0.0, smoothstep(3.0, 4.2, tt))
	if fade:
		fade.color.a = a


## Плавно повернуть взгляд на точку (поворот игрока по Y и наклон головы).
func _aim(point: Vector3, k: float) -> void:
	var p = game.player
	var v: Vector3 = point - p.cam.global_position
	var yaw := atan2(-v.x, -v.z)
	var pitch := atan2(v.y, Vector2(v.x, v.z).length())
	p.rotation.y = lerp_angle(p.rotation.y, yaw, k)
	p.head.rotation.x = lerpf(p.head.rotation.x, clampf(pitch, -1.2, 1.0), k)


func _begin_cut() -> void:
	stage = "cut"
	t = 0.0
	_lock(true)
	var e := Enemy.new()
	e.game = game
	e.kind = "fast"
	e.position = CRAWL_FROM
	e.rotation.y = -PI / 2.0     # ползёт на восток, к проёму
	game.add_child(e)
	e.hp = e.max_hp * 0.5
	if e.bar_fg:
		e.bar_fg.scale.x = 0.5
	e.crawl_path = CRAWL_PATH.duplicate()
	e.crawl_speed = CRAWL_SPEED
	e.crawl_stop = 4.3           # путь ~3.4 м — к концу уже в комнате; стоит, отвернувшись от входа
	e.drop_only = ["rusk", "water"]
	e._set_state("crawl")
	e.died.connect(_on_crawler_died)
	if game.takedown:
		game.takedown.killed.connect(_on_takedown)
	crawler = e
	cut_cam = Camera3D.new()
	cut_cam.fov = game.player.cam.fov
	cut_cam.near = 0.05
	game.add_child(cut_cam)
	cut_cam.global_transform = Transform3D(Basis(), SIDE_CAM).looking_at(e.global_position + Vector3(0, 0.4, 0))
	cut_cam.current = true
	game.player.set_head_visible(true)
	# звук: скрежет ползущего тела, жалобный визг и глухой гул
	var drag := AudioStreamPlayer3D.new()
	drag.stream = _drag_snd()
	drag.unit_size = 3.0
	drag.volume_db = -13.0
	drag.position.y = 0.3
	e.add_child(drag)
	drag.play()
	_whimper(e, 0.72)
	get_tree().create_timer(1.5, false).timeout.connect(_whimper_again)
	var sting := AudioStreamPlayer.new()
	sting.stream = SlotM._dread()
	sting.volume_db = -24.0
	add_child(sting)
	sting.play()


## Жалобный тихий визг ползущего (длиннее и тише обычного, промпт 16.11 03:36).
func _whimper(e, pitch: float) -> void:
	e._growl()
	e.voice.volume_db = -20.0
	e.voice.pitch_scale = pitch


func _whimper_again() -> void:
	if is_instance_valid(crawler) and String(crawler.get("state")) == "crawl":
		_whimper(crawler, 0.62)


func _on_takedown(k) -> void:
	if k == crawler:
		_on_crawler_died(k)


func _end_side_cam() -> void:
	if is_instance_valid(cut_cam):
		cut_cam.queue_free()
	cut_cam = null
	if game and is_instance_valid(game.player):
		game.player.cam.current = true
		game.player.set_head_visible(false)


func _on_crawler_died(_e) -> void:
	if stage in ["hunt", "cut", "free"]:
		if stage == "cut":
			_end_side_cam()
			_lock(false)
		_hide_hint()
		stage = "cue_wait"
		t = 0.0


func _finish() -> void:
	_end_side_cam()
	if game and not game.intro_done:
		game.intro_done = true
		if game.slot and is_instance_valid(game.slot):
			game.slot.set_powered(true, true)
	for c in hidden:
		if is_instance_valid(c):
			(c as Node3D).visible = true
	hidden.clear()
	if game and is_instance_valid(game.player):
		game.player.cam.position = Vector3.ZERO
		game.player.cam.rotation = Vector3.ZERO
	if hint:
		hint.visible = false
	set_process(false)
	queue_free()


# ---------- подсказка «Красться — C» ----------

func _show_hint() -> void:
	hint = Label.new()
	hint.text = "Красться — C"
	hint.add_theme_font_size_override("font_size", 24)
	hint.add_theme_color_override("font_color", Color(0.9, 0.88, 0.8))
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	hint.add_theme_constant_override("outline_size", 6)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_left = -200
	hint.offset_right = 200
	hint.offset_top = -170
	hint.offset_bottom = -130
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.modulate.a = 0.0
	layer.add_child(hint)
	hint_t = 0.0
	create_tween().tween_property(hint, "modulate:a", 1.0, 0.5)


func _hint_tick(delta: float) -> void:
	if hint == null or not hint.visible:
		return
	hint_t += delta
	if game.player.crouched:
		crouch_t += delta
	if crouch_t > 1.5 or hint_t > 14.0:
		_hide_hint()


func _hide_hint() -> void:
	if hint == null or not hint.visible or hint.has_meta("hiding"):
		return
	hint.set_meta("hiding", true)
	var tw := create_tween()
	tw.tween_property(hint, "modulate:a", 0.0, 0.6)
	tw.tween_callback(func(): hint.visible = false)


# ---------- автомат вдалеке ----------

func _play_echo() -> void:
	var s := AudioStreamPlayer3D.new()
	s.stream = echo_snd
	s.unit_size = 9.0
	s.max_distance = 60.0
	s.volume_db = -1.5
	s.attenuation_filter_cutoff_hz = 9000.0
	game.add_child(s)
	if game.slot and is_instance_valid(game.slot):
		s.global_position = game.slot.global_position + Vector3(0, 1.2, 0)
	else:
		s.global_position = Vector3(-6.0, 1.2, 8.5)
	s.finished.connect(s.queue_free)
	s.play()


## Джекпот игрового автомата: колокольчики-арпеджио, звонок и звон монет — с эхом по коридору
## (запаздывающие приглушённые повторы) и чуть глуховато, будто издалека.
static func _slot_echo() -> AudioStreamWAV:
	var r := Sfx.RATE
	var n := int(r * 4.2)
	var dry := PackedFloat32Array()
	dry.resize(n)
	var notes := [1046.5, 1318.5, 1568.0, 2093.0, 1568.0, 2093.0, 2637.0]
	for k in notes.size():
		var s0 := int(r * 0.075 * k)
		var f: float = notes[k]
		for i in range(s0, mini(n, s0 + int(r * 1.0))):
			var ts := float(i - s0) / r
			var env := exp(-ts * 5.0) * minf(1.0, ts * 300.0)
			dry[i] += (sin(TAU * f * ts) + 0.4 * sin(TAU * f * 2.0 * ts) * exp(-ts * 9.0) + 0.2 * sin(TAU * f * 3.01 * ts)) * env * 0.5
	# звонок «дзззынь»
	for i in range(int(r * 0.55), int(r * 1.75)):
		var ts := float(i) / r - 0.55
		var env := minf(1.0, ts * 40.0) * exp(-ts * 1.8) * (0.55 + 0.45 * sin(TAU * 21.0 * ts))
		dry[i] += (sin(TAU * 1760.0 * ts) + 0.5 * sin(TAU * 2349.0 * ts)) * env * 0.3
	# монеты сыплются в лоток
	var rng := RandomNumberGenerator.new()
	rng.seed = 313
	for _c in 16:
		var s0 := int(r * rng.randf_range(0.5, 1.7))
		var f := rng.randf_range(2900.0, 4600.0)
		for i in range(s0, mini(n, s0 + int(r * 0.06))):
			var ts := float(i - s0) / r
			dry[i] += sin(TAU * f * ts) * exp(-ts * 70.0) * 0.35
	# эхо коридора
	var out := dry.duplicate()
	for tap in [[0.27, 0.5], [0.55, 0.3], [0.83, 0.18], [1.12, 0.1], [1.4, 0.06]]:
		var dd := int(r * float(tap[0]))
		var g: float = tap[1]
		var lp := 0.0
		for i in range(dd, n):
			lp += (dry[i - dd] - lp) * 0.3
			out[i] += lp * g
	var lp2 := 0.0
	for i in n:
		lp2 += (out[i] - lp2) * 0.55
		out[i] = lp2
	return Sfx._wav(out, 0.85)


## Скрежет ползущего тела: глухие волочения шумом с паузами.
static func _drag_snd() -> AudioStreamWAV:
	var r := Sfx.RATE
	var n := int(r * 5.6)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var bp := Sfx.Svf.new(700.0, 1.2)
	var bp2 := Sfx.Svf.new(2200.0, 1.5)
	for i in n:
		var ts := float(i) / r
		var ph := fmod(ts, 0.62) / 0.62
		var env := sin(clampf(ph / 0.7, 0.0, 1.0) * PI) * (1.0 - smoothstep(4.6, 5.6, ts))
		var w := rng.randf() * 2.0 - 1.0
		buf[i] = (bp.bp(w) * 0.9 + bp2.bp(w) * 0.25) * env
	return Sfx._wav(buf, 0.6)


# ---------- битое стекло и разбитая бутылка у места пробуждения ----------

func _decor() -> void:
	var root := Node3D.new()
	root.name = "WakeGlass"
	game.add_child(root)
	var green := StandardMaterial3D.new()
	green.albedo_color = Color(0.2, 0.42, 0.24, 0.62)
	green.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	green.roughness = 0.08
	green.metallic_specular = 0.8
	green.cull_mode = BaseMaterial3D.CULL_DISABLED
	var clear := green.duplicate() as StandardMaterial3D
	clear.albedo_color = Color(0.62, 0.7, 0.68, 0.45)
	var base := Vector3(WAKE_POS.x + 0.75, 0.0, WAKE_POS.z + 0.35)
	# половина бутылки на боку: дно и кусок корпуса
	var body := CylinderMesh.new()
	body.top_radius = 0.038
	body.bottom_radius = 0.038
	body.height = 0.13
	body.radial_segments = 12
	body.material = green
	var bm := MeshInstance3D.new()
	bm.mesh = body
	bm.position = base + Vector3(0.05, 0.038, -0.1)
	bm.rotation = Vector3(0, 0.7, PI / 2.0)
	root.add_child(bm)
	# горлышко с отбитым краем
	var neck := CylinderMesh.new()
	neck.top_radius = 0.013
	neck.bottom_radius = 0.03
	neck.height = 0.1
	neck.radial_segments = 10
	neck.material = green
	var nm := MeshInstance3D.new()
	nm.mesh = neck
	nm.position = base + Vector3(0.32, 0.026, 0.2)
	nm.rotation = Vector3(0.0, -1.1, PI / 2.0 - 0.15)
	root.add_child(nm)
	# осколки
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	for k in 14:
		var sh := BoxMesh.new()
		sh.size = Vector3(rng.randf_range(0.015, 0.06), 0.004, rng.randf_range(0.015, 0.07))
		sh.material = green if k % 3 != 0 else clear
		var mi := MeshInstance3D.new()
		mi.mesh = sh
		var a := rng.randf() * TAU
		var rr := sqrt(rng.randf()) * 0.5
		mi.position = base + Vector3(cos(a) * rr, 0.004, sin(a) * rr * 1.3)
		mi.rotation = Vector3(rng.randf_range(-0.15, 0.15), rng.randf() * TAU, rng.randf_range(-0.15, 0.15))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	# осколок, который можно подобрать (материал для ножика)
	game._make_pickup("glass", 1, base + Vector3(0.2, 0.1, -0.35), Vector3.ZERO)
