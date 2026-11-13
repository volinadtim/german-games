extends Node3D
## Битое стекло на полу бункера (промпты 23:58 / 00:00): каждая новая игра раскидывает 3 кучки осколков
## в случайных местах (не у старта и не у автоматов/ящиков). Осколки крупные и тусклые.
## Наступил — game.gd (_glass): урон и кровотечение. Метла с совком (магазин) выметает кучку (sweep).

const SPOTS := 3

var spots: Array = []      # [[Vector3 центр, радиус], ...]; выметенные удаляются
var piles: Array = []      # узел-кучка на каждый spot
var glass_mat: StandardMaterial3D
var glint_mat: StandardMaterial3D

## места, где кучки не ставим (старт, автоматы, сейф, ящики, манекен)
const AVOID := [Vector3(-10.5, 0, 0), Vector3(-6.0, 0, 8.5), Vector3(-4.0, 0, 8.4), Vector3(11.5, 0, 7.0),
	Vector3(-3.0, 0, -8.5), Vector3(9.0, 0, -8.5), Vector3(-11.5, 0, 3.2), Vector3(2.2, 0, -2.15),
	Vector3(2.2, 0, 2.15), Vector3(-8.0, 0, -3.6), Vector3(-7.0, 0, 8.7)]


func _ready() -> void:
	glass_mat = StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.5, 0.58, 0.56, 0.45)
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.roughness = 0.08
	glass_mat.metallic_specular = 0.7
	glass_mat.emission_enabled = true
	glass_mat.emission = Color(0.45, 0.52, 0.5)
	glass_mat.emission_energy_multiplier = 0.06
	glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	glint_mat = StandardMaterial3D.new()
	glint_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glint_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glint_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glint_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	glint_mat.albedo_color = Color(0.9, 0.95, 1.0, 0.22)


## Новая игра: случайные места.
func generate() -> void:
	var list: Array = []
	var tries := 0
	while list.size() < SPOTS and tries < 300:
		tries += 1
		var p := _random_floor_point()
		var ok := true
		for a in AVOID:
			if Vector2(p.x - a.x, p.z - a.z).length() < (3.0 if a == AVOID[0] else 1.6):
				ok = false
		for s in list:
			if (s[0] as Vector3).distance_to(p) < 4.0:
				ok = false
		if ok:
			list.append([p, randf_range(0.45, 0.75)])
	build(list)


## Точка на полу: в коридоре или в одной из четырёх комнат, подальше от стен и проёмов.
func _random_floor_point() -> Vector3:
	if randf() < 0.35:
		return Vector3(randf_range(-10.5, 10.5), 0, randf_range(-0.8, 0.8))
	var sx := -1.0 if randf() < 0.5 else 1.0
	var sz := -1.0 if randf() < 0.5 else 1.0
	return Vector3(sx * randf_range(1.0, 10.8), 0, sz * randf_range(2.6, 8.0))


func build(list: Array) -> void:
	for p in piles:
		if is_instance_valid(p):
			p.queue_free()
	piles = []
	spots = []
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.012, 0.012)
	for s in list:
		var c: Vector3 = s[0]
		var r: float = s[1]
		var pile := Node3D.new()
		add_child(pile)
		var count := int(r * 16)
		for j in count:
			var pm := PrismMesh.new()
			var a := rng.randf_range(0.04, 0.09)
			pm.size = Vector3(a, a * rng.randf_range(0.8, 1.8), 0.004)
			pm.left_to_right = rng.randf()
			var mi := MeshInstance3D.new()
			mi.mesh = pm
			mi.material_override = glass_mat
			var off: Vector2 = Vector2.from_angle(rng.randf() * TAU) * r * sqrt(rng.randf())
			mi.position = c + Vector3(off.x, 0.003, off.y)
			mi.rotation = Vector3(-PI / 2 + rng.randf_range(-0.08, 0.08), rng.randf() * TAU, 0)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			pile.add_child(mi)
			if j % 7 == 0:
				var gl := MeshInstance3D.new()
				gl.mesh = quad
				gl.material_override = glint_mat
				gl.position = mi.position + Vector3(0, 0.012, 0)
				gl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				pile.add_child(gl)
		spots.append([c, r])
		piles.append(pile)


## Для сохранения: [[x, z, r], ...]
func to_save() -> Array:
	var out: Array = []
	for s in spots:
		out.append([(s[0] as Vector3).x, (s[0] as Vector3).z, s[1]])
	return out


func from_save(a: Array) -> void:
	var list: Array = []
	for s in a:
		list.append([Vector3(float(s[0]), 0, float(s[1])), float(s[2])])
	build(list)


## Ближайшая кучка в радиусе reach от точки, -1 — нет.
func nearest(p: Vector3, reach: float) -> int:
	var best := -1
	var bd := reach
	for i in spots.size():
		var c: Vector3 = spots[i][0]
		var d := Vector2(p.x - c.x, p.z - c.z).length() - float(spots[i][1])
		if d < bd:
			bd = d
			best = i
	return best


## Вымести кучку: осколки «уезжают» в совок и пропадают.
func sweep(i: int) -> void:
	var pile: Node3D = piles[i]
	var c: Vector3 = spots[i][0]
	piles.remove_at(i)
	spots.remove_at(i)
	var tw := pile.create_tween().set_parallel()
	for ch in pile.get_children():
		tw.tween_property(ch, "position", c + Vector3(0, 0.02, 0), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(ch, "scale", Vector3.ONE * 0.2, 0.5)
	tw.chain().tween_callback(pile.queue_free)
