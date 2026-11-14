extends CanvasLayer
## Меню: главное («Играть», «Настройки», «Выход»), пауза по Esc («Продолжить», «Настройки», «Выход в меню»)
## и настройки (громкость, яркость, гамма, контраст, постеризация). В углу — звук и полный экран.
## Работает и на паузе (process_mode = ALWAYS). Настройки сохраняются в user://settings.cfg.

signal play_pressed

const IconButton := preload("res://icon_button.gd")
const CFG := "user://settings.cfg"
const Graphics := preload("res://graphics.gd")

# имя -> [подпись, мин, макс, шаг, по умолчанию]
const SETTINGS := {
	"volume": ["Громкость", 0.0, 100.0, 1.0, 80.0],
	"brightness": ["Яркость", 0.5, 1.6, 0.01, 1.0],
	"gamma": ["Гамма", 0.6, 1.8, 0.01, 1.0],
	"contrast": ["Контраст", 0.6, 1.6, 0.01, 1.0],
	"posterize": ["Постеризация", 0.0, 100.0, 1.0, 70.0],
	"sensitivity": ["Чувствительность", 0.2, 4.0, 0.05, 1.0],
	"ui_scale": ["Размер интерфейса", 80.0, 120.0, 1.0, 100.0],
	"crosshair": ["Прицел", 0.0, 1.0, 1.0, 1.0],      # галочка: 0 — выкл, 1 — вкл
	"graphics": ["Графика", 0.0, 2.0, 1.0, 1.0],      # 0 низкая, 1 средняя, 2 высокая (graphics.gd)
}

var in_game := false          # выставляет main.gd, когда игра началась
var post_mat: ShaderMaterial  # постобработка — выставляет main.gd
var values := {}
var icons: Array = []
var main_box: VBoxContainer
var pause_box: VBoxContainer
var slots_box: VBoxContainer      # выбор слота сохранения (промпт 23:39)
var settings_box: VBoxContainer
var settings_from := "main"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.size_changed.connect(_apply_ui_scale)
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
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# главное меню и пауза — колонкой справа, название над кнопками
	var right := MarginContainer.new()
	right.anchor_left = 0.5
	right.anchor_right = 1.0
	right.anchor_bottom = 1.0
	right.add_theme_constant_override("margin_right", 90)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE   # не перехватывать клики (ползунки настроек под ней)
	root.add_child(right)
	var right_col := VBoxContainer.new()
	right_col.alignment = BoxContainer.ALIGNMENT_CENTER
	right_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(right_col)
	# --- главное меню
	main_box = _vbox(right_col)
	main_box.add_child(_title("eskiNess", 104))
	main_box.add_child(_subtitle("бункер. автомат. ничего хорошего."))
	main_box.add_child(_gap(34))
	main_box.add_child(_button("Играть", _open_slots))
	main_box.add_child(_button("Настройки", func(): _open_settings("main")))
	main_box.add_child(_button("Выход", func(): get_tree().quit()))

	# --- пауза
	pause_box = _vbox(right_col)
	pause_box.add_child(_title("ПАУЗА", 80))
	pause_box.add_child(_gap(24))
	pause_box.add_child(_button("Продолжить", resume))
	pause_box.add_child(_button("Сохранить", _save_game))
	pause_box.add_child(_button("Настройки", func(): _open_settings("pause")))
	pause_box.add_child(_button("Выход в меню", _to_main_menu))

	# --- слоты сохранений
	slots_box = _vbox(right_col)

	# --- настройки
	settings_box = _vbox(center)
	settings_box.add_child(_title("НАСТРОЙКИ", 60))
	settings_box.add_child(_gap(16))
	for key in SETTINGS:
		settings_box.add_child(_check_row(key) if key == "crosshair" else _slider_row(key))
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
	elif slots_box.visible:
		_show("main")
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
	var g := _game()
	if g:
		g.save_now()
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
	slots_box.visible = which == "slots"
	settings_box.visible = which == "settings"


# ---------- сохранения ----------
const Save := preload("res://save.gd")


func _game() -> Node:
	for c in get_parent().get_children():
		if c.has_method("save_now"):
			return c
	return null


func _save_game() -> void:
	var g := _game()
	if g:
		g.save_now()
		g.hud.toast("Сохранено: слот %d" % g.save_slot, Color(0.8, 0.85, 0.7))


## «Играть» → три слота: занятый — загрузить, пустой — новая игра; ✕ — удалить слот.
func _open_slots() -> void:
	for c in slots_box.get_children():
		c.queue_free()
	slots_box.add_child(_title("СЛОТЫ", 72))
	slots_box.add_child(_gap(18))
	for i in range(1, Save.SLOTS + 1):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.size_flags_horizontal = Control.SIZE_SHRINK_END
		var used := Save.exists(i)
		var b := _button("Слот %d" % i, _pick_slot.bind(i))
		b.custom_minimum_size = Vector2(300, 64)
		var info := Label.new()
		info.text = Save.summary(i) if used else "пусто — новая игра"
		info.add_theme_font_size_override("font_size", 16)
		info.add_theme_color_override("font_color", Color(0.75, 0.7, 0.62) if used else Color(0.5, 0.47, 0.42))
		info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		info.custom_minimum_size = Vector2(230, 0)
		row.add_child(info)
		row.add_child(b)
		if used:
			var del := _button("✕", _delete_slot.bind(i))
			del.custom_minimum_size = Vector2(58, 64)
			del.tooltip_text = "Удалить сохранение"
			row.add_child(del)
		else:
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(58, 64)
			row.add_child(gap)
		slots_box.add_child(row)
	slots_box.add_child(_gap(10))
	slots_box.add_child(_button("Назад", func(): _show("main")))
	_show("slots")


func _pick_slot(i: int) -> void:
	Engine.set_meta("eskiness_slot", i)
	Engine.set_meta("eskiness_load", Save.exists(i))
	play_pressed.emit()


func _delete_slot(i: int) -> void:
	Save.delete(i)
	_open_slots()


# ---------- настройки ----------

## Строка-галочка (вкл/выкл): значение хранится как 1.0 / 0.0, как у ползунков.
func _check_row(key: String) -> Control:
	var d: Array = SETTINGS[key]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var name_l := Label.new()
	name_l.text = d[0]
	name_l.custom_minimum_size = Vector2(200, 0)
	name_l.add_theme_font_size_override("font_size", 24)
	name_l.add_theme_color_override("font_color", Color(0.82, 0.81, 0.77))
	row.add_child(name_l)
	var cb := CheckBox.new()
	cb.name = key
	cb.focus_mode = Control.FOCUS_NONE
	cb.button_pressed = values[key] > 0.5
	cb.add_theme_icon_override("checked", _check_icon(true))
	cb.add_theme_icon_override("unchecked", _check_icon(false))
	cb.add_theme_icon_override("checked_disabled", _check_icon(true))
	cb.add_theme_icon_override("unchecked_disabled", _check_icon(false))
	cb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cb.toggled.connect(func(on: bool) -> void:
		values[key] = 1.0 if on else 0.0
		apply_settings())
	row.add_child(cb)
	return row


## Квадратик галочки в цветах меню: тёмная ячейка с красной рамкой, внутри светлая «птичка».
func _check_icon(on: bool) -> ImageTexture:
	const S := 30
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.06, 0.03, 0.03, 0.9))
	var frame := Color(0.6, 0.14, 0.1)
	for i in S:
		for k in 2:
			img.set_pixel(i, k, frame)
			img.set_pixel(i, S - 1 - k, frame)
			img.set_pixel(k, i, frame)
			img.set_pixel(S - 1 - k, i, frame)
	if on:
		var col := Color(0.9, 0.86, 0.76)
		var pts := [Vector2(7, 15), Vector2(12, 21), Vector2(23, 8)]
		for seg in 2:
			var a: Vector2 = pts[seg]
			var b: Vector2 = pts[seg + 1]
			for j in 40:
				var p := a.lerp(b, j / 39.0)
				for dx in range(-1, 2):
					for dy in range(-1, 2):
						img.set_pixel(int(p.x) + dx, int(p.y) + dy, col)
	return ImageTexture.create_from_image(img)


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
	if key == "crosshair":
		return "вкл" if v > 0.5 else "выкл"
	if key == "graphics":
		return Graphics.NAMES[clampi(int(round(v)), 0, 2)]
	if key == "volume" or key == "posterize" or key == "ui_scale":
		return "%d%%" % int(v)
	return "%.2f" % v


func _reset() -> void:
	for key in SETTINGS:
		values[key] = SETTINGS[key][4]
		var s := settings_box.find_child(key, true, false)
		if s is HSlider:
			s.value = values[key]
		elif s is CheckBox:
			s.button_pressed = values[key] > 0.5
	apply_settings()


## Размер интерфейса: 100% = прежний размер ×1.25, ползунок 80–120%.
## Масштаб не даём сделать таким, чтобы большие окна (инвентарь ~1240×600) вылезли за экран.
func _apply_ui_scale() -> void:
	var win := get_tree().root
	var want := 1.25 * float(values.get("ui_scale", 100.0)) / 100.0
	var sz := Vector2(win.size)
	if sz.x > 0 and sz.y > 0:
		want = minf(want, maxf(minf(sz.x / 1240.0, sz.y / 600.0), 0.8))
	win.content_scale_factor = want


func apply_settings() -> void:
	_apply_ui_scale()
	Graphics.apply(get_tree(), int(round(values.get("graphics", 1.0))))
	preload("res://player.gd").look_sens = values["sensitivity"]
	preload("res://hud.gd").show_crosshair = values.get("crosshair", 1.0) > 0.5
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
