extends Node
## Сетевая игра (промпт 14.11 19:37): комнаты, подключение по коду / IP:порт, поиск комнат в локальной сети.
## Узел живёт в /root/Net (переживает перезагрузку сцены). Создаётся меню при входе в «Сетевую игру» (ensure).
##
## Транспорт — ENetMultiplayerPeer (UDP), порт по умолчанию PORT. Хост раз в секунду шлёт UDP-broadcast
## на DISCOVERY_PORT (имя комнаты, код, число игроков); клиенты слушают и показывают «Найденные комнаты».
## Код комнаты — 4 байта IP + 2 байта порта в base32 без похожих символов: «XXXXX-XXXXX».
## Наружу (в интернет) ничего не отправляется: внешний IP хост вводит сам.

signal lobby_changed                     # игроки / состояние комнаты
signal rooms_changed                     # найденные в локалке комнаты
signal status(text: String, bad: bool)   # статус подключения для лобби

const PORT := 24680
const DISCOVERY_PORT := 24681
const MAX_PEERS := 7
const VERSION := 1
const CODE_ABC := "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"   # 32 знака: без 0/O и 1/I
const CFG := "user://settings.cfg"

var peer: ENetMultiplayerPeer
var port := PORT
var my_name := "Игрок"
var players := {}          # peer_id -> имя (у хоста и у клиентов)
var hosting := false
var connected := false     # клиент: подключён к хосту
var joining := false       # клиент: идёт подключение
var join_t := 0.0
var in_game := false       # игра началась (новых не пускаем)
var rooms := {}            # код -> {name, ip, port, n, open, t}
var udp_out: PacketPeerUDP
var udp_in: PacketPeerUDP
var bc_t := 0.0
var last_msg := ""         # сообщение для лобби после выхода в меню (хост отключился и т.п.)
var game                   # game.gd, пока идёт сетевая игра (этап 2)


static func ensure(tree: SceneTree) -> Node:
	var n := tree.root.get_node_or_null("Net")
	if n == null:
		n = (load("res://net.gd") as GDScript).new()
		n.name = "Net"
		tree.root.add_child(n)
	return n


static func get_net(tree: SceneTree) -> Node:
	return tree.root.get_node_or_null("Net") if tree else null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_name()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_failed)
	multiplayer.server_disconnected.connect(_on_server_gone)


func is_host() -> bool:
	return hosting


func active() -> bool:
	return hosting or connected


# ---------- имя игрока (settings.cfg, отдельная секция [net]) ----------

func _load_name() -> void:
	var cf := ConfigFile.new()
	if cf.load(CFG) == OK:
		my_name = String(cf.get_value("net", "name", my_name))


func set_player_name(nm: String) -> void:
	nm = nm.strip_edges().substr(0, 20)
	if nm == "":
		return
	my_name = nm
	if Engine.has_meta("eskiness_net_nosave"):
		return   # тестовые запуски не трогают settings.cfg игрока
	var cf := ConfigFile.new()
	cf.load(CFG)   # остальные секции файла сохраняем как есть
	cf.set_value("net", "name", my_name)
	cf.save(CFG)


# ---------- код комнаты ----------

static func encode(ip: String, p: int) -> String:
	var parts := ip.split(".")
	if parts.size() != 4:
		return ""
	var v := 0
	for s in parts:
		if not s.is_valid_int():
			return ""
		v = (v << 8) | (int(s) & 255)
	v = (v << 16) | (p & 0xFFFF)
	var out := ""
	for i in 10:
		out = CODE_ABC[v & 31] + out
		v >>= 5
	return out.substr(0, 5) + "-" + out.substr(5)


## Разбор поля «код комнаты или IP:порт». [ip, порт] или [] — не понял.
static func parse_address(text: String) -> Array:
	var s := text.strip_edges()
	if s == "":
		return []
	if s.count(".") == 3:
		var ip := s
		var p := PORT
		if ":" in s:
			ip = s.get_slice(":", 0)
			var ps := s.get_slice(":", 1)
			if not ps.is_valid_int():
				return []
			p = int(ps)
		if not ip.is_valid_ip_address() or p <= 0 or p > 65535:
			return []
		return [ip, p]
	if s.to_lower() == "localhost":
		return ["127.0.0.1", PORT]
	s = s.to_upper().replace("-", "").replace(" ", "").replace("O", "0")
	if s.length() != 10:
		return []
	var v := 0
	for ch in s:
		var k := CODE_ABC.find(ch)
		if k < 0:
			return []
		v = (v << 5) | k
	if v >> 48 != 0:
		return []
	var p2 := v & 0xFFFF
	v >>= 16
	return ["%d.%d.%d.%d" % [(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255], p2]


## Адреса этого ПК в локальной сети (192.168.*, 10.*, 172.16–31.*), сначала самые «домашние».
static func lan_ips() -> Array:
	var out: Array = []
	for pref in ["192.168.", "10.", "172."]:
		for a in IP.get_local_addresses():
			var s := String(a)
			if not s.begins_with(pref) or s.count(".") != 3:
				continue
			if pref == "172.":
				var b := int(s.get_slice(".", 1))
				if b < 16 or b > 31:
					continue
			if not s in out:
				out.append(s)
	return out


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
	if hosting:
		pass   # ждём rq_hello с именем
	_peer_joined(id)


func _on_peer_disconnected(id: int) -> void:
	if players.has(id):
		var nm: String = players[id]
		players.erase(id)
		if hosting:
			_send_players()
		_peer_left(id, nm)
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
	_close_peer()
	last_msg = "Хост отключился"
	status.emit(last_msg, true)
	lobby_changed.emit()
	if was_game:
		_host_lost_in_game()


## Выйти из комнаты / закрыть её.
func leave() -> void:
	_close_peer()
	lobby_changed.emit()


func _close_peer() -> void:
	if peer:
		peer.close()
	peer = null
	if multiplayer.multiplayer_peer != null and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	hosting = false
	connected = false
	joining = false
	in_game = false
	players = {}
	udp_out = null
	_net_reset()


## Пинг до хоста (клиент) или самый большой до клиентов (хост), мс. -1 — нет связи.
func ping_ms() -> int:
	if peer == null:
		return -1
	if hosting:
		var m := -1
		for id in players:
			if id == 1:
				continue
			var pp := peer.get_peer(id)
			if pp:
				m = maxi(m, int(pp.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)))
		return m
	var hp := peer.get_peer(1)
	return int(hp.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)) if hp else -1


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


# ---------- игра (этап 2) ----------

func _peer_joined(_id: int) -> void:
	pass


func _peer_left(_id: int, _nm: String) -> void:
	pass


func _host_lost_in_game() -> void:
	pass


func _net_reset() -> void:
	game = null


func _game_tick(_delta: float) -> void:
	pass


## «Начать» у хоста (этап 2 — совместная игра).
func start_game() -> void:
	status.emit("Совместная игра — в следующем обновлении", true)
