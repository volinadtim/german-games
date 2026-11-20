extends Node
## Проверка запуска без окна (scripts/smoke.sh): грузит игру, по очереди ставит игрока в бункер, деревню,
## лагерь у озера, город; открывает инвентарь, магазин, настройки; включает сплитскрин.
## Проверяет: под игроком есть пол (коллизия), игрок не проваливается по Y.
## Печатает строки «SMOKE FAIL: …», в конце «SMOKE STATS {json}» (снимок для tests/baseline.json) и «SMOKE DONE».
## Сейвы игрока не трогает: smoke.sh подменяет папку user:// (override.cfg), слот игры — «smoke».

const STEP_FRAMES := 120   # ~2 с игрового времени на каждую проверку (smoke.sh запускает с --fixed-fps 60)

var fails: PackedStringArray = []
var stats := {}
var main: Node
var game: Node


func _ready() -> void:
	seed(20251120)   # случайная расстановка (кувшины, лут) — одинаковая от запуска к запуску
	Engine.set_meta("eskiness_slot", "smoke")
	Engine.set_meta("eskiness_load", false)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _fail(t: String) -> void:
	fails.append(t)
	print("SMOKE FAIL: " + t)


func _run() -> void:
	_check_scripts()
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	await _frames(30)
	if main.get_node_or_null("Level") == null or main.get_node("Level").get_script() == null:
		_fail("нет уровня бункера (Main/Level)")
	main.call("_enter_game")
	await _frames(10)
	for c in main.get_children():
		if c.has_method("save_now"):
			game = c
	if game == null:
		_fail("игра не создалась (core/game.gd)")
		return _finish()
	await _skip_intro()
	var p: Node3D = game.player
	# неуязвимость, чтобы враги не мешали проверке пола
	if "god" in p:
		p.set("god", true)
	var v = game.get("village")
	if v:
		if v.has_method("_ensure_lake"):
			v.call("_ensure_lake")
		if v.has_method("_ensure_city"):
			v.call("_ensure_city")
	await _frames(5)
	var con := _console()
	var places: Array = con.call("_tp_places") if con else []
	if places.is_empty():
		_fail("консоль/места /tp не найдены")
	var keys := {"бункер": "bunker", "деревня": "village", "озеро": "lake", "город": "city"}
	for pl in places:
		var key: String = keys.get(pl[0], String(pl[0]))
		var to: Vector3 = con.call("_tp_ground", pl[2])
		p.global_position = to
		p.velocity = Vector3.ZERO
		await _frames(STEP_FRAMES)
		_check_floor(key, to)
	stats["locations"] = _location_stats(places, keys)
	stats["items"] = _items_count()
	stats["slot_symbols"] = _slot_symbols()
	stats["shops"] = _shop_goods()
	_check_controls()
	await _check_windows()
	await _check_split()
	_finish()


## Все скрипты компилируются (и те, что грузятся позже, по ходу игры).
func _check_scripts() -> void:
	var stack: Array[String] = ["res://scripts"]
	var n := 0
	while not stack.is_empty():
		var d: String = stack.pop_back()
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".gd"):
				n += 1
				var s = load(d + "/" + f)
				if s == null or not s.can_instantiate():
					_fail("скрипт не компилируется: %s/%s" % [d, f])
		for sd in DirAccess.get_directories_at(d):
			stack.append(d + "/" + sd)
	stats["scripts"] = n


## Пропустить кат-сцену пробуждения (как кнопкой пропуска) и закончить вступление (дальше оно ждёт действий игрока).
func _skip_intro() -> void:
	for i in 900:
		var intro = game.get_node_or_null("Intro")
		if intro == null or bool(intro.get("done")):
			return
		if intro.call("can_skip"):
			intro.call("skip_cut")
		if String(intro.get("stage")) not in ["wake", "note", "cut"]:
			intro.call("_finish")
			await _frames(5)
			return
		await get_tree().process_frame
	_fail("кат-сцена пробуждения не закончилась за 15 с")


func _console() -> Node:
	for c in game.get_children():
		if c.has_method("_tp_places"):
			return c
	return null


## Пол под игроком и падение по Y.
func _check_floor(key: String, start: Vector3) -> void:
	var p: CharacterBody3D = game.player
	var y := p.global_position.y
	if y < start.y - 2.0:
		_fail("%s: игрок упал по Y (%.1f -> %.1f)" % [key, start.y, y])
		return
	var q := PhysicsRayQueryParameters3D.create(p.global_position + Vector3(0, 0.5, 0), p.global_position + Vector3(0, -2.0, 0))
	q.exclude = [p.get_rid()]
	var hit: Dictionary = p.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		_fail("%s: под игроком нет пола (позиция %s)" % [key, str(p.global_position.snapped(Vector3.ONE * 0.1))])


## Число узлов и коллизий в радиусе 60 м от точки каждой локации (для сравнения «до/после»).
func _location_stats(places: Array, keys: Dictionary) -> Dictionary:
	var all: Array[Node] = []
	var stack: Array[Node] = [main]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		all.append(n)
		stack.append_array(n.get_children())
	var out := {}
	for pl in places:
		var c: Vector3 = pl[2]
		var nodes := 0
		var shapes := 0
		for n in all:
			if n is Node3D and n.is_inside_tree() and (n as Node3D).global_position.distance_to(c) < 60.0:
				nodes += 1
				if n is CollisionShape3D or (n is CSGShape3D and (n as CSGShape3D).use_collision):
					shapes += 1
		out[keys.get(pl[0], String(pl[0]))] = {"nodes": nodes, "collisions": shapes}
	return out


func _items_count() -> int:
	var Items = load("res://scripts/items/items.gd")
	return (Items.get("ITEMS") as Dictionary).size() if Items.get("ITEMS") != null else -1


## Символы автоматов: KILLBOX, CASHY BOX, КЛЁВ, РАДИАЦИЯ.
func _slot_symbols() -> Dictionary:
	var out := {}
	var src := {"killbox": ["res://scripts/slot/slot_machine.gd", "SYM_ORDER"], "cashy": ["res://scripts/slot/bonus_slot.gd", "SYMS"],
		"lake": ["res://scripts/slot/lake_slot.gd", "SYMS"], "city": ["res://scripts/slot/city_slot.gd", "SYMS"]}
	for k in src:
		var s = load(src[k][0])
		var arr = s.get(src[k][1]) if s else null
		out[k] = (arr as Array).size() if arr is Array else -1
	return out


## Сколько предметов продаёт каждый магазин (по Items.ITEMS и shop.sells).
func _shop_goods() -> Dictionary:
	var Items = load("res://scripts/items/items.gd")
	var ids: Array = (Items.get("ITEMS") as Dictionary).keys()
	var out := {}
	var stack: Array[Node] = [main]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n.has_method("sells") and n.has_method("open_tab"):
			var k := 0
			for id in ids:
				if n.call("sells", id):
					k += 1
			out[String(n.name)] = k
	return out


## Управление (scripts/controls): все действия таблицы есть в InputMap, режимы глушат кнопки, подсказки собираются.
func _check_controls() -> void:
	var c = get_tree().root.get_node_or_null("Controls")
	if c == null:
		_fail("нет autoload Controls")
		return
	var n := 0
	var ev := 0
	for a in c.table.order:
		if not InputMap.has_action(a):
			_fail("управление: нет действия " + a)
		else:
			n += 1
			ev += InputMap.action_get_events(a).size()
	stats["controls"] = {"actions": n, "kb_events": ev, "menu_rows": c.menu_rows().size()}
	if c.hint("[F] Открыть") != "[F] Открыть" or c.hint("{interact}") != "F":
		_fail("управление: подсказка F не собралась: " + c.hint("{interact}"))
	var con := _console()
	if con:
		con.call("show_console")
		if c.allowed("jump") or c.mode() != "console":
			_fail("управление: консоль не глушит прыжок")
		con.call("close")
	if not c.allowed("jump"):
		_fail("управление: после консоли прыжок заглушен (режим %s)" % c.mode())


## Инвентарь, магазин, настройки — открыть и закрыть.
func _check_windows() -> void:
	var inv = game.get("inv")
	if inv and inv.has_method("show_inventory"):
		inv.call("show_inventory")
		await _frames(60)
		inv.call("close")
	else:
		_fail("инвентарь не найден")
	var shop = game.get("shop")
	if shop and shop.has_method("open_tab"):
		for i in 6:
			shop.call("open_tab", game, i)
			await _frames(10)
		shop.call("_close")
	else:
		_fail("магазин бункера не найден")
	var menu = main.get("menu")
	if menu and menu.has_method("_open_settings"):
		menu.visible = true
		menu.call("_open_settings", "pause")
		await _frames(60)
		menu.call("_show", "pause")
		menu.visible = false
	else:
		_fail("меню настроек не найдено")
	await _frames(10)


## Сплитскрин: второй игрок и экран пополам.
func _check_split() -> void:
	var Split = load("res://scripts/network/split.gd")
	Split.set("pending", true)
	Split.call("attach", main)
	await _frames(STEP_FRAMES)
	var s = main.get_node_or_null("Split")
	if s == null:
		_fail("сплитскрин не включился")
	elif s.get("pp") == null:
		_fail("сплитскрин: нет второго игрока")
	Split.set("pending", false)


func _finish() -> void:
	print("SMOKE STATS " + JSON.stringify(stats))
	print("SMOKE DONE fails=%d" % fails.size())
	get_tree().quit(1 if fails.size() > 0 else 0)
