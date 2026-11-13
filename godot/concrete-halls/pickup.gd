extends RigidBody3D
## Предмет на полу (тестовые механики): физическое тельце, подбирается само, когда игрок подходит ближе 1 м.
## Выброшенное игроком поднимается только после того, как игрок отойдёт и вернётся.

const Items := preload("res://items.gd")

var game  # game.gd
var id := "coin"
var n := 1
var age := 0.0
var need_leave := false


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	mass = 0.2
	continuous_cd = true
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.25
	pm.friction = 0.8
	physics_material_override = pm
	var mi := Items.make_mesh(id)
	add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	var s := mi.mesh.get_aabb().size
	bs.size = Vector3(maxf(s.x, 0.04), maxf(s.y, 0.03), maxf(s.z, 0.04))
	cs.shape = bs
	add_child(cs)


func _physics_process(delta: float) -> void:
	age += delta
	if game == null or not game.alive or age < 0.6:
		return
	var pp: Vector3 = game.player.global_position
	var d := Vector2(pp.x - global_position.x, pp.z - global_position.z).length()
	var dy := global_position.y - pp.y
	if need_leave:
		if d > 1.6:
			need_leave = false
		return
	if d < 1.0 and dy > -0.4 and dy < 1.9:
		var left: int = game.collect(id, n)
		if left <= 0:
			queue_free()
		else:
			n = left
