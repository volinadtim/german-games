extends "res://scripts/player/player_combat.gd"
# Часть player.gd: анимация смерти (промпт 03:06). Оседает на колени, затем заваливается набок
# (поворот модели вокруг колен поверх процедурной позы); камера от первого лица уходит вниз и набок
# вместе с головой; оружие выпадает из рук (копии с физикой, сами вещи остаются в инвентаре).
# Работает и у копии чужого игрока в сети (флаг 64 в net_world.gd).

const DEATH_KNEEL := 0.4    # с, оседание на колени
const DEATH_FALL := 0.7     # с, падение набок
const DEATH_ANGLE := 1.42   # рад, на сколько заваливается (почти лёжа)
var death_t := 0.0
var death_side := 1.0       # +1 — падает вправо, -1 — влево
var death_drops: Array = [] # выпавшие из рук копии оружия (RigidBody3D)
# пробуждение в начале игры (промпт 18.11 00:58, world/intro.gd): лежит на боку → садится на колени → встаёт.
# Тайминги совпадают с камерой вступления (intro.gd _wake_pose); у чужих игроков — флаг 128 в net_world.gd.
const WAKE_END := 7.6
var waking := false
var wake_t := 0.0


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
	if model_root != null:   # иначе _apply_bones трогает только .y — тело осталось бы завалено (18.11 02:23)
		model_root.rotation.x = 0.0
		model_root.rotation.z = 0.0
	for w in weapon_nodes:
		if w != null and is_instance_valid(w):
			w.visible = true
	for d in death_drops:
		if is_instance_valid(d):
			d.queue_free()
	death_drops.clear()


func start_wake() -> void:
	waking = true
	wake_t = 0.0
	crouch = 1.0


func end_wake() -> void:
	if not waking:
		return
	waking = false
	if model_root != null:
		model_root.rotation = Vector3(0.0, model_root.rotation.y, 0.0)


## Пробуждение: та же поза «лёжа на боку», что в конце падения (колени согнуты), затем распрямляется
## на колени и встаёт из приседа. Свою камеру ведёт intro.gd — голову держим в обычном месте.
func _wake_tick(delta: float) -> void:
	wake_t += delta
	var lie := 1.0 - 0.12 * smoothstep(3.4, 4.6, wake_t)          # лежит, чуть поворачивается
	lie *= 1.0 - smoothstep(4.9, 6.0, wake_t)                      # садится на колени
	crouch = 1.0 - smoothstep(6.0, 7.3, wake_t)                    # встаёт
	if model_root != null:
		var a := lie * DEATH_ANGLE
		var r := Basis(Vector3(0, 0, 1), -a) * Basis(Vector3.RIGHT, -0.22 * lie)
		var piv := Vector3(0.12, 0.08, -0.12)
		var t := Transform3D(r, piv - r * piv)
		var base := Basis(Vector3.UP, PI + angle_difference(rotation.y, feet_yaw)).scaled(model_root.basis.get_scale())
		model_root.transform = t * Transform3D(base, model_root.position)
	if not puppet:
		head.position = Vector3(0, CAM_Y, -0.22)
	if not puppet and wake_t >= WAKE_END + 0.5:   # у чужих — по флагу из сети
		end_wake()


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
	if waking and not dying:
		_wake_tick(delta)
		return
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
	# 18.11 01:42: поза считается от базовой каждый кадр. Раньше было model_root.transform = t * model_root.transform —
	# поворот накапливался кадр за кадром, тело уезжало под пол, а камера (она ловит высоту по кости головы) тряслась.
	if model_root != null:
		var base := Basis(Vector3.UP, PI + angle_difference(rotation.y, feet_yaw)).scaled(model_root.basis.get_scale())
		model_root.transform = t * Transform3D(base, model_root.position)
	# камера: голова идёт вместе с телом, взгляд заваливается набок и чуть вниз
	var sink := smoothstep(0.0, DEATH_KNEEL, death_t) * 0.08
	head.position = t * (head.position - Vector3(0, sink, 0))
	head.position.y = maxf(head.position.y, 0.24)   # глаз не ниже лежащей головы — иначе пол-кадра под полом
	head.rotation.z = -death_side * a * 0.9
	if not puppet:
		head.rotation.x = lerpf(head.rotation.x, -0.12, 1.0 - exp(-2.5 * delta))
