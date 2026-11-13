extends Node3D
## Заброшенное бетонное помещение: общий коридор вдоль X, комнаты по обе стороны.
##   север (z < 0): три комнаты с центрами x = -12, 0, 12
##   юг    (z > 0): две комнаты с центрами x = -9, 9, между ними дверь

const FlickerLight := preload("res://flicker_light.gd")

const H := 3.2        # высота потолка
const T := 0.3        # толщина стен
const CW := 1.6       # половина ширины коридора
const X0 := -18.0
const X1 := 18.0
const ZN := -10.0
const ZS := 10.0
const DOOR_W := 1.7
const DOOR_H := 2.3

var wall_mat: StandardMaterial3D
var floor_mat: StandardMaterial3D
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.seed = 7
	wall_mat = _make_concrete(Color(0.56, 0.56, 0.54), 11, 0.35)
	floor_mat = _make_concrete(Color(0.40, 0.39, 0.37), 23, 0.5)
	_build()


func _build() -> void:
	var w := X1 - X0 + T
	var d := ZS - ZN + T
	_box(Vector3(0, -0.15, 0), Vector3(w, 0.3, d), floor_mat)
	_box(Vector3(0, H + 0.15, 0), Vector3(w, 0.3, d), wall_mat)

	# внешние стены
	_wall_x(ZN, X0 - T / 2, X1 + T / 2, [])
	_wall_x(ZS, X0 - T / 2, X1 + T / 2, [])
	_wall_z(X0, ZN, ZS, [])
	_wall_z(X1, ZN, ZS, [])

	# стены коридора с проёмами
	_wall_x(-CW, X0, X1, [-12.0, 0.0, 12.0])
	_wall_x(CW, X0, X1, [-9.0, 9.0])

	# перегородки между комнатами
	_wall_z(-6.0, ZN, -CW, [])
	_wall_z(6.0, ZN, -CW, [])
	_wall_z(0.0, CW, ZS, [6.5])

	# балки под потолком коридора
	var x := X0 + 2.0
	while x < X1:
		_box(Vector3(x, H - 0.2, 0), Vector3(0.35, 0.4, CW * 2), wall_mat, false)
		x += 4.0

	# колонны в южных комнатах
	for px in [-13.0, -5.0, 5.0, 13.0]:
		_box(Vector3(px, H / 2, 5.8), Vector3(0.55, H, 0.55), wall_mat)

	_debris()
	_lights()


func _debris() -> void:
	# обломки и старые бетонные блоки
	var spots := [
		Vector3(-15, 0, -8), Vector3(-9, 0, -3.5), Vector3(-2.5, 0, -8.5), Vector3(3, 0, -4),
		Vector3(15, 0, -7), Vector3(10, 0, -3), Vector3(-15, 0, 8.5), Vector3(-3, 0, 3.5),
		Vector3(3, 0, 8.5), Vector3(15.5, 0, 4), Vector3(-17, 0, 1), Vector3(16.8, 0, -0.8),
	]
	for s in spots:
		var n := rng.randi_range(1, 4)
		for i in n:
			var sz := Vector3(rng.randf_range(0.2, 0.9), rng.randf_range(0.1, 0.5), rng.randf_range(0.2, 0.9))
			var p: Vector3 = s + Vector3(rng.randf_range(-0.8, 0.8), sz.y / 2, rng.randf_range(-0.8, 0.8))
			var b := _box(p, sz, wall_mat)
			b.rotation.y = rng.randf_range(0, TAU)
	# пара упавших плит у стен
	var slab := _box(Vector3(-0.5, 0.6, -9.3), Vector3(2.4, 0.2, 1.4), wall_mat)
	slab.rotation.x = 1.1
	var slab2 := _box(Vector3(11, 0.5, 9.2), Vector3(2.0, 0.2, 1.2), wall_mat)
	slab2.rotation.x = -1.0


func _lights() -> void:
	var warm := Color(1.0, 0.85, 0.65)
	var cold := Color(0.75, 0.88, 1.0)
	# коридор: редкие лампы, часть мерцает, одна мёртвая
	_lamp(Vector3(-15, H, 0), warm, 1.6, true)
	_lamp(Vector3(-7, H, 0), cold, 1.2, false)
	_lamp(Vector3(1, H, 0), warm, 0.0, false)  # не горит
	_lamp(Vector3(9, H, 0), warm, 1.6, true)
	_lamp(Vector3(16, H, 0), cold, 1.0, true)
	# комнаты: не во всех есть свет
	_lamp(Vector3(-12, H, -6), cold, 1.8, true)
	_lamp(Vector3(12, H, -6), warm, 1.5, false)
	_lamp(Vector3(-9, H, 6), warm, 1.4, true)
	_lamp(Vector3(9, H, 6.5), cold, 1.7, true)


func _lamp(pos: Vector3, color: Color, energy: float, flicker: bool) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.15, 0.15)
	mat.emission_enabled = energy > 0.0
	mat.emission = color
	mat.emission_energy_multiplier = 3.0
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.0, 0.08, 0.18)
	bm.material = mat
	mi.mesh = bm
	mi.position = pos - Vector3(0, 0.05, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	if energy <= 0.0:
		return
	var l: OmniLight3D = FlickerLight.new()
	l.light_color = color
	l.base_energy = energy
	l.flicker = flicker
	l.lamp_mat = mat
	l.omni_range = 8.0
	l.omni_attenuation = 1.4
	l.shadow_enabled = true
	l.position = pos - Vector3(0, 0.3, 0)
	add_child(l)


func _wall_x(z: float, xa: float, xb: float, doors: Array) -> void:
	var cur := xa
	for dx in doors:
		_seg(Vector3((cur + dx - DOOR_W / 2) / 2, H / 2, z), Vector3(dx - DOOR_W / 2 - cur, H, T))
		_box(Vector3(dx, (DOOR_H + H) / 2, z), Vector3(DOOR_W, H - DOOR_H, T), wall_mat)
		cur = dx + DOOR_W / 2
	_seg(Vector3((cur + xb) / 2, H / 2, z), Vector3(xb - cur, H, T))


func _wall_z(x: float, za: float, zb: float, doors: Array) -> void:
	var cur := za
	for dz in doors:
		_seg(Vector3(x, H / 2, (cur + dz - DOOR_W / 2) / 2), Vector3(T, H, dz - DOOR_W / 2 - cur))
		_box(Vector3(x, (DOOR_H + H) / 2, dz), Vector3(T, H - DOOR_H, DOOR_W), wall_mat)
		cur = dz + DOOR_W / 2
	_seg(Vector3(x, H / 2, (cur + zb) / 2), Vector3(T, H, zb - cur))


func _seg(pos: Vector3, size: Vector3) -> void:
	if size.x > 0.01 and size.z > 0.01:
		_box(pos, size, wall_mat)


func _box(pos: Vector3, size: Vector3, mat: Material, collide := true) -> Node3D:
	var root: Node3D = StaticBody3D.new() if collide else Node3D.new()
	root.position = pos
	add_child(root)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	root.add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		root.add_child(cs)
	return root


func _make_concrete(tint: Color, seed_: int, scale: float) -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.seed = seed_
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.025
	noise.fractal_octaves = 6
	noise.fractal_gain = 0.55

	var ramp := Gradient.new()
	ramp.set_color(0, tint.darkened(0.45))
	ramp.set_color(1, tint.lightened(0.12))
	ramp.add_point(0.55, tint)

	var alb := NoiseTexture2D.new()
	alb.width = 512
	alb.height = 512
	alb.seamless = true
	alb.noise = noise
	alb.color_ramp = ramp

	var nrm := NoiseTexture2D.new()
	nrm.width = 512
	nrm.height = 512
	nrm.seamless = true
	nrm.noise = noise
	nrm.as_normal_map = true
	nrm.bump_strength = 6.0

	var m := StandardMaterial3D.new()
	m.albedo_texture = alb
	m.normal_enabled = true
	m.normal_texture = nrm
	m.roughness = 0.95
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(scale, scale, scale)
	return m
