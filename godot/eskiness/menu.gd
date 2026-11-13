extends CanvasLayer
## Меню: главное («Играть», «Настройки», «Выход»), пауза по Esc («Продолжить», «Настройки», «Выход в меню»)
## и настройки (громкость, яркость, гамма, контраст, постеризация). В углу — звук и полный экран.
## Работает и на паузе (process_mode = ALWAYS). Настройки сохраняются в user://settings.cfg.

signal play_pressed

const IconButton := preload("res://icon_button.gd")
const CFG := "user://settings.cfg"

# имя -> [подпись, мин, макс, шаг, по умолчанию]
const SETTINGS := {
	"volume": ["Громкость", 0.0, 100.0, 1.0, 80.0],
	"brightness": ["Яркость", 0.5, 1.6, 0.01, 1.0],
	"gamma": ["Гамма", 0.6, 1.8, 0.01, 1.0],
	"contrast": ["Контраст", 0.6, 1.6, 0.01, 1.0],
	"posterize": ["Постеризация", 0.0, 100.0, 1.0, 70.0],
}

var in_game := false          # выставляет main.gd, когда игра началась
var post_mat: ShaderMaterial  # постобработка — выставляет main.gd
var values := {}
var icons: Array = []
var main_box: VBoxContainer
var pause_box: VBoxContainer
var settings_box: VBoxContainer
var settings_from := "main"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()

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
	# главное меню и пауза — колонкой справа, название над кнопками
	var right := MarginContainer.new()
	right.anchor_left = 0.5
	right.anchor_right = 1.0
	right.anchor_bottom = 1.0
	right.add_theme_constant_override("margin_right", 90)
	root.add_child(right)
	var right_col := VBoxContainer.new()
	right_col.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_child(right_col)
	# --- главное меню
	main_box = _vbox(right_col)
	main_box.add_child(_title("eskiNess", 104))
	main_box.add_child(_subtitle("бункер. автомат. ничего хорошего."))
	main_box.add_child(_gap(34))
	main_box.add_child(_button("Играть", func(): play_pressed.emit()))
	main_box.add_child(_button("Настройки", func(): _open_settings("main")))
	main_box.add_child(_button("Выход", func(): get_tree().quit()))

	# --- пауза
	pause_box = _vbox(right_col)
	pause_box.add_child(_title("ПАУЗА", 80))
	pause_box.add_child(_gap(24))
	pause_box.add_child(_button("Продолжить", resume))
	pause_box.add_child(_button("Настройки", func(): _open_settings("pause")))
	pause_box.add_child(_button("Выход в меню", _to_main_menu))

	# --- настройки
	settings_box = _vbox(center)
	settings_box.add_child(_title("НАСТРОЙКИ", 60))
	settings_box.add_child(_gap(16))
	for key in SETTINGS:
		settings_box.add_child(_slider_row(key))
	settings_box.add_child(_gap(10))
	var reset := _button("По умолчанию", _reset)
	settings_box.add_child(reset)
	settings_box.add_child(_button("Назад", _close_settings))

	# --- иконки в углу
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

	_show("main")
	apply_settings()


func _process(_delta: float) -> void:
	for i in icons:
		i.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if settings_box.visible:
		_close_settings()
	elif in_game and not visible:
		pause()
	elif in_game and pause_box.visible:
		resume()


# ---------- переходы ----------

func pause() -> void:
	get_tree().paused = true
	visible = true
	_show("pause")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func resume() -> void:
	get_tree().paused = false
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _to_main_menu() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().reload_current_scene()


func _open_settings(from: String) -> void:
	settings_from = from
	_show("settings")


func _close_settings() -> void:
	_save()
	_show(settings_from)


func _show(which: String) -> void:
	main_box.visible = which == "main"
	pause_box.visible = which == "pause"
	settings_box.visible = which == "settings"


# ---------- настройки ----------

func _slider_row(key: String) -> Control:
	var d: Array = SETTINGS[key]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var name_l := Label.new()
	name_l.text = d[0]
	name_l.custom_minimum_size = Vector2(200, 0)
	name_l.add_theme_font_size_override("font_size", 24)
	name_l.add_theme_color_override("font_color", Color(0.82, 0.81, 0.77))
	row.add_child(name_l)
	var s := HSlider.new()
	s.min_value = d[1]
	s.max_value = d[2]
	s.step = d[3]
	s.value = values[key]
	s.custom_minimum_size = Vector2(300, 32)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_NONE
	s.name = key
	row.add_child(s)
	var val_l := Label.new()
	val_l.custom_minimum_size = Vector2(70, 0)
	val_l.add_theme_font_size_override("font_size", 22)
	val_l.add_theme_color_override("font_color", Color(0.7, 0.7, 0.66))
	val_l.text = _fmt(key, s.value)
	row.add_child(val_l)
	s.value_changed.connect(func(v: float) -> void:
		values[key] = v
		val_l.text = _fmt(key, v)
		apply_settings())
	return row


func _fmt(key: String, v: float) -> String:
	if key == "volume" or key == "posterize":
		return "%d%%" % int(v)
	return "%.2f" % v


func _reset() -> void:
	for key in SETTINGS:
		values[key] = SETTINGS[key][4]
		var s := settings_box.find_child(key, true, false) as HSlider
		if s:
			s.value = values[key]
	apply_settings()


func apply_settings() -> void:
	var vol: float = values["volume"] / 100.0
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(vol, 0.0001)))
	if post_mat:
		post_mat.set_shader_parameter("brightness", values["brightness"])
		post_mat.set_shader_parameter("gamma", values["gamma"])
		post_mat.set_shader_parameter("contrast", values["contrast"])
		# 0% — постеризации почти нет (64 уровня), 100% — сильная (4 уровня)
		post_mat.set_shader_parameter("levels", lerpf(64.0, 4.0, values["posterize"] / 100.0))


func _load() -> void:
	var cf := ConfigFile.new()
	var ok := cf.load(CFG) == OK
	for key in SETTINGS:
		values[key] = cf.get_value("settings", key, SETTINGS[key][4]) if ok else SETTINGS[key][4]


func _save() -> void:
	var cf := ConfigFile.new()
	for key in values:
		cf.set_value("settings", key, values[key])
	cf.save(CFG)


# ---------- оформление ----------

func _vbox(parent: Control) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", 12)
	b.size_flags_horizontal = Control.SIZE_SHRINK_END if parent is VBoxContainer else Control.SIZE_SHRINK_CENTER
	parent.add_child(b)
	return b


## Мрачный шрифт меню: если в fonts/ лежит файл шрифта — берём его, иначе системный «тяжёлый».
static var _font_cache: Font
func _menu_font() -> Font:
	if _font_cache:
		return _font_cache
	for path in ["res://fonts/menu.ttf", "res://fonts/menu.otf", "res://fonts/RubikDirt-Regular.ttf"]:
		if ResourceLoader.exists(path):
			_font_cache = load(path)
			return _font_cache
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Bahnschrift SemiBold SemiConden", "Impact", "Franklin Gothic Demi Cond", "Arial Narrow", "sans-serif"])
	sf.font_weight = 700
	var fv := FontVariation.new()
	fv.base_font = sf
	fv.spacing_glyph = 2
	_font_cache = fv
	return _font_cache


func _title(text: String, size: int) -> Label:
	var t := Label.new()
	t.text = text
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	t.add_theme_font_override("font", _menu_font())
	t.add_theme_font_size_override("font_size", size)
	t.add_theme_color_override("font_color", Color(0.86, 0.82, 0.74))
	t.add_theme_color_override("font_outline_color", Color(0.18, 0.03, 0.02, 0.9))
	t.add_theme_constant_override("outline_size", 6)
	t.add_theme_color_override("font_shadow_color", Color(0.5, 0.05, 0.03, 0.55))
	t.add_theme_constant_override("shadow_offset_x", 3)
	t.add_theme_constant_override("shadow_offset_y", 5)
	return t


func _subtitle(text: String) -> Label:
	var t := Label.new()
	t.text = text
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	t.add_theme_font_override("font", _menu_font())
	t.add_theme_font_size_override("font_size", 20)
	t.add_theme_color_override("font_color", Color(0.62, 0.5, 0.42, 0.85))
	return t


func _gap(h: float) -> Control:
	var g := Control.new()
	g.custom_minimum_size = Vector2(0, h)
	return g


## Кнопка: тёмная полупрозрачная плашка, красная полоса слева, текст сдвигается при наведении.
func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(340, 58)
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	b.add_theme_font_override("font", _menu_font())
	b.add_theme_font_size_override("font_size", 28)
	b.add_theme_color_override("font_color", Color(0.8, 0.77, 0.7))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.92, 0.82))
	b.add_theme_color_override("font_pressed_color", Color(0.85, 0.35, 0.25))
	b.add_theme_stylebox_override("normal", _btn_style(Color(0.04, 0.02, 0.02, 0.55), Color(0.45, 0.08, 0.05, 0.85), 4, 22))
	b.add_theme_stylebox_override("hover", _btn_style(Color(0.22, 0.05, 0.03, 0.6), Color(0.85, 0.18, 0.1), 8, 34))
	b.add_theme_stylebox_override("pressed", _btn_style(Color(0.3, 0.05, 0.03, 0.7), Color(1.0, 0.3, 0.2), 8, 36))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(cb)
	return b


func _btn_style(bg: Color, accent: Color, bar: int, pad: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = accent
	s.border_width_left = bar
	s.border_width_bottom = 1
	s.content_margin_left = pad
	s.content_margin_right = 18
	s.skew = Vector2(-0.12, 0)
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 6
	return s


func _style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	return s
