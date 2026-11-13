extends Node3D
## Тестовые механики — связка: HUD, инвентарь, здоровье игрока, взаимодействие на E, лут на полу,
## враги, манекен, ящики/сейф, игровой автомат, фонарик. Создаётся из main.gd (_enter_game).
## Каждая механика — свой скрипт; ненужную выключить флагом ниже (или удалить её файл и строку _spawn_*).
##   Управление: E — взаимодействие, Tab/I — инвентарь, F — фонарик, Q — быстро полечиться.

const Player := preload("res://player.gd")
const Hud := preload("res://hud.gd")
const Inventory := preload("res://inventory.gd")
const Items := preload("res://items.gd")
const Fx := preload("res://fx.gd")
const Pickup := preload("res://pickup.gd")
const Flashlight := preload("res://flashlight.gd")
const TapeSpot := preload("res://tape_spot.gd")
const Enemy := preload("res://enemy.gd")
const Dummy := preload("res://dummy.gd")
const Chest := preload("res://chest.gd")
const SlotMachine := preload("res://slot_machine.gd")
const Shop := preload("res://shop.gd")
const GasMask := preload("res://gasmask.gd")
const Sfx := preload("res://sfx.gd")
const Sfx2 := preload("res://sfx_extra.gd")

# включение механик
const USE_ENEMIES := true
const USE_DUMMY := true
const USE_CHESTS := true
const USE_SLOTS := true
const USE_FLASHLIGHT := true

const MAX_HP := 100.0
const START := Vector3(-10.5, 0.05, 0.0)
## враги бродят по поляне наверху (выход из бункера — лестница в восточном торце коридора)
const ENEMY_SPOTS := [Vector3(28.0, 4.1, 7.0), Vector3(36.0, 4.1, -6.0), Vector3(40.0, 4.1, 4.0), Vector3(31.0, 4.1, -10.0)]
const RESPAWN := 40.0

var player: Player
var hud: Hud
var inv: Inventory
var flashlight: Flashlight
var hp := MAX_HP
var alive := true
var focus: Object = null
var snd := {}
var ui_player: AudioStreamPlayer
var full_toast_t := 0.0
var safe: Chest
var slot: SlotMachine
var shop: Shop
var gasmask: GasMask


func setup(p: Player) -> void:
	player = p
	_setup_input()
	_make_sounds()
	ui_player = AudioStreamPlayer.new()
	ui_player.max_polyphony = 4
	add_child(ui_player)

	hud = Hud.new()
	add_child(hud)
	inv = Inventory.new()
	inv.game = self
	add_child(inv)
	inv.changed.connect(func(): hud.set_coins(inv.count("coin")))
	inv.use_requested.connect(use_item)
	inv.drop_requested.connect(drop_item)
	inv.drop_count_requested.connect(drop_count)
	inv.drop_coins_requested.connect(drop_coins)
	inv.equip_requested.connect(equip)
	inv.unequip_requested.connect(func(slot_: String, to: int): unequip(slot_, to))
	inv.drop_equipped_requested.connect(drop_equipped)
	inv.craft_requested.connect(craft)
	inv.message.connect(func(t: String): hud.toast(t))
	hud.inv = inv
	hud.set_hp(hp, MAX_HP)
	hud.restart_pressed.connect(restart)

	if USE_FLASHLIGHT:
		flashlight = Flashlight.new()
		flashlight.game = self
		add_child(flashlight)
		flashlight.attach(player.cam)

	# стартовый набор (крутка автомата — 10 монет). Фонарика нет — он в магазине снаряжения.
	inv.add("coin", 30)
	inv.add("bandage", 1)

	if USE_DUMMY:
		# манекен — в левой комнате, ближайшей к старту (северо-западная)
		var d := Dummy.new()
		d.game = self
		d.position = Vector3(-8.0, 0.0, -3.6)
		add_child(d)
	if USE_ENEMIES:
		for s in ENEMY_SPOTS:
			_spawn_enemy(s)
	if USE_CHESTS:
		_chest(Vector3(-3.0, 0.0, -8.5), 0.0, [])
		_chest(Vector3(9.0, 0.0, -8.5), 0.0, [])
		_chest(Vector3(-11.5, 0.0, 3.2), PI / 2.0, [])
		_chest(Vector3(2.2, 0.0, -2.15), PI, [])
		_chest(Vector3(2.2, 0.0, 2.15), 0.0, [])
		# сейф открывается только тремя семёрками на автомате KILLBOX (open_safe)
		safe = Chest.new()
		safe.kind = "safe"
		safe.locked = true
		safe.random_loot = false
		safe.extra = [["knuckles", 1], ["coin", 60], ["medkit", 2], ["battery", 2], ["canned", 2], ["wallet", 1]]
		safe.position = Vector3(11.5, 0.0, 7.0)
		safe.rotation.y = -PI / 2.0
		add_child(safe)
	# противогаз и отравленный воздух наверху (G)
	gasmask = GasMask.new()
	gasmask.game = self
	add_child(gasmask)
	if USE_SLOTS:
		# автомат создаёт main.gd (он же фон меню); если его нет — ставим свой
		slot = get_parent().get_node_or_null("SlotMachine") as SlotMachine
		if slot == null:
			slot = SlotMachine.new()
			slot.position = Vector3(-6.0, 0.0, 8.5)
			slot.rotation.y = PI
			add_child(slot)
		slot.game = self
	# изолента, приклеенная к доске выплат у автомата (берётся на E, со временем появляется снова)
	var tape := TapeSpot.new()
	tape.game = self
	tape.position = Vector3(-6.95, 0.95, 8.66)
	add_child(tape)
	# осколки стекла на полу (там, где битое стекло) — материал для ножика
	for gp in [Vector3(-5.4, 0.1, 0.4), Vector3(9.6, 0.1, -6.3), Vector3(-9.1, 0.1, 6.6)]:
		_make_pickup("glass", 1, gp, Vector3.ZERO)
	shop = get_parent().get_node_or_null("Shop") as Shop
	if shop:
		shop.game = self


## Три семёрки на автомате: открыть сейф. false — если сейф уже открыт (или его нет).
func open_safe() -> bool:
	if safe == null or not is_instance_valid(safe) or safe.opened:
		return false
	safe.force_open(self)
	return true

func _chest(pos: Vector3, rot: float, extra: Array) -> void:
	var c := Chest.new()
	c.game = self
	chests.append(c)
	c.extra = extra
	c.position = pos
	c.rotation.y = rot
	add_child(c)


func _spawn_enemy(pos: Vector3) -> void:
	var e := Enemy.new()
	e.game = self
	e.position = pos
	e.rotation.y = randf_range(0, TAU)
	add_child(e)
	e.died.connect(func(_e): _respawn_enemy_later(pos))


func _respawn_enemy_later(pos: Vector3) -> void:
	await get_tree().create_timer(RESPAWN).timeout
	while is_instance_valid(player) and player.global_position.distance_to(pos) < 8.0:
		await get_tree().create_timer(5.0).timeout
	_spawn_enemy(pos)


func _make_sounds() -> void:
	snd["coin"] = [Sfx2.coin(0), Sfx2.coin(1), Sfx2.coin(2)]
	snd["creak"] = [Sfx2.creak(0), Sfx2.creak(1)]
	snd["click"] = [Sfx2.click()]
	snd["tick"] = [Sfx2.tick()]
	snd["clunk"] = [Sfx2.clunk()]
	snd["jingle"] = [Sfx2.jingle()]
	snd["buzz"] = [Sfx2.buzz()]
	snd["growl"] = [Sfx2.growl(0), Sfx2.growl(1), Sfx2.growl(2)]
	snd["thud"] = [Sfx2.thud()]
	snd["pickup"] = [Sfx2.pickup()]
	snd["whoosh"] = [Sfx.whoosh(1), Sfx.whoosh(2)]
	snd["hurt"] = [Sfx.exhale(1), Sfx.exhale(3)]


func play_ui(name_: String, db: float, pitch := 1.0) -> void:
	var set_: Array = snd[name_]
	ui_player.stream = set_[randi() % set_.size()]
	ui_player.volume_db = db
	ui_player.pitch_scale = pitch * randf_range(0.95, 1.05)
	ui_player.play()


func play_at(name_: String, pos: Vector3, db: float, pitch := 1.0) -> void:
	var set_: Array = snd[name_]
	var p := AudioStreamPlayer3D.new()
	p.stream = set_[randi() % set_.size()]
	p.volume_db = db
	p.unit_size = 4.0
	p.pitch_scale = pitch * randf_range(0.95, 1.05)
	add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


func _setup_input() -> void:
	_add_keys("interact", [KEY_E])
	_add_keys("inventory", [KEY_TAB, KEY_I])
	_add_keys("flashlight", [KEY_F])
	_add_keys("quick_heal", [KEY_Q])


func _add_keys(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


# ---------- взаимодействие ----------

func _physics_process(delta: float) -> void:
	full_toast_t -= delta
	if player == null:
		return
	focus = null
	var text := ""
	_glass(delta)
	_tick_buffs(delta)
	if alive:
		var from := player.cam.global_position
		var q := PhysicsRayQueryParameters3D.create(from, from - player.cam.global_transform.basis.z * 2.3)
		q.collision_mask = 1
		q.exclude = [player.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit and hit.collider.has_method("interact"):
			focus = hit.collider
			text = hit.collider.get_prompt(self)
	hud.prompt(text)


## Одно окно за раз: пока открыт инвентарь или магазин, другие окна не открываются.
func window_open() -> bool:
	return (inv != null and inv.open) or (shop != null and shop.opened)


func _unhandled_input(e: InputEvent) -> void:
	if not alive or player == null or window_open():
		return
	if e.is_action_pressed("interact") and not e.is_echo():
		if focus != null and is_instance_valid(focus):
			focus.interact(self)
	elif e.is_action_pressed("flashlight") and flashlight:
		flashlight.toggle()
	elif e.is_action_pressed("quick_heal"):
		_quick_heal()
	else:
		for k in 5:
			if e.is_action_pressed("hot_%d" % (k + 1)):
				hotbar_use(k)


# ---------- стекло и кровотечение (промпт 20:02) ----------
## Битое стекло на полу (те же места, что в level.gd: _floor_litter): наступил — −5 здоровья
## и кровотечение 10 с по 3 в секунду. Повторный наступ обновляет таймер. Снимает бинт или аптечка.
const GLASS_SPOTS := [[Vector3(-5.6, 0, 0.1), 0.9], [Vector3(9.5, 0, -6.5), 0.5], [Vector3(-9.0, 0, 6.8), 0.5]]
const BLEED_TIME := 10.0
const BLEED_DPS := 3.0
var on_glass := false
var last_feet_pos := Vector3.INF
var glass_cd := 0.0
var bleed_t := 0.0


func _glass(delta: float) -> void:
	glass_cd -= delta
	# сапоги стираются от ходьбы: 1 прочности за 8 м
	var pp0 := player.global_position
	if inv.equip["feet"] != "" and player.is_on_floor() and last_feet_pos != Vector3.INF:
		var step := Vector2(pp0.x - last_feet_pos.x, pp0.z - last_feet_pos.z).length()
		if step < 1.0:
			_wear("feet", step / 8.0)
	last_feet_pos = pp0
	if bleed_t > 0.0:
		bleed_t = maxf(bleed_t - delta, 0.0)
		drain_hp(BLEED_DPS * delta)
		if not alive:
			bleed_t = 0.0
	hud.bleed = bleed_t
	var pp := player.global_position
	var now := false
	if alive and player.is_on_floor() and pp.y < 0.4:
		for g in GLASS_SPOTS:
			var c: Vector3 = g[0]
			if Vector2(pp.x - c.x, pp.z - c.z).length() < float(g[1]) + 0.1:
				now = true
	if now and not on_glass and glass_cd <= 0.0 and Items.ITEMS.get(inv.equip["feet"], {}).get("glassproof", false):
		glass_cd = 1.5
		play_ui("tick", -22.0, 0.6)      # хруст под сапогом — без урона, но сапоги теряют 20% прочности
		_wear("feet", Items.max_dur(inv.equip["feet"]) * 0.2)
	elif now and not on_glass and glass_cd <= 0.0:
		glass_cd = 1.5
		drain_hp(5.0)
		if alive:
			bleed_t = BLEED_TIME
			hud.hurt_flash(0.5)
			hud.toast("Стекло! Кровотечение", Color(1.0, 0.4, 0.3))
			play_ui("hurt", -17.0, 0.9)
	on_glass = now


# ---------- прочность (промпт 21:46) ----------

## Попадание по врагу/манекену/ящику: изнашивается оружие в бьющей руке (player.last_arm).
func weapon_hit() -> void:
	if player == null or player.last_arm < 0:
		return
	_wear("left" if player.last_arm == 0 else "right", 1.0)


## Снять прочность с надетой вещи; на нуле вещь ломается и пропадает.
func _wear(slot_: String, amount: float) -> void:
	var id: String = inv.equip[slot_]
	if id == "" or Items.max_dur(id) <= 0.0:
		return
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


# ---------- баффы еды и напитков (промпт 20:06) ----------
## buffs[тип] = {"power": доля, "time": осталось, "icon": предмет}; тип — resist (еда) или speed (напитки).
## Новый бафф того же типа: сила — бо́льшая из двух, время — бо́льшее из двух.
var buffs := {}


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
	hp = maxf(hp - amount, 0.0)
	hud.set_hp(hp, MAX_HP)
	hud.hurt_flash()
	var push := player.global_position - from
	push.y = 0.0
	player.velocity += push.normalized() * 4.5 + Vector3(0, 2.0, 0)
	var tw := create_tween()
	tw.tween_property(player.cam, "rotation:z", randf_range(-0.07, 0.07), 0.05)
	tw.tween_property(player.cam, "rotation:z", 0.0, 0.25)
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
	hud.show_death(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## «Начать заново»: полный сброс — сцена перезагружается и сразу стартует игра (main.gd), минуя меню.
func restart() -> void:
	Engine.set_meta("eskiness_autostart", true)
	get_tree().paused = false
	get_tree().reload_current_scene()


func _quick_heal() -> void:
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
	if def.has("buff"):
		inv.take_at(idx, 1)
		add_buff(id)
		var what := "−%d%% урона" % int(float(def["power"]) * 100) if def["buff"] == "resist" else "+%d%% скорости" % int(float(def["power"]) * 100)
		hud.toast("%s: %s на %d с" % [def["name"], what, int(def["time"])], Color(0.8, 0.9, 0.6))
		play_ui("pickup", -12.0, 0.9)
	elif def.has("heal"):
		var stops := id in ["bandage", "medkit"] and bleed_t > 0.0
		if hp >= MAX_HP and not stops:
			hud.toast("Здоровье и так полное")
			return
		inv.take_at(idx, 1)
		heal(def["heal"])
		if stops:
			stop_bleeding()
		hud.toast("%s: +%d здоровья" % [def["name"], int(def["heal"])], Color(0.7, 0.9, 0.6))
		play_ui("pickup", -12.0, 0.8)
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
	inv.slots[idx] = {"id": prev, "n": 1, "dur": prev_d} if prev != "" else null
	inv.equip[slot_] = id
	inv.equip_dur[slot_] = new_d
	_apply_equip(slot_)
	inv.notify()
	play_ui("click", -10.0, 0.8)


## Снять в ячейку to (или в первую свободную). false — некуда.
func unequip(slot_: String, to := -1) -> bool:
	var id: String = inv.equip[slot_]
	if id == "":
		return false
	if to >= 0 and inv.slots[to] != null:
		if Items.fits(inv.slots[to]["id"], slot_):
			equip(to, slot_)       # обмен
			return true
		to = -1
	if to < 0:
		to = inv.slots.find(null)
	if to < 0:
		hud.toast("Сумка полна — некуда снять")
		return false
	inv.slots[to] = {"id": id, "n": 1, "dur": float(inv.equip_dur.get(slot_, Items.max_dur(id)))}
	inv.equip_dur.erase(slot_)
	inv.equip[slot_] = ""
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
			if id != "":
				hud.toast("%s — %s рука" % [Items.item_name(id), "левая" if arm == 0 else "правая"], Color(0.9, 0.85, 0.7))
		"head":
			if gasmask:
				gasmask.set_worn(id == "gasmask")
			if id != "" and id != "gasmask":
				hud.toast("Надето: %s" % Items.item_name(id), Color(0.9, 0.85, 0.7))
		"hands":
			player.dmg_mult = float(Items.ITEMS[id].get("fist", 1.0)) if id != "" else 1.0
			hud.knuckles = id == "knuckles"
			if id != "":
				hud.toast("Надето: %s" % Items.item_name(id), Color(0.9, 0.85, 0.7))
		"body", "legs", "feet":
			if id != "":
				hud.toast("Надето: %s" % Items.item_name(id), Color(0.9, 0.85, 0.7))


## G: надеть противогаз из сумки / снять его.
func toggle_gasmask() -> void:
	if inv.equip["head"] == "gasmask":
		unequip("head")
		return
	var i := inv.bag_index("gasmask")
	if i < 0:
		hud.toast("Противогаза нет")
		return
	equip(i, "head")


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


func craft(r: int) -> void:
	var rec: Dictionary = Items.RECIPES[r]
	var need: Dictionary = rec["need"]
	for id in need:
		if inv.count(id) < int(need[id]):
			hud.toast("Не хватает: %s" % Items.item_name(id))
			return
	for id in need:
		inv.remove(id, int(need[id]))
	var out: String = rec["out"]
	if inv.add(out, 1) > 0:
		var fwd := -player.global_transform.basis.z
		_make_pickup(out, 1, player.global_position + Vector3(0, 1.0, 0) + fwd * 0.4, Vector3.ZERO).need_leave = true
		hud.toast("Сумка полна — %s на полу" % Items.item_name(out))
	else:
		hud.toast("Скрафчено: %s" % Items.item_name(out), Color(0.8, 0.9, 0.6))
	play_ui("creak", -14.0, 1.6)


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


## Выбросить монеты из кошелька (запоминаем сколько — см. анти-мухлёж в cheat_check).
func drop_coins(n: int) -> void:
	n = mini(n, inv.coins)
	if n <= 0 or not inv.remove("coin", n):
		return
	dropped_coins += n
	var fwd := -player.global_transform.basis.z
	var pos := player.global_position + Vector3(0, 1.2, 0) + fwd * 0.5
	var parts := clampi(n, 1, 6)
	for k in parts:
		var cnt := n / parts + (1 if k < n % parts else 0)
		var p := _make_pickup("coin", cnt, pos, fwd * 2.0 + Vector3(randf_range(-0.6, 0.6), 1.0, randf_range(-0.6, 0.6)))
		p.need_leave = true
		p.set_meta("dropped", true)
	play_ui("coin", -11.0, 0.9)


# ---------- анти-мухлёж ----------
## Выбросил много монет (CHEAT_DROP+), оставил себе мало (≤ CHEAT_KEEP) и пошёл крутить KILLBOX —
## с поверхности по лестнице спускаются 5 монстров и охотятся на игрока прямо в бункере.
## Подобрал выброшенные монеты обратно — счётчик уменьшается.
const CHEAT_DROP := 30
const CHEAT_KEEP := 20
var dropped_coins := 0
var chests: Array = []


## Магазин: закрыть все открытые ящики — при новом открытии в них будет новый лут. Сейф не трогаем.
func refresh_chests() -> int:
	var n := 0
	for c in chests:
		if is_instance_valid(c) and c.opened:
			c.reset()
			n += 1
	return n
var hunters: Array = []


## Вызывает автомат после оплаты крутки. true — мухлёж пойман.
func cheat_check() -> bool:
	if dropped_coins < CHEAT_DROP or inv.coins > CHEAT_KEEP:
		return false
	dropped_coins = 0
	hud.cheat_warning(true)
	play_ui("buzz", -4.0, 0.55)
	_spawn_hunters()
	return true


func _spawn_hunters() -> void:
	for k in 5:
		var e := Enemy.new()
		e.game = self
		e.position = Vector3(20.0 - (k % 2) * 0.8, 4.1, -0.6 + (k % 3) * 0.6)
		e.rotation.y = PI / 2.0
		add_child(e)
		e.make_hunter()
		hunters.append(e)
		e.died.connect(_hunter_died)
		await get_tree().create_timer(0.6).timeout


func _hunter_died(e: Node) -> void:
	hunters.erase(e)
	if hunters.is_empty():
		hud.cheat_warning(false)


## Высыпать лут: монеты разбиваются на несколько монеток, разлетаются с разбросом spread.
func spawn_loot(id: String, n: int, pos: Vector3, vel: Vector3, spread: float) -> void:
	var parts := 1
	if id == "coin":
		parts = clampi(n, 1, 6)
	var per := n / parts
	var rest := n - per * parts
	for k in parts:
		var cnt := per + (1 if k < rest else 0)
		var v := vel + Vector3(randf_range(-1, 1), randf_range(0, 0.6), randf_range(-1, 1)) * spread
		_make_pickup(id, cnt, pos + Vector3(randf_range(-0.1, 0.1), 0, randf_range(-0.1, 0.1)), v)


func _make_pickup(id: String, n: int, pos: Vector3, vel: Vector3) -> Pickup:
	var p := Pickup.new()
	p.game = self
	p.id = id
	p.n = n
	add_child(p)
	p.global_position = pos
	p.linear_velocity = vel
	p.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
	return p


## Вызывается лежащим предметом, когда игрок рядом. Возвращает, сколько не влезло.
func collect(id: String, n: int, from: Node = null) -> int:
	var d: float = float(from.get_meta("dur", -1.0)) if from != null else -1.0
	var left: int = inv.add(id, n, d)
	var got := n - left
	if id == "coin" and from != null and from.get_meta("dropped", false):
		dropped_coins = maxi(dropped_coins - got, 0)
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
