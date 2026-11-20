@tool
extends "res://scripts/locations/bunker/level_decor.gd"
## Заброшенное бетонное помещение: короткий общий коридор вдоль X, по две комнаты с каждой стороны.
##   север (z < 0): комнаты с центрами x = -6, 6
##   юг    (z > 0): комнаты с центрами x = -6, 6, между ними дверь


func _ready() -> void:
	rng.seed = 7
	var big := _noise_tex(11, 0.006, 3)
	var fine := _noise_tex(23, 0.04, 4)
	var cell := _noise_tex(37, 0.05, 2, FastNoiseLite.TYPE_CELLULAR)
	var crack := _noise_tex(41, 0.008, 4)
	noise_extra = [cell, crack]
	wall_mat = _concrete(big, fine, Color(0.2, 0.195, 0.185))
	floor_mat = _concrete(big, fine, Color(0.17, 0.163, 0.155), true)
	ceil_mat = _concrete(big, fine, Color(0.118, 0.114, 0.109), true)  # чуть светлее (промпт 14.11 17:26)
	wire_mat = StandardMaterial3D.new()
	wire_mat.albedo_color = Color(0.05, 0.05, 0.05)
	wire_mat.roughness = 0.5
	_build()
	var we := WorldEnvironment.new()
	we.environment = _make_env()
	add_child(we)
	# выход по лестнице на поверхность (поляна, небо, переключение окружения)
	var sf := Surface.new()
	sf.level = self
	sf.env = we.environment
	add_child(sf)
	# мелкие детали атмосферы: мошки у ламп, капли, пар, далёкие звуки (каждая — своя функция в atmosphere.gd)
	var at := Atmosphere.new()
	at.level = self
	add_child(at)


func _build() -> void:
	var w := X1 - X0 + T
	var d := ZS - ZN + T
	_box(Vector3(0, -0.15, 0), Vector3(w, 0.3, d), floor_mat)
	_box(Vector3(0, H + 0.15, 0), Vector3(w, 0.3, d), ceil_mat)

	# внешние стены
	_wall_x(ZN, X0 - T / 2, X1 + T / 2, [])
	_wall_x(ZS, X0 - T / 2, X1 + T / 2, [])
	_wall_z(X0, ZN, ZS, [])
	var east := _wall_z(X1, ZN, ZS, [])

	# стены коридора с проёмами
	_wall_x(-CW, X0, X1, [-6.0, 6.0])
	_wall_x(CW, X0, X1, [-6.0, 6.0])

	# перегородки между комнатами
	_wall_z(0.0, ZN, -CW, [])
	_wall_z(0.0, CW, ZS, [5.5])

	# балки под потолком коридора
	var x := X0 + 4.0
	while x < X1 - 0.1:
		_beam(Vector3(x, H - 0.2, 0), Vector3(0.35, 0.4, CW * 2))
		x += 4.0

	# колонны в южных комнатах
	for px in [-8.5, 8.5]:
		_column(Vector3(px, H / 2, 5.5), Vector3(0.55, H, 0.55))

	_debris()
	_lights()
	_cracks()
	_cobwebs()
	_floor_litter()
	_dust_motes()
	_low_dust()
	# проём к лестнице на поверхность — режем последним, чтобы не сбить случайную раскладку остального
	_cut_door(east, Vector3(X1, 0, 0), true)

func _make_env() -> Environment:
	var e := Environment.new()
	# телефоны (Mobile/Compatibility): SSAO, SSR и объёмного тумана там нет — не включаем их,
	# обычный туман и glow остаются; на ПК (Forward+) всё как было
	var full := RenderingServer.get_current_rendering_method() == "forward_plus"
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.01, 0.01, 0.012)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.55, 0.46)
	e.ambient_light_energy = 0.18
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = full
	e.ssao_radius = 1.0   # 18.11: AO слабее — углы не такие чёрные
	e.ssao_intensity = 1.6
	e.ssao_power = 1.4
	e.ssao_light_affect = 0.3
	e.ssr_enabled = full
	e.ssr_max_steps = 64
	e.glow_enabled = true
	e.glow_intensity = 0.7
	e.glow_bloom = 0.12
	e.glow_hdr_threshold = 0.85
	e.fog_enabled = true
	e.fog_light_color = Color(0.04, 0.04, 0.045)
	e.fog_density = 0.02
	e.fog_height = 0.6
	e.fog_height_density = 0.5
	e.volumetric_fog_enabled = full
	e.volumetric_fog_density = 0.008
	e.volumetric_fog_albedo = Color(0.8, 0.8, 0.8)
	return e
