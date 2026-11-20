extends CanvasLayer
## Пропуск кат-сцен (промпт 18.11 00:49): пока идёт кат-сцена — внизу справа «Пропустить — держи Пробел»,
## удержание 0.8 с пропускает её. Кат-сцены — узлы в группе "cutscene" с методами
## can_skip() -> bool, skip_cut(), skip_shared() -> bool.
## Сеть: свои кат-сцены (пробуждение, монстрик, автомат, магазин) каждый пропускает сам — у каждого своя камера.
## Общая (отъезд на машине и надпись «заглохла»: все сидят в одной машине) пропускается, когда удержали все
## игроки — на подсказке счётчик «1/3». Голоса рассылаются rpc (узел game/CutSkip — одинаковый путь у всех).
## Split-Screen (network/split.gd, промпт 20.11 14:59): кат-сцену видят оба — любая пропускается, когда
## удержали оба (игрок 2 — прыжок на своём геймпаде), счётчик «1/2».

const HOLD := 0.8

var game
var box: PanelContainer
var label: Label
var ring: CutSkipRing
var hold_t := 0.0
var armed := false            # клавишу отпустили после начала кат-сцены (иначе прыжок «до» сразу пропустил бы)
var cur: Node = null
var votes := {}               # общая кат-сцена: id игрока → удержал
var voted := false
var idle_t := 0.0
var hold2 := 0.0              # Split-Screen: удержание игрока 2
var armed2 := false
var voted2 := false


func _ready() -> void:
	name = "CutSkip"
	layer = 45
	box = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.45)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 8
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	box.add_theme_stylebox_override("panel", sb)
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = -310
	box.offset_right = -20
	box.offset_top = -64
	box.offset_bottom = -20
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN   # длинная надпись («(0/2)» в Split-Screen) растёт влево, а не за край
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.visible = false
	add_child(box)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(hb)
	label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.9, 0.88, 0.8, 0.9))
	hb.add_child(label)
	ring = CutSkipRing.new()
	ring.custom_minimum_size = Vector2(22, 22)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(ring)


func _target() -> Node:
	for n in get_tree().get_nodes_in_group("cutscene"):
		if is_instance_valid(n) and n.is_inside_tree() and n.can_skip():
			return n
	return null


func _process(delta: float) -> void:
	var t := _target()
	if t != cur:
		cur = t
		hold_t = 0.0
		armed = false
		voted = false
		hold2 = 0.0
		armed2 = false
		voted2 = false
	var shared: bool = t != null and t.skip_shared() and _net() != null
	if not shared:
		idle_t += delta
		if idle_t > 3.0:
			votes.clear()   # голоса — только за текущую общую кат-сцену
	else:
		idle_t = 0.0
	box.visible = t != null
	if t == null:
		return
	var console_open: bool = game != null and game.player != null and game.player.input_locks.has("console")
	var down := Input.is_action_pressed("jump") and not console_open
	if not down:
		armed = true
	var sp = game.get_meta("split") if game and game.has_meta("split") else null
	var st2: int = sp.skip_state() if sp else -1
	if st2 >= 0:
		_split_vote(t, delta, down, st2 == 1)
		return
	if armed and down and not voted:
		hold_t += delta
	elif not voted:
		hold_t = maxf(hold_t - delta * 2.0, 0.0)
	if hold_t >= HOLD and not voted:
		if shared:
			voted = true
			rpc("cs_vote")
			cs_vote()
		else:
			hold_t = 0.0
			t.skip_cut()
			return
	var txt: String = preload("res://scripts/ui/key_hint.gd").fmt("Пропустить — держи Пробел", "Пропустить — держи {jump}")
	if shared:
		var n := _need()
		txt += "  (%d/%d)" % [mini(votes.size(), n), n]
		if votes.size() >= n:
			votes.clear()
			voted = false
			hold_t = 0.0
			t.skip_cut()
			return
	label.text = txt
	ring.progress = clampf(hold_t / HOLD, 0.0, 1.0)


## Split-Screen: каждый держит свою кнопку, пропуск — когда оба удержали HOLD.
func _split_vote(t: Node, delta: float, down: bool, down2: bool) -> void:
	if armed and down and not voted:
		hold_t += delta
	elif not voted:
		hold_t = maxf(hold_t - delta * 2.0, 0.0)
	if not down2:
		armed2 = true
	if armed2 and down2 and not voted2:
		hold2 += delta
	elif not voted2:
		hold2 = maxf(hold2 - delta * 2.0, 0.0)
	if hold_t >= HOLD:
		voted = true
	if hold2 >= HOLD:
		voted2 = true
	if voted and voted2:
		hold_t = 0.0
		hold2 = 0.0
		voted = false
		voted2 = false
		t.skip_cut()
		return
	label.text = preload("res://scripts/ui/key_hint.gd").fmt("Пропустить — держи Пробел", "Пропустить — держи {jump}") + "  (%d/2)" % (int(voted) + int(voted2))
	ring.progress = (clampf(hold_t / HOLD, 0.0, 1.0) + clampf(hold2 / HOLD, 0.0, 1.0)) * 0.5


func _net():
	return game.net if game and game.get("net") else null


func _need() -> int:
	var n = _net()
	return maxi(n.players.size(), 1) if n else 1


@rpc("any_peer", "reliable")
func cs_vote() -> void:
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = multiplayer.get_unique_id()
	votes[id] = true
	idle_t = 0.0


## Загрузочный кружочек: тонкое кольцо-подложка + дуга прогресса, растущая по часовой.
class CutSkipRing extends Control:
	var progress := 0.0

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var r := size.x * 0.5 - 2.0
		var c := size * 0.5
		draw_arc(c, r, 0.0, TAU, 28, Color(1, 1, 1, 0.15), 3.0, true)
		if progress > 0.0:
			var start := -PI * 0.5
			draw_arc(c, r, start, start + TAU * progress, 28, Color(0.95, 0.65, 0.3, 0.95), 3.0, true)
