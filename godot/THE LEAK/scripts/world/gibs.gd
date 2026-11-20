extends RefCounted
## Развал трупа (промпт 16.11 03:53): каждая деталь модели врага становится отдельным RigidBody3D
## с импульсом от удара. Куски сталкиваются только с миром (слой 1) — игрок их не толкает.
## Через LIFE секунд куски замирают, сжимаются и уходят в пол, затем удаляются.
## Вызывается из _die у всех врагов, в т.ч. у сетевых копий — развал случается у всех.

const LIFE := 8.0
const FADE := 1.4
const MAX_PARTS := 32


static func shatter(body: Node3D, vis: Node3D, dir: Vector3) -> void:
	if body == null or vis == null or not body.is_inside_tree():
		return
	var world := body.get_parent()
	if world == null:
		return
	var tree := body.get_tree()
	var center := body.global_position + Vector3(0, 0.8, 0)
	var flat := Vector3(dir.x, 0, dir.z)
	flat = flat.normalized() if flat.length() > 0.01 else Vector3.ZERO
	var meshes: Array = []
	_collect(vis, meshes)
	var n := 0
	for mi in meshes:
		if n >= MAX_PARTS:
			break
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.is_visible_in_tree():
			continue
		var gt: Transform3D = m.global_transform
		var aabb: AABB = m.get_aabb()
		var sc: Vector3 = gt.basis.get_scale()
		var size := (aabb.size * sc).abs()
		if size.length() < 0.05:
			continue
		n += 1
		var b := gt.basis.orthonormalized()
		var origin: Vector3 = gt * aabb.get_center()
		var rb := RigidBody3D.new()
		rb.collision_layer = 0
		rb.collision_mask = 1
		rb.mass = clampf(size.x * size.y * size.z * 40.0, 0.2, 4.0)
		rb.linear_damp = 0.4
		rb.angular_damp = 1.2
		var pm := PhysicsMaterial.new()
		pm.friction = 1.0
		pm.rough = true
		pm.bounce = 0.05
		rb.physics_material_override = pm
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(maxf(size.x, 0.06), maxf(size.y, 0.06), maxf(size.z, 0.06))
		cs.shape = box
		rb.add_child(cs)
		var copy := MeshInstance3D.new()
		copy.mesh = m.mesh
		copy.material_override = m.material_override
		for s in m.get_surface_override_material_count():
			copy.set_surface_override_material(s, m.get_surface_override_material(s))
		copy.cast_shadow = m.cast_shadow
		rb.add_child(copy)
		world.add_child(rb)
		var rt := Transform3D(b, origin)
		rb.global_transform = rt
		copy.transform = rt.affine_inverse() * gt
		var out := origin - center
		out = out.normalized() if out.length() > 0.01 else Vector3.UP
		rb.linear_velocity = flat * randf_range(1.5, 3.5) + out * randf_range(0.6, 2.0) + Vector3(0, randf_range(1.0, 2.6), 0)
		rb.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
		tree.create_timer(LIFE + randf() * 0.8, false).timeout.connect(func(): _fade(rb, copy))
	vis.visible = false


static func _collect(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			out.append(c)
		_collect(c, out)


## Растворение: кусок замирает, сжимается и опускается в пол, затем удаляется.
static func _fade(rb: RigidBody3D, copy: MeshInstance3D) -> void:
	if not is_instance_valid(rb):
		return
	rb.freeze = true
	var tw := rb.create_tween().set_parallel()
	tw.tween_property(copy, "scale", copy.scale * 0.05, FADE).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(rb, "position:y", rb.position.y - 0.35, FADE)
	tw.chain().tween_callback(rb.queue_free)
