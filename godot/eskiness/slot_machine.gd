extends StaticBody3D
## Игровой автомат KILLBOX (слоты): E — крутка (крутки покупаются пакетами).
## Окно 3 ряда × 5 барабанов, но открыта только часть — окно прокачивается за монеты (LEVELS):
##   ур.1 — 1×3 (центр), 2 — 2×3, 3 — 3×3, 4 — 3×4, 5 — 3×5. Закрытые клетки — под стальными заслонками
##   и в выигрыше не участвуют. Барабаны — настоящие цилиндры с отпечатанной лентой символов,
## вращаются и останавливаются по очереди. Линии строятся под открытую область (lines_for):
##   ряды (3+ одинаковых подряд), галочки (на 2×3), диагонали по 3 клетки, мостики по 4.
##   3 шестёрки где угодно в открытом окне — автомат забирает все монеты, оставляет 10.
##   3 семёрки на линии — открывают сейф; если сейф уже открыт — 30 монет. Семёрки и шестёрки
##   есть в барабанах только на окне 3×5 (LEVEL_SYMS).
## 4+ семёрки или 4+ шестёрки в открытом окне не выпадают никогда (исключены при генерации).
## Справа от автомата на стене — доска выплат. Автомат стоит в тёмной комнате и мерцает.
## Вид: над вывеской — арка с черепом и венцом из шипов, по углам лампы в проволочных клетках,
## неоновые буквы KILLBOX (одна «О» барахлит), лоток для монет — «пасть» с зубами и красным жаром,
## решётки на боках, заклёпки, косые опоры, полосы «опасно».

const Sym := preload("res://slot_symbols.gd")
const WornMetal := preload("res://worn_metal.gdshader")

const COST := 3                  # цена одной крутки в пакете «3 за 8» (для подписей)
## пакеты круток (промпт 23:57): [круток, монет]
const PACKS := [[3, 8], [6, 15]]
## гарантированный символ из магазина (промпт 14.11 17:18): символ -> [круток, цена].
## Пока действует — после каждого прокрута этот символ ставится в случайную открытую клетку,
## где его нет. Шестёрка не продаётся.
const LUCK := {
	"cherry": [6, 4], "lemon": [6, 5], "plum": [6, 6],
	"grape": [5, 7], "diamond": [4, 9], "seven": [3, 12],
}
const REELS := 5
const ROWS := 3
## прокачка окна: LEVELS[ур-1] = [рядов, барабанов, цена перехода на этот уровень]
const LEVELS := [[1, 3, 0], [2, 3, 40], [3, 3, 80], [3, 4, 130], [3, 5, 200]]
const MAX_LEVEL := 5
## лента барабана (одна на все барабаны, у каждого свой сдвиг): семёрки далеко друг от друга,
## поэтому в окне одного барабана больше одной семёрки не бывает
const STRIP := ["cherry", "seven", "lemon", "plum", "cherry", "grape", "six", "lemon", "seven", "cherry", "diamond", "plum"]
## Шанс символа в каждой клетке окна, %: чем ценнее, тем реже.
## Окно разыгрывается по этим весам, затем на ленты барабанов «впечатываются» выпавшие символы.
const WEIGHTS := {"cherry": 22.0, "lemon": 19.0, "plum": 17.5, "grape": 14.5, "diamond": 13.0, "seven": 10.5, "six": 2.0}
## символы по уровням окна (промпт 14.11 17:40): на ур.1 только вишня, лимон, слива; дальше по символу,
## семёрки и шестёрки — только на последнем уровне (3×5). SYM_ORDER — порядок появления,
## LEVEL_SYMS[ур-1] — сколько первых символов в игре. Шансы — WEIGHTS среди доступных.
const SYM_ORDER := ["cherry", "lemon", "plum", "grape", "diamond", "seven", "six"]
const LEVEL_SYMS := [3, 4, 5, 5, 7]
## шанс, что клетка повторит символ соседа слева по ряду (чаще собираются комбинации)
const STICK := 0.15
## выплаты за линию на окне 1×3: символ -> {сколько одинаковых: монет}
const PAY := {
	"cherry": {3: 4, 4: 8, 5: 15},
	"lemon": {3: 6, 4: 12, 5: 25},
	"plum": {3: 8, 4: 16, 5: 35},
	"grape": {3: 10, 4: 25, 5: 60},
	"diamond": {3: 15, 4: 50, 5: 120},
	"seven": {3: 30},
}
## пара одинаковых подряд в ряду — только на окнах в 3 столбца (промпт 14.11 18:01), без множителя PAY_K
const PAY2 := {"cherry": 1, "lemon": 1, "plum": 1, "grape": 1, "diamond": 2}
## множитель выплат по уровню окна: чем больше линий, тем меньше платит каждая. Подобрано симуляцией
## сессий (промпт 14.11 17:56): отдача ~91–99% цены крутки с учётом пар и множителя серии.
## Семёрки (сейф / 30 монет) не уменьшаются.
const PAY_K := [1.58, 0.64, 0.55, 0.295, 0.165]
## множитель за серию (промпт 14.11 17:56): CHAIN[побед подряд перед этой круткой] — множитель выплаты.
## Проигрыш (и 666) сбрасывает серию; она живёт, пока крутишь: уход от автомата дальше CHAIN_DIST м
## или CHAIN_IDLE с без крутки — сброс.
const CHAIN := [1.0, 1.25, 1.5, 2.0]
const CHAIN_DIST := 4.0
const CHAIN_IDLE := 30.0
const R := 0.19            # радиус барабана
const RW := 0.125          # ширина барабана
const REEL_Y := 0.98
const REEL_Z := 0.07
const TEX := 64            # пикселей на символ в ленте (мало — крупные «пиксели», как у стен)
const K := 1.3             # во сколько раз автомат больше «базового»
const PED := 0.25          # высота подиума
const RIG_Z := 0.1         # сдвиг вперёд, чтобы задняя стенка не уходила в стену
## на сколько корпус шире с каждой стороны, чем у прежнего автомата на 4 барабана (пол-барабана)
const EX := 0.0725
const PITCH := 0.145      # шаг барабанов
## доска выплат на стене справа от автомата (в координатах автомата)
const BOARD_POS := Vector3(1.55, 1.6, -0.25)
const BOARD_PX := Vector2i(900, 980)
const BOARD_M := Vector2(1.35, 1.47)

var game  # game.gd (выставляет game.gd; в меню — null)
var busy := false
var credits := 0                 # оплаченные крутки
var luck := {}                   # гарантированный символ -> осталось круток
var level := MAX_LEVEL           # прокачка окна (1..MAX_LEVEL), хранится в сейве; в меню — всё открыто
var shutters: Array = []         # заслонки закрытых клеток: [ряд][барабан]
var pack_up: Button              # кнопка прокачки в окне покупки круток
var streak := 0                  # побед подряд (множитель серии CHAIN)
var last_spin_t := 0.0
var tray_coins := 0              # выигрыш, лежащий в лотке (в сейве); забирается на E
var tray_shown := 0              # сколько монеток горки сейчас видно
var tray_meshes: Array[MeshInstance3D] = []
var tray_target: StaticBody3D    # отдельная цель взгляда — лоток
var board_sv: SubViewport        # доска выплат — перерисовывается при прокачке
var board_art: Control
var pack_ui: CanvasLayer
var pack_open := false
var pack_info: Label
var reels: Array[Node3D] = []
var strips: Array = []          # лента каждого барабана (12 символов), обновляется к каждой крутке
var strip_views: Array = []     # [SubViewport, Control] на барабан — перерисовка ленты
var stops: Array[int] = [0, 0, 0, 0, 0]
var last_cell: Array[int] = [0, 0, 0, 0, 0]
var spinning: Array[bool] = [false, false, false, false, false]
var lever: Node3D
var bulbs: Array[StandardMaterial3D] = []
const USE_LEDS := false     # цветные RGB-огоньки по краям корпуса (убраны по просьбе, 19:27)
var leds: Array[StandardMaterial3D] = []
var rig: Node3D
var hl_cells: Array = []        # подсветка ячеек 3×5 на стекле: [ряд][барабан]
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
	lever.position = Vector3(0.43 + EX, 0.9, 0.05)
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
	_box(rig, Vector3(0.06, 0.12, 0.12), Vector3(0.42 + EX, 0.9, 0.05), trim)

	_build_grime()
	_build_highlight()
	_build_shutters()

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
	# вуаль поверх ленты — символы чуть блеклые, выцветшие
	art.draw_rect(Rect2(Vector2.ZERO, art.size), Color(0.55, 0.52, 0.48, 0.08))


## Символы, которые есть в барабанах на уровне lv.
static func syms_for(lv: int) -> Array:
	return SYM_ORDER.slice(0, int(LEVEL_SYMS[clampi(lv, 1, MAX_LEVEL) - 1]))


## С какого уровня окна символ появляется в барабанах.
static func sym_level(sym: String) -> int:
	for lv in range(1, MAX_LEVEL + 1):
		if syms_for(lv).has(sym):
			return lv
	return MAX_LEVEL


static func _weighted_symbol(lv: int) -> String:
	var syms := syms_for(lv)
	var total := 0.0
	for k in syms:
		total += float(WEIGHTS[k])
	var r := randf() * total
	for k in syms:
		r -= float(WEIGHTS[k])
		if r <= 0.0:
			return k
	return "cherry"


static func _random_strip(lv: int) -> Array:
	var out: Array = []
	for i in STRIP.size():
		out.append(_weighted_symbol(lv))
	return out


## Открыта ли клетка [ряд r, барабан c] на уровне прокачки lv.
## Ряды: 1 — только средний, 2 — верхний и средний, 3 — все. Барабаны: 3 центральных (2–4),
## на ур.4 добавляется левый, на ур.5 — правый.
static func is_open(lv: int, r: int, c: int) -> bool:
	var d: Array = LEVELS[clampi(lv, 1, MAX_LEVEL) - 1]
	var rows: int = d[0]
	var cols: int = d[1]
	var rok := rows >= 3 or (rows == 2 and r <= 1) or (rows == 1 and r == 1)
	var c0 := 1 if cols <= 3 else 0
	return rok and c >= c0 and c < c0 + cols


## Есть ли в столбце c открытые клетки (только такие барабаны крутятся).
static func col_open(lv: int, c: int) -> bool:
	for r in ROWS:
		if is_open(lv, r, c):
			return true
	return false


## Сколько символов sym в открытой части окна g.
static func count_open(g: Array, lv: int, sym: String) -> int:
	var n := 0
	for r in ROWS:
		for c in REELS:
			if is_open(lv, r, c) and g[r][c] == sym:
				n += 1
	return n


## Линии на уровне lv: [[клетки [ряд, барабан]], вид]. Только целиком в открытой области.
##   row — открытая часть ряда, платят 3+ одинаковых подряд; v — галочка из 3 клеток (на 2×3);
##   diag — диагональ из 3 клеток; bridge — мостик из 4, только все 4.
static func lines_for(lv: int) -> Array:
	var out: Array = []
	for r in ROWS:
		var cells: Array = []
		for c in REELS:
			if is_open(lv, r, c):
				cells.append([r, c])
		if cells.size() >= 3:
			out.append([cells, "row"])
	var shapes: Array = []
	var three_rows := is_open(lv, 0, 2) and is_open(lv, 2, 2)
	for c in REELS - 2:
		if three_rows:
			shapes.append([[[0, c], [1, c + 1], [2, c + 2]], "diag"])
			shapes.append([[[2, c], [1, c + 1], [0, c + 2]], "diag"])
		else:
			for r in ROWS - 1:
				shapes.append([[[r, c], [r + 1, c + 1], [r, c + 2]], "v"])
				shapes.append([[[r + 1, c], [r, c + 1], [r + 1, c + 2]], "v"])
	for c in REELS - 3:
		shapes.append([[[1, c], [0, c + 1], [0, c + 2], [1, c + 3]], "bridge"])
		shapes.append([[[1, c], [2, c + 1], [2, c + 2], [1, c + 3]], "bridge"])
	for sh in shapes:
		var ok := true
		for cl in sh[0]:
			if not is_open(lv, int(cl[0]), int(cl[1])):
				ok = false
		if ok:
			out.append(sh)
	return out


## Гарантированный символ: ставим sym в случайную открытую клетку, где его нет.
## Клетки уже выигравших линий не трогаем (если есть другие) — гарант только добавляет шансы.
## Семёрку не ставим, если в окне их уже 3 (4 семёрки не бывает).
static func _guarantee(g: Array, lv: int, sym: String) -> void:
	if not syms_for(lv).has(sym):
		return
	if sym == "six" or (sym == "seven" and count_open(g, lv, "seven") >= 3):
		return
	var keep: Array = []
	for cells in evaluate(g, lv, lines_for(lv))["lines"]:
		keep.append_array(cells)
	var cand: Array = []
	var spare: Array = []
	for r in ROWS:
		for c in REELS:
			if is_open(lv, r, c) and g[r][c] != sym:
				cand.append([r, c])
				if not keep.has([r, c]):
					spare.append([r, c])
	if not spare.is_empty():
		cand = spare
	if cand.is_empty():
		return
	var p: Array = cand[randi() % cand.size()]
	g[p[0]][p[1]] = sym


## Розыгрыш окна 3×5: каждая клетка — по весам WEIGHTS, иногда повторяет соседа слева
## («липкость» STICK, шестёрки не липнут); затем гарантированные символы guar.
## 4+ семёрки или 4+ шестёрки в открытой области перебрасываем.
static func roll_window(lv: int, guar: Array) -> Array:
	var g: Array = []
	for attempt in 200:
		g = []
		for r in ROWS:
			var row: Array = []
			for c in REELS:
				var s := _weighted_symbol(lv)
				if c > 0:
					var left: String = row[c - 1]
					if left != "six" and randf() < STICK:
						s = left
				row.append(s)
			g.append(row)
		for sym in guar:
			_guarantee(g, lv, String(sym))
		if count_open(g, lv, "seven") <= 3 and count_open(g, lv, "six") <= 3:
			break
	return g


## для симуляции баланса: если не пусто — вместо PAY_K
static var pay_k_test: Array = []


## Множитель серии после streak побед подряд.
static func chain_mult(streak_: int) -> float:
	return float(CHAIN[clampi(streak_, 0, CHAIN.size() - 1)])


## Выплата за n символов sym на линии при уровне окна lv (0 — не платит).
static func pay_for(sym: String, n: int, lv: int) -> int:
	if not PAY.has(sym) or not PAY[sym].has(n):
		return 0
	if sym == "seven":
		return int(PAY[sym][n])
	var ks: Array = pay_k_test if not pay_k_test.is_empty() else PAY_K
	return maxi(1, roundi(float(PAY[sym][n]) * float(ks[clampi(lv, 1, MAX_LEVEL) - 1])))


## Итог крутки: {"six": забирает ли автомат, "win": монет, "sevens": 3 семёрки на линии,
## "lines": [клетки выигравших линий], "ids": номера линий}.
static func evaluate(g: Array, lv: int, lines: Array) -> Dictionary:
	var res := {"six": false, "win": 0, "sevens": false, "big": false, "lines": [], "ids": PackedStringArray()}
	if count_open(g, lv, "six") >= 3:
		res["six"] = true
		return res
	for li in lines.size():
		var line: Array = lines[li][0]
		var kind: String = lines[li][1]
		var syms: Array = []
		for cl in line:
			syms.append(g[int(cl[0])][int(cl[1])])
		var sym := ""
		var cells: Array = []
		if kind == "row":
			# самая длинная серия одинаковых подряд (в ряду из 5 клеток две серии по 3 не бывают)
			var i := 0
			while i < syms.size():
				var j := i
				while j + 1 < syms.size() and syms[j + 1] == syms[i]:
					j += 1
				if j - i + 1 >= 3:
					sym = syms[i]
					cells = line.slice(i, j + 1)
					break
				i = j + 1
			# окна шириной 3 столбца (1×3, 2×3, 3×3): пара одинаковых подряд в центральном ряду —
			# маленькая награда PAY2 (серию не продлевает)
			if sym == "" and int(line[0][0]) == 1 and int(LEVELS[clampi(lv, 1, MAX_LEVEL) - 1][1]) == 3:
				for k in syms.size() - 1:
					if syms[k] == syms[k + 1] and PAY2.has(syms[k]):
						sym = syms[k]
						cells = line.slice(k, k + 2)
						break
		else:
			var same := true
			for s in syms:
				if s != syms[0]:
					same = false
			if same:
				sym = syms[0]
				cells = line
		if sym == "" or sym == "six":
			continue
		var n := cells.size()
		if n == 2:
			res["win"] = int(res["win"]) + int(PAY2[sym])
		elif sym == "seven":
			res["sevens"] = true
			res["big"] = true
		elif PAY.has(sym) and PAY[sym].has(n):
			res["win"] = int(res["win"]) + pay_for(sym, n, lv)
			res["big"] = true
		else:
			continue
		res["ids"].append(str(li + 1))
		res["lines"].append(cells)
	return res


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
	for t in [[Vector3(0.27 + EX, 1.14, 0.306), 0.6], [Vector3(-0.3 - EX, 0.84, 0.306), -0.5], [Vector3(-0.36 - EX, 0.2, 0.302), 0.1]]:
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
		_box(rig, Vector3(0.012, 1.5, 0.02), Vector3((0.43 + EX) * sx, 0.78, 0.29), trim)


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
	board_sv = sv
	board_art = art
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
	_fit(ci, Vector2(pad, 158), "%d крутки — %d монет, %d — %d · окно %s (ур. %d из %d)" % [PACKS[0][0], PACKS[0][1], PACKS[1][0], PACKS[1][1], level_name(level), level, MAX_LEVEL], inner, 20, Color(0.8, 0.72, 0.6), HORIZONTAL_ALIGNMENT_CENTER)
	var y := 184.0
	var text_col := Color(0.95, 0.9, 0.78)
	var rows := ["diamond", "grape", "plum", "lemon", "cherry"]
	for k in rows.size():
		var id: String = rows[k]
		if k % 2 == 0:
			ci.draw_rect(Rect2(pad - 8, y - 4, inner + 16, 92), Color(1, 1, 1, 0.04))
		var pays: Dictionary = PAY[id]   # выплаты — для текущего окна (pay_for)
		Sym.draw(ci, id, Rect2(pad, y, 84, 84))
		if not syms_for(level).has(id):
			ci.draw_rect(Rect2(pad - 8, y - 4, inner + 16, 92), Color(0.12, 0.05, 0.05, 0.75))
			_fit(ci, Vector2(pad + 100, y + 54), "появится на окне %s" % level_name(sym_level(id)), inner - 160, 26, Color(0.7, 0.62, 0.52))
			y += 100.0
			continue
		var parts := PackedStringArray()
		for n in [5, 4, 3]:
			if pays.has(n) and n <= int(LEVELS[level - 1][1]):
				parts.append("×%d — %d" % [n, pay_for(id, n, level)])
		if int(LEVELS[level - 1][1]) == 3 and PAY2.has(id):
			parts.append("×2 — %d" % int(PAY2[id]))
		_fit(ci, Vector2(pad + 100, y + 54), "    ".join(parts), inner - 160, 30, text_col)
		_fit(ci, Vector2(w - pad - 70, y + 54), "%.0f%%" % float(WEIGHTS[id]), 66, 18, Color(0.7, 0.62, 0.52), HORIZONTAL_ALIGNMENT_RIGHT)
		y += 100.0
	y += 6.0
	ci.draw_line(Vector2(pad, y), Vector2(w - pad, y), Color(0.85, 0.62, 0.25, 0.7), 2.0)
	y += 18.0
	for k in 3:
		Sym.draw(ci, "seven", Rect2(pad + k * 62, y, 62, 62))
	_fit(ci, Vector2(pad + 200, y + 28), "×3 на линии — открывают сейф", inner - 200, 24, Color(1.0, 0.85, 0.4))
	_fit(ci, Vector2(pad + 200, y + 58), "сейф уже открыт — %d монет" % int(PAY["seven"][3]), inner - 200, 22, text_col)
	y += 96.0
	for k in 3:
		Sym.draw(ci, "six", Rect2(pad + k * 62, y, 62, 62))
	_fit(ci, Vector2(pad + 200, y + 28), "×3 где угодно в окне —", inner - 200, 24, Color(1.0, 0.3, 0.2))
	_fit(ci, Vector2(pad + 200, y + 58), "автомат забирает всё, кроме 10", inner - 200, 22, Color(1.0, 0.3, 0.2))
	y += 92.0
	if not syms_for(level).has("seven"):
		var top := y - 92.0 - 96.0 - 4.0
		ci.draw_rect(Rect2(pad - 8, top, inner + 16, 188), Color(0.12, 0.05, 0.05, 0.72))
		_fit(ci, Vector2(pad, top + 104), "семёрки и шестёрки — только на окне %s" % level_name(MAX_LEVEL), inner, 28, Color(1.0, 0.82, 0.4), HORIZONTAL_ALIGNMENT_CENTER)
	_fit(ci, Vector2(pad, y + 20), "СЕРИЯ ПОБЕД: ×1 → ×1.25 → ×1.5 → ×2 · проигрыш, уход или 30 с без крутки — сброс", inner, 19, Color(0.7, 0.62, 0.52), HORIZONTAL_ALIGNMENT_CENTER)
	# правая колонка: линии открытого окна схемами 5×3 (закрытые клетки — тёмные)
	var x0 := w
	var cw := ci.size.x - w - pad
	ci.draw_line(Vector2(x0 - 4, 40), Vector2(x0 - 4, ci.size.y - 40), Color(0.85, 0.62, 0.25, 0.5), 2.0)
	_fit(ci, Vector2(x0, 82), "ЛИНИИ", cw, 44, Color(1.0, 0.82, 0.4), HORIZONTAL_ALIGNMENT_CENTER)
	_fit(ci, Vector2(x0, 120), "окно %s · линий: %d" % [level_name(level), lines_for(level).size()], cw, 20, Color(0.8, 0.72, 0.6), HORIZONTAL_ALIGNMENT_CENTER)
	var names := {"row": "ряд", "v": "галочка", "diag": "диагональ", "bridge": "мостик"}
	var cell := 17.0
	var lines := lines_for(level)
	for li in lines.size():
		var gx := x0 + 10 + (li % 3) * 88.0
		var gy := 146.0 + (li / 3) * 100.0
		var line: Array = lines[li][0]
		for c in REELS:
			for r in ROWS:
				var on: bool = line.has([r, c])
				var col := Color(1.0, 0.45, 0.2) if on else (Color(1, 1, 1, 0.12) if is_open(level, r, c) else Color(1, 1, 1, 0.03))
				ci.draw_rect(Rect2(gx + c * cell, gy + r * cell, cell - 2, cell - 2), col)
		for j in line.size() - 1:
			var p0: Array = line[j]
			var p1: Array = line[j + 1]
			var pa := Vector2(gx + int(p0[1]) * cell + cell / 2 - 1, gy + int(p0[0]) * cell + cell / 2 - 1)
			var pb := Vector2(gx + int(p1[1]) * cell + cell / 2 - 1, gy + int(p1[0]) * cell + cell / 2 - 1)
			ci.draw_line(pa, pb, Color(1.0, 0.85, 0.4), 2.0)
		_fit(ci, Vector2(gx, gy + 3 * cell + 20), "%d %s" % [li + 1, names[lines[li][1]]], 5 * cell + 6, 14, Color(0.85, 0.8, 0.7))
	var ry := 146.0 + 5 * 100.0 + 14
	for t_ in ["Ряды: 3–5 одинаковых подряд.", "Галочки, диагонали: все 3.", "Мостики: только все 4.", "Под заслонками не играет.", "Пара (×2) — только центр.", "ряд на окнах в 3 столбца."]:
		_fit(ci, Vector2(x0 + 10, ry), t_, cw - 10, 20, Color(0.9, 0.84, 0.72))
		ry += 28.0


func get_prompt(_game) -> String:
	if tray_coins > 0 and not busy:
		return "[E] Забрать %d монет" % tray_coins
	if busy:
		return ""
	return "[E] Крутить KILLBOX (осталось %d)" % credits if credits > 0 else "[E] KILLBOX — купить крутки"


func interact(g) -> void:
	game = g
	if busy:
		return
	# пока в лотке монеты — E сначала забирает их
	if tray_coins > 0:
		take_tray()
		return
	if credits <= 0:
		_open_packs()
		return
	credits -= 1
	# гарантированный символ тратится с каждой круткой
	for k in luck.keys():
		luck[k] = int(luck[k]) - 1
	busy = true
	screen.text = "КРУТИТСЯ..."
	if g.has_method("cheat_check"):
		g.cheat_check()
	if g.has_method("save_now"):
		g.save_now()      # крутка уже списана — перезагрузка не вернёт её
	_roll_stops()
	for k in luck.keys():
		if int(luck[k]) <= 0:
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
		# закрытые столбцы стоят на месте: ни вращения, ни тиков, ни «clunk» (промпт 14.11 17:51)
		if not col_open(level, i):
			spinning[i] = false
			continue
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


## Розыгрыш окна (roll_window) с гарантированными символами; потом в ленту каждого барабана
## вокруг новой остановки «впечатываем» выпавшие 3 символа (остальная лента — по весам).
## Ленты перерисовываются, когда барабаны уже разогнались.
func _roll_stops() -> void:
	var g := roll_window(level, luck.keys())
	var n := STRIP.size()
	for i in REELS:
		if not col_open(level, i):
			continue   # закрытый барабан не крутится — его лента не меняется
		stops[i] = randi() % n
		var strip := _random_strip(level)
		for r in ROWS:
			strip[(stops[i] + r - 1 + n) % n] = g[r][i]
		strips[i] = strip
	get_tree().create_timer(0.3).timeout.connect(_redraw_strips)


## Видимое окно: 3 ряда по 5 символов (сверху вниз), включая закрытые клетки.
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
	# серия живёт, пока крутишь: ушёл от автомата или долго не крутил — сброс
	if streak > 0 and not busy and game and game.get("player"):
		var far: bool = game.player.global_position.distance_to(global_position) > CHAIN_DIST
		if far or t - last_spin_t > CHAIN_IDLE:
			streak = 0
			screen.text = "СЕРИЯ СГОРЕЛА"
			_update_screen_hint()
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
	var res := evaluate(g, level, lines_for(level))
	if res["six"]:
		var have: int = game.inv.count("coin")
		var lost := maxi(have - 10, 0)
		if lost > 0:
			game.inv.remove("coin", lost)
		screen.text = "666 — KILLBOX ЗАБРАЛ %d" % lost
		game.hud.toast("Три шестёрки! Автомат забрал %d монет" % lost, Color(1.0, 0.35, 0.25))
		game.play_at("buzz", global_position, -6.0, 0.7)
		game.hud.hurt_flash(0.5)
		game.call_deferred("save_now")
		streak = 0
		return
	var win: int = res["win"]
	var sevens: bool = res["sevens"]
	var won_lines: PackedStringArray = res["ids"]
	hl_lines = res["lines"]
	var msg := ""
	if sevens:
		if game.open_safe():
			msg = "СЕЙФ ОТКРЫТ"
			game.hud.toast("777 — сейф открыт", Color(1.0, 0.85, 0.4))
		else:
			win += int(PAY["seven"][3])
	# множитель серии: применяется к выигрышу этой крутки; выигрыш продлевает серию, проигрыш — сброс
	var mult := chain_mult(streak)
	win = roundi(win * mult)
	# серию продлевают только настоящие комбинации (3+ или 777); пара — мелочь, серия сгорает
	streak = streak + 1 if res["big"] else 0
	last_spin_t = t
	if win > 0:
		msg = (msg + " · ") if msg != "" else ""
		msg += "+%d" % win
		if mult > 1.0:
			msg += " (СЕРИЯ ×%s)" % _mult_str(mult)
		# выигрыш со звоном высыпается в лоток-«пасть», забирать на E (промпт 14.11 17:53)
		_pour(win)
		game.hud.toast("KILLBOX: +%d — монеты в лотке" % win, Color(1.0, 0.8, 0.4))
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


func _mult_str(m: float) -> String:
	return ("%.2f" % m).trim_suffix("0").trim_suffix("0").trim_suffix(".")


## Экран автомата между крутками: сколько круток осталось, множитель серии и гарантированные символы.
func _update_screen_hint() -> void:
	if credits <= 0 and luck.is_empty() and streak <= 0:
		return
	var parts := PackedStringArray()
	if streak > 0:
		parts.append("СЕРИЯ %d → ×%s" % [streak, _mult_str(chain_mult(streak))])
	if credits > 0:
		parts.append("КРУТОК: %d" % credits)
	for k in luck:
		parts.append("%s ГАРАНТ (%d)" % [Sym.NAMES[k].to_upper(), int(luck[k])])
	screen.text = (screen.text + "\n" if screen.text != "" else "") + " · ".join(parts)


# ---------- покупка круток (окно) ----------

func _open_packs() -> void:
	if pack_ui == null:
		_build_packs()
	pack_open = true
	pack_ui.visible = true
	pack_info.text = "Монет: %d" % game.inv.coins
	_refresh_pack_up()
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
	pack_up = Button.new()
	pack_up.custom_minimum_size = Vector2(320, 48)
	pack_up.focus_mode = Control.FOCUS_NONE
	pack_up.add_theme_font_size_override("font_size", 20)
	pack_up.pressed.connect(_pack_upgrade)
	v.add_child(pack_up)
	var c := Button.new()
	c.text = "Закрыть (E / Esc)"
	c.focus_mode = Control.FOCUS_NONE
	c.add_theme_font_size_override("font_size", 18)
	c.pressed.connect(close_packs)
	v.add_child(c)
	pack_ui.visible = false


func _buy_pack(n: int, price: int) -> void:
	if busy:
		return
	if not game.inv.remove("coin", price):
		pack_info.text = "Не хватает монет (есть %d)" % game.inv.coins
		game.play_ui("buzz", -14.0)
		return
	close_packs()
	# монеты уже списаны — крутки зачисляем сразу в сейв, а на экране — после того, как 3 монетки
	# залетят в монетоприёмник (промпт 14.11 17:40)
	credits += n
	game.save_now()
	busy = true
	screen.text = "ОПЛАТА..."
	_coin_toss(3, func():
		busy = false
		game.hud.toast("KILLBOX: +%d круток" % n, Color(1.0, 0.8, 0.4))
		screen.text = ""
		_update_screen_hint())


## Монетки из руки игрока по дуге в монетоприёмник, одна за другой, каждая со звоном; потом done.
func _coin_toss(count: int, done: Callable) -> void:
	var slot_pos := rig.global_transform * Vector3(0.3 + EX, 0.71, 0.33)
	var from := slot_pos + global_transform.basis.z * 1.2 + Vector3(0, -0.3, 0)
	if game and game.player and game.player.get("cam"):
		var cam: Camera3D = game.player.cam
		from = cam.global_position - cam.global_transform.basis.z * 0.45 + Vector3(0, -0.2, 0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.86, 0.66, 0.3)
	m.metallic = 0.85
	m.roughness = 0.35
	var cm := CylinderMesh.new()
	cm.top_radius = 0.022
	cm.bottom_radius = 0.022
	cm.height = 0.006
	cm.radial_segments = 12
	cm.rings = 1
	var dur := 0.42
	var gap := 0.28
	for k in count:
		var coin := MeshInstance3D.new()
		coin.mesh = cm
		coin.material_override = m
		coin.visible = false
		if get_tree().current_scene:
			get_tree().current_scene.add_child(coin)
		else:
			add_child(coin)
		coin.global_position = from
		var a := from + Vector3(randf_range(-0.03, 0.03), 0, randf_range(-0.03, 0.03))
		var mid := (a + slot_pos) / 2.0 + Vector3(0, 0.35, 0)
		var tw := create_tween()
		tw.tween_interval(k * gap)
		tw.tween_callback(func(): coin.visible = true)
		tw.tween_method(func(t: float):
			var p := a.lerp(mid, t).lerp(mid.lerp(slot_pos, t), t)
			coin.global_position = p
			coin.rotation = Vector3(t * 9.0, 0.3, t * 4.0), 0.0, 1.0, dur)
		var last := k == count - 1
		tw.tween_callback(func():
			if game:
				game.play_at("coin", slot_pos, -8.0, 1.0 + 0.08 * k)
			coin.queue_free()
			if last:
				done.call())




func _refresh_pack_up() -> void:
	if pack_up == null:
		return
	pack_up.text = upgrade_text()
	pack_up.disabled = level >= MAX_LEVEL


func _pack_upgrade() -> void:
	if buy_upgrade():
		pack_info.text = "Окно прокачано: %s" % level_name(level)
	else:
		pack_info.text = "Не хватает монет (есть %d)" % game.inv.coins
	_refresh_pack_up()


# ---------- прокачка окна ----------

## X-центр барабана i (центральный — третий).
func _reel_x(i: int) -> float:
	return (i - (REELS - 1) / 2.0) * PITCH


static func level_name(lv: int) -> String:
	var d: Array = LEVELS[clampi(lv, 1, MAX_LEVEL) - 1]
	return "%d×%d" % [d[0], d[1]]


## Цена следующего уровня (0 — уже максимум).
func upgrade_price() -> int:
	return int(LEVELS[level][2]) if level < MAX_LEVEL else 0


func upgrade_text() -> String:
	if level >= MAX_LEVEL:
		return "Окно %s — максимум" % level_name(level)
	return "Окно %s (ур. %d) → %s — %d монет" % [level_name(level), level, level_name(level + 1), upgrade_price()]


## Купить следующий уровень окна. false — максимум или не хватает монет.
func buy_upgrade() -> bool:
	if level >= MAX_LEVEL or game == null:
		return false
	if not game.inv.remove("coin", upgrade_price()):
		game.play_ui("buzz", -14.0)
		return false
	set_level(level + 1)
	game.play_ui("coin", -10.0)
	game.hud.toast("KILLBOX: окно %s" % level_name(level), Color(1.0, 0.8, 0.4))
	game.save_now()
	return true


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
	if board_sv:
		board_art.queue_redraw()
		board_sv.render_target_update_mode = SubViewport.UPDATE_ONCE


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


## Магазин: гарантированный символ. Повторная покупка того же символа добавляет крутки.
func add_luck(sym: String) -> void:
	if not LUCK.has(sym):
		return
	luck[sym] = int(luck.get(sym, 0)) + int(LUCK[sym][0])
	screen.text = ""
	_update_screen_hint()


# ---------- лоток с выигрышем ----------

## Лоток в «пасти»: горка до TRAY_MAX маленьких золотых монеток (как монеты лута) на дне,
## и отдельная цель взгляда перед пастью (TrayTarget) — подсказка «[E] Забрать N монет».
## Если лоток пуст, цель ведёт себя как сам автомат (крутка / окно покупки).
const TRAY_MAX := 30


class TrayTarget extends StaticBody3D:
	var slot

	func get_prompt(g) -> String:
		return slot.get_prompt(g)

	func interact(g) -> void:
		slot.interact(g)


func _build_tray() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.86, 0.66, 0.3)
	m.metallic = 0.85
	m.roughness = 0.35
	m.emission_enabled = true
	m.emission = Color(0.5, 0.3, 0.08)
	m.emission_energy_multiplier = 0.25
	var cm := CylinderMesh.new()
	cm.top_radius = 0.017
	cm.bottom_radius = 0.017
	cm.height = 0.005
	cm.radial_segments = 10
	cm.rings = 1
	# дно кармана за нижними зубами пасти — на нём лежит горка
	_box(rig, Vector3(0.44, 0.012, 0.14), Vector3(0, 0.428, 0.38), _mat(Color(0.05, 0.03, 0.025)))
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	for k in TRAY_MAX:
		var c := MeshInstance3D.new()
		c.mesh = cm
		c.material_override = m
		# горка: первые монеты по дну лотка, следующие — выше и ближе к середине
		var layer := k / 12
		var spread := 0.19 - layer * 0.05
		c.position = Vector3(rng.randf_range(-spread, spread), 0.437 + layer * 0.007 + rng.randf_range(0.0, 0.004),
			rng.randf_range(0.33, 0.43))
		c.rotation = Vector3(rng.randf_range(-0.35, 0.35), rng.randf() * TAU, rng.randf_range(-0.35, 0.35))
		c.visible = false
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rig.add_child(c)
		tray_meshes.append(c)
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


func _tray_target_count(n: int) -> int:
	return clampi(n, 0, TRAY_MAX)


## Сразу показать горку под сумму (загрузка сейва).
func set_tray(n: int) -> void:
	tray_coins = maxi(n, 0)
	tray_shown = _tray_target_count(tray_coins)
	for k in tray_meshes.size():
		tray_meshes[k].visible = k < tray_shown


## Высыпать win монет в лоток: монетки падают по одной со звоном.
func _pour(win: int) -> void:
	tray_coins += win
	var want := _tray_target_count(tray_coins)
	var tw := create_tween()
	var k0 := tray_shown
	tray_shown = want
	for k in range(k0, want):
		var c := tray_meshes[k]
		var end := c.position
		tw.tween_callback(func():
			c.position = end + Vector3(0, 0.1, -0.06)
			c.visible = true
			if game and (k - k0) % 2 == 0:
				game.play_at("coin", tray_target.global_position, -14.0, randf_range(0.95, 1.25)))
		tw.tween_property(c, "position", end, 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if want == k0 and game:   # горка уже полная — просто звон
		game.play_at("coin", tray_target.global_position, -10.0)


## Забрать всё из лотка в кошелёк.
func take_tray() -> void:
	if tray_coins <= 0 or game == null:
		return
	var n := tray_coins
	var left: int = game.inv.add("coin", n)
	set_tray(left)
	game.play_ui("coin", -8.0, 1.05)
	game.hud.toast("+%d монет" % (n - left), Color(1.0, 0.8, 0.4))
	if game.has_method("save_now"):
		game.save_now()
