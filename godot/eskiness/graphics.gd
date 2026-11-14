extends RefCounted
## Качество графики (настройка «Графика», промпт 14.11 16:47 — оптимизация для слабых ПК).
##   0 — низкая:  без SSAO/SSR/объёмного тумана/свечения, тени только у фонарика, рендер 3D в 70% разрешения,
##                 трава на поверхности (40%) и пыль — меньше, тени мелкие;
##   1 — средняя: без SSR и объёмного тумана, SSAO упрощённый, тени 2048, без MSAA (FXAA), трава 70%;
##   2 — высокая: всё как было.
## Применяется к уже созданным узлам; исходные значения запоминаются в meta, чтобы можно было вернуть.

const NAMES := ["низкая", "средняя", "высокая"]


static func apply(tree: SceneTree, q: int) -> void:
	if tree == null or tree.root == null:
		return
	q = clampi(q, 0, 2)
	var full := RenderingServer.get_current_rendering_method() == "forward_plus"
	var vp := tree.root
	# разрешение 3D и сглаживание
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = [0.7, 1.0, 1.0][q]
	vp.msaa_3d = Viewport.MSAA_2X if q == 2 else Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if q == 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	# размер карт теней (видеопамять и время на отрисовку теней)
	vp.positional_shadow_atlas_size = [1024, 2048, 4096][q]
	RenderingServer.directional_shadow_atlas_set_size([1024, 2048, 4096][q], true)
	RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_LOW if q < 2 else RenderingServer.ENV_SSAO_QUALITY_MEDIUM,
		q < 2, 0.5, 2, 50.0, 300.0)
	RenderingServer.environment_set_volumetric_fog_filter_active(q == 2)
	# эффекты окружения
	for we in tree.root.find_children("*", "WorldEnvironment", true, false):
		var e: Environment = we.environment
		if e == null:
			continue
		if not e.has_meta("q_orig"):
			e.set_meta("q_orig", [e.ssao_enabled, e.ssr_enabled, e.volumetric_fog_enabled, e.glow_enabled])
		var o: Array = e.get_meta("q_orig")
		e.ssao_enabled = bool(o[0]) and full and q >= 1
		e.ssr_enabled = bool(o[1]) and full and q == 2
		e.volumetric_fog_enabled = bool(o[2]) and full and q == 2
		e.glow_enabled = bool(o[3]) and q >= 1
	# тени ламп: на низкой — только у фонарика (SpotLight)
	for l in tree.root.find_children("*", "Light3D", true, false):
		if not l.has_meta("q_shadow"):
			l.set_meta("q_shadow", l.shadow_enabled)
		var on: bool = l.get_meta("q_shadow")
		l.shadow_enabled = on and (q >= 1 or l is SpotLight3D)
	# трава (MultiMesh) и частицы — на низкой меньше
	for mmi in tree.root.find_children("*", "MultiMeshInstance3D", true, false):
		var mm: MultiMesh = mmi.multimesh
		if mm == null or mm.instance_count < 1000:
			continue
		mm.visible_instance_count = int(mm.instance_count * [0.4, 0.7, 1.0][q]) if q < 2 else -1
	for p in tree.root.find_children("*", "GPUParticles3D", true, false):
		if not p.has_meta("q_amount"):
			p.set_meta("q_amount", p.amount)
		var a: int = p.get_meta("q_amount")
		var want := maxi(int(a * 0.35), 1) if q == 0 and a >= 100 else a
		if p.amount != want:
			p.amount = want
