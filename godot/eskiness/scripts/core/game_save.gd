extends "res://scripts/core/game_items.gd"
# Часть game.gd: сохранение и загрузка.


func save_now() -> void:
	if net:
		return   # сетевая игра в обычные слоты не сохраняется
	if player == null or not alive:
		return
	Save.write(save_slot, save_state())


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
		"coins": inv.coins,
		"bag": bag,
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
		"tox": gasmask.tox if gasmask else 0.0,
		"chests": cs,
		"chest_pos": chest_pos,
		"tape_taken": tape != null and not tape.ready_,
		"stone_piles": stone_piles.map(func(sp): return sp.left),
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
		"shop_bought": shop_bought.duplicate(),
		"blueprints": home.to_save() if home else {},
		"moved": carry.to_save() if carry else {},
		"slot_tray": slot.tray_coins if slot else 0,
		"slot_shield": slot.shield if slot else 0,
		"slot_reveal": slot.reveal_pending if slot else false,
		"play_time": play_time,
		"village": village.to_save() if village else {},
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
	# рюкзак надет — сумка сразу шире, чтобы загрузились вещи из его ячеек
	var back_id := String(eq.get("back", ""))
	inv.set_capacity(inv.BAG + (int(Items.ITEMS[back_id].get("bag", 0)) if Items.ITEMS.has(back_id) else 0))
	for i in inv.slots.size():
		var s = bag[i] if i < bag.size() else null
		if s is Dictionary and Items.ITEMS.has(String(s.get("id", ""))):
			var e := {"id": String(s["id"]), "n": int(s.get("n", 1))}
			if s.has("dur"):
				e["dur"] = float(s["dur"])
			inv.slots[i] = e
		else:
			inv.slots[i] = null
	inv.equip_dur.clear()
	for k in inv.equip:
		var id: String = String(eq.get(k, ""))
		inv.equip[k] = id if Items.ITEMS.has(id) else ""
		if ed.has(k):
			inv.equip_dur[k] = float(ed[k])
		_apply_equip(k)
	var hb: Array = d.get("hotbar", [])
	for k in 5:
		inv.hotbar[k] = String(hb[k]) if k < hb.size() and hb[k] != null else ""
	hp = clampf(float(d.get("hp", MAX_HP)), 1.0, MAX_HP)
	hud.set_hp(hp, MAX_HP)
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
			storage.contents.append(e)
	play_time = float(d.get("play_time", 0.0))
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
	shop_bought = Array(d.get("shop_bought", [])).map(func(x): return String(x))
	if home:
		home.from_save(d.get("blueprints", {}))
	if carry:
		carry.from_save(d.get("moved", {}))
	if slot:
		slot.credits = int(d.get("slot_credits", 0))
		slot.load_buffs(d.get("slot_luck", {}), d.get("slot_boost", {}))
		slot.set_level(int(d.get("slot_level", 1)))
		slot.set_tray(int(d.get("slot_tray", 0)))
		slot.set_shield(int(d.get("slot_shield", 0)))
		slot.set_reveal_pending(bool(d.get("slot_reveal", false)))
		slot.screen.text = ""
		slot._update_screen_hint()
	if village:
		village.from_save(d.get("village", {}))
	inv.notify()
	loading = false
	if net == null:
		hud.toast("Загружено: слот %d" % save_slot, Color(0.8, 0.85, 0.7))
