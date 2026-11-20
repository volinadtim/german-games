@tool
class_name KlevConfig
extends GridSlotConfig
## Автомат КЛЁВ в лагере у озера (scripts/slot/lake_slot.gd). Файл — data/slots/klev.tres.

@export_group("Символы")
## Символы автомата: вес (шанс), выплата за 3 в линию × ставка, у рыб — ценники.
## "fisher" — рыбак (вытягивает рыб в «УЛОВ»; два рыбака — улов ×2, три — ×3).
@export var symbols: Array[KlevSymbol] = []

@export_group("События")
## Шанс щуки-разбойницы (если рыб на поле 2 и больше): глотает рыб в ряду, ценник «сумма ×2». 0..1.
@export_range(0.0, 1.0, 0.01) var pike_chance := 0.15
## Шанс утки (если рыбы есть, а рыбака нет): ныряет в клетку, оттуда выныривает рыбак. 0..1.
@export_range(0.0, 1.0, 0.01) var duck_chance := 0.22
## Садок: столько пойманных рыб — «УХА!».
@export_range(1, 100, 1) var bucket_size := 15
## «УХА!» — монет × ставка.
@export_range(0, 10000, 1) var uha_pay := 60

@export_group("Время событий")
## Щука проплывает ряд, секунд.
@export_range(0.0, 10.0, 0.01) var pike_time := 2.4
## Пролёт утки целиком, секунд.
@export_range(0.0, 10.0, 0.01) var duck_time := 1.9
## Утка ныряет в клетку на этой секунде пролёта.
@export_range(0.0, 10.0, 0.01) var duck_dive := 1.35
## Рыбак: заброс лески, секунд.
@export_range(0.0, 10.0, 0.01) var cast_time := 0.3
## Рыбак: рыба подтянута к этой секунде.
@export_range(0.0, 10.0, 0.01) var pull_time := 0.62
## Рыбак: одна рыба целиком, секунд.
@export_range(0.0, 10.0, 0.01) var catch_time := 0.85
## Надпись «УХА!», секунд.
@export_range(0.0, 10.0, 0.01) var uha_time := 2.2


## id рыбы -> [ценники].
func fish_values() -> Dictionary:
	var out := {}
	for s in symbols:
		if not s.catch_values.is_empty():
			out[s.id] = Array(s.catch_values)
	return out
