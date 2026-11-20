extends CanvasLayer
## Окно продажи в Trinkets Market (промпт 14.11 18:06): слева сумка, справа «на продажу».
## Клик — переложить стопку в другую колонку, Shift+клик — одну штуку, можно перетаскивать мышью.
## Внизу сумма и «Продать всё». Закрыл, не продав, — вещи возвращаются в сумку (не влезли — падают на пол).
##
## Цена продажи = ceil(рыночная / 2) за штуку, у вещей с износом (оружие, одежда, ремкомплекты) — ещё × доля прочности.
## Рыночная — цена в магазине (Weapons.SHOP, shop.gd: CONSUMABLES). У хлама, которого в магазине нет,
## рыночная = 2 × прежняя «цена скупки» (поле price в items.gd), так что за него дают те же 2/3/3/5.
## Монеты и квестовые вещи (car_key и всё с "quest") не продаются.
## Слева две колонки-источника (промпт 15.11 23:31): сумка и сундук дома (game.storage) — продавать можно из обоих;
## непроданное возвращается туда, откуда взято.

const Items := preload("res://scripts/items.gd")
const Weapons := preload("res://scripts/weapons.gd")
## рыночные цены вещей, которых нет в магазине и которые не хлам
const EXTRA_MARKET := {"wallet": 10, "knuckles": 30, "twine": 4,
	"hammer": 16, "shiv": 30, "spiked_club": 50, "knife": 20, "pistol": 120, "mag": 20, "ammo": 3}
const NO_SELL := ["coin", "car_key"]
## мусор, который магазин не берёт совсем (промпты 16.11 02:45, 02:46)
const TRASH := ["glass", "wood", "stone"]
const TRASH_MSG := "Этот мусор даже мы покупать не будем"
const Inv := preload("res://scripts/inventory.gd")
const CELL := 48.0        # 10 колонок сундука = 480 px — ровно в ширину блока снаряжения
const BAG_CELL := 48.0    # компактная, но читаемая сетка сумки (или 58.0, если хотите 1-в-1 как в инвентаре)
const SELL_CELL := 58.0   # компактные ячейки правой колонки «НА ПРОДАЖУ»
const DEFAULT_INFO := "ЛКМ — продать кол-во, Ctrl+ЛКМ — стопка, Shift+ЛКМ — 1 шт."

var game
var shop                        # shop.gd — пересобрать его после продажи
var open := false
var pending: Array = []         # [[id, n, прочность или -1, откуда: "bag" | "chest"], ...]
var bag_grids: Array = []
var bag_labels: Array = []
var doll_slots: Array = [] 
var chest_grid: SellChestGrid
var chest_lbl: Label
var _near_chest = null
var left_scroll: ScrollContainer
var sell_grid: GridContainer
var total_l: Label
var info_l: Label
var _info_t := 0.0
var sell_b: Button
var panel: PanelContainer
var cols: HBoxContainer
var panes := {}                 # side -> Pane (высоту подгоняем под экран, промпт 02:33)
var _qty_popup: PopupPanel
var _qty_slider: HSlider
var _qty_spin: SpinBox
var _qty_val_l: Label
var _qty_cb: Callable

func _find_near_chest():
	if shop == null or not (shop is Node3D):
		return null
	var best = null
	var best_d := 20.0
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if is_instance_valid(n) and n is Node3D and n.get("kind") == "storage":
			var d: float = shop.global_position.distance_to((n as Node3D).global_position)
			if d <= best_d:
				best_d = d
				best = n
	return best


## Рыночная цена (0 — не продаётся).
static func market(id: String) -> int:
	if id in NO_SELL or id in TRASH or not Items.ITEMS.has(id) or Items.ITEMS[id].get("quest", false):
		return 0
	for e in Weapons.SHOP:
		if e[0] == id:
			return int(e[1])
	for e in preload("res://scripts/shop/shop.gd").CONSUMABLES:
		if e[0] == id:
			return int(e[1])
	for e in preload("res://scripts/shop/shop.gd").TOOLS:
		if e[0] == id:
			return int(e[1])
	if Items.ITEMS[id].has("price"):
		return int(Items.ITEMS[id]["price"]) * 2
	return int(EXTRA_MARKET.get(id, 0))


## Сколько дадут за 1 шт. (dur < 0 — новая вещь).
static func unit_price(id: String, dur := -1.0) -> int:
	var m := market(id)
	if m <= 0:
		return 0
	var mx := Items.max_dur(id)
	var fr := 1.0 if mx <= 0.0 or dur < 0.0 or Items.ITEMS[id].has("rounds") else clampf(dur / mx, 0.0, 1.0)
	var base := maxi(1, ceili(m * fr / 2.0))
	# Если это пистолет с магазином — прибавляем цену магазина и патронов в нём
	if id == "pistol" and dur >= 1.0:
		base += unit_price("mag", -1.0)
		var rounds := maxi(0, roundi(dur) - 1)
		if rounds > 0:
			base += unit_price("ammo", -1.0) * rounds
	return base

func _item_tooltip(id: String, dur := -1.0) -> String:
	if id == "":
		return ""
	var m := market(id)
	if m <= 0:
		return Items.item_name(id) + ("\n" + TRASH_MSG if id in TRASH else "\nМагазин не берёт")
	return "%s\nПродать: %d за шт." % [Items.item_name(id), unit_price(id, dur)]

func _drag_icon(id: String) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(44, 44)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void:
		Items.draw_icon(c, id, Rect2(Vector2.ZERO, Vector2(44, 44))))
	return c

class SellBagGrid extends Inv.BagGrid:
	var sw
	var _last_o := -1
	var _press_pos := Vector2(-999, -999)

	func _draw() -> void:
		super()
		var c: float = Inv.CELL
		for i in inv.TOTAL:
			var s = inv.slots[i]
			if not (s is Dictionary) or inv.cell_block(i) != b:
				continue
			if sw.market(String(s["id"])) <= 0:
				var p: Vector2i = inv.cell_xy(i)
				var r := Rect2(Vector2(p) * c, Vector2(inv.item_dim(s)) * c)
				draw_rect(r.grow(-1), Color(0, 0, 0, 0.58))


	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseMotion:
			var o: int = inv.owner_at(cell_at(e.position))
			if o != _last_o:
				_last_o = o
				if o >= 0:
					var s = inv.slots[o]
					tooltip_text = sw._item_tooltip(String(s["id"]), float(s.get("dur", -1.0)))
				else:
					tooltip_text = ""
		elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_press_pos = e.position
			elif _press_pos.x >= 0.0 and e.position.distance_to(_press_pos) < 6.0:
				var o: int = inv.owner_at(cell_at(e.position))
				if o >= 0:
					if e.ctrl_pressed:
						sw.pick_bag_slot(o, -1)
					elif e.shift_pressed:
						sw.pick_bag_slot(o, 1)
					else:
						sw.pick_bag_slot(o, 0)
					accept_event()
				_press_pos = Vector2(-999, -999)

	func _get_drag_data(at: Vector2) -> Variant:
		var data = super(at)
		if data is Dictionary and data.has("inv_key"):
			# Добавляем метку для панели продажи справа, сохраняя родное превью и подсветку инвентаря
			data["sw_direct"] = "bag"
			data["slot"] = data["inv_key"]
		return data

	func _can_drop_data(at: Vector2, data: Variant) -> bool:
		if not (data is Dictionary) or data.get("sw_direct", "") == "chest":
			return false
		return super(at, data)

	func _drop_data(at: Vector2, data: Variant) -> void:
		if not (data is Dictionary) or data.get("sw_direct", "") == "chest":
			return
		super(at, data)
		sw._rebuild()



class SellEquipSlot extends Inv.Slot:
	var sw
	var _press_pos := Vector2(-999, -999)

	func _draw() -> void:
		super()
		var id := item_id()
		if id != "" and sw.market(id) <= 0:
			draw_rect(Rect2(Vector2.ZERO, Vector2(px, px)), Color(0, 0, 0, 0.58))

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and item_id() != "":
			if e.pressed:
				_press_pos = e.position
			elif _press_pos.x >= 0.0 and e.position.distance_to(_press_pos) < 6.0:
				sw.pick_equip_slot(String(key))
				accept_event()
				_press_pos = Vector2(-999, -999)

	func _get_drag_data(at: Vector2) -> Variant:
		var data = super(at)
		if data is Dictionary and data.has("inv_key"):
			data["sw_direct"] = "equip"
			data["slot"] = String(key)
		return data

	func _can_drop_data(at: Vector2, data: Variant) -> bool:
		# Из сундука на куклу надевать запрещено!
		if data is Dictionary and data.get("sw_direct", "") == "chest":
			return false
		return super(at, data)

	func _drop_data(at: Vector2, data: Variant) -> void:
		if data is Dictionary and data.get("sw_direct", "") == "chest":
			return
		super(at, data)
		sw._rebuild()


class SellChestGrid extends Control:
	const Items := preload("res://scripts/items.gd")
	var sw
	var _last_i := -1
	var _press_pos := Vector2(-999, -999)

	func refit() -> void:
		var h := 5
		if sw._near_chest:
			for it in sw._near_chest.contents:
				var p := int(it.get(3)) if it.size() > 3 and int(it.get(3)) >= 0 else 0
				var d := Items.size_of(String(it.get(0)))
				if it.size() > 4 and bool(it.get(4)):
					d = Vector2i(d.y, d.x)
				@warning_ignore("integer_division")
				h = maxi(h, p / 10 + d.y)
		custom_minimum_size = Vector2(10, h) * sw.CELL
		size = custom_minimum_size
		size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		queue_redraw()

	func _owner_at(p: Vector2) -> int:
		if sw._near_chest == null or p.x < 0 or p.y < 0:
			return -1
		var cell := Vector2i(int(p.x / sw.CELL), int(p.y / sw.CELL))
		var cont: Array = sw._near_chest.contents
		for i in cont.size():
			var it: Array = cont[i]
			var idx := int(it.get(3)) if it.size() > 3 and int(it.get(3)) >= 0 else i
			@warning_ignore("integer_division")
			var pos := Vector2i(idx % 10, idx / 10)
			var d := Items.size_of(String(it.get(0)))
			if it.size() > 4 and bool(it.get(4)):
				d = Vector2i(d.y, d.x)
			if Rect2i(pos, d).has_point(cell):
				return i
		return -1

	func _draw() -> void:
		var c: float = sw.CELL
		var cols_n := 10
		var rows_n := int(size.y / c)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.5))
		for x in cols_n + 1:
			draw_line(Vector2(x * c, 0), Vector2(x * c, size.y), Color(1, 1, 1, 0.1), 1.0)
		for y in rows_n + 1:
			draw_line(Vector2(0, y * c), Vector2(size.x, y * c), Color(1, 1, 1, 0.1), 1.0)
		if sw._near_chest == null:
			return
		var f := ThemeDB.fallback_font
		var cont: Array = sw._near_chest.contents
		for i in cont.size():
			var it: Array = cont[i]
			var id := String(it.get(0))
			var idx := int(it.get(3)) if it.size() > 3 and int(it.get(3)) >= 0 else i
			@warning_ignore("integer_division")
			var pos := Vector2i(idx % 10, idx / 10)
			var d := Items.size_of(id)
			if it.size() > 4 and bool(it.get(4)):
				d = Vector2i(d.y, d.x)
			var r := Rect2(Vector2(pos) * c, Vector2(d) * c)
			draw_rect(r.grow(-1), Color(0.2, 0.17, 0.12, 0.45))
			draw_rect(r.grow(-1), Color(1, 1, 1, 0.25), false, 1.0)
			var side := minf(r.size.x, r.size.y) - 10.0
			Items.draw_icon(self, id, Rect2(r.get_center() - Vector2(side, side) / 2, Vector2(side, side)))
			if int(it.get(1)) > 1:
				draw_string_outline(f, Vector2(r.position.x + 2, r.end.y - 6), str(int(it.get(1))), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 6, 14, 3, Color(0, 0, 0, 0.85))
				draw_string(f, Vector2(r.position.x + 2, r.end.y - 6), str(int(it.get(1))), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 6, 14, Color(0.95, 0.88, 0.6))
			if sw.market(id) <= 0:
				draw_rect(r.grow(-1), Color(0, 0, 0, 0.58))

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseMotion:
			var i := _owner_at(e.position)
			if i != _last_i:
				_last_i = i
				if i >= 0:
					var it: Array = sw._near_chest.contents[i]
					var dur := float(it.get(2)) if it.size() > 2 else -1.0
					tooltip_text = sw._item_tooltip(String(it.get(0)), dur)
				else:
					tooltip_text = ""
		elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_press_pos = e.position
			elif _press_pos.x >= 0.0 and e.position.distance_to(_press_pos) < 6.0:
				var i := _owner_at(e.position)
				if i >= 0:
					if e.ctrl_pressed:
						sw.pick_chest_idx(i, -1)
					elif e.shift_pressed:
						sw.pick_chest_idx(i, 1)
					else:
						sw.pick_chest_idx(i, 0)
					accept_event()
				_press_pos = Vector2(-999, -999)

	func _get_drag_data(at: Vector2) -> Variant:
		var i := _owner_at(at)
		if i < 0 or sw.market(String(sw._near_chest.contents[i].get(0))) <= 0:
			return null
		var id := String(sw._near_chest.contents[i].get(0))
		set_drag_preview(sw._drag_icon(id))
		return {"sw_direct": "chest", "slot": i}

	func _can_drop_data(_at: Vector2, _data: Variant) -> bool:
		return false

class Cell extends Button:
	const Items := preload("res://scripts/items.gd")
	var sw
	var side := "bag"            # bag — сумка, sell — на продажу
	var idx := 0
	var id := ""
	var n := 0
	var dur := -1.0
	var price := 0               # для колонки «на продажу» — сумма за стопку
	var dim := false             # в сумке: не продаётся
	var equipped := false        # надето на персонаже

	func _ready() -> void:
		custom_minimum_size = Vector2(sw.SELL_CELL, sw.SELL_CELL)
		focus_mode = Control.FOCUS_NONE
		if id != "":
			var eq_note := " [Надето]" if equipped else ""
			tooltip_text = Items.item_name(id) + eq_note + ("" if dim else "\nПродать: %d за шт." % sw.unit_price(id, dur))


	func _draw() -> void:
		if id == "":
			return
		Items.draw_icon(self, id, Rect2(Vector2(10, 8), size - Vector2(20, 20)))
		var f := ThemeDB.fallback_font
		var mx := Items.max_dur(id)
		if mx > 0.0 and dur >= 0.0:
			var fr := clampf(dur / mx, 0.0, 1.0)
			draw_rect(Rect2(6, size.y - 7, size.x - 12, 3), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(6, size.y - 7, (size.x - 12) * fr, 3), Color(0.85, 0.25, 0.15).lerp(Color(0.45, 0.85, 0.35), fr))
		if n > 1:
			draw_string_outline(f, Vector2(4, size.y - 10), str(n), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 9, 16, 4, Color(0, 0, 0, 0.8))
			draw_string(f, Vector2(4, size.y - 10), str(n), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 9, 16, Color(0.92, 0.9, 0.84))
		if side == "sell":
			var t := "%d" % price
			draw_string_outline(f, Vector2(4, 17), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(0, 0, 0, 0.85))
			draw_string(f, Vector2(4, 17), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.0, 0.82, 0.4))
		if equipped:
			draw_string_outline(f, Vector2(4, 15), "надето", HORIZONTAL_ALIGNMENT_LEFT, size.x - 8, 12, 4, Color(0, 0, 0, 0.9))
			draw_string(f, Vector2(4, 15), "надето", HORIZONTAL_ALIGNMENT_LEFT, size.x - 8, 12, Color(0.55, 0.9, 0.6))
		if dim:
			draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))
			var mark := "мусор" if id in sw.TRASH else "нельзя"
			draw_string_outline(f, Vector2(0, size.y / 2 + 5), mark, HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, 4, Color(0, 0, 0, 0.9))
			draw_string(f, Vector2(0, size.y / 2 + 5), mark, HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, Color(0.95, 0.5, 0.4))

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and id != "":
			sw.click(side, idx, e.shift_pressed)
			accept_event()

	func _get_drag_data(_at: Vector2) -> Variant:
		if id == "" or dim:
			return null
		var pv := Label.new()
		pv.text = Items.item_name(id)
		set_drag_preview(sw._drag_icon(id))
		return {"sw_side": side, "idx": idx}

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		if not (data is Dictionary):
			return false
		if data.has("sw_direct") and side == "sell":
			return true
		return data.has("sw_side") and (data["sw_side"] == "sell") != (side == "sell")

	func _drop_data(_at: Vector2, data: Variant) -> void:
		if data.has("sw_direct"):
			match String(data["sw_direct"]):
				"bag":
					sw.pick_bag_slot(int(data["slot"]), 0)
				"equip":
					sw.pick_equip_slot(String(data["slot"]))
				"chest":
					sw.pick_chest_idx(int(data["slot"]), 0)
			return
		sw.click(data["sw_side"], data["idx"], false, side)



class Pane extends PanelContainer:
	var sw
	var side := "bag"

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		if not (data is Dictionary):
			return false
		if data.has("sw_direct") and side == "sell":
			return true
		return data.has("sw_side") and (data["sw_side"] == "sell") != (side == "sell")

	func _drop_data(_at: Vector2, data: Variant) -> void:
		if data.has("sw_direct"):
			match String(data["sw_direct"]):
				"bag":
					sw.pick_bag_slot(int(data["slot"]), -1)
				"equip":
					sw.pick_equip_slot(String(data["slot"]))
				"chest":
					sw.pick_chest_idx(int(data["slot"]), -1)
			return
		sw.click(data["sw_side"], data["idx"], false, side)


func _ready() -> void:
	layer = 6
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent): preload("res://scripts/loot_window.gd")._click_away(dim, e, close))   # клик мимо — закрыть
	add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cc)
	panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.06, 0.05, 0.97)
	sb.border_color = Color(0.6, 0.3, 0.15, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", sb)
	cc.add_child(panel)
	preload("res://scripts/ui/ui_fit.gd").attach(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	# Верхняя строка: заголовок «ПРОДАЖА» слева и крестик закрытия в правом верхнем углу
	var top_bar := HBoxContainer.new()
	v.add_child(top_bar)
	var title_l := _label("ПРОДАЖА", 30, Color(1.0, 0.6, 0.35))
	title_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(title_l)

	var x := Button.new()
	x.focus_mode = Control.FOCUS_NONE
	x.tooltip_text = "Закрыть (Esc)"
	x.custom_minimum_size = Vector2(34, 34)
	x.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var x_sb := func(bg: Color, brd: Color) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = bg
		s.border_color = brd
		s.set_border_width_all(2)
		s.set_corner_radius_all(17)
		return s
	x.add_theme_stylebox_override("normal", x_sb.call(Color(0.45, 0.1, 0.07), Color(0.95, 0.85, 0.6)))
	x.add_theme_stylebox_override("hover", x_sb.call(Color(0.7, 0.15, 0.08), Color(1, 0.95, 0.7)))
	x.add_theme_stylebox_override("pressed", x_sb.call(Color(0.35, 0.07, 0.05), Color(1, 0.95, 0.7)))
	x.draw.connect(func():
		var c := x.size / 2
		x.draw_line(c + Vector2(-7, -7), c + Vector2(7, 7), Color(1, 0.95, 0.85), 3.0, true)
		x.draw_line(c + Vector2(7, -7), c + Vector2(-7, 7), Color(1, 0.95, 0.85), 3.0, true))
	x.pressed.connect(close)
	top_bar.add_child(x)

	cols = HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	v.add_child(cols)

	left_scroll = ScrollContainer.new()
	left_scroll.custom_minimum_size = Vector2(510, 420)
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cols.add_child(left_scroll)

	var left_pad := MarginContainer.new()
	left_pad.add_theme_constant_override("margin_right", 12) # отступ до скроллбара справа
	left_scroll.add_child(left_pad)

	var bc := VBoxContainer.new()
	bc.add_theme_constant_override("separation", 10)
	left_pad.add_child(bc)

	bc.add_child(_label("СНАРЯЖЕНИЕ", 22, Color(0.86, 0.85, 0.8)))
	var inv_row := HBoxContainer.new()
	inv_row.add_theme_constant_override("separation", 14)
	bc.add_child(inv_row)

	# Кукла в нормальном масштабе (192x320, слоты по 64 px)
	var doll := Inv.Doll.new()
	doll.custom_minimum_size = Vector2(192, 320)
	doll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	inv_row.add_child(doll)
	for k in Inv.EQUIP + ["hands"]:
		var s := SellEquipSlot.new()
		s.sw = self
		s.inv = game.inv
		s.key = k
		s.px = 64.0
		var pos: Vector2 = Inv.HANDS2 if k == "hands" and doll_slots.size() >= Inv.EQUIP.size() else Inv.DOLL_POS[k]
		s.position = pos
		s.mirror = pos.x < 1.0 and k in ["hands", "left"]
		doll.add_child(s)
		doll_slots.append(s)


	var block_holders: Array = []
	for b in Inv.BLOCKS.size():
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		var bl := _label(Inv.BLOCKS[b][4], 13, Color(0.6, 0.6, 0.56))
		col.add_child(bl)
		bag_labels.append(bl)
		var g := SellBagGrid.new()
		g.sw = self
		g.b = b
		g.inv = game.inv
		col.add_child(g)
		bag_grids.append(g)
		block_holders.append(col)

	inv_row.add_child(block_holders[0])
	var pockets_col := VBoxContainer.new()
	pockets_col.add_theme_constant_override("separation", 6)
	inv_row.add_child(pockets_col)
	for b in range(1, block_holders.size()):
		pockets_col.add_child(block_holders[b])

	chest_lbl = _label("СУНДУК РЯДОМ", 20, Color(0.8, 0.72, 0.55))
	bc.add_child(chest_lbl)
	chest_grid = SellChestGrid.new()
	chest_grid.sw = self
	bc.add_child(chest_grid)
	
	# Правая колонка: «НА ПРОДАЖУ», слоты, сумма и кнопка «Продать» прямо под слотами
	var sc := VBoxContainer.new()
	sc.add_theme_constant_override("separation", 8)
	cols.add_child(sc)
	sc.add_child(_label("НА ПРОДАЖУ", 24, Color(1.0, 0.82, 0.4)))
	sell_grid = _pane(sc, "sell", 5)
	total_l = _label("", 22, Color(0.92, 0.8, 0.5))
	sc.add_child(total_l)
	sell_b = _button("Продать", sell_all)
	sc.add_child(sell_b)

	info_l = _label(DEFAULT_INFO, 15, Color(0.7, 0.68, 0.62))
	info_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_l.custom_minimum_size = Vector2(1, 0)
	v.add_child(info_l)

func _indented_label(t: String, size: int, col: Color, left_px: int) -> MarginContainer:
	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left", left_px)
	mc.add_child(_label(t, size, col))
	return mc

## Высота колонок под экран (промпт 02:33): списки укорачиваются (внутри прокрутка),
## чтобы всё окно влезало по высоте; ui_fit дожимает масштабом, если и так не влезло.
func _fit_panes() -> void:
	if panel == null or not visible:
		return
	var vh := get_viewport().get_visible_rect().size.y * 0.9
	var sp: Control = panes["sell"]
	var over := panel.get_combined_minimum_size().y - cols.get_combined_minimum_size().y + 24.0 + 8.0
	var cs := int(SELL_CELL)
	var exact_h := 5 * cs + 4 * 6 + 12
	var h := clampf(vh - over, 3 * cs + 2 * 6 + 12, exact_h)
	sp.custom_minimum_size.y = h
	if left_scroll:
		left_scroll.custom_minimum_size.y = h + 84.0



func _button(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(cb)
	return b


func _pane(parent: Control, side: String, rows := 5) -> GridContainer:
	var p := Pane.new()
	p.sw = self
	p.side = side
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN # рамка строго по ширине сетки, без полей по бокам
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0, 0, 0, 0.3)
	st.set_content_margin_all(6)
	p.add_theme_stylebox_override("panel", st)
	var cs := int(SELL_CELL)
	var exact_w := 5 * cs + 4 * 6 + 12
	var exact_h := rows * cs + (rows - 1) * 6 + 12
	p.custom_minimum_size = Vector2(exact_w, exact_h)
	parent.add_child(p)
	panes[side] = p
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.custom_minimum_size = Vector2(5 * cs + 4 * 6, 0)
	sc.mouse_filter = Control.MOUSE_FILTER_PASS
	p.add_child(sc)
	var g := GridContainer.new()
	g.columns = 5
	g.mouse_filter = Control.MOUSE_FILTER_PASS
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	sc.add_child(g)
	return g



func _label(t: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l

func _set_info(msg: String, temporary := false) -> void:
	if info_l == null:
		return
	info_l.text = msg
	_info_t = 4.0 if temporary else 0.0


func show_window() -> void:
	open = true
	visible = true
	pending = []
	_near_chest = _find_near_chest()
	_rebuild()
	_fit_panes.call_deferred()


## Ячейки источника side ("bag" — сумка, "chest" — сундук дома): [{id, n, dur} или null].
func _src_items(side: String) -> Array:
	var out: Array = []
	if side == "chest":
		if _near_chest:
			for it in _near_chest.contents:
				out.append({"id": String(it.get(0)), "n": int(it.get(1)), "dur": float(it.get(2)) if it.size() > 2 else -1.0})
		return out
	for eq_slot in game.inv.EQUIP:
		var eid: String = game.inv.equip.get(eq_slot, "")
		if eid != "":
			out.append({"id": eid, "n": 1, "dur": game.inv.get_dur(eq_slot), "eq_slot": eq_slot})
	for i in game.inv.slots.size():
		var s = game.inv.slots[i]
		if s != null:
			out.append({"id": String(s["id"]), "n": int(s["n"]), "dur": float(s.get("dur", -1.0)), "slot": i})
	return out


## Забрать n штук из ячейки idx источника. Возвращает, сколько взято.
func _take_src(side: String, idx: int, n: int) -> int:
	if side == "chest":
		if _near_chest == null or idx >= _near_chest.contents.size():
			return 0
		var it: Array = _near_chest.contents[idx]
		var k := mini(n, int(it[1]))
		it[1] = int(it[1]) - k
		if int(it[1]) <= 0:
			_near_chest.contents.remove_at(idx)
		return k
	var bag := _src_items("bag")
	if idx >= bag.size():
		return 0
	var item: Dictionary = bag[idx]
	if item.has("eq_slot"):
		var eq_slot := String(item["eq_slot"])
		game.inv.equip[eq_slot] = ""
		game.inv.equip_dur.erase(eq_slot)
		game._apply_equip(eq_slot)
		game.inv.notify()
		return 1
	var got: Array = game.inv.take_at(int(item["slot"]), n)
	return int(got.get(1))


## Вернуть в источник. Возвращает, сколько не влезло (в сундук влезает всё).
func _give_src(side: String, id: String, n: int, dur: float) -> int:
	if side == "chest" and _near_chest:
		var cont: Array = _near_chest.contents
		var mx: int = int(Items.ITEMS[id].get("stack", 1))
		var no_dur := Items.max_dur(id) <= 0.0 and dur < 0.0
		if no_dur and mx > 1:
			for it in cont:
				if String(it[0]) == id and (it.size() <= 2 or float(it[2]) < 0.0) and int(it[1]) < mx:
					var add := mini(n, mx - int(it[1]))
					it[1] = int(it[1]) + add
					n -= add
					if n <= 0:
						return 0
		var occ := {}
		var max_h := 5
		for it in cont:
			var p := int(it[3]) if it.size() > 3 and int(it[3]) >= 0 else 0
			var d := Items.size_of(String(it[0]))
			if it.size() > 4 and bool(it[4]):
				d = Vector2i(d.y, d.x)
			@warning_ignore("integer_division")
			var pos := Vector2i(p % 10, p / 10)
			max_h = maxi(max_h, pos.y + d.y)
			for yy in d.y:
				for xx in d.x:
					occ[pos + Vector2i(xx, yy)] = true
		while n > 0:
			var take := mini(n, mx)
			var base_d := Items.size_of(id)
			var placed := false
			for h_lim in [max_h, 100]:
				for rot in ([false, true] if base_d.x != base_d.y else [false]):
					var dd := Vector2i(base_d.y, base_d.x) if rot else base_d
					for y in maxi(h_lim - dd.y + 1, 0):
						for x in maxi(10 - dd.x + 1, 0):
							var ok := true
							for yy in dd.y:
								for xx in dd.x:
									if occ.has(Vector2i(x + xx, y + yy)):
										ok = false
										break
								if not ok:
									break
							if ok:
								for yy in dd.y:
									for xx in dd.x:
										occ[Vector2i(x + xx, y + yy)] = true
								cont.append([id, take, dur, y * 10 + x, rot])
								max_h = maxi(max_h, y + dd.y)
								placed = true
								break
						if placed:
							break
					if placed:
						break
				if placed:
					break
			n -= take
		return 0
	var eq_slot: String = Items.equip_slot(id)
	if n == 1 and eq_slot != "" and eq_slot != "hand" and game.inv.equip.get(eq_slot, "") == "":
		game.inv.equip[eq_slot] = id
		if dur >= 0.0:
			game.inv.equip_dur[eq_slot] = dur
		game._apply_equip(eq_slot)
		game.inv.notify()
		return 0
	return game.inv.add(id, n, dur)




## Закрыть: что не продано — обратно, откуда взято; не влезло в сумку — на пол.
func close() -> void:
	if not open:
		return
	open = false
	visible = false
	for it in pending:
		var left: int = _give_src(String(it[3]), String(it[0]), int(it[1]), float(it[2]))
		if left > 0:
			var fwd: Vector3 = -game.player.global_transform.basis.z
			var p = game._make_pickup(String(it[0]), left, game.player.global_position + Vector3(0, 1.2, 0) + fwd * 0.5, fwd * 2.0 + Vector3(0, 1.0, 0))
			p.need_leave = true
			if float(it[2]) >= 0.0:
				p.set_meta("dur", float(it[2]))
			game.hud.toast("Нет места — %s на полу" % Items.item_name(String(it[0])))
	pending = []
	if shop:
		shop._refresh()

func pick_bag_slot(slot_idx: int, qty_mode: int) -> void:
	var s = game.inv.slots[slot_idx]
	if s == null:
		return
	var id := String(s["id"])
	if market(id) <= 0:
		_set_info(TRASH_MSG if id in TRASH else "%s магазин не берёт" % Items.item_name(id), true)
		game.play_ui("buzz", -14.0)
		return
	var total_n := int(s["n"])
	if qty_mode == 0 and total_n > 1:
		_ask_qty(id, total_n, func(cnt: int) -> void:
			_do_pick_bag(slot_idx, cnt))
		return
	_do_pick_bag(slot_idx, 1 if qty_mode == 1 else total_n)

func _do_pick_bag(slot_idx: int, cnt: int) -> void:
	var s = game.inv.slots[slot_idx]
	if s == null or cnt <= 0:
		return
	var id := String(s["id"])
	var dur := float(s.get("dur", -1.0))
	var got: Array = game.inv.take_at(slot_idx, mini(cnt, int(s["n"])))
	if int(got.get(1)) > 0:
		_add_pending(id, int(got.get(1)), dur, "bag")
		game.play_ui("click", -16.0, 1.2)
		_set_info(DEFAULT_INFO)
		_rebuild()

func pick_equip_slot(eq_slot: String) -> void:
	var id: String = game.inv.equip.get(eq_slot, "")
	if id == "":
		return
	if market(id) <= 0:
		_set_info(TRASH_MSG if id in TRASH else "%s магазин не берёт" % Items.item_name(id), true)
		game.play_ui("buzz", -14.0)
		return

	# Если снимаем рюкзак/куртку/штаны — сначала переносим все продаваемые вещи из этого блока на продажу
	for b in Inv.BLOCKS.size():
		if Inv.BLOCKS[b][3] == eq_slot:
			for i in game.inv.TOTAL:
				var s = game.inv.slots[i]
				if s != null and game.inv.cell_block(i) == b:
					var item_id := String(s["id"])
					if market(item_id) > 0:
						var item_dur := float(s.get("dur", -1.0))
						var got: Array = game.inv.take_at(i, int(s["n"]))
						if int(got.get(1)) > 0:
							_add_pending(item_id, int(got.get(1)), item_dur, "bag")

	var dur := float(game.inv.get_dur(eq_slot))
	game.inv.equip[eq_slot] = ""
	game.inv.equip_dur.erase(eq_slot)
	game._apply_equip(eq_slot)
	game.inv.notify()
	_add_pending(id, 1, dur, "bag")
	game.play_ui("click", -16.0, 1.2)
	_set_info(DEFAULT_INFO)
	_rebuild()


func pick_chest_idx(idx: int, qty_mode: int) -> void:
	if _near_chest == null or idx >= _near_chest.contents.size():
		return
	var it: Array = _near_chest.contents[idx]
	var id := String(it.get(0))
	if market(id) <= 0:
		_set_info(TRASH_MSG if id in TRASH else "%s магазин не берёт" % Items.item_name(id), true)
		game.play_ui("buzz", -14.0)
		return
	var total_n := int(it.get(1))
	if qty_mode == 0 and total_n > 1:
		_ask_qty(id, total_n, func(cnt: int) -> void:
			_do_pick_chest(idx, cnt))
		return
	_do_pick_chest(idx, 1 if qty_mode == 1 else total_n)

func _do_pick_chest(idx: int, cnt: int) -> void:
	if _near_chest == null or idx >= _near_chest.contents.size() or cnt <= 0:
		return
	var it: Array = _near_chest.contents[idx]
	var id := String(it.get(0))
	var dur := float(it.get(2)) if it.size() > 2 else -1.0
	var got := _take_src("chest", idx, mini(cnt, int(it.get(1))))
	if got > 0:
		_add_pending(id, got, dur, "chest")
		game.play_ui("click", -16.0, 1.2)
		_set_info(DEFAULT_INFO)
		_rebuild()


func _ask_qty(id: String, max_n: int, on_confirm: Callable) -> void:
	if _qty_popup == null:
		_qty_popup = PopupPanel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.09, 0.07, 0.05, 0.98)
		sb.border_color = Color(0.85, 0.55, 0.25, 0.9)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(4)
		sb.set_content_margin_all(10)
		_qty_popup.add_theme_stylebox_override("panel", sb)
		add_child(_qty_popup)

		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 6)
		_qty_popup.add_child(vb)

		_qty_val_l = _label("", 14, Color(0.95, 0.88, 0.7))
		_qty_val_l.custom_minimum_size = Vector2.ZERO
		_qty_val_l.autowrap_mode = TextServer.AUTOWRAP_OFF
		vb.add_child(_qty_val_l)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		vb.add_child(row)

		_qty_slider = HSlider.new()
		_qty_slider.custom_minimum_size = Vector2(120, 22)
		_qty_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_qty_slider.min_value = 1
		_qty_slider.step = 1
		row.add_child(_qty_slider)

		_qty_spin = SpinBox.new()
		_qty_spin.custom_minimum_size = Vector2(72, 24)
		_qty_spin.min_value = 1
		_qty_spin.step = 1
		_qty_spin.rounded = true
		row.add_child(_qty_spin)

		# Двусторонняя синхронизация ползунка и числового поля
		_qty_slider.value_changed.connect(func(v: float) -> void:
			if int(_qty_spin.value) != int(v):
				_qty_spin.value = int(v))
		_qty_spin.value_changed.connect(func(v: float) -> void:
			if int(_qty_slider.value) != int(v):
				_qty_slider.value = int(v))

		# Подтверждение по нажатию Enter прямо в поле ввода числа
		_qty_spin.get_line_edit().text_submitted.connect(func(_t: String) -> void:
			_qty_spin.apply()
			_qty_popup.hide()
			if _qty_cb.is_valid():
				_qty_cb.call(int(_qty_spin.value)))

		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 6)
		vb.add_child(hb)
		var ok_b := _button("Продать", func() -> void:
			_qty_spin.apply()
			_qty_popup.hide()
			if _qty_cb.is_valid():
				_qty_cb.call(int(_qty_spin.value)))
		ok_b.add_theme_font_size_override("font_size", 13)
		hb.add_child(ok_b)
		var cancel_b := _button("Отмена", func() -> void:
			_qty_popup.hide())
		cancel_b.add_theme_font_size_override("font_size", 13)
		hb.add_child(cancel_b)

	_qty_cb = on_confirm
	_qty_slider.max_value = max_n
	_qty_spin.max_value = max_n
	_qty_slider.value = max_n
	_qty_spin.value = max_n
	_qty_val_l.text = "%s (из %d)" % [Items.item_name(id), max_n]
	var mp := get_viewport().get_mouse_position()
	_qty_popup.position = Vector2i(mp) + Vector2i(10, 10)
	_qty_popup.reset_size()
	_qty_popup.popup()
	# Сразу ставим фокус в поле ввода и выделяем число, чтобы можно было печатать без клика
	var le := _qty_spin.get_line_edit()
	le.grab_focus()
	le.select_all()
	
func _rebuild() -> void:
	for s in doll_slots:
		s.inv = game.inv
		s.queue_redraw()
	for g in bag_grids:
		g.inv = game.inv
		g.refit()
		var d: Vector2i = game.inv.block_dim(g.b)
		var vis := d.x > 0 and d.y > 0
		g.get_parent().visible = vis
		if g.b < bag_labels.size():
			var eid := String(game.inv.equip.get(Inv.BLOCKS[g.b][3], ""))
			bag_labels[g.b].text = "%s %d×%d" % [Items.item_name(eid).to_upper() if eid != "" else Inv.BLOCKS[g.b][4], d.x, d.y]
	_near_chest = _find_near_chest()
	var has_chest := _near_chest != null
	if chest_lbl:
		chest_lbl.visible = has_chest
	if chest_grid:
		chest_grid.visible = has_chest
		if has_chest:
			chest_grid.refit()
	for c in sell_grid.get_children():
		sell_grid.remove_child(c)
		c.queue_free()
	for i in maxi(pending.size(), 25):
		var c := Cell.new()
		c.sw = self
		c.side = "sell"
		c.idx = i
		if i < pending.size():
			c.id = String(pending[i][0])
			c.n = int(pending[i][1])
			c.dur = float(pending[i][2])
			c.price = unit_price(c.id, c.dur) * c.n
		sell_grid.add_child(c)
	total_l.text = "Сумма: %d монет   (в кошельке %d)" % [_total(), game.inv.count("coin")]
	sell_b.disabled = pending.is_empty()

func _total() -> int:
	var t := 0
	for it in pending:
		t += unit_price(String(it[0]), float(it[2])) * int(it[1])
	return t


## Переложить из колонки side (ячейка idx): вся стопка или одна штука.
func click(side: String, idx: int, one: bool, to := "") -> void:
	if side != "sell":
		var items := _src_items(side)
		var s = items[idx] if idx < items.size() else null
		if s == null:
			return
		var id: String = s["id"]
		if market(id) <= 0:
			_set_info(TRASH_MSG if id in TRASH else "%s магазин не берёт" % Items.item_name(id), true)
			game.play_ui("buzz", -14.0)
			return
		var dur := float(s["dur"])
		var got := _take_src(side, idx, 1 if one else int(s["n"]))
		if got <= 0:
			return
		_add_pending(id, got, dur, side)
	else:
		if idx >= pending.size():
			return
		var it: Array = pending[idx]
		var dest: String = to if to == "bag" or to == "chest" else String(it[3])
		var want := 1 if one else int(it[1])
		var left: int = _give_src(dest, String(it[0]), want, float(it[2]))
		var moved := want - left
		if moved <= 0:
			info_l.text = "Нет места"
			return
		it[1] = int(it[1]) - moved
		if int(it[1]) <= 0:
			pending.remove_at(idx)
	game.play_ui("click", -16.0, 1.2)
	info_l.text = DEFAULT_INFO
	_rebuild()


func _add_pending(id: String, n: int, dur: float, from: String) -> void:
	if dur < 0.0:
		var mx: int = Items.ITEMS[id]["stack"]
		for it in pending:
			if it[0] == id and float(it[2]) < 0.0 and int(it[1]) < mx and it[3] == from:
				var take := mini(n, mx - int(it[1]))
				it[1] = int(it[1]) + take
				n -= take
				if n <= 0:
					return
	pending.append([id, n, dur, from])


func sell_all() -> void:
	var t := _total()
	if pending.is_empty():
		info_l.text = "Положи вещи справа — в «На продажу»"
		return
	var n := 0
	for it in pending:
		n += int(it[1])
	pending = []
	game.inv.add("coin", t)
	info_l.text = "Продано %d шт. — +%d монет" % [n, t]
	game.play_ui("coin", -9.0, 1.1)
	_rebuild()
	if shop:
		shop._refresh()


func _input(e: InputEvent) -> void:
	if not open:
		return
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_SPACE:
		if get_viewport().gui_is_dragging():
			get_viewport().set_input_as_handled()
			var dd = get_viewport().gui_get_drag_data()
			if dd is Dictionary and dd.has("inv_key") and game.inv.drag_key != null:
				game.inv.rotate_drag()
				for g in bag_grids:
					g.hint = []
					g.queue_redraw()
			return
	if e.is_action_pressed("ui_cancel") or e.is_action_pressed("interact") or e.is_action_pressed("inventory"):
		get_viewport().set_input_as_handled()
		close()


func _process(delta: float) -> void:
	if not open:
		return
	if _info_t > 0.0:
		_info_t -= delta
		if _info_t <= 0.0 and info_l != null:
			info_l.text = DEFAULT_INFO
	if left_scroll == null:
		return
	var sb_v := left_scroll.get_v_scroll_bar()
	if sb_v == null:
		return
	var mp := get_viewport().get_mouse_position()
	var near_bar := sb_v.get_global_rect().grow(36.0).has_point(mp)
	var target_a := 1.0 if near_bar else 0.02
	sb_v.modulate.a = lerpf(sb_v.modulate.a, target_a, clampf(delta * 12.0, 0.0, 1.0))	
