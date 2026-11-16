extends "res://scripts/player/player_combat.gd"
# Часть player.gd: анимация смерти (промпт 03:06). Оседает на колени, затем заваливается набок
# (поворот модели вокруг колен поверх процедурной позы); камера от первого лица уходит вниз и набок
# вместе с головой; оружие выпадает из рук (копии с физикой, сами вещи остаются в инвентаре).
# Работает и у копии чужого игрока в сети (флаг 64 в net_world.gd).

const DEATH_KNEEL := 0.4    # с, оседание на колени
const DEATH_FALL := 0.7     # с, падение набок
const DEATH_ANGLE := 1.42   # рад, на сколько заваливается (почти лёжа)
var dying := false
var death_t := 0.0
var death_side := 1.0       # +1 — падает вправо, -1 — влево
var death_drops: Array = [] # выпавшие из рук копии оружия (RigidBody3D)


func start_death() -> void:
	if dying:
		return
	dying = true
	death_t = 0.0
	death_side = -1.0 if randf() < 0.5 else 1.0
	charging = -1
	_drop_hand_items()


func end_death() -> void:
	if not dying:
		return
	dying = false
	death_t = 0.0
	head.rotation.z = 0.0
	for w in weapon_nodes:
		if w != null and is_instance_valid(w):
			w.visible = true
	for d in death_drops:
		if is_instance_valid(d):
			d.queue_free()
	death_drops.clear()


## Оружие из рук падает на пол: копия модели в RigidBody3D, оригинал в руке прячется до подъёма.
func _drop_hand_items() -> void:
	var world := get_parent()
	if world == null:
		return
	for i in 2:
		var w = weapon_nodes[i]
		if w == null or not is_instance_valid(w) or not w.is_inside_tree() or not w.visible:
			continue
		var gt: Transform3D = w.global_transform
		var b := gt.basis.orthonormalized()
		var rb := RigidBody3D.new()
		rb.collision_layer = 0
		rb.collision_mask = 1
		rb.mass = 0.6
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = 0.05
		cs.shape = sh
		rb.add_child(cs)
		var copy: Node3D = w.duplicate()
		copy.visible = true
		rb.add_child(copy)
		world.add_child(rb)
		rb.global_transform = Transform3D(b, gt.origin)
		copy.transform = Transform3D(b.inverse() * gt.basis, Vector3.ZERO)
		var side := -1.0 if i == 0 else 1.0
		rb.linear_velocity = velocity * 0.5 + global_basis * Vector3(side * 0.7, 1.2, -0.8)
		rb.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-4, 4), randf_range(-6, 6))
		w.visible = false
		death_drops.append(rb)
		get_tree().create_timer(60.0).timeout.connect(func(): if is_instance_valid(rb): rb.queue_free())


## После _animate: колени подгибаются (присед), затем всё тело и камера поворачиваются вокруг колен.
func _death_tick(delta: float) -> void:
	if not dying:
		return
	death_t += delta
	crouch = minf(crouch + delta * 8.0, 1.0)   # _update_crouch тянет к 0 со скоростью 4 — перебиваем
	var f := clampf((death_t - DEATH_KNEEL) / DEATH_FALL, 0.0, 1.0)
	var k := f * f                                # падает с ускорением
	if f >= 1.0:
		k = 1.0 - 0.04 * sin(clampf((death_t - DEATH_KNEEL - DEATH_FALL) * 9.0, 0.0, PI)) # лёгкий отскок
	var a := k * DEATH_ANGLE
	var r := Basis(Vector3(0, 0, 1), -death_side * a) * Basis(Vector3.RIGHT, -0.22 * k)
	var piv := Vector3(death_side * 0.12, 0.08, -0.12)
	var t := Transform3D(r, piv - r * piv)
	if model_root != null:
		model_root.transform = t * model_root.transform
	# камера: голова идёт вместе с телом, взгляд заваливается набок и чуть вниз
	var sink := smoothstep(0.0, DEATH_KNEEL, death_t) * 0.08
	head.position = t * (head.position - Vector3(0, sink, 0))
	head.rotation.z = -death_side * a * 0.9
	if not puppet:
		head.rotation.x = lerpf(head.rotation.x, -0.12, 1.0 - exp(-2.5 * delta))
