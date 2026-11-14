extends StaticBody3D
## Моток изоленты, прилепленный к доске выплат у игрового автомата: E — взять.
## Один на всю игру (промпт 14.11 18:04): взял — больше не появляется; «взят» пишется в сейв (game.gd: tape_taken).
## Вместе со стеклом на полу и деревом из ящиков — всё для первого ножика под рукой.

var game  # game.gd
var ready_ := true
var vis: Node3D


func _ready() -> void:
	vis = Node3D.new()
	add_child(vis)
	var blue := StandardMaterial3D.new()
	blue.albedo_color = Color(0.16, 0.24, 0.55)
	blue.roughness = 0.35
	var core := StandardMaterial3D.new()
	core.albedo_color = Color(0.72, 0.66, 0.52)
	# моток: кольцо изоленты лицом к комнате
	var roll := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.022
	tm.outer_radius = 0.045
	roll.mesh = tm
	roll.material_override = blue
	roll.rotation.x = PI / 2
	vis.add_child(roll)
	var c := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.022
	cm.bottom_radius = 0.022
	cm.height = 0.02
	c.mesh = cm
	c.material_override = core
	c.rotation.x = PI / 2
	vis.add_child(c)
	# хвостик, которым моток прилеплен к доске
	var strip := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.03, 0.09, 0.003)
	strip.mesh = bm
	strip.material_override = blue
	strip.position = Vector3(0.0, 0.07, -0.012)
	strip.rotation.z = 0.25
	vis.add_child(strip)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.14, 0.2, 0.06)
	cs.shape = bs
	cs.position.y = 0.03
	add_child(cs)


func get_prompt(_g) -> String:
	return "[E] Взять изоленту" if ready_ else ""


func interact(g) -> void:
	if not ready_:
		return
	if g.inv.add("tape", 1) > 0:
		g.hud.toast("Сумка полна")
		return
	g.hud.toast("+ Изолента", Color(0.85, 0.85, 0.8))
	g.play_ui("pickup", -10.0)
	set_taken(true)


func set_taken(t: bool) -> void:
	ready_ = not t
	if vis:
		vis.visible = not t
	for c in get_children():
		if c is CollisionShape3D:
			c.set_deferred("disabled", t)
