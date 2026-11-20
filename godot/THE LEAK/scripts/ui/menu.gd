extends CanvasLayer
## Меню: главное («Играть», «Настройки», «Выход»), пауза по Esc («Продолжить», «Настройки», «Выход в меню»)
## и настройки (громкость, яркость, гамма, постеризация). В углу — звук и полный экран.
## Работает и на паузе (process_mode = ALWAYS). Настройки сохраняются в user://settings.cfg.

signal play_pressed

const SplitScr := preload("res://scripts/network/split.gd")   # сплитскрин (промпт 18.11 00:58)
const IconButton := preload("res://scripts/ui/icon_button.gd")
const CFG := "user://settings.cfg"
const Graphics := preload("res://scripts/core/graphics.gd")
const PlayerScript := preload("res://scripts/player/player.gd")

# имя -> [подпись, мин, макс, шаг, по умолчанию]
const SETTINGS := {
	"volume": ["Громкость", 0.0, 100.0, 1.0, 80.0],
	"voice_volume": ["Громкость голоса", 0.0, 100.0, 1.0, 60.0],   # голоса игроков в сети (voip.gd, промпт 16.11 22:11)
	"brightness": ["Яркость", 0.8, 1.2, 0.01, 1.0],
	"gamma": ["Гамма", 0.8, 1.3, 0.01, 1.0],
	"posterize": ["Постеризация", 0.0, 1.0, 1.0, 1.0],   # галочка: вкл — 50%, выкл — 0 (промпт 00:30 16.11)
	"sensitivity": ["Чувствительность", 0.2, 4.0, 0.05, 1.0],
	"fov": ["Поле зрения", 60.0, 110.0, 1.0, 75.0],   # градусы; 75 — прежний FOV камеры игрока
	"ui_scale": ["Размер интерфейса", 80.0, 120.0, 1.0, 100.0],   # 100% — под монитор (_auto_ui_scale)
	"ui_scale_split": ["Интерфейс в Split-Screen", 60.0, 130.0, 1.0, 100.0],   # 100% — авто под половину экрана (split.gd: _fit_ui)
	# --- категория «Прицел»
	"crosshair": ["Прицел", 0.0, 1.0, 1.0, 1.0],      # галочка: 0 — выкл, 1 — вкл
	"cross_style": ["Вид", 0.0, 2.0, 1.0, 0.0],       # 0 точка, 1 крестик, 2 кружок
	"cross_color": ["Цвет", 0.0, 4.0, 1.0, 0.0],      # см. Hud.CROSS_COLORS
	"cross_size": ["Размер", 50.0, 250.0, 10.0, 100.0],
	"cross_alpha": ["Непрозрачность", 10.0, 100.0, 5.0, 35.0],
	"resolution": ["Разрешение", 0.0, 6.0, 1.0, 0.0],   # индекс в RESOLUTIONS, 0 — авто (промпт 01:33 18.11)
	"window_mode": ["Режим экрана", 0.0, 2.0, 1.0, 2.0],   # 0 оконный, 1 оконный без рамок, 2 полноэкранный (промпт 22:53)
	# --- графика (отдельная страница, graphics.gd): пресет и каждый эффект отдельно (промпт 14.11 17:36)
	"graphics": ["Пресет", 0.0, 2.0, 1.0, 1.0],       # 0 низкая, 1 средняя, 2 высокая — выставляет все g_*
	"g_shadows": ["Тени ламп", 0.0, 1.0, 1.0, 1.0],
	"g_shadow_res": ["Качество теней", 0.0, 2.0, 1.0, 1.0],
	"g_ssao": ["Затенение углов", 0.0, 1.0, 1.0, 1.0],
	"g_ssr": ["Отражения", 0.0, 1.0, 1.0, 0.0],
	"g_volfog": ["Объёмный туман", 0.0, 1.0, 1.0, 0.0],
	"g_glow": ["Свечение", 0.0, 1.0, 1.0, 1.0],
	"g_aa": ["Сглаживание", 0.0, 2.0, 1.0, 1.0],
	"g_scale": ["Разрешение 3D", 50.0, 100.0, 5.0, 100.0],
	"g_textures": ["Текстуры", 0.0, 2.0, 1.0, 1.0],
	"g_geometry": ["Геометрия", 0.0, 2.0, 1.0, 1.0],
	"g_grass": ["Трава", 0.0, 100.0, 5.0, 70.0],
	"g_particles": ["Пыль и мошки", 0.0, 100.0, 5.0, 100.0],
}

var in_game := false          # выставляет main.gd, когда игра началась
var post_mat: ShaderMaterial  # постобработка — выставляет main.gd
var values := {}
var icons: Array = []
var main_box: VBoxContainer
var pause_box: VBoxContainer
var slots_box: VBoxContainer      # выбор слота сохранения (промпт 23:39)
var settings_box: VBoxContainer
var gfx_box: VBoxContainer        # страница «Графика»
var settings_from := "main"
var setup_box: Control            # первая настройка картинки (first_setup.gd, промпт 00:20 16.11)
var setup_back := ""              # "settings" — калибровку открыли из настроек, «Готово» возвращает туда
var blur_rect: ColorRect
var pending_save := ""            # сейв, выбранный до первой настройки картинки
var pending_crash := false        # выбрана аварийная копия сейва
var play_back := "main"           # куда возвращает «Назад» со страницы «Игра» (main / multi)
const FirstSetup := preload("res://scripts/ui/first_setup.gd")
var ctl_box: VBoxContainer        # страница «Управление»
var gen_box: VBoxContainer        # страница «Основное»
var aim_box: VBoxContainer        # страница «Прицел»
var cat := "general"              # открытая категория настроек
var cat_btns := {}                # категория -> кнопка слева
var ctl_tabs: Array = []          # кнопки-вкладки разделов «Управления»
var ctl_groups: Array = []        # бинды каждого раздела (виден только активный)
## Категория «Основное»; всё остальное из SETTINGS — в «Экран и графика».
const GENERAL_KEYS := ["volume", "voice_volume", "sensitivity", "fov", "ui_scale", "ui_scale_split"]
## Категория «Прицел»
const AIM_KEYS := ["crosshair", "cross_style", "cross_color", "cross_size", "cross_alpha"]

## Разрешение окна: индекс 0 — авто (под экран), остальные — фиксированный размер (промпт 01:33 18.11)
const RESOLUTIONS := [
	Vector2i(0, 0), Vector2i(1280, 720), Vector2i(1366, 768),
	Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160),
]
var net_box: Control              # страница «Сетевая игра» (net_lobby.gd, промпт 14.11 19:37)
var ctl_rows := {}                # действие -> [кнопка основной клавиши, кнопка альтернативной]
var waiting_action := ""          # ждём клавишу для этого действия
var pad                           # ui/gamepad.gd — ввод с геймпада, пресеты
var pad_page: Control             # «Управление» → «Геймпад» (ui/gamepad_page.gd)
var kb_nodes: Array = []          # «Управление» → «Клавиатура и мышь»
var dev_btns := {}
var waiting_idx := 0              # 0 — основная, 1 — альтернативная (промпт 16.11 02:15)

## Переназначаемые действия и разделы страницы «Управление» — из таблицы data/controls/bindings.cfg (Controls).
## CONTROLS: [действие, подпись, клавиши по умолчанию]; CTL_GROUPS: [раздел, [действия]].
var CONTROLS: Array = Controls.menu_rows()
var CTL_GROUPS: Array = Controls.menu_groups()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# игра называется THE LEAK (промпт 16.11 21:58); config/name в project.godot прежний — от него зависит папка сейвов
	get_tree().root.title = "THE LEAK"
	get_tree().root.size_changed.connect(_apply_ui_scale)
	pad = preload("res://scripts/controls/gamepad.gd").new()   # геймпад (промпт 18.11 00:41)
	add_child(pad)
	_load()
	_apply_binds()

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = _menu_theme()   # общий шрифт и чёрная обводка у всего текста меню (промпт 19:00)
	add_child(root)

	var blur := ColorRect.new()
	blur.set_anchors_preset(Control.PRESET_FULL_RECT)
	blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://shaders/blur.gdshader")
	blur.material = sm
	root.add_child(blur)
	blur_rect = blur

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
	main_box.add_child(_title("THE LEAK", 104))   # название игры (промпт 16.11 21:58)
	main_box.add_child(_subtitle("no luck. no fun."))
	main_box.add_child(_gap(34))
	main_box.add_child(_button("Играть", func():
		SplitScr.pending = false
		_open_play("main")))
	main_box.add_child(_button("Мультиплеер", _open_multi))   # сеть и Split-Screen (промпт 18.11 02:00)
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

	# --- сетевая игра
	net_box = preload("res://scripts/network/net_lobby.gd").new(self)
	center.add_child(net_box)
	preload("res://scripts/ui/ui_fit.gd").attach(net_box)   # окно в рамках экрана (промпт 00:32)

	# --- настройки (промпт 23:26): слева категории «Основное» / «Экран и графика» / «Управление», справа — их страница
	settings_box = _vbox(center)
	preload("res://scripts/ui/ui_fit.gd").attach(settings_box)   # окно в рамках экрана (промпт 00:32)
	settings_box.add_child(_title("НАСТРОЙКИ", 60))
	settings_box.add_child(_gap(4))
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 24)
	settings_box.add_child(body)
	var cats := VBoxContainer.new()
	cats.add_theme_constant_override("separation", 10)
	body.add_child(cats)
	var pages := VBoxContainer.new()
	pages.custom_minimum_size = Vector2(660, 0)
	body.add_child(pages)
	var touch: bool = preload("res://scripts/ui/touch_controls.gd").wanted()

	# «Основное»
	gen_box = VBoxContainer.new()
	pages.add_child(gen_box)
	var grows := _page_rows(gen_box, 360)
	for key in GENERAL_KEYS:
		grows.add_child(setting_row(key))

	# «Прицел»: вкл/выкл, вид, цвет, размер, непрозрачность
	aim_box = VBoxContainer.new()
	pages.add_child(aim_box)
	var arows := _page_rows(aim_box, 360)
	for key in AIM_KEYS:
		arows.add_child(setting_row(key))

	# «Экран и графика»: режим экрана, яркость/гамма/постеризация, пресет и каждый эффект
	gfx_box = VBoxContainer.new()
	pages.add_child(gfx_box)
	var rows := _page_rows(gfx_box, 360)
	for key in SETTINGS:
		if key in GENERAL_KEYS or key in AIM_KEYS:
			continue
		if (key == "window_mode" or key == "resolution") and _mobile():
			continue   # на телефоне окна нет
		if key == "gamma":
			continue   # 20.11 14:40: яркость и гамма — один ползунок, как на экране калибровки
		if key == "brightness":
			rows.add_child(_bright_row())
			continue
		if key == "graphics":
			rows.add_child(_gap(6))
		rows.add_child(setting_row(key))

	# «Управление»: строка = действие и его клавиша; клик — назначить новую; подразделы CTL_GROUPS
	ctl_box = VBoxContainer.new()
	pages.add_child(ctl_box)
	# переключатель «Клавиатура и мышь» / «Геймпад» (промпт 18.11 00:41)
	var devs := HBoxContainer.new()
	devs.add_theme_constant_override("separation", 6)
	ctl_box.add_child(devs)
	for d in [["kb", "Клавиатура и мышь"], ["pad", "Геймпад"]]:
		var did: String = d[0]
		var db := _button(d[1], func(): _set_dev(did))
		db.custom_minimum_size = Vector2(0, 46)
		db.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		db.add_theme_font_size_override("font_size", 21)
		devs.add_child(db)
		dev_btns[did] = db
	var kb_hint := _subtitle("Нажмите на клавишу, чтобы переназначить. Esc — отмена.")
	ctl_box.add_child(kb_hint)
	kb_nodes.append(kb_hint)
	# вкладки разделов в строку (промпт 23:28): видны бинды только активной вкладки
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	ctl_box.add_child(tabs)
	kb_nodes.append(tabs)
	var crows := _page_rows(ctl_box, 290)
	kb_nodes.append(crows.get_parent())
	crows.add_theme_constant_override("separation", 4)
	var shown := {}
	for gi in CTL_GROUPS.size():
		var g: Array = CTL_GROUPS[gi]
		var grp := VBoxContainer.new()
		grp.add_theme_constant_override("separation", 4)
		crows.add_child(grp)
		ctl_groups.append(grp)
		var tb := _button(g[0], func(): _set_ctl_tab(gi))
		tb.custom_minimum_size = Vector2(0, 44)
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.add_theme_font_size_override("font_size", 19)
		tabs.add_child(tb)
		ctl_tabs.append(tb)
		for a in g[1]:
			for c in CONTROLS:
				if c[0] == a:
					grp.add_child(_bind_row(c[0], c[1]))
					shown[a] = true
	for c in CONTROLS:
		if not shown.has(c[0]):
			ctl_groups[-1].add_child(_bind_row(c[0], c[1]))   # действие без раздела — в последнюю вкладку, чтобы не потерялось
	_set_ctl_tab(0)
	pad_page = preload("res://scripts/ui/gamepad_page.gd").new(self, pad)
	ctl_box.add_child(pad_page)
	_set_dev("pad" if not Input.get_connected_joypads().is_empty() else "kb")

	# кнопки категорий (на телефоне клавиш нет — «Управление» не показываем, экранные кнопки: touch_controls.gd)
	for c in [["general", "Основное"], ["aim", "Прицел"], ["gfx", "Экран и графика"], ["controls", "Управление"]]:
		if c[0] == "controls" and touch:
			continue
		var id: String = c[0]
		var b := _button(c[1], func(): _set_cat(id))
		cats.add_child(b)
		cat_btns[id] = b
	cats.add_child(_gap(18))
	cats.add_child(_button("По умолчанию", _reset_cat))
	cats.add_child(_button("Назад", _close_settings))
	for b in cats.get_children():
		if b is Button:
			b.custom_minimum_size = Vector2(270, 52)
	_set_cat("general")

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
	scr.pressed.connect(toggle_fullscreen)
	corner.add_child(scr)
	icons = [snd, scr]

	# настройка картинки по шагам — когда игрок впервые выбирает слот (_pick_slot)
	setup_box = FirstSetup.new(self)
	root.add_child(setup_box)
	_show("main")
	apply_settings()
	# вышли из сетевой игры (хост отключился и т.п.) — сразу на страницу сети с сообщением
	var nt := get_tree().root.get_node_or_null("Net")
	if nt and nt.last_msg != "":
		_open_net.call_deferred()


func _process(_delta: float) -> void:
	for i in icons:
		i.queue_redraw()


## Ожидание новой клавиши для действия: перехватываем раньше всех (и Esc, и клики мыши).
func _input(event: InputEvent) -> void:
	if waiting_action == "" or not visible:
		return
	if event is InputEventKey and event.pressed and not event.is_echo():
		get_viewport().set_input_as_handled()
		var k: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if event.is_action_pressed("ui_cancel"):
			_stop_wait()
		elif event.is_action_pressed("ui_text_delete") or event.is_action_pressed("ui_text_backspace"):
			_assign(waiting_action, "", waiting_idx)   # Delete/Backspace — убрать клавишу
		else:
			_assign(waiting_action, "k:%d" % k, waiting_idx)
	elif event is InputEventMouseButton and event.pressed:
		get_viewport().set_input_as_handled()
		_assign(waiting_action, "m:%d" % event.button_index, waiting_idx)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if setup_box and setup_box.visible and setup_back != "":
		setup_box.call("_finish")   # калибровка из настроек — Esc/B как «Готово»
	elif settings_box.visible:
		_close_settings()
	elif slots_box.visible:
		_show("main")
	elif net_box.visible and not in_game:
		# в игре меню скрыто, но net_box.visible остаётся true: раньше Esc здесь звал back() → net.leave()
		# и выкидывал из сетевой игры (промпт 18.11 00:26)
		net_box.back()
	elif in_game and not visible:
		pause()
	elif in_game and pause_box.visible:
		resume()


# ---------- переходы ----------

func _net_game() -> bool:
	var nt := get_tree().root.get_node_or_null("Net")
	return nt != null and nt.in_game


## В сетевой игре мир на паузу не встаёт (он общий) — только останавливается свой игрок.
func _set_player_active(on: bool) -> void:
	for c in get_parent().get_children():
		if c is PlayerScript and not c.puppet:
			c.active = on and (_game() == null or _game().alive)


func pause() -> void:
	get_tree().paused = not _net_game()
	if _net_game():
		_set_player_active(false)
	visible = true
	_show("pause")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func resume() -> void:
	get_tree().paused = false
	if _net_game():
		_set_player_active(true)
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _to_main_menu() -> void:
	var g := _game()
	if g:
		g.save_exit()   # сохранились и убрали аварийную копию (промпт 18.11 02:00)
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().reload_current_scene()


func _open_settings(from: String) -> void:
	settings_from = from
	_show("settings")


## Первая настройка картинки закончена (first_setup.gd) — в главное меню.
func setup_finished() -> void:
	for k in ["posterize", "gamma", "brightness"]:
		_set_widget(k)
	if setup_back != "":
		setup_back = ""
		_show("settings")
	elif pending_save != "":
		var id := pending_save
		var cr := pending_crash
		pending_save = ""
		pending_crash = false
		_pick_save(id, cr)
	else:
		_show("main")


func _close_settings() -> void:
	_save()
	_show(settings_from)


func _show(which: String) -> void:
	# в игре пауза и настройки — поверх чёрных переходов и кат-сцен (затемнения на слоях 10–40, промпт 05:45)
	layer = 60 if in_game else 1
	main_box.visible = which == "main"
	pause_box.visible = which == "pause"
	slots_box.visible = which == "slots"
	settings_box.visible = which == "settings"
	net_box.visible = which == "net"
	if setup_box:
		setup_box.visible = which == "setup"
	blur_rect.visible = which != "setup"   # превью настройки картинки — без размытия
	# главное меню — фон-сцена (ui/menu_scene.gd) чёткая, остальные страницы — размытые
	var sharp := which == "main" and not in_game
	var bm := blur_rect.material as ShaderMaterial
	bm.set_shader_parameter("lod", 0.0 if sharp else 1.4)
	bm.set_shader_parameter("spread", 0.0 if sharp else 2.6)
	bm.set_shader_parameter("darken", 1.0 if sharp else 0.88)
	for i in icons:
		i.visible = which != "setup"
	if which != "settings":
		_stop_wait()


# ---------- сохранения ----------
const Save := preload("res://scripts/systems/save.gd")


func _game() -> Node:
	for c in get_parent().get_children():
		if c.has_method("save_now"):
			return c
	return null


func _save_game() -> void:
	var g := _game()
	if g == null:
		return
	if g.net and not g.net.is_host():
		g.hud.toast("Сейв сетевой игры хранится у хоста", Color(0.85, 0.8, 0.6))
		g.net.send_my_save(true)
		return
	g.save_now()
	g.hud.toast("Сохранено", Color(0.8, 0.85, 0.7))


## «Играть» (промпт 18.11 02:00): продолжить прошлую сессию, начать новую игру или выбрать сейв.
func _open_play(from: String) -> void:
	play_back = from
	for c in slots_box.get_children():
		c.queue_free()
	slots_box.add_child(_title("ИГРА", 60))
	slots_box.add_child(_gap(18))
	var last: String = Save.last()
	if last != "":
		slots_box.add_child(_button("Продолжить", func(): _pick_save(last, false)))
	slots_box.add_child(_button("Начать новую игру", _ask_mode))
	if not Save.list().is_empty():
		slots_box.add_child(_button("Загрузить", func(): _open_loads(Callable())))
	slots_box.add_child(_gap(10))
	slots_box.add_child(_button("Назад", func():
		if play_back == "multi":
			_open_multi()
		else:
			_show("main")))
	_show("slots")


## «Мультиплеер»: сетевая игра и Split-Screen (два игрока на одном ПК, network/split.gd).
func _open_multi() -> void:
	for c in slots_box.get_children():
		c.queue_free()
	slots_box.add_child(_title("МУЛЬТИПЛЕЕР", 60))
	slots_box.add_child(_gap(18))
	slots_box.add_child(_button("Сетевая игра", func():
		SplitScr.pending = false
		_open_net()))
	if not _mobile():
		slots_box.add_child(_button("Split-Screen", func():
			SplitScr.pending = true   # обычная игра из сейва, экран пополам
			_open_play("multi")))
	slots_box.add_child(_gap(10))
	slots_box.add_child(_button("Назад", func(): _show("main")))
	_show("slots")


## Список сейвов: сколько угодно (save.gd). cb(id, crash) — если сейв выбирают не для старта игры
## (например хост сетевой игры выбирает, какой сейв продолжить).
func _open_loads(cb: Callable) -> void:
	for c in slots_box.get_children():
		c.queue_free()
	slots_box.add_child(_title("СОХРАНЕНИЯ", 60))
	slots_box.add_child(_gap(12))
	var ids: Array = Save.list()
	if ids.is_empty():
		slots_box.add_child(_subtitle("пока ни одного сохранения"))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.size_flags_horizontal = Control.SIZE_SHRINK_END
	var scr := ScrollContainer.new()
	scr.custom_minimum_size = Vector2(620, mini(ids.size(), 7) * 72)
	scr.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scr.size_flags_horizontal = Control.SIZE_SHRINK_END
	scr.add_child(box)
	slots_box.add_child(scr)
	for id in ids:
		var sid: String = String(id)
		var d: Dictionary = Save.read(sid)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.size_flags_horizontal = Control.SIZE_SHRINK_END
		var info := Label.new()
		info.text = ("сеть · " if bool(d.get("net", false)) else "") + Save.describe(d)
		info.add_theme_font_size_override("font_size", 16)
		info.add_theme_color_override("font_color", Color(0.75, 0.7, 0.62))
		info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		info.custom_minimum_size = Vector2(230, 0)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(info)
		var b := _button("Играть", func():
			if cb.is_valid():
				cb.call(sid, false)
			else:
				_pick_save(sid, false))
		b.custom_minimum_size = Vector2(230, 64)
		row.add_child(b)
		if Save.crash_exists(sid):
			# аварийная копия после вылета игры — отдельным сейвом, основной она не перезаписала
			var cb2 := _button("Аварийный", func():
				if cb.is_valid():
					cb.call(sid, true)
				else:
					_pick_save(sid, true))
			cb2.custom_minimum_size = Vector2(170, 64)
			cb2.tooltip_text = "Сохранение, сделанное при вылете игры: " + Save.describe(Save.read_crash(sid))
			row.add_child(cb2)
		var del := _button("✕", _delete_save.bind(sid, cb))
		del.custom_minimum_size = Vector2(58, 64)
		del.tooltip_text = "Удалить сохранение"
		row.add_child(del)
		box.add_child(row)
	slots_box.add_child(_gap(10))
	slots_box.add_child(_button("Назад", func():
		if cb.is_valid():
			_open_net()
		else:
			_open_play(play_back)))
	_show("slots")


func _open_net() -> void:
	_show("net")
	net_box.open()


## Новая игра: сначала режим (ui/mode_select.gd, промпт 18.11 00:52).
func _ask_mode() -> void:
	preload("res://scripts/ui/mode_select.gd").fill(self, slots_box, _new_game, func(): _open_play(play_back))
	_show("slots")


func _pick_save(id: String, crash: bool) -> void:
	if not FirstSetup.done():
		pending_save = id
		pending_crash = crash
		_show("setup")
		return
	Engine.set_meta("eskiness_slot", id)
	Engine.set_meta("eskiness_load", Save.exists(id))
	Engine.set_meta("eskiness_crash", crash)
	Save.set_last(id)
	play_pressed.emit()


func _new_game(m: int) -> void:
	var id: String = Save.new_id()
	Engine.set_meta("eskiness_mode", m)
	Engine.set_meta("eskiness_slot", id)
	Engine.set_meta("eskiness_load", false)
	Engine.set_meta("eskiness_crash", false)
	Save.set_last(id)
	play_pressed.emit()


func _delete_save(id: String, cb: Callable) -> void:
	Save.delete(id)
	_open_loads(cb)


# ---------- настройки ----------

## Строка настройки: вкл/выкл — галочка, 3 режима (низкая/средняя/высокая, режим экрана…) — селектор «‹ значение ›»,
## непрерывные величины — ползунок (промпты 16.11 02:26, 02:32).
func setting_row(key: String) -> Control:
	var d: Array = SETTINGS[key]
	if d[3] >= 1.0 and d[2] - d[1] <= 1.0:
		return _check_row(key)
	return _select_row(key) if d[3] >= 1.0 and (d[2] - d[1] <= 2.0 or key == "cross_color") else _slider_row(key)


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


func _row_name(text: String) -> Label:
	var name_l := Label.new()
	name_l.text = text
	name_l.custom_minimum_size = Vector2(200, 0)
	name_l.add_theme_font_size_override("font_size", 24)
	name_l.add_theme_color_override("font_color", Color(0.82, 0.81, 0.77))
	return name_l


## Изменилась настройка key: пресет графики раскладывается на g_*, остальное — просто применяем.
func _changed(key: String, v: float) -> void:
	values[key] = v
	if key == "graphics":
		_apply_preset(int(round(v)))
	else:
		apply_settings()


## Селектор со стрелками: ‹ значение › — по кругу; клик по самому значению — следующее.
func _select_row(key: String) -> Control:
	var d: Array = SETTINGS[key]
	var row := HBoxContainer.new()
	row.name = key
	row.add_theme_constant_override("separation", 6)
	row.add_child(_row_name(d[0]))
	var lo := int(d[1])
	var n := int(d[2]) - lo + 1
	var val_b := Button.new()
	var step_by := func(dir: int) -> void:
		var i := posmod(int(round(float(values[key]))) - lo + dir, n) + lo
		val_b.text = _fmt(key, i).to_upper()
		_changed(key, float(i))
	row.add_child(_arrow_button("‹", func(): step_by.call(-1)))
	val_b.text = _fmt(key, values[key]).to_upper()
	val_b.focus_mode = Control.FOCUS_NONE
	val_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val_b.custom_minimum_size = Vector2(0, 40)
	val_b.add_theme_font_size_override("font_size", 22)
	val_b.add_theme_color_override("font_color", Color(0.95, 0.88, 0.78))
	val_b.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.88))
	val_b.add_theme_color_override("font_pressed_color", Color(1.0, 0.95, 0.88))
	val_b.add_theme_color_override("font_hover_pressed_color", Color(1.0, 0.95, 0.88))
	var vs := _style(Color(0.08, 0.03, 0.03, 0.8), Color(0.35, 0.08, 0.06, 0.9))
	var vh := _style(Color(0.16, 0.05, 0.03, 0.85), Color(0.7, 0.16, 0.1))
	for st in ["normal", "pressed", "disabled"]:
		val_b.add_theme_stylebox_override(st, vs)
	val_b.add_theme_stylebox_override("hover", vh)
	val_b.add_theme_stylebox_override("hover_pressed", vh)
	val_b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	val_b.pressed.connect(func(): step_by.call(1))
	row.add_child(val_b)
	row.add_child(_arrow_button("›", func(): step_by.call(1)))
	row.set_meta("val_button", val_b)
	return row


func _arrow_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(44, 40)
	b.add_theme_font_size_override("font_size", 30)
	b.add_theme_color_override("font_color", Color(0.85, 0.3, 0.2))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.55, 0.4))
	b.add_theme_color_override("font_pressed_color", Color(1.0, 0.85, 0.75))
	b.add_theme_stylebox_override("normal", _style(Color(0.05, 0.02, 0.02, 0.6), Color(0.3, 0.07, 0.05, 0.8)))
	b.add_theme_stylebox_override("hover", _style(Color(0.2, 0.05, 0.03, 0.75), Color(0.85, 0.18, 0.1)))
	b.add_theme_stylebox_override("pressed", _style(Color(0.3, 0.06, 0.04, 0.8), Color(1.0, 0.3, 0.2)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(cb)
	return b


func _slider_row(key: String) -> Control:
	var d: Array = SETTINGS[key]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.add_child(_row_name(d[0]))
	var s := make_slider(d[1], d[2], d[3], values[key])
	s.name = key
	row.add_child(s)
	var val_l := value_label()
	val_l.text = _fmt(key, s.value)
	row.add_child(val_l)
	s.value_changed.connect(func(v: float) -> void:
		val_l.text = _fmt(key, v)
		_changed(key, v))
	return row


## Ползунок в теме меню (трек, заливка, ручка — _menu_theme), растягивается на всю строку.
func make_slider(lo: float, hi: float, st: float, v: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = st
	s.value = v
	s.custom_minimum_size = Vector2(260, 36)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_NONE
	s.scrollable = false   # колесо мыши не меняет значение — только прокручивает список (промпт 23:26)
	return s


## Значение рядом с ползунком — в маленькой плашке.
func value_label() -> Label:
	var l := Label.new()
	l.custom_minimum_size = Vector2(84, 34)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.add_theme_font_size_override("font_size", 21)
	l.add_theme_color_override("font_color", Color(0.95, 0.88, 0.78))
	l.add_theme_stylebox_override("normal", _style(Color(0.08, 0.03, 0.03, 0.8), Color(0.35, 0.08, 0.06, 0.9)))
	return l


func _fmt(key: String, v: float) -> String:
	if key == "crosshair":
		return "вкл" if v > 0.5 else "выкл"
	if key == "cross_style":
		return ["точка", "крестик", "кружок"][clampi(int(round(v)), 0, 2)]
	if key == "cross_color":
		return ["белый", "зелёный", "красный", "голубой", "жёлтый"][clampi(int(round(v)), 0, 4)]
	if key == "cross_size" or key == "cross_alpha":
		return "%d%%" % int(v)
	if key == "fov":
		return "%d°" % int(v)
	if key == "window_mode":
		return ["окно", "без рамок", "полный"][clampi(int(round(v)), 0, 2)]
	if key == "resolution":
		var r: Vector2i = RESOLUTIONS[clampi(int(round(v)), 0, RESOLUTIONS.size() - 1)]
		return "авто" if r == Vector2i.ZERO else "%dx%d" % [r.x, r.y]
	if key == "graphics" or key == "g_shadow_res" or key == "g_textures" or key == "g_geometry":
		return Graphics.NAMES[clampi(int(round(v)), 0, 2)]
	if key == "g_aa":
		return ["выкл", "FXAA", "MSAA"][clampi(int(round(v)), 0, 2)]
	if key.begins_with("g_") and SETTINGS[key][2] == 1.0:
		return "вкл" if v > 0.5 else "выкл"
	if key == "g_scale" or key == "g_grass" or key == "g_particles":
		return "%d%%" % int(v)
	if key == "volume" or key == "voice_volume" or key == "ui_scale" or key == "ui_scale_split":
		return "%d%%" % int(v)
	return "%.2f" % v


func _reset() -> void:
	for key in SETTINGS:
		values[key] = SETTINGS[key][4]
		_set_widget(key)
	apply_settings()


## Один ползунок «Яркость» (20.11 14:40): сводит яркость и гамму той же кривой, что экран калибровки
## (first_setup.gd), и кнопка «Калибровка» — открыть экран с эталонными значками заново.
func _bright_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.add_child(_row_name("Яркость"))
	var s := make_slider(0.0, 1.0, 0.01, FirstSetup.from_gamma(float(values["gamma"])))
	s.name = "bright_t"
	row.add_child(s)
	var val_l := value_label()
	val_l.text = "%d%%" % int(round(s.value * 100.0))
	s.set_meta("val_l", val_l)
	row.add_child(val_l)
	s.value_changed.connect(func(t: float) -> void:
		val_l.text = "%d%%" % int(round(t * 100.0))
		var gb := FirstSetup.curve(t)
		values["gamma"] = gb.x
		values["brightness"] = gb.y
		apply_settings())
	var cb := _button("Калибровка", func() -> void:
		_save()
		setup_back = "settings"
		setup_box.call("sync")
		_show("setup"))
	cb.custom_minimum_size = Vector2(170, 40)
	cb.add_theme_font_size_override("font_size", 19)
	row.add_child(cb)
	return row


## Обновить ползунок/галочку под values[key] (виджет может быть на странице настроек или «Графика»).
func _set_widget(key: String) -> void:
	if key == "brightness" or key == "gamma":
		var bs: Node = settings_box.find_child("bright_t", true, false)
		if bs is HSlider:
			bs.set_value_no_signal(FirstSetup.from_gamma(float(values["gamma"])))
			bs.get_meta("val_l").text = "%d%%" % int(round(bs.value * 100.0))
		return
	for box in [settings_box]:
		var s: Node = box.find_child(key, true, false)
		if s is HSlider:
			s.value = values[key]
		elif s is CheckBox:
			s.button_pressed = values[key] > 0.5
		elif s and s.has_meta("val_button"):
			s.get_meta("val_button").text = _fmt(key, values[key]).to_upper()


## Пресет графики выставляет все отдельные настройки g_*.
func _apply_preset(q: int) -> void:
	var d := Graphics.preset(q)
	for k in d:
		values[k] = d[k]
		_set_widget(k)
	apply_settings()


## Размер интерфейса: 100% = прежний размер ×1.25, ползунок 80–120%.
## Масштаб не даём сделать таким, чтобы большие окна (инвентарь ~1200×480, магазин ~760×650) вылезли за экран
## (на телефоне 20:9 по высоте остаётся мало места — считаем по 660).
func _apply_ui_scale() -> void:
	var win := get_tree().root
	var want := _auto_ui_scale() * float(values.get("ui_scale", 100.0)) / 100.0
	var sz := Vector2(win.size)
	if sz.x > 0 and sz.y > 0:
		if win.content_scale_mode != Window.CONTENT_SCALE_MODE_DISABLED:
			# телефон (stretch canvas_items + expand): экран уже растянут под базу 1280×720 —
			# считаем в логических единицах: короткая сторона базы, длинная — по соотношению сторон
			var base := Vector2(win.content_scale_size)
			var ratio := sz.x / sz.y
			sz = Vector2(base.y * ratio, base.y) if ratio >= base.x / base.y else Vector2(base.x, base.x / ratio)
		want = minf(want, maxf(minf(sz.x / 1240.0, sz.y / 660.0), 0.8))
	win.content_scale_factor = want


## Базовый масштаб интерфейса под монитор (промпт 20.11 14:53): 1.25 на 1080p, крупнее на 1440p/4K
## (по высоте экрана); меньшие экраны дожимает ограничение по размеру окон в _apply_ui_scale. Телефон — 1.25.
func _auto_ui_scale() -> float:
	var win := get_tree().root
	if win.content_scale_mode != Window.CONTENT_SCALE_MODE_DISABLED:
		return 1.25
	var h := float(DisplayServer.screen_get_size(DisplayServer.window_get_current_screen()).y)
	return 1.25 * clampf(h / 1080.0, 1.0, 3.0)


func apply_settings() -> void:
	_apply_window()
	_apply_ui_scale()
	Graphics.apply(get_tree(), values)
	PlayerScript.look_sens = values["sensitivity"]
	PlayerScript.fov_base = values.get("fov", PlayerScript.FOV)
	if get_parent():
		for c in get_parent().get_children():
			if c is PlayerScript and c.cam:
				c.cam.fov = PlayerScript.fov_base   # сразу, без ожидания плавного перехода
	var hud_s := preload("res://scripts/ui/hud.gd")
	hud_s.show_crosshair = values.get("crosshair", 1.0) > 0.5
	hud_s.cross_style = int(round(float(values.get("cross_style", 0.0))))
	hud_s.cross_color = int(round(float(values.get("cross_color", 0.0))))
	hud_s.cross_size = float(values.get("cross_size", 100.0))
	hud_s.cross_alpha = float(values.get("cross_alpha", 35.0))
	var vol: float = values["volume"] / 100.0
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(vol, 0.0001)))
	preload("res://scripts/network/voip.gd").voice_vol = float(values.get("voice_volume", 60.0)) / 100.0
	if post_mat:
		post_mat.set_shader_parameter("brightness", values["brightness"])
		post_mat.set_shader_parameter("gamma", values["gamma"])
		# галочка: вкл — всегда 50% (34 уровня), выкл — 0% (64 уровня, постеризации почти нет)
		post_mat.set_shader_parameter("levels", lerpf(64.0, 4.0, 0.5))
		post_mat.set_shader_parameter("posterize", 1.0 if values["posterize"] > 0.5 else 0.0)


static func _mobile() -> bool:
	return OS.has_feature("mobile") or preload("res://scripts/ui/touch_controls.gd").wanted()


var _win_applied := -1
var _res_applied := -1

## Режим экрана: 0 — окно с рамкой (≈75% экрана или выбранное разрешение, по центру),
## 1 — окно без рамок во весь экран (или выбранное разрешение, по центру), 2 — полноэкранный (нативное разрешение).
func _apply_window() -> void:
	if _mobile() or DisplayServer.get_name() == "headless":
		return
	var m := clampi(int(round(float(values.get("window_mode", 2.0)))), 0, 2)
	var r := clampi(int(round(float(values.get("resolution", 0.0)))), 0, RESOLUTIONS.size() - 1)
	if m == _win_applied and r == _res_applied:
		return
	_win_applied = m
	_res_applied = r
	var scr := DisplayServer.window_get_current_screen()
	var ss := DisplayServer.screen_get_size(scr)
	var sp := DisplayServer.screen_get_position(scr)
	match m:
		2:
			# полный экран: сначала снять рамку/запрет ресайза (иначе на некоторых системах
			# EXCLUSIVE_FULLSCREEN остаётся визуально похож на оконный без рамок — промпт 01:33 18.11)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		1:
			var ws1: Vector2i = RESOLUTIONS[r] if RESOLUTIONS[r] != Vector2i.ZERO else ss
			ws1 = Vector2i(mini(ws1.x, ss.x), mini(ws1.y, ss.y))
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED, true)
			DisplayServer.window_set_size(ws1)
			@warning_ignore("integer_division")
			DisplayServer.window_set_position(sp + (ss - ws1) / 2)
		_:
			var ws: Vector2i = RESOLUTIONS[r] if RESOLUTIONS[r] != Vector2i.ZERO else Vector2i(1280, 720)
			ws = Vector2i(mini(ws.x, ss.x), mini(ws.y, ss.y))
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED, false)
			DisplayServer.window_set_size(ws)
			@warning_ignore("integer_division")
			DisplayServer.window_set_position(sp + (ss - ws) / 2)


## F11 и значок в углу: полноэкранный ↔ оконный (без рамок, если он был выбран), сохраняется в настройки.
var _last_windowed := 0.0

func toggle_fullscreen() -> void:
	if _mobile():
		return
	var cur := float(values.get("window_mode", 2.0))
	if cur >= 1.5:
		values["window_mode"] = _last_windowed
	else:
		_last_windowed = cur
		values["window_mode"] = 2.0
	_set_widget("window_mode")
	apply_settings()
	_save()


func _load() -> void:
	var cf := ConfigFile.new()
	var ok := cf.load(CFG) == OK
	for key in SETTINGS:
		values[key] = cf.get_value("settings", key, SETTINGS[key][4]) if ok else SETTINGS[key][4]
	values["posterize"] = 1.0 if float(values["posterize"]) > 0.5 else 0.0   # был ползунок 0..100
	# старые настройки без отдельных g_* — берём их из сохранённого пресета
	if ok and cf.has_section_key("settings", "graphics") and not cf.has_section_key("settings", "g_shadows"):
		var d := Graphics.preset(int(round(float(values["graphics"]))))
		for k in d:
			values[k] = d[k]
	# телефон, первый запуск (в cfg ещё нет графики) — пресет «низкая»
	if preload("res://scripts/ui/touch_controls.gd").wanted() and not (ok and cf.has_section_key("settings", "graphics")):
		values["graphics"] = 0.0
		var lo := Graphics.preset(0)
		for k in lo:
			values[k] = lo[k]
	# переназначения клавиш читает Controls (scripts/controls/bindings.gd: user://controls.cfg, старые — из [controls] тут)


func _save() -> void:
	var cf := ConfigFile.new()
	cf.load(CFG)   # другие секции (имя в сети — [net]) не теряем
	if cf.has_section("settings"):
		cf.erase_section("settings")
	for key in values:
		cf.set_value("settings", key, values[key])
	cf.save(CFG)   # секцию [controls] не трогаем: переназначения теперь в user://controls.cfg (Controls)


# ---------- управление ----------

## По умолчанию — из таблицы (Controls): [основная, альтернативная].
func _default_binds(action: String) -> Array:
	return Controls.kb_default(action)


## Всегда два элемента: [основная, альтернативная] ("" — нет).
func _binds_of(action: String) -> Array:
	return Controls.kb_of(action).slice(0, 2)


## Действия и клавиши ставит Controls (по таблице и переназначениям); оси геймпада — gamepad.gd по Controls.binds_changed.
func _apply_binds() -> void:
	Controls.apply()


func _spec_name(spec: String) -> String:
	return preload("res://scripts/controls/glyphs.gd").kb_name(spec)


func _bind_text(action: String, idx: int) -> String:
	var spec: String = _binds_of(action)[idx]
	return _spec_name(spec) if spec != "" else "—"


## Строка: подпись, основная клавиша, альтернативная (клик — назначить, Delete — убрать, Esc — отмена).
func _bind_row(action: String, label: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var name_l := Label.new()
	name_l.text = label
	name_l.custom_minimum_size = Vector2(320, 0)
	name_l.add_theme_font_size_override("font_size", 22)
	name_l.add_theme_color_override("font_color", Color(0.82, 0.81, 0.77))
	row.add_child(name_l)
	var btns: Array = []
	for idx in 2:
		var b := Button.new()
		b.custom_minimum_size = Vector2(200, 34)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 20)
		b.add_theme_color_override("font_color", Color(0.9, 0.86, 0.76) if idx == 0 else Color(0.75, 0.72, 0.66))
		b.add_theme_color_override("font_hover_color", Color(1.0, 0.92, 0.82))
		b.add_theme_stylebox_override("normal", _style(Color(0.06, 0.03, 0.03, 0.8), Color(0.45, 0.1, 0.07)))
		b.add_theme_stylebox_override("hover", _style(Color(0.2, 0.05, 0.03, 0.85), Color(0.85, 0.18, 0.1)))
		b.add_theme_stylebox_override("pressed", _style(Color(0.3, 0.05, 0.03, 0.9), Color(1.0, 0.3, 0.2)))
		b.text = _bind_text(action, idx)
		b.tooltip_text = "Основная клавиша" if idx == 0 else "Альтернативная клавиша (Delete — убрать)"
		b.pressed.connect(func(): _start_wait(action, idx))
		row.add_child(b)
		btns.append(b)
	ctl_rows[action] = btns
	return row


func _start_wait(action: String, idx := 0) -> void:
	_stop_wait()
	waiting_action = action
	waiting_idx = idx
	ctl_rows[action][idx].text = "нажмите клавишу…"


func _stop_wait() -> void:
	if waiting_action != "" and ctl_rows.has(waiting_action):
		ctl_rows[waiting_action][waiting_idx].text = _bind_text(waiting_action, waiting_idx)
	waiting_action = ""


## Назначить клавишу в ячейку idx ("" — убрать). Если она уже у другого действия — там она заменяется
## старой клавишей этой ячейки (обмен), у этого же действия во второй ячейке — убирается.
func _assign(action: String, spec: String, idx := 0) -> void:
	waiting_action = ""
	var mine := _binds_of(action)
	var old: String = mine[idx]
	if spec != "":
		for c in CONTROLS:
			var other: String = c[0]
			if other == action:
				continue
			var ob := _binds_of(other)
			var k := ob.find(spec)
			if k >= 0:
				ob[k] = old
				Controls.kb_user()[other] = ob
		if mine[1 - idx] == spec:
			mine[1 - idx] = ""
	mine[idx] = spec
	Controls.set_kb(action, mine)   # сохраняет в user://controls.cfg и обновляет InputMap
	_refresh_binds()


func _reset_binds() -> void:
	waiting_action = ""
	Controls.reset_kb()
	_refresh_binds()


func _refresh_binds() -> void:
	for a in ctl_rows:
		for idx in 2:
			ctl_rows[a][idx].text = _bind_text(a, idx)


## Переключить категорию настроек: показать её страницу, подсветить кнопку слева.
func _set_cat(id: String) -> void:
	_stop_wait()
	cat = id
	gen_box.visible = id == "general"
	aim_box.visible = id == "aim"
	gfx_box.visible = id == "gfx"
	ctl_box.visible = id == "controls"
	for k in cat_btns:
		_mark_btn(cat_btns[k], k == id)


## «Клавиатура и мышь» / «Геймпад» на странице «Управление».
func _set_dev(id: String) -> void:
	_stop_wait()
	for n in kb_nodes:
		n.visible = id == "kb"
	pad_page.visible = id == "pad"
	if id == "pad":
		pad_page.refresh()
	for k in dev_btns:
		_mark_btn(dev_btns[k], k == id)


## Вкладка раздела «Управления»: показать её бинды, подсветить кнопку.
func _set_ctl_tab(i: int) -> void:
	_stop_wait()
	for k in ctl_groups.size():
		ctl_groups[k].visible = k == i
		_mark_btn(ctl_tabs[k], k == i)


## Подсветка активной кнопки (категории/вкладки).
func _mark_btn(b: Button, on: bool) -> void:
	if on:
		b.add_theme_stylebox_override("normal", _btn_style(Color(0.3, 0.05, 0.03, 0.7), Color(1.0, 0.3, 0.2), 8, 30))
		b.add_theme_color_override("font_color", Color(1.0, 0.92, 0.82))
	else:
		b.add_theme_stylebox_override("normal", _btn_style(Color(0.04, 0.02, 0.02, 0.55), Color(0.45, 0.08, 0.05, 0.85), 4, 22))
		b.add_theme_color_override("font_color", Color(0.8, 0.77, 0.7))


## «По умолчанию» — только для открытой категории.
func _reset_cat() -> void:
	if cat == "controls" and pad_page and pad_page.visible:
		pad_page.pad.reset_custom()   # «По умолчанию» на странице геймпада (игрока, открытого на ней) — «Свой» = стандартная раскладка
		pad_page.refresh()
		return
	if cat == "controls":
		_reset_binds()
		return
	for key in SETTINGS:
		var kcat := "general" if key in GENERAL_KEYS else ("aim" if key in AIM_KEYS else "gfx")
		if kcat == cat:
			values[key] = SETTINGS[key][4]
			_set_widget(key)
	apply_settings()


## Прокручиваемый список строк на странице настроек.
func _page_rows(page: Control, h: float) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(660, h)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(sc)
	var r := VBoxContainer.new()
	r.add_theme_constant_override("separation", 6)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(r)
	return r


# ---------- оформление ----------

func _vbox(parent: Control) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", 12)
	b.size_flags_horizontal = Control.SIZE_SHRINK_END if parent is VBoxContainer else Control.SIZE_SHRINK_CENTER
	parent.add_child(b)
	return b


## Шрифты меню (промпт 14.11 19:00) — системные, без файлов, с цепочкой запасных:
## основной — спокойный технический узкий гротеск (Windows: Bahnschrift SemiCondensed; Android: sans-serif-condensed),
## заголовки — чистый жирный узкий (Windows: Impact; Android: sans-serif-condensed bold). RubikDirt — только на вывеске автомата.
const OUTLINE := Color(0, 0, 0, 0.95)
static var _body_cache: Font
static var _head_cache: Font


func _menu_font() -> Font:
	if _body_cache:
		return _body_cache
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Bahnschrift SemiBold SemiConden", "Bahnschrift", "Segoe UI Semibold", "Arial Narrow",
		"sans-serif-condensed", "Roboto Condensed", "sans-serif-medium", "sans-serif"])
	sf.font_weight = 600
	sf.font_stretch = 87
	var fv := FontVariation.new()
	fv.base_font = sf
	fv.spacing_glyph = 1
	_body_cache = fv
	return _body_cache


func _head_font() -> Font:
	if _head_cache:
		return _head_cache
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Impact", "Bahnschrift Bold Condensed", "Bahnschrift", "Arial Narrow",
		"sans-serif-condensed", "Roboto Condensed", "sans-serif"])
	sf.font_weight = 700
	sf.font_stretch = 75
	var fv := FontVariation.new()
	fv.base_font = sf
	fv.spacing_glyph = 2
	_head_cache = fv
	return _head_cache


## Тема на корне меню: всем подписям, кнопкам и галочкам — основной шрифт и чёрная обводка.
func _menu_theme() -> Theme:
	var th := Theme.new()
	th.default_font = _menu_font()
	for type in ["Label", "Button", "CheckBox"]:
		th.set_color("font_outline_color", type, OUTLINE)
		th.set_constant("outline_size", type, 5)
	# ползунки (промпт 16.11 02:26): тёмный трек, красная заливка до ручки, светлая ручка-планка
	var track := _style(Color(0.06, 0.03, 0.03, 0.9), Color(0.3, 0.07, 0.05, 0.9))
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	th.set_stylebox("slider", "HSlider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.62, 0.12, 0.07)
	fill.set_corner_radius_all(3)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	th.set_stylebox("grabber_area", "HSlider", fill)
	var fill_hi := fill.duplicate() as StyleBoxFlat
	fill_hi.bg_color = Color(0.85, 0.2, 0.1)
	th.set_stylebox("grabber_area_highlight", "HSlider", fill_hi)
	th.set_icon("grabber", "HSlider", _grabber_icon(false))
	th.set_icon("grabber_highlight", "HSlider", _grabber_icon(true))
	th.set_icon("grabber_disabled", "HSlider", _grabber_icon(false))
	return th


## Ручка ползунка: светлая вертикальная планка с тёмной обводкой и красной серединкой.
func _grabber_icon(hi: bool) -> ImageTexture:
	const W := 16
	const H := 30
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.02, 0.01, 0.01, 0.95))
	img.fill_rect(Rect2i(2, 2, W - 4, H - 4), Color(1.0, 0.93, 0.84) if hi else Color(0.86, 0.8, 0.7))
	img.fill_rect(Rect2i(7, 7, 2, H - 14), Color(0.85, 0.2, 0.1) if hi else Color(0.55, 0.12, 0.07))
	return ImageTexture.create_from_image(img)


func _title(text: String, size: int) -> Label:
	var t := Label.new()
	t.text = text
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	t.add_theme_font_override("font", _head_font())
	t.add_theme_font_size_override("font_size", size)
	t.add_theme_color_override("font_color", Color(0.88, 0.84, 0.76))
	t.add_theme_color_override("font_outline_color", OUTLINE)
	@warning_ignore("integer_division")
	t.add_theme_constant_override("outline_size", clampi(size / 9, 6, 12))
	# лёгкая тёмно-красная тень — характер без шума
	t.add_theme_color_override("font_shadow_color", Color(0.45, 0.04, 0.02, 0.6))
	t.add_theme_constant_override("shadow_offset_x", 3)
	t.add_theme_constant_override("shadow_offset_y", 4)
	return t


func _subtitle(text: String) -> Label:
	var t := Label.new()
	t.text = text
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	t.add_theme_font_override("font", _menu_font())
	t.add_theme_font_size_override("font_size", 22)
	t.add_theme_color_override("font_color", Color(0.72, 0.6, 0.5))
	t.add_theme_color_override("font_outline_color", OUTLINE)
	t.add_theme_constant_override("outline_size", 5)
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
	b.add_theme_color_override("font_outline_color", OUTLINE)
	b.add_theme_constant_override("outline_size", 6)
	b.add_theme_stylebox_override("normal", _btn_style(Color(0.04, 0.02, 0.02, 0.55), Color(0.45, 0.08, 0.05, 0.85), 4, 22))
	b.add_theme_stylebox_override("hover", _btn_style(Color(0.22, 0.05, 0.03, 0.6), Color(0.85, 0.18, 0.1), 8, 34))
	b.add_theme_stylebox_override("pressed", _btn_style(Color(0.3, 0.05, 0.03, 0.7), Color(1.0, 0.3, 0.2), 8, 36))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(cb)
	return b


func _btn_style(bg: Color, accent: Color, bar: int, pad_left: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = accent
	s.border_width_left = bar
	s.border_width_bottom = 1
	s.content_margin_left = pad_left
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
