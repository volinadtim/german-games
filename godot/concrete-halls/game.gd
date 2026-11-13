extends Node3D
## Тестовые механики — связка: HUD, инвентарь, здоровье игрока, взаимодействие на E, лут на полу,
## враги, манекен, ящики/сейф, игровой автомат, фонарик. Создаётся из main.gd (_enter_game).
## Каждая механика — свой скрипт; ненужную выключить флагом ниже (или удалить её файл и строку _spawn_*).
##   Управление: E — взаимодействие, Tab/I — инвентарь, F — фонарик, Q — быстро полечиться.

const Player := preload("res://player.gd")
const Hud := preload("res://hud.gd")
const Inventory := preload("res://inventory.gd")
const Items := preload("res://items.gd")
const Pickup := preload("res://pickup.gd")
const Flashlight := preload("res://flashlight.gd")
const Enemy := preload("res://enemy.gd")
const Dummy := preload("res://dummy.gd")
const Chest := preload("res://chest.gd")
const SlotMachine := preload("res://slot_machine.gd")
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
const ENEMY_SPOTS := [Vector3(6.5, 0.05, -5.5), Vector3(4.0, 0.05, 5.0), Vector3(-3.0, 0.05, 6.0)]
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
	add_child(inv)
	inv.changed.connect(func(): hud.set_coins(inv.count("coin")))
	inv.use_requested.connect(use_item)
	inv.drop_requested.connect(drop_item)
	hud.set_hp(hp, MAX_HP)

	if USE_FLASHLIGHT:
		flashlight = Flashlight.new()
		flashlight.game = self
		add_child(flashlight)
		flashlight.attach(player.cam)

	# стартовый набор, чтобы сразу было что попробовать
	inv.add("coin", 3)
	inv.add("bandage", 1)

	if USE_DUMMY:
		var d := Dummy.new()
		d.position = Vector3(-8.6, 0.0, -0.95)
		add_child(d)
	if USE_ENEMIES:
		for s in ENEMY_SPOTS:
			_spawn_enemy(s)
	if USE_CHESTS:
		_chest(Vector3(-3.0, 0.0, -8.5), 0.0, [])
		_chest(Vector3(9.0, 0.0, -8.5), 0.0, [["key", 1]])           # ключ от сейфа
		_chest(Vector3(-11.5, 0.0, 3.2), PI / 2.0, [])
		var safe := Chest.new()
		safe.kind = "safe"
		safe.need_key = "key"
		safe.random_loot = false
		safe.extra = [["knuckles", 1], ["coin", 15], ["medkit", 1], ["battery", 1]]
		safe.position = Vector3(11.5, 0.0, 7.0)
		safe.rotation.y = -PI / 2.0
		add_child(safe)
	if USE_SLOTS:
		var sm := SlotMachine.new()
		sm.position = Vector3(-6.0, 0.0, 8.5)
		sm.rotation.y = PI
		add_child(sm)


func _chest(pos: Vector3, rot: float, extra: Array) -> void:
	var c := Chest.new()
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


func _unhandled_input(e: InputEvent) -> void:
	if not alive or player == null:
		return
	if e.is_action_pressed("interact"):
		if focus != null and is_instance_valid(focus):
			focus.interact(self)
	elif e.is_action_pressed("flashlight") and flashlight:
		flashlight.toggle()
	elif e.is_action_pressed("quick_heal"):
		_quick_heal()


# ---------- здоровье ----------

func damage_player(amount: float, from: Vector3) -> void:
	if not alive:
		return
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


func heal(amount: float) -> void:
	hp = minf(hp + amount, MAX_HP)
	hud.set_hp(hp, MAX_HP)


func _die() -> void:
	alive = false
	player.active = false
	inv.close()
	inv.enabled = false
	hud.show_death(true)
	await get_tree().create_timer(3.0).timeout
	player.global_position = START
	player.rotation.y = -PI / 2.0
	player.velocity = Vector3.ZERO
	hp = MAX_HP
	hud.set_hp(hp, MAX_HP)
	hud.show_death(false)
	alive = true
	player.active = true
	inv.enabled = true
	hud.toast("Ты очнулся у входа")


func _quick_heal() -> void:
	if hp >= MAX_HP:
		hud.toast("Здоровье и так полное")
		return
	# самое маленькое лечение, которого хватает; иначе самое большое
	var need := MAX_HP - hp
	var best := ""
	var best_v := INF
	var biggest := ""
	var biggest_v := 0.0
	for id in ["rusk", "bandage", "medkit"]:
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
	if def.has("heal"):
		if hp >= MAX_HP:
			hud.toast("Здоровье и так полное")
			return
		inv.take_at(idx, 1)
		heal(def["heal"])
		hud.toast("%s: +%d здоровья" % [def["name"], int(def["heal"])], Color(0.7, 0.9, 0.6))
		play_ui("pickup", -12.0, 0.8)
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
	elif id == "knuckles":
		inv.take_at(idx, 1)
		player.dmg_mult = 1.5
		hud.knuckles = true
		hud.toast("Кастет надет: удары сильнее", Color(0.9, 0.85, 0.7))
		play_ui("coin", -12.0, 0.6)
	elif id == "coin":
		hud.toast("Монеты тратятся в игровом автомате")
	elif id == "key":
		hud.toast("Ключ подходит к сейфу — подойди к нему и нажми E")
	else:
		hud.toast("Это нельзя использовать")


func drop_item(idx: int, all: bool) -> void:
	var s = inv.slots[idx]
	if s == null:
		return
	var got: Array = inv.take_at(idx, int(s["n"]) if all else 1)
	if got[1] <= 0:
		return
	var fwd := -player.global_transform.basis.z
	var pos := player.global_position + Vector3(0, 1.2, 0) + fwd * 0.5
	var p := _make_pickup(got[0], got[1], pos, fwd * 2.0 + Vector3(0, 1.0, 0))
	p.need_leave = true


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
func collect(id: String, n: int) -> int:
	var left: int = inv.add(id, n)
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
