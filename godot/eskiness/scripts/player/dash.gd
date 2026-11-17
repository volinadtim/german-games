extends Node
## Рывок/уклонение на двойное нажатие WASD (промпт 18.11 00:27).
## Только у локального игрока; в сети позицию разносит обычная синхронизация игрока.
## Тратит выносливость (stamina.gd: DASH_COST), кулдаун COOLDOWN.

const WINDOW := 0.28     # макс. пауза между двумя нажатиями
const SPEED := 12.0      # скорость в начале рывка, м/с
const TIME := 0.18       # длительность рывка
const COOLDOWN := 0.8
const ACTIONS := {
	"move_forward": Vector3(0, 0, -1),
	"move_back": Vector3(0, 0, 1),
	"move_left": Vector3(-1, 0, 0),
	"move_right": Vector3(1, 0, 0),
}

var player   # player.gd (родитель)
var last_tap := {}
var t := 0.0
var cd := 0.0
var vel := Vector3.ZERO


func _ready() -> void:
	player = get_parent()


## Ловим двойное нажатие; can — можно ли сейчас рвануть (активен, не несёт, не присел).
func poll(delta: float, can: bool) -> void:
	cd = maxf(cd - delta, 0.0)
	var now := Time.get_ticks_msec() / 1000.0
	for a in ACTIONS:
		if not Input.is_action_just_pressed(a):
			continue
		var prev: float = last_tap.get(a, -10.0)
		last_tap[a] = now
		if not can or now - prev > WINDOW or cd > 0.0 or t > 0.0:
			continue
		var st = player.stamina
		if st != null and not st.can_dash():
			continue
		last_tap[a] = -10.0
		var d: Vector3 = player.global_transform.basis * (ACTIONS[a] as Vector3)
		d.y = 0.0
		if d.length() < 0.01:
			continue
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
