@tool
extends "res://scripts/locations/bunker/level_geometry.gd"
# Часть level.gd: лампы и провода, мусор, паутина, трещины, пыль.


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
			p = _off_walls(p, Vector2(sz.x, sz.z).length() / 2.0)   # обломок не врезается в стену
			var b := _box(p, sz, wall_mat)
			b.rotation.y = rng.randf_range(0, TAU)
	# плиты прислонены к стене: верхний край упирается в стену, нижний — в пол (раньше висели в 15–25 см от стены)
	var slab := _box(Vector3(-5.5, 0.66, -8.43), Vector3(2.4, 0.2, 1.4), wall_mat)
	slab.rotation.x = 1.1
	var slab2 := _box(Vector3(7.5, 0.55, 8.43), Vector3(2.0, 0.2, 1.2), wall_mat)
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
	# светильник оторвался одним краем и висит на проводах; светит туда, куда смотрит его отражатель
	var tilt := 0.6
	var attach := pos + Vector3(-0.55, -0.01, 0)       # этот край ещё держится за потолок
	var along := Vector3(cos(tilt), -sin(tilt), 0)
	var tip := attach + along * 1.1                     # этот край оторвался и висит
	var xf := Transform3D(Basis(Vector3.BACK, -tilt), attach + along * 0.55)
	var l := lamp_fixture(self, xf, energy, true, 1.1)
	broken_mesh = l.get_meta("fixture")
	broken_light = l
	# провода от оторванного края в потолок, с провисом
	for side in [-0.05, 0.05]:
		var a := tip + Vector3(0, -0.03, side)
		var b := Vector3(tip.x - 0.12 + side, H, side * 2.0)
		var m := (a + b) / 2.0 + Vector3(0.09, -0.06, side * 0.6)
		_wire(a, m)
		_wire(m, b)
	_wire(attach + Vector3(0.05, -0.02, 0.06), Vector3(attach.x + 0.05, H, 0.08))


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
	lamp_fixture(self, Transform3D(Basis(), pos), energy, flicker, 1.1)


## Потолочный светильник (промпт 14.11 18:46): металлический короб-отражатель с отогнутыми бортами,
## лампа-трубка внутри и решётка снизу. Свет только вниз — SpotLight3D с мягким краем; над коробом
## потолок подсвечивает лишь слабый ореол (маленький OmniLight без теней).
## xf — верх короба (прижат к потолку), трубка вдоль локальной X длиной len_; возвращает свет (meta "lamp"),
## сам светильник — в meta "fixture".
func lamp_fixture(parent: Node3D, xf: Transform3D, energy: float, flicker: bool, len_ := 1.1, lite_ := lite) -> SpotLight3D:
	var fx := Node3D.new()
	fx.transform = xf
	parent.add_child(fx)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.2, 0.2, 0.19)
	metal.metallic = 0.75
	metal.roughness = 0.5
	var inner := StandardMaterial3D.new()       # нутро отражателя — светлая облупленная эмаль, ловит свет трубки
	inner.albedo_color = Color(0.55, 0.52, 0.45)
	inner.roughness = 0.6
	var tube := StandardMaterial3D.new()
	tube.albedo_color = Color(0.9, 0.85, 0.75)
	tube.emission_enabled = energy > 0.0
	tube.emission = WARM
	tube.emission_energy_multiplier = 1.5
	var w := 0.26                                # ширина короба
	_fx_box(fx, Vector3(len_, 0.03, w), Vector3(0, -0.01, 0), metal)                  # крышка у потолка
	_fx_box(fx, Vector3(len_ - 0.02, 0.005, w - 0.03), Vector3(0, -0.028, 0), inner)  # эмаль изнутри
	for sz in [-1.0, 1.0]:
		var side := _fx_box(fx, Vector3(len_, 0.12, 0.012), Vector3(0, -0.075, sz * (w / 2.0 + 0.02)), metal)
		side.rotation.x = sz * 0.42               # борта отогнуты наружу — отражатель
	for sx in [-1.0, 1.0]:
		_fx_box(fx, Vector3(0.012, 0.1, w + 0.02), Vector3(sx * (len_ / 2.0 - 0.006), -0.065, 0), metal)
	var cm := CylinderMesh.new()
	cm.top_radius = 0.022
	cm.bottom_radius = 0.022
	cm.height = len_ - 0.06
	cm.radial_segments = 8
	cm.rings = 1
	cm.material = tube
	var tm := MeshInstance3D.new()
	tm.mesh = cm
	tm.rotation.z = PI / 2.0
	tm.position = Vector3(0, -0.06, 0)
	tm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx.add_child(tm)
	# защитная решётка снизу: две продольные рейки и поперечные прутья
	for sz in [-1.0, 1.0]:
		_fx_box(fx, Vector3(len_ - 0.02, 0.01, 0.01), Vector3(0, -0.125, sz * (w / 2.0 + 0.04)), metal)
	var bars := int(len_ / 0.14)
	for i in bars + 1:
		_fx_box(fx, Vector3(0.008, 0.008, w + 0.09), Vector3(-len_ / 2.0 + 0.04 + (len_ - 0.08) * i / bars, -0.125, 0), metal)
	if energy <= 0.0:
		return null
	var l: SpotLight3D = FlickerLight.new()
	l.light_color = WARM
	l.base_energy = energy * 3.0      # весь свет — в конус, поэтому ярче прежней всенаправленной
	l.flicker = flicker
	l.lamp_mat = tube
	l.spot_range = 8.0
	l.spot_attenuation = 1.2          # спад круче прежнего — свет не размазывается по всему бункеру
	l.spot_angle = 66.0
	l.spot_angle_attenuation = 0.9    # мягкий край пятна
	l.shadow_enabled = not lite_
	l.shadow_bias = 0.04
	l.shadow_normal_bias = 1.2
	l.shadow_blur = 0.8
	l.shadow_opacity = 0.9
	l.position = Vector3(0, -0.07, 0)
	l.rotation.x = -PI / 2.0          # SpotLight светит по −Z → вниз по −Y короба
	l.set_meta("lamp", true)
	l.set_meta("fixture", fx)
	fx.add_child(l)
	var halo := OmniLight3D.new()     # слабый ореол на потолке вокруг короба
	halo.light_color = WARM
	halo.light_energy = energy * 0.3
	halo.omni_range = 1.1
	halo.omni_attenuation = 1.6
	halo.shadow_enabled = false
	halo.position = Vector3(0, -0.16, 0)
	fx.add_child(halo)
	l.halo = halo
	l.halo_k = 0.3 / 3.0
	return l


# ---------- паутина в верхних углах ----------

func _cobwebs() -> void:
	var tex := _web_tex()
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = Color(0.85, 0.83, 0.8, 0.38)  # тоньше и прозрачнее (промпт 14.11 17:26)
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
	# битое стекло теперь раскидывает game.gd (glass_floor.gd) — случайно в каждой новой игре


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
