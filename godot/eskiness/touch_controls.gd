extends CanvasLayer
## Экранное управление для телефонов (Android): джойстик движения слева, свайп справа — обзор,
## круглые кнопки — действия. Показывается только на мобильных (или с флагом запуска `-- --touch`).
## Игру почти не трогает: нажимает те же input-действия, что и клавиатура
## (движение — Input.action_press, остальное — InputEventAction через Input.parse_input_event,
## чтобы срабатывали _input/_unhandled_input), а обзор и удар зовут методы игрока.

const LOOK_K := 1.4          # чувствительность свайпа относительно мыши
const STICK_R := 90.0        # радиус хода джойстика
const DEAD := 0.15
const SPRINT_AT := 0.9       # джойстик до упора вперёд — бег

var player: Node             # player.gd
var game: Node               # game.gd
var root: Control
var touches := {}            # индекс пальца -> роль: "stick" | "look" | имя кнопки
var stick_base := Vector2.ZERO
var stick_pos := Vector2.ZERO
var stick_on := false
var held := {}               # кнопки, которые сейчас зажаты (для подсветки)
var capture_seen := false    # захват мыши на этом устройстве вообще работает
var gameplay := false
var inv_open := false
var _pressed_moves := {}


## Нужно ли экранное управление на этом устройстве.
static func wanted() -> bool:
	return OS.has_feature("mobile") or "--touch" in OS.get_cmdline_user_args()


## Крупнее интерфейс на телефоне: увеличиваем масштаб, пока окна игры (инвентарь ~1220×480,
## магазин ~1200×580) ещё влезают. Работает только вместе с stretch mode canvas_items (project.godot, .mobile).
static func fit_ui(win: Window) -> void:
	if win.content_scale_mode == Window.CONTENT_SCALE_MODE_DISABLED:
		return
	var sz := Vector2(win.size)
	if sz.x <= 0 or sz.y <= 0:
		return
	var base := Vector2(win.content_scale_size)   # 1280×720
	# логический размер при масштабе 1 (aspect = expand: короткая сторона не меньше базовой)
	var ratio := sz.x / sz.y
	var logical := Vector2(base.y * ratio, base.y) if ratio >= base.x / base.y else Vector2(base.x, base.x / ratio)
	win.content_scale_factor = clampf(minf(logical.x / 1240.0, logical.y / 600.0), 1.0, 1.25)


func setup(p: Node, g: Node) -> void:
	player = p
	game = g


func _ready() -> void:
	layer = 4
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.draw.connect(_draw_ui)
	add_child(root)


# ---------- раскладка ----------

## Кнопки: имя -> [центр, радиус, подпись, когда видна: "game" — в игре,
## "bag" — в игре и в открытом инвентаре, "any" — всегда (кроме паузы)].
func _buttons() -> Dictionary:
	var s := root.size
	return {
		"attack": [Vector2(s.x - 160, s.y - 150), 74.0, "УДАР", "game"],
		"fists": [Vector2(s.x - 320, s.y - 90), 48.0, "СТОЙКА", "game"],
		"jump": [Vector2(s.x - 320, s.y - 235), 48.0, "ПРЫЖОК", "game"],
		"interact": [Vector2(s.x - 200, s.y - 330), 46.0, "E", "game"],
		"flashlight": [Vector2(s.x - 58, 150), 40.0, "СВЕТ", "game"],
		"gasmask": [Vector2(s.x - 58, 240), 40.0, "МАСКА", "game"],
		"quick_heal": [Vector2(s.x - 58, 330), 40.0, "ЛЕЧИТЬ", "game"],
		"inventory": [Vector2(s.x - 150, 52), 38.0, "СУМКА", "bag"],
		"ui_cancel": [Vector2(s.x - 58, 52), 38.0, "II", "any"],
	}


func _shown(b: Array) -> bool:
	match b[3]:
		"game":
			return gameplay
		"bag":
			return gameplay or inv_open
	return true


## Ячейки хотбара — там же, где их рисует hud.gd (внизу по центру).
func _hot_rect(k: int) -> Rect2:
	var s := root.size
	var cell := 50.0
	var gap := 6.0
	var x0 := s.x / 2.0 - (cell * 5 + gap * 4) / 2.0
	return Rect2(x0 + k * (cell + gap), s.y - cell - 18.0, cell, cell).grow(6)


func _stick_home() -> Vector2:
	return Vector2(190, root.size.y - 240)


# ---------- состояние ----------

func _process(_delta: float) -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		capture_seen = true
	var ui_open := get_tree().paused
	inv_open = game != null and game.inv != null and game.inv.open
	if inv_open:
		ui_open = true
	if game and game.shop and game.shop.opened:
		ui_open = true
	# прочие окна прячут курсор обратно при закрытии; если захват на устройстве не работает — не смотрим на него
	if capture_seen and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		ui_open = true
	var alive: bool = game == null or game.alive
	var now: bool = player != null and player.active and alive and not ui_open
	if now != gameplay:
		gameplay = now
		if not gameplay:
			_release_all()
	visible = not get_tree().paused
	root.queue_redraw()


func _release_all() -> void:
	for i in touches.keys():
		_end(touches[i])
	touches.clear()


# ---------- ввод ----------

func _input(e: InputEvent) -> void:
	if not visible:
		return
	if e is InputEventScreenTouch:
		if e.pressed:
			var role := _role_at(e.position)
			if role == "":
				return
			touches[e.index] = role
			_begin(role, e.position)
		elif touches.has(e.index):
			_end(touches[e.index])
			touches.erase(e.index)
	elif e is InputEventScreenDrag and touches.has(e.index):
		var role: String = touches[e.index]
		if role == "stick":
			stick_pos = e.position
			_apply_stick()
		elif role == "look" and player and player.has_method("look"):
			player.look(e.relative * LOOK_K)


func _role_at(p: Vector2) -> String:
	var bs := _buttons()
	for name in bs:
		var b: Array = bs[name]
		if _shown(b) and p.distance_to(b[0]) <= b[1] + 10.0:
			return name
	# хотбар: в игре — использовать, в инвентаре — привязать выбранный предмет
	if gameplay or inv_open:
		for k in 5:
			if _hot_rect(k).has_point(p):
				return "hot_%d" % (k + 1)
	if not gameplay:
		return ""
	if p.x < root.size.x * 0.4:
		return "stick" if p.y > root.size.y * 0.3 else ""
	return "look"


func _begin(role: String, p: Vector2) -> void:
	match role:
		"stick":
			stick_on = true
			stick_base = p
			stick_pos = p
		"look":
			pass
		"attack":
			held[role] = true
			if player:
				if not player.fists:
					player.toggle_fists()
				else:
					player.punch()
		"fists":
			held[role] = true
			if player:
				player.toggle_fists()
		_:
			held[role] = true
			_send(role, true)


func _end(role: String) -> void:
	held.erase(role)
	match role:
		"stick":
			stick_on = false
			for a in ["move_left", "move_right", "move_forward", "move_back", "sprint"]:
				Input.action_release(a)
		"look", "attack", "fists":
			pass
		_:
			_send(role, false)


func _send(action: String, on: bool) -> void:
	if not InputMap.has_action(action):
		return
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = on
	ev.strength = 1.0 if on else 0.0
	Input.parse_input_event(ev)


func _apply_stick() -> void:
	var d := (stick_pos - stick_base) / STICK_R
	if d.length() > 1.0:
		# база едет за пальцем, чтобы не приходилось возвращаться
		stick_base = stick_pos - d.normalized() * STICK_R
		d = d.normalized()
	var m := d.length()
	if m < DEAD:
		d = Vector2.ZERO
	_axis("move_right", "move_left", d.x)
	_axis("move_back", "move_forward", d.y)
	if d.y < 0.0 and m >= SPRINT_AT and absf(d.x) < 0.5:
		Input.action_press("sprint")
	else:
		Input.action_release("sprint")


func _axis(pos: String, neg: String, v: float) -> void:
	if v > 0.0:
		Input.action_press(pos, v)
		Input.action_release(neg)
	elif v < 0.0:
		Input.action_press(neg, -v)
		Input.action_release(pos)
	else:
		Input.action_release(pos)
		Input.action_release(neg)


# ---------- рисование ----------

func _draw_ui() -> void:
	var f := ThemeDB.fallback_font
	var bs := _buttons()
	for name in bs:
		var b: Array = bs[name]
		if not _shown(b):
			continue
		var c: Vector2 = b[0]
		var r: float = b[1]
		var on := held.has(name)
		root.draw_circle(c, r, Color(1, 1, 1, 0.22) if on else Color(0, 0, 0, 0.32))
		root.draw_arc(c, r, 0, TAU, 40, Color(1, 0.85, 0.55, 0.75) if on else Color(1, 1, 1, 0.35), 2.0, true)
		var fs := 22 if r > 60 else (16 if r > 40 else 13)
		var label: String = b[2]
		if name == "ui_cancel" and not gameplay:
			# в окнах эта кнопка закрывает окно — рисуем крестик
			var k := r * 0.38
			var cc := Color(1, 1, 1, 0.85)
			root.draw_line(c + Vector2(-k, -k), c + Vector2(k, k), cc, 3.0, true)
			root.draw_line(c + Vector2(-k, k), c + Vector2(k, -k), cc, 3.0, true)
			continue
		if name == "fists" and player and player.fists:
			label = "ОПУСТИТЬ"
			fs = 12
		var w := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		root.draw_string(f, c + Vector2(-w / 2.0, fs * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.8))
	if not gameplay:
		return
	# джойстик: в покое — бледный в углу, при касании — под пальцем
	var base := stick_base if stick_on else _stick_home()
	var knob := base + (stick_pos - stick_base).limit_length(STICK_R) if stick_on else base
	root.draw_circle(base, STICK_R, Color(0, 0, 0, 0.25 if stick_on else 0.15))
	root.draw_arc(base, STICK_R, 0, TAU, 48, Color(1, 1, 1, 0.3 if stick_on else 0.18), 2.0, true)
	root.draw_circle(knob, 38.0, Color(1, 1, 1, 0.35 if stick_on else 0.18))
