extends CharacterBody3D
## Игрок от первого лица: тело видно, если посмотреть вниз.
## WASD, Shift — бег, пробел — прыжок, ПКМ — режим кулаков (руки в стойку), ЛКМ — удар.

const Sfx := preload("res://sfx.gd")
const STEP_SND := preload("res://sounds/step.mp3")   # звук шага, присланный в чат
const STEP_SPEED := 1.6     # во сколько раз ускоряем
const STEP_PITCH := 1.0     # итоговая высота тона относительно оригинала (1.0 — как в файле)

const WALK := 3.4
const SPRINT := 6.4
const GRAVITY := 22.0
const FALL_MULT := 1.35      # вниз падаем быстрее, чем взлетаем — прыжок не «плывёт»
const JUMP := 5.0            # ~0.55 м
const SENS := 0.0022
const CAM_Y := 1.7
const FOV := 75.0
const ACCEL_WALK := 5.0
const ACCEL_SPRINT := 3.2

# позы руки в градусах: x — подъём плеча вперёд, y — внутрь, z — в сторону, w — сгиб локтя
const REST := Vector4(0, 0, 0, 10)
const GUARD := Vector4(60, 10, 0, 60)
const PUNCHES := {
	"straight": [Vector4(55, 14, 2, 80), Vector4(100, 6, 0, 4)],
	"hook": [Vector4(82, -30, 8, 40), Vector4(96, 32, 0, 28)],
	"upper": [Vector4(45, 12, 6, 100), Vector4(95, 12, 0, 58)],
}

var active := false
var cam: Camera3D
var head: Node3D
var legs: Array[Node3D] = []
var shoulders: Array[Node3D] = []
var elbows: Array[Node3D] = []
var arm_pose: Array[Vector4] = [REST, REST]
var reach: Array[float] = [0.0, 0.0]   # выпад плеча вперёд при ударе
var fists := false
var fist_blend := 0.0
var punching := false
var sprint_carry := 0.0   # 1 сразу после бега, плавно падает — от него зависит «занос»
var phase := 0.0
var bob := 0.0
var last_step := -1
var was_on_floor := true
var land_speed := 0.0

var steps: Array[AudioStreamWAV] = []
var whooshes: Array[AudioStreamWAV] = []
var exhales: Array[AudioStreamWAV] = []
var impacts: Array[AudioStreamWAV] = []
var inhale_snd: AudioStreamWAV
var step_player: AudioStreamPlayer
var step_eq: AudioEffectEQ6
var voice_player: AudioStreamPlayer
var hit_player: AudioStreamPlayer
var step_idx := 0


func _ready() -> void:
	step_player = _audio(3)
	voice_player = _audio(2)
	hit_player = _audio(3)
	_setup_step_bus()
	for i in 4:
		whooshes.append(Sfx.whoosh(i))
		exhales.append(Sfx.exhale(i))
		impacts.append(Sfx.impact(i))
	inhale_snd = Sfx.inhale()

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


## Шина «Steps»: ускорение делаем через pitch_scale плеера (оно же поднимает тон),
## а эффект PitchShift на шине опускает тон обратно до STEP_PITCH.
func _setup_step_bus() -> void:
	if AudioServer.get_bus_index("Steps") == -1:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, "Steps")
		AudioServer.set_bus_send(idx, "Master")
		var ps := AudioEffectPitchShift.new()
		ps.pitch_scale = STEP_PITCH / STEP_SPEED
		AudioServer.add_bus_effect(idx, ps)
		AudioServer.add_bus_effect(idx, AudioEffectEQ6.new())
	step_player.bus = "Steps"
	var bi := AudioServer.get_bus_index("Steps")
	for e in AudioServer.get_bus_effect_count(bi):
		if AudioServer.get_bus_effect(bi, e) is AudioEffectEQ6:
			step_eq = AudioServer.get_bus_effect(bi, e)


## Каждый шаг слегка «подрезан эквалайзером» в случайных местах: 1–2 полосы глушим, иногда одну чуть поднимаем.
func _randomize_step_eq() -> void:
	if step_eq == null:
		return
	for b in step_eq.get_band_count():
		step_eq.set_band_gain_db(b, 0.0)
	var bands := [1, 2, 3, 4, 5]   # 100 Гц, 320 Гц, 1 кГц, 3.2 кГц, 10 кГц
	bands.shuffle()
	for k in randi_range(1, 2):
		step_eq.set_band_gain_db(bands[k], randf_range(-10.0, -4.0))
	if randf() < 0.35:
		step_eq.set_band_gain_db(bands[2], randf_range(1.0, 3.0))


func _audio(poly: int) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.max_polyphony = poly
	add_child(p)
	return p


func _build_body() -> void:
	var jacket := _mat(Color(0.24, 0.27, 0.21))
	var pants := _mat(Color(0.14, 0.14, 0.16))
	var skin := _mat(Color(0.78, 0.6, 0.48))
	var boots := _mat(Color(0.07, 0.06, 0.05))
	var cuffs := _mat(Color(0.18, 0.2, 0.16))

	var body := Node3D.new()
	add_child(body)

	var torso := CapsuleMesh.new()
	torso.radius = 0.19
	torso.height = 0.74
	_part(body, torso, Vector3(0, 1.13, 0.14), jacket)

	# голова и шея только для тени — камера внутри них не нужна
	var hm := SphereMesh.new()
	hm.radius = 0.12
	hm.height = 0.25
	var h := _part(body, hm, Vector3(0, 1.68, 0.08), skin)
	h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
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

		# рука: плечо -> плечевая кость -> локоть -> предплечье -> кулак
		var sh := Node3D.new()
		sh.position = Vector3(0.24 * side, 1.44, 0.13)
		body.add_child(sh)
		var upper := CapsuleMesh.new()
		upper.radius = 0.052
		upper.height = 0.34
		_part(sh, upper, Vector3(0, -0.15, 0), jacket)
		var el := Node3D.new()
		el.position = Vector3(0, -0.3, 0)
		sh.add_child(el)
		var fore := CapsuleMesh.new()
		fore.radius = 0.044
		fore.height = 0.3
		_part(el, fore, Vector3(0, -0.13, 0), jacket)
		# манжета рукава
		var cuff := CylinderMesh.new()
		cuff.top_radius = 0.048
		cuff.bottom_radius = 0.05
		cuff.height = 0.035
		_part(el, cuff, Vector3(0, -0.265, 0), cuffs)
		_build_fist(el, skin, side)
		shoulders.append(sh)
		elbows.append(el)


## Кулак из нескольких частей: ладонь, ряд костяшек, подогнутые пальцы снизу, большой палец сверху.
## В локальных осях предплечья: -Y — вперёд по руке, -Z — тыльная сторона (в стойке смотрит вверх).
func _build_fist(el: Node3D, skin: Material, side: float) -> void:
	var hand := Node3D.new()
	hand.position = Vector3(0, -0.3, 0)
	el.add_child(hand)
	var palm := BoxMesh.new()
	palm.size = Vector3(0.072, 0.07, 0.05)
	var p := _part(hand, palm, Vector3(0, -0.04, 0), skin)
	p.rotation.x = 0.08
	# костяшки: четыре согнутых пальца, видны как бугорки спереди
	for k in 4:
		var x := (k - 1.5) * 0.019
		var knuckle := CapsuleMesh.new()
		knuckle.radius = 0.0115
		knuckle.height = 0.05
		var kn := _part(hand, knuckle, Vector3(x, -0.078 + absf(k - 1.5) * 0.004, -0.004), skin)
		kn.rotation.x = PI / 2
		# средние фаланги, подогнутые к ладони снизу
		var tip := CapsuleMesh.new()
		tip.radius = 0.0105
		tip.height = 0.04
		var t := _part(hand, tip, Vector3(x, -0.06, 0.026), skin)
		t.rotation.x = 0.3
	# большой палец поперёк поверх согнутых пальцев
	var thumb := CapsuleMesh.new()
	thumb.radius = 0.012
	thumb.height = 0.06
	var th := _part(hand, thumb, Vector3(-0.012 * side, -0.06, -0.03), skin)
	th.rotation.z = PI / 2 - 0.35 * side
	# запястье
	var wrist := CylinderMesh.new()
	wrist.top_radius = 0.03
	wrist.bottom_radius = 0.034
	wrist.height = 0.04
	_part(hand, wrist, Vector3(0, -0.005, 0), skin)


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
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and captured:
		rotate_y(-event.relative.x * SENS)
		head.rotation.x = clampf(head.rotation.x - event.relative.y * SENS, -1.5, 1.4)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		if not captured:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			toggle_fists()
		elif event.button_index == MOUSE_BUTTON_LEFT and fists:
			punch()


func toggle_fists() -> void:
	if punching:
		return
	fists = not fists
	var tw := create_tween().set_parallel()
	tw.tween_property(self, "fist_blend", 1.0 if fists else 0.0, 0.3).set_trans(Tween.TRANS_SINE)
	for i in 2:
		tw.tween_method(_pose_setter(i), arm_pose[i], GUARD if fists else REST, 0.3).set_trans(Tween.TRANS_SINE)
	if fists:
		voice_player.stream = inhale_snd
		voice_player.volume_db = -14.0
		voice_player.pitch_scale = randf_range(0.95, 1.05)
		voice_player.play()


func punch() -> void:
	if punching or fist_blend < 0.9:
		return
	punching = true
	var i := randi() % 2
	var r := randf()
	var kind := "straight" if r < 0.45 else ("hook" if r < 0.75 else "upper")
	var keys: Array = PUNCHES[kind]
	var tw := create_tween()
	tw.tween_method(_pose_setter(i), arm_pose[i], keys[0], 0.08).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(_punch_sound)
	tw.tween_method(_pose_setter(i), keys[0], keys[1], 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(func(v: float) -> void: reach[i] = v, 0.0, 0.12, 0.09)
	tw.tween_callback(_check_hit.bind(i))
	tw.tween_method(_pose_setter(i), keys[1], GUARD, 0.22).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_method(func(v: float) -> void: reach[i] = v, 0.12, 0.0, 0.22)
	tw.tween_callback(func(): punching = false)


func _pose_setter(i: int) -> Callable:
	return func(p: Vector4) -> void: arm_pose[i] = p


func _punch_sound() -> void:
	_play(hit_player, whooshes, -10.0)
	_play(voice_player, exhales, -9.0)


func _check_hit(arm: int) -> void:
	var from := cam.global_position
	var to := from - cam.global_transform.basis.z * 1.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		_play(hit_player, impacts, -4.0)
		# лёгкая отдача в камеру
		var tw := create_tween()
		var side := -1.0 if arm == 0 else 1.0
		tw.tween_property(cam, "rotation:z", 0.02 * side, 0.04)
		tw.tween_property(cam, "rotation:z", 0.0, 0.15)


func _play(p: AudioStreamPlayer, set_: Array, db: float) -> void:
	p.stream = set_[randi() % set_.size()]
	p.volume_db = db + randf_range(-1.5, 1.5)
	p.pitch_scale = randf_range(0.92, 1.08)
	p.play()


func _physics_process(delta: float) -> void:
	var on_floor := is_on_floor()
	if not on_floor:
		velocity.y -= GRAVITY * (FALL_MULT if velocity.y < 0.0 else 1.0) * delta
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
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var p: Vector4 = arm_pose[i]
		var arm_swing := swing * 0.8 * (1.0 if i == 0 else -1.0) * -1.0 * (1.0 - fist_blend)
		var guard_bob := deg_to_rad(sin(phase * 2.0 + float(i)) * 3.0 * amt * fist_blend)
		shoulders[i].rotation = Vector3(
			deg_to_rad(p.x) + arm_swing + guard_bob,
			deg_to_rad(p.y) * side,
			deg_to_rad(p.z) * side + 0.08 * side * (1.0 - fist_blend))
		elbows[i].rotation.x = deg_to_rad(p.w)
		shoulders[i].position.z = 0.13 - reach[i]
	bob = lerpf(bob, amt, 1.0 - exp(-8.0 * delta))
	head.position.y = CAM_Y + sin(phase * 2.0) * 0.03 * bob
	head.position.x = sin(phase) * 0.015 * bob
	# в стойке голова чуть назад — к плечам, чтобы кулаки были перед лицом, а не в камере
	head.position.z = lerpf(-0.22, 0.06, fist_blend)
	# шаг — каждый раз, когда нога проходит нижнюю точку (полпериода качания)
	var s := int(floor(phase / PI))
	if s != last_step:
		last_step = s
		if spd > 0.6 and is_on_floor():
			_play_step((-6.0 if sprinting else -12.0) + randf_range(-1.5, 1.5), 1.05 if sprinting else 1.0)
	var want_fov := FOV + (7.0 if sprinting else 0.0)
	cam.fov = lerpf(cam.fov, want_fov, 1.0 - exp(-5.0 * delta))


func _play_step(db: float, pitch := 1.0) -> void:
	_randomize_step_eq()
	step_player.stream = STEP_SND
	step_player.volume_db = db
	step_player.pitch_scale = STEP_SPEED * randf_range(0.95, 1.05) * pitch
	step_player.play()
