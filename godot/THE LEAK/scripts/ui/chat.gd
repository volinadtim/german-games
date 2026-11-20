extends CanvasLayer
## Чат (промпт 16.11 02:13): действие «chat» (T, переназначается в «Управлении» → «Интерфейс»).
## Поле ввода внизу слева, Enter — отправить, Esc — закрыть. Сообщения видят все игроки в сети (с ником,
## net_world.gd: chat_msg), в одиночной — только свои. Лог над полем: строки затухают через FADE_T,
## пока чат открыт — видны все последние. Пока открыт, ввод игрока не обрабатывается (как консоль F1).

const FADE_T := 8.0
const MAX_LINES := 8

var game   # core/game.gd
var open := false
var box: VBoxContainer
var edit: LineEdit
var lines: Array = []   # [Label, время появления]
var _prev_mouse := Input.MOUSE_MODE_CAPTURED


func _ready() -> void:
	layer = 80
	# Лента в обрезающей рамке над полем ввода; растёт вверх, лишнее срезается сверху —
	# на строку ввода не налезает (промпт 16.11 22:11).
	var clip := Control.new()
	clip.anchor_top = 1.0
	clip.anchor_bottom = 1.0
	clip.offset_left = 16
	clip.offset_right = 560
	clip.offset_top = -380
	clip.offset_bottom = -172
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(clip)
	box = VBoxContainer.new()
	box.anchor_left = 0.0
	box.anchor_right = 1.0
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.alignment = BoxContainer.ALIGNMENT_END
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(box)
	edit = LineEdit.new()
	edit.anchor_top = 1.0
	edit.anchor_bottom = 1.0
	edit.offset_left = 16
	edit.offset_right = 16 + 462   # на 15% уже/ниже прежнего (544×32)
	edit.offset_top = -164
	edit.offset_bottom = -137
	edit.placeholder_text = "Пишите."
	edit.max_length = 200
	edit.add_theme_font_size_override("font_size", 15)
	edit.modulate.a = 0.9
	# Без рамки: только полупрозрачный фон, фокус без обводки.
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.35)
	sb.set_border_width_all(0)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	for st in ["normal", "focus", "read_only"]:
		edit.add_theme_stylebox_override(st, sb)
	edit.visible = false
	edit.text_submitted.connect(_submit)
	add_child(edit)


func _process(_d: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for e in lines:
		var l: Label = e[0]
		var age: float = now - float(e[1])
		l.modulate.a = 1.0 if open else clampf((FADE_T - age) / 1.5, 0.0, 1.0)


func _input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	if open:
		if Controls.event(e, "ui_cancel"):
			get_viewport().set_input_as_handled()
			close()
		return
	if InputMap.has_action("chat") and Controls.event(e, "chat") and _can_open():
		get_viewport().set_input_as_handled()
		show_chat()


func _can_open() -> bool:
	if game == null or game.player == null or not game.player.active:
		return false
	if game.has_method("window_open") and game.window_open():
		return false
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func show_chat() -> void:
	open = true
	Controls.mode_on("console", self)   # поле ввода чата глушит игровые кнопки, как консоль
	_prev_mouse = Input.mouse_mode
	game.player.set_lock("chat", true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	edit.visible = true
	edit.clear()
	edit.set_deferred("text", "")   # без «t» от клавиши открытия
	edit.grab_focus.call_deferred()


func close() -> void:
	if not open:
		return
	open = false
	Controls.mode_off("console", self)
	edit.release_focus()
	edit.visible = false
	if game and game.player:
		game.player.set_lock("chat", false)
	Input.mouse_mode = _prev_mouse


func _submit(t: String) -> void:
	t = t.strip_edges()
	if t != "":
		var nick := "Я"
		if game and game.net:
			nick = String(game.net.my_name)
			game.net.chat_send(t)
		add_msg(nick, t)
	close()


## Строка в лог: «ник: текст».
func add_msg(nick: String, text: String) -> void:
	var l := Label.new()
	l.text = "%s: %s" % [nick, text]
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", Color(0.95, 0.92, 0.82))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(l)
	lines.append([l, Time.get_ticks_msec() / 1000.0])
	while lines.size() > MAX_LINES:
		(lines.pop_front()[0] as Label).queue_free()
