extends Node
## Геймпад (промпт 18.11 00:41). Создаёт menu.gd (menu.pad), работает и на паузе.
## Два пресета: «По умолчанию» (DEFAULT, не меняется) и «Свой» (custom, переназначается в настройках).
## Кнопки не кладём в InputMap: этот узел сам шлёт InputEventAction (так работают сочетания Back+кнопка).
## В InputMap идут только оси левого стика (ходьба, аналогово) — и только пока геймпад подключён,
## чтобы не мешать антизалипанию клавиш (player.gd: _unstick_moves).
## Когда курсор виден (меню, инвентарь, магазин…): левый стик — курсор, A — ЛКМ, X — ПКМ,
## B — назад (ui_cancel), LB — повернуть предмет (пробел), правый стик — прокрутка. Start — пауза всегда.
## Руки (промпт 20.11 11:43): кнопка слота (крестовина) — нажать: в левую руку, задержать: в правую.
## Сброс: Back (просто нажать) — режим сброса, потом RT — из левой, LT — из правой (задержать — кинуть дальше).

const CFG := "user://settings.cfg"
const MOD := JOY_BUTTON_BACK     # модификатор сочетаний «Back + кнопка»

## Спецификация кнопки: "b:N" — кнопка N, "c:N" — Back + кнопка N, "t:L"/"t:R" — курок, "" — нет.
const DEFAULT := {
	"jump": "b:0", "handbrake": "b:0",                 # A
	"crouch_toggle": "b:1",                            # B
	"interact": "b:2",                                 # X
	"inventory": "b:3",                                # Y
	"quick_heal": "b:9",                               # LB
	"reload": "b:10", "loot_all": "b:10",              # RB
	"attack_right": "t:L", "attack_left": "t:R",       # LT — прицел/правая, RT — выстрел/левая
	"sprint": "b:7",                                   # L3 — бег (до остановки)
	"fists": "b:8", "inv_use": "b:8",                  # R3 — стойка; в инвентаре — использовать
	"hot_1": "b:11", "hot_2": "b:14", "hot_3": "b:12", "hot_4": "b:13",   # крестовина ↑ → ↓ ←
	"hot_5": "c:11", "gasmask": "c:12", "carry": "c:13", "swap_hands": "c:14",
	"mag_eject": "c:10", "crouch": "c:1", "toggle_ping": "c:3", "hide_ui": "c:9",
	"seat_switch": "c:2",                               # Back + X — пересесть в машине
	"drop_mode": "b:4",                                 # Back (без второй кнопки) — режим сброса
}
const HOLD_T := 0.35         # кнопку слота держат дольше — предмет в правую руку

const DZ := 0.18             # мёртвая зона стиков
const LOOK_PX := 1500.0      # обзор: «пикселей мыши» в секунду при полном отклонении
const CURSOR_PX := 1100.0    # курсор в меню, пикс/с
const MOVE_DZ := 0.3         # мёртвая зона действий ходьбы (InputMap)
const Split := preload("res://scripts/network/split.gd")
const SYNTH := 77            # device у мыши/клавиш, которые шлёт этот узел (сплитскрин отличает их от настоящих)

var preset := "default"      # "default" | "custom"
var custom := {}             # действие -> спецификация
var swap_sticks := false     # только для «Своего»: ходьба правым, обзор левым
var invert_y := false
var sens := 1.0
var capturing := false       # настройки ждут кнопку — ничего не шлём

var held := {}               # физическая кнопка ("b:N"/"t:L") -> [действия]
var mod_down := false
var mod_used := false
var trig := {"L": false, "R": false}
var ui_held := {}            # кнопки, нажатые в режиме курсора (A/X)
var mouse_mask := 0
var sprint_latch := false
var pending := []            # [действие, время отпускания, устройство]
var wheel_t := 0.0
var hot_hold := {}           # кнопка слота -> [слоты hot_N, время нажатия, устройство, уже сработало]
var last_dev := 0
var only_device := -1        # сплитскрин (network/split.gd): -1 любой геймпад, -2 никакой, N — только этот
var virtual_cursor := false  # курсор свой, настоящую мышь не двигаем (сейчас не используется)
var vpos := Vector2(200, 200)
var cursor_layer: CanvasLayer
var cursor_dot: Control


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_cfg()


func _ready() -> void:
	if virtual_cursor:
		cursor_layer = CanvasLayer.new()
		cursor_layer.layer = 128
		add_child(cursor_layer)
		cursor_dot = Control.new()
		cursor_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cursor_dot.draw.connect(func():
			var pts := PackedVector2Array([Vector2.ZERO, Vector2(0, 22), Vector2(6, 16), Vector2(15, 16)])
			cursor_dot.draw_colored_polygon(pts, Color(1, 1, 1))
			cursor_dot.draw_polyline(pts + PackedVector2Array([Vector2.ZERO]), Color(0, 0, 0), 2.0))
		cursor_layer.add_child(cursor_dot)
	Input.joy_connection_changed.connect(func(_d, _c): apply_map())
	# убираем геймпад из ui_*: иначе B в игре = Esc (пауза), A жмёт кнопку с фокусом дважды
	for a in ["ui_accept", "ui_select", "ui_cancel", "ui_up", "ui_down", "ui_left", "ui_right",
			"ui_focus_next", "ui_focus_prev", "ui_page_up", "ui_page_down"]:
		if not InputMap.has_action(a):
			continue
		for ev in InputMap.action_get_events(a):
			if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
				InputMap.action_erase_event(a, ev)
	apply_map()


# ---------- настройки ----------

func binds() -> Dictionary:
	return DEFAULT if preset == "default" else custom


func spec_of(action: String) -> String:
	return str(binds().get(action, ""))


func swapped() -> bool:
	return swap_sticks and preset == "custom"


func load_cfg() -> void:
	var cf := ConfigFile.new()
	if cf.load(CFG) != OK:
		return
	preset = str(cf.get_value("pad", "preset", "default"))
	var c = cf.get_value("pad", "custom", {})
	custom = c if c is Dictionary else {}
	# новые действия (сброс) — в старый «Свой» пресет, если их кнопка там свободна
	if not custom.is_empty():
		for a in ["drop_mode"]:
			if not custom.has(a) and not str(DEFAULT[a]) in custom.values():
				custom[a] = DEFAULT[a]
	swap_sticks = bool(cf.get_value("pad", "swap_sticks", false))
	invert_y = bool(cf.get_value("pad", "invert_y", false))
	sens = float(cf.get_value("pad", "sens", 1.0))


func save_cfg() -> void:
	var cf := ConfigFile.new()
	cf.load(CFG)   # остальные секции (settings, controls, net) не трогаем
	cf.set_value("pad", "preset", preset)
	cf.set_value("pad", "custom", custom)
	cf.set_value("pad", "swap_sticks", swap_sticks)
	cf.set_value("pad", "invert_y", invert_y)
	cf.set_value("pad", "sens", sens)
	cf.save(CFG)


func set_preset(p: String) -> void:
	release_all()
	preset = p
	if p == "custom" and custom.is_empty():
		custom = DEFAULT.duplicate()
	apply_map()
	save_cfg()


func reset_custom() -> void:
	release_all()
	custom = DEFAULT.duplicate()
	swap_sticks = false
	apply_map()
	save_cfg()


static func spec_name(spec: String) -> String:
	if spec == "":
		return "—"
	var p := spec.split(":")
	if p.size() != 2:
		return "?"
	if p[0] == "t":
		return "LT" if p[1] == "L" else "RT"
	var n := _btn_name(int(p[1]))
	return ("Back + " + n) if p[0] == "c" else n


static func _btn_name(b: int) -> String:
	return {0: "A", 1: "B", 2: "X", 3: "Y", 4: "Back", 5: "Guide", 6: "Start", 7: "L3", 8: "R3",
		9: "LB", 10: "RB", 11: "↑", 12: "↓", 13: "←", 14: "→", 15: "Share"}.get(b, "Кнопка %d" % b)


## Оси ходьбы — в InputMap (вызывает и menu.gd после своих клавиш: он стирает события действий).
func apply_map() -> void:
	# сплитскрин (network/split.gd): у игрока 1 — первый геймпад, если их два; иначе только клавиатура и мышь
	only_device = Split.pad_device(false) if Split.inst != null and is_instance_valid(Split.inst) else -1
	var pads := not Input.get_connected_joypads().is_empty() and only_device != -2
	var sx := JOY_AXIS_RIGHT_X if swapped() else JOY_AXIS_LEFT_X
	var sy := JOY_AXIS_RIGHT_Y if swapped() else JOY_AXIS_LEFT_Y
	var axes := {"move_left": [sx, -1.0], "move_right": [sx, 1.0], "move_forward": [sy, -1.0], "move_back": [sy, 1.0],
		"sprint": [JoyAxis.JOY_AXIS_INVALID, 1.0]}   # sprint: ось-заглушка, чтобы _unstick_moves не отпускал бег с геймпада
	for a in axes:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
		for ev in InputMap.action_get_events(a):
			if ev is InputEventJoypadMotion or ev is InputEventJoypadButton:
				InputMap.action_erase_event(a, ev)
		if not pads:
			continue
		var m := InputEventJoypadMotion.new()
		m.device = only_device if only_device >= 0 else -1
		m.axis = axes[a][0]
		m.axis_value = axes[a][1]
		InputMap.action_add_event(a, m)
		if a != "sprint":
			InputMap.action_set_deadzone(a, MOVE_DZ)


# ---------- ввод ----------

func _mine(e: InputEvent) -> bool:
	return only_device == -1 or e.device == only_device


func _input(e: InputEvent) -> void:
	if capturing or not _mine(e):
		return
	if e is InputEventJoypadButton:
		last_dev = e.device
		_button("b:%d" % e.button_index, e.button_index, e.pressed, e.device)
	elif e is InputEventJoypadMotion and (e.axis == JOY_AXIS_TRIGGER_LEFT or e.axis == JOY_AXIS_TRIGGER_RIGHT):
		last_dev = e.device
		var side := "L" if e.axis == JOY_AXIS_TRIGGER_LEFT else "R"
		var on: bool = e.axis_value > (0.3 if trig[side] else 0.5)
		if on != trig[side]:
			trig[side] = on
			_button("t:" + side, -1, on, e.device)


func _ui_mode() -> bool:
	return Input.mouse_mode != Input.MOUSE_MODE_CAPTURED


func _button(key: String, b: int, pressed: bool, dev: int) -> void:
	if b == JOY_BUTTON_START:
		if pressed:
			_tap("ui_cancel", dev)   # пауза / закрыть
		return
	if b == MOD:
		if pressed:
			mod_down = true
			mod_used = false
		else:
			mod_down = false
			if not mod_used:
				for a in _actions("b:%d" % MOD):
					_tap(a, dev)
		return
	if not pressed:
		if ui_held.has(key):
			_ui_button(b, false)
			ui_held.erase(key)
		for a in held.get(key, []):
			_act(a, false, dev)
		held.erase(key)
		if hot_hold.has(key):
			var hh: Array = hot_hold[key]
			hot_hold.erase(key)
			if not hh[3]:
				for a in hh[0]:
					_tap(a, dev)   # коротко — в левую руку
		return
	if _ui_mode() and _ui_button(b, true):
		ui_held[key] = true
		return
	var spec := key
	if mod_down and b >= 0:
		spec = "c:%d" % b
		mod_used = true
	var acts := _actions(spec)
	# слоты hot_N — на отпускании (коротко — левая) или по задержке (правая, _hot_tick)
	var hots: Array = acts.filter(func(a): return str(a).begins_with("hot_"))
	if not hots.is_empty() and not _ui_mode():
		acts = acts.filter(func(a): return not str(a).begins_with("hot_"))
		hot_hold[key] = [hots, Time.get_ticks_msec(), dev, false]
	held[key] = acts
	for a in acts:
		_act(a, true, dev)


## Кнопки в режиме курсора (не переназначаются). true — съели нажатие.
func _ui_button(b: int, pressed: bool) -> bool:
	match b:
		JOY_BUTTON_A:
			_mouse_btn(MOUSE_BUTTON_LEFT, pressed)
			return true
		JOY_BUTTON_X:
			_mouse_btn(MOUSE_BUTTON_RIGHT, pressed)
			return true
		JOY_BUTTON_B:
			if pressed:
				_tap("ui_cancel", last_dev)
			return true
		JOY_BUTTON_LEFT_SHOULDER:
			var k := InputEventKey.new()
			k.physical_keycode = KEY_SPACE
			k.keycode = KEY_SPACE
			k.pressed = pressed
			k.device = SYNTH
			Input.parse_input_event(k)
			return true
	return false


func _actions(spec: String) -> Array:
	var out: Array = []
	var bd := binds()
	for a in bd:
		if str(bd[a]) == spec:
			out.append(a)
	return out


func _act(a: String, pressed: bool, dev: int) -> void:
	if a == "sprint":
		if pressed:
			sprint_latch = true   # L3: бежим, пока не остановишься
		else:
			return
	var ev := InputEventAction.new()
	ev.action = a
	ev.pressed = pressed
	ev.strength = 1.0 if pressed else 0.0
	ev.device = dev
	Input.parse_input_event(ev)


## Нажать и чуть позже отпустить (иначе is_action_just_pressed в физике может не увидеть).
func _tap(a: String, dev: int) -> void:
	_act(a, true, dev)
	pending.append([a, Time.get_ticks_msec() + 90, dev])


## Кнопку слота держат HOLD_T — слот в правую руку: hand_right зажат, пока жмём hot_N (game.gd).
func _hot_tick() -> void:
	var now := Time.get_ticks_msec()
	for k in hot_hold:
		var hh: Array = hot_hold[k]
		if hh[3] or now - int(hh[1]) < int(HOLD_T * 1000.0):
			continue
		hh[3] = true
		_tap("hand_right", int(hh[2]))
		for a in hh[0]:
			_tap(a, int(hh[2]))


func release_all() -> void:
	hot_hold.clear()
	for k in held:
		for a in held[k]:
			_act(a, false, last_dev)
	held.clear()
	if sprint_latch:
		sprint_latch = false
		_act("sprint", false, last_dev)


func _mouse_btn(bi: MouseButton, pressed: bool) -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = bi
	mb.pressed = pressed
	var bit := 1 << (int(bi) - 1)
	mouse_mask = (mouse_mask | bit) if pressed else (mouse_mask & ~bit)
	mb.button_mask = mouse_mask
	mb.device = SYNTH
	var p := vpos if virtual_cursor else _win_mouse()
	mb.position = p
	mb.global_position = p
	Input.parse_input_event(mb)


func _win_mouse() -> Vector2:
	return Vector2(DisplayServer.mouse_get_position() - DisplayServer.window_get_position())


func _stick(left: bool) -> Vector2:
	var v := Vector2.ZERO
	if only_device == -2:
		return v
	for d in Input.get_connected_joypads():
		if only_device >= 0 and d != only_device:
			continue
		var w := Vector2(Input.get_joy_axis(d, JOY_AXIS_LEFT_X if left else JOY_AXIS_RIGHT_X),
			Input.get_joy_axis(d, JOY_AXIS_LEFT_Y if left else JOY_AXIS_RIGHT_Y))
		if w.length() > v.length():
			v = w
	var l := v.length()
	if l < DZ:
		return Vector2.ZERO
	var k := (minf(l, 1.0) - DZ) / (1.0 - DZ)
	return v / l * k * k   # квадратичная кривая: точно в центре, быстро у края


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec()
	for i in range(pending.size() - 1, -1, -1):
		if now >= int(pending[i][1]):
			_act(pending[i][0], false, int(pending[i][2]))
			pending.remove_at(i)
	_hot_tick()
	if cursor_dot:
		cursor_dot.visible = _ui_mode()
		cursor_dot.position = get_tree().root.get_final_transform().affine_inverse() * vpos
	if Input.get_connected_joypads().is_empty() or capturing or only_device == -2:
		return
	var move := _stick(not swapped())
	var look := _stick(swapped())
	if sprint_latch and move.length() < 0.05:
		sprint_latch = false
		_act("sprint", false, last_dev)
	if _ui_mode():
		_cursor(_stick(true), delta)
		wheel_t -= delta
		var r := _stick(false)
		if absf(r.y) > 0.3 and wheel_t <= 0.0:
			wheel_t = 0.09 / absf(r.y)
			var wb := MOUSE_BUTTON_WHEEL_DOWN if r.y > 0.0 else MOUSE_BUTTON_WHEEL_UP
			_mouse_btn(wb, true)
			_mouse_btn(wb, false)
		return
	if look == Vector2.ZERO or get_tree().paused:
		return
	var p = _player()
	if p == null:
		return
	if invert_y:
		look.y = -look.y
	p.look(Vector2(look.x, look.y * 0.75) * LOOK_PX * sens * delta)


func _cursor(v: Vector2, delta: float) -> void:
	if v == Vector2.ZERO:
		return
	# координаты окна (пиксели экрана): так их ждут warp_mouse и события, окно само пересчитает масштаб интерфейса
	var p0 := vpos if virtual_cursor else _win_mouse()
	var sz := Vector2(DisplayServer.window_get_size())
	var p1 := (p0 + v * CURSOR_PX * delta).clamp(Vector2.ZERO, sz - Vector2.ONE)
	vpos = p1
	if not virtual_cursor:
		Input.warp_mouse(p1)
	var mm := InputEventMouseMotion.new()
	mm.position = p1
	mm.global_position = p1
	mm.relative = p1 - p0
	mm.velocity = v * CURSOR_PX
	mm.button_mask = mouse_mask
	mm.device = SYNTH
	Input.parse_input_event(mm)


## Игрок, которому крутим обзор: активный пешком или сидящий в машине.
func _player():
	for c in get_tree().root.get_children():
		for n in c.get_children():
			if n.has_method("save_now") and n.get("player") != null:
				var p = n.player
				var car = n.get("car")
				var seated: bool = car != null and is_instance_valid(car) and car.get("my_seat") != null and int(car.my_seat) >= 0
				if p.active or seated:
					return p
				return null
	return null
