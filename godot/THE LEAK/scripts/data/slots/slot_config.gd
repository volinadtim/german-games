@tool
class_name SlotConfig
extends Resource
## Общее у всех автоматов: список символов и лимит прибыли. Конкретные автоматы — наследники
## (KillboxConfig, CashyBoxConfig, KlevConfig, RadiationConfig); файлы — data/slots/<автомат>.tres.
## Методы ниже собирают из символов прежние таблицы (WEIGHTS, PAY…) — игровой код читает их как раньше.

## Лимит чистой прибыли игрока у автомата, монет: пока выплаты минус купленные крутки не дошли до него,
## автомат платит как обычно; потом отдаёт только то, что в него вложили после этого.
@export_range(0, 100000, 100, "or_greater") var profit_cap := 2000


## Символы автомата (переопределяется в наследнике как поле «Символы»).
func get_symbols() -> Array:
	return get("symbols")


## Ключи символов по порядку списка.
func ids() -> Array:
	var out: Array = []
	for s in get_symbols():
		out.append(s.id)
	return out


## id -> вес.
func weights() -> Dictionary:
	var out := {}
	for s in get_symbols():
		out[s.id] = s.weight
	return out


## id -> выплата за 3 в линию (символы без выплаты пропускаются).
func pays_3() -> Dictionary:
	var out := {}
	for s in get_symbols():
		if s.pay_3 > 0:
			out[s.id] = s.pay_3
	return out


## id -> название.
func titles() -> Dictionary:
	var out := {}
	for s in get_symbols():
		out[s.id] = s.title
	return out
