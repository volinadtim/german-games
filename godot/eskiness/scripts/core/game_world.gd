extends "res://scripts/core/game_base.gd"
# Часть game.gd: спавн мира — ящики, кувшины, враги, охотники, кучи камней, лут на полу.


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


func _random_jars() -> void:
	_collect_obstacles()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var placed: Array = []      # [[pos, радиус], ...]
	# в бункере — ровно 8–10 кувшинов (промпт 14.11 18:47), группами по 1–3 у стен
	var made := 0
	var want := rng.randi_range(8, 10)
	var tries := 0
	while made < want and tries < 400:
		tries += 1
		var a := _bunker_chest_spot()
		var b := Basis(Vector3.UP, float(a[1]))
		var along := b * Vector3.RIGHT
		var front := b * Vector3.BACK
		made += _jar_group(rng, a[0], along, front, placed, true, null, want - made)
	# снаружи — сразу до OUT_JARS_MAX, дальше их пополняет таймер (_outside_jar_tick)
	for k in OUT_JARS_MAX:
		_spawn_outside_jar(false)


func _is_outside_jar(j) -> bool:
	return is_instance_valid(j) and j.position.y > 2.0


func _outside_jar_tick(delta: float) -> void:
	if net and not net.is_host():
		return   # кувшины снаружи в сети появляются у хоста и приходят по сети
	_out_jar_t -= delta
	if _out_jar_t > 0.0:
		return
	_out_jar_t = OUT_JAR_EVERY
	var whole := 0
	var broken_out: Array = []
	for j in jars:
		if _is_outside_jar(j):
			if j.broken:
				broken_out.append(j)
			else:
				whole += 1
	while broken_out.size() > 6:
		var old = broken_out.pop_front()
		if net:
			net.jar_removed(old)
		jars.erase(old)
		old.queue_free()
	if whole < OUT_JARS_MAX:
		_spawn_outside_jar(true)


func _spawn_outside_jar(check_player: bool) -> bool:
	var surf: Node = get_parent().get_node_or_null("Level/Surface")
	if surf == null:
		return false
	var placed: Array = []
	for j in jars:
		if is_instance_valid(j) and not j.broken:
			placed.append([j.position, 0.17 * float(j.size)])
	for t in 40:
		var ang := randf() * TAU
		var rad := randf_range(2.0, Surface.MEADOW_R + 3.0)
		var p := Surface.CENTER + Vector3(cos(ang), 0, sin(ang)) * rad
		if Surface.in_hut(p, 1.0) or Vector2(p.x - Surface.CAR_POS.x, p.z - Surface.CAR_POS.z).length() < Surface.CAR_R:
			continue
		if check_player and player and Vector2(p.x - player.global_position.x, p.z - player.global_position.z).length() < 6.0:
			continue
		p.y = surf.height(p.x, p.z) - 0.02
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var prm := Jar.random_params(rng)
		var r := 0.17 * float(prm["size"])
		if _jar_spot_ok(p, r + 0.35, placed):
			var nj := _make_jar(p, randf() * TAU, prm, false)
			if net:
				net.jar_spawned(nj)
			return true
	return false


## Группа из 1–3 сосудов вдоль стены (или у руин): каждый прижат к опоре на свой радиус.
func _jar_group(rng: RandomNumberGenerator, anchor: Vector3, along: Vector3, front: Vector3, placed: Array, inside: bool, surf: Node = null, max_n := 3) -> int:
	var made := 0
	var n := mini(rng.randi_range(1, 3), max_n)
	var off := 0.0
	for k in n:
		var prm := Jar.random_params(rng)
		var r := 0.17 * float(prm["size"])
		var p := anchor + along * off
		if inside:
			p -= front * (0.33 - r - 0.06)   # anchor — в 0.33 м от стены; ставим вплотную
		else:
			p += front * 0.0
			p.y = surf.height(p.x, p.z) - 0.02
		if _jar_spot_ok(p, r, placed):
			placed.append([p, r])
			var j := _make_jar(p, rng.randf() * TAU, prm, false)
			if inside:
				# настоящий размер (с ручками) известен после постройки: придвигаем вплотную (~1 см до стены)
				j.position -= front * ((r + 0.06) - (_jar_reach(j, -front) + 0.01))
			made += 1
		off += (r * 2.0 + 0.12) * (1.0 if k % 2 == 0 else -1.0) * (k + 1)
	return made


## Насколько сосуд выступает от своего центра в сторону dir (по габаритам мешей, dir почти вдоль оси).
func _jar_reach(j: Node3D, dir: Vector3) -> float:
	var bb := AABB()
	var first := true
	for mi in j.find_children("*", "MeshInstance3D", true, false):
		if not mi.visible:
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		bb = b if first else bb.merge(b)
		first = false
	if first:
		return j.max_r * j.size
	var c := j.global_position
	if absf(dir.x) > absf(dir.z):
		return (bb.end.x - c.x) if dir.x > 0.0 else (c.x - bb.position.x)
	return (bb.end.z - c.z) if dir.z > 0.0 else (c.z - bb.position.z)


func _jar_spot_ok(p: Vector3, r: float, placed: Array) -> bool:
	for c in placed:
		if Vector2(p.x - c[0].x, p.z - c[0].z).length() < r + float(c[1]) + 0.08:
			return false
	if p.y < 1.0:
		for a in CHEST_AVOID:
			if Vector2(p.x - a[0].x, p.z - a[0].z).length() < float(a[1]):
				return false
		if glass_floor:
			for g in glass_floor.spots:
				if Vector2(p.x - g[0].x, p.z - g[0].z).length() < float(g[1]) + 0.6:
					return false
	if _on_object(p, r):
		return false
	var q := PhysicsShapeQueryParameters3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = r
	cyl.height = 0.3
	q.shape = cyl
	q.transform = Transform3D(Basis(), p + Vector3(0, 0.22, 0))
	q.collision_mask = 1
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


## Препятствия на полу (сундуки, мебель, обломки, автоматы...): [Rect2 след по XZ, низ y, верх y].
## Берём из CollisionShape3D статических тел, а не из физики: тела, добавленные в этом же кадре,
## физический запрос ещё не видит — из-за этого кувшины/стекло/камни попадали на объекты.
var _obst: Array = []

func _collect_obstacles() -> void:
	_obst = []
	for cs in get_parent().find_children("*", "CollisionShape3D", true, false):
		if cs.disabled or cs.shape == null or not (cs.get_parent() is StaticBody3D):
			continue
		var la := _shape_aabb(cs.shape)
		if la.size == Vector3.ZERO:
			continue
		var b: AABB = cs.global_transform * la
		if maxf(b.size.x, b.size.z) > 6.0:
			continue   # пол, потолок, длинные стены
		_obst.append([Rect2(b.position.x, b.position.z, b.size.x, b.size.z), b.position.y, b.end.y])


static func _shape_aabb(sh) -> AABB:
	if sh is BoxShape3D:
		return AABB(-sh.size / 2.0, sh.size)
	if sh is SphereShape3D:
		return AABB(-Vector3.ONE * sh.radius, Vector3.ONE * sh.radius * 2.0)
	if sh is CylinderShape3D or sh is CapsuleShape3D:
		return AABB(Vector3(-sh.radius, -sh.height / 2.0, -sh.radius), Vector3(sh.radius * 2.0, sh.height, sh.radius * 2.0))
	if sh is ConvexPolygonShape3D and sh.points.size() > 0:
		var a := AABB(sh.points[0], Vector3.ZERO)
		for pt in sh.points:
			a = a.expand(pt)
		return a
	return AABB()


## Круг радиуса r на полу в точке p задевает объект (сундук, мебель...)?
func _on_object(p: Vector3, r: float) -> bool:
	for o in _obst:
		if o[2] < p.y + 0.04 or o[1] > p.y + 1.2:
			continue   # плоское на полу или высоко над головой
		var rc: Rect2 = o[0]
		var cx := clampf(p.x, rc.position.x, rc.end.x)
		var cz := clampf(p.z, rc.position.y, rc.end.y)
		if Vector2(p.x - cx, p.z - cz).length() < r:
			return true
	return false


## Ближайшее к p свободное место на полу (по кольцам, детерминированно); sf — поверхность для высоты.
func _free_spot_near(p: Vector3, r: float, sf: Node = null) -> Vector3:
	if not _on_object(p, r):
		return p
	for ring in range(1, 9):
		var rad := 0.2 * ring
		for k in 12:
			var ang := TAU * k / 12.0
			var q := p + Vector3(cos(ang), 0, sin(ang)) * rad
			if sf and q.y > 1.0:
				q.y = sf.height(q.x, q.z)
			if not _on_object(q, r):
				return q
	return p


func _make_jar(pos: Vector3, rot: float, prm: Dictionary, was_broken: bool) -> Jar:
	var j := Jar.new()
	j.game = self
	j.setup(prm)
	j.broken = was_broken
	j.position = pos
	j.rotation.y = rot
	add_child(j)
	jars.append(j)
	return j


## Точка у случайной стены случайной комнаты бункера; поворот — передом (+Z ящика) в комнату.
func _bunker_chest_spot() -> Array:
	var sx := -1.0 if randf() < 0.5 else 1.0
	var sz := -1.0 if randf() < 0.5 else 1.0
	var x0 := 0.15 if sx > 0 else -11.85
	var x1 := 11.85 if sx > 0 else -0.15
	var z0 := 1.75 if sz > 0 else -8.85
	var z1 := 8.85 if sz > 0 else -1.75
	var off := 0.33          # половина глубины ящика + зазор
	var pos: Vector3
	var rot: float
	match randi() % 4:
		0:   # дальняя стена комнаты
			pos = Vector3(randf_range(x0 + 0.8, x1 - 0.8), 0, sz * (8.85 - off))
			rot = 0.0 if sz < 0 else PI
		1:   # стена коридора
			pos = Vector3(randf_range(x0 + 0.8, x1 - 0.8), 0, sz * (1.75 + off))
			rot = PI if sz < 0 else 0.0
		2:   # торцевая стена бункера
			pos = Vector3(sx * (11.85 - off), 0, randf_range(z0 + 0.8, z1 - 0.8))
			rot = -sx * PI / 2.0
		_:   # перегородка между комнатами
			pos = Vector3(sx * (0.15 + off), 0, randf_range(z0 + 0.8, z1 - 0.8))
			rot = sx * PI / 2.0
	return [pos, rot + randf_range(-0.06, 0.06)]


func _spawn_enemy(pos: Vector3) -> void:
	var e := Enemy.new()
	e.game = self
	e.kind = "fast" if randf() < FAST_SHARE else "heavy"   # смешанные типы (промпт 14.11 18:08)
	e.position = pos
	e.rotation.y = randf_range(0, TAU)
	add_child(e)
	e.died.connect(func(_e): _respawn_enemy_later(pos))


func _respawn_enemy_later(pos: Vector3) -> void:
	await get_tree().create_timer(RESPAWN).timeout
	while is_instance_valid(player) and player.global_position.distance_to(pos) < 8.0:
		await get_tree().create_timer(5.0).timeout
	_spawn_enemy(pos)


func _spawn_stone_piles() -> void:
	var sf: Node = null
	var level: Node = get_parent().get_node_or_null("Level")
	if level:
		for c in level.get_children():
			if c.has_method("height"):
				sf = c
	# каждую новую игру — в новых местах (промпт 03:18): в бункере 2–3 кучки, по одной на комнату,
	# не в коридоре, не у проёмов и не на предметах; снаружи — около прежних точек со случайным сдвигом
	_collect_obstacles()
	var all: Array = []
	var rooms := [0, 1, 2, 3]
	rooms.shuffle()
	for ri in randi_range(2, 3):
		var sx := -1.0 if rooms[ri] % 2 == 0 else 1.0
		var sz := -1.0 if rooms[ri] < 2 else 1.0
		for t in 60:
			var q := Vector3(sx * randf_range(0.8, 11.3), 0.0, sz * randf_range(2.5, 8.4))
			if _stone_spot_ok(q, all):
				all.append(q)
				break
	for p in STONE_SURFACE:
		for t in 30:
			var q: Vector3 = p + Vector3(randf_range(-3.5, 3.5), 0.0, randf_range(-3.5, 3.5))
			if t == 29:
				q = p
			q.y = sf.height(q.x, q.z) if sf else 6.0
			if t == 29 or not _on_object(q, 0.45):
				all.append(q)
				break
	make_stone_piles(all, [])


## Кучки камней в точках pts (сколько осталось — lefts, иначе 2–4). Из сейва и из сети — те же места.
func make_stone_piles(pts: Array, lefts: Array) -> void:
	for sp in stone_piles:
		if is_instance_valid(sp):
			sp.queue_free()
	stone_piles = []
	for k in pts.size():
		var sp := StonePile.new()
		sp.seed_ = k
		sp.left = int(lefts[k]) if k < lefts.size() else randi_range(2, 4)
		sp.position = pts[k]
		add_child(sp)
		stone_piles.append(sp)


## Место для кучки в бункере: не на предмете, не у проёмов (двери коридора x = ±6, дверь между южными
## комнатами z = 5.5) и не вплотную к другой кучке.
func _stone_spot_ok(q: Vector3, others: Array) -> bool:
	if _on_object(q, 0.45):
		return false
	for d in [Vector2(-6.0, -1.6), Vector2(6.0, -1.6), Vector2(-6.0, 1.6), Vector2(6.0, 1.6), Vector2(0.0, 5.5)]:
		if Vector2(q.x, q.z).distance_to(d) < 2.0:
			return false
	if absf(q.x) < 0.9:
		return false   # вдоль перегородки между комнатами
	for o in others:
		if (o as Vector3).distance_to(q) < 3.0:
			return false
	return true


## Магазин: закрыть все открытые ящики — при новом открытии в них будет новый лут. Сейф не трогаем.
func refresh_chests() -> int:
	var n := 0
	for c in chests:
		if is_instance_valid(c) and c.opened:
			c.reset()
			n += 1
	return n


## Высыпать лут: монеты разбиваются на несколько монеток, разлетаются с разбросом spread.
## leave — не подбирать само, пока игрок не отойдёт (вещи, которые он не взял из окна лута).
func spawn_loot(id: String, n: int, pos: Vector3, vel: Vector3, spread: float, leave := false) -> void:
	var parts := 1
	if id == "coin":
		parts = clampi(n, 1, 6)
	@warning_ignore("integer_division")
	var per := n / parts
	var rest := n - per * parts
	for k in parts:
		var cnt := per + (1 if k < rest else 0)
		var v := vel + Vector3(randf_range(-1, 1), randf_range(0, 0.6), randf_range(-1, 1)) * spread
		_make_pickup(id, cnt, pos + Vector3(randf_range(-0.1, 0.1), 0, randf_range(-0.1, 0.1)), v).need_leave = leave


func _make_pickup(id: String, n: int, pos: Vector3, vel: Vector3) -> Pickup:
	# рядом с игроком (выброс из инвентаря у стены) — не в стене и не за ней: ставим перед стеной (промпт 18:36)
	if is_instance_valid(player) and player.is_inside_tree():
		var from := player.global_position + Vector3(0, 1.0, 0)
		if from.distance_to(pos) < 2.0:
			var q := PhysicsRayQueryParameters3D.create(from, pos)
			q.collision_mask = 1
			q.exclude = [player.get_rid()]
			var hit := get_world_3d().direct_space_state.intersect_ray(q)
			if hit:
				pos = (hit.position as Vector3) - (pos - from).normalized() * 0.2
	var p := Pickup.new()
	p.game = self
	p.id = id
	p.n = n
	add_child(p)
	p.global_position = pos
	p.linear_velocity = vel
	p.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
	if net:
		net.pickup_made(p)   # разослать остальным (поля need_leave/dur выставят после — шлём в конце кадра)
	return p
