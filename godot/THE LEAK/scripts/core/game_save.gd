extends "res://scripts/core/game_items.gd"
# Часть game.gd: сохранение и загрузка.


func save_now() -> void:
	if player == null or not alive or save_slot == "":
		return
	if net:
		# сетевая игра (промпт 18.11 02:00): сейв лежит у хоста — вместе с вещами остальных игроков по их IP
		if net.is_host():
			Save.write(save_slot, host_state())
		else:
			net.send_my_save()
		return
	Save.write(save_slot, save_state())


## Сейв хоста сетевой игры: его мир и вещи + вещи остальных игроков (net_base.gd: net_saves).
func host_state() -> Dictionary:
	var d := save_state()
	d["net"] = true
	d["net_players"] = net.net_saves.duplicate(true) if net else {}
	return d


## Выход из игры по-человечески (в меню / закрыли окно): сохраняемся и убираем аварийную копию.
func save_exit() -> void:
	save_now()
	if save_slot != "" and (net == null or net.is_host()):
		Save.clear_crash(save_slot)


## Вылет игры (game.gd: NOTIFICATION_CRASH): доп. сохранение в отдельный файл, основной сейв не трогаем.
func save_crash() -> void:
	if player == null or save_slot == "":
		return
	if net and not net.is_host():
		return
	Save.write_crash(save_slot, host_state() if net else save_state())


## Режим новой/загруженной игры: сеть — от хоста, сейв — из файла, новая — выбор в меню (ui/mode_select.gd).
func _pick_mode() -> int:
	if net:
		return int(net.game_mode)
	if Engine.get_meta("eskiness_load", false) and Save.exists(Save.slot()):
		return int(Save.read(Save.slot()).get("mode", MODE_NORMAL))
	return int(Engine.get_meta("eskiness_mode", MODE_NORMAL))


func save_state() -> Dictionary:
	var bag: Array = []
	for s in inv.slots:
		bag.append(s.duplicate() if s != null else null)
	var cs: Array = []
	var chest_pos: Array = []
	for c in chests:
		chest_pos.append([c.position.x, c.position.y, c.position.z, c.rotation.y] if is_instance_valid(c) else [0.0, -100.0, 0.0, 0.0])
		cs.append([c.opened, c.broken, c.contents.duplicate(true)] if is_instance_valid(c) else [false, false, []])
	var floor_items: Array = []
	for n in get_children():
		if n is Pickup and is_instance_valid(n) and not n.is_queued_for_deletion() and not n.taken:
			floor_items.append({"id": n.id, "n": n.n, "pos": _v3(n.global_position),
				"dur": float(n.get_meta("dur", -1.0)), "dropped": bool(n.get_meta("dropped", false)),
				"manual": n.need_leave, "ttl": n.life})
	return {
		"version": 1,
		"mode": mode,
		"coins": inv.coins,
		"bag": bag,
		"bag_layout": inv.BAG_LAYOUT,
		"equip": inv.equip.duplicate(),
		"equip_dur": inv.equip_dur.duplicate(),
		"hotbar": inv.hotbar.duplicate(),
		"hp": hp,
		"bleed": bleed_t,
		"buffs": buffs.duplicate(true),
		"pos": _v3(player.global_position),
		"yaw": player.rotation.y,
		"pitch": player.head.rotation.x,
		"light_charge": flashlight.charge if flashlight else 0.0,
		"light_on": flashlight.on if flashlight else false,
		"filter": gasmask.filter_left if gasmask else 0.0,
		"filter_max": gasmask.filter_max if gasmask else 100.0,
		"tox": gasmask.tox if gasmask else 0.0,
		"chests": cs,
		"chest_pos": chest_pos,
		"tape_taken": tape != null and not tape.ready_,
		"stone_piles": stone_piles.map(func(sp): return sp.left),
		"stone_pos": stone_piles.map(func(sp): return [sp.position.x, sp.position.y, sp.position.z]),   # места кучек случайные (промпт 03:18)
		"jars": jars.filter(func(x): return is_instance_valid(x)).map(func(x): return x.to_save()),
		"safe_open": safe != null and is_instance_valid(safe) and safe.opened,
		"storage": storage.contents.duplicate(true) if storage else [],
		"safe_contents": safe.contents.duplicate(true) if safe != null and is_instance_valid(safe) else [],
		"floor": floor_items,
		"glass": glass_floor.to_save(),
		"slot_credits": slot.credits if slot else 0,
		"slot_luck": slot.luck.duplicate(true) if slot else {},
		"slot_boost": slot.boost.duplicate(true) if slot else {},
		"slot_level": slot.level if slot else 1,
		"slot_level_v3": true,   # окно 2×3 снова есть (промпт 18.11 00:39)
		"shop_bought": shop_bought.duplicate(),
		"apple_bought": apple_bought,
		"blueprints": home.to_save() if home else {},
		"moved": carry.to_save() if carry else {},
		"slot_tray": slot.tray_coins if slot else 0,
		"slot_shield": slot.shield if slot else 0,
		"slot_profit": slot.profit if slot else 0,
		"slot_capped": slot.capped if slot else false,
		"slot_bank": slot.bank if slot else 0,
		"slot_sevens": slot.sevens_hit if slot else false,
		"slot_reveal": slot.reveal_pending if slot else false,
		"play_time": play_time,
		"intro_done": intro_done,
		"intro_wake_done": intro_wake_done,
		"dummy_knife_taken": dummy_knife_taken,
		"last_chance": last_chance.used if last_chance else false,
		"shop_on": shop_on,
		"shop_cue_done": shop_cue_done,
		"village": village.to_save() if village else {},
		"cheats": _save_cheats(),
	}


func load_state(d: Dictionary) -> void:
	loading = true
	inv.coins = int(d.get("coins", 0))
	var bag: Array = d.get("bag", [])
	var eq: Dictionary = d.get("equip", {}).duplicate()
	var ed: Dictionary = d.get("equip_dur", {}).duplicate()
	# старые сейвы: противогаз был в слоте «Голова» — переезжает в «Лицо»
	if String(eq.get("head", "")) == "gasmask" and String(eq.get("face", "")) == "":
		eq["face"] = "gasmask"
		eq["head"] = ""
		if ed.has("head"):
			ed["face"] = ed["head"]
			ed.erase("head")
	# сетка (промпт 16.11 02:42): сначала снаряжение (рюкзак / карманы дают свои блоки), потом вещи.
	# Старые сейвы (10–15 ячеек 1×1): вещи стоят по старым номерам, наложившиеся крупные reflow перекладывает,
	# не влезшие — на пол у игрока (ниже, после позиции).
	inv.slots.clear()
	inv.slots.resize(inv.TOTAL)
	inv.equip_dur.clear()
	# без общей сумки (промпт 16.11 06:03): старому сейву надеваем стартовые футболку / штаны / вещмешок в пустые слоты
	var old_layout := int(d.get("bag_layout", 1)) < inv.BAG_LAYOUT
	if old_layout:
		for k in inv.START_GEAR:
			if String(eq.get(k, "")) == "" or not Items.ITEMS.has(String(eq.get(k, ""))):
				eq[k] = inv.START_GEAR[k]
				ed.erase(k)
	for k in inv.equip:
		var id: String = String(eq.get(k, ""))
		inv.equip[k] = id if Items.ITEMS.has(id) else ""
		if ed.has(k):
			inv.equip_dur[k] = float(ed[k])
		_apply_equip(k)
	# старая раскладка: все вещи раскладываются по ячейкам одежды заново (inv.migrate_bag)
	var bag_extra: Array = []
	if old_layout:
		var mg: Array = Inventory.migrate_bag(bag)
		bag = mg[0]
		bag_extra = mg[1]
	var extra_in: Array = []
	for i in inv.slots.size() + bag_extra.size():
		var s = (bag[i] if i < bag.size() else null) if i < inv.slots.size() else bag_extra[i - inv.slots.size()]
		if s is Dictionary and Items.ITEMS.has(String(s.get("id", ""))):
			var e := {"id": String(s["id"]), "n": int(s.get("n", 1))}
			if s.has("dur"):
				e["dur"] = float(s["dur"])
			if bool(s.get("r", false)):
				e["r"] = true
			# лимиты стаков (промпт 18.11 01:09): лишнее — отдельными стопками в свободные клетки, не влезло — на пол
			var mx: int = maxi(1, int(Items.ITEMS[e["id"]]["stack"]))
			while int(e["n"]) > mx:
				var part := {"id": e["id"], "n": mini(mx, int(e["n"]) - mx)}
				if e.has("dur"):
					part["dur"] = e["dur"]
				e["n"] = int(e["n"]) - int(part["n"])
				extra_in.append(part)
			if i < inv.slots.size():
				inv.slots[i] = e
			else:
				extra_in.append(e)
	var spill: Array = inv.reflow(extra_in)
	var hb: Array = d.get("hotbar", [])
	for k in 5:
		inv.hotbar[k] = String(hb[k]) if k < hb.size() and hb[k] != null else ""
	hp = clampf(float(d.get("hp", MAX_HP)), 1.0, MAX_HP)
	hud.set_hp(hp, MAX_HP, true)
	bleed_t = float(d.get("bleed", 0.0))
	buffs = {}
	var bf: Dictionary = d.get("buffs", {})
	for k in bf:
		buffs[k] = {"power": float(bf[k]["power"]), "time": float(bf[k]["time"]), "icon": String(bf[k]["icon"])}
	player.global_position = _to_v3(d.get("pos", [START.x, START.y, START.z]))
	player.rotation.y = float(d.get("yaw", -PI / 2.0))
	player.head.rotation.x = float(d.get("pitch", 0.0))
	player.velocity = Vector3.ZERO
	if flashlight:
		flashlight.charge = float(d.get("light_charge", 0.6))
		if bool(d.get("light_on", false)) and inv.count("flashlight") > 0:
			flashlight.on = true
			flashlight.light.visible = true
	if gasmask:
		gasmask.filter_left = float(d.get("filter", 0.0))
		gasmask.filter_max = float(d.get("filter_max", 100.0))
		gasmask.tox = float(d.get("tox", 0.0))
	# расстановка ящиков из сейва (старые сейвы без chest_pos — остаётся новая случайная)
	if d.has("chest_pos"):
		for c in chests:
			if is_instance_valid(c):
				c.queue_free()
		chests = []
		for a in d["chest_pos"]:
			_chest(Vector3(float(a[0]), float(a[1]), float(a[2])), float(a[3]), [])
	# кувшины и колбы из сейва: то же место, вид, размер и рисунок; разбитые — осколками
	if tape:
		tape.set_taken(bool(d.get("tape_taken", false)))
	var spl: Array = d.get("stone_piles", [])
	if d.has("stone_pos"):
		var spts: Array = []
		for a in d["stone_pos"]:
			spts.append(Vector3(float(a[0]), float(a[1]), float(a[2])))
		make_stone_piles(spts, [])
	for k in mini(spl.size(), stone_piles.size()):
		stone_piles[k].set_left(int(spl[k]))
	if d.has("jars"):
		for jr in jars:
			if is_instance_valid(jr):
				jr.queue_free()
		jars = []
		for a in d["jars"]:
			_make_jar(Vector3(float(a[0]), float(a[1]), float(a[2])), float(a[3]),
				{"kind": str(a[4]), "size": float(a[5]), "seed": int(a[6])}, bool(a[7]))
	var cs: Array = d.get("chests", [])
	for i in mini(cs.size(), chests.size()):
		chests[i].restore(bool(cs[i][0]), bool(cs[i][1]), cs[i][2] if cs[i].size() > 2 else [])
	if bool(d.get("safe_open", false)) and safe:
		safe.restore(true, false, d.get("safe_contents", []))
	# вещи на полу: убираем стартовые, раскладываем сохранённые
	for n in get_children():
		if n is Pickup:
			n.queue_free()
	for it in d.get("floor", []):
		var id: String = String(it.get("id", ""))
		if not Items.ITEMS.has(id):
			continue
		var p := _make_pickup(id, int(it.get("n", 1)), _to_v3(it.get("pos")) + Vector3(0, 0.05, 0), Vector3.ZERO)
		p.angular_velocity = Vector3.ZERO
		if float(it.get("dur", -1.0)) >= 0.0:
			p.set_meta("dur", float(it["dur"]))
		if bool(it.get("dropped", false)):
			p.set_meta("dropped", true)
		p.need_leave = bool(it.get("manual", it.get("dropped", false)))   # выброшенное игроком — только по E
		p.life = float(it.get("ttl", Pickup.LIFE))
	if storage:
		storage.contents = []
		for it in d.get("storage", []):
			var e: Array = [String(it[0]), int(it[1])]
			if it.size() > 2:
				e.append(float(it[2]))
			if it.size() > 4:   # ячейка и поворот в сетке сундука (loot_window, промпт 16.11 05:05)
				e.append_array([int(it[3]), bool(it[4])])
			storage.contents.append(e)
	if not spill.is_empty():
		# старый сейв: не влезло в ячейки одежды — в сундук дома (с пола вещи пропадают), нет сундука — на пол
		if storage:
			for sp in spill:
				var e: Array = [String(sp["id"]), int(sp.get("n", 1))]
				if sp.has("dur"):
					e.append(float(sp["dur"]))
				storage.contents.append(e)
			hud.toast("Общей сумки больше нет: вещи — в одежде и вещмешке, что не влезло — в сундуке дома", Color(0.95, 0.75, 0.45))
		else:
			drop_spilled(spill)
			hud.toast("Общей сумки больше нет: что не влезло в одежду и вещмешок — на полу рядом", Color(0.95, 0.75, 0.45))
	play_time = float(d.get("play_time", 0.0))
	dummy_knife_taken = bool(d.get("dummy_knife_taken", false))
	if last_chance:
		last_chance.used = bool(d.get("last_chance", false))
	if dummy_knife_taken and knife_dummy and is_instance_valid(knife_dummy):
		knife_dummy.remove_knife()
	# вступление: сохранились посреди него — монстрика уже нет, поэтому автомат всё равно включаем
	intro_done = true
	intro_wake_done = bool(d.get("intro_wake_done", false))
	if slot:
		slot.set_powered(true)
	shop_on = bool(d.get("shop_on", true))   # старые сейвы — магазин включён
	if shop:
		shop.set_powered(shop_on)
	shop_cue_done = bool(d.get("shop_cue_done", false))
	# сейвы до машины: сейф уже открыт, а ключа нигде нет — кладём его в сейф
	if safe and safe.opened:
		# машина уже уехала — ключ в её зажигании (car_drive.gd: from_save)
		var has_key := inv.count("car_key") > 0 or bool(d.get("village", {}).get("car", {}).get("escaped", false))
		for arr in [safe.contents, storage.contents if storage else [], d.get("floor", []).map(func(x): return [String(x.get("id", ""))])]:
			for it in arr:
				if String(it[0]) == "car_key":
					has_key = true
		if not has_key:
			safe.contents.append(["car_key", 1])
	if d.has("glass"):
		glass_floor.from_save(d["glass"])
	apple_bought = bool(d.get("apple_bought", false))
	shop_bought = Array(d.get("shop_bought", [])).map(func(x): return String(x))
	if home:
		home.from_save(d.get("blueprints", {}))
	if carry:
		carry.from_save(d.get("moved", {}))
	if slot:
		slot.credits = int(d.get("slot_credits", 0))
		slot.load_buffs(d.get("slot_luck", {}), d.get("slot_boost", {}))
		var slv := int(d.get("slot_level", 1))
		if not d.get("slot_level_v3", false) and d.get("slot_level_v2", false) and slv >= 2:
			slv += 1   # сейвы без окна 2×3 (v2): 3×3 и выше сдвигаются на 1 вверх
		slot.set_level(slv)
		slot.set_tray(int(d.get("slot_tray", 0)))
		slot.set_shield(int(d.get("slot_shield", 0)))
		slot.profit = int(d.get("slot_profit", 0))
		slot.capped = bool(d.get("slot_capped", false))
		slot.bank = int(d.get("slot_bank", 0))
		slot.sevens_hit = bool(d.get("slot_sevens", d.get("safe_open", false)))
		slot.set_reveal_pending(bool(d.get("slot_reveal", false)))
		slot.screen_msg = ""
		slot._update_screen_hint()
	if village:
		village.from_save(d.get("village", {}))
	_load_cheats(d.get("cheats", {}))
	inv.notify()
	loading = false
	if net == null:
		hud.toast("Загружено", Color(0.8, 0.85, 0.7))
func _save_cheats() -> Dictionary:
	var con := _find_console()
	var on := bool(con.get("cheats_on")) if con != null else false
	var fc = con.get("_freecam") if con != null else null
	var fc_on: bool = on and fc != null and is_instance_valid(fc)
	var d := {
		"cheats_on": on,
		"god": bool(god) if on else false,
		"noclip": bool(player.noclip) if (on and player != null) else false,
		"freecam": fc_on,
	}
	if fc_on:
		d["fc_pos"] = _v3((fc as Node3D).global_position)
		d["fc_rot"] = [con.get("_freecam_rot").x, con.get("_freecam_rot").y]
		d["fc_spd"] = float(con.get("_freecam_speed"))
	return d


func _load_cheats(c) -> void:
	if not (c is Dictionary) or c.is_empty():
		return
	var on := bool(c.get("cheats_on", false))
	var con := _find_console()
	if con != null:
		con.set("cheats_on", on)
	god = on and bool(c.get("god", false))
	if player != null:
		player.noclip = on and bool(c.get("noclip", false))
		player.velocity = Vector3.ZERO
	if on and bool(c.get("freecam", false)) and con != null and con.has_method("_enable_freecam"):
		if con._enable_freecam():
			var fc = con.get("_freecam")
			if fc != null and is_instance_valid(fc):
				(fc as Node3D).global_position = _to_v3(c.get("fc_pos", [0, 2, 0]))
				var r: Array = c.get("fc_rot", [0.0, 0.0])
				var rot_v := Vector2(float(r[0]), float(r[1]))
				con.set("_freecam_rot", rot_v)
				(fc as Node3D).rotation = Vector3(rot_v.x, rot_v.y, 0.0)
				con.set("_freecam_speed", float(c.get("fc_spd", 10.0)))


func _find_console() -> Node:
	for ch in get_children():
		if "cheats_on" in ch:
			return ch
	return null
