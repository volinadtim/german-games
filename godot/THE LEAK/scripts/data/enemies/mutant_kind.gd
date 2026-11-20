@tool
class_name MutantKind
extends Resource
## Вид мутанта: Плевун, Таран, Тень. Поведение — в коде (enemy/mutant*.gd) по id.

## Ключ вида в коде и сейвах — не менять.
@export var id := ""
## Название.
@export var title := ""
## Здоровье.
@export_range(1.0, 2000.0, 1.0) var hp := 50.0
## Скорость, м/с.
@export_range(0.0, 20.0, 0.05) var speed := 3.0
## Рост, м.
@export_range(0.5, 5.0, 0.05) var height := 1.8
## Цвет кожи.
@export var skin := Color.GRAY
## Цвет свечения глаз.
@export var glow := Color.WHITE


## Прежний вид записи KINDS[id].
func to_dict() -> Dictionary:
	return {"name": title, "hp": hp, "speed": speed, "h": height, "skin": skin, "glow": glow}
