extends Node
## Сеть машины и деревни (промпт 15.11 23:20). Узел /root/VillageNet — с одним путём у всех игроков
## (RPC Godot ищет узел по пути). Создаётся в game.setup, если игра сетевая.
##   v_escape — кто-то завёл машину ключом: кат-сцену видят все, места раздаёт тот, кто взял ключ;
##   v_seat / v_door — кто где сидит, двери; v_car / v_fuel — машину ведёт водитель, остальные повторяют;
##   v_mut* — мутанты деревни: думают у хоста, копии у остальных (как обычные враги в net_world.gd).

var game


static func ensure(g) -> Node:
	var root: Node = g.get_tree().root
	var n := root.get_node_or_null("VillageNet")
	if n == null:
		n = (load("res://scripts/village/village_net.gd") as GDScript).new()
		n.name = "VillageNet"
		root.add_child(n)
	n.game = g
	return n


func _car():
	return game.car if game and is_instance_valid(game) else null


@rpc("any_peer", "call_local", "reliable")
func v_escape(o: Array) -> void:
	var c = _car()
	if c:
		c.escape(o)


@rpc("any_peer", "call_remote", "reliable")
func v_seat(peer_id: int, idx: int) -> void:
	var c = _car()
	if c == null:
		return
	for i in 4:
		if c.seats[i] == peer_id:
			c.seats[i] = 0
	if idx >= 0 and idx < 4:
		c.seats[idx] = peer_id
	if idx != 0:
		c.net_drive = c.net_drive and c.seats[0] != 0


@rpc("any_peer", "call_remote", "reliable")
func v_door(i: int, on: bool) -> void:
	var c = _car()
	if c and i >= 0 and i < 4:
		c.open_door(i, on, false)


@rpc("any_peer", "call_remote", "unreliable_ordered", 3)
func v_car(pos: Vector3, yaw: float, spd: float, fuel: float, eng: bool) -> void:
	var c = _car()
	if c == null or c.state != "parked" or c.my_seat == 0:
		return
	c.net_pos = pos
	c.net_yaw = yaw
	c.speed = spd
	c.fuel = fuel
	if not c.net_drive:
		c.net_drive = true
	c._engine(eng)


## Удар машины (водитель решает): урон всем сидящим (промпт 18.11 00:42).
@rpc("any_peer", "call_remote", "reliable")
func v_car_hurt(dmg: float) -> void:
	var c = _car()
	if c:
		c.car_hurt(dmg)


## Багажник машины: кто закрыл окно — шлёт содержимое всем (промпт 18.11 00:47).
@rpc("any_peer", "call_remote", "reliable")
func v_trunk(items: Array) -> void:
	var c = _car()
	if c:
		c.set_trunk(items)


@rpc("any_peer", "call_remote", "reliable")
func v_fuel(f: float) -> void:
	var c = _car()
	if c:
		c.fuel = f


# ---------- мутанты ----------

@rpc("authority", "call_remote", "unreliable_ordered", 3)
func v_mut(arr: Array, full := true) -> void:
	if game and is_instance_valid(game) and game.village:
		game.village.net_mutants(arr, full)


@rpc("any_peer", "call_remote", "reliable")
func v_mut_hit(nid: int, dmg: float, dir: Vector3) -> void:
	if not multiplayer.is_server() or game == null or game.village == null:
		return
	var m = game.village.mutant_by_id(nid)
	if m:
		m.apply_hit(clampf(dmg, 0.0, 200.0), dir)


@rpc("authority", "call_remote", "reliable")
func v_mut_fx(nid: int, what: String, a: Vector3) -> void:
	if game == null or game.village == null:
		return
	var m = game.village.mutant_by_id(nid)
	if m:
		m.net_fx(what, a)
