extends Node
## Подкат (скольжение) при нажатии приседа на бегу.
## Ускоряется на спусках, тормозит на ровном и в гору. Прыжок во время скольжения даёт мощный импульс вперёд.

const Sfx := preload("res://scripts/core/sfx.gd")
const MIN_START_SPEED := 5.2   # мин. горизонтальная скорость для начала подката
const START_BOOST := 1.8      # начальный импульс при входе в подкат (множитель скорости)
const MAX_SPEED := 16.5        # предел скорости при разгоне с горы
const STOP_SPEED := 2.4        # при падении скорости ниже этой — выход из подката
const FRICTION_FLAT := 7.5     # трение на ровной поверхности
const SLOPE_ACCEL := 18.0      # ускорение/торможение от угла наклона поверхности
const STEER_FORCE := 3.5       # лёгкое подруливание влево/вправо в подкате
const COOLDOWN := 0.65         # задержка перед следующим подкатом

const JUMP_FWD_MULT := 1.45    # множитель горизонтальной скорости при прыжке из подката
const JUMP_UP_MULT := 1.12     # небольшой бонус к высоте прыжка

var player
var active := false
var vel := Vector3.ZERO
var cd := 0.0
var jump_boost := Vector3.ZERO
var jump_boost_t := 0.0
var k := 0.0   # плавная «сила» подката 0..1 для камеры (FOV, наклон вниз)
var snd: AudioStreamPlayer


func _ready() -> void:
	player = get_parent()
	snd = AudioStreamPlayer.new()
	snd.stream = _scrape()
	snd.volume_db = -24.0
	add_child(snd)


## Звук скольжения: шорох/скрежет шума с падающей полосой.
static func _scrape() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var n := int(Sfx.RATE * 0.55)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var f := Sfx.Svf.new(900.0, 0.7)
	for i in n:
		var x := float(i) / n
		f.set_fc(lerpf(1500.0, 350.0, x))
		buf[i] = f.bp(rng.randf() * 2.0 - 1.0) * minf(x * 12.0, 1.0) * pow(1.0 - x, 1.3)
	return Sfx._wav(buf, 0.6)


## Вызывается каждый физический кадр из player.gd.
## want_crouch — нажата ли кнопка приседа или включён тумблер приседа.
func poll(delta: float, can: bool, sprinting: bool, want_crouch: bool, move_dir: Vector3) -> void:
	cd = maxf(cd - delta, 0.0)
	k = move_toward(k, 1.0 if active else 0.0, delta * 6.0)
	if jump_boost_t > 0.0:
		jump_boost_t = maxf(jump_boost_t - delta, 0.0)
		if jump_boost_t <= 0.0:
			jump_boost = Vector3.ZERO

	var hv := Vector3(player.velocity.x, 0.0, player.velocity.z)
	var spd := hv.length()

	if not active:
		# Вход в скольжение: на земле, бежим (или достаточно быстро движемся) и нажали присед
		# только из бега стоя (не из приседа) и за стамину — иначе не слайдим
		var st = player.stamina
		if can and player.is_on_floor() and want_crouch and cd <= 0.0 and sprinting and not player.crouched 				and spd >= MIN_START_SPEED and st != null and st.can_dash():
			st.slide()
			active = true
			var dir: Vector3 = move_dir.normalized() if move_dir.length() > 0.01 else (hv.normalized() if spd > 0.01 else -player.global_transform.basis.z)
			dir.y = 0.0
			vel = dir.normalized() * clampf(maxf(spd, MIN_START_SPEED) * START_BOOST, MIN_START_SPEED, MAX_SPEED)
			player.make_noise(player.NOISE_JUMP)
			snd.pitch_scale = randf_range(0.92, 1.08)
			snd.play()
		return

	# Условия прерывания подката: отпустили присед, запретили действие или упали в воздух
	if not can or not want_crouch or not player.is_on_floor():
		stop()
		return

	# Расчёт уклона поверхности по нормали пола
	var n: Vector3 = player.get_floor_normal()
	var slide_dir := vel.normalized()
	# Проекция вектора «вниз по склону» на направление скольжения:
	# > 0 на спуске (ускоряемся), < 0 на подъёме (тормозим быстрее)
	var slope_vec := Vector3(n.x, 0.0, n.z)
	var slope_dot := slide_dir.dot(slope_vec)

	var cur_spd := vel.length()
	if slope_dot > 0.05:
		# Спуск — разгоняемся
		cur_spd = minf(cur_spd + slope_dot * SLOPE_ACCEL * delta, MAX_SPEED)
	else:
		# Ровная поверхность или подъём — тормозим (в гору сильнее)
		var uphill_pen := absf(minf(slope_dot, 0.0)) * SLOPE_ACCEL
		cur_spd = maxf(cur_spd - (FRICTION_FLAT + uphill_pen) * delta, 0.0)

	# Лёгкое подруливание в стороны при скольжении
	if move_dir.length() > 0.01:
		var wish := Vector3(move_dir.x, 0.0, move_dir.z).normalized()
		slide_dir = slide_dir.lerp(wish, clampf(STEER_FORCE * delta, 0.0, 1.0)).normalized()

	vel = slide_dir * cur_spd

	if cur_spd < STOP_SPEED:
		stop()


## Вызывать при нажатии прыжка: если игрок в подкате — даёт двойной импульс вперёд и завершает подкат.
func try_slide_jump() -> bool:
	if not active:
		return false
	var dir := vel.normalized()
	var boost_spd := clampf(vel.length() * JUMP_FWD_MULT, 9.0, MAX_SPEED * 1.25)
	jump_boost = dir * boost_spd
	jump_boost_t = 0.45   # время сохранения повышенного импульса в воздухе
	stop()
	return true


func stop() -> void:
	if active:
		active = false
		cd = COOLDOWN


## Подменяет горизонтальную скорость во время подката или прыжка из него.
func apply(hv: Vector3, _delta: float) -> Vector3:
	if active:
		return vel
	if jump_boost_t > 0.0:
		# В воздухе сохраняем импульс с плавным затуханием, позволяя чуть корректировать полёт
		return jump_boost.lerp(hv, clampf(1.0 - (jump_boost_t / 0.45), 0.0, 0.45))
	return hv
