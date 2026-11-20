@tool
class_name CashyBoxConfig
extends GridSlotConfig
## Автомат CASHY BOX в подвале деревни (scripts/slot/bonus_slot.gd). Файл — data/slots/cashy_box.tres.

@export_group("Символы")
## Символы автомата: вес (шанс), выплата за 3 в линию × ставка, гарант красного магазина.
## "bonus" — бонуска (считается по всему полю), "jack" — корона (джекпот).
@export var symbols: Array[CashySymbol] = []

@export_group("Бонуски и бонус-игра")
## Две бонуски по полю (вне бонус-игры) — столько бесплатных круток.
@export_range(0, 100, 1) var free_spins_2 := 2
## Две бонуски во время бонус-игры — столько бесплатных круток.
@export_range(0, 100, 1) var free_spins_2_in_bonus := 3
## Три бонуски и больше — бонус-игра: столько бесплатных круток с множителем.
@export_range(0, 100, 1) var bonus_game_spins := 8
## Множитель выигрыша в бонус-игре.
@export_range(1.0, 10.0, 0.1) var bonus_game_mult := 2.0
## Покупка бонус-игры в красном магазине: цена — столько круток по текущей ставке.
@export_range(0, 1000, 1) var bonus_buy_spins := 20

@export_group("Джекпот")
## Банк джекпота в начале (счётчик уменьшается на 1 с каждой платной крутки, на нуле корона встаёт сама).
@export_range(0, 10000, 1) var jackpot_start := 100
## Три короны в линию — джекпот, монет × ставка.
@export_range(0, 100000, 1) var jackpot_win := 300
## Три короны и больше по полю — мини-джекпот, монет × ставка.
@export_range(0, 100000, 1) var mini_jackpot := 100

@export_group("Шансы")
## После первых 777: шанс, что новые 777 перебросятся. 0..1.
@export_range(0.0, 1.0, 0.01) var sevens_reroll := 0.85

@export_group("Время крутки")
## «Интрига»: третий барабан крутится дольше на столько секунд.
@export_range(0.0, 5.0, 0.01) var tease_time := 1.2
## Скорость ленты, клеток в секунду.
@export_range(0.0, 50.0, 0.25) var reel_speed := 11.25
## Торможение барабана, секунд (плавно, с лёгким перекатом).
@export_range(0.0, 5.0, 0.01) var stop_time := 0.45
## Торможение третьего барабана в «интриге», секунд (медленно доползает).
@export_range(0.0, 5.0, 0.01) var stop_time_tease := 1.4
## Сила переката при остановке (easeOutBack).
@export_range(0.0, 5.0, 0.05) var stop_overshoot := 1.3


## id -> [круток, цена в крутках по ставке] (гарант).
func guarantee_table() -> Dictionary:
	var out := {}
	for s in symbols:
		if s.guarantee_spins > 0:
			out[s.id] = [s.guarantee_spins, s.guarantee_price]
	return out
