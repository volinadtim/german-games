extends "res://scripts/network/net_session.gd"
## Сетевая игра (промпт 14.11 19:37): комнаты, подключение по коду / IP:порт, поиск комнат в локальной сети.
## Узел живёт в /root/Net (переживает перезагрузку сцены). Создаётся меню при входе в «Сетевую игру» (ensure).
##
## Транспорт — ENetMultiplayerPeer (UDP), порт по умолчанию PORT. Хост раз в секунду шлёт UDP-broadcast
## на DISCOVERY_PORT (имя комнаты, код, число игроков); клиенты слушают и показывают «Найденные комнаты».
## Код комнаты — 4 байта IP + 2 байта порта в base32 без похожих символов: «XXXXX-XXXXX».
## Наружу (в интернет) ничего не отправляется: внешний IP хост вводит сам.


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_name()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_failed)
	multiplayer.server_disconnected.connect(_on_server_gone)


func _process(delta: float) -> void:
	if joining:
		join_t -= delta
		if join_t <= 0.0:
			joining = true
			_on_failed()
	# хост: объявление раз в секунду
	if hosting and udp_out:
		bc_t -= delta
		if bc_t <= 0.0:
			bc_t = 1.0
			_broadcast()
	# клиент: слушаем объявления
	if udp_in:
		var changed := false
		while udp_in.get_available_packet_count() > 0:
			var pkt := udp_in.get_packet()
			var from_ip := udp_in.get_packet_ip()
			var d = JSON.parse_string(pkt.get_string_from_utf8())
			if not d is Dictionary or d.get("g", "") != "eskiness":
				continue
			var code := String(d.get("code", ""))
			var key := code if code != "" else "%s:%d" % [from_ip, int(d.get("port", PORT))]
			var old: Dictionary = rooms.get(key, {})
			# одна комната приходит и широковещательно, и на 127.0.0.1 (тот же ПК) — 127.0.0.1 надёжнее
			var ip := from_ip
			if old.get("ip", "") == "127.0.0.1" and Time.get_ticks_msec() / 1000.0 - float(old.get("t_lo", 0.0)) < 3.0:
				ip = "127.0.0.1"
			var e := {"name": String(d.get("name", "?")), "ip": ip, "port": int(d.get("port", PORT)),
				"n": int(d.get("n", 1)), "open": bool(d.get("open", true)), "code": code,
				"t": Time.get_ticks_msec() / 1000.0, "t_lo": old.get("t_lo", 0.0)}
			if from_ip == "127.0.0.1":
				e["t_lo"] = e["t"]
			if old.is_empty() or old["name"] != e["name"] or old["n"] != e["n"] or old["ip"] != e["ip"] or old["open"] != e["open"]:
				changed = true
			rooms[key] = e
		var now := Time.get_ticks_msec() / 1000.0
		for k in rooms.keys():
			if now - float(rooms[k]["t"]) > 3.5:
				rooms.erase(k)
				changed = true
		if changed:
			rooms_changed.emit()
	if game != null:
		_game_tick(delta)
