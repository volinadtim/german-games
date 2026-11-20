extends "res://scripts/core/game_save.gd"
## Тестовые механики — связка: HUD, инвентарь, здоровье игрока, взаимодействие на E, лут на полу,
## враги, манекен, ящики/сейф, игровой автомат, фонарик. Создаётся из main.gd (_enter_game).
## Каждая механика — свой скрипт; ненужную выключить флагом ниже (или удалить её файл и строку _spawn_*).
##   Управление: E — взаимодействие, Tab/I — инвентарь, F — фонарик, Q — быстро полечиться.


func setup(p: Player) -> void:
	player = p
	mode = _pick_mode()
	_setup_input()
	_make_sounds()
	ui_player = AudioStreamPlayer.new()
	ui_player.max_polyphony = 3
	add_child(ui_player)
	audio = Audio.new()
	audio.name = "AudioMixer"
	add_child(audio)

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
	inv.unequip_requested.connect(func(slot_: String, to: int):
		if to < 0 and inv.has_method("_try_stack_unequip") and inv._try_stack_unequip(slot_):
			return
		unequip(slot_, to))
	inv.drop_equipped_requested.connect(drop_equipped)
	inv.craft_requested.connect(craft)
	inv.repair_requested.connect(repair)
	inv.message.connect(func(t: String): hud.toast(t))
	inv.spilled.connect(drop_spilled)
	hud.inv = inv
	hud.minimal = mode == MODE_REAL
	hud.set_hp(hp, MAX_HP)
	hud.restart_pressed.connect(restart)
	hud.menu_pressed.connect(to_main_menu)
	var con = preload("res://scripts/ui/console.gd").new()   # F1 — консоль (ui/console.gd)
	con.game = self
	add_child(con)
	chat = preload("res://scripts/ui/chat.gd").new()   # T — чат (ui/chat.gd), в сети — всем
	chat.game = self
	add_child(chat)
	revive = preload("res://scripts/systems/revive.gd").new()   # смерть, подъём союзника, лечение с полоской
	revive.game = self
	add_child(revive)
	last_chance = preload("res://scripts/systems/last_chance.gd").new()   # «Это последний шанс!» — 23 монеты, когда застрял
	last_chance.game = self
	add_child(last_chance)

	if USE_FLASHLIGHT:
		flashlight = Flashlight.new()
		flashlight.game = self
		add_child(flashlight)
		flashlight.attach(player.cam)

	# стартовый набор: 25 монет (промпт 16.11 21:46). Фонарика нет — он в магазине снаряжения.
	# Одежда (футболка, штаны, вещмешок) и бинты не надеты — лежат на полу рядом со спавном (intro.gd: _starter_kit).
	inv.update_blocks()
	inv.add("coin", 25)

	if USE_DUMMY:
		# манекен — в комнате с KILLBOX (юго-западная), слева от магазина, рядом с сундуком (промпт 16.11 03:13)
		# в боку торчит стеклянный нож (промпт 18.11 01:07/01:38 — второй манекен убран, нож в этом же)
		var d := Dummy.new()
		d.game = self
		d.knife = true
		d.position = DUMMY_POS
		add_child(d)
		knife_dummy = d
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
		safe.extra = [["pistol", 1, 0.0], ["mag", 1, 8.0], ["ammo", randi_range(12, 16)], ["car_key", 1], ["knuckles", 1], ["coin", 80], ["medkit", 2], ["wallet", 2]]   # без батарейки и тушёнки (промпт 16.11 02:47)
		# в комнате с KILLBOX (юго-западная), у западной стены (промпт 18.11 00:46); задняя стенка вплотную к стене
		safe.position = Vector3(-11.54, 0.0, 5.6)
		safe.rotation.y = PI / 2.0
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
	player.stone_throw = stone_throw
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
		slot.sevens_hit = false
		slot.profit = 0
		slot.capped = false
		slot.bank = 0
		slot.set_level(1)
		slot.set_tray(0)
		slot.set_shield(0)
		slot.set_reveal_pending(false)
	# изолента, приклеенная к доске выплат у автомата (берётся на E, со временем появляется снова)
	_spawn_stone_piles()
	preload("res://scripts/world/wood_source.gd").spawn_all(self)   # деревья и доски на поляне — топорик (промпт 16.11 02:42)
	tape = TapeSpot.new()
	tape.game = self
	tape.position = Vector3(-7.05, 0.95, 8.813)   # на самой доске выплат (main.gd прижимает её к стене)
	add_child(tape)
	add_child(preload("res://scripts/world/exit_sign.gd").new())   # табличка «только в противогазе» над выходом к лестнице
	# осколки стекла на полу (там, где битое стекло) — материал для ножика
	loot_window = LootWindow.new()
	loot_window.game = self
	add_child(loot_window)
	# сундук-хранилище: складывать вещи (промпт 00:08) — у южной стены слева от магазина, рядом с манекеном (16.11 03:13)
	storage = Chest.new()
	storage.game = self
	storage.kind = "storage"
	storage.position = STORAGE_POS   # вплотную к стене
	storage.rotation.y = PI
	add_child(storage)
	home = preload("res://scripts/world/bunker_home.gd").new()
	home.game = self
	add_child(home)
	carry = preload("res://scripts/world/carry.gd").new()
	carry.game = self
	add_child(carry)
	glass_floor = GlassFloor.new()
	add_child(glass_floor)
	_collect_obstacles()
	glass_floor.generate(func(gp: Vector3, r: float) -> bool: return not _on_object(gp, r))
	for sp in glass_floor.spots:
		_make_pickup("glass", 1, (sp[0] as Vector3) + Vector3(0.2, 0.1, 0.2), Vector3.ZERO)
	# старая машина на поляне — до кувшинов, чтобы они её обходили
	var surf_node: Node = get_parent().get_node_or_null("Level/Surface")
	if surf_node:
		# вторая локация — деревня в конце дороги (village.gd), стоит всегда; машина ездит по её высотам
		village = Village.new()
		village.level = get_parent().get_node_or_null("Level")
		village.surface = surf_node
		add_child(village)
		car = Car.new()
		car.game = self
		car.surface = village
		car.village = village
		car.position = Surface.CAR_POS
		car.rotation.y = Surface.CAR_YAW
		add_child(car)
		village.car = car
		village.setup_game(self)
		if net:
			VillageNet.ensure(self)
		if net == null or net.is_host():
			village.spawn_village_loot()
	if USE_CHESTS:
		_random_jars()
	shop = get_parent().get_node_or_null("Shop") as Shop
	if shop:
		shop.game = self
	# сохранения: загрузить выбранный слот (menu.gd) или начать новую игру в нём
	takedown = preload("res://scripts/world/takedown.gd").new()
	takedown.game = self
	add_child(takedown)
	var cs = preload("res://scripts/ui/cutscene_skip.gd").new()   # пропуск кат-сцен (промпт 18.11 00:49)
	cs.game = self
	add_child(cs)
	save_slot = Save.slot()
	if save_slot == "":
		save_slot = Save.new_id()
		Engine.set_meta("eskiness_slot", save_slot)
	# что грузим: сам сейв или его аварийную копию (вылет игры, save.gd: write_crash)
	var sd: Dictionary = {}
	if bool(Engine.get_meta("eskiness_load", false)):
		if bool(Engine.get_meta("eskiness_crash", false)) and Save.crash_exists(save_slot):
			sd = Save.read_crash(save_slot)
		else:
			sd = Save.read(save_slot)
	if net and not net.is_host():
		# клиент: мир и свои вещи присылает хост (сейв сетевой игры лежит у хоста)
		preload("res://scripts/slot/slot_net.gd").ensure(self)   # автоматы общие (промпт 18.11 02:13)
		net.on_game_setup(self)
		if not net.skip_intro:
			_start_intro()   # одна комната, своё место, одна кат-сцена (промпт 16.11 22:04)
	elif net:
		# хост сетевой игры сохраняется как обычно, в свой сейв (промпт 18.11 02:00)
		if sd.is_empty():
			_start_intro()
		else:
			from_save = true
			load_state(sd)
			var np = sd.get("net_players", {})
			net.net_saves = np if np is Dictionary else {}
			if not bool(sd.get("intro_done", true)):
				_start_intro(false, intro_wake_done)
		preload("res://scripts/slot/slot_net.gd").ensure(self)
		net.on_game_setup(self)
		save_now()
	elif not sd.is_empty():
		from_save = true
		load_state(sd)
		# вышли до конца вступления — оно начинается заново, вещи из сейва остаются (промпт 16.11 21:46)
		# пробуждение уже показано (промпт 18.11 01:10) — сразу с места из сейва, без кат-сцены «встаёт»
		if not bool(sd.get("intro_done", true)):
			_start_intro(false, intro_wake_done)
	else:
		_start_intro()
		save_now()


## Новая игра: пробуждение в северо-западной комнате и заблудший монстрик (world/intro.gd, промпт 16.11 03:13).
func _start_intro(new_game := true, skip_wake := false) -> void:
	var intro = preload("res://scripts/world/intro.gd").new()
	intro.game = self
	intro.name = "Intro"   # одинаковый путь у всех игроков — для rpc кат-сцены
	add_child(intro)
	intro.start(new_game, skip_wake)


## Первое закрытие магазина (shop_ui.gd _close, промпт 16.11 21:55): камера к выходу на улицу, оттуда звуки монстров.
func shop_cue() -> void:
	if shop_cue_done or not alive or player == null or not player.input_locks.is_empty() or window_open():
		return
	shop_cue_done = true
	var cue = preload("res://scripts/world/shop_cue.gd").new()
	cue.game = self
	add_child(cue)
	cue.start()


# ---------- взаимодействие ----------

## Пока открыто любое окно (инвентарь, лут, магазин, продажа, автомат) — курсор всегда виден:
## кто бы ни вернул захват (закрытие подокна, клик, стойка), снимаем его (баг 14.11 20:05).
func _process(_delta: float) -> void:
	if alive and window_open() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif not alive and hud != null and hud.death_on and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	full_toast_t -= delta
	if alive:
		play_time += delta
	if _drop_mode and _drop_side != "":
		_drop_charge = minf(_drop_charge + delta, DROP_MAX_CHARGE)
		if _drop_ui:
			_drop_ui.queue_redraw()
	_outside_jar_tick(delta)
	autosave_t -= delta
	if autosave_t <= 0.0:
		autosave_t = AUTOSAVE
		save_now()
	# доп. сохранение (промпт 18.11 02:00): отдельный файл, основной сейв не перезаписывает —
	# после вылета (в том числе с ошибкой) его видно в списке сохранений как «аварийный»
	crash_t -= delta
	if crash_t <= 0.0:
		crash_t = CRASH_SAVE
		save_crash()
	if player == null:
		return
	focus = null
	var text := ""
	_glass(delta)
	_tick_buffs(delta)
	if alive:
		var from := player.cam.global_position
		var q := PhysicsRayQueryParameters3D.create(from, from - player.cam.global_transform.basis.z * 2.3)
		q.collision_mask = 1 | StonePile.LAYER   # кучки камней — на своём слое (сквозь них проходят, промпт 03:34)
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
		# мелкий враг спиной к игроку рядом — E: добить (world/takedown.gd)
		if takedown and takedown.candidate() != null:
			focus = takedown
			text = takedown.get_prompt(self)
	if carry and alive:
		# манекен и т.п. без interact() не попадают в focus — для B берём цель луча переноски (05:04)
		var ct: Object = focus if focus != null else carry._aim()
		var ch: String = carry.hint(ct)
		if ch != "":
			text = ch if text == "" or carry.held else text + "   " + ch
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


## Закрыть все окна (инвентарь, магазин с продажей, наборы KILLBOX, лут) — перед кат-сценой (промпт 16.11 21:40).
## Вызывать ДО блокировки игрока: _close магазина/наборов возвращают player.active = true.
func close_windows() -> void:
	if inv != null and inv.open:
		inv.close()
	if shop != null and shop.opened:
		shop._close()
	if slot != null and slot.pack_open:
		slot.close_packs()
	if loot_window != null and loot_window.open:
		loot_window.close()


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
	if _drop_mode:
		if not e.is_echo() and (e.is_action_pressed("drop_mode") or e.is_action_pressed("ui_cancel")):
			_drop_cancel()
			get_viewport().set_input_as_handled()
			return
		# кнопки рук — действия (ЛКМ/ПКМ, на геймпаде RT/LT, переназначаются в настройках)
		var side := ""
		if e.is_action("attack_left"):
			side = "left"
		elif e.is_action("attack_right"):
			side = "right"
		if side != "" and not e.is_echo():
			if e.is_pressed() and _drop_side == "":
				if inv.equip.get(side, "") == "":
					hud.toast("В %s руке пусто" % ("левой" if side == "left" else "правой"), Color(0.9, 0.5, 0.4))
					_drop_cancel()
				else:
					_drop_side = side
					_drop_charge = 0.0
					if _drop_ui: _drop_ui.queue_redraw()
			elif not e.is_pressed() and _drop_side == side:
				_drop_execute(side, _drop_charge)
			get_viewport().set_input_as_handled()
			return

	if not alive or player == null or window_open():
		return
	if e.is_action_pressed("interact") and not e.is_echo():
		if focus != null and is_instance_valid(focus):
			focus.interact(self)
	elif e.is_action_pressed("quick_heal"):
		_quick_heal()
	elif e.is_action_pressed("swap_hands") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		swap_hands()
	elif e.is_action_pressed("drop_mode") and not e.is_echo():   # H (была G — совпадала с противогазом)
		_drop_menu_open()
		get_viewport().set_input_as_handled()
	else:
		for k in 5:
			if e.is_action_pressed("hot_%d" % (k + 1)):
				# в правую — с «hand_right» (Shift; геймпад — задержать кнопку слота, ui/gamepad.gd)
				var to_right: bool = InputMap.has_action("hand_right") and Input.is_action_pressed("hand_right")
				hotbar_use_hand(k, "right" if to_right else "left")
				break


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
	if alive and player.active and player.is_on_floor() and pp.y < 0.4:   # в кат-сценах стекло не срабатывает (промпт 16.11 04:12)
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
	close_windows()
	alive = false
	won = true
	player.active = false
	inv.close()
	inv.enabled = false
	if loot_window and loot_window.open:
		loot_window.close()
	hud.set_cinematic(true)
	player.cinematic_stance(true)
	if gasmask:
		gasmask.visible = false
	for n in get_parent().get_children():
		if n.get_script() == preload("res://scripts/ui/touch_controls.gd"):
			n.visible = false


## Кат-сцена кончилась (village.gd): снова игра — игрок уже сидит в машине.
func end_cinematic() -> void:
	alive = true
	won = false   # иначе на 2-й локации экран смерти с кнопками не появлялся (revive.gd)
	inv.enabled = true
	hud.set_cinematic(false)
	player.cinematic_stance(false)
	if gasmask:
		gasmask.visible = true
	for n in get_parent().get_children():
		if n.get_script() == preload("res://scripts/ui/touch_controls.gd"):
			n.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Машина уехала: экран победы со статистикой.
func win() -> void:
	var s := int(play_time)
	@warning_ignore("integer_division")
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
	Engine.set_meta("eskiness_mode", mode)     # тот же режим
	get_tree().paused = false
	get_tree().reload_current_scene()

func hotbar_use_hand(k: int, hand_slot: String) -> void:
	var hb_val: Variant = inv.hotbar[k] if k < inv.hotbar.size() else null
	if hb_val == null:
		return
	# за рулём вторую руку не занимаем: слот берётся в ту руку, что уже держит предмет (промпт 20.11 11:40)
	var dh := drive_hand()
	if dh != "" and inv.equip.get("left" if hand_slot == "right" else "right", "") != "":
		hand_slot = dh

	var src_idx := -1
	var target_id := ""
	if hb_val is Dictionary:
		target_id = String(hb_val.get("id", ""))
	elif hb_val is String:
		target_id = hb_val
	elif hb_val is int and hb_val >= 0 and hb_val < inv.slots.size() and inv.slots[hb_val] != null:
		src_idx = hb_val
		target_id = String(inv.slots[hb_val]["id"])

	var cur_id: String = inv.equip.get(hand_slot, "")
	if cur_id != "" and cur_id == target_id:
		_safe_unequip_to_bag(hand_slot)
		return

	if target_id == "":
		return

	if src_idx < 0:
		for i in inv.slots.size():
			if inv.slots[i] != null and String(inv.slots[i]["id"]) == target_id:
				src_idx = i
				break

	if src_idx < 0 or not Items.fits(target_id, hand_slot):
		return

	if cur_id != "":
		if not _safe_unequip_to_bag(hand_slot):
			return

	var s: Dictionary = inv.slots[src_idx]
	var dur := float(s.get("dur", -1.0))
	var got: Array = inv.take_at(src_idx, 1)
	if int(got.get(1)) <= 0:
		return
	inv.equip[hand_slot] = target_id
	if dur >= 0.0:
		inv.equip_dur[hand_slot] = dur
	else:
		inv.equip_dur.erase(hand_slot)
	_apply_equip(hand_slot)
	inv.notify()


func _safe_unequip_to_bag(hand_slot: String) -> bool:
	var eid: String = inv.equip.get(hand_slot, "")
	if eid == "":
		return true
	if inv.has_method("_try_stack_unequip") and inv._try_stack_unequip(hand_slot):
		return true
	if inv.find_place(eid).is_empty():
		hud.toast("В инвентаре нет места", Color(0.95, 0.5, 0.4))
		play_ui("buzz", -14.0)
		return false
	unequip(hand_slot, -1)
	return inv.equip.get(hand_slot, "") == ""


var _drop_ui: Control
var _drop_mode := false
var _drop_side := ""
var _drop_charge := 0.0
const DROP_MAX_CHARGE := 1.2
const DROP_TAP_T := 0.18

func _drop_menu_open() -> void:
	if inv.equip.get("left", "") == "" and inv.equip.get("right", "") == "":
		hud.toast("В руках пусто", Color(0.75, 0.72, 0.65))
		return
	_drop_mode = true
	_drop_side = ""
	_drop_charge = 0.0
	if _drop_ui == null:
		var cl := CanvasLayer.new()
		cl.layer = 5
		add_child(cl)
		_drop_ui = Control.new()
		_drop_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
		_drop_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_drop_ui.draw.connect(_drop_ui_draw)
		cl.add_child(_drop_ui)
	_drop_ui.visible = true
	_drop_ui.queue_redraw()

func _drop_cancel() -> void:
	_drop_mode = false
	_drop_side = ""
	_drop_charge = 0.0
	if _drop_ui: _drop_ui.visible = false

func _drop_execute(side: String, hold_t: float) -> void:
	_drop_cancel()
	var id: String = inv.equip.get(side, "")
	if id == "": return
	var power := clampf((hold_t - DROP_TAP_T) / (DROP_MAX_CHARGE - DROP_TAP_T), 0.15, 1.0) if hold_t > DROP_TAP_T else 0.0
	if power <= 0.0:
		drop_equipped(side)
		return
	var dur: float = inv.get_dur(side)
	inv.equip[side] = ""
	inv.equip_dur.erase(side)
	_apply_equip(side)
	inv.notify()
	var fwd := -player.cam.global_transform.basis.z.normalized()
	var right := player.cam.global_transform.basis.x.normalized() * (-1.0 if side == "left" else 1.0)
	var pk = _make_pickup(id, 1, player.cam.global_position + fwd * 0.45 + right * 0.15 - Vector3(0, 0.1, 0), fwd * lerpf(4.0, 14.0, power) + Vector3.UP * lerpf(1.5, 4.5, power))
	if pk != null and dur >= 0.0: pk.set_meta("dur", dur)
	play_ui("whoosh" if power > 0.5 else "pickup", -12.0, 1.1)

func _drop_ui_draw() -> void:
	var vp := _drop_ui.get_viewport_rect().size
	var cx := vp.x * 0.5
	var y0 := vp.y * 0.74
	var f := ThemeDB.fallback_font
	_drop_ui.draw_string(f, Vector2(cx - 200.0, y0 - 12.0), "ЛКМ / ПКМ (RT / LT) — выбросить (держать — кинуть дальше) | ещё раз — отмена", HORIZONTAL_ALIGNMENT_CENTER, 400.0, 14, Color(0.95, 0.9, 0.8, 0.85))
	for side_info in [["left", Rect2(cx - 98.0, y0, 92.0, 64.0), "Левая"], ["right", Rect2(cx + 6.0, y0, 92.0, 64.0), "Правая"]]:
		var s_key: String = side_info.get(0)
		var rect: Rect2 = side_info.get(1)
		var has_item: bool = inv.equip.get(s_key, "") != ""
		var active_s: bool = (_drop_side == s_key)
		_drop_ui.draw_rect(rect, Color(0.55, 0.22, 0.14, 0.65) if active_s else Color(0.06, 0.05, 0.04, 0.45))
		_drop_ui.draw_rect(rect, Color(1.0, 0.72, 0.45, 0.9) if active_s else Color(1.0, 1.0, 1.0, 0.25), false, 1.5)
		var col := Color(1.0, 0.92, 0.8, 0.95) if has_item else Color(0.6, 0.6, 0.6, 0.35)
		_drop_ui.draw_string(f, Vector2(rect.position.x, rect.position.y + 26.0), side_info.get(2), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 14, col)
		_drop_ui.draw_string(f, Vector2(rect.position.x + 4.0, rect.position.y + 48.0), Items.item_name(inv.equip.get(s_key, "")) if has_item else "Пусто", HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 8.0, 12, col)
	if _drop_side != "" and _drop_charge > DROP_TAP_T:
		var power := clampf((_drop_charge - DROP_TAP_T) / (DROP_MAX_CHARGE - DROP_TAP_T), 0.0, 1.0)
		_drop_ui.draw_rect(Rect2(cx - 100.0, y0 + 72.0, 200.0, 12.0), Color(0, 0, 0, 0.6))
		_drop_ui.draw_rect(Rect2(cx - 98.0, y0 + 74.0, 196.0 * power, 8.0), Color(0.95, 0.65, 0.25, 0.95))

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_exit()
	elif what == NOTIFICATION_CRASH:
		save_crash()
