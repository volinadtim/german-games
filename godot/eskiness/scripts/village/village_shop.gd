extends "res://scripts/shop/shop.gd"
## Второй Trinkets Market — в подвале деревни (промпт 16.11 00:17). Тот же магазин (товары, цены, продажа,
## вкладки), только стоит в другом месте. game.shop пока открыт этот — указывает на него (окно открыто →
## game.window_open() видит его), после закрытия — снова на магазин бункера.

var main_shop                         # магазин бункера (game.shop до открытия этого)


func interact(g) -> void:
	if not opened and g.shop != self:
		main_shop = g.shop
		g.shop = self
	super(g)


func _close() -> void:
	super()
	if game and main_shop and game.shop == self:
		game.shop = main_shop
