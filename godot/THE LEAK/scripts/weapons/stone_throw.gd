extends Node
## Бросок камня игроком (промпт 14.11 20:08, как оружие — 16.11 02:13): камень берут в руку («Взять в руку»),
## ПКМ держать — замах и прицел (рисуется дуга полёта и точка падения), ЛКМ при этом — бросок; без ПКМ ЛКМ — удар камнем
## (player_combat.gd). Брошенный из руки заменяется следующим из сумки, камни кончились — рука пустая.
## Камень (предмет stone, с каменных кучек) летит по дуге из руки; упал — стук и пыль, враги в HEAR_R, которые не видят игрока, идут проверить место
## и стоят там пару секунд (enemy.gd: hear_stone) — отвлечь. Попал во врага — малый урон, враг агрится — привлечь.
## После падения камень лежит на земле обычным предметом (pickup.gd) — его можно подобрать снова.

const Fx := preload("res://scripts/core/fx.gd")
const HEAR_R := 15.0
const DMG := 6.0
const SPEED := 15.0
const CD := 0.55

const SLOTS := ["left", "right"]

var game
var cd := 0.0
var aiming := false              # ПКМ держат с камнем в руке
var arc: MeshInstance3D
var arc_mesh: ImmediateMesh
var arc_mat: StandardMaterial3D


func _ready() -> void:
	arc_mesh = ImmediateMesh.new()
	arc = MeshInstance3D.new()
	arc.mesh = arc_mesh
	arc.top_level = true
	arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arc_mat = StandardMaterial3D.new()
	arc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	arc_mat.vertex_color_use_as_albedo = true
	arc_mat.no_depth_test = true
	arc.material_override = arc_mat
	add_child(arc)


## Рука с камнем: 1 — правая, 0 — левая, -1 — нет.
func hand() -> int:
	if game == null or game.inv == null:
		return -1
	if game.inv.equip["right"] == "stone":
		return 1
	if game.inv.equip["left"] == "stone":
		return 0
	return -1


func rmb_input(down: bool) -> void:
	aiming = down and hand() >= 0


func _process(delta: float) -> void:
	cd -= delta
	var p = game.player if game else null
	if aiming and (p == null or hand() < 0 or not game.alive or not p.active or game.inv.open \
			or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED):
		aiming = false
	if p != null:
		p.throw_aim = aiming   # поза замаха (player_anim.gd: _gun_pose), уходит в сеть
	arc_mesh.clear_surfaces()
	if aiming:
		_draw_arc()


## Откуда и с какой скоростью полетит камень.
func _launch() -> Array:
	var p = game.player
	var cb: Basis = p.cam.global_transform.basis
	var eye: Vector3 = p.cam.global_position
	var dir := -cb.z
	var side := 1.0 if hand() != 0 else -1.0
	# из руки, чуть ниже глаз; рука упёрлась в стену — бросок от лица
	var from := eye + dir * 0.35 + cb.x * 0.22 * side - cb.y * 0.12
	var q := PhysicsRayQueryParameters3D.create(eye, from)
	q.collision_mask = 1
	q.exclude = [p.get_rid()]
	if not p.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		from = eye
	return [from, dir * SPEED + Vector3(0, 2.2, 0) + p.velocity * Vector3(0.5, 0.0, 0.5)]


## Дуга полёта пунктиром и кружок в точке падения (тот же расчёт, что у Stone).
func _draw_arc() -> void:
	var l := _launch()
	var pos: Vector3 = l[0]
	var vel: Vector3 = l[1]
	var space: PhysicsDirectSpaceState3D = game.player.get_world_3d().direct_space_state
	var pts: Array[Vector3] = [pos]
	var hit := {}
	var dt := 1.0 / 60.0
	for k in 180:
		vel.y -= Stone.G * dt
		var to := pos + vel * dt
		var q := PhysicsRayQueryParameters3D.create(pos, to)
		q.collision_mask = 1
		q.exclude = [game.player.get_rid()]
		hit = space.intersect_ray(q)
		if not hit.is_empty():
			pts.append(hit.position)
			break
		pos = to
		pts.append(pos)
	arc_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for k in range(0, pts.size() - 1, 2):
		var a := 0.75 * (1.0 - 0.5 * float(k) / float(pts.size()))
		arc_mesh.surface_set_color(Color(1, 1, 1, a))
		arc_mesh.surface_add_vertex(pts[k])
		arc_mesh.surface_set_color(Color(1, 1, 1, a))
		arc_mesh.surface_add_vertex(pts[k + 1])
	if not hit.is_empty():
		var n: Vector3 = hit.normal
		var t1 := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
		var t2 := n.cross(t1)
		var c: Vector3 = hit.position + n * 0.02
		for k in 16:
			var a0 := TAU * k / 16.0
			var a1 := TAU * (k + 1) / 16.0
			arc_mesh.surface_set_color(Color(1, 0.9, 0.6, 0.85))
			arc_mesh.surface_add_vertex(c + (t1 * cos(a0) + t2 * sin(a0)) * 0.18)
			arc_mesh.surface_set_color(Color(1, 0.9, 0.6, 0.85))
			arc_mesh.surface_add_vertex(c + (t1 * cos(a1) + t2 * sin(a1)) * 0.18)
	arc_mesh.surface_end()


## Бросок камня из руки (ЛКМ при зажатой ПКМ).
func throw() -> void:
	if cd > 0.0 or not game.alive or game.player == null:
		return
	var h := hand()
	if h < 0:
		return
	cd = CD
	game.player.throw_flick = 1.0
	var l := _launch()
	var from: Vector3 = l[0]
	# в руку — следующий камень из сумки, кончились — рука пустая
	var slot: String = SLOTS[h]
	if not game.inv.remove("stone", 1):
		game.inv.equip[slot] = ""
		game.inv.equip_dur.erase(slot)
		game._apply_equip(slot)
		aiming = false
		game.hud.toast("Камни кончились")
	game.inv.notify()
	var p = game.player
	var s := Stone.new()
	s.game = game
	s.vel = l[1]
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
