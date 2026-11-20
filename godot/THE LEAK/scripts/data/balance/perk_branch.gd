@tool
class_name PerkBranch
extends Resource
## Ветка навыков. Что именно даёт уровень — в коде systems/perks.gd по id.

## Ключ ветки в коде и сейвах — не менять.
@export var id := ""
## Название.
@export var title := ""
## Что даёт один уровень (подпись для игрока).
@export var desc := ""
## Цены уровней 1..N, монет. Сколько цен — столько уровней.
@export var costs: Array[int] = []
