extends "res://scripts/slot/slot_machine_base.gd"
# Часть slot_machine.gd: 3D-модель автомата (корпус, барабаны, неон, грязь, заслонки, лоток, яблоки).


## Перед автомата — +Z.
func _build() -> void:
	var body := _worn(Color(0.34, 0.04, 0.05), false, 0.28, 0.7, 0.6)
	var trim := _worn(Color(0.62, 0.5, 0.26), true, 0.0, 0.6, 0.5)
	var black := _mat(Color(0.015, 0.015, 0.015))
	# всё видимое — в rig: он увеличен в K раз и стоит на подиуме
	rig = Node3D.new()
	rig.scale = Vector3.ONE * K
	rig.position = Vector3(0, PED, RIG_Z)
	add_child(rig)
	_build_extras(body, trim, black)
	# корпус: низ, полость под барабаны (бока, задник, рамка окна), верх, вывеска
	var e2 := EX * 2.0
	_box(rig, Vector3(0.8 + e2, 0.8, 0.6), Vector3(0, 0.4, 0), body)
	for sx in [-1.0, 1.0]:
		_box(rig, Vector3(0.1, 0.4, 0.6), Vector3((0.35 + EX) * sx, 0.98, 0), body)
	_box(rig, Vector3(0.6 + e2, 0.4, 0.1), Vector3(0, 0.98, -0.25), black)
	_box(rig, Vector3(0.8 + e2, 0.04, 0.6), Vector3(0, 1.18, 0), body)
	_box(rig, Vector3(0.62 + e2, 0.05, 0.05), Vector3(0, 1.14, 0.275), trim)
	_box(rig, Vector3(0.62 + e2, 0.05, 0.05), Vector3(0, 0.82, 0.275), trim)
	_box(rig, Vector3(0.62 + e2, 0.035, 0.12), Vector3(0, 1.17, 0.21), black)
	_box(rig, Vector3(0.62 + e2, 0.035, 0.12), Vector3(0, 0.79, 0.21), black)
	for k in REELS - 1:
		_box(rig, Vector3(0.018, 0.28, 0.04), Vector3((k - (REELS - 2) / 2.0) * PITCH, REEL_Y, 0.275), trim)
	for sx in [-1.0, 1.0]:
		_box(rig, Vector3(0.025, 0.32, 0.05), Vector3((0.3 + EX) * sx, REEL_Y, 0.275), trim)
	_box(rig, Vector3(0.86 + e2, 0.36, 0.66), Vector3(0, 1.38, 0), body)
	_box(rig, Vector3(0.88 + e2, 0.04, 0.68), Vector3(0, 1.2, 0), trim)
	_box(rig, Vector3(0.88 + e2, 0.04, 0.68), Vector3(0, 1.56, 0), trim)

	# барабаны: у каждого своя лента символов в SubViewport, натянутая на цилиндр
	var reel_mats: Array = []
	for ri in REELS:
		strips.append(_random_strip(level))
		var sv := SubViewport.new()
		sv.size = Vector2i(TEX, TEX * STRIP.size())
		sv.transparent_bg = false
		sv.render_target_update_mode = SubViewport.UPDATE_ONCE
		add_child(sv)
		var art := Control.new()
		art.size = Vector2(sv.size)
		art.draw.connect(_draw_strip.bind(art, ri))
		sv.add_child(art)
		strip_views.append([sv, art])
		var reel_mat := StandardMaterial3D.new()
		reel_mat.albedo_texture = sv.get_texture()
		reel_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		# промпт 16.11 03:21: контрастнее, без мерцания (текстура — снимок с мип-картами, см. _snap_strips)
		reel_mat.albedo_color = Color(0.95, 0.93, 0.9)
		reel_mat.roughness = 0.85
		reel_mat.metallic_specular = 0.2
		reel_mat.emission_enabled = true
		reel_mat.emission_texture = sv.get_texture()
		reel_mat.emission = Color(0.85, 0.8, 0.72)
		reel_mat.emission_energy_multiplier = 0.22
		reel_mats.append(reel_mat)
	var mesh := _reel_mesh()
	for i in REELS:
		var r := MeshInstance3D.new()
		r.mesh = mesh
		r.material_override = reel_mats[i]
		r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		r.position = Vector3(_reel_x(i), REEL_Y, REEL_Z)
		rig.add_child(r)
		reels.append(r)

	# вывеска
	_neon_sign(trim, black)
	screen = Label3D.new()
	screen.text = "%d КРУТКИ — %d · %d — %d" % [PACKS[0][0], PACKS[0][1], PACKS[1][0], PACKS[1][1]]
	screen.font_size = 40
	screen.pixel_size = 0.0009
	screen.outline_size = 0
	screen.width = 600.0
	screen.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	screen.modulate = Color(0.95, 0.78, 0.45)
	screen.position = Vector3(-0.05, 0.71, 0.316)
	rig.add_child(screen)
	_box(rig, Vector3(0.58, 0.1, 0.01), Vector3(-0.05, 0.71, 0.3), black)
	# лампочки по верху вывески
	for k in 11:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.3, 0.2, 0.1)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.55, 0.25)
		var b := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.022
		sm.height = 0.044
		b.mesh = sm
		b.material_override = m
		b.position = Vector3(-0.45 + k * 0.09, 1.6, 0.31)
		rig.add_child(b)
		bulbs.append(m)
	# прорезь для монет и лоток
	_box(rig, Vector3(0.08, 0.1, 0.02), Vector3(0.3 + EX, 0.71, 0.305), trim)
	_box(rig, Vector3(0.012, 0.06, 0.01), Vector3(0.3 + EX, 0.71, 0.318), black)
	_box(rig, Vector3(0.5, 0.06, 0.2), Vector3(0, 0.3, 0.36), trim)
	_box(rig, Vector3(0.46, 0.14, 0.02), Vector3(0, 0.36, 0.45), trim)
	# рычаг справа
	lever = Node3D.new()
	lever.position = Vector3(0.47 + EX, 0.9, 0.05)   # правее — не уходит в корпус (промпт 16.11 03:21)
	rig.add_child(lever)
	var rod := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.018
	cm.bottom_radius = 0.018
	cm.height = 0.45
	rod.mesh = cm
	rod.material_override = trim
	rod.position = Vector3(0.03, 0.22, 0)
	lever.add_child(rod)
	var ball := MeshInstance3D.new()
	var bs := SphereMesh.new()
	bs.radius = 0.05
	bs.height = 0.1
	ball.mesh = bs
	ball.material_override = _worn(Color(0.5, 0.07, 0.05), false, 0.15, 0.3, 0.3)
	ball.position = Vector3(0.03, 0.46, 0)
	lever.add_child(ball)
	_box(rig, Vector3(0.1, 0.12, 0.12), Vector3(0.44 + EX, 0.9, 0.05), trim)

	_build_grime()
	_build_highlight()
	_build_shutters()

	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.5, 0.28)
	light.light_energy = 1.0
	light.omni_range = 6.0
	light.shadow_enabled = true
	light.shadow_bias = 0.12          # без «ряби» теней на крутящихся барабанах
	light.shadow_normal_bias = 2.5
	light.position = Vector3(0, 1.3, 0.75)
	rig.add_child(light)

	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	var top := PED + 2.0 * K
	shape.size = Vector3((0.9 + EX * 2.0) * K, top, 0.68 * K)
	cs.shape = shape
	cs.position = Vector3(0, top / 2.0, RIG_Z)
	add_child(cs)


## Лента барабана ri: цвет старой кости, тёмные полосы между ячейками, пятна и царапины.
func _draw_strip(art: Control, ri: int) -> void:
	var strip: Array = strips[ri]
	art.draw_rect(Rect2(Vector2.ZERO, art.size), Color(0.66, 0.61, 0.51))
	var gr := RandomNumberGenerator.new()
	gr.seed = 66 + ri
	for i in strip.size():
		var r := Rect2(0, i * TEX, TEX, TEX)
		art.draw_rect(Rect2(0, i * TEX, TEX, 3), Color(0.36, 0.3, 0.24))
		art.draw_rect(Rect2(0, i * TEX + 3, TEX, 2), Color(0.55, 0.49, 0.4))
		Sym.draw(art, strip[i], r.grow(-TEX * 0.1))
	for k in 90:
		var p := Vector2(gr.randi_range(0, TEX - 2), gr.randi_range(0, TEX * strip.size() - 2))
		var sz := Vector2(gr.randi_range(1, 3), gr.randi_range(1, 2))
		art.draw_rect(Rect2(p, sz), Color(0.25, 0.18, 0.12, gr.randf_range(0.3, 0.7)))
	for k in 14:
		var p := Vector2(gr.randi_range(0, TEX), gr.randi_range(0, TEX * strip.size()))
		art.draw_line(p, p + Vector2(gr.randf_range(-12, 12), gr.randf_range(-4, 4)), Color(0.85, 0.8, 0.7, 0.35), 1.0)
	# вуаль убрана (промпт 16.11 03:21) — символы контрастнее


func _redraw_strips() -> void:
	for v in strip_views:
		(v[1] as Control).queue_redraw()
		(v[0] as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE
	_snap_strips()


## Снимок лент в ImageTexture с мип-картами: у ViewportTexture их нет — на удалении символы рябили.
func _snap_strips() -> void:
	snap_gen += 1
	var gen := snap_gen
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if gen != snap_gen or not is_inside_tree():
		return
	for i in mini(strip_views.size(), reels.size()):
		var img: Image = (strip_views[i][0] as SubViewport).get_texture().get_image()
		if img == null or img.is_empty():
			continue
		img.generate_mipmaps()
		var tex := ImageTexture.create_from_image(img)
		var m := reels[i].material_override as StandardMaterial3D
		m.albedo_texture = tex
		m.emission_texture = tex


## Подсветка выигрышных линий: 12 светящихся рамок на стекле, мигают по линиям по очереди.
func _build_highlight() -> void:
	for r in 3:
		var row: Array = []
		for i in REELS:
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.no_depth_test = false
			m.albedo_color = Color(1, 0.8, 0.3, 0.0)
			var q := QuadMesh.new()
			q.size = Vector2(0.125, 0.088 if r != 1 else 0.096)
			var mi := MeshInstance3D.new()
			mi.mesh = q
			mi.material_override = m
			mi.position = Vector3(_reel_x(i), REEL_Y + (1 - r) * 0.094, 0.291)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visible = false
			rig.add_child(mi)
			row.append(mi)
		hl_cells.append(row)


func _update_highlight(delta: float) -> void:
	if hl_lines.is_empty():
		return
	hl_t -= delta
	if hl_t <= 0.0:
		hl_lines = []
		for row in hl_cells:
			for c in row:
				c.visible = false
		return
	# линии по очереди, каждая своим цветом; мигание
	var k := int(t * 1.4) % hl_lines.size()
	var cells: Array = hl_lines[k]
	var col: Color = HL_COLORS[k % HL_COLORS.size()]
	var a := 0.25 + 0.3 * (0.5 + 0.5 * sin(t * 14.0))
	for r in 3:
		for i in REELS:
			var on: bool = cells.has([r, i])
			var c: MeshInstance3D = hl_cells[r][i]
			c.visible = on
			if on:
				(c.material_override as StandardMaterial3D).albedo_color = Color(col.r, col.g, col.b, a)


## Мутное стекло перед барабанами, рваные наклейки, следы скотча, вмятины.
func _build_grime() -> void:
	# стекло: лёгкая серая муть и разводы (барабаны остаются читаемыми)
	var gs := Shader.new()
	gs.code = """shader_type spatial;
render_mode cull_disabled, depth_draw_never;
uniform sampler2D n_px : filter_nearest_mipmap, repeat_enable;
uniform sampler2D n_lin : filter_linear_mipmap, repeat_enable;
void fragment() {
	float smear = texture(n_lin, UV * vec2(1.6, 0.8) + vec2(0.3, 0.1)).r;
	float spot = texture(n_px, UV * vec2(2.4, 1.2) + vec2(0.7)).r;
	float a = 0.07 + 0.16 * smoothstep(0.45, 0.8, smear) + 0.1 * smoothstep(0.6, 0.75, spot);
	a += 0.12 * (1.0 - smoothstep(0.0, 0.25, UV.y)) * smoothstep(0.3, 0.7, spot);
	ALBEDO = vec3(0.55, 0.53, 0.48);
	ALPHA = a;
	ROUGHNESS = 0.15 + 0.6 * smoothstep(0.45, 0.8, smear);
	SPECULAR = 0.6;
}"""
	var gm := ShaderMaterial.new()
	gm.shader = gs
	gm.set_shader_parameter("n_px", _noise())
	gm.set_shader_parameter("n_lin", _noise())
	var glass := MeshInstance3D.new()
	var gq := QuadMesh.new()
	gq.size = Vector2(0.58 + EX * 2.0, 0.28)
	glass.mesh = gq
	glass.material_override = gm
	glass.position = Vector3(0, REEL_Y, 0.288)
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rig.add_child(glass)
	# наклейки: выцветшие, с оборванным краем
	_sticker(Vector3(-0.24 - EX, 0.6, 0.302), Vector2(0.15, 0.09), 0.08, Color(0.78, 0.66, 0.28), 1, 0.0)
	_sticker(Vector3(0.24 + EX, 0.16, 0.302), Vector2(0.11, 0.11), -0.25, Color(0.82, 0.8, 0.74), 2, 0.0)
	_sticker(Vector3(0.405 + EX, 0.45, 0.05), Vector2(0.14, 0.09), 0.15, Color(0.7, 0.72, 0.6), 3, PI / 2.0)
	# следы скотча: полупрозрачные пожелтевшие полоски
	for tpos in [[Vector3(0.27 + EX, 1.14, 0.306), 0.6], [Vector3(-0.3 - EX, 0.84, 0.306), -0.5], [Vector3(-0.36 - EX, 0.2, 0.302), 0.1]]:
		var tm := StandardMaterial3D.new()
		tm.albedo_color = Color(0.72, 0.64, 0.45, 0.55)
		tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tm.roughness = 0.5
		var tq := QuadMesh.new()
		tq.size = Vector2(0.1, 0.026)
		var tp := MeshInstance3D.new()
		tp.mesh = tq
		tp.material_override = tm
		tp.position = tpos[0]
		tp.rotation.z = tpos[1]
		tp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rig.add_child(tp)
	# вмятины: мягкие тёмные пятна (тень в углублении)
	var g := Gradient.new()
	g.set_color(0, Color(0.05, 0.02, 0.02, 0.4))
	g.set_offset(1, 1.0)
	g.set_color(1, Color(0.05, 0.02, 0.02, 0.0))
	var dt := GradientTexture2D.new()
	dt.gradient = g
	dt.fill = GradientTexture2D.FILL_RADIAL
	dt.fill_from = Vector2(0.5, 0.5)
	dt.fill_to = Vector2(1.0, 0.5)
	dt.width = 32
	dt.height = 32
	for d in [[Vector3(0.1, 0.24, 0.302), 0.0, Vector2(0.09, 0.06)], [Vector3(-0.401 - EX, 0.62, 0.12), -PI / 2.0, Vector2(0.12, 0.08)], [Vector3(0.2, 1.47, 0.332), 0.0, Vector2(0.07, 0.05)]]:
		var dm := StandardMaterial3D.new()
		dm.albedo_texture = dt
		dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		var dq := QuadMesh.new()
		dq.size = d[2]
		var dp := MeshInstance3D.new()
		dp.mesh = dq
		dp.material_override = dm
		dp.position = d[0]
		dp.rotation.y = d[1]
		dp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rig.add_child(dp)


## Наклейка из картинки (рисуется кодом): цветной фон, «строчки текста», значок; угол оборван,
## краска полустёрта. Пиксельная, без сглаживания.
func _sticker(pos: Vector3, size: Vector2, rot: float, col: Color, seed_: int, rot_y: float) -> void:
	var w := 48
	var h := int(48 * size.y / size.x)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + seed_
	img.fill(col)
	# «текст» — тёмные полоски строк
	for row in range(4, h - 4, 6):
		var x0 := rng.randi_range(3, 8)
		var x1 := rng.randi_range(w - 14, w - 4)
		for x in range(x0, x1):
			if rng.randf() < 0.85:
				for yy in 2:
					img.set_pixel(x, row + yy, col.darkened(0.65))
	if seed_ == 2:
		for y in h:
			for x in w:
				if Vector2(x - w * 0.5, y - h * 0.5).length() < h * 0.32 and Vector2(x - w * 0.5, y - h * 0.5).length() > h * 0.22:
					img.set_pixel(x, y, Color(0.7, 0.12, 0.08))
	# оборванный угол и потёртости
	var tear_k := rng.randf_range(0.9, 1.25)
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			if float(x) / w + float(y) / h * 0.6 + rng.randf() * 0.18 > tear_k + 0.2:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
			elif rng.randf() < 0.18:
				img.set_pixel(x, y, Color(c.r, c.g, c.b, rng.randf_range(0.2, 0.6)))
			else:
				img.set_pixel(x, y, Color(c.r * 0.85, c.g * 0.85, c.b * 0.82, 0.9))
	var tex := ImageTexture.create_from_image(img)
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.15
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.roughness = 0.85
	var q := QuadMesh.new()
	q.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.position = pos
	mi.rotation = Vector3(0, rot_y, rot)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rig.add_child(mi)


## Подиум, надстройка «777» с лампами, цветные бегущие огни по бокам корпуса.
func _build_extras(body: Material, trim: Material, black: Material) -> void:
	# подиум (вне rig — в мировых метрах)
	# подиум в цементной пыли
	var ped := _worn(Color(0.1, 0.085, 0.07), false, 0.4, 0.5, 1.0)
	ped.set_shader_parameter("dust_color", Color(0.42, 0.4, 0.37))
	_box(self, Vector3((0.9 + EX * 2.0) * K + 0.06, PED, 0.68 * K + 0.06), Vector3(0, PED / 2.0, RIG_Z), ped)
	_box(self, Vector3((0.9 + EX * 2.0) * K + 0.08, 0.03, 0.68 * K + 0.08), Vector3(0, PED, RIG_Z), trim)
	# надстройка над вывеской: арка с черепом и шипами; лампы в клетках; пасть, решётки, заклёпки, опоры
	_arch_skull(body, trim, black)
	_cage_lamps(trim)
	_maw(trim, black)
	_build_tray()
	_build_apples()
	_grilles(trim, black)
	_braces(body, trim)
	_rivets(trim)
	_hazard_bands()
	# цветные огни: по передним рёбрам корпуса и вдоль надстройки
	var palette := [Color(1, 0.15, 0.1), Color(1, 0.55, 0.1), Color(1, 0.9, 0.2), Color(0.2, 1, 0.35), Color(0.2, 0.8, 1), Color(0.6, 0.3, 1)]
	var spots: Array = []
	for k in 14:
		var y := 0.06 + k * 0.105
		spots.append(Vector3(-0.415, y, 0.305))
		spots.append(Vector3(0.415, y, 0.305))
	for k in 7:
		spots.append(Vector3(-0.27 + k * 0.09, 1.86, 0.235))
	for i in (spots.size() if USE_LEDS else 0):
		var m := StandardMaterial3D.new()
		@warning_ignore("integer_division")
		var col: Color = palette[(i / 2) % palette.size()]
		m.albedo_color = col.darkened(0.6)
		m.emission_enabled = true
		m.emission = col
		var bl := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.016
		sm.height = 0.032
		bl.mesh = sm
		bl.material_override = m
		bl.position = spots[i]
		rig.add_child(bl)
		leds.append(m)
	# хромированные полосы по бокам
	for sx in [-1.0, 1.0]:
		_box(rig, Vector3(0.012, 1.5, 0.02), Vector3((0.43 + EX) * sx, 0.78, 0.29), trim)


## Арка над вывеской: полукруг корпуса с хромовым ободом, венец из ржавых шипов, в середине — череп
## со светящимися глазами.
func _arch_skull(body: Material, trim: Material, black: Material) -> void:
	var cy := 1.58
	_cyl(rig, 0.31, 0.5, Vector3(0, cy, -0.02), Vector3(PI / 2.0, 0, 0), body, 24)
	_cyl(rig, 0.335, 0.05, Vector3(0, cy, 0.24), Vector3(PI / 2.0, 0, 0), trim, 24)
	_cyl(rig, 0.27, 0.02, Vector3(0, cy, 0.262), Vector3(PI / 2.0, 0, 0), black, 24)
	# шипы венцом
	var rust := _worn(Color(0.3, 0.16, 0.08), true, 0.0, 1.0, 0.4)
	for k in 9:
		var a := lerpf(0.2, PI - 0.2, k / 8.0)
		var long := 0.11 if k % 2 == 0 else 0.07
		var p := Vector3(cos(a) * (0.34 + long * 0.45), cy + sin(a) * (0.34 + long * 0.45), 0.2)
		_prism(rig, Vector3(0.045, long, 0.04), p, a - PI / 2.0, rust)
	# череп
	var bone := _worn(Color(0.6, 0.55, 0.44), false, 0.12, 0.35, 0.8)
	var sk := Node3D.new()
	sk.position = Vector3(0, cy + 0.13, 0.27)
	rig.add_child(sk)
	var cr := _sphere(sk, 0.1, Vector3(0, 0.02, 0), bone, 14)
	cr.scale = Vector3(1.0, 0.92, 0.7)
	var cheek := _box(sk, Vector3(0.13, 0.06, 0.08), Vector3(0, -0.06, 0.0), bone)
	cheek.rotation.x = 0.1
	var jaw := _box(sk, Vector3(0.1, 0.035, 0.07), Vector3(0, -0.105, 0.0), bone)
	jaw.rotation.x = -0.12
	for sx in [-1.0, 1.0]:
		_sphere(sk, 0.03, Vector3(0.038 * sx, -0.005, 0.052), black, 8)
		var em := _emis(Color(1.0, 0.12, 0.05), 3.0)
		_sphere(sk, 0.012, Vector3(0.038 * sx, -0.005, 0.07), em, 6)
		eye_mats.append(em)
	_prism(sk, Vector3(0.026, 0.03, 0.02), Vector3(0, -0.045, 0.066), PI, black)
	# зубы
	for k in 6:
		_box(sk, Vector3(0.013, 0.02, 0.01), Vector3(-0.034 + k * 0.0136, -0.084, 0.04), bone)
	_box(sk, Vector3(0.09, 0.006, 0.012), Vector3(0, -0.095, 0.038), black)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.15, 0.05)
	glow.light_energy = 0.35
	glow.omni_range = 0.9
	glow.position = Vector3(0, 0, 0.18)
	sk.add_child(glow)


## Лампы в проволочных клетках по углам над вывеской.
func _cage_lamps(trim: Material) -> void:
	for sx in [-1.0, 1.0]:
		var base := Vector3((0.375 + EX) * sx, 1.6, 0.2)
		_cyl(rig, 0.04, 0.03, base, Vector3.ZERO, trim, 10)
		var em := _emis(Color(1.0, 0.42, 0.12), 2.0)
		_sphere(rig, 0.032, base + Vector3(0, 0.06, 0), em, 10)
		cage_mats.append(em)
		for k in 6:
			var a := TAU * k / 6.0
			_cyl(rig, 0.004, 0.11, base + Vector3(cos(a) * 0.048, 0.065, sin(a) * 0.048), Vector3.ZERO, trim, 4)
		_cyl(rig, 0.052, 0.012, base + Vector3(0, 0.12, 0), Vector3.ZERO, trim, 10)
		_cyl(rig, 0.05, 0.006, base + Vector3(0, 0.065, 0), Vector3.ZERO, trim, 10)


## Неоновые буквы KILLBOX шрифтом меню, каждая чуть криво — будто вешали вручную.
## Тёмная подложка с хромовой рамкой.
func _neon_sign(trim: Material, black: Material) -> void:
	_box(rig, Vector3(0.78 + EX * 2.0, 0.25, 0.012), Vector3(0, 1.385, 0.334), black)
	for sy in [-1.0, 1.0]:
		_box(rig, Vector3(0.8 + EX * 2.0, 0.018, 0.02), Vector3(0, 1.385 + 0.125 * sy, 0.338), trim)
	var font: Font = null
	if ResourceLoader.exists("res://assets/fonts/RubikDirt-Regular.ttf"):
		font = load("res://assets/fonts/RubikDirt-Regular.ttf")
	var txt := "KILLBOX"
	var fs := 110
	var px := 0.0019
	var widths: Array[float] = []
	var total := 0.0
	var f: Font = font if font else ThemeDB.fallback_font
	for ch in txt:
		var wdt := f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * px * 0.92
		widths.append(wdt)
		total += wdt
	# ужимаем, чтобы надпись влезла в подложку
	var fit := minf(1.0, 0.78 / total)
	px *= fit
	total *= fit
	for i in widths.size():
		widths[i] *= fit
	var x := -total / 2.0
	var r := RandomNumberGenerator.new()
	r.seed = 13
	for i in txt.length():
		var l := Label3D.new()
		l.text = txt[i]
		if font:
			l.font = font
		l.font_size = fs
		l.pixel_size = px
		l.outline_size = 14
		l.outline_modulate = Color(0.35, 0.02, 0.0)
		l.modulate = neon_col
		l.shaded = false
		l.double_sided = false
		l.position = Vector3(x + widths[i] / 2.0, 1.385 + r.randf_range(-0.008, 0.008), 0.342)
		l.rotation.z = r.randf_range(-0.07, 0.07)
		rig.add_child(l)
		neon.append(l)
		x += widths[i]


## Лоток для монет — «пасть»: тёмный зев с красным жаром внутри, сверху и снизу зубы.
func _maw(trim: Material, black: Material) -> void:
	_box(rig, Vector3(0.48, 0.17, 0.02), Vector3(0, 0.42, 0.301), black)
	maw_mat = _emis(Color(0.9, 0.12, 0.04), 0.8)
	_box(rig, Vector3(0.42, 0.1, 0.004), Vector3(0, 0.43, 0.313), maw_mat)
	var bone := _worn(Color(0.58, 0.53, 0.42), false, 0.15, 0.6, 0.8)
	for k in 8:
		var x := -0.21 + k * 0.06
		var h := 0.05 if k % 3 == 1 else 0.035
		_prism(rig, Vector3(0.04, h, 0.03), Vector3(x, 0.505 - h / 2.0, 0.322), PI, bone)
	for k in 7:
		var x := -0.18 + k * 0.06
		var h := 0.055 if k % 2 == 0 else 0.04
		_prism(rig, Vector3(0.036, h, 0.02), Vector3(x, 0.43 + h / 2.0, 0.45), 0.0, bone)
	# «губы» — хромовая полоса
	_box(rig, Vector3(0.54, 0.03, 0.05), Vector3(0, 0.52, 0.305), trim)


## Решётки вентиляции на боках: щели с тусклым красным светом изнутри.
func _grilles(trim: Material, black: Material) -> void:
	var glow := _emis(Color(0.7, 0.1, 0.04), 0.35)
	for sx in [-1.0, 1.0]:
		_box(rig, Vector3(0.012, 0.22, 0.34), Vector3((0.401 + EX) * sx, 0.66, 0.0), black)
		_box(rig, Vector3(0.006, 0.2, 0.32), Vector3((0.398 + EX) * sx, 0.66, 0.0), glow)
		for k in 6:
			var sl := _box(rig, Vector3(0.02, 0.012, 0.34), Vector3((0.408 + EX) * sx, 0.565 + k * 0.038, 0.0), trim)
			sl.rotation.x = 0.35
		for sz in [-1.0, 1.0]:
			_box(rig, Vector3(0.025, 0.25, 0.02), Vector3((0.41 + EX) * sx, 0.66, 0.18 * sz), trim)


## Косые опоры по бокам у пола — силуэт шире книзу, как у тяжёлой станины.
func _braces(body: Material, trim: Material) -> void:
	for sx in [-1.0, 1.0]:
		var b := _box(rig, Vector3(0.05, 0.42, 0.44), Vector3((0.43 + EX) * sx, 0.19, 0.0), body)
		b.rotation.z = -0.22 * sx
		_box(rig, Vector3(0.09, 0.03, 0.5), Vector3((0.45 + EX) * sx, 0.015, 0.0), trim)


## Заклёпки по рамке окна, вывеске, рёбрам корпуса и арке.
func _rivets(trim: Material) -> void:
	var sm := SphereMesh.new()
	sm.radius = 0.009
	sm.height = 0.012
	sm.radial_segments = 6
	sm.rings = 3
	var pts: Array[Vector3] = []
	for k in 11:
		var x := -0.35 + k * 0.07
		pts.append(Vector3(x, 1.14, 0.302))
		pts.append(Vector3(x, 0.82, 0.302))
	for k in 12:
		var y := 0.1 + k * 0.095
		pts.append(Vector3(-0.385 - EX, y, 0.302))
		pts.append(Vector3(0.385 + EX, y, 0.302))
	for k in 10:
		pts.append(Vector3(-0.45 + k * 0.1, 1.236, 0.341))
		pts.append(Vector3(-0.45 + k * 0.1, 1.534, 0.341))
	for k in 7:
		var a := lerpf(0.15, PI - 0.15, k / 6.0)
		pts.append(Vector3(cos(a) * 0.3, 1.58 + sin(a) * 0.3, 0.27))
	for p in pts:
		var mi := MeshInstance3D.new()
		mi.mesh = sm
		mi.material_override = trim
		mi.position = p
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rig.add_child(mi)


## Полоса «опасно» (жёлто-чёрная, потёртая) внизу корпуса.
func _hazard_bands() -> void:
	var img := Image.create(64, 8, false, Image.FORMAT_RGBA8)
	var r := RandomNumberGenerator.new()
	r.seed = 5
	for y in 8:
		for x in 64:
			@warning_ignore("integer_division")
			var on := ((x + y) / 4) % 2 == 0
			var c := Color(0.62, 0.48, 0.1) if on else Color(0.06, 0.05, 0.04)
			if r.randf() < 0.18:
				c = c.lerp(Color(0.25, 0.2, 0.15), 0.7)
			img.set_pixel(x, y, c)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.roughness = 0.85
	var q := QuadMesh.new()
	q.size = Vector2(0.76 + EX * 2.0, 0.06)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.position = Vector3(0, 0.08, 0.302)
	rig.add_child(mi)


func _animate_style(delta: float) -> void:
	# неон: ровный с лёгким гулом; «О» барахлит — то гаснет, то трещит
	var hum := 1.0 + 0.04 * sin(t * 50.0)
	neon_off = maxf(neon_off - delta, 0.0)
	if neon_off <= 0.0 and randf() < delta * 0.35:
		neon_off = randf_range(0.08, 1.2)
	for i in neon.size():
		var k := hum
		if i == broken_letter and neon_off > 0.0 and fmod(neon_off * 17.0, 1.0) > 0.3:
			k = 0.12
		if party > 0.0:
			k *= 0.6 + 0.8 * float(int(t * 12.0 + i) % 2)
		neon[i].modulate = Color(neon_col.r * k, neon_col.g * k, neon_col.b * k)
	# глаза черепа тлеют, при выигрыше полыхают
	var eye := 2.2 + 1.2 * sin(t * 1.7)
	if party > 0.0:
		eye = 6.0 if int(t * 10.0) % 2 == 0 else 1.0
	for m in eye_mats:
		m.emission_energy_multiplier = eye
	# лампы в клетках дышат вразнобой
	for i in cage_mats.size():
		var v := 1.4 + 0.8 * sin(t * 2.1 + i * 2.4)
		if party > 0.0:
			v = 4.0 if (int(t * 8.0) + i) % 2 == 0 else 0.3
		cage_mats[i].emission_energy_multiplier = v
	if maw_mat:
		maw_mat.emission_energy_multiplier = 0.5 + 0.2 * sin(t * 1.3) + (1.2 if party > 0.0 else 0.0)


func set_level(lv: int) -> void:
	level = clampi(lv, 1, MAX_LEVEL)
	# ленты — только символами этого уровня
	for i in strips.size():
		strips[i] = _random_strip(level)
	if not strip_views.is_empty():
		_redraw_strips()
	for r in shutters.size():
		for c in shutters[r].size():
			(shutters[r][c] as Node3D).visible = not is_open(level, r, c)
	_redraw_board()


## Заслонки закрытых клеток: серая стальная пластина, полосы крест-накрест, заклёпки и навесной замок —
## клетка «заколочена» (промпт 14.11 17:40: серый металл, без цветных деталей).
func _build_shutters() -> void:
	var plate := _worn(Color(0.46, 0.47, 0.48), false, 0.15, 0.15, 0.35)
	var trim := _worn(Color(0.62, 0.63, 0.64), true, 0.0, 0.15, 0.3)
	var dark := _mat(Color(0.12, 0.12, 0.13))
	var w := PITCH - 0.02
	var h := 0.09
	var diag := sqrt(w * w + h * h)
	var ang := atan2(h, w)
	for r in ROWS:
		var row: Array = []
		for c in REELS:
			var n := Node3D.new()
			n.position = Vector3(_reel_x(c), REEL_Y + (1 - r) * 0.094, 0.274)
			rig.add_child(n)
			_box(n, Vector3(w, h, 0.008), Vector3.ZERO, plate)
			for k in 3:   # тёмные щели жалюзи
				_box(n, Vector3(w - 0.012, 0.004, 0.002), Vector3(0, -0.03 + k * 0.03, 0.005), dark)
			for sg in [-1.0, 1.0]:
				var bar := _box(n, Vector3(diag - 0.01, 0.009, 0.006), Vector3(0, 0, 0.008), trim)
				bar.rotation.z = ang * sg
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					_sphere(n, 0.005, Vector3(sx * (w / 2.0 - 0.009), sy * (h / 2.0 - 0.009), 0.006), trim, 6)
			_box(n, Vector3(0.022, 0.018, 0.008), Vector3(0, -0.012, 0.014), trim)
			_box(n, Vector3(0.012, 0.012, 0.004), Vector3(0, 0.002, 0.012), dark)
			for mi in n.get_children():
				(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			row.append(n)
		shutters.append(row)
	set_level(level)


func _build_tray() -> void:
	# дно кармана за нижними зубами пасти — на нём лежит горка
	_box(rig, Vector3(0.44, 0.012, 0.14), Vector3(0, 0.428, 0.38), _mat(Color(0.05, 0.03, 0.025)))
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	for k in TRAY_MAX:
		# та же модель, что у монеты-лута на полу (pickup_mesh.gd), в мировом размере (rig увеличен в K раз)
		var c: Node3D = PickupMesh.make("coin")[0]
		c.scale = Vector3.ONE * float(PickupMesh.SCALES["coin"]) / K
		# по всему дну лотка (промпт 14.11 19:50): каждый слой из 12 монет — сетка 4×3 со смещением,
		# следующие слои ложатся поверх
		var p := _tray_spot(k, rng)
		c.position = p
		c.rotation = Vector3(rng.randf_range(-0.25, 0.25), rng.randf() * TAU, rng.randf_range(-0.25, 0.25))
		c.visible = false
		for mi in c.get_children():
			(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rig.add_child(c)
		tray_meshes.append(c)
		tray_pos.append(c.position)
	# цель взгляда: коробка перед пастью, чуть выступает из общего коллайдера автомата
	tray_target = TrayTarget.new()
	tray_target.slot = self
	add_child(tray_target)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.5 * K, 0.2 * K, 0.16 * K)
	cs.shape = bs
	cs.position = Vector3(0, PED + 0.42 * K, RIG_Z + 0.4 * K)
	tray_target.add_child(cs)


func _tray_spot(k: int, rng: RandomNumberGenerator) -> Vector3:
	@warning_ignore("integer_division")
	var layer := k / 12
	var cell := (k * 5 + layer * 7) % 12   # перемешанный порядок ячеек
	var cx := cell % 4
	@warning_ignore("integer_division")
	var cz := cell / 4
	var w := TRAY_X * 2.0 / 4.0
	var d := (TRAY_Z1 - TRAY_Z0) / 3.0
	var x := -TRAY_X + w * (cx + rng.randf_range(0.15, 0.85))
	var z := TRAY_Z0 + d * (cz + rng.randf_range(0.15, 0.85))
	return Vector3(x, 0.437 + layer * 0.008 + rng.randf_range(0.0, 0.003), z)


## Маленькое 3D-яблоко: бурый шар, гнилой бок, черенок.
func _apple_mesh() -> Node3D:
	var n := Node3D.new()
	var body := _mat(Color(0.5, 0.15, 0.08), 0.0, 0.7)
	_sphere(n, 0.03, Vector3.ZERO, body, 10)
	_sphere(n, 0.018, Vector3(-0.016, -0.004, 0.016), _mat(Color(0.3, 0.2, 0.08), 0.0, 0.9), 8)
	_sphere(n, 0.006, Vector3(-0.02, 0.0, 0.024), _mat(Color(0.6, 0.65, 0.5), 0.0, 0.9), 6)
	_cyl(n, 0.003, 0.025, Vector3(0, 0.032, 0), Vector3(0, 0, 0.3), _mat(Color(0.25, 0.18, 0.1)), 5)
	return n


## Яблоки-«трофеи» слева от экрана: видно, сколько защит от 666 сейчас.
func _build_apples() -> void:
	for k in SHIELD_MAX:
		var a := _apple_mesh()
		a.position = Vector3(-0.41, 0.74 - k * 0.07, 0.33)
		a.visible = false
		rig.add_child(a)
		apple_props.append(a)


# ---------- кат-сцена появления 7 и 6 (промпт 14.11 19:27) ----------

func _redraw_board() -> void:
	if board_sv:
		board_art.queue_redraw()
		board_sv.render_target_update_mode = SubViewport.UPDATE_ONCE
