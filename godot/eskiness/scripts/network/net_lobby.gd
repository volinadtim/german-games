extends VBoxContainer
## Страница меню «Сетевая игра» (промпт 14.11 19:37): имя игрока, «Создать комнату» / «Присоединиться» / «Назад».
## Комната: код для локальной сети, код для интернета (по введённому внешнему IP), игроки, «Начать».
## Присоединиться: поле «код или IP:порт» и список комнат, найденных в локальной сети.
## Оформление — функциями menu.gd (_button, _title…), тема с обводкой наследуется от корня меню.

const NetScript := preload("res://scripts/network/net.gd")

var menu          # menu.gd
var net           # net.gd (/root/Net)
var page := "home"
var body: VBoxContainer
var status_l: Label
var players_box: VBoxContainer
var rooms_box: VBoxContainer
var wan_code_l: Label
var addr_edit: LineEdit
var port_edit: LineEdit


func _init(m) -> void:
	menu = m
	add_theme_constant_override("separation", 10)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	custom_minimum_size = Vector2(700, 0)


## Открыть страницу (из главного меню).
func open() -> void:
	if net == null:
		net = NetScript.ensure(get_tree())
		net.lobby_changed.connect(_on_lobby)
		net.rooms_changed.connect(_on_rooms)
		net.status.connect(_on_status)
	if net.hosting:
		_build("host")
	elif net.connected or net.joining:
		_build("join")
	else:
		_build("home")
	if net.last_msg != "":
		_on_status(net.last_msg, true)
		net.last_msg = ""


## Esc / «Назад».
func back() -> void:
	match page:
		"home":
			menu._show("main")
		_:
			net.leave()
			net.stop_discovery()
			_build("home")


func _clear() -> void:
	for c in get_children():
		c.queue_free()
	status_l = null
	players_box = null
	rooms_box = null
	wan_code_l = null


func _build(p: String) -> void:
	page = p
	_clear()
	match p:
		"home":
			_home()
		"host":
			_host()
		"join":
			_join()


# ---------- страницы ----------

func _home() -> void:
	add_child(_title_c("СЕТЕВАЯ ИГРА"))
	var row := _row()
	row.add_child(_label("Ваше имя:", 24, Color(0.82, 0.81, 0.77), 170))
	var ne := _edit(net.my_name, "имя", 300)
	ne.max_length = 20
	ne.text_changed.connect(func(t: String): net.set_player_name(t))
	row.add_child(ne)
	add_child(row)
	add_child(menu._gap(8))
	add_child(_centered(menu._button("Создать комнату", func(): _build("host"))))
	add_child(_centered(menu._button("Присоединиться", func():
		_build("join")
		if not net.start_discovery():
			_on_status("Поиск комнат в сети недоступен (порт %d занят другой копией игры) — введите код" % NetScript.DISCOVERY_PORT, true))))
	add_child(_centered(menu._button("Назад", back)))
	status_l = _label("", 18, Color(0.85, 0.45, 0.35), 0)
	status_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status_l)


func _host() -> void:
	add_child(_title_c("КОМНАТА"))
	if not net.hosting:
		var row := _row()
		row.add_child(_label("Порт:", 24, Color(0.82, 0.81, 0.77), 120))
		port_edit = _edit(str(NetScript.PORT), "порт", 140)
		row.add_child(port_edit)
		var ob: Button = menu._button("Открыть", func():
			var pt := int(port_edit.text) if port_edit.text.is_valid_int() else NetScript.PORT
			if net.host(clampi(pt, 1024, 65535)) == OK:
				_build("host"))
		ob.custom_minimum_size = Vector2(220, 52)
		row.add_child(ob)
		add_child(row)
		add_child(_hint("Порт по умолчанию %d. Меняйте, только если он занят." % NetScript.PORT))
	else:
		var ips: Array = NetScript.lan_ips()
		add_child(_label("Код для локальной сети:", 20, Color(0.75, 0.7, 0.62), 0))
		var lan := _label(NetScript.encode(ips[0], net.port) if not ips.is_empty() else "нет локальной сети", 44, Color(0.95, 0.88, 0.7), 0)
		lan.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(lan)
		var extra := "IP %s, порт %d" % [ips[0], net.port] if not ips.is_empty() else "на этом ПК: 127.0.0.1:%d" % net.port
		if ips.size() > 1:
			var others := PackedStringArray()
			for k in range(1, ips.size()):
				others.append("%s (%s)" % [ips[k], NetScript.encode(ips[k], net.port)])
			extra += "   ·   другие сети: " + ", ".join(others)
		add_child(_hint(extra))
		# интернет: внешний IP узнаём не сами (ничего не шлём наружу) — его вводит хост
		var row := _row()
		row.add_child(_label("Внешний IP:", 20, Color(0.82, 0.81, 0.77), 150))
		var we := _edit("", "например 95.12.34.56", 260)
		row.add_child(we)
		wan_code_l = _label("", 30, Color(0.95, 0.88, 0.7), 210)
		row.add_child(wan_code_l)
		we.text_changed.connect(func(t: String):
			var a: Array = NetScript.parse_address(t.strip_edges())
			wan_code_l.text = NetScript.encode(a[0], net.port) if not a.is_empty() and t.count(".") == 3 else "")
		add_child(row)
		add_child(_hint("Через интернет: нужен белый (статический) IP и проброс порта %d (UDP) на роутере на этот ПК. Введите свой внешний IP — получите код." % net.port))
		add_child(_label("Игроки:", 22, Color(0.75, 0.7, 0.62), 0))
		players_box = VBoxContainer.new()
		add_child(players_box)
		_fill_players()
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 16)
	if net.hosting:
		var sb: Button = menu._button("Начать", _start)
		sb.custom_minimum_size = Vector2(240, 54)
		btns.add_child(sb)
	var bb: Button = menu._button("Закрыть" if net.hosting else "Назад", back)
	bb.custom_minimum_size = Vector2(240, 54)
	btns.add_child(bb)
	add_child(btns)
	status_l = _label("", 18, Color(0.85, 0.45, 0.35), 0)
	status_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status_l)


func _join() -> void:
	add_child(_title_c("ПРИСОЕДИНИТЬСЯ"))
	if not (net.connected or net.joining):
		var row := _row()
		addr_edit = _edit("", "код комнаты или IP:порт", 380)
		addr_edit.text_submitted.connect(func(_t): _connect_typed())
		row.add_child(addr_edit)
		var cb: Button = menu._button("Подключиться", _connect_typed)
		cb.custom_minimum_size = Vector2(260, 52)
		row.add_child(cb)
		add_child(row)
		add_child(_label("Найденные комнаты в локальной сети:", 20, Color(0.75, 0.7, 0.62), 0))
		rooms_box = VBoxContainer.new()
		rooms_box.add_theme_constant_override("separation", 6)
		add_child(rooms_box)
		_fill_rooms()
	else:
		add_child(_label("Игроки в комнате:", 22, Color(0.75, 0.7, 0.62), 0))
		players_box = VBoxContainer.new()
		add_child(players_box)
		_fill_players()
	status_l = _label("", 20, Color(0.8, 0.77, 0.7), 0)
	status_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status_l)
	if net.connected:
		status_l.text = "Подключено. Ждём, пока хост начнёт игру…"
	var bb: Button = menu._button("Отключиться" if (net.connected or net.joining) else "Назад", back)
	add_child(_centered(bb))


func _connect_typed() -> void:
	var a: Array = NetScript.parse_address(addr_edit.text)
	if a.is_empty():
		_on_status("Не понял адрес: введите код вида ABCDE-FGHJK или IP:порт (например 192.168.1.5:%d)" % NetScript.PORT, true)
		return
	connect_to(a[0], a[1])


func connect_to(ip: String, p: int) -> void:
	if net.join(ip, p) == OK:
		_build("join")
		status_l.text = "Подключаемся к %s:%d…" % [ip, p]


func _start() -> void:
	net.start_game()


# ---------- обновления ----------

func _on_lobby() -> void:
	if not is_visible_in_tree():
		return
	# сменилось состояние подключения — перестраиваем страницу
	if page == "join" and (net.connected or net.joining) == (rooms_box != null):
		var keep := status_l.text if status_l else ""
		_build("join")
		if keep != "" and status_l and status_l.text == "":
			status_l.text = keep
		return
	_fill_players()


func _on_rooms() -> void:
	_fill_rooms()


func _on_status(text: String, bad: bool) -> void:
	if status_l and is_instance_valid(status_l):
		status_l.text = text
		status_l.add_theme_color_override("font_color", Color(0.9, 0.45, 0.35) if bad else Color(0.75, 0.85, 0.65))


func _fill_players() -> void:
	if players_box == null or not is_instance_valid(players_box):
		return
	for c in players_box.get_children():
		c.queue_free()
	var ids: Array = net.players.keys()
	ids.sort()
	for id in ids:
		var t: String = "• %s%s" % [net.players[id], "  (хост)" if id == 1 else ""]
		if id == net.multiplayer.get_unique_id():
			t += "  — вы"
		players_box.add_child(_label(t, 22, Color(0.9, 0.86, 0.76), 0))
	if ids.size() <= 1 and net.hosting:
		players_box.add_child(_hint("Пока никого — сообщите код друзьям"))


func _fill_rooms() -> void:
	if rooms_box == null or not is_instance_valid(rooms_box):
		return
	for c in rooms_box.get_children():
		c.queue_free()
	if net.rooms.is_empty():
		rooms_box.add_child(_hint("ищем… (комната появится, если её открыли в этой же сети)"))
		return
	for k in net.rooms:
		var r: Dictionary = net.rooms[k]
		var b: Button = menu._button("%s — %d игр.%s" % [r["name"], r["n"], "" if r["open"] else " (идёт игра)"], connect_to.bind(String(r["ip"]), int(r["port"])))
		b.text = "%s — %d игр.%s" % [r["name"], r["n"], "" if r["open"] else " (идёт игра)"]   # без капса
		b.custom_minimum_size = Vector2(560, 48)
		b.add_theme_font_size_override("font_size", 22)
		b.tooltip_text = "%s:%d  ·  код %s" % [r["ip"], r["port"], r["code"]]
		b.disabled = not r["open"]
		rooms_box.add_child(_centered(b))


# ---------- оформление ----------

func _title_c(t: String) -> Label:
	var l: Label = menu._title(t, 56)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _row() -> HBoxContainer:
	var r := HBoxContainer.new()
	r.alignment = BoxContainer.ALIGNMENT_CENTER
	r.add_theme_constant_override("separation", 14)
	return r


func _centered(c: Control) -> Control:
	var r := _row()
	c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	r.add_child(c)
	return r


func _label(t: String, fsize: int, col: Color, w: float) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if w > 0:
		l.custom_minimum_size = Vector2(w, 0)
	return l


func _hint(t: String) -> Label:
	var l := _label(t, 17, Color(0.62, 0.58, 0.52), 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(680, 0)
	return l


func _edit(text: String, placeholder: String, w: float) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.placeholder_text = placeholder
	e.custom_minimum_size = Vector2(w, 46)
	e.add_theme_font_size_override("font_size", 24)
	e.add_theme_color_override("font_color", Color(0.92, 0.88, 0.8))
	e.add_theme_color_override("font_placeholder_color", Color(0.5, 0.47, 0.42))
	e.add_theme_color_override("caret_color", Color(1.0, 0.5, 0.35))
	var n: StyleBoxFlat = menu._style(Color(0.06, 0.03, 0.03, 0.85), Color(0.45, 0.1, 0.07))
	n.content_margin_left = 12
	n.content_margin_right = 12
	var f: StyleBoxFlat = menu._style(Color(0.1, 0.04, 0.03, 0.9), Color(0.85, 0.18, 0.1))
	f.content_margin_left = 12
	f.content_margin_right = 12
	e.add_theme_stylebox_override("normal", n)
	e.add_theme_stylebox_override("focus", f)
	return e
