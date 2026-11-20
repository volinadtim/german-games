extends Node
## Геймпад (промпт 18.11 00:41). Создаёт menu.gd (menu.pad), работает и на паузе.
## Два пресета: «По умолчанию» (DEFAULT, не меняется) и «Свой» (custom, переназначается в настройках).
## Кнопки не кладём в InputMap: этот узел сам шлёт InputEventAction (так работают сочетания Back+кнопка).
## В InputMap идут только оси левого стика (ходьба, аналогово) — и только пока геймпад подключён,
## чтобы не мешать антизалипанию клавиш (player.gd: _unstick_moves).
## Когда курсор виден (меню, инвентарь, магазин…): навигация — autoload UiNav (ui/ui_nav.gd, встроенный фокус):
## крестовина (все 4 стороны) и правый стик шлют ui_up / ui_down / ui_left / ui_right; левый стик — тоже, но только пока
## персонаж не управляется (пауза, главное меню, магазин, лут), иначе он — ходьба. Back (коротко) — toggle_cursor:
## рамка ↔ свободный курсор (его водит правый стик). A — ЛКМ по рамке, X — ПКМ, B — назад (ui_cancel), RB — крафт
## в инвентаре, при перетаскивании LB — повернуть предмет. В игре курсора нет. Start — пауза всегда.
## Back + стрелка в инвентаре — привязать предмет под рамкой к слоту (как раньше просто стрелка).
## Руки (промпт 20.11 11:43): кнопка слота (крестовина) — нажать: в левую руку, задержать: в правую.
## Сброс: RB — режим сброса, потом LT — из левой, RT — из правой (задержать — кинуть дальше).
## LT — левая рука (ЛКМ), RT — правая / прицел (ПКМ); B — присед, LB — бег, X — взаимодействие (промпт 20.11 15:29).

const CFG := "user://settings.cfg"
const MOD := JOY_BUTTON_BACK     # модификатор сочетаний «Back + кнопка»

## Спецификация кнопки: "b:N" — кнопка N, "c:N" — Back + кнопка N, "t:L"/"t:R" — курок, "" — нет.
const DEFAULT := {
	# раскладка Германа (промпт 20.11 15:29): A — прыжок, B — присед, X — взаимодействие, Y — инвентарь,
	# LB — бег вкл/выкл, RB — режим сброса (в инвентаре RB — крафт), LT/RT — левая / правая рука
	"jump": "b:0", "handbrake": "b:0",                 # A
	"crouch_toggle": "b:1",                            # B — присед (как было)
	"interact": "b:2",                                 # X — взаимодействие / поднять союзника
	"inventory": "b:3",                                # Y
	"sprint": "b:9",                                   # LB — бег (до остановки или повторного LB)
	"attack_left": "t:L", "attack_right": "t:R",       # LT — левая рука / выстрел (ЛКМ), RT — правая / прицел (ПКМ)
	"drop_mode": "b:10",                               # RB — режим сброса, потом LT — из левой, RT — из правой
	"fists": "b:8", "inv_use": "b:8",                  # R3 — стойка; в инвентаре — использовать
	# крестовина (промпты 20.11 14:51/14:54): ← держать — круговое меню хотбара (ui/pad_wheel.gd), → — перезарядка,
	# ↑ ↓ в игре свободны (в окнах — ui_up / ui_down, ui/ui_nav.gd). hot_wheel ловит _button.
	"hot_wheel": "b:13", "reload": "b:14",
	"loot_all": "c:0",                                  # Back + A — забрать всё (в окне лута)
	"hot_5": "c:11", "gasmask": "c:12", "carry": "c:13", "swap_hands": "c:14",
	"mag_eject": "c:10", "crouch": "c:1", "toggle_ping": "c:3", "hide_ui": "c:9",
	"seat_switch": "c:2",                               # Back + X — пересесть в машине
	"skills": "c:7",                                    # Back + L3 — окно прокачки (промпт 20.11 18:54)
	"toggle_cursor": "b:4",                             # Back коротко — в окнах рамка ↔ курсор (промпт 20.11 15:24)
}
const SPRINT_HOLD := 0.2    # бег: держат кнопку бега во время бега — выключить (промпт 20.11 15:31)
const SPRINT_STILL := 1.0   # ...или постоять на месте секунду
const UI_DIR := {JOY_BUTTON_DPAD_UP: "ui_up", JOY_BUTTON_DPAD_DOWN: "ui_down", JOY_BUTTON_DPAD_LEFT: "ui_left", JOY_BUTTON_DPAD_RIGHT: "ui_right"}
const HOLD_T := 0.35         # кнопку слота держат дольше — предмет в правую руку
const UI_HOT := {JOY_BUTTON_DPAD_UP: 1, JOY_BUTTON_DPAD_RIGHT: 2, JOY_BUTTON_DPAD_DOWN: 3, JOY_BUTTON_DPAD_LEFT: 4}

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
var section := "pad"         # секция settings.cfg: "pad" — игрок 1, "pad2" — игрок 2 (сплитскрин)
var profile := false         # true — только настройки игрока 2 (узел не в дереве, ввод не обрабатывает)
var p2                       # gamepad.gd-профиль игрока 2: свой пресет, кнопки, чувствительность (промпт 20.11 14:49)
var swap_pads := false       # сплитскрин: поменять геймпады игроков местами (network/split.gd: pad_device)

var held := {}               # физическая кнопка ("b:N"/"t:L") -> [действия]
var mod_down := false
var mod_used := false
var trig := {"L": false, "R": false}
var ui_held := {}            # кнопки, нажатые в режиме курсора (A/X)
var mouse_mask := 0
var sprint_latch := false
var _sprint_hold := -1       # мс, когда во время бега зажали кнопку бега (-1 — не держат)
var _still_t := 0.0          # сколько стоим на месте при включённом беге
var pending := []            # [действие, время отпускания, устройство]
var wheel_t := 0.0
var hot_hold := {}           # кнопка слота -> [слоты hot_N, время нажатия, устройство, уже сработало]
var last_dev := 0
var only_device := -1        # сплитскрин (network/split.gd): -1 любой геймпад, -2 никакой, N — только этот
var ui_owner := -1           # сплитскрин: паузу открыл геймпад игрока 2 — меню водит только он (до возврата в игру)
var virtual_cursor := false  # курсор свой, настоящую мышь не двигаем (сейчас не используется)
var vpos := Vector2(200, 200)
var cursor_layer: CanvasLayer
var cursor_dot: Control
var nav                      # ui/ui_nav.gd — autoload UiNav, навигация в меню
static var inst              # главный узел (menu.pad) — для pad_text / rumble
static var ps := false       # последний геймпад — PlayStation (DualSense): другие имена кнопок
var vibration := true        # вибрация (settings.cfg [pad] vibration)
var _ps_dev := -99
var _tok_re: RegEx
var _tok_cache := {}
var wheel                    # ui/pad_wheel.gd — круговое меню хотбара
var lb_space := false
var dl_t := 0                # ← крестовины зажата в инвентаре (мс) — держать дольше HOLD_T: круг хотбара
var trig_ui := {}            # курки, нажатые в инвентаре (LT — перетаскивание, RT — поворот)


func _init(sec := "pad") -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	section = sec
	profile = sec != "pad"
	load_cfg()
	if not profile:
		p2 = get_script().new("pad2")


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and p2 and is_instance_valid(p2):
		p2.free()


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
	inst = self
	nav = get_node("/root/UiNav")
	nav.pad = self
	wheel = preload("res://scripts/ui/pad_wheel.gd").new()
	wheel.pad = self
	add_child(wheel)
	Input.joy_connection_changed.connect(func(d, c):
		apply_map()
		if c and d == _ps_dev:
			ps = is_ps(d)
		_tok_cache.clear())
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
	if not profile:
		swap_pads = bool(cf.get_value("pad", "swap_pads", false))
		Split.swap_pads = swap_pads
	if not cf.has_section(section):
		return
	preset = str(cf.get_value(section, "preset", "default"))
	var c = cf.get_value(section, "custom", {})
	custom = c if c is Dictionary else {}
	# новые действия (сброс) — в старый «Свой» пресет, если их кнопка там свободна
	if not custom.is_empty():
		custom.erase("pad_cursor")   # курсор в игре убран (промпт 20.11 15:04)
		for a in ["drop_mode", "hot_wheel", "toggle_cursor"]:
			if not custom.has(a) and not str(DEFAULT[a]) in custom.values():
				custom[a] = DEFAULT[a]
	swap_sticks = bool(cf.get_value(section, "swap_sticks", false))
	invert_y = bool(cf.get_value(section, "invert_y", false))
	vibration = bool(cf.get_value(section, "vibration", true))
	sens = float(cf.get_value(section, "sens", 1.0))


func save_cfg() -> void:
	var cf := ConfigFile.new()
	cf.load(CFG)   # остальные секции (settings, controls, net) не трогаем
	cf.set_value(section, "preset", preset)
	cf.set_value(section, "custom", custom)
	cf.set_value(section, "swap_sticks", swap_sticks)
	cf.set_value(section, "invert_y", invert_y)
	cf.set_value(section, "vibration", vibration)
	cf.set_value(section, "sens", sens)
	if not profile:
		cf.set_value("pad", "swap_pads", swap_pads)
		Split.swap_pads = swap_pads
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
		if ps:
			return "L2" if p[1] == "L" else "R2"
		return "LT" if p[1] == "L" else "RT"
	var n := _btn_name(int(p[1]))
	return (_btn_name(MOD) + " + " + n) if p[0] == "c" else n


## Имя кнопки: раскладка Xbox (Flydigi в XInput и прочие) или PlayStation (DualSense/DualShock — ps).
## Godot (SDL) нумерует по положению: 0 — нижняя (A / ✕), 1 — правая (B / ○), 2 — левая (X / □), 3 — верхняя (Y / △).
static func _btn_name(b: int) -> String:
	if ps:
		return {0: "✕", 1: "○", 2: "□", 3: "△", 4: "Create", 5: "PS", 6: "Options", 7: "L3", 8: "R3",
			9: "L1", 10: "R1", 11: "↑", 12: "↓", 13: "←", 14: "→", 15: "Mute", 20: "Тачпад"}.get(b, "Кнопка %d" % b)
	return {0: "A", 1: "B", 2: "X", 3: "Y", 4: "Back", 5: "Guide", 6: "Start", 7: "L3", 8: "R3",
		9: "LB", 10: "RB", 11: "↑", 12: "↓", 13: "←", 14: "→", 15: "Share"}.get(b, "Кнопка %d" % b)


## Геймпад PlayStation? Сначала производитель Sony (054C = 1356; на Android get_joy_info пуст), потом имя.
static func is_ps(dev: int) -> bool:
	var info := Input.get_joy_info(dev)
	var vid := str(info.get("vendor_id", "")).to_lower()
	if vid == "1356" or vid == "054c" or vid == "0x054c":
		return true
	var n := (Input.get_joy_name(dev) + " " + str(info.get("raw_name", ""))).to_lower()
	for w in ["ps5", "ps4", "ps3", "dualsense", "dualshock", "playstation", "sony"]:
		if w in n:
			return true
	return false


## Подсказка на экране (hud.gd prompt/toast): последний ввод с геймпада — «[F]» и «ЛКМ/ПКМ» меняем
## на кнопки геймпада по текущей раскладке; ввод с клавиатуры/мыши — текст как есть (промпт 20.11 14:49).
static func pad_text(s: String) -> String:
	if inst == null or not is_instance_valid(inst) or inst.nav == null or not inst.nav.pad_used or inst.nav.by_kb:
		return s
	return inst._pad_text(s)


func _pad_text(s: String) -> String:
	if _tok_re == null:
		_tok_re = RegEx.create_from_string("\\[([^\\[\\]]{1,12})\\]")
	var ms := _tok_re.search_all(s)
	for i in range(ms.size() - 1, -1, -1):
		var m: RegExMatch = ms[i]
		var n := _key_to_pad(m.get_string(1))
		if n != "":
			s = s.substr(0, m.get_start()) + "[" + n + "]" + s.substr(m.get_end())
	if "ЛКМ" in s or "ПКМ" in s:
		s = s.replace("ЛКМ", spec_name(spec_of("attack_left"))).replace("ПКМ", spec_name(spec_of("attack_right")))
	return s


## Клавиша (как в «[F]») -> кнопка геймпада того действия, что на ней висит; "" — не нашли.
func _key_to_pad(tok: String) -> String:
	var t := tok.strip_edges().to_upper()
	if _tok_cache.has(t):
		return _tok_cache[t]
	var out := ""
	var bd := binds()
	for a in bd:
		if out != "" or str(bd[a]) == "" or not InputMap.has_action(a):
			continue
		for ev in InputMap.action_get_events(a):
			if ev is InputEventKey:
				var k := OS.get_keycode_string(ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode)
				if k.to_upper() == t:
					out = spec_name(str(bd[a]))
					break
	_tok_cache[t] = out
	return out


## Вибрация последнего геймпада (если играют с него): weak/strong 0..1, dur — секунды.
static func rumble(weak: float, strong: float, dur: float) -> void:
	if inst == null or not is_instance_valid(inst) or inst.nav == null or not inst.nav.pad_used:
		return
	if not bool(inst.get("vibration")):
		return
	Input.start_joy_vibration(inst.last_dev, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), dur)


## Оси ходьбы — в InputMap (вызывает и menu.gd после своих клавиш: он стирает события действий).
func apply_map() -> void:
	_tok_cache.clear()
	if not profile:
		for d in Input.get_connected_joypads():
			if Input.has_joy_light(d):
				Input.set_joy_light(d, Color(1.0, 0.42, 0.08))   # подсветка DualSense — в тон игре
		if not Input.get_connected_joypads().is_empty() and _ps_dev == -99:
			_ps_dev = Input.get_connected_joypads()[0]
			ps = is_ps(_ps_dev)
	if profile:
		return   # у игрока 2 оси читает сам split.gd
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

## Чей геймпад сейчас слушаем: в меню, открытом игроком 2, — его (промпт 20.11 15:15), иначе only_device.
func dev_now() -> int:
	return ui_owner if ui_owner >= 0 and _ui_mode() else only_device


func _mine(e: InputEvent) -> bool:
	var d := dev_now()
	return d == -1 or e.device == d


func _input(e: InputEvent) -> void:
	if capturing or not _mine(e):
		return
	if e is InputEventJoypadButton:
		last_dev = e.device
		if e.device != _ps_dev:
			_ps_dev = e.device
			ps = is_ps(e.device)
			_tok_cache.clear()
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
	if key.begins_with("t:") and _ui_trigger(key, pressed):
		return
	if wheel.is_open and not wheel.assign:
		if not pressed and key == wheel.key:
			wheel.release()
			return
		if pressed and key.begins_with("t:"):
			wheel.pick(key == "t:R")   # RT — в правую руку, LT — в левую
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
	if acts.has("hot_wheel"):
		acts.erase("hot_wheel")
		wheel.open(key, dev)
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
			if mod_down and pressed:
				return false   # Back + A — «забрать всё» (loot_all, c:0) обычным путём
			if pressed and nav.popup_open():
				_send("ui_accept", true, last_dev)   # выпадающий список: выбрать пункт
				_send("ui_accept", false, last_dev)
				return true
			if pressed:
				nav.before_click()
			_mouse_btn(MOUSE_BUTTON_LEFT, pressed)
			return true
		JOY_BUTTON_X:
			if pressed:
				nav.before_click()
			_mouse_btn(MOUSE_BUTTON_RIGHT, pressed)
			return true
		JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT:
			if mod_down:
				# Back + ↑ → ↓ ← — предмет под рамкой в слот 1–4 хотбара (Back + RB — в 5)
				if pressed:
					mod_used = true
					_tap("hot_%d" % UI_HOT[b], last_dev)
				return true
			if b == JOY_BUTTON_DPAD_LEFT and (dl_t > 0 or (pressed and _inv_open())):
				_dl_button(pressed)
				return true
			_send(UI_DIR[b], pressed, last_dev)   # ui_* — UiNav двигает фокус (или листает выпадающий список)
			return true
		JOY_BUTTON_RIGHT_SHOULDER:
			# RB: в инвентаре — крафт (промпт 20.11 15:10); вне инвентаря — как в игре (лут: «забрать всё»)
			if not pressed:
				return true
			if mod_down:
				mod_used = true
				_tap("hot_5", last_dev)
				return true
			return nav.toggle_craft()
		JOY_BUTTON_B:
			if pressed:
				_tap("ui_cancel", last_dev)
			return true
		JOY_BUTTON_LEFT_SHOULDER:
			# LB: тащим предмет — повернуть (пробел); разделов окна больше нет (промпт 20.11 15:10)
			if pressed and not get_viewport().gui_is_dragging():
				return true
			if not pressed and not lb_space:
				return true
			lb_space = pressed
			var k := InputEventKey.new()
			k.physical_keycode = KEY_SPACE
			k.keycode = KEY_SPACE
			k.pressed = pressed
			k.device = SYNTH
			Input.parse_input_event(k)
			return true
	return false


## Открыт инвентарь (у того, чьё меню водим) — для ← с кругом хотбара и курков.
func _inv_open() -> bool:
	var i = nav._inv() if nav else null
	return i != null and bool(i.get("open"))


## ← крестовины в инвентаре (промпт 20.11 17:07): коротко — рамка влево (на отпускании), держать — круг хотбара; отпустить — предмет под рамкой в выбранный слот.
func _dl_button(pressed: bool) -> void:
	if pressed:
		dl_t = Time.get_ticks_msec()
		return
	dl_t = 0
	if wheel.is_open and wheel.assign:
		if wheel.sel >= 0:
			_tap("hot_%d" % (wheel.sel + 1), last_dev)
		wheel.close()
	else:
		_tap("ui_left", last_dev)


## LT/RT в инвентаре (промпт 20.11 17:07): LT держать — перетаскивать (как зажатая ЛКМ), RT — повернуть перетаскиваемый предмет.
func _ui_trigger(key: String, pressed: bool) -> bool:
	if pressed and not (_ui_mode() and _inv_open()):
		return false
	if not pressed and not trig_ui.has(key):
		return false
	if pressed:
		trig_ui[key] = true
	else:
		trig_ui.erase(key)
	if key == "t:L":
		if pressed:
			nav.before_click()
		_mouse_btn(MOUSE_BUTTON_LEFT, pressed)
	elif pressed:
		var inv = nav._inv()
		if inv != null and inv.get_viewport().gui_is_dragging():
			for on in [true, false]:
				var k := InputEventKey.new()
				k.physical_keycode = KEY_SPACE
				k.keycode = KEY_SPACE
				k.pressed = on
				k.device = SYNTH
				Input.parse_input_event(k)
	return true


func _actions(spec: String) -> Array:
	var out: Array = []
	var bd := binds()
	for a in bd:
		if str(bd[a]) == spec:
			out.append(a)
	return out


func _act(a: String, pressed: bool, dev: int) -> void:
	if a == "sprint":
		# бег (промпт 20.11 15:31): нажать — бежим; выключается, если постоять секунду или зажать кнопку бега во время бега
		if not pressed:
			_sprint_hold = -1
			return
		if sprint_latch:
			_sprint_hold = Time.get_ticks_msec()   # держат — выключим в _sprint_tick
			return
		sprint_latch = true
		_still_t = 0.0
	_send(a, pressed, dev)


## Событие действия a в Input (без логики защёлки бега).
func _send(a: String, pressed: bool, dev: int) -> void:
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
		_send("sprint", false, last_dev)


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
	var od := dev_now()
	if od == -2:
		return v
	for d in Input.get_connected_joypads():
		if od >= 0 and d != od:
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
	if dl_t > 0:
		if not _inv_open():
			if wheel.assign:
				wheel.close()
		elif not wheel.is_open and now - dl_t >= int(HOLD_T * 1000.0):
			wheel.assign = true
			wheel.inv_src = nav._inv()
			wheel.open("ui", last_dev)
	if cursor_dot:
		cursor_dot.visible = _ui_mode()
		cursor_dot.position = get_tree().root.get_final_transform().affine_inverse() * vpos
	if ui_owner >= 0 and not _ui_mode():
		ui_owner = -1   # вернулись в игру — меню снова у игрока 1
	if Input.get_connected_joypads().is_empty() or capturing or dev_now() == -2:
		return
	var move := _stick(not swapped())
	var look := _stick(swapped())
	_sprint_tick(move, delta)
	if _ui_mode():
		var v := look
		if _sticks_free() and move.length() > v.length():
			v = move   # персонаж не управляется — левый стик тоже листает (во время ходьбы — нет)
		if wheel.is_open and wheel.assign:
			wheel.aim(look if look.length() >= move.length() else move)   # круг хотбара в инвентаре: любой стик
			return
		if nav.free_cursor():
			_cursor(v, delta)   # свободный курсор (toggle_cursor)
			return
		nav.stick(v, delta)   # рамка по клеткам
		return
	if wheel.is_open:
		wheel.aim(look)   # круговое меню: правый стик выбирает слот, обзор стоит
		return
	if look == Vector2.ZERO or get_tree().paused:
		return
	var p = _player()
	if p == null:
		return
	if invert_y:
		look.y = -look.y
	p.look(Vector2(look.x, look.y * 0.75) * LOOK_PX * sens * delta)


## Бег с геймпада выключается: стоим на месте SPRINT_STILL или держим кнопку бега SPRINT_HOLD.
func _sprint_tick(move: Vector2, delta: float) -> void:
	if not sprint_latch:
		_still_t = 0.0
		return
	_still_t = _still_t + delta if move.length() < 0.05 else 0.0
	var held_long := _sprint_hold >= 0 and Time.get_ticks_msec() - _sprint_hold >= int(SPRINT_HOLD * 1000.0)
	if _still_t >= SPRINT_STILL or held_long:
		sprint_latch = false
		_sprint_hold = -1
		_still_t = 0.0
		_send("sprint", false, last_dev)


## Левый стик свободен от ходьбы: пауза, главное меню или персонаж не управляется (магазин, лут, автомат…).
func _sticks_free() -> bool:
	return get_tree().paused or _player() == null


func _cursor(v: Vector2, delta: float) -> void:
	if v == Vector2.ZERO:
		return
	# координаты окна (пиксели экрана): так их ждут warp_mouse и события, окно само пересчитает масштаб интерфейса
	var p0 := vpos if virtual_cursor else _win_mouse()
	var sz := Vector2(DisplayServer.window_get_size())
	mouse_to((p0 + v * CURSOR_PX * delta).clamp(Vector2.ZERO, sz - Vector2.ONE), v * CURSOR_PX)


## Мышь — в точку окна p1 (пиксели) и движение мыши от геймпада (курсор стиком, рамка ui_nav.gd).
func mouse_to(p1: Vector2, vel := Vector2.ZERO) -> void:
	var p0 := vpos if virtual_cursor else _win_mouse()
	vpos = p1
	if not virtual_cursor:
		Input.warp_mouse(p1)
	if nav:
		nav._warp_ms = Time.get_ticks_msec()
	var mm := InputEventMouseMotion.new()
	mm.position = p1
	mm.global_position = p1
	mm.relative = p1 - p0
	mm.velocity = vel
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
