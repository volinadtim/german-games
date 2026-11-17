extends "res://scripts/enemy/enemy_model.gd"
# Часть enemy.gd: навигация — обход стен, проёмы, зоны, блуждание, застревание.


## Направление движения к цели: напрямую, если видно, иначе через ближайший подходящий проём.
func _steer(goal: Vector3, delta: float) -> Vector3:
	think -= delta
	if think <= 0.0:
		think = 0.3
		target = goal
		# охотник: между поляной/лестницей и бункером ходит через низ лестницы
		var up := global_position.x > 12.4
		if hunter and up != (goal.x > 12.4):
			target = Vector3(11.4, global_position.y, 0.0) if up else Vector3(13.6, 0.0, 0.0)
		elif surface and _zone(global_position) != _zone(goal):
			target = _route(goal)
			if _zone(global_position) == 2 and not _clear(global_position, target):
				target = _doorway_to(target)
		elif (not surface or _zone(global_position) == 2) and not _clear(global_position, goal):
			target = _doorway_to(goal)
	var tp := target
	in_door = false
	if _zone(global_position) == 2:
		tp = _through_door(target)
	var dir := tp - global_position
	dir.y = 0.0
	var dist := dir.length()
	if dist < 0.05:
		return Vector3.ZERO
	# в проёме «усы» не нужны (они цепляют косяки и уводят в стену) — идём по оси, соседей обтекает move_and_slide
	dir = dir.normalized() if in_door else _avoid(dir.normalized(), minf(dist, 1.3), delta)
	_face(dir, delta)
	return dir


## Путь к goal пересекает проём — сначала точка на оси проёма со своей стороны, у оси — насквозь на 1.2 м.
func _through_door(goal: Vector3) -> Vector3:
	var p := global_position
	for dr in DOORS:
		var c: Vector3 = dr[0]
		var n: Vector3 = dr[1]
		var sp := (p.x - c.x) * n.x + (p.z - c.z) * n.z
		var sg := (goal.x - c.x) * n.x + (goal.z - c.z) * n.z
		if sp * sg >= 0.0 or absf(sp) > 3.5:
			continue
		var ax := Vector3(n.z, 0, -n.x)   # вдоль стены
		var x := p.lerp(goal, sp / (sp - sg))
		if absf((x.x - c.x) * ax.x + (x.z - c.z) * ax.z) > DOOR_HALF + 0.8:
			continue   # путь пересекает стену не у этого проёма
		var lat := (p.x - c.x) * ax.x + (p.z - c.z) * ax.z
		var side := signf(sp)
		var cc := Vector3(c.x, p.y, c.z)
		if absf(lat) > 0.2 and absf(sp) > 0.45:
			return cc + n * side * clampf(absf(sp) * 0.5, 0.45, 1.0)
		in_door = absf(lat) < DOOR_HALF + 0.3
		return cc - n * side * 1.2
	return goal


## Отрезок a→b проходит через проём бункера (прыжок Шныги так не делаем).
func _crosses_door(a: Vector3, b: Vector3) -> bool:
	for dr in DOORS:
		var c: Vector3 = dr[0]
		var n: Vector3 = dr[1]
		var sa := (a.x - c.x) * n.x + (a.z - c.z) * n.z
		var sb := (b.x - c.x) * n.x + (b.z - c.z) * n.z
		if sa * sb > 0.0 and minf(absf(sa), absf(sb)) > 0.5:
			continue
		var ax := Vector3(n.z, 0, -n.x)
		var x := a.lerp(b, clampf(sa / (sa - sb), 0.0, 1.0)) if absf(sa - sb) > 0.001 else a
		if absf((x.x - c.x) * ax.x + (x.z - c.z) * ax.z) < DOOR_HALF + 0.6:
			return true
	return false


# ---------- ум (промпт 19:15): обход препятствий, окружение, абилки ----------

## «Усы»: луч вперёд на уровне пояса. Впереди стена/кувшин/ящик/другой враг — выбираем сторону, где больше места,
## и держим её (обходим вдоль препятствия по наименьшему свободному углу), пока путь не будет чист 0.3 с.
## Сторона вся перекрыта — пробуем другую. Так враг не мечется туда-сюда перед препятствием.
func _avoid(dir: Vector3, look: float, delta: float) -> Vector3:
	var from := global_position + Vector3(0, 0.55, 0)
	if _free(from, dir, look):
		avoid_clear += delta
		if avoid_clear > 0.3:
			avoid_on = false
		if not avoid_on:
			avoid_angle = 0.0
			return dir
	else:
		avoid_clear = 0.0
	if not avoid_on:
		var l := _free_dist(from, dir.rotated(Vector3.UP, 1.2), 3.0)
		var r := _free_dist(from, dir.rotated(Vector3.UP, -1.2), 3.0)
		avoid_side = 1.0 if l >= r else -1.0
		avoid_on = true
	for a in [0.0, 0.45, 0.8, 1.15, 1.5, 1.8]:
		var d2 := dir.rotated(Vector3.UP, a * avoid_side)
		# вбок смотрим ближе (в узком коридоре боковой луч иначе упирается в стену)
		if _free(from, d2, look * maxf(0.45, cos(a))):
			avoid_angle = a * avoid_side
			return d2
	avoid_side = -avoid_side
	avoid_angle = 1.6 * avoid_side
	return dir.rotated(Vector3.UP, avoid_angle)


func _free_dist(from: Vector3, dir: Vector3, look: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * look)
	q.collision_mask = 1
	q.exclude = [get_rid(), tg.player.get_rid()]
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(q)
	return look if hit.is_empty() else from.distance_to(hit["position"])


func _free(from: Vector3, dir: Vector3, look: float) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * look)
	q.collision_mask = 1
	q.exclude = [get_rid(), tg.player.get_rid()]
	return game.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Застрял (хочет идти, а почти не сдвинулся за секунду) — меняет сторону обхода и отходит вбок.
func _check_stuck(delta: float, want: Vector3) -> void:
	if want.length() < 0.5 or state in ["leap", "leap_prep", "throw", "dead"]:
		stuck_t = 0.0
		stuck_pos = global_position
		return
	stuck_t += delta
	if stuck_t > 1.0:
		if global_position.distance_to(stuck_pos) < 0.25:
			avoid_side = -avoid_side   # упёрся — обходим с другой стороны
			avoid_on = true
			avoid_clear = 0.0
		stuck_t = 0.0
		stuck_pos = global_position


## Окружение: если другой враг уже бьёт игрока спереди, этот заходит сбоку/сзади (±110°/±150°/±90° от взгляда
## игрока, по очереди между врагами), чтобы не толпиться в одну точку.
func _chase_goal(ppos: Vector3, d: float) -> Vector3:
	if d > 5.0:
		return ppos
	var front := _front_enemy(ppos)
	if front == null or front == self:
		return ppos
	var pf: Vector3 = -tg.player.global_transform.basis.z
	pf.y = 0.0
	if pf.length() < 0.01:
		return ppos
	var slot := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == self or e == front or e.state == "dead":
			continue
		if e.global_position.distance_to(ppos) < 6.0 and e.get_instance_id() < get_instance_id():
			slot += 1
	var ang: float = [1.92, -1.92, 2.6, -2.6, 1.57, -1.57][slot % 6]
	var p: Vector3 = ppos + pf.normalized().rotated(Vector3.UP, ang) * attack_range * 0.8
	if not _clear(ppos, p):
		return ppos
	return p


## Кто сейчас «спереди»: ближайший к игроку враг в конусе его взгляда (≈ ±55°) не дальше 2.4 м.
func _front_enemy(ppos: Vector3) -> Node:
	var pf: Vector3 = -tg.player.global_transform.basis.z
	pf.y = 0.0
	pf = pf.normalized()
	# кто уже «спереди», тот и остаётся, пока рядом и перед игроком (иначе роли скачут: заходящий сбоку
	# проходит через конус взгляда, становится ближайшим и «отбирает» фронт)
	var cur = instance_from_id(_front_id) if _front_id != 0 else null
	if cur != null and is_instance_valid(cur) and cur.is_inside_tree() and not cur.state in ["dead", "idle", "return"]:
		var cv: Vector3 = cur.global_position - ppos
		cv.y = 0.0
		if cv.length() < 3.0 and cv.length() > 0.01 and pf.dot(cv.normalized()) > 0.3:
			return cur
	var best: Node = null
	var bd := 2.4
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.state in ["dead", "idle", "return"]:
			continue
		var v: Vector3 = e.global_position - ppos
		v.y = 0.0
		var dd := v.length()
		if dd < bd and dd > 0.01 and pf.dot(v / dd) > 0.57:
			bd = dd
			best = e
	_front_id = best.get_instance_id() if best != null else 0
	return best


## Где точка: 0 — поляна (поверху, не в будке), 1 — будка и лестница, 2 — бункер.
func _zone(p: Vector3) -> int:
	if p.y > Surface.G - 1.0 and not Surface.in_hut(p):
		return 0
	if p.x < Surface.X_WALL:
		return 2
	return 1


## Промежуточная точка пути между зонами: поляна ↔ вход в будку ↔ лестница ↔ бункер.
func _route(goal: Vector3) -> Vector3:
	var p := global_position
	var gz := _zone(goal)
	match _zone(p):
		0:
			var sz := 1.0 if p.z >= 0.0 else -1.0
			if p.x < 21.4 and absf(p.z) < 3.0:
				return Vector3(p.x, Surface.G, 4.4 * sz)       # сбоку/позади будки — отойти от стены
			if p.x < 21.4:
				return Vector3(24.0, Surface.G, 4.4 * sz)      # обогнуть угол (мимо обломков у входа)
			if p.x < 23.6 and absf(p.z) < 1.0:
				return Vector3(19.6, Surface.G, 0.0)           # у входа — внутрь, на площадку
			return Vector3(23.0, Surface.G, 0.0)               # к входу
		1:
			return Vector3(11.2, 0.0, 0.0) if gz == 2 else Vector3(23.0, Surface.G, 0.0)
		_:
			return Vector3(13.2, 0.0, 0.0)                     # к проёму на лестницу


## Следующая точка пути по бункеру к цели (кратчайший путь по WAYPOINTS, Дейкстра на ~20 точках).
func _doorway_to(goal: Vector3) -> Vector3:
	var n := WAYPOINTS.size()
	if _wp_links.is_empty():
		for i in n:
			var l: Array = []
			for j in n:
				if i != j and _clear(WAYPOINTS[i], WAYPOINTS[j]):
					l.append(j)
			_wp_links.append(l)
	# старт и финиш подключаем к видимым точкам
	var from_me: Array = []
	var to_goal := {}
	for i in n:
		var q: Vector3 = WAYPOINTS[i]
		if Vector2(q.x - global_position.x, q.z - global_position.z).length() > 0.5 and _clear(global_position, q):
			from_me.append(i)
		if _clear(q, goal):
			to_goal[i] = true
	var dist: Array = []
	var prev: Array = []
	var done: Array = []
	for i in n:
		dist.append(INF)
		prev.append(-1)
		done.append(false)
	for i in from_me:
		dist[i] = global_position.distance_to(WAYPOINTS[i])
	var best_end := -1
	var best_cost := INF
	for it in n:
		var u := -1
		for i in n:
			if not done[i] and dist[i] < INF and (u == -1 or dist[i] < dist[u]):
				u = i
		if u == -1:
			break
		done[u] = true
		if to_goal.has(u):
			var c: float = dist[u] + (WAYPOINTS[u] as Vector3).distance_to(goal)
			if c < best_cost:
				best_cost = c
				best_end = u
		for v in _wp_links[u]:
			var nd: float = dist[u] + (WAYPOINTS[u] as Vector3).distance_to(WAYPOINTS[v])
			if nd < dist[v]:
				dist[v] = nd
				prev[v] = u
	if best_end == -1:
		return goal
	var k := best_end
	while prev[k] != -1:
		k = prev[k]
	var t: Vector3 = WAYPOINTS[k]
	return Vector3(t.x, global_position.y, t.z)


## Блуждание по поляне: идёт к случайной точке, постоит, выбирает следующую.
func _wander(delta: float) -> Vector3:
	wander_t -= delta
	if wander_t <= 0.0:
		wander_t = randf_range(5.0, 11.0)
		for i in 20:
			var a := randf() * TAU
			var r := Surface.MEADOW_R * sqrt(randf())
			var p := Surface.CENTER + Vector3(cos(a) * r, 0, sin(a) * r)
			if not Surface.in_hut(p, 2.0):
				target = p
				break
	var dir := target - global_position
	dir.y = 0.0
	if dir.length() < 0.6:
		return Vector3.ZERO
	dir = dir.normalized()
	_face(dir, delta)
	return dir * WANDER_SPEED


func _from_center(p: Vector3) -> float:
	return Vector2(p.x - Surface.CENTER.x, p.z - Surface.CENTER.z).length()


# ---------- граница первой локации (промпт 18.11 01:01) ----------
# Мобы поляны гонятся за игроком куда угодно в пределах локации (поляна + начало дороги в деревню — переход),
# но сами за границу не выходят: у края стоят и бьют, если игрок рядом.
const ROAM_R := 22.0         # поляна (MEADOW_R + 8)
const ROAD_HALF := 9.0       # коридор дороги на север: |x - CENTER.x| < ROAD_HALF
const ROAD_Z1 := 44.0        # до сюда — ещё первая локация (переход ко второй)

func _in_bounds(p: Vector3) -> bool:
	if _from_center(p) <= ROAM_R:
		return true
	return absf(p.x - Surface.CENTER.x) < ROAD_HALF and p.z > 0.0 and p.z < ROAD_Z1


## Не даёт выйти за границу локации: шаг наружу — скользит вдоль края (по одной оси) или стоит.
func _keep_in(want: Vector3) -> Vector3:
	if want == Vector3.ZERO or _zone(global_position) != 0:
		return want
	var p := global_position
	if not _in_bounds(p):
		# уже снаружи (отбросило) — пускаем только внутрь
		var back := Surface.CENTER - p
		back.y = 0.0
		return want if want.dot(back) > 0.0 else back.normalized() * want.length() * 0.6
	var look := 0.35
	if _in_bounds(p + want * look):
		return want
	var wx := Vector3(want.x, 0.0, 0.0)
	var wz := Vector3(0.0, 0.0, want.z)
	if absf(want.x) >= absf(want.z):
		if _in_bounds(p + wx * look):
			return wx
		if _in_bounds(p + wz * look):
			return wz
	else:
		if _in_bounds(p + wz * look):
			return wz
		if _in_bounds(p + wx * look):
			return wx
	return Vector3.ZERO


## Видит игрока: в пределах дальности (вприсядку — меньше), в конусе взгляда (вплотную — в любую сторону), без стен.
func _sees(ppos: Vector3, d: float, rng := SIGHT) -> bool:
	if not tg.alive:
		return false
	var pl = tg.player
	var crouch := bool(pl.get("crouched"))
	if crouch:
		rng *= SIGHT_CROUCH
	rng *= _light_mult()
	if d > rng:
		return false
	if d > (NEAR_FEEL_CROUCH if crouch else NEAR_FEEL):
		var fwd := -global_transform.basis.z
		fwd.y = 0.0
		var to := ppos - global_position
		to.y = 0.0
		if fwd.length() > 0.01 and to.length() > 0.01 and fwd.normalized().dot(to.normalized()) < cos(deg_to_rad(FOV_DEG)):
			return false
	return _clear(global_position, ppos)


## Свет: фонарик игрока включён — видно дальше; выключен в бункере (темно) — ближе.
func _light_mult() -> float:
	if tg.player == game.player and game.get("flashlight") != null and game.flashlight.on:
		return 1.3
	return 0.75 if _zone(global_position) == 2 else 1.0


## Постепенное обнаружение: видит — копит подозрение (быстрее вблизи), не видит — остывает. true — заметил.
func _notice(ppos: Vector3, d: float, delta: float) -> bool:
	if hunter:
		suspicion = 1.0
	elif _sees(ppos, d):
		var rng := SIGHT * _light_mult() * (SIGHT_CROUCH if bool(tg.player.get("crouched")) else 1.0)
		var t := lerpf(NOTICE_NEAR, NOTICE_FAR, clampf(d / maxf(rng, 0.1), 0.0, 1.0))
		suspicion = minf(suspicion + delta / t, 1.0)
		if suspicion > 0.45:
			var to := ppos - global_position
			to.y = 0.0
			_face(to, delta * 0.5)   # насторожился — поворачивается посмотреть
	else:
		suspicion = maxf(suspicion - delta * 0.35, 0.0)
	_sus_show()
	return suspicion >= 1.0


func _sus_show() -> void:
	var show := suspicion > 0.05 and suspicion < 1.0 and state in ["idle", "investigate", "return"]
	if sus_label == null:
		if not show:
			return
		sus_label = Label3D.new()
		sus_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sus_label.font_size = 64
		sus_label.pixel_size = 0.006
		sus_label.outline_size = 10
		sus_label.no_depth_test = true
		sus_label.position = Vector3(0, height + 0.55, 0)
		add_child(sus_label)
	sus_label.visible = show
	if show:
		sus_label.text = "?" if suspicion < 0.6 else "!"
		sus_label.modulate = Color(1.0, 1.0 - suspicion * 0.8, 0.3 - suspicion * 0.3, 0.35 + suspicion * 0.65)


## Слышит игрока: дистанция меньше его шума (через стену — вдвое меньше).
func _hears(ppos: Vector3, d: float) -> bool:
	if not tg.alive:
		return false
	var r := float(tg.player.get("noise_r")) if tg.player.get("noise_r") != null else 0.0
	if r <= 0.0 or d > r:
		return false
	return d < r * 0.5 or _clear(global_position, ppos)


## Цель сидит в машине (промпт 18.11 01:25): враги агрятся на машину — кузов не мешает видеть и бить,
## удары идут по кузову (car_drive.gd enemy_hit). null — цель не в машине.
func _car_tgt():
	if game == null or tg == null or tg.player == null:
		return null
	var c = game.get("car")
	if c == null or not is_instance_valid(c) or String(c.state) != "parked":
		return null
	var l: Vector3 = c.global_transform.affine_inverse() * tg.player.global_position
	if absf(l.x) > 1.2 or absf(l.z) > 2.3 or l.y < -0.3 or l.y > 2.0:
		return null
	return c


## Машина шумит (мотор / катится) — слышно далеко.
func _car_noisy(c) -> bool:
	return c != null and (bool(c.engine_on) or absf(float(c.speed)) > 0.4)


func _clear(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a + Vector3(0, 1.2, 0), b + Vector3(0, 1.2, 0))
	q.collision_mask = 1
	# другие враги обзор не загораживают (иначе второй «не видит» игрока за спиной первого)
	var ex: Array[RID] = [get_rid(), tg.player.get_rid()]
	var car = _car_tgt()
	if car != null:
		ex.append(car.get_rid())   # игрока в машине видно (стёкла выбиты) и достать можно
	if is_inside_tree():
		for e in get_tree().get_nodes_in_group("enemies"):
			ex.append(e.get_rid())
	q.exclude = ex
	return game.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _face(dir: Vector3, delta: float) -> void:
	if dir.length() < 0.01:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 1.0 - exp(-7.0 * delta))
