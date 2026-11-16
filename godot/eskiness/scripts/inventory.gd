extends CanvasLayer
## Инвентарь: сетка 5×4 (+ отсек рюкзака и карманы одежды; монеты — отдельный кошелёк), снаряжение на силуэте человека
## (голова, лицо — противогаз, спина — рюкзак, тело, руки, ноги, обувь, левая и правая рука — оружие/щит), хотбар 1–5 и крафт.
## Tab / I — открыть/закрыть, игра не на паузе.
##   ЛКМ — использовать / надеть / снять; ПКМ — меню действий (промпт 14.11 19:07);
##   Shift+ПКМ — выбросить 1 шт., Shift + держать ПКМ — выбросить всю стопку (кольцо на ячейке);
##   перетаскивание мышью между ячейками и в слоты снаряжения, за окно — выбросить (стопка — спросит сколько);
##   палец: долгое нажатие — то же меню; навёл + 1–5 — хотбар.
##   Хотбар (ссылки на предметы, hud.gd рисует внизу): пока окно открыто, на его ячейки можно перетащить предмет,
##   ячейку хотбара — на другую (обмен) или обратно в сумку / за окно (отвязать).
## Сам инвентарь хранит данные и шлёт сигналы; что делает предмет — решает game.gd.

signal changed
signal use_requested(idx: int)
signal drop_requested(idx: int, all: bool)
signal drop_count_requested(idx: int, n: int)
signal drop_coins_requested(n: int)
signal equip_requested(idx: int, slot: String)
signal unequip_requested(slot: String, to_idx: int)
signal drop_equipped_requested(slot: String)
signal craft_requested(recipe: int)
signal repair_requested(kit_idx: int, target)   # target — номер ячейки или слот экипировки
signal message(text: String)
signal spilled(items: Array)   # не влезли после пропажи блока ячеек — game.gd выбрасывает на пол

const Items := preload("res://scripts/items.gd")
const Gun := preload("res://scripts/gun.gd")
## Сетка (промпт 16.11 02:42): сумка 5×5 без зазоров (с 03:44 — 5×4), предметы занимают w×h ячеек (Items.SIZES),
## пробел при перетаскивании — повернуть. Предмет хранится в ячейке-якоре (левый верхний угол),
## остальные ячейки под ним — null; "r": true — повёрнут. Отдельные блоки: рюкзак и карманы одежды.
## Блок: [первая ячейка, макс. ширина, макс. высота, слот снаряжения ("" — сумка), подпись].
## Индексы фиксированы (ячейка = начало + y * макс.ширина + x), активна только часть, которую даёт вещь.
## сумка 5×4 (промпт 16.11 03:44, было 5×5 — сейвы без "bag_layout" сдвигаются, см. migrate_bag)
const BLOCKS := [[0, 5, 4, "", "СУМКА"], [20, 5, 3, "back", "РЮКЗАК"], [35, 3, 2, "body", "КАРМАНЫ: ВЕРХ"], [41, 3, 2, "legs", "КАРМАНЫ: ШТАНЫ"]]
const TOTAL := 47
const BAG := 20                  # ячеек основной сумки
const BAG_LAYOUT := 2            # версия раскладки номеров ячеек в сейве
const COLS := 5
const SLOT := 76.0
const CELL := 58.0               # ячейка сетки сумки
const EQUIP := ["head", "face", "back", "body", "hands", "legs", "feet", "left", "right"]
const EQUIP_NAMES := {"head": "Голова", "face": "Лицо", "back": "Спина", "body": "Тело", "hands": "Руки", "legs": "Ноги", "feet": "Обувь",
	"left": "Левая", "right": "Правая"}
## Слоты вплотную в форме тела, без фигуры и подписей (промпт 04:23; вид со спины: левая рука слева).
## В пустом слоте — полупрозрачная иконка части тела (Slot._draw_part). Перчатки — на обеих кистях (HANDS2 —
## второй квадратик того же слота).
const DOLL_POS := {"head": Vector2(64, 0), "face": Vector2(64, 64), "back": Vector2(128, 64), "body": Vector2(64, 128),
	"hands": Vector2(128, 128), "left": Vector2(0, 192), "right": Vector2(128, 192), "legs": Vector2(64, 192), "feet": Vector2(64, 256)}
const HANDS2 := Vector2(0, 128)
const HOLD_TIME := 0.4                  # Shift + держать ПКМ столько — выбросить всю стопку
const TOUCH_HOLD := 0.5                 # палец: столько держать на ячейке — меню действий

var slots: Array = []            # null или {"id": String, "n": int}
var coins := 0
var equip := {"head": "", "face": "", "back": "", "body": "", "hands": "", "legs": "", "feet": "", "left": "", "right": ""}
var hotbar: Array = ["", "", "", "", ""]
var equip_dur := {}             # прочность надетого: слот -> значение
var open := false
var enabled := true
var hover = null                 # int — ячейка сумки, String — слот экипировки
var root: Control
var info_name: Label
var info_desc: Label
var tip: PanelContainer          # всплывающая подсказка (название + описание) у курсора
var slot_nodes: Array = []
var grids: Array = []            # BagGrid на каждый блок BLOCKS
var block_ls: Array = []         # подписи блоков
var drag_rot := false            # тащим предмет повёрнутым (пробел)
var drag_off := Vector2i.ZERO    # за какую ячейку предмета взяли
var drag_key = null
var drag_pv: Control = null
var drop_rot := false            # поворот для unequip в ячейку (game.unequip читает)
var bag_l: Label
var craft_box: VBoxContainer
var craft_tab: Button
var craft_wrap: Control
var craft_panel: PanelContainer
var craft_shown := false
var craft_tw: Tween
var craft_open := -1            # раскрытый рецепт в списке крафта (-1 — все свёрнуты)
var _press_key = null
var _press_pos := Vector2.ZERO
const CLICK_SLOP := 6.0          # ЛКМ: сдвиг меньше — клик (надеть/снять), больше — перетаскивание
var game  # game.gd — чтобы не открываться поверх магазина
var hold_key = null              # что выбрасываем удержанием ПКМ: номер ячейки или "coin"
var hold_t := 0.0
var touch_key = null             # палец держит эту ячейку (долгое нажатие = выбросить)
var touch_t := 0.0
var touch_sel = null             # последняя ячейка, которой коснулись (для привязки к хотбару без наведения)
var wallet_l: Label
var dlg: PanelContainer           # окно «сколько выбросить»
var dlg_title: Label
var dlg_slider: HSlider
var dlg_val: Label
var dlg_key = null
var menu_bg: Control              # меню действий (ПКМ): прозрачная подложка — клик мимо закрывает
var menu: PanelContainer
var menu_box: VBoxContainer
var menu_key = null
var touch_pos := Vector2.ZERO
var hot_nodes: Array = []         # ячейки хотбара поверх hud.gd, пока открыт инвентарь


## Ячейка: key — номер в сумке (int) или имя слота экипировки (String).
class Slot extends Control:
	const Items := preload("res://scripts/items.gd")
	var inv
	var key
	var px := 76.0
	var mirror := false   # иконка части тела отзеркалена (левая колонка куклы)

	func _ready() -> void:
		custom_minimum_size = Vector2(px, px)
		size = Vector2(px, px)
		mouse_entered.connect(func(): inv.set_hover(key))
		mouse_exited.connect(func(): inv.set_hover(null))

	func item_id() -> String:
		if key is String:
			return inv.equip[key]
		var s = inv.slots[key]
		return "" if s == null else String(s["id"])

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var hovered: bool = typeof(inv.hover) == typeof(key) and inv.hover == key
		var is_eq: bool = key is String
		var extra: bool = not is_eq and int(key) >= inv.BAG   # ячейка рюкзака
		draw_rect(r, Color(0.09, 0.06, 0.03, 0.75) if is_eq else (Color(0.12, 0.09, 0.04, 0.6) if extra else Color(0.0, 0.0, 0.0, 0.5)))
		draw_rect(r, Color(0.9, 0.7, 0.4, 0.6 if hovered else 0.25) if is_eq else Color(1, 1, 1, 0.45 if hovered else 0.12), false, 1.0)
		var f := ThemeDB.fallback_font
		var id := item_id()
		if id == "":
			if is_eq:
				_draw_part(String(key))
			return
		if is_eq and key == "hands":
			# надетые перчатки — пальцами вниз, в левой колонке зеркально (промпт 04:44)
			var ir := r.grow(-12)
			var c := ir.get_center()
			draw_set_transform(c, PI, Vector2(1.0 if not mirror else -1.0, 1.0))   # зеркало в другую сторону (промпт 04:51)
			Items.draw_icon(self, id, Rect2(-ir.size / 2.0, ir.size))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			Items.draw_icon(self, id, r.grow(-12))
		# полоска прочности
		var mx := Items.max_dur(id)
		if mx > 0.0:
			var fr := clampf(float(inv.get_dur(key)) / mx, 0.0, 1.0)
			if id == "pistol":
				fr = float(Gun.mag_rounds(inv.get_dur(key))) / Gun.CAP
			draw_rect(Rect2(6, size.y - 9, size.x - 12, 4), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(6, size.y - 9, (size.x - 12) * fr, 4), Color(0.85, 0.25, 0.15).lerp(Color(0.45, 0.85, 0.35), fr))
		if Items.ITEMS[id].has("rounds"):
			# пистолет / магазин: патронов внутри
			var rt := "%d/%d" % [int(round(inv.get_dur(key))), int(mx)]
			if id == "pistol":
				var pd: float = inv.get_dur(key)
				rt = "%d/%d" % [Gun.mag_rounds(pd), Gun.CAP] if Gun.has_mag(pd) else "без маг."
			draw_string_outline(f, Vector2(4, size.y - 12), rt, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 9, 15, 4, Color(0, 0, 0, 0.8))
			draw_string(f, Vector2(4, size.y - 12), rt, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 9, 15, Color(0.95, 0.85, 0.55))
		elif Items.ITEMS[id].has("repair"):
			# ремкомплект: сколько зарядов осталось
			var ch := "×%d" % int(ceil(inv.get_dur(key)))
			draw_string_outline(f, Vector2(4, size.y - 12), ch, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 9, 16, 4, Color(0, 0, 0, 0.8))
			draw_string(f, Vector2(4, size.y - 12), ch, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 9, 16, Color(0.95, 0.85, 0.55))
		elif not is_eq:
			var n: int = inv.slots[key]["n"]
			if n > 1:
				draw_string_outline(f, Vector2(4, size.y - 6), str(n), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 9, 17, 4, Color(0, 0, 0, 0.8))
				draw_string(f, Vector2(4, size.y - 6), str(n), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 9, 17, Color(0.92, 0.9, 0.84))
		# Shift + держать ПКМ: кольцо заполняется — на полном выбросится вся стопка
		if typeof(inv.hold_key) == typeof(key) and inv.hold_key == key:
			var fr2 := clampf(inv.hold_t / inv.HOLD_TIME, 0.0, 1.0)
			draw_rect(r, Color(0.6, 0.1, 0.05, 0.25 * fr2))
			draw_arc(size / 2, size.x * 0.4, -PI / 2, -PI / 2 + TAU * fr2, 32, Color(1.0, 0.45, 0.3, 0.95), 4.0, true)
		var hk: int = inv.hotbar.find(id)
		if hk >= 0:
			draw_string_outline(f, Vector2(5, 17), str(hk + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(0, 0, 0, 0.8))
			draw_string(f, Vector2(5, 17), str(hk + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.0, 0.8, 0.4))

	## Иконка части тела в пустом слоте снаряжения (промпт 04:33): простой силуэт с толстым светлым контуром,
	## рисуется в рамке 64×64; mirror — левая колонка (кулак / кисть отзеркалены). Пальцы и костяшки — вниз.
	## Фигура — список примитивов: ["c", центр, r], ["r", Rect2], ["l", [точки], ширина], ["p", [точки]];
	## сначала все с запасом OUT (контур), потом заливка — без наложений полупрозрачного.
	const OUT := 3.0
	const C_OUT := Color(1, 1, 1, 0.16)    # тусклее, без «свечения» (промпт 04:41)
	const C_FILL := Color(0.13, 0.12, 0.11, 0.9)
	const C_CUT := Color(1, 1, 1, 0.16)

	func _shape(ops: Array, grow: float, col: Color) -> void:
		for o in ops:
			match String(o[0]):
				"c":
					draw_circle(o[1], float(o[2]) + grow, col)
				"r":
					draw_rect((o[1] as Rect2).grow(grow), col)
				"l":
					var pts: Array = o[1]
					var w: float = float(o[2]) + grow * 2.0
					for i in pts.size():
						draw_circle(pts[i], w / 2.0, col)
						if i > 0:
							draw_line(pts[i - 1], pts[i], col, w)
				"p":
					var pp := PackedVector2Array(o[1])
					if grow > 0.0:
						if Geometry2D.is_polygon_clockwise(pp):
							pp.reverse()   # обход в одну сторону — иначе offset сжимает, а не расширяет
						var g := Geometry2D.offset_polygon(pp, grow, Geometry2D.JOIN_ROUND)
						if not g.is_empty():
							pp = g[0]
					draw_colored_polygon(pp, col)

	func _draw_part(k: String) -> void:
		var u := size.x / 64.0
		# кулаки и кисти отзеркалены в другую сторону (промпт 04:51): правая колонка — зеркально, левая — как нарисовано
		var mir: bool = mirror != (k in ["hands", "left", "right"])
		if mir:
			draw_set_transform(Vector2(size.x, 0), 0.0, Vector2(-u, u))
		else:
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(u, u))
		var ops: Array = []
		var cuts: Array = []   # светлые линии поверх заливки: [точки, ширина]
		match k:
			"head":   # голова, шея, плечи
				ops = [["c", Vector2(32, 22), 14.0], ["r", Rect2(26, 32, 12, 14)],
					["p", [Vector2(8, 60), Vector2(14, 48), Vector2(24, 44), Vector2(40, 44), Vector2(50, 48), Vector2(56, 60)]]]
			"face":   # овал лица; глаза, нос, рот
				var ov: Array = []
				for i in 24:
					var t := TAU * i / 24.0
					ov.append(Vector2(32 + 17 * cos(t), 32 + 22 * sin(t)))
				ops = [["p", ov]]
				cuts = [[[Vector2(23, 27), Vector2(27, 27)], 4.0], [[Vector2(37, 27), Vector2(41, 27)], 4.0],
					[[Vector2(32, 30), Vector2(30, 38), Vector2(33, 38)], 2.5], [[Vector2(25, 45), Vector2(32, 47), Vector2(39, 45)], 3.0]]
			"back":   # рюкзак: ручка, корпус, клапан, карман, лямки по бокам
				ops = [["l", [Vector2(26, 14), Vector2(27, 6), Vector2(37, 6), Vector2(38, 14)], 4.0],
					["l", [Vector2(15, 20), Vector2(9, 50)], 5.0], ["l", [Vector2(49, 20), Vector2(55, 50)], 5.0],
					["p", [Vector2(20, 12), Vector2(44, 12), Vector2(50, 20), Vector2(50, 58), Vector2(14, 58), Vector2(14, 20)]]]
				cuts = [[[Vector2(14, 28), Vector2(32, 33), Vector2(50, 28)], 3.0], [[Vector2(32, 33), Vector2(32, 37)], 3.0],
					[[Vector2(21, 41), Vector2(43, 41), Vector2(43, 53), Vector2(21, 53), Vector2(21, 41)], 2.5]]
			"body":   # торс
				ops = [["p", [Vector2(10, 12), Vector2(54, 12), Vector2(60, 26), Vector2(48, 30), Vector2(46, 58), Vector2(18, 58),
					Vector2(16, 30), Vector2(4, 26)]]]
				cuts = [[[Vector2(26, 12), Vector2(32, 20), Vector2(38, 12)], 3.0]]
			"hands":  # кисть ладонью к нам, узкая (промпт 04:57): запястье сверху, пальцы вниз, большой палец к центру
				ops = [["r", Rect2(27, 2, 12, 12)], ["p", [Vector2(21, 12), Vector2(43, 12), Vector2(44, 35), Vector2(20, 35)]],
					["l", [Vector2(23, 34), Vector2(23, 50)], 5.0], ["l", [Vector2(29, 34), Vector2(29, 56)], 5.0],
					["l", [Vector2(35, 34), Vector2(35, 55)], 5.0], ["l", [Vector2(41, 34), Vector2(41, 48)], 4.5],
					["l", [Vector2(21, 17), Vector2(14, 31)], 5.0]]
			"left", "right":   # сжатый кулак (промпт 04:57): узкий, угловатый; запястье сверху, костяшки внизу,
				# 4 выступа костяшек, подогнутые пальцы, большой палец поперёк
				ops = [["r", Rect2(27, 2, 12, 12)],
					["p", [Vector2(20, 12), Vector2(44, 12), Vector2(46, 22), Vector2(46, 46), Vector2(18, 46), Vector2(18, 22)]],
					["p", [Vector2(18, 44), Vector2(25, 44), Vector2(24, 53), Vector2(19, 52)]],
					["p", [Vector2(25, 44), Vector2(32, 44), Vector2(31, 55), Vector2(26, 54)]],
					["p", [Vector2(32, 44), Vector2(39, 44), Vector2(38, 55), Vector2(33, 54)]],
					["p", [Vector2(39, 44), Vector2(46, 44), Vector2(45, 52), Vector2(40, 53)]]]
				cuts = [[[Vector2(25, 34), Vector2(25, 50)], 2.0], [[Vector2(32, 34), Vector2(32, 52)], 2.0], [[Vector2(39, 34), Vector2(39, 50)], 2.0],
					[[Vector2(18, 34), Vector2(46, 34)], 2.0],
					[[Vector2(18, 24), Vector2(36, 27), Vector2(38, 31), Vector2(18, 31)], 2.5]]
			"legs":   # таз и две ноги
				ops = [["r", Rect2(16, 6, 32, 12)], ["p", [Vector2(16, 16), Vector2(31, 16), Vector2(29, 60), Vector2(19, 60)]],
					["p", [Vector2(33, 16), Vector2(48, 16), Vector2(45, 60), Vector2(35, 60)]]]
			"feet":   # пара ботинок сбоку, носками в разные стороны
				for sx in [1.0, -1.0]:
					var bx := func(x: float) -> float: return 32.0 + sx * (x - 32.0)
					ops.append(["r", Rect2(minf(bx.call(35.0), bx.call(45.0)), 14, 10, 26)])
					ops.append(["p", [Vector2(bx.call(34), 38), Vector2(bx.call(46), 38), Vector2(bx.call(58), 44),
						Vector2(bx.call(60), 54), Vector2(bx.call(34), 54)]])
		_shape(ops, OUT, C_OUT)
		_shape(ops, 0.0, C_FILL)
		for c in cuts:
			var pts: Array = c[0]
			for i in range(1, pts.size()):
				draw_line(pts[i - 1], pts[i], C_CUT, float(c[1]))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _gui_input(e: InputEvent) -> void:
		# палец (мышь, эмулированная из касаний): долгое нажатие — как ПКМ, выбросить
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.device == InputEvent.DEVICE_ID_EMULATION:
			if e.pressed:
				inv.touch_sel = key
				inv.set_hover(key)
				if item_id() != "":
					inv.touch_key = key
					inv.touch_t = 0.0
					inv.touch_pos = get_global_mouse_position()
			else:
				inv.touch_key = null
		# ПКМ — меню действий; Shift+ПКМ — выбросить 1, Shift + держать — всю стопку
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT and item_id() != "":
			if e.shift_pressed:
				if key is String:
					inv.drop_equipped_requested.emit(key)
				else:
					inv.start_hold(key, int(inv.slots[key]["n"]))
			else:
				inv.open_menu(key, get_global_mouse_position())
			accept_event()

	func _get_drag_data(_at: Vector2) -> Variant:
		if item_id() == "":
			return null
		set_drag_preview(inv.begin_drag(key, Vector2i.ZERO))
		return {"inv_key": key, "off": Vector2i.ZERO}

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and (data.has("inv_key") or data.has("hot"))

	func _drop_data(_at: Vector2, data: Variant) -> void:
		if data.has("hot"):
			inv.unbind_hot(int(data["hot"]))
			return
		inv.move(data["inv_key"], key)


## Блок сетки сумки (промпт 16.11 02:42): ячейки без зазоров, предметы w×h рисуются целиком.
class BagGrid extends Control:
	const Items := preload("res://scripts/items.gd")
	const Gun := preload("res://scripts/gun.gd")
	var inv
	var b := 0
	var hint: Array = []          # ячейки, куда ляжет тащимый предмет
	var hint_ok := true

	func _ready() -> void:
		mouse_exited.connect(func():
			hint = []
			queue_redraw())

	func refit() -> void:
		var d: Vector2i = inv.block_dim(b)
		custom_minimum_size = Vector2(d) * inv.CELL
		size = custom_minimum_size
		queue_redraw()

	## Ячейка под точкой p (локально); -1 — мимо.
	func cell_at(p: Vector2) -> int:
		var d: Vector2i = inv.block_dim(b)
		if p.x < 0 or p.y < 0:
			return -1
		var x := int(p.x / inv.CELL)
		var y := int(p.y / inv.CELL)
		if x >= d.x or y >= d.y:
			return -1
		return inv.cell_idx(b, x, y)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_DRAG_END:
			hint = []
			queue_redraw()

	func _draw() -> void:
		var d: Vector2i = inv.block_dim(b)
		var c: float = inv.CELL
		draw_rect(Rect2(Vector2.ZERO, Vector2(d) * c), Color(0.12, 0.09, 0.04, 0.6) if b > 0 else Color(0, 0, 0, 0.5))
		for x in d.x + 1:
			draw_line(Vector2(x * c, 0), Vector2(x * c, d.y * c), Color(1, 1, 1, 0.1), 1.0)
		for y in d.y + 1:
			draw_line(Vector2(0, y * c), Vector2(d.x * c, y * c), Color(1, 1, 1, 0.1), 1.0)
		var f := ThemeDB.fallback_font
		for i in inv.TOTAL:
			var s = inv.slots[i]
			if s == null or inv.cell_block(i) != b:
				continue
			var p: Vector2i = inv.cell_xy(i)
			var r := Rect2(Vector2(p) * c, Vector2(inv.item_dim(s)) * c)
			var id: String = s["id"]
			var hovered: bool = inv.hover is int and inv.hover == i
			draw_rect(r.grow(-1), Color(0.2, 0.17, 0.12, 0.55 if hovered else 0.35))
			draw_rect(r.grow(-1), Color(1, 1, 1, 0.5 if hovered else 0.2), false, 1.0)
			var side := minf(r.size.x, r.size.y) - 14.0
			Items.draw_icon(self, id, Rect2(r.get_center() - Vector2(side, side) / 2, Vector2(side, side)))
			var mx := Items.max_dur(id)
			if mx > 0.0:
				var fr := clampf(float(inv.get_dur(i)) / mx, 0.0, 1.0)
				if id == "pistol":
					fr = float(Gun.mag_rounds(inv.get_dur(i))) / Gun.CAP
				draw_rect(Rect2(r.position.x + 5, r.end.y - 8, r.size.x - 10, 4), Color(0, 0, 0, 0.6))
				draw_rect(Rect2(r.position.x + 5, r.end.y - 8, (r.size.x - 10) * fr, 4), Color(0.85, 0.25, 0.15).lerp(Color(0.45, 0.85, 0.35), fr))
			var txt := ""
			if Items.ITEMS[id].has("rounds"):
				txt = "%d/%d" % [int(round(inv.get_dur(i))), int(mx)]
				if id == "pistol":
					var pd: float = inv.get_dur(i)
					txt = "%d/%d" % [Gun.mag_rounds(pd), Gun.CAP] if Gun.has_mag(pd) else "без маг."
			elif Items.ITEMS[id].has("repair"):
				txt = "×%d" % int(ceil(inv.get_dur(i)))
			elif int(s["n"]) > 1:
				txt = str(int(s["n"]))
			if txt != "":
				var tp := Vector2(r.position.x + 3, r.end.y - 10)
				draw_string_outline(f, tp, txt, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 8, 15, 4, Color(0, 0, 0, 0.8))
				draw_string(f, tp, txt, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 8, 15, Color(0.95, 0.88, 0.6))
			if inv.hold_key is int and inv.hold_key == i:
				var fr2 := clampf(inv.hold_t / inv.HOLD_TIME, 0.0, 1.0)
				draw_rect(r, Color(0.6, 0.1, 0.05, 0.25 * fr2))
				draw_arc(r.get_center(), minf(r.size.x, r.size.y) * 0.4, -PI / 2, -PI / 2 + TAU * fr2, 32, Color(1.0, 0.45, 0.3, 0.95), 4.0, true)
			var hk: int = inv.hotbar.find(id)
			if hk >= 0:
				draw_string_outline(f, r.position + Vector2(4, 15), str(hk + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.8))
				draw_string(f, r.position + Vector2(4, 15), str(hk + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.8, 0.4))
		for h in hint:
			var hp: Vector2i = inv.cell_xy(h)
			draw_rect(Rect2(Vector2(hp) * c, Vector2(c, c)).grow(-2), Color(0.4, 0.9, 0.4, 0.3) if hint_ok else Color(0.95, 0.3, 0.2, 0.35))

	func _gui_input(e: InputEvent) -> void:
		var o: int = inv.owner_at(cell_at(get_local_mouse_position()))
		var key = o if o >= 0 else null
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.device == InputEvent.DEVICE_ID_EMULATION:
			if e.pressed:
				inv.touch_sel = key
				inv.set_hover(key)
				if key != null:
					inv.touch_key = key
					inv.touch_t = 0.0
					inv.touch_pos = get_global_mouse_position()
			else:
				inv.touch_key = null
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT and key != null:
			if e.shift_pressed:
				inv.start_hold(key, int(inv.slots[key]["n"]))
			else:
				inv.open_menu(key, get_global_mouse_position())
			accept_event()

	func _get_drag_data(at: Vector2) -> Variant:
		var cell := cell_at(at)
		var o: int = inv.owner_at(cell)
		if o < 0:
			return null
		var off: Vector2i = inv.cell_xy(cell) - inv.cell_xy(o)
		set_drag_preview(inv.begin_drag(o, off))
		return {"inv_key": o, "off": off}

	func _can_drop_data(at: Vector2, data: Variant) -> bool:
		if not (data is Dictionary and (data.has("inv_key") or data.has("hot"))):
			return false
		hint = []
		if data.has("inv_key"):
			var cell := cell_at(at)
			if cell >= 0:
				var res: Array = inv.drop_preview(data["inv_key"], cell)
				hint = res[0]
				hint_ok = res[1]
		queue_redraw()
		return true

	func _drop_data(at: Vector2, data: Variant) -> void:
		hint = []
		queue_redraw()
		if data.has("hot"):
			inv.unbind_hot(int(data["hot"]))
			return
		var cell := cell_at(at)
		if cell >= 0:
			inv.drop_to_cell(data["inv_key"], cell)


## Превью перетаскивания: предмет в натуральную величину (поворачивается пробелом).
class DragIcon extends Control:
	const Items := preload("res://scripts/items.gd")
	var id := ""

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.2, 0.17, 0.12, 0.45))
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.8, 0.45, 0.6), false, 1.5)
		var side := minf(size.x, size.y) - 12.0
		Items.draw_icon(self, id, Rect2(size / 2 - Vector2(side, side) / 2, Vector2(side, side)))


## Ячейка хотбара 1–5 поверх нарисованной hud.gd (только пока открыт инвентарь): цель перетаскивания.
class HotSlot extends Control:
	const Items := preload("res://scripts/items.gd")
	var inv
	var k := 0
	var dragging := false
	var over := false

	func _ready() -> void:
		mouse_entered.connect(_set_over.bind(true))
		mouse_exited.connect(_set_over.bind(false))

	func _set_over(v: bool) -> void:
		over = v
		queue_redraw()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_DRAG_BEGIN:
			dragging = true
			queue_redraw()
		elif what == NOTIFICATION_DRAG_END:
			dragging = false
			queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var id: String = inv.hotbar[k]
		draw_rect(r, Color(0.05, 0.04, 0.03, 0.85))
		if id != "":
			Items.draw_icon(self, id, r.grow(-11))
			var cnt: int = inv.count(id)
			if cnt == 0:
				draw_rect(r.grow(-1), Color(0, 0, 0, 0.6))
			elif cnt > 1:
				var f0 := ThemeDB.fallback_font
				draw_string_outline(f0, Vector2(0, size.y - 5), str(cnt), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 5, 16, 4, Color(0, 0, 0, 0.8))
				draw_string(f0, Vector2(0, size.y - 5), str(cnt), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 5, 16, Color(0.92, 0.9, 0.84))
		var f := ThemeDB.fallback_font
		draw_string_outline(f, Vector2(5, 17), str(k + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color(0, 0, 0, 0.8))
		draw_string(f, Vector2(5, 17), str(k + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.8, 0.45))
		# пока тащишь предмет — ячейки подсвечены как цели
		var a := 0.95 if (dragging and over) else (0.7 if dragging else 0.25)
		draw_rect(r, Color(1.0, 0.75, 0.35, a), false, 3.0 if dragging else 1.0)
		if dragging:
			draw_rect(r, Color(1.0, 0.75, 0.35, 0.18 if over else 0.08))

	func _get_drag_data(_at: Vector2) -> Variant:
		var id: String = inv.hotbar[k]
		if id == "":
			return null
		var pv := Icon.new()
		pv.id = id
		pv.size = Vector2(56, 56)
		pv.position = Vector2(-28, -28)
		var holder := Control.new()
		holder.add_child(pv)
		set_drag_preview(holder)
		return {"hot": k}

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and (data.has("inv_key") or data.has("hot"))

	func _drop_data(_at: Vector2, data: Variant) -> void:
		if data.has("hot"):
			inv.swap_hot(int(data["hot"]), k)
		else:
			inv.bind_hot(data["inv_key"], k)


## Подложка под слотами снаряжения (фигуры больше нет, промпт 04:23).
class Doll extends Control:
	pass


## Картинка предмета (превью перетаскивания, крафт).
class Icon extends Control:
	const Items := preload("res://scripts/items.gd")
	var id := ""
	var dim := false

	func _draw() -> void:
		Items.draw_icon(self, id, Rect2(Vector2.ZERO, size))
		if dim:
			draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))


## Фон вокруг окна: бросить сюда предмет — выбросить его на пол.
class DropZone extends ColorRect:
	var inv

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and (data.has("inv_key") or data.has("hot"))

	func _drop_data(_at: Vector2, data: Variant) -> void:
		if data.has("hot"):
			inv.unbind_hot(int(data["hot"]))
			return
		var k = data["inv_key"]
		if k is String:
			inv.drop_equipped_requested.emit(k)
		elif inv.slots[k] != null and int(inv.slots[k]["n"]) > 1:
			inv.open_drop_dialog(k)     # стопка — «Сколько выбросить?»
		else:
			inv.drop_requested.emit(k, true)

	# клик мимо окна (по затемнению) — закрыть; событие съедено, в игру не уходит (промпт 02:15)
	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			accept_event()
			if inv.dlg.visible:
				inv.dlg.visible = false
			else:
				inv.close()


func _ready() -> void:
	layer = 2
	process_mode = Node.PROCESS_MODE_ALWAYS
	slots.resize(TOTAL)
	for k in 5:
		_add_key("hot_%d" % (k + 1), KEY_1 + k)
	_build_ui()
	root.visible = false


func _add_key(action: String, key: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)


func _build_ui() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var shade := DropZone.new()
	shade.inv = self
	shade.color = Color(0, 0, 0, 0.35)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_bottom = -92   # окно — над хотбаром (ячейки 1–5 внизу остаются видны для перетаскивания)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var panel := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.07, 0.065, 0.06, 0.93)
	st.border_color = Color(1, 1, 1, 0.14)
	st.set_border_width_all(1)
	st.set_corner_radius_all(3)
	st.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", st)
	center.add_child(panel)
	preload("res://scripts/ui/ui_fit.gd").attach(panel)   # окно в рамках экрана (промпт 00:32)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 28)
	panel.add_child(hb)

	# снаряжение на силуэте
	var dc := VBoxContainer.new()
	dc.add_theme_constant_override("separation", 10)
	hb.add_child(dc)
	# надпись «СНАРЯЖЕНИЕ» убрана (промпт 03:47)
	var doll := Doll.new()
	doll.custom_minimum_size = Vector2(192, 320)
	dc.add_child(doll)
	for k in EQUIP + ["hands"]:
		var s := Slot.new()
		s.inv = self
		s.key = k
		s.px = 64.0
		s.position = HANDS2 if k == "hands" and slot_nodes.size() >= EQUIP.size() else DOLL_POS[k]
		s.mirror = s.position.x < 1.0 and k in ["hands", "left"]
		doll.add_child(s)
		slot_nodes.append(s)

	# слева — экипировка: силуэт, под ним рюкзак и карманы одежды (видны, только когда надето); справа — сумка 5×4
	# (промпт 16.11 03:44)
	var gear := HBoxContainer.new()
	gear.add_theme_constant_override("separation", 12)
	dc.add_child(gear)
	var extra := VBoxContainer.new()
	extra.add_theme_constant_override("separation", 4)
	gear.add_child(extra)
	var pockets := VBoxContainer.new()
	pockets.add_theme_constant_override("separation", 8)
	gear.add_child(pockets)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	hb.add_child(vb)
	# заголовок: «ИНВЕНТАРЬ» и рядом кнопка «Крафт» (промпт 04:07) — выкатывает панель крафта, повторно прячет
	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 18)
	vb.add_child(title)
	title.add_child(_label("ИНВЕНТАРЬ", 34, Color(0.86, 0.85, 0.8)))
	craft_tab = Button.new()
	craft_tab.text = "Крафт ▸"
	craft_tab.focus_mode = Control.FOCUS_NONE
	craft_tab.add_theme_font_size_override("font_size", 22)
	craft_tab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	craft_tab.pressed.connect(toggle_craft)
	title.add_child(craft_tab)
	var mainc := VBoxContainer.new()
	mainc.add_theme_constant_override("separation", 4)
	vb.add_child(mainc)
	for bi in BLOCKS.size():
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 3)
		var bl := _label(BLOCKS[bi][4], 14, Color(0.6, 0.6, 0.56))
		col.add_child(bl)
		block_ls.append(bl)
		var g := BagGrid.new()
		g.inv = self
		g.b = bi
		g.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		g.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		col.add_child(g)
		grids.append(g)
		if bi == 0:
			mainc.add_child(col)
		elif bi == 1:
			extra.add_child(col)
		else:
			pockets.add_child(col)
	bag_l = block_ls[0]
	update_blocks()
	var wallet := HBoxContainer.new()
	wallet.add_theme_constant_override("separation", 10)
	var wi := Icon.new()
	wi.id = "coin"
	wi.custom_minimum_size = Vector2(30, 30)
	wallet.add_child(wi)
	wallet_l = _label("", 20, Color(0.92, 0.8, 0.5))
	wallet_l.custom_minimum_size = Vector2(170, 0)
	wallet.add_child(wallet_l)
	var wb := Button.new()
	wb.text = "Выбросить монеты"
	wb.focus_mode = Control.FOCUS_NONE
	wb.add_theme_font_size_override("font_size", 16)
	wb.pressed.connect(open_drop_dialog.bind("coin"))
	wallet.add_child(wb)
	vb.add_child(wallet)
	# название и описание — во всплывающей подсказке у курсора (промпт 04:41), постоянной панели нет
	tip = PanelContainer.new()
	var tst := StyleBoxFlat.new()
	tst.bg_color = Color(0.05, 0.05, 0.05, 0.94)
	tst.border_color = Color(1, 1, 1, 0.18)
	tst.set_border_width_all(1)
	tst.set_corner_radius_all(3)
	tst.set_content_margin_all(8)
	tip.add_theme_stylebox_override("panel", tst)
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.visible = false
	var tvb := VBoxContainer.new()
	tvb.add_theme_constant_override("separation", 4)
	tvb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.add_child(tvb)
	info_name = _label(" ", 19, Color(0.9, 0.82, 0.62))
	info_name.custom_minimum_size = Vector2(300, 0)
	info_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tvb.add_child(info_name)
	info_desc = _label(" ", 15, Color(0.72, 0.71, 0.67))
	info_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_desc.custom_minimum_size = Vector2(300, 0)
	tvb.add_child(info_desc)
	# подсказки короче (промпт 03:46): без «ЛКМ — перетащить», «Tab — закрыть», «за окно — выбросить»
	var hint_text := "F (навести) — использовать
ПКМ — действия
Shift+ПКМ — выбросить 1 (держать — всю стопку)
Быстр. действие 1–5"
	if preload("res://scripts/ui/touch_controls.gd").wanted():
		hint_text = "Нажать — использовать
Подержать — действия
Перетащить — переложить
Быстр. действие 1–5"
	var hint := _label(hint_text, 14, Color(0.55, 0.55, 0.52))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # сумка узкая (5 клеток) — подсказка переносится
	hint.custom_minimum_size.x = COLS * CELL
	vb.add_child(hint)

	# обёртка обрезает панель: её ширина плавно растёт от 0 (выкатывание)
	craft_wrap = Control.new()
	craft_wrap.clip_contents = true
	craft_wrap.custom_minimum_size = Vector2(0, 0)
	craft_wrap.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	craft_wrap.visible = false
	hb.add_child(craft_wrap)
	# крафт — отдельная панель с рамкой и своим фоном (промпт 03:44)
	var cpanel := PanelContainer.new()
	craft_panel = cpanel
	var cst := StyleBoxFlat.new()
	cst.bg_color = Color(0.04, 0.04, 0.04, 0.6)   # без жёлтого фона (промпт 04:16)
	cst.border_color = Color(1, 1, 1, 0.18)
	cst.set_border_width_all(2)
	cst.set_corner_radius_all(4)
	cst.set_content_margin_all(12)
	cpanel.add_theme_stylebox_override("panel", cst)
	craft_wrap.add_child(cpanel)
	var cb := VBoxContainer.new()
	cb.add_theme_constant_override("separation", 10)
	cb.custom_minimum_size = Vector2(250, 0)
	cpanel.add_child(cb)
	# заголовка «КРАФТ» внутри нет (промпт 04:16) — есть кнопка рядом с «ИНВЕНТАРЬ»
	# рецептов много — список названий прокручивается, рецепт раскрывается по нажатию
	var cscroll := ScrollContainer.new()
	cscroll.custom_minimum_size = Vector2(290, 440)
	cscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER   # длинные подписи не расширяют окно
	cb.add_child(cscroll)
	craft_box = VBoxContainer.new()
	craft_box.add_theme_constant_override("separation", 4)
	craft_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cscroll.add_child(craft_box)
	for k in 5:
		var hs := HotSlot.new()
		hs.inv = self
		hs.k = k
		root.add_child(hs)
		hot_nodes.append(hs)
	root.add_child(tip)   # поверх окна
	_build_drop_dialog()
	_build_menu()


## Окно «сколько выбросить»: ползунок и кнопка.
func _build_drop_dialog() -> void:
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cc)
	dlg = PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.1, 0.085, 0.07, 0.98)
	st.border_color = Color(0.9, 0.7, 0.4, 0.6)
	st.set_border_width_all(2)
	st.set_corner_radius_all(4)
	st.set_content_margin_all(18)
	dlg.add_theme_stylebox_override("panel", st)
	cc.add_child(dlg)
	preload("res://scripts/ui/ui_fit.gd").attach(dlg)   # окно в рамках экрана (промпт 00:32)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	dlg.add_child(v)
	dlg_title = _label("", 22, Color(0.92, 0.88, 0.75))
	dlg_title.clip_text = true
	dlg_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	dlg_title.custom_minimum_size = Vector2(400, 0)
	v.add_child(dlg_title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	dlg_slider = HSlider.new()
	dlg_slider.custom_minimum_size = Vector2(260, 30)
	dlg_slider.min_value = 1
	dlg_slider.step = 1
	dlg_slider.focus_mode = Control.FOCUS_NONE
	row.add_child(dlg_slider)
	dlg_val = _label("1", 22, Color(1.0, 0.85, 0.5))
	dlg_val.custom_minimum_size = Vector2(50, 0)
	row.add_child(dlg_val)
	var pm := HBoxContainer.new()
	pm.add_theme_constant_override("separation", 8)
	v.add_child(pm)
	for d in [["−", -1], ["+", 1], ["Всё", 0]]:
		var b := Button.new()
		b.text = d[0]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(56, 34)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 18)
		var step: int = d[1]
		b.pressed.connect(func(): dlg_slider.value = dlg_slider.max_value if step == 0 else dlg_slider.value + step)
		pm.add_child(b)
	dlg_slider.value_changed.connect(func(x: float): dlg_val.text = str(int(x)))
	var bb := HBoxContainer.new()
	bb.add_theme_constant_override("separation", 10)
	v.add_child(bb)
	var ok := Button.new()
	ok.text = "ОК"
	ok.focus_mode = Control.FOCUS_NONE
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ok.add_theme_font_size_override("font_size", 18)
	ok.pressed.connect(_confirm_drop)
	bb.add_child(ok)
	var no := Button.new()
	no.text = "Отмена"
	no.focus_mode = Control.FOCUS_NONE
	no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	no.add_theme_font_size_override("font_size", 18)
	no.pressed.connect(func(): dlg.visible = false)
	bb.add_child(no)
	dlg.visible = false


## key — номер ячейки или "coin".
func open_drop_dialog(key) -> void:
	var mx := coins if key is String else (int(slots[key]["n"]) if slots[key] != null else 0)
	if mx <= 0:
		return
	dlg_key = key
	dlg_title.text = "Сколько выбросить? %s" % ("Монеты" if key is String else Items.item_name(slots[key]["id"]))
	dlg_slider.max_value = mx
	dlg_slider.value = mx
	dlg_val.text = str(mx)
	dlg.visible = true


func _confirm_drop() -> void:
	dlg.visible = false
	var n := int(dlg_slider.value)
	if dlg_key is String:
		drop_coins_requested.emit(n)
	elif slots[dlg_key] != null:
		drop_count_requested.emit(dlg_key, n)


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _rebuild_craft() -> void:
	for c in craft_box.get_children():
		c.queue_free()
	# список — только иконки (промпт 04:16); название и описание — во всплывающей подсказке у курсора,
	# рецепт выбранного — под сеткой
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	craft_box.add_child(grid)
	for r in Items.RECIPES.size():
		var rec: Dictionary = Items.RECIPES[r]
		var out: String = rec["out"]
		var ok := true
		var need: Dictionary = rec["need"]
		for id in need:
			ok = ok and count(id) >= int(need[id])
		var tid: String = rec.get("tool", "")
		var have_t := tid == ""
		if tid != "":
			for t in Items.tool_ids(tid):
				if count(t) > 0:
					have_t = true
					tid = t   # показываем тот, что есть (слесарный молоток)
					break
		ok = ok and have_t
		var opened := craft_open == r
		# кнопка-иконка; нажатие раскрывает / сворачивает рецепт
		var head := Button.new()
		head.focus_mode = Control.FOCUS_NONE
		head.flat = not opened
		head.custom_minimum_size = Vector2(52, 52)
		head.tooltip_text = "%s
%s" % [Items.item_name(out), String(Items.ITEMS[out].get("desc", ""))]
		head.pressed.connect(func():
			craft_open = -1 if craft_open == r else r
			_rebuild_craft())
		var ic := Icon.new()
		ic.id = out
		ic.dim = not ok
		ic.position = Vector2(4, 4)
		ic.size = Vector2(44, 44)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(ic)
		grid.add_child(head)
		if not opened:
			continue
		var det := VBoxContainer.new()
		det.add_theme_constant_override("separation", 6)
		craft_box.add_child(det)
		det.add_child(HSeparator.new())
		var dn := _label(Items.item_name(out), 18, Color(0.92, 0.88, 0.75))
		dn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		det.add_child(dn)
		for id in need:
			var have := count(id)
			var n: int = need[id]
			var nr := HBoxContainer.new()
			nr.add_theme_constant_override("separation", 6)
			var ni := Icon.new()
			ni.id = id
			ni.dim = have < n
			ni.custom_minimum_size = Vector2(30, 30)
			nr.add_child(ni)
			nr.add_child(_label("%s  %d/%d" % [Items.item_name(id), mini(have, n), n], 15, Color(0.7, 0.85, 0.6) if have >= n else Color(0.85, 0.5, 0.4)))
			det.add_child(nr)
		if tid != "":
			# инструмент не тратится, но теряет прочность
			var trow := HBoxContainer.new()
			trow.add_theme_constant_override("separation", 6)
			var ti := Icon.new()
			ti.id = tid
			ti.dim = not have_t
			ti.custom_minimum_size = Vector2(30, 30)
			trow.add_child(ti)
			trow.add_child(_label("%s (−%d прочности)" % [Items.item_name(tid), int(rec.get("wear", 1))], 15, Color(0.7, 0.85, 0.6) if have_t else Color(0.85, 0.5, 0.4)))
			det.add_child(trow)
		var b := Button.new()
		b.text = "Скрафтить"
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = not ok
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(func(): craft_requested.emit(r))
		det.add_child(b)


func _input(e: InputEvent) -> void:
	if not enabled:
		return
	if e.is_action_pressed("inventory"):
		if open:
			close()
		elif game and game.shop and game.shop.opened:
			return   # Tab в магазине закрывает магазин (shop.gd), инвентарь поверх не открываем
		elif not get_tree().paused:
			show_inventory()
		else:
			return
		get_viewport().set_input_as_handled()
	elif open and menu_bg.visible:
		# пока открыто меню действий — только Esc (клик мимо ловит подложка)
		if e.is_action_pressed("ui_cancel"):
			close_menu()
			get_viewport().set_input_as_handled()
	elif open and e.is_action_pressed("ui_cancel"):
		if dlg.visible:
			dlg.visible = false
		else:
			close()
		get_viewport().set_input_as_handled()
	elif open and not dlg.visible and e.is_action_pressed("interact") and not e.is_echo():
		close()   # E тоже закрывает инвентарь (промпт 04:41)
		get_viewport().set_input_as_handled()
	elif open and hold_key != null and e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
		_finish_hold()
	elif open and e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_SPACE:
		# пробел при перетаскивании — повернуть предмет (промпт 16.11 02:42)
		if get_viewport().gui_is_dragging() and drag_key != null:
			rotate_drag()
		get_viewport().set_input_as_handled()
	elif open:
		for k in 5:
			if e.is_action_pressed("hot_%d" % (k + 1)):
				_bind_hover(k)
				get_viewport().set_input_as_handled()
		# ячейку под курсором считаем по геометрии, а не по mouse_entered: после перетаскивания Godot
		# не шлёт mouse_entered, наведение «залипало» на старой ячейке и клики уходили не туда (промпт 22:53)
		if e is InputEventMouseMotion and not dlg.visible:
			var hk = _slot_at()
			if not _same(hk, hover):
				set_hover(hk)
		# F (inv_use, переназначается) на предмете под курсором — использовать / снять (промпт 02:19)
		if InputMap.has_action("inv_use") and e.is_action_pressed("inv_use") and not e.is_echo() and not dlg.visible:
			var uk = _slot_at()
			if uk == null:
				uk = hover
			if uk is int and slots[uk] != null:
				use_requested.emit(uk)
			elif uk is String and equip[uk] != "":
				unequip_requested.emit(uk, -1)
			get_viewport().set_input_as_handled()
		# касание пальцем (эмуляция мыши) — использовать; ЛКМ мышью: клик (без сдвига дальше порога) по одежде /
		# снаряжению — надеть в свой слот (занят — меняются), по надетому — снять в сумку (промпт 04:43);
		# со сдвигом — обычное перетаскивание
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not dlg.visible:
			var touch: bool = e.device == InputEvent.DEVICE_ID_EMULATION
			var at = _slot_at()
			if e.pressed:
				_press_key = at
				_press_pos = e.position
				if not _same(at, hover):
					set_hover(at)
			else:
				var pk = _press_key
				_press_key = null
				var still: bool = touch or e.position.distance_to(_press_pos) < CLICK_SLOP
				if at != null and _same(pk, at) and still and not get_viewport().gui_is_dragging():
					if at is int and slots[at] != null and (touch or Items.equip_slot(String(slots[at]["id"])) != ""):
						use_requested.emit(at)
					elif at is String and equip[at] != "":
						unequip_requested.emit(at, -1)


## Ячейка (номер или слот экипировки) под курсором; null — мимо.
func _slot_at():
	for n in slot_nodes:
		var c: Control = n
		if c.is_visible_in_tree() and Rect2(Vector2.ZERO, c.size).has_point(c.get_local_mouse_position()):
			return c.key
	for g in grids:
		var gc: Control = g
		if gc.is_visible_in_tree() and Rect2(Vector2.ZERO, gc.size).has_point(gc.get_local_mouse_position()):
			var o := owner_at(g.cell_at(gc.get_local_mouse_position()))
			return o if o >= 0 else null
	return null


# ---------- перетаскивание по сетке (промпт 16.11 02:42) ----------

## Начать тащить предмет key (ячейка-якорь или слот экипировки), взятый за ячейку off. Возвращает превью.
func begin_drag(key, off: Vector2i) -> Control:
	drag_key = key
	drag_off = off
	var id := ""
	if key is String:
		id = equip[key]
		drag_rot = false
	else:
		id = slots[key]["id"]
		drag_rot = bool(slots[key].get("r", false))
	var holder := Control.new()
	var pv := DragIcon.new()
	pv.id = id
	pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(pv)
	drag_pv = pv
	_fit_drag_pv()
	return holder


func _drag_dim() -> Vector2i:
	if drag_key == null:
		return Vector2i.ONE
	var id: String = equip[drag_key] if drag_key is String else (String(slots[drag_key]["id"]) if slots[drag_key] != null else "")
	var d := Items.size_of(id)
	return Vector2i(d.y, d.x) if drag_rot else d


func _fit_drag_pv() -> void:
	if drag_pv == null or not is_instance_valid(drag_pv):
		return
	drag_pv.size = Vector2(_drag_dim()) * CELL
	drag_pv.position = -(Vector2(drag_off) * CELL + Vector2(CELL, CELL) / 2)
	drag_pv.queue_redraw()


## Пробел: повернуть тащимый предмет (ячейка, за которую держим, остаётся под курсором).
func rotate_drag() -> void:
	drag_rot = not drag_rot
	drag_off = Vector2i(drag_off.y, drag_off.x)
	_fit_drag_pv()
	for g in grids:
		g.hint = []
		g.queue_redraw()


## Якорь, если отпустить тащимое над ячейкой cell (с учётом того, за что взяли).
func _drop_anchor(cell: int) -> int:
	var b := cell_block(cell)
	var p := cell_xy(cell) - drag_off
	p.x = maxi(p.x, 0)
	p.y = maxi(p.y, 0)
	return cell_idx(b, p.x, p.y)


## Подсветка при наведении тащимого: [ячейки, помещается ли].
func drop_preview(from, cell: int) -> Array:
	var d := _drag_dim()
	var at := _drop_anchor(cell)
	var cells := _cells(at, d)
	if cells.is_empty():
		return [[cell], false]
	var occ := occupancy()
	var t := occ[cell]
	if from is int and t >= 0 and t != from and _special_target(from, t):
		return [_cells(t, item_dim(slots[t])), true]
	var others: Array = []
	for c in cells:
		if occ[c] >= 0 and occ[c] != from and not (occ[c] in others):
			others.append(occ[c])
	return [cells, others.size() <= (1 if from is int else 0)]


## Отпустили тащимое над ячейкой cell.
func drop_to_cell(from, cell: int) -> void:
	var t := owner_at(cell)
	if from is int and t >= 0 and t != from and _special_target(from, t):
		move(from, t)   # починка, магазин в пистолет, патроны в магазин, слить стопки
		return
	var at := _drop_anchor(cell)
	if from is String:
		drop_rot = drag_rot
		unequip_requested.emit(from, at)
		drop_rot = false
		return
	_move_item(from, at, drag_rot)


## Предмет from, брошенный на t, делает что-то особое (а не просто перекладывается).
func _special_target(from: int, t: int) -> bool:
	var a = slots[from]
	var b = slots[t]
	if a == null or b == null:
		return false
	var fid: String = a["id"]
	var tid: String = b["id"]
	if Items.ITEMS[fid].has("repair") and Items.repairable(tid) != "":
		return true
	if (fid == "mag" and tid == "pistol") or (fid == "ammo" and tid == "mag"):
		return true
	return fid == tid and int(Items.ITEMS[fid]["stack"]) > 1 and int(b["n"]) < int(Items.ITEMS[fid]["stack"])


## Переложить предмет из якоря from в якорь at (rot — повёрнут). Один мешающий предмет меняется местами.
func _move_item(from: int, at: int, rot: bool) -> void:
	var s = slots[from]
	if s == null:
		return
	var d := Items.size_of(s["id"])
	if rot:
		d = Vector2i(d.y, d.x)
	var sn := snapshot()
	slots[from] = null
	var occ := occupancy()
	var cells := _cells(at, d)
	var others: Array = []
	for c in cells:
		if occ[c] >= 0 and not (occ[c] in others):
			others.append(occ[c])
	if cells.is_empty() or others.size() > 1:
		restore(sn)
		message.emit("Не помещается")
		return
	var displaced = null
	if others.size() == 1:
		displaced = slots[others[0]]
		slots[others[0]] = null
	_put(s, at, rot)
	if displaced != null:
		displaced["_at"] = from
		if not reflow([displaced]).is_empty():
			restore(sn)
			message.emit("Не помещается")
			return
	_after_change()


static func _same(a, b) -> bool:
	return typeof(a) == typeof(b) and a == b


## Shift+ПКМ: отпустил быстро — выбросить 1 шт.; продержал HOLD_TIME — всю стопку.
func start_hold(key, _mx: int) -> void:
	hold_key = key
	hold_t = 0.0


func _process(delta: float) -> void:
	if open:
		_place_tip()
	_touch_hold(delta)
	if hold_key == null:
		return
	hold_t += delta
	_refresh()   # кольцо удержания на ячейке
	if hold_t >= HOLD_TIME:
		var k = hold_key
		hold_key = null
		if k is int and slots[k] != null:
			drop_requested.emit(k, true)
		_refresh()


## Палец держат на ячейке TOUCH_HOLD секунд и не тащат — меню действий.
func _touch_hold(delta: float) -> void:
	if touch_key == null:
		return
	if not open or get_viewport().gui_is_dragging():
		touch_key = null
		return
	touch_t += delta
	if touch_t < TOUCH_HOLD:
		return
	var k = touch_key
	touch_key = null
	_press_key = null   # отпускание пальца уже не «использовать»
	if (k is String and equip[k] != "") or (k is int and slots[k] != null):
		open_menu(k, touch_pos)


func _finish_hold() -> void:
	var k = hold_key
	hold_key = null
	_finish_hold_key(k)
	_refresh()


func _finish_hold_key(k) -> void:
	if k is int and slots[k] != null:
		drop_count_requested.emit(k, 1)


# ---------- меню действий (ПКМ / долгий тап) ----------

func _build_menu() -> void:
	menu_bg = Control.new()
	menu_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	menu_bg.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			close_menu())
	menu_bg.visible = false
	root.add_child(menu_bg)
	menu = PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.1, 0.085, 0.07, 0.98)
	st.border_color = Color(0.9, 0.7, 0.4, 0.55)
	st.set_border_width_all(1)
	st.set_corner_radius_all(3)
	st.set_content_margin_all(6)
	menu.add_theme_stylebox_override("panel", st)
	menu_bg.add_child(menu)
	menu_box = VBoxContainer.new()
	menu_box.add_theme_constant_override("separation", 2)
	menu.add_child(menu_box)


## Что делает «использовать» для этой вещи ("" — нечего).
func _use_label(id: String) -> String:
	var d: Dictionary = Items.ITEMS[id]
	if d.has("repair"):
		return "Починить…"
	if d.has("weapon"):
		return "Взять в руку"
	if d.has("equip"):
		return "Надеть"
	if d.has("buff"):
		return "Съесть" if d["buff"] == "resist" else "Выпить"
	if d.has("heal"):
		return "Выпить" if id == "pills" else "Лечиться"
	if id == "mag":
		return "Снарядить"
	return {"wallet": "Открыть", "flashlight": "Включить / выключить", "battery": "Зарядить фонарик",
		"broom": "Подмести стекло"}.get(id, "")


## Меню у курсора: пункты по типу вещи в ячейке / слоте.
func open_menu(key, at: Vector2) -> void:
	hold_key = null
	for c in menu_box.get_children():
		menu_box.remove_child(c)
		c.queue_free()
	var acts: Array = []   # [текст, действие]
	var title := ""
	if key is String:
		if equip[key] == "":
			return
		title = Items.item_name(equip[key])
		if equip[key] == "pistol" and Gun.has_mag(get_dur(key)):
			acts.append(["Извлечь магазин", "eject"])
		acts.append(["Снять", "unequip"])
		acts.append(["Выбросить", "drop_eq"])
	else:
		var s = slots[key]
		if s == null:
			return
		var id: String = s["id"]
		var n := int(s["n"])
		title = Items.item_name(id) + ("  ×%d" % n if n > 1 else "")
		var ul := _use_label(id)
		if ul != "":
			acts.append([ul, "use"])
		if id == "pistol" and Gun.has_mag(get_dur(key)):
			acts.append(["Извлечь магазин", "eject"])
		if id == "mag" and (equip["right"] == "pistol" or equip["left"] == "pistol"):
			acts.append(["Вставить в пистолет", "insert_mag"])
		if n > 1:
			acts.append(["Разделить", "split"])
		acts.append(["Выбросить 1", "drop1"])
		if n > 1:
			acts.append(["Выбросить всё", "drop_all"])
	acts.append(["Отмена", "cancel"])
	var tl := _label(title, 15, Color(0.75, 0.7, 0.6))
	tl.clip_text = true
	tl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tl.custom_minimum_size = Vector2(190, 0)
	menu_box.add_child(tl)
	# пункта «На хотбар» нет (промпт 14.11 19:20) — на хотбар только перетаскиванием
	for a in acts:
		var b := Button.new()
		b.text = a[0]
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(190, 32)
		b.add_theme_font_size_override("font_size", 18)
		var act: String = a[1]
		if act.begins_with("drop"):
			b.add_theme_color_override("font_color", Color(1.0, 0.6, 0.5))
		b.pressed.connect(_menu_pick.bind(key, act))
		menu_box.add_child(b)
	menu_key = key
	menu_bg.visible = true
	menu.reset_size()
	# у курсора, но не за краем экрана
	var vs := get_viewport().get_visible_rect().size
	var sz := menu.get_combined_minimum_size()
	menu.position = Vector2(clampf(at.x + 4, 0, vs.x - sz.x), clampf(at.y + 4, 0, vs.y - sz.y))
	set_hover(key)


func close_menu() -> void:
	if menu_bg and menu_bg.visible:
		menu_bg.visible = false
		menu_key = null
		_press_key = null


func _menu_pick(key, act: String) -> void:
	close_menu()
	match act:
		"use":
			if key is int and slots[key] != null:
				use_requested.emit(key)
		"split":
			split(key)
		"eject":
			if game and game.gun:
				game.gun.eject(key)
		"insert_mag":
			if game and game.gun and key is int:
				game.gun.insert_mag(key, "right" if equip["right"] == "pistol" else "left")
		"drop1":
			if key is int and slots[key] != null:
				drop_count_requested.emit(key, 1)
		"drop_all":
			if key is int and slots[key] != null:
				drop_requested.emit(key, true)
		"unequip":
			unequip_requested.emit(key, -1)
		"drop_eq":
			drop_equipped_requested.emit(key)


## Разделить стопку пополам: половина (меньшая) — в первую свободную ячейку.
func split(idx: int) -> void:
	var s = slots[idx]
	if s == null or int(s["n"]) < 2:
		return
	var fp := find_place(String(s["id"]))
	if int(fp[0]) < 0:
		message.emit("Нет места")
		return
	@warning_ignore("integer_division")
	var half := int(s["n"]) / 2
	s["n"] = int(s["n"]) - half
	_put({"id": s["id"], "n": half}, int(fp[0]), bool(fp[1]))
	_after_change()


## Привязать к ячейке хотбара hk предмет из ячейки сумки / слота снаряжения key.
func bind_hot(key, hk: int) -> void:
	var id := ""
	if key is String:
		id = equip[key]
	elif key is int and key < slots.size() and slots[key] != null:
		id = slots[key]["id"]
	if id == "":
		return
	var old := hotbar.find(id)
	if old >= 0:
		hotbar[old] = ""
	hotbar[hk] = id
	message.emit("%s → клавиша %d" % [Items.item_name(id), hk + 1])
	_after_change()


func swap_hot(a: int, b: int) -> void:
	if a == b:
		return
	var t: String = hotbar[a]
	hotbar[a] = hotbar[b]
	hotbar[b] = t
	_after_change()


func unbind_hot(k: int) -> void:
	if hotbar[k] == "":
		return
	message.emit("%s отвязан от %d" % [Items.item_name(hotbar[k]), k + 1])
	hotbar[k] = ""
	_after_change()


## Ячейки хотбара — там же, где их рисует hud.gd (внизу по центру).
func _place_hot() -> void:
	var sz := root.size
	var cell := 64.0
	var gap := 8.0
	var x0 := sz.x / 2.0 - (cell * 5 + gap * 4) / 2.0
	for k in hot_nodes.size():
		var hs: Control = hot_nodes[k]
		hs.position = Vector2(x0 + k * (cell + gap), sz.y - cell - 18.0)
		hs.size = Vector2(cell, cell)
		hs.queue_redraw()


func _bind_hover(k: int) -> void:
	var h = hover if hover != null else touch_sel
	if h == null:
		return
	var id := ""
	if h is String:
		id = equip[h]
	elif slots[h] != null:
		id = slots[h]["id"]
	if id == "":
		return
	if hotbar[k] == id:
		hotbar[k] = ""
		message.emit("%s отвязан от %d" % [Items.item_name(id), k + 1])
	else:
		var old := hotbar.find(id)
		if old >= 0:
			hotbar[old] = ""
		hotbar[k] = id
		message.emit("%s → клавиша %d" % [Items.item_name(id), k + 1])
	_after_change()


## Выкатить / спрятать панель крафта (вкладка «Крафт», промпт 03:56).
func toggle_craft() -> void:
	set_craft(not craft_shown)


func set_craft(on: bool, instant := false) -> void:
	craft_shown = on
	craft_tab.text = "Крафт " + ("◂" if on else "▸")
	if craft_tw:
		craft_tw.kill()
	var sz := craft_panel.get_combined_minimum_size()
	craft_panel.size = sz
	craft_wrap.custom_minimum_size.y = sz.y
	var w := sz.x if on else 0.0
	if on:
		craft_wrap.visible = true
	if instant:
		craft_wrap.custom_minimum_size.x = w
		craft_wrap.visible = on
		return
	craft_tw = create_tween()
	craft_tw.tween_property(craft_wrap, "custom_minimum_size:x", w, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if not on:
		craft_tw.tween_callback(func(): craft_wrap.visible = false)


func show_inventory() -> void:
	open = true
	root.visible = true
	set_craft(false, true)   # по умолчанию — только инвентарь
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_rebuild_craft()
	_place_hot()
	set_hover(null)


func close() -> void:
	if not open:
		return
	open = false
	root.visible = false
	hover = null
	hold_key = null
	touch_key = null
	touch_sel = null
	dlg.visible = false
	close_menu()
	if not get_tree().paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func set_hover(k) -> void:
	hover = k
	var id := ""
	var n := 0
	if k is String:
		id = equip[k]
		n = 1
	elif k is int and slots[k] != null:
		id = slots[k]["id"]
		n = slots[k]["n"]
	if id != "":
		# при наведении — только название (промпт 03:50: без «×количество» и «[F — использовать]»)
		info_name.text = Items.item_name(id)
		info_desc.text = Items.ITEMS[id]["desc"] + _size_note(id)
		tip.visible = true
		tip.reset_size()
		_place_tip()
	else:
		tip.visible = false
	_refresh()


## Подсказка у курсора, в пределах экрана.
func _place_tip() -> void:
	if tip == null or not tip.visible:
		return
	var vp := root.get_viewport_rect().size
	var m := root.get_global_mouse_position()
	var sz := tip.get_combined_minimum_size()
	var p := m + Vector2(18, 18)
	if p.x + sz.x > vp.x:
		p.x = m.x - sz.x - 12
	if p.y + sz.y > vp.y:
		p.y = m.y - sz.y - 12
	tip.position = p.max(Vector2.ZERO)


## Название клавиши действия inv_use (по умолчанию F).
func _use_key() -> String:
	if InputMap.has_action("inv_use"):
		for ev in InputMap.action_get_events("inv_use"):
			if ev is InputEventKey:
				return OS.get_keycode_string(ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode)
			if ev is InputEventMouseButton:
				return "Кнопка мыши %d" % ev.button_index
	return "F"


## «Размер 2×3» и карманы / отсек рюкзака — к описанию.
## Подпись размера в описании убрана (промпт 03:46) — оставлено пустым, чтобы не трогать вызовы.
func _size_note(_id: String) -> String:
	return ""


func _refresh() -> void:
	for n in slot_nodes:
		n.queue_redraw()
	for n in grids:
		n.queue_redraw()
	for n in hot_nodes:
		n.queue_redraw()


## Перетаскивание: from/to — номер ячейки или имя слота экипировки.
func move(from, to) -> void:
	if typeof(from) == typeof(to) and from == to:
		return
	# ремкомплект перетащили на вещь — починить её
	if from is int and slots[from] != null and Items.ITEMS[slots[from]["id"]].has("repair"):
		var tid := ""
		if to is String:
			tid = equip[to]
		elif slots[to] != null:
			tid = slots[to]["id"]
		if tid != "" and Items.repairable(tid) != "":
			repair_requested.emit(from, to)
			return
	# пистолет: магазин на пистолет — вставить; патроны на магазин — дозарядить (промпт 22:53)
	if from is int and slots[from] != null and game and game.gun:
		var fid: String = slots[from]["id"]
		var tid2 := ""
		if to is String:
			tid2 = equip[to]
		elif slots[to] != null:
			tid2 = slots[to]["id"]
		if fid == "mag" and tid2 == "pistol":
			game.gun.insert_mag(from, to)
			return
		if fid == "ammo" and tid2 == "mag" and to is int:
			game.gun.fill_mag(to)
			return
	if from is int and to is int:
		var a = slots[from]
		var b = slots[to]
		if a != null and b != null and a["id"] == b["id"]:
			var mx: int = Items.ITEMS[a["id"]]["stack"]
			var take := mini(int(a["n"]), mx - int(b["n"]))
			b["n"] += take
			a["n"] -= take
			if a["n"] <= 0:
				slots[from] = null
		elif a != null:
			_move_item(from, to, bool(a.get("r", false)))
			return
		_after_change()
	elif from is int and to is String:
		var s = slots[from]
		if s == null:
			return
		if not Items.fits(s["id"], to):
			message.emit("%s сюда не надеть" % Items.item_name(s["id"]))
			return
		equip_requested.emit(from, to)
	elif from is String and to is int:
		unequip_requested.emit(from, to)
	elif from is String and to is String:
		_swap_equip(from, to)


## Слот экипировки → другой слот (левая рука ↔ правая): меняем местами вместе с прочностью.
func _swap_equip(a: String, b: String) -> void:
	var ia: String = equip[a]
	var ib: String = equip[b]
	if ia == "":
		return
	if not Items.fits(ia, b) or (ib != "" and not Items.fits(ib, a)):
		message.emit("%s сюда не надеть" % Items.item_name(ia))
		return
	var da = equip_dur.get(a)
	var db = equip_dur.get(b)
	equip[a] = ib
	equip[b] = ia
	equip_dur.erase(a)
	equip_dur.erase(b)
	if db != null and ib != "":
		equip_dur[a] = db
	if da != null:
		equip_dur[b] = da
	if game:
		game._apply_equip(a)
		game._apply_equip(b)
	_after_change()


# ---------- данные ----------


# ---------- сетка (промпт 16.11 02:42) ----------

## Размер блока b сейчас (рюкзак / карманы — от надетой вещи; не надето — 0×0).
func block_dim(b: int) -> Vector2i:
	if b == 0:
		return Vector2i(COLS, int(BLOCKS[0][2]))
	var d := Items.block_of(String(equip.get(BLOCKS[b][3], "")))
	return Vector2i(mini(d.x, BLOCKS[b][1]), mini(d.y, BLOCKS[b][2]))


func cell_block(i: int) -> int:
	for b in range(BLOCKS.size() - 1, -1, -1):
		if i >= int(BLOCKS[b][0]):
			return b
	return 0


func cell_xy(i: int) -> Vector2i:
	var b := cell_block(i)
	var o: int = i - int(BLOCKS[b][0])
	var w: int = BLOCKS[b][1]
	@warning_ignore("integer_division")
	return Vector2i(o % w, o / w)


func cell_idx(b: int, x: int, y: int) -> int:
	return int(BLOCKS[b][0]) + y * int(BLOCKS[b][1]) + x


## Размер предмета в ячейке с учётом поворота.
func item_dim(s) -> Vector2i:
	var d := Items.size_of(String(s["id"]))
	return Vector2i(d.y, d.x) if bool(s.get("r", false)) else d


## Ячейки под предметом размера d с якорем at; [] — выходит за активную часть блока.
func _cells(at: int, d: Vector2i) -> Array:
	if at < 0 or at >= TOTAL:
		return []
	var b := cell_block(at)
	var p := cell_xy(at)
	var bd := block_dim(b)
	if p.x + d.x > bd.x or p.y + d.y > bd.y:
		return []
	var out: Array = []
	for y in d.y:
		for x in d.x:
			out.append(cell_idx(b, p.x + x, p.y + y))
	return out


## Для каждой ячейки — якорь предмета, который её занимает (-1 — пусто).
func occupancy() -> PackedInt32Array:
	var occ := PackedInt32Array()
	occ.resize(TOTAL)
	occ.fill(-1)
	for i in TOTAL:
		var s = slots[i]
		if s == null:
			continue
		for c in _cells(i, item_dim(s)):
			occ[c] = i
	return occ


## Якорь предмета, накрывающего ячейку i; -1 — пусто.
func owner_at(i: int) -> int:
	if i < 0 or i >= TOTAL:
		return -1
	return occupancy()[i]


func _fits_at(at: int, d: Vector2i, occ: PackedInt32Array) -> bool:
	var cells := _cells(at, d)
	if cells.is_empty():
		return false
	for c in cells:
		if occ[c] != -1:
			return false
	return true


## Свободное место под предмет id: [якорь, повёрнут]; [-1, false] — нет места. Сначала сумка, потом рюкзак, карманы.
func find_place(id: String, occ = null) -> Array:
	if occ == null:
		occ = occupancy()
	var d := Items.size_of(id)
	for b in BLOCKS.size():
		var bd := block_dim(b)
		for rot in ([false, true] if d.x != d.y else [false]):
			var dd := Vector2i(d.y, d.x) if rot else d
			for y in maxi(bd.y - dd.y + 1, 0):
				for x in maxi(bd.x - dd.x + 1, 0):
					var at := cell_idx(b, x, y)
					if _fits_at(at, dd, occ):
						return [at, rot]
	return [-1, false]


func _put(s: Dictionary, at: int, rot: bool, occ = null) -> void:
	if rot:
		s["r"] = true
	else:
		s.erase("r")
	slots[at] = s
	if occ != null:
		for c in _cells(at, item_dim(s)):
			occ[c] = at


## Проверить раскладку: предметы, что вылезли за блок (сняли рюкзак/куртку) или наложились, — переложить
## в свободное место; extra — новые предметы ({..., "_at": желаемый якорь}). Возвращает то, что не влезло
## (эти предметы из сумки уже убраны — вызывающий откатывает snapshot или выбрасывает их).
func reflow(extra: Array = []) -> Array:
	var pending: Array = extra.duplicate()
	var occ := PackedInt32Array()
	occ.resize(TOTAL)
	occ.fill(-1)
	for i in TOTAL:
		var s = slots[i]
		if s == null:
			continue
		var cells := _cells(i, item_dim(s))
		var ok := not cells.is_empty()
		for c in cells:
			if occ[c] != -1:
				ok = false
		if ok:
			for c in cells:
				occ[c] = i
		else:
			slots[i] = null
			pending.append(s)
	var left: Array = []
	for s in pending:
		var at := int(s.get("_at", -1))
		s.erase("_at")
		var placed := false
		if at >= 0:
			var r0 := bool(s.get("r", false))
			for rot in [r0, not r0]:
				var d := Items.size_of(String(s["id"]))
				if rot:
					d = Vector2i(d.y, d.x)
				if _fits_at(at, d, occ):
					_put(s, at, rot, occ)
					placed = true
					break
		if not placed:
			var fp := find_place(String(s["id"]), occ)
			if int(fp[0]) >= 0:
				_put(s, int(fp[0]), bool(fp[1]), occ)
				placed = true
		if not placed:
			left.append(s)
	return left


## Старая раскладка (сумка 5×5, 52 ячейки): номера ячеек → новые. Нижний ряд сумки (20..24) — в extra
## (reflow положит куда влезет, остальное — на пол), рюкзак и карманы сдвигаются на 5.
static func migrate_bag(old: Array) -> Array:
	var out: Array = []
	out.resize(TOTAL)
	var extra: Array = []
	for i in old.size():
		var s = old[i]
		if s == null:
			continue
		if i < 20:
			out[i] = s
		elif i < 25:
			extra.append(s)
		elif i - 5 < TOTAL:
			out[i - 5] = s
		else:
			extra.append(s)
	return [out, extra]


func snapshot() -> Array:
	return [slots.duplicate(true), equip.duplicate(), equip_dur.duplicate()]


func restore(sn: Array) -> void:
	slots = sn[0]
	equip = sn[1]
	equip_dur = sn[2]
	update_blocks()


## Блоки рюкзака и карманов — по надетому (вызывает game._apply_equip и загрузка).
func update_blocks() -> void:
	if slots.size() != TOTAL:
		slots.resize(TOTAL)
	for b in grids.size():
		var d := block_dim(b)
		grids[b].refit()
		grids[b].get_parent().visible = d.x > 0 and d.y > 0
		if b > 0:
			block_ls[b].text = "%s %d×%d" % [BLOCKS[b][4], d.x, d.y]
	if hover is int and slots[hover] == null:
		hover = null
	if touch_sel is int and slots[touch_sel] == null:
		touch_sel = null
	_refresh()


## Есть ли место под предмет id (для разделения стопки и т.п.).
func free_cell_for(id: String) -> int:
	return int(find_place(id)[0])

## Прочность предмета в ячейке (int) или в слоте снаряжения (String).
func get_dur(key) -> float:
	if key is String:
		var eid: String = equip[key]
		return float(equip_dur.get(key, Items.max_dur(eid)))
	var s = slots[key]
	if s == null:
		return 0.0
	return float(s.get("dur", Items.max_dur(s["id"])))




## Добавить предметы; возвращает, сколько не влезло. Монеты идут в кошелёк.
## dur — прочность (для оружия/сапог, подобранных с пола), -1 — новая вещь.
## Новая стопка ложится туда, где помещается её размер (find_place), при нужде — повёрнутой.
func add(id: String, n: int, dur := -1.0) -> int:
	if id == "coin":
		coins += n
		_after_change()
		return 0
	var mx: int = Items.ITEMS[id]["stack"]
	for s in slots:
		if n <= 0:
			break
		if s != null and s["id"] == id and s["n"] < mx:
			var take := mini(n, mx - int(s["n"]))
			s["n"] += take
			n -= take
	while n > 0:
		var fp := find_place(id)
		var i := int(fp[0])
		if i == -1:
			break
		var take := mini(n, mx)
		var e := {"id": id, "n": take}
		if dur >= 0.0:
			e["dur"] = dur
		_put(e, i, bool(fp[1]))
		n -= take
	_after_change()
	return n



## Сколько есть (в сумке + надето; монеты — в кошельке).
func count(id: String) -> int:
	if id == "coin":
		return coins
	var c := 0
	for s in slots:
		if s != null and s["id"] == id:
			c += int(s["n"])
	for k in equip:
		if equip[k] == id:
			c += 1
	return c


func bag_index(id: String) -> int:
	for i in slots.size():
		if slots[i] != null and slots[i]["id"] == id:
			return i
	return -1


## Убрать n штук из сумки (с последних стаков). false — если столько нет.
func remove(id: String, n: int) -> bool:
	if id == "coin":
		if coins < n:
			return false
		coins -= n
		_after_change()
		return true
	var have := 0
	for s in slots:
		if s != null and s["id"] == id:
			have += int(s["n"])
	if have < n:
		return false
	for i in range(slots.size() - 1, -1, -1):
		var s = slots[i]
		if n <= 0:
			break
		if s != null and s["id"] == id:
			var take := mini(n, int(s["n"]))
			s["n"] -= take
			n -= take
			if s["n"] <= 0:
				slots[i] = null
	_after_change()
	return true


## Забрать из ячейки idx до n штук; возвращает [id, сколько забрали].
func take_at(idx: int, n: int) -> Array:
	var s = slots[idx]
	if s == null:
		return ["", 0]
	var take := mini(n, int(s["n"]))
	s["n"] -= take
	var id: String = s["id"]
	if s["n"] <= 0:
		slots[idx] = null
	_after_change()
	return [id, take]


func notify() -> void:
	_after_change()


func _after_change() -> void:
	# вещь сломалась / её забрали — карманы или рюкзак пропали: вещи из них перекладываем, не влезло — на пол
	var lost := reflow()
	if not lost.is_empty():
		spilled.emit(lost)
	if wallet_l:
		wallet_l.text = "Монеты: %d" % coins
	if open:
		set_hover(hover)
		_rebuild_craft()
	changed.emit()
