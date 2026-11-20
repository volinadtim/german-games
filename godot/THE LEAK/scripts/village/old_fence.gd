extends Node3D
## Старый полугнилой деревянный забор поперёк дороги на выезде с поляны (промпт 20.11 11:59).
## Машина в кат-сцене отъезда (car.gd) проламывает середину: штакетины, жерди и средний столб
## разлетаются вперёд и ложатся на дорогу. Проломан навсегда (car.escaped в сейве): у обочин забор
## стоит, посередине — обломки, по ним можно проехать и пройти. Справа в заборе давно дыра — пешком
## пролезть можно и до отъезда. Раскладка обломков — с постоянным зерном: одинакова у всех и после загрузки.

const Z := 20.0               # где стоит (дорога идёт вдоль Z, x = ROAD_X)
const STEP := 2.2             # шаг столбов
const POSTS := 3              # столбов в каждую сторону от середины
const BREAK := 2.25           # |x - середина| < BREAK — проламывает машина
const GAP := [4.4, 6.6]       # пролёт справа (x от середины), где штакетин почти нет и жердь упала

var broken := false
var pieces: Array = []        # [узел, откуда Transform3D, куда Transform3D, высота дуги, задержка, длительность, ось кручения]
var stubs: Array[Node3D] = [] # обломок среднего столба — виден, когда проломан
var mid_cols: Array[Node] = []  # коллизия середины — убираем при проломе
var anim_t := -1.0


## Построить забор: v — village.gd (height(), материалы), cx — середина дороги.
func build(v, cx: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2011
	var rot := StandardMaterial3D.new()
	rot.albedo_color = Color(0.24, 0.23, 0.15)
	rot.roughness = 1.0
	var mats: Array = [v.wood_mat, v.wood_dark, rot, v.wood_dark]
	for k in range(-POSTS, POSTS + 1):
		var x := cx + k * STEP
		var y: float = v.height(x, Z)
		var h := rng.randf_range(1.2, 1.45)
		var post := _mesh(Vector3(0.13, h, 0.13), v.wood_dark)
		post.position = Vector3(x, y + h / 2.0 - 0.15, Z)
		post.rotation = Vector3(rng.randf_range(-0.06, 0.06), rng.randf() * 0.4, rng.randf_range(-0.07, 0.07))
		if k == 0:
			_piece(post, v, rng, 0.065)
			var stub := _mesh(Vector3(0.13, 0.34, 0.13), v.wood_dark)
			stub.position = Vector3(x, y + 0.1, Z)
			stub.rotation = Vector3(0.25, 0.3, -0.15)
			stub.visible = false
			stubs.append(stub)
		if k == POSTS:
			break
		# пролёт до следующего столба: две жерди и штакетник со стороны поляны
		var mx := x + STEP / 2.0
		var off := mx - cx
		var in_gap := off > float(GAP[0]) and off < float(GAP[1])
		var mid := absf(off) < BREAK
		for ry in [0.32, 0.92]:
			var rail := _mesh(Vector3(STEP + 0.1, 0.09, 0.05), mats[rng.randi() % 2])
			rail.position = Vector3(mx, v.height(mx, Z) + ry, Z + 0.09)
			rail.rotation.z = rng.randf_range(-0.04, 0.04)
			if in_gap and ry > 0.5:
				# верхняя жердь сгнила и одним концом упала на землю
				rail.rotation.z = -0.36
				rail.position.y -= 0.3
			if mid:
				_piece(rail, v, rng, 0.03)
		var px := x + 0.16
		while px < x + STEP - 0.1:
			var miss := 0.75 if in_gap else 0.17
			if rng.randf() >= miss:
				var ph := rng.randf_range(0.8, 1.2)
				var pk := _mesh(Vector3(0.11, ph, 0.025), mats[rng.randi() % mats.size()])
				pk.position = Vector3(px, v.height(px, Z) + 0.06 + ph / 2.0, Z + 0.135)
				pk.rotation = Vector3(rng.randf_range(-0.08, 0.05), 0.0, rng.randf_range(-0.13, 0.13))
				if mid:
					_piece(pk, v, rng, 0.02)
			px += rng.randf_range(0.17, 0.22)
		# невидимый щит пролёта (в дыре — нет)
		if not in_gap:
			var col := _col(Vector3(STEP, 1.4, 0.3), Vector3(mx, v.height(mx, Z) + 0.6, Z + 0.08))
			if mid:
				mid_cols.append(col)


func _mesh(size: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	add_child(mi)
	return mi


func _col(size: Vector3, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	add_child(body)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	return body


## Кусок, который машина сносит: куда он ляжет (плашмя на землю впереди забора) — сразу по зерну.
func _piece(n: Node3D, v, rng: RandomNumberGenerator, lie: float) -> void:
	var p := n.position
	var tx := p.x + rng.randf_range(-1.6, 1.6)
	var tz := Z + rng.randf_range(0.8, 7.5)
	var to := Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, PI / 2.0), Vector3(tx, float(v.height(tx, tz)) + lie + 0.04, tz))
	var axis := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 0.3), rng.randf_range(-1, 1)).normalized()
	pieces.append([n, n.transform, to, rng.randf_range(0.5, 1.6), rng.randf_range(0.0, 0.1),
		rng.randf_range(0.55, 1.0), axis])


## Машина врезалась (кат-сцена): обломки разлетаются.
func smash() -> void:
	if broken:
		return
	broken = true
	_drop_cols()
	anim_t = 0.0


## Проломан давно (машина уже уехала: после кат-сцены, загрузка) — обломки сразу лежат.
func set_broken() -> void:
	broken = true
	anim_t = -1.0
	_drop_cols()
	for pc in pieces:
		(pc[0] as Node3D).transform = pc[2]


func _drop_cols() -> void:
	for c in mid_cols:
		if is_instance_valid(c):
			c.queue_free()
	mid_cols.clear()
	for s in stubs:
		s.visible = true


func _process(delta: float) -> void:
	if anim_t < 0.0:
		return
	anim_t += delta
	var done := true
	for pc in pieces:
		var n: Node3D = pc[0]
		var k := clampf((anim_t - float(pc[4])) / float(pc[5]), 0.0, 1.0)
		if k < 1.0:
			done = false
		var a: Transform3D = pc[1]
		var b: Transform3D = pc[2]
		# вперёд — сразу быстро (толкнула машина), вверх — дугой, в полёте кувыркается
		var e := 1.0 - (1.0 - k) * (1.0 - k)
		var pos := a.origin.lerp(b.origin, e) + Vector3(0, float(pc[3]) * 4.0 * k * (1.0 - k), 0)
		var q := a.basis.get_rotation_quaternion().slerp(b.basis.get_rotation_quaternion(), e)
		var spin := Basis(pc[6] as Vector3, sin(k * PI) * 5.0)
		n.transform = Transform3D(spin * Basis(q), pos)
	if done:
		anim_t = -1.0
