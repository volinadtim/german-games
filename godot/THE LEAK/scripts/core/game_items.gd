extends "res://scripts/core/game_world.gd"
# Часть game.gd: здоровье, баффы, предметы, экипировка, износ, ремонт, крафт, выброс и подбор.


# ---------- прочность (промпт 21:46) ----------

## Попадание по врагу/ящику/кувшину (не манекену): изнашивается оружие в бьющей руке (player.last_arm).
func weapon_hit() -> void:
	if Fx.by != null and is_instance_valid(Fx.by) and Fx.by != player:
		var sp = get_meta("split", null)
		if sp != null and Fx.by == sp.pp:
			sp._as_p2(weapon_hit)   # Split-Screen: бил игрок 2 — изнашивается его оружие
		return
	if player == null or player.last_arm < 0:
		return
	var sl := "left" if player.last_arm == 0 else "right"
	if Items.ITEMS.has(String(inv.equip[sl])) and Items.ITEMS[String(inv.equip[sl])].has("weapon"):
		_wear(sl, 1.0)   # не оружие в руке (куртка, еда — промпт 18.11 00:27) от ударов не изнашивается


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
	if not alive or god:
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
	if not alive or god:
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
	hb_clear()   # предмет из хотбара — из руки
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
	take_one(pick)   # аптечка — −1 применение, а не вся
	heal(Items.ITEMS[pick]["heal"])
	hud.toast("%s: +%d здоровья" % [Items.item_name(pick), int(Items.ITEMS[pick]["heal"])], Color(0.7, 0.9, 0.6))
	play_ui("pickup", -12.0, 0.8)


# ---------- предметы ----------

## key — ячейка сумки (int) или слот руки "left"/"right" (предмет взят в руку, промпт 18.11 02:27).
func use_item(key, no_channel := false) -> void:
	var in_hand: bool = key is String
	var id := ""
	if in_hand:
		id = String(inv.equip[key])
	elif inv.slots[key] != null:
		id = String(inv.slots[key]["id"])
	if id == "" or not Items.ITEMS.has(id):
		return
	var idx = key
	var def: Dictionary = Items.ITEMS[id]
	if def.has("repair"):
		repair(idx, _most_worn(String(def["repair"])))
	elif def.has("buff"):
		# еда и питьё — не через противогаз (промпт 16.11 21:46); в машине — тоже можно, и водителю (18.11 00:49):
		# ввод из салона идёт сюда же (game._unhandled_input, инвентарь), игрок при этом выключен — это не мешает
		if GasMask.is_mask(inv.equip["face"]):
			var in_car: bool = car != null and is_instance_valid(car) and int(car.my_seat) >= 0
			hud.toast("В противогазе не поесть и не попить%s — сними его (G)" % (" даже в машине" if in_car else ""), Color(0.95, 0.7, 0.45))
			return
		_use_take(idx)
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
		if revive and not no_channel:
			revive.heal_channel(id)   # не мгновенно: полоска, прерывается движением и уроном
			return
		_use_take(idx)
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
		# светит только в руке (промпт 18.11 02:27): в руке — вкл/выкл, из сумки — сначала берём в руку
		if in_hand and flashlight:
			flashlight.toggle()
		elif not in_hand:
			take_in_hand(idx)
	elif id == "battery":
		if flashlight == null:
			return
		if flashlight.charge >= 0.99:
			hud.toast("Фонарик и так заряжен")
			return
		_use_take(idx)
		flashlight.recharge()
		hud.toast("Фонарик заряжен", Color(0.9, 0.85, 0.55))
		play_ui("click", -12.0)
	elif in_hand and Items.equip_slot(id) != "":
		pass   # оружие/снаряжение уже в руке — применять нечего
	elif id == "pistol":
		# второй пистолет — в свободную левую (стреляют по очереди, gun.gd)
		equip(idx, "left" if inv.equip["right"] == "pistol" and inv.equip["left"] == "" else "right")
	elif id == "mag":
		gun.fill_mag(idx)
	elif Items.equip_slot(id) == "hand":
		take_in_hand(idx)   # оружие — в свободную руку (сначала правая), обе заняты — меняем правую
	elif Items.equip_slot(id) != "":
		equip(idx, Items.equip_slot(id))
	elif id == "filter" or id == "filter2":
		if casual():
			hud.toast("Фильтр ставится сам")
		elif gasmask:
			gasmask.change_filter(id)
	elif id == "coin":
		pass
	elif id == "car_key":
		hud.toast("Ключ от машины на поляне — открой водительскую дверь [F]")
	elif id == "wallet":
		_use_take(idx)
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
	if not can_take_hand(slot_):
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
	# снятое из руки докладываем в свою стопку, если в ней есть место (промпт 20.11 14:21)
	if prev != "" and int(Items.ITEMS[prev]["stack"]) > 1 and Items.max_dur(prev) <= 0.0:
		for t in inv.slots:
			if t != null and String(t["id"]) == prev and int(t["n"]) < int(Items.ITEMS[prev]["stack"]):
				t["n"] = int(t["n"]) + 1
				extra.clear()
				break
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
	if player != null and alive and car != null and is_instance_valid(car) and int(car.my_seat) >= 0 and int(car.seat_dir) == 0:
		# в машине игрок выключен — анимации рук нет, меняем сразу (за рулём так переключаются между
		# предметом в руке и тем, что «на коленях», промпт 20.11 11:40)
		if inv.equip["left"] == "" and inv.equip["right"] == "":
			return
		if gun and gun.armed() and (gun.reloading or gun.rmb or gun.ads or gun.hip):
			return
		_do_swap_hands()
		return
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
	if hb_slot != "":
		hb_slot = "right" if hb_slot == "left" else "left"
	player.set_weapon(r, 0)
	player.set_weapon(l, 1)
	inv.notify()
	play_ui("click", -19.0, 0.75)   # свап колесом тише (04:57)


## Водитель за рулём (промпт 20.11 11:40): одна рука на руле — в руках работает максимум один предмет
## (оружие, еда, бинты — любой). Второй, если был, лежит «на коленях»; колесо мыши меняет их местами.
func driving() -> bool:
	return car != null and is_instance_valid(car) and int(car.my_seat) == 0


## Рука, которой водитель держит предмет: правая, если в ней что-то есть, иначе левая. Не за рулём — "".
func drive_hand() -> String:
	if not driving():
		return ""
	return "right" if inv.equip["right"] != "" else "left"


## Работает ли предмет в руке sl (за рулём — только в drive_hand, вторая рука на руле).
func hand_live(sl: String) -> bool:
	var dh := drive_hand()
	return dh == "" or dh == sl


## Можно ли взять предмет в руку sl: за рулём — только если вторая рука пуста. false — с подсказкой.
func can_take_hand(sl: String) -> bool:
	if not sl in ["left", "right"] or not driving():
		return true
	if inv.equip["left" if sl == "right" else "right"] == "":
		return true
	hud.toast("За рулём занята только одна рука — сменить предмет: колесо мыши", Color(0.95, 0.7, 0.45))
	play_ui("buzz", -14.0)
	return false


## Сел за руль с двумя предметами в руках — подсказка (car_drive.gd: _driver_in).
func drive_hands_hint() -> void:
	if inv.equip["left"] != "" and inv.equip["right"] != "":
		hud.toast("За рулём одна рука: %s — на коленях, колесо мыши — сменить" % Items.item_name(inv.equip["left"]), Color(0.9, 0.85, 0.7))


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
	if player and player.has_method("set_outfit"):
		player.set_outfit(inv.equip)   # одежда видна на модели (промпт 18.11 00:44)
	match slot_:
		"left", "right":
			var arm := 0 if slot_ == "left" else 1
			player.set_weapon(id, arm)
			if id != "" and not loading:
				var how := (" (%s — применить)" % ["ЛКМ", "ПКМ"][arm] if Items.hand_use(id) else "") + " · [H] — выкинуть"   # с геймпада — кнопка сброса (pad_text в toast)
				hud.toast("%s — %s рука%s" % [Items.item_name(id), "левая" if arm == 0 else "правая", how], Color(0.9, 0.85, 0.7))
		"face":
			# противогаз — в слоте «Лицо», каска при этом остаётся на голове
			if gasmask:
				gasmask.set_worn(GasMask.is_mask(id), loading)
			if id != "" and not GasMask.is_mask(id) and not loading:
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
	if GasMask.is_mask(inv.equip["face"]):
		unequip("face")
		return
	# сначала армейский «Шлемыч» (обзор лучше), потом «Нюхич»
	var i := inv.bag_index("gasmask2")
	if i < 0:
		i = inv.bag_index("gasmask")
	if i < 0:
		hud.toast("Противогаза нет")
		return
	equip(i, "face")


## Клавиша 1–5: предмет берётся в руку — он виден в руке, как если бы его поставили в слот экипировки
## (промпт 18.11 02:27). Броня/рюкзак/противогаз — в свой слот, всё остальное (оружие, еда, бинты, фонарик) —
## в свободную руку. Повторное нажатие той же клавиши — убрать предмет из руки (снять).
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
	var eq := Items.equip_slot(id)
	if eq == "" or eq == "hand":
		take_in_hand(i)
		return
	equip(i, eq)


## Взять предмет из ячейки idx в свободную руку (сначала правая; обе заняты — меняется правая).
## Применяется кнопкой этой руки: ЛКМ — левая, ПКМ — правая (hb_press).
func take_in_hand(idx: int) -> void:
	var dh := drive_hand()
	if dh != "":   # за рулём — меняем предмет в занятой руке, вторую не берём
		equip(idx, dh)
		return
	equip(idx, "right" if inv.equip["right"] == "" or inv.equip["left"] != "" else "left")


## Убрать предмет из руки (отмена удержания, предмет кончился, смерть).
func hb_clear(msg := "") -> void:
	hb_hand = ""
	hb_slot = ""
	hb_lmb = false
	if revive and revive.ch_on:
		revive.cancel_channel()
	if msg != "":
		hud.toast(msg, Color(0.85, 0.82, 0.75))


## Где лежит предмет, который применяют: слот руки ("left"/"right") или null — предмет из руки пропал.
func hb_key():
	if hb_slot != "" and inv.equip.get(hb_slot, "") == hb_hand:
		return hb_slot
	return null


## Предмет в руке arm (0 — левая/ЛКМ, 1 — правая/ПКМ), который применяется кнопкой этой руки; "" — нет такого.
func hb_item(arm: int) -> String:
	var id: String = inv.equip["left" if arm == 0 else "right"]
	if id == "" or not Items.hand_use(id):
		return ""
	# пистолет в руках забирает ЛКМ под выстрел (gun.gd) — предмет левой рукой в это время не применить
	if arm == 0 and player and not player.fists and (player.weapon_ids[0] == "pistol" or player.weapon_ids[1] == "pistol"):
		return ""
	return id


## Нажали кнопку руки: предмет в этой руке применяется (с полоской; фонарик — сразу).
## true — удар этой рукой не нужен (player_combat.gd).
func hb_press(arm := 0) -> bool:
	var sl := "left" if arm == 0 else "right"
	var id := hb_item(arm)
	if id == "" or not alive:
		return false
	if id == "flashlight":
		if flashlight:
			flashlight.toggle()   # светит только в руке (промпт 18.11 02:27)
		return true
	if revive and revive.ch_on:
		return true
	hb_hand = id
	hb_slot = sl
	hb_lmb = true
	if revive:
		revive.use_channel(id)
	else:
		use_item(sl, true)
		hb_after_use(id)
	return true


## Отпустили кнопку руки: применение прерывается (полоска гаснет), удара нет.
func hb_release(arm := 0) -> bool:
	var sl := "left" if arm == 0 else "right"
	if hb_item(arm) == "":
		return false
	if hb_slot == sl:
		hb_lmb = false
	return true


## После применения: предмет израсходован — такой же из сумки сам идёт в ту же руку, иначе рука пустеет.
func hb_after_use(id: String) -> void:
	if hb_hand != id:
		return
	hb_lmb = false
	var sl := hb_slot
	if sl != "" and inv.equip[sl] == "":
		var i := inv.bag_index(id)
		if i >= 0:
			equip(i, sl)
	if sl == "" or inv.equip[sl] != id:
		hb_hand = ""
		hb_slot = ""


## Убрать одну штуку предмета: сначала из сумки, иначе из руки (там он тоже считается, inv.count).
func take_one(id: String) -> bool:
	if Items.ITEMS.get(id, {}).has("uses"):
		var bi := inv.bag_index(id)
		if bi >= 0:
			_use_take(bi)   # −1 применение (промпт 20.11 14:22)
			return true
	elif inv.remove(id, 1):
		return true
	for sl in ["right", "left"]:
		if inv.equip[sl] == id:
			_use_take(sl)
			return true
	return false


## Убрать одну штуку применённого предмета: из сумки (int) или из руки (слот — пустеет, модель убирает предмет).
func _use_take(key) -> void:
	# предмет на несколько применений (аптечка, вода, газировка, тушёнка) — −1, на нуле пропадает
	var uid: String = String(inv.equip[key]) if key is String else (String(inv.slots[key]["id"]) if inv.slots[key] != null else "")
	if Items.ITEMS.get(uid, {}).has("uses"):
		var left: float = inv.get_dur(key) - 1.0
		if left > 0.0:
			if key is String:
				inv.equip_dur[key] = left
			else:
				inv.slots[key]["dur"] = left
			inv.notify()
			return
	if key is String:
		inv.equip[key] = ""
		inv.equip_dur.erase(key)
		_apply_equip(key)
		inv.notify()
	else:
		inv.take_at(key, 1)


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
		var fr: float = Gun.gun_dur(inv.get_dur(k)) / Gun.DUR_MAX if kind == "gun" else inv.get_dur(k) / Items.max_dur(id)
		if fr < best_fr - 0.001:
			best_fr = fr
			best = k
	return best


## Починить вещь target (ячейка или слот) ремкомплектом из ячейки kit_key (или из руки — слот "left"/"right"):
## −1 заряд, на нуле комплект исчезает.
func repair(kit_key, target) -> void:
	var kit_id := ""
	if kit_key is String:
		kit_id = String(inv.equip[kit_key])
	elif inv.slots[kit_key] != null:
		kit_id = String(inv.slots[kit_key]["id"])
	if not Items.ITEMS.get(kit_id, {}).has("repair"):
		return
	var kind: String = Items.ITEMS[kit_id]["repair"]
	if target == null:
		hud.toast("Чинить нечего — всё целое")
		return
	var id: String = inv.equip[target] if target is String else (String(inv.slots[target]["id"]) if inv.slots[target] != null else "")
	if Items.repairable(id) != kind:
		hud.toast("%s этим не починить" % Items.item_name(id))
		return
	# у пистолета прочность — дробная часть dur (gun.gd), целая часть (магазин с патронами) не трогается
	var gun_kit := kind == "gun"
	var mx: float = Gun.DUR_MAX if gun_kit else Items.max_dur(id)
	var raw: float = inv.get_dur(target)
	var cur: float = Gun.gun_dur(raw) if gun_kit else raw
	if cur >= mx - 0.01:
		hud.toast("%s и так целое" % Items.item_name(id))
		return
	var nd := minf(cur + mx * REPAIR_PART, mx)
	var store: float = Gun.with_gun_dur(raw, nd) if gun_kit else nd
	if target is String:
		inv.equip_dur[target] = store
	else:
		inv.slots[target]["dur"] = store
	var left: float = inv.get_dur(kit_key) - 1.0
	if kit_key is String:
		if left <= 0.0:
			_use_take(kit_key)   # комплект в руке кончился — рука пустеет
		else:
			inv.equip_dur[kit_key] = left
	elif left <= 0.0:
		inv.slots[kit_key] = null
	else:
		inv.slots[kit_key]["dur"] = left
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


## Насколько вещь хороша для своего слота: броня, ячейки (рюкзак, карманы), сила удара перчаток, прочность.
func gear_score(id: String) -> float:
	if id == "" or not Items.ITEMS.has(id):
		return -1.0
	var d: Dictionary = Items.ITEMS[id]
	var sc := float(d.get("armor", 0.0)) * 100.0 + float(d.get("fist", 0.0)) * 10.0 + float(d.get("dur", 0)) / 10.0
	var bag: Array = d.get("bag", [])
	if bag.size() == 2:
		sc += float(int(bag[0]) * int(bag[1])) * 2.0
	return sc


## Надеть сразу, даже без места (промпт 18.11 00:28): прежняя вещь из слота — в ячейки, не влезла — на пол;
## вещи из пропавшего блока (рюкзак/карманы) тоже раскладываются, лишнее — на пол.
func wear_now(id: String, dur := -1.0) -> void:
	var k := Items.equip_slot(id)
	var prev: String = inv.equip[k]
	var extra: Array = []
	if prev != "":
		extra.append({"id": prev, "n": 1, "dur": float(inv.equip_dur.get(k, Items.max_dur(prev)))})
	inv.equip[k] = id
	inv.equip_dur[k] = dur if dur >= 0.0 else Items.max_dur(id)
	inv.update_blocks()
	var left := inv.reflow(extra)
	if not left.is_empty():
		drop_spilled(left)
	_apply_equip(k)
	inv.notify()
	play_ui("click", -10.0, 0.8)


## Выдать вещь (покупка): надеть в свободный слот → в сумку → на пол рядом. "equip" / "bag" / "floor".
## upgrade — покупка в магазине: одежда надевается сразу вместо прежней, та — в ячейки / на пол (промпт 18.11 00:28).
func give_gear(id: String, dur := -1.0, upgrade := false) -> String:
	if auto_equip(id, dur):
		return "equip"
	var k := Items.equip_slot(id)
	if upgrade and k != "" and k != "hand" and inv.equip.has(k):
		wear_now(id, dur)
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
	if left > 0 and Items.holdable(id):
		# сумка полна — берём в свободную руку, как оружие (промпт 18.11 00:27)
		for sl in ["right", "left"]:
			if left > 0 and inv.equip[sl] == "":
				inv.equip[sl] = id
				inv.equip_dur[sl] = d if d >= 0.0 else Items.max_dur(id)
				_apply_equip(sl)
				left -= 1
				inv.notify()
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
