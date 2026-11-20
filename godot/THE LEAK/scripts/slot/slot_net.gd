extends Node
## Сеть слот-автоматов (промпт 18.11 02:13). Узел /root/SlotNet — один и тот же путь у всех
## игроков (по пути RPC ищет узел), создаётся в game.setup, если игра сетевая.
## Оба автомата общие: KILLBOX (slot/slot_machine.gd) и ФОРТУНА (slot/bonus_slot.gd) —
## крутки, баффы (гаранты и шансы), уровень окна, касса (profit/bank/обчищено), лоток,
## защита от 666, джекпот, бесплатные крутки, бонус-игра и ставка одинаковы у всех.
## Личным остаётся личное: монеты за крутки платит тот, кто крутит; выигрыш ФОРТУНЫ, бонуски
## и наказание «666» достаются тому, кто дёрнул рычаг.
##   k_* — KILLBOX, f_* — ФОРТУНА; *_state хост досылает тому, кто вошёл (возврат после обрыва).

var game
var got_state := false   # клиент: состояние автоматов от хоста получено (иначе спрашиваем ещё)
var ask_t := 0.8
var tries := 6


static func ensure(g) -> Node:
	var root: Node = g.get_tree().root
	var n := root.get_node_or_null("SlotNet")
	if n == null:
		n = (load("res://scripts/slot/slot_net.gd") as GDScript).new()
		n.name = "SlotNet"
		root.add_child(n)
	n.game = g
	n.got_state = g.net == null or g.net.is_host()
	n.ask_t = 0.8
	n.tries = 6
	return n


## Клиент: пока состояние автоматов не пришло — спрашиваем хоста (он мог ещё не создать узел,
## а его собственная досылка — попасть в момент, когда у нас ещё нет мира). Промпт 18.11 02:10.
func _process(delta: float) -> void:
	if got_state or tries <= 0 or _killbox() == null:
		return
	ask_t -= delta
	if ask_t > 0.0:
		return
	ask_t = 1.5
	tries -= 1
	rpc_id(1, "k_rq_state")


@rpc("any_peer", "call_remote", "reliable")
func k_rq_state() -> void:
	if multiplayer.is_server():
		_send_state(multiplayer.get_remote_sender_id())


func _ready() -> void:
	if not multiplayer.peer_connected.is_connected(_peer_joined):
		multiplayer.peer_connected.connect(_peer_joined)


## Игрок вошёл (или вернулся после обрыва) — хост досылает ему состояние автоматов.
func _peer_joined(id: int) -> void:
	if not multiplayer.is_server():
		return
	get_tree().create_timer(3.0).timeout.connect(func() -> void: _send_state(id))


func _send_state(id: int) -> void:
	if not multiplayer.is_server() or not multiplayer.get_peers().has(id):
		return
	var k = _killbox()
	if k:
		rpc_id(id, "k_state", k.net_state_dict())
	var f = _fortune()
	if f:
		rpc_id(id, "f_state", f.net_state_dict())


func _killbox():
	if game == null or not is_instance_valid(game):
		return null
	return game.slot


func _fortune():
	if game == null or not is_instance_valid(game) or game.village == null:
		return null
	return game.village.bonus_slot


# ---------- KILLBOX ----------

@rpc("any_peer", "call_remote", "reliable")
func k_spin(st: Array, sp: Array, strk: int) -> void:
	var k = _killbox()
	if k:
		k.net_spin(st, sp, strk)


@rpc("any_peer", "call_remote", "reliable")
func k_pay(n: int, price: int) -> void:
	var k = _killbox()
	if k:
		k.net_pay(clampi(n, 0, 99), clampi(price, 0, 9999))


@rpc("any_peer", "call_remote", "reliable")
func k_luck(sym: String, mult: int) -> void:
	var k = _killbox()
	if k:
		k.add_luck(sym, mult, false)


@rpc("any_peer", "call_remote", "reliable")
func k_boost(sym: String) -> void:
	var k = _killbox()
	if k:
		k.add_boost(sym, false)


@rpc("any_peer", "call_remote", "reliable")
func k_level(lv: int) -> void:
	var k = _killbox()
	if k:
		k.net_level(lv)


@rpc("any_peer", "call_remote", "reliable")
func k_tray(n: int) -> void:
	var k = _killbox()
	if k:
		k.net_tray(maxi(n, 0))


@rpc("any_peer", "call_remote", "reliable")
func k_shield(n: int) -> void:
	var k = _killbox()
	if k:
		k.net_shield(n)


## Монстрика из вступления добил любой игрок — KILLBOX включается у всех (промпт 18.11 02:10).
@rpc("any_peer", "call_remote", "reliable")
func k_power(on: bool) -> void:
	var k = _killbox()
	if k:
		k.net_power_apply(on)


@rpc("authority", "call_remote", "reliable")
func k_state(d: Dictionary) -> void:
	got_state = true
	var k = _killbox()
	if k:
		k.net_state(d)


# ---------- ФОРТУНА ----------

@rpc("any_peer", "call_remote", "reliable")
func f_spin(res: Array, free_used: bool) -> void:
	var f = _fortune()
	if f and res.size() == 9:   # CASHY BOX — поле 3×3 (промпт 20.11 11:51)
		f.net_spin(res, free_used)


## Бонус-игру CASHY BOX купили в красном магазине (промпт 20.11 11:53).
@rpc("any_peer", "call_remote", "reliable")
func f_buy() -> void:
	var f = _fortune()
	if f:
		f.net_bonus_buy()


## Гарант символа CASHY BOX купили в красном магазине (промпт 20.11 18:07).
@rpc("any_peer", "call_remote", "reliable")
func f_guar(sym: String) -> void:
	var f = _fortune()
	if f:
		f.net_guar(sym)


@rpc("any_peer", "call_remote", "reliable")
func f_bet(b: int) -> void:
	var f = _fortune()
	if f:
		f.set_bet(b)


@rpc("authority", "call_remote", "reliable")
func f_state(d: Dictionary) -> void:
	var f = _fortune()
	if f:
		f.net_state(d)
