extends SceneTree
## Автотест сетевой игры: два экземпляра на одном ПК.
##   godot --path godot/eskiness -s res://tests/net_test.gd -- host <папка_скриншотов>
##   godot --path godot/eskiness -s res://tests/net_test.gd -- client <папка_скриншотов>
## Хост открывает комнату и ждёт клиента; клиент находит комнату через broadcast, подключается по коду.
## Дальше (этап 2): хост начинает, клиент ходит и бьёт врага, хост видит. Пишет в лог строки «NETTEST …».
## Сейв-слот 99, settings.cfg не трогается (eskiness_net_nosave).

var role := "host"
var shots := ""
var menu
var net
var t0 := 0


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		role = a[0]
	if a.size() > 1:
		shots = a[1]
	Engine.set_meta("eskiness_slot", 99)
	Engine.set_meta("eskiness_net_nosave", true)
	t0 = Time.get_ticks_msec()
	change_scene_to_file("res://main.tscn")
	_run.call_deferred()


func log_(s: String) -> void:
	print("NETTEST %s %.1f %s" % [role, (Time.get_ticks_msec() - t0) / 1000.0, s])


func wait(sec: float) -> void:
	await create_timer(sec).timeout


func shot(nm: String) -> void:
	if shots == "":
		return
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png(shots.path_join("%s_%s.png" % [role, nm]))
	log_("screenshot " + nm)


func _find_menu() -> Node:
	for c in current_scene.get_children():
		if c.get_script() == load("res://menu.gd"):
			return c
	return null


func _run() -> void:
	await wait(1.5)
	menu = _find_menu()
	if menu == null:
		log_("FAIL no menu")
		quit(1)
		return
	menu._open_net()
	net = root.get_node("Net")
	net.set_player_name("Хост" if role == "host" else "Клиент")
	var lobby = menu.net_box
	if role == "host":
		lobby._build("host")
		lobby.port_edit.text = "24680"
		if net.host(24680) != OK:
			log_("FAIL host")
			quit(1)
			return
		lobby._build("host")
		log_("hosting code %s" % net.encode(net.lan_ips()[0] if not net.lan_ips().is_empty() else "127.0.0.1", 24680))
		var w := 0.0
		while net.players.size() < 2 and w < 40.0:
			await wait(0.5)
			w += 0.5
		if net.players.size() < 2:
			log_("FAIL no client")
			quit(1)
			return
		log_("client joined: %s" % str(net.players))
		await wait(1.0)
		await shot("lobby")
		await _host_game()
	else:
		await wait(2.0)
		lobby._build("join")
		if not net.start_discovery():
			log_("FAIL discovery bind")
		var w := 0.0
		while net.rooms.is_empty() and w < 15.0:
			await wait(0.5)
			w += 0.5
		if net.rooms.is_empty():
			log_("FAIL no rooms found")
			quit(1)
			return
		var r: Dictionary = net.rooms.values()[0]
		log_("found room %s code %s from %s" % [r["name"], r["code"], r["ip"]])
		await shot("rooms")
		# подключение по коду (как если бы ввели руками); код содержит LAN-IP хоста
		lobby.addr_edit.text = r["code"]
		var a: Array = net.parse_address(r["code"])
		log_("code decodes to %s:%d" % [a[0], a[1]])
		lobby._connect_typed()
		w = 0.0
		while not net.connected and w < 12.0:
			await wait(0.5)
			w += 0.5
		if not net.connected:
			log_("code connect failed, fallback 127.0.0.1")
			lobby.connect_to("127.0.0.1", 24680)
			w = 0.0
			while not net.connected and w < 12.0:
				await wait(0.5)
				w += 0.5
		if not net.connected:
			log_("FAIL connect")
			quit(1)
			return
		log_("connected, players %s" % str(net.players))
		await wait(1.5)
		await shot("lobby")
		await _client_game()
	log_("DONE")
	quit(0)


## Этап 2 (совместная игра) — дописывается позже.
func _host_game() -> void:
	await wait(3.0)


func _client_game() -> void:
	await wait(3.0)
