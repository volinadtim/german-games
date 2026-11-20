extends Node3D
## Третья локация — лагерь у озера (промпт 20.11 18:00). Стоит далеко к северу от деревни (z ~1170..1270),
## строится, только когда туда приехали (village.gd: lake_sequence / сейв). Ровная поляна в лесу:
## круглое озеро с песчаным берегом, костёр с огнём и брёвнами, палатки, лодка, ели по краям.
## Высота земли для машины — village_build.gd: height (за LAKE_Z0 — ровно G).

const G := 4.0
const X0 := -9.0
const X1 := 71.0
const Z0 := 1170.0
const Z1 := 1270.0
## Где встаёт машина после поездки (носом к озеру)
const CAR_POS := Vector3(31.0, G, 1182.0)
const CAR_YAW := 0.0
const LAKE_C := Vector3(31.0, G, 1240.0)
const LAKE_R := 15.0
const FIRE := Vector3(20.0, G, 1210.0)
const LakeDive := preload("res://scripts/village/lake_dive.gd")
const LakeShop := preload("res://scripts/village/lake_shop.gd")
## Trinkets Market #3 (тир 2, промпт 20.11 18:33) — у тропинки, витриной к костру
const SHOP_POS := Vector3(44.0, G, 1198.0)

var rng := RandomNumberGenerator.new()
var fire_light: OmniLight3D
var fire_t := 0.0


func _ready() -> void:
	name = "LakeCamp"
	rng.seed = 1800
	_ground()
	_lake()
	_bounds()
	_campfire()
	for t in [[Vector3(13.0, G, 1203.0), 0.5, Color(0.75, 0.38, 0.12)], [Vector3(14.5, G, 1217.0), 2.3, Color(0.25, 0.4, 0.22)],
			[Vector3(27.0, G, 1214.0), -0.4, Color(0.2, 0.32, 0.5)]]:
		_tent(t[0], t[1], t[2])
	_boat(Vector3(47.5, G, 1229.0), 0.9)
	_sign(Vector3(35.5, G, 1185.0))
	var shop := LakeShop.new()
	shop.name = "LakeShop"
	shop.position = SHOP_POS
	shop.rotation.y = -PI / 2.0
	add_child(shop)
	_trees()
	_hidden_safe()


## Воздух у озера чистый (промпт 20.11 18:31): здесь можно ходить без противогаза.
static func clean_air(p: Vector3) -> bool:
	return p.z > Z0 - 25.0


## Собирательство (промпт 20.11 18:31): [id, мин, макс, вес]. Хост раскладывает находки при приезде,
## потом каждые FORAGE_T с подкладывает новые (подальше от игрока), пока на земле меньше FORAGE_MAX.
const FORAGE := [["wood", 2, 3, 30], ["stone", 1, 3, 22], ["twine", 1, 2, 12], ["water", 1, 1, 8], ["rot_apple", 1, 2, 8],
	["canned", 1, 1, 4], ["bandage", 1, 1, 5], ["scrap", 1, 2, 9], ["nut", 2, 4, 7], ["tape", 1, 1, 4], ["ammo", 2, 5, 5],
	["filter", 1, 1, 2], ["pills", 1, 1, 3], ["glass", 1, 1, 4], ["coin", 2, 6, 8]]
const FORAGE_MAX := 18
const FORAGE_T := 25.0
var forage: Array = []
var forage_t := 2.0
var forage_first := true


## Хост: разложить / подложить находки по лагерю.
func _forage_tick(delta: float) -> void:
	var g = get_parent().get("game")
	if g == null or g.player == null or (g.net and not g.net.is_host()):
		return
	forage_t -= delta
	if forage_t > 0.0:
		return
	forage_t = FORAGE_T
	forage = forage.filter(func(p): return is_instance_valid(p))
	var n := 14 if forage_first else mini(2, FORAGE_MAX - forage.size())
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


## Точка для находки: не в озере, не в костре, не у машины; far — не ближе 10 м к игроку.
func _forage_spot(pp: Vector3, far: bool) -> Vector3:
	for t in 12:
		var p := Vector3(randf_range(X0 + 3.0, X1 - 3.0), G + 0.4, randf_range(Z0 + 4.0, Z1 - 4.0))
		if Vector2(p.x - LAKE_C.x, p.z - LAKE_C.z).length() < LAKE_R + 2.0:
			continue
		if Vector2(p.x - FIRE.x, p.z - FIRE.z).length() < 3.0 or Vector2(p.x - CAR_POS.x, p.z - CAR_POS.z).length() < 4.0:
			continue
		if far and Vector2(p.x - pp.x, p.z - pp.z).length() < 10.0:
			continue
		return p
	return Vector3.INF


func _process(delta: float) -> void:
	_forage_tick(delta)
	fire_t += delta
	if fire_light:
		fire_light.light_energy = 2.4 + 0.5 * sin(fire_t * 11.0) + 0.35 * sin(fire_t * 23.7 + 1.3)


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


## Трава, по которой ходят, и холмы за краем лагеря.
func _ground() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(200.0, 200.0)
	_mesh(pm, _mat(Color(0.24, 0.3, 0.16)), Vector3((X0 + X1) / 2.0, G, (Z0 + Z1) / 2.0))
	_solid(Vector3((X0 + X1) / 2.0, G - 1.0, (Z0 + Z1) / 2.0), Vector3(X1 - X0 + 4.0, 2.0, Z1 - Z0 + 4.0))
	# тропинка от машины к костру
	var path := PlaneMesh.new()
	path.size = Vector2(2.2, 26.0)
	_mesh(path, _mat(Color(0.36, 0.3, 0.2)), Vector3(26.0, G + 0.01, 1196.0), Vector3(0, 0.4, 0))
	var hill_m := _mat(Color(0.14, 0.2, 0.12))
	for i in 14:
		var a := TAU * float(i) / 14.0
		var sm := SphereMesh.new()
		sm.radius = rng.randf_range(22.0, 34.0)
		sm.height = sm.radius * 0.9
		_mesh(sm, hill_m, Vector3(31.0 + cos(a) * 82.0, G - 4.0, 1220.0 + sin(a) * 92.0))


## Круглое озеро: песок, вода, невидимая стенка по кромке воды.
func _lake() -> void:
	var sand := CylinderMesh.new()
	sand.top_radius = LAKE_R + 3.5
	sand.bottom_radius = LAKE_R + 3.5
	sand.height = 0.04
	_mesh(sand, _mat(Color(0.62, 0.56, 0.4)), LAKE_C + Vector3(0, 0.01, 0))
	var water := CylinderMesh.new()
	water.top_radius = LAKE_R
	water.bottom_radius = LAKE_R
	water.height = 0.04
	water.radial_segments = 48
	var wm := _mat(Color(0.1, 0.22, 0.27), 0.05)
	wm.metallic = 0.35
	_mesh(water, wm, LAKE_C + Vector3(0, 0.04, 0))
	var body := LakeDive.new()   # [F] у воды — нырнуть с аквалангом (lake_dive.gd)
	body.center = LAKE_C
	body.position = LAKE_C + Vector3(0, 1.5, 0)
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = LAKE_R - 0.6
	cy.height = 3.0
	cs.shape = cy
	body.add_child(cs)
	add_child(body)
	# камыши по берегу
	var reed_m := _mat(Color(0.35, 0.4, 0.2))
	for i in 40:
		var a := rng.randf() * TAU
		var r := LAKE_R + rng.randf_range(-0.6, 0.4)
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.03
		cm.height = rng.randf_range(0.8, 1.5)
		_mesh(cm, reed_m, LAKE_C + Vector3(cos(a) * r, cm.height / 2.0, sin(a) * r), Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2)))


## Стены по краю лагеря — дальше лес.
func _bounds() -> void:
	var yc := G + 30.0
	_solid(Vector3(X0 - 0.5, yc, (Z0 + Z1) / 2.0), Vector3(1.0, 60.0, Z1 - Z0 + 2.0))
	_solid(Vector3(X1 + 0.5, yc, (Z0 + Z1) / 2.0), Vector3(1.0, 60.0, Z1 - Z0 + 2.0))
	_solid(Vector3((X0 + X1) / 2.0, yc, Z0 - 0.5), Vector3(X1 - X0 + 2.0, 60.0, 1.0))
	_solid(Vector3((X0 + X1) / 2.0, yc, Z1 + 0.5), Vector3(X1 - X0 + 2.0, 60.0, 1.0))


## Костёр: камни кругом, брёвна шалашом, огонь (частицы) и мерцающий свет; брёвна-скамейки вокруг.
func _campfire() -> void:
	var stone_m := _mat(Color(0.4, 0.4, 0.38))
	for i in 9:
		var a := TAU * float(i) / 9.0
		var sm := SphereMesh.new()
		sm.radius = 0.16
		sm.height = 0.22
		_mesh(sm, stone_m, FIRE + Vector3(cos(a) * 0.6, 0.08, sin(a) * 0.6))
	var wood_m := _mat(Color(0.3, 0.2, 0.12))
	for i in 4:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.05
		cm.bottom_radius = 0.06
		cm.height = 0.9
		var a := TAU * float(i) / 4.0
		var mi := _mesh(cm, wood_m, FIRE + Vector3(cos(a) * 0.18, 0.3, sin(a) * 0.18))
		mi.rotation = Vector3(0.5 * sin(a), 0, -0.5 * cos(a))
	var fl := CPUParticles3D.new()
	fl.amount = 28
	fl.lifetime = 0.8
	fl.position = FIRE + Vector3(0, 0.25, 0)
	fl.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	fl.emission_sphere_radius = 0.2
	fl.direction = Vector3.UP
	fl.spread = 12.0
	fl.gravity = Vector3(0, 1.5, 0)
	fl.initial_velocity_min = 0.4
	fl.initial_velocity_max = 0.9
	fl.scale_amount_min = 0.6
	fl.scale_amount_max = 1.1
	var q := QuadMesh.new()
	q.size = Vector2(0.35, 0.45)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.vertex_color_use_as_albedo = true
	q.material = fm
	fl.mesh = q
	var gr := Gradient.new()
	gr.set_color(0, Color(1.0, 0.75, 0.3, 0.9))
	gr.set_color(1, Color(0.8, 0.2, 0.05, 0.0))
	fl.color_ramp = gr
	add_child(fl)
	fire_light = OmniLight3D.new()
	fire_light.light_color = Color(1.0, 0.58, 0.25)
	fire_light.omni_range = 10.0
	fire_light.light_energy = 2.4
	fire_light.shadow_enabled = true
	fire_light.position = FIRE + Vector3(0, 0.9, 0)
	add_child(fire_light)
	var log_m := _mat(Color(0.36, 0.26, 0.17))
	for k in 3:
		var a := TAU * float(k) / 3.0 + 0.4
		var cm := CylinderMesh.new()
		cm.top_radius = 0.2
		cm.bottom_radius = 0.2
		cm.height = 1.8
		var p := FIRE + Vector3(cos(a) * 2.0, 0.2, sin(a) * 2.0)
		var mi := _mesh(cm, log_m, p)
		mi.rotation = Vector3(0, -a, PI / 2.0)
		mi.rotation_order = EULER_ORDER_YXZ
		_solid(p, Vector3(0.4, 0.4, 1.8), -a + PI / 2.0)


## Палатка: двускатный тент (призма) и тёмный вход.
func _tent(p: Vector3, yaw: float, c: Color) -> void:
	var pr := PrismMesh.new()
	pr.size = Vector3(2.4, 1.5, 2.8)
	var mi := _mesh(pr, _mat(c, 0.8), p + Vector3(0, 0.75, 0))
	mi.rotation.y = yaw
	var door := PrismMesh.new()
	door.size = Vector3(0.9, 0.9, 0.02)
	var d := _mesh(door, _mat(Color(0.05, 0.05, 0.05)), p + Basis(Vector3.UP, yaw) * Vector3(0, 0.45, 1.41))
	d.rotation.y = yaw
	_solid(p + Vector3(0, 0.7, 0), Vector3(2.2, 1.4, 2.8), yaw)


## Перевёрнутая лодка у воды.
func _boat(p: Vector3, yaw: float) -> void:
	var hull := CapsuleMesh.new()
	hull.radius = 0.6
	hull.height = 3.6
	var mi := _mesh(hull, _mat(Color(0.32, 0.36, 0.3)), p + Vector3(0, 0.15, 0))
	mi.rotation = Vector3(PI / 2.0, yaw, 0)
	mi.rotation_order = EULER_ORDER_YXZ
	mi.scale = Vector3(1.0, 1.0, 0.45)
	_solid(p + Vector3(0, 0.3, 0), Vector3(1.2, 0.6, 3.6), yaw)


## Табличка на столбике.
func _sign(p: Vector3) -> void:
	var post := CylinderMesh.new()
	post.top_radius = 0.06
	post.bottom_radius = 0.07
	post.height = 1.8
	_mesh(post, _mat(Color(0.3, 0.22, 0.14)), p + Vector3(0, 0.9, 0))
	var board := BoxMesh.new()
	board.size = Vector3(1.6, 0.5, 0.05)
	_mesh(board, _mat(Color(0.45, 0.34, 0.2)), p + Vector3(0, 1.6, 0), Vector3(0, PI, 0))
	var l := Label3D.new()
	l.text = "Лагерь «Озёрный»"
	l.font_size = 40
	l.pixel_size = 0.0035
	l.modulate = Color(0.95, 0.9, 0.75)
	l.outline_size = 6
	l.position = p + Vector3(0, 1.6, -0.04)
	l.rotation.y = PI
	add_child(l)


## Ели по краям лагеря и вокруг озера (не на тропе, не у костра и не у машины).
func _trees() -> void:
	var trunk_m := _mat(Color(0.28, 0.2, 0.13))
	var crown_m := _mat(Color(0.1, 0.2, 0.12))
	var n := 0
	var tries := 0
	while n < 70 and tries < 900:
		tries += 1
		var p := Vector3(rng.randf_range(X0 + 1.0, X1 - 1.0), G, rng.randf_range(Z0 + 1.0, Z1 - 1.0))
		if Vector2(p.x - LAKE_C.x, p.z - LAKE_C.z).length() < LAKE_R + 5.0:
			continue
		if p.x > 6.0 and p.x < 42.0 and p.z < 1228.0:
			continue   # лагерь, тропа и машина
		var h := rng.randf_range(5.0, 8.0)
		var tc := CylinderMesh.new()
		tc.top_radius = 0.14
		tc.bottom_radius = 0.24
		tc.height = h * 0.4
		_mesh(tc, trunk_m, p + Vector3(0, h * 0.2, 0))
		for k in 3:
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = h * (0.28 - 0.06 * k)
			cone.height = h * 0.42
			_mesh(cone, crown_m, p + Vector3(0, h * (0.38 + 0.2 * k), 0))
		var body := StaticBody3D.new()
		body.position = p + Vector3(0, 1.5, 0)
		var cs := CollisionShape3D.new()
		var cy := CylinderShape3D.new()
		cy.radius = 0.3
		cy.height = 3.0
		cs.shape = cy
		body.add_child(cs)
		add_child(body)
		n += 1


## Спрятанный сейф (промпт 20.11 18:35): в кустах у дальнего края лагеря, за озером. Вскрывается отмычкой
## из магазина (Chest.pickable), внутри — противогаз Снюхатель5088 для города.
func _hidden_safe() -> void:
	var sf := preload("res://scripts/world/chest.gd").new()
	sf.kind = "safe"
	sf.locked = true
	sf.pickable = true
	sf.random_loot = false
	sf.extra = [["snyuhatel5088", 1], ["filter2", 2]]
	sf.position = Vector3(66.5, G, 1264.5)
	sf.rotation.y = PI * 0.75
	add_child(sf)
	var gm = get_parent().get("game")
	if gm != null:
		sf.game = gm
		gm.lake_safe_restore(sf)
	var bush := SphereMesh.new()
	bush.radius = 0.9
	bush.height = 1.3
	var bm := _mat(Color(0.18, 0.3, 0.14))
	for o in [Vector3(-0.9, 0.5, -0.6), Vector3(0.8, 0.5, -0.8), Vector3(-0.2, 0.55, 1.0)]:
		_mesh(bush, bm, sf.position + o)
