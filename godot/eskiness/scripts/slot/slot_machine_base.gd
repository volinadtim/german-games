extends StaticBody3D

const SlotSounds := preload("res://scripts/slot/slot_sounds.gd")   # звуки монет в лотке и рычага (промпт 16.11 04:18)
# Часть slot_machine.gd: константы, состояние, математика барабанов и выплат (static), процедурные звуки, примитивы мешей.
const Sym := preload("res://scripts/slot/slot_symbols.gd")
const PickupMesh := preload("res://scripts/world/pickup_mesh.gd")
const WornMetal := preload("res://shaders/worn_metal.gdshader")

const COST := 3                  # цена одной крутки в пакете «3 за 8» (для подписей)
## пакеты круток (промпт 23:57): [круток, монет]
const PACKS := [[3, 8], [6, 15]]
## гарантированный символ из магазина (промпты 14.11 17:18, 18:08): символ -> [круток, цена ×1, ×2, ×3].
## Пока действует — после каждого прокрута k штук этого символа встают в случайные открытые клетки,
## где его нет (выигравшие линии не трогает). k за крутку не больше GUAR_MAX уровня окна.
## Цены подобраны симуляцией: прибавка выигрыша за все крутки баффа меньше его цены. Шестёрка не продаётся.
const LUCK := {
	"cherry": [6, 6, 14, 16], "lemon": [6, 8, 15, 17], "plum": [6, 11, 18, 19],
	"grape": [5, 13, 19, 20],
	# промпт 18.11 00:45: алмаз и семёрка — только ×1 (не больше +1 гарантом за крутку);
	# семёрка всё равно не ставится на барабан, где она уже есть (одна семёрка на барабан)
	"diamond": [5, 24], "seven": [4, 34],
}
const REELS := 5
const ROWS := 3
## прокачка окна: LEVELS[ур-1] = [рядов, барабанов, цена перехода на этот уровень]
## упрощено (промпт 15.11 23:03): переходы дешевле — первая локация проходится быстрее
## промпт 18.11 00:39: окно 2×3 вернули (1×3 → 2×3 → 3×3 → 3×4 → 3×5); сейвы — slot_level_v3 в game_save.gd
const LEVELS := [[1, 3, 0], [2, 3, 25], [3, 3, 45], [3, 4, 80], [3, 5, 120]]
const MAX_LEVEL := 5
## лента барабана (одна на все барабаны, у каждого свой сдвиг): семёрки далеко друг от друга,
## поэтому в окне одного барабана больше одной семёрки не бывает
const STRIP := ["cherry", "seven", "lemon", "plum", "cherry", "grape", "six", "lemon", "seven", "cherry", "diamond", "plum"]
## Шанс символа в каждой клетке окна, %: чем ценнее, тем реже.
## Окно разыгрывается по этим весам, затем на ленты барабанов «впечатываются» выпавшие символы.
## семёрки и шестёрки чаще (промпт 15.11 23:03)
const WEIGHTS := {"cherry": 22.0, "lemon": 19.0, "plum": 17.5, "grape": 14.5, "diamond": 13.0, "seven": 15.0, "six": 3.5}
## символы по уровням окна (промпт 14.11 17:40): на ур.1 только вишня, лимон, слива; дальше по символу,
## семёрки и шестёрки — только на последнем уровне (3×5). SYM_ORDER — порядок появления,
## LEVEL_SYMS[ур-1] — сколько первых символов в игре. Шансы — WEIGHTS среди доступных.
const SYM_ORDER := ["cherry", "lemon", "plum", "grape", "diamond", "seven", "six"]
## алмазы — с 4-го уровня (3×4), промпт 15.11 22:53
const LEVEL_SYMS := [3, 4, 4, 5, 7]
## гарантов одного символа за крутку максимум по уровню окна (промпт 14.11 18:08)
const GUAR_MAX := [1, 1, 2, 2, 3]
## шанс комбинации (промпт 14.11 18:08): символ -> [круток, цена]. Пока действует, этот символ
## «липнет» к соседу слева с шансом STICK_BOOST вместо STICK — 3 в ряд выпадают заметно чаще.
const BOOST := {
	"cherry": [6, 8], "lemon": [6, 11], "plum": [6, 13],
	"grape": [5, 14],
}
const STICK_BOOST := 0.45
## шанс, что клетка повторит символ соседа слева по ряду (чаще собираются комбинации)
const STICK := 0.12
## выплаты за линию: символ -> {сколько одинаковых: монет}. Простая таблица (промпт 15.11 22:53):
## одна на все уровни, без множителей по уровню. Промпт 16.11 02:16 — всё ≈ −12%.
const PAY := {
	"cherry": {3: 7, 4: 11, 5: 16},
	"lemon": {3: 13, 4: 19, 5: 28},
	"plum": {3: 18, 4: 26, 5: 40},
	"grape": {3: 22, 4: 35, 5: 53},
	"diamond": {3: 31, 4: 53, 5: 88},
	"seven": {3: 44},
}
## пара одинаковых соседних в ряду — только на 1-м уровне (1×3): любая, кроме вишни, +2 (промпт 15.11 22:53)
const PAIR_MAX_LEVEL := 1
## две вишни — 1 монета (промпт 16.11 03:19)
const PAY2 := {"cherry": 1, "lemon": 2, "plum": 2, "grape": 2, "diamond": 2}
## множитель за серию (промпт 14.11 17:56): CHAIN[побед подряд перед этой круткой] — множитель выплаты.
## Проигрыш (и 666) сбрасывает серию; она живёт, пока крутишь: уход от автомата дальше CHAIN_DIST м
## или CHAIN_IDLE с без крутки — сброс.
## промпт 16.11 03:16: множитель порезан (был до ×2), потолок ×1.3
const CHAIN := [1.0, 1.1, 1.2, 1.3]
## 777 уже выпадали (флаг в сейве): семёрки в 4 раза реже, а 777 на линии перебрасывается с шансом SEVENS_REROLL
const SEVENS_RARE_W := 0.25
const SEVENS_REROLL := 0.85
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
var luck := {}                   # гарантированный символ -> {"left": осталось круток, "k": штук за крутку, "q": [[k, круток], ...] — очередь купленных позже (промпт 16.11 04:32)}
var buff_panel: Label3D          # табличка баффов на стене между автоматом и магазином
@warning_ignore("unused_private_class_variable")
var _bp_t := 0.0
var boost := {}                  # шанс комбинации: символ -> осталось круток (липкость STICK_BOOST)
var level := MAX_LEVEL           # прокачка окна (1..MAX_LEVEL), хранится в сейве; в меню — всё открыто
var shutters: Array = []         # заслонки закрытых клеток: [ряд][барабан]
var pack_up: Button              # кнопка прокачки в окне покупки круток
var sevens_hit := false          # 777 уже выпадали (в сейве) — дальше они намного реже
var streak := 0                  # побед подряд (множитель серии CHAIN)
var last_spin_t := 0.0
## защита от 666 (промпт 14.11 19:23): скормленные гнилые яблоки; при «666» одно сгорает, монеты целы
const SHIELD_MAX := 2
const APPLE_PRICE := 30   # цена — по просьбе Германа (19:23)
var shield := 0
var apple_props: Array[Node3D] = []   # яблоки на табло у экрана — сколько защит
var tray_coins := 0              # выигрыш, лежащий в лотке (в сейве); забирается на E
var tray_shown := 0              # сколько монеток горки сейчас видно
var tray_meshes: Array[Node3D] = []
var tray_pos: Array[Vector3] = []   # места монеток горки (после «съедания» возвращаем)
var tray_target: StaticBody3D    # отдельная цель взгляда — лоток
var pour_tweens: Array[Tween] = []   # анимации высыпания (обрываются при сборе, промпт 02:34)
var pour_gen := 0                # поколение высыпания: звон старой россыпи после сбора не играет
## 7 и 6 на доске скрыты до 3×5; при прокачке до 3×5 — кат-сцена их появления (промпт 14.11 19:27)
var reveal_pending := false      # прокачали до 3×5, кат-сцену ещё не показали (в сейве)
var cut_active := false
var cut_t := 0.0
var rev7 := 1.0                  # проявление строк 7 / 6 (0..1) во время кат-сцены
var rev6 := 1.0
var dark6 := 0.0                 # затемнение доски перед шестёрками
var cut_cam: Camera3D
var cut_from: Transform3D
var cut_to: Transform3D
var board_node: Node3D
var board_sv: SubViewport        # доска выплат — перерисовывается при прокачке
var board_art: Control
var pack_ui: CanvasLayer
var pack_open := false
var pack_info: Label
var reels: Array[Node3D] = []
var strips: Array = []          # лента каждого барабана (12 символов), обновляется к каждой крутке
var snap_gen := 0                # поколение снимка лент (_snap_strips)
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


## Символы, которые есть в барабанах на уровне lv.
static func syms_for(lv: int) -> Array:
	return SYM_ORDER.slice(0, int(LEVEL_SYMS[clampi(lv, 1, MAX_LEVEL) - 1]))


## С какого уровня окна символ появляется в барабанах.
static func sym_level(sym: String) -> int:
	for lv in range(1, MAX_LEVEL + 1):
		if syms_for(lv).has(sym):
			return lv
	return MAX_LEVEL


static func _weighted_symbol(lv: int, rare7 := false) -> String:
	var syms := syms_for(lv)
	var total := 0.0
	for k in syms:
		total += _w(k, rare7)
	var r := randf() * total
	for k in syms:
		r -= _w(k, rare7)
		if r <= 0.0:
			return k
	return "cherry"


static func _w(sym: String, rare7: bool) -> float:
	return float(WEIGHTS[sym]) * (SEVENS_RARE_W if rare7 and sym == "seven" else 1.0)


static func _random_strip(lv: int) -> Array:
	var out: Array = []
	for i in STRIP.size():
		out.append(_weighted_symbol(lv))
	limit_sevens(out, lv)
	return out


## Не семёрка: символ по весам уровня lv, кроме семёрки.
static func _non_seven(lv: int) -> String:
	for k in 50:
		var s := _weighted_symbol(lv)
		if s != "seven":
			return s
	return "cherry"


## На одном барабане не больше одной семёрки (промпт 18.11 00:39): лишние семёрки ленты strip
## заменяются; клетки keep (выпавшее окно) не трогаем — в столбце окна семёрка уже одна.
static func limit_sevens(strip: Array, lv: int, keep: Array = []) -> void:
	var seen := false
	for idx in keep:
		if strip[idx] == "seven":
			seen = true
	for i in strip.size():
		if keep.has(i) or strip[i] != "seven":
			continue
		if seen:
			strip[i] = _non_seven(lv)
		else:
			seen = true


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
##   diag — диагональ из 3 клеток; bridge — мостик во всю ширину открытого окна (промпт 18.11 00:39):
##   на 3×3 маленький из 3, на 3×4 из 4, на 3×5 из 5; платит только целиком.
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
	if three_rows:
		var cols := 0
		var c0 := -1
		for c in REELS:
			if col_open(lv, c):
				cols += 1
				if c0 < 0:
					c0 = c
		for top in [0, 2]:
			var br: Array = [[1, c0]]
			for k in range(1, cols - 1):
				br.append([top, c0 + k])
			br.append([1, c0 + cols - 1])
			shapes.append([br, "bridge"])
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
static func _guarantee(g: Array, lv: int, sym: String, k := 1) -> void:
	k = mini(k, int(GUAR_MAX[clampi(lv, 1, MAX_LEVEL) - 1]))
	if LUCK.has(sym):
		k = mini(k, LUCK[sym].size() - 1)   # алмаз/семёрка — максимум +1
	for i in k:
		_guarantee_one(g, lv, sym)


static func _guarantee_one(g: Array, lv: int, sym: String) -> void:
	if not syms_for(lv).has(sym):
		return
	if sym == "six" or (sym == "seven" and count_open(g, lv, "seven") >= 3):
		return
	var col7: Array = []   # барабаны, где семёрка уже есть (на барабане — не больше одной)
	if sym == "seven":
		for r in ROWS:
			for c in REELS:
				if g[r][c] == "seven":
					col7.append(c)
	var keep: Array = []
	for cells in evaluate(g, lv, lines_for(lv))["lines"]:
		keep.append_array(cells)
	var cand: Array = []
	var spare: Array = []
	for r in ROWS:
		for c in REELS:
			if is_open(lv, r, c) and g[r][c] != sym and not col7.has(c):
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
## rare7 — 777 уже выпадали: семёрки реже, 777 на линии чаще перебрасывается.
## промпт 16.11 04:19: шанс любой выплаты ×0.9 — 10% выигрышных окон (без купленных гарантов)
## заменяются проигрышными; пропорции между комбинациями сохраняются.
const WIN_CUT := 0.1


static func _is_win(g: Array, lv: int) -> bool:
	var ev := evaluate(g, lv, lines_for(lv))
	return int(ev["win"]) > 0 or bool(ev["sevens"])


static func roll_window(lv: int, guar, boosted: Array = [], rare7 := false, cut := true) -> Array:
	var g := _roll_window(lv, guar, boosted, rare7)
	if cut and guar.is_empty() and randf() < WIN_CUT and _is_win(g, lv):
		for k in 200:
			var g2 := _roll_window(lv, guar, boosted, rare7)
			if not _is_win(g2, lv) and count_open(g2, lv, "six") < 3:
				return g2
	return g


static func _roll_window(lv: int, guar, boosted: Array = [], rare7 := false) -> Array:
	var g: Array = []
	for attempt in 200:
		g = []
		for r in ROWS:
			var row: Array = []
			for c in REELS:
				var s := _weighted_symbol(lv, rare7)
				if c > 0:
					var left: String = row[c - 1]
					if left != "six" and randf() < (STICK_BOOST if boosted.has(left) else STICK):
						s = left
				row.append(s)
			g.append(row)
		# промпт 18.11 00:46: шанс комбинации — и по диагоналям/галочкам/мостикам: клетка линии
		# с той же липкостью повторяет предыдущую клетку этой линии, если там купленный символ
		if not boosted.is_empty():
			for ln in lines_for(lv):
				if ln[1] == "row":
					continue
				var cl: Array = ln[0]
				for i in range(1, cl.size()):
					var prev: String = g[int(cl[i - 1][0])][int(cl[i - 1][1])]
					if boosted.has(prev) and randf() < STICK_BOOST:
						g[int(cl[i][0])][int(cl[i][1])] = prev
		# на одном барабане (столбце окна) — не больше одной семёрки (промпт 18.11 00:39)
		for c in REELS:
			var has7 := false
			for r in ROWS:
				if g[r][c] == "seven":
					if has7:
						g[r][c] = _non_seven(lv)
					has7 = true
		for sym in guar:
			_guarantee(g, lv, String(sym), int(guar[sym]) if guar is Dictionary else 1)
		if rare7 and attempt < 199 and randf() < SEVENS_REROLL and evaluate(g, lv, lines_for(lv))["sevens"]:
			continue
		if count_open(g, lv, "seven") <= 3 and count_open(g, lv, "six") <= 3:
			break
	return g


## Цена гаранта sym ×k (k штук за крутку на LUCK[sym][0] круток).
static func guar_price(sym: String, k: int) -> int:
	return int(LUCK[sym][clampi(k, 1, LUCK[sym].size() - 1)])


## Множитель серии после streak побед подряд.
static func chain_mult(streak_: int) -> float:
	return float(CHAIN[clampi(streak_, 0, CHAIN.size() - 1)])


## Выплата за n символов sym на линии при уровне окна lv (0 — не платит).
## промпт 18.11 01:02: на окнах 3×3, 3×4, 3×5 (ур. 3–5) все выплаты ×0.75
const HIGH_PAY_MULT := 0.75
const HIGH_PAY_FROM := 3


static func pay_for(sym: String, n: int, lv := 0) -> int:
	if not PAY.has(sym) or not PAY[sym].has(n):
		return 0
	var p := int(PAY[sym][n])
	if lv >= HIGH_PAY_FROM:
		p = maxi(1, roundi(p * HIGH_PAY_MULT))
	return p


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
		else:
			var same := true
			for s in syms:
				if s != syms[0]:
					same = false
			if same:
				sym = syms[0]
				cells = line
		# на 1×3: пара одинаковых соседних (вишни — 1 монета) — маленькая награда PAY2
		# (промпт 14.11 18:33; серию не продлевает). На галочках пар нет: там они были бы почти каждую крутку.
		if sym == "" and kind == "row" and lv <= PAIR_MAX_LEVEL:
			for k in syms.size() - 1:
				if syms[k] == syms[k + 1] and PAY2.has(syms[k]):
					sym = syms[k]
					cells = line.slice(k, k + 2)
					break
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
	@warning_ignore("integer_division")
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


# ---------- прокачка окна ----------

## X-центр барабана i (центральный — третий).
func _reel_x(i: int) -> float:
	return (i - (REELS - 1) / 2.0) * PITCH


static func level_name(lv: int) -> String:
	var d: Array = LEVELS[clampi(lv, 1, MAX_LEVEL) - 1]
	return "%d×%d" % [d[0], d[1]]


# ---------- лоток с выигрышем ----------

## Лоток в «пасти»: горка до TRAY_MAX маленьких золотых монеток (как монеты лута) на дне,
## и отдельная цель взгляда перед пастью (TrayTarget) — подсказка «[E] Забрать N монет».
## Если лоток пуст, цель ведёт себя как сам автомат (крутка / окно покупки).
const TRAY_MAX := 30


## Монеты забираются только взглядом на лоток (промпт 14.11 18:32); пустой лоток — как сам автомат.
class TrayTarget extends StaticBody3D:
	var slot

	func get_prompt(g) -> String:
		if slot.tray_coins > 0 and not slot.eating:
			return "[E] Забрать %d монет" % slot.tray_coins
		if slot.can_feed(g):
			return "[E] Скормить гнилое яблоко (защита от 666: %d/%d)" % [slot.shield, slot.SHIELD_MAX]
		return slot.get_prompt(g)

	func interact(g) -> void:
		if slot.tray_coins > 0 and not slot.eating:
			slot.game = g
			slot.take_tray()
		elif slot.can_feed(g):
			slot.game = g
			slot.feed_apple()
		else:
			slot.interact(g)


## Место монеты k на дне лотка: слой k/12, в слое — ячейка 4×3 (по ширине и глубине) со случайным сдвигом.
## Отступ от стенок — чтобы монета не торчала из лотка.
const TRAY_X := 0.17
const TRAY_Z0 := 0.335
const TRAY_Z1 := 0.425


## 666 при монетах в лотке (промпт 14.11 18:32): пасть «съедает» их — монетки втягиваются внутрь
## и проваливаются, жар в пасти вспыхивает, хруст-чавканье. Лоток обнуляется (в сейве тоже).
var eating := false


## Процедурный хруст-чавканье: 4 «укуса» — шумовой треск с низким телом, между ними хлюп.
static var _crunch_wav: AudioStreamWAV


static func _crunch() -> AudioStreamWAV:
	if _crunch_wav:
		return _crunch_wav
	var rate := 22050
	var n := int(rate * 1.1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 666
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	var lp2 := 0.0
	var bites := [0.0, 0.24, 0.5, 0.78]
	for i in n:
		var ts := float(i) / rate
		var v := 0.0
		for b in bites:
			var dt: float = ts - b
			if dt < 0.0 or dt > 0.22:
				continue
			# треск: редкие острые щелчки + шум, затухание
			var crack := (rng.randf() * 2.0 - 1.0) * (1.0 if rng.randf() < 0.25 else 0.35)
			lp += (crack - lp) * 0.35
			var env := exp(-dt * 22.0)
			# низкое «тело» укуса
			var body := sin(TAU * (90.0 - dt * 120.0) * dt) * exp(-dt * 14.0)
			v += lp * env * 0.9 + body * 0.7
			# хлюп после укуса
			if dt > 0.08:
				lp2 += ((rng.randf() * 2.0 - 1.0) - lp2) * 0.05
				v += lp2 * sin(TAU * 7.0 * dt) * exp(-(dt - 0.08) * 18.0) * 1.2
		var fade := minf(1.0, float(n - i) / (rate * 0.05))
		data.encode_s16(i * 2, int(clampf(v * 0.6 * fade, -1.0, 1.0) * 32000.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = rate
	st.stereo = false
	st.data = data
	_crunch_wav = st
	return st


const CUT_LEN := 4.3


static func _smooth(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


static func _wav(buf: PackedFloat32Array) -> AudioStreamWAV:
	var peak := 0.0001
	for v in buf:
		peak = maxf(peak, absf(v))
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		var fade := minf(1.0, float(buf.size() - i) / (22050.0 * 0.05))
		data.encode_s16(i * 2, int(clampf(buf[i] / peak * 0.85 * fade, -1.0, 1.0) * 32000.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = 22050
	st.data = data
	return st


## «Динь»-аккорд: арпеджио C–E–G–C колокольчиками с мерцающими обертонами.
static func _chime() -> AudioStreamWAV:
	var rate := 22050
	var buf := PackedFloat32Array()
	buf.resize(int(rate * 1.8))
	var notes := [1046.5, 1318.5, 1568.0, 2093.0]
	for k in notes.size():
		var start := int(rate * 0.09 * k)
		var f: float = notes[k]
		for i in range(start, buf.size()):
			var ts := float(i - start) / rate
			var env := exp(-ts * 2.6) * minf(1.0, ts * 200.0)
			buf[i] += (sin(TAU * f * ts) + 0.35 * sin(TAU * f * 2.01 * ts) * exp(-ts * 6.0) + 0.15 * sin(TAU * f * 3.0 * ts)) * env
	return _wav(buf)


## Зловещее: низкий гул с биениями, нарастающий шёпот-шум и глухой удар.
static func _dread() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 1.7)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6
	var lp := 0.0
	var bp := 0.0
	for i in n:
		var ts := float(i) / rate
		var env := minf(1.0, ts * 3.0) * exp(-maxf(0.0, ts - 0.9) * 2.5)
		var hum := sin(TAU * 41.0 * ts) + 0.7 * sin(TAU * 43.3 * ts) + 0.3 * sin(TAU * 82.0 * ts + sin(TAU * 0.7 * ts))
		var nz := rng.randf() * 2.0 - 1.0
		lp += (nz - lp) * 0.08
		bp += (lp - bp) * 0.5
		var whisper := (lp - bp) * 2.5 * (0.5 + 0.5 * sin(TAU * 5.0 * ts)) * minf(1.0, ts * 1.5)
		var hit := sin(TAU * 55.0 * ts) * exp(-ts * 9.0) * 1.5
		buf[i] = hum * env * 0.6 + whisper * env + hit
	return _wav(buf)
