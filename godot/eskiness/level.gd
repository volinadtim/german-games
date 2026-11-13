@tool
extends Node3D
## Заброшенное бетонное помещение: короткий общий коридор вдоль X, по две комнаты с каждой стороны.
##   север (z < 0): комнаты с центрами x = -6, 6
##   юг    (z > 0): комнаты с центрами x = -6, 6, между ними дверь

const FlickerLight := preload("res://flicker_light.gd")
const Surface := preload("res://surface.gd")
const Atmosphere := preload("res://atmosphere.gd")
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
## Телефон: облегчённая сборка (меньше сколов CSG, пылинок, без теней от потолочных ламп).
## На ПК и в редакторе — false, всё как было.
var lite := OS.has_feature("mobile") or "--lite" in OS.get_cmdline_user_args()
var noise_extra: Array = []
## поломанная лампа — её подрагивание делает atmosphere.gd
var broken_mesh: MeshInstance3D
var broken_light: OmniLight3D

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
	# выход по лестнице на поверхность (поляна, небо, переключение окружения)
	var sf := Surface.new()
	sf.level = self
	sf.env = we.environment
	add_child(sf)
	# мелкие детали атмосферы: мошки у ламп, капли, пар, далёкие звуки (каждая — своя функция в atmosphere.gd)
	var at := Atmosphere.new()
	at.level = self
	add_child(at)


func _build() -> void:
	var w := X1 - X0 + T
	var d := ZS - ZN + T
	_box(Vector3(0, -0.15, 0), Vector3(w, 0.3, d), floor_mat)
	_box(Vector3(0, H + 0.15, 0), Vector3(w, 0.3, d), ceil_mat)

	# внешние стены
	_wall_x(ZN, X0 - T / 2, X1 + T / 2, [])
	_wall_x(ZS, X0 - T / 2, X1 + T / 2, [])
	_wall_z(X0, ZN, ZS, [])
	var east := _wall_z(X1, ZN, ZS, [])

	# стены коридора с проёмами
	_wall_x(-CW, X0, X1, [-6.0, 6.0])
	_wall_x(CW, X0, X1, [-6.0, 6.0])

	# перегородки между комнатами
	_wall_z(0.0, ZN, -CW, [])
	_wall_z(0.0, CW, ZS, [5.5])

	# балки под потолком коридора
	var x := X0 + 4.0
	while x < X1 - 0.1:
		_beam(Vector3(x, H - 0.2, 0), Vector3(0.35, 0.4, CW * 2))
		x += 4.0

	# колонны в южных комнатах
	for px in [-8.5, 8.5]:
		_column(Vector3(px, H / 2, 5.5), Vector3(0.55, H, 0.55))

	_debris()
	_lights()
	_cracks()
	_cobwebs()
	_floor_litter()
	_dust_motes()
	_low_dust()
	# проём к лестнице на поверхность — режем последним, чтобы не сбить случайную раскладку остального
	_cut_door(east, Vector3(X1, 0, 0), true)


func _debris() -> void:
	var spots := [
		Vector3(-10, 0, -7.5), Vector3(-3, 0, -4), Vector3(2.5, 0, -7.8), Vector3(10, 0, -3.5),
		Vector3(-10.5, 0, 8), Vector3(-2.5, 0, 3.5), Vector3(3, 0, 8), Vector3(10.8, 0, 3.5),
		Vector3(11.0, 0, -6.8),
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
	_broken_lamp(Vector3(-6, H, 0), 1.1)
	_lamp(Vector3(6, H, 0), 1.05, false)
	_lamp(Vector3(-6, H, rn), 1.05, false)
	_lamp(Vector3(6, H, rn), 1.0, false)
	_lamp(Vector3(6, H, rs), 1.05, false)


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
	broken_mesh = mi
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
	l.shadow_enabled = not lite
	l.position = center - Vector3(0, 0.15, 0)
	add_child(l)
	broken_light = l


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
	l.shadow_enabled = not lite
	l.position = pos - Vector3(0, 0.3, 0)
	add_child(l)


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


# ---------- паутина в верхних углах ----------

func _cobwebs() -> void:
	var tex := _web_tex()
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = Color(0.85, 0.83, 0.8, 0.75)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 1.0
	m.disable_receive_shadows = true
	# углы помещений у потолка: [точка угла, направление вдоль стены 1, вдоль стены 2]
	var corners := []
	var rooms := [
		[X0 + T / 2, -T / 2, ZN + T / 2, -CW - T / 2], [T / 2, X1 - T / 2, ZN + T / 2, -CW - T / 2],
		[X0 + T / 2, -T / 2, CW + T / 2, ZS - T / 2], [T / 2, X1 - T / 2, CW + T / 2, ZS - T / 2],
		[X0 + T / 2, X1 - T / 2, -CW + T / 2, CW - T / 2],
	]
	for r in rooms:
		for cx in [r[0], r[1]]:
			for cz in [r[2], r[3]]:
				var dx := 1.0 if cx == r[0] else -1.0
				var dz := 1.0 if cz == r[2] else -1.0
				corners.append([Vector3(cx, H - 0.01, cz), Vector3(dx, 0, 0), Vector3(0, 0, dz)])
	corners.shuffle()
	for k in 11:
		var c: Array = corners[k]
		var s := rng.randf_range(0.3, 0.75)
		var a: Vector3 = c[0] + c[1] * s
		var b: Vector3 = c[0] + c[2] * s * rng.randf_range(0.7, 1.3)
		var d: Vector3 = c[0] + Vector3(0, -s * rng.randf_range(0.6, 1.1), 0)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_uv(Vector2(0, 0)); st.add_vertex(a)
		st.set_uv(Vector2(1, 0)); st.add_vertex(b)
		st.set_uv(Vector2(0.5, 1)); st.add_vertex(d)
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


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
		_line(img, hub, p, 0.9, col)
	# спираль из провисающих перемычек
	var f := 0.12
	while f < 0.95:
		for i in edge.size():
			var p0: Vector2 = hub.lerp(edge[i], f)
			var p1: Vector2 = hub.lerp(edge[(i + 1) % edge.size()], f + 0.015)
			if r.randf() < 0.85:
				var mid := (p0 + p1) / 2.0 + (hub - (p0 + p1) / 2.0).normalized() * 3.0
				_line(img, p0, mid, 0.7, col)
				_line(img, mid, p1, 0.7, col)
		f += r.randf_range(0.06, 0.1)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# ---------- пыль, мусор, стекло на полу ----------

func _floor_litter() -> void:
	# слои пыли: мягкие светлые пятна, чаще у стен и в углах
	var dust_tex: Array[ImageTexture] = []
	for i in 3:
		dust_tex.append(_dust_tex(500 + i))
	for k in 18:
		var p := _near_wall_point(0.3, 1.6)
		var s := rng.randf_range(0.8, 2.2)
		var d := Decal.new()
		d.texture_albedo = dust_tex[k % 3]
		d.modulate = Color(0.55, 0.52, 0.47, rng.randf_range(0.35, 0.6))
		d.size = Vector3(s, 0.2, s * rng.randf_range(0.6, 1.0))
		d.position = Vector3(p.x, 0.0, p.z)
		d.rotation.y = rng.randf() * TAU
		d.normal_fade = 0.5
		add_child(d)
	# мусор: мелкие обломки бетона, кучками у стен
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	bm.material = wall_mat
	mm.mesh = bm
	var xforms: Array[Transform3D] = []
	for k in 22:
		var c := _near_wall_point(0.15, 1.2)
		for j in rng.randi_range(4, 14):
			var sz := Vector3(rng.randf_range(0.015, 0.07), rng.randf_range(0.01, 0.04), rng.randf_range(0.015, 0.07))
			var p := c + Vector3(rng.randf_range(-0.35, 0.35), sz.y / 2 - 0.004, rng.randf_range(-0.35, 0.35))
			var b := Basis.from_euler(Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3))).scaled(sz)
			xforms.append(Transform3D(b, p))
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
	# осколки стекла: под поломанной лампой и в паре мест
	var glass := StandardMaterial3D.new()
	# осколки заметнее: крупнее, светлее, с лёгким свечением и бликами-искрами
	glass.albedo_color = Color(0.62, 0.72, 0.7, 0.5)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.02
	glass.metallic_specular = 1.0
	glass.emission_enabled = true
	glass.emission = Color(0.55, 0.65, 0.62)
	glass.emission_energy_multiplier = 0.25
	var glint := StandardMaterial3D.new()
	glint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glint.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glint.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	glint.albedo_color = Color(0.9, 0.95, 1.0, 0.55)
	var glint_q := QuadMesh.new()
	glint_q.size = Vector2(0.014, 0.014)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	for spot in [[Vector3(-5.6, 0, 0.1), 0.9, 30], [Vector3(9.5, 0, -6.5), 0.5, 12], [Vector3(-9.0, 0, 6.8), 0.5, 10]]:
		for j in spot[2]:
			var pm := PrismMesh.new()
			var a := rng.randf_range(0.02, 0.06)
			pm.size = Vector3(a, a * rng.randf_range(0.8, 2.0), 0.003)
			pm.left_to_right = rng.randf()
			var mi := MeshInstance3D.new()
			mi.mesh = pm
			mi.material_override = glass
			var off: Vector2 = Vector2.from_angle(rng.randf() * TAU) * float(spot[1]) * sqrt(rng.randf())
			mi.position = (spot[0] as Vector3) + Vector3(off.x, 0.002, off.y)
			mi.rotation = Vector3(-PI / 2 + rng.randf_range(-0.08, 0.08), rng.randf() * TAU, 0)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			if j % 4 == 0:
				var gl := MeshInstance3D.new()
				gl.mesh = glint_q
				gl.material_override = glint
				gl.position = mi.position + Vector3(0, 0.012, 0)
				gl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(gl)


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
	m.albedo_color = Color(0.74, 0.73, 0.71, 0.35)   # серо-бежевая пыль: тёплые лампы и так её подкрашивают
	m.roughness = 1.0
	m.disable_receive_shadows = true
	var q := QuadMesh.new()
	q.size = Vector2(0.018, 0.018)
	q.material = m

	var ps := GPUParticles3D.new()
	ps.amount = 250 if lite else 700
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
	if RenderingServer.get_current_rendering_method() != "forward_plus":
		return   # на телефонах объёмного тумана нет (а в Compatibility FogMaterial даже не компилируется)
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
	# телефоны (Mobile/Compatibility): SSAO, SSR и объёмного тумана там нет — не включаем их,
	# обычный туман и glow остаются; на ПК (Forward+) всё как было
	var full := RenderingServer.get_current_rendering_method() == "forward_plus"
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.01, 0.01, 0.012)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.55, 0.46)
	e.ambient_light_energy = 0.18
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = full
	e.ssao_radius = 1.4
	e.ssao_intensity = 3.0
	e.ssao_power = 2.0
	e.ssao_light_affect = 0.3
	e.ssr_enabled = full
	e.ssr_max_steps = 64
	e.glow_enabled = true
	e.glow_intensity = 0.7
	e.glow_bloom = 0.12
	e.glow_hdr_threshold = 0.85
	e.fog_enabled = true
	e.fog_light_color = Color(0.04, 0.04, 0.045)
	e.fog_density = 0.02
	e.fog_height = 0.6
	e.fog_height_density = 0.5
	e.volumetric_fog_enabled = full
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
