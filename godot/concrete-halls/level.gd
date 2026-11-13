@tool
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
var ceil_mat: ShaderMaterial
var wire_mat: StandardMaterial3D
var rng := RandomNumberGenerator.new()
var noise_extra: Array = []

## Кнопка в инспекторе (выдели узел Level): сохраняет сгенерированную локацию в обычную сцену
## res://level_baked.tscn — с настоящими узлами, мешами и материалами, которые можно двигать и править руками.
@export_tool_button("Запечь в level_baked.tscn", "PackedScene") var bake_action = _bake


func _ready() -> void:
	rng.seed = 7
	var big := _noise_tex(11, 0.006, 3)
	var fine := _noise_tex(23, 0.04, 4)
	var cell := _noise_tex(37, 0.05, 2, FastNoiseLite.TYPE_CELLULAR)
	var crack := _noise_tex(41, 0.008, 4)
	noise_extra = [cell, crack]
	wall_mat = _concrete(big, fine, Color(0.2, 0.195, 0.185))
	floor_mat = _concrete(big, fine, Color(0.17, 0.163, 0.155), true)
	ceil_mat = _concrete(big, fine, Color(0.1, 0.097, 0.093), true)
	wire_mat = StandardMaterial3D.new()
	wire_mat.albedo_color = Color(0.05, 0.05, 0.05)
	wire_mat.roughness = 0.5
	_build()
	var we := WorldEnvironment.new()
	we.environment = _make_env()
	add_child(we)


func _build() -> void:
	var w := X1 - X0 + T
	var d := ZS - ZN + T
	_box(Vector3(0, -0.15, 0), Vector3(w, 0.3, d), floor_mat)
	_box(Vector3(0, H + 0.15, 0), Vector3(w, 0.3, d), ceil_mat)

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
	var x := X0 + 4.0
	while x < X1 - 0.1:
		_box(Vector3(x, H - 0.2, 0), Vector3(0.35, 0.4, CW * 2), wall_mat, false)
		x += 4.0

	# колонны в южных комнатах
	for px in [-8.5, 8.5]:
		_box(Vector3(px, H / 2, 5.5), Vector3(0.55, H, 0.55), wall_mat)

	_debris()
	_lights()
	_cracks()
	_dust_motes()
	_low_dust()


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
	# только тёплый свет; в коридоре две лампы на равном расстоянии от торцевых стен:
	# левая поломана, висит на проводах и мерцает, правая работает штатно. Одна комната без света.
	var rn := (ZN + -CW) / 2.0
	var rs := (CW + ZS) / 2.0
	_broken_lamp(Vector3(-6, H, 0), 0.8)
	_lamp(Vector3(6, H, 0), 0.75, false)
	_lamp(Vector3(-6, H, rn), 0.75, false)
	_lamp(Vector3(6, H, rn), 0.7, false)
	_lamp(Vector3(6, H, rs), 0.75, false)


func _broken_lamp(pos: Vector3, energy: float) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.12, 0.12)
	mat.emission_enabled = true
	mat.emission = WARM
	mat.emission_energy_multiplier = 1.5
	var tilt := 0.6
	var attach := pos + Vector3(-0.5, -0.05, 0)       # этот край ещё держится за потолок
	var along := Vector3(cos(tilt), -sin(tilt), 0)
	var center := attach + along * 0.5
	var tip := attach + along * 1.0                     # этот край оторвался и висит
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.0, 0.08, 0.18)
	bm.material = mat
	mi.mesh = bm
	mi.position = center
	mi.rotation.z = -tilt
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# провода от оторванного края в потолок, с провисом
	for side in [-0.05, 0.05]:
		var a := tip + Vector3(0, 0.03, side)
		var b := Vector3(tip.x - 0.12 + side, H, side * 2.0)
		var m := (a + b) / 2.0 + Vector3(0.09, -0.06, side * 0.6)
		_wire(a, m)
		_wire(m, b)
	_wire(attach + Vector3(0.05, 0, 0.06), Vector3(attach.x + 0.05, H, 0.08))
	var l: OmniLight3D = FlickerLight.new()
	l.light_color = WARM
	l.base_energy = energy
	l.flicker = true
	l.lamp_mat = mat
	l.omni_range = 8.5
	l.omni_attenuation = 1.0
	l.shadow_enabled = true
	l.position = center - Vector3(0, 0.15, 0)
	add_child(l)


func _wire(a: Vector3, b: Vector3) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.006
	cm.bottom_radius = 0.006
	cm.height = a.distance_to(b)
	cm.radial_segments = 6
	cm.rings = 1
	cm.material = wire_mat
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	var y := (b - a).normalized()
	var x := y.cross(Vector3.FORWARD)
	if x.length() < 0.01:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y)
	mi.transform = Transform3D(Basis(x, y, z), (a + b) / 2.0)
	add_child(mi)


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
	if doors.is_empty():
		_seg(Vector3((xa + xb) / 2, H / 2, z), Vector3(xb - xa, H, T))
		return
	var csg := _csg_wall(Vector3((xa + xb) / 2, H / 2, z), Vector3(xb - xa, H, T))
	for dx in doors:
		_cut_door(csg, Vector3(dx, 0, z), false)


func _wall_z(x: float, za: float, zb: float, doors: Array) -> void:
	if doors.is_empty():
		_seg(Vector3(x, H / 2, (za + zb) / 2), Vector3(T, H, zb - za))
		return
	var csg := _csg_wall(Vector3(x, H / 2, (za + zb) / 2), Vector3(T, H, zb - za))
	for dz in doors:
		_cut_door(csg, Vector3(x, 0, dz), true)


func _csg_wall(pos: Vector3, size: Vector3) -> CSGCombiner3D:
	var csg := CSGCombiner3D.new()
	csg.use_collision = true
	add_child(csg)
	var wb := CSGBox3D.new()
	wb.size = size
	wb.position = pos
	wb.material = wall_mat
	csg.add_child(wb)
	return csg


## Проём с неровными краями: слегка кривой прямоугольник + выбоины по кромкам с обеих сторон стены.
func _cut_door(csg: CSGCombiner3D, base: Vector3, along_z: bool) -> void:
	var w := DOOR_W + rng.randf_range(-0.06, 0.06)
	var h := DOOR_H + rng.randf_range(-0.05, 0.05)
	var hole := CSGBox3D.new()
	hole.operation = CSGShape3D.OPERATION_SUBTRACTION
	hole.material = wall_mat
	var tilt := rng.randf_range(-0.012, 0.012)
	if along_z:
		hole.size = Vector3(T + 0.4, h + 0.2, w)
		hole.rotation.x = tilt
	else:
		hole.size = Vector3(w, h + 0.2, T + 0.4)
		hole.rotation.z = tilt
	hole.position = base + Vector3(0, (h - 0.2) / 2, 0)
	csg.add_child(hole)
	for i in 16:
		var chip := CSGBox3D.new()
		chip.operation = CSGShape3D.OPERATION_SUBTRACTION
		chip.material = wall_mat
		var s := rng.randf_range(0.07, 0.2)
		chip.size = Vector3(s, s * rng.randf_range(0.6, 1.5), s * rng.randf_range(0.6, 1.2))
		chip.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		var u: float
		var y: float
		if i % 3 == 0:
			u = rng.randf_range(-w / 2, w / 2)
			y = h
		else:
			u = (w / 2) * (1.0 if i % 2 == 0 else -1.0)
			y = rng.randf_range(0.05, h)
		var f := (T / 2) * (1.0 if rng.randf() < 0.5 else -1.0)
		chip.position = base + (Vector3(f, y, u) if along_z else Vector3(u, y, f))
		csg.add_child(chip)


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


func _noise_tex(seed_: int, freq: float, octaves: int, ntype := FastNoiseLite.TYPE_SIMPLEX_SMOOTH) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = seed_
	noise.noise_type = ntype
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


func _concrete(big: Texture2D, fine: Texture2D, base: Color, polished := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ConcreteShader
	m.set_shader_parameter("noise_big", big)
	m.set_shader_parameter("noise_fine", fine)
	m.set_shader_parameter("noise_cell", noise_extra[0])
	m.set_shader_parameter("noise_crack", noise_extra[1])
	m.set_shader_parameter("base_color", base)
	m.set_shader_parameter("ceiling_h", H)
	m.set_shader_parameter("polished", 1.0 if polished else 0.0)
	return m



# ---------- трещины: тонкие, ломаные, растут от стен; часть переходит со стены на пол ----------

func _cracks() -> void:
	var texs: Array[ImageTexture] = []
	for i in 8:
		texs.append(_crack_tex(900 + i))
	# грани стен: [точка A, точка B, нормаль внутрь помещения]
	var faces := [
		[Vector3(X0, 0, ZN + T / 2), Vector3(X1, 0, ZN + T / 2), Vector3(0, 0, 1)],
		[Vector3(X0, 0, ZS - T / 2), Vector3(X1, 0, ZS - T / 2), Vector3(0, 0, -1)],
		[Vector3(X0 + T / 2, 0, ZN), Vector3(X0 + T / 2, 0, ZS), Vector3(1, 0, 0)],
		[Vector3(X1 - T / 2, 0, ZN), Vector3(X1 - T / 2, 0, ZS), Vector3(-1, 0, 0)],
		[Vector3(X0, 0, -CW - T / 2), Vector3(X1, 0, -CW - T / 2), Vector3(0, 0, -1)],
		[Vector3(X0, 0, -CW + T / 2), Vector3(X1, 0, -CW + T / 2), Vector3(0, 0, 1)],
		[Vector3(X0, 0, CW - T / 2), Vector3(X1, 0, CW - T / 2), Vector3(0, 0, -1)],
		[Vector3(X0, 0, CW + T / 2), Vector3(X1, 0, CW + T / 2), Vector3(0, 0, 1)],
		[Vector3(-T / 2, 0, ZN), Vector3(-T / 2, 0, -CW), Vector3(-1, 0, 0)],
		[Vector3(T / 2, 0, ZN), Vector3(T / 2, 0, -CW), Vector3(1, 0, 0)],
		[Vector3(-T / 2, 0, CW), Vector3(-T / 2, 0, ZS), Vector3(-1, 0, 0)],
		[Vector3(T / 2, 0, CW), Vector3(T / 2, 0, ZS), Vector3(1, 0, 0)],
	]
	var made := 0
	var tries := 0
	while made < 26 and tries < 200:
		tries += 1
		var f: Array = faces[rng.randi() % faces.size()]
		var p: Vector3 = (f[0] as Vector3).lerp(f[1], rng.randf_range(0.05, 0.95))
		var nrm: Vector3 = f[2]
		if _in_doorway(p):
			continue
		made += 1
		var tex: ImageTexture = texs[rng.randi() % texs.size()]
		var ceiling := rng.randf() < 0.3
		var l := rng.randf_range(0.5, 1.4)
		var y := H if ceiling else 0.0
		# по полу/потолку — от стены внутрь комнаты
		var up := Vector3.DOWN if ceiling else Vector3.UP
		_decal(tex, p + Vector3(0, y, 0) + nrm * (l / 2 - 0.02), up, -nrm, Vector3(l * 0.5, 0.2, l))
		# продолжение по стене
		if rng.randf() < 0.55:
			var lw := rng.randf_range(0.3, 0.8)
			var along := Vector3.UP if ceiling else Vector3.DOWN
			var c := p + Vector3(0, y, 0) - along * (lw / 2 - 0.02)
			_decal(texs[rng.randi() % texs.size()], c, nrm, along, Vector3(lw * 0.5, 0.2, lw))


func _in_doorway(p: Vector3) -> bool:
	for dx in [-6.0, 6.0]:
		if absf(p.x - dx) < DOOR_W / 2 + 0.25 and absf(absf(p.z) - CW) < T:
			return true
	if absf(p.x) < T and absf(p.z - 5.5) < DOOR_W / 2 + 0.25:
		return true
	return false


## Декаль: проецируется вдоль -proj_up; «основание» трещины (низ текстуры) — со стороны +base_dir.
func _decal(tex: Texture2D, pos: Vector3, proj_up: Vector3, base_dir: Vector3, size: Vector3) -> void:
	var d := Decal.new()
	d.texture_albedo = tex
	d.size = size
	d.modulate = Color(1, 1, 1, 0.55)
	d.normal_fade = 0.4
	d.upper_fade = 0.1
	d.lower_fade = 0.1
	var y := proj_up.normalized()
	var z := base_dir.normalized()
	var x := y.cross(z).normalized()
	d.transform = Transform3D(Basis(x, y, z), pos)
	add_child(d)


func _crack_tex(seed_: int) -> ImageTexture:
	var img := Image.create(128, 256, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := RandomNumberGenerator.new()
	r.seed = seed_
	_crack_branch(img, r, Vector2(64 + r.randf_range(-10, 10), 255), -PI / 2 + r.randf_range(-0.4, 0.4), 2.2, r.randf_range(150, 240), 2)
	return ImageTexture.create_from_image(img)


func _crack_branch(img: Image, r: RandomNumberGenerator, p: Vector2, ang: float, width: float, length: float, depth: int) -> void:
	var base := ang
	var travelled := 0.0
	while travelled < length:
		# ломаная: короткие прямые отрезки с резкими изломами
		ang = clampf(ang + r.randf_range(-0.9, 0.9), base - 0.9, base + 0.9)
		var seg := r.randf_range(4.0, 11.0)
		var q := p + Vector2(cos(ang), sin(ang)) * seg
		var k := 1.0 - travelled / length
		_line(img, p, q, maxf(width * k, 0.6))
		if depth > 0 and r.randf() < 0.1:
			_crack_branch(img, r, q, ang + r.randf_range(-1.0, 1.0), width * 0.6 * k, length * 0.35 * k, depth - 1)
		travelled += seg
		p = q
		if p.y < 2.0 or p.x < 2.0 or p.x > 125.0:
			break


func _line(img: Image, a: Vector2, b: Vector2, w: float) -> void:
	var n := int(a.distance_to(b)) + 1
	for i in n + 1:
		_dot(img, a.lerp(b, float(i) / n), w)


func _dot(img: Image, c: Vector2, w: float) -> void:
	var rad := w * 0.5
	for y in range(int(c.y - rad - 1.0), int(c.y + rad + 2.0)):
		for x in range(int(c.x - rad - 1.0), int(c.x + rad + 2.0)):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var a := clampf(rad + 0.5 - Vector2(x + 0.5, y + 0.5).distance_to(c), 0.0, 1.0)
			if a > img.get_pixel(x, y).a:
				img.set_pixel(x, y, Color(0.04, 0.04, 0.035, a))


# ---------- пыль ----------

## Плавающие в воздухе пылинки: крупные, полупрозрачные, видны в свете ламп.
func _dust_motes() -> void:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(X1 - 0.5, H / 2 - 0.2, ZS - 0.5)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.005
	pm.initial_velocity_max = 0.03
	pm.gravity = Vector3(0, -0.004, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.4
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_noise_speed_random = 0.2
	pm.turbulence_influence_min = 0.01
	pm.turbulence_influence_max = 0.04
	pm.scale_min = 0.5
	pm.scale_max = 1.6
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.set_color(1, Color(1, 1, 1, 0))
	ramp.add_point(0.2, Color(1, 1, 1, 1))
	ramp.add_point(0.8, Color(1, 1, 1, 1))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt

	var dot := Gradient.new()
	dot.set_color(0, Color(1, 1, 1, 1))
	dot.set_color(1, Color(1, 1, 1, 0))
	var dt := GradientTexture2D.new()
	dt.gradient = dot
	dt.fill = GradientTexture2D.FILL_RADIAL
	dt.fill_from = Vector2(0.5, 0.5)
	dt.fill_to = Vector2(1.0, 0.5)
	dt.width = 32
	dt.height = 32

	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = dt
	m.albedo_color = Color(0.95, 0.88, 0.75, 0.4)
	m.roughness = 1.0
	m.disable_receive_shadows = true
	var q := QuadMesh.new()
	q.size = Vector2(0.018, 0.018)
	q.material = m

	var ps := GPUParticles3D.new()
	ps.amount = 700
	ps.lifetime = 24.0
	ps.preprocess = 24.0
	ps.process_material = pm
	ps.draw_pass_1 = q
	ps.position = Vector3(0, H / 2, 0)
	ps.visibility_aabb = AABB(Vector3(X0 - 1, -H, ZN - 1), Vector3(X1 - X0 + 2, H * 2, ZS - ZN + 2))
	ps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ps)


## Пылевая дымка, прижатая к полу (объёмный туман, гуще внизу).
func _low_dust() -> void:
	var fm := FogMaterial.new()
	fm.density = 0.05
	fm.albedo = Color(0.75, 0.7, 0.62)
	fm.height_falloff = 2.5
	fm.edge_fade = 0.3
	var fv := FogVolume.new()
	fv.size = Vector3(X1 - X0, 1.2, ZS - ZN)
	fv.position = Vector3(0, 0.6, 0)
	fv.material = fm
	add_child(fv)

func _make_env() -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.01, 0.01, 0.012)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.55, 0.46)
	e.ambient_light_energy = 0.1
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = true
	e.ssao_radius = 1.4
	e.ssao_intensity = 3.0
	e.ssao_power = 2.0
	e.ssao_light_affect = 0.3
	e.ssr_enabled = true
	e.ssr_max_steps = 64
	e.glow_enabled = true
	e.glow_intensity = 0.6
	e.fog_enabled = true
	e.fog_light_color = Color(0.04, 0.04, 0.045)
	e.fog_density = 0.02
	e.fog_height = 0.6
	e.fog_height_density = 0.5
	e.volumetric_fog_enabled = true
	e.volumetric_fog_density = 0.008
	e.volumetric_fog_albedo = Color(0.8, 0.8, 0.8)
	return e


func _bake() -> void:
	var root := Node3D.new()
	root.name = "LevelBaked"
	for c in get_children():
		var d := c.duplicate()
		root.add_child(d)
		_own(d, root)
	var ps := PackedScene.new()
	ps.pack(root)
	var err := ResourceSaver.save(ps, "res://level_baked.tscn")
	root.free()
	print("level_baked.tscn: ", "сохранено" if err == OK else "ошибка %d" % err)


func _own(n: Node, o: Node) -> void:
	n.owner = o
	for c in n.get_children():
		_own(c, o)
