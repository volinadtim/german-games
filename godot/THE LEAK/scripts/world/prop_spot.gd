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
## Только редактор: светлое окружение без тумана и «солнце», чтобы место было видно (в игре не действует, в сцену не сохраняется).
@export var editor_light := false:
	set(v):
		editor_light = v
		_show()
## Только редактор: спрятать поверхность над бункером (рельеф, будку, лестницу, небо), чтобы видеть бункер сверху.
@export var editor_hide_surface := false:
	set(v):
		editor_hide_surface = v
		_show()


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
	if editor_light:
		_light_up(n)
	if editor_hide_surface:
		for c in n.find_children("*", "Node3D", true, false):
			var s: Script = c.get_script()
			if s != null and s.resource_path.ends_with("bunker/surface.gd"):
				(c as Node3D).visible = false


## Редактор: заменить тёмное игровое окружение превью на светлое и добавить свет сверху.
func _light_up(n: Node) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.32, 0.34, 0.38)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.2
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var found := false
	for we in n.find_children("*", "WorldEnvironment", true, false):
		(we as WorldEnvironment).environment = env   # игровой Environment с туманом и тьмой отцепляется
		found = true
	if not found:
		var we := WorldEnvironment.new()
		we.environment = env
		n.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.light_energy = 1.0
	n.add_child(sun)
