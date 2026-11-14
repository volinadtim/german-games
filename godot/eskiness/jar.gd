extends StaticBody3D
## Кувшин или колба — бьющиеся «лутбоксы» (промпт 14.11 00:08). Расставляет их game.gd случайно каждую игру.
## Форма точится по профилю (как на гончарном круге), размер и пропорции — случайные от seed:
##   jar     — пузатый глиняный кувшин с горлышком и полосками глазури;
##   amphora — высокий узкий кувшин;
##   flask   — круглая колба с длинным горлом, внутри мутная светящаяся жидкость;
##   cone    — коническая колба (как в лаборатории), тоже с жидкостью.
## Удар кулаком или оружием (take_hit) — разбивается: звон стекла или хруст керамики, осколки разлетаются
## и остаются лежать; лут (всегда монеты + несколько вещей) вылетает на пол. Большие кувшины выдерживают один удар.

const Fx := preload("res://fx.gd")
const Chest := preload("res://chest.gd")
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


func setup(params: Dictionary) -> void:
	kind = params["kind"]
	size = float(params["size"])
	seed_ = int(params["seed"])
	if kind == "flask" or kind == "cone":  # старые сейвы с колбами — теперь керамика
		kind = "jar" if kind == "flask" else "amphora"
		size = clampf(size * 1.2, 0.65, 1.6)


func to_save() -> Array:
	return [position.x, position.y, position.z, rotation.y, kind, size, seed_, broken]


func _ready() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed_
	var prof := _profile(r)
	_lathe(prof, r)
	hp = 2.0 if kind in ["jar", "amphora"] and size > 1.25 else 1.0
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = max_r * size * 0.9
	cyl.height = height * size
	cs.shape = cyl
	cs.position.y = height * size / 2.0
	add_child(cs)
	if broken:
		_hide_body()
		_scatter_static(r)


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
			for v in [[a0, ca], [b0, cb], [b1, cb], [a0, ca], [b1, cb], [a1, ca]]:
				st.set_color(v[1])
				st.add_vertex(v[0])
	st.generate_normals()
	return st.commit()


# ---------- разбивание ----------

func take_hit(_dmg: float, dir: Vector3) -> void:
	if broken:
		return
	if game:
		game.weapon_hit()
	hp -= 1.0
	if hp > 0.0:
		# треснул, но держится: качнулся и звякнул
		var tw := create_tween()
		tw.tween_property(self, "rotation:z", 0.12, 0.05)
		tw.tween_property(self, "rotation:z", 0.0, 0.2).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		_play(_sound(kind in ["flask", "cone"], true), -12.0)
		return
	_shatter(dir)


func _shatter(dir: Vector3) -> void:
	broken = true
	_hide_body()
	var glass := kind in ["flask", "cone"]
	_play(_sound(glass, false), -6.0)
	Fx.dust_burst(get_parent(), global_position + Vector3(0, height * size * 0.5, 0), body_col.lightened(0.2) if not glass else Color(0.6, 0.65, 0.6), 18)
	# осколки
	var r := RandomNumberGenerator.new()
	r.randomize()
	var flat := Vector3(dir.x, 0, dir.z).normalized()
	for k in int(8 + 6 * size):
		var sh := _shard_mesh(r, glass)
		sh.position = Vector3(r.randf_range(-max_r, max_r), r.randf_range(0.05, height), r.randf_range(-max_r, max_r)) * size
		add_child(sh)
		var v := (Vector3(r.randf_range(-1, 1), r.randf_range(0.6, 1.6), r.randf_range(-1, 1)) * 1.6 + flat * 1.5)
		var w := Vector3(r.randf_range(-12, 12), r.randf_range(-12, 12), r.randf_range(-12, 12))
		shards.append([sh, global_transform.basis.inverse() * v, w])
	# лут сразу вылетает на пол (без окна — промпт 14.11 16:43), подбирается, когда подойдёшь
	if game:
		var pos := global_position + Vector3(0, 0.15, 0)
		for it in _roll(r):
			game.spawn_loot(it[0], it[1], pos, Vector3(0, 2.2, 0) + flat * 0.8, 1.0)


func _hide_body() -> void:
	for c in get_children():
		if c is MeshInstance3D:
			c.visible = false
		if c is CollisionShape3D:
			c.set_deferred("disabled", true)


## Лут кувшина: всегда монеты + 2–4 вещи (большой — ещё одна). Пусто не бывает.
func _roll(r: RandomNumberGenerator) -> Array:
	var out: Array = [["coin", r.randi_range(4, 10) + int(6 * maxf(size - 1.0, 0.0))]]
	# сколько вещей — по правке Германа: 2 / 3 / 4
	var roll := r.randf()
	var n := 2 if roll < 0.22 else (3 if roll < 0.8 else 4)
	if size > 1.25:
		n += 1
	var total := 0
	for row in Chest.LOOT:
		total += int(row[1])
	for k in n:
		var pick := r.randi_range(0, total - 1)
		for row in Chest.LOOT:
			pick -= int(row[1])
			if pick < 0:
				out.append([row[0], r.randi_range(int(row[2]), int(row[3]))])
				break
	return out


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


## Загруженный из сейва разбитый кувшин: осколки просто лежат вокруг.
func _scatter_static(r: RandomNumberGenerator) -> void:
	var glass := kind in ["flask", "cone"]
	for k in int(6 + 5 * size):
		var sh := _shard_mesh(r, glass)
		var off := Vector2.from_angle(r.randf() * TAU) * r.randf_range(0.05, 0.7)
		sh.position = Vector3(off.x, 0.006, off.y)
		sh.rotation = Vector3(-PI / 2.0 + r.randf_range(-0.2, 0.2), r.randf() * TAU, 0)
		add_child(sh)


func _process(delta: float) -> void:
	if shards.is_empty():
		return
	for i in range(shards.size() - 1, -1, -1):
		var s: Array = shards[i]
		var n: MeshInstance3D = s[0]
		var v: Vector3 = s[1]
		v.y -= 9.8 * delta
		n.position += v * delta
		n.rotation += (s[2] as Vector3) * delta
		if n.position.y <= 0.006:
			# упал: лежит плашмя
			n.position.y = 0.006
			n.rotation = Vector3(-PI / 2.0 + randf_range(-0.2, 0.2), n.rotation.y, 0)
			shards.remove_at(i)
		else:
			s[1] = v


func _play(stream: AudioStreamWAV, db: float) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = db
	p.unit_size = 4.0
	p.pitch_scale = randf_range(0.85, 1.15) / sqrt(size)
	add_child(p)
	p.position.y = 0.2
	p.finished.connect(p.queue_free)
	p.play()


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
