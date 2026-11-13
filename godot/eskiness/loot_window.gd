extends CanvasLayer
## Общее окно лута и хранилища (промпты 00:07, 00:08).
##   Лут (сейф, ящик, кувшин, колба…): сетка содержимого; клик — взять, R / «Забрать всё» — всё сразу.
##   Сундук-хранилище (chest.gd, kind = "storage"): две колонки «СУНДУК | СУМКА». Клик — переложить стопку
##   в другую колонку, Shift+клик — одну штуку, можно перетаскивать мышью между колонками.
## E / Esc / Tab — закрыть. Игра не на паузе.
##
## API для других скриптов (game.gd):
##   game.open_loot(obj) — obj с полем contents: Array [[id, n(, прочность)], ...] (и, по желанию, loot_title);
##   game.open_loot_items(items, pos, title) — разовый лут (разбитый кувшин): что не взяли — выпадет на пол в pos.

const Items := preload("res://items.gd")
const STORAGE_SLOTS := 20

var game
var src                        # объект с contents
var open := false
var storage := false
var src_grid: GridContainer
var bag_grid: GridContainer
var bag_col: VBoxContainer
var title: Label
var info: Label
var all_b: Button
var _opened_at := 0


## Разовый лут без своего объекта: после закрытия остаток высыпается на пол.
class LootBag extends RefCounted:
	var contents: Array = []
	var loot_title := "ЛУТ"
	var pos := Vector3.ZERO
	var game

	func on_loot_closed() -> void:
		for it in contents:
			game.spawn_loot(String(it[0]), int(it[1]), pos + Vector3(0, 0.4, 0), Vector3(0, 2.0, 0), 0.8)
		contents = []


## Клетка с предметом: клик / Shift+клик / перетаскивание в другую колонку.
class Cell extends Button:
	const Items := preload("res://items.gd")
	var lw
	var side := "src"            # src — содержимое, bag — сумка игрока
	var idx := 0
	var id := ""
	var n := 0

	func _ready() -> void:
		custom_minimum_size = Vector2(70, 70)
		focus_mode = Control.FOCUS_NONE
		tooltip_text = Items.item_name(id)

	func _draw() -> void:
		if id == "":
			return
		Items.draw_icon(self, id, Rect2(Vector2(10, 10), size - Vector2(20, 20)))
		if n > 1:
			var f := ThemeDB.fallback_font
			draw_string_outline(f, Vector2(4, size.y - 6), str(n), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 9, 16, 4, Color(0, 0, 0, 0.8))
			draw_string(f, Vector2(4, size.y - 6), str(n), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 9, 16, Color(0.92, 0.9, 0.84))

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and id != "":
			lw.click(side, idx, e.shift_pressed)
			accept_event()

	func _get_drag_data(_at: Vector2) -> Variant:
		if id == "" or not lw.storage:
			return null
		var pv := Label.new()
		pv.text = Items.item_name(id)
		set_drag_preview(pv)
		return {"lw_side": side, "idx": idx}

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("lw_side") and data["lw_side"] != side

	func _drop_data(_at: Vector2, data: Variant) -> void:
		lw.click(data["lw_side"], data["idx"], false)


## Колонка: бросить сюда предмет из другой колонки.
class Pane extends PanelContainer:
	var lw
	var side := "src"

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("lw_side") and data["lw_side"] != side

	func _drop_data(_at: Vector2, data: Variant) -> void:
		lw.click(data["lw_side"], data["idx"], false)


func _ready() -> void:
	layer = 4
	visible = false
	if not InputMap.has_action("loot_all"):
		InputMap.add_action("loot_all")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_R
		InputMap.action_add_event("loot_all", ev)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cc)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.065, 0.05, 0.95)
	sb.border_color = Color(0.7, 0.5, 0.25, 0.7)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", sb)
	cc.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	v.add_child(cols)
	var sc := VBoxContainer.new()
	cols.add_child(sc)
	title = _label("", 28, Color(0.95, 0.8, 0.5))
	sc.add_child(title)
	src_grid = _pane(sc, "src")
	bag_col = VBoxContainer.new()
	cols.add_child(bag_col)
	bag_col.add_child(_label("СУМКА", 28, Color(0.86, 0.85, 0.8)))
	bag_grid = _pane(bag_col, "bag")
	info = _label("", 15, Color(0.7, 0.68, 0.62))
	v.add_child(info)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	v.add_child(hb)
	all_b = Button.new()
	all_b.text = "Забрать всё (R)"
	all_b.focus_mode = Control.FOCUS_NONE
	all_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	all_b.add_theme_font_size_override("font_size", 20)
	all_b.pressed.connect(take_all)
	hb.add_child(all_b)
	var close_b := Button.new()
	close_b.text = "Закрыть"
	close_b.focus_mode = Control.FOCUS_NONE
	close_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_b.add_theme_font_size_override("font_size", 20)
	close_b.pressed.connect(close)
	hb.add_child(close_b)


func _label(t: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _pane(parent: Control, side: String) -> GridContainer:
	var p := Pane.new()
	p.lw = self
	p.side = side
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0, 0, 0, 0.3)
	st.set_content_margin_all(6)
	p.add_theme_stylebox_override("panel", st)
	p.custom_minimum_size = Vector2(5 * 76, 2 * 76)
	parent.add_child(p)
	var g := GridContainer.new()
	g.columns = 5
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	p.add_child(g)
	return g


func show_for(c) -> void:
	src = c
	open = true
	visible = true
	_opened_at = Time.get_ticks_msec()
	storage = c.get("kind") == "storage"
	var t = c.get("loot_title")
	if t == null or String(t) == "":
		t = "СУНДУК" if storage else ("СЕЙФ" if c.get("kind") == "safe" else "ЯЩИК")
	title.text = String(t)
	bag_col.visible = storage
	all_b.visible = true
	info.text = "Клик — переложить стопку · Shift+клик — одну · можно перетаскивать · R — забрать всё · E / Esc — закрыть" if storage \
		else "Клик — взять · R — забрать всё · E / Esc — закрыть"
	game.player.active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_rebuild()


func close() -> void:
	if not open:
		return
	open = false
	visible = false
	if src and src.has_method("on_loot_closed"):
		src.on_loot_closed()
	src = null
	if game and game.player and game.alive:
		game.player.active = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(e: InputEvent) -> void:
	if not open:
		return
	if e.is_action_pressed("loot_all"):
		get_viewport().set_input_as_handled()
		take_all()
	elif e.is_action_pressed("ui_cancel") or e.is_action_pressed("inventory") \
			or (e.is_action_pressed("interact") and not e.is_echo() and Time.get_ticks_msec() - _opened_at > 250):
		get_viewport().set_input_as_handled()
		close()


func _rebuild() -> void:
	for ch in src_grid.get_children():
		ch.queue_free()
	for ch in bag_grid.get_children():
		ch.queue_free()
	if src == null:
		return
	var cont: Array = src.contents
	var shown := cont.size()
	if storage:
		shown = STORAGE_SLOTS
	elif cont.is_empty():
		src_grid.add_child(_label("Пусто", 20, Color(0.6, 0.58, 0.54)))
	for i in shown:
		var c := Cell.new()
		c.lw = self
		c.side = "src"
		c.idx = i
		if i < cont.size():
			c.id = String(cont[i][0])
			c.n = int(cont[i][1])
		src_grid.add_child(c)
	if storage:
		for i in game.inv.slots.size():
			var c := Cell.new()
			c.lw = self
			c.side = "bag"
			c.idx = i
			var s = game.inv.slots[i]
			if s != null:
				c.id = String(s["id"])
				c.n = int(s["n"])
			bag_grid.add_child(c)


## Клик по клетке: из содержимого — в сумку, из сумки — в сундук.
func click(side: String, i: int, one: bool) -> void:
	if side == "src":
		take(i, one)
	else:
		put(i, one)


## Взять позицию i (или одну штуку). Что не влезло — остаётся.
func take(i: int, one := false) -> void:
	if src == null or i >= src.contents.size():
		return
	var it: Array = src.contents[i]
	var want := 1 if one else int(it[1])
	var dur := float(it[2]) if it.size() > 2 else -1.0
	var left: int = game.inv.add(String(it[0]), want, dur)
	var got := want - left
	if got <= 0:
		game.hud.toast("Сумка полна", Color(0.9, 0.5, 0.4))
		return
	it[1] = int(it[1]) - got
	if int(it[1]) <= 0:
		src.contents.remove_at(i)
	game.play_ui("coin" if it[0] == "coin" else "pickup", -13.0)
	_rebuild()


## Положить из сумки (ячейка i) в сундук-хранилище.
func put(i: int, one := false) -> void:
	if not storage or src == null:
		return
	var s = game.inv.slots[i]
	if s == null:
		return
	var id: String = s["id"]
	var dur := float(s.get("dur", -1.0))
	var cnt := 1 if one else int(s["n"])
	var mx: int = Items.ITEMS[id]["stack"]
	var cont: Array = src.contents
	var left := cnt
	if dur < 0.0:
		for it in cont:
			if left > 0 and it[0] == id and it.size() < 3 and int(it[1]) < mx:
				var add := mini(left, mx - int(it[1]))
				it[1] = int(it[1]) + add
				left -= add
	while left > 0 and cont.size() < STORAGE_SLOTS:
		var add := mini(left, mx)
		cont.append([id, add, dur] if dur >= 0.0 else [id, add])
		left -= add
	var moved := cnt - left
	if moved <= 0:
		game.hud.toast("Сундук полон", Color(0.9, 0.5, 0.4))
		return
	game.inv.take_at(i, moved)
	game.play_ui("pickup", -14.0, 0.9)
	_rebuild()


func take_all() -> void:
	if src == null:
		return
	var i := 0
	while i < src.contents.size():
		var before: int = src.contents.size()
		var n_before: int = int(src.contents[i][1])
		take(i)
		if src.contents.size() == before and int(src.contents[i][1]) == n_before:
			i += 1      # не влезло — дальше
		elif src.contents.size() == before:
			i += 1
	if src.contents.is_empty() and not storage:
		close()
