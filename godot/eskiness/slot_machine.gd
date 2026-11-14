extends StaticBody3D
## Игровой автомат KILLBOX (слоты): E — крутка за 10 монет.
## Окно 3 ряда × 4 барабана. Барабаны — настоящие цилиндры с отпечатанной лентой символов,
## вращаются и останавливаются по очереди. 9 линий (LINES): 3 ряда, 4 малые диагонали по 3 клетки, 2 мостика.
## В рядах выигрывают 3–4 одинаковых подряд слева направо, на мостиках — только все 4.
##   3 шестёрки где угодно в окне — автомат забирает все монеты, оставляет 10 (выпадают редко).
##   3 семёрки подряд на линии — открывают сейф; если сейф уже открыт — 20 монет.
## 4 семёрки или 4 шестёрки в окне не выпадают никогда (исключены при генерации).
## Справа от автомата на стене — доска выплат. Автомат стоит в тёмной комнате и мерцает.
## Вид: над вывеской — арка с черепом и венцом из шипов, по углам лампы в проволочных клетках,
## неоновые буквы KILLBOX (одна «О» барахлит), лоток для монет — «пасть» с зубами и красным жаром,
## решётки на боках, заклёпки, косые опоры, полосы «опасно».

const Sym := preload("res://slot_symbols.gd")
const WornMetal := preload("res://worn_metal.gdshader")

const COST := 3                  # цена одной крутки в пакете «3 за 9» (для подписей)
## пакеты круток (промпт 23:57): [круток, монет]
const PACKS := [[3, 8], [6, 15]]
## баффы удачи из магазина: символ -> [прибавка к весу, круток, цена]; чем реже символ, тем дороже
const LUCK := {
	"cherry": [0.3, 6, 6], "lemon": [0.4, 6, 8], "plum": [0.5, 6, 9],
	"grape": [0.6, 6, 12], "diamond": [0.8, 3, 16], "seven": [1, 3, 20],
}
const REELS := 4
## лента барабана (одна на все барабаны, у каждого свой сдвиг): семёрки далеко друг от друга,
## поэтому в окне одного барабана больше одной семёрки не бывает
const STRIP := ["cherry", "seven", "lemon", "plum", "cherry", "grape", "six", "lemon", "seven", "cherry", "diamond", "plum"]
## Шанс символа в каждой клетке окна, %: чем ценнее, тем реже. Вес шестёрки подобран симуляцией так,
## чтобы три шестёрки в окне выпадали ≈1% круток (промпт 23:57).
## Окно разыгрывается по этим весам, затем на ленты барабанов «впечатываются» выпавшие символы.
## Выплаты в 5 раз меньше прежних (промпт 23:57): в среднем ~1.5 монеты с крутки, выигрыш в ~33% круток.
const WEIGHTS := {"cherry": 22.0, "lemon": 19.0, "plum": 17.5, "grape": 14.5, "diamond": 13.0, "seven": 10.5, "six": 3.5}
## линии — списки клеток [ряд (0 верх), барабан]; LINE_KIND — как линия платит:
##   row — 3 одинаковых подряд где угодно в ряду (барабаны 1–3 или 2–4) или все 4;
##   diag — малая диагональ из 3 клеток, все 3 одинаковых; bridge — мостик, только все 4.
const LINES := [
	[[1, 0], [1, 1], [1, 2], [1, 3]], [[0, 0], [0, 1], [0, 2], [0, 3]], [[2, 0], [2, 1], [2, 2], [2, 3]],
	[[0, 0], [1, 1], [2, 2]], [[0, 1], [1, 2], [2, 3]], [[2, 0], [1, 1], [0, 2]], [[2, 1], [1, 2], [0, 3]],
	[[1, 0], [0, 1], [0, 2], [1, 3]], [[1, 0], [2, 1], [2, 2], [1, 3]],
]
const LINE_KIND := ["row", "row", "row", "diag", "diag", "diag", "diag", "bridge", "bridge"]
## доля раскладов с тремя шестёрками, которые всё-таки остаются (остальные перебрасываются)
## шанс, что клетка повторит символ соседа слева по ряду (чаще собираются комбинации)
const STICK := 0.22
const SIX_KEEP := 0.35
## выплаты за линию: символ -> {сколько подряд слева: монет}
const PAY := {
	"cherry": {3: 4, 4: 10},
	"lemon": {3: 6, 4: 20},
	"plum": {3: 8, 4: 30},
	"grape": {3: 10, 4: 50},
	"diamond": {3: 15, 4: 150},
	"seven": {3: 30},
}
const R := 0.19            # радиус барабана
const RW := 0.125          # ширина барабана
const REEL_Y := 0.98
const REEL_Z := 0.07
const TEX := 64            # пикселей на символ в ленте (мало — крупные «пиксели», как у стен)
const K := 1.3             # во сколько раз автомат больше «базового»
const PED := 0.25          # высота подиума
const RIG_Z := 0.1         # сдвиг вперёд, чтобы задняя стенка не уходила в стену
## доска выплат на стене справа от автомата (в координатах автомата)
const BOARD_POS := Vector3(1.45, 1.6, -0.25)
const BOARD_PX := Vector2i(900, 980)
const BOARD_M := Vector2(1.35, 1.47)

var game  # game.gd (выставляет game.gd; в меню — null)
var busy := false
var credits := 0                 # оплаченные крутки
var luck := {}                   # символ -> [прибавка к весу, осталось круток]
var pack_ui: CanvasLayer
var pack_open := false
var pack_info: Label
var reels: Array[Node3D] = []
var strips: Array = []          # лента каждого барабана (12 символов), обновляется к каждой крутке
var strip_views: Array = []     # [SubViewport, Control] на барабан — перерисовка ленты
var stops: Array[int] = [0, 0, 0, 0]
var last_cell: Array[int] = [0, 0, 0, 0]
var spinning: Array[bool] = [false, false, false, false]
var lever: Node3D
var bulbs: Array[StandardMaterial3D] = []
const USE_LEDS := false     # цветные RGB-огоньки по краям корпуса (убраны по просьбе, 19:27)
var leds: Array[StandardMaterial3D] = []
var rig: Node3D
var hl_cells: Array = []        # подсветка ячеек 3×4 на стекле: [ряд][барабан]
var hl_lines: Array = []        # выигравшие линии последней крутки
var hl_t := 0.0
const HL_COLORS := [Color(1.0, 0.75, 0.25), Color(0.4, 1.0, 0.5), Color(0.4, 0.8, 1.0), Color(1.0, 0.45, 0.8), Color(1.0, 0.35, 0.2)]
var light: OmniLight3D
var screen: Label3D
var neon: Array[Label3D] = []       # буквы KILLBOX
var neon_col := Color(1.5, 0.3, 0.12)
var broken_letter := 5              # «O» мигает и гаснет
var eye_mats: Array[StandardMaterial3D] = []
var cage_mats: Array[StandardMaterial3D] = []
var maw_mat: StandardMaterial3D
var neon_off := 0.0
var party := 0.0
var t := 0.0
var tick_t := 0.0
var snd: AudioStreamPlayer3D
var snd2: AudioStreamPlayer3D


func _ready() -> void:
	_build()
	_build_board()
	snd = AudioStreamPlayer3D.new()
	snd.position = Vector3(0, 1.0, 0.3)
	snd.unit_size = 4.0
	add_child(snd)
	snd2 = AudioStreamPlayer3D.new()
	snd2.position = Vector3(0, 1.0, 0.3)
	snd2.unit_size = 4.0
	add_child(snd2)
	for i in REELS:
		stops[i] = randi() % STRIP.size()
		reels[i].rotation.x = _angle_for(stops[i])


func _mat(c: Color, metal := 0.0, rough := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m


## Шумовая текстура для состаривания (128 px, бесшовная) — одна на автомат.
var _wear_noise: NoiseTexture2D


func _noise() -> NoiseTexture2D:
	if _wear_noise == null:
		var n := FastNoiseLite.new()
		n.seed = 77
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 0.045
		n.fractal_octaves = 3
		_wear_noise = NoiseTexture2D.new()
		_wear_noise.width = 128
		_wear_noise.height = 128
		_wear_noise.seamless = true
		_wear_noise.noise = n
	return _wear_noise


## Состаренный материал (worn_metal.gdshader): облупленная краска / тусклый хром, ржавчина, пыль.
func _worn(c: Color, chrome := false, wear := 0.3, rust := 0.6, dust := 0.6) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WornMetal
	m.set_shader_parameter("n_px", _noise())
	m.set_shader_parameter("n_lin", _noise())
	m.set_shader_parameter("paint_color", c)
	m.set_shader_parameter("chrome", 1.0 if chrome else 0.0)
	m.set_shader_parameter("wear", wear)
	m.set_shader_parameter("rust", rust)
	m.set_shader_parameter("dust", dust)
	m.set_shader_parameter("base_y", global_position.y if is_inside_tree() else 0.0)
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


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
	_box(rig, Vector3(0.8, 0.8, 0.6), Vector3(0, 0.4, 0), body)
	for sx in [-1.0, 1.0]:
		_box(rig, Vector3(0.1, 0.4, 0.6), Vector3(0.35 * sx, 0.98, 0), body)
	_box(rig, Vector3(0.6, 0.4, 0.1), Vector3(0, 0.98, -0.25), black)
	_box(rig, Vector3(0.8, 0.04, 0.6), Vector3(0, 1.18, 0), body)
	_box(rig, Vector3(0.62, 0.05, 0.05), Vector3(0, 1.14, 0.275), trim)
	_box(rig, Vector3(0.62, 0.05, 0.05), Vector3(0, 0.82, 0.275), trim)
	_box(rig, Vector3(0.62, 0.035, 0.12), Vector3(0, 1.17, 0.21), black)
	_box(rig, Vector3(0.62, 0.035, 0.12), Vector3(0, 0.79, 0.21), black)
	for k in 3:
		_box(rig, Vector3(0.018, 0.28, 0.04), Vector3((k - 1) * 0.145, REEL_Y, 0.275), trim)
	for sx in [-1.0, 1.0]:
		_box(rig, Vector3(0.025, 0.32, 0.05), Vector3(0.3 * sx, REEL_Y, 0.275), trim)
	_box(rig, Vector3(0.86, 0.36, 0.66), Vector3(0, 1.38, 0), body)
	_box(rig, Vector3(0.88, 0.04, 0.68), Vector3(0, 1.2, 0), trim)
	_box(rig, Vector3(0.88, 0.04, 0.68), Vector3(0, 1.56, 0), trim)

	# барабаны: у каждого своя лента символов в SubViewport, натянутая на цилиндр
	var reel_mats: Array = []
	for ri in REELS:
		strips.append(_random_strip())
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
		reel_mat.albedo_color = Color(0.82, 0.8, 0.77)
		reel_mat.roughness = 0.7
		reel_mat.emission_enabled = true
		reel_mat.emission_texture = sv.get_texture()
		reel_mat.emission = Color(0.85, 0.8, 0.72)
		reel_mat.emission_energy_multiplier = 0.16
		reel_mats.append(reel_mat)
	var mesh := _reel_mesh()
	for i in REELS:
		var r := MeshInstance3D.new()
		r.mesh = mesh
		r.material_override = reel_mats[i]
		r.position = Vector3((i - 1.5) * 0.145, REEL_Y, REEL_Z)
		rig.add_child(r)
		reels.append(r)

	# вывеска
	_neon_sign(trim, black)
	screen = Label3D.new()
	screen.text = "3 КРУТКИ — 9 · 6 — 16"
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
	for k in 9:
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
		b.position = Vector3(-0.36 + k * 0.09, 1.6, 0.31)
		rig.add_child(b)
		bulbs.append(m)
	# прорезь для монет и лоток
	_box(rig, Vector3(0.08, 0.1, 0.02), Vector3(0.3, 0.71, 0.305), trim)
	_box(rig, Vector3(0.012, 0.06, 0.01), Vector3(0.3, 0.71, 0.318), black)
	_box(rig, Vector3(0.5, 0.06, 0.2), Vector3(0, 0.3, 0.36), trim)
	_box(rig, Vector3(0.46, 0.14, 0.02), Vector3(0, 0.36, 0.45), trim)
	# рычаг справа
	lever = Node3D.new()
	lever.position = Vector3(0.43, 0.9, 0.05)
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
	_box(rig, Vector3(0.06, 0.12, 0.12), Vector3(0.42, 0.9, 0.05), trim)

	_build_grime()
	_build_highlight()

	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.5, 0.28)
	light.light_energy = 1.0
	light.omni_range = 6.0
	light.shadow_enabled = true
	light.position = Vector3(0, 1.3, 0.75)
	rig.add_child(light)

	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	var top := PED + 2.0 * K
	shape.size = Vector3(0.9 * K, top, 0.68 * K)
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
	# вуаль поверх ленты — символы чуть блеклые, выцветшие
	art.draw_rect(Rect2(Vector2.ZERO, art.size), Color(0.55, 0.52, 0.48, 0.08))


func _w(k: String) -> float:
	var w := float(WEIGHTS[k])
	if luck.has(k):
		w *= 1.0 + float(luck[k][0])
	return w


func _weighted_symbol() -> String:
	var total := 0.0
	for k in WEIGHTS:
		total += _w(k)
	var r := randf() * total
	for k in WEIGHTS:
		r -= _w(k)
		if r <= 0.0:
			return k
	return "cherry"


func _random_strip() -> Array:
	var out: Array = []
	for i in STRIP.size():
		out.append(_weighted_symbol())
	return out


func _redraw_strips() -> void:
	for v in strip_views:
		(v[1] as Control).queue_redraw()
		(v[0] as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE


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
			mi.position = Vector3((i - 1.5) * 0.145, REEL_Y + (1 - r) * 0.094, 0.291)
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
	gq.size = Vector2(0.58, 0.28)
	glass.mesh = gq
	glass.material_override = gm
	glass.position = Vector3(0, REEL_Y, 0.288)
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rig.add_child(glass)
	# наклейки: выцветшие, с оборванным краем
	_sticker(Vector3(-0.24, 0.6, 0.302), Vector2(0.15, 0.09), 0.08, Color(0.78, 0.66, 0.28), 1, 0.0)
	_sticker(Vector3(0.24, 0.16, 0.302), Vector2(0.11, 0.11), -0.25, Color(0.82, 0.8, 0.74), 2, 0.0)
	_sticker(Vector3(0.405, 0.45, 0.05), Vector2(0.14, 0.09), 0.15, Color(0.7, 0.72, 0.6), 3, PI / 2.0)
	# следы скотча: полупрозрачные пожелтевшие полоски
	for t in [[Vector3(0.27, 1.14, 0.306), 0.6], [Vector3(-0.3, 0.84, 0.306), -0.5], [Vector3(-0.36, 0.2, 0.302), 0.1]]:
		var tm := StandardMaterial3D.new()
		tm.albedo_color = Color(0.72, 0.64, 0.45, 0.55)
		tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tm.roughness = 0.5
		var tq := QuadMesh.new()
		tq.size = Vector2(0.1, 0.026)
		var tp := MeshInstance3D.new()
		tp.mesh = tq
		tp.material_override = tm
		tp.position = t[0]
		tp.rotation.z = t[1]
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
	for d in [[Vector3(0.1, 0.24, 0.302), 0.0, Vector2(0.09, 0.06)], [Vector3(-0.401, 0.62, 0.12), -PI / 2.0, Vector2(0.12, 0.08)], [Vector3(0.2, 1.47, 0.332), 0.0, Vector2(0.07, 0.05)]]:
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
	_box(self, Vector3(0.9 * K + 0.06, PED, 0.68 * K + 0.06), Vector3(0, PED / 2.0, RIG_Z), ped)
	_box(self, Vector3(0.9 * K + 0.08, 0.03, 0.68 * K + 0.08), Vector3(0, PED, RIG_Z), trim)
	# надстройка над вывеской: арка с черепом и шипами; лампы в клетках; пасть, решётки, заклёпки, опоры
	_arch_skull(body, trim, black)
	_cage_lamps(trim)
	_maw(trim, black)
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
		_box(rig, Vector3(0.012, 1.5, 0.02), Vector3(0.43 * sx, 0.78, 0.29), trim)


# ---------- стиль: арка, череп, клетки, неон, пасть ----------

func _emis(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c.darkened(0.6)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


func _cyl(parent: Node3D, r: float, h: float, pos: Vector3, rot: Vector3, m: Material, seg := 16) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = seg
	cm.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _sphere(parent: Node3D, r: float, pos: Vector3, m: Material, seg := 10) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = seg
	sm.rings = seg / 2
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func _prism(parent: Node3D, size: Vector3, pos: Vector3, rot_z: float, m: Material) -> MeshInstance3D:
	var pm := PrismMesh.new()
	pm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = m
	mi.position = pos
	mi.rotation.z = rot_z
	parent.add_child(mi)
	return mi


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
		var base := Vector3(0.375 * sx, 1.6, 0.2)
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
	_box(rig, Vector3(0.78, 0.25, 0.012), Vector3(0, 1.385, 0.334), black)
	for sy in [-1.0, 1.0]:
		_box(rig, Vector3(0.8, 0.018, 0.02), Vector3(0, 1.385 + 0.125 * sy, 0.338), trim)
	var font: Font = null
	if ResourceLoader.exists("res://fonts/RubikDirt-Regular.ttf"):
		font = load("res://fonts/RubikDirt-Regular.ttf")
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
	var fit := minf(1.0, 0.68 / total)
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
		_box(rig, Vector3(0.012, 0.22, 0.34), Vector3(0.401 * sx, 0.66, 0.0), black)
		_box(rig, Vector3(0.006, 0.2, 0.32), Vector3(0.398 * sx, 0.66, 0.0), glow)
		for k in 6:
			var sl := _box(rig, Vector3(0.02, 0.012, 0.34), Vector3(0.408 * sx, 0.565 + k * 0.038, 0.0), trim)
			sl.rotation.x = 0.35
		for sz in [-1.0, 1.0]:
			_box(rig, Vector3(0.025, 0.25, 0.02), Vector3(0.41 * sx, 0.66, 0.18 * sz), trim)


## Косые опоры по бокам у пола — силуэт шире книзу, как у тяжёлой станины.
func _braces(body: Material, trim: Material) -> void:
	for sx in [-1.0, 1.0]:
		var b := _box(rig, Vector3(0.05, 0.42, 0.44), Vector3(0.43 * sx, 0.19, 0.0), body)
		b.rotation.z = -0.22 * sx
		_box(rig, Vector3(0.09, 0.03, 0.5), Vector3(0.45 * sx, 0.015, 0.0), trim)


## Заклёпки по рамке окна, вывеске, рёбрам корпуса и арке.
func _rivets(trim: Material) -> void:
	var sm := SphereMesh.new()
	sm.radius = 0.009
	sm.height = 0.012
	sm.radial_segments = 6
	sm.rings = 3
	var pts: Array[Vector3] = []
	for k in 9:
		var x := -0.28 + k * 0.07
		pts.append(Vector3(x, 1.14, 0.302))
		pts.append(Vector3(x, 0.82, 0.302))
	for k in 12:
		var y := 0.1 + k * 0.095
		pts.append(Vector3(-0.385, y, 0.302))
		pts.append(Vector3(0.385, y, 0.302))
	for k in 8:
		pts.append(Vector3(-0.35 + k * 0.1, 1.236, 0.341))
		pts.append(Vector3(-0.35 + k * 0.1, 1.534, 0.341))
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
	q.size = Vector2(0.76, 0.06)
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

## Цилиндр барабана вдоль оси X с развёрткой: v = 0..1 по окружности (сверху вниз по ленте).
func _reel_mesh() -> ArrayMesh:
	var k := 48
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in k:
		var a0 := TAU * j / k
		var a1 := TAU * (j + 1) / k
		var p00 := Vector3(-RW / 2, -R * sin(a0), R * cos(a0))
		var p10 := Vector3(RW / 2, -R * sin(a0), R * cos(a0))
		var p01 := Vector3(-RW / 2, -R * sin(a1), R * cos(a1))
		var p11 := Vector3(RW / 2, -R * sin(a1), R * cos(a1))
		var n0 := Vector3(0, -sin(a0), cos(a0))
		var n1 := Vector3(0, -sin(a1), cos(a1))
		var v0 := float(j) / k
		var v1 := float(j + 1) / k
		for vert in [[p00, n0, Vector2(0, v0)], [p10, n0, Vector2(1, v0)], [p11, n1, Vector2(1, v1)],
				[p00, n0, Vector2(0, v0)], [p11, n1, Vector2(1, v1)], [p01, n1, Vector2(0, v1)]]:
			st.set_normal(vert[1])
			st.set_uv(vert[2])
			st.add_vertex(vert[0])
	return st.commit()


## Угол барабана, при котором символ i стоит в среднем ряду (выше — i-1, ниже — i+1).
func _angle_for(i: int) -> float:
	return -TAU * (i + 0.5) / STRIP.size()


## Доска выплат на стене справа от автомата.
func _build_board() -> void:
	var sv := SubViewport.new()
	sv.size = BOARD_PX
	sv.transparent_bg = false
	sv.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(sv)
	var art := Control.new()
	art.size = Vector2(sv.size)
	art.draw.connect(_draw_board.bind(art))
	sv.add_child(art)
	var frame := _worn(Color(0.62, 0.5, 0.26), true, 0.0, 0.6, 0.5)
	var back := _worn(Color(0.12, 0.08, 0.05), false, 0.2, 0.4, 0.5)
	var board := Node3D.new()
	board.position = BOARD_POS
	board.rotation.y = -0.12
	add_child(board)
	var bw := BOARD_M.x + 0.08
	_box(board, Vector3(bw, 1.56, 0.03), Vector3(0, 0, -0.012), back)
	for sy in [-1.0, 1.0]:
		_box(board, Vector3(bw, 0.03, 0.04), Vector3(0, 0.775 * sy, 0), frame)
	for sx in [-1.0, 1.0]:
		_box(board, Vector3(0.03, 1.58, 0.04), Vector3(bw / 2.0 * sx, 0, 0), frame)
	var q := QuadMesh.new()
	q.size = BOARD_M
	var m := StandardMaterial3D.new()
	m.albedo_texture = sv.get_texture()
	m.emission_enabled = true
	m.emission_texture = sv.get_texture()
	m.emission_energy_multiplier = 0.35
	m.roughness = 0.9
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.position.z = 0.007
	board.add_child(mi)


## Строка, ужатая по ширине: шрифт уменьшается, пока текст не влезет.
func _fit(ci: Control, pos: Vector2, text: String, width: float, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var f := ThemeDB.fallback_font
	var fs := size
	while fs > 10 and f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
		fs -= 1
	ci.draw_string(f, pos, text, align, width, fs, col)


func _draw_board(ci: Control) -> void:
	var w := 600.0          # левая колонка — выплаты, правая — линии
	var pad := 34.0
	var inner := w - pad * 2.0
	ci.draw_rect(Rect2(Vector2.ZERO, ci.size), Color(0.12, 0.05, 0.05))
	ci.draw_rect(Rect2(Vector2(10, 10), ci.size - Vector2(20, 20)), Color(0.85, 0.62, 0.25), false, 4.0)
	ci.draw_rect(Rect2(Vector2(18, 18), ci.size - Vector2(36, 36)), Color(0.85, 0.2, 0.15, 0.6), false, 2.0)
	_fit(ci, Vector2(pad, 82), "KILLBOX", inner, 64, Color(1.0, 0.35, 0.2), HORIZONTAL_ALIGNMENT_CENTER)
	_fit(ci, Vector2(pad, 124), "ТАБЛИЦА ВЫПЛАТ", inner, 30, Color(1.0, 0.82, 0.4), HORIZONTAL_ALIGNMENT_CENTER)
	_fit(ci, Vector2(pad, 158), "3 крутки — 9 монет, 6 — 16 · 3 подряд в любом месте линии", inner, 20, Color(0.8, 0.72, 0.6), HORIZONTAL_ALIGNMENT_CENTER)
	var y := 184.0
	var text_col := Color(0.95, 0.9, 0.78)
	var rows := ["diamond", "grape", "plum", "lemon", "cherry"]
	for k in rows.size():
		var id: String = rows[k]
		if k % 2 == 0:
			ci.draw_rect(Rect2(pad - 8, y - 4, inner + 16, 92), Color(1, 1, 1, 0.04))
		var pays: Dictionary = PAY[id]
		Sym.draw(ci, id, Rect2(pad, y, 84, 84))
		var parts := PackedStringArray()
		for n in [4, 3, 2]:
			if pays.has(n):
				parts.append("×%d — %d" % [n, pays[n]])
		_fit(ci, Vector2(pad + 100, y + 54), "    ".join(parts), inner - 160, 30, text_col)
		_fit(ci, Vector2(w - pad - 70, y + 54), "%.0f%%" % float(WEIGHTS[id]), 66, 18, Color(0.7, 0.62, 0.52), HORIZONTAL_ALIGNMENT_RIGHT)
		y += 100.0
	y += 6.0
	ci.draw_line(Vector2(pad, y), Vector2(w - pad, y), Color(0.85, 0.62, 0.25, 0.7), 2.0)
	y += 18.0
	for k in 3:
		Sym.draw(ci, "seven", Rect2(pad + k * 62, y, 62, 62))
	_fit(ci, Vector2(pad + 200, y + 28), "×3 на линии — открывают сейф", inner - 200, 24, Color(1.0, 0.85, 0.4))
	_fit(ci, Vector2(pad + 200, y + 58), "сейф уже открыт — 20 монет", inner - 200, 22, text_col)
	y += 96.0
	for k in 3:
		Sym.draw(ci, "six", Rect2(pad + k * 62, y, 62, 62))
	_fit(ci, Vector2(pad + 200, y + 28), "×3 где угодно в окне —", inner - 200, 24, Color(1.0, 0.3, 0.2))
	_fit(ci, Vector2(pad + 200, y + 58), "автомат забирает всё, кроме 10", inner - 200, 22, Color(1.0, 0.3, 0.2))
	y += 92.0
	_fit(ci, Vector2(pad, y + 20), "три шестёрки — около 1% круток · 4 семёрки и 4 шестёрки не выпадают", inner, 19, Color(0.7, 0.62, 0.52), HORIZONTAL_ALIGNMENT_CENTER)
	# правая колонка: 9 линий схемами 4×3
	var x0 := w
	var cw := ci.size.x - w - pad
	ci.draw_line(Vector2(x0 - 4, 40), Vector2(x0 - 4, ci.size.y - 40), Color(0.85, 0.62, 0.25, 0.5), 2.0)
	_fit(ci, Vector2(x0, 82), "ЛИНИИ", cw, 44, Color(1.0, 0.82, 0.4), HORIZONTAL_ALIGNMENT_CENTER)
	_fit(ci, Vector2(x0, 120), "ряды, диагонали, мостики", cw, 20, Color(0.8, 0.72, 0.6), HORIZONTAL_ALIGNMENT_CENTER)
	var names := {"row": "ряд 3–4", "diag": "диагональ 3", "bridge": "мостик 4"}
	var cell := 18.0
	for li in LINES.size():
		var gx := x0 + 14 + (li % 3) * 88.0
		var gy := 150.0 + (li / 3) * 128.0
		var line: Array = LINES[li]
		for c in 4:
			for r in 3:
				var on: bool = line.has([r, c])
				ci.draw_rect(Rect2(gx + c * cell, gy + r * cell, cell - 2, cell - 2), Color(1.0, 0.45, 0.2) if on else Color(1, 1, 1, 0.08))
		for j in line.size() - 1:
			var p0: Array = line[j]
			var p1: Array = line[j + 1]
			var pa := Vector2(gx + int(p0[1]) * cell + cell / 2 - 1, gy + int(p0[0]) * cell + cell / 2 - 1)
			var pb := Vector2(gx + int(p1[1]) * cell + cell / 2 - 1, gy + int(p1[0]) * cell + cell / 2 - 1)
			ci.draw_line(pa, pb, Color(1.0, 0.85, 0.4), 2.0)
		_fit(ci, Vector2(gx, gy + 3 * cell + 22), "%d %s" % [li + 1, names[LINE_KIND[li]]], 4 * cell + 10, 14, Color(0.85, 0.8, 0.7))
	var ry := 150.0 + 3 * 128.0 + 10
	for t_ in ["Ряды: 3 одинаковых подряд", "в любом месте ряда или 4.", "Диагонали: все 3 клетки.", "Мостики: только все 4.", "Линии платят отдельно,", "выигрыши складываются."]:
		_fit(ci, Vector2(x0 + 10, ry), t_, cw - 10, 20, Color(0.9, 0.84, 0.72))
		ry += 28.0


func get_prompt(_game) -> String:
	if busy:
		return ""
	return "[E] Крутить KILLBOX (осталось %d)" % credits if credits > 0 else "[E] KILLBOX — купить крутки"


func interact(g) -> void:
	game = g
	if busy:
		return
	if credits <= 0:
		_open_packs()
		return
	credits -= 1
	# бафф удачи тратится с каждой круткой
	for k in luck.keys():
		luck[k][1] = int(luck[k][1]) - 1
	busy = true
	screen.text = "КРУТИТСЯ..."
	if g.has_method("cheat_check"):
		g.cheat_check()
	if g.has_method("save_now"):
		g.save_now()      # крутка уже списана — перезагрузка не вернёт её
	_roll_stops()
	for k in luck.keys():
		if int(luck[k][1]) <= 0:
			luck.erase(k)
	hl_lines = []
	hl_t = 0.0
	for row in hl_cells:
		for c in row:
			c.visible = false
	g.play_at("coin", global_position + Vector3(0.0, 0.7, 0.0), -10.0)
	var tw := create_tween()
	tw.tween_property(lever, "rotation:x", 1.1, 0.18).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(lever, "rotation:x", 0.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for i in REELS:
		spinning[i] = true
		var cur := reels[i].rotation.x
		var target := _angle_for(stops[i])
		# барабан крутится вниз (угол растёт): минимум 3 оборота + по обороту на каждый следующий
		var turns := 3.0 + i
		target += TAU * ceil((cur - target) / TAU + turns)
		var rt := create_tween()
		rt.tween_interval(0.15 + i * 0.05)
		rt.tween_property(reels[i], "rotation:x", target, 1.3 + i * 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		rt.tween_callback(_reel_stopped.bind(i))


## Розыгрыш окна: каждая клетка — по весам WEIGHTS; 4+ семёрки или 4+ шестёрки перебрасываем.
## Потом в ленту каждого барабана вокруг новой остановки «впечатываем» выпавшие 3 символа
## (остальная лента — тоже по весам). Ленты перерисовываются, когда барабаны уже разогнались.
func _roll_stops() -> void:
	var cols: Array = []
	for attempt in 200:
		cols = []
		var sevens := 0
		var sixes := 0
		for i in REELS:
			var col: Array = [_weighted_symbol(), _weighted_symbol(), _weighted_symbol()]
			# «липкость»: клетка иногда повторяет соседа слева по ряду — комбинации собираются чаще
			# (промпт 14.11 16:46). Шестёрки не липнут, чтобы «три шестёрки» не участились.
			if i > 0:
				for r in 3:
					var left: String = cols[i - 1][r]
					if left != "six" and randf() < STICK:
						col[r] = left
			sevens += col.count("seven")
			sixes += col.count("six")
			cols.append(col)
		if sevens <= 3 and sixes <= 3:
			break
	var n := STRIP.size()
	for i in REELS:
		stops[i] = randi() % n
		var strip := _random_strip()
		for r in 3:
			strip[(stops[i] + r - 1 + n) % n] = cols[i][r]
		strips[i] = strip
	get_tree().create_timer(0.3).timeout.connect(_redraw_strips)


## Видимое окно: 3 ряда по 4 символа (сверху вниз).
func grid() -> Array:
	var n := STRIP.size()
	var rows: Array = []
	for r in 3:
		var row: Array = []
		for i in REELS:
			row.append(strips[i][(stops[i] + r - 1 + n) % n])
		rows.append(row)
	return rows


func _reel_stopped(i: int) -> void:
	spinning[i] = false
	if game:
		game.play_at("clunk", reels[i].global_position, -8.0)
	if not spinning.has(true):
		_payout()


func _process(delta: float) -> void:
	t += delta
	# лампочки: бегущий огонёк, при выигрыше — быстро мигают все
	party = maxf(party - delta, 0.0)
	_update_highlight(delta)
	for k in bulbs.size():
		var on: bool
		if party > 0.0:
			on = int(t * 10.0) % 2 == k % 2
		else:
			on = int(t * 3.0) % 3 != k % 3
		bulbs[k].emission_energy_multiplier = 1.6 if on else 0.15
	# цветные огни: волна снизу вверх, при выигрыше — вспышки
	for i in leds.size():
		var w := sin(t * 5.0 - float(i / 2) * 0.6)
		if party > 0.0:
			leds[i].emission_energy_multiplier = 2.2 if (int(t * 12.0) + i) % 3 == 0 else 0.3
		else:
			leds[i].emission_energy_multiplier = 0.4 + 1.4 * maxf(w, 0.0)
	_animate_style(delta)
	# свечение мерцает и переливается от янтарного к красному
	var flick := 0.06 * sin(t * 2.3) + 0.04 * sin(t * 7.1) + (0.12 if randf() < 0.02 else 0.0)
	light.light_energy = 0.8 + flick + (0.35 * sin(t * 30.0) if party > 0.0 else 0.0)
	light.light_color = Color.from_hsv(0.045 + 0.03 * sin(t * 0.6), 0.75, 1.0)
	# тики при прохождении символов
	if busy and game:
		tick_t -= delta
		for i in REELS:
			if not spinning[i]:
				continue
			var cell := int(floor(reels[i].rotation.x * STRIP.size() / TAU))
			if cell != last_cell[i]:
				last_cell[i] = cell
				if tick_t <= 0.0:
					tick_t = 0.05
					snd.stream = game.snd["tick"][0]
					snd.volume_db = -17.0
					snd.pitch_scale = randf_range(0.9, 1.1)
					snd.play()


func _payout() -> void:
	busy = false
	var g := grid()
	var sixes := 0
	for row in g:
		sixes += row.count("six")
	if sixes >= 3:
		var have: int = game.inv.count("coin")
		var lost := maxi(have - 10, 0)
		if lost > 0:
			game.inv.remove("coin", lost)
		screen.text = "666 — KILLBOX ЗАБРАЛ %d" % lost
		game.hud.toast("Три шестёрки! Автомат забрал %d монет" % lost, Color(1.0, 0.35, 0.25))
		game.play_at("buzz", global_position, -6.0, 0.7)
		game.hud.hurt_flash(0.5)
		game.call_deferred("save_now")
		return
	var win := 0
	var sevens := false
	var won_lines := PackedStringArray()
	for li in LINES.size():
		var line: Array = LINES[li]
		var sym := ""
		var cells: Array = []
		var syms: Array = []
		for cl in line:
			syms.append(g[int(cl[0])][int(cl[1])])
		match LINE_KIND[li]:
			"row":
				if syms[0] == syms[1] and syms[1] == syms[2] and syms[2] == syms[3]:
					sym = syms[0]
					cells = line
				elif syms[0] == syms[1] and syms[1] == syms[2]:
					sym = syms[0]
					cells = line.slice(0, 3)
				elif syms[1] == syms[2] and syms[2] == syms[3]:
					sym = syms[1]
					cells = line.slice(1, 4)
			"diag":
				if syms[0] == syms[1] and syms[1] == syms[2]:
					sym = syms[0]
					cells = line
			"bridge":
				if syms[0] == syms[1] and syms[1] == syms[2] and syms[2] == syms[3]:
					sym = syms[0]
					cells = line
		if sym == "" or sym == "six":
			continue
		var n := cells.size()
		if sym == "seven" and n >= 3:
			sevens = true
		elif PAY.has(sym) and PAY[sym].has(n):
			win += int(PAY[sym][n])
		else:
			continue
		won_lines.append(str(li + 1))
		hl_lines.append(cells)
	var msg := ""
	if sevens:
		if game.open_safe():
			msg = "СЕЙФ ОТКРЫТ"
			game.hud.toast("777 — сейф открыт", Color(1.0, 0.85, 0.4))
		else:
			win += int(PAY["seven"][3])
	if win > 0:
		msg = (msg + " · ") if msg != "" else ""
		msg += "+%d" % win
		var tray := rig.global_transform * Vector3(0, 0.45, 0.4)
		var fwd := global_transform.basis.z
		game.spawn_loot("coin", win, tray, fwd * 1.2 + Vector3(0, 1.2, 0), 0.5)
		game.hud.toast("KILLBOX: +%d" % win, Color(1.0, 0.8, 0.4))
	if sevens or win >= 30:
		party = 2.5
		snd2.stream = game.snd["jingle"][0]
		snd2.volume_db = -10.0
		snd2.play()
	# какие линии сыграли — видно по подсветке на барабанах
	if won_lines.size() > 1:
		msg = "КОМБО ×%d · " % won_lines.size() + msg
	if won_lines.size() > 0:
		hl_t = 6.0
	screen.text = msg if msg != "" else "ПУСТО"
	if game.has_method("save_now"):
		game.call_deferred("save_now")
	_update_screen_hint()


## Экран автомата между крутками: сколько круток осталось и активная удача.
func _update_screen_hint() -> void:
	if credits <= 0 and luck.is_empty():
		return
	var parts := PackedStringArray()
	if credits > 0:
		parts.append("КРУТОК: %d" % credits)
	for k in luck:
		parts.append("%s +%d%% (%d)" % [Sym.NAMES[k].to_upper(), int(float(luck[k][0]) * 100), int(luck[k][1])])
	screen.text = (screen.text + "\n" if screen.text != "" else "") + " · ".join(parts)


# ---------- покупка круток (окно) ----------

func _open_packs() -> void:
	if pack_ui == null:
		_build_packs()
	pack_open = true
	pack_ui.visible = true
	pack_info.text = "Монет: %d" % game.inv.coins
	game.player.active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_packs() -> void:
	pack_open = false
	if pack_ui:
		pack_ui.visible = false
	if game and game.player:
		game.player.active = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(e: InputEvent) -> void:
	if pack_open and (e.is_action_pressed("ui_cancel") or e.is_action_pressed("interact") or e.is_action_pressed("inventory")):
		get_viewport().set_input_as_handled()
		if not e.is_echo():
			close_packs()


func _build_packs() -> void:
	pack_ui = CanvasLayer.new()
	pack_ui.layer = 5
	add_child(pack_ui)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	pack_ui.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	pack_ui.add_child(cc)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.03, 0.02, 0.96)
	sb.border_color = Color(0.85, 0.2, 0.1, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", sb)
	cc.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var t := Label.new()
	t.text = "KILLBOX — КРУТКИ"
	t.add_theme_font_size_override("font_size", 30)
	t.add_theme_color_override("font_color", Color(1.0, 0.4, 0.25))
	v.add_child(t)
	pack_info = Label.new()
	pack_info.add_theme_font_size_override("font_size", 20)
	pack_info.add_theme_color_override("font_color", Color(0.92, 0.8, 0.5))
	v.add_child(pack_info)
	for pk in PACKS:
		var b := Button.new()
		b.text = "%d крутки — %d монет" % [pk[0], pk[1]] if int(pk[0]) < 5 else "%d круток — %d монет" % [pk[0], pk[1]]
		b.custom_minimum_size = Vector2(320, 48)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(_buy_pack.bind(int(pk[0]), int(pk[1])))
		v.add_child(b)
	var c := Button.new()
	c.text = "Закрыть (E / Esc)"
	c.focus_mode = Control.FOCUS_NONE
	c.add_theme_font_size_override("font_size", 18)
	c.pressed.connect(close_packs)
	v.add_child(c)
	pack_ui.visible = false


func _buy_pack(n: int, price: int) -> void:
	if not game.inv.remove("coin", price):
		pack_info.text = "Не хватает монет (есть %d)" % game.inv.coins
		game.play_ui("buzz", -14.0)
		return
	credits += n
	game.play_ui("coin", -10.0)
	game.hud.toast("KILLBOX: +%d круток" % n, Color(1.0, 0.8, 0.4))
	screen.text = ""
	_update_screen_hint()
	game.save_now()
	close_packs()


## Магазин: бафф удачи на символ. Повторная покупка того же символа добавляет крутки.
func add_luck(sym: String) -> void:
	var d: Array = LUCK[sym]
	if luck.has(sym):
		luck[sym][1] = int(luck[sym][1]) + int(d[1])
	else:
		luck[sym] = [float(d[0]), int(d[1])]
	screen.text = ""
	_update_screen_hint()
