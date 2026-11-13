extends Node3D
## Заброшенное бетонное помещение: короткий общий коридор вдоль X, по две комнаты с каждой стороны.
##   север (z < 0): комнаты с центрами x = -6, 6
##   юг    (z > 0): комнаты с центрами x = -6, 6, между ними дверь

const FlickerLight := preload("res://flicker_light.gd")
const ConcreteShader := preload("res://concrete.gdshader")

const H := 3.2        # высота потолка
const T := 0.3        # толщина стен
const CW := 1.6       # половина ширины коридора
const X0 := -12.0
const X1 := 12.0
const ZN := -9.0
const ZS := 9.0
const DOOR_W := 1.7
const DOOR_H := 2.3
const WARM := Color(1.0, 0.78, 0.52)

var wall_mat: ShaderMaterial
var floor_mat: ShaderMaterial
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.seed = 7
	var big := _noise_tex(11, 0.006, 3)
	var fine := _noise_tex(23, 0.04, 4)
	wall_mat = _concrete(big, fine, Color(0.27, 0.265, 0.25))
	floor_mat = _concrete(big, fine, Color(0.22, 0.21, 0.2))
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
	_wall_x(-CW, X0, X1, [-6.0, 6.0])
	_wall_x(CW, X0, X1, [-6.0, 6.0])

	# перегородки между комнатами
	_wall_z(0.0, ZN, -CW, [])
	_wall_z(0.0, CW, ZS, [5.5])

	# балки под потолком коридора
	var x := X0 + 2.0
	while x < X1:
		_box(Vector3(x, H - 0.2, 0), Vector3(0.35, 0.4, CW * 2), wall_mat, false)
		x += 4.0

	# колонны в южных комнатах
	for px in [-8.5, 8.5]:
		_box(Vector3(px, H / 2, 5.5), Vector3(0.55, H, 0.55), wall_mat)

	_debris()
	_lights()


func _debris() -> void:
	var spots := [
		Vector3(-10, 0, -7.5), Vector3(-3, 0, -4), Vector3(2.5, 0, -7.8), Vector3(10, 0, -3.5),
		Vector3(-10.5, 0, 8), Vector3(-2.5, 0, 3.5), Vector3(3, 0, 8), Vector3(10.8, 0, 3.5),
		Vector3(11.2, 0, -0.8),
	]
	for s in spots:
		var n := rng.randi_range(1, 4)
		for i in n:
			var sz := Vector3(rng.randf_range(0.2, 0.9), rng.randf_range(0.1, 0.5), rng.randf_range(0.2, 0.9))
			var p: Vector3 = s + Vector3(rng.randf_range(-0.8, 0.8), sz.y / 2, rng.randf_range(-0.8, 0.8))
			var b := _box(p, sz, wall_mat)
			b.rotation.y = rng.randf_range(0, TAU)
	var slab := _box(Vector3(-5.5, 0.6, -8.3), Vector3(2.4, 0.2, 1.4), wall_mat)
	slab.rotation.x = 1.1
	var slab2 := _box(Vector3(7.5, 0.5, 8.2), Vector3(2.0, 0.2, 1.2), wall_mat)
	slab2.rotation.x = -1.0


func _lights() -> void:
	# только тёплый свет, неяркий; часть мерцает, одна лампа мёртвая, одна комната без света
	_lamp(Vector3(-8, H, 0), 0.75, true)
	_lamp(Vector3(0, H, 0), 0.7, false)
	_lamp(Vector3(8, H, 0), 0.0, false)
	_lamp(Vector3(-6, H, -5.5), 0.8, true)
	_lamp(Vector3(6, H, -5.5), 0.65, false)
	_lamp(Vector3(6, H, 5.5), 0.8, true)


func _lamp(pos: Vector3, energy: float, flicker: bool) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.12, 0.12)
	mat.emission_enabled = energy > 0.0
	mat.emission = WARM
	mat.emission_energy_multiplier = 1.5
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
	l.light_color = WARM
	l.base_energy = energy
	l.flicker = flicker
	l.lamp_mat = mat
	l.omni_range = 8.5
	l.omni_attenuation = 1.0
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


func _noise_tex(seed_: int, freq: float, octaves: int) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = seed_
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = freq
	noise.fractal_octaves = octaves
	noise.fractal_gain = 0.5
	var t := NoiseTexture2D.new()
	t.width = 512
	t.height = 512
	t.seamless = true
	t.generate_mipmaps = true
	t.noise = noise
	return t


func _concrete(big: Texture2D, fine: Texture2D, base: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ConcreteShader
	m.set_shader_parameter("noise_big", big)
	m.set_shader_parameter("noise_fine", fine)
	m.set_shader_parameter("base_color", base)
	m.set_shader_parameter("ceiling_h", H)
	return m
