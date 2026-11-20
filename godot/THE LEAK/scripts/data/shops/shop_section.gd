@tool
class_name ShopSection
extends Resource
## Подвкладка магазина: название и предметы по порядку.

## Название подвкладки.
@export var title := ""
## Предметы (id из data/items) по порядку.
@export var items: Array[String] = []


## [[название, [предметы]], …]
static func table(sections: Array) -> Array:
	var out: Array = []
	for s in sections:
		out.append([s.title, Array(s.items)])
	return out
