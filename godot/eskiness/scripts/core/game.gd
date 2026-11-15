extends "res://scripts/core/game_save.gd"
## Тестовые механики — связка: HUD, инвентарь, здоровье игрока, взаимодействие на E, лут на полу,
## враги, манекен, ящики/сейф, игровой автомат, фонарик. Создаётся из main.gd (_enter_game).
## Каждая механика — свой скрипт; ненужную выключить флагом ниже (или удалить её файл и строку _spawn_*).
##   Управление: E — взаимодействие, Tab/I — инвентарь, F — фонарик, Q — быстро полечиться.


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
	inv.repair_requested.connect(repair)
	inv.message.connect(func(t: String): hud.toast(t))
	hud.inv = inv
	hud.set_hp(hp, MAX_HP)
	hud.restart_pressed.connect(restart)
	hud.menu_pressed.connect(to_main_menu)

	if USE_FLASHLIGHT:
		flashlight = Flashlight.new()
		flashlight.game = self
		add_child(flashlight)
		flashlight.attach(player.cam)

	# стартовый набор (крутка автомата — 10 монет). Фонарика нет — он в магазине снаряжения.
	inv.add("coin", 50)
	inv.add("bandage", 2)

	if USE_DUMMY:
		# манекен — в левой комнате, ближайшей к старту (северо-западная)
		var d := Dummy.new()
		d.game = self
		d.position = Vector3(-8.0, 0.0, -3.6)
		add_child(d)
	if USE_ENEMIES and (net == null or net.is_host()):   # в сети враги — у хоста, клиенту приходят копии
		for s in ENEMY_SPOTS:
			_spawn_enemy(s)
	if USE_CHESTS:
		# лутбоксы — кувшины и колбы, случайно каждую новую игру — ниже, после стекла (_random_jars)
		# сейф открывается только тремя семёрками на автомате KILLBOX (open_safe)
		safe = Chest.new()
		safe.kind = "safe"
		safe.locked = true
		safe.random_loot = false
		# пистолет без патронов, полный магазин и россыпь патронов (промпт 14.11 19:49)
		safe.extra = [["pistol", 1, 0.0], ["mag", 1, 8.0], ["ammo", randi_range(12, 16)], ["car_key", 1], ["knuckles", 1], ["coin", 80], ["medkit", 2], ["battery", 1], ["canned", 2], ["wallet", 2]]
		safe.position = Vector3(11.54, 0.0, 7.0)   # задняя стенка вплотную к стене
		safe.rotation.y = -PI / 2.0
		add_child(safe)
	# противогаз и отравленный воздух наверху (G)
	gun = Gun.new()
	gun.game = self
	add_child(gun)
	player.gun = gun
	player.game = self
	stone_throw = StoneThrow.new()
	stone_throw.game = self
	add_child(stone_throw)
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
		# новая игра в той же сессии: автомат общий с меню — сбрасываем (загрузка сейва выставит своё)
		slot.credits = 0
		slot.luck = {}
		slot.boost = {}
		slot.set_level(1)
		slot.set_tray(0)
		slot.set_shield(0)
		slot.set_reveal_pending(false)
	# изолента, приклеенная к доске выплат у автомата (берётся на E, со временем появляется снова)
	_spawn_stone_piles()
	tape = TapeSpot.new()
	tape.game = self
	tape.position = Vector3(-7.05, 0.95, 8.813)   # на самой доске выплат (main.gd прижимает её к стене)
	add_child(tape)
	# осколки стекла на полу (там, где битое стекло) — материал для ножика
	loot_window = LootWindow.new()
	loot_window.game = self
	add_child(loot_window)
	# сундук-хранилище (один, у старта): складывать вещи (промпт 00:08)
	storage = Chest.new()
	storage.game = self
	storage.kind = "storage"
	storage.position = Vector3(-11.55, 0.0, -2.7)   # вплотную к стене (был зазор 11 см)
	storage.rotation.y = PI / 2.0
	add_child(storage)
	glass_floor = GlassFloor.new()
	add_child(glass_floor)
	glass_floor.generate()
	for sp in glass_floor.spots:
		_make_pickup("glass", 1, (sp[0] as Vector3) + Vector3(0.2, 0.1, 0.2), Vector3.ZERO)
	# старая машина на поляне — до кувшинов, чтобы они её обходили
	var surf_node: Node = get_parent().get_node_or_null("Level/Surface")
	if surf_node:
		car = Car.new()
		car.game = self
		car.surface = surf_node
		car.position = Surface.CAR_POS
		car.rotation.y = Surface.CAR_YAW
		add_child(car)
	if USE_CHESTS:
		_random_jars()
	shop = get_parent().get_node_or_null("Shop") as Shop
	if shop:
		shop.game = self
	# сохранения: загрузить выбранный слот (menu.gd) или начать новую игру в нём
	save_slot = Save.slot()
	if net:
		net.on_game_setup(self)   # сетевая сессия в слоты сохранений не пишет; мир у клиента — от хоста
	elif Engine.get_meta("eskiness_load", false) and Save.exists(save_slot):
		load_state(Save.read(save_slot))
	else:
		save_now()


# ---------- взаимодействие ----------

## Пока открыто любое окно (инвентарь, лут, магазин, продажа, автомат) — курсор всегда виден:
## кто бы ни вернул захват (закрытие подокна, клик, стойка), снимаем его (баг 14.11 20:05).
func _process(_delta: float) -> void:
	if alive and window_open() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	full_toast_t -= delta
	if alive:
		play_time += delta
	_outside_jar_tick(delta)
	autosave_t -= delta
	if autosave_t <= 0.0:
		autosave_t = AUTOSAVE
		save_now()
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
		var hit_d := 99.0
		if hit and hit.collider.has_method("interact"):
			focus = hit.collider
			text = hit.collider.get_prompt(self)
			hit_d = from.distance_to(hit.position)
		# лежащий предмет под прицелом (pickup.gd) — ближе, чем другая цель
		var pk := _aimed_pickup(from, -player.cam.global_transform.basis.z)
		if pk != null and from.distance_to(pk.global_position) < hit_d:
			focus = pk
			text = pk.get_prompt(self)
	hud.prompt(text)


## Предмет на полу, на который смотрит игрок: в пределах Pickup.REACH, в узком конусе взгляда
## (чем ближе, тем шире — маленькую вещь легко навести), и не за стеной.
func _aimed_pickup(from: Vector3, fwd: Vector3) -> Node:
	var best: Node = null
	var best_a := 99.0
	for p in get_tree().get_nodes_in_group("pickup"):
		if p.taken:
			continue
		var to: Vector3 = p.global_position + Vector3(0, 0.06, 0) - from
		var d := to.length()
		if d > Pickup.REACH or d < 0.05:
			continue
		var a := fwd.angle_to(to)
		if a > maxf(deg_to_rad(8.0), atan(0.3 / d)) or a >= best_a:
			continue
		var q := PhysicsRayQueryParameters3D.create(from, from + to * 0.97)
		q.collision_mask = 1
		q.exclude = [player.get_rid()]
		if get_world_3d().direct_space_state.intersect_ray(q):
			continue
		best = p
		best_a = a
	return best


## Одно окно за раз: пока открыт инвентарь или магазин, другие окна не открываются.
func window_open() -> bool:
	return (inv != null and inv.open) or (shop != null and shop.opened) or (slot != null and slot.pack_open) \
		or (loot_window != null and loot_window.open)


## Открыть окно лута: obj с полем contents [[id, n], ...] (ящик, сейф, сундук, кувшин…).
func open_loot(c) -> void:
	if not alive or (window_open() and not (loot_window and loot_window.open)):
		return
	loot_window.show_for(c)


## Разовый лут (разбитый кувшин/колба): окно с items [[id, n], ...]; не взятое высыпется на пол в pos.
func open_loot_items(items: Array, pos: Vector3, title := "ЛУТ") -> void:
	var bag := LootWindow.LootBag.new()
	bag.game = self
	bag.pos = pos
	bag.loot_title = title
	for it in items:
		bag.contents.append([String(it[0]), int(it[1])])
	if not alive or window_open():
		bag.on_loot_closed()
		return
	loot_window.show_for(bag)


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


func _glass(delta: float) -> void:
	glass_cd -= delta
	# сапоги от ходьбы больше не стираются (14.11 21:13) — только стекло и удары врагов
	if bleed_t > 0.0:
		bleed_t = maxf(bleed_t - delta, 0.0)
		drain_hp(BLEED_DPS * delta)
		if not alive:
			bleed_t = 0.0
	hud.bleed = bleed_t
	var pp := player.global_position
	var now := false
	if alive and player.is_on_floor() and pp.y < 0.4:
		for g in glass_floor.spots:
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


## Сел в машину (car.gd): игрок больше не управляется, враги и отрава его не трогают, HUD прячется.
func begin_escape() -> void:
	alive = false
	won = true
	player.active = false
	inv.close()
	inv.enabled = false
	if loot_window and loot_window.open:
		loot_window.close()
	hud.set_cinematic(true)
	if gasmask:
		gasmask.visible = false
	for n in get_parent().get_children():
		if n.get_script() == preload("res://scripts/ui/touch_controls.gd"):
			n.visible = false


## Машина уехала: экран победы со статистикой.
func win() -> void:
	var s := int(play_time)
	hud.show_win("Время: %d:%02d   ·   Монет: %d" % [s / 60, s % 60, inv.coins])


## «В главное меню» с экрана победы.
func to_main_menu() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().reload_current_scene()


## «Начать заново»: полный сброс — сцена перезагружается и сразу стартует игра (main.gd), минуя меню.
func restart() -> void:
	Engine.set_meta("eskiness_autostart", true)
	Engine.set_meta("eskiness_load", false)    # новая игра в том же слоте
	get_tree().paused = false
	get_tree().reload_current_scene()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_now()
