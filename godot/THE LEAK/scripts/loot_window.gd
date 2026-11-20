extends CanvasLayer
## Общее окно лута и хранилища (промпты 00:07, 00:08; сетка и перетаскивание — промпт 16.11 05:05).
##   Слева — сумка игрока (те же сетки, что в инвентаре), справа — содержимое (ящик, сейф, кувшин, сундук дома)
##   тоже сеткой ячеек: предмет w×h занимает свои ячейки. Предметы перетаскиваются мышью куда угодно
##   (внутри, из содержимого в сумку и обратно, в конкретную ячейку), пробел при перетаскивании — поворот.
##   Shift+ЛКМ — переложить стопку целиком в другую сторону. R / кнопка — забрать всё. Обычный клик ничего не делает.
## E / Esc / Tab — закрыть. Игра не на паузе.
##
## Формат содержимого: contents — Array [[id, n(, прочность, ячейка, повёрнут)], ...]; прочность -1 — нет.
## Ячейка — y * ширина + x в сетке окна (у сундука 10×5, у лута 5×4+); без неё предмет кладётся в первое свободное место.
##
## API для других скриптов (game.gd):
##   game.open_loot(obj) — obj с полем contents (и, по желанию, loot_title);
##   game.open_loot_items(items, pos, title) — разовый лут (разбитый кувшин): что не взяли — выпадет на пол в pos.

const Items := preload("res://scripts/items.gd")
const Inv := preload("res://scripts/inventory.gd")
const CELL := 58.0
const STORAGE_W := 10    # сундук дома: 10×5 = 50 ячеек (прежний объём)
const STORAGE_H := 5
const LOOT_W := 5
const LOOT_H := 4

var game
var src                        # объект с contents
var open := false
var storage := false
var src_grid: SrcGrid
var src_scroll: ScrollContainer
var bag_grids: Array = []      # LwBag на каждый блок сумки
var title: Label
var all_b: Button
var _opened_at := 0
var press_pos := Vector2(-999, -999)
var gw := LOOT_W
var gh := LOOT_H
var drag_idx := -1             # тащим позицию содержимого
var drag_off := Vector2i.ZERO
var drag_rot := false
var drag_pv: Control = null
var bag_labels: Array = []
var bag_empty_l: Label
var doll_slots: Array = []
var _qty_popup: PopupPanel
var _qty_slider: HSlider
var _qty_spin: SpinBox
var _qty_val_l: Label
var _qty_cb: Callable



## Разовый лут без своего объекта: после закрытия остаток высыпается на пол.
class LootBag extends RefCounted:
	var contents: Array = []
	var loot_title := "ЛУТ"
	var pos := Vector3.ZERO
	var game

	func on_loot_closed() -> void:
		for it in contents:
			game.spawn_loot(String(it[0]), int(it[1]), pos + Vector3(0, 0.4, 0), Vector3(0, 2.0, 0), 0.8, true)
		contents = []


## Сетка содержимого (ящик / сундук).
class SrcGrid extends Control:
	const Items := preload("res://scripts/items.gd")
	const CELL := 58.0
	var lw
	var hint: Array = []     # Vector2i — куда ляжет тащимое
	var hint_ok := true

	func _ready() -> void:
		mouse_exited.connect(func():
			hint = []
			queue_redraw())

	func _notification(what: int) -> void:
		if what == NOTIFICATION_DRAG_END:
			hint = []
			queue_redraw()

	func cell_at(p: Vector2) -> Vector2i:
		var c := Vector2i(int(floor(p.x / CELL)), int(floor(p.y / CELL)))
		if c.x < 0 or c.y < 0 or c.x >= lw.gw or c.y >= lw.gh:
			return Vector2i(-1, -1)
		return c

	func _draw() -> void:
		var c: float = CELL
		draw_rect(Rect2(Vector2.ZERO, Vector2(lw.gw, lw.gh) * c), Color(0, 0, 0, 0.5))
		for x in lw.gw + 1:
			draw_line(Vector2(x * c, 0), Vector2(x * c, lw.gh * c), Color(1, 1, 1, 0.1), 1.0)
		for y in lw.gh + 1:
			draw_line(Vector2(0, y * c), Vector2(lw.gw * c, y * c), Color(1, 1, 1, 0.1), 1.0)
		if lw.src == null:
			return
		var f := ThemeDB.fallback_font
		for it in lw.src.contents:
			var id := String(it[0])
			var p: Vector2i = lw.e_pos(it)
			var r := Rect2(Vector2(p) * c, Vector2(lw.e_dim(it)) * c)
			draw_rect(r.grow(-1), Color(0.2, 0.17, 0.12, 0.35))
			draw_rect(r.grow(-1), Color(1, 1, 1, 0.2), false, 1.0)
			var side := minf(r.size.x, r.size.y) - 14.0
			Items.draw_icon(self, id, Rect2(r.get_center() - Vector2(side, side) / 2, Vector2(side, side)))
			var mx := Items.max_dur(id)
			var dur: float = lw.e_dur(it)
			if mx > 0.0 and dur >= 0.0 and not Items.ITEMS[id].has("rounds"):
				var fr := clampf(dur / mx, 0.0, 1.0)
				draw_rect(Rect2(r.position.x + 5, r.end.y - 8, r.size.x - 10, 4), Color(0, 0, 0, 0.6))
				draw_rect(Rect2(r.position.x + 5, r.end.y - 8, (r.size.x - 10) * fr, 4), Color(0.85, 0.25, 0.15).lerp(Color(0.45, 0.85, 0.35), fr))
			if int(it[1]) > 1:
				var tp := Vector2(r.position.x + 3, r.end.y - 10)
				draw_string_outline(f, tp, str(int(it[1])), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 8, 15, 4, Color(0, 0, 0, 0.8))
				draw_string(f, tp, str(int(it[1])), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 8, 15, Color(0.95, 0.88, 0.6))
		for h in hint:
			draw_rect(Rect2(Vector2(h) * c, Vector2(c, c)).grow(-2), Color(0.4, 0.9, 0.4, 0.3) if hint_ok else Color(0.95, 0.3, 0.2, 0.35))

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				lw.press_pos = e.position
			elif lw.press_pos.x >= 0.0 and e.position.distance_to(lw.press_pos) < 6.0:
				var i: int = lw.owner_at(cell_at(e.position))
				if i >= 0:
					if e.ctrl_pressed:
						lw.pick_src(i, -1)
					elif e.shift_pressed:
						lw.pick_src(i, 1)
					else:
						lw.pick_src(i, 0)
					accept_event()
				lw.press_pos = Vector2(-999, -999)


	func _get_drag_data(at: Vector2) -> Variant:
		var cell := cell_at(at)
		var i: int = lw.owner_at(cell)
		if i < 0:
			return null
		set_drag_preview(lw.begin_src_drag(i, cell - lw.e_pos(lw.src.contents[i])))
		return {"lw_src": i}

	func _can_drop_data(at: Vector2, data: Variant) -> bool:
		if not (data is Dictionary and (data.has("lw_src") or data.has("inv_key"))):
			return false
		var res: Array = lw.src_preview(data, cell_at(at))
		hint = res.get(0)
		hint_ok = res.get(1)
		queue_redraw()
		return true

	func _drop_data(at: Vector2, data: Variant) -> void:
		hint = []
		queue_redraw()
		lw.drop_on_src(data, cell_at(at))


## Сетка сумки — та же, что в инвентаре, плюс приём предметов из содержимого и Shift+ЛКМ.
class LwBag extends Inv.BagGrid:
	var lw

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				lw.press_pos = e.position
			elif lw.press_pos.x >= 0.0 and e.position.distance_to(lw.press_pos) < 6.0:
				var o: int = inv.owner_at(cell_at(e.position))
				if o >= 0:
					if e.ctrl_pressed:
						lw.pick_bag(o, -1)
					elif e.shift_pressed:
						lw.pick_bag(o, 1)
					else:
						lw.pick_bag(o, 0)
					accept_event()
				lw.press_pos = Vector2(-999, -999)


	func _can_drop_data(at: Vector2, data: Variant) -> bool:
		if data is Dictionary and data.has("lw_src"):
			var res: Array = lw.bag_preview(cell_at(at))
			hint = res[0]
			hint_ok = res[1]
			queue_redraw()
			return true
		return super(at, data)

	func _drop_data(at: Vector2, data: Variant) -> void:
		if data.has("lw_src"):
			hint = []
			queue_redraw()
			lw.drop_on_bag(cell_at(at))
			return
		super(at, data)
		lw.redraw()

class LwSlot extends Inv.Slot:
	var lw

	func _can_drop_data(at: Vector2, data: Variant) -> bool:
		if data is Dictionary and data.has("lw_src"):
			return true
		return super(at, data)

	func _drop_data(at: Vector2, data: Variant) -> void:
		if data is Dictionary and data.has("lw_src"):
			lw.drop_on_equip(String(key))
			return
		super(at, data)
		lw._rebuild()


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
	dim.gui_input.connect(func(e: InputEvent): _click_away(dim, e, close))   # клик мимо — закрыть (промпт 02:15)
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
	preload("res://scripts/ui/ui_fit.gd").attach(panel)   # окно в рамках экрана (промпт 00:32)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	v.add_child(cols)
	var doll := Inv.Doll.new()
	doll.custom_minimum_size = Vector2(192, 320)
	doll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	cols.add_child(doll)
	for k in Inv.EQUIP + ["hands"]:
		var s := LwSlot.new()
		s.lw = self
		s.inv = game.inv
		s.key = k
		s.px = 64.0
		s.position = Inv.HANDS2 if k == "hands" and doll_slots.size() >= Inv.EQUIP.size() else Inv.DOLL_POS[k]
		s.mirror = s.position.x < 1.0 and k in ["hands", "left"]
		doll.add_child(s)
		doll_slots.append(s)
	# сумка слева (промпт 14.11 16:43): основная сетка, под ней рюкзак и карманы
	var bc := VBoxContainer.new()
	bc.add_theme_constant_override("separation", 8)
	cols.add_child(bc)
	bc.add_child(_label("СНАРЯЖЕНИЕ", 28, Color(0.86, 0.85, 0.8)))
	var holders: Array = []
	for b in Inv.BLOCKS.size():
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 3)
		var bl := _label(Inv.BLOCKS[b][4], 14, Color(0.6, 0.6, 0.56))
		col.add_child(bl)
		bag_labels.append(bl)
		var g := LwBag.new()
		g.lw = self
		g.b = b
		g.inv = game.inv
		bag_grids.append(g)
		col.add_child(g)
		holders.append(col)
	bag_empty_l = _label("Наденьте одежду\nили вещмешок —\nпоявятся ячейки", 14, Color(0.55, 0.55, 0.52))
	var low := HBoxContainer.new()
	low.add_theme_constant_override("separation", 10)
	bc.add_child(low)
	low.add_child(holders[0])
	var pk := VBoxContainer.new()
	pk.add_theme_constant_override("separation", 6)
	low.add_child(pk)
	for b in range(1, holders.size()):
		pk.add_child(holders[b])
	low.add_child(bag_empty_l)
	# содержимое справа
	var sc := VBoxContainer.new()
	sc.add_theme_constant_override("separation", 8)
	cols.add_child(sc)
	title = _label("", 28, Color(0.95, 0.8, 0.5))
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sc.add_child(title)
	src_scroll = ScrollContainer.new()
	src_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.add_child(src_scroll)
	src_grid = SrcGrid.new()
	src_grid.lw = self
	src_scroll.add_child(src_grid)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	v.add_child(hb)
	all_b = Button.new()
	preload("res://scripts/ui/key_hint.gd").attach(all_b, "Забрать всё [R]", "Забрать всё [{loot_all}]")   # промпт 20.11 15:14
	all_b.focus_mode = Control.FOCUS_NONE
	all_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	all_b.add_theme_font_size_override("font_size", 20)
	all_b.pressed.connect(take_all)
	hb.add_child(all_b)
	var close_b := Button.new()
	preload("res://scripts/ui/key_hint.gd").attach(close_b, "Закрыть [Esc]", "Закрыть [{b:1}]")
	close_b.focus_mode = Control.FOCUS_NONE
	close_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_b.add_theme_font_size_override("font_size", 20)
	close_b.pressed.connect(close)
	hb.add_child(close_b)


## Клик мимо окна (ЛКМ/ПКМ по затемнению) — закрыть; событие съедено, в игру не уходит.
static func _click_away(c: Control, e: InputEvent, fn: Callable) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		c.accept_event()
		fn.call()


func _label(t: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


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
	if not game.inv.changed.is_connected(redraw):
		game.inv.changed.connect(redraw)
	for g in bag_grids:
		g.inv = game.inv
	for s in doll_slots:
		s.inv = game.inv
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
	elif e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_SPACE:
		# пробел при перетаскивании — повернуть предмет, как в инвентаре
		get_viewport().set_input_as_handled()
		if get_viewport().gui_is_dragging():
			var dd = get_viewport().gui_get_drag_data()
			if dd is Dictionary and dd.has("lw_src"):
				_rotate_src_drag()
			elif dd is Dictionary and dd.has("inv_key") and game.inv.drag_key != null:
				game.inv.rotate_drag()
			src_grid.hint = []
			src_grid.queue_redraw()
			for g in bag_grids:
				g.hint = []
				g.queue_redraw()
	elif e.is_action_pressed("ui_cancel") or e.is_action_pressed("inventory") \
			or (e.is_action_pressed("interact") and not e.is_echo() and Time.get_ticks_msec() - _opened_at > 250):
		get_viewport().set_input_as_handled()
		close()


# ---------- позиции содержимого ----------

## Дополнить запись до [id, n, прочность, ячейка, повёрнут].
static func _norm(it: Array) -> void:
	if it.size() < 3:
		it.append(-1.0)
	if it.size() < 4:
		it.append(-1)
	if it.size() < 5:
		it.append(false)


static func e_dur(it: Array) -> float:
	return float(it[2]) if it.size() > 2 else -1.0


func e_pos(it: Array) -> Vector2i:
	var p := int(it[3]) if it.size() > 3 else 0
	@warning_ignore("integer_division")
	return Vector2i(p % gw, p / gw)


func e_dim(it: Array) -> Vector2i:
	var d := Items.size_of(String(it[0]))
	return Vector2i(d.y, d.x) if it.size() > 4 and bool(it[4]) else d


static func _dim(id: String, rot: bool) -> Vector2i:
	var d := Items.size_of(id)
	return Vector2i(d.y, d.x) if rot else d


## Занятость: Vector2i -> номер позиции. ignore — эту позицию не учитывать.
func _occ(ignore := -1) -> Dictionary:
	var occ := {}
	for i in src.contents.size():
		if i == ignore:
			continue
		var it: Array = src.contents[i]
		var p := e_pos(it)
		var d := e_dim(it)
		for y in d.y:
			for x in d.x:
				occ[p + Vector2i(x, y)] = i
	return occ


func _free(p: Vector2i, d: Vector2i, occ: Dictionary, maxh: int) -> bool:
	if p.x < 0 or p.y < 0 or p.x + d.x > gw or p.y + d.y > maxh:
		return false
	for y in d.y:
		for x in d.x:
			if occ.has(p + Vector2i(x, y)):
				return false
	return true


## Первое свободное место под id: [Vector2i, повёрнут] или [] — нет.
func _find(id: String, occ: Dictionary, maxh: int) -> Array:
	var d := Items.size_of(id)
	for rot in ([false, true] if d.x != d.y else [false]):
		var dd := _dim(id, rot)
		for y in maxi(maxh - dd.y + 1, 0):
			for x in maxi(gw - dd.x + 1, 0):
				if _free(Vector2i(x, y), dd, occ, maxh):
					return [Vector2i(x, y), rot]
	return []


func _mark(occ: Dictionary, p: Vector2i, d: Vector2i, i: int) -> void:
	for y in d.y:
		for x in d.x:
			occ[p + Vector2i(x, y)] = i


func _set_pos(it: Array, p: Vector2i, rot: bool) -> void:
	_norm(it)
	it[3] = p.y * gw + p.x
	it[4] = rot


## Разложить содержимое: у кого нет места или оно занято — в первое свободное (сетка при нужде растёт вниз).
func _layout() -> void:
	gw = STORAGE_W if storage else LOOT_W
	var base_h := STORAGE_H if storage else LOOT_H
	var cont: Array = src.contents
	var occ := {}
	var pending: Array = []
	for i in cont.size():
		var it: Array = cont[i]
		_norm(it)
		var p := e_pos(it)
		if int(it[3]) >= 0 and _free(p, e_dim(it), occ, 1000):
			_mark(occ, p, e_dim(it), i)
		else:
			pending.append(i)
	for i in pending:
		var it: Array = cont[i]
		var fp := _find(String(it[0]), occ, 1000)
		_set_pos(it, fp[0], fp[1])
		_mark(occ, fp[0], e_dim(it), i)
	gh = base_h
	for it in cont:
		gh = maxi(gh, e_pos(it).y + e_dim(it).y)


func owner_at(c: Vector2i) -> int:
	if src == null or c.x < 0:
		return -1
	return int(_occ().get(c, -1))


func _rebuild() -> void:
	if src == null:
		return
	_layout()
	src_grid.custom_minimum_size = Vector2(gw, gh) * CELL
	src_scroll.custom_minimum_size = Vector2(gw * CELL + 8, minf(gh, 6) * CELL + 4)
	var any_bag := false
	for g in bag_grids:
		g.refit()
		var d: Vector2i = game.inv.block_dim(g.b)
		var vis := d.x > 0 and d.y > 0
		g.get_parent().visible = vis
		any_bag = any_bag or vis
		if g.b < bag_labels.size():
			var eid := String(game.inv.equip.get(Inv.BLOCKS[g.b][3], ""))
			bag_labels[g.b].text = "%s %d×%d" % [Items.item_name(eid).to_upper() if eid != "" else Inv.BLOCKS[g.b][4], d.x, d.y]
	if bag_empty_l:
		bag_empty_l.visible = not any_bag
	redraw()



func redraw() -> void:
	if not open:
		return
	src_grid.queue_redraw()
	for g in bag_grids:
		g.queue_redraw()
	for s in doll_slots:
		s.queue_redraw()


# ---------- перетаскивание ----------

func begin_src_drag(i: int, off: Vector2i) -> Control:
	drag_idx = i
	drag_off = off
	var it: Array = src.contents[i]
	drag_rot = it.size() > 4 and bool(it[4])
	var holder := Control.new()
	var pv := Inv.DragIcon.new()
	pv.id = String(it[0])
	pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(pv)
	drag_pv = pv
	_fit_src_pv()
	return holder


func _fit_src_pv() -> void:
	if drag_pv == null or not is_instance_valid(drag_pv) or src == null or drag_idx >= src.contents.size():
		return
	drag_pv.size = Vector2(_dim(String(src.contents[drag_idx][0]), drag_rot)) * CELL
	drag_pv.position = -(Vector2(drag_off) * CELL + Vector2(CELL, CELL) / 2)
	drag_pv.queue_redraw()


func _rotate_src_drag() -> void:
	drag_rot = not drag_rot
	drag_off = Vector2i(drag_off.y, drag_off.x)
	_fit_src_pv()


## Что тащим: [id, n, прочность, размер, за какую ячейку держим, своя позиция (-1 — из сумки)].
func _dragged(data: Dictionary) -> Array:
	if data.has("lw_src"):
		if src == null or drag_idx < 0 or drag_idx >= src.contents.size():
			return []
		var it: Array = src.contents.get(drag_idx)
		return [String(it.get(0)), int(it.get(1)), e_dur(it), _dim(String(it.get(0)), drag_rot), drag_off, drag_idx]
	var k = data["inv_key"]
	if k is String:
		var eid: String = game.inv.equip.get(k, "")
		if eid == "":
			return []
		return [eid, 1, game.inv.get_dur(k), _dim(eid, game.inv.drag_rot), game.inv.drag_off, -2]
	var s = game.inv.slots[int(k)]
	if s == null:
		return []
	var id := String(s["id"])
	return [id, int(s["n"]), float(s.get("dur", -1.0)), _dim(id, game.inv.drag_rot), game.inv.drag_off, -1]


## Можно ли долить в стопку t: [id, прочность] того же вида, есть место.
func _can_stack(t: int, id: String, _dur: float) -> bool:
	if t < 0 or t >= src.contents.size():
		return false
	var it: Array = src.contents[t]
	var mx: int = int(Items.ITEMS[id].get("stack", 1))
	if String(it[0]) != id or mx <= 1 or int(it[1]) >= mx:
		return false
	# Проверяем прочность только если она реально есть у предмета в базе
	if Items.max_dur(id) > 0.0:
		return false
	return true


## Подсветка при наведении на сетку содержимого: [ячейки, помещается ли].
func src_preview(data: Dictionary, cell: Vector2i) -> Array:
	var dr := _dragged(data)
	if dr.is_empty() or cell.x < 0:
		return [[], false]
	var occ := _occ(int(dr[5]))
	var t := int(occ.get(cell, -1))
	if _can_stack(t, dr[0], dr[2]):
		return [_rect(e_pos(src.contents[t]), e_dim(src.contents[t])), true]
	var p := (cell - Vector2i(dr[4])).max(Vector2i.ZERO)
	return [_rect(p, dr[3]), _free(p, dr[3], occ, gh)]


func _rect(p: Vector2i, d: Vector2i) -> Array:
	var out: Array = []
	for y in d.y:
		for x in d.x:
			var c := p + Vector2i(x, y)
			if c.x < gw and c.y < gh:
				out.append(c)
	return out


## Отпустили тащимое над ячейкой содержимого.
func drop_on_src(data: Dictionary, cell: Vector2i) -> void:
	var dr := _dragged(data)
	if dr.is_empty() or cell.x < 0:
		return
	var total_n := int(dr[1])
	var self_i := int(dr[5])

	# Если тащим стопку (> 1 шт.) из сумки в сундук — открываем окно выбора количества
	if self_i == -1 and total_n > 1:
		var inv_slot := int(data["inv_key"])
		_ask_qty(String(dr[0]), total_n, "Положить", func(cnt: int) -> void:
			_execute_drop_on_src(dr, inv_slot, cell, cnt))
		return

	_execute_drop_on_src(dr, data.get("inv_key", -1), cell, total_n)


## Выполнение переноса/стака в сетку содержимого
func _execute_drop_on_src(dr: Array, inv_key: Variant, cell: Vector2i, move_n: int) -> void:
	if src == null or move_n <= 0:
		return
	var id := String(dr[0])
	var self_i := int(dr[5])
	var occ := _occ(self_i)
	var t := int(occ.get(cell, -1))
	var cont: Array = src.contents

	if _can_stack(t, id, float(dr[2])):
		var mx: int = int(Items.ITEMS[id].get("stack", 1))
		var add := mini(move_n, mx - int(cont[t][1]))
		cont[t][1] = int(cont[t][1]) + add
		var rem := move_n - add

		if self_i >= 0:
			cont[self_i][1] = int(cont[self_i][1]) - add
			if int(cont[self_i][1]) <= 0:
				cont.remove_at(self_i)
		elif self_i == -2:
			var eq_slot := String(inv_key)
			game.inv.equip[eq_slot] = ""
			game.inv.equip_dur.erase(eq_slot)
			game._apply_equip(eq_slot)
			game.inv.notify()
		else:
			game.inv.take_at(int(inv_key), add)
			# Если влезла только часть выбранного количества — остаток кладём в свободную ячейку
			if rem > 0:
				var fp := _find(id, _occ(), gh)
				if not fp.is_empty():
					var e2: Array = [id, rem, -1.0, 0, false]
					_set_pos(e2, fp[0], fp[1])
					cont.append(e2)
					game.inv.take_at(int(inv_key), rem)
		_moved(id)
		return

	var p := (cell - Vector2i(dr[4])).max(Vector2i.ZERO)
	if not _free(p, dr[3], occ, gh):
		game.hud.toast("Не помещается", Color(0.9, 0.5, 0.4))
		return

	var rot: bool = Vector2i(dr[3]) != Items.size_of(id)
	if self_i >= 0:
		_set_pos(cont[self_i], p, rot)
	else:
		var e: Array = [id, move_n, float(dr[2]), 0, false]
		_set_pos(e, p, rot)
		cont.append(e)
		if self_i == -2:
			var eq_slot := String(inv_key)
			game.inv.equip[eq_slot] = ""
			game.inv.equip_dur.erase(eq_slot)
			game._apply_equip(eq_slot)
			game.inv.notify()
		else:
			game.inv.take_at(int(inv_key), move_n)
	_moved(id)


func drop_on_equip(slot: String) -> void:
	if src == null or drag_idx < 0 or drag_idx >= src.contents.size():
		return
	var it: Array = src.contents.get(drag_idx)
	var id := String(it.get(0))
	if not Items.fits(id, slot):
		game.hud.toast("%s сюда не надеть" % Items.item_name(id), Color(0.9, 0.5, 0.4))
		return
	if not game.can_take_hand(slot):   # за рулём — одна рука (game_items.gd)
		return
	if game.inv.equip[slot] != "":
		var old_id: String = game.inv.equip[slot]
		var old_dur: float = game.inv.get_dur(slot)
		if game.inv.add(old_id, 1, old_dur) > 0:
			game.hud.toast("Нет места снять %s" % Items.item_name(old_id), Color(0.9, 0.5, 0.4))
			return
	game.inv.equip[slot] = id
	if e_dur(it) >= 0.0:
		game.inv.equip_dur[slot] = e_dur(it)
	else:
		game.inv.equip_dur.erase(slot)
	game._apply_equip(slot)
	it[1] = int(it.get(1)) - 1
	if int(it.get(1)) <= 0:
		src.contents.remove_at(drag_idx)
	game.inv.notify()
	_moved(id)

## Куда ляжет предмет содержимого в сумке: якорь (-1 — мимо) и цель для стопки.
func _bag_target(cell: int) -> Array:
	var inv = game.inv
	if cell < 0 or src == null or drag_idx < 0 or drag_idx >= src.contents.size():
		return [-1, -1]
	var it: Array = src.contents[drag_idx]
	var id := String(it[0])
	var t: int = inv.owner_at(cell)
	if t >= 0:
		var s = inv.slots[t]
		var mx: int = Items.ITEMS[id]["stack"]
		if String(s["id"]) == id and mx > 1 and e_dur(it) < 0.0 and not s.has("dur") and int(s["n"]) < mx:
			return [-1, t]
	var b: int = inv.cell_block(cell)
	var p: Vector2i = (inv.cell_xy(cell) - drag_off).max(Vector2i.ZERO)
	return [inv.cell_idx(b, p.x, p.y), -1]


func bag_preview(cell: int) -> Array:
	var inv = game.inv
	var bt := _bag_target(cell)
	if int(bt[1]) >= 0:
		return [inv._cells(bt[1], inv.item_dim(inv.slots[bt[1]])), true]
	if int(bt[0]) < 0:
		return [[], false]
	var d := _dim(String(src.contents[drag_idx][0]), drag_rot)
	var cells: Array = inv._cells(bt[0], d)
	if cells.is_empty():
		return [[cell], false]
	return [cells, inv._fits_at(bt[0], d, inv.occupancy())]


## Отпустили предмет содержимого над ячейкой сумки.
func drop_on_bag(cell: int) -> void:
	var inv = game.inv
	var bt := _bag_target(cell)
	if int(bt[0]) < 0 and int(bt[1]) < 0:
		return
	var cont: Array = src.contents
	var it: Array = cont[drag_idx]
	var id := String(it[0])
	var n := int(it[1])
	var got := 0
	if id == "coin":
		got = n - int(inv.add(id, n))
	elif int(bt[1]) >= 0:
		var s = inv.slots[bt[1]]
		got = mini(n, int(Items.ITEMS[id]["stack"]) - int(s["n"]))
		s["n"] = int(s["n"]) + got
		inv.notify()
	else:
		var d := _dim(id, drag_rot)
		if not inv._fits_at(bt[0], d, inv.occupancy()):
			game.hud.toast("Не помещается", Color(0.9, 0.5, 0.4))
			return
		got = mini(n, int(Items.ITEMS[id]["stack"]))
		var e := {"id": id, "n": got}
		if e_dur(it) >= 0.0:
			e["dur"] = e_dur(it)
		inv._put(e, bt[0], d != Items.size_of(id))
		inv.notify()
	if got <= 0:
		return
	it[1] = n - got
	if int(it[1]) <= 0:
		cont.remove_at(drag_idx)
	_moved(id)


func _moved(id: String) -> void:
	game.play_ui("coin" if id == "coin" else "pickup", -14.0)
	_rebuild()


# ---------- быстрые действия (ЛКМ, Ctrl+ЛКМ, Shift+ЛКМ, R) ----------

func pick_src(i: int, qty_mode: int) -> void:
	if src == null or i >= src.contents.size():
		return
	var it: Array = src.contents[i]
	var id := String(it[0])
	var total_n := int(it[1])
	if qty_mode == 0 and total_n > 1:
		_ask_qty(id, total_n, "Забрать", func(cnt: int) -> void:
			take_cnt(i, cnt))
		return
	take_cnt(i, 1 if qty_mode == 1 else total_n)


func take_cnt(i: int, cnt: int, quiet := false) -> void:
	if src == null or i >= src.contents.size() or cnt <= 0:
		return
	var it: Array = src.contents[i]
	var want := mini(cnt, int(it[1]))
	var left: int = 0 if want == 1 and game.auto_equip(String(it[0]), e_dur(it)) \
		else game.inv.add(String(it[0]), want, e_dur(it))
	var got := want - left
	if got <= 0:
		if not quiet:
			game.hud.toast("Нет места", Color(0.9, 0.5, 0.4))
		return
	it[1] = int(it[1]) - got
	if int(it[1]) <= 0:
		src.contents.remove_at(i)
	game.play_ui("coin" if it[0] == "coin" else "pickup", -13.0)
	_rebuild()


func take(i: int, quiet := false) -> void:
	if src == null or i >= src.contents.size():
		return
	take_cnt(i, int(src.contents[i][1]), quiet)


func pick_bag(i: int, qty_mode: int) -> void:
	if src == null or game.inv.slots[i] == null:
		return
	var s = game.inv.slots[i]
	var id := String(s["id"])
	var total_n := int(s["n"])
	if qty_mode == 0 and total_n > 1:
		_ask_qty(id, total_n, "Положить", func(cnt: int) -> void:
			put_cnt(i, cnt))
		return
	put_cnt(i, 1 if qty_mode == 1 else total_n)


func pick_equip(eq_slot: String) -> void:
	if src == null:
		return
	var id: String = game.inv.equip.get(eq_slot, "")
	if id == "":
		return
	_layout()
	var dur := float(game.inv.get_dur(eq_slot))
	var fp := _find(id, _occ(), gh if not storage else 100)
	if fp.is_empty():
		game.hud.toast("Не помещается", Color(0.9, 0.5, 0.4))
		return
	for b in Inv.BLOCKS.size():
		if Inv.BLOCKS[b][3] == eq_slot:
			for i in game.inv.TOTAL:
				var s = game.inv.slots[i]
				if s != null and game.inv.cell_block(i) == b:
					put_cnt(i, int(s["n"]))
	game.inv.equip[eq_slot] = ""
	game.inv.equip_dur.erase(eq_slot)
	game._apply_equip(eq_slot)
	game.inv.notify()
	var e: Array = [id, 1, dur, 0, false]
	_set_pos(e, fp[0], fp[1])
	src.contents.append(e)
	game.play_ui("pickup", -14.0, 0.9)
	_rebuild()


func put_cnt(i: int, cnt: int) -> void:
	if src == null or cnt <= 0:
		return
	var s = game.inv.slots[i]
	if s == null:
		return
	_layout()
	var id: String = s["id"]
	var dur := float(s.get("dur", -1.0))
	var want := mini(cnt, int(s["n"]))
	var mx: int = Items.ITEMS[id]["stack"]
	var cont: Array = src.contents
	var left := want
	var no_dur := Items.max_dur(id) <= 0.0 and dur < 0.0
	if no_dur and mx > 1:
		for it in cont:
			if left > 0 and String(it[0]) == id and e_dur(it) < 0.0 and int(it[1]) < mx:
				var add := mini(left, mx - int(it[1]))
				it[1] = int(it[1]) + add
				left -= add
	while left > 0:
		var take_part := mini(left, mx)
		var fp := _find(id, _occ(), gh if not storage else 100)
		if fp.is_empty():
			break
		var e: Array = [id, take_part, dur, 0, false]
		_set_pos(e, fp[0], fp[1])
		cont.append(e)
		left -= take_part
	var moved := want - left
	if moved <= 0:
		game.hud.toast("Не помещается", Color(0.9, 0.5, 0.4))
		return
	game.inv.take_at(i, moved)
	game.play_ui("pickup", -14.0, 0.9)
	_rebuild()


func put(i: int) -> void:
	if src == null or game.inv.slots[i] == null:
		return
	put_cnt(i, int(game.inv.slots[i]["n"]))


func _ask_qty(id: String, max_n: int, btn_text: String, on_confirm: Callable) -> void:
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

		_qty_slider.value_changed.connect(func(v: float) -> void:
			if int(_qty_spin.value) != int(v):
				_qty_spin.value = int(v))
		_qty_spin.value_changed.connect(func(v: float) -> void:
			if int(_qty_slider.value) != int(v):
				_qty_slider.value = int(v))

		_qty_spin.get_line_edit().text_submitted.connect(func(_t: String) -> void:
			_qty_spin.apply()
			_qty_popup.hide()
			if _qty_cb.is_valid():
				_qty_cb.call(int(_qty_spin.value)))

		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 6)
		vb.add_child(hb)
		var ok_b := Button.new()
		ok_b.name = "OkBtn"
		ok_b.focus_mode = Control.FOCUS_NONE
		ok_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ok_b.add_theme_font_size_override("font_size", 13)
		ok_b.pressed.connect(func() -> void:
			_qty_spin.apply()
			_qty_popup.hide()
			if _qty_cb.is_valid():
				_qty_cb.call(int(_qty_spin.value)))
		hb.add_child(ok_b)

		var cancel_b := Button.new()
		cancel_b.text = "Отмена"
		cancel_b.focus_mode = Control.FOCUS_NONE
		cancel_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cancel_b.add_theme_font_size_override("font_size", 13)
		cancel_b.pressed.connect(func() -> void:
			_qty_popup.hide())
		hb.add_child(cancel_b)

	_qty_popup.find_child("OkBtn", true, false).text = btn_text
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
	var le := _qty_spin.get_line_edit()
	le.grab_focus()
	le.select_all()


func take_all() -> void:
	if src == null:
		return
	var i := 0
	while src != null and i < src.contents.size():
		var before: int = src.contents.size()
		take(i, true)
		if src.contents.size() == before:
			i += 1
	if src != null and src.contents.is_empty() and not storage:
		close()
	elif src != null and not src.contents.is_empty():
		game.hud.toast("Нет места", Color(0.9, 0.5, 0.4))
