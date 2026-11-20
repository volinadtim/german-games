extends CanvasLayer
## Фон главного меню (промпт 20.11 18:55): ночь, выход из бункера с тёплым светом изнутри, персонаж (модель
## игрока) в эпичной позе целится из пистолета с глушителем, коллиматором и ЛЦУ — красный луч и точка на мёртвом
## дереве. Отдельный мир в SubViewport (своё небо и свет); main.gd кладёт слой под меню и убирает при входе в игру.

const Weapons := preload("res://scripts/weapons/weapons.gd")
const MODEL := preload("res://assets/models/Player1.glb")
const CHAR_POS := Vector3.ZERO
const AIM := Vector3(-0.8, 0.03, -0.6)          # куда целится (мир)
const BODY_TURN := 1.1                           # корпус развёрнут от линии прицела влево, рад
const CAM_POS := Vector3(-0.3, 0.95, 2.7)        # чуть снизу — фигура выглядит внушительнее
const CAM_TURN := -0.14                          # камера чуть правее персонажа: он левее центра, кнопки справа
const LASER_L := 2.2                             # от ЛЦУ до точки на дереве, м
const LASER_FROM := Vector3(0.131, 0.068, 0)     # излучатель ЛЦУ в координатах пистолета (weapons.gd: mod_laser)
const MOON_DIR := Vector3(-0.5, 0.45, -0.75)
const DOOR := Vector3(0.9, 0.0, -4.2)            # низ середины проёма бункера, проём смотрит на +Z
const WARM := Color(1.0, 0.68, 0.38)

const SKY_CODE := """
shader_type sky;
void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col = mix(vec3(0.035, 0.045, 0.09), vec3(0.004, 0.007, 0.02), smoothstep(0.0, 0.6, h));
	col = h < 0.0 ? vec3(0.01, 0.012, 0.02) : col;
	vec3 p = d * 230.0;
	float n = fract(sin(dot(floor(p), vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	float s = step(0.9965, n) * smoothstep(0.03, 0.25, h) * smoothstep(0.5, 0.0, length(fract(p) - 0.5));
	vec3 md = normalize(vec3(-0.5, 0.45, -0.75));
	float c = dot(d, md);
	col += vec3(s) * (0.6 + 1.2 * fract(n * 91.7));
	col += vec3(0.85, 0.9, 1.0) * smoothstep(0.99925, 0.9995, c) * 2.5;
	col += vec3(0.08, 0.1, 0.18) * pow(max(c, 0.0), 40.0);
	COLOR = col;
}
"""

const HAZE_CODE := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 col = vec3(1.0, 0.66, 0.36);
uniform float power = 0.05;
void fragment() {
	vec2 e = abs(UV - 0.5) * 2.0;
	float k = (1.0 - smoothstep(0.35, 1.0, e.x)) * (1.0 - smoothstep(0.3, 1.0, e.y));
	ALBEDO = col;
	ALPHA = power * k;
}
"""

var world: Node3D
var cam: Camera3D
var cam_base: Transform3D
var laser_mat: StandardMaterial3D
var t := 0.0


## Строит SubViewport со своим миром и всю сцену фона.
func _ready() -> void:
	layer = -2   # под постобработкой (-1) и меню
	var box := SubViewportContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.stretch = true
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_2X
	vp.gui_disable_input = true
	box.add_child(vp)
	world = Node3D.new()
	vp.add_child(world)
	_env()
	_ground()
	_bunker()
	_trees()
	_hero()
	cam = Camera3D.new()
	cam.fov = 50.0
	world.add_child(cam)
	cam.look_at_from_position(CAM_POS, CHAR_POS + Vector3(0, 1.3, 0))
	cam.rotate_y(CAM_TURN)
	cam_base = cam.transform
	cam.current = true


## Камера чуть «дышит», луч ЛЦУ слегка мерцает.
func _process(delta: float) -> void:
	t += delta
	if cam:
		cam.transform = cam_base.translated(Vector3(sin(t * 0.3) * 0.025, sin(t * 0.6) * 0.012, 0))
	if laser_mat:
		laser_mat.albedo_color.a = 0.75 + 0.15 * sin(t * 23.0) * sin(t * 7.0)


## Матовый материал.
func _mat(c: Color, rough := 0.9, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


## Светящийся материал (лампы, точка лазера) — под glow.
func _glow(c: Color, e: float) -> StandardMaterial3D:
	var m := _mat(Color.BLACK)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	return m


## Коробка-меш в мире.
func _box(p: Node3D, size: Vector3, pos: Vector3, m: Material, rot_y := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	mi.rotation.y = rot_y
	p.add_child(mi)
	return mi


## Цилиндр-меш в мире.
func _cyl(p: Node3D, r0: float, r1: float, h: float, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r0
	cm.bottom_radius = r1
	cm.height = h
	cm.radial_segments = 10
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = m
	mi.position = pos
	p.add_child(mi)
	return mi


## Шар (сплюснутый scale) — камни, насыпь, лампы.
func _ball(p: Node3D, r: float, pos: Vector3, sc: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 16
	sm.rings = 8
	mi.mesh = sm
	mi.material_override = m
	mi.position = pos
	mi.scale = sc
	p.add_child(mi)
	return mi


## Ночное небо со звёздами и луной, туман, свечение, лунный свет.
func _env() -> void:
	var sh := Shader.new()
	sh.code = SKY_CODE
	var smat := ShaderMaterial.new()
	smat.shader = sh
	var sky := Sky.new()
	sky.sky_material = smat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.2, 0.24, 0.38)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.035, 0.045, 0.08)
	env.fog_density = 0.03
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.6, 0.7, 1.0)
	moon.light_energy = 0.45
	moon.shadow_enabled = true
	world.add_child(moon)
	moon.look_at_from_position(MOON_DIR.normalized() * 10.0, Vector3.ZERO)
	# холодная подсветка со стороны камеры — видно пистолет и модули
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.55, 0.65, 1.0)
	fill.light_energy = 0.6
	fill.omni_range = 4.5
	fill.position = Vector3(-0.9, 1.8, 1.7)
	world.add_child(fill)


## Земля, дорожка от бункера, камни.
func _ground() -> void:
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(140, 140)
	g.mesh = pm
	g.material_override = _mat(Color(0.1, 0.105, 0.085))
	world.add_child(g)
	_box(world, Vector3(2.6, 0.02, 6.5), DOOR + Vector3(0, 0.01, 3.1), _mat(Color(0.2, 0.19, 0.17)))   # бетонная площадка
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var rock := _mat(Color(0.16, 0.16, 0.15))
	for i in 34:
		var p := Vector3(rng.randf_range(-16, 16), 0, rng.randf_range(-18, 3))
		if p.distance_to(CHAR_POS) < 2.2 or (absf(p.x - DOOR.x) < 3.6 and p.z > DOOR.z - 7.0):
			continue
		var r := rng.randf_range(0.15, 0.7)
		_ball(world, r, p, Vector3(1.0, rng.randf_range(0.35, 0.7), rng.randf_range(0.7, 1.2)), rock)


## Бункер: насыпь, бетонный портал с открытой гермодверью, коридор с лампами, свет и дымка из проёма.
func _bunker() -> void:
	var earth := _mat(Color(0.075, 0.08, 0.06))
	_ball(world, 1.0, DOOR + Vector3(0, -2.0, -6.5), Vector3(10, 6, 6.5), earth)
	var conc := _mat(Color(0.32, 0.32, 0.31))
	var inner := _mat(Color(0.45, 0.43, 0.4))
	# фасад с проёмом 2.2 × 2.5
	_box(world, Vector3(1.9, 3.4, 0.6), DOOR + Vector3(-2.05, 1.7, -0.3), conc)
	_box(world, Vector3(1.9, 3.4, 0.6), DOOR + Vector3(2.05, 1.7, -0.3), conc)
	_box(world, Vector3(2.2, 0.9, 0.6), DOOR + Vector3(0, 2.95, -0.3), conc)
	_box(world, Vector3(6.4, 0.25, 0.8), DOOR + Vector3(0, 3.52, -0.3), conc)   # козырёк
	for s in [-1.0, 1.0]:
		_box(world, Vector3(0.4, 1.7, 3.2), DOOR + Vector3(3.3 * s, 0.85, 1.1), conc, -0.35 * s)   # подпорные стенки
	# коридор внутрь
	for s in [-1.0, 1.0]:
		_box(world, Vector3(0.4, 3.0, 6.0), DOOR + Vector3(1.3 * s, 1.5, -3.6), inner)
	_box(world, Vector3(3.0, 0.5, 6.0), DOOR + Vector3(0, 2.75, -3.6), inner)
	_box(world, Vector3(2.2, 0.05, 6.6), DOOR + Vector3(0, 0.025, -3.3), _mat(Color(0.3, 0.29, 0.27)))
	_box(world, Vector3(2.2, 2.5, 0.3), DOOR + Vector3(0, 1.25, -6.6), inner)
	_box(world, Vector3(1.0, 2.0, 0.05), DOOR + Vector3(0, 1.0, -6.43), _glow(WARM, 1.6))   # освещённая дверь в глубине
	# лампы на потолке
	for z in [-1.2, -3.4, -5.6]:
		_box(world, Vector3(0.35, 0.06, 0.14), DOOR + Vector3(0, 2.47, z), _glow(WARM, 6.0))
		var l := OmniLight3D.new()
		l.light_color = WARM
		l.light_energy = 1.8
		l.omni_range = 4.5
		l.position = DOOR + Vector3(0, 2.2, z)
		world.add_child(l)
	# прожектор из проёма — длинная тень персонажа к камере
	var sp := SpotLight3D.new()
	sp.light_color = WARM
	sp.light_energy = 7.0
	sp.spot_range = 16.0
	sp.spot_angle = 42.0
	sp.shadow_enabled = true
	world.add_child(sp)
	sp.look_at_from_position(DOOR + Vector3(0, 2.3, -1.2), CHAR_POS + Vector3(0.3, 0, 1.5))
	# гермодверь распахнута наружу
	var hinge := Node3D.new()
	hinge.position = DOOR + Vector3(1.1, 0, 0)
	hinge.rotation.y = 1.9
	world.add_child(hinge)
	var steel := _mat(Color(0.22, 0.24, 0.23), 0.55, 0.7)
	_box(hinge, Vector3(1.2, 2.45, 0.25), Vector3(-0.6, 1.225, 0.13), steel)
	var wheel := _cyl(hinge, 0.16, 0.16, 0.06, Vector3(-0.6, 1.25, 0.28), steel)   # штурвал
	wheel.rotation.x = PI / 2
	# жёлто-чёрные полосы над проёмом
	for i in 11:
		var c := Color(0.85, 0.65, 0.05) if i % 2 == 0 else Color(0.03, 0.03, 0.03)
		_box(world, Vector3(0.2, 0.18, 0.02), DOOR + Vector3(-1.0 + i * 0.2, 2.64, 0.011), _mat(c, 0.7))
	# красный фонарь над дверью
	_ball(world, 0.08, DOOR + Vector3(0, 3.2, 0.12), Vector3.ONE, _glow(Color(1.0, 0.1, 0.05), 5.0))
	var rl := OmniLight3D.new()
	rl.light_color = Color(1.0, 0.15, 0.08)
	rl.light_energy = 0.9
	rl.omni_range = 2.8
	rl.position = DOOR + Vector3(0, 3.2, 0.3)
	world.add_child(rl)
	# мешки с песком у входа
	var bag := _mat(Color(0.3, 0.27, 0.2))
	for i in 7:
		var row := 0 if i < 4 else 1
		var k := i if row == 0 else i - 4
		_ball(world, 0.3, DOOR + Vector3(-2.1 - k * 0.55 + row * 0.27, 0.13 + row * 0.22, 1.2), Vector3(1.0, 0.45, 0.6), bag)
	# дымка — свет из проёма растекается наружу
	var hs := Shader.new()
	hs.code = HAZE_CODE
	for i in 6:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(2.4 + i * 0.4, 2.6 + i * 0.25)
		q.mesh = qm
		var hm := ShaderMaterial.new()
		hm.shader = hs
		hm.set_shader_parameter("power", 0.08 * (1.0 - i / 6.0))
		q.material_override = hm
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		q.position = DOOR + Vector3(0, 1.25 - i * 0.04, 0.2 + i * 0.7)
		world.add_child(q)


## Мёртвое дерево: ствол и голые ветки.
func _tree(pos: Vector3, h: float, r: float, rng: RandomNumberGenerator) -> void:
	var bark := _mat(Color(0.07, 0.06, 0.05))
	_cyl(world, r * 0.55, r, h, pos + Vector3(0, h * 0.5, 0), bark)
	for i in 5:
		var piv := Node3D.new()
		piv.position = pos + Vector3(0, h * rng.randf_range(0.55, 0.92), 0)
		piv.rotation = Vector3(0, rng.randf() * TAU, rng.randf_range(0.5, 1.1) * (1.0 if i % 2 == 0 else -1.0))
		world.add_child(piv)
		var bl := h * rng.randf_range(0.2, 0.38)
		_cyl(piv, r * 0.12, r * 0.3, bl, Vector3(0, bl * 0.5, 0), bark)


## Силуэты мёртвых деревьев вдали.
func _trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for p in [Vector2(-7, -9), Vector2(-10.5, -4), Vector2(6.5, -10), Vector2(9.5, -5.5), Vector2(-4.5, -13),
			Vector2(13, -12), Vector2(-13, -11), Vector2(3.5, -16), Vector2(-8, -17), Vector2(16, -7)]:
		_tree(Vector3(p.x, 0, p.y), rng.randf_range(4.0, 7.0), rng.randf_range(0.14, 0.25), rng)


## Персонаж: модель игрока в позе, пистолет с модулями в правой руке, луч ЛЦУ и дерево с точкой.
func _hero() -> void:
	var model: Node3D = MODEL.instantiate()
	for n in model.find_children("*", "", true, false):
		if n is Light3D or n is Camera3D or n is AnimationPlayer:
			n.free()
	world.add_child(model)
	var aim_flat := Vector3(AIM.x, 0, AIM.z).normalized()
	var f := aim_flat.rotated(Vector3.UP, BODY_TURN)
	model.position = CHAR_POS
	model.rotation.y = atan2(f.x, f.z)   # в файле модель смотрит на +Z
	var found := model.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return
	var skel: Skeleton3D = found[0]
	var sk := skel.global_transform.basis.orthonormalized()
	# пистолет: ствол — по линии прицела, чуть завален внутрь
	var gx := AIM.normalized()
	var gy := (Vector3.UP - gx * gx.dot(Vector3.UP)).normalized().rotated(gx, -0.12)
	var gun_b := Basis(gx, gy, gx.cross(gy))
	_pose(skel, sk, f, aim_flat, gun_b)
	var wb := skel.find_bone("weapon_R")
	var bone := "weapon_R" if wb >= 0 else "hand_R"
	if wb < 0:
		wb = skel.find_bone("hand_R")
	var gun := Weapons.make("pistol")
	Weapons.set_mods(gun, ["mod_reddot", "mod_silencer", "", "mod_laser"])
	var att := BoneAttachment3D.new()
	att.bone_name = bone
	skel.add_child(att)
	att.add_child(gun)
	var sc := maxf(skel.global_transform.basis.get_scale().x, 0.0001)
	gun.transform = Transform3D(Basis.from_scale(Vector3.ONE / sc), Vector3.ZERO)
	_laser(gun)
	# дерево там, куда упирается луч
	var gun_w := skel.global_transform * Transform3D(skel.get_bone_global_pose(wb)) * gun.transform
	var dot_w := gun_w * (LASER_FROM + Vector3(LASER_L, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	_tree(Vector3(dot_w.x, 0, dot_w.z) + aim_flat * 0.21, 4.2, 0.22, rng)


## Поза: корпус и голова повёрнуты к цели, правая рука вытянута, кисть ставит пистолет в gun_b,
## левая рука опущена, ноги в широкой стойке. Направления — в мире, кость смотрит вдоль своей +Y.
func _pose(skel: Skeleton3D, sk: Basis, f: Vector3, aim_flat: Vector3, gun_b: Basis) -> void:
	var right := Vector3(-f.z, 0, f.x)
	var left := -right
	var turn := f.signed_angle_to(aim_flat, Vector3.UP)
	for e in [["spine01", 0.15], ["spine02", 0.15], ["spine03", 0.15], ["neck", 0.2], ["head", 0.3]]:
		var b := skel.find_bone(e[0])
		if b >= 0:
			_rot_global(skel, sk, b, Basis(Vector3.UP, turn * float(e[1])))
	_point(skel, sk, "upperarm_R", AIM.normalized() + Vector3.DOWN * 0.06 + right * 0.04)
	_point(skel, sk, "lowerarm_R", AIM.normalized() + Vector3.UP * 0.02)
	var hb := skel.find_bone("hand_R")
	var wb := skel.find_bone("weapon_R")
	if hb >= 0 and wb >= 0 and wb != hb:
		var w := sk * skel.get_bone_global_pose(wb).basis.orthonormalized()
		_rot_global(skel, sk, hb, gun_b * w.inverse())
	_point(skel, sk, "upperarm_L", Vector3.DOWN + left * 0.3 - f * 0.08)
	_point(skel, sk, "lowerarm_L", Vector3.DOWN + f * 0.35 + left * 0.12)
	_point(skel, sk, "thigh_L", Vector3.DOWN + f * 0.16 + left * 0.16)
	_point(skel, sk, "calf_L", Vector3.DOWN + left * 0.1 - f * 0.05)
	_point(skel, sk, "thigh_R", Vector3.DOWN - f * 0.2 + right * 0.14)
	_point(skel, sk, "calf_R", Vector3.DOWN - f * 0.28 + right * 0.1)


## Поворачивает кость так, чтобы она (+Y) смотрела в dir (мир).
func _point(skel: Skeleton3D, sk: Basis, bn: String, dir: Vector3) -> void:
	var b := skel.find_bone(bn)
	if b < 0:
		return
	var cur := (sk * skel.get_bone_global_pose(b).basis.orthonormalized().y).normalized()
	var d := dir.normalized()
	if cur.dot(d) > 0.9999:
		return
	_rot_global(skel, sk, b, Basis(Quaternion(cur, d)))


## Доворачивает кость на r (поворот в мире) поверх её текущей позы.
func _rot_global(skel: Skeleton3D, sk: Basis, b: int, r: Basis) -> void:
	var g := skel.get_bone_global_pose(b).basis.orthonormalized()
	var ng := sk.inverse() * r * sk * g
	var pb := skel.get_bone_parent(b)
	var parent := skel.get_bone_global_pose(pb).basis.orthonormalized() if pb != -1 else Basis.IDENTITY
	skel.set_bone_pose_rotation(b, (parent.inverse() * ng).orthonormalized().get_rotation_quaternion())


## Луч ЛЦУ (тонкая нить + ореол) и точка с красным отсветом — в координатах пистолета.
func _laser(gun: Node3D) -> void:
	laser_mat = StandardMaterial3D.new()
	laser_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	laser_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	laser_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	laser_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	laser_mat.albedo_color = Color(1.0, 0.12, 0.06, 0.8)
	var halo := laser_mat.duplicate() as StandardMaterial3D
	halo.albedo_color = Color(1.0, 0.1, 0.05, 0.12)
	for e in [[0.004, laser_mat], [0.014, halo]]:
		var beam := _cyl(gun, e[0], e[0], LASER_L, LASER_FROM + Vector3(LASER_L * 0.5, 0, 0), e[1])
		beam.rotation.z = PI / 2
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var end := LASER_FROM + Vector3(LASER_L, 0, 0)
	var spot := _ball(gun, 0.016, end, Vector3.ONE, _glow(Color(1.0, 0.12, 0.06), 9.0))
	spot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.1, 0.05)
	l.light_energy = 1.4
	l.omni_range = 0.8
	l.position = end - Vector3(0.06, 0, 0)
	gun.add_child(l)
