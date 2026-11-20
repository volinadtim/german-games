@tool
class_name LevelsConfig
extends Resource
## Уровни и опыт (scripts/systems/levels.gd). Файл — data/balance/levels.tres.

@export_group("Опыт")
## Опыт за убийство обычного врага.
@export_range(0, 1000, 1) var xp_kill := 12
## Опыт за убийство тяжёлого врага.
@export_range(0, 1000, 1) var xp_kill_heavy := 25
## Опыт за лут.
@export_range(0, 1000, 1) var xp_loot := 4

@export_group("Атрибуты")
## Максимальный уровень персонажа.
@export_range(1, 200, 1) var max_level := 26
## Максимум уровней одного атрибута.
@export_range(1, 50, 1) var max_attr := 5
## Атрибуты по порядку.
@export var attrs: Array[LevelAttr] = []


## [[id, название, что даёт], …]
func attrs_table() -> Array:
	var out: Array = []
	for a in attrs:
		out.append([a.id, a.title, a.desc])
	return out
