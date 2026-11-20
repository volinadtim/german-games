extends CanvasLayer
## Круговое меню хотбара на геймпаде (промпт 20.11 14:51). Создаёт ui/gamepad.gd (pad.wheel).
## Держать ← крестовины — по центру экрана 5 слотов хотбара по кругу (1 — сверху, дальше по часовой).
## Правый стик выбирает слот (обзор в это время стоит; левый стик — ходьба).
## Отпустить ← — выбранное в левую руку; LT — в левую, RT — в правую (сразу, меню закрывается).
## Ничего не выбрано — просто закрыть.

const Items := preload("res://scripts/items.gd")
const R := 150.0            # радиус круга слотов
const CELL := 70.0

var pad                     # ui/gamepad.gd
var is_open := false
var key := ""               # кнопка, которой открыли ("b:13")
var dev := 0
var sel := -1
var _ui: Control
var inv_src = null          # Split-Screen (network/split.gd): круг игрока 2 — его инвентарь
var on_pick := Callable()   # ...и выбор слота (номер, в правую руку) — его хотбар вместо нажатий hot_N
var assign := false         # открыт из инвентаря (держат ←): отпустить — предмет под рамкой в слот (gamepad.gd: _dl_button)


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_ui = Control.new()
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.draw.connect(_draw_wheel)
	add_child(_ui)


func open(k: String, d: int) -> void:
	is_open = true
	key = k
	dev = d
	sel = -1
	visible = true
	_ui.queue_redraw()


func close() -> void:
	is_open = false
	visible = false
	key = ""
	if assign:
		assign = false
		inv_src = null


## Отпустили ← — выбранный слот в левую руку.
func release() -> void:
	if sel >= 0:
		_choose(false)
	close()


## Курок при открытом меню: right — в правую руку (RT), иначе в левую (LT).
func pick(right: bool) -> void:
	if sel >= 0:
		_choose(right)
	close()


func _choose(right: bool) -> void:
	if on_pick.is_valid():
		on_pick.call(sel, right)
		return
	if right:
		pad._tap("hand_right", dev)
	pad._tap("hot_%d" % (sel + 1), dev)


## Правый стик: направление выбирает слот (центр — выбор остаётся).
func aim(v: Vector2) -> void:
	if v.length() < 0.45:
		return
	var a := fposmod(atan2(v.x, -v.y) + TAU / 10.0, TAU)   # 0 — вверх, по часовой
	var s := int(a / (TAU / 5.0)) % 5
	if s != sel:
		sel = s
		_ui.queue_redraw()


func _process(_d: float) -> void:
	if is_open:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not assign:
			close()   # открылось окно/меню
		else:
			_ui.queue_redraw()


func _inv():
	if inv_src != null:
		return inv_src
	for c in get_tree().root.get_children():
		for n in c.get_children():
			if n.has_method("save_now") and n.get("inv") != null:
				return n.inv
	return null


func _draw_wheel() -> void:
	if not is_open:
		return
	var inv = _inv()
	var f := ThemeDB.fallback_font
	var c := _ui.get_viewport_rect().size * 0.5
	_ui.draw_circle(c, R + CELL * 0.75, Color(0, 0, 0, 0.35))
	for k in 5:
		var ang := k * TAU / 5.0
		var p := c + Vector2(sin(ang), -cos(ang)) * R
		var r := Rect2(p - Vector2(CELL, CELL) * 0.5, Vector2(CELL, CELL))
		var on := k == sel
		_ui.draw_rect(r, Color(0.16, 0.13, 0.06, 0.85) if on else Color(0, 0, 0, 0.6))
		_ui.draw_rect(r, Color(1.0, 0.82, 0.3) if on else Color(1, 1, 1, 0.2), false, 3.0 if on else 1.0)
		var id: String = str(inv.hotbar[k]) if inv != null and k < inv.hotbar.size() else ""
		if id != "":
			Items.draw_icon(_ui, id, r.grow(-12))
			var cnt: int = inv.count(id)
			if cnt == 0:
				_ui.draw_rect(r.grow(-1), Color(0, 0, 0, 0.6))
			elif cnt > 1:
				_ui.draw_string_outline(f, r.position + Vector2(0, CELL - 6), str(cnt), HORIZONTAL_ALIGNMENT_RIGHT, CELL - 6, 16, 4, Color(0, 0, 0, 0.8))
				_ui.draw_string(f, r.position + Vector2(0, CELL - 6), str(cnt), HORIZONTAL_ALIGNMENT_RIGHT, CELL - 6, 16, Color(0.92, 0.9, 0.84))
		_ui.draw_string_outline(f, r.position + Vector2(6, 18), str(k + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color(0, 0, 0, 0.8))
		_ui.draw_string(f, r.position + Vector2(6, 18), str(k + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.8, 0.45))
	var t := "правый стик — выбрать · отпустить ← или %s — в левую · %s — в правую" % [pad.spec_name("t:L"), pad.spec_name("t:R")]
	if assign:
		t = "стик — выбрать слот · отпустить ← — положить предмет в слот"
	if sel >= 0 and inv != null and str(inv.hotbar[sel]) != "":
		t = Items.item_name(str(inv.hotbar[sel])) + "\n" + t
	var lines := t.split("\n")
	var y := c.y + R + CELL * 0.75 + 26.0
	for ln in lines:
		_ui.draw_string_outline(f, Vector2(c.x - 400, y), ln, HORIZONTAL_ALIGNMENT_CENTER, 800, 18, 5, Color(0, 0, 0, 0.85))
		_ui.draw_string(f, Vector2(c.x - 400, y), ln, HORIZONTAL_ALIGNMENT_CENTER, 800, 18, Color(0.92, 0.9, 0.84))
		y += 24.0
