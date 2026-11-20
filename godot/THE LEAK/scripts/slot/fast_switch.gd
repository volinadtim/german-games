extends StaticBody3D
## Тумблер «быстрые крутки» на левой стенке автомата (KILLBOX и CASHY BOX, промпт 20.11 14:35):
## F — вкл/выкл, крутка в FAST раз быстрее. Флаг хранит сам автомат (slot.fast), во время крутки не щёлкается.
## Узел ставится точкой на стенке; коробочка торчит наружу по −X на depth (чтобы луч взгляда попадал в неё раньше корпуса).

const SlotSounds := preload("res://scripts/slot/slot_sounds.gd")
const FAST := 3.0

var slot
var depth := 0.03
var pivot: Node3D
var lamp: StandardMaterial3D


## Подготовка: s — автомат (поля fast, busy), d — вынос от стенки.
func setup(s, d := 0.03) -> void:
	slot = s
	depth = d


## Строит коробку с тумблером, лампой и надписью FAST.
func _ready() -> void:
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.05, 0.05, 0.055)
	dark.metallic = 0.6
	dark.roughness = 0.35
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.7, 0.68, 0.62)
	steel.metallic = 1.0
	steel.roughness = 0.3
	if depth > 0.005:
		_mesh(Vector3(depth, 0.1, 0.08), Vector3(-depth / 2.0, 0, 0), dark)   # кронштейн
	_mesh(Vector3(0.02, 0.17, 0.13), Vector3(-depth - 0.01, 0, 0), dark)
	_mesh(Vector3(0.024, 0.04, 0.04), Vector3(-depth - 0.022, -0.02, 0), steel)  # гнездо тумблера
	pivot = Node3D.new()
	pivot.position = Vector3(-depth - 0.032, -0.02, 0)
	add_child(pivot)
	var stick := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.012, 0.012)
	stick.mesh = bm
	stick.material_override = steel
	stick.position = Vector3(-0.025, 0, 0)
	pivot.add_child(stick)
	lamp = StandardMaterial3D.new()
	lamp.emission_enabled = true
	var lm := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.011
	sm.height = 0.022
	lm.mesh = sm
	lm.material_override = lamp
	lm.position = Vector3(-depth - 0.022, -0.02, 0.045)
	add_child(lm)
	var l := Label3D.new()
	l.text = "FAST"
	l.font_size = 28
	l.pixel_size = 0.0016
	l.modulate = Color(0.85, 0.8, 0.65)
	l.outline_size = 4
	l.rotation.y = -PI / 2.0
	l.position = Vector3(-depth - 0.021, 0.05, 0)
	add_child(l)
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	var w := depth + 0.09
	bx.size = Vector3(w, 0.19, 0.15)
	cs.shape = bx
	cs.position = Vector3(-w / 2.0, 0, 0)
	add_child(cs)
	_show()


func _mesh(size: Vector3, pos: Vector3, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	add_child(mi)


## Тумблер вверх и зелёная лампа — включено; вниз и тусклая — выключено.
func _show() -> void:
	var on: bool = slot.fast
	pivot.rotation.z = -0.55 if on else 0.55
	lamp.albedo_color = Color(0.2, 0.9, 0.35) if on else Color(0.15, 0.12, 0.1)
	lamp.emission = Color(0.2, 1.0, 0.4) if on else Color(0, 0, 0)
	lamp.emission_energy_multiplier = 1.4 if on else 0.0


func get_prompt(_g) -> String:
	if slot.busy:
		return ""
	return "[F] Быстрые крутки: %s" % ("ВКЛ → выключить" if slot.fast else "ВЫКЛ → включить (×3)")


func interact(_g) -> void:
	if slot.busy:
		return
	slot.fast = not slot.fast
	_show()
	SlotSounds.play3d(self, SlotSounds.lever(), global_position, -14.0, 1.8 if slot.fast else 1.6)
