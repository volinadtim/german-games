extends CharacterBody3D
## Игрок от первого лица: тело видно, если посмотреть вниз; WASD, Shift — бег, инерция.

const WALK := 3.4
const SPRINT := 6.4
const GRAVITY := 9.8
const SENS := 0.0022
const CAM_Y := 1.62
const FOV := 75.0

var active := false
var cam: Camera3D
var head: Node3D
var legs: Array[Node3D] = []
var arms: Array[Node3D] = []
var sprint_carry := 0.0   # 1 сразу после бега, плавно падает — от него зависит «занос»
var phase := 0.0
var bob := 0.0


func _ready() -> void:
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)

	head = Node3D.new()
	head.position = Vector3(0, CAM_Y, -0.14)
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
	_part(body, torso, Vector3(0, 1.13, 0.1), jacket)

	# голова только для тени — камера внутри неё не нужна
	var hm := SphereMesh.new()
	hm.radius = 0.12
	hm.height = 0.25
	var h := _part(body, hm, Vector3(0, 1.66, 0.06), skin)
	h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY

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
		sh.position = Vector3(0.26 * side, 1.42, 0.1)
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
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

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
	# разгон быстрый, торможение мягкое; после бега — ещё мягче
	var rate := 9.0 if moving else lerpf(7.0, 2.8, sprint_carry)
	var hv := Vector3(velocity.x, 0, velocity.z).lerp(target, 1.0 - exp(-rate * delta))
	velocity.x = hv.x
	velocity.z = hv.z
	move_and_slide()

	_animate(delta, hv.length(), sprinting)


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
	var want_fov := FOV + (7.0 if sprinting else 0.0)
	cam.fov = lerpf(cam.fov, want_fov, 1.0 - exp(-5.0 * delta))
