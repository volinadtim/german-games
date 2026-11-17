extends "res://scripts/world/jar_model.gd"
## Кувшин или колба — бьющиеся «лутбоксы» (промпт 14.11 00:08). Расставляет их game.gd случайно каждую игру.
## Форма точится по профилю (как на гончарном круге), размер и пропорции — случайные от seed:
##   jar     — пузатый глиняный кувшин с горлышком и полосками глазури;
##   amphora — высокий узкий кувшин;
##   flask   — круглая колба с длинным горлом, внутри мутная светящаяся жидкость;
##   cone    — коническая колба (как в лаборатории), тоже с жидкостью.
## Удар кулаком или оружием (take_hit) — разбивается: звон стекла или хруст керамики, осколки разлетаются
## и остаются лежать; лут (всегда монеты + несколько вещей) вылетает на пол. Большие кувшины выдерживают один удар.


func setup(params: Dictionary) -> void:
	kind = params["kind"]
	size = float(params["size"])
	seed_ = int(params["seed"])
	if kind == "flask" or kind == "cone":  # старые сейвы с колбами — теперь керамика
		kind = "jar" if kind == "flask" else "amphora"
		size = clampf(size * 1.2, 0.65, 1.6)


func to_save() -> Array:
	return [position.x, position.y, position.z, rotation.y, kind, size, seed_, broken]


func _ready() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed_
	var prof := _profile(r)
	_lathe(prof, r)
	hp = 1.0   # любой кувшин — с одного удара (промпт 18.11 01:16)
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = max_r * size * 0.9
	cyl.height = height * size
	cs.shape = cyl
	cs.position.y = height * size / 2.0
	add_child(cs)
	if broken:
		_hide_body()
		_scatter_static(r)


# ---------- разбивание ----------

func take_hit(_dmg: float, dir: Vector3) -> void:
	if broken:
		return
	if game:
		game.weapon_hit()
	if game and game.net and game.net.jar_hit(self, dir):
		return   # клиент: удар ушёл хосту, разобьётся по его команде
	hp -= 1.0
	if hp > 0.0:
		# треснул, но держится: качнулся и звякнул
		var tw := create_tween()
		tw.tween_property(self, "rotation:z", 0.12, 0.05)
		tw.tween_property(self, "rotation:z", 0.0, 0.2).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		_play(_sound(kind in ["flask", "cone"], true), -12.0)
		return
	_shatter(dir)


func _shatter(dir: Vector3) -> void:
	broken = true
	_hide_body()
	var glass := kind in ["flask", "cone"]
	_play(_sound(glass, false), -6.0)
	Fx.dust_burst(get_parent(), global_position + Vector3(0, height * size * 0.5, 0), body_col.lightened(0.2) if not glass else Color(0.6, 0.65, 0.6), 18)
	# осколки
	var r := RandomNumberGenerator.new()
	r.randomize()
	var flat := Vector3(dir.x, 0, dir.z).normalized()
	for k in int(8 + 6 * size):
		var sh := _shard_mesh(r, glass)
		sh.position = Vector3(r.randf_range(-max_r, max_r), r.randf_range(0.05, height), r.randf_range(-max_r, max_r)) * size
		add_child(sh)
		var v := (Vector3(r.randf_range(-1, 1), r.randf_range(0.6, 1.6), r.randf_range(-1, 1)) * 1.6 + flat * 1.5)
		var w := Vector3(r.randf_range(-12, 12), r.randf_range(-12, 12), r.randf_range(-12, 12))
		shards.append([sh, global_transform.basis.inverse() * v, w])
	# лут сразу вылетает на пол (без окна — промпт 14.11 16:43), подбирается, когда подойдёшь
	if game and game.net:
		game.net.jar_broken(self, dir)
	if game and (game.net == null or game.net.is_host()):
		var pos := global_position + Vector3(0, 0.15, 0)
		for it in _roll(r):
			game.spawn_loot(it[0], it[1], pos, Vector3(0, 2.2, 0) + flat * 0.8, 1.0)


func _hide_body() -> void:
	for c in get_children():
		if c is MeshInstance3D:
			c.visible = false
		if c is CollisionShape3D:
			c.set_deferred("disabled", true)


## Лут кувшина (промпт 18.11 01:08): всего 1–3 предмета, все разные и по одной штуке
## (монеты — тоже один из предметов, кучкой 3–6). В больших кувшинах чаще 3, в маленьких — 1.
func _roll(r: RandomNumberGenerator) -> Array:
	var out: Array = []
	var pool: Array = []
	for row in Chest.LOOT:
		if row[0] != "coin":
			pool.append(row)
	pool.append(["twine", 6])   # бечёвка (промпт 14.11 19:22)
	pool.append(["coin", 14])
	var big := clampf(inverse_lerp(0.65, 1.6, size), 0.0, 1.0)
	var count := 1
	for k in 2:
		if r.randf() < lerpf(0.25, 0.65, big):
			count += 1
	for k in count:
		var total := 0
		for row in pool:
			total += int(row[1])
		if total <= 0:
			break
		var pick := r.randi_range(0, total - 1)
		for i in pool.size():
			pick -= int(pool[i][1])
			if pick < 0:
				var pid := String(pool[i][0])
				out.append([pid, r.randi_range(3, 6) if pid == "coin" else 1])
				pool.remove_at(i)
				break
	return out


## Загруженный из сейва разбитый кувшин: осколки просто лежат вокруг.
func _scatter_static(r: RandomNumberGenerator) -> void:
	var glass := kind in ["flask", "cone"]
	for k in int(6 + 5 * size):
		var sh := _shard_mesh(r, glass)
		var off := Vector2.from_angle(r.randf() * TAU) * r.randf_range(0.05, 0.7)
		sh.position = Vector3(off.x, 0.0, off.y)
		add_child(sh)
		_lay_flat(sh, r.randf_range(-0.04, 0.04))


func _process(delta: float) -> void:
	if shards.is_empty():
		return
	for i in range(shards.size() - 1, -1, -1):
		var s: Array = shards[i]
		var n: MeshInstance3D = s[0]
		var v: Vector3 = s[1]
		v.y -= 9.8 * delta
		n.position += v * delta
		n.rotation += (s[2] as Vector3) * delta
		if n.position.y <= _ground_y(n.position) + 0.02:
			# упал: лежит плашмя
			_lay_flat(n, randf_range(-0.04, 0.04))
			shards.remove_at(i)
		else:
			s[1] = v


func _play(stream: AudioStreamWAV, db: float) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = db
	p.unit_size = 4.0
	p.pitch_scale = randf_range(0.85, 1.15) / sqrt(size)
	add_child(p)
	p.position.y = 0.2
	p.finished.connect(p.queue_free)
	p.play()
