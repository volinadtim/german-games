extends Node3D
## Тестовые механики — связка: HUD, инвентарь, здоровье игрока, взаимодействие на E, лут на полу,
## враги, манекен, ящики/сейф, игровой автомат, фонарик. Создаётся из main.gd (_enter_game).
## Каждая механика — свой скрипт; ненужную выключить флагом ниже (или удалить её файл и строку _spawn_*).
##   Управление: E — взаимодействие, Tab/I — инвентарь, F — фонарик, Q — быстро полечиться.

const Player := preload("res://player.gd")
const Hud := preload("res://hud.gd")
const Inventory := preload("res://inventory.gd")
const Items := preload("res://items.gd")
const LootWindow := preload("res://loot_window.gd")
const GlassFloor := preload("res://glass_floor.gd")
const Save := preload("res://save.gd")
const Fx := preload("res://fx.gd")
const Pickup := preload("res://pickup.gd")
const Flashlight := preload("res://flashlight.gd")
const TapeSpot := preload("res://tape_spot.gd")
var tape  # моток изоленты у доски выплат — один на игру
const Enemy := preload("res://enemy.gd")
const Dummy := preload("res://dummy.gd")
const Chest := preload("res://chest.gd")
const Jar := preload("res://jar.gd")
const Surface := preload("res://surface.gd")
const SlotMachine := preload("res://slot_machine.gd")
const Shop := preload("res://shop.gd")
const GasMask := preload("res://gasmask.gd")
const Sfx := preload("res://sfx.gd")
const Sfx2 := preload("res://sfx_extra.gd")
const Car := preload("res://car.gd")
var car   # старая машина на поляне (car.gd): ключ в сейфе, уехать = победа
var play_time := 0.0   # сколько играл (для экрана победы, в сейве)
var won := false

# включение механик
const USE_ENEMIES := true
const USE_DUMMY := true
const USE_CHESTS := true
const USE_SLOTS := true
const USE_FLASHLIGHT := true

const MAX_HP := 100.0
const START := Vector3(-10.5, 0.05, 0.0)
## враги бродят по поляне наверху (выход из бункера — лестница в восточном торце коридора)
const ENEMY_SPOTS := [Vector3(28.0, 4.1, 7.0), Vector3(36.0, 4.1, -6.0), Vector3(40.0, 4.1, 4.0), Vector3(31.0, 4.1, -10.0)]
const RESPAWN := 40.0
const FAST_SHARE := 0.4   # доля быстрых врагов («Шныга», enemy.gd kind = "fast") на поляне

var player: Player
var hud: Hud
var inv: Inventory
var flashlight: Flashlight
var hp := MAX_HP
var alive := true
var focus: Object = null
var snd := {}
var ui_player: AudioStreamPlayer
var full_toast_t := 0.0
var safe: Chest
var slot: SlotMachine
var shop: Shop
var gasmask: GasMask


func setup(p: Player) -> void:
	player = p
	_setup_input()
	_make_sounds()
	ui_player = AudioStreamPlayer.new()
	ui_player.max_polyphony = 4
	add_child(ui_player)

	hud = Hud.new()
	add_child(hud)
	inv = Inventory.new()
	inv.game = self
	add_child(inv)
	inv.changed.connect(func(): hud.set_coins(inv.count("coin")))
	inv.use_requested.connect(use_item)
	inv.drop_requested.connect(drop_item)
	inv.drop_count_requested.connect(drop_count)
	inv.drop_coins_requested.connect(drop_coins)
	inv.equip_requested.connect(equip)
	inv.unequip_requested.connect(func(slot_: String, to: int): unequip(slot_, to))
	inv.drop_equipped_requested.connect(drop_equipped)
	inv.craft_requested.connect(craft)
	inv.repair_requested.connect(repair)
	inv.message.connect(func(t: String): hud.toast(t))
	hud.inv = inv
	hud.set_hp(hp, MAX_HP)
	hud.restart_pressed.connect(restart)
	hud.menu_pressed.connect(to_main_menu)

	if USE_FLASHLIGHT:
		flashlight = Flashlight.new()
		flashlight.game = self
		add_child(flashlight)
		flashlight.attach(player.cam)

	# стартовый набор (крутка автомата — 10 монет). Фонарика нет — он в магазине снаряжения.
	inv.add("coin", 50)
	inv.add("bandage", 2)

	if USE_DUMMY:
		# манекен — в левой комнате, ближайшей к старту (северо-западная)
		var d := Dummy.new()
		d.game = self
		d.position = Vector3(-8.0, 0.0, -3.6)
		add_child(d)
	if USE_ENEMIES:
		for s in ENEMY_SPOTS:
			_spawn_enemy(s)
	if USE_CHESTS:
		# лутбоксы — кувшины и колбы, случайно каждую новую игру — ниже, после стекла (_random_jars)
		# сейф открывается только тремя семёрками на автомате KILLBOX (open_safe)
		safe = Chest.new()
		safe.kind = "safe"
		safe.locked = true
		safe.random_loot = false
		safe.extra = [["car_key", 1], ["knuckles", 1], ["coin", 80], ["medkit", 2], ["battery", 1], ["canned", 2], ["wallet", 2]]
		safe.position = Vector3(11.5, 0.0, 7.0)
		safe.rotation.y = -PI / 2.0
		add_child(safe)
	# противогаз и отравленный воздух наверху (G)
	gasmask = GasMask.new()
	gasmask.game = self
	add_child(gasmask)
	if USE_SLOTS:
		# автомат создаёт main.gd (он же фон меню); если его нет — ставим свой
		slot = get_parent().get_node_or_null("SlotMachine") as SlotMachine
		if slot == null:
			slot = SlotMachine.new()
			slot.position = Vector3(-6.0, 0.0, 8.5)
			slot.rotation.y = PI
			add_child(slot)
		slot.game = self
		# новая игра в той же сессии: автомат общий с меню — сбрасываем (загрузка сейва выставит своё)
		slot.credits = 0
		slot.luck = {}
		slot.boost = {}
		slot.set_level(1)
		slot.set_tray(0)
	# изолента, приклеенная к доске выплат у автомата (берётся на E, со временем появляется снова)
	tape = TapeSpot.new()
	tape.game = self
	tape.position = Vector3(-7.05, 0.95, 8.66)   # доска выплат сдвинута на 0.1 (автомат шире)
	add_child(tape)
	# осколки стекла на полу (там, где битое стекло) — материал для ножика
	loot_window = LootWindow.new()
	loot_window.game = self
	add_child(loot_window)
	# сундук-хранилище (один, у старта): складывать вещи (промпт 00:08)
	storage = Chest.new()
	storage.kind = "storage"
	storage.position = Vector3(-11.45, 0.0, -2.7)
	storage.rotation.y = PI / 2.0
	add_child(storage)
	glass_floor = GlassFloor.new()
	add_child(glass_floor)
	glass_floor.generate()
	for sp in glass_floor.spots:
		_make_pickup("glass", 1, (sp[0] as Vector3) + Vector3(0.2, 0.1, 0.2), Vector3.ZERO)
	# старая машина на поляне — до кувшинов, чтобы они её обходили
	var surf_node: Node = get_parent().get_node_or_null("Level/Surface")
	if surf_node:
		car = Car.new()
		car.game = self
		car.surface = surf_node
		car.position = Surface.CAR_POS
		car.rotation.y = Surface.CAR_YAW
		add_child(car)
	if USE_CHESTS:
		_random_jars()
	shop = get_parent().get_node_or_null("Shop") as Shop
	if shop:
		shop.game = self
	# сохранения: загрузить выбранный слот (menu.gd) или начать новую игру в нём
	save_slot = Save.slot()
	if Engine.get_meta("eskiness_load", false) and Save.exists(save_slot):
		load_state(Save.read(save_slot))
	else:
		save_now()


## Три семёрки на автомате: открыть сейф. false — если сейф уже открыт (или его нет).
func open_safe() -> bool:
	if safe == null or not is_instance_valid(safe) or safe.opened:
		return false
	safe.force_open(self)
	return true

func _chest(pos: Vector3, rot: float, extra: Array) -> void:
	var c := Chest.new()
	c.game = self
	chests.append(c)
	c.extra = extra
	c.position = pos
	c.rotation.y = rot
	add_child(c)


# ---------- кувшины и колбы: случайная расстановка (промпты 14.11 00:06 и 00:08) ----------
## Каждая новая игра: 5–8 групп по 1–3 кувшина/колбы у стен комнат бункера и 3–5 групп у руин на поляне,
## разных форм и размеров (jar.gd). Разбиваются ударом — лут выпадает на пол.
## Не ставим у проёмов, автомата, магазина, сейфа, манекена, завалов и стекла; пересечения проверяет физика.
## Расстановка (место, вид, размер, рисунок, разбит ли) пишется в сейв (jars).
const CHEST_AVOID := [[Vector3(-6.0, 0, 8.5), 1.9], [Vector3(-4.05, 0, 8.5), 1.7], [Vector3(11.5, 0, 7.0), 1.4],
	[Vector3(-8.0, 0, -3.6), 1.3], [Vector3(-6.95, 0, 8.66), 1.0], [Vector3(-10.5, 0, 0), 1.5],
	[Vector3(-6, 0, -1.6), 1.6], [Vector3(-6, 0, 1.6), 1.6], [Vector3(6, 0, -1.6), 1.6], [Vector3(6, 0, 1.6), 1.6],
	[Vector3(0, 0, 5.5), 1.6], [Vector3(-8.5, 0, 5.5), 1.0], [Vector3(8.5, 0, 5.5), 1.0],
	# завалы из level.gd
	[Vector3(-10, 0, -7.5), 1.4], [Vector3(-3, 0, -4), 1.4], [Vector3(2.5, 0, -7.8), 1.4], [Vector3(10, 0, -3.5), 1.4],
	[Vector3(-10.5, 0, 8), 1.4], [Vector3(-2.5, 0, 3.5), 1.4], [Vector3(3, 0, 8), 1.4], [Vector3(10.8, 0, 3.5), 1.4],
	[Vector3(11.0, 0, -6.8), 1.4], [Vector3(-5.5, 0, -8.3), 1.6], [Vector3(7.5, 0, 8.2), 1.5]]
const RUINS := [Vector3(26, 0, -9), Vector3(38, 0, 7), Vector3(35, 0, -12), Vector3(24, 0, 9), Vector3(42, 0, -3)]
var jars: Array = []


func _random_jars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var placed: Array = []      # [[pos, радиус], ...]
	var groups := 0
	var want := rng.randi_range(5, 8)
	var tries := 0
	while groups < want and tries < 300:
		tries += 1
		var a := _bunker_chest_spot()
		var b := Basis(Vector3.UP, float(a[1]))
		var along := b * Vector3.RIGHT
		var front := b * Vector3.BACK
		if _jar_group(rng, a[0], along, front, placed, true) > 0:
			groups += 1
	# снаружи — сразу до OUT_JARS_MAX, дальше их пополняет таймер (_outside_jar_tick)
	for k in OUT_JARS_MAX:
		_spawn_outside_jar(false)


# ---------- кувшины снаружи (промпт 14.11 17:35) ----------
## На поляне одновременно не больше OUT_JARS_MAX целых кувшинов. Раз в OUT_JAR_EVERY с, если целых меньше,
## появляется ещё один — в случайном месте поляны: не в будке, не впритык к другим кувшинам и препятствиям,
## не ближе 6 м к игроку (чтобы не возникал на глазах). Старые разбитые снаружи убираем (осколки), держим ≤ 6.
const OUT_JARS_MAX := 5
const OUT_JAR_EVERY := 25.0
var _out_jar_t := OUT_JAR_EVERY


func _is_outside_jar(j) -> bool:
	return is_instance_valid(j) and j.position.y > 2.0


func _outside_jar_tick(delta: float) -> void:
	_out_jar_t -= delta
	if _out_jar_t > 0.0:
		return
	_out_jar_t = OUT_JAR_EVERY
	var whole := 0
	var broken_out: Array = []
	for j in jars:
		if _is_outside_jar(j):
			if j.broken:
				broken_out.append(j)
			else:
				whole += 1
	while broken_out.size() > 6:
		var old = broken_out.pop_front()
		jars.erase(old)
		old.queue_free()
	if whole < OUT_JARS_MAX:
		_spawn_outside_jar(true)


func _spawn_outside_jar(check_player: bool) -> bool:
	var surf: Node = get_parent().get_node_or_null("Level/Surface")
	if surf == null:
		return false
	var placed: Array = []
	for j in jars:
		if is_instance_valid(j) and not j.broken:
			placed.append([j.position, 0.17 * float(j.size)])
	for t in 40:
		var ang := randf() * TAU
		var rad := randf_range(2.0, Surface.MEADOW_R + 3.0)
		var p := Surface.CENTER + Vector3(cos(ang), 0, sin(ang)) * rad
		if Surface.in_hut(p, 1.0) or Vector2(p.x - Surface.CAR_POS.x, p.z - Surface.CAR_POS.z).length() < Surface.CAR_R:
			continue
		if check_player and player and Vector2(p.x - player.global_position.x, p.z - player.global_position.z).length() < 6.0:
			continue
		p.y = surf.height(p.x, p.z) - 0.02
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var prm := Jar.random_params(rng)
		var r := 0.17 * float(prm["size"])
		if _jar_spot_ok(p, r + 0.35, placed):
			_make_jar(p, randf() * TAU, prm, false)
			return true
	return false


## Группа из 1–3 сосудов вдоль стены (или у руин): каждый прижат к опоре на свой радиус.
func _jar_group(rng: RandomNumberGenerator, anchor: Vector3, along: Vector3, front: Vector3, placed: Array, inside: bool, surf: Node = null) -> int:
	var made := 0
	var n := rng.randi_range(1, 3)
	var off := 0.0
	for k in n:
		var prm := Jar.random_params(rng)
		var r := 0.17 * float(prm["size"])
		var p := anchor + along * off
		if inside:
			p -= front * (0.33 - r - 0.06)   # anchor — в 0.33 м от стены; ставим вплотную
		else:
			p += front * 0.0
			p.y = surf.height(p.x, p.z) - 0.02
		if _jar_spot_ok(p, r, placed):
			placed.append([p, r])
			_make_jar(p, rng.randf() * TAU, prm, false)
			made += 1
		off += (r * 2.0 + 0.12) * (1.0 if k % 2 == 0 else -1.0) * (k + 1)
	return made


func _jar_spot_ok(p: Vector3, r: float, placed: Array) -> bool:
	for c in placed:
		if Vector2(p.x - c[0].x, p.z - c[0].z).length() < r + float(c[1]) + 0.08:
			return false
	if p.y < 1.0:
		for a in CHEST_AVOID:
			if Vector2(p.x - a[0].x, p.z - a[0].z).length() < float(a[1]):
				return false
		if glass_floor:
			for g in glass_floor.spots:
				if Vector2(p.x - g[0].x, p.z - g[0].z).length() < float(g[1]) + 0.6:
					return false
	var q := PhysicsShapeQueryParameters3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = r
	cyl.height = 0.3
	q.shape = cyl
	q.transform = Transform3D(Basis(), p + Vector3(0, 0.22, 0))
	q.collision_mask = 1
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func _make_jar(pos: Vector3, rot: float, prm: Dictionary, was_broken: bool) -> void:
	var j := Jar.new()
	j.game = self
	j.setup(prm)
	j.broken = was_broken
	j.position = pos
	j.rotation.y = rot
	add_child(j)
	jars.append(j)


## Точка у случайной стены случайной комнаты бункера; поворот — передом (+Z ящика) в комнату.
func _bunker_chest_spot() -> Array:
	var sx := -1.0 if randf() < 0.5 else 1.0
	var sz := -1.0 if randf() < 0.5 else 1.0
	var x0 := 0.15 if sx > 0 else -11.85
	var x1 := 11.85 if sx > 0 else -0.15
	var z0 := 1.75 if sz > 0 else -8.85
	var z1 := 8.85 if sz > 0 else -1.75
	var off := 0.33          # половина глубины ящика + зазор
	var pos: Vector3
	var rot: float
	match randi() % 4:
		0:   # дальняя стена комнаты
			pos = Vector3(randf_range(x0 + 0.8, x1 - 0.8), 0, sz * (8.85 - off))
			rot = 0.0 if sz < 0 else PI
		1:   # стена коридора
			pos = Vector3(randf_range(x0 + 0.8, x1 - 0.8), 0, sz * (1.75 + off))
			rot = PI if sz < 0 else 0.0
		2:   # торцевая стена бункера
			pos = Vector3(sx * (11.85 - off), 0, randf_range(z0 + 0.8, z1 - 0.8))
			rot = -sx * PI / 2.0
		_:   # перегородка между комнатами
			pos = Vector3(sx * (0.15 + off), 0, randf_range(z0 + 0.8, z1 - 0.8))
			rot = sx * PI / 2.0
	return [pos, rot + randf_range(-0.06, 0.06)]


func _spawn_enemy(pos: Vector3) -> void:
	var e := Enemy.new()
	e.game = self
	e.kind = "fast" if randf() < FAST_SHARE else "heavy"   # смешанные типы (промпт 14.11 18:08)
	e.position = pos
	e.rotation.y = randf_range(0, TAU)
	add_child(e)
	e.died.connect(func(_e): _respawn_enemy_later(pos))


func _respawn_enemy_later(pos: Vector3) -> void:
	await get_tree().create_timer(RESPAWN).timeout
	while is_instance_valid(player) and player.global_position.distance_to(pos) < 8.0:
		await get_tree().create_timer(5.0).timeout
	_spawn_enemy(pos)


func _make_sounds() -> void:
	snd["coin"] = [Sfx2.coin(0), Sfx2.coin(1), Sfx2.coin(2)]
	snd["creak"] = [Sfx2.creak(0), Sfx2.creak(1)]
	snd["click"] = [Sfx2.click()]
	snd["tick"] = [Sfx2.tick()]
	snd["clunk"] = [Sfx2.clunk()]
	snd["jingle"] = [Sfx2.jingle()]
	snd["buzz"] = [Sfx2.buzz()]
	snd["growl"] = [Sfx2.growl(0), Sfx2.growl(1), Sfx2.growl(2)]
	snd["thud"] = [Sfx2.thud()]
	snd["pickup"] = [Sfx2.pickup()]
	snd["dread"] = [Sfx2.dread()]
	snd["estep"] = [Sfx.step(10), Sfx.step(11), Sfx.step(12), Sfx.step(13)]   # шаги врагов
	snd["whoosh"] = [Sfx.whoosh(1), Sfx.whoosh(2)]
	snd["hurt"] = [Sfx.exhale(1), Sfx.exhale(3)]


func play_ui(name_: String, db: float, pitch := 1.0) -> void:
	var set_: Array = snd[name_]
	ui_player.stream = set_[randi() % set_.size()]
	ui_player.volume_db = db
	ui_player.pitch_scale = pitch * randf_range(0.95, 1.05)
	ui_player.play()


func play_at(name_: String, pos: Vector3, db: float, pitch := 1.0) -> void:
	var set_: Array = snd[name_]
	var p := AudioStreamPlayer3D.new()
	p.stream = set_[randi() % set_.size()]
	p.volume_db = db
	p.unit_size = 4.0
	p.pitch_scale = pitch * randf_range(0.95, 1.05)
	add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


func _setup_input() -> void:
	_add_keys("interact", [KEY_E])
	_add_keys("inventory", [KEY_TAB, KEY_I])
	_add_keys("flashlight", [KEY_F])
	_add_keys("quick_heal", [KEY_Q])


func _add_keys(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


# ---------- взаимодействие ----------

func _physics_process(delta: float) -> void:
	full_toast_t -= delta
	if alive:
		play_time += delta
	_outside_jar_tick(delta)
	autosave_t -= delta
	if autosave_t <= 0.0:
		autosave_t = AUTOSAVE
		save_now()
	if player == null:
		return
	focus = null
	var text := ""
	_glass(delta)
	_tick_buffs(delta)
	if alive:
		var from := player.cam.global_position
		var q := PhysicsRayQueryParameters3D.create(from, from - player.cam.global_transform.basis.z * 2.3)
		q.collision_mask = 1
		q.exclude = [player.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		var hit_d := 99.0
		if hit and hit.collider.has_method("interact"):
			focus = hit.collider
			text = hit.collider.get_prompt(self)
			hit_d = from.distance_to(hit.position)
		# лежащий предмет под прицелом (pickup.gd) — ближе, чем другая цель
		var pk := _aimed_pickup(from, -player.cam.global_transform.basis.z)
		if pk != null and from.distance_to(pk.global_position) < hit_d:
			focus = pk
			text = pk.get_prompt(self)
	hud.prompt(text)


## Предмет на полу, на который смотрит игрок: в пределах Pickup.REACH, в узком конусе взгляда
## (чем ближе, тем шире — маленькую вещь легко навести), и не за стеной.
func _aimed_pickup(from: Vector3, fwd: Vector3) -> Node:
	var best: Node = null
	var best_a := 99.0
	for p in get_tree().get_nodes_in_group("pickup"):
		if p.taken:
			continue
		var to: Vector3 = p.global_position + Vector3(0, 0.06, 0) - from
		var d := to.length()
		if d > Pickup.REACH or d < 0.05:
			continue
		var a := fwd.angle_to(to)
		if a > maxf(deg_to_rad(8.0), atan(0.3 / d)) or a >= best_a:
			continue
		var q := PhysicsRayQueryParameters3D.create(from, from + to * 0.97)
		q.collision_mask = 1
		q.exclude = [player.get_rid()]
		if get_world_3d().direct_space_state.intersect_ray(q):
			continue
		best = p
		best_a = a
	return best


## Одно окно за раз: пока открыт инвентарь или магазин, другие окна не открываются.
func window_open() -> bool:
	return (inv != null and inv.open) or (shop != null and shop.opened) or (slot != null and slot.pack_open) \
		or (loot_window != null and loot_window.open)


## Открыть окно лута: obj с полем contents [[id, n], ...] (ящик, сейф, сундук, кувшин…).
func open_loot(c) -> void:
	if not alive or (window_open() and not (loot_window and loot_window.open)):
		return
	loot_window.show_for(c)


## Разовый лут (разбитый кувшин/колба): окно с items [[id, n], ...]; не взятое высыпется на пол в pos.
func open_loot_items(items: Array, pos: Vector3, title := "ЛУТ") -> void:
	var bag := LootWindow.LootBag.new()
	bag.game = self
	bag.pos = pos
	bag.loot_title = title
	for it in items:
		bag.contents.append([String(it[0]), int(it[1])])
	if not alive or window_open():
		bag.on_loot_closed()
		return
	loot_window.show_for(bag)


func _unhandled_input(e: InputEvent) -> void:
	if not alive or player == null or window_open():
		return
	if e.is_action_pressed("interact") and not e.is_echo():
		if focus != null and is_instance_valid(focus):
			focus.interact(self)
	elif e.is_action_pressed("flashlight") and flashlight:
		flashlight.toggle()
	elif e.is_action_pressed("quick_heal"):
		_quick_heal()
	else:
		for k in 5:
			if e.is_action_pressed("hot_%d" % (k + 1)):
				hotbar_use(k)


# ---------- стекло и кровотечение (промпт 20:02) ----------
## Битое стекло на полу (те же места, что в level.gd: _floor_litter): наступил — −5 здоровья
## и кровотечение 10 с по 3 в секунду. Повторный наступ обновляет таймер. Снимает бинт или аптечка.
var loot_window: LootWindow   # окно лута ящиков и сейфа
var storage: Chest            # сундук-хранилище
var glass_floor: GlassFloor   # кучки стекла (glass_floor.gd), случайные каждую новую игру
const BLEED_TIME := 10.0
const BLEED_DPS := 3.0
var on_glass := false
var last_feet_pos := Vector3.INF
var glass_cd := 0.0
var bleed_t := 0.0


func _glass(delta: float) -> void:
	glass_cd -= delta
	# сапоги стираются от ходьбы: 1 прочности за 8 м
	var pp0 := player.global_position
	if inv.equip["feet"] != "" and player.is_on_floor() and last_feet_pos != Vector3.INF:
		var step := Vector2(pp0.x - last_feet_pos.x, pp0.z - last_feet_pos.z).length()
		if step < 1.0:
			_wear("feet", step / 8.0)
	last_feet_pos = pp0
	if bleed_t > 0.0:
		bleed_t = maxf(bleed_t - delta, 0.0)
		drain_hp(BLEED_DPS * delta)
		if not alive:
			bleed_t = 0.0
	hud.bleed = bleed_t
	var pp := player.global_position
	var now := false
	if alive and player.is_on_floor() and pp.y < 0.4:
		for g in glass_floor.spots:
			var c: Vector3 = g[0]
			if Vector2(pp.x - c.x, pp.z - c.z).length() < float(g[1]) + 0.1:
				now = true
	if now and not on_glass and glass_cd <= 0.0 and Items.ITEMS.get(inv.equip["feet"], {}).get("glassproof", false):
		glass_cd = 1.5
		play_ui("tick", -22.0, 0.6)      # хруст под сапогом — без урона, но сапоги теряют 20% прочности
		_wear("feet", Items.max_dur(inv.equip["feet"]) * 0.2)
	elif now and not on_glass and glass_cd <= 0.0:
		glass_cd = 1.5
		drain_hp(5.0)
		if alive:
			bleed_t = BLEED_TIME
			hud.hurt_flash(0.5)
			hud.toast("Стекло! Кровотечение", Color(1.0, 0.4, 0.3))
			play_ui("hurt", -17.0, 0.9)
	on_glass = now


# ---------- прочность (промпт 21:46) ----------

## Попадание по врагу/манекену/ящику: изнашивается оружие в бьющей руке (player.last_arm).
func weapon_hit() -> void:
	if player == null or player.last_arm < 0:
		return
	_wear("left" if player.last_arm == 0 else "right", 1.0)


## Снять прочность с надетой вещи; на нуле вещь ломается и пропадает.
func _wear(slot_: String, amount: float) -> void:
	var id: String = inv.equip[slot_]
	if id == "" or Items.max_dur(id) <= 0.0:
		return
	var d: float = float(inv.equip_dur.get(slot_, Items.max_dur(id))) - amount
	inv.equip_dur[slot_] = d
	if d <= 0.0:
		inv.equip[slot_] = ""
		inv.equip_dur.erase(slot_)
		_apply_equip(slot_)
		hud.toast("Сломано: %s" % Items.item_name(id) if id != "boots" else "Сапоги развалились", Color(1.0, 0.5, 0.35))
		play_ui("thud", -10.0, 1.6)
		inv.notify()
	elif inv.open:
		inv._refresh()


## Бинт или аптечка останавливают кровотечение. true — было что останавливать.
func stop_bleeding() -> bool:
	if bleed_t <= 0.0:
		return false
	bleed_t = 0.0
	hud.toast("Кровотечение остановлено", Color(0.7, 0.9, 0.6))
	return true


# ---------- баффы еды и напитков (промпт 20:06) ----------
## buffs[тип] = {"power": доля, "time": осталось, "icon": предмет}; тип — resist (еда) или speed (напитки).
## Новый бафф того же типа: сила — бо́льшая из двух, время — бо́льшее из двух.
var buffs := {}


func add_buff(id: String) -> void:
	var def: Dictionary = Items.ITEMS[id]
	var kind: String = def["buff"]
	var cur: Dictionary = buffs.get(kind, {"power": 0.0, "time": 0.0, "icon": id})
	var stronger: bool = float(def["power"]) >= float(cur["power"])
	buffs[kind] = {
		"power": maxf(cur["power"], def["power"]),
		"time": maxf(cur["time"], def["time"]),
		"icon": id if stronger else cur["icon"],
	}
	hud.buffs = buffs


func buff_mult(kind: String) -> float:
	var gear := 1.0 + gear_sum("speed") if kind == "speed" else 1.0
	if not buffs.has(kind):
		return gear
	var p: float = buffs[kind]["power"]
	return (1.0 + p) * gear if kind == "speed" else 1.0 - p


## Сумма свойства по надетой одежде (armor — доля защиты, speed — прибавка скорости).
func gear_sum(prop: String) -> float:
	var t := 0.0
	for k in inv.equip:
		var id: String = inv.equip[k]
		if id != "":
			t += float(Items.ITEMS[id].get(prop, 0.0))
	return t


func gear_armor() -> float:
	return minf(gear_sum("armor"), 0.6)


func _tick_buffs(delta: float) -> void:
	for k in buffs.keys():
		buffs[k]["time"] -= delta
		if buffs[k]["time"] <= 0.0:
			buffs.erase(k)
			hud.toast("Бафф закончился: %s" % ("скорость" if k == "speed" else "защита"), Color(0.75, 0.72, 0.65))
	hud.buffs = buffs


# ---------- здоровье ----------

func damage_player(amount: float, from: Vector3) -> void:
	if not alive:
		return
	# щит в левой руке: половина ударов блокируется полностью
	if inv.equip["left"] == "shield" and randf() < 0.5:
		hud.block_flash()
		_wear("left", 1.0)
		play_ui("clunk", -6.0, 0.8)
		var bpush := player.global_position - from
		bpush.y = 0.0
		player.velocity += bpush.normalized() * 2.0
		Fx.popup_text(self, player.global_position + Vector3(0, 1.4, 0) - player.global_transform.basis.z * 0.8, "БЛОК", Color(0.6, 0.85, 1.0))
		return
	amount *= buff_mult("resist") * (1.0 - gear_armor())
	# одежда с защитой изнашивается от ударов (чинит ремкомплект одежды)
	for sl in ["head", "body", "legs"]:
		_wear(sl, 1.0)
	hp = maxf(hp - amount, 0.0)
	hud.set_hp(hp, MAX_HP)
	hud.hurt_flash()
	var push := player.global_position - from
	push.y = 0.0
	player.velocity += push.normalized() * 4.5 + Vector3(0, 2.0, 0)
	var tw := create_tween()
	tw.tween_property(player.cam, "rotation:z", randf_range(-0.07, 0.07), 0.05)
	tw.tween_property(player.cam, "rotation:z", 0.0, 0.25)
	play_ui("hurt", -9.0, 0.75)
	if hp <= 0.0:
		_die()


## Тихая потеря здоровья (отравление) — без отброса и вспышки.
func drain_hp(amount: float) -> void:
	if not alive:
		return
	hp = maxf(hp - amount, 0.0)
	hud.set_hp(hp, MAX_HP)
	if hp <= 0.0:
		_die()


func heal(amount: float) -> void:
	hp = minf(hp + amount, MAX_HP)
	hud.set_hp(hp, MAX_HP)


func _die() -> void:
	alive = false
	player.active = false
	inv.close()
	inv.enabled = false
	hud.show_death(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Сел в машину (car.gd): игрок больше не управляется, враги и отрава его не трогают, HUD прячется.
func begin_escape() -> void:
	alive = false
	won = true
	player.active = false
	inv.close()
	inv.enabled = false
	if loot_window and loot_window.open:
		loot_window.close()
	hud.set_cinematic(true)
	if gasmask:
		gasmask.visible = false
	for n in get_parent().get_children():
		if n.get_script() == preload("res://touch_controls.gd"):
			n.visible = false


## Машина уехала: экран победы со статистикой.
func win() -> void:
	var s := int(play_time)
	hud.show_win("Время: %d:%02d   ·   Монет: %d" % [s / 60, s % 60, inv.coins])


## «В главное меню» с экрана победы.
func to_main_menu() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().reload_current_scene()


## «Начать заново»: полный сброс — сцена перезагружается и сразу стартует игра (main.gd), минуя меню.
func restart() -> void:
	Engine.set_meta("eskiness_autostart", true)
	Engine.set_meta("eskiness_load", false)    # новая игра в том же слоте
	get_tree().paused = false
	get_tree().reload_current_scene()


func _quick_heal() -> void:
	if bleed_t > 0.0:
		for bid in ["bandage", "medkit"]:
			var bi := inv.bag_index(bid)
			if bi >= 0:
				use_item(bi)
				return
	if hp >= MAX_HP:
		hud.toast("Здоровье и так полное")
		return
	# самое маленькое лечение, которого хватает; иначе самое большое
	var need := MAX_HP - hp
	var best := ""
	var best_v := INF
	var biggest := ""
	var biggest_v := 0.0
	for id in Items.ITEMS:
		if not Items.ITEMS[id].has("heal"):
			continue
		if inv.count(id) == 0:
			continue
		var v: float = Items.ITEMS[id]["heal"]
		if v >= need and v < best_v:
			best = id
			best_v = v
		if v > biggest_v:
			biggest = id
			biggest_v = v
	var pick := best if best != "" else biggest
	if pick == "":
		hud.toast("Нечем лечиться")
		return
	inv.remove(pick, 1)
	heal(Items.ITEMS[pick]["heal"])
	hud.toast("%s: +%d здоровья" % [Items.item_name(pick), int(Items.ITEMS[pick]["heal"])], Color(0.7, 0.9, 0.6))
	play_ui("pickup", -12.0, 0.8)


# ---------- предметы ----------

func use_item(idx: int) -> void:
	var s = inv.slots[idx]
	if s == null:
		return
	var id: String = s["id"]
	var def: Dictionary = Items.ITEMS[id]
	if def.has("repair"):
		repair(idx, _most_worn(String(def["repair"])))
	elif def.has("buff"):
		inv.take_at(idx, 1)
		add_buff(id)
		var what := "−%d%% урона" % int(float(def["power"]) * 100) if def["buff"] == "resist" else "+%d%% скорости" % int(float(def["power"]) * 100)
		hud.toast("%s: %s на %d с" % [def["name"], what, int(def["time"])], Color(0.8, 0.9, 0.6))
		play_ui("pickup", -12.0, 0.9)
	elif def.has("heal"):
		var stops := id in ["bandage", "medkit"] and bleed_t > 0.0
		if hp >= MAX_HP and not stops:
			hud.toast("Здоровье и так полное")
			return
		inv.take_at(idx, 1)
		heal(def["heal"])
		if stops:
			stop_bleeding()
		hud.toast("%s: +%d здоровья" % [def["name"], int(def["heal"])], Color(0.7, 0.9, 0.6))
		play_ui("pickup", -12.0, 0.8)
	elif id == "broom":
		var gi := glass_floor.nearest(player.global_position, 1.8)
		if gi < 0:
			hud.toast("Рядом нет стекла")
		else:
			var c: Vector3 = glass_floor.spots[gi][0]
			glass_floor.sweep(gi)
			Fx.dust_burst(self, c + Vector3(0, 0.1, 0), Color(0.42, 0.4, 0.37), 12)
			play_at("creak", c, -18.0, 2.2)
			hud.toast("Стекло выметено", Color(0.8, 0.85, 0.7))
	elif id == "flashlight":
		if flashlight:
			flashlight.toggle()
	elif id == "battery":
		if flashlight == null:
			return
		if flashlight.charge >= 0.99:
			hud.toast("Фонарик и так заряжен")
			return
		inv.take_at(idx, 1)
		flashlight.recharge()
		hud.toast("Фонарик заряжен", Color(0.9, 0.85, 0.55))
		play_ui("click", -12.0)
	elif Items.equip_slot(id) == "hand":
		# оружие: в свободную руку (сначала правая), обе заняты — меняем правую
		var hand := "right" if inv.equip["right"] == "" or inv.equip["left"] != "" else "left"
		equip(idx, hand)
	elif Items.equip_slot(id) != "":
		equip(idx, Items.equip_slot(id))
	elif id == "filter":
		hud.toast("Фильтр ставится сам")
	elif id == "coin":
		pass
	elif id == "car_key":
		hud.toast("Ключ от машины на поляне — подойди к ней и нажми E")
	elif id == "wallet":
		inv.take_at(idx, 1)
		var c := randi_range(10, 40)
		inv.add("coin", c)
		hud.toast("В кошельке нашлось %d монет" % c, Color(0.92, 0.82, 0.55))
		play_ui("coin", -11.0)
	else:
		hud.toast("Это нельзя использовать")


# ---------- экипировка, хотбар, крафт ----------

## Надеть предмет из ячейки idx в слот (что было в слоте — встаёт на его место в сумке).
func equip(idx: int, slot_: String) -> void:
	var s = inv.slots[idx]
	if s == null or not Items.fits(s["id"], slot_):
		return
	var id: String = s["id"]
	var prev: String = inv.equip[slot_]
	var prev_d: float = inv.equip_dur.get(slot_, Items.max_dur(prev))
	var new_d: float = float(s.get("dur", Items.max_dur(id)))
	inv.slots[idx] = {"id": prev, "n": 1, "dur": prev_d} if prev != "" else null
	inv.equip[slot_] = id
	inv.equip_dur[slot_] = new_d
	_apply_equip(slot_)
	inv.notify()
	play_ui("click", -10.0, 0.8)


## Снять в ячейку to (или в первую свободную). false — некуда.
func unequip(slot_: String, to := -1) -> bool:
	var id: String = inv.equip[slot_]
	if id == "":
		return false
	if to >= 0 and inv.slots[to] != null:
		if Items.fits(inv.slots[to]["id"], slot_):
			equip(to, slot_)       # обмен
			return true
		to = -1
	# рюкзак: сначала вещи из его ячеек — в основные; не влезли — не снимаем
	var limit := -1
	if slot_ == "back":
		if not _empty_backpack():
			return false
		limit = inv.BAG
		if to >= limit:
			to = -1
	if to < 0:
		to = inv.free_cell(limit)
	if to < 0:
		hud.toast("Сумка полна — некуда снять")
		return false
	inv.slots[to] = {"id": id, "n": 1, "dur": float(inv.equip_dur.get(slot_, Items.max_dur(id)))}
	inv.equip_dur.erase(slot_)
	inv.equip[slot_] = ""
	_apply_equip(slot_)
	inv.notify()
	play_ui("click", -12.0, 0.7)
	return true


func drop_equipped(slot_: String) -> void:
	var id: String = inv.equip[slot_]
	if id == "":
		return
	if slot_ == "back" and not _empty_backpack():
		return
	var d: float = inv.equip_dur.get(slot_, Items.max_dur(id))
	inv.equip[slot_] = ""
	inv.equip_dur.erase(slot_)
	_apply_equip(slot_)
	inv.notify()
	var fwd := -player.global_transform.basis.z
	var p := _make_pickup(id, 1, player.global_position + Vector3(0, 1.2, 0) + fwd * 0.5, fwd * 2.0 + Vector3(0, 1.0, 0))
	p.need_leave = true
	if Items.max_dur(id) > 0.0:
		p.set_meta("dur", d)


## Перед тем как снять рюкзак: вещи из его ячеек — в свободные основные. false — не влезли (рюкзак остаётся).
func _empty_backpack() -> bool:
	if inv.free_extra():
		return true
	hud.toast("Рюкзак не снять: в сумке нет места для вещей из него", Color(0.95, 0.6, 0.45))
	play_ui("buzz", -14.0)
	return false


func _apply_equip(slot_: String) -> void:
	var id: String = inv.equip[slot_]
	match slot_:
		"left", "right":
			var arm := 0 if slot_ == "left" else 1
			player.set_weapon(id, arm)
			if id != "" and not loading:
				hud.toast("%s — %s рука" % [Items.item_name(id), "левая" if arm == 0 else "правая"], Color(0.9, 0.85, 0.7))
		"face":
			# противогаз — в слоте «Лицо», каска при этом остаётся на голове
			if gasmask:
				gasmask.set_worn(id == "gasmask", loading)
			if id != "" and id != "gasmask" and not loading:
				hud.toast("Надето: %s" % Items.item_name(id), Color(0.9, 0.85, 0.7))
		"back":
			# рюкзак: +ячейки сумки (снимают его только с пустыми доп. ячейками — unequip/drop_equipped)
			inv.set_capacity(inv.BAG + (int(Items.ITEMS[id].get("bag", 0)) if id != "" else 0))
			if id != "" and not loading:
				hud.toast("Надето: %s (+%d ячеек)" % [Items.item_name(id), int(Items.ITEMS[id].get("bag", 0))], Color(0.9, 0.85, 0.7))
		"head":
			if id != "" and not loading:
				hud.toast("Надето: %s" % Items.item_name(id), Color(0.9, 0.85, 0.7))
		"hands":
			player.dmg_mult = float(Items.ITEMS[id].get("fist", 1.0)) if id != "" else 1.0
			hud.knuckles = id == "knuckles"
			if id != "" and not loading:
				hud.toast("Надето: %s" % Items.item_name(id), Color(0.9, 0.85, 0.7))
		"body", "legs", "feet":
			if id != "" and not loading:
				hud.toast("Надето: %s" % Items.item_name(id), Color(0.9, 0.85, 0.7))


## G: надеть противогаз из сумки / снять его.
func toggle_gasmask() -> void:
	if inv.equip["face"] == "gasmask":
		unequip("face")
		return
	var i := inv.bag_index("gasmask")
	if i < 0:
		hud.toast("Нюхича нет")
		return
	equip(i, "face")


## Клавиша 1–5: использовать привязанный предмет; надетый — снять.
func hotbar_use(k: int) -> void:
	var id: String = inv.hotbar[k]
	if id == "":
		return
	for sl in inv.equip:
		if inv.equip[sl] == id:
			unequip(sl)
			return
	var i := inv.bag_index(id)
	if i < 0:
		hud.toast("Нет: %s" % Items.item_name(id))
		return
	use_item(i)


# ---------- ремкомплекты (промпт 14.11 17:59) ----------

const REPAIR_PART := 0.5    # один заряд — +50% прочности

## Самая побитая вещь под этот комплект: надетое и сумка. null — чинить нечего.
func _most_worn(kind: String):
	var best = null
	var best_fr := 1.0
	var keys: Array = []
	for k in inv.equip:
		keys.append(k)
	for i in inv.slots.size():
		keys.append(i)
	for k in keys:
		var id: String = inv.equip[k] if k is String else (String(inv.slots[k]["id"]) if inv.slots[k] != null else "")
		if Items.repairable(id) != kind:
			continue
		var fr: float = inv.get_dur(k) / Items.max_dur(id)
		if fr < best_fr - 0.001:
			best_fr = fr
			best = k
	return best


## Починить вещь target (ячейка или слот) ремкомплектом из ячейки kit_idx: −1 заряд, на нуле комплект исчезает.
func repair(kit_idx: int, target) -> void:
	var kit = inv.slots[kit_idx]
	if kit == null or not Items.ITEMS[kit["id"]].has("repair"):
		return
	var kind: String = Items.ITEMS[kit["id"]]["repair"]
	if target == null:
		hud.toast("Чинить нечего — всё целое")
		return
	var id: String = inv.equip[target] if target is String else (String(inv.slots[target]["id"]) if inv.slots[target] != null else "")
	if Items.repairable(id) != kind:
		hud.toast("%s этим не починить" % Items.item_name(id))
		return
	var mx := Items.max_dur(id)
	var cur: float = inv.get_dur(target)
	if cur >= mx - 0.01:
		hud.toast("%s и так целое" % Items.item_name(id))
		return
	var nd := minf(cur + mx * REPAIR_PART, mx)
	if target is String:
		inv.equip_dur[target] = nd
	else:
		inv.slots[target]["dur"] = nd
	var left: float = inv.get_dur(kit_idx) - 1.0
	if left <= 0.0:
		inv.slots[kit_idx] = null
	else:
		kit["dur"] = left
	hud.toast("Починено: %s (%d%%)%s" % [Items.item_name(id), int(round(nd / mx * 100.0)),
		"" if left > 0.0 else " — ремкомплект закончился"], Color(0.8, 0.9, 0.6))
	play_ui("creak", -12.0, 1.4)
	inv.notify()


func craft(r: int) -> void:
	var rec: Dictionary = Items.RECIPES[r]
	var need: Dictionary = rec["need"]
	for id in need:
		if inv.count(id) < int(need[id]):
			hud.toast("Не хватает: %s" % Items.item_name(id))
			return
	for id in need:
		inv.remove(id, int(need[id]))
	var out: String = rec["out"]
	if inv.add(out, 1) > 0:
		var fwd := -player.global_transform.basis.z
		_make_pickup(out, 1, player.global_position + Vector3(0, 1.0, 0) + fwd * 0.4, Vector3.ZERO).need_leave = true
		hud.toast("Сумка полна — %s на полу" % Items.item_name(out))
	else:
		hud.toast("Скрафчено: %s" % Items.item_name(out), Color(0.8, 0.9, 0.6))
	play_ui("creak", -14.0, 1.6)


func drop_item(idx: int, all: bool) -> void:
	var s = inv.slots[idx]
	if s == null:
		return
	drop_count(idx, int(s["n"]) if all else 1)


func drop_count(idx: int, n: int) -> void:
	var dur: float = float(inv.slots[idx].get("dur", -1.0)) if inv.slots[idx] != null else -1.0
	var got: Array = inv.take_at(idx, n)
	if got[1] <= 0:
		return
	var fwd := -player.global_transform.basis.z
	var pos := player.global_position + Vector3(0, 1.2, 0) + fwd * 0.5
	var p := _make_pickup(got[0], got[1], pos, fwd * 2.0 + Vector3(0, 1.0, 0))
	p.need_leave = true
	if dur >= 0.0:
		p.set_meta("dur", dur)


## Выбросить монеты из кошелька (запоминаем сколько — см. анти-мухлёж в cheat_check).
func drop_coins(n: int) -> void:
	n = mini(n, inv.coins)
	if n <= 0 or not inv.remove("coin", n):
		return
	dropped_coins += n
	var fwd := -player.global_transform.basis.z
	var pos := player.global_position + Vector3(0, 1.2, 0) + fwd * 0.5
	var parts := clampi(n, 1, 6)
	for k in parts:
		var cnt := n / parts + (1 if k < n % parts else 0)
		var p := _make_pickup("coin", cnt, pos, fwd * 2.0 + Vector3(randf_range(-0.6, 0.6), 1.0, randf_range(-0.6, 0.6)))
		p.need_leave = true
		p.set_meta("dropped", true)
	play_ui("coin", -11.0, 0.9)


# ---------- анти-мухлёж ----------
## Выбросил много монет (CHEAT_DROP+), оставил себе мало (≤ CHEAT_KEEP) и пошёл крутить KILLBOX —
## с поверхности по лестнице спускаются 5 монстров и охотятся на игрока прямо в бункере.
## Подобрал выброшенные монеты обратно — счётчик уменьшается.
const CHEAT_DROP := 10        # стартовых монет мало, поэтому порог низкий (промпт 23:59)
const CHEAT_KEEP := 20
var dropped_coins := 0
var chests: Array = []


## Магазин: закрыть все открытые ящики — при новом открытии в них будет новый лут. Сейф не трогаем.
func refresh_chests() -> int:
	var n := 0
	for c in chests:
		if is_instance_valid(c) and c.opened:
			c.reset()
			n += 1
	return n
var hunters: Array = []


## Наценка за мухлёж (промпт 14.11 18:10): каждая поимка +1 к cheat_count; на одну следующую покупку
## в Trinkets Market цена × (1 + 10% × cheat_count), вверх. Купил — наценка снята до следующей поимки.
var cheat_count := 0
var markup_pending := false


func markup_pct() -> int:
	return 10 * cheat_count if markup_pending else 0


func marked_price(p: int) -> int:
	return (p * (100 + markup_pct()) + 99) / 100


func markup_used() -> void:
	markup_pending = false


## Вызывает автомат после оплаты крутки. true — мухлёж пойман.
func cheat_check() -> bool:
	if dropped_coins < CHEAT_DROP or inv.coins > CHEAT_KEEP or dropped_coins < inv.coins:
		return false
	dropped_coins = 0
	cheat_count += 1
	markup_pending = true
	hud.cheat_warning(true)
	play_ui("dread", -1.0, 1.0)  # страшный звук за мухлёж (промпт 14.11 17:26)
	_spawn_hunters()
	return true


func _spawn_hunters(count := 5) -> void:
	for k in count:
		var e := Enemy.new()
		e.game = self
		e.position = Vector3(20.0 - (k % 2) * 0.8, 4.1, -0.6 + (k % 3) * 0.6)
		e.rotation.y = PI / 2.0
		add_child(e)
		e.make_hunter()
		hunters.append(e)
		e.died.connect(_hunter_died)
		await get_tree().create_timer(0.6).timeout


func _hunter_died(e: Node) -> void:
	hunters.erase(e)
	if hunters.is_empty():
		hud.cheat_warning(false)


## Высыпать лут: монеты разбиваются на несколько монеток, разлетаются с разбросом spread.
func spawn_loot(id: String, n: int, pos: Vector3, vel: Vector3, spread: float) -> void:
	var parts := 1
	if id == "coin":
		parts = clampi(n, 1, 6)
	var per := n / parts
	var rest := n - per * parts
	for k in parts:
		var cnt := per + (1 if k < rest else 0)
		var v := vel + Vector3(randf_range(-1, 1), randf_range(0, 0.6), randf_range(-1, 1)) * spread
		_make_pickup(id, cnt, pos + Vector3(randf_range(-0.1, 0.1), 0, randf_range(-0.1, 0.1)), v)


func _make_pickup(id: String, n: int, pos: Vector3, vel: Vector3) -> Pickup:
	var p := Pickup.new()
	p.game = self
	p.id = id
	p.n = n
	add_child(p)
	p.global_position = pos
	p.linear_velocity = vel
	p.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
	return p


## Вызывается лежащим предметом, когда игрок рядом. Возвращает, сколько не влезло.
func collect(id: String, n: int, from: Node = null) -> int:
	var d: float = float(from.get_meta("dur", -1.0)) if from != null else -1.0
	var left: int = inv.add(id, n, d)
	var got := n - left
	if id == "coin" and from != null and from.get_meta("dropped", false):
		dropped_coins = maxi(dropped_coins - got, 0)
	if got > 0:
		var nm := Items.item_name(id)
		hud.toast("+%d  %s" % [got, nm] if got > 1 else "+ " + nm, Color(0.92, 0.82, 0.55) if id == "coin" else Color(0.85, 0.85, 0.8))
		if id == "coin":
			play_ui("coin", -13.0)
		else:
			play_ui("pickup", -10.0)
	elif full_toast_t <= 0.0:
		full_toast_t = 3.0
		hud.toast("Инвентарь полон", Color(0.9, 0.5, 0.4))
	return left


# ---------- сохранения (промпт 23:39) ----------
## 3 слота (save.gd). Автосейв: каждые 2 минуты, после каждой крутки KILLBOX (и сразу после оплаты —
## перезагрузка не откатит проигрыш), при выходе в меню и при закрытии окна.
const AUTOSAVE := 120.0
var save_slot := 1
var autosave_t := AUTOSAVE
var loading := false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_now()


func save_now() -> void:
	if player == null or not alive:
		return
	Save.write(save_slot, save_state())


func _v3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


func _to_v3(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2])) if a is Array and a.size() == 3 else Vector3.ZERO


func save_state() -> Dictionary:
	var bag: Array = []
	for s in inv.slots:
		bag.append(s.duplicate() if s != null else null)
	var cs: Array = []
	var chest_pos: Array = []
	for c in chests:
		chest_pos.append([c.position.x, c.position.y, c.position.z, c.rotation.y] if is_instance_valid(c) else [0.0, -100.0, 0.0, 0.0])
		cs.append([c.opened, c.broken, c.contents.duplicate(true)] if is_instance_valid(c) else [false, false, []])
	var floor_items: Array = []
	for n in get_children():
		if n is Pickup and is_instance_valid(n) and not n.is_queued_for_deletion() and not n.taken:
			floor_items.append({"id": n.id, "n": n.n, "pos": _v3(n.global_position),
				"dur": float(n.get_meta("dur", -1.0)), "dropped": bool(n.get_meta("dropped", false))})
	var alive_hunters := 0
	for h in hunters:
		if is_instance_valid(h):
			alive_hunters += 1
	return {
		"version": 1,
		"coins": inv.coins,
		"bag": bag,
		"equip": inv.equip.duplicate(),
		"equip_dur": inv.equip_dur.duplicate(),
		"hotbar": inv.hotbar.duplicate(),
		"hp": hp,
		"bleed": bleed_t,
		"buffs": buffs.duplicate(true),
		"pos": _v3(player.global_position),
		"yaw": player.rotation.y,
		"pitch": player.head.rotation.x,
		"light_charge": flashlight.charge if flashlight else 0.0,
		"light_on": flashlight.on if flashlight else false,
		"filter": gasmask.filter_left if gasmask else 0.0,
		"tox": gasmask.tox if gasmask else 0.0,
		"chests": cs,
		"chest_pos": chest_pos,
		"tape_taken": tape != null and not tape.ready_,
		"jars": jars.filter(func(x): return is_instance_valid(x)).map(func(x): return x.to_save()),
		"safe_open": safe != null and is_instance_valid(safe) and safe.opened,
		"storage": storage.contents.duplicate(true) if storage else [],
		"safe_contents": safe.contents.duplicate(true) if safe != null and is_instance_valid(safe) else [],
		"floor": floor_items,
		"dropped_coins": dropped_coins,
		"hunters": alive_hunters,
		"glass": glass_floor.to_save(),
		"slot_credits": slot.credits if slot else 0,
		"slot_luck": slot.luck.duplicate(true) if slot else {},
		"slot_boost": slot.boost.duplicate(true) if slot else {},
		"slot_level": slot.level if slot else 1,
		"cheat_count": cheat_count,
		"markup_pending": markup_pending,
		"slot_tray": slot.tray_coins if slot else 0,
		"play_time": play_time,
	}


func load_state(d: Dictionary) -> void:
	loading = true
	inv.coins = int(d.get("coins", 0))
	var bag: Array = d.get("bag", [])
	var eq: Dictionary = d.get("equip", {}).duplicate()
	var ed: Dictionary = d.get("equip_dur", {}).duplicate()
	# старые сейвы: противогаз был в слоте «Голова» — переезжает в «Лицо»
	if String(eq.get("head", "")) == "gasmask" and String(eq.get("face", "")) == "":
		eq["face"] = "gasmask"
		eq["head"] = ""
		if ed.has("head"):
			ed["face"] = ed["head"]
			ed.erase("head")
	# рюкзак надет — сумка сразу шире, чтобы загрузились вещи из его ячеек
	var back_id := String(eq.get("back", ""))
	inv.set_capacity(inv.BAG + (int(Items.ITEMS[back_id].get("bag", 0)) if Items.ITEMS.has(back_id) else 0))
	for i in inv.slots.size():
		var s = bag[i] if i < bag.size() else null
		if s is Dictionary and Items.ITEMS.has(String(s.get("id", ""))):
			var e := {"id": String(s["id"]), "n": int(s.get("n", 1))}
			if s.has("dur"):
				e["dur"] = float(s["dur"])
			inv.slots[i] = e
		else:
			inv.slots[i] = null
	inv.equip_dur.clear()
	for k in inv.equip:
		var id: String = String(eq.get(k, ""))
		inv.equip[k] = id if Items.ITEMS.has(id) else ""
		if ed.has(k):
			inv.equip_dur[k] = float(ed[k])
		_apply_equip(k)
	var hb: Array = d.get("hotbar", [])
	for k in 5:
		inv.hotbar[k] = String(hb[k]) if k < hb.size() and hb[k] != null else ""
	hp = clampf(float(d.get("hp", MAX_HP)), 1.0, MAX_HP)
	hud.set_hp(hp, MAX_HP)
	bleed_t = float(d.get("bleed", 0.0))
	buffs = {}
	var bf: Dictionary = d.get("buffs", {})
	for k in bf:
		buffs[k] = {"power": float(bf[k]["power"]), "time": float(bf[k]["time"]), "icon": String(bf[k]["icon"])}
	player.global_position = _to_v3(d.get("pos", [START.x, START.y, START.z]))
	player.rotation.y = float(d.get("yaw", -PI / 2.0))
	player.head.rotation.x = float(d.get("pitch", 0.0))
	player.velocity = Vector3.ZERO
	if flashlight:
		flashlight.charge = float(d.get("light_charge", 0.6))
		if bool(d.get("light_on", false)) and inv.count("flashlight") > 0:
			flashlight.on = true
			flashlight.light.visible = true
	if gasmask:
		gasmask.filter_left = float(d.get("filter", 0.0))
		gasmask.tox = float(d.get("tox", 0.0))
	# расстановка ящиков из сейва (старые сейвы без chest_pos — остаётся новая случайная)
	if d.has("chest_pos"):
		for c in chests:
			if is_instance_valid(c):
				c.queue_free()
		chests = []
		for a in d["chest_pos"]:
			_chest(Vector3(float(a[0]), float(a[1]), float(a[2])), float(a[3]), [])
	# кувшины и колбы из сейва: то же место, вид, размер и рисунок; разбитые — осколками
	if tape:
		tape.set_taken(bool(d.get("tape_taken", false)))
	if d.has("jars"):
		for jr in jars:
			if is_instance_valid(jr):
				jr.queue_free()
		jars = []
		for a in d["jars"]:
			_make_jar(Vector3(float(a[0]), float(a[1]), float(a[2])), float(a[3]),
				{"kind": str(a[4]), "size": float(a[5]), "seed": int(a[6])}, bool(a[7]))
	var cs: Array = d.get("chests", [])
	for i in mini(cs.size(), chests.size()):
		chests[i].restore(bool(cs[i][0]), bool(cs[i][1]), cs[i][2] if cs[i].size() > 2 else [])
	if bool(d.get("safe_open", false)) and safe:
		safe.restore(true, false, d.get("safe_contents", []))
	# вещи на полу: убираем стартовые, раскладываем сохранённые
	for n in get_children():
		if n is Pickup:
			n.queue_free()
	for it in d.get("floor", []):
		var id: String = String(it.get("id", ""))
		if not Items.ITEMS.has(id):
			continue
		var p := _make_pickup(id, int(it.get("n", 1)), _to_v3(it.get("pos")) + Vector3(0, 0.05, 0), Vector3.ZERO)
		p.angular_velocity = Vector3.ZERO
		if float(it.get("dur", -1.0)) >= 0.0:
			p.set_meta("dur", float(it["dur"]))
		if bool(it.get("dropped", false)):
			p.set_meta("dropped", true)
	dropped_coins = int(d.get("dropped_coins", 0))
	if storage:
		storage.contents = []
		for it in d.get("storage", []):
			var e: Array = [String(it[0]), int(it[1])]
			if it.size() > 2:
				e.append(float(it[2]))
			storage.contents.append(e)
	play_time = float(d.get("play_time", 0.0))
	# сейвы до машины: сейф уже открыт, а ключа нигде нет — кладём его в сейф
	if safe and safe.opened:
		var has_key := inv.count("car_key") > 0
		for arr in [safe.contents, storage.contents if storage else [], d.get("floor", []).map(func(x): return [String(x.get("id", ""))])]:
			for it in arr:
				if String(it[0]) == "car_key":
					has_key = true
		if not has_key:
			safe.contents.append(["car_key", 1])
	if d.has("glass"):
		glass_floor.from_save(d["glass"])
	if slot:
		slot.credits = int(d.get("slot_credits", 0))
		slot.load_buffs(d.get("slot_luck", {}), d.get("slot_boost", {}))
		slot.set_level(int(d.get("slot_level", 1)))
		slot.set_tray(int(d.get("slot_tray", 0)))
		slot.screen.text = ""
		slot._update_screen_hint()
	cheat_count = int(d.get("cheat_count", 0))
	markup_pending = bool(d.get("markup_pending", false))
	var h := int(d.get("hunters", 0))
	if h > 0:
		hud.cheat_warning(true)
		_spawn_hunters(h)
	inv.notify()
	loading = false
	hud.toast("Загружено: слот %d" % save_slot, Color(0.8, 0.85, 0.7))
