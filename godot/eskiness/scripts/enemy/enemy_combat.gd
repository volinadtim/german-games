extends "res://scripts/enemy/enemy_nav.gd"
# Часть enemy.gd: бой — удары, прыжки, броски камней, получение урона, смерть.


## Быстрый бегает рывками: рывок 0.35 с (×1.35), передышка 0.2 с (×0.38) — в среднем ≈ speed.
func _dash(delta: float) -> float:
	if kind != "fast":
		return 1.0
	dash_ph = fmod(dash_ph + delta / 0.55, 1.0)
	return 1.35 if dash_ph < 0.636 else 0.38
func _footsteps(_delta: float) -> void:
	if (not is_on_floor() and not net_puppet) or game == null or not game.snd.has("estep"):
		return
	var hv := Vector2(velocity.x, velocity.z).length()
	if hv < 0.3:
		_step_dist = 0.35
		return
	_step_dist += hv * get_physics_process_delta_time()
	if kind == "fast":
		# лёгкие частые шлепки: короткий шаг, тише, выше
		if _step_dist >= 0.42:
			_step_dist = 0.0
			game.play_at("estep", global_position + Vector3(0, 0.05, 0), -17.0 + minf(hv, 4.0) * 0.5, randf_range(1.15, 1.4))
		return
	# тяжёлый: шаг — строго когда нога ставится на землю по анимации (walk_ph проходит каждые π),
	# а не по пройденному пути — так звук не обгоняет медленную походку (промпт 14.11 18:41)
	var ph_step := int(floor(walk_ph / PI))
	if ph_step != _last_ph_step:
		_last_ph_step = ph_step
		game.play_at("estep", global_position + Vector3(0, 0.05, 0), -9.0 + minf(hv, 4.0), randf_range(0.58, 0.7))


## Абилки (кд 12 с у каждого): Шныга прыгает на игрока с 3–6 м, бетонник кидает камень с 5–12 м.
func _try_ability(d: float, ppos: Vector3) -> bool:
	if ability_cd > 0.0 or not tg.alive or not is_on_floor():
		return false
	if not _clear(global_position, ppos):
		return false
	if kind == "fast" and d > 3.0 and d < 6.0 and _leap_ok(ppos, d):
		ability_cd = ABILITY_CD
		_set_state("leap_prep")
		if _screech_cache.is_empty():
			for v in 3:
				_screech_cache.append(_screech(v))
		_play(voice, _screech_cache, -4.0, 1.25)
		return true
	if kind == "heavy" and d > 5.0 and d < 12.0:
		throw_vel = _plan_throw(ppos)
		if throw_vel == Vector3.INF:
			ability_cd = 1.5   # дуга не проходит (косяк, притолока, потолок) — подождать и попробовать снова
			return false
		# в бункере бросает реже
		ability_cd = ABILITY_CD * (1.6 if _zone(global_position) == 2 else 1.0)
		thrown = false
		_set_state("throw")
		_play(voice, game.snd["growl"], -9.0, 1.15)
		return true
	return false


## Прыжок Шныги: коридор прыжка свободен (лучи на трёх высотах и по бокам), в бункере — не через проём.
func _leap_ok(ppos: Vector3, d: float) -> bool:
	var dir := (ppos - global_position) * Vector3(1, 0, 1) / d
	var side := dir.cross(Vector3.UP) * 0.3
	var low := _zone(global_position) == 2
	if low and _crosses_door(global_position, ppos + tg.player.velocity * Vector3(1, 0, 1) * 0.35):
		return false
	for h in [0.35, 0.9, 1.8 if low else 2.1]:
		for s in [-1.0, 0.0, 1.0]:
			if not _free(global_position + Vector3(0, h, 0) + side * s, dir, d):
				return false
	return true


func _rock_from() -> Vector3:
	return global_position + Vector3(0, height * 0.95, 0) - global_transform.basis.z * 0.3


## Скорость броска, при которой ВСЯ дуга чиста (отрезками, как летит камень), или Vector3.INF.
## Наверху — обычная дуга, если перекрыта — площе или выше; в бункере — только прямой низкий бросок под притолокой.
func _plan_throw(ppos: Vector3) -> Vector3:
	var from := _rock_from()
	var dist := Vector2(ppos.x - from.x, ppos.z - from.z).length()
	var low := _zone(global_position) == 2 or _zone(ppos) == 2
	var times: Array = [dist / 17.0, dist / 14.0] if low else [dist / 11.0, dist / 16.0, dist / 8.5]
	for t0 in times:
		var t := clampf(t0, 0.25 if low else 0.35, 1.3)
		var aim: Vector3 = ppos + Vector3(0, 1.1, 0) + tg.player.velocity * Vector3(1, 0, 1) * t
		var v := Vector3((aim.x - from.x) / t, (aim.y - from.y + 0.5 * Rock.G * t * t) / t, (aim.z - from.z) / t)
		if low and v.y > 0.0 and from.y + v.y * v.y / (2.0 * Rock.G) > global_position.y + 2.15:
			continue   # выше притолоки проёма — в бункере так не кидает
		if _arc_clear(from, v, t):
			return v
	return Vector3.INF


## Дуга свободна: шаги по 0.04 с, луч на каждом отрезке (и чуть выше — камень не точка).
func _arc_clear(from: Vector3, v: Vector3, t: float) -> bool:
	var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
	var ex: Array[RID] = [get_rid(), tg.player.get_rid()]
	var n := maxi(int(ceil(t / 0.04)), 1)
	var dt := t / n
	var p := from
	for i in n:
		v.y -= Rock.G * dt
		var np := p + v * dt
		for off in [Vector3.ZERO, Vector3(0, 0.14, 0)]:
			var q := PhysicsRayQueryParameters3D.create(p + off, np + off)
			q.collision_mask = 1
			q.exclude = ex
			if not space.intersect_ray(q).is_empty():
				return false
		p = np
	return true


## Бросок камня по дуге с упреждением (дуга перепроверяется в момент броска). false — не бросил.
func _throw_rock(ppos: Vector3) -> bool:
	var from := _rock_from()
	var v := _plan_throw(ppos)
	if v == Vector3.INF:
		return false
	var r := Rock.new()
	r.game = game
	r.tg = tg
	r.dmg = ROCK_DMG
	r.vel = v
	r.owner_rid = get_rid()
	get_parent().add_child(r)
	r.global_position = from
	_play(body_snd, game.snd["whoosh"], -4.0, 0.6)
	return true


## Камень игрока упал рядом (stone_throw.gd): кто не видит игрока — идёт проверить место и стоит там пару секунд.
func hear_stone(at: Vector3) -> void:
	if net_puppet or not state in ["idle", "return", "investigate"]:
		return
	var ppos: Vector3 = tg.player.global_position
	if tg.alive and global_position.distance_to(ppos) < SIGHT and _clear(global_position, ppos):
		return   # игрока видит — отвлечь не выйдет
	probe = at
	probe_wait = 0.0
	think = 0.0
	_set_state("investigate")


## Камень бетонника: видимый серый булыжник, летит по дуге; попал в игрока — урон, в стену/землю — пыль и стук.
class Rock extends Node3D:
	const G := 14.0
	var game
	var tg   # в кого брошен (game или сетевой игрок)
	var vel := Vector3.ZERO
	var dmg := 13.0
	var life := 3.0
	var owner_rid: RID
	var spin := Vector3.ZERO

	func _ready() -> void:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.14
		sm.height = 0.24
		sm.radial_segments = 7
		sm.rings = 4
		mi.mesh = sm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.42, 0.41, 0.39)
		m.roughness = 1.0
		mi.material_override = m
		mi.scale = Vector3(1.0, 0.85, 1.15)
		add_child(mi)
		spin = Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9))

	func _physics_process(delta: float) -> void:
		life -= delta
		if life <= 0.0:
			queue_free()
			return
		vel.y -= G * delta
		var from := global_position
		var to := from + vel * delta
		rotation += spin * delta
		# попал в игрока (капсула ~ от ног до головы)
		if game != null and tg.alive:
			var pp: Vector3 = tg.player.global_position
			var seg := Geometry3D.get_closest_point_to_segment(pp + Vector3(0, 0.9, 0), from, to)
			if Vector2(seg.x - pp.x, seg.z - pp.z).length() < 0.45 and seg.y > pp.y - 0.1 and seg.y < pp.y + 1.9:
				tg.damage_player(dmg, from - vel.normalized() * 2.0)
				_burst(seg)
				return
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.collision_mask = 1
		q.exclude = [owner_rid, tg.player.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit:
			_burst(hit.position)
			return
		global_position = to

	func _burst(p: Vector3) -> void:
		Fx.dust_burst(get_parent(), p, Color(0.45, 0.43, 0.4), 18)
		game.play_at("thud", p, -8.0, 1.7)
		queue_free()


func _strike(d: float, to: Vector3) -> void:
	_play(body_snd, game.snd["whoosh"], -6.0 if kind == "heavy" else -9.0, 0.7 if kind == "heavy" else 1.15)
	cool = cool_t
	var fwd := -global_transform.basis.z
	if tg.alive and d < hit_range and fwd.dot(to.normalized()) > 0.3:
		tg.damage_player(damage, global_position)


func _growl() -> void:
	growl_t = randf_range(4.0, 8.0)
	if kind == "fast":
		growl_t = randf_range(2.5, 5.0)
		if _screech_cache.is_empty():
			for v in 3:
				_screech_cache.append(_screech(v))
		_play(voice, _screech_cache, -7.0, randf_range(0.9, 1.15))
		return
	_play(voice, game.snd["growl"], -8.0, randf_range(0.85, 1.05))


## Попадание кулаком игрока.
func take_hit(dmg: float, dir: Vector3) -> void:
	if state == "dead":
		return
	game.weapon_hit()
	if net_puppet:
		_hit_fx(dmg, dir)
		game.net.enemy_hit(self, dmg, dir)
		return
	apply_hit(dmg, dir)


func _hit_fx(dmg: float, dir: Vector3) -> void:
	bar_t = 4.0
	Fx.damage_number(get_parent(), global_position + Vector3(0, height + 0.1, 0), dmg)
	Fx.dust_burst(get_parent(), global_position + Vector3(0, height * 0.65, 0) - dir * 0.2)
	mat.emission_energy_multiplier = 0.5
	create_tween().tween_property(mat, "emission_energy_multiplier", 0.0, 0.25)


## Урон (у хоста — и от ударов других игроков по сети, net.gd).
func apply_hit(dmg: float, dir: Vector3) -> void:
	if state == "dead":
		return
	hp -= dmg
	bar_t = 4.0
	bar_fg.scale.x = maxf(hp / max_hp, 0.0)
	Fx.damage_number(get_parent(), global_position + Vector3(0, height + 0.1, 0), dmg)
	Fx.dust_burst(get_parent(), global_position + Vector3(0, height * 0.65, 0) - dir * 0.2)
	var flat := Vector3(dir.x, 0, dir.z).normalized()
	knock = flat * (3.0 + dmg * 0.06) * (1.0 if kind == "heavy" else 1.5)   # лёгкого отбрасывает дальше
	mat.emission_energy_multiplier = 0.5
	create_tween().tween_property(mat, "emission_energy_multiplier", 0.0, 0.25)
	if hp <= 0.0:
		_die(flat)
	elif not state in ["windup", "leap", "throw"]:
		_set_state("stagger")


func _die(dir: Vector3) -> void:
	_set_state("dead")
	collision_layer = 0
	bar.visible = false
	_play(body_snd, game.snd["thud"], -4.0, 0.9)
	# разваливается на куски (world/gibs.gd), сам враг невидим и удаляется после растворения кусков
	knock = Vector3.ZERO
	Gibs.shatter(self, vis, dir)
	Fx.dust_burst(get_parent(), global_position + Vector3(0, 0.5, 0), Color(0.4, 0.38, 0.35), 30)
	# лут (промпт 14.11 18:08): тяжёлый — 0–2 предмета и 0–6 монет; быстрый — 1–3 предмета и 0–2 монеты
	if net_puppet:
		# лут и respawn — у хоста (лут придёт по сети); копия тоже разваливается (выше)
		get_tree().create_timer(Gibs.LIFE + 3.0, false).timeout.connect(queue_free)
		return
	var pos := global_position + Vector3(0, height * 0.5, 0)
	if not drop_only.is_empty():
		for id in drop_only:
			game.spawn_loot(String(id), 1, pos, Vector3(0, 2.5, 0), 1.0)
		died.emit(self)
		get_tree().create_timer(Gibs.LIFE + 3.0, false).timeout.connect(queue_free)
		return
	var coins := randi_range(0, 6) if kind == "heavy" else randi_range(0, 2)
	if coins > 0:
		game.spawn_loot("coin", coins, pos, Vector3(0, 2.5, 0), 1.6)
	var extra: Array = ["bandage", "pills", "choco", "rusk", "battery", "scrap"]   # без гаек (промпт 16.11 02:47)
	for k in (randi_range(0, 2) if kind == "heavy" else randi_range(1, 3)):
		game.spawn_loot(extra[randi() % extra.size()], 1, pos, Vector3(0, 2.5, 0), 1.2)
	if randf() < 0.2:   # бечёвка — для молотка и кастета (промпт 14.11 19:22)
		game.spawn_loot("twine", 1, pos, Vector3(0, 2.5, 0), 1.2)
	if randf() < 0.03:  # кошелёк — редкость (промпт 14.11 17:21)
		game.spawn_loot("wallet", 1, pos, Vector3(0, 2.5, 0), 1.2)
	died.emit(self)
	get_tree().create_timer(Gibs.LIFE + 3.0, false).timeout.connect(queue_free)
