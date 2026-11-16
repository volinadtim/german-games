extends Node3D
# Часть village.gd: константы, рельеф дороги и деревни, дома, подвал с автоматом, мелочи.
# Вторая локация (промпт 15.11 23:01): заброшенная деревня в ~300 м к северу (было ~700, промпт 16.11 02:16) от поляны.
# Дорога идёт от машины на поляне прямо на север (x = ROAD_X) по долине между холмами.
# Земля до z = 38 — поляна (surface.gd), дальше — своя сетка; на стыке высоты плавно сходятся.

const G := 4.0                       # уровень земли (как у поляны)
const ROAD_X := 31.0                 # дорога прямая вдоль Z
const ROAD_Z0 := 11.0                # начало дороги — у машины на поляне
const ROAD_W := 2.6                  # полуширина полотна
const Z_SEAM := 38.0                 # где кончается сетка поляны
const Z_END := 422.0
const GX0 := -15.0                   # сетка земли: x от GX0, шаг GSTEP
const GNX := 46
const GSTEP := 2.0
const VZ0 := 312.0                   # деревня: z от VZ0 до VZ1
const VZ1 := 392.0
const V_HALF := 26.0                 # полуширина ровной площадки деревни (от ROAD_X)

## Машина глохнет здесь (car.gd): на улице деревни, водительская дверь (+X) смотрит на дом с подвалом.
const STALL := Vector3(32.2, G, 332.0)
const STALL_YAW := 0.0

## Дом с подвалом (H0): участок x 37..45, z 334..342 (по сетке земли — под ним дыра).
const H0 := Rect2(37.0, 334.0, 8.0, 8.0)
const FLOOR_Y := G + 0.25            # пол домов
const B := 0.6                       # пол подвала
const B_H := 2.7                     # высота подвала
const ST_X0 := 42.2                  # лестница в подвал: люк в полу дома, вниз вдоль +Z
const ST_X1 := 43.6
const ST_Z0 := 335.5
const ST_LEN := 4.8
const ROOM := Rect2(35.5, 340.3, 11.5, 10.7)   # подвал: x 35.5..47, z 340.3..351
## Где стоит автомат-«бонусник» в подвале (передом на юг, к лестнице)
const SLOT_POS := Vector3(41.2, B, 350.35)
## Второй Trinkets Market — справа от автомата (как в бункере)
const SHOP_POS := Vector3(43.25, B, 350.55)

## Остальные дома: [центр x, центр z, ширина (X), глубина (Z), сторона двери (+1 — дверь на +X)]
const HOUSES := [
	[21.0, 330.0, 7.0, 6.0, 1.0], [20.5, 346.0, 8.0, 7.0, 1.0], [42.0, 357.0, 7.0, 6.0, -1.0],
	[21.0, 364.0, 7.0, 6.0, 1.0], [43.5, 371.5, 9.0, 8.0, -1.0], [22.0, 382.0, 6.0, 6.0, 1.0],
]

var level: Node3D                    # level.gd (материалы, светильники)
var surface: Node                    # surface.gd (высота поляны)
var wall_mat: Material
var floor_mat: Material
var wood_mat: StandardMaterial3D
var wood_dark: StandardMaterial3D
var roof_mat: StandardMaterial3D
var road_mat: StandardMaterial3D
var rng := RandomNumberGenerator.new()
var hn := FastNoiseLite.new()
var hn2 := FastNoiseLite.new()
## точки внутри домов, где можно положить лут: [Vector3, ...] по домам (0 — подвал)
var loot_spots: Array = []
var marker_pos := Vector3.ZERO       # куда смотрит метка задания (дверь дома с подвалом)


# ---------- высота земли ----------

## Высота в любой точке: на поляне — surface.gd, дальше — долина дороги и деревня.
func height(x: float, z: float) -> float:
	if z <= Z_SEAM:
		return surface.height(x, z) if surface else G
	var vh := _vh(x, z)
	if z < Z_SEAM + 14.0 and surface:
		return lerpf(surface.height(x, z), vh, smoothstep(Z_SEAM, Z_SEAM + 14.0, z))
	return vh


func _vh(x: float, z: float) -> float:
	var dx := absf(x - ROAD_X)
	var vk := smoothstep(VZ0 - 30.0, VZ0, z) * (1.0 - smoothstep(VZ1, VZ1 + 12.0, z))   # 1 — в деревне
	var half := lerpf(8.5, V_HALF, vk)
	var hill := smoothstep(half, half + 14.0, dx) * (6.5 + 4.0 * hn.get_noise_2d(x, z))
	hill += smoothstep(VZ1 + 4.0, Z_END - 6.0, z) * (8.0 + 3.0 * hn.get_noise_2d(x * 1.3, z))
	var bump := hn2.get_noise_2d(x, z) * 0.3 + hn.get_noise_2d(x * 2.0, z * 2.0) * 0.25
	bump *= lerpf(1.0, 0.35, vk) * smoothstep(ROAD_W + 0.4, ROAD_W + 4.0, dx)
	# у дома с подвалом — ровно (потолок подвала под землёй)
	var dh := _rect_d(x, z, Rect2(ROOM.position.x - 1.0, H0.position.y - 1.0, ROOM.size.x + 2.0, ROOM.end.y - H0.position.y + 2.0))
	bump *= smoothstep(0.0, 3.0, dh)
	return G + hill + bump


static func _rect_d(x: float, z: float, r: Rect2) -> float:
	var dx := maxf(maxf(r.position.x - x, x - r.end.x), 0.0)
	var dz := maxf(maxf(r.position.y - z, z - r.end.y), 0.0)
	return Vector2(dx, dz).length()


## В подвале (или на лестнице в него) — противогаз не нужен.
static func in_basement(p: Vector3) -> bool:
	return p.y < G - 1.2 and p.x > ROOM.position.x - 1.0 and p.x < ROOM.end.x + 1.0 \
		and p.z > ST_Z0 - 0.5 and p.z < ROOM.end.y + 0.5


# ---------- постройка ----------

func _materials() -> void:
	wall_mat = level.wall_mat if level else StandardMaterial3D.new()
	floor_mat = level.floor_mat if level else StandardMaterial3D.new()
	wood_mat = _tex_mat(_planks_tex(Color(0.33, 0.25, 0.17), 7), 0.5)
	wood_dark = _tex_mat(_planks_tex(Color(0.2, 0.16, 0.12), 13), 0.5)
	roof_mat = _tex_mat(_sheet_tex(), 0.4)
	road_mat = _tex_mat(_gravel_tex(), 0.25)


func _tex_mat(t: Texture2D, scale_: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = t
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale_
	m.roughness = 0.95
	return m


## Доски: полосы с щелями и сучками, пиксельно (как стены бункера).
func _planks_tex(base: Color, seed_: int) -> ImageTexture:
	const S := 64
	var r := RandomNumberGenerator.new()
	r.seed = seed_
	var img := Image.create(S, S, false, Image.FORMAT_RGB8)
	var bands: Array = []
	for b in 8:
		bands.append(r.randf_range(0.75, 1.15))
	for y in S:
		@warning_ignore("integer_division")
		var band := y / 8
		for x in S:
			var k: float = bands[band] * (0.9 + 0.12 * sin(x * 0.4 + band * 3.0) + r.randf_range(-0.06, 0.06))
			if y % 8 == 0:
				k *= 0.35
			img.set_pixel(x, y, Color(base.r * k, base.g * k, base.b * k))
	for n in 10:
		var cx := r.randi_range(2, S - 3)
		var cy := r.randi_range(2, S - 3)
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				img.set_pixel(cx + dx, cy + dy, base.darkened(0.55))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Ржавый профнастил.
func _sheet_tex() -> ImageTexture:
	const S := 64
	var r := RandomNumberGenerator.new()
	r.seed = 77
	var img := Image.create(S, S, false, Image.FORMAT_RGB8)
	for y in S:
		for x in S:
			var wave := 0.75 + 0.25 * sin(x * TAU / 8.0)
			var rust := r.randf() < 0.18 or (sin(x * 0.3 + y * 0.17) > 0.75)
			var c := Color(0.36, 0.2, 0.1) if rust else Color(0.27, 0.27, 0.25)
			img.set_pixel(x, y, c * wave * r.randf_range(0.85, 1.05))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _gravel_tex() -> ImageTexture:
	const S := 64
	var r := RandomNumberGenerator.new()
	r.seed = 5
	var img := Image.create(S, S, false, Image.FORMAT_RGB8)
	for y in S:
		for x in S:
			var v := r.randf_range(0.16, 0.26)
			if r.randf() < 0.08:
				v += 0.12
			img.set_pixel(x, y, Color(v * 1.05, v, v * 0.92))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _ground() -> void:
	var nz := int((Z_END - Z_SEAM) / GSTEP)
	var hs: Array = []
	for iz in nz + 1:
		var row := PackedFloat32Array()
		row.resize(GNX + 1)
		for ix in GNX + 1:
			row[ix] = height(GX0 + ix * GSTEP, Z_SEAM + iz * GSTEP)
		hs.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in nz:
		for ix in GNX:
			var x := GX0 + ix * GSTEP
			var z := Z_SEAM + iz * GSTEP
			# дыра под домом с подвалом (её закрывает пол дома)
			if x >= H0.position.x and x + GSTEP <= H0.end.x and z >= H0.position.y and z + GSTEP <= H0.end.y:
				continue
			var p00 := Vector3(x, hs[iz][ix], z)
			var p10 := Vector3(x + GSTEP, hs[iz][ix + 1], z)
			var p01 := Vector3(x, hs[iz + 1][ix], z + GSTEP)
			var p11 := Vector3(x + GSTEP, hs[iz + 1][ix + 1], z + GSTEP)
			st.add_vertex(p00); st.add_vertex(p10); st.add_vertex(p11)
			st.add_vertex(p00); st.add_vertex(p11); st.add_vertex(p01)
	st.index()
	st.generate_normals()
	var mesh := st.commit()
	var body := StaticBody3D.new()
	body.set_meta("ground", "grass")
	add_child(body)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = surface.grass_mat if surface and surface.grass_mat else floor_mat
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)


## Полотно дороги: гравийная лента поверх земли, от поляны до конца деревни.
## Невидимые стены по краям карты (промпт 16.11 05:21): поляна (сетка x -6..70, z -38..38) и долина
## дороги/деревня (x -15..77, z до Z_END) — один общий прямоугольник чуть внутри сеток. Низ стен — на уровне
## земли G: бункер под поляной ниже, его не задевают; у краёв везде холмы, так что стены уходят в землю.
func _bounds() -> void:
	const X_LO := -4.5
	const X_HI := 68.5
	const Z_LO := -36.5
	var z_hi := Z_END - 1.5
	var body := StaticBody3D.new()
	body.name = "MapBounds"
	add_child(body)
	var yc := G - 0.2 + 30.0
	for w in [[Vector3(X_LO - 0.5, yc, (Z_LO + z_hi) / 2.0), Vector3(1.0, 60.0, z_hi - Z_LO + 2.0)],
			[Vector3(X_HI + 0.5, yc, (Z_LO + z_hi) / 2.0), Vector3(1.0, 60.0, z_hi - Z_LO + 2.0)],
			[Vector3((X_LO + X_HI) / 2.0, yc, Z_LO - 0.5), Vector3(X_HI - X_LO + 2.0, 60.0, 1.0)],
			[Vector3((X_LO + X_HI) / 2.0, yc, z_hi + 0.5), Vector3(X_HI - X_LO + 2.0, 60.0, 1.0)]]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = w[1]
		cs.shape = bs
		cs.position = w[0]
		body.add_child(cs)


func _road() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z := ROAD_Z0
	const DZ := 2.0
	while z < VZ1:
		var row: Array = []
		for zz in [z, z + DZ]:
			var pts: Array = []
			for k in 5:
				var x := ROAD_X - ROAD_W + k * ROAD_W * 0.5
				pts.append(Vector3(x, height(x, zz) + 0.035, zz))
			row.append(pts)
		for k in 4:
			var a: Vector3 = row[0][k]
			var b2: Vector3 = row[0][k + 1]
			var c: Vector3 = row[1][k + 1]
			var d: Vector3 = row[1][k]
			for v in [a, c, b2, a, d, c]:
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
		z += DZ
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = road_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# столбы вдоль дороги (провода давно оборваны), сухие деревья и указатель
	var z2 := 30.0
	var k2 := 0
	while z2 < VZ1:
		var px := ROAD_X + 4.2
		var y := height(px, z2)
		_box(Vector3(px - 0.11, y - 0.3, z2 - 0.11), Vector3(px + 0.11, y + 6.0, z2 + 0.11), wood_dark, true)
		_box(Vector3(px - 0.8, y + 5.5, z2 - 0.06), Vector3(px + 0.8, y + 5.62, z2 + 0.06), wood_dark, false)
		if k2 % 3 == 1:
			var b := _box(Vector3(px - 0.08, y + 0.5, z2 - 0.08), Vector3(px + 0.08, y + 5.0, z2 + 0.08), wood_dark, false)
			b.rotation.z = 0.5   # завалившийся
			b.position.x -= 1.4
		z2 += 34.0
		k2 += 1
	for n in 26:
		var tz := rng.randf_range(40.0, VZ1)
		var tx := ROAD_X + rng.randf_range(6.0, 14.0) * (1.0 if rng.randf() < 0.5 else -1.0)
		if tz > VZ0 - 5.0 and absf(tx - ROAD_X) < 16.0:
			continue
		_dead_tree(Vector3(tx, height(tx, tz), tz))


## Указатель у выезда с поляны — ставится только при открытии деревни (village.gd reveal, промпт 16.11 02:18).
func _sign() -> void:
	var sx := ROAD_X - 3.6
	var sy := height(sx, 26.0)
	_box(Vector3(sx - 0.05, sy - 0.2, 25.95), Vector3(sx + 0.05, sy + 2.0, 26.05), wood_dark, true)
	_box(Vector3(sx - 0.7, sy + 1.55, 25.98), Vector3(sx + 0.7, sy + 1.95, 26.02), wood_mat, false)
	var lb := Label3D.new()
	lb.text = "ЗАРЕЧЬЕ  ↑"
	lb.font_size = 40
	lb.pixel_size = 0.006
	lb.modulate = Color(0.85, 0.82, 0.72)
	lb.outline_size = 0
	lb.position = Vector3(sx, sy + 1.75, 25.95)
	lb.rotation.y = PI
	add_child(lb)


func _dead_tree(p: Vector3) -> void:
	var trunk := wood_dark
	var h := rng.randf_range(3.0, 6.0)
	var root := Node3D.new()
	root.position = p
	root.rotation = Vector3(rng.randf_range(-0.08, 0.08), rng.randf() * TAU, rng.randf_range(-0.08, 0.08))
	add_child(root)
	var cm := CylinderMesh.new()
	cm.top_radius = 0.07
	cm.bottom_radius = 0.2
	cm.height = h
	cm.radial_segments = 6
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = trunk
	mi.position.y = h / 2.0 - 0.1
	root.add_child(mi)
	for k in rng.randi_range(2, 4):
		var bm := CylinderMesh.new()
		bm.top_radius = 0.02
		bm.bottom_radius = 0.06
		bm.height = rng.randf_range(1.0, 2.0)
		bm.radial_segments = 5
		var br := MeshInstance3D.new()
		br.mesh = bm
		br.material_override = trunk
		var y := rng.randf_range(h * 0.45, h * 0.9)
		var a := rng.randf() * TAU
		br.position = Vector3(cos(a) * 0.4, y, sin(a) * 0.4)
		br.rotation = Vector3(sin(a) * 0.9, 0, -cos(a) * 0.9)
		root.add_child(br)


# ---------- дома ----------

## Блок по двум углам; collide — со столкновениями.
func _box(a: Vector3, b: Vector3, mat: Material, collide: bool) -> Node3D:
	var size := (b - a).abs()
	var root: Node3D = StaticBody3D.new() if collide else Node3D.new()
	root.position = (a + b) / 2.0
	add_child(root)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	root.add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		root.add_child(cs)
	return root


## Стена вдоль оси (along_x — вдоль X на координате c, иначе вдоль Z) от u0 до u1, высота y0..y1,
## с проёмами holes [[u0, u1, низ, верх], ...] (по возрастанию u).
func _wall(along_x: bool, c: float, u0: float, u1: float, y0: float, y1: float, holes: Array, mat: Material, t := 0.16) -> void:
	var cur := u0
	for h in holes:
		if float(h[0]) > cur:
			_wseg(along_x, c, cur, float(h[0]), y0, y1, mat, t)
		if float(h[2]) > y0:
			_wseg(along_x, c, float(h[0]), float(h[1]), y0, float(h[2]), mat, t)
		if float(h[3]) < y1:
			_wseg(along_x, c, float(h[0]), float(h[1]), float(h[3]), y1, mat, t)
		cur = float(h[1])
	if cur < u1:
		_wseg(along_x, c, cur, u1, y0, y1, mat, t)


func _wseg(along_x: bool, c: float, u0: float, u1: float, y0: float, y1: float, mat: Material, t: float) -> void:
	if along_x:
		_box(Vector3(u0, y0, c - t / 2), Vector3(u1, y1, c + t / 2), mat, true)
	else:
		_box(Vector3(c - t / 2, y0, u0), Vector3(c + t / 2, y1, u1), mat, true)


## Наклонная доска от земли к полу дома у двери: x — стена, side — наружу, z — середина двери.
func _ramp(x: float, side: float, z: float, w: float) -> void:
	var run := 1.0
	var rise := FLOOR_Y - (G - 0.05)
	var ln := sqrt(run * run + rise * rise)
	var body := StaticBody3D.new()
	body.position = Vector3(x + side * run / 2.0, G - 0.05 + rise / 2.0 - 0.04, z)
	body.rotation.z = -side * atan2(rise, run)
	add_child(body)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(ln, 0.08, w)
	mi.mesh = bm
	mi.material_override = wood_dark
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = bm.size
	cs.shape = sh
	body.add_child(cs)


## Деревянный дом: пол, четыре стены с дверным проёмом к улице и окнами, двускатная крыша (иногда с дырой),
## внутри стол, лавка, шкаф. Возвращает точки для лута внутри.
func _house(r: Rect2, door_side: float, hole_floor := Rect2()) -> Array:
	var x0 := r.position.x
	var x1 := r.end.x
	var z0 := r.position.y
	var z1 := r.end.y
	var top := FLOOR_Y + 2.5
	var y0 := G - 0.4
	# пол (с люком, если задан)
	if hole_floor.size == Vector2.ZERO:
		_box(Vector3(x0, G - 0.1, z0), Vector3(x1, FLOOR_Y, z1), wood_mat, true)
	else:
		var hx0 := hole_floor.position.x
		var hx1 := hole_floor.end.x
		var hz0 := hole_floor.position.y
		var hz1 := hole_floor.end.y
		_box(Vector3(x0, G + 0.1, z0), Vector3(hx0, FLOOR_Y, z1), wood_mat, true)
		_box(Vector3(hx1, G + 0.1, z0), Vector3(x1, FLOOR_Y, z1), wood_mat, true)
		_box(Vector3(hx0, G + 0.1, z0), Vector3(hx1, FLOOR_Y, hz0), wood_mat, true)
		_box(Vector3(hx0, G + 0.1, hz1), Vector3(hx1, FLOOR_Y, z1), wood_mat, true)
	var mz := (z0 + z1) / 2.0
	var mx := (x0 + x1) / 2.0
	var dz0 := mz - 0.55 + rng.randf_range(-0.8, 0.8)
	var door := [dz0, dz0 + 1.1, FLOOR_Y, FLOOR_Y + 2.05]
	var win_lo := FLOOR_Y + 0.9
	var win_hi := FLOOR_Y + 1.75
	# стены вдоль Z (x0 и x1): на одной — дверь, на другой — окно
	var front := x0 if door_side < 0.0 else x1
	var back := x1 if door_side < 0.0 else x0
	_wall(false, front, z0, z1, y0, top, [door], wood_mat)
	# крыльцо-пандус к двери (на пол дома в 25 см не «шагнуть»)
	_ramp(front, door_side, (dz0 + dz0 + 1.1) / 2.0, 1.3)
	_wall(false, back, z0, z1, y0, top, [[mz - 0.5, mz + 0.5, win_lo, win_hi]], wood_mat)
	# стены вдоль X (z0 и z1): по окну
	_wall(true, z0, x0 - 0.08, x1 + 0.08, y0, top, [[mx - 0.5, mx + 0.4, win_lo, win_hi]], wood_mat)
	_wall(true, z1, x0 - 0.08, x1 + 0.08, y0, top, [[mx - 0.3, mx + 0.6, win_lo, win_hi]], wood_mat)
	# доски поперёк окон — наспех заколочены
	for wz in [z0, z1]:
		for k in rng.randi_range(0, 2):
			var b := _box(Vector3(mx - 0.6, win_lo + 0.2 + k * 0.35, wz - 0.11), Vector3(mx + 0.6, win_lo + 0.32 + k * 0.35, wz + 0.11), wood_dark, false)
			b.rotation.z = rng.randf_range(-0.25, 0.25)
	# крыша: два ската вдоль Z, конёк по центру
	var w := x1 - x0
	var rise := 1.5
	var slope := sqrt(pow(w / 2.0 + 0.35, 2.0) + rise * rise)
	var ang := atan2(rise, w / 2.0 + 0.35)
	var holed := rng.randf() < 0.5
	for s in [-1.0, 1.0]:
		var sk := Node3D.new()
		sk.position = Vector3(mx + s * (w / 4.0 + 0.09), top + rise / 2.0, mz)
		sk.rotation.z = -s * ang
		add_child(sk)
		var n := 1 if not (holed and s > 0) else 2
		for k in n:
			var len_z := (z1 - z0 + 0.6) if n == 1 else (z1 - z0 + 0.6) * 0.38
			var oz := 0.0 if n == 1 else (-1.0 if k == 0 else 1.0) * (z1 - z0 + 0.6) * 0.31
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(slope, 0.07, len_z)
			mi.mesh = bm
			mi.material_override = roof_mat
			mi.position.z = oz
			sk.add_child(mi)
	# фронтоны
	for gz in [z0, z1]:
		var pm := PrismMesh.new()
		pm.size = Vector3(w, rise, 0.14)
		var gi := MeshInstance3D.new()
		gi.mesh = pm
		gi.material_override = wood_mat
		gi.position = Vector3(mx, top + rise / 2.0, gz)
		add_child(gi)
	# мебель: стол, лавка, шкаф
	var spots: Array = []
	var tx := mx + rng.randf_range(-0.8, 0.8)
	var tz := mz + rng.randf_range(-0.8, 0.8)
	if hole_floor.size != Vector2.ZERO:
		tx = x0 + 1.6
		tz = z1 - 2.0
	_box(Vector3(tx - 0.6, FLOOR_Y + 0.72, tz - 0.4), Vector3(tx + 0.6, FLOOR_Y + 0.78, tz + 0.4), wood_dark, true)
	for lx in [-0.52, 0.52]:
		for lz in [-0.32, 0.32]:
			_box(Vector3(tx + lx - 0.03, FLOOR_Y, tz + lz - 0.03), Vector3(tx + lx + 0.03, FLOOR_Y + 0.72, tz + lz + 0.03), wood_dark, false)
	spots.append(Vector3(tx, FLOOR_Y + 0.85, tz))
	var cx := (x0 + 0.45) if door_side > 0.0 else (x1 - 0.45)
	var cz := z0 + 0.5
	_box(Vector3(cx - 0.3, FLOOR_Y, cz - 0.3), Vector3(cx + 0.3, FLOOR_Y + 1.8, cz + 0.35), wood_dark, true)
	spots.append(Vector3(cx, FLOOR_Y + 0.15, cz + 0.8))
	spots.append(Vector3(mx + rng.randf_range(-1.5, 1.5), FLOOR_Y + 0.15, z1 - 0.7))
	# мусор на полу
	for k in 4:
		var p := Vector3(rng.randf_range(x0 + 0.5, x1 - 0.5), FLOOR_Y + 0.02, rng.randf_range(z0 + 0.5, z1 - 0.5))
		if hole_floor.size != Vector2.ZERO and hole_floor.grow(0.4).has_point(Vector2(p.x, p.z)):
			continue
		var b := _box(p - Vector3(0.5, 0.0, 0.07), p + Vector3(0.5, 0.04, 0.07), wood_dark, false)
		b.rotation.y = rng.randf() * TAU
	# забор у дома, местами повален
	var fx := front + door_side * 3.0
	var fz := z0 - 1.0
	while fz < z1 + 1.0:
		if rng.randf() < 0.75:
			var b := _box(Vector3(fx - 0.04, G - 0.2, fz - 0.06), Vector3(fx + 0.04, G + 1.1, fz + 0.06), wood_dark, false)
			if rng.randf() < 0.25:
				b.rotation.x = rng.randf_range(-0.6, 0.6)
		fz += 0.45
	return spots


## Дом с подвалом: люк в полу у задней стены, лестница вниз, подвал — бетонная комната (другая, чем бункер):
## трубы под потолком, кафель, стеллажи, топчан и новый автомат «ФОРТУНА».
func _basement_house() -> void:
	var hatch := Rect2(ST_X0, ST_Z0, ST_X1 - ST_X0, 3.2)
	var spots := _house(H0, -1.0, hatch)
	marker_pos = Vector3(H0.position.x, FLOOR_Y + 2.9, (H0.position.y + H0.end.y) / 2.0)
	# крышка люка — откинута к стене
	var lid := _box(Vector3(ST_X0, FLOOR_Y, ST_Z0 - 0.05), Vector3(ST_X1, FLOOR_Y + 1.1, ST_Z0 + 0.0), wood_dark, false)
	lid.rotation.x = -0.12
	# шахта лестницы: стенки и торец
	var top := G + 0.1
	_box(Vector3(ST_X0 - 0.16, B - 0.1, ST_Z0 - 0.15), Vector3(ST_X0, top, ROOM.position.y), wall_mat, true)
	_box(Vector3(ST_X1, B - 0.1, ST_Z0 - 0.15), Vector3(ST_X1 + 0.16, top, ROOM.position.y), wall_mat, true)
	_box(Vector3(ST_X0 - 0.16, B - 0.1, ST_Z0 - 0.3), Vector3(ST_X1 + 0.16, top, ST_Z0 - 0.15), wall_mat, true)
	# ступени (вид) и пандус (коллизия)
	var n := 14
	var rise := (FLOOR_Y - B) / n
	var run := ST_LEN / n
	for i in n:
		var zz := ST_Z0 + i * run
		var yy := FLOOR_Y - (i + 1) * rise
		var s := _box(Vector3(ST_X0, yy - 0.25, zz), Vector3(ST_X1, yy, zz + run), floor_mat, false)
		s.set_meta("ground", "concrete")
	var a := Vector2(ST_Z0, FLOOR_Y)
	var b := Vector2(ST_Z0 + ST_LEN, B)
	var dir := (b - a).normalized()
	var ln := a.distance_to(b) + 0.6
	var body := StaticBody3D.new()
	var mid := (a + b) / 2.0
	body.position = Vector3((ST_X0 + ST_X1) / 2.0, mid.y - 0.15, mid.x)
	body.rotation.x = -atan2(dir.y, dir.x)
	add_child(body)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(ST_X1 - ST_X0, 0.3, ln)
	cs.shape = sh
	body.add_child(cs)
	# комната
	var r := ROOM
	var x0 := r.position.x
	var x1 := r.end.x
	var z0 := r.position.y
	var z1 := r.end.y
	var ct := B + B_H
	_box(Vector3(x0 - 0.3, B - 0.3, z0 - 0.3), Vector3(x1 + 0.3, B, z1 + 0.3), floor_mat, true)
	_box(Vector3(x0 - 0.3, ct, z0 - 0.3), Vector3(x1 + 0.3, ct + 0.3, z1 + 0.3), wall_mat, true)
	_wall(true, z0 - 0.1, x0 - 0.3, x1 + 0.3, B, ct, [[ST_X0, ST_X1, B, B + 2.3]], wall_mat, 0.2)
	_wall(true, z1 + 0.1, x0 - 0.3, x1 + 0.3, B, ct, [], wall_mat, 0.2)
	_wall(false, x0 - 0.1, z0, z1, B, ct, [], wall_mat, 0.2)
	_wall(false, x1 + 0.1, z0, z1, B, ct, [], wall_mat, 0.2)
	# потолок над проходом из шахты (между полом дома и комнатой)
	_box(Vector3(ST_X0 - 0.16, B + 2.4, z0 - 0.2), Vector3(ST_X1 + 0.16, ct, z0 + 0.01), wall_mat, false)
	# кафель на полу — светлые и тёмные плитки полосой у стен
	var tile := StandardMaterial3D.new()
	tile.albedo_color = Color(0.33, 0.33, 0.3)
	tile.roughness = 0.4
	var tile_d := StandardMaterial3D.new()
	tile_d.albedo_color = Color(0.17, 0.2, 0.18)
	tile_d.roughness = 0.45
	var tx := x0 + 0.3
	var k := 0
	while tx < x1 - 0.3:
		var tz := z0 + 0.3
		var j := 0
		while tz < z1 - 0.3:
			if rng.randf() > 0.12:   # часть плиток отвалилась
				_box(Vector3(tx + 0.02, B, tz + 0.02), Vector3(tx + 0.58, B + 0.012, tz + 0.58), tile if (k + j) % 2 == 0 else tile_d, false)
			tz += 0.6
			j += 1
		tx += 0.6
		k += 1
	# трубы под потолком
	var pipe := StandardMaterial3D.new()
	pipe.albedo_color = Color(0.25, 0.14, 0.08)
	pipe.metallic = 0.6
	pipe.roughness = 0.6
	for pz in [z0 + 0.35, z0 + 0.6]:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.07
		cm.bottom_radius = 0.07
		cm.height = x1 - x0
		cm.radial_segments = 8
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.material_override = pipe
		mi.position = Vector3((x0 + x1) / 2.0, ct - 0.2, pz)
		mi.rotation.z = PI / 2
		add_child(mi)
	# стеллажи у западной стены, топчан, ящики
	for sz in [z0 + 2.0, z0 + 4.2]:
		_box(Vector3(x0, B, sz - 0.9), Vector3(x0 + 0.5, B + 1.9, sz - 0.86), wood_dark, true)
		_box(Vector3(x0, B, sz + 0.86), Vector3(x0 + 0.5, B + 1.9, sz + 0.9), wood_dark, true)
		for sy in [0.4, 1.0, 1.6]:
			_box(Vector3(x0, B + sy, sz - 0.9), Vector3(x0 + 0.5, B + sy + 0.04, sz + 0.9), wood_dark, true)
		spots.append(Vector3(x0 + 0.25, B + 1.1, sz))
	_box(Vector3(x1 - 0.9, B, z0 + 1.2), Vector3(x1 - 0.05, B + 0.45, z0 + 3.2), wood_mat, true)   # топчан
	_box(Vector3(x1 - 0.85, B + 0.45, z0 + 1.25), Vector3(x1 - 0.1, B + 0.55, z0 + 3.15), _mat(Color(0.24, 0.26, 0.2)), false)
	for c in [Vector3(x1 - 0.6, B, z1 - 0.7), Vector3(x1 - 1.4, B, z1 - 0.6), Vector3(x1 - 0.7, B + 0.6, z1 - 0.7)]:
		_box(c - Vector3(0.3, 0.0, 0.3), c + Vector3(0.3, 0.6, 0.3), wood_mat, true)
	spots.append(Vector3(x1 - 1.0, B + 0.15, z0 + 4.0))
	# лампы
	if level:
		level.lamp_fixture(self, Transform3D(Basis(), Vector3((x0 + x1) / 2.0 - 2.5, ct, (z0 + z1) / 2.0)), 0.75, true, 0.9, false)
		level.lamp_fixture(self, Transform3D(Basis(), Vector3((x0 + x1) / 2.0 + 2.5, ct, z1 - 2.2)), 0.6, false, 0.9, false)
		level.lamp_fixture(self, Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3((ST_X0 + ST_X1) / 2.0, FLOOR_Y + 2.45, ST_Z0 + 1.0)), 0.25, true, 0.5, false)
	loot_spots.append(spots)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


## Колодец в центре улицы и пара брошенных вещей.
func _props() -> void:
	var wc := Vector3(ROAD_X - 5.0, G, 352.0)
	for k in 8:
		var a := TAU * k / 8.0
		var p := wc + Vector3(cos(a), 0, sin(a)) * 0.75
		var b := _box(p - Vector3(0.22, 0.4, 0.12), p + Vector3(0.22, 0.75, 0.12), wall_mat, true)
		b.rotation.y = -a
	_box(wc + Vector3(-0.05, 0.7, -0.8), wc + Vector3(0.05, 2.1, -0.7), wood_dark, false)
	_box(wc + Vector3(-0.05, 0.7, 0.7), wc + Vector3(0.05, 2.1, 0.8), wood_dark, false)
	_box(wc + Vector3(-0.05, 2.0, -0.85), wc + Vector3(0.05, 2.1, 0.85), wood_dark, false)
	# перевёрнутая телега и бочки
	var cart := _box(Vector3(36.0, G, 362.0), Vector3(38.5, G + 0.5, 363.4), wood_dark, true)
	cart.rotation = Vector3(0.0, 0.4, 0.15)
	for p in [Vector3(26.0, G, 337.0), Vector3(26.6, G, 337.4), Vector3(36.4, G, 378.0)]:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.3
		cm.bottom_radius = 0.3
		cm.height = 0.9
		cm.radial_segments = 10
		var body := StaticBody3D.new()
		body.position = p + Vector3(0, 0.45, 0)
		add_child(body)
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.material_override = roof_mat
		body.add_child(mi)
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = 0.3
		sh.height = 0.9
		cs.shape = sh
		body.add_child(cs)
