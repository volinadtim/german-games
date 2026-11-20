extends "res://scripts/network/net_objects.gd"
# Часть net.gd: игра по сети — старт, мир, копии игроков, враги.


## Пинг до хоста (клиент) или самый большой до клиентов (хост), мс. -1 — нет связи.
func ping_ms() -> int:
	if peer == null:
		return -1
	if hosting:
		var m := -1
		for id in players:
			if id == 1:
				continue
			var v := _rtt_of(id)
			if v >= 0:
				m = maxi(m, v)
		return m
	return _rtt_of(1)


## Пинг по окну замеров — минимум из них (промпт 18.11 02:10). Метка идёт через игровой кадр,
## поэтому в каждый отдельный замер подмешана просадка кадров у обоих; минимум её отсекает.
func _rtt_of(id: int) -> int:
	var w: Array = rtt.get(id, [])
	if w.is_empty():
		return -1
	var m: float = w[0]
	for v in w:
		m = minf(m, float(v))
	return int(m)


## Свой замер пинга (промпт 16.11 22:04): метка времени туда-обратно; первый замер — сразу.
func _ping_tick(delta: float) -> void:
	png_t -= delta
	if png_t > 0.0 or peer == null:
		return
	png_t = 0.4
	if hosting:
		rpc("png", Time.get_ticks_msec())
	else:
		rpc_id(1, "png", Time.get_ticks_msec())


@rpc("any_peer", "unreliable", "call_remote")
func png(t: int) -> void:
	rpc_id(multiplayer.get_remote_sender_id(), "png_r", t)


@rpc("any_peer", "unreliable", "call_remote")
func png_r(t: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	var ms := float(maxi(Time.get_ticks_msec() - t, 0))
	var w: Array = rtt.get(id, [])
	w.append(ms)
	while w.size() > PNG_WINDOW:
		w.pop_front()
	rtt[id] = w


func _peer_joined(_id: int) -> void:
	pass


func _peer_left(id: int, nm: String, lost := false) -> void:
	rtt.erase(id)
	if puppets.has(id):
		if is_instance_valid(puppets[id]):
			puppets[id].queue_free()
		puppets.erase(id)
	targets.erase(id)
	if game and is_instance_valid(game):
		game.hud.toast(("%s отключился: пропала связь" if lost else "%s вышел из игры") % nm, Color(0.85, 0.7, 0.5))


func _host_lost_in_game(g) -> void:
	last_msg = "Выкинуло из игры: " + last_msg if last_msg != "" else "Хост отключился — игра закончена"
	_net_reset()
	if g and is_instance_valid(g):
		g.to_main_menu()


## «Начать» у хоста.
func start_game() -> void:
	if not hosting or in_game:
		return
	in_game = true
	peer.refuse_new_connections = false   # в идущую игру можно дозагрузиться и вернуться после вылета
	# сейв сетевой игры лежит у хоста (промпт 18.11 02:00): продолжаем выбранный или начинаем новый
	if save_load and Save.exists(save_id):
		Engine.set_meta("eskiness_slot", save_id)
		Engine.set_meta("eskiness_load", true)
		Engine.set_meta("eskiness_crash", save_crash_sel)
	else:
		Engine.set_meta("eskiness_slot", Save.new_id())
		Engine.set_meta("eskiness_load", false)
		Engine.set_meta("eskiness_crash", false)
		net_saves = {}   # новая игра: даже у того же хоста все начинают с начала
	Engine.set_meta("eskiness_mode", game_mode)
	Save.set_last(String(Engine.get_meta("eskiness_slot", "")))
	lobby_changed.emit()
	get_tree().current_scene._start_game()


## Старт у клиента: мир от хоста, mine — его вещи из сейва хоста (по IP), late — игра уже идёт.
@rpc("authority", "reliable")
func net_start(world: Dictionary, pl: Dictionary, mine: Dictionary, late: bool) -> void:
	players = pl
	pending_world = world
	pending_mine = mine
	skip_intro = late or not mine.is_empty()   # вступление только тому, кто начинает с начала вместе со всеми
	in_game = true
	lobby_changed.emit()
	get_tree().current_scene._start_game()


## Из game.setup (вместо загрузки сейва у клиента; у хоста — после загрузки его сейва).
func on_game_setup(g) -> void:
	game = g
	_make_ui()
	var keep_pos := false
	if hosting:
		keep_pos = g.from_save   # хост продолжил сейв — стоит там, где сохранился
		var w := _world_state(g)
		for id in players:
			if id != 1:
				rpc_id(id, "net_start", w, players, _saved_for(id), false)
	else:
		keep_pos = not pending_mine.is_empty()
		_apply_world(g, pending_world, pending_mine)
		if keep_pos:
			g.from_save = true
		pending_world = {}
		pending_mine = {}
	var ids: Array = players.keys()
	ids.sort()
	var k := maxi(ids.find(multiplayer.get_unique_id()), 0)
	if not keep_pos:
		g.player.global_position = g.START + Vector3(0.9 * k, 0, 0)
	for id in ids:
		if id != multiplayer.get_unique_id():
			_make_puppet(id)
	g.player.net_push = _soft_push
	g.hud.toast("Сетевая игра: %d игр." % ids.size(), Color(0.75, 0.85, 0.65))
	for c in early:
		c.call()
	early = []


func _world_state(g) -> Dictionary:
	var d: Dictionary = g.save_state()
	var w := {}
	for key in ["chest_pos", "chests", "jars", "glass", "stone_piles", "stone_pos", "floor"]:
		w[key] = d[key]
	# номера уже выданные (кто-то дозагружается в идущую игру) не меняем — иначе у старых клиентов всё разъедется
	var jids: Array = []
	for j in g.jars:
		if is_instance_valid(j):
			if not j.has_meta("nid"):
				j.set_meta("nid", "j%d" % jar_seq)
				jar_seq += 1
			jids.append(j.get_meta("nid"))
	w["jar_ids"] = jids
	var fids: Array = []
	var k := 0
	for n in _floor_pickups(g):
		if not n.has_meta("nid"):
			n.set_meta("nid", "w%d" % k)
			k += 1
		var nid: String = String(n.get_meta("nid"))
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


## Клиент строит мир хоста; mine — его вещи с прошлой сессии у этого хоста (или {} — новая игра).
func _apply_world(g, w: Dictionary, mine := {}) -> void:
	if w.is_empty() and mine.is_empty():
		return
	var d: Dictionary = g.save_state()   # свой игрок (инвентарь, здоровье) — свой
	for key in mine:
		if not key in WORLD_KEYS:
			d[key] = mine[key]
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


## Копии игроков — по списку от хоста: вернувшийся после обрыва пришёл с новым id.
func sync_puppets() -> void:
	if game == null or not is_instance_valid(game):
		return
	var me := multiplayer.get_unique_id()
	for id in players:
		if id != me and not puppets.has(id):
			_make_puppet(id)
	for id in puppets.keys():
		if not players.has(id):
			if is_instance_valid(puppets[id]):
				puppets[id].queue_free()
			puppets.erase(id)
			targets.erase(id)


## Имена над головами — по текущему списку игроков (имя могли сменить / прийти позже).
func refresh_nicks() -> void:
	for id in puppets:
		var pp = puppets[id]
		if is_instance_valid(pp) and pp.has_meta("nick"):
			(pp.get_meta("nick") as Label3D).text = String(players.get(id, "?"))


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
	pp.collision_layer = PUPPET_LAYER   # видят только удары и пули игроков (огонь по своим); враги и свой игрок — нет
	pp.collision_mask = 0
	pp.set_meta("peer", id)
	pp.add_to_group("allies")
	pp.net_hit = _pvp_hit
	var lb := Label3D.new()
	lb.text = String(players.get(id, "?"))
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.pixel_size = 0.0035
	lb.font_size = 44
	lb.outline_size = 10
	lb.modulate = Color(0.95, 0.9, 0.8)
	lb.position.y = 1.9   # чуть над макушкой (промпт 16.11 22:04)
	lb.no_depth_test = true          # ник над головой виден и из-за угла / в темноте (промпт 16.11 21:47)
	lb.render_priority = 10
	lb.shaded = false
	pp.add_child(lb)
	pp.set_meta("nick", lb)
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
	var online := hosting or connected   # клиент переподключается — ничего не шлём
	if online:
		_ping_tick(delta)
	send_t -= delta
	if send_t <= 0.0 and p and peer and online:
		send_t = SEND_DT
		var flags := (1 if p.fists else 0) | (2 if p.crouched else 0) | (4 if game.alive else 0) \
				| (8 if p.gun_mode == 1 else 0) | (16 if p.gun_mode == 2 else 0) | (32 if p.throw_aim else 0) | (64 if p.dying else 0) | (128 if p.waking else 0)   # 128 — просыпается во вступлении; позы с пистолетом; 64 — лежит (player_death.gd)
		rpc("ps", p.global_position, p.rotation.y, p.head.rotation.x, p.velocity, flags, p.weapon_ids[0], p.weapon_ids[1])
	gear_t -= delta
	if gear_t <= 0.0 and p and peer and online and game.get("inv") != null:
		gear_t = 1.0
		var eq := {}
		for k in ["head", "body", "legs", "feet", "hands", "back"]:
			eq[k] = String(game.inv.equip.get(k, ""))
		rpc("pgear", eq)
		var lc = game.get("last_chance")
		rpc("pcash", int(game.inv.coins), lc != null and bool(lc.used))
	if p and p.punching and not was_punching and peer and online:
		rpc("pev", p.last_arm)
	was_punching = p != null and p.punching
	if hosting:
		es_t -= delta
		if es_t <= 0.0:
			es_t = ENEMY_DT
			_send_enemies()
	if not hosting and connected:
		send_my_save()   # свой сейв хосту (внутри — не чаще SAVE_SEND_DT)
	if killer_t > 0.0:
		killer_t -= delta
		if killer_t <= 0.0:
			killer = ""
	if dead_t > 0.0:
		dead_t -= delta
		info_l.text = "Вы погибли. Возрождение через %d с" % int(ceil(dead_t))
		if dead_t <= 0.0:
			_respawn()
	ui_t -= delta
	if ui_t <= 0.0:
		ui_t = 0.5
		var pm := ping_ms()
		var txt := ("пинг %d мс" % pm if pm >= 0 else "пинг —") + "  ·  игроков %d" % players.size()
		if rejoining:
			txt += "\nпереподключение к хосту…"
		var now := Time.get_ticks_msec() / 1000.0
		for id in last_seen:
			var gap: float = now - float(last_seen[id])
			if gap > 2.0:
				txt += "
нет связи с %s %d с…" % [String(players.get(id, "?")), int(gap)]
		ping_l.text = txt


## Чат (ui/chat.gd): сообщение всем остальным, ник — из players.
func chat_send(text: String) -> void:
	if peer:
		rpc("chat_msg", text.substr(0, 200))


@rpc("any_peer", "reliable", "call_remote")
func chat_msg(text: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if game and game.get("chat"):
		game.chat.add_msg(String(players.get(id, "Игрок")), text.substr(0, 200))


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and InputMap.has_action("toggle_ping") and e.is_action_pressed("toggle_ping"):
		ping_shown = not ping_shown
		if ping_l and is_instance_valid(ping_l):
			ping_l.visible = ping_shown


func _make_ui() -> void:
	if ui and is_instance_valid(ui):
		ui.queue_free()
	ui = CanvasLayer.new()
	ui.layer = 4
	add_child(ui)
	ping_l = Label.new()   # левый верхний угол, мелко и зелёным; ~ — показать/скрыть
	ping_l.offset_left = 8
	ping_l.offset_top = 4
	ping_l.add_theme_font_size_override("font_size", 12)
	ping_l.add_theme_color_override("font_color", Color(0.35, 1.0, 0.4, 0.9))
	ping_l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	ping_l.add_theme_constant_override("outline_size", 3)
	ping_l.visible = ping_shown
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

## Монеты другого игрока и получил ли он «последний шанс» (systems/last_chance.gd, раз в секунду).
@rpc("any_peer", "unreliable", "call_remote")
func pcash(coins: int, used: bool) -> void:
	peer_cash[multiplayer.get_remote_sender_id()] = [coins, used]


## Одежда другого игрока — видна на его модели (промпт 18.11 00:44).
@rpc("any_peer", "unreliable", "call_remote")
func pgear(eq: Dictionary) -> void:
	var pp = puppets.get(multiplayer.get_remote_sender_id())
	if pp != null and is_instance_valid(pp) and pp.has_method("set_outfit"):
		pp.set_outfit(eq)


@rpc("any_peer", "unreliable_ordered", "call_remote", 1)
func ps(pos: Vector3, yaw: float, pitch: float, vel: Vector3, flags: int, w0: String, w1: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	last_seen[id] = Time.get_ticks_msec() / 1000.0
	var pp = puppets.get(id)
	if pp == null or not is_instance_valid(pp):
		return
	pp.net_pos = pos
	pp.net_yaw = yaw
	pp.net_pitch = pitch
	pp.net_vel = vel
	pp.net_sprint = Vector2(vel.x, vel.z).length() > PlayerScript.WALK + 0.4
	pp.net_crouch = flags & 2 != 0
	pp.gun_mode = 2 if flags & 16 != 0 else (1 if flags & 8 != 0 else 0)
	pp.throw_aim = flags & 32 != 0
	var f := flags & 1 != 0
	if f != pp.fists and not pp.punching:
		pp.toggle_fists()
	var alive := flags & 4 != 0
	var down := flags & 64 != 0   # упал — тело лежит, а не пропадает (промпт 03:06)
	pp.visible = alive or down
	pp.set_meta("alive", alive)
	if down and not pp.dying:
		pp.start_death()
	elif not down and pp.dying:
		pp.end_death()
	var wake := flags & 128 != 0   # вступление: лежит → встаёт (player_death.gd)
	if wake and not pp.waking:
		pp.start_wake()
	elif not wake and pp.waking:
		pp.end_wake()
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
		killer = ""
		game.damage_player(amount, from)


func local_died() -> void:
	if game.revive and game.revive.can_be_revived():
		game.revive.set_downed()   # лежим, пока не поднимет союзник (revive.gd)
	else:
		dead_t = RESPAWN_T
	if killer != "":
		game.hud.toast("Вас убил %s" % killer, Color(1.0, 0.55, 0.45))
	game.hud.hurt_flash()


func _respawn() -> void:
	dead_t = -1.0
	game.player.end_death()
	if game.revive:
		game.revive.on_respawn()
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


## Союзник поднял нас медициной (revive.gd): amount — сколько здоровья.
@rpc("any_peer", "reliable")
func net_revive(amount: float) -> void:
	if game and is_instance_valid(game) and game.revive:
		game.revive.revived(clampf(amount, 1.0, 100.0), String(players.get(multiplayer.get_remote_sender_id(), "союзник")))


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

## Есть ли игрок (свой или чужая кукла) ближе r к точке — далёких врагов шлём реже (промпт 18.11 02:10).
func near_player(pos: Vector3, r: float) -> bool:
	if game == null or not is_instance_valid(game):
		return true
	var r2 := r * r
	if is_instance_valid(game.player) and game.player.global_position.distance_squared_to(pos) < r2:
		return true
	for id in puppets:
		var pp = puppets[id]
		if is_instance_valid(pp) and (pp as Node3D).global_position.distance_squared_to(pos) < r2:
			return true
	return false


## Хост → всем: состояние врагов. Далёких (никого ближе NET_FAR) гоняем только в полной посылке,
## каждой NET_FULL-й — пока все на поляне, трафик деревни не идёт, и наоборот (промпт 18.11 02:10).
func _send_enemies() -> void:
	es_n += 1
	var full := es_n % NET_FULL == 0
	var arr: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.net_puppet or not e.is_inside_tree():
			continue
		if not e.has_meta("nid"):
			e.set_meta("nid", enemy_seq)
			enemy_map[enemy_seq] = e
			enemy_seq += 1
		if not full and not near_player(e.global_position, NET_FAR):
			continue
		arr.append([e.get_meta("nid"), 0 if e.kind == "heavy" else 1, e.global_position, e.rotation.y, e.state, e.hp, e.hunter])
	rpc("es", arr, full)


@rpc("authority", "unreliable_ordered", "call_remote", 2)
func es(arr: Array, full := true) -> void:
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
	if not full:
		return   # неполная посылка (только те, кто рядом с игроками) — лишние копии не убираем
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

