extends "res://scripts/player/player_anim.gd"
# Часть player.gd: бой — стойка, удары, заряд, взмахи оружием, попадания.


func toggle_fists() -> void:
	if punching:
		return
	fists = not fists
	var tw := create_tween().set_parallel()
	tw.tween_property(self, "fist_blend", 1.0 if fists else 0.0, 0.3).set_trans(Tween.TRANS_SINE)
	for i in 2:
		tw.tween_method(_pose_setter(i), arm_pose[i], GUARDS[i] if fists else REST, 0.3).set_trans(Tween.TRANS_SINE)
	voice_player.stream = inhale_snd if fists else exhale_out_snd
	voice_player.volume_db = -25.0
	voice_player.pitch_scale = randf_range(0.95, 1.05)
	if not puppet:
		voice_player.play()


## Кат-сцена (промпт 16.11 04:28): стойка опускается без звука, после — поднимается обратно, если была.
func cinematic_stance(on: bool) -> void:
	var want := false
	if on:
		if not fists:
			return
		stance_saved = true
	else:
		if not stance_saved or fists:
			stance_saved = false
			return
		stance_saved = false
		want = true
	fists = want
	var tw := create_tween().set_parallel()
	tw.tween_property(self, "fist_blend", 1.0 if fists else 0.0, 0.3).set_trans(Tween.TRANS_SINE)
	for i in 2:
		tw.tween_method(_pose_setter(i), arm_pose[i], GUARDS[i] if fists else REST, 0.3).set_trans(Tween.TRANS_SINE)


## Удар рукой arm (0 — левая, ЛКМ; 1 — правая, ПКМ) без заряда. Кулаки опущены — только поднимает их.
## В руке оружие (или щит) — бьёт им.
func attack(arm: int) -> void:
	if punching:
		return
	if not fists:
		toggle_fists()
		return
	punch(arm)


## Цель удара получает урон или ломается: враги, манекен, целый кувшин, ящик. Автомат, сейф, сундук и т.п. — нет.
func _breakable(c: Object) -> bool:
	var sc: Script = c.get_script()
	match sc.resource_path.get_file() if sc else "":
		"enemy.gd":
			return c.get("state") != "dead"
		"dummy.gd":
			return true
		"jar.gd":
			return not bool(c.get("broken"))
		"chest.gd":
			return str(c.get("kind")) == "crate" and not bool(c.get("broken"))
	return false


## Множитель урона от заряда: 0 → 0.6, 0.5 → 1.0 (прежний урон), 1 → 1.6.
static func charge_mult(c: float) -> float:
	return 0.6 + 0.6 * c + 0.4 * c * c


func charge_frac() -> float:
	return clampf((charge_t - TAP_T) / (CHARGE_MAX - TAP_T), 0.0, 1.0)


## Нажал кнопку удара. Кулаки опущены — только поднимаем их, без удара и заряда (промпт 19:08);
## следующее нажатие, уже в стойке, копит заряд.
func charge_begin(arm: int) -> void:
	# предмет в руке (промпт 18.11 02:27): кнопка этой руки применяет его (полоска), а не бьёт
	if game and game.hb_press(arm):
		return
	var whip := false
	# в боевой стойке (промпт 05:34): кнопка руки с пистолетом — выстрел в центр (ЛКМ — левый, ПКМ — правый,
	# независимо); патронов нет — дальше обычный удар этой рукой с зарядом (рукоятью)
	if gun and fists and active and weapon_ids[arm] == "pistol" and fist_blend >= 0.9:
		if gun.stance_fire(arm):
			return
	if gun and _has_pistol() and active and not fists:
		if arm == 1:
			gun.rmb_input(true)   # ПКМ: держать — от бедра, клик — прицел (gun.gd)
			return
		if gun.ready_to_fire():
			gun.fire()   # ЛКМ с ПКМ — выстрел
			return
		# ЛКМ без ПКМ — удар рукоятью рукой с пистолетом (с двумя — по очереди)
		arm = 1 if weapon_ids[1] == "pistol" else 0
		if weapon_ids[0] == "pistol" and weapon_ids[1] == "pistol" and last_arm == 1:
			arm = 0
		whip = true
	elif stone_throw and _has_stone() and active:
		# камень в руке (промпт 16.11 02:13): ПКМ держать — замах с траекторией, ЛКМ при этом — бросок, без ПКМ — удар камнем
		if arm == 1:
			stone_throw.rmb_input(true)
			return
		if stone_throw.aiming:
			stone_throw.throw()
			return
		arm = 1 if weapon_ids[1] == "stone" else 0
		whip = true
	if charging >= 0 or not active:
		return
	if not fists:
		toggle_fists()
		return
	charging = arm
	charge_t = 0.0
	_whip_lmb = whip


func _has_pistol() -> bool:
	return weapon_ids[0] == "pistol" or weapon_ids[1] == "pistol"


func _has_stone() -> bool:
	return weapon_ids[0] == "stone" or weapon_ids[1] == "stone"


## Отпустил: удар этой рукой с накопленным зарядом (кулаки ещё поднимаются — ударит, как поднимутся).
func charge_release(arm: int) -> void:
	if game and game.hb_release(arm):
		return
	if arm == 1 and gun:
		gun.rmb_input(false)
	if arm == 1 and stone_throw:
		stone_throw.rmb_input(false)
	if (_has_pistol() and not fists) or _has_stone() or _whip_lmb:
		if arm == 1 or not _whip_lmb:
			return
		_whip_lmb = false
		arm = charging   # ЛКМ отпустили — бьёт рука с пистолетом
	if charging != arm:
		return
	charging = -1
	var c := charge_frac()
	# выпад плеча удара начнётся с оттянутого положения (так удар хлёстче); вторая рука плавно возвращается
	create_tween().tween_method(_reach_setter(1 - arm), reach[1 - arm], 0.0, 0.2).set_trans(Tween.TRANS_SINE)
	if fists and fist_blend >= 0.9:
		punch(arm, c)
	else:
		_queued_arm = arm
		get_tree().create_timer(0.32).timeout.connect(func():
			if fists and _queued_arm == arm:
				_queued_arm = -1
				punch(arm, c))


func _charge_tick(delta: float) -> void:
	if charging >= 0:
		if punching or not fists:
			if not fists and fist_blend < 0.05 and not punching:
				charging = -1   # кулаки опустили (V) — заряд сброшен
		elif fist_blend >= 0.9:
			charge_t = minf(charge_t + delta, CHARGE_MAX)
			# замах тянется: плечо уходит назад (корпус поворачивается за счёт разницы выпадов плеч)
			var kk := smoothstep(0.0, 1.0, charge_frac())
			var heavy := 1.3 if weapon_ids[charging] != "" else 1.0
			reach[charging] = -0.05 * kk * heavy
			reach[1 - charging] = 0.02 * kk
		charge_ui_k = charge_frac()
	# поза рук догоняет заряд; после удара плавно возвращается
	if charging >= 0:
		charge_arm = charging
		charge_vis = lerpf(charge_vis, charge_frac(), 1.0 - exp(-10.0 * delta))
	else:
		charge_vis = move_toward(charge_vis, 0.0, delta * 5.0)
		if charge_vis <= 0.0:
			charge_arm = -1
		if not punching:
			for i in 2:   # заряд отменён без удара — плечи плавно на место
				reach[i] = move_toward(reach[i], 0.0, delta * 0.8)
	var want := 1.0 if charging >= 0 and charge_t > TAP_T else 0.0
	charge_ui_a = move_toward(charge_ui_a, want, delta * (6.0 if want > 0.0 else 3.0))
	if charge_ui:
		charge_ui.visible = charge_ui_a > 0.01
		if charge_ui.visible:
			charge_ui.queue_redraw()


func _make_charge_ui() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 1
	add_child(cl)
	charge_ui = Control.new()
	charge_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	charge_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	charge_ui.visible = false
	charge_ui.draw.connect(_charge_draw)
	cl.add_child(charge_ui)


## Тонкая полупрозрачная красноватая полоска заряда — под прицелом, выше хотбара (промпт 04:13).
func _charge_draw() -> void:
	var sz := charge_ui.size
	var w := 240.0
	var h := 5.0
	var x0 := sz.x / 2.0 - w / 2.0
	var y0 := sz.y * 0.928 - 78.4   # 04:25: опущена на 80% от подъёма 04:13 (был sz.y−98, стал 0.64·sz.y)
	var a := charge_ui_a * 0.6
	var full := charge_ui_k >= 0.999
	charge_ui.draw_rect(Rect2(x0 - 2, y0 - 2, w + 4, h + 4), Color(0, 0, 0, 0.45 * a))
	charge_ui.draw_rect(Rect2(x0, y0, w, h), Color(1, 0.5, 0.45, 0.12 * a))
	charge_ui.draw_rect(Rect2(x0, y0, w * charge_ui_k, h), Color(0.95, 0.38, 0.32, 0.9 * a))
	if full:
		# максимум: пульсирующее свечение вокруг
		var p := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU * 3.0)
		charge_ui.draw_rect(Rect2(x0 - 4, y0 - 4, w + 8, h + 8), Color(1, 0.45, 0.4, (0.25 + 0.45 * p) * a), false, 2.0)


## arm = -1 — рука выбирается сама (чередование; старый код). charge — заряд удара 0..1.
func punch(arm := -1, charge := 0.0) -> void:
	if punching or fist_blend < 0.9:
		return
	punching = true
	strike_charge = charge
	make_noise(NOISE_PUNCH)
	var i := arm
	if i < 0:
		# рука: с шансом 75% другая, чем в прошлый раз
		i = randi() % 2
		if last_arm != -1:
			i = (1 - last_arm) if randf() < 0.75 else last_arm
		# оружие только в одной руке — чаще бьём им
		var armed0 := weapon_ids[0] != ""
		if armed0 != (weapon_ids[1] != "") and randf() < 0.75:
			i = 0 if armed0 else 1
	last_arm = i
	if weapon_ids[i] != "":
		_weapon_swing(i, weapon_ids[i])
		return
	# вид удара: базовые шансы, но прошлый вид выпадает реже (вес ×0.35)
	var weights := {"straight": 0.45, "hook": 0.3, "upper": 0.25}
	if last_kind != "":
		weights[last_kind] *= 0.35
	var total := 0.0
	for k in weights:
		total += weights[k]
	var r := randf() * total
	var kind := "straight"
	for k in weights:
		r -= weights[k]
		if r <= 0.0:
			kind = k
			break
	last_kind = kind
	var keys: Array = PUNCHES[kind]
	var rs := _reach_setter(i)
	# хлёстко: короткий замах (плечо чуть назад) -> очень быстрый выброс с перелётом ->
	# короткая фиксация -> мягкий возврат
	var tw := create_tween()
	tw.tween_method(_pose_setter(i), arm_pose[i], keys[0], 0.06).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_method(rs, reach[i], -0.035, 0.06).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(_punch_sound)
	tw.tween_callback(_punch_fx.bind(i, kind, true))
	tw.tween_method(_pose_setter(i), keys[0], keys[1], 0.07).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(rs, -0.035, 0.15, 0.07).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_check_hit.bind(i, kind))
	tw.tween_interval(0.05)
	tw.tween_callback(_punch_fx.bind(i, kind, false))
	tw.tween_method(_pose_setter(i), keys[1], GUARDS[i], 0.24).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_method(rs, 0.15, 0.0, 0.24).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func(): punching = false)


func _reach_setter(i: int) -> Callable:
	return func(v: float) -> void: reach[i] = v


func _twist_setter(v: float) -> void:
	swing_twist = v


## Мах оружием: свой набор траекторий и таймингов для каждого типа, вариация случайная
## (прошлая повторяется реже).
func _weapon_swing(i: int, wid: String) -> void:
	var group := "heavy"
	if wid in ["machete", "knife", "shield"]:
		group = wid
		if wid in ["knife", "shiv"] and i == 0:
			group = "knife_rev"   # левая — обратный хват, свой мах
	elif wid == "shiv":
		group = "knife_rev" if i == 0 else "knife"   # заточка — как нож (промпт 04:49), в левой — обратный хват
	elif wid == "pistol":
		group = "pistol"
	elif wid == "stone":
		group = "knife"   # камнем — короткий тычок
	var set_: Array = SWINGS[group]
	var v := randi() % set_.size()
	if v == last_swing[i] and randf() < 0.65:
		v = (v + 1 + randi() % maxi(set_.size() - 1, 1)) % set_.size()
	last_swing[i] = v
	var sw: Dictionary = set_[v]
	var side := -1.0 if i == 0 else 1.0
	var t: Array = sw["t"]
	var tws: Array = sw["tw"]
	var rc: Array = sw["rc"]
	var heavy := group == "heavy" or group == "shield"
	var ps := _pose_setter(i)
	var rs := _reach_setter(i)
	# хлёст кистью: в замахе оружие взведено вверх, к удару кисть «выстреливает» и оружие продолжает руку
	var fl: Array = sw.get("wf", [-0.25, WRIST_HIT, WRIST_HIT * 1.1] if group != "shield" else [0.0, 0.0, 0.0])
	var fs := func(fv: float) -> void: wrist_flex[i] = fv
	var tw := create_tween()
	# замах — с разгоном и торможением в верхней точке
	tw.tween_method(ps, arm_pose[i], sw["wind"], t[0]).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_method(_twist_setter, swing_twist, tws[0] * side, t[0]).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_method(rs, reach[i], rc[0], t[0]).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_method(fs, wrist_flex[i], fl[0], t[0]).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(_swing_sound.bind(heavy))
	tw.tween_callback(_punch_fx.bind(i, sw["blur"], true))
	# удар: тяжёлое разгоняется (ease-in), лезвие срывается сразу (ease-out)
	var ez := Tween.EASE_IN if group == "heavy" else Tween.EASE_OUT
	var trans := Tween.TRANS_QUAD if group == "heavy" else Tween.TRANS_CUBIC
	tw.tween_method(ps, sw["wind"], sw["hit"], t[1]).set_trans(trans).set_ease(ez)
	tw.parallel().tween_method(_twist_setter, tws[0] * side, tws[1] * side, t[1]).set_trans(trans).set_ease(ez)
	tw.parallel().tween_method(rs, rc[0], rc[1], t[1]).set_trans(trans).set_ease(ez)
	tw.parallel().tween_method(fs, fl[0], fl[1], t[1]).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(_check_hit.bind(i, "hook"))
	# проводка по инерции и плавное торможение
	tw.tween_method(ps, sw["hit"], sw["thru"], t[2]).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(_twist_setter, tws[1] * side, tws[2] * side, t[2]).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(fs, fl[1], fl[2], t[2]).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_punch_fx.bind(i, sw["blur"], false))
	# возврат в стойку
	tw.tween_method(ps, sw["thru"], GUARDS[i], t[3]).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_method(_twist_setter, tws[2] * side, 0.0, t[3]).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_method(rs, rc[1], 0.0, t[3]).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_method(fs, fl[2], 0.0, t[3]).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func(): punching = false)


func _swing_sound(heavy: bool) -> void:
	_play(hit_player, heavy_whooshes if heavy else whooshes, -14.0 if heavy else -16.0)
	if not heavy:
		hit_player.pitch_scale = randf_range(1.1, 1.25)   # лезвие свистит выше
	_play(voice_player, exhales, -13.0 if heavy else -15.0)
	if heavy:
		voice_player.pitch_scale = randf_range(0.85, 0.95)


## Эффекты удара: размытие в движении (прямой — «зум», хук — по горизонтали, апперкот — по вертикали)
## и потоки воздуха за кулаком.
func _punch_fx(i: int, kind: String, on: bool) -> void:
	trail_on[i] = on
	if on:
		trail_pts[i].clear()
		trail_alpha[i] = 1.0
	if not on or post_mat == null:
		return
	# размытие только вокруг кулака и слабее
	var fp := _trail_point(i)
	if not cam.is_position_behind(fp):
		post_mat.set_shader_parameter("blur_center", cam.unproject_position(fp) / get_viewport().get_visible_rect().size)
	var side := -1.0 if i == 0 else 1.0
	var param := "blur_amt"
	var peak := 0.008
	if kind == "straight":
		param = "zoom_amt"
		peak = 0.018
	elif kind == "hook":
		post_mat.set_shader_parameter("blur_dir", Vector2(-side, 0.0))
	else:
		post_mat.set_shader_parameter("blur_dir", Vector2(0.0, 1.0))
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: post_mat.set_shader_parameter(param, v), 0.0, peak, 0.05)
	tw.tween_method(func(v: float) -> void: post_mat.set_shader_parameter(param, v), peak, 0.0, 0.14)


func _pose_setter(i: int) -> Callable:
	return func(p: Vector4) -> void: arm_pose[i] = p


func _punch_sound() -> void:
	_play(hit_player, whooshes, -17.0)
	_play(voice_player, exhales, -14.0)


## Сеть: по модели другого игрока попали (удар или пуля) — урон уходит ему через хоста.
func take_hit(dmg: float, dir: Vector3) -> void:
	if puppet and visible and net_hit.is_valid():
		net_hit.call(self, dmg, dir)


func _check_hit(arm: int, _kind := "straight") -> void:
	if puppet:
		return   # чужой игрок бьёт у себя; урон приходит по сети
	var from := cam.global_position
	var wid: String = weapon_ids[arm]
	var armed := wid != ""
	var reach_len: float = Weapons.stats(wid)["reach"] if armed else 1.0
	# взгляд вниз: удар идёт ниже и тело наклоняется — достаём до низких целей (ящики) и стоя
	reach_len *= 1.0 + 0.75 * clampf(-head.rotation.x, 0.0, 1.0)
	var hit := _hit_scan(from, reach_len)
	if hit:
		_play(hit_player, impacts, -11.0)
		# урон врагам/манекену (тестовые механики, см. game.gd): у цели должен быть take_hit(урон, направление)
		if hit.collider.has_method("take_hit"):
			var mult: float = Weapons.stats(wid)["mult"] if armed else dmg_mult
			# без случайности (промпт 19:06): вид удара и криты на урон не влияют, растёт только от заряда
			var dmg: float = PUNCH_BASE * mult * HAND_DMG[arm] * charge_mult(strike_charge)
			# ящик кулаками ломается медленно (~10 ударов)
			if not armed and hit.collider is StaticBody3D and str(hit.collider.get("kind")) == "crate":
				dmg *= 0.45
			# нож в левой (обратный хват, промпт 04:40): 25% — крит ×1.5, плашка «КРИТ» рядом с цифрой урона
			if wid in ["knife", "shiv"] and arm == 0 and randf() < 0.25 and _breakable(hit.collider):
				dmg *= 1.5
				Fx.popup_text(get_parent(), hit.position + Vector3(0, 0.35, 0) + cam.global_transform.basis.x * 0.22,
						"КРИТ", Color(1.0, 0.3, 0.2), 0.7)
			# надпись полного заряда — вдвое мельче и только по тому, что получает урон / ломается (промпт 19:20)
			if strike_charge >= 0.999 and _breakable(hit.collider):
				Fx.popup_text(get_parent(), hit.position + Vector3(0, 0.25, 0), "МОЩНО!", Color(1.0, 0.9, 0.7), 0.5)
			hit.collider.take_hit(dmg, -cam.global_transform.basis.z)
		# лёгкая отдача в камеру
		# короткий «дёрг» камеры: крен в сторону руки и кивок, оружием — сильнее
		var k := 1.6 if armed else 1.0
		var side := -1.0 if arm == 0 else 1.0
		var tw := create_tween()
		tw.tween_property(cam, "rotation:z", 0.022 * side * k, 0.03).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(cam, "rotation:z", 0.0, 0.16).set_trans(Tween.TRANS_SINE)
		var tw2 := create_tween()
		tw2.tween_property(cam, "rotation:x", -0.014 * k, 0.03).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw2.tween_property(cam, "rotation:x", 0.0, 0.14).set_trans(Tween.TRANS_SINE)


## Надёжное попадание: лучи конусом по взгляду (центр, кольцо ~7° и ~15°, и пара ниже — для
## низких целей вроде ящиков). Цель с take_hit важнее стены; из целей — ближайшая к центру.
func _hit_scan(from: Vector3, reach_len: float) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var b := cam.global_transform.basis
	var dirs: Array[Vector3] = [-b.z]
	for ring in [[0.12, 8], [0.26, 8]]:
		for k in int(ring[1]):
			var a := TAU * float(k) / float(ring[1])
			dirs.append((-b.z + (b.x * cos(a) + b.y * sin(a)) * float(ring[0])).normalized())
	for dn in [0.45, 0.7]:
		dirs.append((-b.z - b.y * dn).normalized())
	var best := {}
	var best_score := INF
	var wall := {}
	for k in dirs.size():
		var q := PhysicsRayQueryParameters3D.create(from, from + dirs[k] * reach_len * (1.0 if k == 0 else 1.1))
		q.exclude = [get_rid()]
		q.collision_mask = 1 | 512   # 512 — модели других игроков в сети
		var h := space.intersect_ray(q)
		if h.is_empty():
			continue
		if h.collider.has_method("take_hit"):
			var score := float(k) * 0.05 + from.distance_to(h.position)
			if score < best_score:
				best_score = score
				best = h
		elif k == 0:
			wall = h   # стена/пол — только если прямо по центру
	return best if not best.is_empty() else wall


## Aim punch (промпт 04:26): получил удар — камера резко дёргается (питч вверх + случайный yaw/roll),
## сила от урона; толчок гаснет ~0.25 с, а небольшая часть остаётся в прицеле — он реально сбивается.
func aim_punch(dmg: float) -> void:
	var k := clampf(dmg / 25.0, 0.25, 1.4)
	aim_kick += Vector3(randf_range(0.06, 0.09) * k, randf_range(-0.05, 0.05) * k, randf_range(-0.07, 0.07) * k)
	# остаток: прицел смещается и не возвращается сам
	head.rotation.x = clampf(head.rotation.x + randf_range(0.012, 0.025) * k, -1.5, 1.4)
	rotate_y(randf_range(-0.015, 0.015) * k)


## Толчок прибавляется к повороту камеры приращением — не мешает кат-сценам, которые сами ставят cam.rotation.
func _aim_kick_tick(delta: float) -> void:
	if cam == null or (aim_kick == Vector3.ZERO and aim_kick_applied == Vector3.ZERO):
		return
	aim_kick *= exp(-delta * 16.0)
	if aim_kick.length() < 0.0005:
		aim_kick = Vector3.ZERO
	cam.rotation += aim_kick - aim_kick_applied
	aim_kick_applied = aim_kick
