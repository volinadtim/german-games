@tool
class_name CashySymbol
extends SlotSymbol
## Символ автомата CASHY BOX: выплата за 3 в линию (×ставка) и гарант из красного магазина деревни.

@export_group("Гарант (магазин)")
## Гарант символа на несколько круток: сколько круток. 0 — не продаётся (7, бонуски и короны).
@export_range(0, 100, 1, "or_greater") var guarantee_spins := 0
## Цена гаранта — в крутках по текущей ставке (3 = три крутки по ставке).
@export_range(0, 1000, 1, "or_greater") var guarantee_price := 0
