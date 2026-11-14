extends RefCounted
const Weapons := preload("res://weapons.gd")
## Справочник предметов (тестовые механики): название, описание, размер стака, иконка и 3D-модель.
## Иконки и модели рисуются кодом, файлов нет.

const ITEMS := {
	"coin": {"name": "Монета", "desc": "Старая монета. Её ест игровой автомат.", "stack": 999,
		"icon": "coin", "color": Color(0.86, 0.66, 0.3)},
	"medkit": {"name": "Аптечка", "desc": "Восстанавливает 50 здоровья.", "stack": 5,
		"icon": "medkit", "color": Color(0.72, 0.16, 0.12), "heal": 50.0},
	"bandage": {"name": "Бинт", "desc": "Восстанавливает 20 здоровья.", "stack": 10,
		"icon": "bandage", "color": Color(0.84, 0.8, 0.7), "heal": 20.0},
	# еда — сопротивление урону, напитки — скорость (game.gd: buffs). Лечат только аптечка, бинт, таблетки.
	"rusk": {"name": "Сухарь", "desc": "Еда: −10% входящего урона на 30 с.", "stack": 10,
		"icon": "rusk", "color": Color(0.6, 0.42, 0.22), "buff": "resist", "power": 0.10, "time": 30.0},
	"choco": {"name": "Шоколадка", "desc": "Еда: −20% входящего урона на 60 с.", "stack": 6,
		"icon": "choco", "color": Color(0.36, 0.2, 0.12), "buff": "resist", "power": 0.20, "time": 60.0},
	"soda": {"name": "Газировка", "desc": "Напиток: +30% к скорости на 60 с.", "stack": 6,
		"icon": "soda", "color": Color(0.75, 0.2, 0.15), "buff": "speed", "power": 0.30, "time": 60.0},
	"broom": {"name": "Метла с совком", "desc": "Использовать у битого стекла — вымести его.", "stack": 1,
		"icon": "broom", "color": Color(0.6, 0.48, 0.25)},
	"flashlight": {"name": "Фонарик", "desc": "F или клавиша хотбара — включить. Нужны батарейки.", "stack": 1,
		"icon": "flashlight", "color": Color(0.3, 0.32, 0.3)},
	"battery": {"name": "Батарейка", "desc": "Полностью заряжает фонарик (F).", "stack": 10,
		"icon": "battery", "color": Color(0.34, 0.44, 0.3)},
	"knuckles": {"name": "Кастет", "desc": "Руки: удар кулаком ×1.5.", "stack": 1,
		"icon": "knuckles", "color": Color(0.58, 0.58, 0.6), "equip": "hands", "fist": 1.5},
	# одежда (магазин снаряжения): слот и небольшой эффект
	"helmet": {"name": "Каска", "desc": "Голова: −10% урона.", "stack": 1,
		"icon": "helmet", "color": Color(0.78, 0.6, 0.15), "equip": "head", "armor": 0.10},
	"jacket": {"name": "Ватник", "desc": "Тело: −15% урона.", "stack": 1,
		"icon": "jacket", "color": Color(0.24, 0.27, 0.21), "equip": "body", "armor": 0.15},
	"gloves": {"name": "Рабочие перчатки", "desc": "Руки: удар кулаком ×1.2.", "stack": 1,
		"icon": "gloves", "color": Color(0.55, 0.48, 0.32), "equip": "hands", "fist": 1.2},
	"pants": {"name": "Рабочие штаны", "desc": "Ноги: +8% к скорости.", "stack": 1,
		"icon": "pants", "color": Color(0.2, 0.24, 0.32), "equip": "legs", "speed": 0.08},
	"boots": {"name": "Кирзовые сапоги", "desc": "Обувь: стекло не ранит. Изнашиваются от ходьбы и стекла.", "stack": 1,
		"icon": "boots", "color": Color(0.17, 0.13, 0.1), "equip": "feet", "glassproof": true, "dur": 100},
	"canned": {"name": "Тушёнка", "desc": "Еда: −30% входящего урона на 90 с.", "stack": 5,
		"icon": "canned", "color": Color(0.55, 0.56, 0.58), "buff": "resist", "power": 0.30, "time": 90.0},
	"water": {"name": "Бутылка воды", "desc": "Напиток: +15% к скорости на 30 с.", "stack": 6,
		"icon": "water", "color": Color(0.45, 0.6, 0.7), "buff": "speed", "power": 0.15, "time": 30.0},
	"pills": {"name": "Обезболивающее", "desc": "Блистер таблеток. +15 здоровья.", "stack": 8,
		"icon": "pills", "color": Color(0.85, 0.85, 0.82), "heal": 15.0},
	"wallet": {"name": "Старый кошелёк", "desc": "Открыть: внутри 10–40 монет.", "stack": 5,
		"icon": "wallet", "color": Color(0.32, 0.2, 0.12)},
	"scrap": {"name": "Металлолом", "desc": "Гнутые железки. Хлам — магазин купит за 3 монеты.", "stack": 20, "price": 3, "junk": true,
		"icon": "scrap", "color": Color(0.4, 0.33, 0.28)},
	"gear": {"name": "Шестерёнка", "desc": "Из какого-то механизма. Хлам — магазин купит за 3 монеты.", "stack": 20, "price": 3, "junk": true,
		"icon": "gear", "color": Color(0.55, 0.5, 0.4)},
	"tape": {"name": "Изолента", "desc": "Синяя. Нужна для ножика. Магазин купит за 2 монеты.", "stack": 10, "price": 2,
		"icon": "tape", "color": Color(0.2, 0.3, 0.6)},
	"photo": {"name": "Старое фото", "desc": "Люди в касках у входа в бункер. Лица выцвели. Магазин купит за 5 монет.", "stack": 5, "price": 5, "junk": true,
		"icon": "photo", "color": Color(0.75, 0.68, 0.55)},
	"nut": {"name": "Гайка", "desc": "Бесполезный хлам. Магазин купит за 2 монеты.", "stack": 20, "price": 2, "junk": true,
		"icon": "nut", "color": Color(0.46, 0.46, 0.46)},
	# оружие ближнего боя из магазина (weapons.gd): «использовать» — взять в правую руку
	"bat": {"name": "Бита", "desc": "Деревянная бита. Урон ×2.0, бьёт чуть дальше.", "stack": 1,
		"icon": "bat", "color": Color(0.55, 0.38, 0.22), "weapon": true, "dur": 40},
	"pipe": {"name": "Труба", "desc": "Стальная труба. Урон ×2.5.", "stack": 1,
		"icon": "pipe", "color": Color(0.42, 0.43, 0.44), "weapon": true, "dur": 60},
	"crowbar": {"name": "Монтировка", "desc": "Тяжёлая, красная. Урон ×3.0.", "stack": 1,
		"icon": "crowbar", "color": Color(0.6, 0.14, 0.1), "weapon": true, "dur": 80},
	"machete": {"name": "Мачете", "desc": "Широкий клинок. Урон ×3.6.", "stack": 1,
		"icon": "machete", "color": Color(0.62, 0.63, 0.62), "weapon": true, "dur": 70},
	"shield": {"name": "Щит", "desc": "В левой руке — 50% блокирует удар. В правой — бьёт краем (чуть слабее биты).", "stack": 1,
		"icon": "shield", "color": Color(0.38, 0.39, 0.4), "weapon": true, "dur": 40},
	"knife": {"name": "Ножик", "desc": "Самодельный: деревяшка, осколок стекла, изолента. Урон ×2.2.", "stack": 1,
		"icon": "knife", "color": Color(0.55, 0.7, 0.68), "weapon": true, "dur": 15},
	# материалы для крафта
	"wood": {"name": "Деревяшка", "desc": "Обломок доски. Нужна для крафта.", "stack": 5,
		"icon": "wood", "color": Color(0.5, 0.35, 0.2)},
	"glass": {"name": "Кусочек стекла", "desc": "Острый осколок. Нужен для крафта.", "stack": 5,
		"icon": "glass", "color": Color(0.6, 0.78, 0.76)},
	# противогаз (G — надеть/снять) и фильтры к нему
	"gasmask": {"name": "Противогаз", "desc": "Голова. G — надеть/снять. Наверху без него плохо.", "stack": 1,
		"icon": "gasmask", "color": Color(0.22, 0.25, 0.2), "equip": "head"},
	"filter": {"name": "Фильтр", "desc": "Сменный фильтр противогаза: 90 секунд наверху.", "stack": 10,
		"icon": "filter", "color": Color(0.36, 0.38, 0.3)},
}


## Рецепты крафта: что получится и что нужно.
const RECIPES := [
	{"out": "knife", "need": {"wood": 1, "glass": 1, "tape": 1}},
]


## Куда надевается предмет: hand (левая или правая рука), head (голова), hands (кастет) или "".
static func equip_slot(id: String) -> String:
	if not ITEMS.has(id):
		return ""
	if ITEMS[id].has("weapon"):
		return "hand"
	return String(ITEMS[id].get("equip", ""))


## Подходит ли предмет в слот экипировки (left/right/head/hands).
static func fits(id: String, slot: String) -> bool:
	var k := equip_slot(id)
	if k == "hand":
		return slot == "left" or slot == "right"
	return k != "" and k == slot


## Прочность предмета (0 — вечный): оружие ломается от ударов, сапоги — от ходьбы и стекла.
static func max_dur(id: String) -> float:
	return float(ITEMS[id].get("dur", 0)) if ITEMS.has(id) else 0.0


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
	if String(ITEMS[id]["icon"]) in ["bat", "pipe", "crowbar", "machete", "knife", "shield", "gasmask", "filter"]:
		Weapons.draw_icon(ci, String(ITEMS[id]["icon"]), r, col)
		return
	match String(ITEMS[id]["icon"]):
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
			ci.draw_rect(Rect2(c + Vector2(0, s * 0.05), Vector2(s * 0.38, s * 0.16)), col.darkened(0.1))
			ci.draw_circle(c, s * 0.27, col)
			ci.draw_arc(c, s * 0.18, 0.0, TAU, 24, col.darkened(0.2), maxf(1.0, s * 0.03), true)
			ci.draw_circle(c, s * 0.08, col.darkened(0.5))
		"choco":
			var box := Rect2(c - Vector2(s * 0.34, s * 0.2), Vector2(s * 0.68, s * 0.4))
			ci.draw_rect(box, col)
			ci.draw_rect(Rect2(box.position + Vector2(s * 0.34, 0), Vector2(s * 0.34, s * 0.4)), Color(0.8, 0.75, 0.6))
			for k in 2:
				ci.draw_line(box.position + Vector2(s * 0.11 * (k + 1), 0), box.position + Vector2(s * 0.11 * (k + 1), s * 0.4), col.darkened(0.4), maxf(1.0, s * 0.03))
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
			ci.draw_rect(Rect2(body.position + Vector2(0, s * 0.42), Vector2(body.size.x, s * 0.22)), Color(0.15, 0.15, 0.15))
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
			var box := Rect2(c - Vector2(s * 0.34, s * 0.22), Vector2(s * 0.68, s * 0.44))
			ci.draw_rect(box, Color(0.7, 0.72, 0.75))
			for k in 6:
				ci.draw_circle(c + Vector2((k % 3 - 1) * s * 0.2, (k / 3 - 0.5) * s * 0.2), s * 0.07, col)
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
		"jacket":
			var body := PackedVector2Array([c + Vector2(-s * 0.2, -s * 0.32), c + Vector2(s * 0.2, -s * 0.32), c + Vector2(s * 0.4, -s * 0.1),
				c + Vector2(s * 0.3, s * 0.0), c + Vector2(s * 0.22, -s * 0.06), c + Vector2(s * 0.22, s * 0.34), c + Vector2(-s * 0.22, s * 0.34),
				c + Vector2(-s * 0.22, -s * 0.06), c + Vector2(-s * 0.3, s * 0.0), c + Vector2(-s * 0.4, -s * 0.1)])
			ci.draw_colored_polygon(body, col)
			ci.draw_line(c + Vector2(0, -s * 0.3), c + Vector2(0, s * 0.33), col.darkened(0.45), maxf(1.5, s * 0.03))
			for k in 4:
				ci.draw_line(c + Vector2(-s * 0.2, -s * 0.18 + k * s * 0.12), c + Vector2(s * 0.2, -s * 0.18 + k * s * 0.12), col.darkened(0.25), maxf(1.0, s * 0.02))
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
		"nut":
			var pts := PackedVector2Array()
			for k in 6:
				var a := TAU * k / 6.0 + PI / 6.0
				pts.append(c + Vector2(cos(a), sin(a)) * s * 0.3)
			ci.draw_colored_polygon(pts, col)
			ci.draw_circle(c, s * 0.12, Color(0.08, 0.08, 0.08))


## Маленькая 3D-модель предмета (для лежащих на полу вещей).
static func make_mesh(id: String) -> Node3D:
	if id in ["bat", "pipe", "crowbar", "machete", "knife", "shield", "gasmask", "filter"]:
		var w := Weapons.make(id)
		if id in ["bat", "pipe", "crowbar", "machete", "knife"]:
			w.rotation.z = PI / 2   # на полу оружие лежит
		return w
	var col: Color = ITEMS[id]["color"] if ITEMS.has(id) else Color.WHITE
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
		"helmet":
			var sm := SphereMesh.new()
			sm.radius = 0.13
			sm.height = 0.14
			sm.is_hemisphere = true
			mi.mesh = sm
		"jacket", "pants":
			var bm := BoxMesh.new()
			bm.size = Vector3(0.4, 0.06, 0.32) if id == "jacket" else Vector3(0.3, 0.05, 0.42)
			mi.mesh = bm
		"boots":
			var bm := BoxMesh.new()
			bm.size = Vector3(0.12, 0.22, 0.26)
			mi.mesh = bm
		"gloves":
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
