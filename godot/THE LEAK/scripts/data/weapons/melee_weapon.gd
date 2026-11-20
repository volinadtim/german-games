@tool
class_name MeleeWeapon
extends Resource
## Предмет как оружие ближнего боя: множитель урона и дальность удара.

## id предмета (data/items).
@export var id := ""
## Урон удара = урон кулака × это число.
@export_range(0.0, 20.0, 0.05) var dmg_mult := 1.0
## Дальность удара, м.
@export_range(0.0, 5.0, 0.01) var reach := 1.2
## Цена (справочная; продаётся по ценам магазинов).
@export_range(0, 100000, 1) var price := 0
