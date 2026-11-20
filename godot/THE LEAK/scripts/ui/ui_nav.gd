extends Node
## Клетки (плитки) в меню и окнах — с геймпада и с клавиатуры (промпты 20.11 14:40–15:10). Создаёт ui/gamepad.gd (pad.nav),
## работает и на паузе. Клетки ищем по всему интерфейсу (кнопка, ползунок, поле, слот, ячейка сетки) — каждое окно
## и каждая страница меню работают без своей разметки; закрытое другой панелью (выше по отрисовке, ловит мышь) — пропускаем.
## Активная клетка обведена рамкой, курсора мыши нет. Мышь всё равно ставим в центр клетки (warp) — подсказки
## и перетаскивание (A держать + стрелки) работают как от мыши.
## Клавиатура: стрелки — клетка (на ползунке ←/→ — значение), Enter — клик, Esc — назад (ui_cancel, как и было).
## Геймпад: ↑ ← → и правый стик — клетка, A — клик, X — правый клик, B — назад, RB — крафт в инвентаре,
## ↓ — переключить «клетки ↔ свободный курсор» (курсор — правым стиком). В игре (мышь захвачена) курсора с геймпада нет.
## Геймпад подключён при запуске — клетки сразу, и в главном меню. Новый экран — рамка на первом пункте (сверху слева);
## перестроилось то же окно / закрылось подменю — на прежнем месте.
## Движение мыши, клик мышью или касание — клетки прячем, курсор возвращаем (до следующей стрелки / кнопки геймпада).

const ST_ON := 0.55           # правый стик: отклонение для шага по клеткам
const REP_DELAY := 0.32       # стрелку держат — повтор
const REP_T := 0.1
const SAME_PX := 24.0         # клетка на прежнем месте (окно перестроилось) — та же
const FRAME_COL := Color(1.0, 0.82, 0.3)
const PAD_HINT := "Стрелки — клетка  ·  %s — взять / положить (держать + стрелки — перетащить)  ·  %s — действия  ·  %s — использовать  ·  %s — крафт  ·  %s + стрелка — в слот"
const KB_DIR := {KEY_UP: Vector2.UP, KEY_DOWN: Vector2.DOWN, KEY_LEFT: Vector2.LEFT, KEY_RIGHT: Vector2.RIGHT}

var pad                        # ui/gamepad.gd
var pad_used := false          # клетки включены: последний ввод — геймпад или стрелки клавиатуры
var by_kb := false             # ...и это была клавиатура (подсказки — клавиши, не кнопки геймпада)
var cursor_mode := false       # свободный курсор геймпада (↓ переключает)
var target: Control            # активная клетка
var trect := Rect2()           # её прямоугольник в target (ячейка сетки или весь контрол)
var last_pt := Vector2(-1, -1) # центр последней клетки (холст)
var _hist: Array = []          # прежние центры клеток (новые в конце) — вернуться после закрытия подменю
var _warp_ms := 0              # когда геймпад двигал мышь (её «настоящие» движения после warp не считаем)
var _layer: CanvasLayer
var _frame: Control
var _dir_b := -1
var _dir_t := 0.0
var _rep := 0.0
var _st_dir := Vector2.ZERO    # правый стик: куда шагаем
var _st_t := 0.0
var _ui_t := 0.0
var _check_t := 0.0
var _warp_wait := 0            # кадров до warp после прокрутки ScrollContainer
var _sec_wait := 0.0           # ждём выезда крафта — потом выбрать клетку в нём
var _hidden_mouse := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer = CanvasLayer.new()
	_layer.layer = 127
	add_child(_layer)
	_frame = Control.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame.draw.connect(_draw_frame)
	_layer.add_child(_frame)
	pad_used = not Input.get_connected_joypads().is_empty()


func _input(e: InputEvent) -> void:
	if e is InputEventJoypadButton:
		if e.pressed:
			pad_used = true
			by_kb = false
	elif e is InputEventJoypadMotion:
		if absf(e.axis_value) > 0.5:
			pad_used = true
			by_kb = false
	elif e.device != pad.SYNTH:
		if e is InputEventKey:
			if e.pressed:
				_key(e)
		elif e is InputEventMouseMotion:
			if Time.get_ticks_msec() - _warp_ms > 150 and e.relative.length() > 3.0:
				_off()
		elif (e is InputEventMouseButton and e.pressed) or e is InputEventScreenTouch:
			_off()


## Клавиатура в меню / окне: стрелки — клетка, Enter — клик. Поле ввода, ожидание клавиши в «Управлении»,
## выпадающий список (у него свои стрелки) — не трогаем.
func _key(e: InputEventKey) -> void:
	if not pad._ui_mode() or pad.capturing:
		return
	var k: int = e.keycode
	var enter := k == KEY_ENTER or k == KEY_KP_ENTER
	if not enter and not KB_DIR.has(k):
		return
	var m = pad.get_parent()
	if m != null and str(m.get("waiting_action")) != "" and str(m.get("waiting_action")) != "<null>":
		return
	var fo := get_viewport().gui_get_focus_owner()
	if fo is TextEdit or (fo is LineEdit and (fo as LineEdit).is_editing()):
		return
	if popup_open():
		return
	get_viewport().set_input_as_handled()
	if fo != null:
		fo.release_focus()   # фокус Godot не нужен: рамка — наша
	pad_used = true
	by_kb = true
	cursor_mode = false
	if enter:
		if not e.is_echo() and _valid(target):
			before_click()
			pad._mouse_btn(MOUSE_BUTTON_LEFT, true)
			pad._mouse_btn(MOUSE_BUTTON_LEFT, false)
		return
	if not _valid(target):
		_repick()
	else:
		_step(KB_DIR[k])


## Открыт выпадающий список / всплывающее окно Godot (OptionButton) — у него своя навигация (ui_up / ui_accept).
func popup_open() -> bool:
	for w in get_tree().root.get_embedded_subwindows():
		if w.visible:
			return true
	return false


## Мышь / касание — клетки и рамку прячем, курсор возвращаем.
func _off() -> void:
	if not pad_used and not cursor_mode:
		return
	pad_used = false
	by_kb = false
	cursor_mode = false
	target = null
	_dir_b = -1
	_show(false)
	_restore_mouse()


## Курсором правого стика двигаем свободно: режим курсора или в окне нет ни одной клетки.
func free_cursor() -> bool:
	return cursor_mode or not _valid(target)


func _process(delta: float) -> void:
	if not pad._ui_mode() or pad.capturing:
		_ui_t = 0.0
		target = null
		cursor_mode = false
		last_pt = Vector2(-1, -1)
		_hist.clear()
		_dir_b = -1
		_show(false)
		_restore_mouse()
		return
	_ui_t += delta
	_inv_hint()
	if not pad_used:
		_show(false)
		_restore_mouse()
		return
	if _sec_wait > 0.0:
		_sec_wait -= delta
		if _sec_wait <= 0.0:
			_craft_pick()
	if _warp_wait > 0:
		_warp_wait -= 1
		if _warp_wait == 0:
			_warp()
	if cursor_mode:
		_show(false)
		_restore_mouse()
	else:
		_check_t -= delta
		if _ui_t > 0.12 and (not _valid(target) or _check_t <= 0.0):
			_check_t = 0.25
			if not _target_ok():
				_repick()
		var ok := _valid(target)
		_show(ok)
		if ok:
			_hide_mouse()
		else:
			_restore_mouse()   # клеток нет (например, 3D-экран автомата) — нужен обычный курсор
	if _dir_b >= 0:
		_dir_t += delta
		if _dir_t >= REP_DELAY:
			_rep -= delta
			if _rep <= 0.0:
				_rep = REP_T
				_step(_dir_vec(_dir_b))


# ---------- кнопки (зовёт gamepad.gd в режиме меню) ----------

## Стрелка крестовины в меню.
func dpad(b: int, pressed: bool) -> void:
	if not pressed:
		if b == _dir_b:
			_dir_b = -1
		return
	pad_used = true
	by_kb = false
	if b == JOY_BUTTON_DPAD_DOWN:
		_dir_b = -1
		if cursor_mode:
			cursor_mode = false
			_pick_near(_mouse_canvas())   # из курсора — к ближайшей клетке
		else:
			cursor_mode = true   # клетки -> свободный курсор (мышь там, где была рамка)
		return
	_dir_b = b
	_dir_t = 0.0
	_rep = 0.0
	if cursor_mode:
		cursor_mode = false
		_pick_near(_mouse_canvas())   # из курсора — к ближайшей клетке
		return
	if not _valid(target):
		_repick()
		return
	_step(_dir_vec(b))


## Правый стик в режиме клеток (зовёт gamepad.gd): шаг по клеткам, держат — повтор.
func stick(v: Vector2, delta: float) -> void:
	var d := Vector2.ZERO
	if v.length() >= ST_ON:
		d = Vector2(signf(v.x), 0.0) if absf(v.x) > absf(v.y) else Vector2(0.0, signf(v.y))
	if d == Vector2.ZERO:
		_st_dir = Vector2.ZERO
		return
	pad_used = true
	by_kb = false
	if d != _st_dir:
		_st_dir = d
		_st_t = REP_DELAY
	else:
		_st_t -= delta
		if _st_t > 0.0:
			return
		_st_t = REP_T
	if not _valid(target):
		_repick()
	else:
		_step(d)


## Перед кликом A/X/Enter — мышь точно в центр активной клетки (окно могло перестроиться).
func before_click() -> void:
	pad_used = true
	if not cursor_mode and _valid(target):
		_warp()


## RB: в инвентаре — выкатить / спрятать крафт (промпт 20.11 15:10). false — инвентарь не открыт.
func toggle_craft() -> bool:
	var inv = _inv()
	if inv == null or not bool(inv.get("open")) or not inv.has_method("set_craft"):
		return false
	pad_used = true
	cursor_mode = false
	var on := not bool(inv.get("craft_shown"))
	inv.set_craft(on)
	if on:
		_sec_wait = 0.35   # клетку в крафте выберем, когда панель доедет
	return true


## Первая клетка в выехавшем крафте.
func _craft_pick() -> void:
	var inv = _inv()
	var cp = inv.get("craft_panel") if inv != null else null
	if not (cp is Control):
		return
	var best = null
	var bs := INF
	for cd in _collect():
		if not (cp as Control).is_ancestor_of(cd.c):
			continue
		var s: float = cd.p.y + cd.p.x * 0.25
		if s < bs:
			bs = s
			best = cd
	if best != null:
		_select(best)


# ---------- клетки ----------

func _dir_vec(b: int) -> Vector2:
	match b:
		JOY_BUTTON_DPAD_UP: return Vector2.UP
		JOY_BUTTON_DPAD_DOWN: return Vector2.DOWN
		JOY_BUTTON_DPAD_LEFT: return Vector2.LEFT
	return Vector2.RIGHT


## Шаг в сторону dir: ближайшая клетка в этом направлении (сдвиг вбок штрафуется вдвое). Ползунок — ←/→ меняют значение.
func _step(dir: Vector2) -> void:
	if target is Slider and dir.x != 0.0:
		var s: Range = target
		var st := maxf(s.step, (s.max_value - s.min_value) / 20.0)
		s.value = clampf(s.value + st * signf(dir.x), s.min_value, s.max_value)
		return
	var from := _tpoint()
	var best = null
	var bs := INF
	for cd in _collect():
		if cd.c == target and cd.r == trect:
			continue
		var d: Vector2 = cd.p - from
		var along := d.dot(dir)
		if along < 6.0:
			continue
		var sc := along + absf(d.cross(dir)) * 2.0
		if sc < bs:
			bs = sc
			best = cd
	if best != null:
		_select(best)


## Новый экран — первая клетка (сверху слева); перестроилось то же окно / закрылось подменю —
## клетка на одном из прежних мест (последние сначала).
func _repick() -> void:
	var cs := _collect()
	for i in range(_hist.size() - 1, -1, -1):
		var hp: Vector2 = _hist[i]
		for cd in cs:
			if (cd.p as Vector2).distance_to(hp) < SAME_PX:
				_select(cd)
				return
	_pick_near(Vector2(-1, -1))


## Ближайшая к точке клетка; точки нет (-1) — первая по порядку чтения (сверху слева).
func _pick_near(from: Vector2) -> void:
	var best = null
	var bs := INF
	for cd in _collect():
		var s: float = cd.p.y + cd.p.x * 0.25 if from.x < 0.0 else cd.p.distance_squared_to(from)
		if s < bs:
			bs = s
			best = cd
	if best == null:
		target = null
		return
	_select(best)


func _select(cd: Dictionary) -> void:
	target = cd.c
	trect = cd.r
	if cd.sc != null:
		_scroll_into(cd.sc, cd.c, cd.r)
		_warp_wait = 2   # ScrollContainer передвинет детей к концу кадра
	else:
		_warp()
	_frame.queue_redraw()


func _scroll_into(sc: ScrollContainer, c: Control, r: Rect2) -> void:
	var rr: Rect2 = (sc.get_global_transform_with_canvas().affine_inverse() * c.get_global_transform_with_canvas()) * r
	if rr.position.y < 0.0:
		sc.scroll_vertical += int(rr.position.y) - 8
	elif rr.end.y > sc.size.y:
		sc.scroll_vertical += int(rr.end.y - sc.size.y) + 8
	if rr.position.x < 0.0:
		sc.scroll_horizontal += int(rr.position.x) - 8
	elif rr.end.x > sc.size.x:
		sc.scroll_horizontal += int(rr.end.x - sc.size.x) + 8


func _warp() -> void:
	if not _valid(target):
		return
	var p := _tpoint()
	last_pt = p
	if _hist.is_empty() or (_hist[-1] as Vector2).distance_to(p) > 1.0:
		_hist.append(p)
		if _hist.size() > 6:
			_hist.pop_front()
	pad.mouse_to(get_tree().root.get_final_transform() * p)


func _tpoint() -> Vector2:
	if not _valid(target):
		return last_pt if last_pt.x >= 0.0 else _mouse_canvas()
	return target.get_global_transform_with_canvas() * trect.get_center()


func _mouse_canvas() -> Vector2:
	return get_tree().root.get_final_transform().affine_inverse() * pad._win_mouse()


## Активная клетка ещё на экране и не закрыта другим окном.
func _target_ok() -> bool:
	if not _valid(target):
		return false
	for cd in _collect():
		if cd.c == target and cd.r == trect:
			return true
	return false


func _valid(c) -> bool:
	if c == null or not is_instance_valid(c) or not (c as Control).is_inside_tree() or not (c as Control).is_visible_in_tree():
		return false
	var p: Node = (c as Control).get_parent()
	while p:
		if p is CanvasLayer and not p.visible:
			return false
		p = p.get_parent()
	return true


## Все доступные клетки: {c, r — прямоугольник в c, p — центр на холсте, sc — ScrollContainer, если клетка за краем}.
func _collect() -> Array:
	var cands := []
	var stops := []
	_walk(get_tree().root, 0, cands, stops, [0])
	var vr := get_viewport().get_visible_rect()
	var out := []
	for cd in cands:
		var c: Control = cd[0]
		var ord: int = cd[1]
		var xf := c.get_global_transform_with_canvas()
		var sc := _scroll_of(c)
		var sr := Rect2()
		if sc != null:
			sr = sc.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, sc.size)
			if not vr.intersects(sr):
				continue
		for r in _rects(c):
			var p: Vector2 = xf * (r as Rect2).get_center()
			var clipped := sc != null and not sr.has_point(p)
			if not clipped and not vr.has_point(p):
				continue
			var q := p.clamp(sr.position + Vector2(4, 4), sr.end - Vector2(4, 4)) if clipped else p
			if _occluded(q, ord, c, stops):
				continue
			out.append({"c": c, "r": r, "p": p, "sc": sc if clipped else null})
	return out


func _walk(n: Node, lay: int, cands: Array, stops: Array, idx: Array) -> void:
	for ch in n.get_children():
		if ch is Node3D or ch is SubViewport or ch is Window or ch == _layer:
			continue
		if ch is CanvasLayer:
			if (ch as CanvasLayer).visible:
				_walk(ch, (ch as CanvasLayer).layer, cands, stops, idx)
			continue
		if ch is CanvasItem and not (ch as CanvasItem).visible:
			continue
		if ch is Control:
			var c: Control = ch
			idx[0] += 1
			var ord: int = (lay + 1000) * 1000000 + idx[0]
			if c.mouse_filter == Control.MOUSE_FILTER_STOP and c.size.x > 2.0 and c.size.y > 2.0:
				stops.append([c.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, c.size), ord, c])
				if _is_target(c):
					cands.append([c, ord])
		_walk(ch, lay, cands, stops, idx)


## Точку q закрывает контрол, нарисованный позже (выше) и ловящий мышь, — кроме детей самой клетки.
func _occluded(q: Vector2, ord: int, c: Control, stops: Array) -> bool:
	for s in stops:
		if int(s[1]) > ord and (s[0] as Rect2).has_point(q) and s[2] != c and not c.is_ancestor_of(s[2]):
			return true
	return false


func _is_target(c: Control) -> bool:
	if c is BaseButton:
		return not (c as BaseButton).disabled
	if c is ScrollBar:
		return false
	if c is Slider or c is LineEdit or c is SpinBox:
		return true
	if _is_grid(c):
		return true
	if c.size.x > 520.0 or c.size.y > 520.0:
		return false
	if c.get_script() != null and (c.has_method("_gui_input") or c.has_method("_get_drag_data") or c.has_method("_can_drop_data")):
		return true
	return c.mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND or not c.get_signal_connection_list("gui_input").is_empty()


func _is_grid(c: Control) -> bool:
	return c.get_script() != null and (c.has_method("cell_at") or c.has_method("_owner_at"))


## Сетка (сумка, сундук, лут) — по ячейке на клетку; остальное — целиком.
func _rects(c: Control) -> Array:
	if not _is_grid(c):
		return [Rect2(Vector2.ZERO, c.size)]
	var cs := _cell(c)
	var nx := maxi(1, int(c.size.x / cs + 0.05))
	var ny := maxi(1, int(c.size.y / cs + 0.05))
	if nx * ny > 400:
		return [Rect2(Vector2.ZERO, c.size)]
	var out := []
	for y in ny:
		for x in nx:
			out.append(Rect2(Vector2(x, y) * cs, Vector2(cs, cs)))
	return out


## Размер ячейки сетки: константа CELL у неё самой или у окна (inv / sw / lw), иначе 58.
func _cell(c: Control) -> float:
	for o in [c, c.get("inv"), c.get("sw"), c.get("lw")]:
		if o is Object:
			var v = (o as Object).get("CELL")
			if (v is float or v is int) and float(v) > 8.0:
				return float(v)
	return 58.0


func _scroll_of(c: Control) -> ScrollContainer:
	var p := c.get_parent()
	while p != null and not (p is CanvasLayer):
		if p is ScrollContainer:
			return p
		p = p.get_parent()
	return null


## Подсказки внизу инвентаря — под геймпад, пока играют с него (исходный текст — в meta).
func _inv_hint() -> void:
	var inv = _inv()
	if inv == null or not bool(inv.get("open")) or inv.get("hint_l") == null:
		return
	var l: Label = inv.hint_l
	if not l.has_meta("kb"):
		l.set_meta("kb", l.text)
	var t: String = PAD_HINT % [pad.spec_name("b:0"), pad.spec_name("b:2"), pad.spec_name("b:8"),
		pad.spec_name("b:10"), pad.spec_name("b:4")] if pad_used and not by_kb else str(l.get_meta("kb"))
	if l.text != t:
		l.text = t


func _game():
	for c in get_tree().root.get_children():
		for n in c.get_children():
			if n.has_method("save_now") and n.get("inv") != null:
				return n
	return null


func _inv():
	var g = _game()
	return g.inv if g != null else null


# ---------- рамка и мышь ----------

func _show(on: bool) -> void:
	_frame.visible = on
	if on:
		_frame.queue_redraw()


func _draw_frame() -> void:
	if not _valid(target):
		return
	var r: Rect2 = (target.get_global_transform_with_canvas() * trect).grow(3.0)
	_frame.draw_rect(r, Color(FRAME_COL, 0.12), true)
	_frame.draw_rect(r, FRAME_COL, false, 3.0)


func _hide_mouse() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		_hidden_mouse = true


func _restore_mouse() -> void:
	if _hidden_mouse:
		_hidden_mouse = false
		if Input.mouse_mode == Input.MOUSE_MODE_HIDDEN:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
