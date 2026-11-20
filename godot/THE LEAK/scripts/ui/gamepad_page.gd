extends VBoxContainer
## Настройки → Управление → «Геймпад» (промпт 18.11 00:41): пресеты «По умолчанию» (только просмотр)
## и «Свой» (клик по кнопке → нажать кнопку геймпада; Back + кнопка — сочетание; Delete — убрать; Esc — отмена).
## Логика ввода — ui/gamepad.gd (menu.pad).
## Два игрока (промпт 20.11 14:49): «Игрок 1 / Игрок 2» — у каждого свой пресет, кнопки, чувствительность
## (игрок 2 — menu.pad.p2, для сплитскрина); список подключённых геймпадов с игроками и «Поменять геймпады».

const Pad := preload("res://scripts/ui/gamepad.gd")
const Split := preload("res://scripts/network/split.gd")

var menu      # menu.gd
var pad       # gamepad.gd — профиль, открытый на странице (root или root.p2)
var root      # gamepad.gd — главный узел ввода (menu.pad)
var who_btns := {}
var preset_btns := {}
var sens_s: HSlider
var sens_l: Label
var swap_pads_b: Button
var hint: Label
var pad_l: Label
var rows := {}               # действие -> кнопка
var swap_b: Button
var inv_b: Button
var vib_b: Button
var waiting := ""
var wait_since := 0
var back_alone := false      # Back нажата одна — ждём отпускания (назначить «Back»)


func _init(m, p) -> void:
	menu = m
	pad = p
	root = p
	add_theme_constant_override("separation", 6)
	var who := HBoxContainer.new()
	who.add_theme_constant_override("separation", 6)
	add_child(who)
	for pr in [[1, "Игрок 1"], [2, "Игрок 2 (Split-Screen)"]]:
		var n: int = pr[0]
		var b: Button = menu._button(pr[1], func(): _set_who(n))
		b.custom_minimum_size = Vector2(0, 40)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 18)
		who.add_child(b)
		who_btns[n] = b
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	add_child(top)
	for pr in [["default", "По умолчанию"], ["custom", "Свой"]]:
		var id: String = pr[0]
		var b: Button = menu._button(pr[1], func(): _set_preset(id))
		b.custom_minimum_size = Vector2(0, 44)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 19)
		top.add_child(b)
		preset_btns[id] = b
	hint = menu._subtitle("")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 17)
	add_child(hint)
	pad_l = menu._subtitle("")
	pad_l.add_theme_font_size_override("font_size", 17)
	add_child(pad_l)

	var list: VBoxContainer = menu._page_rows(self, 250)
	list.add_theme_constant_override("separation", 4)
	# общие для обоих пресетов
	var sr := HBoxContainer.new()
	sr.add_theme_constant_override("separation", 14)
	sr.add_child(_name("Чувствительность стика"))
	sens_s = menu.make_slider(0.3, 2.5, 0.05, pad.sens)
	sr.add_child(sens_s)
	sens_l = menu.value_label()
	sens_l.text = "%d%%" % roundi(pad.sens * 100.0)
	sr.add_child(sens_l)
	sens_s.value_changed.connect(func(v: float) -> void:
		pad.sens = v
		sens_l.text = "%d%%" % roundi(v * 100.0)
		pad.save_cfg())
	list.add_child(sr)
	inv_b = _row(list, "Инверсия обзора по вертикали", func():
		pad.invert_y = not pad.invert_y
		pad.save_cfg()
		refresh())
	vib_b = _row(list, "Вибрация", func():
		pad.vibration = not pad.vibration
		pad.save_cfg()
		refresh())
	swap_b = _row(list, "Поменять стики (только «Свой»)", func():
		if pad.preset != "custom":
			return
		pad.swap_sticks = not pad.swap_sticks
		pad.apply_map()
		pad.save_cfg()
		refresh())
	swap_pads_b = _row(list, "Поменять геймпады игроков", func():
		root.swap_pads = not root.swap_pads
		root.save_cfg()
		root.apply_map()
		refresh())
	var fixed: Label = menu._subtitle("Левый стик — ходьба, правый — обзор. Start — пауза. В меню и окнах: крестовина и правый стик — по пунктам (рамка), "
		+ "левый стик — тоже, когда персонаж стоит (пауза, магазин, лут). A — клик, X — правый клик, B — назад, "
		+ "RB — крафт в инвентаре (тащим предмет: LB — повернуть), Back — рамка / свободный курсор. "
		+ "В игре курсора с геймпада нет. С клавиатуры: стрелки, Enter, Esc, F2 — рамка / курсор. "
		+ "Back + стрелка в инвентаре — предмет в слот.")
	fixed.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fixed.add_theme_font_size_override("font_size", 16)
	list.add_child(fixed)
	for g in menu.CTL_GROUPS:
		list.add_child(menu._subtitle(g[0]))
		for a in g[1]:
			for c in menu.CONTROLS:
				if c[0] == a:
					var act: String = a
					rows[a] = _row(list, c[1], func(): _start(act))
	Input.joy_connection_changed.connect(func(_d, _c): if is_inside_tree() and is_visible_in_tree(): refresh())
	refresh()


## Чьи настройки открыты: 1 — игрок 1 (menu.pad), 2 — игрок 2 в сплитскрине (menu.pad.p2).
func _set_who(n: int) -> void:
	stop()
	pad = root.p2 if n == 2 and root.p2 else root
	refresh()


func _name(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(390, 0)
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", Color(0.82, 0.81, 0.77))
	return l


func _row(parent: Control, label: String, cb: Callable) -> Button:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.add_child(_name(label))
	var b := Button.new()
	b.custom_minimum_size = Vector2(220, 34)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_color", Color(0.9, 0.86, 0.76))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.92, 0.82))
	b.add_theme_color_override("font_disabled_color", Color(0.62, 0.6, 0.56))
	b.add_theme_stylebox_override("normal", menu._style(Color(0.06, 0.03, 0.03, 0.8), Color(0.45, 0.1, 0.07)))
	b.add_theme_stylebox_override("hover", menu._style(Color(0.2, 0.05, 0.03, 0.85), Color(0.85, 0.18, 0.1)))
	b.add_theme_stylebox_override("pressed", menu._style(Color(0.3, 0.05, 0.03, 0.9), Color(1.0, 0.3, 0.2)))
	b.add_theme_stylebox_override("disabled", menu._style(Color(0.04, 0.03, 0.03, 0.6), Color(0.25, 0.08, 0.06)))
	b.pressed.connect(cb)
	row.add_child(b)
	parent.add_child(row)
	return b


func _set_preset(id: String) -> void:
	stop()
	pad.set_preset(id)
	refresh()


func refresh() -> void:
	var custom: bool = pad.preset == "custom"
	for n in who_btns:
		menu._mark_btn(who_btns[n], (n == 2) == (pad != root))
	sens_s.set_value_no_signal(pad.sens)
	sens_l.text = "%d%%" % roundi(pad.sens * 100.0)
	for id in preset_btns:
		menu._mark_btn(preset_btns[id], id == pad.preset)
	hint.text = ("Свой пресет: нажмите на ячейку, затем кнопку геймпада (Back + кнопка — сочетание). Delete — убрать, Esc — отмена."
		if custom else "Стандартная раскладка — только просмотр. Выберите «Свой», чтобы настроить под себя.") + "\nСлот: нажать — в левую руку, задержать — в правую. Back — режим сброса, затем RT — из левой, LT — из правой (задержать — дальше)."
	pad_l.text = _pads_text()
	swap_pads_b.text = "вкл" if root.swap_pads else "выкл"
	swap_pads_b.disabled = Input.get_connected_joypads().size() < 2
	inv_b.text = "вкл" if pad.invert_y else "выкл"
	vib_b.text = "вкл" if pad.vibration else "выкл"
	swap_b.text = "вкл" if pad.swapped() else "выкл"
	swap_b.disabled = not custom
	for a in rows:
		var b: Button = rows[a]
		b.disabled = not custom
		b.text = "нажмите кнопку…" if a == waiting else Pad.spec_name(pad.spec_of(a))


## Подключённые геймпады и чей каждый в сплитскрине (как network/split.gd: pad_device).
func _pads_text() -> String:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		return "Геймпад не подключён. Для Split-Screen вдвоём: игрок 1 — клавиатура и мышь, игрок 2 — геймпад; или два геймпада."
	var d1: int = Split.pad_device(false)
	var d2: int = Split.pad_device(true)
	var lines: Array = []
	for i in pads.size():
		var d: int = pads[i]
		var who := "игрок 1" if d == d1 else ("игрок 2" if d == d2 else "не используется")
		lines.append("%d. %s — %s" % [i + 1, Input.get_joy_name(d), who])
	var tail := "\nВ Split-Screen игрок 1 — клавиатура и мышь." if pads.size() == 1 else ""
	return "Подключено (в Split-Screen):\n" + "\n".join(lines) + tail


func _start(a: String) -> void:
	if pad.preset != "custom":
		return
	stop()
	waiting = a
	wait_since = Time.get_ticks_msec()
	back_alone = false
	root.release_all()
	root.capturing = true
	refresh()


func stop() -> void:
	waiting = ""
	back_alone = false
	root.capturing = false
	if is_inside_tree():
		refresh()


func _assign(spec: String) -> void:
	pad.custom[waiting] = spec
	pad.save_cfg()
	stop()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree() and waiting != "":
		stop()


func _input(e: InputEvent) -> void:
	if waiting == "":
		return
	if not is_visible_in_tree():
		stop()
		return
	if e is InputEventKey and e.pressed and not e.is_echo():
		get_viewport().set_input_as_handled()
		var k: int = e.physical_keycode if e.physical_keycode != 0 else e.keycode
		if k == KEY_ESCAPE:
			stop()
		elif k == KEY_DELETE or k == KEY_BACKSPACE:
			_assign("")
		return
	if Time.get_ticks_msec() - wait_since < 200:
		return
	if e is InputEventJoypadButton:
		get_viewport().set_input_as_handled()
		var b: int = e.button_index
		if b == JOY_BUTTON_START or b == JOY_BUTTON_GUIDE:
			return   # Start — всегда пауза
		if b == pad.MOD:
			if e.pressed:
				back_alone = true
			elif back_alone:
				_assign("b:%d" % b)   # Back отпустили, ничего не нажав, — сама Back
			return
		if not e.pressed:
			return
		_assign(("c:%d" if Input.is_joy_button_pressed(e.device, pad.MOD) else "b:%d") % b)
	elif e is InputEventJoypadMotion and e.axis_value > 0.6 \
			and (e.axis == JOY_AXIS_TRIGGER_LEFT or e.axis == JOY_AXIS_TRIGGER_RIGHT):
		get_viewport().set_input_as_handled()
		_assign("t:L" if e.axis == JOY_AXIS_TRIGGER_LEFT else "t:R")
