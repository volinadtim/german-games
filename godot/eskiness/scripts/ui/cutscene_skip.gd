extends CanvasLayer
## Пропуск кат-сцен (промпт 18.11 00:49): пока идёт кат-сцена — внизу справа «Пропустить — держи Пробел»,
## удержание 0.8 с пропускает её. Кат-сцены — узлы в группе "cutscene" с методами
## can_skip() -> bool, skip_cut(), skip_shared() -> bool.
## Сеть: свои кат-сцены (пробуждение, монстрик, автомат, магазин) каждый пропускает сам — у каждого своя камера.
## Общая (отъезд на машине и надпись «заглохла»: все сидят в одной машине) пропускается, когда удержали все
## игроки — на подсказке счётчик «1/3». Голоса рассылаются rpc (узел game/CutSkip — одинаковый путь у всех).

const HOLD := 0.8

var game
var box: PanelContainer
var label: Label
var bar: ColorRect
var hold_t := 0.0
var armed := false            # клавишу отпустили после начала кат-сцены (иначе прыжок «до» сразу пропустил бы)
var cur: Node = null
var votes := {}               # общая кат-сцена: id игрока → удержал
var voted := false
var idle_t := 0.0


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
	box.offset_left = -330
	box.offset_right = -20
	box.offset_top = -64
	box.offset_bottom = -20
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.visible = false
	add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	box.add_child(vb)
	label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.9, 0.88, 0.8, 0.9))
	vb.add_child(label)
	var track := ColorRect.new()
	track.color = Color(1, 1, 1, 0.15)
	track.custom_minimum_size = Vector2(0, 3)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(track)
	bar = ColorRect.new()
	bar.color = Color(0.95, 0.65, 0.3, 0.95)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.anchor_bottom = 1.0
	track.add_child(bar)


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
	var txt := "Пропустить — держи Пробел"
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
	bar.anchor_right = clampf(hold_t / HOLD, 0.0, 1.0)


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
