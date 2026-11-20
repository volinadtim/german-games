@tool
class_name CraftRecipe
extends Resource
## Рецепт крафта.

## Что получается (id предмета).
@export var out := ""
## Что тратится: предмет -> сколько штук.
@export var need: Dictionary[String, int] = {}
## Инструмент (не тратится, а теряет прочность). Пусто — без инструмента.
@export var tool_id := ""
## Сколько прочности инструмента уходит за крафт.
@export_range(0, 100, 1) var wear := 0


## Прежний вид записи RECIPES[i].
func to_dict() -> Dictionary:
	var d := {"out": out, "need": need}
	if tool_id != "":
		d["tool"] = tool_id
		d["wear"] = wear
	return d
