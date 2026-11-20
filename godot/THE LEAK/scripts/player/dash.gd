extends Node
## Рывок/уклонение на короткое нажатие Shift (тап).
## Удержание Shift — обычный бег (player.gd).
## Только у локального игрока; в сети позицию разносит обычная синхронизация игрока.
## Тратит выносливость (stamina.gd: DASH_COST), кулдаун COOLDOWN.

const TAP_MAX := 0.22    # макс. длительность нажатия Shift для срабатывания рывка, с
const SPEED := 18.0      # скорость в начале рывка (+50% от прежних 12.0 м/с)
const TIME := 0.18       # длительность рывка
const COOLDOWN := 0.8    # задержка между рывками

var player   # player.gd (родитель)
var hold_t := 0.0
var holding := false
var t := 0.0
var cd := 0.0
var vel := Vector3.ZERO


func _ready() -> void:
	player = get_parent()


## Ловим короткое нажатие Shift; can — можно ли сейчас рвануть (активен, не несёт, не присел).
## move_dir — текущее горизонтальное направление движения в мировых координатах.
func poll(delta: float, can: bool, move_dir: Vector3) -> void:
	cd = maxf(cd - delta, 0.0)
	if Input.is_action_just_pressed("sprint"):
		holding = true
		hold_t = 0.0

	if holding:
		if Input.is_action_pressed("sprint"):
			hold_t += delta
		else:
			holding = false
			if can and hold_t <= TAP_MAX and cd <= 0.0 and t <= 0.0:
				_trigger(move_dir)


func _trigger(move_dir: Vector3) -> void:
	var st = player.stamina
	if st != null and not st.can_dash():
		return
	var d := Vector3(move_dir.x, 0.0, move_dir.z)
	if d.length() < 0.01:
		# если персонаж стоит — рывок в сторону взгляда (вперёд по горизонтали)
		d = -player.global_transform.basis.z
		d.y = 0.0
	if d.length() < 0.01:
		return
	vel = d.normalized() * SPEED
	t = TIME
	cd = COOLDOWN
	if st != null:
		st.dash()
	player.make_noise(player.NOISE_JUMP)
	player._play_step(-6.0, 1.0, true)


## Подменяет горизонтальную скорость на время рывка (скорость плавно спадает к концу).
func apply(hv: Vector3, delta: float) -> Vector3:
	if t <= 0.0:
		return hv
	t -= delta
	var k := clampf(t / TIME, 0.0, 1.0)
	return vel * lerpf(0.55, 1.0, k)
