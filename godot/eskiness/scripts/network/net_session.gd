extends "res://scripts/network/net_world.gd"
# Часть net.gd: комнаты — хост, подключение, лобби, отключение, поиск в локальной сети.


# ---------- хост ----------

func host(p: int) -> Error:
	leave()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(p, MAX_PEERS)
	if err != OK:
		peer = null
		status.emit("Не удалось открыть порт %d (занят?)" % p, true)
		return err
	port = p
	multiplayer.multiplayer_peer = peer
	hosting = true
	in_game = false
	players = {1: my_name}
	udp_out = PacketPeerUDP.new()
	udp_out.set_broadcast_enabled(true)
	bc_t = 0.0
	status.emit("Комната открыта", false)
	lobby_changed.emit()
	return OK


func _on_peer_connected(id: int) -> void:
	_lenient(id)
	if hosting:
		pass   # ждём rq_hello с именем
	_peer_joined(id)


func _lenient(id: int) -> void:
	if peer:
		var pp := peer.get_peer(id)
		if pp:
			pp.set_timeout(TIMEOUT_LIMIT, TIMEOUT_MIN, TIMEOUT_MAX)
			pp.ping_interval(500)


func _on_peer_disconnected(id: int) -> void:
	last_seen.erase(id)
	if players.has(id):
		var nm: String = players[id]
		var lost := not bye.has(id)
		bye.erase(id)
		players.erase(id)
		if hosting:
			_send_players()
		_peer_left(id, nm, lost)
	lobby_changed.emit()


@rpc("any_peer", "reliable")
func rq_hello(nm: String, ver: int) -> void:
	if not hosting:
		return
	var id := multiplayer.get_remote_sender_id()
	if ver != VERSION:
		rpc_id(id, "kicked", "Разные версии игры — обновите обе")
		_drop_later(id)
		return
	if in_game:
		rpc_id(id, "kicked", "Игра уже началась")
		_drop_later(id)
		return
	nm = nm.strip_edges().substr(0, 20)
	if nm == "":
		nm = "Игрок %d" % players.size()
	players[id] = nm
	_send_players()
	lobby_changed.emit()


@rpc("any_peer", "reliable")
func rq_bye() -> void:
	var id := multiplayer.get_remote_sender_id()
	bye[id] = true
	if id == 1:
		host_bye = true


func _drop_later(id: int) -> void:
	await get_tree().create_timer(0.5).timeout
	if peer and hosting:
		peer.disconnect_peer(id)


func _send_players() -> void:
	rpc("lobby_players", players)


@rpc("authority", "reliable")
func lobby_players(d: Dictionary) -> void:
	players = d
	lobby_changed.emit()


@rpc("authority", "reliable")
func kicked(reason: String) -> void:
	status.emit(reason, true)
	last_msg = reason
	_close_peer()
	lobby_changed.emit()


# ---------- клиент ----------

func join(ip: String, p: int) -> Error:
	leave()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, p)
	if err != OK:
		peer = null
		status.emit("Не удалось подключиться к %s:%d" % [ip, p], true)
		return err
	multiplayer.multiplayer_peer = peer
	joining = true
	join_t = 10.0
	status.emit("Подключаемся к %s:%d…" % [ip, p], false)
	lobby_changed.emit()
	return OK


func _on_connected() -> void:
	_lenient(1)
	host_bye = false
	joining = false
	connected = true
	status.emit("Подключено. Ждём, пока хост начнёт игру…", false)
	rpc_id(1, "rq_hello", my_name, VERSION)
	lobby_changed.emit()


func _on_failed() -> void:
	if not joining:
		return
	_close_peer()
	status.emit("Не получилось подключиться: комната не отвечает (неверный код, порт закрыт или файрвол)", true)
	lobby_changed.emit()


func _on_server_gone() -> void:
	var was_game := in_game
	var g = game
	_close_peer()
	last_msg = "Хост закрыл комнату" if host_bye else "Связь с хостом пропала (нет ответа по сети больше 20 с)"
	host_bye = false
	status.emit(last_msg, true)
	lobby_changed.emit()
	if was_game:
		_host_lost_in_game(g)


# ---------- поиск комнат в локальной сети ----------

func start_discovery() -> bool:
	if udp_in:
		return true
	udp_in = PacketPeerUDP.new()
	var err := udp_in.bind(DISCOVERY_PORT)
	if err != OK:
		udp_in = null
		return false
	return true


func stop_discovery() -> void:
	if udp_in:
		udp_in.close()
	udp_in = null
	rooms = {}


func _broadcast() -> void:
	var ips := lan_ips()
	var code := encode(ips[0], port) if not ips.is_empty() else encode("127.0.0.1", port)
	var msg := JSON.stringify({"g": "eskiness", "v": VERSION, "name": "Комната %s" % my_name, "port": port,
		"code": code, "n": players.size(), "open": not in_game}).to_utf8_buffer()
	for dest in ["255.255.255.255", "127.0.0.1"]:
		udp_out.set_dest_address(dest, DISCOVERY_PORT)
		udp_out.put_packet(msg)
	# широковещательный адрес каждой подсети /24 (некоторые сети 255.255.255.255 не пропускают)
	for ip in ips:
		var p: PackedStringArray = ip.split(".")
		udp_out.set_dest_address("%s.%s.%s.255" % [p[0], p[1], p[2]], DISCOVERY_PORT)
		udp_out.put_packet(msg)
