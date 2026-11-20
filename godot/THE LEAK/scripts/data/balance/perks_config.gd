@tool
class_name PerksConfig
extends Resource
## Навыки (scripts/systems/perks.gd). Файл — data/balance/perks.tres.

## Ветки навыков по порядку.
@export var branches: Array[PerkBranch] = []


## [[id, название, что даёт, [цены]], …]
func tree_table() -> Array:
	var out: Array = []
	for b in branches:
		out.append([b.id, b.title, b.desc, Array(b.costs)])
	return out
