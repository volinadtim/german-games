extends CanvasLayer
## Главное меню: «Играть», «Выход», в углу — звук и полный экран. Фон размыт.

signal play_pressed

const IconButton := preload("res://icon_button.gd")

var icons: Array = []


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var blur := ColorRect.new()
	blur.set_anchors_preset(Control.PRESET_FULL_RECT)
	blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://blur.gdshader")
	blur.material = sm
	root.add_child(blur)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)

	var title := Label.new()
	title.text = "БЕТОН"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 96)
	title.add_theme_color_override("font_color", Color(0.86, 0.85, 0.8))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	title.add_theme_constant_override("shadow_offset_y", 4)
	box.add_child(title)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 30)
	box.add_child(gap)

	var play := _button("Играть")
	play.pressed.connect(func(): play_pressed.emit())
	box.add_child(play)
	var quit := _button("Выход")
	quit.pressed.connect(func(): get_tree().quit())
	box.add_child(quit)

	var corner := HBoxContainer.new()
	corner.anchor_left = 1.0
	corner.anchor_right = 1.0
	corner.offset_left = -130
	corner.offset_right = -16
	corner.offset_top = 16
	corner.offset_bottom = 64
	corner.alignment = BoxContainer.ALIGNMENT_END
	corner.add_theme_constant_override("separation", 10)
	root.add_child(corner)

	var snd: Button = IconButton.new("sound")
	snd.pressed.connect(func(): AudioServer.set_bus_mute(0, not AudioServer.is_bus_mute(0)))
	corner.add_child(snd)
	var scr: Button = IconButton.new("screen")
	scr.pressed.connect(func(): get_parent().toggle_fullscreen())
	corner.add_child(scr)
	icons = [snd, scr]


func _process(_delta: float) -> void:
	for i in icons:
		i.queue_redraw()


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(280, 56)
	b.add_theme_font_size_override("font_size", 30)
	b.add_theme_color_override("font_color", Color(0.82, 0.81, 0.77))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", Color(0.7, 0.7, 0.7))
	b.add_theme_stylebox_override("normal", _style(Color(0, 0, 0, 0.35), Color(1, 1, 1, 0.15)))
	b.add_theme_stylebox_override("hover", _style(Color(1, 1, 1, 0.10), Color(1, 1, 1, 0.5)))
	b.add_theme_stylebox_override("pressed", _style(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.3)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


func _style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	return s
