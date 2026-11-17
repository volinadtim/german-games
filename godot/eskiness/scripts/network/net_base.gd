extends Node
# Часть net.gd: константы, состояние, коды комнат и адреса (static), имя игрока.
@warning_ignore("unused_signal")
signal lobby_changed                     # игроки / состояние комнаты
@warning_ignore("unused_signal")
signal rooms_changed                     # найденные в локалке комнаты
@warning_ignore("unused_signal")
signal status(text: String, bad: bool)   # статус подключения для лобби

const PORT := 24680
const DISCOVERY_PORT := 24681
const MAX_PEERS := 3   # до 4 игроков в комнате (хост + 3): в машине 4 места (промпт 15.11 23:20)
const VERSION := 1
const CODE_ABC := "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"   # 32 знака: без 0/O и 1/I
const CFG := "user://settings.cfg"

var peer: ENetMultiplayerPeer
var port := PORT
var my_name := "Игрок"
var players := {}          # peer_id -> имя (у хоста и у клиентов)
var game_mode := 1        # режим игры (хост выбирает в лобби, ui/mode_select.gd; game_base.gd: MODE_*)
var friendly_fire := false # огонь по своим (галочка хоста в лобби, промпт 16.11 21:47); выкл — удары и пули по игрокам без урона
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
var bye := {}              # peer_id -> true: попрощался сам (вышел), а не пропал по таймауту
var host_bye := false      # клиент: хост сам закрыл комнату
## Переподключение (промпт 18.11 00:38): связь с хостом оборвалась сама (не «хост закрыл комнату») —
## клиент тихо подключается заново к тому же адресу, в лобби и прямо в игре; мир у клиента остаётся.
const REJOIN_TRIES := 12      # попыток (~3 с каждая) — около 35 с
var rejoining := false
var rejoin_t := 0.0
var rejoin_left := 0
var rejoin_game := false      # обрыв случился в игре
var last_seen := {}        # peer_id -> время (с) последнего пакета позиции — для «связь прерывается»
## Таймауты ENet. По умолчанию ENet рвёт связь уже через ~5 с без ответа: хватает подвисания Wi-Fi
## (энергосбережение телефона/роутера), сворачивания игры на телефоне или долгого кадра при загрузке.
## Теперь: не раньше 20 с тишины, наверняка — через 60 с.
const TIMEOUT_LIMIT := 64
const TIMEOUT_MIN := 20000
const TIMEOUT_MAX := 60000


static func ensure(tree: SceneTree) -> Node:
	var n := tree.root.get_node_or_null("Net")
	if n == null:
		n = (load("res://scripts/network/net.gd") as GDScript).new()
		n.name = "Net"
		tree.root.add_child(n)
	return n


static func get_net(tree: SceneTree) -> Node:
	return tree.root.get_node_or_null("Net") if tree else null


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


# ---------- совместная игра (этап 2) ----------
## Старт: хост строит мир как обычную новую игру и рассылает клиентам его расстановку (кувшины, стекло,
## вещи на полу, кучки камней) — клиент строит ту же сцену. Сейвы в сети не пишутся.
## Игроки: у каждого свой player.gd с камерой; чужие — модели (player.gd с puppet = true), 20 Гц, с интерполяцией.
## Враги — только у хоста (ИИ, урон, лут); клиенту 15 раз в секунду приходят их позиции/состояния/HP.
## Удар клиента по врагу → хосту; враг бьёт ближайшего живого игрока (урон — тому игроку по сети).
## Предметы: кто взял — решает хост (без дюпа). Кувшины бьются у всех, лут высыпает хост.
## Автомат, магазин, ящики, сейф, сундук, машина — у каждого свои (монеты и инвентарь свои).

const PlayerScript := preload("res://scripts/player/player.gd")
const EnemyScript := preload("res://scripts//enemy/enemy.gd")
const Items := preload("res://scripts/items.gd")
const PickupScript := preload("res://scripts/world/pickup.gd")
const SEND_DT := 1.0 / 20.0
const ENEMY_DT := 1.0 / 15.0
const RESPAWN_T := 10.0
const PUPPET_LAYER := 512   # слой моделей других игроков (лучи ударов и пистолета: маска 1 | 512)
const PUSH_R := 0.62        # игроки касаются, когда центры ближе (капсулы по 0.3)
const Fx := preload("res://scripts/core/fx.gd")

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
var gear_t := 0.0                 # раз в секунду — надетая одежда (net_world.gd: pgear, промпт 18.11 00:44)
var es_t := 0.0
var ui_t := 0.0
var was_punching := false
var dead_t := -1.0
var killer := ""         # кто из игроков ударил последним (для «Вас убил …»)
var killer_t := 0.0
var ui: CanvasLayer
var ping_l: Label
var ping_shown := true   # ~ переключает
var rtt := {}            # peer_id -> свой замер пинга, мс (png/png_r; у ENet старт с 500 мс и медленное сглаживание)
var png_t := 0.0
# последний адрес подключения — для «Повторить попытку» в лобби (промпт 16.11 21:56)
var last_ip := ""
var last_port := 0
var info_l: Label


## Цель врага у хоста — другой игрок: у него, как у game.gd, есть player, alive и damage_player.
class RemoteTarget:
	var player: CharacterBody3D
	var alive := true
	var peer := 0
	var net

	func damage_player(amount: float, from: Vector3) -> void:
		net.rpc_id(peer, "net_damage", amount, from)
