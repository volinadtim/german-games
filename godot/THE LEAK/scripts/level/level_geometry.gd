@tool
extends Node3D
# Часть level.gd: константы, стены (CSG, сколы, проёмы), колонны, балки, бетонные материалы, процедурные текстуры.
const FlickerLight := preload("res://scripts/level/flicker_light.gd")
const Surface := preload("res://scripts/level/surface.gd")
const Atmosphere := preload("res://scripts/level/atmosphere.gd")
const ConcreteShader := preload("res://shaders/concrete.gdshader")

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
## Телефон: облегчённая сборка (меньше сколов CSG, пылинок, без теней от потолочных ламп).
## На ПК и в редакторе — false, всё как было.
var lite := OS.has_feature("mobile") or "--lite" in OS.get_cmdline_user_args()
var noise_extra: Array = []
## поломанная лампа — её подрагивание делает atmosphere.gd
var broken_mesh: Node3D
var broken_light: SpotLight3D

## Кнопка в инспекторе (выдели узел Level): сохраняет сгенерированную локацию в обычную сцену
## res://level_baked.tscn — с настоящими узлами, мешами и материалами, которые можно двигать и править руками.
@export_tool_button("Запечь в level_baked.tscn", "PackedScene") var bake_action = _bake


## Сдвигает точку пола внутрь помещения, если круг радиуса r заходит за стену (внешние стены, перегородки, коридор).
func _off_walls(p: Vector3, r: float) -> Vector3:
	var ix := X0 + T / 2 + r
	var ax := X1 - T / 2 - r
	p.x = clampf(p.x, ix, ax)
	if p.z < -CW - T / 2:           # северные комнаты
		p.z = clampf(p.z, ZN + T / 2 + r, -CW - T / 2 - r)
	elif p.z > CW + T / 2:          # южные
		p.z = clampf(p.z, CW + T / 2 + r, ZS - T / 2 - r)
	else:
		return p
	if absf(p.x) < T / 2 + r and not (p.z > CW and absf(p.z - 5.5) < DOOR_W / 2):
		p.x = (T / 2 + r) * (1.0 if p.x >= 0.0 else -1.0)
	return p


func _fx_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _wall_x(z: float, xa: float, xb: float, doors: Array) -> void:
	var csg := _csg_wall(Vector3((xa + xb) / 2, H / 2, z), Vector3(xb - xa, H, T))
	_edge_chips(csg, Vector3((xa + xb) / 2, 0, z), xb - xa, false, doors)
	for dx in doors:
		_cut_door(csg, Vector3(dx, 0, z), false)


func _wall_z(x: float, za: float, zb: float, doors: Array) -> CSGCombiner3D:
	var csg := _csg_wall(Vector3(x, H / 2, (za + zb) / 2), Vector3(T, H, zb - za))
	_edge_chips(csg, Vector3(x, 0, (za + zb) / 2), zb - za, true, doors)
	for dz in doors:
		_cut_door(csg, Vector3(x, 0, dz), true)
	return csg


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


## Выбоина: случайный размер (чаще мелкие, иногда крупные), форма — кубик или шар, случайный поворот.
func _chip(csg: CSGCombiner3D, pos: Vector3, scale_k := 1.0) -> void:
	if lite and rng.randf() < 0.65:
		return   # телефон: примерно треть сколов — CSG считается на старте и тяжёлый для слабого процессора
	var s := lerpf(0.06, 0.3, pow(rng.randf(), 1.6)) * scale_k
	var c: CSGShape3D
	if rng.randf() < 0.3:
		var sp := CSGSphere3D.new()
		sp.radius = s * 0.6
		sp.radial_segments = 6
		sp.rings = 4
		c = sp
	else:
		var b := CSGBox3D.new()
		b.size = Vector3(s, s * rng.randf_range(0.4, 1.6), s * rng.randf_range(0.5, 1.3))
		c = b
	c.operation = CSGShape3D.OPERATION_SUBTRACTION
	c.material = wall_mat
	c.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
	c.position = pos + Vector3(rng.randf_range(-0.02, 0.02), rng.randf_range(-0.02, 0.02), rng.randf_range(-0.02, 0.02))
	csg.add_child(c)


## Сколы по рёбрам стены у пола и потолка (там бетон бьют и он крошится), с обеих сторон.
## Скоплениями: в одном месте 1–4 выбоины рядом.
func _edge_chips(csg: CSGCombiner3D, base: Vector3, length: float, along_z: bool, doors: Array) -> void:
	var spots := int(length * rng.randf_range(0.35, 0.6))
	for k in spots:
		var u := rng.randf_range(-length / 2 + 0.3, length / 2 - 0.3)
		var skip := false
		for d in doors:
			var dc: float = d - (base.z if along_z else base.x)
			if absf(u - dc) < DOOR_W / 2 + 0.2:
				skip = true
		if skip:
			continue
		var y := 0.0 if rng.randf() < 0.55 else H
		var f := (T / 2) * (1.0 if rng.randf() < 0.5 else -1.0)
		for j in rng.randi_range(1, 4):
			var uu := u + rng.randf_range(-0.15, 0.15)
			var yy := y + (rng.randf_range(0.0, 0.12) if y == 0.0 else -rng.randf_range(0.0, 0.12))
			_chip(csg, base + (Vector3(f, yy, uu) if along_z else Vector3(uu, yy, f)), 1.4)


## Проём с неровными краями: слегка кривой прямоугольник + выбоины по кромкам,
## гуще всего — в верхних углах проёма, где бетон слабее.
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
	var n := rng.randi_range(18, 32)
	for i in n:
		var u: float
		var y: float
		var r := rng.randf()
		if r < 0.4:
			# верхние углы проёма
			u = (w / 2) * (1.0 if rng.randf() < 0.5 else -1.0) + rng.randf_range(-0.12, 0.12)
			y = h + rng.randf_range(-0.15, 0.08)
		elif r < 0.55:
			# нижние углы (бьют ногами и тележками)
			u = (w / 2) * (1.0 if rng.randf() < 0.5 else -1.0)
			y = rng.randf_range(0.0, 0.25)
		elif r < 0.75:
			u = rng.randf_range(-w / 2, w / 2)
			y = h
		else:
			u = (w / 2) * (1.0 if rng.randf() < 0.5 else -1.0)
			y = rng.randf_range(0.05, h)
		var f := (T / 2) * (1.0 if rng.randf() < 0.5 else -1.0)
		_chip(csg, base + (Vector3(f, y, u) if along_z else Vector3(u, y, f)), 1.1)


## Колонна со сколами на вертикальных рёбрах — самые уязвимые места.
func _column(pos: Vector3, size: Vector3) -> void:
	var csg := _csg_wall(pos, size)
	for e in 4:
		var cx := size.x / 2 * (1.0 if e % 2 == 0 else -1.0)
		var cz := size.z / 2 * (1.0 if e < 2 else -1.0)
		for k in rng.randi_range(2, 5):
			var y := rng.randf_range(0.0, size.y) if rng.randf() < 0.6 else rng.randf_range(0.0, 0.4)
			_chip(csg, pos + Vector3(cx, y - size.y / 2, cz), 0.9)


## Балка под потолком: сколы по нижним рёбрам.
func _beam(pos: Vector3, size: Vector3) -> void:
	var csg := CSGCombiner3D.new()
	add_child(csg)
	var b := CSGBox3D.new()
	b.size = size
	b.position = pos
	b.material = wall_mat
	csg.add_child(b)
	for k in rng.randi_range(2, 5):
		var ex := size.x / 2 * (1.0 if rng.randf() < 0.5 else -1.0)
		var z := rng.randf_range(-size.z / 2, size.z / 2)
		_chip(csg, pos + Vector3(ex, -size.y / 2, z), 0.7)


func _web_tex() -> ImageTexture:
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := RandomNumberGenerator.new()
	r.seed = 77
	var hub := Vector2(128, 95)
	var col := Color(0.9, 0.9, 0.88, 0.7)
	# края треугольника (UV): A(0,0) B(256,0) D(128,256)
	var edge := []
	for i in 13:
		var t := float(i) / 12.0
		var p: Vector2
		if t < 0.34:
			p = Vector2(0, 0).lerp(Vector2(255, 0), t / 0.34)
		elif t < 0.67:
			p = Vector2(255, 0).lerp(Vector2(128, 255), (t - 0.34) / 0.33)
		else:
			p = Vector2(128, 255).lerp(Vector2(0, 0), (t - 0.67) / 0.33)
		edge.append(p + Vector2(r.randf_range(-6, 6), r.randf_range(-6, 6)))
	for p in edge:
		_line(img, hub, p, 0.5, col)
	# спираль из провисающих перемычек
	var f := 0.12
	while f < 0.95:
		for i in edge.size():
			var p0: Vector2 = hub.lerp(edge[i], f)
			var p1: Vector2 = hub.lerp(edge[(i + 1) % edge.size()], f + 0.015)
			if r.randf() < 0.85:
				var mid := (p0 + p1) / 2.0 + (hub - (p0 + p1) / 2.0).normalized() * 3.0
				_line(img, p0, mid, 0.4, col)
				_line(img, mid, p1, 0.4, col)
		f += r.randf_range(0.06, 0.1)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Случайная точка на полу недалеко от какой-нибудь стены (не в проёме).
func _near_wall_point(dmin: float, dmax: float) -> Vector3:
	for tries in 50:
		var p := Vector3(rng.randf_range(X0 + 0.3, X1 - 0.3), 0, rng.randf_range(ZN + 0.3, ZS - 0.3))
		var dz := minf(minf(absf(p.z - ZN), absf(p.z - ZS)), minf(absf(absf(p.z) - CW), 99.0))
		var dx := minf(absf(p.x - X0), absf(p.x - X1))
		if absf(p.z) > CW:
			dx = minf(dx, absf(p.x))
		var d := minf(dx, dz)
		if d >= dmin and d <= dmax and not _in_doorway(p):
			return p
	return Vector3(X0 + 0.5, 0, ZN + 0.5)


func _dust_tex(seed_: int) -> ImageTexture:
	var n := FastNoiseLite.new()
	n.seed = seed_
	n.frequency = 0.04
	n.fractal_octaves = 4
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for y in 128:
		for x in 128:
			var r := Vector2(x - 64, y - 64).length() / 64.0
			var fall := clampf(1.0 - r, 0.0, 1.0)
			var v := clampf(n.get_noise_2d(x, y) * 0.8 + 0.5, 0.0, 1.0)
			var a := clampf(fall * fall * (0.3 + v), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


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


## Текстуры шума маленькие (128 px) и в шейдере берутся без сглаживания — крупные «пиксели».
## Частота пересчитана так, чтобы рисунок остался прежнего масштаба; мелкие октавы срезаны, чтобы не рябило.
func _noise_tex(seed_: int, freq: float, octaves: int, ntype := FastNoiseLite.TYPE_SIMPLEX_SMOOTH) -> NoiseTexture2D:
	const SIZE := 128
	var noise := FastNoiseLite.new()
	noise.seed = seed_
	noise.noise_type = ntype
	noise.frequency = freq * 512.0 / SIZE
	noise.fractal_octaves = mini(octaves, 3)
	noise.fractal_gain = 0.5
	var t := NoiseTexture2D.new()
	t.width = SIZE
	t.height = SIZE
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
	m.set_shader_parameter("noise_big_px", big)
	m.set_shader_parameter("noise_fine_px", fine)
	m.set_shader_parameter("noise_cell_px", noise_extra[0])
	m.set_shader_parameter("base_color", base)
	m.set_shader_parameter("ceiling_h", H)
	m.set_shader_parameter("polished", 1.0 if polished else 0.0)
	return m


func _in_doorway(p: Vector3) -> bool:
	for dx in [-6.0, 6.0]:
		if absf(p.x - dx) < DOOR_W / 2 + 0.25 and absf(absf(p.z) - CW) < T:
			return true
	if absf(p.x) < T and absf(p.z - 5.5) < DOOR_W / 2 + 0.25:
		return true
	if absf(p.x - X1) < T and absf(p.z) < DOOR_W / 2 + 0.25:
		return true
	return false


## Декаль: проецируется вдоль -proj_up; «основание» трещины (низ текстуры) — со стороны +base_dir.
func _decal(tex: Texture2D, pos: Vector3, proj_up: Vector3, base_dir: Vector3, size: Vector3) -> void:
	var d := Decal.new()
	d.texture_albedo = tex
	d.size = size
	d.modulate = Color(1, 1, 1, 0.7)
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
	_crack_branch(img, r, Vector2(64 + r.randf_range(-10, 10), 255), -PI / 2 + r.randf_range(-0.4, 0.4), 3.2, r.randf_range(150, 240), 2)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _crack_branch(img: Image, r: RandomNumberGenerator, p: Vector2, ang: float, width: float, length: float, depth: int) -> void:
	var base := ang
	var travelled := 0.0
	while travelled < length:
		# ломаная: короткие прямые отрезки с резкими изломами
		ang = clampf(ang + r.randf_range(-0.8, 0.8), base - 0.6, base + 0.6)
		# у края текстуры разворачиваемся к центру
		if p.x < 20.0:
			ang = clampf(ang, -PI / 2 - 0.2, -PI / 2 + 0.6)
		elif p.x > 108.0:
			ang = clampf(ang, -PI / 2 - 0.6, -PI / 2 + 0.2)
		var seg := r.randf_range(4.0, 11.0)
		var q := p + Vector2(cos(ang), sin(ang)) * seg
		var k := 1.0 - travelled / length
		_line(img, p, q, maxf(width * k, 1.0))
		if depth > 0 and r.randf() < 0.1:
			_crack_branch(img, r, q, ang + r.randf_range(-1.0, 1.0), width * 0.6 * k, length * 0.35 * k, depth - 1)
		travelled += seg
		p = q
		if p.y < 2.0:
			break
		p.x = clampf(p.x, 3.0, 125.0)


func _line(img: Image, a: Vector2, b: Vector2, w: float, col := Color(0.04, 0.04, 0.035)) -> void:
	var n := int(a.distance_to(b)) + 1
	for i in n + 1:
		_dot(img, a.lerp(b, float(i) / n), w, col)


func _dot(img: Image, c: Vector2, w: float, col := Color(0.04, 0.04, 0.035)) -> void:
	var rad := w * 0.5
	for y in range(int(c.y - rad - 1.0), int(c.y + rad + 2.0)):
		for x in range(int(c.x - rad - 1.0), int(c.x + rad + 2.0)):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var a := clampf(rad + 0.5 - Vector2(x + 0.5, y + 0.5).distance_to(c), 0.0, 1.0)
			a *= col.a if col.a < 1.0 else 1.0
			if a > img.get_pixel(x, y).a:
				img.set_pixel(x, y, Color(col.r, col.g, col.b, a))


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
