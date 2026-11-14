extends CanvasLayer
## Окно продажи в Trinkets Market (промпт 14.11 18:06): слева сумка, справа «на продажу».
## Клик — переложить стопку в другую колонку, Shift+клик — одну штуку, можно перетаскивать мышью.
## Внизу сумма и «Продать всё». Закрыл, не продав, — вещи возвращаются в сумку (не влезли — падают на пол).
##
## Цена продажи = ceil(рыночная / 2) за штуку, у вещей с износом (оружие, одежда, ремкомплекты) — ещё × доля прочности.
## Рыночная — цена в магазине (Weapons.SHOP, shop.gd: CONSUMABLES). У хлама, которого в магазине нет,
## рыночная = 2 × прежняя «цена скупки» (поле price в items.gd), так что за него дают те же 2/3/3/5.
## Монеты и квестовые вещи (car_key и всё с "quest") не продаются.

const Items := preload("res://items.gd")
const Weapons := preload("res://weapons.gd")
## рыночные цены вещей, которых нет в магазине и которые не хлам
const EXTRA_MARKET := {"wood": 2, "glass": 2, "wallet": 10, "knuckles": 30}
const NO_SELL := ["coin", "car_key"]

var game
var shop                        # shop.gd — пересобрать его после продажи
var open := false
var pending: Array = []         # [[id, n, прочность или -1], ...]
var bag_grid: GridContainer
var sell_grid: GridContainer
var total_l: Label
var info_l: Label
var sell_b: Button


## Рыночная цена (0 — не продаётся).
static func market(id: String) -> int:
	if id in NO_SELL or not Items.ITEMS.has(id) or Items.ITEMS[id].get("quest", false):
		return 0
	for e in Weapons.SHOP:
		if e[0] == id:
			return int(e[1])
	for e in preload("res://shop.gd").CONSUMABLES:
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
	var fr := 1.0 if mx <= 0.0 or dur < 0.0 else clampf(dur / mx, 0.0, 1.0)
	return maxi(1, ceili(m * fr / 2.0))


class Cell extends Button:
	const Items := preload("res://items.gd")
	var sw
	var side := "bag"            # bag — сумка, sell — на продажу
	var idx := 0
	var id := ""
	var n := 0
	var dur := -1.0
	var price := 0               # для колонки «на продажу» — сумма за стопку
	var dim := false             # в сумке: не продаётся

	func _ready() -> void:
		custom_minimum_size = Vector2(70, 70)
		focus_mode = Control.FOCUS_NONE
		if id != "":
			tooltip_text = Items.item_name(id) + ("" if dim else "\nПродать: %d за шт." % sw.unit_price(id, dur))

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
		if dim:
			draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and id != "":
			sw.click(side, idx, e.shift_pressed)
			accept_event()

	func _get_drag_data(_at: Vector2) -> Variant:
		if id == "" or dim:
			return null
		var pv := Label.new()
		pv.text = Items.item_name(id)
		set_drag_preview(pv)
		return {"sw_side": side, "idx": idx}

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("sw_side") and data["sw_side"] != side

	func _drop_data(_at: Vector2, data: Variant) -> void:
		sw.click(data["sw_side"], data["idx"], false)


class Pane extends PanelContainer:
	var sw
	var side := "bag"

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("sw_side") and data["sw_side"] != side

	func _drop_data(_at: Vector2, data: Variant) -> void:
		sw.click(data["sw_side"], data["idx"], false)


func _ready() -> void:
	layer = 6
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cc)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.06, 0.05, 0.97)
	sb.border_color = Color(0.6, 0.3, 0.15, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", sb)
	cc.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	v.add_child(_label("ПРОДАЖА", 30, Color(1.0, 0.6, 0.35)))
	v.add_child(_label("Магазин берёт вещи за полцены от своей цены (с округлением вверх), побитые — дешевле.", 15, Color(0.65, 0.63, 0.58)))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	v.add_child(cols)
	var bc := VBoxContainer.new()
	cols.add_child(bc)
	bc.add_child(_label("СУМКА", 24, Color(0.86, 0.85, 0.8)))
	bag_grid = _pane(bc, "bag")
	var sc := VBoxContainer.new()
	cols.add_child(sc)
	sc.add_child(_label("НА ПРОДАЖУ", 24, Color(1.0, 0.82, 0.4)))
	sell_grid = _pane(sc, "sell")
	total_l = _label("", 22, Color(0.92, 0.8, 0.5))
	v.add_child(total_l)
	info_l = _label("Клик — переложить стопку, Shift+клик — одну штуку, можно перетаскивать.", 15, Color(0.7, 0.68, 0.62))
	v.add_child(info_l)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	v.add_child(hb)
	sell_b = _button("Продать всё", sell_all)
	hb.add_child(sell_b)
	hb.add_child(_button("Закрыть (Esc)", close))


func _button(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(cb)
	return b


func _pane(parent: Control, side: String) -> GridContainer:
	var p := Pane.new()
	p.sw = self
	p.side = side
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0, 0, 0, 0.3)
	st.set_content_margin_all(6)
	p.add_theme_stylebox_override("panel", st)
	p.custom_minimum_size = Vector2(5 * 76, 3 * 76)
	parent.add_child(p)
	var g := GridContainer.new()
	g.columns = 5
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	p.add_child(g)
	return g


func _label(t: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(5 * 76 * 2 + 24, 0) if size < 20 else Vector2.ZERO
	return l


func show_window() -> void:
	open = true
	visible = true
	pending = []
	_rebuild()


## Закрыть: что не продано — обратно в сумку, не влезло — на пол.
func close() -> void:
	if not open:
		return
	open = false
	visible = false
	for it in pending:
		var left: int = game.inv.add(String(it[0]), int(it[1]), float(it[2]))
		if left > 0:
			var fwd: Vector3 = -game.player.global_transform.basis.z
			var p = game._make_pickup(String(it[0]), left, game.player.global_position + Vector3(0, 1.2, 0) + fwd * 0.5, fwd * 2.0 + Vector3(0, 1.0, 0))
			p.need_leave = true
			if float(it[2]) >= 0.0:
				p.set_meta("dur", float(it[2]))
			game.hud.toast("Сумка полна — %s на полу" % Items.item_name(String(it[0])))
	pending = []
	if shop:
		shop._refresh()


func _total() -> int:
	var t := 0
	for it in pending:
		t += unit_price(String(it[0]), float(it[2])) * int(it[1])
	return t


## Переложить из колонки side (ячейка idx): вся стопка или одна штука.
func click(side: String, idx: int, one: bool) -> void:
	if side == "bag":
		var s = game.inv.slots[idx] if idx < game.inv.slots.size() else null
		if s == null:
			return
		var id: String = s["id"]
		if market(id) <= 0:
			info_l.text = "%s магазин не берёт" % Items.item_name(id)
			game.play_ui("buzz", -14.0)
			return
		var dur := float(s.get("dur", -1.0))
		var got: Array = game.inv.take_at(idx, 1 if one else int(s["n"]))
		if int(got[1]) <= 0:
			return
		_add_pending(id, int(got[1]), dur)
	else:
		if idx >= pending.size():
			return
		var it: Array = pending[idx]
		var want := 1 if one else int(it[1])
		var left: int = game.inv.add(String(it[0]), want, float(it[2]))
		var moved := want - left
		if moved <= 0:
			info_l.text = "Сумка полна"
			return
		it[1] = int(it[1]) - moved
		if int(it[1]) <= 0:
			pending.remove_at(idx)
	game.play_ui("click", -16.0, 1.2)
	_rebuild()


func _add_pending(id: String, n: int, dur: float) -> void:
	if dur < 0.0:
		var mx: int = Items.ITEMS[id]["stack"]
		for it in pending:
			if it[0] == id and float(it[2]) < 0.0 and int(it[1]) < mx:
				var take := mini(n, mx - int(it[1]))
				it[1] = int(it[1]) + take
				n -= take
				if n <= 0:
					return
	pending.append([id, n, dur])


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


func _rebuild() -> void:
	for g in [bag_grid, sell_grid]:
		for c in g.get_children():
			g.remove_child(c)
			c.queue_free()
	for i in game.inv.slots.size():
		var c := Cell.new()
		c.sw = self
		c.side = "bag"
		c.idx = i
		var s = game.inv.slots[i]
		if s != null:
			c.id = String(s["id"])
			c.n = int(s["n"])
			c.dur = float(s.get("dur", -1.0))
			c.dim = market(c.id) <= 0
		bag_grid.add_child(c)
	for i in maxi(pending.size(), 10):
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


func _input(e: InputEvent) -> void:
	if open and (e.is_action_pressed("ui_cancel") or e.is_action_pressed("interact") or e.is_action_pressed("inventory")):
		get_viewport().set_input_as_handled()
		close()
