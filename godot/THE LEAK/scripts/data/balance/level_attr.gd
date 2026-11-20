@tool
class_name LevelAttr
extends Resource
## Атрибут прокачки персонажа (очко за уровень). Что именно даёт уровень — в коде systems/levels.gd по id.

## Ключ атрибута в коде и сейвах — не менять.
@export var id := ""
## Название.
@export var title := ""
## Что даёт один уровень (подпись для игрока).
@export var desc := ""
