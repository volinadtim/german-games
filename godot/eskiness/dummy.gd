extends StaticBody3D
## Тренировочный манекен (боёвка): мешок на столбе. Не умирает, качается от ударов,
## показывает урон каждого удара и сумму за серию (сбрасывается через 3 с без ударов).

const Fx := preload("res://fx.gd")

var sway: Node3D
var ang := Vector2.ZERO       # наклон (x — вперёд/назад, y — вбок)
var ang_v := Vector2.ZERO
var combo := 0.0
var combo_t := 0.0
var label: Label3D
var game                       # game.gd — износ оружия


func _ready() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.22, 0.15, 0.09)
	wood.roughness = 0.9
	var sack := StandardMaterial3D.new()
	sack.albedo_color = Color(0.4, 0.33, 0.22)
	sack.roughness = 1.0
	var rope := StandardMaterial3D.new()
	rope.albedo_color = Color(0.3, 0.25, 0.16)

	var base := BoxMesh.new()
	base.size = Vector3(0.5, 0.08, 0.5)
	_part(self, base, Vector3(0, 0.04, 0), wood)

	sway = Node3D.new()
	sway.position.y = 0.08
	add_child(sway)
	var post := CylinderMesh.new()
	post.top_radius = 0.04
	post.bottom_radius = 0.05
	post.height = 0.9
	_part(sway, post, Vector3(0, 0.45, 0), wood)
	var body := CylinderMesh.new()
	body.top_radius = 0.2
	body.bottom_radius = 0.23
	body.height = 0.75
	_part(sway, body, Vector3(0, 1.22, 0), sack)
	for y in [0.95, 1.5]:
		var band := CylinderMesh.new()
		band.top_radius = 0.235
		band.bottom_radius = 0.235
		band.height = 0.04
		_part(sway, band, Vector3(0, y, 0), rope)
	var arm := CylinderMesh.new()
	arm.top_radius = 0.035
	arm.bottom_radius = 0.035
	arm.height = 0.8
	var a := _part(sway, arm, Vector3(0, 1.38, 0), wood)
	a.rotation.z = PI / 2
	var head := SphereMesh.new()
	head.radius = 0.14
	head.height = 0.28
	_part(sway, head, Vector3(0, 1.75, 0), sack)

	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.25
	cyl.height = 1.9
	cs.shape = cyl
	cs.position.y = 0.95
	add_child(cs)

	label = Label3D.new()
	label.text = "МАНЕКЕН"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.pixel_size = 0.003
	label.outline_size = 8
	label.modulate = Color(0.85, 0.82, 0.74, 0.7)
	label.position.y = 2.15
	add_child(label)


func _part(parent: Node3D, mesh: Mesh, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func _physics_process(delta: float) -> void:
	# пружина с затуханием
	ang_v += (-ang * 60.0 - ang_v * 5.0) * delta
	ang += ang_v * delta
	sway.rotation = Vector3(ang.x, 0, ang.y)
	if combo_t > 0.0:
		combo_t -= delta
		if combo_t <= 0.0:
			combo = 0.0
			label.text = "МАНЕКЕН"


func take_hit(dmg: float, dir: Vector3) -> void:
	if game:
		game.weapon_hit()
	var local := global_transform.basis.inverse() * dir
	ang_v += Vector2(local.z, -local.x) * (2.0 + dmg * 0.08)
	combo += dmg
	combo_t = 3.0
	label.text = "СЕРИЯ: %d" % int(combo)
	Fx.damage_number(get_parent(), global_position + Vector3(0, 1.9, 0), dmg)
	Fx.dust_burst(get_parent(), global_position + Vector3(0, 1.3, 0) - dir * 0.2, Color(0.5, 0.42, 0.3), 8)
