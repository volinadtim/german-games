extends Node
## Клетки в меню с геймпада (промпты 20.11 14:40–14:48). Создаёт ui/gamepad.gd (pad.nav), работает и на паузе.
## В меню и окнах (курсор не захвачен) курсора по умолчанию нет: крестовина переключает активную клетку
## (кнопка, ползунок, поле, слот, ячейка сетки), она обведена рамкой; A — клик по ней, X — правый клик.
## Мышь всё равно ставим в центр клетки (warp) — подсказки и перетаскивание (A держать + стрелки) работают как от мыши.
## Удержать ↓ — свободный курсор (правым стиком; левый — ходьба); любая стрелка — обратно к клеткам.
## LB / RB — соседний раздел окна (крафт / снаряжение / лут — крупные панели слева направо).
## Клетки ищем по всему интерфейсу; закрытое другой панелью (выше по отрисовке, ловит мышь) — пропускаем.
## Мышь, клавиатура или касание выключают клетки до следующего нажатия на геймпаде.

const HOLD_T := 0.35          # ↓ держать — свободный курсор
const REP_DELAY := 0.32       # стрелку держат — повтор
const REP_T := 0.1
const SEC_MIN := Vector2(200, 150)   # панель от такого размера — отдельный раздел для LB/RB
const FRAME_COL := Color(1.0, 0.82, 0.3)

var pad                        # ui/gamepad.gd
var pad_used := false          # последний ввод — с геймпада
var cursor_mode := false       # свободный курсор (удержание ↓)
var target: Control            # активная клетка
var trect := Rect2()           # её прямоугольник в target (ячейка сетки или весь контрол)
var last_pt := Vector2(-1, -1) # центр последней клетки (холст) — после закрытия окна берём ближайшую
var _warp_ms := 0              # когда геймпад двигал мышь (её «настоящие» движения после warp не считаем)
var _layer: CanvasLayer
var _frame: Control
var _dir_b := -1
var _dir_t := 0.0
var _rep := 0.0
var _down_hold := false
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


func _input(e: InputEvent) -> void:
	if e is InputEventJoypadButton:
		if e.pressed:
			pad_used = true
	elif e is InputEventJoypadMotion:
		if absf(e.axis_value) > 0.5:
			pad_used = true
	elif e.device != pad.SYNTH:
		if e is InputEventMouseMotion:
			if Time.get_ticks_msec() - _warp_ms > 150 and e.relative.length() > 3.0:
				_off()
		elif (e is InputEventMouseButton and e.pressed) or (e is InputEventKey and e.pressed) or e is InputEventScreenTouch:
			_off()


## Мышь/клавиатура — клетки и рамку прячем, курсор возвращаем.
func _off() -> void:
	if not pad_used and not cursor_mode:
		return
	pad_used = false
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
		_dir_b = -1
		_show(false)
		_restore_mouse()
		return
	_ui_t += delta
	if not pad_used:
		_show(false)
		_restore_mouse()
		return
	if _sec_wait > 0.0:
		_sec_wait -= delta
		if _sec_wait <= 0.0:
			section(0)
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
				_pick_near(last_pt)
		var ok := _valid(target)
		_show(ok)
		if ok:
			_hide_mouse()
		else:
			_restore_mouse()   # клеток нет (например, 3D-экран автомата) — нужен обычный курсор
	if _dir_b >= 0:
		_dir_t += delta
		if _dir_b == JOY_BUTTON_DPAD_DOWN:
			if _down_hold and _dir_t >= HOLD_T:
				_down_hold = false
				cursor_mode = true
		elif _dir_t >= REP_DELAY:
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
			_down_hold = false
		return
	pad_used = true
	_dir_b = b
	_dir_t = 0.0
	_rep = 0.0
	_down_hold = false
	if cursor_mode:
		cursor_mode = false
		_pick_near(_mouse_canvas())   # из курсора — к ближайшей клетке
		return
	_down_hold = b == JOY_BUTTON_DPAD_DOWN
	if not _valid(target):
		_pick_near(last_pt)
		return
	_step(_dir_vec(b))


## Перед кликом A/X — мышь точно в центр активной клетки (окно могло перестроиться).
func before_click() -> void:
	pad_used = true
	if not cursor_mode and _valid(target):
		_warp()


## LB / RB: соседний раздел (dirn -1 / +1; 0 — выбрать первую клетку в разделе, куда ехали).
func section(dirn: int) -> void:
	pad_used = true
	cursor_mode = false
	var cs := _collect()
	if cs.is_empty():
		return
	var secs := {}
	for cd in cs:
		if not secs.has(cd.sec):
			secs[cd.sec] = []
		secs[cd.sec].append(cd)
	var keys: Array = secs.keys()
	var cx := {}
	for k in keys:
		var sx := 0.0
		for cd in secs[k]:
			sx += cd.p.x
		cx[k] = sx / float(secs[k].size())
	keys.sort_custom(func(a, b): return cx[a] < cx[b])
	var inv = _inv()
	var want = null
	if dirn == 0:
		want = inv.craft_panel if inv != null and inv.get("craft_panel") != null else null
		if not secs.has(want):
			return
	else:
		var cur = _section(target) if _valid(target) else null
		var i := keys.find(cur)
		# крафт спрятан — ещё один раздел справа: выкатываем панель, клетку в ней выберем, когда доедет
		if inv != null and bool(inv.get("open")) and not bool(inv.get("craft_shown")) \
				and dirn > 0 and (i < 0 or i == keys.size() - 1) and inv.has_method("set_craft"):
			inv.set_craft(true)
			_sec_wait = 0.35
			return
		if keys.size() < 2 and i >= 0:
			return
		want = keys[posmod(i + dirn, keys.size())] if i >= 0 else keys[0 if dirn > 0 else keys.size() - 1]
	var best = null
	var bs := INF
	for cd in secs[want]:
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


## Все доступные клетки: {c, r — прямоугольник в c, p — центр на холсте, sc — ScrollContainer, если клетка за краем, sec — раздел}.
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
		var sec = _section(c)
		for r in _rects(c):
			var p: Vector2 = xf * (r as Rect2).get_center()
			var clipped := sc != null and not sr.has_point(p)
			if not clipped and not vr.has_point(p):
				continue
			var q := p.clamp(sr.position + Vector2(4, 4), sr.end - Vector2(4, 4)) if clipped else p
			if _occluded(q, ord, c, stops):
				continue
			out.append({"c": c, "r": r, "p": p, "sc": sc if clipped else null, "sec": sec})
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


## Раздел для LB/RB — ближайшая крупная панель вокруг клетки.
func _section(c: Control) -> Node:
	var p: Node = c.get_parent()
	var last: Node = c
	while p != null:
		if (p is PanelContainer or p is Panel) and (p as Control).size.x >= SEC_MIN.x and (p as Control).size.y >= SEC_MIN.y:
			return p
		if p is CanvasLayer:
			return p
		last = p
		p = p.get_parent()
	return last


func _inv():
	for c in get_tree().root.get_children():
		for n in c.get_children():
			if n.has_method("save_now") and n.get("inv") != null:
				return n.inv
	return null


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
