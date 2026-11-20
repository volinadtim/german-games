extends Node
## Начало новой игры (промпт 16.11 03:13). Только новая игра / новый сейв; в сети — только у хоста.
##   1. Игрок просыпается полулёжа у западной стены северо-западной комнаты, рядом битое стекло
##      и разбитая бутылка; веки моргают, он садится и встаёт (камера — без управления).
##   1a. Встал — замечает у себя в руке мятую записку «Выиграй всё», быстро читает и выкидывает её
##      (промпт 18.11 01:54). Эта сцена короткая и НЕ скипается — играет и после пропуска пробуждения.
##   2. Почти дошёл до проёма в коридор — короткая сцена: камера сама поворачивается, из-за угла
##      выползает заблудший мелкий монстрик («Шныга», половина здоровья) и ползёт прочь по коридору.
##      Единственная подсказка эпизода — «Красться — C». Добить его — сзади на E (world/takedown.gd).
##   3. Монстрик умер — по коридору эхом звенит игровой автомат, камера плавно поворачивается
##      в сторону комнаты с KILLBOX, потом управление полностью возвращается.
const Enemy := preload("res://scripts/enemy/enemy.gd")
const PickupScript := preload("res://scripts/world/pickup.gd")
const Items := preload("res://scripts/items.gd")
const Sfx := preload("res://scripts/core/sfx.gd")
const SlotM := preload("res://scripts/slot/slot_machine.gd")
const WAKE_POS := Vector3(-11.25, 0.05, -4.3)   # у западной стены; game_base.gd CHEST_AVOID и glass_floor.gd AVOID обходят это место
## Сеть (промпт 16.11 22:04): все просыпаются в этой же комнате, каждый у своей стены — [место, поворот, вещи рядом
## (вперёд, вбок)]. Номер места — по порядку id игроков (хост — первое, у бутылки). Места обходят завалы и плиту.
const KIT := ["tshirt", "rag_pants", "sack", "bandage"]
const SPOTS := [
	[WAKE_POS, -PI / 2.0, [Vector2(1.0, -0.85), Vector2(1.45, -0.45), Vector2(0.85, 1.2), Vector2(1.4, 1.0)]],
	[Vector3(-7.7, 0.05, -8.45), PI, [Vector2(1.0, 0.85), Vector2(1.45, 0.45), Vector2(0.85, -1.2), Vector2(1.4, -1.0)]],
	[Vector3(-8.6, 0.05, -2.15), 0.0, [Vector2(1.0, -0.85), Vector2(1.45, -0.45), Vector2(0.85, 1.2), Vector2(1.4, 1.0)]],
	[Vector3(-11.25, 0.05, -6.0), -PI / 2.0, [Vector2(0.95, -0.35), Vector2(1.4, -0.05), Vector2(0.85, 0.4), Vector2(1.4, 0.45)]],
]

const DOOR := Vector3(-6.0, 0.0, -1.6)          # проём из северо-западной комнаты в коридор
const TRIGGER_R := 2.3                          # «почти подошёл к выходу»
const TRIGGER_X := -5.0                         # граница участка у проёма (вместо невидимой стены, промпт 16.11 04:50)
const CRAWL_FROM := Vector3(-10.8, 0.0, 1.15)   # глубже в конце коридора, у южной стенки (промпт 16.11 04:47)    # из-за угла коридора; заворачивает в комнату KILLBOX (промпт 16.11 03:49)
# камера выскальзывает из глаз назад-влево, за плечо, и смотрит, как персонаж выглядывает из-за косяка (промпт 16.11 03:59)
# (промпт 16.11 04:04) осторожно: прижался к стене сбоку от проёма, присел, медленно выглядывает головой
# и плечом из-за косяка, задерживает дыхание, отклоняется обратно за укрытие и тихо выдыхает
# (04:12) выглядывает у ближнего к нему косяка, проём не пересекает: пришёл с запада — у западного, иначе — у восточного
const SHOULDER := Vector3(0.45, 0.18, 0.95)      # от глаз, в осях игрока (+Z — назад); X умножается на сторону
const PEEK_DX := 1.2                             # от оси проёма до места у стены (край проёма — 0.85)
const PEEK_Z := -2.02                            # вплотную к стене с проёмом, внутри комнаты
const PEEK_YAW := PI                             # смотрит на юг (+Z), выглядывает вбок — к проёму
const SIDE_T := 4.7                              # потом камера плавно возвращается в глаза
# по коридору к проёму комнаты с автоматом (x = -6, z = 1.6), по оси проёма внутрь; конец пути — стоп (~4 с)
const CRAWL_PATH := [Vector3(-7.2, 0, 0.85), Vector3(-6.0, 0, 1.6), Vector3(-6.0, 0, 2.9)]
const CRAWL_SPEED := 1.1   # ~6 м за ~5.5 с — к концу кат-сцены уже в комнате
# ---------- записка в руке (промпт 18.11 01:54) ----------
const NOTE_TEXT := "Выиграй всё"
const NOTE_T := 2.75       # поднял в кадр → прочитал → отвёл руку → выкинул (короче, промпт 18.11 02:15)
const NOTE_TOSS := 1.95    # на этой секунде бумажка летит из руки на пол
const WAKE_T := 7.6
const CUT_T := 6.2
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
var held := false
var side := 1.0          # с какой стороны проёма стоит: -1 — запад, +1 — восток
var peek_at := Vector3.ZERO
var exhaled := false
var spot := 0            # номер места пробуждения (сеть)
var pending_cut := false # сеть: кат-сцену запустил другой игрок, пока этот ещё просыпался
var cut_sent := false    # хост: кат-сцена уже разослана; клиент: уже попросил
var cue_sent := false    # смерть монстрика уже разослана (хостом — всем, клиентом — хосту)
var uncalm_sent := false # клиент: попросил хоста снять с монстрика неуязвимость
var want_note := false   # новая игра: после пробуждения — нескипаемая сцена с запиской
var note: Node3D         # записка в руке (ребёнок камеры игрока)
var note_tossed := false
var done := false
var keep_t := 0.0
var actor                # кто выглядывает в кат-сцене у проёма (сплитскрин: любой из двух игроков)
var new_run := false     # новая игра (стартовые наборы на полу)


func _net():
	return game.net if game and game.net else null


## Хост или одиночная игра — монстрик настоящий; у клиента — копия от хоста (net_world.gd es).
func _owner() -> bool:
	var n = _net()
	return n == null or n.is_host()


## Пропуск (ui/cutscene_skip.gd): пробуждение, выглядывание из-за косяка, поворот к KILLBOX — у каждого свой.
func can_skip() -> bool:
	return not done and ((stage == "wake" and t < WAKE_T) or (stage == "cut" and t < CUT_T) or (stage == "cue" and t < CUE_T))


func skip_cut() -> void:
	match stage:
		"wake":
			groaned = true
			stood = true
			t = WAKE_T
		"cut":
			held = true
			exhaled = true
			t = CUT_T
		"cue":
			t = CUE_T


func skip_shared() -> bool:
	return false


func start(new_game := true, skip_wake := false) -> void:
	add_to_group("cutscene")
	var p = game.player
	var n = _net()
	if n:
		var ids: Array = n.players.keys()
		ids.sort()
		spot = clampi(maxi(ids.find(multiplayer.get_unique_id()), 0), 0, SPOTS.size() - 1)
	new_run = new_game
	if new_game:
		_starter_kit()
		want_note = true   # записку находит в руке только в новой игре
	if not skip_wake:   # загрузка после пробуждения — игрок остаётся там, где сохранился
		p.global_position = SPOTS[spot][0]
		p.rotation.y = float(SPOTS[spot][1])   # лицом в комнату
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
	if _owner():
		_spawn_crawler()
	if game.takedown:
		game.takedown.killed.connect(_on_takedown)
	echo_snd = _slot_echo()
	game.intro_done = false
	game.shop_on = false
	if game.shop and is_instance_valid(game.shop):
		game.shop.set_powered(false)   # Trinkets Market включится после первых круток (slot_machine.gd)
	if game.slot and is_instance_valid(game.slot):
		game.slot.set_powered(false)   # KILLBOX выключен до убийства монстрика
	_wake_pose(0.0)
	if skip_wake:
		_end_wake()
		return
	if p.has_method("start_wake"):
		p.start_wake()   # тело лежит → садится → встаёт (player_death.gd), видно другим игрокам


## Новая игра (промпт 16.11 21:46): персонаж без одежды — футболка, штаны, вещмешок и бинты лежат рядом
## на полу (подбираются на E, не исчезают). Повтор вступления после загрузки — без них: вещи уже в сейве.
## В сети каждый кладёт такой же набор у своего места сам — остальным его рассылает net (pickup_made).
func _starter_kit(sp := -1) -> void:
	var s := spot if sp < 0 else sp
	var base: Vector3 = SPOTS[s][0]
	var yaw := float(SPOTS[s][1])
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var offs: Array = SPOTS[s][2]
	for i in KIT.size():
		var id: String = KIT[i]
		var o: Vector2 = offs[i]
		var pos: Vector3 = base + fwd * o.x + right * o.y
		pos.y = 0.15
		var pk = game._make_pickup(id, 2 if id == "bandage" else 1, pos, Vector3.ZERO)
		pk.angular_velocity = Vector3.ZERO
		pk.rotation.y = randf_range(0.0, TAU)
		pk.need_leave = true   # не подлетает сама, только по E
		pk.set_meta("kit", true)   # стартовый набор — никогда не подбирается сам (промпт 18.11 00:54)
		pk.life = 1.0e9        # не исчезает
		if Items.max_dur(id) > 0.0:
			pk.set_meta("dur", Items.max_dur(id))


## Сплитскрин (network/split.gd _spawn_p2): игрок 2 в новой игре встаёт на второе место этой же комнаты, рядом — его набор.
func place_p2(pl, fresh: bool) -> void:
	if not new_run:
		return
	pl.global_position = SPOTS[1][0]
	pl.rotation.y = float(SPOTS[1][1])
	pl.velocity = Vector3.ZERO
	if fresh:
		_starter_kit(1)


## Кто может подойти к проёму и запустить кат-сцену: игрок 1 и живой игрок 2 сплитскрина.
func _cut_players() -> Array:
	var a: Array = [game.player]
	var sp = game.get_meta("split") if game.has_meta("split") else null
	if sp and is_instance_valid(sp.get("pp")) and sp.get("alive"):
		a.append(sp.pp)
	return a


## Персонаж кат-сцены у проёма: тот, кто её запустил (по умолчанию игрок 1).
func _actor():
	return actor if is_instance_valid(actor) else game.player


## Сеть: копии чужих стартовых наборов приходят с обычным сроком (3.5 мин) — тоже делаем вечными.
func _keep_kits() -> void:
	if game == null or not is_instance_valid(game):
		return
	for c in game.get_children():
		if c is PickupScript and c.need_leave and String(c.id) in KIT and c.life < 1.0e8:
			var gp: Vector3 = c.global_position
			if gp.x < -4.5 and gp.x > -12.0 and gp.z < -1.5 and gp.z > -9.0:
				c.life = 1.0e9
				c.set_meta("kit", true)


func _lock(on: bool) -> void:
	var p = game.player
	if on:
		game.close_windows()   # кат-сцена закрывает любые окна (промпт 16.11 21:40)
	p.set_lock("intro", on)   # независимая блокировка (консоль и чат её не снимают, промпт 16.11 04:51)
	game.hud.set_cinematic(on)
	p.cinematic_stance(on)
	if not on and p.input_locks.is_empty():   # консоль ещё открыта — мышь не захватываем
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	if game == null or not is_instance_valid(game.player):
		queue_free()
		return
	t += delta
	var p = game.player
	if _net():
		keep_t += delta
		if keep_t > 0.5:
			keep_t = 0.0
			_keep_kits()
	elif stage != "wake" and not game.alive:   # в сети — возрождение, вступление идёт дальше
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
				_end_wake()
		"note":
			_note_pose(t)
			if t >= NOTE_T:
				_end_note()
		"free":
			for who in _cut_players():
				var pp: Vector3 = who.global_position
				# Срабатывает только если игрок реально находится в районе северо-западной комнаты бункера
				# (по высоте под землёй y < 2.0 и в пределах квадрата комнаты/коридора вокруг DOOR)
				var in_room := pp.y > -2.0 and pp.y < 2.5 and pp.x > -14.0 and pp.x < -1.0 and pp.z > -10.5 and pp.z < 3.5
				if in_room and (Vector2(pp.x - DOOR.x, pp.z - DOOR.z).length() < TRIGGER_R or pp.z > DOOR.z or pp.x > TRIGGER_X):
					actor = who
					_request_cut()
					break
		"cut":
			p = _actor()
			if not is_instance_valid(crawler) and not _owner():
				crawler = _find_crawler()
			if is_instance_valid(crawler):
				# крадётся к стене у косяка, приседает и медленно выглядывает: наклон корпуса и головы
				var to: Vector3 = peek_at - p.global_position
				to.y = 0.0
				p.global_position += to * (1.0 - exp(-2.2 * delta))
				p.force_crouch = t < 5.4
				p.rotation.y = lerp_angle(p.rotation.y, PEEK_YAW, 1.0 - exp(-2.5 * delta))
				var v: Vector3 = crawler.global_position + Vector3(0, 0.4, 0) - p.cam.global_position
				var pitch := atan2(v.y, Vector2(v.x, v.z).length())
				p.head.rotation.x = lerpf(p.head.rotation.x, clampf(pitch, -0.6, 0.4), 1.0 - exp(-2.0 * delta))
				p.peek = side * smoothstep(1.3, 3.0, t) * (1.0 - smoothstep(4.0, 5.1, t))
				if t > 1.3 and not held:
					held = true
					_breath(0, -30.0, 1.25)   # короткий тихий вдох — затаил дыхание
				if t > 5.1 and not exhaled:
					exhaled = true
					_breath(0, -27.0, 0.75)   # за укрытием — медленный выдох
				var eye: Transform3D = p.cam.global_transform
				var out := smoothstep(0.0, 1.3, t) * (1.0 - smoothstep(SIDE_T, CUT_T - 0.05, t))
				var head_pt: Vector3 = eye.origin
				var look: Vector3 = head_pt.lerp(crawler.global_position + Vector3(0, 0.4, 0), 0.55)
				var sh_pos: Vector3 = eye.origin + Basis(Vector3.UP, p.rotation.y) * Vector3(SHOULDER.x * side, SHOULDER.y, SHOULDER.z)
				var shoulder := Transform3D(Basis(), sh_pos).looking_at(look)
				cut_cam.global_transform = eye.interpolate_with(shoulder, out)
				p.set_head_visible(out > 0.2)   # голова видна, пока камера снаружи
			if t >= CUT_T:
				_end_side_cam()
				_lock(false)
				_show_hint()
				if _owner():
					if is_instance_valid(crawler):
						crawler.set("calm", false)
				elif not uncalm_sent:
					uncalm_sent = true
					rpc_id(1, "rq_uncalm")   # пропустил кат-сцену раньше хоста — монстрик должен стать уязвим
				stage = "hunt"
		"hunt":
			if not _owner():
				# клиент: ждём смерть монстрика от хоста (net_cue); подстраховка — копия монстрика умерла
				if not is_instance_valid(crawler):
					crawler = _find_crawler()
				if is_instance_valid(crawler) and String(crawler.get("state")) == "dead":
					_on_crawler_died(crawler)
			elif not is_instance_valid(crawler):
				if _net():
					_on_crawler_died(null)
				else:
					_finish()
			elif String(crawler.get("state")) == "dead":
				_on_crawler_died(crawler)   # подстраховка, если сигнал died не дошёл
		"cue_wait":
			if t >= 0.1:   # сразу после убийства (промпт 16.11 03:39)
				game.intro_done = true
				if game.slot and is_instance_valid(game.slot):
					game.slot.net_power(true)   # KILLBOX загорается со звуком — у всех игроков
				_play_echo()
				p.set_lock("intro_cue", true)
				t = 0.0
				stage = "cue"
		"cue":
			var at := Vector3(-6.0, 1.4, 8.5)
			if game.slot and is_instance_valid(game.slot):
				at = game.slot.global_position + Vector3(0, 1.4, 0)
			_aim(at, 1.0 - exp(-2.2 * delta))
			if t >= CUE_T:
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


func _end_wake() -> void:
	_wake_pose(WAKE_T)
	if game.player.has_method("end_wake"):
		game.player.end_wake()
	for c in hidden:
		if is_instance_valid(c):
			(c as Node3D).visible = true
	hidden.clear()
	fade.visible = false
	if not game.intro_wake_done:
		game.intro_wake_done = true
		game.save_now()   # пробуждение показано — при следующем входе его не будет
	if pending_cut:
		pending_cut = false
		want_note = false
		_lock(false)
		stage = "free"
		_begin_cut()
		return
	if want_note:
		_begin_note()
		return
	_lock(false)
	stage = "free"


# ---------- записка «Выиграй всё» в руке ----------

## Нескипаемая сцена (can_skip() на стадии "note" даёт false): рука с мятой запиской поднимается
## в кадр, персонаж читает её пару секунд и выкидывает — бумажка падает на пол рядом.
func _begin_note() -> void:
	want_note = false
	note_tossed = false
	stage = "note"
	t = 0.0
	_lock(true)
	game.player.head.rotation.x = 0.0
	note = _note_mesh()
	game.player.cam.add_child(note)
	_note_pose(0.0)
	_paper(-14.0, 1.05)


## Записка дочитана и выкинута — управление возвращается (в сети кат-сцена могла подождать).
func _end_note() -> void:
	if note and is_instance_valid(note):
		note.queue_free()
	note = null
	if is_instance_valid(game.player):
		game.player.head.rotation.x = 0.0
	_lock(false)
	stage = "free"
	t = 0.0
	if pending_cut:
		pending_cut = false
		_begin_cut()


## Поза руки с запиской в осях камеры: поднял → читает (лёгкая дрожь) → замах → бросок.
func _note_pose(tt: float) -> void:
	var p = game.player
	var up := smoothstep(0.0, 0.55, tt)            # рука быстро поднимает записку в кадр
	var away := smoothstep(1.5, NOTE_TOSS, tt)     # отвёл в сторону перед броском
	if note and is_instance_valid(note):
		var low := Vector3(0.26, -0.44, -0.55)
		var read := Vector3(0.015, -0.055, -0.3)
		var side_pos := Vector3(-0.26, -0.16, -0.42)
		var pos: Vector3 = low.lerp(read, up).lerp(side_pos, away)
		var rl := Vector3(-1.15, 0.35, 0.55)
		var rr := Vector3(-0.13, 0.0, 0.04)
		var rs := Vector3(0.12, 0.65, -0.5)
		var rot: Vector3 = rl.lerp(rr, up).lerp(rs, away)
		var shake := (1.0 - away) * up * 0.004
		pos += Vector3(sin(tt * 7.3), cos(tt * 5.1), 0.0) * shake
		rot.z += sin(tt * 4.3) * shake * 3.0
		note.position = pos
		note.rotation = rot
	# голова чуть опущена к записке, к концу — обратно
	var look := up * (1.0 - smoothstep(NOTE_TOSS, NOTE_T - 0.25, tt))
	p.head.rotation.x = lerpf(0.0, -0.24, look)
	if tt >= NOTE_TOSS and not note_tossed:
		_toss_note()


## Бросок: записка исчезает из руки и плавно слетает на пол (без физики — RigidBody её
## колбасило и ставило на ребро; тонкий листок обязан лежать плашмя).
func _toss_note() -> void:
	note_tossed = true
	var p = game.player
	if note and is_instance_valid(note):
		note.queue_free()
		note = null
	var fwd: Vector3 = -p.cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var right: Vector3 = p.cam.global_transform.basis.x
	right.y = 0.0
	right = right.normalized() if right.length() > 0.01 else Vector3.RIGHT
	var start_pos: Vector3 = p.cam.global_position + fwd * 0.35 - right * 0.14 - Vector3(0, 0.2, 0)
	var land: Vector3 = start_pos + fwd * 0.5 - right * 0.3
	land.y = _note_floor_y(land, p.global_position.y) + 0.004
	var mid: Vector3 = start_pos.lerp(land, 0.55) + Vector3(0, 0.1, 0) + right * 0.06
	var yaw := randf_range(-PI, PI)
	var n := _note_mesh()
	game.add_child(n)
	n.global_position = start_pos
	n.rotation = Vector3(-0.7, yaw, randf_range(-0.5, 0.5))
	var tw := n.create_tween()
	tw.set_parallel(true)
	tw.tween_property(n, "rotation", Vector3(-PI * 0.5, yaw, 0.0), 0.8) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var mv := n.create_tween()
	mv.tween_property(n, "global_position", mid, 0.38).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	mv.tween_property(n, "global_position", land, 0.44).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_paper(-12.0, 0.9)


## Пол под точкой падения записки (луч вниз); если не нашёл — высота ног игрока.
func _note_floor_y(at: Vector3, fallback: float) -> float:
	var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 0.8, 0), at - Vector3(0, 2.5, 0))
	q.collide_with_areas = false
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return fallback
	return float(hit.position.y)


## Мятый листок с надписью «Выиграй всё» (Node3D: бумага двумя изломанными половинками + текст).
func _note_mesh() -> Node3D:
	var root := Node3D.new()
	root.name = "Note"
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color(0.84, 0.81, 0.71)
	paper.roughness = 0.96
	paper.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in 2:
		var q := QuadMesh.new()
		q.size = Vector2(0.136, 0.092)
		q.material = paper
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.position = Vector3(0, 0.046 if i == 0 else -0.046, 0.0)
		mi.rotation = Vector3(0.1 if i == 0 else -0.08, 0.0, 0.0)   # излом по сгибу
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	var l := Label3D.new()
	l.text = NOTE_TEXT
	l.font = _note_font()
	l.font_size = 40
	l.pixel_size = 0.00052
	l.width = 140.0
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.modulate = Color(0.08, 0.09, 0.2)
	l.outline_size = 0
	l.shaded = false
	l.position = Vector3(0, 0.0, 0.003)
	root.add_child(l)
	return root


static var _note_f: SystemFont
static func _note_font() -> SystemFont:
	if _note_f == null:
		_note_f = SystemFont.new()
		_note_f.font_names = PackedStringArray(["Segoe Script", "Comic Sans MS", "Gabriola", "sans-serif"])
	return _note_f


## Шорох бумаги в руке.
func _paper(db: float, pitch: float) -> void:
	var p = game.player
	var pl := AudioStreamPlayer3D.new()
	pl.stream = _paper_snd()
	pl.volume_db = db
	pl.pitch_scale = pitch
	pl.unit_size = 2.0
	game.add_child(pl)
	pl.global_position = p.cam.global_position
	pl.finished.connect(pl.queue_free)
	pl.play()


static func _paper_snd() -> AudioStreamWAV:
	var r := Sfx.RATE
	var n := int(r * 0.55)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 991
	var hp := Sfx.Svf.new(3200.0, 0.8)
	for i in n:
		var ts := float(i) / r
		var ph := fmod(ts, 0.14) / 0.14
		var env := sin(clampf(ph / 0.55, 0.0, 1.0) * PI) * exp(-ts * 2.2)
		buf[i] = hp.bp(rng.randf() * 2.0 - 1.0) * env * 0.8
	return Sfx._wav(buf, 0.5)


# ---------- сеть: кат-сцена и финал одни на всех ----------

## Кто-то подошёл к проёму: одиночная игра — сразу; хост рассылает всем; клиент просит хоста.
func _request_cut() -> void:
	var n = _net()
	if n == null:
		_begin_cut()
	elif n.is_host():
		_host_cut()
	elif not cut_sent:
		cut_sent = true
		rpc_id(1, "rq_cut")


func _host_cut() -> void:
	if not cut_sent:
		cut_sent = true
		if is_instance_valid(crawler):
			crawler.crawl_wait = false   # монстрик ползёт у хоста, остальные видят копию
		rpc("net_cut")
	net_cut()


@rpc("any_peer", "reliable")
func rq_cut() -> void:
	var n = _net()
	if n == null or not n.is_host():
		return
	var who := multiplayer.get_remote_sender_id()
	if cue_sent:
		rpc_id(who, "net_cue")   # опоздал: монстрик уже мёртв
	elif cut_sent:
		rpc_id(who, "net_cut")   # кат-сцена уже была — этот её пропустил (ещё грузился)
	else:
		_host_cut()


## Клиент закончил кат-сцену раньше хоста (пропустил) — монстрик у хоста больше не неуязвим.
@rpc("any_peer", "reliable")
func rq_uncalm() -> void:
	var n = _net()
	if n and n.is_host() and is_instance_valid(crawler):
		crawler.set("calm", false)
		crawler.crawl_wait = false


@rpc("authority", "reliable")
func net_cut() -> void:
	if done:
		return
	if stage == "wake" or stage == "note":
		pending_cut = true
	elif stage == "free":
		_begin_cut()


## Монстрика добил клиент — хост заканчивает вступление у себя и у всех остальных.
@rpc("any_peer", "reliable")
func rq_cue() -> void:
	var n = _net()
	if n == null or not n.is_host():
		return
	if not cue_sent:
		cue_sent = true
		rpc("net_cue")
	net_power_cue()


@rpc("authority", "reliable")
func net_cue() -> void:
	net_power_cue()


## Вступление пора заканчивать: монстрика добил кто-то (net_cue) или автомат уже включили у других
## игроков (slot_machine.gd net_power_apply); у стадий «просыпается» и «записка» — свой выход.
func net_power_cue() -> void:
	if done:
		return
	cue_sent = true   # о смерти уже знают все — обратно хосту не шлём
	if stage == "wake":
		pending_cut = false
		want_note = false
		_end_wake()
	elif stage == "note":
		_end_note()
	_on_crawler_died(null)


## Клиент: копия монстрика (ближайший к коридору мелкий враг).
func _find_crawler() -> Node3D:
	var best: Node3D = null
	var bd := 6.0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Node3D and String(e.get("kind")) == "fast":
			var d: float = (e as Node3D).global_position.distance_to(Vector3(-8.0, 0.0, 1.0))
			if d < bd:
				bd = d
				best = e
	return best


func _begin_cut() -> void:
	stage = "cut"
	var a = _actor()
	var px: float = a.global_position.x
	side = -1.0 if px < DOOR.x else 1.0   # к ближнему косяку, проём не пересекает
	peek_at = Vector3(DOOR.x + side * (PEEK_DX + 0.6 * spot), 0.0, PEEK_Z)   # в сети — каждый на своём месте у стены
	t = 0.0
	_lock(true)
	if _owner():
		if not is_instance_valid(crawler):
			_spawn_crawler()
		crawler.crawl_wait = false          # кат-сцена запускает его движение
	else:
		crawler = _find_crawler()
	var e = crawler
	cut_cam = Camera3D.new()
	cut_cam.fov = a.cam.fov
	cut_cam.near = 0.05
	game.add_child(cut_cam)
	cut_cam.global_transform = a.cam.global_transform
	cut_cam.current = true
	if is_instance_valid(e):
		_cut_sounds(e)


## Монстрик стоит у угла коридора с самого начала новой игры (промпт 16.11 04:27): копошится на месте
## и не замечает игрока, пока кат-сцена не запустит его движение.
func _spawn_crawler() -> void:
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
	e.crawl_stop = 0.0           # стоп — в конце пути, в комнате; стоит, отвернувшись от входа
	e.calm = true                # до конца кат-сцены не агрится и неуязвим
	e.drop_only = ["choco", "water"]   # шоколадка вместо сухаря (промпт 20.11 14:22)
	e._set_state("crawl")
	e.died.connect(_on_crawler_died)
	e.crawl_wait = true
	crawler = e


func _cut_sounds(e) -> void:
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


## Дыхание персонажа (звуки выдоха из player.gd), тихо и с заданной высотой.
func _breath(i: int, db: float, pitch: float) -> void:
	var p = _actor()
	if p.exhales.is_empty():
		return
	p.voice_player.stream = p.exhales[mini(i, p.exhales.size() - 1)]
	p.voice_player.volume_db = db
	p.voice_player.pitch_scale = pitch
	p.voice_player.play()


func _end_side_cam() -> void:
	if is_instance_valid(cut_cam):
		cut_cam.queue_free()
	cut_cam = null
	if game and is_instance_valid(game.player):
		game.player.cam.current = true
		game.player.set_head_visible(false)
		game.player.peek = 0.0
		game.player.force_crouch = false
	if is_instance_valid(actor) and game and actor != game.player:
		actor.set_head_visible(false)
		actor.peek = 0.0
		actor.force_crouch = false


## Монстрика добили (любой игрок, промпт 18.11 02:10): конец вступления и включение автомата — у всех.
func _on_crawler_died(_e) -> void:
	var n = _net()
	if n and not cue_sent:
		cue_sent = true
		if n.is_host():
			rpc("net_cue")        # финал вступления — всем
		else:
			rpc_id(1, "rq_cue")   # добил клиент: хост разошлёт конец вступления остальным
	if stage in ["hunt", "cut", "free"]:
		if stage == "cut":
			_end_side_cam()
			_lock(false)
		_hide_hint()
		stage = "cue_wait"
		t = 0.0


func _finish() -> void:
	_end_side_cam()
	if note and is_instance_valid(note):
		note.queue_free()
	note = null
	if game and is_instance_valid(game.player):
		game.player.set_lock("intro", false)
		game.player.set_lock("intro_cue", false)
	if is_instance_valid(crawler):
		crawler.set("calm", false)
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
	done = true
	set_process(false)
	if _net():
		# в сети узел остаётся (поздние rpc других игроков); чужие стартовые наборы ещё могут прийти
		for i in 6:
			get_tree().create_timer(5.0 * (i + 1), false).timeout.connect(_keep_kits)
		return
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
	s.volume_db = -13.0   # 04:06 −3.5 дБ; 04:32 «слишком громко» — ещё −8 дБ
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
	# осколок, который можно подобрать (материал для ножика); в сети — один, у хоста (остальным рассылается)
	if _owner():
		# в сторону от лица лежащего игрока (промпт 18.11 01:54): раньше висел прямо перед камерой,
		# будто осколок у него в руке
		game._make_pickup("glass", 1, base + Vector3(0.25, 0.1, 0.5), Vector3.ZERO)
