extends "res://scripts/village/mutant_base.gd"
const StepUp := preload("res://scripts/core/step_up.gd")
## Мутанты деревни (промпт 15.11 23:10) — три вида, у каждого свой стиль боя:
##   «Плевун» (spitter) — держит дистанцию 6–10 м, ходит боком и плюётся кислотой по дуге (замах — зоб
##     раздувается и светится); подошёл вплотную — отпрыгивает и царапает.
##   «Таран» (charger) — огромный и медленный; издалека ревёт, роет землю (телеграф ~0.9 с) и бросается
##     по прямой: попал — сильный удар и отброс; промахнулся в стену — оглушён 2 с и получает двойной урон.
##     Вблизи — удар обеими руками сверху.
##   «Тень» (stalker) — почти невидимая, быстрая; обходит игрока со спины, бьёт серией из двух ударов
##     (на миг проявляется) и отбегает, снова растворяясь. Попал по ней — видна 2 с.
## В подвал не спускаются (там можно отсидеться). Умирая — монеты, иногда патроны, фильтр или бензин.
## Интерфейс урона: take_hit(урон, направление). В сети думают у хоста (village_net.gd).


func _ready() -> void:
	var k: Dictionary = KINDS[kind]
	max_hp = k["hp"]
	hp = max_hp
	speed = k["speed"]
	height = k["h"]
	tg = game
	add_to_group("mutants")
	floor_snap_length = 0.3
	collision_layer = 1
	collision_mask = 1
	_build()
	voice = AudioStreamPlayer3D.new()
	voice.unit_size = 2.5
	voice.max_distance = 24.0   # не слышно через всю деревню (промпт 17.11 02:50)
	voice.position.y = height * 0.8
	add_child(voice)
	strafe = -1.0 if randf() < 0.5 else 1.0
	cool = randf_range(1.0, 3.0)
	if kind == "stalker":
		_set_alpha(0.12)


func _physics_process(delta: float) -> void:
	if net_puppet:
		_puppet_tick(delta)
		return
	if state == "dead":
		return
	if game.net:
		tg = game.net.pick_target(self)
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	st += delta
	cool -= delta
	bar_t -= delta
	bar.visible = bar_t > 0.0
	knock = knock.lerp(Vector3.ZERO, 1.0 - exp(-6.0 * delta))
	var ppos: Vector3 = tg.player.global_position
	var to := ppos - global_position
	to.y = 0.0
	var d := to.length()
	var can: bool = tg.alive and ppos.y > G - 1.0 and ppos.distance_to(home) < LEASH + 10.0
	var want := Vector3.ZERO
	voice_t -= delta
	if voice_t <= 0.0 and state != "idle":
		voice_t = randf_range(3.0, 6.0)
		_growl()
	match state:
		"idle":
			if can and d < SIGHT and _clear(ppos):
				_set_state("chase")
				_growl()
			else:
				want = _wander(delta)
		"chase":
			if not can or global_position.distance_to(home) > LEASH or (d > SIGHT * 1.8):
				_set_state("return")
			else:
				want = _fight(delta, d, to, ppos)
		"return":
			if can and d < SIGHT * 0.7 and _clear(ppos):
				_set_state("chase")
			elif Vector2(home.x - global_position.x, home.z - global_position.z).length() < 1.5:
				_set_state("idle")
			else:
				want = _steer(home, delta) * speed * 0.8
		"stagger":
			if st > 0.35:
				_set_state("chase")
		_:
			want = _special(delta, d, to, ppos)
	velocity.x = want.x + knock.x
	velocity.z = want.z + knock.z
	var was_floor := is_on_floor()
	StepUp.step_up(self, was_floor, delta)   # ступеньки (промпт 03:51)
	move_and_slide()
	StepUp.step_down(self, was_floor)
	_animate(delta, Vector2(velocity.x, velocity.z).length())


# ---------- бой по видам ----------

func _fight(delta: float, d: float, to: Vector3, ppos: Vector3) -> Vector3:
	match kind:
		"spitter":
			if d < 1.6 and cool <= 0.0:
				_set_state("swipe")
				return Vector3.ZERO
			if d < 5.0:
				return _steer(global_position - to.normalized() * 3.0, delta) * speed
			if d > 10.5 or not _clear(ppos):
				return _steer(ppos, delta) * speed
			if cool <= 0.0:
				_set_state("spit_prep")
				return Vector3.ZERO
			_face(to, delta)
			var side := to.normalized().cross(Vector3.UP) * strafe
			if randf() < delta * 0.3:
				strafe = -strafe
			return _steer(global_position + side * 2.0, delta) * speed * 0.6
		"charger":
			if d < 2.0 and cool <= 0.0:
				_set_state("slam_prep")
				return Vector3.ZERO
			if d > 4.0 and d < 17.0 and cool <= 0.0 and _clear(ppos):
				_set_state("roar")
				_growl(0.6)
				return Vector3.ZERO
			return _steer(ppos, delta) * speed
		"stalker":
			vis_t -= delta
			_set_alpha(lerpf(alpha, 1.0 if vis_t > 0.0 else 0.12, 1.0 - exp(-5.0 * delta)))
			# цель — за спиной игрока
			var back: Vector3 = tg.player.global_transform.basis.z
			back.y = 0.0
			var goal := ppos + back.normalized() * 2.2
			var behind := back.normalized().dot((global_position - ppos).normalized()) > 0.3
			if d < 2.8 and cool <= 0.0 and (behind or d < 1.6):
				_set_state("lunge")
				hits_done = 0
				return Vector3.ZERO
			if d > 6.0:
				goal = ppos
			return _steer(goal, delta) * speed
	return Vector3.ZERO


## Особые состояния видов (замахи, рывки, оглушение).
func _special(delta: float, d: float, to: Vector3, ppos: Vector3) -> Vector3:
	match state:
		"spit_prep":
			_face(to, delta)
			sack.scale = Vector3.ONE * (1.0 + st * 1.2)
			glow_mat.emission_energy_multiplier = 2.0 + st * 6.0
			if st > 0.55:
				sack.scale = Vector3.ONE
				glow_mat.emission_energy_multiplier = 2.0
				var from := head.global_position + global_transform.basis.z * -0.0 + Vector3(0, -0.05, 0)
				var lead: Vector3 = ppos + Vector3(0, 1.0, 0) + tg.player.velocity * 0.45
				var v := _arc(from, lead, 13.0)
				_spit(from, v, true)
				_fx("spit", v)
				cool = SPIT_CD + randf_range(-0.4, 0.6)
				_set_state("chase")
		"swipe":
			_face(to, delta)
			if st > 0.35 and hits_done == 0:
				hits_done = 1
				if d < 1.8 and _clear(ppos):   # сквозь стены не бьёт (промпт 18.11 01:03)
					tg.damage_player(SWIPE_DMG, global_position)
			if st > 0.7:
				hits_done = 0
				cool = 1.0
				knock = -to.normalized() * 5.0   # отскок назад
				_set_state("chase")
		"roar":
			_face(to, delta)
			if st > 0.9:
				charge_dir = to.normalized()
				_set_state("charge")
		"charge":
			var v := charge_dir * CHARGE_SPEED
			if d < 1.5 and hits_done == 0 and tg.alive and _clear(ppos):
				hits_done = 1
				tg.damage_player(CHARGE_DMG, global_position)
				if tg == game:
					game.player.velocity += charge_dir * 9.0 + Vector3(0, 3.5, 0)
				_set_state("recover")
				cool = 4.0
				hits_done = 0
				return Vector3.ZERO
			if st > 0.15 and is_on_wall():
				_set_state("stunned")
				Fx.dust_burst(game, global_position + charge_dir * 0.8 + Vector3(0, 1.0, 0), Color(0.45, 0.4, 0.35), 26)
				_growl(0.5)
				cool = 4.5
				return Vector3.ZERO
			if st > 1.6:
				_set_state("recover")
				cool = 3.5
			return v
		"stunned":
			vis.rotation.z = sin(st * 14.0) * 0.08
			if st > 2.2:
				vis.rotation.z = 0.0
				_set_state("chase")
		"recover":
			if st > 0.8:
				_set_state("chase")
		"slam_prep":
			_face(to, delta)
			for a in arms:
				a.rotation.x = lerpf(a.rotation.x, -2.6, 1.0 - exp(-10.0 * delta))
			if st > 0.7:
				for a in arms:
					a.rotation.x = 0.3
				if d < 2.4 and _clear(ppos):
					tg.damage_player(SLAM_DMG, global_position)
				Fx.dust_burst(game, global_position - global_transform.basis.z * 1.0, Color(0.4, 0.37, 0.33), 18)
				cool = 2.2
				_set_state("recover")
		"lunge":
			vis_t = 1.0
			_set_alpha(1.0)
			_face(to, delta)
			if (hits_done == 0 and st > 0.25) or (hits_done == 1 and st > 0.6):
				hits_done += 1
				if d < 1.8 and _clear(ppos):
					tg.damage_player(STALK_DMG, global_position)
			if st > 0.9:
				hits_done = 0
				cool = 2.5
				_set_state("flee")
			return to.normalized() * (3.0 if d > 1.0 else 0.0)
		"flee":
			_set_alpha(lerpf(alpha, 0.12, 1.0 - exp(-4.0 * delta)))
			if st > 1.6:
				_set_state("chase")
			return _steer(global_position - to.normalized() * 6.0, delta) * speed * 1.1
	return Vector3.ZERO


## Скорость броска, чтобы комок по дуге (g = 9) прилетел в to.
func _arc(from: Vector3, to: Vector3, spd: float) -> Vector3:
	var d := to - from
	var flat := Vector3(d.x, 0, d.z)
	var t := clampf(flat.length() / spd, 0.25, 1.4)
	var v := flat / t
	v.y = (d.y + 0.5 * 9.0 * t * t) / t
	return v


# ---------- движение ----------

func _face(to: Vector3, delta: float) -> void:
	if to.length() < 0.01:
		return
	var a := atan2(-to.x, -to.z)
	rotation.y = lerp_angle(rotation.y, a, 1.0 - exp(-10.0 * delta))


## Направление к цели с обходом препятствий (луч вперёд на уровне пояса).
func _steer(goal: Vector3, delta: float) -> Vector3:
	var to := goal - global_position
	to.y = 0.0
	if to.length() < 0.2:
		return Vector3.ZERO
	var dir := to.normalized()
	avoid_t -= delta
	var probe := dir.rotated(Vector3.UP, avoid)
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.8, 0), global_position + Vector3(0, 0.8, 0) + probe * 1.4)
	q.collision_mask = 1
	q.exclude = [get_rid(), game.player.get_rid()]
	var blocked := not get_world_3d().direct_space_state.intersect_ray(q).is_empty()
	if blocked:
		avoid = clampf(avoid + strafe * 2.5 * delta * 3.0, -1.6, 1.6)
		avoid_t = 0.8
	elif avoid_t <= 0.0:
		avoid = move_toward(avoid, 0.0, delta * 1.5)
	var mv := dir.rotated(Vector3.UP, avoid)
	_face(mv, delta)
	return mv


func _wander(delta: float) -> Vector3:
	wander_t -= delta
	if wander_t <= 0.0:
		wander_t = randf_range(3.0, 7.0)
		wander_to = home + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6)) if randf() < 0.7 else global_position
	if Vector2(wander_to.x - global_position.x, wander_to.z - global_position.z).length() < 0.6:
		return Vector3.ZERO
	return _steer(wander_to, delta) * speed * 0.35


func _clear(to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, height * 0.8, 0), to + Vector3(0, 1.4, 0))
	q.collision_mask = 1
	# другие мутанты и сам игрок-цель обзор не загораживают; стены и заборы — да
	var ex: Array[RID] = [get_rid(), game.player.get_rid()]
	if tg != null and tg.player != null:
		ex.append(tg.player.get_rid())
	for m in get_tree().get_nodes_in_group("mutants"):
		ex.append(m.get_rid())
	q.exclude = ex
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _animate(delta: float, spd: float) -> void:
	walk_ph += delta * spd * (3.2 if kind != "charger" else 2.2)
	var sw := sin(walk_ph) * clampf(spd / 2.0, 0.0, 1.0)
	for i in legs.size():
		legs[i].rotation.x = sw * 0.6 * (1.0 if i == 0 else -1.0)
	if state != "slam_prep" and state != "recover":
		for i in arms.size():
			var base := -0.5 if (kind == "stalker" and state == "lunge") else 0.0
			arms[i].rotation.x = lerpf(arms[i].rotation.x, base - sw * 0.5 * (1.0 if i == 0 else -1.0), 1.0 - exp(-8.0 * delta))
	if kind == "stalker" and state == "lunge":
		arms[hits_done % 2].rotation.x = -1.6
	vis.position.y = absf(sin(walk_ph)) * 0.05 * clampf(spd / 3.0, 0.0, 1.0)
	torso.rotation.x = (0.35 if state == "charge" or state == "roar" else 0.0)


# ---------- урон ----------

func take_hit(dmg: float, dir: Vector3) -> void:
	if state == "dead":
		return
	game.weapon_hit()
	if net_puppet:
		_hit_fx(dmg, dir)
		var vn = game.get_tree().root.get_node_or_null("VillageNet")
		if vn:
			vn.rpc_id(1, "v_mut_hit", int(get_meta("nid", -1)), dmg, dir)
		return
	apply_hit(dmg, dir)


func _hit_fx(dmg: float, dir: Vector3) -> void:
	bar_t = 4.0
	Fx.damage_number(get_parent(), global_position + Vector3(0, height + 0.1, 0), dmg)
	Fx.dust_burst(get_parent(), global_position + Vector3(0, height * 0.6, 0) - dir * 0.2, (KINDS[kind]["skin"] as Color).lightened(0.2))


func apply_hit(dmg: float, dir: Vector3) -> void:
	if state == "dead":
		return
	if state == "stunned":
		dmg *= 2.0   # Таран, врезавшийся в стену, уязвим
	hp -= dmg
	_hit_fx(dmg, dir)
	bar_fg.scale.x = maxf(hp / max_hp, 0.0)
	vis_t = 2.0
	var flat := Vector3(dir.x, 0, dir.z).normalized()
	knock = flat * (1.0 if kind == "charger" else 3.5) * (1.0 + dmg * 0.04)
	if hp <= 0.0:
		_die(flat)
		return
	if state in ["idle", "return"]:
		_set_state("chase")
	elif kind != "charger" and state in ["chase", "spit_prep", "flee"]:
		_set_state("stagger")


func _die(_dir: Vector3) -> void:
	_set_state("dead")
	collision_layer = 0
	bar.visible = false
	_set_alpha(1.0)
	_growl(0.6)
	# разваливается на куски (world/gibs.gd), куски растворяются через 8 с
	var back := global_transform.basis.z
	Gibs.shatter(self, vis, _dir if _dir.length() > 0.01 else Vector3(back.x, 0, back.z).normalized())
	Fx.dust_burst(get_parent(), global_position + Vector3(0, 0.5, 0), Color(0.4, 0.38, 0.35), 30)
	get_tree().create_timer(Gibs.LIFE + 3.0, false).timeout.connect(queue_free)
	if not net_puppet:
		var at := global_position + Vector3(0, 0.8, 0)
		game.spawn_loot("coin", randi_range(3, 9), at, Vector3(0, 2.5, 0), 1.5)
		var r := randf()
		if r < 0.35:
			game.spawn_loot("ammo", randi_range(3, 6), at, Vector3(0, 2.5, 0), 1.5)
		elif r < 0.55:
			game.spawn_loot("filter", 1, at, Vector3(0, 2.5, 0), 1.5)
		elif r < 0.63:
			game.spawn_loot("fuel", 1, at, Vector3(0, 2.5, 0), 1.5)
	died.emit(self)


## Рык: процедурный, у каждого вида свой тон (Таран — низкий, Плевун — булькающий, Тень — шипение).
func _growl(db := 0.0) -> void:
	if game == null or not game.snd.has("growl"):
		return
	voice.stream = game.snd["growl"][randi() % game.snd["growl"].size()]
	voice.pitch_scale = {"spitter": 1.35, "charger": 0.6, "stalker": 1.8}[kind] * randf_range(0.93, 1.07)
	voice.volume_db = -8.0 + db * 10.0 - (8.0 if kind == "stalker" else 0.0)
	voice.play()


func _fx(what: String, a: Vector3) -> void:
	if game.net and game.net.is_host():
		var vn = game.get_tree().root.get_node_or_null("VillageNet")
		if vn:
			vn.rpc("v_mut_fx", int(get_meta("nid", -1)), what, a)


# ---------- сеть ----------

func net_apply(pos: Vector3, rot: float, s: String, h: float) -> void:
	net_pos = pos
	net_rot = rot
	if h < hp - 0.01:
		bar_t = 4.0
	hp = h
	bar_fg.scale.x = maxf(hp / max_hp, 0.0)
	if s == state:
		return
	if s == "dead":
		_die(Vector3.BACK)
		return
	if s == "roar":
		_growl(0.6)
	_set_state(s)


func net_fx(what: String, a: Vector3) -> void:
	if what == "spit" and state != "dead":
		_spit(head.global_position, a, false)


func _puppet_tick(delta: float) -> void:
	if state == "dead":
		return
	st += delta
	bar_t -= delta
	bar.visible = bar_t > 0.0
	var old := global_position
	if global_position.distance_to(net_pos) > 5.0:
		global_position = net_pos
	else:
		global_position = global_position.lerp(net_pos, 1.0 - exp(-12.0 * delta))
	rotation.y = lerp_angle(rotation.y, net_rot, 1.0 - exp(-12.0 * delta))
	if kind == "stalker":
		var seen := state in ["lunge", "stagger"] or bar_t > 2.0
		_set_alpha(lerpf(alpha, 1.0 if seen else 0.12, 1.0 - exp(-5.0 * delta)))
	var v := (global_position - old) / maxf(delta, 0.001)
	_animate(delta, Vector2(v.x, v.z).length())
