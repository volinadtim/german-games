extends RefCounted
## Мелкие эффекты для тестовых механик: всплывающие цифры урона и облачко бетонной крошки.


## Точка для всплывающей надписи — так, чтобы игрок её точно видел (промпт 16.11 03:43): чуть ближе к камере
## и к центру экрана, не за спиной у камеры и не за краем экрана.
static func _to_view(parent: Node, pos: Vector3) -> Vector3:
	var cam := parent.get_viewport().get_camera_3d() if parent.is_inside_tree() else null
	if cam == null:
		return pos
	var cp := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var v := pos - cp
	var along := v.dot(fwd)
	if along < 0.6:
		return cp + fwd * 1.2 + cam.global_transform.basis.y * 0.15   # сзади или вплотную — перед глазами
	var axis := cp + fwd * along
	var p := pos.lerp(axis, 0.3)                 # к центру экрана
	p = cp + (p - cp) * 0.85                    # и к камере
	# за краем экрана — подтягиваем к оси взгляда, пока не войдёт в кадр (с полями 10%)
	var vp := parent.get_viewport().get_visible_rect().size
	for i in 4:
		var sp := cam.unproject_position(p)
		if sp.x > vp.x * 0.1 and sp.x < vp.x * 0.9 and sp.y > vp.y * 0.1 and sp.y < vp.y * 0.9:
			break
		p = p.lerp(cp + fwd * (p - cp).dot(fwd), 0.4)
	return p


## Цифра урона: на 15% мельче и с меньшим разлётом (промпт 16.11 03:43); «666» (стелс-добивание) — красная.
static func damage_number(parent: Node, pos: Vector3, value: float, col := Color(1.0, 0.82, 0.5)) -> void:
	var l := Label3D.new()
	l.text = str(int(round(value)))
	if int(round(value)) == 666:
		col = Color(1.0, 0.12, 0.08)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 48
	l.pixel_size = 0.004
	l.outline_size = 10
	l.modulate = col
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.position = _to_view(parent, pos) + Vector3(randf_range(-0.17, 0.17), 0.0, randf_range(-0.17, 0.17)) * 0.6
	parent.add_child(l)
	var tw := l.create_tween().set_parallel()
	tw.tween_property(l, "position:y", l.position.y + 0.42, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.5).set_delay(0.4)
	tw.tween_property(l, "outline_modulate:a", 0.0, 0.5).set_delay(0.4)
	tw.chain().tween_callback(l.queue_free)


## Всплывающая надпись (КРИТ!, БЛОК, МОЩНО!) над точкой — тоже к камере, на 15% мельче.
## k — размер (1 — обычный; надпись заряженного удара — 0.5).
static func popup_text(parent: Node, pos: Vector3, text: String, col: Color, k := 1.0) -> void:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = int(54 * k)
	l.pixel_size = 0.004
	l.outline_size = int(12 * k)
	l.modulate = col
	l.outline_modulate = Color(0, 0, 0, 0.9)
	var at := _to_view(parent, pos)
	l.position = at
	parent.add_child(l)
	var tw := l.create_tween().set_parallel()
	tw.tween_property(l, "position:y", at.y + 0.38, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector3.ONE * 1.25, 0.12)
	tw.tween_property(l, "modulate:a", 0.0, 0.4).set_delay(0.45)
	tw.tween_property(l, "outline_modulate:a", 0.0, 0.4).set_delay(0.45)
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
