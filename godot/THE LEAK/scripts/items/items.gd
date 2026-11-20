extends RefCounted
const _D_TABLES := preload("res://data/items/tables.tres")   # настройки — правятся в Инспекторе
const Weapons := preload("res://scripts/weapons/weapons.gd")
## Справочник предметов (тестовые механики): название, описание, размер стака, иконка и 3D-модель.
## Иконки и модели рисуются кодом, файлов нет.

static var MOD_HINT: String = _D_TABLES.mod_hint
static var ITEMS: Dictionary = _load_items()   # data/items/<id>.tres (scripts/data/item_type.gd)


## Справочник предметов из data/items/*.tres (кроме tables.tres) в порядке поля order: id -> словарь, как раньше.
static func _load_items() -> Dictionary:
	var list: Array = []
	for f in ResourceLoader.list_directory("res://data/items"):
		if not f.ends_with(".tres") or f == "tables.tres":
			continue
		var it = load("res://data/items/" + f)
		if it != null and it.get("id") != null:
			list.append(it)
	list.sort_custom(func(a, b): return a.order < b.order or (a.order == b.order and a.id < b.id))
	var out := {}
	for it in list:
		out[it.id] = it.to_dict()
	return out


## Рецепты крафта: что получится и что нужно.
## tool — инструмент (не тратится, а теряет прочность wear), промпт 14.11 19:22.
static var RECIPES: Array = _D_TABLES.recipes_table()


## Размер предмета в ячейках сумки [ширина, высота] (промпт 16.11 02:42); нет в списке — 1×1.
## Пробел при перетаскивании поворачивает (inventory.gd).
static var SIZES: Dictionary = _D_TABLES.cells(_D_TABLES.sizes)

## Отдельные ячейки хранения у одежды (промпт 16.11 02:42): [ширина, высота] блока карманов.
## Рюкзак — "bag" в ITEMS (свой блок).
static var POCKETS: Dictionary = _D_TABLES.cells(_D_TABLES.pockets)


## Чем можно заменить инструмент рецепта: сам он и вещи с "tool_of" (слесарный молоток вместо каменного).
static func tool_ids(tid: String) -> Array:
	var out: Array = []
	for id in ITEMS:
		if String(ITEMS[id].get("tool_of", "")) == tid:
			out.append(id)
	out.append(tid)
	return out


## Чью 3D-модель берёт предмет: свой id или базовый из Weapons.ALIAS (новые предметы без своей модели).
static func model_of(id: String) -> String:
	return String(Weapons.ALIAS.get(id, id))


static func size_of(id: String) -> Vector2i:
	var a = SIZES.get(id, [1, 1])
	return Vector2i(int(a[0]), int(a[1]))


## Блок ячеек, который даёт надетая вещь (рюкзак, карманы); (0,0) — никакого.
static func block_of(id: String) -> Vector2i:
	if id == "" or not ITEMS.has(id):
		return Vector2i.ZERO
	var a = ITEMS[id].get("bag", POCKETS.get(id, null))
	if a is Array:
		return Vector2i(int(a[0]), int(a[1]))
	if a != null:   # старый формат рюкзака: число ячеек
		return Vector2i(4, 3)
	return Vector2i.ZERO


## Куда надевается предмет: hand (левая или правая рука), head (голова), face (противогаз), back (рюкзак), hands (кастет) или "".
static func equip_slot(id: String) -> String:
	if not ITEMS.has(id):
		return ""
	if ITEMS[id].has("weapon"):
		return "hand"
	return String(ITEMS[id].get("equip", ""))


## Подходит ли предмет в слот экипировки (left/right/head/hands).
static func fits(id: String, slot: String) -> bool:
	var k := equip_slot(id)
	if slot == "gps":
		return id == "gps"
	if slot == "holster":
		return ITEMS.has(id) and ITEMS[id].get("gun", false)
	if slot == "hook1" or slot == "hook2":
		return hookable(id)
	if slot == "left" or slot == "right":
		return k == "hand" or holdable(id)
	return k != "" and k == slot


## Можно повесить на крючок рюкзака: холодное оружие и инструменты (не огнестрел, не камень).
static func hookable(id: String) -> bool:
	if not ITEMS.has(id):
		return false
	var d: Dictionary = ITEMS[id]
	return (d.get("weapon", false) and not d.get("gun", false) and id != "stone") or id in ["flashlight", "broom", "dive_light"]


## Любой предмет можно взять в руку, как оружие (промпт 18.11 00:27): бьёт им как дубинкой-слабачкой.
static func holdable(id: String) -> bool:
	return ITEMS.has(id) and id != "coin"


## Можно ли применить предмет прямо из руки кнопкой этой руки (промпт 18.11 02:27):
## лечение, еда и питьё, ремкомплект, фонарик, батарейка, веник, кошелёк.
static func hand_use(id: String) -> bool:
	var d: Dictionary = ITEMS.get(id, {})
	return d.has("heal") or d.has("buff") or d.has("repair") or id in ["flashlight", "battery", "broom", "wallet", "ammo_box"]


## Предмет с зарядами/применениями (ремкомплект, аптечка, вода…): в ячейке — «×N», dur — сколько осталось.
static func charged(id: String) -> bool:
	return ITEMS.has(id) and (ITEMS[id].has("repair") or ITEMS[id].has("uses"))


## Каким ремкомплектом чинится: "weapon", "gun" (пистолет), "gear" (одежда с прочностью) или "".
static func repairable(id: String) -> String:
	if not ITEMS.has(id) or max_dur(id) <= 0.0 or charged(id):
		return ""
	if ITEMS[id].has("gun"):
		return "gun"    # у пистолета своя прочность в дробной части dur (gun.gd)
	if ITEMS[id].has("rounds"):
		return ""
	if ITEMS[id].has("weapon"):
		return "weapon"
	return "gear" if ITEMS[id].has("equip") else ""


## Прочность предмета (0 — вечный): оружие ломается от ударов, сапоги — от ударов и стекла (не от ходьбы).
static func max_dur(id: String) -> float:
	return float(ITEMS[id].get("dur", 0)) if ITEMS.has(id) else 0.0


## Сколько секунд держать ЛКМ, чтобы применить предмет из руки (хотбар, промпт 18.11 01:16).
static func use_time(id: String) -> float:
	var d: Dictionary = ITEMS.get(id, {})
	if d.has("heal"):
		return 1.0 + float(d["heal"]) / 25.0
	if d.has("repair"):
		return 2.5
	if d.has("buff"):
		return 1.4
	return 0.7


static func item_name(id: String) -> String:
	return ITEMS[id]["name"] if ITEMS.has(id) else id


## Иконка предмета в прямоугольнике r (рисуется на любом CanvasItem в его _draw / сигнале draw).
static func draw_icon(ci: CanvasItem, id: String, r: Rect2) -> void:
	if not ITEMS.has(id):
		return
	var c := r.get_center()
	var s := minf(r.size.x, r.size.y)
	var col: Color = ITEMS[id]["color"]
	var dark := col.darkened(0.45)
	if String(ITEMS[id]["icon"]) in ["bat", "pipe", "crowbar", "machete", "knife", "gasmask", "filter", "hammer", "steel_hammer", "hatchet", "shiv", "spiked_club", "pistol", "sawnoff", "rifle", "smg"]:
		Weapons.draw_icon(ci, String(ITEMS[id]["icon"]), r, col)
		return
	if ITEMS[id].has("mod"):
		_mod_icon(ci, id, c, s, col)
		return
	match String(ITEMS[id]["icon"]):
		"holster":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.18, -s * 0.34), c + Vector2(s * 0.2, -s * 0.34),
				c + Vector2(s * 0.14, s * 0.38), c + Vector2(-s * 0.06, s * 0.38), c + Vector2(-s * 0.2, s * 0.1)]), col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.3, -s * 0.38), Vector2(s * 0.6, s * 0.08)), dark)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.04, -s * 0.24), Vector2(s * 0.14, s * 0.1)), col.lightened(0.25))
		"hooks":
			for i in 2:
				var hx := c + Vector2(-s * 0.18 + i * s * 0.36, 0)
				ci.draw_line(hx + Vector2(0, -s * 0.36), hx + Vector2(0, s * 0.1), col, s * 0.06)
				ci.draw_arc(hx + Vector2(s * 0.09, s * 0.1), s * 0.09, 0.0, PI, 8, col, s * 0.06)
				ci.draw_rect(Rect2(hx + Vector2(-s * 0.07, -s * 0.4), Vector2(s * 0.14, s * 0.06)), dark)
		"gps":
			ci.draw_rect(Rect2(c - Vector2(s * 0.2, s * 0.32), Vector2(s * 0.4, s * 0.64)), col.darkened(0.6))
			ci.draw_rect(Rect2(c - Vector2(s * 0.15, s * 0.25), Vector2(s * 0.3, s * 0.3)), Color(0.3, 0.6, 0.4))
			ci.draw_circle(c + Vector2(0, -s * 0.1), s * 0.05, Color(1.0, 0.3, 0.2))
			ci.draw_rect(Rect2(c + Vector2(s * 0.1, -s * 0.44), Vector2(s * 0.05, s * 0.13)), col)
			for i in 3:
				ci.draw_rect(Rect2(c + Vector2(-s * 0.13 + i * s * 0.1, s * 0.13), Vector2(s * 0.06, s * 0.06)), col)
		"sketch_map":
			ci.draw_rect(Rect2(c - Vector2(s * 0.34, s * 0.26), Vector2(s * 0.68, s * 0.52)), col)
			ci.draw_rect(Rect2(c - Vector2(s * 0.34, s * 0.26), Vector2(s * 0.68, s * 0.52)), dark, false, maxf(1.0, s * 0.03))
			ci.draw_polyline(PackedVector2Array([c + Vector2(-s * 0.26, s * 0.12), c + Vector2(-s * 0.08, -s * 0.06), c + Vector2(s * 0.06, s * 0.08), c + Vector2(s * 0.26, -s * 0.14)]), dark, maxf(1.5, s * 0.04))
			ci.draw_circle(c + Vector2(s * 0.14, s * 0.1), s * 0.05, Color(0.85, 0.15, 0.1))
		"fuel":
			var body := Rect2(c - Vector2(s * 0.28, s * 0.3), Vector2(s * 0.56, s * 0.66))
			ci.draw_rect(body, dark)
			ci.draw_rect(body.grow(-s * 0.03), col)
			ci.draw_line(c + Vector2(-s * 0.2, -s * 0.2), c + Vector2(s * 0.2, s * 0.3), dark, maxf(1.5, s * 0.04))
			ci.draw_line(c + Vector2(s * 0.2, -s * 0.2), c + Vector2(-s * 0.2, s * 0.3), dark, maxf(1.5, s * 0.04))
			ci.draw_rect(Rect2(c + Vector2(-s * 0.18, -s * 0.42), Vector2(s * 0.24, s * 0.1)), dark)
			ci.draw_rect(Rect2(c + Vector2(s * 0.12, -s * 0.4), Vector2(s * 0.1, s * 0.12)), Color(0.3, 0.3, 0.28))
		"rot_apple":
			preload("res://scripts/slot/slot_symbols.gd").draw(ci, "rot_apple", r)
		"coin":
			ci.draw_circle(c, s * 0.34, dark)
			ci.draw_circle(c, s * 0.29, col)
			ci.draw_arc(c, s * 0.19, 0.0, TAU, 24, col.darkened(0.25), maxf(1.5, s * 0.04), true)
			ci.draw_line(c + Vector2(0, -s * 0.1), c + Vector2(0, s * 0.1), col.darkened(0.3), maxf(1.5, s * 0.05))
		"medkit":
			var box := Rect2(c - Vector2(s * 0.38, s * 0.28), Vector2(s * 0.76, s * 0.56))
			ci.draw_rect(box, Color(0.8, 0.77, 0.7))
			ci.draw_rect(Rect2(c - Vector2(s * 0.12, s * 0.38), Vector2(s * 0.24, s * 0.12)), Color(0.35, 0.33, 0.3))
			ci.draw_rect(Rect2(c - Vector2(s * 0.06, s * 0.19), Vector2(s * 0.12, s * 0.38)), col)
			ci.draw_rect(Rect2(c - Vector2(s * 0.19, s * 0.06), Vector2(s * 0.38, s * 0.12)), col)
		"bandage":
			# скатка марли сбоку: узкий плотный рулон, бумажная лента с красным крестом, хвостик вниз (промпт 18:36)
			var gz := col.darkened(0.08)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(s * 0.12, s * 0.06), c + Vector2(s * 0.24, s * 0.06),
				c + Vector2(s * 0.4, s * 0.36), c + Vector2(s * 0.28, s * 0.38)]), gz.darkened(0.1))
			ci.draw_rect(Rect2(c - Vector2(s * 0.26, s * 0.13), Vector2(s * 0.46, s * 0.26)), gz)
			ci.draw_circle(c + Vector2(-s * 0.26, 0), s * 0.13, gz.darkened(0.12))
			ci.draw_circle(c + Vector2(s * 0.2, 0), s * 0.13, gz.lightened(0.05))
			ci.draw_arc(c + Vector2(s * 0.2, 0), s * 0.07, 0.0, TAU * 0.8, 16, gz.darkened(0.25), maxf(1.0, s * 0.02), true)
			for k in 4:
				var x := -s * 0.2 + k * s * 0.11
				ci.draw_line(c + Vector2(x, -s * 0.12), c + Vector2(x, s * 0.12), gz.darkened(0.15), maxf(1.0, s * 0.012))
			ci.draw_rect(Rect2(c - Vector2(s * 0.09, s * 0.14), Vector2(s * 0.15, s * 0.28)), Color(0.74, 0.65, 0.48))
			ci.draw_rect(Rect2(c + Vector2(-s * 0.04, -s * 0.07), Vector2(s * 0.05, s * 0.14)), Color(0.75, 0.14, 0.1))
			ci.draw_rect(Rect2(c + Vector2(-s * 0.085, -s * 0.025), Vector2(s * 0.14, s * 0.05)), Color(0.75, 0.14, 0.1))
		"choco":
			# как моделька: тёмно-красная обёртка с жёлтой полосой, фольга, надорванный конец с дольками (промпт 19:12)
			var box := Rect2(c - Vector2(s * 0.38, s * 0.2), Vector2(s * 0.44, s * 0.4))
			ci.draw_rect(box, Color(0.5, 0.1, 0.08))
			ci.draw_rect(Rect2(box.position + Vector2(0, s * 0.16), Vector2(box.size.x, s * 0.08)), Color(0.9, 0.8, 0.4))
			ci.draw_rect(Rect2(c + Vector2(s * 0.06, -s * 0.2), Vector2(s * 0.05, s * 0.4)), Color(0.8, 0.8, 0.82))   # фольга
			ci.draw_rect(Rect2(c + Vector2(s * 0.11, -s * 0.18), Vector2(s * 0.27, s * 0.36)), col)
			for i in 2:
				for j in 3:
					ci.draw_rect(Rect2(c + Vector2(s * (0.13 + i * 0.125), s * (-0.16 + j * 0.115)), Vector2(s * 0.1, s * 0.095)), col.lightened(0.12))
		"soda":
			var body := Rect2(c - Vector2(s * 0.17, s * 0.3), Vector2(s * 0.34, s * 0.6))
			ci.draw_rect(body, col)
			ci.draw_rect(Rect2(body.position, Vector2(body.size.x, s * 0.06)), Color(0.7, 0.7, 0.72))
			ci.draw_rect(Rect2(body.position + Vector2(0, s * 0.54), Vector2(body.size.x, s * 0.06)), Color(0.7, 0.7, 0.72))
			ci.draw_line(c + Vector2(-s * 0.1, -s * 0.05), c + Vector2(s * 0.1, s * 0.05), Color(1, 1, 1, 0.8), maxf(1.5, s * 0.05))
		"rusk":
			var box := Rect2(c - Vector2(s * 0.32, s * 0.2), Vector2(s * 0.64, s * 0.4))
			ci.draw_rect(box, col)
			ci.draw_rect(box, dark, false, maxf(1.5, s * 0.04))
			for k in 4:
				ci.draw_circle(c + Vector2((k - 1.5) * s * 0.14, (k % 2 - 0.5) * s * 0.12), s * 0.03, dark)
		"battery":
			var body := Rect2(c - Vector2(s * 0.16, s * 0.3), Vector2(s * 0.32, s * 0.64))
			ci.draw_rect(Rect2(c - Vector2(s * 0.07, s * 0.38), Vector2(s * 0.14, s * 0.1)), Color(0.6, 0.6, 0.58))
			ci.draw_rect(body, col)
			ci.draw_rect(Rect2(body.position, Vector2(body.size.x, s * 0.16)), Color(0.75, 0.5, 0.25))   # медный торец, как у модельки
			ci.draw_line(c + Vector2(-s * 0.08, -s * 0.06), c + Vector2(s * 0.08, -s * 0.06), Color(0.9, 0.85, 0.6), maxf(1.5, s * 0.04))
			ci.draw_line(c + Vector2(0, -s * 0.14), c + Vector2(0, s * 0.02), Color(0.9, 0.85, 0.6), maxf(1.5, s * 0.04))
		"knuckles":
			ci.draw_rect(Rect2(c + Vector2(-s * 0.34, s * 0.04), Vector2(s * 0.68, s * 0.14)), dark)
			for k in 4:
				var p := c + Vector2((k - 1.5) * s * 0.17, -s * 0.06)
				ci.draw_arc(p, s * 0.075, 0.0, TAU, 14, col, maxf(2.0, s * 0.045), true)
		"canned":
			var box := Rect2(c - Vector2(s * 0.24, s * 0.3), Vector2(s * 0.48, s * 0.6))
			ci.draw_rect(box, col)
			ci.draw_rect(Rect2(box.position + Vector2(0, s * 0.14), Vector2(box.size.x, s * 0.3)), Color(0.5, 0.18, 0.12))
			ci.draw_line(box.position, box.position + Vector2(box.size.x, 0), col.lightened(0.3), maxf(1.5, s * 0.04))
		"water":
			ci.draw_rect(Rect2(c - Vector2(s * 0.06, s * 0.38), Vector2(s * 0.12, s * 0.1)), Color(0.2, 0.4, 0.75))
			ci.draw_rect(Rect2(c - Vector2(s * 0.16, s * 0.27), Vector2(s * 0.32, s * 0.62)), col)
			ci.draw_rect(Rect2(c - Vector2(s * 0.16, s * 0.0), Vector2(s * 0.32, s * 0.35)), col.darkened(0.25))
		"pills":
			# баночка, как моделька (pickup_mesh.gd): оранжевая банка, белая крышка, белая этикетка с красным крестом (промпт 19:12)
			var jar := Rect2(c - Vector2(s * 0.2, s * 0.2), Vector2(s * 0.4, s * 0.56))
			ci.draw_rect(jar, Color(0.75, 0.42, 0.12))
			ci.draw_rect(Rect2(jar.position + Vector2(s * 0.04, s * 0.02), Vector2(s * 0.06, jar.size.y - s * 0.04)), Color(0.9, 0.62, 0.3))   # блик
			ci.draw_rect(Rect2(jar.position + Vector2(0, s * 0.18), Vector2(jar.size.x, s * 0.24)), Color(0.92, 0.9, 0.85))
			ci.draw_rect(Rect2(c + Vector2(-s * 0.025, s * 0.2), Vector2(s * 0.05, s * 0.16)), Color(0.8, 0.15, 0.1))
			ci.draw_rect(Rect2(c + Vector2(-s * 0.08, s * 0.255), Vector2(s * 0.16, s * 0.05)), Color(0.8, 0.15, 0.1))
			ci.draw_rect(Rect2(c - Vector2(s * 0.23, s * 0.38), Vector2(s * 0.46, s * 0.18)), Color(0.95, 0.95, 0.93))   # крышка
			for k in 5:
				var x := -s * 0.19 + k * s * 0.095
				ci.draw_line(c + Vector2(x, -s * 0.37), c + Vector2(x, -s * 0.21), Color(0.75, 0.75, 0.72), maxf(1.0, s * 0.015))
		"wallet":
			var box := Rect2(c - Vector2(s * 0.34, s * 0.24), Vector2(s * 0.68, s * 0.48))
			ci.draw_rect(box, col)
			ci.draw_rect(Rect2(c + Vector2(s * 0.1, -s * 0.08), Vector2(s * 0.24, s * 0.16)), col.lightened(0.15))
			ci.draw_circle(c + Vector2(s * 0.2, 0), s * 0.04, Color(0.8, 0.65, 0.3))
		"scrap":
			ci.draw_line(c + Vector2(-s * 0.3, s * 0.2), c + Vector2(s * 0.1, -s * 0.25), col, maxf(3.0, s * 0.1))
			ci.draw_line(c + Vector2(-s * 0.1, -s * 0.2), c + Vector2(s * 0.3, s * 0.2), col.darkened(0.2), maxf(3.0, s * 0.1))
			ci.draw_rect(Rect2(c + Vector2(-s * 0.25, s * 0.05), Vector2(s * 0.2, s * 0.2)), col.lightened(0.1))
		"gear":
			var pts := PackedVector2Array()
			for k in 16:
				var a := TAU * k / 16.0
				var rr := s * (0.34 if k % 2 == 0 else 0.26)
				pts.append(c + Vector2(cos(a), sin(a)) * rr)
			ci.draw_colored_polygon(pts, col)
			ci.draw_circle(c, s * 0.1, Color(0.08, 0.08, 0.08))
		"tape":
			ci.draw_circle(c, s * 0.32, col)
			ci.draw_circle(c, s * 0.16, Color(0.75, 0.7, 0.6))
			ci.draw_circle(c, s * 0.12, Color(0.08, 0.08, 0.08))
		"photo":
			var box := Rect2(c - Vector2(s * 0.3, s * 0.34), Vector2(s * 0.6, s * 0.68))
			ci.draw_rect(box, col)
			ci.draw_rect(box.grow(-s * 0.06), Color(0.3, 0.27, 0.22))
			ci.draw_circle(c + Vector2(-s * 0.1, -s * 0.06), s * 0.07, col.darkened(0.2))
			ci.draw_circle(c + Vector2(s * 0.1, -s * 0.06), s * 0.07, col.darkened(0.2))
		"wood":
			var a := c + Vector2(-s * 0.32, s * 0.18)
			var b := c + Vector2(s * 0.32, -s * 0.18)
			ci.draw_line(a, b, col, maxf(4.0, s * 0.2))
			ci.draw_line(a.lerp(b, 0.2), a.lerp(b, 0.8), col.darkened(0.3), maxf(1.0, s * 0.03))
		"glass":
			var pts := PackedVector2Array([c + Vector2(-s * 0.2, s * 0.3), c + Vector2(-s * 0.05, -s * 0.34),
				c + Vector2(s * 0.24, -s * 0.1), c + Vector2(s * 0.1, s * 0.32)])
			ci.draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.75))
			ci.draw_line(c + Vector2(-s * 0.05, -s * 0.2), c + Vector2(s * 0.05, s * 0.1), Color(1, 1, 1, 0.8), maxf(1.0, s * 0.03))
		"broom":
			ci.draw_line(c + Vector2(-s * 0.3, -s * 0.36), c + Vector2(s * 0.08, s * 0.12), Color(0.5, 0.36, 0.2), maxf(2.0, s * 0.06))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, s * 0.06), c + Vector2(s * 0.16, -s * 0.06),
				c + Vector2(s * 0.36, s * 0.22), c + Vector2(s * 0.16, s * 0.36)]), col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.38, s * 0.2), Vector2(s * 0.3, s * 0.14)), Color(0.3, 0.32, 0.3))
		"flashlight":
			ci.draw_rect(Rect2(c + Vector2(-s * 0.32, -s * 0.08), Vector2(s * 0.42, s * 0.16)), col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(s * 0.1, -s * 0.08), c + Vector2(s * 0.3, -s * 0.16),
				c + Vector2(s * 0.3, s * 0.16), c + Vector2(s * 0.1, s * 0.08)]), col.lightened(0.2))
			ci.draw_rect(Rect2(c + Vector2(s * 0.3, -s * 0.15), Vector2(s * 0.05, s * 0.3)), Color(1.0, 0.92, 0.6))
			ci.draw_rect(Rect2(c + Vector2(-s * 0.12, -s * 0.13), Vector2(s * 0.08, s * 0.05)), Color(0.7, 0.2, 0.15))
		"helmet":
			ci.draw_arc(c + Vector2(0, s * 0.08), s * 0.3, PI, TAU, 16, col, s * 0.02)
			var dome := PackedVector2Array()
			for k in 17:
				var a := PI + PI * k / 16.0
				dome.append(c + Vector2(cos(a) * s * 0.3, s * 0.08 + sin(a) * s * 0.3))
			ci.draw_colored_polygon(dome, col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.4, s * 0.06), Vector2(s * 0.8, s * 0.08)), col.darkened(0.25))
		"tshirt":
			# футболка: короткие рукава, вырез
			var tb := PackedVector2Array([c + Vector2(-s * 0.18, -s * 0.3), c + Vector2(s * 0.18, -s * 0.3), c + Vector2(s * 0.38, -s * 0.16),
				c + Vector2(s * 0.3, -s * 0.02), c + Vector2(s * 0.22, -s * 0.06), c + Vector2(s * 0.22, s * 0.32), c + Vector2(-s * 0.22, s * 0.32),
				c + Vector2(-s * 0.22, -s * 0.06), c + Vector2(-s * 0.3, -s * 0.02), c + Vector2(-s * 0.38, -s * 0.16)])
			ci.draw_colored_polygon(tb, col)
			ci.draw_arc(c + Vector2(0, -s * 0.3), s * 0.08, 0.0, PI, 10, col.darkened(0.4), maxf(1.5, s * 0.03))
		"sack":
			# вещмешок: горловина на шнурке, мешок, лямка
			ci.draw_line(c + Vector2(-s * 0.08, -s * 0.3), c + Vector2(s * 0.08, -s * 0.3), dark, maxf(2.0, s * 0.05))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.08, -s * 0.28), c + Vector2(s * 0.08, -s * 0.28),
				c + Vector2(s * 0.3, s * 0.05), c + Vector2(s * 0.26, s * 0.34), c + Vector2(-s * 0.26, s * 0.34), c + Vector2(-s * 0.3, s * 0.05)]), col)
			ci.draw_line(c + Vector2(-s * 0.06, -s * 0.24), c + Vector2(-s * 0.32, s * 0.3), col.darkened(0.35), maxf(1.5, s * 0.04))
		"jacket":
			var body := PackedVector2Array([c + Vector2(-s * 0.2, -s * 0.32), c + Vector2(s * 0.2, -s * 0.32), c + Vector2(s * 0.4, -s * 0.1),
				c + Vector2(s * 0.3, s * 0.0), c + Vector2(s * 0.22, -s * 0.06), c + Vector2(s * 0.22, s * 0.34), c + Vector2(-s * 0.22, s * 0.34),
				c + Vector2(-s * 0.22, -s * 0.06), c + Vector2(-s * 0.3, s * 0.0), c + Vector2(-s * 0.4, -s * 0.1)])
			ci.draw_colored_polygon(body, col)
			ci.draw_line(c + Vector2(0, -s * 0.3), c + Vector2(0, s * 0.33), col.darkened(0.45), maxf(1.5, s * 0.03))
			for k in 4:
				ci.draw_line(c + Vector2(-s * 0.2, -s * 0.18 + k * s * 0.12), c + Vector2(s * 0.2, -s * 0.18 + k * s * 0.12), col.darkened(0.25), maxf(1.0, s * 0.02))
		"repair_weapon", "repair_gear", "repair_gun":
			# чемоданчик с ручкой; на крышке — гаечный ключ (оружие) или катушка с иглой (одежда)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.1, -s * 0.3), Vector2(s * 0.2, s * 0.08)), dark)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.36, -s * 0.22), Vector2(s * 0.72, s * 0.5)), col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.36, -s * 0.22), Vector2(s * 0.72, s * 0.08)), col.darkened(0.25))
			var mark := Color(0.85, 0.83, 0.78)
			if id == "repair_weapon":
				ci.draw_line(c + Vector2(-s * 0.18, s * 0.18), c + Vector2(s * 0.12, -s * 0.06), mark, maxf(2.0, s * 0.07))
				ci.draw_circle(c + Vector2(s * 0.15, -s * 0.09), s * 0.08, mark)
				ci.draw_circle(c + Vector2(s * 0.19, -s * 0.13), s * 0.04, col)
			elif id == "repair_gun":
				# на крышке — патрон и шомпол (ремкомплект огнестрела)
				ci.draw_rect(Rect2(c + Vector2(-s * 0.22, -s * 0.04), Vector2(s * 0.14, s * 0.22)), mark)
				ci.draw_circle(c + Vector2(-s * 0.15, -s * 0.06), s * 0.07, Color(0.85, 0.66, 0.3))
				ci.draw_line(c + Vector2(s * 0.02, s * 0.18), c + Vector2(s * 0.22, -s * 0.06), mark, maxf(1.5, s * 0.04))
				ci.draw_circle(c + Vector2(s * 0.22, -s * 0.08), s * 0.05, mark)
			else:
				ci.draw_rect(Rect2(c + Vector2(-s * 0.12, -s * 0.08), Vector2(s * 0.16, s * 0.26)), mark)
				ci.draw_rect(Rect2(c + Vector2(-s * 0.15, -s * 0.1), Vector2(s * 0.22, s * 0.04)), dark)
				ci.draw_rect(Rect2(c + Vector2(-s * 0.15, s * 0.16), Vector2(s * 0.22, s * 0.04)), dark)
				ci.draw_line(c + Vector2(s * 0.12, -s * 0.1), c + Vector2(s * 0.22, s * 0.2), mark, maxf(1.0, s * 0.025))
		"mag":
			# магазин: чуть наклонный корпус, сверху виден патрон
			var body := PackedVector2Array([c + Vector2(-s * 0.12, -s * 0.3), c + Vector2(s * 0.08, -s * 0.3),
				c + Vector2(s * 0.16, s * 0.32), c + Vector2(-s * 0.04, s * 0.32)])
			ci.draw_colored_polygon(body, col.lightened(0.15))
			ci.draw_rect(Rect2(c + Vector2(-s * 0.06, s * 0.32), Vector2(s * 0.26, s * 0.05)), col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.08, -s * 0.38), Vector2(s * 0.12, s * 0.08)), Color(0.8, 0.62, 0.25))
		"ammo":
			for k in 3:
				var x := c.x + (k - 1) * s * 0.2
				ci.draw_rect(Rect2(Vector2(x - s * 0.06, c.y - s * 0.05), Vector2(s * 0.12, s * 0.3)), col)
				ci.draw_circle(Vector2(x, c.y - s * 0.07), s * 0.06, Color(0.65, 0.42, 0.25))
				ci.draw_rect(Rect2(Vector2(x - s * 0.065, c.y + s * 0.22), Vector2(s * 0.13, s * 0.04)), col.darkened(0.3))
		"stone":
			var pts := PackedVector2Array()
			for k in 9:
				var ang := TAU * k / 9.0
				var rr := s * (0.3 + 0.05 * sin(k * 2.3))
				pts.append(c + Vector2(cos(ang) * rr * 1.15, sin(ang) * rr * 0.85 + s * 0.04))
			ci.draw_colored_polygon(pts, col)
			ci.draw_circle(c + Vector2(-s * 0.08, -s * 0.06), s * 0.09, col.lightened(0.15))
			ci.draw_line(c + Vector2(s * 0.05, s * 0.02), c + Vector2(s * 0.2, s * 0.12), dark, maxf(1.0, s * 0.03))
		"twine":
			ci.draw_circle(c, s * 0.3, col.darkened(0.15))
			ci.draw_circle(c, s * 0.1, Color(0.12, 0.1, 0.08))
			for k in 6:
				var yy := -s * 0.25 + k * s * 0.1
				ci.draw_line(c + Vector2(-s * 0.26, yy), c + Vector2(s * 0.26, yy + s * 0.05), col.lightened(0.1), maxf(1.0, s * 0.025))
			ci.draw_line(c + Vector2(s * 0.25, s * 0.15), c + Vector2(s * 0.42, s * 0.38), col, maxf(1.5, s * 0.035))
		"backpack":
			# лямки, корпус, клапан с пряжкой, боковой карман
			var strap := col.darkened(0.35)
			ci.draw_arc(c + Vector2(0, -s * 0.24), s * 0.12, PI, TAU, 12, strap, maxf(2.0, s * 0.05))
			ci.draw_rect(Rect2(c + Vector2(-s * 0.27, -s * 0.24), Vector2(s * 0.54, s * 0.6)), col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.27, -s * 0.24), Vector2(s * 0.54, s * 0.22)), col.darkened(0.2))
			ci.draw_rect(Rect2(c + Vector2(-s * 0.05, -s * 0.05), Vector2(s * 0.1, s * 0.08)), Color(0.7, 0.62, 0.4))
			ci.draw_rect(Rect2(c + Vector2(-s * 0.18, s * 0.12), Vector2(s * 0.36, s * 0.18)), col.darkened(0.12))
			ci.draw_line(c + Vector2(-s * 0.18, s * 0.12), c + Vector2(s * 0.18, s * 0.12), dark, maxf(1.0, s * 0.02))
		"gloves":
			ci.draw_rect(Rect2(c + Vector2(-s * 0.18, -s * 0.05), Vector2(s * 0.36, s * 0.36)), col)
			for k in 4:
				ci.draw_rect(Rect2(c + Vector2(-s * 0.18 + k * s * 0.09, -s * 0.32), Vector2(s * 0.075, s * 0.3)), col)
			ci.draw_rect(Rect2(c + Vector2(s * 0.18, -s * 0.02), Vector2(s * 0.14, s * 0.08)), col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.2, s * 0.22), Vector2(s * 0.4, s * 0.08)), col.darkened(0.3))
		"pants":
			var p := PackedVector2Array([c + Vector2(-s * 0.26, -s * 0.34), c + Vector2(s * 0.26, -s * 0.34), c + Vector2(s * 0.3, s * 0.36),
				c + Vector2(s * 0.06, s * 0.36), c + Vector2(0, -s * 0.06), c + Vector2(-s * 0.06, s * 0.36), c + Vector2(-s * 0.3, s * 0.36)])
			ci.draw_colored_polygon(p, col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.26, -s * 0.34), Vector2(s * 0.52, s * 0.06)), col.darkened(0.35))
		"boots":
			var p := PackedVector2Array([c + Vector2(-s * 0.2, -s * 0.34), c + Vector2(s * 0.06, -s * 0.34), c + Vector2(s * 0.06, s * 0.06),
				c + Vector2(s * 0.36, s * 0.14), c + Vector2(s * 0.36, s * 0.32), c + Vector2(-s * 0.2, s * 0.32)])
			ci.draw_colored_polygon(p, col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.22, s * 0.26), Vector2(s * 0.6, s * 0.08)), Color(0.05, 0.04, 0.03))
		"ushanka":
			# меховой купол, отворот спереди, уши по бокам, красная звёздочка
			var fur := col.lightened(0.15)
			for sx in [-1.0, 1.0]:
				ci.draw_rect(Rect2(c + Vector2(sx * s * 0.36 - s * 0.08, -s * 0.02), Vector2(s * 0.16, s * 0.34)), fur)
			var dome := PackedVector2Array()
			for k in 17:
				var a := PI + PI * k / 16.0
				dome.append(c + Vector2(cos(a) * s * 0.32, s * 0.04 + sin(a) * s * 0.3))
			ci.draw_colored_polygon(dome, col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.36, -s * 0.06), Vector2(s * 0.72, s * 0.16)), fur)
			for k in 6:
				ci.draw_line(c + Vector2(-s * 0.32 + k * s * 0.13, -s * 0.05), c + Vector2(-s * 0.3 + k * s * 0.13, s * 0.09), fur.darkened(0.2), maxf(1.0, s * 0.02))
			ci.draw_circle(c + Vector2(0, s * 0.02), s * 0.04, Color(0.8, 0.15, 0.1))
		"moto_helmet":
			# армейский шлем: стальной купол с узкими полями, подбородочный ремень, лицо открыто
			var dome := PackedVector2Array()
			for k in 17:
				var a := PI + PI * k / 16.0
				dome.append(c + Vector2(cos(a) * s * 0.34, s * 0.06 + sin(a) * s * 0.34))
			ci.draw_colored_polygon(dome, col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.42, s * 0.04), Vector2(s * 0.84, s * 0.07)), col.darkened(0.3))   # поля
			ci.draw_arc(c + Vector2(0, s * 0.06), s * 0.26, PI * 1.15, PI * 1.45, 8, col.lightened(0.3), maxf(1.0, s * 0.03))   # блик
			ci.draw_line(c + Vector2(-s * 0.22, s * 0.11), c + Vector2(-s * 0.1, s * 0.36), Color(0.25, 0.2, 0.14), maxf(1.0, s * 0.03))   # ремень
			ci.draw_line(c + Vector2(s * 0.22, s * 0.11), c + Vector2(s * 0.1, s * 0.36), Color(0.25, 0.2, 0.14), maxf(1.0, s * 0.03))
			ci.draw_line(c + Vector2(-s * 0.1, s * 0.36), c + Vector2(s * 0.1, s * 0.36), Color(0.25, 0.2, 0.14), maxf(1.0, s * 0.03))
		"kurtka", "vest":
			var body := PackedVector2Array([c + Vector2(-s * 0.2, -s * 0.32), c + Vector2(s * 0.2, -s * 0.32), c + Vector2(s * 0.4, -s * 0.1),
				c + Vector2(s * 0.3, s * 0.0), c + Vector2(s * 0.22, -s * 0.06), c + Vector2(s * 0.22, s * 0.34), c + Vector2(-s * 0.22, s * 0.34),
				c + Vector2(-s * 0.22, -s * 0.06), c + Vector2(-s * 0.3, s * 0.0), c + Vector2(-s * 0.4, -s * 0.1)])
			if id == "vest":
				# без рукавов: корпус, стальные пластины, ремни
				body = PackedVector2Array([c + Vector2(-s * 0.14, -s * 0.34), c + Vector2(s * 0.14, -s * 0.34), c + Vector2(s * 0.26, -s * 0.2),
					c + Vector2(s * 0.26, s * 0.34), c + Vector2(-s * 0.26, s * 0.34), c + Vector2(-s * 0.26, -s * 0.2)])
			ci.draw_colored_polygon(body, col)
			if id == "vest":
				var plate := Color(0.55, 0.56, 0.55)
				ci.draw_rect(Rect2(c + Vector2(-s * 0.2, -s * 0.16), Vector2(s * 0.4, s * 0.22)), plate)
				ci.draw_rect(Rect2(c + Vector2(-s * 0.2, s * 0.09), Vector2(s * 0.4, s * 0.18)), plate.darkened(0.12))
				for k in 4:
					ci.draw_circle(c + Vector2(-s * 0.16 + (k % 2) * s * 0.32, -s * 0.12 + (1.0 if k >= 2 else 0.0) * s * 0.36), s * 0.02, Color(0.25, 0.24, 0.22))
				ci.draw_line(c + Vector2(-s * 0.26, s * 0.0), c + Vector2(s * 0.26, s * 0.0), Color(0.15, 0.12, 0.08), maxf(2.0, s * 0.05))
			else:
				ci.draw_line(c + Vector2(0, -s * 0.28), c + Vector2(0, s * 0.33), Color(0.75, 0.72, 0.65), maxf(1.5, s * 0.03))   # молния
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.2, -s * 0.32), c + Vector2(0, -s * 0.2),
					c + Vector2(s * 0.2, -s * 0.32), c + Vector2(s * 0.12, -s * 0.38), c + Vector2(-s * 0.12, -s * 0.38)]), col.darkened(0.3))   # воротник
				for sx in [-1.0, 1.0]:
					ci.draw_line(c + Vector2(sx * s * 0.08, s * 0.14), c + Vector2(sx * s * 0.18, s * 0.14), col.lightened(0.25), maxf(1.0, s * 0.025))   # карманы
		"jeans", "wpants":
			var p := PackedVector2Array([c + Vector2(-s * 0.26, -s * 0.34), c + Vector2(s * 0.26, -s * 0.34), c + Vector2(s * 0.3, s * 0.36),
				c + Vector2(s * 0.06, s * 0.36), c + Vector2(0, -s * 0.06), c + Vector2(-s * 0.06, s * 0.36), c + Vector2(-s * 0.3, s * 0.36)])
			ci.draw_colored_polygon(p, col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.26, -s * 0.34), Vector2(s * 0.52, s * 0.06)), col.darkened(0.35))
			if id == "jeans":
				var st := Color(0.85, 0.6, 0.25)   # рыжая строчка, заклёпки
				for sx in [-1.0, 1.0]:
					ci.draw_line(c + Vector2(sx * s * 0.22, -s * 0.26), c + Vector2(sx * s * 0.25, s * 0.34), st, maxf(1.0, s * 0.015))
				ci.draw_arc(c + Vector2(-s * 0.18, -s * 0.28), s * 0.08, 0.0, PI / 2, 6, st, maxf(1.0, s * 0.015))
				ci.draw_arc(c + Vector2(s * 0.18, -s * 0.28), s * 0.08, PI / 2, PI, 6, st, maxf(1.0, s * 0.015))
			else:
				for k in 5:
					var yy := -s * 0.2 + k * s * 0.12
					ci.draw_line(c + Vector2(-s * 0.27, yy), c + Vector2(-s * 0.04, yy), col.darkened(0.3), maxf(1.0, s * 0.02))
					ci.draw_line(c + Vector2(s * 0.04, yy), c + Vector2(s * 0.27, yy), col.darkened(0.3), maxf(1.0, s * 0.02))
		"sneakers":
			# низкий кед: тканевый верх, белая подошва и носок, шнурки
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.36, -s * 0.06), c + Vector2(-s * 0.1, -s * 0.12),
				c + Vector2(s * 0.12, s * 0.02), c + Vector2(s * 0.38, s * 0.1), c + Vector2(s * 0.38, s * 0.2), c + Vector2(-s * 0.36, s * 0.2)]), col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.38, s * 0.18), Vector2(s * 0.78, s * 0.1)), Color(0.9, 0.88, 0.84))
			ci.draw_circle(c + Vector2(s * 0.32, s * 0.15), s * 0.07, Color(0.9, 0.88, 0.84))
			for k in 3:
				var x := -s * 0.08 + k * s * 0.08
				ci.draw_line(c + Vector2(x, -s * 0.06 + k * s * 0.04), c + Vector2(x + s * 0.06, -s * 0.02 + k * s * 0.04), Color(0.95, 0.95, 0.95), maxf(1.0, s * 0.025))
		"tac_gloves":
			# как рабочие, но чёрные, с вырезами и стальными накладками на костяшках
			ci.draw_rect(Rect2(c + Vector2(-s * 0.18, -s * 0.05), Vector2(s * 0.36, s * 0.36)), col)
			for k in 4:
				ci.draw_rect(Rect2(c + Vector2(-s * 0.18 + k * s * 0.09, -s * 0.32), Vector2(s * 0.075, s * 0.3)), col)
				ci.draw_rect(Rect2(c + Vector2(-s * 0.18 + k * s * 0.09, -s * 0.32), Vector2(s * 0.075, s * 0.08)), Color(0.75, 0.6, 0.48))
			ci.draw_rect(Rect2(c + Vector2(s * 0.18, -s * 0.02), Vector2(s * 0.14, s * 0.08)), col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.2, -s * 0.08), Vector2(s * 0.4, s * 0.08)), Color(0.55, 0.56, 0.58))
			for k in 4:
				ci.draw_circle(c + Vector2(-s * 0.14 + k * s * 0.09, -s * 0.04), s * 0.03, Color(0.78, 0.78, 0.8))
			ci.draw_rect(Rect2(c + Vector2(-s * 0.2, s * 0.22), Vector2(s * 0.4, s * 0.08)), Color(0.3, 0.32, 0.28))
		"nut":
			var pts := PackedVector2Array()
			for k in 6:
				var a := TAU * k / 6.0 + PI / 6.0
				pts.append(c + Vector2(cos(a), sin(a)) * s * 0.3)
			ci.draw_colored_polygon(pts, col)
			ci.draw_circle(c, s * 0.12, Color(0.08, 0.08, 0.08))
		"lockpick":
			# две тонкие отмычки крест-накрест в кожаном чехле: крючок и граблевидная
			var lw := maxf(1.5, s * 0.05)
			var st := Color(0.78, 0.8, 0.84)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.3, s * 0.12), Vector2(s * 0.6, s * 0.26)), Color(0.36, 0.22, 0.12))
			ci.draw_line(c + Vector2(-s * 0.3, s * 0.2), c + Vector2(s * 0.3, s * 0.2), Color(0.2, 0.12, 0.07), maxf(1.0, s * 0.02))
			ci.draw_line(c + Vector2(-s * 0.2, s * 0.14), c + Vector2(-s * 0.06, -s * 0.34), st, lw, true)
			ci.draw_line(c + Vector2(-s * 0.06, -s * 0.34), c + Vector2(s * 0.04, -s * 0.38), st, lw, true)
			ci.draw_line(c + Vector2(s * 0.2, s * 0.14), c + Vector2(s * 0.08, -s * 0.3), st.darkened(0.15), lw, true)
			for k in 3:
				var tx := c + Vector2(s * (0.08 - 0.035 * k) + s * 0.0, -s * (0.3 - 0.0) + s * 0.07 * k)
				ci.draw_line(tx, tx + Vector2(s * 0.08, 0), st.darkened(0.15), maxf(1.0, s * 0.03), true)
		"car_key":
			# ключ по диагонали: чёрная пластмассовая головка, стальное жало с бородкой, кольцо и латунная бирка
			var d := Vector2(1, 1).normalized()          # вдоль жала
			var n := Vector2(-d.y, d.x)                  # поперёк
			var hc := c - d * s * 0.12
			var head := PackedVector2Array([hc - d * s * 0.14 - n * s * 0.12, hc + d * s * 0.06 - n * s * 0.12,
				hc + d * s * 0.06 + n * s * 0.12, hc - d * s * 0.14 + n * s * 0.12])
			ci.draw_colored_polygon(head, Color(0.08, 0.08, 0.08))
			ci.draw_line(hc - d * s * 0.1 - n * s * 0.08, hc - d * s * 0.1 + n * s * 0.08, Color(0.3, 0.3, 0.3), maxf(1.0, s * 0.03))
			var b0 := hc + d * s * 0.06
			var b1 := b0 + d * s * 0.36
			var steel := Color(0.72, 0.73, 0.72)
			ci.draw_colored_polygon(PackedVector2Array([b0 - n * s * 0.05, b1 - n * s * 0.05, b1 + d * s * 0.03, b1 + n * s * 0.03, b0 + n * s * 0.05]), steel)
			for k in 3:
				var tp := b0.lerp(b1, 0.3 + 0.22 * k)
				ci.draw_colored_polygon(PackedVector2Array([tp + n * s * 0.04, tp + d * s * 0.04 + n * s * 0.1, tp + d * s * 0.08 + n * s * 0.04]), steel.darkened(0.15))
			ci.draw_line(b0, b1, steel.darkened(0.35), maxf(1.0, s * 0.02))
			var rc := hc - d * s * 0.2
			ci.draw_arc(rc, s * 0.08, 0.0, TAU, 16, Color(0.6, 0.6, 0.58), maxf(1.5, s * 0.03), true)
			var tg := rc + Vector2(-s * 0.12, s * 0.02)
			ci.draw_rect(Rect2(tg - Vector2(s * 0.08, 0), Vector2(s * 0.13, s * 0.2)), col)
			ci.draw_circle(tg + Vector2(-s * 0.015, s * 0.04), s * 0.02, Color(0.1, 0.08, 0.05))


## Маленькая 3D-модель предмета (для лежащих на полу вещей).
## Иконка модуля огнестрела (промпт 20.11 18:43): c — центр, s — размер ячейки.
static func _mod_icon(ci: CanvasItem, id: String, c: Vector2, s: float, col: Color) -> void:
	var lt := col.lightened(0.35)
	var red := Color(1.0, 0.2, 0.12)
	var w := maxf(1.5, s * 0.05)
	match id:
		"mod_reddot":
			ci.draw_rect(Rect2(c + Vector2(-s * 0.3, s * 0.12), Vector2(s * 0.6, s * 0.1)), col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.22, -s * 0.22), Vector2(s * 0.44, s * 0.34)), lt, false, w)
			ci.draw_circle(c + Vector2(0, -s * 0.05), s * 0.05, red)
		"mod_scope":
			ci.draw_rect(Rect2(c + Vector2(-s * 0.34, -s * 0.1), Vector2(s * 0.64, s * 0.18)), lt)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.4, -s * 0.13), Vector2(s * 0.08, s * 0.24)), col)
			ci.draw_rect(Rect2(c + Vector2(s * 0.28, -s * 0.16), Vector2(s * 0.12, s * 0.3)), col)
			for x in [-0.15, 0.1]:
				ci.draw_rect(Rect2(c + Vector2(s * x, s * 0.08), Vector2(s * 0.06, s * 0.12)), col)
		"mod_silencer":
			ci.draw_rect(Rect2(c + Vector2(-s * 0.38, -s * 0.11), Vector2(s * 0.76, s * 0.22)), lt)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.44, -s * 0.06), Vector2(s * 0.06, s * 0.12)), col)
		"mod_comp":
			ci.draw_rect(Rect2(c + Vector2(-s * 0.22, -s * 0.12), Vector2(s * 0.44, s * 0.24)), lt)
			for k in 3:
				ci.draw_rect(Rect2(c + Vector2(-s * 0.15 + k * s * 0.11, -s * 0.12), Vector2(s * 0.05, s * 0.1)), col.darkened(0.5))
		"mod_stock":
			ci.draw_line(c + Vector2(s * 0.32, -s * 0.15), c + Vector2(-s * 0.3, -s * 0.2), lt, w)
			ci.draw_line(c + Vector2(s * 0.32, s * 0.15), c + Vector2(-s * 0.3, s * 0.2), lt, w)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.38, -s * 0.32), Vector2(s * 0.1, s * 0.64)), col.darkened(0.2))
		"mod_grip":
			ci.draw_rect(Rect2(c + Vector2(-s * 0.3, -s * 0.3), Vector2(s * 0.6, s * 0.1)), lt)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.1, -s * 0.22), Vector2(s * 0.2, s * 0.52)), col.lightened(0.15))
		"mod_laser":
			ci.draw_rect(Rect2(c + Vector2(-s * 0.32, -s * 0.12), Vector2(s * 0.5, s * 0.24)), lt)
			ci.draw_line(c + Vector2(s * 0.18, 0), c + Vector2(s * 0.44, 0), red, w * 0.8)
			ci.draw_circle(c + Vector2(s * 0.18, 0), s * 0.04, red)


static func make_mesh(id: String) -> Node3D:
	var own_col: Color = ITEMS[id]["color"] if ITEMS.has(id) else Color.WHITE
	if ITEMS.has(id) and ITEMS[id].has("mod"):
		# модуль огнестрела: та же модель, что на пистолете (weapons.gd: add_mod), сдвинутая к центру
		var mw := Node3D.new()
		var g := Weapons.add_mod(mw, id)
		var off := {"mod_stock": Vector3(0.12, -0.04, 0), "mod_silencer": Vector3(-0.19, -0.1, 0), "mod_comp": Vector3(-0.157, -0.1, 0),
			"mod_grip": Vector3(-0.11, -0.05, 0), "mod_laser": Vector3(-0.11, -0.06, 0)}
		g.position = off.get(id, Vector3(-0.072, -0.13, 0))
		return mw
	id = model_of(id)
	# армейские версии (деревня) — те же модели, что у обычных
	if id == "gasmask2" or id == "snyuhatel5088":
		id = "gasmask"
	elif id == "filter2":
		id = "filter"
	if id in ["bat", "pipe", "crowbar", "machete", "knife", "gasmask", "filter", "hammer", "steel_hammer", "hatchet", "shiv", "spiked_club", "pistol", "sawnoff", "rifle", "smg"]:
		var w := Weapons.make(id)
		if id in ["bat", "pipe", "crowbar", "machete", "knife", "hammer", "steel_hammer", "hatchet", "shiv", "spiked_club"]:
			w.rotation.z = PI / 2   # на полу оружие лежит
		elif id in ["pistol", "sawnoff", "rifle", "smg"]:
			# пистолет лежит на боку (модель — в плоскости XY): плоская сторона вниз, по центру коробки
			w.rotation.x = -PI / 2
			w.position = Vector3(-0.065, 0.014, 0.065)
		return w
	var col: Color = own_col
	var mi := MeshInstance3D.new()
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.6
	# лёгкое свечение — чтобы лут было видно в темноте
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 0.25
	match id:
		"coin":
			var cm := CylinderMesh.new()
			cm.top_radius = 0.05
			cm.bottom_radius = 0.05
			cm.height = 0.014
			cm.radial_segments = 16
			mi.mesh = cm
			m.metallic = 0.8
			m.roughness = 0.35
		"medkit":
			var bm := BoxMesh.new()
			bm.size = Vector3(0.24, 0.12, 0.17)
			mi.mesh = bm
			m.albedo_color = Color(0.75, 0.72, 0.66)
			m.emission = col
		"bandage":
			var cm := CylinderMesh.new()
			cm.top_radius = 0.04
			cm.bottom_radius = 0.04
			cm.height = 0.07
			mi.mesh = cm
		"rusk":
			var bm := BoxMesh.new()
			bm.size = Vector3(0.09, 0.035, 0.065)
			mi.mesh = bm
		"battery":
			var cm := CylinderMesh.new()
			cm.top_radius = 0.022
			cm.bottom_radius = 0.022
			cm.height = 0.1
			mi.mesh = cm
		"knuckles":
			var bm := BoxMesh.new()
			bm.size = Vector3(0.13, 0.03, 0.05)
			mi.mesh = bm
			m.metallic = 0.8
			m.roughness = 0.4
		"soda":
			var cm := CylinderMesh.new()
			cm.top_radius = 0.033
			cm.bottom_radius = 0.033
			cm.height = 0.12
			mi.mesh = cm
			m.metallic = 0.6
		"choco":
			var bm := BoxMesh.new()
			bm.size = Vector3(0.12, 0.015, 0.06)
			mi.mesh = bm
		"canned", "water", "tape":
			var cm := CylinderMesh.new()
			cm.top_radius = 0.045 if id != "water" else 0.035
			cm.bottom_radius = cm.top_radius
			cm.height = {"canned": 0.09, "water": 0.22, "tape": 0.04}[id]
			mi.mesh = cm
			m.metallic = 0.6 if id == "canned" else 0.0
		"pills", "wallet", "photo", "scrap":
			var bm := BoxMesh.new()
			bm.size = {"pills": Vector3(0.1, 0.012, 0.06), "wallet": Vector3(0.12, 0.025, 0.09),
				"photo": Vector3(0.1, 0.004, 0.13), "scrap": Vector3(0.18, 0.03, 0.06)}[id]
			mi.mesh = bm
		"wood":
			var bm := BoxMesh.new()
			bm.size = Vector3(0.22, 0.03, 0.05)
			mi.mesh = bm
		"glass":
			var pm := PrismMesh.new()
			pm.size = Vector3(0.06, 0.09, 0.006)
			mi.mesh = pm
			mi.rotation.x = -PI / 2
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color = Color(col.r, col.g, col.b, 0.6)
			m.roughness = 0.1
		"broom":
			var bm := BoxMesh.new()
			bm.size = Vector3(0.6, 0.03, 0.12)
			mi.mesh = bm
		"flashlight":
			var cm := CylinderMesh.new()
			cm.top_radius = 0.03
			cm.bottom_radius = 0.022
			cm.height = 0.16
			mi.mesh = cm
			mi.rotation.z = PI / 2
		"helmet", "ushanka":
			var sm := SphereMesh.new()
			sm.radius = 0.13
			sm.height = 0.14
			sm.is_hemisphere = true
			mi.mesh = sm
			if id == "ushanka":
				m.roughness = 1.0
		"moto_helmet":
			# армейский шлем: невысокий стальной купол (промпт 18.11 00:45)
			var sm := SphereMesh.new()
			sm.radius = 0.15
			sm.height = 0.13
			sm.is_hemisphere = true
			mi.mesh = sm
			m.roughness = 0.55
			m.metallic = 0.35
		"jacket", "pants", "rag_pants", "kurtka", "vest", "jeans", "wpants", "tshirt":
			var bm := BoxMesh.new()
			bm.size = Vector3(0.4, 0.06, 0.32) if id in ["jacket", "kurtka", "vest", "tshirt"] else Vector3(0.3, 0.05, 0.42)
			if id == "vest":
				bm.size = Vector3(0.34, 0.08, 0.36)
				m.metallic = 0.4
			mi.mesh = bm
		"boots", "sneakers":
			var bm := BoxMesh.new()
			bm.size = Vector3(0.12, 0.22, 0.26) if id == "boots" else Vector3(0.11, 0.09, 0.26)
			mi.mesh = bm
		"backpack":
			var bm := BoxMesh.new()
			bm.size = Vector3(0.28, 0.36, 0.14)
			mi.mesh = bm
		"sack":
			var sm := SphereMesh.new()   # мягкий округлый мешок, не коробка (промпт 18.11 00:55)
			sm.radius = 0.1
			sm.height = 0.24
			mi.mesh = sm
			mi.scale = Vector3(1.0, 1.0, 0.7)
			m.roughness = 1.0
		"repair_weapon", "repair_gear", "repair_gun":
			var bm := BoxMesh.new()
			bm.size = Vector3(0.2, 0.08, 0.14)
			mi.mesh = bm
		"gloves", "tac_gloves":
			var bm := BoxMesh.new()
			bm.size = Vector3(0.12, 0.03, 0.17)
			mi.mesh = bm
		"gear":
			var cm := CylinderMesh.new()
			cm.top_radius = 0.05
			cm.bottom_radius = 0.05
			cm.height = 0.015
			cm.radial_segments = 12
			mi.mesh = cm
			m.metallic = 0.7
		_:
			var cm := CylinderMesh.new()
			cm.top_radius = 0.03
			cm.bottom_radius = 0.03
			cm.height = 0.02
			cm.radial_segments = 6
			mi.mesh = cm
			m.metallic = 0.7
	mi.material_override = m
	return mi
