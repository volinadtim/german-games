extends "res://scripts/core/game_world.gd"
# Часть game.gd: здоровье, баффы, предметы, экипировка, износ, ремонт, крафт, выброс и подбор.


# ---------- прочность (промпт 21:46) ----------

## Попадание по врагу/ящику/кувшину (не манекену): изнашивается оружие в бьющей руке (player.last_arm).
func weapon_hit() -> void:
	if player == null or player.last_arm < 0:
		return
	_wear("left" if player.last_arm == 0 else "right", 1.0)


## Снять прочность с надетой вещи; на нуле вещь ломается и пропадает.
func _wear(slot_: String, amount: float) -> void:
	var id: String = inv.equip[slot_]
	if id == "" or Items.max_dur(id) <= 0.0 or Items.ITEMS[id].has("rounds"):
		return   # у пистолета «прочность» — патроны, ударом рукоятью не тратятся
	var d: float = float(inv.equip_dur.get(slot_, Items.max_dur(id))) - amount
	inv.equip_dur[slot_] = d
	if d <= 0.0:
		inv.equip[slot_] = ""
		inv.equip_dur.erase(slot_)
		_apply_equip(slot_)
		hud.toast("Сломано: %s" % Items.item_name(id) if id != "boots" else "Сапоги развалились", Color(1.0, 0.5, 0.35))
		play_ui("thud", -10.0, 1.6)
		inv.notify()
	elif inv.open:
		inv._refresh()


## Бинт или аптечка останавливают кровотечение. true — было что останавливать.
func stop_bleeding() -> bool:
	if bleed_t <= 0.0:
		return false
	bleed_t = 0.0
	hud.toast("Кровотечение остановлено", Color(0.7, 0.9, 0.6))
	return true


func add_buff(id: String) -> void:
	var def: Dictionary = Items.ITEMS[id]
	var kind: String = def["buff"]
	var cur: Dictionary = buffs.get(kind, {"power": 0.0, "time": 0.0, "icon": id})
	var stronger: bool = float(def["power"]) >= float(cur["power"])
	buffs[kind] = {
		"power": maxf(cur["power"], def["power"]),
		"time": maxf(cur["time"], def["time"]),
		"icon": id if stronger else cur["icon"],
	}
	hud.buffs = buffs


func buff_mult(kind: String) -> float:
	var gear := 1.0 + gear_sum("speed") if kind == "speed" else 1.0
	if not buffs.has(kind):
		return gear
	var p: float = buffs[kind]["power"]
	return (1.0 + p) * gear if kind == "speed" else 1.0 - p


## Сумма свойства по надетой одежде (armor — доля защиты, speed — прибавка скорости).
func gear_sum(prop: String) -> float:
	var t := 0.0
	for k in inv.equip:
		var id: String = inv.equip[k]
		if id != "":
			t += float(Items.ITEMS[id].get(prop, 0.0))
	return t


func gear_armor() -> float:
	return minf(gear_sum("armor"), 0.6)


func _tick_buffs(delta: float) -> void:
	for k in buffs.keys():
		buffs[k]["time"] -= delta
		if buffs[k]["time"] <= 0.0:
			buffs.erase(k)
			hud.toast("Бафф закончился: %s" % ("скорость" if k == "speed" else "защита"), Color(0.75, 0.72, 0.65))
	hud.buffs = buffs


# ---------- здоровье ----------

func damage_player(amount: float, from: Vector3) -> void:
	if not alive:
		return
	# щит в левой руке: половина ударов блокируется полностью
	if inv.equip["left"] == "shield" and randf() < 0.5:
		hud.block_flash()
		_wear("left", 1.0)
		play_ui("clunk", -6.0, 0.8)
		var bpush := player.global_position - from
		bpush.y = 0.0
		player.velocity += bpush.normalized() * 2.0
		Fx.popup_text(self, player.global_position + Vector3(0, 1.4, 0) - player.global_transform.basis.z * 0.8, "БЛОК", Color(0.6, 0.85, 1.0))
		return
	amount *= buff_mult("resist") * (1.0 - gear_armor())
	# одежда изнашивается только от вражеских ударов, камней, прыжков (чинит ремкомплект одежды)
	for sl in ["head", "body", "legs", "feet"]:
		_wear(sl, 1.0)
	hp = maxf(hp - amount, 0.0)
	hud.set_hp(hp, MAX_HP)
	hud.hurt_flash()
	var push := player.global_position - from
	push.y = 0.0
	player.velocity += push.normalized() * 4.5 + Vector3(0, 2.0, 0)
	player.aim_punch(amount)   # толчок камеры и прицела (player_combat.gd)
	play_ui("hurt", -9.0, 0.75)
	if hp <= 0.0:
		_die()


## Тихая потеря здоровья (отравление) — без отброса и вспышки.
func drain_hp(amount: float) -> void:
	if not alive:
		return
	hp = maxf(hp - amount, 0.0)
	hud.set_hp(hp, MAX_HP)
	if hp <= 0.0:
		_die()


func heal(amount: float) -> void:
	hp = minf(hp + amount, MAX_HP)
	hud.set_hp(hp, MAX_HP)


func _die() -> void:
	alive = false
	player.active = false
	inv.close()
	inv.enabled = false
	player.start_death()   # падение, оружие из рук (player_death.gd)
	if revive:
		revive.on_died()   # виньет, глухой звук; в одиночке экран смерти — после падения
	if net:
		net.local_died()   # в сети — лежит, ждёт союзника (revive.gd); лежат все — возрождение у старта
		return
	if revive == null:
		hud.show_death(true)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _quick_heal() -> void:
	if revive and revive.try_revive_with(""):   # Q на лежащего союзника — поднять
		return
	if bleed_t > 0.0:
		for bid in ["bandage", "medkit"]:
			var bi := inv.bag_index(bid)
			if bi >= 0:
				use_item(bi)
				return
	if hp >= MAX_HP:
		hud.toast("Здоровье и так полное")
		return
	# самое маленькое лечение, которого хватает; иначе самое большое
	var need := MAX_HP - hp
	var best := ""
	var best_v := INF
	var biggest := ""
	var biggest_v := 0.0
	for id in Items.ITEMS:
		if not Items.ITEMS[id].has("heal"):
			continue
		if inv.count(id) == 0:
			continue
		var v: float = Items.ITEMS[id]["heal"]
		if v >= need and v < best_v:
			best = id
			best_v = v
		if v > biggest_v:
			biggest = id
			biggest_v = v
	var pick := best if best != "" else biggest
	if pick == "":
		hud.toast("Нечем лечиться")
		return
	if revive:
		revive.heal_channel(pick)
		return
	inv.remove(pick, 1)
	heal(Items.ITEMS[pick]["heal"])
	hud.toast("%s: +%d здоровья" % [Items.item_name(pick), int(Items.ITEMS[pick]["heal"])], Color(0.7, 0.9, 0.6))
	play_ui("pickup", -12.0, 0.8)


# ---------- предметы ----------

func use_item(idx: int) -> void:
	var s = inv.slots[idx]
	if s == null:
		return
	var id: String = s["id"]
	var def: Dictionary = Items.ITEMS[id]
	if def.has("repair"):
		repair(idx, _most_worn(String(def["repair"])))
	elif def.has("buff"):
		if inv.equip["face"] == "gasmask":   # еда и питьё — не через противогаз (промпт 16.11 21:46)
			hud.toast("В противогазе не поесть и не попить — сними его (G)", Color(0.95, 0.7, 0.45))
			return
		inv.take_at(idx, 1)
		add_buff(id)
		var what := "−%d%% урона" % int(float(def["power"]) * 100) if def["buff"] == "resist" else "+%d%% скорости" % int(float(def["power"]) * 100)
		hud.toast("%s: %s на %d с" % [def["name"], what, int(def["time"])], Color(0.8, 0.9, 0.6))
		play_ui("pickup", -12.0, 0.9)
	elif def.has("heal"):
		if revive and revive.try_revive_with(id):   # смотрим на лежащего союзника — поднимаем его
			return
		var stops := id in ["bandage", "medkit"] and bleed_t > 0.0
		if hp >= MAX_HP and not stops:
			hud.toast("Здоровье и так полное")
			return
		if revive:
			revive.heal_channel(id)   # не мгновенно: полоска, прерывается движением и уроном
			return
		inv.take_at(idx, 1)
		heal(def["heal"])
		if stops:
			stop_bleeding()
		hud.toast("%s: +%d здоровья" % [def["name"], int(def["heal"])], Color(0.7, 0.9, 0.6))
		play_ui("pickup", -12.0, 0.8)
	elif id == "broom":
		var gi := glass_floor.nearest(player.global_position, 1.8)
		if gi < 0:
			hud.toast("Рядом нет стекла")
		else:
			var c: Vector3 = glass_floor.spots[gi][0]
			glass_floor.sweep(gi)
			Fx.dust_burst(self, c + Vector3(0, 0.1, 0), Color(0.42, 0.4, 0.37), 12)
			play_at("creak", c, -18.0, 2.2)
			hud.toast("Стекло выметено", Color(0.8, 0.85, 0.7))
	elif id == "flashlight":
		if flashlight:
			flashlight.toggle()
	elif id == "battery":
		if flashlight == null:
			return
		if flashlight.charge >= 0.99:
			hud.toast("Фонарик и так заряжен")
			return
		inv.take_at(idx, 1)
		flashlight.recharge()
		hud.toast("Фонарик заряжен", Color(0.9, 0.85, 0.55))
		play_ui("click", -12.0)
	elif id == "pistol":
		# второй пистолет — в свободную левую (стреляют по очереди, gun.gd)
		equip(idx, "left" if inv.equip["right"] == "pistol" and inv.equip["left"] == "" else "right")
	elif id == "mag":
		gun.fill_mag(idx)
	elif Items.equip_slot(id) == "hand":
		# оружие: в свободную руку (сначала правая), обе заняты — меняем правую
		var hand := "right" if inv.equip["right"] == "" or inv.equip["left"] != "" else "left"
		equip(idx, hand)
	elif Items.equip_slot(id) != "":
		equip(idx, Items.equip_slot(id))
	elif id == "filter":
		hud.toast("Фильтр ставится сам")
	elif id == "coin":
		pass
	elif id == "car_key":
		hud.toast("Ключ от машины на поляне — подойди к ней и нажми E")
	elif id == "wallet":
		inv.take_at(idx, 1)
		var c := randi_range(10, 40)
		inv.add("coin", c)
		hud.toast("В кошельке нашлось %d монет" % c, Color(0.92, 0.82, 0.55))
		play_ui("coin", -11.0)
	else:
		hud.toast("Это нельзя использовать")


# ---------- экипировка, хотбар, крафт ----------

## Надеть предмет из ячейки idx в слот (что было в слоте — встаёт на его место в сумке).
func equip(idx: int, slot_: String) -> void:
	var s = inv.slots[idx]
	if s == null or not Items.fits(s["id"], slot_):
		return
	var id: String = s["id"]
	var prev: String = inv.equip[slot_]
	var prev_d: float = inv.equip_dur.get(slot_, Items.max_dur(prev))
	var new_d: float = float(s.get("dur", Items.max_dur(id)))
	# сетка (промпт 16.11 02:42): прежнее из слота ложится на место нового (не влезет — куда поместится);
	# куртка/штаны/рюкзак меняют свой блок ячеек — вещи из него перекладываются. Не влезло — отменяем.
	var sn := inv.snapshot()
	var extra: Array = []
	if prev != "":
		extra.append({"id": prev, "n": 1, "dur": prev_d, "_at": idx})
	if int(s.get("n", 1)) > 1:
		s["n"] = int(s["n"]) - 1   # из стопки (камни) в руку берём один
		if not extra.is_empty():
			extra[0].erase("_at")
	else:
		inv.slots[idx] = null
	inv.equip[slot_] = id
	inv.equip_dur[slot_] = new_d
	inv.update_blocks()
	var left := inv.reflow(extra)
	if left.size() == 1 and not extra.is_empty() and is_same(left[0], extra[0]):
		drop_spilled(left)   # снятому некуда — на пол (общей сумки нет, промпт 16.11 06:03)
	elif not left.is_empty():
		inv.restore(sn)
		hud.toast("Нет места — некуда переложить")
		inv.notify()
		return
	_apply_equip(slot_)
	inv.notify()
	play_ui("click", -10.0, 0.8)


## Колесо мыши (промпт 04:53): левая ↔ правая. Обе руки уходят вниз, в нижней точке оружие меняется местами
## (прочность и магазин пистолета — вместе с ним), руки поднимаются. Кулдаун — пока идёт анимация.
func swap_hands() -> void:
	if player == null or not alive or not player.active or player.swap_t > 0.0 or player.carrying 			or player.punching or player.charging >= 0:
		return
	if inv.equip["left"] == "" and inv.equip["right"] == "":
		return
	if gun and gun.armed() and (gun.reloading or gun.rmb or gun.ads or gun.hip or gun.aiming):
		return   # прицел / перезарядку не сбиваем
	player.start_swap(_do_swap_hands)
	play_ui("click", -21.0, 0.6)   # свап колесом тише (04:57)


func _do_swap_hands() -> void:
	var l: String = inv.equip["left"]
	var r: String = inv.equip["right"]
	var dl = inv.equip_dur.get("left")
	var dr = inv.equip_dur.get("right")
	inv.equip["left"] = r
	inv.equip["right"] = l
	inv.equip_dur.erase("left")
	inv.equip_dur.erase("right")
	if r != "" and dr != null:
		inv.equip_dur["left"] = dr
	if l != "" and dl != null:
		inv.equip_dur["right"] = dl
	player.set_weapon(r, 0)
	player.set_weapon(l, 1)
	inv.notify()
	play_ui("click", -19.0, 0.75)   # свап колесом тише (04:57)


## Снять в ячейку to (или в первую свободную). false — некуда.
func unequip(slot_: String, to := -1) -> bool:
	var id: String = inv.equip[slot_]
	if id == "":
		return false
	var o: int = inv.owner_at(to) if to >= 0 else -1
	if o >= 0 and Items.fits(inv.slots[o]["id"], slot_):
		equip(o, slot_)       # обмен
		return true
	# сетка: вещь — в ячейку to (или куда поместится); рюкзак/куртка/штаны — их блок пропадает,
	# вещи из него перекладываются в остальные; не влезло — не снимаем
	var sn := inv.snapshot()
	var e := {"id": id, "n": 1, "dur": float(inv.equip_dur.get(slot_, Items.max_dur(id)))}
	if to >= 0:
		e["_at"] = to
		if inv.drop_rot:
			e["r"] = true
	inv.equip_dur.erase(slot_)
	inv.equip[slot_] = ""
	inv.update_blocks()
	var left := inv.reflow([e])
	if left.size() == 1 and is_same(left[0], e):
		drop_spilled(left)   # снятую вещь некуда положить — на пол (общей сумки нет, промпт 16.11 06:03)
	elif not left.is_empty():
		inv.restore(sn)
		hud.toast("Не снять: нет места для вещей из %s" % Items.item_name(id).to_lower(), Color(0.95, 0.6, 0.45))
		play_ui("buzz", -14.0)
		inv.notify()
		return false
	_apply_equip(slot_)
	inv.notify()
	play_ui("click", -12.0, 0.7)
	return true


func drop_equipped(slot_: String) -> void:
	var id: String = inv.equip[slot_]
	if id == "":
		return
	var d: float = inv.equip_dur.get(slot_, Items.max_dur(id))
	var sn := inv.snapshot()
	inv.equip[slot_] = ""
	inv.equip_dur.erase(slot_)
	inv.update_blocks()
	var left := inv.reflow()
	if not left.is_empty():
		drop_spilled(left)   # выбросили вещмешок / одежду — что не влезло в остальное, падает рядом
	_apply_equip(slot_)
	inv.notify()
	var fwd := -player.global_transform.basis.z
	var p := _make_pickup(id, 1, player.global_position + Vector3(0, 1.2, 0) + fwd * 0.5, fwd * 2.0 + Vector3(0, 1.0, 0))
	p.need_leave = true
	if Items.max_dur(id) > 0.0:
		p.set_meta("dur", d)


func _apply_equip(slot_: String) -> void:
	var id: String = inv.equip[slot_]
	match slot_:
		"left", "right":
			var arm := 0 if slot_ == "left" else 1
			player.set_weapon(id, arm)
			if id != "" and not loading:
				hud.toast("%s — %s рука" % [Items.item_name(id), "левая" if arm == 0 else "правая"], Color(0.9, 0.85, 0.7))
		"face":
			# противогаз — в слоте «Лицо», каска при этом остаётся на голове
			if gasmask:
				gasmask.set_worn(id == "gasmask", loading)
			if id != "" and id != "gasmask" and not loading:
				hud.toast("Надето: %s" % Items.item_name(id), Color(0.9, 0.85, 0.7))
		"back":
			# рюкзак: свой блок ячеек (промпт 16.11 02:42; вещи из него при снятии — inv.reflow)
			inv.update_blocks()
			if id != "" and not loading:
				var bd := Items.block_of(id)
				hud.toast("Надето: %s (отсек %d×%d)" % [Items.item_name(id), bd.x, bd.y], Color(0.9, 0.85, 0.7))
		"head":
			if id != "" and not loading:
				hud.toast("Надето: %s" % Items.item_name(id), Color(0.9, 0.85, 0.7))
		"hands":
			player.dmg_mult = float(Items.ITEMS[id].get("fist", 1.0)) if id != "" else 1.0
			hud.knuckles = id == "knuckles"
			if id != "" and not loading:
				hud.toast("Надето: %s" % Items.item_name(id), Color(0.9, 0.85, 0.7))
		"body", "legs", "feet":
			inv.update_blocks()   # карманы куртки / штанов
			if id != "" and not loading:
				hud.toast("Надето: %s" % Items.item_name(id), Color(0.9, 0.85, 0.7))


## G: надеть противогаз из сумки / снять его.
func toggle_gasmask() -> void:
	if inv.equip["face"] == "gasmask":
		unequip("face")
		return
	var i := inv.bag_index("gasmask")
	if i < 0:
		hud.toast("Нюхича нет")
		return
	equip(i, "face")


## Клавиша 1–5: использовать привязанный предмет; надетый — снять.
func hotbar_use(k: int) -> void:
	var id: String = inv.hotbar[k]
	if id == "":
		return
	for sl in inv.equip:
		if inv.equip[sl] == id:
			unequip(sl)
			return
	var i := inv.bag_index(id)
	if i < 0:
		hud.toast("Нет: %s" % Items.item_name(id))
		return
	use_item(i)

## Самая побитая вещь под этот комплект: надетое и сумка. null — чинить нечего.
func _most_worn(kind: String):
	var best = null
	var best_fr := 1.0
	var keys: Array = []
	for k in inv.equip:
		keys.append(k)
	for i in inv.slots.size():
		keys.append(i)
	for k in keys:
		var id: String = inv.equip[k] if k is String else (String(inv.slots[k]["id"]) if inv.slots[k] != null else "")
		if Items.repairable(id) != kind:
			continue
		var fr: float = inv.get_dur(k) / Items.max_dur(id)
		if fr < best_fr - 0.001:
			best_fr = fr
			best = k
	return best


## Починить вещь target (ячейка или слот) ремкомплектом из ячейки kit_idx: −1 заряд, на нуле комплект исчезает.
func repair(kit_idx: int, target) -> void:
	var kit = inv.slots[kit_idx]
	if kit == null or not Items.ITEMS[kit["id"]].has("repair"):
		return
	var kind: String = Items.ITEMS[kit["id"]]["repair"]
	if target == null:
		hud.toast("Чинить нечего — всё целое")
		return
	var id: String = inv.equip[target] if target is String else (String(inv.slots[target]["id"]) if inv.slots[target] != null else "")
	if Items.repairable(id) != kind:
		hud.toast("%s этим не починить" % Items.item_name(id))
		return
	var mx := Items.max_dur(id)
	var cur: float = inv.get_dur(target)
	if cur >= mx - 0.01:
		hud.toast("%s и так целое" % Items.item_name(id))
		return
	var nd := minf(cur + mx * REPAIR_PART, mx)
	if target is String:
		inv.equip_dur[target] = nd
	else:
		inv.slots[target]["dur"] = nd
	var left: float = inv.get_dur(kit_idx) - 1.0
	if left <= 0.0:
		inv.slots[kit_idx] = null
	else:
		kit["dur"] = left
	hud.toast("Починено: %s (%d%%)%s" % [Items.item_name(id), int(round(nd / mx * 100.0)),
		"" if left > 0.0 else " — ремкомплект закончился"], Color(0.8, 0.9, 0.6))
	play_ui("creak", -12.0, 1.4)
	inv.notify()


func craft(r: int) -> void:
	var rec: Dictionary = Items.RECIPES[r]
	var need: Dictionary = rec["need"]
	for id in need:
		if inv.count(id) < int(need[id]):
			hud.toast("Не хватает: %s" % Items.item_name(id))
			return
	var tool_id: String = rec.get("tool", "")
	if tool_id != "":
		# слесарный молоток заменяет каменный (Items.tool_ids), он и тратится первым
		var have := ""
		for t in Items.tool_ids(tool_id):
			if inv.count(t) > 0:
				have = t
				break
		if have == "":
			hud.toast("Нужен инструмент: %s" % Items.item_name(tool_id))
			return
		tool_id = have
	for id in need:
		inv.remove(id, int(need[id]))
	if tool_id != "":
		_wear_tool(tool_id, float(rec.get("wear", 1)))
	var out: String = rec["out"]
	if inv.add(out, 1) > 0:
		var fwd := -player.global_transform.basis.z
		_make_pickup(out, 1, player.global_position + Vector3(0, 1.0, 0) + fwd * 0.4, Vector3.ZERO).need_leave = true
		hud.toast("Нет места — %s на полу" % Items.item_name(out))
	else:
		hud.toast("Скрафчено: %s" % Items.item_name(out), Color(0.8, 0.9, 0.6))
	play_ui("creak", -14.0, 1.6)


## Инструмент крафта теряет прочность: сначала тот, что в сумке, иначе — в руке. На нуле ломается.
func _wear_tool(id: String, amount: float) -> void:
	var i := inv.bag_index(id)
	if i >= 0:
		var d: float = float(inv.slots[i].get("dur", Items.max_dur(id))) - amount
		if d <= 0.0:
			inv.slots[i] = null
			hud.toast("Сломано: %s" % Items.item_name(id), Color(1.0, 0.5, 0.35))
			play_ui("thud", -10.0, 1.6)
		else:
			inv.slots[i]["dur"] = d
		inv.notify()
		return
	for sl in ["right", "left"]:
		if inv.equip[sl] == id:
			_wear(sl, amount)
			return


func drop_item(idx: int, all: bool) -> void:
	var s = inv.slots[idx]
	if s == null:
		return
	drop_count(idx, int(s["n"]) if all else 1)


func drop_count(idx: int, n: int) -> void:
	var dur: float = float(inv.slots[idx].get("dur", -1.0)) if inv.slots[idx] != null else -1.0
	var got: Array = inv.take_at(idx, n)
	if got[1] <= 0:
		return
	var fwd := -player.global_transform.basis.z
	var pos := player.global_position + Vector3(0, 1.2, 0) + fwd * 0.5
	var p := _make_pickup(got[0], got[1], pos, fwd * 2.0 + Vector3(0, 1.0, 0))
	p.need_leave = true
	if dur >= 0.0:
		p.set_meta("dur", dur)


## Вещи, которым не нашлось места в сетке (inv.spilled: пропали карманы / рюкзак, старый сейв) — на пол у игрока.
func drop_spilled(items: Array) -> void:
	if player == null:
		return
	var fwd := -player.global_transform.basis.z
	for s in items:
		var p := _make_pickup(String(s["id"]), int(s.get("n", 1)), player.global_position + Vector3(0, 1.2, 0) + fwd * 0.5,
			fwd * 1.5 + Vector3(randf_range(-0.8, 0.8), 1.0, randf_range(-0.8, 0.8)))
		p.need_leave = true
		if s.has("dur"):
			p.set_meta("dur", float(s["dur"]))
	if not loading:
		hud.toast("Нет места — выпало на пол", Color(0.95, 0.6, 0.45))


## Выбросить монеты из кошелька.
func drop_coins(n: int) -> void:
	n = mini(n, inv.coins)
	if n <= 0 or not inv.remove("coin", n):
		return
	var fwd := -player.global_transform.basis.z
	var pos := player.global_position + Vector3(0, 1.2, 0) + fwd * 0.5
	var parts := clampi(n, 1, 6)
	for k in parts:
		@warning_ignore("integer_division")
		var cnt := n / parts + (1 if k < n % parts else 0)
		var p := _make_pickup("coin", cnt, pos, fwd * 2.0 + Vector3(randf_range(-0.6, 0.6), 1.0, randf_range(-0.6, 0.6)))
		p.need_leave = true
		p.set_meta("dropped", true)
	play_ui("coin", -11.0, 0.9)


## Новая одежда/снаряжение (промпт 05:37): сразу в свободный подходящий слот экипировки. true — надето.
func auto_equip(id: String, dur := -1.0) -> bool:
	var k := Items.equip_slot(id)
	if k == "" or k == "hand" or not inv.equip.has(k) or inv.equip[k] != "":
		return false
	inv.equip[k] = id
	inv.equip_dur[k] = dur if dur >= 0.0 else Items.max_dur(id)
	inv.update_blocks()
	_apply_equip(k)
	inv.notify()
	play_ui("click", -10.0, 0.8)
	return true


## Выдать вещь (покупка): надеть в свободный слот → в сумку → на пол рядом. "equip" / "bag" / "floor".
func give_gear(id: String, dur := -1.0) -> String:
	if auto_equip(id, dur):
		return "equip"
	if inv.add(id, 1, dur) == 0:
		return "bag"
	var e := {"id": id, "n": 1}
	if dur >= 0.0:
		e["dur"] = dur
	drop_spilled([e])
	return "floor"


## Вызывается лежащим предметом, когда игрок рядом. Возвращает, сколько не влезло.
func collect(id: String, n: int, from: Node = null) -> int:
	var d: float = float(from.get_meta("dur", -1.0)) if from != null else -1.0
	if n == 1 and auto_equip(id, d):
		return 0
	var left: int = inv.add(id, n, d)
	var got := n - left
	if got > 0:
		var nm := Items.item_name(id)
		hud.toast("+%d  %s" % [got, nm] if got > 1 else "+ " + nm, Color(0.92, 0.82, 0.55) if id == "coin" else Color(0.85, 0.85, 0.8))
		if id == "coin":
			play_ui("coin", -13.0)
		else:
			play_ui("pickup", -10.0)
	elif full_toast_t <= 0.0:
		full_toast_t = 3.0
		hud.toast("Инвентарь полон", Color(0.9, 0.5, 0.4))
	return left
