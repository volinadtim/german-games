extends "res://scripts/enemy/enemy_base.gd"
# Часть enemy.gd: модели бетонника и Шныги, анимация.


func _build() -> void:
	if kind == "fast":
		_build_fast()
		return
	mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.29, 0.27)
	mat.roughness = 1.0
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.7)
	mat.emission_energy_multiplier = 0.0
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.2, 0.19, 0.18)
	dark.roughness = 1.0
	var rebar := StandardMaterial3D.new()
	rebar.albedo_color = Color(0.22, 0.13, 0.08)
	rebar.metallic = 0.5
	rebar.roughness = 0.7
	var eye := StandardMaterial3D.new()
	eye.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye.albedo_color = Color(1.0, 0.55, 0.2)

	vis = Node3D.new()
	add_child(vis)

	for side in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(0.14 * side, 0.92, 0)
		vis.add_child(hip)
		var leg := CapsuleMesh.new()
		leg.radius = 0.1
		leg.height = 0.92
		_part(hip, leg, Vector3(0, -0.44, 0), mat)
		var foot := BoxMesh.new()
		foot.size = Vector3(0.16, 0.08, 0.26)
		_part(hip, foot, Vector3(0, -0.88, -0.05), dark)
		legs.append(hip)

	torso = Node3D.new()
	torso.position = Vector3(0, 0.9, 0)
	torso.rotation.x = -0.38
	vis.add_child(torso)
	var chest := CapsuleMesh.new()
	chest.radius = 0.25
	chest.height = 0.9
	var c := _part(torso, chest, Vector3(0, 0.42, 0), mat)
	c.scale = Vector3(1.2, 1.0, 0.8)
	# горб из обломков
	var hump := BoxMesh.new()
	hump.size = Vector3(0.36, 0.22, 0.2)
	var hm := _part(torso, hump, Vector3(0.05, 0.68, 0.14), dark)
	hm.rotation = Vector3(0.4, 0.3, 0.2)
	# торчащая арматура
	for k in 3:
		var rb := CylinderMesh.new()
		rb.top_radius = 0.012
		rb.bottom_radius = 0.012
		rb.height = 0.35 + 0.1 * k
		var r := _part(torso, rb, Vector3(-0.12 + 0.12 * k, 0.8, 0.12), rebar)
		r.rotation = Vector3(0.5 + 0.2 * k, 0.0, -0.4 + 0.35 * k)

	var head := Node3D.new()
	head.position = Vector3(0, 0.92, -0.1)
	torso.add_child(head)
	var hs := SphereMesh.new()
	hs.radius = 0.16
	hs.height = 0.3
	var h := _part(head, hs, Vector3.ZERO, mat)
	h.scale = Vector3(1.0, 0.9, 1.05)
	for side in [-1.0, 1.0]:
		var es := SphereMesh.new()
		es.radius = 0.025
		es.height = 0.05
		_part(head, es, Vector3(0.06 * side, 0.02, -0.15), eye)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.5, 0.2)
	glow.light_energy = 0.25
	glow.omni_range = 0.8
	glow.position = Vector3(0, 0.02, -0.3)
	head.add_child(glow)

	for side in [-1.0, 1.0]:
		var sh := Node3D.new()
		sh.position = Vector3(0.34 * side, 0.72, 0)
		sh.rotation.z = 0.12 * side
		torso.add_child(sh)
		var arm := CapsuleMesh.new()
		arm.radius = 0.08
		arm.height = 0.8
		_part(sh, arm, Vector3(0, -0.36, 0), mat)
		var fist := SphereMesh.new()
		fist.radius = 0.11
		fist.height = 0.2
		_part(sh, fist, Vector3(0, -0.78, 0), dark)
		arms.append(sh)

	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)

	# полоска здоровья над головой
	bar = Node3D.new()
	bar.position.y = 2.0
	bar.visible = false
	add_child(bar)
	_bar_quad(Color(0, 0, 0, 0.7), Vector2(0.62, 0.075), 0.0)
	bar_fg = _bar_quad(Color(0.7, 0.14, 0.08), Vector2(0.6, 0.055), 0.01)


## «Шныга»: ростом ~1.4 м, тощая, сильно сгорбленная, с длинными руками-палками и крупной головой.
## Бледная ржаво-серая кожа, белёсо-зелёные глаза, торчащие рёбра.
func _build_fast() -> void:
	mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.46, 0.38, 0.33)
	mat.roughness = 0.85
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.7)
	mat.emission_energy_multiplier = 0.0
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.22, 0.15, 0.13)
	dark.roughness = 0.9
	var rib := StandardMaterial3D.new()
	rib.albedo_color = Color(0.62, 0.55, 0.48)
	rib.roughness = 0.8
	var eye := StandardMaterial3D.new()
	eye.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye.albedo_color = Color(0.75, 1.0, 0.7)

	vis = Node3D.new()
	add_child(vis)
	for side in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(0.1 * side, 0.66, 0)
		vis.add_child(hip)
		var leg := CapsuleMesh.new()
		leg.radius = 0.05
		leg.height = 0.68
		var lg := _part(hip, leg, Vector3(0, -0.32, 0.03), mat)
		lg.rotation.x = 0.12
		var foot := BoxMesh.new()
		foot.size = Vector3(0.09, 0.05, 0.2)
		_part(hip, foot, Vector3(0, -0.64, -0.04), dark)
		legs.append(hip)

	torso = Node3D.new()
	torso.position = Vector3(0, 0.64, 0)
	torso.rotation.x = -0.75
	vis.add_child(torso)
	var chest := CapsuleMesh.new()
	chest.radius = 0.14
	chest.height = 0.62
	var c := _part(torso, chest, Vector3(0, 0.3, 0), mat)
	c.scale = Vector3(1.0, 1.0, 0.75)
	# рёбра и позвоночник
	for k in 4:
		var rb := BoxMesh.new()
		rb.size = Vector3(0.26 - 0.02 * k, 0.018, 0.04)
		_part(torso, rb, Vector3(0, 0.2 + 0.08 * k, -0.095), rib)
	for k in 5:
		var vb := SphereMesh.new()
		vb.radius = 0.03
		vb.height = 0.05
		_part(torso, vb, Vector3(0, 0.1 + 0.1 * k, 0.1), rib)

	var head := Node3D.new()
	head.position = Vector3(0, 0.66, -0.1)
	head.rotation.x = 0.6   # голова задрана вперёд, морда к игроку
	torso.add_child(head)
	var hs := SphereMesh.new()
	hs.radius = 0.13
	hs.height = 0.26
	var h := _part(head, hs, Vector3.ZERO, mat)
	h.scale = Vector3(0.9, 0.95, 1.2)
	var jaw := BoxMesh.new()
	jaw.size = Vector3(0.14, 0.04, 0.14)
	var jw := _part(head, jaw, Vector3(0, -0.1, -0.07), dark)
	jw.rotation.x = -0.35
	for side in [-1.0, 1.0]:
		var es := SphereMesh.new()
		es.radius = 0.028
		es.height = 0.056
		_part(head, es, Vector3(0.055 * side, 0.02, -0.14), eye)
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.7, 1.0, 0.6)
	glow.light_energy = 0.2
	glow.omni_range = 0.6
	glow.position = Vector3(0, 0.02, -0.25)
	head.add_child(glow)

	for side in [-1.0, 1.0]:
		var sh := Node3D.new()
		sh.position = Vector3(0.18 * side, 0.52, 0)
		sh.rotation.z = 0.2 * side
		torso.add_child(sh)
		var arm := CapsuleMesh.new()
		arm.radius = 0.04
		arm.height = 0.78
		_part(sh, arm, Vector3(0, -0.36, 0), mat)
		# когти
		for k in 3:
			var cl := CylinderMesh.new()
			cl.top_radius = 0.003
			cl.bottom_radius = 0.012
			cl.height = 0.11
			var cm := _part(sh, cl, Vector3((k - 1) * 0.025, -0.8, -0.02), dark)
			cm.rotation.x = 0.4
		arms.append(sh)

	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.24
	cap.height = height
	cs.shape = cap
	cs.position.y = height * 0.5
	add_child(cs)

	bar = Node3D.new()
	bar.position.y = height + 0.15
	bar.visible = false
	add_child(bar)
	_bar_quad(Color(0, 0, 0, 0.7), Vector2(0.5, 0.065), 0.0)
	bar_fg = _bar_quad(Color(0.7, 0.14, 0.08), Vector2(0.48, 0.045), 0.01)


func _animate(delta: float, spd: float) -> void:
	if state == "dead":
		return
	walk_amt = lerpf(walk_amt, clampf(spd / speed, 0.0, 1.0), 1.0 - exp(-8.0 * delta))
	walk_ph += delta * spd * (3.2 if kind == "heavy" else 4.6)
	for i in 2:
		var s := 1.0 if i == 0 else -1.0
		legs[i].rotation.x = sin(walk_ph) * 0.5 * walk_amt * s
	var arm_x := 0.25
	var base := -0.38 if kind == "heavy" else -0.75
	var lean := base
	match state:
		"windup":
			arm_x = lerpf(0.25, 2.7, smoothstep(0.0, windup_t * 0.82, st))
			lean = lerpf(base, 0.05, smoothstep(0.0, windup_t * 0.82, st))
		"recover":
			arm_x = lerpf(0.6, 0.25, smoothstep(0.0, 0.6, st))
			lean = lerpf(base - 0.37, base, smoothstep(0.0, 0.6, st))
		"stagger":
			lean = base + 0.35 * sin(minf(st / 0.4, 1.0) * PI)
		"throw":
			# правая рука заносит камень за голову и выбрасывает вперёд
			arm_x = lerpf(0.25, 3.0, smoothstep(0.0, 0.55, st)) if st < 0.6 else lerpf(3.0, 0.9, smoothstep(0.6, 0.75, st))
			lean = lerpf(base, 0.15, smoothstep(0.0, 0.55, st)) if st < 0.6 else base - 0.3
		"leap_prep":
			lean = base - 0.25
		"leap":
			arm_x = 1.7
			lean = base - 0.35
		"crawl":
			# заблудший (intro.gd): почти на четвереньках, руки тянутся вперёд и подтягивают тело
			arm_x = 1.35
			lean = base - 0.6
	for i in 2:
		var s := 1.0 if i == 0 else -1.0
		var swing := -sin(walk_ph) * 0.35 * walk_amt * s if state == "chase" or state == "idle" else 0.0
		if state == "crawl":
			swing = -sin(walk_ph) * 0.6 * walk_amt * s
		arms[i].rotation.x = lerpf(arms[i].rotation.x, arm_x + swing, 1.0 - exp(-14.0 * delta))
	torso.rotation.x = lerpf(torso.rotation.x, lean, 1.0 - exp(-12.0 * delta))
	vis.position.y = absf(sin(walk_ph)) * 0.04 * walk_amt
	if state == "leap_prep":
		vis.position.y = -0.14 * smoothstep(0.0, 0.25, st)   # присела перед прыжком
	if state == "crawl":
		vis.position.y = -0.32 + absf(sin(walk_ph)) * 0.05 * walk_amt
	if kind == "fast" and state == "chase" and spd > 0.5:
		# рывок — прыжок: тело подлетает и наклоняется вперёд, в передышке приседает
		var hop := sin(clampf(dash_ph / 0.636, 0.0, 1.0) * PI) if dash_ph < 0.636 else 0.0
		vis.position.y = hop * 0.22 - (0.06 if dash_ph >= 0.636 else 0.0)
		torso.rotation.x = lerpf(torso.rotation.x, base - 0.25 * hop, 1.0 - exp(-14.0 * delta))
