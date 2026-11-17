extends Node
## Сплитскрин на одном ПК (промпт 18.11 00:41): работает как сетевая игра, только без пинга.
## «Сплитскрин» в главном меню: эта копия игры открывает комнату на 127.0.0.1 и запускает вторую копию
## с аргументами `-- --split-client --split-port=N`; окна встают половинками экрана (слева игрок 1, справа игрок 2).
## Управление: два геймпада — у каждого игрока свой (у игрока 1 ещё клавиатура и мышь);
## один геймпад — игрок 1 на клавиатуре и мыши, игрок 2 на геймпаде.
## Вторая копия: окно не берёт фокус, звук выключен, настоящие мышь/клавиатура игнорируются,
## курсор в меню рисуется свой (gamepad.gd: virtual_cursor). Узел живёт в /root/Split.

const NetScript := preload("res://scripts/network/net.gd")
const PORT0 := 24690
const Pad := preload("res://scripts/ui/gamepad.gd")

var client := false
var port := 0
var pid := -1
var net
var menu
var start_t := -1.0
var was_online := false
var lost_t := 0.0


static func client_port() -> int:
	var args := OS.get_cmdline_user_args()
	if not "--split-client" in args:
		return 0
	for a in args:
		if a.begins_with("--split-port="):
			return int(a.get_slice("=", 1))
	return PORT0


static func get_split(tree: SceneTree) -> Node:
	return tree.root.get_node_or_null("Split") if tree else null


static func _make(tree: SceneTree, m) -> Node:
	var s := Node.new()
	s.set_script(load("res://scripts/network/split.gd"))
	s.name = "Split"
	s.menu = m
	tree.root.add_child(s)
	return s


## Игрок 1: «Сплитскрин» в меню.
static func start_host(m) -> void:
	var tree: SceneTree = m.get_tree()
	if get_split(tree):
		return
	var s := _make(tree, m)
	s._host()


## Игрок 2: запущен с --split-client (menu.gd, конец _ready).
static func boot_client(m) -> void:
	var tree: SceneTree = m.get_tree()
	if get_split(tree) or client_port() == 0:
		return
	var s := _make(tree, m)
	s._client()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.set_ignore_joypad_on_unfocused_application(false)   # геймпады работают в обоих окнах
	Input.joy_connection_changed.connect(func(_d, _c): _apply_pad())


func _host() -> void:
	net = NetScript.ensure(get_tree())
	net.my_name = "Игрок 1"   # без set_player_name: не перезаписываем сохранённое имя
	for p in range(PORT0, PORT0 + 10):
		if net.host(p) == OK:
			port = p
			break
	if port == 0:
		queue_free()
		return
	var args := PackedStringArray()
	if OS.has_feature("editor"):
		args.append_array(["--path", ProjectSettings.globalize_path("res://")])
	args.append_array(["--", "--split-client", "--split-port=%d" % port])
	pid = OS.create_process(OS.get_executable_path(), args)
	layout()
	_apply_pad()
	menu._open_net()   # страница комнаты: видно, что игрок 2 подключился; старт сам
	start_t = 0.0
	# вторая копия забирает фокус при запуске — возвращаем окно игроку 1
	get_tree().create_timer(2.5).timeout.connect(func(): DisplayServer.window_move_to_foreground())


func _client() -> void:
	client = true
	port = client_port()
	net = NetScript.ensure(get_tree())
	net.my_name = "Игрок 2"
	AudioServer.set_bus_mute(0, true)   # звук — из окна игрока 1
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	layout()
	_apply_pad()
	net.join("127.0.0.1", port)
	menu._open_net()


## Устройство геймпада для этой копии: -2 — без геймпада.
func pad_device() -> int:
	var pads := Input.get_connected_joypads()
	if client:
		return pads[1] if pads.size() >= 2 else (pads[0] if pads.size() == 1 else -2)
	return pads[0] if pads.size() >= 2 else -2


func _apply_pad() -> void:
	if menu and is_instance_valid(menu) and menu.pad:
		menu.pad.apply_map()


## Окно — половина экрана (вызывает и menu._apply_window вместо полноэкранного режима).
func layout() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var scr := DisplayServer.window_get_current_screen()
	var ss := DisplayServer.screen_get_size(scr)
	var sp := DisplayServer.screen_get_position(scr)
	@warning_ignore("integer_division")
	var w := ss.x / 2
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED, true)
	DisplayServer.window_set_size(Vector2i(w, ss.y))
	DisplayServer.window_set_position(sp + Vector2i(w if client else 0, 0))


func _input(e: InputEvent) -> void:
	# вторая копия: настоящие мышь и клавиатура принадлежат игроку 1 (курсор может пройти над этим окном)
	if client and (e is InputEventMouse or e is InputEventKey) and e.device != Pad.SYNTH:
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var root := get_tree().root
	if get_index() != root.get_child_count() - 1:
		root.move_child.call_deferred(self, -1)   # последним в корне — первым получает _input
	if net == null or not is_instance_valid(net):
		return
	if net.ping_l and is_instance_valid(net.ping_l):
		net.ping_l.visible = false   # без пинга
	if client:
		var online: bool = net.connected or net.joining or net.rejoining
		if online:
			was_online = true
			lost_t = 0.0
		elif was_online:
			lost_t += delta
			if lost_t > 2.0:
				get_tree().quit()   # игрок 1 вышел — закрываемся
		return
	# вышли из комнаты (меню, «Назад») — закрываем вторую копию, окно обратно во весь экран
	if not net.hosting:
		_end()
		return
	# игрок 1: игрок 2 подключился — начинаем
	if start_t >= 0.0 and not net.in_game and net.players.size() >= 2:
		start_t += delta
		if start_t > 1.0:
			start_t = -1.0
			net.start_game()
	# вторая копия могла захватить курсор (Windows) — возвращаем захват своему окну
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and DisplayServer.window_is_focused():
		var r := Rect2i(DisplayServer.window_get_position(), DisplayServer.window_get_size())
		if not r.has_point(DisplayServer.mouse_get_position()):
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _end() -> void:
	if pid > 0:
		OS.kill(pid)
		pid = -1
	if net and is_instance_valid(net) and net.hosting:
		net.leave()
	get_parent().remove_child(self)
	queue_free()
	if menu and is_instance_valid(menu):
		menu.set("_win_applied", -1)
		menu.call_deferred("apply_settings")
		if menu.pad:
			menu.pad.call_deferred("apply_map")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if pid > 0:
			OS.kill(pid)
			pid = -1
