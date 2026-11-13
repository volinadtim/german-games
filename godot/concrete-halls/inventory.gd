extends CanvasLayer
## Инвентарь (тестовая механика): сетка 6×5, стаки, Tab / I — открыть/закрыть (игра на паузе).
## ЛКМ по слоту — использовать, ПКМ — выбросить 1 шт., Shift+ПКМ — выбросить весь стак.
## Сам инвентарь только хранит предметы и шлёт сигналы; что делает предмет — решает game.gd.

signal changed
signal use_requested(idx: int)
signal drop_requested(idx: int, all: bool)

const Items := preload("res://items.gd")
const COLS := 6
const ROWS := 5
const SLOT := 76.0

var slots: Array = []        # null или {"id": String, "n": int}
var open := false
var enabled := true
var hover := -1
var root: Control
var info_name: Label
var info_desc: Label
var slot_nodes: Array = []


class Slot extends Control:
	const Items := preload("res://items.gd")
	var inv  # inventory.gd
	var idx := 0

	func _ready() -> void:
		custom_minimum_size = Vector2(76, 76)
		mouse_entered.connect(func(): inv.set_hover(idx))
		mouse_exited.connect(func(): inv.set_hover(-1))

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var hovered: bool = inv.hover == idx
		draw_rect(r, Color(0.0, 0.0, 0.0, 0.5))
		draw_rect(r, Color(1, 1, 1, 0.45 if hovered else 0.12), false, 1.0)
		var s = inv.slots[idx]
		if s == null:
			return
		Items.draw_icon(self, s["id"], r.grow(-12))
		if s["n"] > 1:
			var f := ThemeDB.fallback_font
			draw_string_outline(f, Vector2(4, size.y - 6), str(s["n"]), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 9, 17, 4, Color(0, 0, 0, 0.8))
			draw_string(f, Vector2(4, size.y - 6), str(s["n"]), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 9, 17, Color(0.92, 0.9, 0.84))

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			if e.button_index == MOUSE_BUTTON_LEFT:
				inv.use_requested.emit(idx)
			elif e.button_index == MOUSE_BUTTON_RIGHT:
				inv.drop_requested.emit(idx, e.shift_pressed)


func _ready() -> void:
	layer = 2
	process_mode = Node.PROCESS_MODE_ALWAYS
	slots.resize(COLS * ROWS)
	_build_ui()
	root.visible = false


func _build_ui() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.07, 0.065, 0.06, 0.92)
	st.border_color = Color(1, 1, 1, 0.14)
	st.set_border_width_all(1)
	st.set_corner_radius_all(3)
	st.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", st)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	vb.add_child(_label("ИНВЕНТАРЬ", 36, Color(0.86, 0.85, 0.8)))
	var grid := GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	vb.add_child(grid)
	for i in COLS * ROWS:
		var s := Slot.new()
		s.inv = self
		s.idx = i
		grid.add_child(s)
		slot_nodes.append(s)
	info_name = _label(" ", 22, Color(0.9, 0.82, 0.62))
	vb.add_child(info_name)
	info_desc = _label(" ", 17, Color(0.72, 0.71, 0.67))
	info_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_desc.custom_minimum_size = Vector2(COLS * (SLOT + 6), 44)
	vb.add_child(info_desc)
	vb.add_child(_label("ЛКМ — использовать    ПКМ — выбросить    Shift+ПКМ — выбросить всё    Tab — закрыть", 14, Color(0.55, 0.55, 0.52)))


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _input(e: InputEvent) -> void:
	if not enabled:
		return
	if e.is_action_pressed("inventory"):
		if open:
			close()
		elif not get_tree().paused:
			show_inventory()
		else:
			return
		get_viewport().set_input_as_handled()
	elif open and e.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func show_inventory() -> void:
	open = true
	root.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_hover(-1)


func close() -> void:
	if not open:
		return
	open = false
	root.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func set_hover(i: int) -> void:
	hover = i
	var s = slots[i] if i >= 0 else null
	if s != null:
		info_name.text = "%s  ×%d" % [Items.item_name(s["id"]), s["n"]] if s["n"] > 1 else Items.item_name(s["id"])
		info_desc.text = Items.ITEMS[s["id"]]["desc"]
	else:
		info_name.text = " "
		info_desc.text = " "
	_refresh()


func _refresh() -> void:
	for n in slot_nodes:
		n.queue_redraw()


# ---------- данные ----------

## Добавить предметы; возвращает, сколько не влезло.
func add(id: String, n: int) -> int:
	var mx: int = Items.ITEMS[id]["stack"]
	for s in slots:
		if n <= 0:
			break
		if s != null and s["id"] == id and s["n"] < mx:
			var take := mini(n, mx - int(s["n"]))
			s["n"] += take
			n -= take
	while n > 0:
		var i := slots.find(null)
		if i == -1:
			break
		var take := mini(n, mx)
		slots[i] = {"id": id, "n": take}
		n -= take
	_after_change()
	return n


func count(id: String) -> int:
	var c := 0
	for s in slots:
		if s != null and s["id"] == id:
			c += int(s["n"])
	return c


## Убрать n штук (с последних стаков). false — если столько нет (тогда ничего не убираем).
func remove(id: String, n: int) -> bool:
	if count(id) < n:
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


## Забрать из слота idx до n штук; возвращает [id, сколько забрали].
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


func _after_change() -> void:
	if open:
		set_hover(hover)
	changed.emit()
