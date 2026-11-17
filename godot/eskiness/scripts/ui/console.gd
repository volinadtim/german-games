extends CanvasLayer
## Внутриигровая консоль: F1 — открыть/закрыть, Enter — выполнить, ↑/↓ — история, Esc — закрыть.
## Пока открыта, ввод игрока не обрабатывается (player.active = false, инвентарь выключен).
## Создаётся из game.gd (setup) — у каждого игрока своя, команды действуют на локального игрока.
## Новая команда: register("имя", "описание", func(args: PackedStringArray) -> void).
## Читерская команда (money/get/noclip/god и т.п.): register_cheat(...) — работает только после /cheats on.

const Items := preload("res://scripts/items.gd")
const SUGG_ROWS := 8      # сколько строк подсказок /get видно сразу

var game   # core/game.gd
var open := false
var sugg_l: RichTextLabel   # подсказки предметов над полем (после «/get »)
var sugg: Array = []        # id подходящих предметов
var sugg_i := -1            # выделенный
var commands := {}        # имя -> {"desc": String, "fn": Callable, "cheat": bool}
var cheats_on := false   # /cheats on|off — разблокирует читерские команды
var history: PackedStringArray = []
var hist_i := 0

var root: Control
var log_l: RichTextLabel
var edit: LineEdit

var _prev_mouse := Input.MOUSE_MODE_CAPTURED


func _ready() -> void:
	layer = 90
	_build_ui()
	register("help", "список команд", _cmd_help)
	register("clear", "очистить лог", func(_a: PackedStringArray): log_l.clear())
	register("cheats", "/cheats on|off — включить/выключить читерские команды", _cmd_cheats)
	register_cheat("money", "/money [кол-во] — выдать монеты (по умолчанию 100)", _cmd_money)
	register_cheat("get", "/get [предмет] [кол-во] — выдать предмет (Tab — подсказки, места нет — под ноги)", _cmd_get)
	register_cheat("noclip", "/noclip — полёт сквозь стены вкл/выкл (WASD, Пробел — вверх, Ctrl — вниз, Shift — быстрее)", _cmd_noclip)
	register_cheat("god", "/god — неуязвимость (урон и отравление не берут) вкл/выкл", _cmd_god)
	print_line("[color=#9a9]Консоль. /help — список команд.[/color]")


func register(name_: String, desc: String, fn: Callable) -> void:
	commands[name_] = {"desc": desc, "fn": fn, "cheat": false}


## Читерская команда — доступна только после /cheats on (run() проверяет cheats_on).
func register_cheat(name_: String, desc: String, fn: Callable) -> void:
	commands[name_] = {"desc": desc, "fn": fn, "cheat": true}


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
	sugg_l = RichTextLabel.new()
	sugg_l.bbcode_enabled = true
	sugg_l.fit_content = true
	sugg_l.scroll_active = false
	sugg_l.visible = false
	sugg_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sugg_l.add_theme_font_size_override("normal_font_size", 16)
	box.add_child(sugg_l)
	edit = LineEdit.new()
	edit.text_changed.connect(func(_t: String): _update_sugg())
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
		KEY_TAB:
			get_viewport().set_input_as_handled()   # не уводить фокус с поля
			_sugg_tab(-1 if e.shift_pressed else 1)
		KEY_ENTER, KEY_KP_ENTER:
			# подсказка выделена, а в поле ещё не она — сначала подставить, второй Enter выполнит
			if sugg_l.visible and sugg_i >= 0 and _norm(edit.text) != _norm(_sugg_text(sugg_i)):
				get_viewport().set_input_as_handled()
				_apply_sugg()


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
	_prev_mouse = Input.mouse_mode
	game.player.set_lock("console", true)   # независимая блокировка: не перетирает кат-сцены (промпт 16.11 04:51)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hist_i = history.size()
	edit.clear()
	_update_sugg()
	edit.grab_focus.call_deferred()


func close() -> void:
	if not open:
		return
	open = false
	root.visible = false
	edit.release_focus()
	if game and game.player:
		game.player.set_lock("console", false)
	Input.mouse_mode = _prev_mouse


func _hist(d: int) -> void:
	if history.is_empty():
		return
	hist_i = clampi(hist_i + d, 0, history.size())
	edit.text = history[hist_i] if hist_i < history.size() else ""
	edit.caret_column = edit.text.length()
	_update_sugg()


func _submit(t: String) -> void:
	t = t.strip_edges()
	edit.clear()
	_update_sugg()
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
	if commands[cmd]["cheat"] and not cheats_on:
		print_line("[color=#e77]Читы выключены. /cheats on — включить.[/color]")
		return
	commands[cmd]["fn"].call(parts.slice(1))


func _cmd_help(_a: PackedStringArray) -> void:
	var names := commands.keys()
	names.sort()
	for n in names:
		var tag := " [color=#a77](чит)[/color]" if commands[n]["cheat"] else ""
		print_line("[color=#fd6]/%s[/color] — %s%s" % [n, commands[n]["desc"], tag])


func _cmd_cheats(a: PackedStringArray) -> void:
	if a.is_empty() or not (a[0].to_lower() in ["on", "off"]):
		print_line("[color=#e77]/cheats on|off[/color]")
		return
	cheats_on = a[0].to_lower() == "on"
	if not cheats_on and game and game.god:
		game.god = false   # выключаем читы — снимаем и godmode
	print_line("[color=#9e9]Читы: %s[/color]" % ("вкл" if cheats_on else "выкл"))


func _cmd_god(_a: PackedStringArray) -> void:
	if game == null:
		return
	game.god = not game.god
	print_line("[color=#9e9]Godmode: %s[/color]" % ("вкл" if game.god else "выкл"))


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


func _cmd_noclip(_a: PackedStringArray) -> void:
	if game == null or game.player == null:
		return
	var p = game.player
	p.noclip = not p.noclip
	p.velocity = Vector3.ZERO
	print_line("[color=#9e9]Noclip: %s[/color]" % ("вкл" if p.noclip else "выкл"))


# ---------- /get ----------

## Нормализация для сравнения: регистр, ё→е, лишние пробелы.
func _norm(s: String) -> String:
	return " ".join(s.to_lower().replace("ё", "е").split(" ", false))


## id по игровому названию или внутреннему id ("" — не нашли).
func _find_item(q: String) -> String:
	q = _norm(q)
	if q == "":
		return ""
	if Items.ITEMS.has(q):
		return q
	for id in Items.ITEMS:
		if _norm(Items.ITEMS[id]["name"]) == q:
			return id
	return ""


## Разбор аргументов: [id, кол-во]; последнее слово-число — количество.
func _parse_get(a: PackedStringArray) -> Array:
	var n := 1
	var words := Array(a)
	if words.size() > 1 and String(words[-1]).is_valid_int():
		n = String(words.pop_back()).to_int()
	return [_find_item(" ".join(words)), n]


func _cmd_get(a: PackedStringArray) -> void:
	if a.is_empty():
		print_line("[color=#e77]/get [предмет] [кол-во] — например: /get аптечка 3[/color]")
		return
	var r := _parse_get(a)
	var id: String = r[0]
	var n: int = clampi(r[1], 1, 9999)
	if id == "":
		print_line("[color=#e77]Нет предмета «%s». Наберите /get и смотрите подсказки.[/color]" % " ".join(a))
		return
	if game == null or game.inv == null or game.player == null:
		return
	var left: int = game.inv.add(id, n)
	if left > 0 and game.has_method("_make_pickup"):   # не влезло — бросить под ноги
		var fwd: Vector3 = -game.player.global_transform.basis.z
		var pos: Vector3 = game.player.global_position + Vector3(0, 1.0, 0) + fwd * 0.4
		var p = game._make_pickup(id, left, pos, fwd * 1.0 + Vector3(0, 0.5, 0))
		if p:
			p.need_leave = true
	if game.has_method("save_now"):
		game.save_now()
	var nm := Items.item_name(id)
	if left > 0:
		print_line("[color=#9e9]+%d %s[/color] [color=#db8](%d не влезло — под ногами)[/color]" % [n - left, nm, left])
	else:
		print_line("[color=#9e9]+%d %s[/color]" % [n, nm])


## Текст поля для подсказки i.
func _sugg_text(i: int) -> String:
	return "/get " + String(Items.ITEMS[sugg[i]]["name"]) + " "


## Пересчитать подсказки по набранному тексту (вызывается при вводе пользователем).
func _update_sugg() -> void:
	sugg.clear()
	sugg_i = -1
	var t := edit.text
	if not t.to_lower().begins_with("/get "):
		sugg_l.visible = false
		return
	var rest := t.substr(5)
	var words := rest.split(" ", false)
	# название уже введено полностью (дальше пробел или количество) — подсказки не нужны
	if _find_item(rest) != "" and rest.ends_with(" "):
		sugg_l.visible = false
		return
	if words.size() > 1 and words[-1].is_valid_int() and _parse_get(words)[0] != "":
		sugg_l.visible = false
		return
	var q := _norm(rest)
	var first: Array = []
	var other: Array = []
	for id in Items.ITEMS:
		var nm := _norm(Items.ITEMS[id]["name"])
		if q == "" or nm.begins_with(q) or String(id).begins_with(q):
			first.append(id)
		elif nm.contains(q) or String(id).contains(q):
			other.append(id)
	var by_name := func(x, y): return _norm(Items.ITEMS[x]["name"]) < _norm(Items.ITEMS[y]["name"])
	first.sort_custom(by_name)
	other.sort_custom(by_name)
	sugg = first + other
	if not sugg.is_empty():
		sugg_i = 0
	_draw_sugg()


func _draw_sugg() -> void:
	sugg_l.clear()
	if sugg.is_empty():
		sugg_l.append_text("[color=#a77]  нет такого предмета[/color]")
		sugg_l.visible = true
		return
	@warning_ignore("integer_division")
	var from := clampi(sugg_i - SUGG_ROWS / 2, 0, maxi(0, sugg.size() - SUGG_ROWS))
	var to := mini(from + SUGG_ROWS, sugg.size())
	var lines: PackedStringArray = []
	if from > 0:
		lines.append("[color=#777]  … ещё %d выше[/color]" % from)
	for i in range(from, to):
		var nm := String(Items.ITEMS[sugg[i]]["name"])
		if i == sugg_i:
			lines.append("[bgcolor=#3a3520][color=#fd6]▶ %s[/color] [color=#998]%s[/color][/bgcolor]" % [nm, sugg[i]])
		else:
			lines.append("[color=#ccc]  %s[/color] [color=#777]%s[/color]" % [nm, sugg[i]])
	if to < sugg.size():
		lines.append("[color=#777]  … ещё %d ниже (Tab / Shift+Tab)[/color]" % (sugg.size() - to))
	sugg_l.append_text("\n".join(lines))
	sugg_l.visible = true


## Tab: первый раз подставляет выделенный, дальше листает (Shift — назад) и сразу подставляет.
func _sugg_tab(d: int) -> void:
	if not sugg_l.visible or sugg.is_empty():
		return
	if _norm(edit.text) == _norm(_sugg_text(sugg_i)):
		sugg_i = wrapi(sugg_i + d, 0, sugg.size())
	edit.text = _sugg_text(sugg_i)
	edit.caret_column = edit.text.length()
	_draw_sugg()


## Enter: подставить выделенный и спрятать список (следующий Enter выполнит команду).
func _apply_sugg() -> void:
	edit.text = _sugg_text(sugg_i)
	edit.caret_column = edit.text.length()
	sugg.clear()
	sugg_i = -1
	sugg_l.visible = false
