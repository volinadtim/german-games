extends Node
## Управление — фасад (autoload «Controls», грузится первым). Единственная точка, через которую игра спрашивает ввод.
##   Controls.pressed(игрок, "jump")        — держат ли действие (игрок = player.gd или null — игрок 1 / любой);
##   Controls.just_pressed(игрок, "jump"), Controls.strength(игрок, "x"), Controls.vector(игрок, -x, +x, -y, +y);
##   Controls.event(e, "interact")          — событие e нажимает действие (в _input / _unhandled_input);
##   Controls.mode_on("inventory", self) / mode_off(...) — стек режимов (scripts/controls/modes.gd);
##   Controls.glyph("interact") -> «F» / «X» / «□»;  Controls.hint("{interact} — открыть") — подсказка под текущий ввод.
## Кнопки — только в data/controls/bindings.cfg (умолчания) и user://controls.cfg (переназначения игрока).
## Части: bindings.gd (таблица), modes.gd (режимы), router.gd (устройства по игрокам), glyphs.gd (имена кнопок),
## gamepad.gd (кнопки геймпада -> действия), ui_nav.gd (рамка в меню), key_hint.gd (подписи на кнопках).

signal binds_changed      # переназначили кнопку / сбросили — InputMap уже обновлён
signal glyphs_changed     # сменился вид ввода (клавиатура ↔ Xbox ↔ DualSense) или кнопка — перерисовать подсказки
signal mode_changed(mode: String)

const Bindings := preload("res://scripts/controls/bindings.gd")
const Modes := preload("res://scripts/controls/modes.gd")
const Glyphs := preload("res://scripts/controls/glyphs.gd")
const Router := preload("res://scripts/controls/router.gd")

var table := Bindings.new()
var modes := Modes.new()
var _kind := ""
var _tok_re: RegEx


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	table.load_table()
	table.load_user()
	apply()


func _process(_d: float) -> void:
	var k := Router.kind()
	if k != _kind:
		_kind = k
		glyphs_changed.emit()


# ---------- таблица ----------

## Все действия InputMap из таблицы: клавиатура/мышь (с переназначениями игрока). Оси геймпада добавляет gamepad.gd по binds_changed.
func apply() -> void:
	for a in table.order:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
		InputMap.action_erase_events(a)
		for spec in table.kb_of(a):
			var ev := Bindings.spec_event(str(spec))
			if ev:
				InputMap.action_add_event(a, ev)
	# пробел — прыжок и поворот предмета, а не «нажать кнопку с фокусом»: ui_accept/ui_select — только Enter
	for a in ["ui_accept", "ui_select"]:
		if InputMap.has_action(a):
			for ev in InputMap.action_get_events(a):
				if ev is InputEventKey and (ev.keycode == KEY_SPACE or ev.physical_keycode == KEY_SPACE):
					InputMap.action_erase_event(a, ev)
	binds_changed.emit()
	glyphs_changed.emit()


func has(action: String) -> bool:
	return table.rows.has(action)


## Строки для страницы «Управление»: [действие, подпись, клавиши по умолчанию] (только с разделом).
func menu_rows() -> Array:
	var out: Array = []
	for a in table.order:
		var r: Dictionary = table.rows[a]
		if str(r["group"]) != "":
			out.append([a, str(r["label"]), (r["keys"] as Array).duplicate()])
	return out


## Разделы страницы «Управление» в порядке таблицы: [имя, [действия]].
func menu_groups() -> Array:
	var out: Array = []
	var idx := {}
	for a in table.order:
		var g := str(table.rows[a]["group"])
		if g == "":
			continue
		if not idx.has(g):
			idx[g] = out.size()
			out.append([g, []])
		(out[idx[g]][1] as Array).append(a)
	return out


func kb_of(action: String) -> Array:
	return table.kb_of(action)


func kb_default(action: String) -> Array:
	return table.kb_default(action)


func kb_user() -> Dictionary:
	return table.kb_user


## Переназначить клавиши действия ([основная, альтернативная]); null — вернуть по умолчанию.
func set_kb(action: String, specs) -> void:
	if specs == null:
		table.kb_user.erase(action)
	else:
		table.kb_user[action] = specs
	table.save_user()
	apply()


func reset_kb() -> void:
	table.kb_user.clear()
	table.save_user()
	apply()


func pad_defaults() -> Dictionary:
	return table.pad_defaults()


func pad_axes() -> Dictionary:
	return table.pad_axes()


## «Свой» пресет геймпада: section "pad" — игрок 1, "pad2" — игрок 2.
func pad_custom(section: String) -> Dictionary:
	return table.pad_user.get(section, {})


func set_pad_custom(section: String, c: Dictionary) -> void:
	table.pad_user[section] = c
	table.save_user()
	glyphs_changed.emit()


# ---------- режимы ----------

func mode_on(mode: String, owner: Object) -> void:
	if modes.set_mode(mode, owner, true):
		mode_changed.emit(modes.top())


func mode_off(mode: String, owner: Object) -> void:
	if modes.set_mode(mode, owner, false):
		mode_changed.emit(modes.top())


func mode_set(mode: String, owner: Object, on: bool) -> void:
	if on:
		mode_on(mode, owner)
	else:
		mode_off(mode, owner)


func mode() -> String:
	return modes.top()


## Работает ли действие в текущем режиме (действия не из таблицы, например ui_*, — всегда).
func allowed(action: String) -> bool:
	if not table.rows.has(action):
		return true
	return modes.top() in (table.rows[action]["modes"] as Array)


# ---------- опрос ----------

func _src(who) -> Object:
	if who != null and is_instance_valid(who):
		var ia = who.get("ia")
		if ia != null:
			return ia
	return Input


func pressed(who, action: String) -> bool:
	return allowed(action) and InputMap.has_action(action) and _src(who).is_action_pressed(action)


func just_pressed(who, action: String) -> bool:
	return allowed(action) and InputMap.has_action(action) and _src(who).is_action_just_pressed(action)


func just_released(who, action: String) -> bool:
	var s := _src(who)
	return allowed(action) and InputMap.has_action(action) and s.has_method("is_action_just_released") and s.is_action_just_released(action)


func strength(who, action: String) -> float:
	if not allowed(action) or not InputMap.has_action(action):
		return 0.0
	var s := _src(who)
	if s.has_method("get_action_strength"):
		return s.get_action_strength(action)
	return 1.0 if s.is_action_pressed(action) else 0.0


func vector(who, nx: String, px: String, ny: String, py: String) -> Vector2:
	for a in [nx, px, ny, py]:
		if not InputMap.has_action(a) or not allowed(a):
			return Vector2.ZERO
	return _src(who).get_vector(nx, px, ny, py)


## Событие e нажимает действие (с учётом режима). pad_raw-кнопки геймпада из таблицы тоже засчитываются.
func event(e: InputEvent, action: String, allow_echo := false) -> bool:
	if e == null or not allowed(action):
		return false
	if InputMap.has_action(action) and e.is_action_pressed(action, allow_echo):
		return true
	if e is InputEventJoypadButton and e.pressed and table.rows.has(action):
		return str(table.rows[action]["pad"]) == "b:%d" % (e as InputEventJoypadButton).button_index
	return false


func event_released(e: InputEvent, action: String) -> bool:
	return e != null and allowed(action) and InputMap.has_action(action) and e.is_action_released(action)


func is_event(e: InputEvent, action: String) -> bool:
	return e != null and InputMap.has_action(action) and e.is_action(action)


## Клавиши действия физически зажаты (антизалипание player.gd: Windows «съедает» отпускания).
func physically_held(action: String) -> bool:
	if not InputMap.has_action(action):
		return false
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			if (k.physical_keycode != KEY_NONE and Input.is_physical_key_pressed(k.physical_keycode)) \
					or (k.keycode != KEY_NONE and Input.is_key_pressed(k.keycode)):
				return true
		elif ev is InputEventMouseButton and Input.is_mouse_button_pressed((ev as InputEventMouseButton).button_index):
			return true
		elif ev is InputEventJoypadMotion or ev is InputEventJoypadButton:
			return true   # с геймпада не трогаем
	return false


## Курок геймпада 0..1 (любой подключённый, первый ненулевой): side "L" / "R".
func trigger(side: String) -> float:
	for d in Input.get_connected_joypads():
		var v := Input.get_joy_axis(d, JOY_AXIS_TRIGGER_LEFT if side == "L" else JOY_AXIS_TRIGGER_RIGHT)
		if absf(v) > 0.01:
			return v
	return 0.0


# ---------- глифы и подсказки ----------

func kind() -> String:
	return Router.kind()


## Имя кнопки действия для вида ввода kind ("" — текущий у игрока 1).
func glyph(action: String, kind_ := "") -> String:
	var k := kind_ if kind_ != "" else Router.kind()
	if k == Glyphs.KB:
		var b := table.kb_of(action)
		return Glyphs.kb_name(str(b[0])) if str(b[0]) != "" else (Glyphs.kb_name(str(b[1])) if str(b[1]) != "" else "—")
	var pad = preload("res://scripts/controls/gamepad.gd").inst
	var spec := ""
	if pad != null and is_instance_valid(pad):
		spec = pad.spec_of(action)
	elif table.rows.has(action):
		spec = str(table.rows[action]["pad"])
	return Glyphs.pad_name(spec, k)


## Подсказка под текущий ввод: «{interact}» -> имя кнопки; старые «[F]» -> кнопка действия, которому F назначена
## по таблице (hint=…), с учётом переназначения игрока.
func hint(text: String, kind_ := "") -> String:
	if not ("{" in text or "[" in text):
		return text
	if _tok_re == null:
		_tok_re = RegEx.create_from_string("\\{([a-z_0-9]+)\\}|\\[([^\\[\\]{}]{1,12})\\]")
	var ms := _tok_re.search_all(text)
	for i in range(ms.size() - 1, -1, -1):
		var m: RegExMatch = ms[i]
		var rep := ""
		if m.get_string(1) != "":
			var a := m.get_string(1)
			if not table.rows.has(a):
				continue
			rep = glyph(a, kind_)
		else:
			var a2: String = table.hint_keys.get(m.get_string(2).strip_edges(), "")
			if a2 == "":
				continue
			rep = "[" + glyph(a2, kind_) + "]"
		text = text.substr(0, m.get_start()) + rep + text.substr(m.get_end())
	return text
