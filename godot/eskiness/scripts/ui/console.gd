extends CanvasLayer
## Внутриигровая консоль: F1 — открыть/закрыть, Enter — выполнить, ↑/↓ — история, Esc — закрыть.
## Пока открыта, ввод игрока не обрабатывается (player.active = false, инвентарь выключен).
## Создаётся из game.gd (setup) — у каждого игрока своя, команды действуют на локального игрока.
## Новая команда: register("имя", "описание", func(args: PackedStringArray) -> void).

var game   # core/game.gd
var open := false
var commands := {}        # имя -> {"desc": String, "fn": Callable}
var history: PackedStringArray = []
var hist_i := 0

var root: Control
var log_l: RichTextLabel
var edit: LineEdit

var _prev_active := true
var _prev_inv := true
var _prev_mouse := Input.MOUSE_MODE_CAPTURED


func _ready() -> void:
	layer = 90
	_build_ui()
	register("help", "список команд", _cmd_help)
	register("money", "/money [кол-во] — выдать монеты (по умолчанию 100)", _cmd_money)
	register("clear", "очистить лог", func(_a: PackedStringArray): log_l.clear())
	print_line("[color=#9a9]Консоль. /help — список команд.[/color]")


func register(name_: String, desc: String, fn: Callable) -> void:
	commands[name_] = {"desc": desc, "fn": fn}


func print_line(t: String) -> void:
	log_l.append_text(t + "\n")


func _build_ui() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP   # клики не уходят в игру
	root.visible = false
	add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.04, 0.85)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 0.42
	root.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 12
	box.offset_top = 10
	box.offset_right = -12
	box.offset_bottom = -10
	bg.add_child(box)
	log_l = RichTextLabel.new()
	log_l.bbcode_enabled = true
	log_l.scroll_following = true
	log_l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_l.add_theme_font_size_override("normal_font_size", 16)
	log_l.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(log_l)
	edit = LineEdit.new()
	edit.placeholder_text = "/help"
	edit.add_theme_font_size_override("font_size", 18)
	edit.keep_editing_on_text_submit = true
	edit.text_submitted.connect(_submit)
	box.add_child(edit)


func _input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed):
		return
	if e.keycode == KEY_F1 and not e.echo:
		get_viewport().set_input_as_handled()
		toggle()
		return
	if not open:
		return
	match e.keycode:
		KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			close()
		KEY_UP:
			get_viewport().set_input_as_handled()
			_hist(-1)
		KEY_DOWN:
			get_viewport().set_input_as_handled()
			_hist(1)


func toggle() -> void:
	if open:
		close()
	else:
		show_console()


func show_console() -> void:
	if open or game == null or game.player == null:
		return
	open = true
	root.visible = true
	_prev_active = game.player.active
	_prev_mouse = Input.mouse_mode
	game.player.active = false
	if game.inv:
		_prev_inv = game.inv.enabled
		game.inv.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hist_i = history.size()
	edit.clear()
	edit.grab_focus.call_deferred()


func close() -> void:
	if not open:
		return
	open = false
	root.visible = false
	edit.release_focus()
	if game and game.player:
		# если за время консоли открылось другое окно — оно само вернёт управление
		game.player.active = _prev_active and game.alive
	if game and game.inv:
		game.inv.enabled = _prev_inv
	Input.mouse_mode = _prev_mouse


func _hist(d: int) -> void:
	if history.is_empty():
		return
	hist_i = clampi(hist_i + d, 0, history.size())
	edit.text = history[hist_i] if hist_i < history.size() else ""
	edit.caret_column = edit.text.length()


func _submit(t: String) -> void:
	t = t.strip_edges()
	edit.clear()
	if t == "":
		return
	if history.is_empty() or history[history.size() - 1] != t:
		history.append(t)
	hist_i = history.size()
	print_line("[color=#ccc]> %s[/color]" % t)
	run(t)


func run(t: String) -> void:
	var parts := t.trim_prefix("/").split(" ", false)
	if parts.is_empty():
		return
	var cmd := parts[0].to_lower()
	if not commands.has(cmd):
		print_line("[color=#e77]Нет команды «%s». /help — список.[/color]" % cmd)
		return
	commands[cmd]["fn"].call(parts.slice(1))


func _cmd_help(_a: PackedStringArray) -> void:
	var names := commands.keys()
	names.sort()
	for n in names:
		print_line("[color=#fd6]/%s[/color] — %s" % [n, commands[n]["desc"]])


func _cmd_money(a: PackedStringArray) -> void:
	var n := 100
	if a.size() > 0:
		if not a[0].is_valid_int():
			print_line("[color=#e77]Нужно число: /money 500[/color]")
			return
		n = a[0].to_int()
	if game == null or game.inv == null:
		return
	if n < 0:
		n = -mini(-n, game.inv.coins)   # отнять можно не больше, чем есть
	game.inv.coins += n
	game.inv._after_change()   # кошелёк в инвентаре + HUD (inv.changed)
	if game.has_method("save_now"):
		game.save_now()
	print_line("[color=#9e9]Монеты %+d → %d[/color]" % [n, game.inv.coins])
