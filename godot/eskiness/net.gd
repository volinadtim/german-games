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
	var g = game
	_close_peer()
	last_msg = "Хост отключился"
	status.emit(last_msg, true)
	lobby_changed.emit()
	if was_game:
		_host_lost_in_game(g)


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




# ---------- совместная игра (этап 2) ----------
## Старт: хост строит мир как обычную новую игру и рассылает клиентам его расстановку (кувшины, стекло,
## вещи на полу, кучки камней) — клиент строит ту же сцену. Сейвы в сети не пишутся.
## Игроки: у каждого свой player.gd с камерой; чужие — модели (player.gd с puppet = true), 20 Гц, с интерполяцией.
## Враги — только у хоста (ИИ, урон, лут); клиенту 15 раз в секунду приходят их позиции/состояния/HP.
## Удар клиента по врагу → хосту; враг бьёт ближайшего живого игрока (урон — тому игроку по сети).
## Предметы: кто взял — решает хост (без дюпа). Кувшины бьются у всех, лут высыпает хост.
## Автомат, магазин, ящики, сейф, сундук, машина — у каждого свои (монеты и инвентарь свои).

const PlayerScript := preload("res://player.gd")
const EnemyScript := preload("res://enemy.gd")
const Items := preload("res://items.gd")
const PickupScript := preload("res://pickup.gd")
const SEND_DT := 1.0 / 20.0
const ENEMY_DT := 1.0 / 15.0
const RESPAWN_T := 10.0

var puppets := {}         # peer_id -> player.gd (модель другого игрока)
var targets := {}         # хост: peer_id -> RemoteTarget (цель для врагов)
var enemy_map := {}       # nid -> враг (хост: свои, клиент: копии)
var enemy_seq := 0
var pickups := {}         # nid -> pickup.gd
var pk_seq := 0
var jar_seq := 0
var suppress := false     # предмет создаётся по сети — не рассылать обратно
var pending_world := {}   # клиент: мир от хоста до старта
var early: Array = []     # клиент: события, пришедшие до постройки мира
var send_t := 0.0
var es_t := 0.0
var ui_t := 0.0
var was_punching := false
var dead_t := -1.0
var ui: CanvasLayer
var ping_l: Label
var info_l: Label


## Цель врага у хоста — другой игрок: у него, как у game.gd, есть player, alive и damage_player.
class RemoteTarget:
	var player: CharacterBody3D
	var alive := true
	var peer := 0
	var net

	func damage_player(amount: float, from: Vector3) -> void:
		net.rpc_id(peer, "net_damage", amount, from)


func _peer_joined(_id: int) -> void:
	pass


func _peer_left(id: int, nm: String) -> void:
	if puppets.has(id):
		if is_instance_valid(puppets[id]):
			puppets[id].queue_free()
		puppets.erase(id)
	targets.erase(id)
	if game and is_instance_valid(game):
		game.hud.toast("%s вышел из игры" % nm, Color(0.85, 0.7, 0.5))


func _host_lost_in_game(g) -> void:
	last_msg = "Хост отключился — игра закончена"
	_net_reset()
	if g and is_instance_valid(g):
		g.to_main_menu()


func _net_reset() -> void:
	game = null
	puppets = {}
	targets = {}
	enemy_map = {}
	pickups = {}
	pending_world = {}
	early = []
	dead_t = -1.0
	if ui and is_instance_valid(ui):
		ui.queue_free()
	ui = null


## «Начать» у хоста.
func start_game() -> void:
	if not hosting or in_game:
		return
	in_game = true
	peer.refuse_new_connections = true
	lobby_changed.emit()
	get_tree().current_scene._start_game()


@rpc("authority", "reliable")
func net_start(world: Dictionary, pl: Dictionary) -> void:
	players = pl
	pending_world = world
	in_game = true
	lobby_changed.emit()
	get_tree().current_scene._start_game()


## Из game.setup (вместо загрузки сейва).
func on_game_setup(g) -> void:
	game = g
	_make_ui()
	if hosting:
		rpc("net_start", _world_state(g), players)
	else:
		_apply_world(g, pending_world)
		pending_world = {}
	var ids: Array = players.keys()
	ids.sort()
	var k := maxi(ids.find(multiplayer.get_unique_id()), 0)
	g.player.global_position = g.START + Vector3(0.9 * k, 0, 0)
	for id in ids:
		if id != multiplayer.get_unique_id():
			_make_puppet(id)
	g.hud.toast("Сетевая игра: %d игр." % ids.size(), Color(0.75, 0.85, 0.65))
	for c in early:
		c.call()
	early = []


func _world_state(g) -> Dictionary:
	var d: Dictionary = g.save_state()
	var w := {}
	for key in ["chest_pos", "chests", "jars", "glass", "stone_piles", "floor"]:
		w[key] = d[key]
	var jids: Array = []
	for j in g.jars:
		if is_instance_valid(j):
			j.set_meta("nid", "j%d" % jar_seq)
			jar_seq += 1
			jids.append(j.get_meta("nid"))
	w["jar_ids"] = jids
	var fids: Array = []
	var k := 0
	for n in _floor_pickups(g):
		var nid := "w%d" % k
		k += 1
		n.set_meta("nid", nid)
		pickups[nid] = n
		fids.append(nid)
	w["floor_ids"] = fids
	return w


func _floor_pickups(g) -> Array:
	var out: Array = []
	for n in g.get_children():
		if n is PickupScript and not n.is_queued_for_deletion() and not n.taken:
			out.append(n)
	return out


func _apply_world(g, w: Dictionary) -> void:
	if w.is_empty():
		return
	var d: Dictionary = g.save_state()   # свой игрок (инвентарь, здоровье) — свой
	for key in w:
		d[key] = w[key]
	d["hunters"] = 0
	suppress = true
	g.load_state(d)
	suppress = false
	var jl: Array = g.jars.filter(func(x): return is_instance_valid(x) and not x.is_queued_for_deletion())
	var jids: Array = w.get("jar_ids", [])
	for i in mini(jl.size(), jids.size()):
		jl[i].set_meta("nid", jids[i])
	var fl := _floor_pickups(g)
	var fids: Array = w.get("floor_ids", [])
	for i in mini(fl.size(), fids.size()):
		fl[i].set_meta("nid", fids[i])
		pickups[fids[i]] = fl[i]


func _make_puppet(id: int) -> void:
	if puppets.has(id) or game == null:
		return
	var pp = PlayerScript.new()
	pp.puppet = true
	pp.name = "NetPlayer%d" % id
	pp.position = game.START
	pp.rotation.y = -PI / 2.0
	pp.net_pos = game.START
	pp.net_yaw = -PI / 2.0
	game.get_parent().add_child(pp)
	pp.cam.current = false
	pp.collision_layer = 0   # свой игрок сквозь чужого проходит, лучи врагов и ударов его не видят
	var lb := Label3D.new()
	lb.text = String(players.get(id, "?"))
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.pixel_size = 0.0035
	lb.font_size = 44
	lb.outline_size = 10
	lb.modulate = Color(0.95, 0.9, 0.8)
	lb.position.y = 2.05
	pp.add_child(lb)
	puppets[id] = pp
	if hosting:
		var t := RemoteTarget.new()
		t.player = pp
		t.peer = id
		t.net = self
		targets[id] = t


# ---------- каждый кадр ----------

func _game_tick(delta: float) -> void:
	if not is_instance_valid(game):
		_net_reset()
		return
	var p = game.player
	send_t -= delta
	if send_t <= 0.0 and p and peer:
		send_t = SEND_DT
		var flags := (1 if p.fists else 0) | (2 if p.crouched else 0) | (4 if game.alive else 0)
		rpc("ps", p.global_position, p.rotation.y, p.head.rotation.x, p.velocity, flags, p.weapon_ids[0], p.weapon_ids[1])
	if p and p.punching and not was_punching and peer:
		rpc("pev", p.last_arm)
	was_punching = p != null and p.punching
	if hosting:
		es_t -= delta
		if es_t <= 0.0:
			es_t = ENEMY_DT
			_send_enemies()
	if dead_t > 0.0:
		dead_t -= delta
		info_l.text = "Вы погибли. Возрождение через %d с" % int(ceil(dead_t))
		if dead_t <= 0.0:
			_respawn()
	ui_t -= delta
	if ui_t <= 0.0:
		ui_t = 0.5
		var pm := ping_ms()
		ping_l.text = ("пинг %d мс" % pm if pm >= 0 else "пинг —") + "  ·  игроков %d" % players.size()


func _make_ui() -> void:
	if ui and is_instance_valid(ui):
		ui.queue_free()
	ui = CanvasLayer.new()
	ui.layer = 4
	add_child(ui)
	ping_l = Label.new()   # сверху по центру: справа вверху на телефоне — экранные кнопки
	ping_l.anchor_left = 0.5
	ping_l.anchor_right = 0.5
	ping_l.offset_left = -200
	ping_l.offset_right = 200
	ping_l.offset_top = 6
	ping_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ping_l.add_theme_font_size_override("font_size", 16)
	ping_l.add_theme_color_override("font_color", Color(0.8, 0.78, 0.7, 0.85))
	ping_l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	ping_l.add_theme_constant_override("outline_size", 4)
	ui.add_child(ping_l)
	info_l = Label.new()
	info_l.set_anchors_preset(Control.PRESET_CENTER)
	info_l.offset_left = -400
	info_l.offset_right = 400
	info_l.offset_top = -80
	info_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_l.add_theme_font_size_override("font_size", 34)
	info_l.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
	info_l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	info_l.add_theme_constant_override("outline_size", 8)
	ui.add_child(info_l)


# ---------- игроки ----------

@rpc("any_peer", "unreliable_ordered", "call_remote", 1)
func ps(pos: Vector3, yaw: float, pitch: float, vel: Vector3, flags: int, w0: String, w1: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	var pp = puppets.get(id)
	if pp == null or not is_instance_valid(pp):
		return
	pp.net_pos = pos
	pp.net_yaw = yaw
	pp.net_pitch = pitch
	pp.net_vel = vel
	pp.net_sprint = Vector2(vel.x, vel.z).length() > PlayerScript.WALK + 0.4
	pp.net_crouch = flags & 2 != 0
	var f := flags & 1 != 0
	if f != pp.fists and not pp.punching:
		pp.toggle_fists()
	var alive := flags & 4 != 0
	pp.visible = alive
	if targets.has(id):
		targets[id].alive = alive
	if pp.weapon_ids[0] != w0:
		pp.set_weapon(w0, 0)
	if pp.weapon_ids[1] != w1:
		pp.set_weapon(w1, 1)


@rpc("any_peer", "reliable")
func pev(arm: int) -> void:
	var pp = puppets.get(multiplayer.get_remote_sender_id())
	if pp and is_instance_valid(pp):
		pp.punch(clampi(arm, 0, 1))


@rpc("authority", "reliable")
func net_damage(amount: float, from: Vector3) -> void:
	if game and is_instance_valid(game):
		game.damage_player(amount, from)


func local_died() -> void:
	dead_t = RESPAWN_T
	game.hud.hurt_flash()


func _respawn() -> void:
	dead_t = -1.0
	info_l.text = ""
	game.alive = true
	game.hp = game.MAX_HP
	game.bleed_t = 0.0
	game.hud.set_hp(game.hp, game.MAX_HP)
	game.inv.enabled = true
	game.player.active = true
	game.player.global_position = game.START
	game.player.rotation.y = -PI / 2.0
	game.player.velocity = Vector3.ZERO
	game.hud.toast("Вы снова в бункере", Color(0.75, 0.85, 0.65))


## Враг у хоста: ближайший живой игрок (текущей цели — небольшая фора, чтобы не метался).
func pick_target(e) -> Object:
	var best: Object = game
	var bd := INF
	if game.alive:
		bd = e.global_position.distance_to(game.player.global_position) - (1.5 if e.tg == game else 0.0)
	for id in targets:
		var t: RemoteTarget = targets[id]
		if not t.alive or not is_instance_valid(t.player):
			continue
		var d: float = e.global_position.distance_to(t.player.global_position) - (1.5 if e.tg == t else 0.0)
		if d < bd:
			bd = d
			best = t
	return best


# ---------- враги ----------

func _send_enemies() -> void:
	var arr: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.net_puppet or not e.is_inside_tree():
			continue
		if not e.has_meta("nid"):
			e.set_meta("nid", enemy_seq)
			enemy_map[enemy_seq] = e
			enemy_seq += 1
		arr.append([e.get_meta("nid"), 0 if e.kind == "heavy" else 1, e.global_position, e.rotation.y, e.state, e.hp, e.hunter])
	rpc("es", arr)


@rpc("authority", "unreliable_ordered", "call_remote", 2)
func es(arr: Array) -> void:
	if game == null or not is_instance_valid(game):
		return
	var seen := {}
	for a in arr:
		var nid: int = a[0]
		seen[nid] = true
		var e = enemy_map.get(nid)
		if e == null or not is_instance_valid(e):
			if a[4] == "dead":
				continue
			e = EnemyScript.new()
			e.game = game
			e.kind = "heavy" if a[1] == 0 else "fast"
			e.net_puppet = true
			e.hunter = a[6]
			e.position = a[2]
			e.rotation.y = a[3]
			e.net_pos = a[2]
			e.net_rot = a[3]
			e.set_meta("nid", nid)
			game.add_child(e)
			enemy_map[nid] = e
		e.net_apply(a[2], a[3], a[4], a[5])
	for nid in enemy_map.keys():
		if not seen.has(nid):
			var e = enemy_map[nid]
			if is_instance_valid(e) and e.state != "dead":
				e.queue_free()
			enemy_map.erase(nid)


## Клиент ударил копию врага — урон считает хост.
func enemy_hit(e, dmg: float, dir: Vector3) -> void:
	if e.has_meta("nid"):
		rpc_id(1, "rq_enemy_hit", int(e.get_meta("nid")), dmg, dir)


@rpc("any_peer", "reliable")
func rq_enemy_hit(nid: int, dmg: float, dir: Vector3) -> void:
	if not hosting:
		return
	var e = enemy_map.get(nid)
	if e and is_instance_valid(e):
		e.apply_hit(clampf(dmg, 0.0, 200.0), dir)


func request_hunters(count: int) -> void:
	rpc_id(1, "rq_hunters", count)


@rpc("any_peer", "reliable")
func rq_hunters(count: int) -> void:
	if hosting and game and is_instance_valid(game):
		game._spawn_hunters(clampi(count, 1, 5))


# ---------- предметы на полу ----------

## Из game._make_pickup: свой новый предмет — разослать (в конце кадра, когда выставлены need_leave/dur).
func pickup_made(p) -> void:
	if suppress or game == null:
		return
	var nid := "%d_%d" % [multiplayer.get_unique_id(), pk_seq]
	pk_seq += 1
	p.set_meta("nid", nid)
	pickups[nid] = p
	_send_pickup.call_deferred(p)


func _send_pickup(p) -> void:
	if not is_instance_valid(p) or game == null or peer == null:
		return
	rpc("pk_spawn", String(p.get_meta("nid")), p.id, p.n, p.global_position, p.linear_velocity, p.need_leave,
		float(p.get_meta("dur", -1.0)), bool(p.get_meta("dropped", false)))


@rpc("any_peer", "reliable")
func pk_spawn(nid: String, id: String, n: int, pos: Vector3, vel: Vector3, leave: bool, dur: float, dropped: bool) -> void:
	if game == null:
		if in_game:
			early.append(pk_spawn.bind(nid, id, n, pos, vel, leave, dur, dropped))
		return
	if pickups.has(nid) or not Items.ITEMS.has(id):
		return
	suppress = true
	var p = game._make_pickup(id, n, pos, vel)
	suppress = false
	p.set_meta("nid", nid)
	p.need_leave = leave
	if dur >= 0.0:
		p.set_meta("dur", dur)
	if dropped:
		p.set_meta("dropped", true)
	pickups[nid] = p


func _has_room(id: String) -> bool:
	if id == "coin" or not Items.ITEMS.has(id):
		return true
	var mx := int(Items.ITEMS[id]["stack"])
	for s in game.inv.slots:
		if s == null or (s["id"] == id and int(s["n"]) < mx):
			return true
	return false


## Из pickup.gd перед подбором. true — сеть сама разберётся (запрос хосту / выдано), false — обычный подбор.
func take(p) -> bool:
	if game == null or not p.has_meta("nid") or not _has_room(p.id):
		return false
	var nid := String(p.get_meta("nid"))
	if hosting:
		_grant(nid, 1)
		return true
	var now := Time.get_ticks_msec()
	if now - int(p.get_meta("rq_t", -100000)) < 700:
		return true
	p.set_meta("rq_t", now)
	rpc_id(1, "rq_take", nid)
	return true


@rpc("any_peer", "reliable")
func rq_take(nid: String) -> void:
	if hosting:
		_grant(nid, multiplayer.get_remote_sender_id())


func _grant(nid: String, who: int) -> void:
	var p = pickups.get(nid)
	if p == null or not is_instance_valid(p) or p.taken:
		return   # уже взял кто-то другой
	pickups.erase(nid)
	rpc("pk_taken", nid, who)
	_on_taken(p, who)


@rpc("authority", "reliable")
func pk_taken(nid: String, who: int) -> void:
	var p = pickups.get(nid)
	pickups.erase(nid)
	if p != null and is_instance_valid(p) and not p.taken:
		_on_taken(p, who)


func _on_taken(p, who: int) -> void:
	if game == null:
		return
	if who == multiplayer.get_unique_id():
		var id: String = p.id
		var n: int = p.n
		var pos: Vector3 = p.global_position
		var left: int = game.collect(id, n, p)
		p._fly_to(game)
		if left > 0:
			var rest = game._make_pickup(id, left, pos + Vector3(0, 0.1, 0), Vector3.ZERO)
			rest.need_leave = true
	else:
		var pp = puppets.get(who)
		if pp and is_instance_valid(pp):
			p._fly_to(game, pp)
		else:
			p.queue_free()


# ---------- кувшины ----------

func _jar(nid: String):
	if game == null:
		return null
	for j in game.jars:
		if is_instance_valid(j) and j.get_meta("nid", "") == nid:
			return j
	return null


## Из jar.take_hit. Клиент: удар уходит хосту (true). Хост: бьёт сам (false).
func jar_hit(j, dir: Vector3) -> bool:
	if hosting or game == null or not j.has_meta("nid"):
		return false
	rpc_id(1, "rq_jar", String(j.get_meta("nid")), dir)
	return true


@rpc("any_peer", "reliable")
func rq_jar(nid: String, dir: Vector3) -> void:
	if not hosting:
		return
	var j = _jar(nid)
	if j and not j.broken:
		j.hp -= 1.0
		if j.hp <= 0.0:
			j._shatter(dir)


## Из jar._shatter: хост рассылает, что кувшин разбит.
func jar_broken(j, dir: Vector3) -> void:
	if hosting and j.has_meta("nid") and peer:
		rpc("jar_break", String(j.get_meta("nid")), dir)


@rpc("authority", "reliable")
func jar_break(nid: String, dir: Vector3) -> void:
	if game == null:
		if in_game:
			early.append(jar_break.bind(nid, dir))
		return
	var j = _jar(nid)
	if j and not j.broken:
		j._shatter(dir)


func jar_spawned(j) -> void:
	if not hosting or peer == null:
		return
	j.set_meta("nid", "j%d" % jar_seq)
	jar_seq += 1
	rpc("jar_new", String(j.get_meta("nid")), j.to_save())


@rpc("authority", "reliable")
func jar_new(nid: String, a: Array) -> void:
	if game == null:
		if in_game:
			early.append(jar_new.bind(nid, a))
		return
	var j = game._make_jar(Vector3(float(a[0]), float(a[1]), float(a[2])), float(a[3]),
		{"kind": str(a[4]), "size": float(a[5]), "seed": int(a[6])}, bool(a[7]))
	j.set_meta("nid", nid)


func jar_removed(j) -> void:
	if hosting and peer and j.has_meta("nid"):
		rpc("jar_del", String(j.get_meta("nid")))


@rpc("authority", "reliable")
func jar_del(nid: String) -> void:
	var j = _jar(nid)
	if j:
		game.jars.erase(j)
		j.queue_free()


# ---------- выстрелы (gun.gd) ----------
## Урон пули по врагу идёт обычным путём (enemy.take_hit → хосту). Здесь — вспышка и звук у других игроков,
## а у хоста враги рядом слышат выстрел клиента.
func shot(pos: Vector3) -> void:
	if peer and game:
		rpc("pshot", pos)


@rpc("any_peer", "unreliable", "call_remote", 1)
func pshot(pos: Vector3) -> void:
	if game == null or not is_instance_valid(game) or game.gun == null:
		return
	var a := AudioStreamPlayer3D.new()
	a.stream = game.gun.snd_shot
	a.unit_size = 12.0
	a.volume_db = 2.0
	a.pitch_scale = randf_range(0.95, 1.05)
	game.add_child(a)
	a.global_position = pos
	a.finished.connect(a.queue_free)
	a.play()
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.75, 0.4)
	l.light_energy = 5.0
	l.omni_range = 7.0
	game.add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.07)
	tw.tween_callback(l.queue_free)
	if hosting:
		game.gun._alert(pos)
