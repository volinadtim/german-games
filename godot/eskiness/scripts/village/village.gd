extends "res://scripts/village/village_build.gd"
## Вторая локация — заброшенная деревня «Заречье» (промпты 15.11 23:01–23:20).
## Строится вместе с игрой (game.gd: setup) и стоит всегда: дорога от поляны ведёт сюда без загрузок.
## Машина после кат-сцены отъезда глохнет здесь (car.gd → stall_sequence): затемнение, надпись,
## игрок сидит в салоне. Вышел — надевается Нюхич, задание справа: дойти до дома и спрятаться в подвале.
## В подвале воздух чистый и стоит автомат «ФОРТУНА» (bonus_slot.gd). В деревне — бензин (канистра)
## и расходники для пистолета; залил бензин — машина едет (car_drive.gd), обратно к бункеру ~1 мин.
## Пешком по дороге ~3 мин — нужны фильтры. Здесь же бродят мутанты (mutant.gd).

const Pickup := preload("res://scripts/world/pickup.gd")
const BonusSlot := preload("res://scripts/village/bonus_slot.gd")
const Mutant := preload("res://scripts/village/mutant.gd")
const VillageShop := preload("res://scripts/village/village_shop.gd")
const ChestScript := preload("res://scripts/world/chest.gd")

var game                             # game.gd
var car                              # car.gd
var stage := 0                       # задание: 0 — нет, 1 — до подвала, 2 — найти бензин, 3 — залить, 4 — машина на ходу
var stage_t := 0.0
var loot_done := false               # лут деревни разложен (в сейве)
var bonus_slot: Node3D
var ui: CanvasLayer
var quest_box: PanelContainer
var quest_l: Label
var hint_l: Label
var card_bg: ColorRect
var card_l: Label
var marker: Label3D
var poll_t := 0.0
var mutants: Array = []
var mut_seq := 0
var shop                             # village_shop.gd — второй Trinkets Market в подвале
## Свой сундук во втором бункере (подвале) — отдельный от сундука первого (промпт 18.11 00:47), в сейве village.storage
var storage                          # chest.gd (kind "storage")
const STORAGE_POS := Vector3(38.9, B, 350.6)   # у южной стены, слева от «ФОРТУНЫ»
## Деревню не видно, пока туда нельзя уехать (промпт 16.11 00:17): дома, подвал, автомат, мутанты спрятаны
## до ключа от машины / отъезда / подхода к деревне пешком. Земля и дорога видны всегда.
var revealed := false
var hidden_nodes: Array = []
## Надпись «заглохла» и её пропуск (ui/cutscene_skip.gd)
var card_tw: Tween
var card_seat := -1
var card_moved := false
var card_after := false
var card_fast := false

## Где бродят мутанты деревни: [точка, вид]
const MUT_SPOTS := [
	[Vector3(27.0, G, 340.0), "spitter"], [Vector3(35.0, G, 352.0), "charger"], [Vector3(26.0, G, 368.0), "stalker"],
	[Vector3(36.0, G, 380.0), "spitter"], [Vector3(30.0, G, 324.0), "stalker"], [Vector3(33.0, G, 362.0), "charger"],
]
const MUT_RESPAWN := 70.0


func _ready() -> void:
	name = "Village"
	add_to_group("cutscene")
	rng.seed = 2311
	hn.seed = 17
	hn.frequency = 0.045
	hn.fractal_octaves = 2
	hn2.seed = 23
	hn2.frequency = 0.11
	hn2.fractal_octaves = 1
	_materials()
	_ground()
	_road()
	_bounds()
	var first := get_child_count()
	_basement_house()
	for h in HOUSES:
		var r := Rect2(float(h[0]) - float(h[2]) / 2.0, float(h[1]) - float(h[3]) / 2.0, float(h[2]), float(h[3]))
		loot_spots.append(_house(r, float(h[4])))
	_props()
	bonus_slot = BonusSlot.new()
	bonus_slot.position = SLOT_POS
	bonus_slot.rotation.y = PI
	add_child(bonus_slot)
	shop = VillageShop.new()
	shop.name = "VillageShop"
	shop.position = SHOP_POS
	shop.rotation.y = PI
	add_child(shop)
	storage = ChestScript.new()
	storage.name = "VillageStorage"
	storage.kind = "storage"
	storage.position = STORAGE_POS
	storage.rotation.y = PI
	add_child(storage)
	for k in range(first, get_child_count()):
		var n := get_child(k)
		if n is Node3D:
			n.visible = false
			hidden_nodes.append(n)
	_make_ui()


func setup_game(g) -> void:
	game = g
	bonus_slot.game = g
	shop.game = g
	storage.game = g
	if g.net == null or g.net.is_host():
		for s in MUT_SPOTS:
			_spawn_mutant(s[0], s[1])


# ---------- лут ----------

## Вещи в домах и подвале — один раз за игру (новая игра; в сети — у хоста, остальным придёт с миром).
func spawn_village_loot() -> void:
	if loot_done or game == null:
		return
	loot_done = true
	var r := RandomNumberGenerator.new()
	r.randomize()
	var houses: Array = range(1, loot_spots.size())
	houses.shuffle()
	# бензин — в случайном доме (не в подвале), ещё одна канистра — в другом
	_put("fuel", 1, _spot(houses[0], r))
	_put("fuel", 1, _spot(houses[1], r))
	# расходники для пистолета
	_put("ammo", r.randi_range(8, 12), _spot(houses[2], r))
	_put("ammo", r.randi_range(6, 10), _spot(houses[3], r))
	_put("mag", 1, _spot(houses[4], r), 2.0)
	_put("filter", 1, _spot(houses[5 % houses.size()], r))
	_put("canned", 1, _spot(houses[1], r))   # вторая локация — тушёнка можно
	for k in 3:
		_put("coin", r.randi_range(6, 14), _spot(houses[k], r))
	# подвал — запасы на полках
	_put("ammo", 8, _spot(0, r))
	_put("filter", 2, _spot(0, r))
	_put("coin", 20, _spot(0, r))


func _spot(house: int, r: RandomNumberGenerator) -> Vector3:
	var arr: Array = loot_spots[house]
	return (arr[r.randi() % arr.size()] as Vector3) + Vector3(r.randf_range(-0.2, 0.2), 0.05, r.randf_range(-0.2, 0.2))


func _put(id: String, n: int, pos: Vector3, dur := -1.0, manual := false) -> void:
	var p = game._make_pickup(id, n, pos, Vector3.ZERO)
	p.angular_velocity = Vector3.ZERO
	p.life = 1.0e9          # вещи деревни не пропадают
	p.need_leave = manual   # в салоне — только по E (иначе всё соберётся само, пока сидишь)
	if dur >= 0.0:
		p.set_meta("dur", dur)


## Лут в салоне заглохшей машины: на втором сиденье пистолет, по салону монеты и мелочь.
func spawn_car_loot() -> void:
	if game == null or car == null:
		return
	if game.net and not game.net.is_host():
		return
	var xf: Transform3D = car.global_transform
	_put("pistol", 1, xf * Vector3(-0.36, 1.06, -0.02), 5.0, true)
	_put("coin", randi_range(5, 9), xf * Vector3(0.25, 1.05, -0.8), -1.0, true)
	_put("coin", randi_range(3, 6), xf * Vector3(-0.3, 1.05, -0.75), -1.0, true)
	_put("coin", randi_range(2, 5), xf * Vector3(0.1, 1.06, 0.66), -1.0, true)
	_put("ammo", randi_range(4, 7), xf * Vector3(0.0, 0.95, -0.45), -1.0, true)
	_put("filter", 1, xf * Vector3(-0.1, 1.05, -0.85), -1.0, true)
	_put("bandage", 1, xf * Vector3(-0.36, 0.95, 0.35), -1.0, true)


# ---------- кат-сцена: машина заглохла ----------

## Из car.gd, когда машина отъехала: экран темнеет, надпись, машина переносится в деревню, игрок — в салон.
## seat — место этого игрока (0 — водитель).
## fast — пропуск кат-сцены (ui/cutscene_skip.gd): короткое затемнение без надписи.
func stall_sequence(seat: int, fast := false) -> void:
	card_seat = seat
	card_moved = false
	card_after = false
	card_fast = false
	card_bg.visible = true
	card_bg.color.a = 0.0
	card_l.modulate.a = 0.0
	card_l.text = "Через пару сотен метров мотор чихнул, кашлянул — и заглох.\nБак пуст.\n\nВокруг — брошенная деревня. Воздух снаружи всё такой же.\nНадо что-то делать."
	if fast:
		_card_fast()
		return
	var tw := create_tween()
	card_tw = tw
	tw.tween_property(card_bg, "color:a", 1.0, 1.6)
	tw.tween_callback(_relocate_once)
	tw.tween_property(card_l, "modulate:a", 1.0, 1.2)
	tw.tween_interval(4.5)
	tw.tween_property(card_l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(_after_once)
	tw.tween_property(card_bg, "color:a", 0.0, 1.6)
	tw.tween_callback(func(): card_bg.visible = false)


## Пропуск надписи «заглохла»: быстро в чёрное (если ещё не), перенос, сразу игра.
func _card_fast() -> void:
	if card_tw and card_tw.is_valid():
		card_tw.kill()
	card_fast = true
	card_bg.visible = true
	var tw := create_tween()
	card_tw = tw
	tw.tween_property(card_bg, "color:a", 1.0, maxf(0.4 * (1.0 - card_bg.color.a), 0.05))
	tw.parallel().tween_property(card_l, "modulate:a", 0.0, 0.2)
	tw.tween_callback(_relocate_once)
	tw.tween_callback(_after_once)
	tw.tween_property(card_bg, "color:a", 0.0, 0.8)
	tw.tween_callback(func(): card_bg.visible = false)


func _relocate_once() -> void:
	if not card_moved:
		card_moved = true
		_relocate(card_seat)


func _after_once() -> void:
	if not card_after:
		card_after = true
		_after_card()


func can_skip() -> bool:
	return card_bg.visible and not card_fast and not card_after


func skip_cut() -> void:
	if can_skip():
		_card_fast()


func skip_shared() -> bool:
	return game != null and game.get("net") != null


func _relocate(seat: int) -> void:
	car.park_at(STALL, STALL_YAW)
	spawn_car_loot()
	if seat >= 0 and seat < 4:
		car.seat_local(seat, true)
	else:
		# мест не хватило — стоит рядом с машиной
		game.player.global_position = STALL + Vector3(2.5, 0.1, -2.0 - 0.8 * randf())
		game.player.active = true
		if game.player.model_root:
			game.player.model_root.visible = true


func _after_card() -> void:
	game.end_cinematic()
	_force_gasmask()   # в салоне тоже отравленный воздух (gasmask.gd: _outside)
	hint("В салоне что-то есть — осмотрись (E — взять).\nПосмотри на дверь и нажми E — выйти.", 9.0)


## Первый выход из машины в деревне: Нюхич на лицо, метка на ближайшем доме, задание.
func on_exit_car() -> void:
	if stage != 0 or not near_village(game.player.global_position):
		return
	_force_gasmask()
	set_stage(1)


func _force_gasmask() -> void:
	if game.inv.equip["face"] == "gasmask":
		return
	if game.inv.count("gasmask") == 0:
		if game.inv.add("gasmask", 1) > 0:
			game.drop_spilled([{"id": "gasmask", "n": 1}])
		game.hud.toast("В бардачке нашёлся Нюхич", Color(0.7, 0.85, 0.6))
	if game.gasmask and game.gasmask.filter_left <= 0.0:
		if game.inv.count("filter") > 0:
			game.inv.remove("filter", 1)
			game.gasmask.filter_left = preload("res://scripts/player/gasmask.gd").FILTER_TIME
		else:
			game.gasmask.filter_left = 60.0
	game.toggle_gasmask()


static func near_village(p: Vector3) -> bool:
	return p.z > VZ0 - 40.0


# ---------- задание и подсказки ----------

func set_stage(s: int) -> void:
	stage = s
	stage_t = 0.0
	match s:
		1:
			_quest("Дойди до дома с меткой и спрячься в подвале")
		2:
			_quest("")   # без задания про бензин (промпт 16.11 05:09)
			game.hud.toast("Здесь воздух чистый — Нюхич можно снять (G)", Color(0.7, 0.85, 0.6))
		3:
			_quest("")
		4:
			_quest("")
		_:
			_quest("")


func _quest(text: String) -> void:
	quest_box.visible = text != ""
	quest_l.text = text
	if text != "":
		quest_box.modulate.a = 0.0
		create_tween().tween_property(quest_box, "modulate:a", 1.0, 0.6)


## Подсказка по центру снизу на time секунд.
func hint(text: String, time := 5.0) -> void:
	hint_l.text = text
	hint_l.modulate.a = 1.0
	hint_l.set_meta("t", time)


func _process(delta: float) -> void:
	if game == null or game.player == null:
		return
	stage_t += delta
	var ht := float(hint_l.get_meta("t", 0.0)) - delta
	hint_l.set_meta("t", ht)
	if ht < 1.0:
		hint_l.modulate.a = clampf(ht, 0.0, 1.0)
	if game.net and game.net.is_host():
		_send_mutants(delta)
	poll_t -= delta
	if poll_t <= 0.0:
		poll_t = 0.4
		if not revealed and _can_reveal():
			reveal()
		_poll()
	# метка: над дверью дома с подвалом или над машиной
	var mp := Vector3.INF
	if stage == 1:
		mp = marker_pos
	elif stage == 3 and car:
		mp = car.global_position + Vector3(0, 2.2, 0)
	marker.visible = mp != Vector3.INF and game.alive
	if marker.visible:
		marker.global_position = mp
		marker.text = "▼\n%d м" % int(game.player.global_position.distance_to(mp))


func _can_reveal() -> bool:
	if car and (car.state != "idle" or car.escaped):
		return true
	# до первой посадки в машину о деревне ни слова (промпт 16.11 02:18); пешком — видна вблизи
	return game.player.global_position.z > VZ0 - 160.0


func reveal() -> void:
	revealed = true
	_sign()
	for n in hidden_nodes:
		if is_instance_valid(n):
			n.visible = true
	for m in mutants:
		if is_instance_valid(m):
			m.visible = true


func _poll() -> void:
	var pp: Vector3 = game.player.global_position
	match stage:
		1:
			if in_basement(pp):
				set_stage(2)
		2:
			if game.inv.count("fuel") > 0 and car and car.fuel < 0.9:
				set_stage(3)
		3:
			if car and car.fuel >= 0.9:
				set_stage(4)
			elif game.inv.count("fuel") == 0:
				set_stage(2)
		4:
			if stage_t > 30.0:
				set_stage(5)


func _make_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 3
	add_child(ui)
	quest_box = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.045, 0.04, 0.72)
	sb.border_color = Color(0.85, 0.55, 0.25, 0.8)
	sb.border_width_left = 3
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	quest_box.add_theme_stylebox_override("panel", sb)
	quest_box.anchor_left = 1.0
	quest_box.anchor_right = 1.0
	quest_box.offset_left = -400
	quest_box.offset_right = -16
	quest_box.offset_top = 170
	quest_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quest_box.visible = false
	ui.add_child(quest_box)
	var vb := VBoxContainer.new()
	quest_box.add_child(vb)
	var t := Label.new()
	t.text = "ЗАДАНИЕ"
	t.add_theme_font_size_override("font_size", 15)
	t.add_theme_color_override("font_color", Color(0.95, 0.65, 0.3))
	vb.add_child(t)
	quest_l = Label.new()
	quest_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quest_l.custom_minimum_size = Vector2(360, 0)
	quest_l.add_theme_font_size_override("font_size", 18)
	quest_l.add_theme_color_override("font_color", Color(0.92, 0.9, 0.84))
	vb.add_child(quest_l)
	hint_l = Label.new()
	hint_l.anchor_left = 0.5
	hint_l.anchor_right = 0.5
	hint_l.anchor_top = 1.0
	hint_l.anchor_bottom = 1.0
	hint_l.offset_left = -420
	hint_l.offset_right = 420
	hint_l.offset_top = -190
	hint_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_l.add_theme_font_size_override("font_size", 19)
	hint_l.add_theme_color_override("font_color", Color(0.95, 0.9, 0.78))
	hint_l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	hint_l.add_theme_constant_override("outline_size", 6)
	hint_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(hint_l)
	# чёрный экран с надписью (кат-сцена) — поверх всего
	var cl := CanvasLayer.new()
	cl.layer = 12
	add_child(cl)
	card_bg = ColorRect.new()
	card_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	card_bg.color = Color(0, 0, 0, 0)
	card_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_bg.visible = false
	cl.add_child(card_bg)
	card_l = Label.new()
	card_l.set_anchors_preset(Control.PRESET_FULL_RECT)
	card_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_l.add_theme_font_size_override("font_size", 28)
	card_l.add_theme_color_override("font_color", Color(0.9, 0.86, 0.78))
	card_bg.add_child(card_l)
	marker = Label3D.new()
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.no_depth_test = true
	marker.fixed_size = true
	marker.pixel_size = 0.0012
	marker.font_size = 40
	marker.outline_size = 10
	marker.modulate = Color(1.0, 0.65, 0.25)
	marker.visible = false
	add_child(marker)


# ---------- мутанты ----------

func _spawn_mutant(pos: Vector3, kind: String) -> void:
	var m := Mutant.new()
	m.game = game
	m.kind = kind
	m.position = pos + Vector3(0, 0.1, 0)
	m.rotation.y = randf() * TAU
	m.home = pos
	m.visible = revealed
	m.set_meta("nid", mut_seq)
	mut_seq += 1
	game.add_child(m)
	mutants.append(m)
	m.died.connect(func(_m): _mutant_died(pos, kind))
	m.tree_exiting.connect(func(): mutants.erase(m))


func _mutant_died(pos: Vector3, kind: String) -> void:
	await get_tree().create_timer(MUT_RESPAWN).timeout
	if not is_instance_valid(game):
		return
	while is_instance_valid(game.player) and game.player.global_position.distance_to(pos) < 15.0:
		await get_tree().create_timer(6.0).timeout
	_spawn_mutant(pos, kind)


func mutant_by_id(nid: int):
	for m in mutants:
		if is_instance_valid(m) and int(m.get_meta("nid", -1)) == nid:
			return m
	return null


## Хост: раз в 0.1 с — всем состояние мутантов.
var _mut_send_t := 0.0


func _send_mutants(delta: float) -> void:
	_mut_send_t -= delta
	if _mut_send_t > 0.0:
		return
	_mut_send_t = 0.1
	var vn := get_tree().root.get_node_or_null("VillageNet")
	if vn == null:
		return
	var arr: Array = []
	for m in mutants:
		if is_instance_valid(m) and m.is_inside_tree():
			arr.append([int(m.get_meta("nid")), m.kind, m.global_position, m.rotation.y, m.state, m.hp])
	vn.rpc("v_mut", arr)


## Клиент: копии мутантов по данным хоста.
func net_mutants(arr: Array) -> void:
	var seen := {}
	for a in arr:
		var nid: int = a[0]
		seen[nid] = true
		var m = mutant_by_id(nid)
		if m == null:
			if a[4] == "dead":
				continue
			m = Mutant.new()
			m.game = game
			m.kind = String(a[1])
			m.net_puppet = true
			m.visible = revealed
			m.position = a[2]
			m.rotation.y = a[3]
			m.net_pos = a[2]
			m.net_rot = a[3]
			m.set_meta("nid", nid)
			game.add_child(m)
			mutants.append(m)
		m.net_apply(a[2], a[3], a[4], a[5])
	for m in mutants.duplicate():
		if is_instance_valid(m) and not seen.has(int(m.get_meta("nid", -1))):
			if m.state != "dead":
				m.queue_free()
			mutants.erase(m)
		elif not is_instance_valid(m):
			mutants.erase(m)


# ---------- сохранение ----------

func to_save() -> Dictionary:
	var d := {"stage": stage, "loot": loot_done}
	if car:
		d["car"] = car.to_save()
	if bonus_slot:
		d["jackpot"] = bonus_slot.jackpot
		d["sevens"] = bonus_slot.sevens_hit
	if storage:
		d["storage"] = storage.contents.duplicate(true)
	return d


func from_save(d: Dictionary) -> void:
	stage = int(d.get("stage", 0))
	set_stage(stage)
	loot_done = bool(d.get("loot", false))
	if bonus_slot and d.has("jackpot"):
		bonus_slot.jackpot = int(d["jackpot"])
		bonus_slot.sevens_hit = bool(d.get("sevens", false))
	if car and d.has("car"):
		car.from_save(d["car"])
	if storage:
		storage.contents = []
		for it in d.get("storage", []):
			var e: Array = [String(it[0]), int(it[1])]
			if it.size() > 2:
				e.append(float(it[2]))
			if it.size() > 4:   # ячейка и поворот в сетке сундука (loot_window)
				e.append_array([int(it[3]), bool(it[4])])
			storage.contents.append(e)
	if not loot_done and game and game.net == null:
		spawn_village_loot()   # старые сейвы — без лута деревни
