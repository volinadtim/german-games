extends Resource
## Предмет (паттерн Type Object): один файл data/items/<id>.tres на предмет.
## Общие поля — отдельно, всё остальное (heal, armor, equip, weapon, buff…) — в props.
## items.gd собирает из файлов прежний словарь Items.ITEMS[id] = {"name": …, "desc": …, …} — остальной код не меняется.
## Цена и тир — у магазинов (data/shops/shops.tres), у одного предмета в разных лавках цена разная.

@export var id := ""
@export var order := 0                ## порядок в справочнике (списки, подсказки /get)
@export var name := ""
@export_multiline var desc := ""
@export var stack := 1                ## сколько в одной ячейке
@export var icon := ""                ## рисунок иконки (items.gd: draw_icon)
@export var color := Color.WHITE
@export var uses := false             ## на несколько применений (dur — сколько осталось), не стакается
@export var dur := 0                  ## прочность / число применений (0 — нет)
@export var props: Dictionary = {}    ## остальные свойства предмета как были в коде


## Прежний вид записи Items.ITEMS[id] (ключи uses/dur — только если были).
func to_dict() -> Dictionary:
	var d := {"name": name, "desc": desc, "stack": stack, "icon": icon, "color": color}
	if uses:
		d["uses"] = true
	if dur != 0:
		d["dur"] = dur
	for k in props:
		d[k] = props[k]
	return d
