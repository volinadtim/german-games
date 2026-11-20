extends Node3D
## Четвёртая локация — город (промпт 20.11 18:35): самая загрязнённая. Стоит далеко к северу от лагеря у озера
## (z ~1400..1540), строится, только когда туда приехали (village.gd: city_sequence / сейв).
## Проспект от машины на север, две поперечные улицы, кварталы коробок-домов, разбитые машины, фонари,
## жёлто-зелёный смог. Дышать можно только в противогазе MASK (gasmask.gd: city).
## Высота земли для машины — village_build.gd: height (за LAKE_Z0 — ровно G).

const G := 4.0
const X0 := -20.0
const X1 := 100.0
const Z0 := 1400.0
const Z1 := 1540.0
## Противогаз, в котором в городе можно дышать (предмет делает другой агент — сверяемся по id)
const MASK := "gasmask3"
const MASK_NAME := "Снюхатель5088"
## Где встаёт машина после поездки (носом на север, в проспект)
const CAR_POS := Vector3(40.0, G, 1406.0)
const CAR_YAW := 0.0
## Что положить в багажник в лагере для поездки (плюс полный бак и Снюхатель у водителя)
const NEED := {"filter": 6, "fuel": 2}
## Улицы [x0, x1, z0, z1]: по ним находки и мутанты, дома — между ними
const STREETS := [[34.0, 46.0, 1400.0, Z1], [X0, X1, 1455.0, 1465.0], [X0, X1, 1500.0, 1510.0], [X0, X1, 1400.0, 1413.0]]
## Мутанты города: [позиция, вид] — умные (mutant.gd: smart)
const MUT := [[Vector3(38.0, G, 1440.0), "stalker"], [Vector3(44.0, G, 1472.0), "charger"], [Vector3(5.0, G, 1460.0), "spitter"],
	[Vector3(75.0, G, 1458.0), "stalker"], [Vector3(-12.0, G, 1505.0), "charger"], [Vector3(90.0, G, 1503.0), "spitter"],
	[Vector3(40.0, G, 1525.0), "stalker"], [Vector3(60.0, G, 1505.0), "spitter"], [Vector3(20.0, G, 1462.0), "charger"],
	[Vector3(42.0, G, 1535.0), "spitter"]]

var rng := RandomNumberGenerator.new()


func _ready() -> void:
	name = "City"
	rng.seed = 1835
	_ground()
	_bounds()
	_blocks()
	_wrecks()
	_lamps()
	_sign(Vector3(32.0, G, 1411.0))
	_skyline()
	_smog()


## Точка в городе (тут воздух хуже всего).
static func in_city(p: Vector3) -> bool:
	return p.z > Z0 - 30.0


## Собирательство в развалинах: [id, мин, макс, вес]. Хост раскладывает при приезде, потом подкладывает.
const FORAGE := [["scrap", 1, 3, 30], ["glass", 1, 2, 14], ["nut", 2, 4, 12], ["tape", 1, 1, 8], ["ammo", 2, 6, 9],
	["canned", 1, 1, 6], ["pills", 1, 1, 5], ["bandage", 1, 1, 5], ["filter", 1, 1, 5], ["filter2", 1, 1, 2],
	["coin", 3, 8, 10], ["fuel", 1, 1, 3]]
const FORAGE_MAX := 20
const FORAGE_T := 25.0
var forage: Array = []
var forage_t := 2.0
var forage_first := true


## Хост: разложить / подложить находки по улицам.
func _forage_tick(delta: float) -> void:
	var g = get_parent().get("game")
	if g == null or g.player == null or (g.net and not g.net.is_host()):
		return
	forage_t -= delta
	if forage_t > 0.0:
		return
	forage_t = FORAGE_T
	forage = forage.filter(func(p): return is_instance_valid(p))
	var n := 16 if forage_first else mini(2, FORAGE_MAX - forage.size())
	var pp: Vector3 = g.player.global_position
	for i in n:
		var at := _forage_spot(pp, not forage_first)
		if at == Vector3.INF:
			continue
		var e: Array = _forage_pick()
		var p = g._make_pickup(String(e[0]), randi_range(int(e[1]), int(e[2])), at, Vector3.ZERO)
		p.angular_velocity = Vector3.ZERO
		p.life = 1.0e9
		forage.append(p)
	forage_first = false


## Случайная находка по весам FORAGE.
func _forage_pick() -> Array:
	var sum := 0
	for e in FORAGE:
		sum += int(e[3])
	var r := randi() % sum
	for e in FORAGE:
		r -= int(e[3])
		if r < 0:
			return e
	return FORAGE[0]


## Точка для находки на улице: не у машины; far — не ближе 10 м к игроку.
func _forage_spot(pp: Vector3, far: bool) -> Vector3:
	for t in 12:
		var s: Array = STREETS[randi() % STREETS.size()]
		var p := Vector3(randf_range(float(s[0]) + 2.0, float(s[1]) - 2.0), G + 0.4, randf_range(float(s[2]) + 2.0, float(s[3]) - 2.0))
		if Vector2(p.x - CAR_POS.x, p.z - CAR_POS.z).length() < 5.0:
			continue
		if far and Vector2(p.x - pp.x, p.z - pp.z).length() < 10.0:
			continue
		return p
	return Vector3.INF


func _process(delta: float) -> void:
	_forage_tick(delta)


## Материал однотонный.
func _mat(c: Color, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


## Меш в точке (без столкновений).
func _mesh(m: Mesh, mat: Material, p: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = p
	mi.rotation = rot
	add_child(mi)
	return mi


## Невидимое препятствие-коробка (center, size, поворот по Y).
func _solid(center: Vector3, size: Vector3, yaw := 0.0) -> void:
	var body := StaticBody3D.new()
	body.position = center
	body.rotation.y = yaw
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	add_child(body)


## Коробка с видом и столкновением.
func _box(center: Vector3, size: Vector3, mat: Material, yaw := 0.0) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	_mesh(bm, mat, center, Vector3(0, yaw, 0))
	_solid(center, size, yaw)


## Асфальт, тротуары и разметка проспекта.
func _ground() -> void:
	var cx := (X0 + X1) / 2.0
	var cz := (Z0 + Z1) / 2.0
	var pm := PlaneMesh.new()
	pm.size = Vector2(X1 - X0 + 120.0, Z1 - Z0 + 120.0)
	_mesh(pm, _mat(Color(0.2, 0.2, 0.19)), Vector3(cx, G, cz))
	_solid(Vector3(cx, G - 1.0, cz), Vector3(X1 - X0 + 4.0, 2.0, Z1 - Z0 + 4.0))
	var line_m := _mat(Color(0.6, 0.55, 0.3))
	var z := Z0 + 4.0
	while z < Z1:
		var lm := PlaneMesh.new()
		lm.size = Vector2(0.25, 3.0)
		_mesh(lm, line_m, Vector3(40.0, G + 0.01, z))
		z += 7.0


## Стены по краю города — дальше завалы.
func _bounds() -> void:
	var yc := G + 30.0
	_solid(Vector3(X0 - 0.5, yc, (Z0 + Z1) / 2.0), Vector3(1.0, 60.0, Z1 - Z0 + 2.0))
	_solid(Vector3(X1 + 0.5, yc, (Z0 + Z1) / 2.0), Vector3(1.0, 60.0, Z1 - Z0 + 2.0))
	_solid(Vector3((X0 + X1) / 2.0, yc, Z0 - 0.5), Vector3(X1 - X0 + 2.0, 60.0, 1.0))
	_solid(Vector3((X0 + X1) / 2.0, yc, Z1 + 0.5), Vector3(X1 - X0 + 2.0, 60.0, 1.0))
	# завалы по краям — видно, что дальше не пройти
	var rub_m := _mat(Color(0.33, 0.31, 0.28))
	for i in 40:
		var side := i % 4
		var p: Vector3
		if side == 0:
			p = Vector3(X0 + 0.5, G, rng.randf_range(Z0, Z1))
		elif side == 1:
			p = Vector3(X1 - 0.5, G, rng.randf_range(Z0, Z1))
		elif side == 2:
			p = Vector3(rng.randf_range(X0, X1), G, Z0 + 0.5)
		else:
			p = Vector3(rng.randf_range(X0, X1), G, Z1 - 0.5)
		var bm := BoxMesh.new()
		bm.size = Vector3(rng.randf_range(1.5, 4.0), rng.randf_range(0.8, 2.5), rng.randf_range(1.5, 4.0))
		_mesh(bm, rub_m, p + Vector3(0, bm.size.y * 0.4, 0), Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3)))


## Кварталы между улицами: в каждом — несколько домов-коробок с полосами окон, часть — развалины.
func _blocks() -> void:
	var xs := [[X0 + 1.0, 33.0], [47.0, X1 - 1.0]]
	var zs := [[1414.0, 1454.0], [1466.0, 1499.0], [1511.0, Z1 - 1.0]]
	var wall_ms := [_mat(Color(0.42, 0.4, 0.36)), _mat(Color(0.5, 0.44, 0.38)), _mat(Color(0.36, 0.38, 0.37)), _mat(Color(0.46, 0.36, 0.3))]
	var win_m := _mat(Color(0.06, 0.07, 0.06), 0.3)
	for bx in xs:
		for bz in zs:
			# участки по 2 в ширину и 1–2 в глубину, между ними проходы 4 м
			var nz := 2 if float(bz[1]) - float(bz[0]) > 34.0 else 1
			for ix in 2:
				for iz in nz:
					var lx0: float = lerpf(float(bx[0]), float(bx[1]), float(ix) / 2.0) + 2.0
					var lx1: float = lerpf(float(bx[0]), float(bx[1]), float(ix + 1) / 2.0) - 2.0
					var lz0: float = lerpf(float(bz[0]), float(bz[1]), float(iz) / nz) + 2.0
					var lz1: float = lerpf(float(bz[0]), float(bz[1]), float(iz + 1) / nz) - 2.0
					if rng.randf() < 0.15:
						continue   # пустырь
					var c := Vector3((lx0 + lx1) / 2.0, G, (lz0 + lz1) / 2.0)
					var size := Vector3(lx1 - lx0, 0.0, lz1 - lz0)
					var wm: Material = wall_ms[rng.randi() % wall_ms.size()]
					if rng.randf() < 0.25:
						_ruin(c, size, wm)
						continue
					var floors := rng.randi_range(2, 8)
					size.y = floors * 3.0
					_box(c + Vector3(0, size.y / 2.0, 0), size, wm)
					for f in floors:
						var band := BoxMesh.new()
						band.size = Vector3(size.x + 0.04, 1.1, size.z + 0.04)
						_mesh(band, win_m, c + Vector3(0, f * 3.0 + 1.7, 0))


## Развалины дома: обломки стен и кучи бетона.
func _ruin(c: Vector3, size: Vector3, wm: Material) -> void:
	var h := rng.randf_range(2.5, 5.0)
	_box(c + Vector3(-size.x / 2.0 + 0.3, h / 2.0, 0), Vector3(0.6, h, size.z), wm)
	_box(c + Vector3(0, h * 0.35, size.z / 2.0 - 0.3), Vector3(size.x, h * 0.7, 0.6), wm)
	var rub_m := _mat(Color(0.35, 0.33, 0.3))
	for i in 6:
		var bm := BoxMesh.new()
		bm.size = Vector3(rng.randf_range(1.0, 3.0), rng.randf_range(0.5, 1.6), rng.randf_range(1.0, 3.0))
		var p := c + Vector3(rng.randf_range(-size.x, size.x) * 0.3, bm.size.y * 0.4, rng.randf_range(-size.z, size.z) * 0.3)
		_mesh(bm, rub_m, p, Vector3(rng.randf_range(-0.25, 0.25), rng.randf() * TAU, rng.randf_range(-0.25, 0.25)))
		_solid(p, bm.size * 0.8)


## Брошенные ржавые машины на улицах.
func _wrecks() -> void:
	var ms := [_mat(Color(0.4, 0.22, 0.12)), _mat(Color(0.25, 0.28, 0.3)), _mat(Color(0.35, 0.33, 0.2))]
	var spots := [[Vector3(36.5, G, 1430.0), 0.1], [Vector3(44.0, G, 1452.0), 3.0], [Vector3(12.0, G, 1458.0), 1.6], [Vector3(70.0, G, 1462.0), 1.4],
		[Vector3(37.0, G, 1488.0), -0.2], [Vector3(-5.0, G, 1503.0), 1.7], [Vector3(84.0, G, 1507.0), 1.5], [Vector3(43.5, G, 1520.0), 2.9]]
	for s in spots:
		var p: Vector3 = s[0]
		var yaw: float = s[1]
		var m: Material = ms[rng.randi() % ms.size()]
		_box(p + Vector3(0, 0.55, 0), Vector3(1.8, 0.8, 4.2), m, yaw)
		var cab := BoxMesh.new()
		cab.size = Vector3(1.6, 0.6, 2.0)
		_mesh(cab, m, p + Vector3(0, 1.25, 0), Vector3(0, yaw, 0))


## Погнутые фонари вдоль проспекта.
func _lamps() -> void:
	var pole_m := _mat(Color(0.18, 0.18, 0.18), 0.6)
	var z := Z0 + 18.0
	while z < Z1 - 5.0:
		for x in [33.6, 46.4]:
			var pc := CylinderMesh.new()
			pc.top_radius = 0.07
			pc.bottom_radius = 0.1
			pc.height = 6.0
			_mesh(pc, pole_m, Vector3(x, G + 3.0, z), Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12)))
		z += 22.0


## Табличка на въезде.
func _sign(p: Vector3) -> void:
	var post := CylinderMesh.new()
	post.top_radius = 0.06
	post.bottom_radius = 0.07
	post.height = 1.8
	_mesh(post, _mat(Color(0.3, 0.3, 0.3)), p + Vector3(0, 0.9, 0))
	var board := BoxMesh.new()
	board.size = Vector3(2.0, 0.6, 0.05)
	_mesh(board, _mat(Color(0.75, 0.65, 0.15)), p + Vector3(0, 1.6, 0), Vector3(0, PI, 0))
	var l := Label3D.new()
	l.text = "ГОРОД · ЗОНА Ч\nтолько в " + MASK_NAME
	l.font_size = 36
	l.pixel_size = 0.0035
	l.modulate = Color(0.1, 0.08, 0.05)
	l.outline_size = 0
	l.position = p + Vector3(0, 1.6, -0.04)
	l.rotation.y = PI
	add_child(l)


## Силуэты высоток за краем города.
func _skyline() -> void:
	var m := _mat(Color(0.24, 0.26, 0.22))
	for i in 26:
		var a := TAU * float(i) / 26.0
		var bm := BoxMesh.new()
		bm.size = Vector3(rng.randf_range(10.0, 22.0), rng.randf_range(20.0, 55.0), rng.randf_range(10.0, 22.0))
		var p := Vector3(40.0 + cos(a) * 110.0, G + bm.size.y / 2.0 - 1.0, 1470.0 + sin(a) * 120.0)
		_mesh(bm, m, p, Vector3(0, rng.randf() * TAU, 0))


## Жёлто-зелёный смог: полупрозрачные слои над улицами.
func _smog() -> void:
	for k in 4:
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.6, 0.7, 0.2, 0.09)
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.cull_mode = BaseMaterial3D.CULL_DISABLED
		var pm := PlaneMesh.new()
		pm.size = Vector2(X1 - X0 + 200.0, Z1 - Z0 + 200.0)
		var mi := _mesh(pm, sm, Vector3((X0 + X1) / 2.0, G + 0.6 + k * 1.6, (Z0 + Z1) / 2.0))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
