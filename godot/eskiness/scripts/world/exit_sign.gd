extends Node3D
## Табличка над проёмом к лестнице на поверхность (промпт 18.11 01:02): иконка Нюхича и «ТОЛЬКО В ПРОТИВОГАЗЕ».
## Висит на торцевой стене коридора (level_geometry.gd: X1 12, T 0.3; проём DOOR_W 1.7 × DOOR_H 2.3), лицом в бункер (−X).
## Создаётся из game.gd.
const Items := preload("res://scripts/items.gd")

const POS := Vector3(11.83, 2.76, 0.0)
const W := 1.5
const H := 0.56


func _ready() -> void:
	position = POS
	rotation.y = -PI / 2.0   # передняя сторона (+Z) смотрит на −X, в коридор
	# жестяная плашка с рамкой
	var plate := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(W, H, 0.02)
	plate.mesh = bm
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.78, 0.62, 0.18)   # выцветший жёлтый — предупреждение
	pm.roughness = 0.75
	pm.metallic = 0.3
	plate.material_override = pm
	add_child(plate)
	var frame := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(W + 0.06, H + 0.06, 0.012)
	frame.mesh = fm
	frame.position.z = -0.006
	var frm := StandardMaterial3D.new()
	frm.albedo_color = Color(0.12, 0.1, 0.08)
	frm.roughness = 0.9
	frame.material_override = frm
	add_child(frame)
	# иконка противогаза слева
	var spr := Sprite3D.new()
	spr.pixel_size = 0.42 / 128.0
	spr.position = Vector3(-W / 2.0 + 0.27, 0.0, 0.012)
	spr.shaded = true
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(spr)
	_render_icon(spr)
	# надпись справа
	var l := Label3D.new()
	l.text = "ТОЛЬКО\nВ ПРОТИВОГАЗЕ"
	l.font_size = 56
	l.outline_size = 0
	l.pixel_size = 0.0034
	l.modulate = Color(0.1, 0.07, 0.05)
	l.shaded = true
	l.double_sided = false
	l.position = Vector3(0.24, 0.0, 0.013)
	l.width = 900
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(l)


## Иконка Нюхича (items.gd: draw_icon) — один раз во вьюпорте 128×128.
func _render_icon(spr: Sprite3D) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(128, 128)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var cv := Control.new()
	cv.size = Vector2(128, 128)
	cv.draw.connect(func(): Items.draw_icon(cv, "gasmask", Rect2(4, 4, 120, 120)))
	vp.add_child(cv)
	add_child(vp)
	spr.texture = vp.get_texture()
