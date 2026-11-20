extends Node
## «Последний шанс» (промпт 20.11 11:48) — вместо 100 монет жалости: 23 монеты один раз за игру.
## Даётся, только если игрок застрял: монет меньше 8 (в сети — сумма у всех игроков), в бункере нет
## целых кувшинов, деревня не открыта (машина не уезжала), нет противогаза и/или оружия, в сумке и на
## себе нечего продать, и на локации бункера нет монет/вещей на продажу дропом (на полу, в ящиках,
## в хранилище) — чтобы нельзя было просто скинуть деньги. Хлам за 1 монету (стекло, доски, лохмотья —
## теперь продаётся всё, 20.11 11:57) вещью на продажу не считается, но его цена в сумке идёт к монетам;
## камни не считаются вовсе — их полная куча. Проверка — раз в 2 с и после крутки
## автомата (slot_machine.gd: pity). Создаётся в game.gd (game.last_chance); used — в сейве "last_chance".
## Сеть: монеты и флаг used каждого игрока приходят по net_world.gd: pcash (net.peer_cash).

const Weapons := preload("res://scripts/weapons.gd")
const SellWindow := preload("res://scripts/sell_window.gd")
const COINS := 23
const LIMIT := 8                 # дешевле пачки круток (slot_machine_base.gd: PACKS[0][1])
const CHECK_DT := 2.0
const VILLAGE_Z := 280.0         # дальше по дороге (z) — уже деревня (village_build.gd: VZ0 = 312)

var game
var used := false
var _t := CHECK_DT


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = CHECK_DT
	try_give()


## Застрял — выдать 23 монеты и «Это последний шанс!» (один раз за игру). true — выдали.
func try_give() -> bool:
	if used or not stuck():
		return false
	used = true
	game.inv.add("coin", COINS)
	game.hud.toast("Это последний шанс! +%d монет" % COINS, Color(1.0, 0.5, 0.35), true)
	game.call_deferred("save_now")
	return true


## Все условия «последнего шанса» выполнены.
func stuck() -> bool:
	if game == null or not game.alive or not game.intro_done or game.inv == null:
		return false
	if _total_coins() + _bag_junk() >= LIMIT:
		return false
	if game.car != null and is_instance_valid(game.car) and game.car.escaped:
		return false
	if _has_gasmask() and _has_weapon():
		return false
	if _bag_sellable() or _bunker_jars() or _dropped_value():
		return false
	return true


## Свои монеты + монеты других игроков (сеть). Чужие ещё не пришли / кто-то уже получил шанс — 99.
func _total_coins() -> int:
	var c: int = game.inv.coins
	if game.net == null:
		return c
	var cash: Dictionary = game.net.get("peer_cash") if game.net.get("peer_cash") != null else {}
	for id in game.net.multiplayer.get_peers():
		if not cash.has(id):
			return 99
		if bool(cash[id][1]):
			return 99
		c += int(cash[id][0])
	return c


func _has_gasmask() -> bool:
	return game.inv.count("gasmask") + game.inv.count("gasmask2") > 0


## Оружие в сумке или в руках (камень не считается — их полная куча).
func _has_weapon() -> bool:
	for id in Weapons.WEAPONS:
		if id != "stone" and game.inv.count(id) > 0:
			return true
	return false


## Вещь, которую стоит продать: монеты или дороже 1 монеты за штуку (хлам и камни — нет).
func _sellable(id: String) -> bool:
	return id == "coin" or (id != "" and id != "stone" and SellWindow.unit_price(id) >= 2)


## Сколько дадут за хлам в сумке (вещи по 1 монете, кроме камней).
func _bag_junk() -> int:
	var c := 0
	for s in game.inv.slots:
		if s == null:
			continue
		var id := String(s["id"])
		if id != "stone" and id != "coin" and not _sellable(id) and SellWindow.market(id) > 0:
			c += int(s["n"])
	return c


## В сумке или на себе есть что продать.
func _bag_sellable() -> bool:
	for s in game.inv.slots:
		if s != null and _sellable(String(s["id"])):
			return true
	for k in game.inv.equip:
		if _sellable(String(game.inv.equip[k])):
			return true
	return false


## В бункере (под землёй, y < 2) остались целые кувшины.
func _bunker_jars() -> bool:
	for j in game.jars:
		if is_instance_valid(j) and not j.broken and j.position.y <= 2.0:
			return true
	return false


## На локации бункера лежат монеты / вещи на продажу: на полу, в ящиках, в хранилище.
func _dropped_value() -> bool:
	for p in get_tree().get_nodes_in_group("pickup"):
		if is_instance_valid(p) and not p.taken and p.global_position.z < VILLAGE_Z and _sellable(String(p.id)):
			return true
	var boxes: Array = game.chests.duplicate()
	if game.storage != null:
		boxes.append(game.storage)
	for c in boxes:
		if not is_instance_valid(c) or c.locked or c.broken:
			continue
		if not c.opened and c.kind != "storage":
			return true   # нераскрытый ящик — в нём лут
		for it in c.contents:
			if _sellable(String(it[0])):
				return true
	return false
