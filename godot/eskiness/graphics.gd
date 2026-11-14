extends RefCounted
## Настройки графики (промпты 14.11 16:47 и 17:36): пресет «низкая / средняя / высокая» + каждый эффект отдельно.
## Значения хранит menu.gd (ключи g_* в user://settings.cfg), сюда приходит словарь values.
##   g_shadows    тени ламп (0 — только у фонарика)          g_shadow_res  размер карт теней 0/1/2 → 1024/2048/4096
##   g_ssao       затенение углов (SSAO)                       g_ssr         отражения на полу (SSR)
##   g_volfog     объёмный туман                               g_glow        свечение ламп (glow)
##   g_aa         сглаживание 0 выкл / 1 FXAA / 2 MSAA 2×      g_scale       разрешение 3D, % (50–100)
##   g_grass      густота травы, %                             g_particles   пыль и мошки, %
##   g_textures   качество текстур 0/1/2 (смещение мипмапов: на низком текстуры мягче — меньше нагрузка на память видеокарты при выборке)
##   g_geometry   детализация геометрии 0/1/2 (порог LOD: на низкой у моделей раньше включаются упрощённые версии)
## Применяется к уже созданным узлам; исходные значения запоминаются в meta.

const NAMES := ["низкая", "средняя", "высокая"]

## пресеты: индекс 0/1/2 → значения ключей
const PRESETS := {
	"g_shadows": [0.0, 1.0, 1.0], "g_shadow_res": [0.0, 1.0, 2.0],
	"g_ssao": [0.0, 1.0, 1.0], "g_ssr": [0.0, 0.0, 1.0], "g_volfog": [0.0, 0.0, 1.0], "g_glow": [0.0, 1.0, 1.0],
	"g_aa": [0.0, 1.0, 2.0], "g_scale": [70.0, 100.0, 100.0],
	"g_grass": [40.0, 70.0, 100.0], "g_particles": [35.0, 100.0, 100.0],
	"g_textures": [0.0, 1.0, 2.0], "g_geometry": [0.0, 1.0, 2.0],
}


static func preset(q: int) -> Dictionary:
	var d := {}
	for k in PRESETS:
		d[k] = float(PRESETS[k][clampi(q, 0, 2)])
	return d


static func _b(v: Dictionary, k: String) -> bool:
	return float(v.get(k, PRESETS[k][1])) > 0.5


static func _i(v: Dictionary, k: String) -> int:
	return int(round(float(v.get(k, PRESETS[k][1]))))


static func _f(v: Dictionary, k: String) -> float:
	return float(v.get(k, PRESETS[k][1]))


static func apply(tree: SceneTree, v: Dictionary) -> void:
	if tree == null or tree.root == null:
		return
	var full := RenderingServer.get_current_rendering_method() == "forward_plus"
	var vp := tree.root
	# разрешение 3D, сглаживание, текстуры, геометрия
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = clampf(_f(v, "g_scale") / 100.0, 0.5, 1.0)
	var aa := _i(v, "g_aa")
	vp.msaa_3d = Viewport.MSAA_2X if aa == 2 else Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.texture_mipmap_bias = [1.5, 0.5, 0.0][clampi(_i(v, "g_textures"), 0, 2)]
	vp.mesh_lod_threshold = [6.0, 2.5, 1.0][clampi(_i(v, "g_geometry"), 0, 2)]
	# тени
	var sr: int = [1024, 2048, 4096][clampi(_i(v, "g_shadow_res"), 0, 2)]
	vp.positional_shadow_atlas_size = sr
	RenderingServer.directional_shadow_atlas_set_size(sr, true)
	RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_LOW if _i(v, "g_shadow_res") < 2 else RenderingServer.ENV_SSAO_QUALITY_MEDIUM,
		_i(v, "g_shadow_res") < 2, 0.5, 2, 50.0, 300.0)
	RenderingServer.environment_set_volumetric_fog_filter_active(_b(v, "g_volfog"))
	# эффекты окружения
	for we in tree.root.find_children("*", "WorldEnvironment", true, false):
		var e: Environment = we.environment
		if e == null:
			continue
		if not e.has_meta("q_orig"):
			e.set_meta("q_orig", [e.ssao_enabled, e.ssr_enabled, e.volumetric_fog_enabled, e.glow_enabled])
		var o: Array = e.get_meta("q_orig")
		e.ssao_enabled = bool(o[0]) and full and _b(v, "g_ssao")
		e.ssr_enabled = bool(o[1]) and full and _b(v, "g_ssr")
		e.volumetric_fog_enabled = bool(o[2]) and full and _b(v, "g_volfog")
		e.glow_enabled = bool(o[3]) and _b(v, "g_glow")
	# тени ламп: выключены — остаются только у фонарика (SpotLight)
	var sh := _b(v, "g_shadows")
	for l in tree.root.find_children("*", "Light3D", true, false):
		if not l.has_meta("q_shadow"):
			l.set_meta("q_shadow", l.shadow_enabled)
		l.shadow_enabled = bool(l.get_meta("q_shadow")) and (sh or l is SpotLight3D)
	# трава (MultiMesh): доля видимых травинок (позиции случайные — прореживается равномерно)
	var grass := clampf(_f(v, "g_grass") / 100.0, 0.0, 1.0)
	for mmi in tree.root.find_children("*", "MultiMeshInstance3D", true, false):
		var mm: MultiMesh = mmi.multimesh
		if mm == null or mm.instance_count < 1000:
			continue
		mm.visible_instance_count = -1 if grass >= 0.999 else int(mm.instance_count * grass)
	# частицы (пыль, мошки)
	var part := clampf(_f(v, "g_particles") / 100.0, 0.0, 1.0)
	for p in tree.root.find_children("*", "GPUParticles3D", true, false):
		if not p.has_meta("q_amount"):
			p.set_meta("q_amount", p.amount)
		var a: int = p.get_meta("q_amount")
		p.visible = part > 0.0
		var want := maxi(int(round(a * part)), 1)
		if p.amount != want:
			p.amount = want
