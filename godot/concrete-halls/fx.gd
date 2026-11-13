extends RefCounted
## Мелкие эффекты для тестовых механик: всплывающие цифры урона и облачко бетонной крошки.


static func damage_number(parent: Node, pos: Vector3, value: float, col := Color(1.0, 0.82, 0.5)) -> void:
	var l := Label3D.new()
	l.text = str(int(round(value)))
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 56
	l.pixel_size = 0.004
	l.outline_size = 12
	l.modulate = col
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.position = pos + Vector3(randf_range(-0.2, 0.2), 0.0, randf_range(-0.2, 0.2))
	parent.add_child(l)
	var tw := l.create_tween().set_parallel()
	tw.tween_property(l, "position:y", l.position.y + 0.6, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.5).set_delay(0.4)
	tw.tween_property(l, "outline_modulate:a", 0.0, 0.5).set_delay(0.4)
	tw.chain().tween_callback(l.queue_free)


static func dust_burst(parent: Node, pos: Vector3, col := Color(0.42, 0.4, 0.37), amount := 16) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = 0.8
	p.position = pos
	p.direction = Vector3(0, 1, 0)
	p.spread = 70.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 2.4
	p.gravity = Vector3(0, -7, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.4
	var bm := BoxMesh.new()
	bm.size = Vector3(0.035, 0.035, 0.035)
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 1.0
	bm.material = m
	p.mesh = bm
	parent.add_child(p)
	p.emitting = true
	p.get_tree().create_timer(1.3).timeout.connect(p.queue_free)
