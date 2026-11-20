@tool
class_name MeleeConfig
extends Resource
## Ближний бой (scripts/weapons/weapons.gd). Файл — data/weapons/melee.tres.

## Оружие ближнего боя: урон и дальность по предметам.
@export var weapons: Array[MeleeWeapon] = []
## Что продаёт магазин в бункере, по порядку (предмет и цена).
@export var shop: Array[ShopItem] = []
## Рисунок модели: предмет -> какой предмет рисовать вместо него (у кого нет своей модели).
@export var model_alias: Dictionary[String, String] = {}


## id -> {mult, reach, price}
func weapons_table() -> Dictionary:
	var out := {}
	for w in weapons:
		out[w.id] = {"mult": w.dmg_mult, "reach": w.reach, "price": w.price}
	return out


## [[id, цена], …]
func shop_table() -> Array:
	return ShopItem.table(shop)
