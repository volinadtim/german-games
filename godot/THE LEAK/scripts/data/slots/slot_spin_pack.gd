@tool
class_name SlotSpinPack
extends Resource
## Пакет круток KILLBOX в окне покупки: «3 за 8».

## Сколько круток в пакете.
@export_range(1, 100, 1, "or_greater") var spins := 3
## Цена пакета, монет.
@export_range(0, 10000, 1, "or_greater") var price := 8
