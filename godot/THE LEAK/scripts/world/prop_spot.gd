@tool
extends Marker3D
## Метка расстановки в scenes/locations/*.tscn: где стоит объект (scripts/world/places.gd читает её положение).
## В редакторе показывает превью модели (preview — путь к сцене scenes/props/preview/*.tscn); в игре метка не создаётся —
## объект ставит его скрипт по координатам метки. Превью пересобирает инструмент tests/tools/bake_places.gd.

@export_file("*.tscn", "*.scn") var preview := "":
	set(v):
		preview = v
		_show()
@export var note := ""   ## что это за место (для людей)
@export var tag := ""    ## доп. значение для кода (вид мутанта, сторона двери дома…)
@export var size := Vector3.ZERO   ## размер (дома деревни: ширина x, глубина z)


func _ready() -> void:
	_show()


func _show() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	for c in get_children():
		if c.has_meta("_preview"):
			c.queue_free()
	if preview == "" or not ResourceLoader.exists(preview):
		return
	var ps: PackedScene = load(preview)
	if ps == null:
		return
	var n := ps.instantiate()
	n.set_meta("_preview", true)
	add_child(n)   # без owner — в сцену не сохраняется
