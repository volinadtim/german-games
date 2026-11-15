extends "res://scripts/network/net_base.gd"
# Часть net.gd: синхронизация лута на полу, кувшинов, выстрелов, толкания и PvP.


## Выйти из комнаты / закрыть её.
func leave() -> void:
	if peer and (hosting or connected):
		rpc("rq_bye")   # другие узнают, что вышли сами, а не пропала связь
		peer.host.flush()
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


func _net_reset() -> void:
	game = null
	puppets = {}
	targets = {}
	enemy_map = {}
	pickups = {}
	pending_world = {}
	early = []
	last_seen = {}
	dead_t = -1.0
	if ui and is_instance_valid(ui):
		ui.queue_free()
	ui = null


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
func pk_spawn(nid: String, id: String, n: int, pos: Vector3, vel: Vector3, leave_after: bool, dur: float, dropped: bool) -> void:
	if game == null:
		if in_game:
			early.append(pk_spawn.bind(nid, id, n, pos, vel, leave_after, dur, dropped))
		return
	if pickups.has(nid) or not Items.ITEMS.has(id):
		return
	suppress = true
	var p = game._make_pickup(id, n, pos, vel)
	suppress = false
	p.set_meta("nid", nid)
	p.need_leave = leave_after
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


# ---------- игроки друг с другом: толкание и огонь по своим ----------
## Толкание (до move_and_slide своего игрока): в другого не войти — скорость «в него» гасится,
## при перекрытии слегка расходимся, а если другой идёт на нас — нас чуть отпихивает (слабо, без рывков).
## Каждый толкает только своего игрока, поэтому у обоих выходит симметрично.
func _soft_push(p: CharacterBody3D, _delta: float) -> void:
	for id in puppets:
		var pp = puppets[id]
		if not is_instance_valid(pp) or not pp.visible:
			continue
		var d: Vector3 = p.global_position - pp.global_position
		if absf(d.y) > 1.6:
			continue
		d.y = 0.0
		var dist := d.length()
		if dist >= PUSH_R:
			continue
		var n := d / dist if dist > 0.01 else Vector3(1, 0, 0).rotated(Vector3.UP, float(id % 628) * 0.01)
		var vn := p.velocity.dot(n)
		var want := vn * 0.15 if vn < 0.0 else vn   # в другого почти не войти
		want = maxf(want, minf((PUSH_R - dist) * 5.0, 1.2))   # при перекрытии мягко расходимся
		var shove: float = -Vector3(pp.net_vel.x, 0, pp.net_vel.z).dot(n)
		want = maxf(want, shove * 0.3)   # другой идёт на нас — слабый толчок
		p.velocity += n * (want - vn)


## Попали по модели другого игрока (удар, заряженный удар, пуля) — урон ему через хоста.
func _pvp_hit(pp, dmg: float, dir: Vector3) -> void:
	if game == null or not game.alive:
		return
	game.weapon_hit()
	Fx.damage_number(pp.get_parent(), pp.global_position + Vector3(0, 2.0, 0), dmg, Color(1.0, 0.55, 0.45))
	Fx.dust_burst(pp.get_parent(), pp.global_position + Vector3(0, 1.2, 0) - dir * 0.2)
	var victim: int = pp.get_meta("peer", 0)
	var from: Vector3 = game.player.global_position
	if hosting:
		_pvp_route(victim, dmg, from, multiplayer.get_unique_id())
	else:
		rpc_id(1, "rq_pvp", victim, dmg, from)


@rpc("any_peer", "reliable")
func rq_pvp(victim: int, dmg: float, from: Vector3) -> void:
	if hosting:
		_pvp_route(victim, clampf(dmg, 0.0, 120.0), from, multiplayer.get_remote_sender_id())


func _pvp_route(victim: int, dmg: float, from: Vector3, attacker: int) -> void:
	if victim == multiplayer.get_unique_id():
		pvp_damage(dmg, from, attacker)
	elif players.has(victim):
		rpc_id(victim, "pvp_damage", dmg, from, attacker)


@rpc("authority", "reliable")
func pvp_damage(amount: float, from: Vector3, attacker: int) -> void:
	if game == null or not is_instance_valid(game) or not game.alive:
		return
	killer = String(players.get(attacker, "?"))
	killer_t = 3.0
	game.damage_player(amount, from)
