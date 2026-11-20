@tool
class_name ItemTables
extends Resource
## Общие таблицы предметов (scripts/items/items.gd): крафт, размеры в сумке, карманы. Файл — data/items/tables.tres.
## Сами предметы — data/items/<id>.tres (ItemType).

## Рецепты крафта.
@export var recipes: Array[CraftRecipe] = []
## Размер предмета в сумке, ячеек: x — ширина, y — высота (нет в списке — 1×1).
@export var sizes: Dictionary[String, Vector2i] = {}
## Карманы одежды, ячеек: x — ширина, y — высота.
@export var pockets: Dictionary[String, Vector2i] = {}
## Подсказка у модулей огнестрела.
@export_multiline var mod_hint := ""


func recipes_table() -> Array:
	var out: Array = []
	for r in recipes:
		out.append(r.to_dict())
	return out


## id -> [ширина, высота]
static func cells(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[k] = [d[k].x, d[k].y]
	return out
