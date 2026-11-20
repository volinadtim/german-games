extends Node
## Навигация по меню и окнам — один autoload UiNav (project.godot), подход Германа (промпт 20.11 15:24):
## встроенный Focus Godot + ui_up / ui_down / ui_left / ui_right + действие toggle_cursor. Работает и на паузе.
## Направления: стрелки клавиатуры (ui_* в InputMap), крестовина и стики геймпада — их шлёт ui/gamepad.gd как ui_*
## (с фильтром по геймпаду игрока; левый стик — только пока персонаж не управляется: пауза, меню, магазин, лут).
## Кнопка / ползунок получают настоящий фокус (grab_focus) с яркой рамкой-стилем focus; ячейки сеток (сумка, сундук, лут)
## и прочие клетки без фокуса — та же рамка рисуется поверх. Сосед: focus_neighbor_* у контрола, если задан, иначе
## ближайшая клетка в ту сторону (клетки ищем по всему интерфейсу, закрытые другой панелью пропускаем).
## Новый экран — фокус на первом пункте (сверху слева); перестроилось окно / закрылось подменю — на прежнем месте.
## Ввод с клавиатуры (стрелки, Enter) или геймпада — курсор мыши прячется; движение мыши / клик / касание — рамку
## и фокус убираем, курсор возвращаем. toggle_cursor (по умолчанию F2 и Back на геймпаде; переназначается в «Управлении»)
## — вручную: рамка ↔ курсор (с геймпада курсор водит правый стик). Enter / A — клик, Esc / B — назад.

const ST_ON := 0.55           # стик: отклонение для шага по клеткам
const REP_DELAY := 0.32       # направление держат — повтор
const REP_T := 0.1
const SAME_PX := 24.0         # клетка на прежнем месте (окно перестроилось) — та же
const MOUSE_OFF_PX := 40.0    # настоящая мышь проехала столько — рамку прячем, курсор возвращаем
const PAD_QUIET_MS := 400     # после кнопки / стика геймпада столько мс движения мыши не считаем (Steam / драйвер дублирует стик мышью)
const FRAME_COL := Color(1.0, 0.82, 0.3)
const PAD_HINT := "Крестовина / правый стик — клетка  ·  %s — взять / положить  ·  держать левый курок — перетащить, правый курок — повернуть  ·  %s — действия  ·  %s — использовать  ·  %s — крафт  ·  держать ← (или %s + стрелка) — в слот хотбара  ·  %s — курсор"
const Split := preload("res://scripts/network/split.gd")
const DIRS := {"ui_up": Vector2.UP, "ui_down": Vector2.DOWN, "ui_left": Vector2.LEFT, "ui_right": Vector2.RIGHT}

var pad                        # ui/gamepad.gd (menu.pad) — ставит себя сам
var pad_used := false          # рамка включена: последний ввод — геймпад или стрелки клавиатуры
var by_kb := false             # ...и это была клавиатура (подсказки — клавиши, не кнопки геймпада)
var cursor_mode := false       # свободный курсор геймпада (toggle_cursor)
var target: Control            # активная клетка
var trect := Rect2()           # её прямоугольник в target (ячейка сетки или весь контрол)
var last_pt := Vector2(-1, -1) # центр последней клетки (холст)
var _hist: Array = []          # прежние центры клеток (новые в конце) — вернуться после закрытия подменю
var _warp_ms := 0              # когда геймпад двигал мышь (её «настоящие» движения после warp не считаем)
var _pad_ms := -100000         # последний ввод с геймпада / стрелок: мышь сразу после него — не «пользователь взял мышь»
var _mouse_acc := 0.0          # сколько пикселей проехала настоящая мышь подряд (дрожание и сдвиг на 1–2 px не считаем)
var _layer: CanvasLayer
var _frame: Control
var _hold := Vector2.ZERO      # направление, зажатое на геймпаде (ui_* от gamepad.gd) — повтор
var _hold_t := 0.0
var _rep := 0.0
var _st_dir := Vector2.ZERO    # стик: куда шагаем
var _st_t := 0.0
var _ui_t := 0.0
var _check_t := 0.0
var _warp_wait := 0            # кадров до warp после прокрутки ScrollContainer
var _sec_wait := 0.0           # ждём выезда крафта — потом выбрать клетку в нём
var _hidden_mouse := false
var _focused: Control          # кому мы дали фокус
var _sb: StyleBoxFlat


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
	# пробел — прыжок и поворот предмета (LB), а не «нажать кнопку с фокусом»: ui_accept — только Enter
	for a in ["ui_accept", "ui_select"]:
		if InputMap.has_action(a):
			for ev in InputMap.action_get_events(a):
				if ev is InputEventKey and (ev.keycode == KEY_SPACE or ev.physical_keycode == KEY_SPACE):
					InputMap.action_erase_event(a, ev)
	if not InputMap.has_action("toggle_cursor"):   # menu.gd переставит клавишу из настроек
		InputMap.add_action("toggle_cursor")
		var k := InputEventKey.new()
		k.physical_keycode = KEY_F2
		InputMap.action_add_event("toggle_cursor", k)


func _input(e: InputEvent) -> void:
	if pad == null or not is_instance_valid(pad):
		return
	if e is InputEventJoypadButton:
		if e.pressed:
			pad_used = true
			by_kb = false
			_pad_input()
	elif e is InputEventJoypadMotion:
		if absf(e.axis_value) > 0.25:
			_pad_input()
		if absf(e.axis_value) > 0.5:
			pad_used = true
			by_kb = false
	elif e is InputEventAction:
		_action(e)
	elif e.device != pad.SYNTH:
		if e is InputEventKey:
			if e.pressed:
				_key(e)
		elif e is InputEventMouseMotion:
			_mouse_moved(e.relative)
		elif e is InputEventMouseButton:
			if e.pressed:
				_off()
			else:
				_drop_mouse_focus.call_deferred()
		elif e is InputEventScreenTouch:
			_off()


## Был ввод с геймпада / стрелок — недавние движения мыши не считаем.
func _pad_input() -> void:
	_pad_ms = Time.get_ticks_msec()
	_mouse_acc = 0.0


## Настоящая мышь сдвинулась: рамку убираем, только если её явно повели (не warp, не дрожание, не стик через Steam).
func _mouse_moved(rel: Vector2) -> void:
	var now := Time.get_ticks_msec()
	if now - _warp_ms < 150 or now - _pad_ms < PAD_QUIET_MS:
		_mouse_acc = 0.0
		return
	_mouse_acc += rel.length()
	if _mouse_acc > MOUSE_OFF_PX:
		_mouse_acc = 0.0
		_off()


## Окно / меню открыто и не ждём клавишу в «Управлении».
func _ui_ok() -> bool:
	if not pad._ui_mode() or pad.capturing:
		return false
	var m = pad.get_parent()
	return not (m != null and str(m.get("waiting_action")) != "" and str(m.get("waiting_action")) != "<null>")


## ui_* и toggle_cursor от геймпада (ui/gamepad.gd шлёт их как InputEventAction).
func _action(e: InputEventAction) -> void:
	if not _ui_ok():
		return
	if e.action == "toggle_cursor":
		if e.pressed:
			get_viewport().set_input_as_handled()
			toggle_cursor(false)
		return
	if not DIRS.has(e.action) or popup_open():
		return   # выпадающий список листает сам
	get_viewport().set_input_as_handled()
	var d: Vector2 = DIRS[e.action]
	if not e.pressed:
		if d == _hold:
			_hold = Vector2.ZERO
		return
	pad_used = true
	by_kb = false
	_hold = d
	_hold_t = 0.0
	_rep = 0.0
	_go(d)


## Клавиатура в меню / окне: ui_* (стрелки) — клетка, Enter — клик, toggle_cursor (F2) — рамка ↔ курсор.
## Поле ввода и выпадающий список (у него свои стрелки) — не трогаем.
func _key(e: InputEventKey) -> void:
	if not _ui_ok():
		return
	var fo := get_viewport().gui_get_focus_owner()
	if fo is TextEdit or (fo is LineEdit and (fo as LineEdit).is_editing()):
		return
	if e.is_action_pressed("toggle_cursor") and not e.is_echo():
		get_viewport().set_input_as_handled()
		toggle_cursor(true)
		return
	var k: int = e.keycode
	var enter := k == KEY_ENTER or k == KEY_KP_ENTER
	var dir := Vector2.ZERO
	for a in DIRS:
		if e.is_action_pressed(a, true):
			dir = DIRS[a]
	if (not enter and dir == Vector2.ZERO) or popup_open():
		return
	get_viewport().set_input_as_handled()
	pad_used = true
	by_kb = true
	_pad_input()
	if enter:
		cursor_mode = false
		if not e.is_echo() and _valid(target):
			before_click()
			pad._mouse_btn(MOUSE_BUTTON_LEFT, true)
			pad._mouse_btn(MOUSE_BUTTON_LEFT, false)
		return
	_go(dir)


## Шаг рамки: из свободного курсора — к ближайшей клетке, нет клетки — первая на экране.
func _go(d: Vector2) -> void:
	if cursor_mode:
		cursor_mode = false
		_pick_near(_mouse_canvas())
		return
	if not _valid(target):
		_repick()
		return
	_step(d)


## toggle_cursor: рамка ↔ курсор. С клавиатуры — обычная мышь, с геймпада — свободный курсор правым стиком.
func toggle_cursor(kb: bool) -> void:
	if pad_used and not cursor_mode and _valid(target):
		if kb:
			_off()
		else:
			cursor_mode = true
			_unfocus()
		return
	pad_used = true
	by_kb = kb
	cursor_mode = false
	_pick_near(_mouse_canvas())


## Открыт выпадающий список / всплывающее окно Godot (OptionButton) — у него своя навигация (ui_up / ui_accept).
## Подсказку (tooltip) не считаем: она всплывает, когда рамка ставит мышь на кнопку, и раньше глушила стрелки.
func popup_open() -> bool:
	for w in get_tree().root.get_embedded_subwindows():
		if w.visible and not w.get_flag(Window.FLAG_NO_FOCUS) and not w.get_flag(Window.FLAG_MOUSE_PASSTHROUGH):
			return true
	return false


## Мышь / касание — рамку и фокус прячем, курсор возвращаем.
func _off() -> void:
	if not pad_used and not cursor_mode:
		return
	pad_used = false
	by_kb = false
	cursor_mode = false
	target = null
	_hold = Vector2.ZERO
	_unfocus()
	_show(false)
	_restore_mouse()


## Кнопку нажали мышью — фокус с неё снимаем (рамка только при навигации), поля ввода не трогаем.
func _drop_mouse_focus() -> void:
	if pad_used:
		return
	var fo := get_viewport().gui_get_focus_owner()
	if fo is BaseButton or fo is Slider:
		fo.release_focus()


## Курсором стика двигаем свободно: режим курсора или в окне нет ни одной клетки.
func free_cursor() -> bool:
	return cursor_mode or not _valid(target)


func _process(delta: float) -> void:
	if pad == null or not is_instance_valid(pad):
		return
	if not pad._ui_mode() or pad.capturing:
		_ui_t = 0.0
		target = null
		cursor_mode = false
		last_pt = Vector2(-1, -1)
		_hist.clear()
		_hold = Vector2.ZERO
		_unfocus()
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
			_unfocus()
			_restore_mouse()   # клеток нет (например, 3D-экран автомата) — нужен обычный курсор
	if _hold != Vector2.ZERO:
		_hold_t += delta
		if _hold_t >= REP_DELAY:
			_rep -= delta
			if _rep <= 0.0:
				_rep = REP_T
				_go(_hold)


# ---------- стики и кнопки (зовёт gamepad.gd в режиме меню) ----------

## Стик в режиме клеток (зовёт gamepad.gd: правый; левый — только когда персонаж не управляется): шаг, держат — повтор.
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
	_go(d)


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

## Шаг в сторону dir: сосед из focus_neighbor_* (если задан в окне), иначе ближайшая клетка в этом направлении
## (сдвиг вбок штрафуется вдвое). Ползунок — ←/→ меняют значение.
func _step(dir: Vector2) -> void:
	if target is Slider and dir.x != 0.0:
		var s: Range = target
		var st := maxf(s.step, (s.max_value - s.min_value) / 20.0)
		s.value = clampf(s.value + st * signf(dir.x), s.min_value, s.max_value)
		return
	var side := SIDE_TOP if dir.y < 0.0 else SIDE_BOTTOM if dir.y > 0.0 else SIDE_LEFT if dir.x < 0.0 else SIDE_RIGHT
	var np := target.get_focus_neighbor(side)
	if not np.is_empty():
		var nb := target.get_node_or_null(np)
		if nb is Control and _valid(nb):
			_select({"c": nb, "r": Rect2(Vector2.ZERO, (nb as Control).size), "sc": _scroll_of(nb)})
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
	_focus_target()
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
	return _xf(target) * trect.get_center()


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
		var xf := _xf(c)
		var sc := _scroll_of(c)
		var sr := Rect2()
		if sc != null:
			sr = _xf(sc) * Rect2(Vector2.ZERO, sc.size)
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
		if ch is SubViewport and ch == _ui_vp():
			_walk(ch, lay, cands, stops, idx)   # Split-Screen: окна в половине того, у кого окно открыто
			continue
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
				stops.append([_xf(c) * Rect2(Vector2.ZERO, c.size), ord, c])
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
		pad.spec_name("b:10"), pad.spec_name("b:4"), pad.spec_name(pad.spec_of("toggle_cursor"))] if pad_used and not by_kb else str(l.get_meta("kb"))
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
	if g == null:
		return null
	for i in g.get("invs"):
		if is_instance_valid(i) and i.open:
			return i   # Split-Screen: открытый — может быть инвентарь игрока 2
	return g.inv


## Split-Screen (network/split.gd): SubViewport половины, где открыто окно; без сплитскрина — null.
func _ui_vp() -> Node:
	var s = Split.inst
	return s.ui_vp() if s != null and is_instance_valid(s) else null


## Контрол → координаты корневого окна (холст): в Split-Screen окна лежат в SubViewport половинки
## (свой масштаб size_2d_override и сдвиг контейнера).
func _xf(c: CanvasItem) -> Transform2D:
	var t := c.get_global_transform_with_canvas()
	var vp := c.get_viewport()
	while vp is SubViewport and vp.get_parent() is SubViewportContainer:
		var sv := vp as SubViewport
		var cont := sv.get_parent() as SubViewportContainer
		var k := Vector2.ONE
		if sv.size_2d_override != Vector2i.ZERO and sv.size_2d_override_stretch:
			k = Vector2(sv.size) / Vector2(sv.size_2d_override)
		t = cont.get_global_transform_with_canvas() * Transform2D(0.0, k, 0.0, Vector2.ZERO) * t
		vp = cont.get_viewport()
	return t


# ---------- рамка и мышь ----------

## Кнопке / ползунку — настоящий фокус Godot (grab_focus); у Button рамку рисует его стиль focus (_focus_sb).
## Ячейке сетки и прочим клеткам фокус не нужен — рамку рисует _frame. Поля ввода фокусом не трогаем (иначе
## стрелки уйдут в редактирование) — в них входят кликом (A / Enter).
func _focus_target() -> void:
	if not (target is BaseButton or target is Slider):
		_unfocus()
		return
	if target.focus_mode == Control.FOCUS_NONE:
		target.focus_mode = Control.FOCUS_ALL   # окна ставили FOCUS_NONE от пробела; пробел из ui_accept убран (_ready)
	if target is Button and not target.has_theme_stylebox_override("focus"):
		target.add_theme_stylebox_override("focus", _focus_sb())
	if _focused != target:
		_unfocus()
	_focused = target
	if not target.has_focus():
		target.grab_focus()


func _unfocus() -> void:
	if _focused != null and is_instance_valid(_focused) and _focused.has_focus():
		_focused.release_focus()
	_focused = null


## Стиль фокуса для всех кнопок: яркая рамка (как у рамки клеток), лёгкая заливка.
func _focus_sb() -> StyleBoxFlat:
	if _sb == null:
		_sb = StyleBoxFlat.new()
		_sb.bg_color = Color(FRAME_COL, 0.12)
		_sb.border_color = FRAME_COL
		_sb.set_border_width_all(3)
		_sb.set_corner_radius_all(3)
		_sb.set_expand_margin_all(3.0)
	return _sb


## Рамку активной клетки рисует сам Godot (фокус кнопки со стилем focus)?
func _styled() -> bool:
	return target is Button and target.has_focus() and target.get_theme_stylebox("focus") == _sb


func _show(on: bool) -> void:
	_frame.visible = on
	if on:
		_frame.queue_redraw()


func _draw_frame() -> void:
	if not _valid(target) or _styled():
		return
	var r: Rect2 = (_xf(target) * trect).grow(3.0)
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
