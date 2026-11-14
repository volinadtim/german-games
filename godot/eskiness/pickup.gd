extends RigidBody3D
## Предмет на полу (тестовые механики): физическое тельце. Подбирается на E издалека (до ~2.8 м):
## game.gd ищет лежащий предмет под прицелом, подсказка «[E] Взять: …», предмет летит к игроку.
## Монеты по-прежнему подбираются сами, когда игрок подходит ближе 1 м.
## Выброшенные игроком монеты поднимаются сами только после того, как игрок отойдёт и вернётся.

const Items := preload("res://items.gd")
const PickupMesh := preload("res://pickup_mesh.gd")
const REACH := 3.0   # дальность подбора на E, м

var game  # game.gd
var id := "coin"
var n := 1
var age := 0.0
var need_leave := false
var taken := false   # уже летит к игроку (в сохранение не попадает)
var model: Node3D
var model_base := Vector3.ZERO   # положение визуала без подъёма
var lift := 0.0                  # подъём визуала над полом — по мировой вертикали, как бы предмет ни лёг


func _ready() -> void:
	add_to_group("pickup")
	collision_layer = 4
	collision_mask = 1
	mass = 0.2
	continuous_cd = true
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.25
	pm.friction = 0.8
	physics_material_override = pm
	var made: Array = PickupMesh.make(id)
	model = made[0]
	add_child(model)
	# PickupMesh уже поднял визуал по своей оси; запоминаем подъём и дальше держим его по мировой вертикали
	lift = PickupMesh.LIFT_FLAT if id in PickupMesh.FLAT else PickupMesh.LIFT
	model_base = model.position - Vector3(0, lift, 0)
	var s: Vector3 = made[1]
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(maxf(s.x, 0.04), maxf(s.y, 0.03), maxf(s.z, 0.04))
	cs.shape = bs
	if model is Sprite3D:
		cs.position.y = s.y * 0.5
	add_child(cs)


func _physics_process(delta: float) -> void:
	age += delta
	if not taken:
		# лёг на бок — визуал всё равно приподнят вверх по миру (тело без масштаба: inverse = transposed)
		model.position = model_base + global_transform.basis.transposed() * Vector3(0, lift, 0)
	if taken or game == null or not game.alive or age < 0.6 or id != "coin":
		return
	var pp: Vector3 = game.player.global_position
	var d := Vector2(pp.x - global_position.x, pp.z - global_position.z).length()
	var dy := global_position.y - pp.y
	if need_leave:
		if d > 1.6:
			need_leave = false
		return
	if d < 1.0 and dy > -0.4 and dy < 1.9:
		var left: int = game.collect(id, n, self)
		if left <= 0:
			_fly_to(game)
		else:
			n = left


func get_prompt(_g) -> String:
	if taken:
		return ""
	var nm := Items.item_name(id)
	return "[E] Взять: %s ×%d" % [nm, n] if n > 1 else "[E] Взять: %s" % nm


## E: в инвентарь. Не влезло ничего — сообщение «Инвентарь полон», предмет остаётся лежать.
func interact(g) -> void:
	if taken:
		return
	g.full_toast_t = 0.0   # на нажатие E сообщение о полной сумке показываем всегда
	var left: int = g.collect(id, n, self)
	if left >= n:
		return
	if left > 0:
		n = left   # взяли часть — остаток лежит
		return
	_fly_to(g)


## Предмет коротко летит к груди игрока, уменьшаясь, и исчезает.
func _fly_to(g) -> void:
	taken = true
	remove_from_group("pickup")
	collision_layer = 0
	collision_mask = 0
	freeze = true
	var tw := create_tween().set_parallel()
	var target: Vector3 = g.player.global_position + Vector3(0, 1.1, 0)
	tw.tween_method(func(k: float) -> void:
		if is_instance_valid(g) and g.player:
			target = g.player.global_position + Vector3(0, 1.1, 0)
		global_position = global_position.lerp(target, k), 0.0, 1.0, 0.22).set_ease(Tween.EASE_IN)
	tw.tween_property(model, "scale", model.scale * 0.3, 0.22)
	tw.chain().tween_callback(queue_free)
