extends CharacterBody3D
## Игрок от первого лица: тело видно, если посмотреть вниз; WASD, Shift — бег, инерция.

const WALK := 3.4
const SPRINT := 6.4
const GRAVITY := 9.8
const SENS := 0.0022
const CAM_Y := 1.62
const FOV := 75.0
const JUMP := 3.7
const ACCEL_WALK := 5.0
const ACCEL_SPRINT := 3.2

var active := false
var cam: Camera3D
var head: Node3D
var legs: Array[Node3D] = []
var arms: Array[Node3D] = []
var sprint_carry := 0.0   # 1 сразу после бега, плавно падает — от него зависит «занос»
var phase := 0.0
var bob := 0.0
var steps: Array[AudioStreamWAV] = []
var step_player: AudioStreamPlayer
var step_idx := 0
var last_step := -1
var was_on_floor := true
var land_speed := 0.0


func _ready() -> void:
	step_player = AudioStreamPlayer.new()
	step_player.max_polyphony = 3
	add_child(step_player)
	for i in 5:
		steps.append(_make_step(i))

	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)

	head = Node3D.new()
	head.position = Vector3(0, CAM_Y, -0.22)
	add_child(head)
	cam = Camera3D.new()
	cam.near = 0.03
	cam.fov = FOV
	head.add_child(cam)

	_build_body()


func _build_body() -> void:
	var jacket := _mat(Color(0.24, 0.27, 0.21))
	var pants := _mat(Color(0.14, 0.14, 0.16))
	var skin := _mat(Color(0.78, 0.6, 0.48))
	var boots := _mat(Color(0.07, 0.06, 0.05))

	var body := Node3D.new()
	add_child(body)

	var torso := CapsuleMesh.new()
	torso.radius = 0.19
	torso.height = 0.74
	_part(body, torso, Vector3(0, 1.13, 0.14), jacket)

	# голова только для тени — камера внутри неё не нужна
	var hm := SphereMesh.new()
	hm.radius = 0.12
	hm.height = 0.25
	var h := _part(body, hm, Vector3(0, 1.68, 0.08), skin)
	h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	# шея — соединяет голову с торсом (тоже только тень, чтобы не лезть в камеру)
	var neck := CylinderMesh.new()
	neck.top_radius = 0.06
	neck.bottom_radius = 0.075
	neck.height = 0.24
	var n := _part(body, neck, Vector3(0, 1.53, 0.1), skin)
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	# плечевой пояс — закрывает щели между торсом и руками
	var yoke := CapsuleMesh.new()
	yoke.radius = 0.1
	yoke.height = 0.64
	var y := _part(body, yoke, Vector3(0, 1.42, 0.13), jacket)
	y.rotation.z = PI / 2

	for side in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(0.1 * side, 0.86, 0.08)
		body.add_child(hip)
		var leg := CapsuleMesh.new()
		leg.radius = 0.085
		leg.height = 0.84
		_part(hip, leg, Vector3(0, -0.42, 0), pants)
		var boot := BoxMesh.new()
		boot.size = Vector3(0.12, 0.09, 0.27)
		_part(hip, boot, Vector3(0, -0.815, -0.05), boots)
		legs.append(hip)

		var sh := Node3D.new()
		sh.position = Vector3(0.24 * side, 1.44, 0.13)
		sh.rotation.z = 0.08 * side
		body.add_child(sh)
		var arm := CapsuleMesh.new()
		arm.radius = 0.06
		arm.height = 0.6
		_part(sh, arm, Vector3(0, -0.3, 0), jacket)
		var hand := SphereMesh.new()
		hand.radius = 0.055
		hand.height = 0.12
		_part(sh, hand, Vector3(0, -0.63, 0), skin)
		arms.append(sh)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


func _part(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * SENS)
		head.rotation.x = clampf(head.rotation.x - event.relative.y * SENS, -1.5, 1.4)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	var on_floor := is_on_floor()
	if not on_floor:
		velocity.y -= GRAVITY * delta
	elif active and Input.is_action_just_pressed("jump"):
		velocity.y = JUMP
		on_floor = false

	var inp := Vector2.ZERO
	if active:
		inp = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := transform.basis * Vector3(inp.x, 0, inp.y)
	var moving := dir.length() > 0.01
	var sprinting := active and moving and inp.y < -0.1 and Input.is_action_pressed("sprint")

	if sprinting:
		sprint_carry = 1.0
	else:
		sprint_carry = move_toward(sprint_carry, 0.0, delta * 0.7)

	var target := dir * (SPRINT if sprinting else WALK)
	var hv := Vector3(velocity.x, 0, velocity.z)
	var air := 1.0 if on_floor else 0.25
	if moving and target.length() > hv.length() + 0.01:
		# разгон: с места до шага ~0.7 с, с шага до бега ~1 с
		var accel := ACCEL_SPRINT if hv.length() > WALK - 0.2 else ACCEL_WALK
		# поворот на ходу не тормозим: сначала выравниваем направление, потом добавляем скорость
		var spd := move_toward(hv.length(), target.length(), accel * air * delta)
		var d := hv.normalized().slerp(target.normalized(), 1.0 - exp(-10.0 * air * delta)) if hv.length() > 0.1 else target.normalized()
		hv = d * spd
	else:
		# торможение мягкое; после бега — ещё мягче
		var rate := (7.0 if moving else lerpf(6.0, 2.6, sprint_carry)) * air
		hv = hv.lerp(target, 1.0 - exp(-rate * delta))
	velocity.x = hv.x
	velocity.z = hv.z
	move_and_slide()

	if is_on_floor() and not was_on_floor and land_speed < -2.5:
		_play_step(-4.0)
	land_speed = velocity.y
	was_on_floor = is_on_floor()

	_animate(delta, hv.length() if is_on_floor() else 0.0, sprinting)


func _animate(delta: float, spd: float, sprinting: bool) -> void:
	var amt := clampf(spd / WALK, 0.0, 1.5)
	phase += delta * spd * 2.6
	var swing := sin(phase) * 0.5 * minf(amt, 1.3)
	legs[0].rotation.x = swing
	legs[1].rotation.x = -swing
	arms[0].rotation.x = -swing * 0.8
	arms[1].rotation.x = swing * 0.8
	bob = lerpf(bob, amt, 1.0 - exp(-8.0 * delta))
	head.position.y = CAM_Y + sin(phase * 2.0) * 0.03 * bob
	head.position.x = sin(phase) * 0.015 * bob
	# шаг — каждый раз, когда нога проходит нижнюю точку (полпериода качания)
	var s := int(floor(phase / PI))
	if s != last_step:
		last_step = s
		if spd > 0.6 and is_on_floor():
			_play_step((-6.0 if sprinting else -12.0) + randf_range(-1.5, 1.5), 1.05 if sprinting else 1.0)
	var want_fov := FOV + (7.0 if sprinting else 0.0)
	cam.fov = lerpf(cam.fov, want_fov, 1.0 - exp(-5.0 * delta))


func _play_step(db: float, pitch := 1.0) -> void:
	step_idx = (step_idx + 1 + randi() % (steps.size() - 1)) % steps.size()
	step_player.stream = steps[step_idx]
	step_player.volume_db = db
	step_player.pitch_scale = randf_range(0.9, 1.08) * pitch
	step_player.play()


## Шаг ботинка по камню: мягкий удар пятки + перекат на носок + короткий шорох подошвы
## и лёгкое эхо помещения. Только отфильтрованный шум — без тональных «звонких» составляющих.
func _make_step(variant: int) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.38)
	var rng := RandomNumberGenerator.new()
	rng.seed = 200 + variant
	var buf := PackedFloat32Array()
	buf.resize(n)
	var toe_t := rng.randf_range(0.055, 0.085)
	var heel_amp := rng.randf_range(0.85, 1.0)
	var toe_amp := rng.randf_range(0.4, 0.6)
	var lo := 0.0
	var lo2 := 0.0
	var mid := 0.0
	var sc := 0.0
	for i in n:
		var t := float(i) / rate
		var w := rng.randf() * 2.0 - 1.0
		lo += (w - lo) * 0.06        # ~200 Гц: глухое тело удара
		lo2 += (lo - lo2) * 0.06
		mid += (w - mid) * 0.25      # ~900 Гц: «щелчок» подошвы о камень
		sc += (w - sc) * 0.12        # шорох
		var env_heel := exp(-t * 55.0) * minf(t * 900.0, 1.0)
		var env_click := exp(-t * 160.0) * minf(t * 2000.0, 1.0)
		var env_toe := 0.0
		var env_toe_click := 0.0
		if t > toe_t:
			var tt := t - toe_t
			env_toe = exp(-tt * 70.0) * minf(tt * 900.0, 1.0)
			env_toe_click = exp(-tt * 200.0)
		var env_scuff := exp(-pow((t - 0.05) / 0.045, 2.0))
		var v := lo2 * 9.0 * (env_heel * heel_amp + env_toe * toe_amp)
		v += mid * 0.55 * (env_click * heel_amp + env_toe_click * toe_amp * 0.7)
		v += sc * 0.08 * env_scuff
		buf[i] = v
	# эхо бетонной комнаты
	var d1 := int(rate * 0.029)
	var d2 := int(rate * 0.047)
	var d3 := int(rate * 0.071)
	var sm := 0.0
	for i in n:
		var e := 0.0
		if i >= d1: e += buf[i - d1] * 0.22
		if i >= d2: e += buf[i - d2] * 0.14
		if i >= d3: e += buf[i - d3] * 0.09
		sm += (e - sm) * 0.3       # эхо глуше прямого звука
		buf[i] += sm
	var peak := 0.001
	for v in buf:
		peak = maxf(peak, absf(v))
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var fade := minf(1.0, float(n - i) / (rate * 0.05))
		data.encode_s16(i * 2, int(buf[i] / peak * 0.9 * fade * 32000.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = rate
	st.stereo = false
	st.data = data
	return st
