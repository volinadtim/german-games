@tool
class_name GunModSlot
extends Resource
## Слот модуля огнестрела (прицел, дуло, приклад, цевьё).

## Ключ слота в коде и сейвах — не менять.
@export var id := ""
## Подпись.
@export var title := ""
## Предметы-модули, которые встают в этот слот (id из data/items).
@export var mods: Array[String] = []
