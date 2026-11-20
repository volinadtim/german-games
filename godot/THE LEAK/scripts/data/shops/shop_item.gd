@tool
class_name ShopItem
extends Resource
## Товар магазина: предмет и цена.

## id предмета (data/items).
@export var id := ""
## Цена, монет.
@export_range(0, 100000, 1, "or_greater") var price := 0


## [[id, цена], …] — прежний вид списков товаров.
static func table(items: Array) -> Array:
	var out: Array = []
	for it in items:
		out.append([it.id, it.price])
	return out
