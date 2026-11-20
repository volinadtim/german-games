@tool
class_name KillboxConfig
extends SlotConfig
## Автомат KILLBOX в бункере (scripts/slot/slot_machine*.gd). Файл — data/slots/killbox.tres.

@export_group("Символы")
## Символы по порядку появления: на первом уровне окна — только первые (см. «Прокачка окна»).
## У каждого: шанс (вес), выплаты за 3/4/5 и пару, баффы магазина бункера.
@export var symbols: Array[KillboxSymbol] = []

@export_group("Цены и крутки")
## Цена одной крутки в первом пакете — только для подписей (сами крутки продаются пакетами).
@export_range(0, 1000, 1, "or_greater") var spin_price := 3
## Пакеты круток в окне покупки: сколько круток и за сколько монет.
@export var packs: Array[SlotSpinPack] = []

@export_group("Шансы")
## Шанс, что клетка повторит символ соседа слева по ряду (чаще собираются комбинации). 0..1.
@export_range(0.0, 1.0, 0.01) var stick := 0.12
## То же, пока куплен «шанс комбинации» этого символа. 0..1.
@export_range(0.0, 1.0, 0.01) var stick_boost := 0.28
## Доля выигрышных окон, которые заменяются проигрышными (без купленных гарантов). 0.1 — шанс выплаты ×0.9.
@export_range(0.0, 1.0, 0.01) var win_cut := 0.1
## После первых 777 (флаг в сейве): вес семёрок умножается на это число (0.25 — в 4 раза реже).
@export_range(0.0, 1.0, 0.01) var sevens_rare_weight := 0.25
## После первых 777: шанс, что новые 777 на линии перебросятся. 0..1.
@export_range(0.0, 1.0, 0.01) var sevens_reroll := 0.85

@export_group("Выплаты")
## Пара одинаковых соседних в ряду платит только до этого уровня окна включительно (1 — только на 1×3).
@export_range(0, 5, 1) var pair_max_level := 1
## С этого уровня окна все выплаты умножаются на «Множитель больших окон».
@export_range(1, 5, 1) var high_pay_from_level := 3
## Множитель выплат на больших окнах (0.75 — ×0.75, округление, минимум 1 монета).
@export_range(0.0, 2.0, 0.05) var high_pay_mult := 0.75

@export_group("Прокачка окна")
## Уровни окна по порядку: рядов, барабанов, цена перехода, сколько символов в игре, максимум гарантов за крутку.
## Последний уровень — самое большое окно (по нему строятся барабаны).
@export var levels: Array[SlotWindowLevel] = []

@export_group("Серия")
## Множитель выплаты за серию: [при 0 победах подряд, при 1, при 2, …]; дальше — последний.
## Проигрыш (и 666) сбрасывает серию.
@export var chain_mults: Array[float] = []
## Серия сбрасывается, если отойти от автомата дальше стольких метров.
@export_range(0.0, 50.0, 0.5) var chain_dist := 4.0
## Серия сбрасывается, если столько секунд не крутить.
@export_range(0.0, 600.0, 1.0) var chain_idle := 30.0

@export_group("Защита от 666")
## Сколько гнилых яблок можно скормить автомату: при «666» одно сгорает, монеты целы.
@export_range(0, 10, 1) var shield_max := 2
## Цена гнилого яблока в магазине, монет (купить можно только одно).
@export_range(0, 10000, 1, "or_greater") var apple_price := 150

@export_group("Лента барабана")
## Лента барабана (одна на все барабаны, у каждого свой сдвиг). Семёрки далеко друг от друга —
## в окне одного барабана больше одной семёрки не бывает. Значения — id символов.
@export var strip: Array[String] = []

@export_group("Лоток и экран")
## Сколько монеток горки видно в лотке (больше — не рисуется).
@export_range(0, 100, 1) var tray_max := 30
## Бегущая строка, когда касса обчищена (лимит прибыли).
@export var cap_text := "ОБЧИЩЕНО "
## Длина видимого окна бегущей строки, символов.
@export_range(1, 64, 1) var cap_chars := 16
## Скорость бегущей строки, символов в секунду.
@export_range(1, 30, 1) var cap_speed := 3
## Длина кат-сцены появления 7 и 6 на доске (при прокачке до последнего окна), секунд.
@export_range(0.0, 20.0, 0.1) var cutscene_len := 4.3

@export_group("Модель и вид (не баланс)")
## Радиус барабана, м.
@export var reel_radius := 0.19
## Ширина барабана, м.
@export var reel_width := 0.125
## Высота оси барабанов, м.
@export var reel_y := 0.98
## Сдвиг барабанов вперёд, м.
@export var reel_z := 0.07
## Пикселей на символ в ленте (мало — крупные «пиксели», как у стен).
@export var strip_tex_px := 64
## Во сколько раз автомат больше «базового».
@export var scale := 1.3
## Высота подиума, м.
@export var podium_h := 0.25
## Сдвиг вперёд, чтобы задняя стенка не уходила в стену, м.
@export var rig_z := 0.1
## На сколько корпус шире с каждой стороны, чем у прежнего автомата на 4 барабана, м.
@export var body_extra := 0.0725
## Шаг барабанов, м.
@export var reel_pitch := 0.145
## Цвета подсветки выигравших линий (по кругу).
@export var highlight_colors: Array[Color] = []
## Полуширина дна лотка, м.
@export var tray_x := 0.17
## Дно лотка: ближний край по глубине, м.
@export var tray_z0 := 0.335
## Дно лотка: дальний край по глубине, м.
@export var tray_z1 := 0.425


# ---------- прежние таблицы для игрового кода ----------

## id -> {3: монет, 4: …, 5: …} (символы без выплат пропускаются).
func pay_table() -> Dictionary:
	var out := {}
	for s in symbols:
		var d := {}
		for n in [3, 4, 5]:
			var p: int = s.get("pay_%d" % n)
			if p > 0:
				d[n] = p
		if not d.is_empty():
			out[s.id] = d
	return out


## id -> монет за пару.
func pair_pays() -> Dictionary:
	var out := {}
	for s in symbols:
		if s.pay_pair > 0:
			out[s.id] = s.pay_pair
	return out


## id -> [круток, цена ×1, ×2, …] (гарант).
func luck_table() -> Dictionary:
	var out := {}
	for s in symbols:
		if s.guarantee_spins > 0:
			out[s.id] = [s.guarantee_spins] + Array(s.guarantee_prices)
	return out


## id -> [круток, цена] (шанс комбинации).
func boost_table() -> Dictionary:
	var out := {}
	for s in symbols:
		if s.boost_spins > 0:
			out[s.id] = [s.boost_spins, s.boost_price]
	return out


## [[рядов, барабанов, цена], …]
func levels_table() -> Array:
	var out: Array = []
	for l in levels:
		out.append([l.rows, l.reels, l.price])
	return out


func level_symbols() -> Array:
	var out: Array = []
	for l in levels:
		out.append(l.symbols)
	return out


func level_guarantee_max() -> Array:
	var out: Array = []
	for l in levels:
		out.append(l.guarantee_max)
	return out


## [[круток, монет], …]
func packs_table() -> Array:
	var out: Array = []
	for p in packs:
		out.append([p.spins, p.price])
	return out
