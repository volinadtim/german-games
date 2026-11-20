extends "res://scripts/player/player.gd"
## Человек в кат-сцене посадки (промпт 16.11 00:17): та же модель и та же процедурная походка, что у игрока
## (player.gd), голова видна (как у модели чужого игрока — puppet). car.gd двигает узел сам: подходит к двери,
## поворачивается, садится — ноги вперёд, колени согнуты; водитель кладёт руки на руль.
## Узел — внутри rig машины; столкновений нет.

var sit := 0.0            # 0 — стоит, 1 — сидит (car.gd)
var wheel := false        # водитель: руки на руль
var _last := Vector3.INF
var _arms := 0.0


func _init() -> void:
	puppet = true


func _ready() -> void:
	super()
	collision_layer = 0
	collision_mask = 0
	cam.current = false
	set_process(false)    # следы ударов, заряд — не нужны


func _physics_process(delta: float) -> void:
	if skel == null:
		return
	var gp := global_position
	var v := Vector3.ZERO if _last == Vector3.INF else (gp - _last) / maxf(delta, 0.0001)
	_last = gp
	var v_local := global_basis.inverse() * Vector3(v.x, 0, v.z)
	_update_idle(delta, v_local.length(), true)
	if sit <= 0.001:
		_animate_legs(delta, v_local, true)
	else:
		_sit_legs(delta)
	_arms_pose(delta)
	_apply_bones()


## Сидя: стопа уходит вперёд и вниз от бедра (бедро почти горизонтально), корпус — по взгляду.
func _sit_legs(delta: float) -> void:
	var k := smoothstep(0.0, 1.0, sit)
	feet_yaw = lerp_angle(feet_yaw, rotation.y, 1.0 - exp(-10.0 * delta))
	torso_yaw = lerp_angle(torso_yaw, rotation.y, 1.0 - exp(-10.0 * delta))
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var stand := Vector3(side * 0.03, GROUND_Y, 0.0) - _hip()
		var seated := Vector3(side * 0.06, -LEG_L2 * 0.78, -LEG_L1 * 1.02)
		foot[i] = foot[i].lerp(Vector3(side * 0.03, GROUND_Y, 0.0), 1.0 - exp(-8.0 * delta))
		foot_yaw[i] = lerpf(foot_yaw[i], 0.0, 1.0 - exp(-8.0 * delta))
		foot_pitch[i] = lerpf(foot_pitch[i], 0.25 * k, 1.0 - exp(-8.0 * delta))
		_leg_ik(i, stand.lerp(seated, k))


## Руки: на ходу качаются навстречу ногам, сидя — на коленях, у водителя — вперёд, на руль.
func _arms_pose(delta: float) -> void:
	_arms = lerpf(_arms, 1.0 if wheel and sit > 0.9 else 0.0, 1.0 - exp(-4.0 * delta))
	var k := smoothstep(0.0, 1.0, sit)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var swing := clampf(-foot[1 - i].z * 1.1, -0.6, 0.6) * (1.0 - k)
		var lap := Vector3(0.55, 0.05 * side, 0.1 * side)
		var on_wheel := Vector3(1.15, -0.12 * side, 0.05 * side)
		var r := Vector3(0.04 + swing, 0.1 * side, 0.09 * side).lerp(lap, k).lerp(on_wheel, _arms)
		shoulders[i].rotation = r
		elbows[i].rotation.x = lerpf(lerpf(0.2, 1.0, k), 0.55, _arms)
