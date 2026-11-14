extends Node
## Бросок камня игроком (промпт 14.11 20:08): действие «throw_stone» (T, «Бросить камень» в «Управлении»)
## или пункт «Бросить камень» в меню ПКМ камня в инвентаре. Камень (предмет stone, с каменных кучек)
## летит по дуге из руки; упал — стук и пыль, враги в HEAR_R, которые не видят игрока, идут проверить место
## и стоят там пару секунд (enemy.gd: hear_stone) — отвлечь. Попал во врага — малый урон, враг агрится — привлечь.
## После падения камень лежит на земле обычным предметом (pickup.gd) — его можно подобрать снова.

const Fx := preload("res://fx.gd")
const HEAR_R := 15.0
const DMG := 6.0
const SPEED := 15.0
const CD := 0.55

var game
var cd := 0.0


func _ready() -> void:
	if not InputMap.has_action("throw_stone"):
		InputMap.add_action("throw_stone")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_T
		InputMap.action_add_event("throw_stone", ev)


func _process(delta: float) -> void:
	cd -= delta


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("throw_stone") and not e.is_echo() and game.alive and game.player.active and not game.window_open():
		throw()


func throw() -> void:
	if cd > 0.0 or not game.alive or game.player == null:
		return
	if game.inv.count("stone") <= 0:
		game.hud.toast("Нет камней — набери с каменной кучки")
		return
	if not game.inv.remove("stone", 1):
		return
	cd = CD
	var p = game.player
	var cb: Basis = p.cam.global_transform.basis
	var eye: Vector3 = p.cam.global_position
	var dir := -cb.z
	# из правой руки, чуть ниже глаз; рука упёрлась в стену — бросок от лица
	var from := eye + dir * 0.35 + cb.x * 0.22 - cb.y * 0.12
	var q := PhysicsRayQueryParameters3D.create(eye, from)
	q.collision_mask = 1
	q.exclude = [p.get_rid()]
	if not p.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		from = eye
	var s := Stone.new()
	s.game = game
	s.vel = dir * SPEED + Vector3(0, 2.2, 0) + p.velocity * Vector3(0.5, 0.0, 0.5)
	s.player_rid = p.get_rid()
	game.add_child(s)
	s.global_position = from
	game.play_at("whoosh", from, -12.0, 1.4)
	if game.inv.open:
		game.inv._refresh()


## Летящий камень: дуга, лучом от прошлой точки до новой. Удар — стук, пыль, шум для врагов, камень ложится на пол.
class Stone extends Node3D:
	const G := 14.0
	var game
	var vel := Vector3.ZERO
	var life := 4.0
	var player_rid: RID
	var spin := Vector3.ZERO

	func _ready() -> void:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.07
		sm.height = 0.12
		sm.radial_segments = 7
		sm.rings = 4
		mi.mesh = sm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.46, 0.45, 0.42)
		m.roughness = 1.0
		mi.material_override = m
		mi.scale = Vector3(1.0, 0.8, 1.2)
		add_child(mi)
		spin = Vector3(randf_range(-10, 10), randf_range(-10, 10), randf_range(-10, 10))

	func _physics_process(delta: float) -> void:
		life -= delta
		if life <= 0.0:
			queue_free()
			return
		vel.y -= G * delta
		var from := global_position
		var to := from + vel * delta
		rotation += spin * delta
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.collision_mask = 1
		q.exclude = [player_rid]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty():
			global_position = to
			return
		var at: Vector3 = hit.position
		var nrm: Vector3 = hit.normal
		var col = hit.collider
		if col != null and col.has_method("take_hit") and col.is_in_group("enemies"):
			# попал во врага: малый урон и агро (apply_hit → stagger → chase). Износ оружия в руке не трогаем.
			var p = game.player
			var la: int = p.last_arm
			p.last_arm = -1
			col.take_hit(DMG, vel.normalized())
			p.last_arm = la
			if col.has_method("_set_state") and col.get("state") in ["idle", "return", "investigate"]:
				col._set_state("chase")
			game.play_at("thud", at, -6.0, 1.3)
		else:
			Fx.dust_burst(game, at, Color(0.45, 0.43, 0.4), 8)
			game.play_at("thud", at, -5.0, 1.9)
			for e in game.get_tree().get_nodes_in_group("enemies"):
				if e != col and e.has_method("hear_stone") and e.global_position.distance_to(at) < HEAR_R:
					e.hear_stone(at)
		# камень ложится на пол — обычный предмет, можно подобрать снова
		var bounce := vel.bounce(nrm) * 0.2 if nrm != Vector3.ZERO else Vector3.ZERO
		game._make_pickup("stone", 1, at + nrm * 0.12, bounce)
		queue_free()
