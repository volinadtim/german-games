@tool
class_name RadiationConfig
extends GridSlotConfig
## Автомат РАДИАЦИЯ в городе (scripts/slot/city_slot.gd). Файл — data/slots/radiation.tres.

@export_group("Символы")
## Символы автомата: вес (шанс) и выплата за 3 в линию × ставка. "barrel" — бочка: дикий символ и мутаген.
@export var symbols: Array[SlotSymbol] = []

@export_group("Мутации")
## Ранги хлама снизу вверх (id символов): бочка поднимает соседей на ранг выше; последний не растёт.
@export var mutation_ranks: Array[String] = []
## Счётчик Гейгера: столько бочек — ВЫБРОС (всё поле +1 ранг и выигрыш ×2).
@export_range(1, 100, 1) var geiger_max := 12

@export_group("Время крутки")
## Вспышка одной бочки (мутация соседей), секунд.
@export_range(0.0, 10.0, 0.01) var mutation_time := 0.8
## ВЫБРОС, секунд.
@export_range(0.0, 10.0, 0.01) var burst_time := 2.0
