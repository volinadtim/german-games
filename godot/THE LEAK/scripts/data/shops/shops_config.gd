@tool
class_name ShopsConfig
extends Resource
## Магазины (scripts/shop/shop_model.gd и наследники). Файл — data/shops/shops.tres.
## Магазины в локациях продают одинаковый ассортимент, отличаются тиром: в каждом следующем — всё прежнее + новое.

@export_group("Оружие")
## Огнестрел: предмет и цена (только в деревне и дальше).
@export var guns: Array[ShopItem] = []
## Какие предметы показываются на подвкладке огнестрела, по порядку.
@export var gun_ids: Array[String] = []
## Патроны: набор и цена за набор.
@export var ammo: Array[ShopItem] = []
## Сколько патронов в одном наборе.
@export_range(1, 1000, 1) var ammo_pack := 10
## Магазины для огнестрела.
@export var mags: Array[ShopItem] = []
## Модули огнестрела: предмет и цена.
@export var mods: Array[ShopItem] = []
## Какие модули показываются на подвкладке «Модули», по порядку.
@export var mod_ids: Array[String] = []

@export_group("Расходники и инструменты")
## Расходники: предмет и цена.
@export var consumables: Array[ShopItem] = []
## Подвкладки «Расходников» (цены — в списке выше).
@export var consumable_sections: Array[ShopSection] = []
## «Инструменты»: предмет и цена.
@export var tools: Array[ShopItem] = []

@export_group("Одежда")
## Подвкладки «Одежды»; последняя — «Снаряжение». Цены — у оружия ближнего боя/одежды в data/weapons/melee.tres (магазин).
@export var clothes: Array[ShopSection] = []

@export_group("Тиры")
## Тир предмета: с какого магазина он продаётся (нет в списке — тир 0, с первого магазина).
@export var tier: Dictionary[String, int] = {}
## Тир чертежа: с какого магазина он продаётся.
@export var blueprint_tier: Dictionary[String, int] = {}

@export_group("Прочее")
## «Обновить все ящики» — цена, монет.
@export_range(0, 100000, 1) var chest_refresh := 80
## Вкладки магазина по порядку.
@export var tabs: Array[String] = []

@export_group("Модель (не баланс)")
## Ширина корпуса, м.
@export var width := 1.0
## Высота корпуса, м.
@export var height := 2.15
## Глубина корпуса, м.
@export var depth := 0.7
## Витрина: левый край по X, м.
@export var window_x0 := -0.47
## Витрина: правый край по X, м.
@export var window_x1 := 0.17
## Высоты полок, м.
@export var shelf_y: Array[float] = []
## Высота лотка выдачи, м.
@export var tray_y := 0.3
## Шрифт надписей на модели (системный).
@export var font := "Courier New"


## Список товаров поля prop в прежнем виде: [[id, цена], …]
func items(prop: String) -> Array:
	return ShopItem.table(get(prop))


## Подвкладки поля prop в прежнем виде: [[название, [предметы]], …]
func sections(prop: String) -> Array:
	return ShopSection.table(get(prop))
