extends CanvasLayer
## Окно лута (промпт 00:07): содержимое открытого ящика/сейфа сеткой. Клик по предмету — в инвентарь,
## «Забрать всё» (кнопка или R) — всё сразу. E / Esc / Tab — закрыть. Игра не на паузе.
## Что не влезло в сумку, остаётся в ящике (chest.contents) и сохраняется в сейв.

const Items := preload("res://items.gd")

var game
var chest                     # chest.gd, чьё содержимое показываем
var open := false
var grid: GridContainer
var title: Label
var info: Label
var _opened_at := 0


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
	title = Label.new()
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.95, 0.8, 0.5))
	v.add_child(title)
	grid = GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	v.add_child(grid)
	info = Label.new()
	info.add_theme_font_size_override("font_size", 16)
	info.add_theme_color_override("font_color", Color(0.7, 0.68, 0.62))
	info.text = "Клик — взять · R — забрать всё · E / Esc — закрыть"
	v.add_child(info)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	v.add_child(hb)
	var all_b := Button.new()
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


func show_for(c) -> void:
	chest = c
	open = true
	visible = true
	_opened_at = Time.get_ticks_msec()
	title.text = "СЕЙФ" if c.kind == "safe" else "ЯЩИК"
	game.player.active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_rebuild()


func close() -> void:
	if not open:
		return
	open = false
	visible = false
	chest = null
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
	for ch in grid.get_children():
		ch.queue_free()
	if chest == null:
		return
	if chest.contents.is_empty():
		var l := Label.new()
		l.text = "Пусто"
		l.add_theme_font_size_override("font_size", 20)
		l.add_theme_color_override("font_color", Color(0.6, 0.58, 0.54))
		grid.add_child(l)
		return
	for i in chest.contents.size():
		var it: Array = chest.contents[i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(76, 76)
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = Items.item_name(it[0])
		var id: String = it[0]
		var n: int = it[1]
		b.draw.connect(func():
			Items.draw_icon(b, id, Rect2(Vector2(10, 10), b.size - Vector2(20, 20)))
			if n > 1:
				var f := ThemeDB.fallback_font
				b.draw_string_outline(f, Vector2(4, b.size.y - 6), str(n), HORIZONTAL_ALIGNMENT_RIGHT, b.size.x - 9, 17, 4, Color(0, 0, 0, 0.8))
				b.draw_string(f, Vector2(4, b.size.y - 6), str(n), HORIZONTAL_ALIGNMENT_RIGHT, b.size.x - 9, 17, Color(0.92, 0.9, 0.84)))
		b.pressed.connect(take.bind(i))
		grid.add_child(b)


## Взять позицию i. Что не влезло — остаётся в ящике.
func take(i: int) -> void:
	if chest == null or i >= chest.contents.size():
		return
	var it: Array = chest.contents[i]
	var left: int = game.collect(it[0], int(it[1]))
	if left > 0:
		it[1] = left
	else:
		chest.contents.remove_at(i)
	_rebuild()


func take_all() -> void:
	if chest == null:
		return
	var i := 0
	while i < chest.contents.size():
		var before: int = chest.contents.size()
		take(i)
		if chest.contents.size() == before:
			i += 1   # не влезло — пропускаем
	if chest.contents.is_empty():
		close()
