extends StaticBody3D
# Часть jar.gd: константы, состояние, форма (профиль и вращение), осколки, звуки.
const Fx := preload("res://scripts/core/fx.gd")
const Chest := preload("res://scripts/world/chest.gd")
const KINDS := ["jar", "jar", "amphora"]  # только керамика, без колб (промпт 14.11 16:46)
const RATE := 22050

var kind := "jar"
var size := 1.0
var seed_ := 0
var broken := false
var game
var hp := 1.0
var mats: Array[Material] = []
var body_col := Color(0.4, 0.25, 0.16)
var shards: Array = []       # [[узел, скорость, угл. скорость]] — пока летят
var max_r := 0.15
var height := 0.4

static var _snd_cache := {}


## Случайный кувшин/колба: вид, размер, рисунок.
static func random_params(rng: RandomNumberGenerator) -> Dictionary:
	var k: String = KINDS[rng.randi() % KINDS.size()]
	var s := rng.randf_range(0.65, 1.6) if k in ["jar", "amphora"] else rng.randf_range(0.6, 1.2)
	return {"kind": k, "size": s, "seed": rng.randi() % 100000}


## Профиль: точки (радиус, высота) снизу вверх, в «базовом» размере (до size).
func _profile(r: RandomNumberGenerator) -> Array:
	var p: Array = []
	match kind:
		"jar":
			var belly := r.randf_range(0.13, 0.18)
			var bh := r.randf_range(0.12, 0.2)
			var neck := r.randf_range(0.045, 0.07)
			var top := r.randf_range(0.32, 0.42)
			p = [Vector2(0.0, 0.0), Vector2(belly * 0.6, 0.0), Vector2(belly * 0.85, bh * 0.35), Vector2(belly, bh),
				Vector2(belly * 0.85, bh + (top - bh) * 0.45), Vector2(neck * 1.3, top * 0.82), Vector2(neck, top * 0.9),
				Vector2(neck * 1.35, top), Vector2(neck * 1.1, top + 0.01), Vector2(neck * 0.8, top - 0.01)]
			body_col = [Color(0.38, 0.22, 0.14), Color(0.3, 0.27, 0.22), Color(0.42, 0.3, 0.18), Color(0.25, 0.2, 0.17)][r.randi() % 4]
		"amphora":
			var belly := r.randf_range(0.1, 0.13)
			var top := r.randf_range(0.5, 0.65)
			var neck := r.randf_range(0.04, 0.055)
			p = [Vector2(0.0, 0.0), Vector2(0.05, 0.0), Vector2(belly * 0.7, top * 0.15), Vector2(belly, top * 0.45),
				Vector2(belly * 0.8, top * 0.7), Vector2(neck, top * 0.85), Vector2(neck * 1.4, top), Vector2(neck * 1.1, top + 0.01), Vector2(neck * 0.8, top - 0.01)]
			body_col = [Color(0.4, 0.24, 0.15), Color(0.33, 0.29, 0.23), Color(0.28, 0.18, 0.12)][r.randi() % 3]
		"flask":
			var br := r.randf_range(0.1, 0.14)
			var top := br * 2.0 + r.randf_range(0.12, 0.2)
			var neck := r.randf_range(0.025, 0.035)
			for k in 9:
				var a := -PI / 2.0 + PI * 0.9 * k / 8.0
				p.append(Vector2(maxf(cos(a) * br, 0.0) if k > 0 else 0.0, br + sin(a) * br))
			p.append(Vector2(neck, br * 2.0))
			p.append(Vector2(neck, top))
			p.append(Vector2(neck * 1.4, top + 0.01))
		_:  # cone
			var base := r.randf_range(0.11, 0.15)
			var top := r.randf_range(0.28, 0.36)
			var neck := r.randf_range(0.028, 0.038)
			p = [Vector2(0.0, 0.0), Vector2(base, 0.0), Vector2(base, 0.015), Vector2(neck, top * 0.7),
				Vector2(neck, top), Vector2(neck * 1.4, top + 0.01)]
	max_r = 0.0
	height = 0.0
	for v in p:
		max_r = maxf(max_r, (v as Vector2).x)
		height = maxf(height, (v as Vector2).y)
	return p


## Тело вращения из профиля. У керамики — полосы глазури по высоте (цвет по вершинам), у колб — стекло + жидкость.
func _lathe(prof: Array, r: RandomNumberGenerator) -> void:
	var glass := kind in ["flask", "cone"]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	if glass:
		m.albedo_color = Color(0.6, 0.7, 0.66, 0.32)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.08
		m.metallic_specular = 0.9
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	else:
		m.roughness = 0.75
	mats.append(m)
	var bands: Array = []
	for k in r.randi_range(1, 3):
		bands.append([r.randf_range(0.25, 0.85), r.randf_range(0.03, 0.07)])
	var band_col := body_col.darkened(0.45) if r.randf() < 0.5 else body_col.lightened(0.25)
	var mesh := _revolve(prof, func(t: float) -> Color:
		if glass:
			return Color(1, 1, 1)
		for b in bands:
			if absf(t - float(b[0])) < float(b[1]):
				return band_col
		return body_col)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.scale = Vector3.ONE * size
	mi.position.y = 0.006  # дно чуть над полом — без мерцания пересечения (промпт 14.11 17:26)
	add_child(mi)
	if glass:
		# мутная жидкость внутри (чуть светится — заметно в темноте)
		var fill := r.randf_range(0.35, 0.7)
		var liq_col: Color = [Color(0.35, 0.6, 0.15), Color(0.7, 0.4, 0.08), Color(0.55, 0.1, 0.08), Color(0.3, 0.45, 0.5)][r.randi() % 4]
		var lp: Array = []
		var top_y := height * fill
		for v in prof:
			var pv: Vector2 = v
			if pv.y <= top_y:
				lp.append(Vector2(pv.x * 0.9, pv.y + 0.004))
		if lp.size() >= 2:
			lp.append(Vector2((lp[lp.size() - 1] as Vector2).x, top_y))
			lp.append(Vector2(0.0, top_y))
			var lm := StandardMaterial3D.new()
			lm.albedo_color = Color(liq_col.r, liq_col.g, liq_col.b, 0.8)
			lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			lm.emission_enabled = true
			lm.emission = liq_col
			lm.emission_energy_multiplier = 0.35
			lm.roughness = 0.3
			mats.append(lm)
			var li := MeshInstance3D.new()
			li.mesh = _revolve(lp, func(_t: float) -> Color: return Color(1, 1, 1))
			li.material_override = lm
			li.scale = Vector3.ONE * size
			add_child(li)
		body_col = liq_col


func _revolve(prof: Array, col_at: Callable) -> ArrayMesh:
	const SEG := 14
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := maxf((prof[prof.size() - 1] as Vector2).y, 0.01)
	for i in prof.size() - 1:
		var a: Vector2 = prof[i]
		var b: Vector2 = prof[i + 1]
		var ca: Color = col_at.call(a.y / h)
		var cb: Color = col_at.call(b.y / h)
		for k in SEG:
			var t0 := TAU * k / SEG
			var t1 := TAU * (k + 1) / SEG
			var a0 := Vector3(cos(t0) * a.x, a.y, sin(t0) * a.x)
			var a1 := Vector3(cos(t1) * a.x, a.y, sin(t1) * a.x)
			var b0 := Vector3(cos(t0) * b.x, b.y, sin(t0) * b.x)
			var b1 := Vector3(cos(t1) * b.x, b.y, sin(t1) * b.x)
			# порядок вершин — против часовой снаружи: лицевая сторона наружу (иначе видна изнанка и «прозрачность», промпт 19:16)
			for v in [[a0, ca], [b1, cb], [b0, cb], [a0, ca], [a1, ca], [b1, cb]]:
				st.set_color(v[1])
				st.add_vertex(v[0])
	st.generate_normals()
	return st.commit()


func _shard_mesh(r: RandomNumberGenerator, glass: bool) -> MeshInstance3D:
	var pm := PrismMesh.new()
	var a := r.randf_range(0.025, 0.06) * size
	pm.size = Vector3(a, a * r.randf_range(0.6, 1.4), 0.006 if glass else 0.012)
	pm.left_to_right = r.randf()
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	if glass:
		m.albedo_color = Color(0.6, 0.7, 0.66, 0.45)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.05
		m.metallic_specular = 0.9
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	else:
		m.albedo_color = body_col if r.randf() < 0.6 else body_col.darkened(0.3)
		m.roughness = 0.8
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.rotation = Vector3(r.randf() * TAU, r.randf() * TAU, r.randf() * TAU)
	return mi


## Осколок лежит плашмя на полу (в бункере) или земле (на поляне): почти без наклона и целиком над поверхностью —
## иначе его грани пересекаются с полом и мерцают (промпт 14.11 18:16).
func _lay_flat(n: MeshInstance3D, tilt: float) -> void:
	var pm := n.mesh as PrismMesh
	var half := maxf(pm.size.x, pm.size.y) * 0.5
	n.rotation = Vector3(-PI / 2.0 + tilt, n.rotation.y, 0)
	n.position.y = _ground_y(n.position) + pm.size.z * 0.5 + absf(tilt) * half + 0.005


## Высота пола под точкой (в координатах кувшина): луч вниз по коллизиям уровня.
func _ground_y(p: Vector3) -> float:
	if not is_inside_tree():
		return 0.0
	var g := to_global(p)
	var q := PhysicsRayQueryParameters3D.create(g + Vector3(0, 0.5, 0), g - Vector3(0, 1.5, 0))
	q.collision_mask = 1
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return 0.0
	return to_local(hit.position).y


# ---------- процедурные звуки ----------

## Звон стекла (glass) или хруст керамики; crack — только треск без разлёта.
static func _sound(glass: bool, crack: bool) -> AudioStreamWAV:
	var key := "%s_%s" % [glass, crack]
	if _snd_cache.has(key):
		return _snd_cache[key]
	var r := RandomNumberGenerator.new()
	r.seed = 1700 + (1 if glass else 0) + (2 if crack else 0)
	var dur := 0.25 if crack else (1.0 if glass else 0.7)
	var n := int(RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	# звонкие осколки: набор высоких призвуков, каждый со своим моментом удара (осколки падают вразнобой)
	var tones: Array = []
	for k in (3 if crack else (14 if glass else 6)):
		var f := r.randf_range(2600.0, 6800.0) if glass else r.randf_range(900.0, 2600.0)
		tones.append([f, r.randf_range(0.0, 0.03 if crack else (0.5 if glass else 0.3)), r.randf_range(18.0, 40.0) if glass else r.randf_range(35.0, 70.0), r.randf_range(0.3, 1.0)])
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var w := r.randf() * 2.0 - 1.0
		lp += (w - lp) * 0.08
		lp2 += (lp - lp2) * 0.2
		var v := 0.0
		# удар: у керамики — глухой «бум» и хруст, у стекла — короткий резкий всплеск
		var e0 := minf(t / 0.002, 1.0) * exp(-t * (60.0 if glass else 25.0))
		v += (w * 0.6 if glass else lp2 * 4.0 + w * 0.35) * e0
		# хруст: редкие щелчки
		if r.randf() < (0.02 if glass else 0.05) * exp(-t * 8.0):
			v += r.randf_range(-0.8, 0.8)
		for tn in tones:
			var tt: float = t - float(tn[1])
			if tt > 0.0:
				v += sin(TAU * float(tn[0]) * tt) * exp(-tt * float(tn[2])) * float(tn[3]) * 0.25
		buf[i] = v
	var peak := 0.0001
	for x in buf:
		peak = maxf(peak, absf(x))
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var fade := minf(1.0, float(n - i) / (RATE * 0.03))
		data.encode_s16(i * 2, int(clampf(buf[i] / peak * 0.85 * fade, -1.0, 1.0) * 32000.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = RATE
	st.data = data
	_snd_cache[key] = st
	return st
