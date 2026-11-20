@tool
extends "res://scripts/locations/bunker/atmosphere_assets.gd"
## Мелкие детали атмосферы бункера. Каждая добавка — своя функция; ненужную убрать, закомментировав строку в _ready.
##   _moths            — мошки кружат в свете ламп (без звука)
##   _broken_lamp_tremble — поломанная лампа на проводах чуть подрагивает, тени дрожат
##   _drips            — с потолка изредка падают капли (со звуком), под ними мокрые пятна и плесень
##   _steam            — ржавая труба под потолком, из трещины в ней сочится пар с шипением
##   _distant_sounds   — редкие далёкие звуки бункера: лязг, стон трубы, гул
##   _more_webs        — паутина в проходе к лестнице и в будке
## Создаётся из level.gd (_ready). Звук и движение — только в игре, в редакторе видны частицы и предметы.


func _ready() -> void:
	name = "Atmosphere"
	rng.seed = 2034
	_moths()
	_broken_lamp_tremble()
	_drips()
	_steam()
	_distant_sounds()
	_more_webs()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	t += delta
	_update_tremble()
	_update_drips(delta)
	_update_distant(delta)


# ---------- мошки у ламп ----------

func _moths() -> void:
	var buzz: AudioStreamWAV = null   # жужжание мошек выключено (промпт 21:39); вернуть: _buzz_loop()
	var tex := _moth_tex()
	# потолочные лампы — SpotLight с meta "lamp" (level.gd: lamp_fixture); мошки кружат под коробом
	var lights := level.find_children("*", "SpotLight3D", true, false)
	var k := 0
	for l in lights:
		var lt := l as SpotLight3D
		if not lt.has_meta("lamp"):
			continue
		var at: Vector3 = lt.global_position if lt.is_inside_tree() else (lt.get_parent() as Node3D).transform * lt.position
		_moth_swarm(at + Vector3(0, -0.15, 0), tex)
		# жужжание — не у каждой лампы, чтобы не гудело хором
		if buzz and k % 2 == 0:
			var p := AudioStreamPlayer3D.new()
			p.stream = buzz
			p.volume_db = -30.0
			p.unit_size = 1.2
			p.max_distance = 7.0
			p.pitch_scale = rng.randf_range(0.85, 1.15)
			lt.add_child(p)
			p.play(rng.randf_range(0.0, 2.5))
		k += 1


func _moth_swarm(at: Vector3, tex: Texture2D) -> void:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.35
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	# мелкие и мечутся хаотично (промпт 14.11 17:26): сильная мелкая турбулентность, быстрый шум
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.3
	pm.gravity = Vector3.ZERO
	pm.damping_min = 0.1
	pm.damping_max = 0.4
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 9.0
	pm.turbulence_noise_scale = 0.22
	pm.turbulence_noise_speed = Vector3(1.6, 1.4, 1.6)
	pm.turbulence_influence_min = 0.5
	pm.turbulence_influence_max = 0.9
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.set_color(1, Color(1, 1, 1, 0))
	ramp.add_point(0.1, Color(1, 1, 1, 1))
	ramp.add_point(0.9, Color(1, 1, 1, 1))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt

	var m := ShaderMaterial.new()
	m.shader = MothShader
	m.set_shader_parameter("tex", tex)
	var q := QuadMesh.new()
	q.size = Vector2(0.018, 0.018)
	q.material = m

	var ps := GPUParticles3D.new()
	ps.amount = rng.randi_range(6, 11)
	ps.lifetime = 7.0
	ps.preprocess = 7.0
	ps.process_material = pm
	ps.draw_pass_1 = q
	ps.position = at
	ps.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))
	ps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ps)
	# притягиваются к лампе — не разлетаются, а нарезают круги
	var att := GPUParticlesAttractorSphere3D.new()
	att.radius = 1.3
	att.strength = 2.5
	att.attenuation = 0.6
	att.position = at
	add_child(att)


# ---------- поломанная лампа подрагивает ----------

func _broken_lamp_tremble() -> void:
	if level.broken_mesh:
		broken_base = level.broken_mesh.transform


func _update_tremble() -> void:
	if level.broken_mesh == null:
		return
	# медленное покачивание на проводах + мелкая дрожь
	var sway := sin(t * 0.9) * 0.012 + sin(t * 2.3 + 1.0) * 0.006 + sin(t * 23.0) * 0.0015
	var pivot := broken_base.origin + broken_base.basis.x * -0.55   # край, что держится за потолок
	var rot := Transform3D(Basis(Vector3.FORWARD, sway), Vector3.ZERO)
	var off := Transform3D(Basis(), pivot) * rot * Transform3D(Basis(), -pivot)
	# свет — внутри короба (дочерний), качается и дрожит вместе с ним: пятно и тени гуляют по полу
	level.broken_mesh.transform = off * broken_base.translated(Vector3(sin(t * 31.0), 0, cos(t * 27.0)) * 0.002)


# ---------- капли с потолка ----------

func _drips() -> void:
	# у ламп капли видны; (-9.6, 4.2) — в тёмной комнате, там их только слышно
	var spots := [Vector3(-8.2, H, -3.1), Vector3(9.6, H, -3.4), Vector3(3.6, H, 6.9), Vector3(-9.6, H, 4.2), Vector3(-1.2, H, -0.9)]
	if not Engine.is_editor_hint():
		for i in 4:
			drip_snds.append(_drip_sound(i))
	var stain := _blob_tex(61)
	var drop_mat := StandardMaterial3D.new()
	drop_mat.albedo_color = Color(0.6, 0.65, 0.65, 0.6)
	drop_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop_mat.roughness = 0.05
	drop_mat.metallic_specular = 1.0
	for s in spots:
		var pos: Vector3 = s
		# мокрое пятно на полу и сырое — на потолке
		_stain(stain, Vector3(pos.x, 0.0, pos.z), Vector3.UP, rng.randf_range(0.5, 0.9), Color(0.04, 0.045, 0.04, 0.55), 0.15)
		_stain(stain, Vector3(pos.x, H, pos.z), Vector3.DOWN, rng.randf_range(0.6, 1.1), Color(0.05, 0.07, 0.045, 0.6), 0.6)
		var sm := SphereMesh.new()
		sm.radius = 0.01
		sm.height = 0.02
		sm.radial_segments = 6
		sm.rings = 3
		sm.material = drop_mat
		var drop := MeshInstance3D.new()
		drop.mesh = sm
		drop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		drop.position = pos - Vector3(0, 0.01, 0)
		drop.visible = false
		add_child(drop)
		var sp := CPUParticles3D.new()
		sp.emitting = false
		sp.one_shot = true
		sp.amount = 7
		sp.lifetime = 0.35
		sp.explosiveness = 1.0
		sp.direction = Vector3.UP
		sp.spread = 60.0
		sp.initial_velocity_min = 0.4
		sp.initial_velocity_max = 0.9
		sp.gravity = Vector3(0, -9.8, 0)
		sp.scale_amount_min = 0.4
		sp.scale_amount_max = 0.8
		sp.mesh = sm
		sp.position = Vector3(pos.x, 0.01, pos.z)
		add_child(sp)
		var snd: AudioStreamPlayer3D = null
		if not Engine.is_editor_hint():
			snd = AudioStreamPlayer3D.new()
			snd.unit_size = 2.5
			snd.max_distance = 18.0
			snd.position = Vector3(pos.x, 0.05, pos.z)
			add_child(snd)
		drips.append({"pos": pos, "wait": rng.randf_range(0.5, 6.0), "phase": 0, "k": 0.0, "drop": drop, "splash": sp, "snd": snd})


func _update_drips(delta: float) -> void:
	for d in drips:
		var drop: MeshInstance3D = d["drop"]
		var pos: Vector3 = d["pos"]
		match d["phase"]:
			0:   # ждёт
				d["wait"] -= delta
				if d["wait"] <= 0.0:
					d["phase"] = 1
					d["k"] = 0.0
					drop.visible = true
			1:   # капля набухает на потолке
				d["k"] += delta / 0.9
				var s := lerpf(0.3, 1.0, minf(float(d["k"]), 1.0))
				drop.scale = Vector3(s, s * 1.3, s)
				drop.position = pos - Vector3(0, 0.01 * s, 0)
				if d["k"] >= 1.0:
					d["phase"] = 2
					d["k"] = 0.0
			2:   # падает
				d["k"] += delta
				var k: float = d["k"]
				var y := H - 0.015 - 4.9 * k * k
				drop.scale = Vector3(0.8, 1.8, 0.8)
				drop.position = Vector3(pos.x, y, pos.z)
				if y <= 0.01:
					drop.visible = false
					(d["splash"] as CPUParticles3D).restart()
					var snd: AudioStreamPlayer3D = d["snd"]
					snd.stream = drip_snds[rng.randi() % drip_snds.size()]
					snd.volume_db = rng.randf_range(-20.0, -14.0)
					snd.pitch_scale = rng.randf_range(0.85, 1.2)
					snd.play()
					d["phase"] = 0
					# иногда две капли подряд
					d["wait"] = rng.randf_range(0.4, 0.8) if rng.randf() < 0.2 else rng.randf_range(3.0, 9.0)


# ---------- пар из трубы ----------

func _steam() -> void:
	# ржавая труба вдоль северной стены северо-восточной комнаты, под потолком
	var z := ZN + T / 2 + 0.1     # труба почти касается стены, хомуты уходят в бетон
	var y := H - 0.45
	var rust := StandardMaterial3D.new()
	rust.albedo_color = Color(0.2, 0.12, 0.08)
	rust.roughness = 0.75
	rust.metallic = 0.4
	var cm := CylinderMesh.new()
	cm.top_radius = 0.07
	cm.bottom_radius = 0.07
	cm.height = 11.6
	cm.radial_segments = 10
	cm.material = rust
	var pipe := MeshInstance3D.new()
	pipe.mesh = cm
	pipe.position = Vector3(6.0, y, z)
	pipe.rotation.z = PI / 2.0
	add_child(pipe)
	# хомуты
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.12, 0.24)
	bm.material = rust
	for bx in [1.0, 3.5, 6.0, 8.5, 11.0]:
		var b := MeshInstance3D.new()
		b.mesh = bm
		b.position = Vector3(bx, y + 0.02, z - 0.04)
		add_child(b)
	# пар из трещины
	var leak := Vector3(8.0, y - 0.02, z + 0.05)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.03
	pm.direction = Vector3(0.2, -0.6, 1.0)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.9
	pm.initial_velocity_max = 1.4
	pm.gravity = Vector3(0, 0.25, 0)
	pm.damping_min = 0.3
	pm.damping_max = 0.5
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.0
	pm.turbulence_noise_scale = 2.0
	pm.turbulence_influence_min = 0.08
	pm.turbulence_influence_max = 0.18
	pm.scale_min = 0.6
	pm.scale_max = 1.0
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.3))
	sc.add_point(Vector2(1, 2.6))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.set_color(1, Color(1, 1, 1, 0))
	ramp.add_point(0.12, Color(1, 1, 1, 0.35))
	ramp.add_point(0.4, Color(1, 1, 1, 1))
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
	m.albedo_color = Color(0.42, 0.4, 0.37, 0.07)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED   # плоские спрайты почти не ловят свет лампы — тусклый собственный тон
	m.roughness = 1.0
	m.disable_receive_shadows = true
	var q := QuadMesh.new()
	q.size = Vector2(0.4, 0.4)
	q.material = m
	var ps := GPUParticles3D.new()
	ps.amount = 60
	ps.lifetime = 3.5
	ps.preprocess = 4.0
	ps.process_material = pm
	ps.draw_pass_1 = q
	ps.position = leak
	ps.visibility_aabb = AABB(Vector3(-2, -3, -1), Vector3(4, 4, 4))
	ps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ps)
	if not Engine.is_editor_hint():
		var hiss := AudioStreamPlayer3D.new()
		hiss.stream = _hiss_loop()
		hiss.volume_db = -27.0
		hiss.unit_size = 1.5
		hiss.max_distance = 10.0
		hiss.position = leak
		add_child(hiss)
		hiss.play()


# ---------- далёкие звуки бункера ----------

func _distant_sounds() -> void:
	if Engine.is_editor_hint():
		return
	for i in 3:
		far_snds.append(_far_clank(i))
	far_snds.append(_far_groan(0))
	far_snds.append(_far_groan(1))
	far_snds.append(_far_rumble())
	far_player = AudioStreamPlayer3D.new()
	far_player.unit_size = 12.0
	far_player.max_distance = 60.0
	add_child(far_player)
	far_wait = rng.randf_range(12.0, 25.0)


func _update_distant(delta: float) -> void:
	if far_player == null:
		return
	far_wait -= delta
	if far_wait > 0.0:
		return
	far_wait = rng.randf_range(25.0, 60.0)
	# звук приходит «из-за стены»: точка за пределами бункера в случайной стороне
	var a := rng.randf() * TAU
	far_player.position = Vector3(cos(a) * 20.0, rng.randf_range(-2.0, 2.0), sin(a) * 14.0)
	far_player.stream = far_snds[rng.randi() % far_snds.size()]
	far_player.volume_db = rng.randf_range(-12.0, -6.0)
	far_player.pitch_scale = rng.randf_range(0.8, 1.1)
	far_player.play()


# ---------- ещё паутина ----------

func _more_webs() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_texture = level._web_tex()
	m.albedo_color = Color(0.85, 0.83, 0.8, 0.38)  # тоньше и прозрачнее (промпт 14.11 17:26)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 1.0
	m.disable_receive_shadows = true
	# [угол, вдоль стены 1, вдоль стены 2, размер]
	var webs := [
		[Vector3(12.16, 2.59, 1.09), Vector3(1, 0, 0), Vector3(0, 0, -1), 0.5],     # проход к лестнице, у проёма
		[Vector3(12.16, 2.59, -1.09), Vector3(1, 0, 0), Vector3(0, 0, 1), 0.35],
		[Vector3(15.01, 6.39, -1.09), Vector3(1, 0, 0), Vector3(0, 0, 1), 0.7],     # будка-выход, под крышей
		[Vector3(-T / 2 - 0.01, H - 0.01, 8.84), Vector3(-1, 0, 0), Vector3(0, 0, -1), 0.55],   # тёмная комната
	]
	for w in webs:
		var c: Vector3 = w[0]
		var s: float = w[3]
		var a: Vector3 = c + (w[1] as Vector3) * s
		var b: Vector3 = c + (w[2] as Vector3) * s * rng.randf_range(0.7, 1.3)
		var d: Vector3 = c + Vector3(0, -s * rng.randf_range(0.6, 1.1), 0)
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


# ---------- помощники ----------

func _stain(tex: Texture2D, pos: Vector3, up: Vector3, size: float, col: Color, depth: float) -> void:
	var d := Decal.new()
	d.texture_albedo = tex
	d.modulate = col
	d.size = Vector3(size, depth, size * rng.randf_range(0.7, 1.0))
	d.position = pos
	if up == Vector3.DOWN:
		d.rotation.x = PI
	d.rotation.y = rng.randf() * TAU
	d.normal_fade = 0.5
	add_child(d)
