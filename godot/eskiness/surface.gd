@tool
extends Node3D
## Выход из бункера и поверхность.
##   Из восточного торца коридора (x = 12) — проём, за ним лестничный марш вверх (по ступеням — пологий пандус
##   для коллизии) и бетонная будка-выход на поляне. Поляна с центром CENTER, по краям холмы, мрачное красное небо.
##   Окружение (свет, туман, небо) плавно переключается, когда камера выходит наружу, — внутри бункера остаётся темно.
## Создаётся из level.gd (_ready).

const FlickerLight := preload("res://flicker_light.gd")
const GrassShader := preload("res://grass.gdshader")
const SkyShader := preload("res://sky.gdshader")

const G := 4.0                         # уровень земли
const CENTER := Vector3(31.0, G, 0.0)  # центр поляны
const MEADOW_R := 14.0                 # ровная часть поляны, где бродят враги
const TW := 1.1                        # полуширина прохода лестницы
const X_WALL := 12.15                  # наружная грань торцевой стены бункера
const X_RAMP0 := 13.0                  # первая ступень
const STEP_RUN := 0.4
const STEP_RISE := 0.25
const X_TOP := 19.0                    # верхняя площадка (x 19..21)
const X_OUT := 21.0                    # выход из будки на поляну
const HUT_X0 := 14.6                   # западная стена будки
const HUT_H := 2.4                     # высота будки над землёй (до потолка)
## прямоугольник будки (x0, x1, z0, z1) — враги туда не заходят
const HUT := Rect2(14.4, -2.2, 7.0, 4.4)
## старая машина (car.gd): к северо-востоку от выхода из будки, между руинами; перед — по CAR_YAW
const CAR_POS := Vector3(31.0, G, 9.5)
const CAR_YAW := 0.35
const CAR_R := 3.0                     # радиус, где не ставим кувшины и арматуру

var level: Node3D
var env: Environment
var wall_mat: Material
var floor_mat: Material
var grass_mat: ShaderMaterial
var sun: DirectionalLight3D
var wind: AudioStreamPlayer
var wind_pb: AudioStreamGeneratorPlayback
var w_lp := 0.0
var w_lp2 := 0.0
var w_t := 0.0
var out_k := 0.0
var rng := RandomNumberGenerator.new()
var hn := FastNoiseLite.new()
var hn2 := FastNoiseLite.new()

# окружение: внутри (как в level.gd) и снаружи
const WARM := Color(1.0, 0.78, 0.52)
const IN_AMB := Color(0.62, 0.55, 0.46)
const OUT_AMB := Color(0.5, 0.46, 0.38)
const IN_FOG := Color(0.04, 0.04, 0.045)
const OUT_FOG := Color(0.15, 0.08, 0.065)


static func in_hut(p: Vector3, margin := 0.0) -> bool:
	return p.x > HUT.position.x - margin and p.x < HUT.end.x + margin \
		and p.z > HUT.position.y - margin and p.z < HUT.end.y + margin


## Точка на поляне, куда можно дойти поверху (не в будке и не под землёй).
static func on_meadow(p: Vector3) -> bool:
	return p.y > G - 0.6 and not in_hut(p)


func _ready() -> void:
	name = "Surface"
	rng.seed = 91
	hn.seed = 5
	hn.frequency = 0.045
	hn.fractal_octaves = 2
	hn2.seed = 9
	hn2.frequency = 0.11
	hn2.fractal_octaves = 1
	wall_mat = level.wall_mat
	floor_mat = level.floor_mat
	grass_mat = ShaderMaterial.new()
	grass_mat.shader = GrassShader
	for p in ["noise_big", "noise_big_px", "noise_fine_px", "noise_cell_px"]:
		grass_mat.set_shader_parameter(p, wall_mat.get_shader_parameter(p))
	_stairs()
	_hut()
	_ground()
	_tufts()
	_ruins()
	_sky_and_sun()
	if not Engine.is_editor_hint():
		_wind()


# ---------- лестница ----------

func _stairs() -> void:
	var n := int(round(G / STEP_RISE)) - 1          # ступеней до площадки
	# нижняя площадка за проёмом
	_vbox(Vector3(X_WALL, -0.3, -TW), Vector3(X_RAMP0, 0.0, TW), floor_mat, true)
	# ступени (только вид)
	for i in n:
		var x0 := X_RAMP0 + i * STEP_RUN
		var top := (i + 1) * STEP_RISE
		_vbox(Vector3(x0, top - 0.55, -TW), Vector3(x0 + STEP_RUN, top, TW), floor_mat, false)
	# верхняя площадка: вид от края последней ступени, коллизия — от конца пандуса
	_vbox(Vector3(X_TOP, G - 0.4, -TW), Vector3(X_OUT, G, TW), floor_mat, false)
	_col(Vector3(X_TOP + 0.2, G - 0.4, -TW), Vector3(X_OUT + 0.4, G, TW))
	# пандус через середины подступёнков: ноги не проваливаются и не висят над ступенями
	var a := Vector2(X_RAMP0 - STEP_RUN * 0.5, 0.0)
	var b := Vector2(X_TOP + STEP_RUN * 0.5, G)
	var dir := (b - a).normalized()
	a -= dir * 0.6
	var ang := atan2(dir.y, dir.x)
	var ln := a.distance_to(b)
	var nrm := Vector2(-dir.y, dir.x)
	var c := (a + b) / 2.0 - nrm * 0.15
	var body := StaticBody3D.new()
	body.position = Vector3(c.x, c.y, 0)
	body.rotation.z = ang
	add_child(body)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(ln, 0.3, TW * 2.0)
	cs.shape = sh
	body.add_child(cs)
	# стены прохода (подземная часть)
	for s in [-1.0, 1.0]:
		var z0 := TW if s > 0 else -2.0
		var z1 := 2.0 if s > 0 else -TW
		_vbox(Vector3(X_WALL, -0.3, z0), Vector3(X_OUT, G - 0.05, z1), wall_mat, true)
	# потолок ступеньками, пока проход под землёй
	_vbox(Vector3(X_WALL, 2.6, -TW), Vector3(X_RAMP0, 2.9, TW), wall_mat, true)
	var x := X_RAMP0
	var i := 0
	while x < HUT_X0 + 0.39:
		var y := (i + 1) * STEP_RISE + 2.4
		_vbox(Vector3(x, y, -TW), Vector3(x + STEP_RUN, minf(y + 0.3, G - 0.05), TW), wall_mat, true)
		x += STEP_RUN
		i += 1
	# лампа над серединой марша
	_lamp(Vector3(16.6, G + HUT_H - 0.1, 0), 0.55, true)
	_lamp(Vector3(12.6, 2.56, 0), 0.35, false)


# ---------- будка-выход ----------

func _hut() -> void:
	var top := G + HUT_H
	var x_in := HUT_X0 + 0.4                     # внутренняя грань западной стены
	_vbox(Vector3(HUT_X0, G - 0.6, -2.0), Vector3(x_in, top, 2.0), wall_mat, true)
	for s in [-1.0, 1.0]:
		var z0 := TW if s > 0 else -2.0
		var z1 := 2.0 if s > 0 else -TW
		_vbox(Vector3(HUT_X0, G - 0.4, z0), Vector3(X_OUT, top, z1), wall_mat, true)
	# крыша с напуском и козырёк
	_vbox(Vector3(HUT_X0 - 0.2, top, -2.2), Vector3(X_OUT + 0.35, top + 0.35, 2.2), wall_mat, true)
	# порог и обломки у входа
	_vbox(Vector3(X_OUT - 0.1, G - 0.2, -TW - 0.1), Vector3(X_OUT + 0.25, G + 0.06, TW + 0.1), wall_mat, false)
	for k in 5:
		var sz := Vector3(rng.randf_range(0.15, 0.5), rng.randf_range(0.08, 0.3), rng.randf_range(0.15, 0.5))
		var p := Vector3(X_OUT + rng.randf_range(0.3, 1.6), G + sz.y / 2 - 0.05, (2.4 + rng.randf_range(0, 1.2)) * (1.0 if k % 2 == 0 else -1.0))
		var m := _vbox(p - sz / 2, p + sz / 2, wall_mat, true)
		m.rotation.y = rng.randf() * TAU


# ---------- земля ----------

func height(x: float, z: float) -> float:
	var r := Vector2(x - CENTER.x, z - CENTER.z).length()
	var hill := smoothstep(MEADOW_R + 3.0, MEADOW_R + 16.0, r) * (7.0 + 5.0 * hn.get_noise_2d(x, z))
	var d_hut := _rect_dist(x, z)
	var bump := (hn2.get_noise_2d(x, z) * 0.3 + hn.get_noise_2d(x * 2.0, z * 2.0) * 0.25) * smoothstep(1.5, 6.0, d_hut)
	return G + hill + bump


func _rect_dist(x: float, z: float) -> float:
	var dx := maxf(maxf(HUT.position.x - x, x - HUT.end.x), 0.0)
	var dz := maxf(maxf(HUT.position.y - z, z - HUT.end.y), 0.0)
	return Vector2(dx, dz).length()


func _ground() -> void:
	const STEP := 1.0
	const X0 := -6.0
	const Z0 := -38.0
	const NX := 76
	const NZ := 76
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in NZ:
		for ix in NX:
			var x := X0 + ix * STEP
			var z := Z0 + iz * STEP
			# дыра над лестницей (её закрывает будка)
			if x >= 15.0 and x < X_OUT and z >= -2.0 and z < 2.0:
				continue
			var p00 := Vector3(x, height(x, z), z)
			var p10 := Vector3(x + STEP, height(x + STEP, z), z)
			var p01 := Vector3(x, height(x, z + STEP), z + STEP)
			var p11 := Vector3(x + STEP, height(x + STEP, z + STEP), z + STEP)
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
	mi.material_override = grass_mat
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)


## Пучки травы: крестики из двух квадов с пиксельной текстурой травинок.
func _tufts() -> void:
	var tex := _tuft_tex()
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	m.metallic_specular = 0.1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 2:
		var ang := k * PI / 2.0 + PI / 4.0
		var d := Vector3(cos(ang), 0, sin(ang)) * 0.3
		var a := -d
		var b := d
		var h := Vector3(0, 0.45, 0)
		st.set_normal(Vector3.UP)
		for v in [[a, Vector2(0, 1)], [b, Vector2(1, 1)], [b + h, Vector2(1, 0)], [a, Vector2(0, 1)], [b + h, Vector2(1, 0)], [a + h, Vector2(0, 0)]]:
			st.set_uv(v[1])
			st.set_normal(Vector3.UP)
			st.add_vertex(v[0])
	var mesh := st.commit()
	mesh.surface_set_material(0, m)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	var xf: Array[Transform3D] = []
	var cols: Array[Color] = []
	var palette := [Color(0.42, 0.54, 0.2), Color(0.6, 0.6, 0.24), Color(0.48, 0.56, 0.22), Color(0.64, 0.6, 0.3)]
	var tries := 0
	while xf.size() < 4500 and tries < 20000:
		tries += 1
		var p := CENTER + Vector3(rng.randf_range(-30, 30), 0, rng.randf_range(-30, 30))
		var r := Vector2(p.x - CENTER.x, p.z - CENTER.z).length()
		if r > 30.0 or _rect_dist(p.x, p.z) < 0.6:
			continue
		# гуще кучками: шум решает, где трава выше и плотнее
		var dens := hn2.get_noise_2d(p.x * 0.7, p.z * 0.7) * 0.5 + 0.5
		if rng.randf() > dens * 1.2 - 0.1:
			continue
		p.y = height(p.x, p.z) - 0.03
		var s := rng.randf_range(0.6, 1.1) * (0.8 + dens * 0.6)
		var bs := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s))
		xf.append(Transform3D(bs, p))
		var c: Color = palette[rng.randi() % palette.size()]
		cols.append(c * rng.randf_range(0.85, 1.05))
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _tuft_tex() -> ImageTexture:
	const S := 16
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := RandomNumberGenerator.new()
	r.seed = 33
	for k in 9:
		var x := float(r.randi_range(1, S - 2))
		var h := r.randi_range(6, S - 1)
		var lean := r.randf_range(-0.35, 0.35)
		var shade := r.randf_range(0.7, 1.0)
		for j in h:
			var y := S - 1 - j
			var xi := int(round(x + lean * j))
			if xi < 0 or xi >= S:
				break
			var t := float(j) / h
			var v := lerpf(0.45, 1.0, t) * shade
			img.set_pixel(xi, y, Color(v, v, v * 0.9, 1.0))
	return ImageTexture.create_from_image(img)


## Пара бетонных обломков на поляне — укрытия и ориентиры.
func _ruins() -> void:
	var spots := [Vector3(26, 0, -9), Vector3(38, 0, 7), Vector3(35, 0, -12), Vector3(24, 0, 9), Vector3(42, 0, -3)]
	for s in spots:
		for k in rng.randi_range(1, 3):
			var sz := Vector3(rng.randf_range(0.6, 2.2), rng.randf_range(0.3, 1.3), rng.randf_range(0.5, 1.6))
			var p: Vector3 = s + Vector3(rng.randf_range(-1.2, 1.2), 0, rng.randf_range(-1.2, 1.2))
			p.y = height(p.x, p.z) + sz.y / 2 - 0.15
			var b := _vbox(p - sz / 2, p + sz / 2, wall_mat, true)
			b.rotation = Vector3(rng.randf_range(-0.15, 0.15), rng.randf() * TAU, rng.randf_range(-0.15, 0.15))
	# ржавая арматура торчит из земли
	var rebar := StandardMaterial3D.new()
	rebar.albedo_color = Color(0.22, 0.12, 0.07)
	rebar.roughness = 0.8
	for k in 14:
		var p := CENTER + Vector3(rng.randf_range(-16, 16), 0, rng.randf_range(-16, 16))
		if _rect_dist(p.x, p.z) < 2.0 or Vector2(p.x - CAR_POS.x, p.z - CAR_POS.z).length() < CAR_R:
			continue
		var cm := CylinderMesh.new()
		cm.top_radius = 0.015
		cm.bottom_radius = 0.015
		cm.height = rng.randf_range(0.4, 1.2)
		cm.radial_segments = 5
		cm.material = rebar
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.position = Vector3(p.x, height(p.x, p.z) + cm.height * 0.4, p.z)
		mi.rotation = Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5))
		add_child(mi)


# ---------- небо, солнце, окружение ----------

func _sky_and_sun() -> void:
	var cn := FastNoiseLite.new()
	cn.seed = 3
	cn.frequency = 0.02
	cn.fractal_octaves = 3
	var ct := NoiseTexture2D.new()
	ct.width = 128
	ct.height = 128
	ct.seamless = true
	ct.noise = cn
	var sm := ShaderMaterial.new()
	sm.shader = SkyShader
	sm.set_shader_parameter("clouds", ct)
	var sky := Sky.new()
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.fog_sky_affect = 0.35
	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.68, 0.52)
	sun.light_energy = 0.0
	sun.visible = false
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	sun.rotation = Vector3(-0.32, 2.4, 0)    # низкое солнце с юго-запада, сквозь мглу
	add_child(sun)
	_apply_env(0.0)


## 0 — внутри бункера, 1 — снаружи. В проходе лестницы — плавно по мере подъёма.
func _outside(p: Vector3) -> float:
	if p.x > X_WALL - 0.3 and p.x < X_OUT + 0.5 and absf(p.z) < 2.2:
		return smoothstep(HUT_X0, X_OUT - 0.5, p.x)
	if p.y > G - 0.5:
		return 1.0
	return 0.0


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var k := _outside(cam.global_position)
	out_k = lerpf(out_k, k, 1.0 - exp(-3.0 * delta))
	_apply_env(out_k)
	_feed_wind()


func _apply_env(k: float) -> void:
	env.ambient_light_color = IN_AMB.lerp(OUT_AMB, k)
	env.ambient_light_energy = lerpf(0.18, 0.5, k)
	env.fog_light_color = IN_FOG.lerp(OUT_FOG, k)
	env.fog_density = lerpf(0.02, 0.013, k)
	env.fog_height_density = lerpf(0.5, 0.0, k)
	env.volumetric_fog_density = lerpf(0.008, 0.012, k)
	env.volumetric_fog_albedo = Color(0.8, 0.8, 0.8).lerp(Color(0.75, 0.55, 0.48), k)
	if sun:
		sun.light_energy = 0.6 * k
		sun.visible = k > 0.01
	if wind:
		wind.volume_db = lerpf(-60.0, -20.0, k)


# ---------- ветер снаружи ----------

func _wind() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.3
	wind = AudioStreamPlayer.new()
	wind.stream = gen
	wind.volume_db = -60.0
	add_child(wind)
	wind.play()
	wind_pb = wind.get_stream_playback()


func _feed_wind() -> void:
	if wind_pb == null:
		return
	var n := wind_pb.get_frames_available()
	for i in n:
		w_t += 1.0 / 22050.0
		var g := 0.55 + 0.3 * sin(w_t * 0.31) + 0.15 * sin(w_t * 0.83 + 1.0)
		var w := randf() * 2.0 - 1.0
		w_lp += (w - w_lp) * (0.02 + 0.03 * g)
		w_lp2 += (w_lp - w_lp2) * 0.15
		var s := w_lp2 * 3.0 * g
		wind_pb.push_frame(Vector2(s, s))


# ---------- помощники ----------

## Бетонный блок по двум углам (a — минимальный, b — максимальный).
func _vbox(a: Vector3, b: Vector3, mat: Material, collide: bool) -> Node3D:
	var size := b - a
	var root: Node3D = StaticBody3D.new() if collide else Node3D.new()
	root.position = (a + b) / 2.0
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


func _col(a: Vector3, b: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = (a + b) / 2.0
	add_child(body)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = b - a
	cs.shape = sh
	body.add_child(cs)


func _lamp(pos: Vector3, energy: float, flicker: bool) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.12, 0.12)
	mat.emission_enabled = true
	mat.emission = WARM
	mat.emission_energy_multiplier = 1.5
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.18, 0.08, 0.7)
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var l: OmniLight3D = FlickerLight.new()
	l.light_color = WARM
	l.base_energy = energy
	l.flicker = flicker
	l.lamp_mat = mat
	l.omni_range = 7.0
	l.omni_attenuation = 1.0
	l.shadow_enabled = true
	l.position = pos - Vector3(0, 0.25, 0)
	add_child(l)
