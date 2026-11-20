@tool
class_name KlevSymbol
extends SlotSymbol
## Символ автомата КЛЁВ. Рыба — символ с ценниками: рыбак вытягивает её в «УЛОВ».

@export_group("Рыба")
## Ценники рыбы (монет ×ставка): при выпадении берётся случайный из списка. Пусто — не рыба.
@export var catch_values: Array[int] = []
