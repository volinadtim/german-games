extends "res://scripts/slot/slot_machine_board.gd"
## Игровой автомат KILLBOX (слоты): E — крутка (крутки покупаются пакетами).
## Окно 3 ряда × 5 барабанов, но открыта только часть — окно прокачивается за монеты (LEVELS):
##   ур.1 — 1×3 (центр), 2 — 2×3, 3 — 3×3, 4 — 3×4, 5 — 3×5. Закрытые клетки — под стальными заслонками
##   и в выигрыше не участвуют. Барабаны — настоящие цилиндры с отпечатанной лентой символов,
## вращаются и останавливаются по очереди. Линии строятся под открытую область (lines_for):
##   ряды (3+ одинаковых подряд), галочки (на 2×3), диагонали по 3 клетки, мостики по 4.
##   3 шестёрки где угодно в открытом окне — автомат забирает одну вещь, купленную в магазине (промпт 15.11 23:03).
##   3 семёрки на линии — открывают сейф; если сейф уже открыт — 30 монет. Семёрки и шестёрки
##   есть в барабанах только на окне 3×5 (LEVEL_SYMS).
## 4+ семёрки или 4+ шестёрки в открытом окне не выпадают никогда (исключены при генерации).
## Справа от автомата на стене — доска выплат. Автомат стоит в тёмной комнате и мерцает.
## Вид: над вывеской — арка с черепом и венцом из шипов, по углам лампы в проволочных клетках,
## неоновые буквы KILLBOX (одна «О» барахлит), лоток для монет — «пасть» с зубами и красным жаром,
## решётки на боках, заклёпки, косые опоры, полосы «опасно».


func _ready() -> void:
	_build()
	_build_board()
	snd = AudioStreamPlayer3D.new()
	snd.position = Vector3(0, 1.0, 0.3)
	snd.unit_size = 4.0
	add_child(snd)
	snd2 = AudioStreamPlayer3D.new()
	snd2.position = Vector3(0, 1.0, 0.3)
	snd2.unit_size = 4.0
	add_child(snd2)
	for i in REELS:
		stops[i] = randi() % STRIP.size()
		reels[i].rotation.x = _angle_for(stops[i])
	_snap_strips()


## Питание (world/intro.gd, промпт 16.11 03:42): в начале новой игры автомат выключен — экран, лампы
## и свет погашены, крутить нельзя; после убийства заблудшего монстрика включается со звуком.
var powered := true
var _glow_e := {}     # материал → яркость свечения до выключения


func _power_parts() -> Array:
	var mats: Array = []
	var lights: Array = []
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is Light3D:
			lights.append(n)
		elif n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var list: Array = [mi.material_override]
			if mi.mesh:
				for i in mi.mesh.get_surface_count():
					list.append(mi.get_surface_override_material(i))
					list.append(mi.mesh.surface_get_material(i))
			for m in list:
				if m is StandardMaterial3D and (m as StandardMaterial3D).emission_enabled and not m in mats:
					mats.append(m)
	return [mats, lights]


func set_powered(on: bool, fx := false) -> void:
	if on == powered and not fx:
		return
	var parts := _power_parts()
	if not on:
		powered = false
		for m in parts[0]:
			if not _glow_e.has(m):
				_glow_e[m] = (m as StandardMaterial3D).emission_energy_multiplier
			(m as StandardMaterial3D).emission_energy_multiplier = 0.0
		for l in parts[1]:
			(l as Light3D).visible = false
		screen.visible = false
		return
	if not fx:
		_power_apply(parts, true)
		return
	# включение: щелчок, гудение, свет и экран дважды мигают и загораются
	if game:
		game.play_at("clunk", global_position + Vector3(0, 1.0, 0.4), -13.0, 0.8)   # включение тише (промпты 04:06, 04:28, 04:32)
		game.play_at("buzz", global_position + Vector3(0, 1.2, 0.4), -18.0, 0.9)
	var tw := create_tween()
	for k in [true, false, true, false]:
		tw.tween_callback(_power_apply.bind(parts, k))
		tw.tween_interval(0.07 if k else 0.12)
	tw.tween_callback(_power_apply.bind(parts, true))
	tw.tween_callback(_power_jingle)


## Первые купленные крутки (3 или 6) прокручены — включается Trinkets Market (промпт 16.11 04:30).
func _first_spins_check() -> void:
	if game == null or credits > 0 or bool(game.get("shop_on")):
		return
	game.shop_on = true
	game.call_deferred("save_now")
	get_tree().create_timer(1.6, false).timeout.connect(func():
		if game and game.shop and is_instance_valid(game.shop):
			game.shop.set_powered(true, true))


func _power_jingle() -> void:
	if game:
		game.play_at("jingle", global_position + Vector3(0, 1.2, 0.4), -17.0)


func _power_apply(parts: Array, on: bool) -> void:
	powered = on
	for m in parts[0]:
		(m as StandardMaterial3D).emission_energy_multiplier = float(_glow_e.get(m, 1.0)) if on else 0.0
	for l in parts[1]:
		(l as Light3D).visible = on
	screen.visible = on


func get_prompt(_game) -> String:
	if not powered:
		return ""
	if busy:
		return ""
	return "[E] Крутить KILLBOX (осталось %d)" % credits if credits > 0 else "[E] KILLBOX — купить крутки"


func interact(g) -> void:
	game = g
	if busy or not powered:
		return
	if credits <= 0:
		_open_packs()
		return
	credits -= 1
	# гарантированный символ тратится с каждой круткой
	for k in luck.keys():
		luck[k]["left"] = int(luck[k]["left"]) - 1
	for k in boost.keys():
		boost[k] = int(boost[k]) - 1
	busy = true
	screen.text = "КРУТИТСЯ..."
	if g.has_method("save_now"):
		g.save_now()      # крутка уже списана — перезагрузка не вернёт её
	_roll_stops()
	for k in luck.keys():
		if int(luck[k]["left"]) <= 0:
			luck.erase(k)
	for k in boost.keys():
		if int(boost[k]) <= 0:
			boost.erase(k)
	hl_lines = []
	hl_t = 0.0
	for row in hl_cells:
		for c in row:
			c.visible = false
	SlotSounds.play3d(self, SlotSounds.lever(), lever.global_position, -7.0, randf_range(0.96, 1.04))   # промпт 16.11 04:18
	var tw := create_tween()
	tw.tween_property(lever, "rotation:x", 1.1, 0.18).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(lever, "rotation:x", 0.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for i in REELS:
		# закрытые столбцы стоят на месте: ни вращения, ни тиков, ни «clunk» (промпт 14.11 17:51)
		if not col_open(level, i):
			spinning[i] = false
			continue
		spinning[i] = true
		var cur := reels[i].rotation.x
		var target := _angle_for(stops[i])
		# барабан крутится вниз (угол растёт): минимум 3 оборота + по обороту на каждый следующий
		var turns := 3.0 + i
		target += TAU * ceil((cur - target) / TAU + turns)
		var rt := create_tween()
		rt.tween_interval(0.12 + i * 0.04)   # крутка ×0.8 (промпт 16.11 04:18)
		rt.tween_property(reels[i], "rotation:x", target, 1.04 + i * 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		rt.tween_callback(_reel_stopped.bind(i))


## Розыгрыш окна (roll_window) с гарантированными символами; потом в ленту каждого барабана
## вокруг новой остановки «впечатываем» выпавшие 3 символа (остальная лента — по весам).
## Ленты перерисовываются, когда барабаны уже разогнались.
func _roll_stops() -> void:
	var guar := {}
	for k in luck:
		guar[k] = int(luck[k]["k"])
	var g := roll_window(level, guar, boost.keys(), sevens_hit)
	var n := STRIP.size()
	for i in REELS:
		if not col_open(level, i):
			continue   # закрытый барабан не крутится — его лента не меняется
		stops[i] = randi() % n
		var strip := _random_strip(level)
		for r in ROWS:
			strip[(stops[i] + r - 1 + n) % n] = g[r][i]
		strips[i] = strip
	get_tree().create_timer(0.24).timeout.connect(_redraw_strips)


## Видимое окно: 3 ряда по 5 символов (сверху вниз), включая закрытые клетки.
func grid() -> Array:
	var n := STRIP.size()
	var rows: Array = []
	for r in 3:
		var row: Array = []
		for i in REELS:
			row.append(strips[i][(stops[i] + r - 1 + n) % n])
		rows.append(row)
	return rows


func _reel_stopped(i: int) -> void:
	spinning[i] = false
	if game:
		game.play_at("clunk", reels[i].global_position, -10.5)   # −25% (промпт 16.11 03:21)
	if not spinning.has(true):
		_payout()


func _process(delta: float) -> void:
	if not powered:
		return
	t += delta
	# лампочки: бегущий огонёк, при выигрыше — быстро мигают все
	party = maxf(party - delta, 0.0)
	_update_highlight(delta)
	for k in bulbs.size():
		var on: bool
		if party > 0.0:
			on = int(t * 10.0) % 2 == k % 2
		else:
			on = int(t * 3.0) % 3 != k % 3
		bulbs[k].emission_energy_multiplier = 1.6 if on else 0.15
	# цветные огни: волна снизу вверх, при выигрыше — вспышки
	for i in leds.size():
		@warning_ignore("integer_division")
		var w := sin(t * 5.0 - float(i / 2) * 0.6)
		if party > 0.0:
			leds[i].emission_energy_multiplier = 2.2 if (int(t * 12.0) + i) % 3 == 0 else 0.3
		else:
			leds[i].emission_energy_multiplier = 0.4 + 1.4 * maxf(w, 0.0)
	_animate_style(delta)
	_cutscene(delta)
	# серия живёт, пока крутишь: ушёл от автомата или долго не крутил — сброс
	if streak > 0 and not busy and game and game.get("player"):
		var far: bool = game.player.global_position.distance_to(global_position) > CHAIN_DIST
		if far or t - last_spin_t > CHAIN_IDLE:
			streak = 0
			screen.text = "СЕРИЯ СГОРЕЛА"
			_update_screen_hint()
	# свечение мерцает и переливается от янтарного к красному
	var flick := 0.04 * sin(t * 2.3)   # без резких скачков — барабаны не мерцают
	light.light_energy = 0.8 + flick + (0.35 * sin(t * 30.0) if party > 0.0 else 0.0)
	light.light_color = Color.from_hsv(0.045 + 0.03 * sin(t * 0.6), 0.75, 1.0)
	# тики при прохождении символов
	if busy and game:
		tick_t -= delta
		for i in REELS:
			if not spinning[i]:
				continue
			var cell := int(floor(reels[i].rotation.x * STRIP.size() / TAU))
			if cell != last_cell[i]:
				last_cell[i] = cell
				if tick_t <= 0.0:
					tick_t = 0.04
					snd.stream = game.snd["tick"][0]
					snd.volume_db = -14.5   # +25% (промпт 16.11 03:21)
					snd.pitch_scale = randf_range(0.9, 1.1)
					snd.play()


func _payout() -> void:
	busy = false
	_first_spins_check()
	var g := grid()
	var res := evaluate(g, level, lines_for(level))
	if res["six"] and shield > 0:
		# яблоко спасло: монеты не трогаем, защита сгорает
		shield -= 1
		_update_apples()
		screen.text = "666 — ЯБЛОКО СПАСЛО"
		game.hud.toast("Три шестёрки! Гнилое яблоко спасло твою экипировку", Color(0.7, 1.0, 0.5))
		game.play_at("buzz", global_position, -10.0, 0.9)
		game.call_deferred("save_now")
		streak = 0
		_update_screen_hint()
		return
	if res["six"]:
		var took := _take_bought()
		if took != "":
			var nm: String = preload("res://scripts/items.gd").item_name(took)
			screen.text = "666 — KILLBOX ЗАБРАЛ: %s" % nm.to_upper()
			game.hud.toast("Три шестёрки! Автомат забрал: %s" % nm, Color(1.0, 0.35, 0.25))
		else:
			screen.text = "666 — НЕЧЕГО ЗАБРАТЬ"
			game.hud.toast("Три шестёрки! Но купленной экипировки у тебя нет", Color(1.0, 0.6, 0.35))
		game.play_at("buzz", global_position, -6.0, 0.7)
		game.hud.hurt_flash(0.5)
		game.call_deferred("save_now")
		streak = 0
		return
	var win: int = res["win"]
	var sevens: bool = res["sevens"]
	var won_lines: PackedStringArray = res["ids"]
	hl_lines = res["lines"]
	var msg := ""
	if sevens:
		sevens_hit = true
		if game.open_safe():
			msg = "СЕЙФ ОТКРЫТ"
			game.hud.toast("777 — сейф открыт", Color(1.0, 0.85, 0.4))
		else:
			win += int(PAY["seven"][3])
	# множитель серии: применяется к выигрышу этой крутки; выигрыш продлевает серию, проигрыш — сброс
	var mult := chain_mult(streak)
	win = roundi(win * mult)
	# серию продлевают только настоящие комбинации (3+ или 777); пара — мелочь, серия сгорает
	streak = streak + 1 if res["big"] else 0
	last_spin_t = t
	if win > 0:
		msg = (msg + " · ") if msg != "" else ""
		msg += "+%d" % win
		if mult > 1.0:
			msg += " (СЕРИЯ ×%s)" % _mult_str(mult)
		# выигрыш со звоном высыпается в лоток-«пасть», забирать на E (промпт 14.11 17:53)
		_pour(win)
		game.hud.toast("KILLBOX: +%d — монеты в лотке" % win, Color(1.0, 0.8, 0.4))
	if sevens or win >= 30:
		party = 2.5
		snd2.stream = game.snd["jingle"][0]
		snd2.volume_db = -10.0
		snd2.play()
	# какие линии сыграли — видно по подсветке на барабанах
	if won_lines.size() > 1:
		msg = "КОМБО ×%d · " % won_lines.size() + msg
	if won_lines.size() > 0:
		hl_t = 6.0
	screen.text = msg if msg != "" else "ПУСТО"
	if game.has_method("save_now"):
		game.call_deferred("save_now")
	_update_screen_hint()


## Наказание 666: забрать одну случайную экипировку, купленную в Trinkets Market (game.shop_bought).
## Сначала ищем в сумке, потом — надетое (кроме рюкзака). Возвращает id или "".
func _take_bought() -> String:
	var Items := preload("res://scripts/items.gd")
	var bought: Array = game.get("shop_bought") if game.get("shop_bought") != null else []
	var cand: Array = []
	for id in bought:
		var d: Dictionary = Items.ITEMS.get(id, {})
		if (d.has("equip") or d.get("weapon", false)) and game.inv.count(id) > 0 and not cand.has(id):
			cand.append(id)
	if cand.is_empty():
		return ""
	var id: String = cand[randi() % cand.size()]
	bought.erase(id)
	if game.inv.remove(id, 1):
		return id
	for k in game.inv.equip:
		if game.inv.equip[k] == id and id != "backpack":
			game.inv.equip[k] = ""
			game.inv.equip_dur.erase(k)
			game.inv.notify()
			return id
	return ""


func _input(e: InputEvent) -> void:
	if pack_open and (e.is_action_pressed("ui_cancel") or e.is_action_pressed("interact") or e.is_action_pressed("inventory")):
		get_viewport().set_input_as_handled()
		if not e.is_echo():
			close_packs()


## Магазин: гарантированный символ ×k. Повторная покупка того же символа добавляет крутки,
## число штук за крутку — большее из старого и нового (не больше GUAR_MAX уровня).
func add_luck(sym: String, k := 1) -> void:
	if not LUCK.has(sym):
		return
	var cur: Dictionary = luck.get(sym, {"left": 0, "k": 1})
	luck[sym] = {"left": int(cur["left"]) + int(LUCK[sym][0]), "k": maxi(int(cur["k"]), k)}
	screen.text = ""
	_update_screen_hint()


## Магазин: шанс комбинации символа на BOOST[sym][0] круток.
func add_boost(sym: String) -> void:
	if not BOOST.has(sym):
		return
	boost[sym] = int(boost.get(sym, 0)) + int(BOOST[sym][0])
	screen.text = ""
	_update_screen_hint()


## Сейв: гаранты и шансы. Старые сейвы: гарант — число круток или [вес, круток].
func load_buffs(lk: Dictionary, bst: Dictionary) -> void:
	luck = {}
	for k in lk:
		if not LUCK.has(k):
			continue
		var v = lk[k]
		if v is Dictionary:
			luck[k] = {"left": int(v.get("left", 0)), "k": int(v.get("k", 1))}
		elif v is Array:
			luck[k] = {"left": int(v[1]), "k": 1}
		else:
			luck[k] = {"left": int(v), "k": 1}
	boost = {}
	for k in bst:
		if BOOST.has(k):
			boost[k] = int(bst[k])


func _tray_target_count(n: int) -> int:
	return clampi(n, 0, TRAY_MAX)


## Сразу показать горку под сумму (загрузка сейва).
func set_tray(n: int) -> void:
	_stop_pour()
	tray_coins = maxi(n, 0)
	tray_shown = _tray_target_count(tray_coins)
	for k in tray_meshes.size():
		tray_meshes[k].visible = k < tray_shown
		tray_meshes[k].position = tray_pos[k]


## Оборвать анимацию высыпания (сбор во время россыпи забирает всю сумму сразу — промпт 02:34).
func _stop_pour() -> void:
	for tw in pour_tweens:
		if tw and tw.is_valid():
			tw.kill()
	pour_tweens.clear()
	pour_gen += 1


## Высыпать win монет в лоток (промпт 14.11 19:18): монетки вылетают из пасти почти разом
## (разброс старта 0.02–0.05 с), каждая летит плавно ~0.6 с по мягкой дуге и чуть подпрыгивает на горке;
## звон — общая россыпь из нескольких наложенных «coin».
func _pour(win: int) -> void:
	tray_coins += win
	var want := _tray_target_count(tray_coins)
	var k0 := tray_shown
	tray_shown = want
	var delay := 0.0
	for k in range(k0, want):
		var c := tray_meshes[k]
		# каждая монета выбирает новое место по всему дну лотка (19:50)
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var end := _tray_spot(k, rng)
		tray_pos[k] = end
		var start := Vector3(randf_range(-0.12, 0.12), 0.465, 0.318)   # из глубины пасти, за верхними зубами
		# лежит плашмя под своим углом; в полёте сильно кувыркается по трём осям и «докручивается» до него
		var rest := Vector3(randf_range(-0.22, 0.22), randf() * TAU, randf_range(-0.22, 0.22))
		var spin := Vector3(randf_range(2.5, 4.0) * TAU * (1 if randf() < 0.5 else -1), randf_range(-1.5, 1.5) * TAU,
			randf_range(1.0, 2.5) * TAU * (1 if randf() < 0.5 else -1))
		var roll := Vector3(randf_range(-0.012, 0.012), 0, randf_range(-0.01, 0.01))   # прокатится после удара
		var tw := create_tween()
		pour_tweens.append(tw)
		tw.tween_interval(delay)
		tw.tween_callback(func():
			c.position = start
			c.rotation = rest + spin
			c.visible = true)
		tw.tween_method(func(ts: float):
			var e := ts * ts * (3.0 - 2.0 * ts)   # плавный разгон и торможение
			c.position = start.lerp(end - roll, e) + Vector3(0, sin(PI * ts) * 0.03, 0)
			var sp := 1.0 - ts
			c.rotation = rest + spin * sp * sp, 0.0, 1.0, randf_range(0.55, 0.68))
		# удар о дно: подскок с кувырком, прокатывание и укладка плашмя
		var wob := Vector3(randf_range(-0.9, 0.9), randf_range(-0.6, 0.6), randf_range(-0.9, 0.9))
		tw.tween_method(func(ts: float):
			c.position = (end - roll).lerp(end, ts) + Vector3(0, sin(PI * ts) * 0.012, 0)
			c.rotation = rest + wob * (1.0 - ts) * cos(ts * 9.0), 0.0, 1.0, 0.26)
		delay += randf_range(0.02, 0.05)
	# звон россыпью: несколько наложенных «coin» к моменту приземления
	pour_tweens = pour_tweens.filter(func(x): return x and x.is_valid())
	var gen := pour_gen
	if game:
		# пачка звяков о металлический лоток (промпт 16.11 04:18); на крупный выигрыш — 2–3 пачки внахлёст
		var packs := clampi(ceili((want - k0) / 4.0), 1, 3)
		for r in packs:
			var at := 0.5 + r * randf_range(0.12, 0.22)
			get_tree().create_timer(at).timeout.connect(func():
				if game and gen == pour_gen:
					SlotSounds.play3d(self, SlotSounds.tray(), tray_target.global_position, -9.0 - r * 2.0, randf_range(0.93, 1.07)))


## Забрать всё из лотка в кошелёк.
func take_tray() -> void:
	if tray_coins <= 0 or game == null:
		return
	var n := tray_coins
	var left: int = game.inv.add("coin", n)
	set_tray(left)
	game.play_ui("coin", -8.0, 1.05)
	game.hud.toast("+%d монет" % (n - left), Color(1.0, 0.8, 0.4))
	if game.has_method("save_now"):
		game.save_now()


func eat_tray() -> void:
	if tray_coins <= 0:
		return
	_stop_pour()
	var n := tray_coins
	tray_coins = 0
	eating = true
	var tw := create_tween().set_parallel(true)
	for k in tray_shown:
		var c := tray_meshes[k]
		var d := randf_range(0.0, 0.35)
		tw.tween_property(c, "position", Vector3(c.position.x * 0.3, 0.41, 0.31), 0.45).set_delay(d) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func():
		eating = false
		set_tray(0))
	party = 0.0
	if maw_mat:
		var mt := create_tween()
		mt.tween_property(maw_mat, "emission_energy_multiplier", 4.0, 0.15)
		mt.tween_property(maw_mat, "emission_energy_multiplier", 0.6, 0.8)
	snd2.stream = _crunch()
	snd2.volume_db = -4.0
	snd2.play()
	if game:
		game.hud.toast("KILLBOX сожрал монеты из лотка: −%d" % n, Color(1.0, 0.35, 0.25))


# ---------- гнилое яблоко: защита от 666 ----------

## Можно ли сейчас скормить яблоко: оно есть в сумке и защит меньше SHIELD_MAX.
func can_feed(g) -> bool:
	return g != null and not busy and not eating and shield < SHIELD_MAX and g.inv.count("rot_apple") > 0


## Скормить яблоко: оно летит из руки в пасть и пропадает, жар вспыхивает, чавканье; +1 защита.
func feed_apple() -> void:
	if not can_feed(game) or not game.inv.remove("rot_apple", 1):
		return
	shield += 1
	var a := _apple_mesh()
	a.scale = Vector3.ONE * 1.6
	rig.add_child(a)
	var from := Vector3(0, 0.75, 0.9)
	var to := Vector3(0, 0.45, 0.31)
	a.position = from
	var tw := create_tween()
	tw.tween_method(func(ts: float):
		a.position = from.lerp(to, ts) + Vector3(0, sin(PI * ts) * 0.12, 0)
		a.rotation = Vector3(ts * 6.0, ts * 3.0, 0), 0.0, 1.0, 0.45).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(a, "scale", Vector3.ONE * 0.2, 0.15)
	tw.tween_callback(func():
		a.queue_free()
		snd2.stream = _crunch()
		snd2.volume_db = -8.0
		snd2.pitch_scale = 1.15
		snd2.play()
		if maw_mat:
			var mt := create_tween()
			mt.tween_property(maw_mat, "emission_energy_multiplier", 3.0, 0.12)
			mt.tween_property(maw_mat, "emission_energy_multiplier", 0.6, 0.6)
		_update_apples()
		screen.text = "НЯМ. ЗАЩИТА ОТ 666 ×%d" % shield
		_update_screen_hint())
	if game:
		game.hud.toast("KILLBOX съел гнилое яблоко: при следующих «666» вещи останутся (%d/%d)" % [shield, SHIELD_MAX], Color(0.7, 1.0, 0.5))
		if game.has_method("save_now"):
			game.call_deferred("save_now")


func _update_apples() -> void:
	for k in apple_props.size():
		apple_props[k].visible = k < shield


func set_shield(n: int) -> void:
	shield = clampi(n, 0, SHIELD_MAX)
	_update_apples()


func set_reveal_pending(v: bool) -> void:
	reveal_pending = v and level >= MAX_LEVEL
	_redraw_board()


func _cutscene(delta: float) -> void:
	if not cut_active:
		if reveal_pending and game and game.get("player") and not busy and not game.window_open():
			_start_cut()
		return
	cut_t += delta
	var ct := cut_t
	# камера: к доске 0–0.9 с, обратно 3.4–4.3 с (плавно)
	var a := 0.0
	if ct < 0.9:
		a = _smooth(ct / 0.9)
	elif ct < 3.4:
		a = 1.0
	else:
		a = 1.0 - _smooth((ct - 3.4) / 0.9)
	cut_cam.global_transform = cut_from.interpolate_with(cut_to, a)
	rev7 = clampf((ct - 0.95) / 0.9, 0.0, 1.0)
	dark6 = clampf(1.0 - absf(ct - 2.05) / 0.25, 0.0, 1.0) * 0.6
	rev6 = clampf((ct - 2.1) / 1.0, 0.0, 1.0)
	if ct >= 0.9 and ct - delta < 0.9:
		_play_cut(_chime())
	if ct >= 2.0 and ct - delta < 2.0:
		_play_cut(_dread())
	board_art.queue_redraw()
	if ct >= CUT_LEN:
		_end_cut()


func _start_cut() -> void:
	var pcam: Camera3D = game.player.cam
	cut_active = true
	cut_t = 0.0
	rev7 = 0.0
	rev6 = 0.0
	game.player.active = false
	cut_from = pcam.global_transform
	var bt := board_node.global_transform
	var eye := bt.origin + bt.basis.z.normalized() * 1.75
	cut_to = Transform3D(Basis.IDENTITY, eye).looking_at(bt.origin, Vector3.UP)
	cut_cam = Camera3D.new()
	cut_cam.fov = pcam.fov
	get_tree().current_scene.add_child(cut_cam)
	cut_cam.global_transform = cut_from
	cut_cam.make_current()
	board_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_redraw_board()
	board_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func _end_cut() -> void:
	cut_active = false
	reveal_pending = false
	rev7 = 1.0
	rev6 = 1.0
	dark6 = 0.0
	if game and game.player:
		game.player.cam.make_current()
		game.player.active = true
	if cut_cam:
		cut_cam.queue_free()
		cut_cam = null
	_redraw_board()
	if game and game.has_method("save_now"):
		game.save_now()


func _play_cut(st: AudioStream) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = st
	p.volume_db = -6.0
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
