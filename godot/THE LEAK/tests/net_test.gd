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


func _world_sig(g) -> String:
	var js: Array = []
	for j in g.jars:
		if is_instance_valid(j) and not j.is_queued_for_deletion():
			js.append("%s@%.1f,%.1f" % [j.get_meta("nid", "?"), j.position.x, j.position.z])
	return "jars=%d [%s] floor=%d" % [js.size(), ", ".join(js.slice(0, 3)), net._floor_pickups(g).size()]


func _enemies_sig() -> String:
	var s := PackedStringArray()
	for e in get_nodes_in_group("enemies"):
		s.append("%s:%s:%.0f@%.1f,%.1f" % [e.get_meta("nid", "?"), e.state, e.hp, e.global_position.x, e.global_position.z])
	return " ".join(s)


## Хост: «Начать», затем следит, что видит клиента и что враги получают урон.
func _host_game() -> void:
	net.start_game()
	var w := 0.0
	while net.game == null and w < 10.0:
		await wait(0.25)
		w += 0.25
	if net.game == null:
		log_("FAIL game not started")
		return
	var g = net.game
	await wait(1.0)
	log_("world " + _world_sig(g))
	log_("puppets %s" % str(net.puppets.keys()))
	for i in 22:
		await wait(1.0)
		for id in net.puppets:
			var pp = net.puppets[id]
			log_("sees client at %.2f,%.2f,%.2f fists=%s vis=%s" % [pp.global_position.x, pp.global_position.y, pp.global_position.z, pp.fists, pp.visible])
		if i % 3 == 0:
			log_("enemies " + _enemies_sig())
		if i == 5:
			await shot("game")
	log_("enemies end " + _enemies_sig())
	for i in 14:
		await wait(1.0)
		for id in net.puppets:
			var pp = net.puppets[id]
			log_("client puppet vis=%s at %.1f,%.1f" % [pp.visible, pp.global_position.x, pp.global_position.z])
	await shot("end")
	var broken := 0
	for j in g.jars:
		if is_instance_valid(j) and j.broken:
			broken += 1
	log_("jars broken %d" % broken)


## Клиент: ждёт старта, ходит, оборачивается к хосту, идёт к врагу и бьёт его, разбивает кувшин.
func _client_game() -> void:
	var w := 0.0
	while net.game == null and w < 15.0:
		await wait(0.25)
		w += 0.25
	if net.game == null:
		log_("FAIL game not started")
		return
	var g = net.game
	await wait(1.0)
	log_("world " + _world_sig(g))
	var p = g.player
	log_("me at %.2f,%.2f  host puppet %s" % [p.global_position.x, p.global_position.z, str(net.puppets.keys())])
	Input.action_press("move_forward")
	await wait(1.5)
	Input.action_release("move_forward")
	log_("walked to %.2f,%.2f" % [p.global_position.x, p.global_position.z])
	p.toggle_fists()
	await wait(1.0)
	p.rotation.y += PI
	await wait(1.0)
	await shot("game")
	p.rotation.y -= PI
	# кувшин: ударить ближайший
	var jar = null
	for j in g.jars:
		if is_instance_valid(j) and not j.broken and (jar == null or j.global_position.distance_to(p.global_position) < jar.global_position.distance_to(p.global_position)):
			jar = j
	if jar:
		log_("hit jar %s" % jar.get_meta("nid", "?"))
		for k in 3:
			if not jar.broken:
				jar.take_hit(5.0, Vector3(1, 0, 0))
				await wait(0.4)
		log_("jar broken on client: %s" % jar.broken)
		await wait(1.5)
		var near := 0
		for pk in net._floor_pickups(g):
			if pk.global_position.distance_to(jar.global_position) < 3.0:
				near += 1
		log_("loot near jar (from host): %d, bag before: coins=%d items=%d" % [near, g.inv.coins, _items(g)])
		p.global_position = jar.global_position + Vector3(0, 0.2, 0)
		await wait(2.5)
		log_("after walking onto loot: coins=%d items=%d, pickups left near jar=%d" % [g.inv.coins, _items(g), _near(g, jar.global_position)])
		p.global_position = Vector3(-4.7, 0.05, 0)
	# враг: подойти и ударить
	log_("enemies " + _enemies_sig())
	var e = null
	for c in get_nodes_in_group("enemies"):
		if c.state != "dead":
			e = c
			break
	if e == null:
		log_("FAIL no enemy puppets")
		return
	var coins0: int = g.inv.coins
	var to_e: Vector3 = e.global_position
	p.global_position = to_e + Vector3(-1.3, 0.3, 0)
	p.rotation.y = -PI / 2.0
	await wait(0.6)
	for k in 3:
		if is_instance_valid(e) and e.state != "dead":
			log_("hit enemy %s hp(before)=%.0f" % [e.get_meta("nid"), e.hp])
			e.take_hit(14.0, Vector3(1, 0, 0))
			await wait(0.7)
	# выстрел из пистолета (gun.gd) — урон тоже через хоста
	var e2 = null
	for c in get_nodes_in_group("enemies"):
		if c.state != "dead":
			e2 = c
			break
	if e2 and g.gun:
		g.inv.equip["right"] = "pistol"
		g.inv.equip_dur["right"] = 8.0
		g._apply_equip("right")
		await wait(0.3)
		for k in 2:
			if not is_instance_valid(e2) or e2.state == "dead":
				break
			var c: Vector3 = p.cam.global_position
			var tgt: Vector3 = e2.global_position + Vector3(0, 1.0, 0)
			var d := tgt - c
			p.rotation.y = atan2(-d.x, -d.z)
			p.head.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())
			await wait(0.05)
			log_("shoot enemy %s hp(before)=%.0f" % [e2.get_meta("nid"), e2.hp])
			g.gun.cd = 0.0
			g.gun.fire()
			await wait(0.6)
		log_("after shots: %s" % (("%s hp=%.0f state=%s" % [e2.get_meta("nid"), e2.hp, e2.state]) if is_instance_valid(e2) else "gone"))
	await wait(1.0)
	log_("enemy after: %s hp=%.0f state=%s" % [e.get_meta("nid"), e.hp, e.state] if is_instance_valid(e) else "enemy gone")
	await shot("fight")
	for k in 5:
		await wait(1.0)
		log_("my hp %.0f alive=%s coins=%d (было %d)" % [g.hp, g.alive, g.inv.coins, coins0])
	log_("enemies end " + _enemies_sig())
	var w2 := 0.0
	while not g.alive and w2 < 14.0:
		await wait(1.0)
		w2 += 1.0
	log_("respawned=%s hp=%.0f at %.1f,%.1f" % [g.alive, g.hp, p.global_position.x, p.global_position.z])
	# хост выходит — ждём сообщение и выход в меню
	w2 = 0.0
	while net.active() and w2 < 25.0:
		await wait(0.5)
		w2 += 0.5
	await wait(2.0)
	log_("after host quit: active=%s last_msg=%s menu_visible=%s" % [net.active(), net.last_msg, _find_menu().visible if _find_menu() else "?"])
	await shot("host_left")


func _items(g) -> int:
	var n := 0
	for s in g.inv.slots:
		if s != null:
			n += int(s["n"])
	return n


func _near(g, pos: Vector3) -> int:
	var c := 0
	for pk in net._floor_pickups(g):
		if pk.global_position.distance_to(pos) < 3.0:
			c += 1
	return c
