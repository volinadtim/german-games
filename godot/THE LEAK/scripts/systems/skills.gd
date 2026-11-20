extends CanvasLayer
## Древо прокачки (промпт 20.11 18:06): окно на K (геймпад — Back + L3), навыки покупаются за монеты.
## Вид (промпт 20.11 18:54): вкладки-разделы, в каждой — древо узлов со связями от центрального «хаба».
## Древо тянут мышью (панорама), колесо / + − / LT RT — масштаб, Q E / LB RB — вкладки, Home / R3 — вписать,
## WASD — сдвиг. Узел: наведи — описание справа, клик / A — изучить; при покупке — вспышка и пульс узла.
## Разделы добавляются через add_section() — активные навыки здесь, пассивные (systems/perks.gd) и атрибуты
## (systems/levels.gd) регистрируются сами; их древа строятся из Perks.TREE / Levels.ATTRS (все уровни веткой).
## Купленное — owned {id: уровень}; проверка — has(id) / level(id). Сохраняется в сейв ("skills").

const Perks := preload("res://scripts/systems/perks.gd")
const Levels := preload("res://scripts/systems/levels.gd")
const WIN_CD := 10   # «двойной выигрыш»: после срабатывания ждёт столько наград
const GRID := Vector2(215, 112)   # шаг сетки древа: колонка, ряд
const NODE := Vector2(176, 72)    # размер узла
const ZMIN := 0.35
const ZMAX := 1.8
const GOLD := Color(1.0, 0.8, 0.35)
const BLUE := Color(0.5, 0.78, 1.0)
const DIMC := Color(0.33, 0.33, 0.31)
const ROMAN := ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]

var game
var open := false
var owned := {}          # id → уровень (1 = куплен)
var win_cd := 0          # сколько наград осталось до перезарядки «двойного выигрыша»
var xp := 0              # опыт персонажа (systems/levels.gd)
var attrs := {}          # атрибут → уровень (systems/levels.gd)
var sections: Array = [] # [{title, items: [{id, name, desc, cost, req}]}]
var _coins_l: Label
var _lvl_l: Label
var _xp_l: Label
var _xp_bar: ProgressBar
var _tabs: HBoxContainer
var _view: Control       # область древа (обрезает, ловит панораму и зум)
var _canvas: Control     # само древо: двигается и масштабируется
var _d_name: Label
var _d_state: Label
var _d_desc: Label
var _d_price: Label
var _d_btn: Button
var _cur := 0            # текущая вкладка
var _nodes := {}         # key → узел {key, name, sub, desc, state, price, can, pos, from, buy}
var _btns := {}          # key → Button
var _hub := Vector2.ZERO
var _sel := ""
var _zoom := 1.0
var _zoom_t := 1.0
var _pan := Vector2.ZERO
var _pan_t := Vector2.ZERO
var _need_fit := true
var _intro := true
var _drag := false
var _bursts: Array = []  # [центр, время, поворот]
var _sb_can: StyleBoxFlat
var _sb_focus: StyleBoxFlat


func _ready() -> void:
	layer = 20
	visible = false
	if not InputMap.has_action("skills"):
		InputMap.add_action("skills")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_K
		InputMap.action_add_event("skills", ev)
	add_section("АКТИВНЫЕ НАВЫКИ", [
		{"id": "slide", "name": "Подкат", "cost": 30,
			"desc": "Присед на бегу — скольжение, прыжок из него даёт рывок вперёд"},
		{"id": "double_jump", "name": "Двойной прыжок", "cost": 60, "req": "slide",
			"desc": "Ещё один прыжок в воздухе"},
		{"id": "double_win", "name": "Двойной выигрыш", "cost": 120, "req": "double_jump",
			"desc": "Следующая награда KILLBOX ×2. Перезарядка — %d наград" % WIN_CD},
	])
	_build()


## Добавить раздел навыков (вкладку окна). items: [{id, name, desc, cost, req?, nodisc?}]
## или Callable, возвращающий такой массив (пересобирается при каждой перестройке — systems/perks.gd).
func add_section(title: String, items: Variant) -> void:
	for s in sections:
		if s["title"] == title:
			s["items"] = items
			_rebuild()
			return
	sections.append({"title": title, "items": items})
	_rebuild()


## Куплен ли навык.
func has(id: String) -> bool:
	return int(owned.get(id, 0)) > 0


## Уровень навыка (0 — не куплен).
func level(id: String) -> int:
	return int(owned.get(id, 0))


## Награда KILLBOX своего спина: true — удвоить её (навык заряжен), иначе отсчёт перезарядки.
func on_reward() -> bool:
	if not has("double_win"):
		return false
	if win_cd <= 0:
		win_cd = WIN_CD
		if game and game.hud:
			game.hud.toast("Двойной выигрыш! Перезарядка — %d наград" % WIN_CD, Color(1.0, 0.85, 0.3))
		return true
	win_cd -= 1
	if win_cd == 0 and game and game.hud:
		game.hud.toast("Двойной выигрыш заряжен", Color(1.0, 0.85, 0.3))
	return false


## Данные для сейва.
func to_save() -> Dictionary:
	return {"owned": owned.duplicate(), "win_cd": win_cd, "xp": xp, "attrs": attrs.duplicate()}


## Загрузка из сейва.
func from_save(d: Dictionary) -> void:
	owned = {}
	var o: Dictionary = d.get("owned", {})
	for k in o:
		owned[String(k)] = int(o[k])
	win_cd = int(d.get("win_cd", 0))
	xp = int(d.get("xp", 0))
	attrs = {}
	var a: Dictionary = d.get("attrs", {})
	for k in a:
		attrs[String(k)] = clampi(int(a[k]), 0, Levels.MAX_ATTR)
	Levels.apply()   # максимум здоровья
	_rebuild()


## Открыть окно.
func show_window() -> void:
	if open or game == null or not game.alive or game.window_open():
		return
	open = true
	visible = true
	game.player.active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_intro = true
	_need_fit = true
	_rebuild()


## Закрыть окно.
func close() -> void:
	if not open:
		return
	open = false
	visible = false
	_drag = false
	if game and game.player and game.alive:
		game.player.active = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(e: InputEvent) -> void:
	if e.is_echo() or not e.is_pressed():
		return
	if game != null and game.player != null and (game.player.input_locks.has("console") or game.player.input_locks.has("chat")):
		return   # пока открыта консоль/чат, клавиши идут только в поле ввода
	if open:
		if e.is_action_pressed("skills") or e.is_action_pressed("ui_cancel") or e.is_action_pressed("inventory"):
			close()
			get_viewport().set_input_as_handled()
			return
		if e is InputEventKey:
			match e.physical_keycode:
				KEY_Q: _tab(-1)
				KEY_E: _tab(1)
				KEY_EQUAL, KEY_KP_ADD: _zoom_by(1.2, _view.size / 2)
				KEY_MINUS, KEY_KP_SUBTRACT: _zoom_by(1.0 / 1.2, _view.size / 2)
				KEY_HOME: _need_fit = true
				_: return
			get_viewport().set_input_as_handled()
		elif e is InputEventJoypadButton:
			match e.button_index:
				JOY_BUTTON_LEFT_SHOULDER: _tab(-1)
				JOY_BUTTON_RIGHT_SHOULDER: _tab(1)
				JOY_BUTTON_RIGHT_STICK: _need_fit = true
				_: return
			get_viewport().set_input_as_handled()
	elif e.is_action_pressed("skills"):
		show_window()
		if open:
			get_viewport().set_input_as_handled()


## Плавный зум/панорама, WASD, курки геймпада, пульс доступных узлов, анимация связей.
func _process(delta: float) -> void:
	if not open or _view == null:
		return
	if _need_fit and _view.size.x > 10:
		_fit()
	var mv := Vector2(float(Input.is_physical_key_pressed(KEY_A)) - float(Input.is_physical_key_pressed(KEY_D)),
		float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S)))
	if mv != Vector2.ZERO:
		_pan_t += mv * 750.0 * delta
	for d in Input.get_connected_joypads():
		var zt := Input.get_joy_axis(d, JOY_AXIS_TRIGGER_RIGHT) - Input.get_joy_axis(d, JOY_AXIS_TRIGGER_LEFT)
		if absf(zt) > 0.2:
			_zoom_by(pow(2.0, zt * delta * 1.6), _view.size / 2)
			break
	var k := 1.0 - exp(-delta * 14.0)
	_zoom = lerpf(_zoom, _zoom_t, k)
	_pan = _pan.lerp(_pan_t, k)
	_canvas.position = _pan
	_canvas.scale = Vector2.ONE * _zoom
	var t := Time.get_ticks_msec() / 1000.0
	var p := 0.5 + 0.5 * sin(t * 4.0)
	_sb_can.shadow_color = Color(BLUE, 0.2 + 0.35 * p)
	_sb_can.border_color = BLUE.lerp(Color.WHITE, 0.6 * p)
	_view.queue_redraw()
	_canvas.queue_redraw()


## Каркас окна: затемнение, панель, шапка (уровень, опыт, очки, монеты), вкладки, древо, описание.
func _build() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 48
	panel.offset_top = 34
	panel.offset_right = -48
	panel.offset_bottom = -34
	var sb := _sb(Color(0.06, 0.06, 0.055, 0.97), Color(0.55, 0.45, 0.25), 2, Color(GOLD, 0.15), 18)
	sb.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", sb)
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	# шапка
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	v.add_child(top)
	top.add_child(_label("ПРОКАЧКА", 30, GOLD))
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 2)
	top.add_child(lv)
	_lvl_l = _label("", 16, Color(0.95, 0.93, 0.88))
	lv.add_child(_lvl_l)
	_xp_bar = ProgressBar.new()
	_xp_bar.show_percentage = false
	_xp_bar.custom_minimum_size = Vector2(240, 10)
	_xp_bar.add_theme_stylebox_override("background", _sb(Color(0.12, 0.12, 0.12), Color(0.3, 0.28, 0.2), 1, Color(0, 0, 0, 0), 0))
	_xp_bar.add_theme_stylebox_override("fill", _sb(Color(0.45, 0.8, 1.0), Color(0.75, 0.92, 1.0), 0, Color(BLUE, 0.5), 6))
	lv.add_child(_xp_bar)
	_xp_l = _label("", 12, Color(0.6, 0.65, 0.7))
	lv.add_child(_xp_l)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	_coins_l = _label("", 20, Color(1.0, 0.85, 0.45))
	top.add_child(_coins_l)
	var x := Button.new()
	x.text = "  ✕  "
	x.focus_mode = Control.FOCUS_NONE
	x.pressed.connect(close)
	top.add_child(x)
	# вкладки
	var tabs_row := HBoxContainer.new()
	tabs_row.add_theme_constant_override("separation", 10)
	tabs_row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(tabs_row)
	tabs_row.add_child(_label("Q / LB  «", 15, Color(0.6, 0.6, 0.55)))
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 8)
	tabs_row.add_child(_tabs)
	tabs_row.add_child(_label("»  E / RB", 15, Color(0.6, 0.6, 0.55)))
	# древо + описание
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	v.add_child(body)
	_view = Control.new()
	_view.clip_contents = true
	_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_view.mouse_default_cursor_shape = Control.CURSOR_DRAG
	_view.gui_input.connect(_view_input)
	_view.draw.connect(_draw_bg)
	body.add_child(_view)
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_links)
	_view.add_child(_canvas)
	var dp := PanelContainer.new()
	dp.custom_minimum_size = Vector2(310, 0)
	var dsb := _sb(Color(0.09, 0.09, 0.085), Color(0.3, 0.27, 0.2), 1, Color(0, 0, 0, 0), 0)
	dsb.set_content_margin_all(14)
	dp.add_theme_stylebox_override("panel", dsb)
	body.add_child(dp)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 10)
	dp.add_child(dv)
	_d_name = _label("", 22, GOLD)
	_d_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dv.add_child(_d_name)
	_d_state = _label("", 15, BLUE)
	_d_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dv.add_child(_d_state)
	_d_desc = _label("", 15, Color(0.78, 0.78, 0.72))
	_d_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_d_desc.custom_minimum_size = Vector2(280, 0)
	dv.add_child(_d_desc)
	_d_price = _label("", 17, Color(1.0, 0.85, 0.45))
	dv.add_child(_d_price)
	_d_btn = Button.new()
	_d_btn.custom_minimum_size = Vector2(0, 40)
	_d_btn.pressed.connect(func(): _press(_sel))
	dv.add_child(_d_btn)
	var sp2 := Control.new()
	sp2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dv.add_child(sp2)
	var help := _label("Наведи на узел — описание\nКлик / A — изучить\nТяни мышью / WASD — двигать\nКолесо, + −, LT / RT — масштаб\nQ E, LB RB — вкладки\nHome / R3 — вписать древо\nK / B — закрыть", 13, Color(0.55, 0.55, 0.5))
	dv.add_child(help)
	_sb_can = _sb(Color(0.07, 0.13, 0.21), BLUE, 2, Color(BLUE, 0.4), 12)
	_sb_focus = _sb(Color(0, 0, 0, 0), Color.WHITE, 3, Color(1, 1, 1, 0.35), 10)
	_sb_focus.draw_center = false
	_sb_focus.set_expand_margin_all(5)
	_rebuild()


## Перестроить окно (после покупки, загрузки, нового раздела, смены вкладки).
func _rebuild() -> void:
	if _view == null:
		return
	var pr: Array = Levels.progress()
	_lvl_l.text = "Уровень %d" % Levels.level()
	_xp_bar.max_value = maxi(int(pr[1]), 1)
	_xp_bar.value = float(pr[0]) if int(pr[1]) > 0 else _xp_bar.max_value
	_xp_l.text = ("опыт %d / %d" % [pr[0], pr[1]]) if int(pr[1]) > 0 else "максимальный уровень"
	_coins_l.text = "Очки: %d     Монеты: %d   " % [Levels.points(), _coins()]
	_cur = clampi(_cur, 0, maxi(sections.size() - 1, 0))
	for c in _tabs.get_children():
		c.queue_free()
	for i in sections.size():
		var tb := Button.new()
		tb.text = "  %s  " % sections[i]["title"]
		tb.add_theme_font_size_override("font_size", 16)
		var on := i == _cur
		var tsb := _sb(Color(0.22, 0.17, 0.07) if on else Color(0.1, 0.1, 0.1), GOLD if on else Color(0.3, 0.3, 0.28), 2 if on else 1, Color(GOLD, 0.35) if on else Color(0, 0, 0, 0), 8 if on else 0)
		tsb.set_content_margin_all(6)
		for st in ["normal", "hover", "pressed"]:
			tb.add_theme_stylebox_override(st, tsb)
		tb.add_theme_stylebox_override("focus", _sb_focus)
		tb.add_theme_color_override("font_color", GOLD if on else Color(0.75, 0.75, 0.7))
		tb.pressed.connect(func(): _tab(i - _cur))
		_tabs.add_child(tb)
	var foc := ""
	var fo: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	for k in _btns:
		if _btns[k] == fo:
			foc = k
	for c in _canvas.get_children():
		c.queue_free()
	_btns.clear()
	_nodes.clear()
	if sections.is_empty():
		return
	for nd in _graph(sections[_cur]):
		_nodes[nd["key"]] = nd
	for k in _nodes:
		var b := _node_btn(_nodes[k])
		_canvas.add_child(b)
		_btns[k] = b
	if foc != "" and _btns.has(foc):
		(_btns[foc] as Button).grab_focus.call_deferred()
	if not _nodes.has(_sel):
		_sel = ""
		for k in _nodes:
			if _sel == "" or (_nodes[k]["state"] == "avail" and _nodes[_sel]["state"] != "avail"):
				_sel = k
	_show_details("")


## Узлы древа раздела: пассивные и атрибуты — ветки уровней, остальное — по цепочкам req.
func _graph(s: Dictionary) -> Array:
	match String(s["title"]):
		"ПАССИВНЫЕ":
			return _graph_rows(Perks.TREE, true)
		"АТРИБУТЫ":
			return _graph_rows(Levels.ATTRS, false)
	return _graph_req(_items(s))


## Древо по req: колонка — глубина цепочки, хаб слева.
func _graph_req(items: Array) -> Array:
	_hub = Vector2.ZERO
	var by := {}
	for it in items:
		by[String(it["id"])] = it
	var depth := {}
	for _pass in 8:
		for id in by:
			var rq := String(by[id].get("req", ""))
			depth[id] = (int(depth.get(rq, 0)) + 1) if by.has(rq) else 1
	var cols := {}
	for id in by:
		var d: int = depth[id]
		if not cols.has(d):
			cols[d] = []
		cols[d].append(id)
	var out: Array = []
	var coins := _coins()
	for d in cols:
		var ids: Array = cols[d]
		for i in ids.size():
			var id: String = ids[i]
			var it: Dictionary = by[id]
			var rq := String(it.get("req", ""))
			var got := has(id)
			var locked := rq != "" and not has(rq)
			var cost := int(it.get("cost", 0)) if it.get("nodisc", false) else Perks.cost(int(it.get("cost", 0)))   # прокачка «Скидка»
			var sub := ""
			if id == "double_win" and got:
				sub = "заряжен" if win_cd <= 0 else "ещё %d наград" % win_cd
			out.append({"key": id, "name": String(it["name"]), "sub": sub, "desc": String(it.get("desc", "")),
				"state": "owned" if got else ("locked" if locked else "avail"), "attr": false,
				"price": "%d монет" % cost, "can": not got and not locked and coins >= cost,
				"pos": Vector2(d, i - (ids.size() - 1) / 2.0), "from": rq if by.has(rq) else "hub",
				"buy": func(): _buy(id, cost)})
	return out


## Древо веток уровней: ряд — ветка (удача, скорость…), колонка — уровень, хаб слева посередине.
func _graph_rows(tree: Array, perks: bool) -> Array:
	_hub = Vector2(0, (tree.size() - 1) / 2.0) * GRID
	var out: Array = []
	var coins := _coins()
	for r in tree.size():
		var b: Array = tree[r]
		var id := String(b[0])
		var nm := String(b[1])
		var prices: Array = b[3] if perks else []
		var n: int = prices.size() if perks else Levels.MAX_ATTR
		var l: int = Perks.level(id) if perks else Levels.attr(id)
		for k in range(1, n + 1):
			var st := "owned" if k <= l else ("avail" if k == l + 1 else "locked")
			var cost: int = int(prices[k - 1]) if perks else 0
			var key := "%s_%d" % [id, k]
			var nd := {"key": key, "name": "%s %s" % [nm, ROMAN[mini(k, ROMAN.size() - 1)]], "sub": "",
				"desc": "За уровень: " + String(b[2]) + "\n\nВетка: %d / %d" % [l, n],
				"state": st, "pos": Vector2(k, r), "from": "hub" if k == 1 else "%s_%d" % [id, k - 1], "attr": not perks}
			if perks:
				nd["price"] = "%d монет" % cost
				nd["can"] = st == "avail" and coins >= cost
				nd["buy"] = func(): _buy(key, cost)
			else:
				nd["price"] = "1 очко"
				nd["can"] = st == "avail" and Levels.points() > 0
				nd["buy"] = func(): _upgrade_attr(id, nm)
			out.append(nd)
	return out


## Кнопка-узел древа: стиль по состоянию (изучен — золото со свечением, доступен — пульсирует, закрыт — тусклый).
func _node_btn(nd: Dictionary) -> Button:
	var key: String = nd["key"]
	var st: String = nd["state"]
	var can: bool = nd["can"]
	var b := Button.new()
	b.custom_minimum_size = NODE
	b.size = NODE
	b.position = _center(key) - NODE / 2
	b.pivot_offset = NODE / 2
	b.focus_mode = Control.FOCUS_ALL
	var sb: StyleBoxFlat
	var nc := Color(0.95, 0.93, 0.88)
	var sc := Color(0.7, 0.7, 0.65)
	var sub: String = nd["sub"]
	match st:
		"owned":
			sb = _sb(Color(0.2, 0.15, 0.05), GOLD, 2, Color(GOLD, 0.45), 12)
			nc = GOLD
			sc = Color(1.0, 0.9, 0.6)
			sub = "изучено" + ("  ·  " + sub if sub != "" else "")
		"avail":
			sb = _sb_can if can else _sb(Color(0.11, 0.11, 0.12), Color(0.42, 0.5, 0.62), 2, Color(0, 0, 0, 0), 0)
			sc = Color(1.0, 0.85, 0.45) if can else Color(0.85, 0.45, 0.4)
			sub = String(nd["price"])
		_:
			sb = _sb(Color(0.07, 0.07, 0.07), Color(0.24, 0.24, 0.23), 1, Color(0, 0, 0, 0), 0)
			nc = Color(0.5, 0.5, 0.47)
			sc = Color(0.4, 0.4, 0.38)
			sub = "закрыто · " + String(nd["price"])
	var hv := sb.duplicate() as StyleBoxFlat
	hv.bg_color = sb.bg_color.lightened(0.12)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("focus", _sb_focus)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 2)
	b.add_child(v)
	var n := _label(String(nd["name"]), 17, nc)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(n)
	var s := _label(sub, 13, sc)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	b.pressed.connect(func(): _press(key))
	b.mouse_entered.connect(func(): _show_details(key))
	b.mouse_exited.connect(func(): _show_details(""))
	b.focus_entered.connect(func():
		_sel = key
		_show_details("")
		_ensure_visible(key))
	return b


## Описание узла справа (key пустой — выбранный).
func _show_details(key: String) -> void:
	if key == "":
		key = _sel
	if not _nodes.has(key):
		_d_name.text = ""
		_d_state.text = ""
		_d_desc.text = ""
		_d_price.text = ""
		_d_btn.visible = false
		return
	var nd: Dictionary = _nodes[key]
	var st: String = nd["state"]
	_d_name.text = String(nd["name"])
	_d_desc.text = String(nd["desc"])
	_d_price.text = "" if st == "owned" else "Цена: " + String(nd["price"])
	_d_btn.visible = st != "owned"
	_d_btn.disabled = not bool(nd["can"])
	_d_btn.text = "Прокачать" if nd["attr"] else "Изучить"
	if st == "owned":
		_d_state.text = "ИЗУЧЕНО" + ("  ·  " + String(nd["sub"]) if String(nd["sub"]) != "" else "")
		_d_state.add_theme_color_override("font_color", GOLD)
	elif st == "locked":
		var fr: String = nd["from"]
		_d_state.text = "ЗАКРЫТО — сначала: %s" % (String(_nodes[fr]["name"]) if _nodes.has(fr) else fr)
		_d_state.add_theme_color_override("font_color", Color(0.6, 0.6, 0.56))
	elif nd["can"]:
		_d_state.text = "МОЖНО ИЗУЧИТЬ"
		_d_state.add_theme_color_override("font_color", BLUE)
	else:
		_d_state.text = "НЕ ХВАТАЕТ " + ("ОЧКОВ" if nd["attr"] else "МОНЕТ")
		_d_state.add_theme_color_override("font_color", Color(0.95, 0.45, 0.4))


## Нажали узел: изучить, если можно (вспышка), иначе — встряхнуть.
func _press(key: String) -> void:
	if not _nodes.has(key):
		return
	_sel = key
	var nd: Dictionary = _nodes[key]
	if not nd["can"]:
		_shake(key)
		_show_details("")
		return
	(nd["buy"] as Callable).call()
	if _nodes.has(key) and _nodes[key]["state"] == "owned":
		_celebrate(key)


## Покупка удалась: кольцо с искрами и пружинистый пульс узла.
func _celebrate(key: String) -> void:
	_bursts.append([_center(key), Time.get_ticks_msec() / 1000.0, randf() * TAU])
	if _btns.has(key):
		var b: Button = _btns[key]
		b.scale = Vector2.ONE * 1.35
		b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## Нельзя купить: узел качается из стороны в сторону.
func _shake(key: String) -> void:
	if not _btns.has(key):
		return
	var b: Button = _btns[key]
	var x0 := _center(key).x - NODE.x / 2
	var tw := b.create_tween()
	for dx in [10.0, -8.0, 6.0, -3.0, 0.0]:
		tw.tween_property(b, "position:x", x0 + dx, 0.05)


## Сменить вкладку (d = −1 / +1): древо уезжает вбок и проявляется.
func _tab(d: int) -> void:
	if sections.is_empty() or d == 0:
		return
	_cur = wrapi(_cur + d, 0, sections.size())
	_sel = ""
	_rebuild()
	_need_fit = true
	_pan += Vector2(-280.0 * signf(d), 0)
	_canvas.modulate.a = 0.0
	_canvas.create_tween().tween_property(_canvas, "modulate:a", 1.0, 0.3)
	if game and game.has_method("play_ui"):
		game.play_ui("coin", -22.0, 2.2)


## Мышь по древу: колесо — зум к курсору, зажатая кнопка на пустом месте — панорама.
func _view_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			if mb.pressed:
				_zoom_by(1.12, mb.position)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				_zoom_by(1.0 / 1.12, mb.position)
		else:
			_drag = mb.pressed
		_view.accept_event()
	elif e is InputEventMouseMotion and _drag:
		var mm := e as InputEventMouseMotion
		if mm.button_mask == 0:
			_drag = false
			return
		_pan += mm.relative
		_pan_t = _pan
		_view.accept_event()


## Зум в k раз вокруг точки p (координаты области древа).
func _zoom_by(k: float, p: Vector2) -> void:
	var z := clampf(_zoom_t * k, ZMIN, ZMAX)
	var w := (p - _pan_t) / _zoom_t
	_pan_t = p - w * z
	_zoom_t = z


## Вписать всё древо в область (при открытии — с наездом камеры).
func _fit() -> void:
	_need_fit = false
	var r := Rect2(_hub, Vector2.ZERO)
	for k in _nodes:
		r = r.expand(_center(k))
	r = r.grow(120)
	var z := clampf(minf(_view.size.x / r.size.x, _view.size.y / r.size.y), ZMIN, 1.15)
	_zoom_t = z
	_pan_t = _view.size / 2 - r.get_center() * z
	if _intro:
		_intro = false
		_zoom = z * 0.75
		_pan = _view.size / 2 - r.get_center() * _zoom


## Узел с фокусом (геймпад / стрелки) — подвинуть древо, чтобы он был виден.
func _ensure_visible(key: String) -> void:
	var c := _pan_t + _center(key) * _zoom_t
	var m := Vector2(130, 90)
	var r := Rect2(m, _view.size - m * 2)
	if r.size.x <= 0 or r.size.y <= 0:
		return
	var d := Vector2.ZERO
	if c.x < r.position.x:
		d.x = r.position.x - c.x
	elif c.x > r.end.x:
		d.x = r.end.x - c.x
	if c.y < r.position.y:
		d.y = r.position.y - c.y
	elif c.y > r.end.y:
		d.y = r.end.y - c.y
	_pan_t += d


## Центр узла на холсте ("hub" — хаб).
func _center(key: String) -> Vector2:
	if key == "hub" or not _nodes.has(key):
		return _hub
	return (_nodes[key]["pos"] as Vector2) * GRID


## Фон области древа: тёмная сетка точек и свечение вокруг хаба.
func _draw_bg() -> void:
	_view.draw_rect(Rect2(Vector2.ZERO, _view.size), Color(0.035, 0.035, 0.045))
	var hc := _pan + _hub * _zoom
	for i in 4:
		_view.draw_circle(hc, (420.0 - i * 90.0) * _zoom, Color(GOLD, 0.025))
	var st := 48.0 * _zoom
	while st < 22.0:
		st *= 2.0
	var c := Color(0.6, 0.55, 0.4, 0.12)
	var x := fposmod(_pan.x, st)
	while x < _view.size.x:
		var y := fposmod(_pan.y, st)
		while y < _view.size.y:
			_view.draw_rect(Rect2(x - 1, y - 1, 2, 2), c)
			y += st
		x += st


## Связи (кривые с бегущими огоньками), хаб с уровнем и вспышки покупок.
func _draw_links() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for k in _nodes:
		var nd: Dictionary = _nodes[k]
		var st: String = nd["state"]
		var a := _center(String(nd["from"]))
		var b := _center(k)
		var col := GOLD if st == "owned" else (BLUE if st == "avail" else DIMC)
		var pts := PackedVector2Array()
		for i in 17:
			pts.append(_bez(a, b, i / 16.0))
		if st == "owned":
			_canvas.draw_polyline(pts, Color(col, 0.12), 14.0, true)
			_canvas.draw_polyline(pts, Color(col, 0.3), 6.0, true)
		_canvas.draw_polyline(pts, col, 1.5 if st == "locked" else 2.5, true)
		if st != "locked":
			for i in 3:
				var f := fposmod(t * (0.55 if st == "owned" else 0.3) + i / 3.0, 1.0)
				_canvas.draw_circle(_bez(a, b, f), 3.5, Color(col.lightened(0.3), sin(f * PI)))
	for i in 3:
		_canvas.draw_circle(_hub, 70.0 - i * 9.0, Color(GOLD, 0.07))
	_canvas.draw_circle(_hub, 48.0, Color(0.13, 0.1, 0.05))
	_canvas.draw_arc(_hub, 48.0, 0.0, TAU, 48, GOLD, 3.0, true)
	_canvas.draw_arc(_hub, 57.0 + 3.0 * sin(t * 2.0), t, t + PI * 1.2, 32, Color(GOLD, 0.65), 2.0, true)
	_canvas.draw_arc(_hub, 57.0 + 3.0 * sin(t * 2.0), t + PI, t + PI * 1.6, 16, Color(GOLD, 0.35), 2.0, true)
	var font := ThemeDB.fallback_font
	var s := "УР. %d" % Levels.level()
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	_canvas.draw_string(font, _hub + Vector2(-w / 2, 7), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, GOLD)
	var keep: Array = []
	for bu in _bursts:
		var e: float = (t - float(bu[1])) / 0.9
		if e >= 1.0:
			continue
		keep.append(bu)
		var p: Vector2 = bu[0]
		var ee := 1.0 - pow(1.0 - e, 3.0)
		_canvas.draw_circle(p, 110.0 * ee, Color(GOLD, 0.18 * (1.0 - e)))
		_canvas.draw_arc(p, 40.0 + 150.0 * ee, 0.0, TAU, 64, Color(GOLD, 1.0 - e), 4.0 * (1.0 - e) + 1.0, true)
		for i in 12:
			var ang := i * TAU / 12.0 + float(bu[2])
			_canvas.draw_circle(p + Vector2.from_angle(ang) * (30.0 + 170.0 * ee), 5.0 * (1.0 - e) + 1.0, Color(1.0, 0.9, 0.5, 1.0 - e))
	_bursts = keep


## Точка на S-кривой связи от a к b (f от 0 до 1).
func _bez(a: Vector2, b: Vector2, f: float) -> Vector2:
	var h := Vector2((b.x - a.x) * 0.5, 0)
	return a.bezier_interpolate(a + h, b - h, b, f)


## Прокачать атрибут за очко уровня (systems/levels.gd).
func _upgrade_attr(aid: String, nm: String) -> void:
	if game == null or not Levels.upgrade(aid):
		return
	game.play_ui("coin", -8.0, 1.4)
	game.hud.toast("Атрибут прокачан: %s" % nm, Color(0.55, 0.9, 1.0))
	if game.has_method("save_now"):
		game.call_deferred("save_now")
	_rebuild()


## Купить навык за монеты.
func _buy(id: String, cost: int) -> void:
	if has(id) or game == null or game.inv.coins < cost:
		return
	if cost > 0 and not game.inv.remove("coin", cost):
		return
	owned[id] = 1
	game.play_ui("coin", -8.0, 1.2)
	game.hud.toast("Навык изучен: %s" % _name_of(id), Color(0.5, 1.0, 0.55))
	if game.has_method("save_now"):
		game.call_deferred("save_now")
	_rebuild()


## Монеты игрока (0 — нет инвентаря).
func _coins() -> int:
	return int(game.inv.coins) if game != null and game.inv != null else 0


## Название навыка по id (из всех разделов).
func _name_of(id: String) -> String:
	if _nodes.has(id):
		return String(_nodes[id]["name"])
	for s in sections:
		for it in _items(s):
			if it["id"] == id:
				return it["name"]
	return id


## Скруглённая плашка с рамкой и свечением (тенью).
func _sb(bg: Color, border: Color, bw: int, glow: Color, gs: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(14)
	s.shadow_color = glow
	s.shadow_size = gs
	return s


func _label(t: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


## Карточки раздела: массив или результат Callable.
func _items(s: Dictionary) -> Array:
	return s["items"].call() if s["items"] is Callable else s["items"]
