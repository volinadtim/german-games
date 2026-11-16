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

var game
var shop                        # shop.gd — пересобрать его после продажи
var open := false
var pending: Array = []         # [[id, n, прочность или -1, откуда: "bag" | "chest"], ...]
var bag_grid: GridContainer
var chest_grid: GridContainer
var sell_grid: GridContainer
var total_l: Label
var info_l: Label
var sell_b: Button
var panel: PanelContainer
var cols: HBoxContainer
var panes := {}                 # side -> Pane (высоту подгоняем под экран, промпт 02:33)


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
	return maxi(1, ceili(m * fr / 2.0))


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

	func _ready() -> void:
		custom_minimum_size = Vector2(70, 70)
		focus_mode = Control.FOCUS_NONE
		if id != "":
			tooltip_text = Items.item_name(id) + (("\n" + sw.TRASH_MSG if id in sw.TRASH else "") if dim else "\nПродать: %d за шт." % sw.unit_price(id, dur))

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
		set_drag_preview(pv)
		return {"sw_side": side, "idx": idx}

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("sw_side") and (data["sw_side"] == "sell") != (side == "sell")

	func _drop_data(_at: Vector2, data: Variant) -> void:
		sw.click(data["sw_side"], data["idx"], false, side)


class Pane extends PanelContainer:
	var sw
	var side := "bag"

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("sw_side") and (data["sw_side"] == "sell") != (side == "sell")

	func _drop_data(_at: Vector2, data: Variant) -> void:
		sw.click(data["sw_side"], data["idx"], false, side)


func _ready() -> void:
	layer = 6
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent): preload("res://scripts/loot_window.gd")._click_away(dim, e, close))   # клик мимо — закрыть (промпт 02:15)
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
	preload("res://scripts/ui/ui_fit.gd").attach(panel)   # окно в рамках экрана (промпт 00:32)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	v.add_child(_label("ПРОДАЖА", 30, Color(1.0, 0.6, 0.35)))
	v.add_child(_label("Магазин берёт почти любые вещи за полцены от своей цены, округляя в твою пользу (вещь за 3 — продашь за 2). " +
		"Побитое оружие, одежда и начатые ремкомплекты — дешевле, по остатку прочности. Хлам (гайки, шестерёнки, фото) — по 2–5. " +
		"Не берёт монеты и ключ от машины — они затемнены.", 15, Color(0.65, 0.63, 0.58)))
	cols = HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	v.add_child(cols)
	var bc := VBoxContainer.new()
	cols.add_child(bc)
	bc.add_child(_label("СУМКА", 22, Color(0.86, 0.85, 0.8)))
	bag_grid = _pane(bc, "bag", 2)
	bc.add_child(_label("СУНДУК ДОМА", 22, Color(0.8, 0.72, 0.55)))
	chest_grid = _pane(bc, "chest", 2)
	var sc := VBoxContainer.new()
	cols.add_child(sc)
	sc.add_child(_label("НА ПРОДАЖУ", 24, Color(1.0, 0.82, 0.4)))
	sell_grid = _pane(sc, "sell", 5)
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
	get_viewport().size_changed.connect(_fit_panes)


## Высота колонок под экран (промпт 02:33): списки укорачиваются (внутри прокрутка),
## чтобы всё окно влезало по высоте; ui_fit дожимает масштабом, если и так не влезло.
func _fit_panes() -> void:
	if panel == null or not visible:
		return
	var vh := get_viewport().get_visible_rect().size.y * 0.9
	var sp: Control = panes["sell"]
	# всё, кроме колонок, + заголовок «НА ПРОДАЖУ» с отступом
	var over := panel.get_combined_minimum_size().y - cols.get_combined_minimum_size().y + 24.0 + 8.0
	var h := clampf(vh - over, 2.0 * 76.0 + 14.0, 5.0 * 76.0 + 3.0 * 30.0)
	sp.custom_minimum_size.y = h
	# слева две колонки с заголовками (по 22 px + отступы) — вместе не выше правой
	var lh := clampf((h + 24.0 - 2.0 * 30.0 - 12.0) * 0.5, 76.0 + 14.0, 2.0 * 76.0)
	for side in ["bag", "chest"]:
		(panes[side] as Control).custom_minimum_size.y = lh


func _button(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(cb)
	return b


func _pane(parent: Control, side: String, rows := 3) -> GridContainer:
	var p := Pane.new()
	p.sw = self
	p.side = side
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0, 0, 0, 0.3)
	st.set_content_margin_all(6)
	p.add_theme_stylebox_override("panel", st)
	p.custom_minimum_size = Vector2(5 * 76 + 14, rows * 76 + (rows - 2) * 30)   # фиксированно: больше — прокрутка (промпт 14.11 19:28)
	parent.add_child(p)
	panes[side] = p
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
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
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(5 * 76 * 2 + 24, 0) if size < 20 else Vector2.ZERO
	return l


func show_window() -> void:
	open = true
	visible = true
	pending = []
	_rebuild()
	_fit_panes.call_deferred()


## Ячейки источника side ("bag" — сумка, "chest" — сундук дома): [{id, n, dur} или null].
func _src_items(side: String) -> Array:
	var out: Array = []
	if side == "chest":
		if game.storage:
			for it in game.storage.contents:
				out.append({"id": String(it[0]), "n": int(it[1]), "dur": float(it[2]) if it.size() > 2 else -1.0})
		return out
	# сумка — сетка с предметами разного размера: показываем только сами предметы, slot — ячейка-якорь
	for i in game.inv.slots.size():
		var s = game.inv.slots[i]
		if s != null:
			out.append({"id": String(s["id"]), "n": int(s["n"]), "dur": float(s.get("dur", -1.0)), "slot": i})
	return out


## Забрать n штук из ячейки idx источника. Возвращает, сколько взято.
func _take_src(side: String, idx: int, n: int) -> int:
	if side == "chest":
		if game.storage == null or idx >= game.storage.contents.size():
			return 0
		var it: Array = game.storage.contents[idx]
		var k := mini(n, int(it[1]))
		it[1] = int(it[1]) - k
		if int(it[1]) <= 0:
			game.storage.contents.remove_at(idx)
		return k
	var bag := _src_items("bag")
	if idx >= bag.size():
		return 0
	var got: Array = game.inv.take_at(int(bag[idx]["slot"]), n)
	return int(got[1])


## Вернуть в источник. Возвращает, сколько не влезло (в сундук влезает всё).
func _give_src(side: String, id: String, n: int, dur: float) -> int:
	if side == "chest" and game.storage:
		if dur < 0.0:
			for it in game.storage.contents:
				if String(it[0]) == id and it.size() <= 2:
					it[1] = int(it[1]) + n
					return 0
		var e: Array = [id, n]
		if dur >= 0.0:
			e.append(dur)
		game.storage.contents.append(e)
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
func click(side: String, idx: int, one: bool, to := "") -> void:
	if side != "sell":
		var items := _src_items(side)
		var s = items[idx] if idx < items.size() else null
		if s == null:
			return
		var id: String = s["id"]
		if market(id) <= 0:
			info_l.text = TRASH_MSG if id in TRASH else "%s магазин не берёт" % Items.item_name(id)
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
			info_l.text = "Сумка полна"
			return
		it[1] = int(it[1]) - moved
		if int(it[1]) <= 0:
			pending.remove_at(idx)
	game.play_ui("click", -16.0, 1.2)
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


func _rebuild() -> void:
	for g in [bag_grid, chest_grid, sell_grid]:
		for c in g.get_children():
			g.remove_child(c)
			c.queue_free()
	for side in ["bag", "chest"]:
		var items := _src_items(side)
		for i in maxi(items.size(), 10):
			var c := Cell.new()
			c.sw = self
			c.side = side
			c.idx = i
			var s = items[i] if i < items.size() else null
			if s != null:
				c.id = String(s["id"])
				c.n = int(s["n"])
				c.dur = float(s["dur"])
				c.dim = market(c.id) <= 0
			(bag_grid if side == "bag" else chest_grid).add_child(c)
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
