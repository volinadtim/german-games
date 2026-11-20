extends Node
## Перенос объектов в руках (промпт 15.11 23:31): B — поднять то, на что смотришь, B ещё раз — поставить.
## Переносить можно постройки по чертежам (bunker_home.gd), манекен и сундук дома. В инвентарь они не попадают —
## держатся перед игроком; пока несёшь, нельзя драться, бегать и прыгать (player.gd смотрит player.carrying).
## Новые места пишутся в сейв (game_save.gd: "moved"): ключ -> [x, y, z, поворот].

const REACH := 2.6
const HOLD_D := 1.25      # на каком расстоянии перед игроком держим
const HOLD_LIFT := 0.3    # насколько приподнят над полом

var game
var held: Node3D = null
var held_layer := 1
var held_mask := 1
var yaw_off := 0.0
var moved := {}           # ключ -> [x, y, z, rot_y]
var who: Node3D = null    # Split-Screen (network/split.gd): перенос игрока 2 — его player.gd; B жмёт split.gd
var share: Node = null    # ...и новые места пишет в перенос игрока 1 (он в сейве)
## Проверка места (промпт 16.11 04:28): нельзя ставить внутрь стен, пола, других объектов и игроков.
const FIT_TOL := 0.04     # допуск: формы сжимаются на столько с каждой стороны
const FIT_LIFT := 0.02    # и чуть приподнимаются — чтобы пол под объектом не считался пересечением
const FIT_MASK := 1 | 512 # мир + модели других игроков (net_base.gd: PUPPET_LAYER)
var blocked := false
var _ov_red: StandardMaterial3D
var _ov_green: StandardMaterial3D
var _ov_on: Material = null


func _ready() -> void:
	_ov_red = _ov_mat(Color(1.0, 0.1, 0.08, 0.45))
	_ov_green = _ov_mat(Color(0.2, 1.0, 0.3, 0.14))
	if not InputMap.has_action("carry"):
		InputMap.add_action("carry")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_B
		InputMap.action_add_event("carry", ev)


## Ключ переносимого объекта ("" — нельзя переносить).
func key_of(n: Object) -> String:
	if n == null or not (n is Node3D):
		return ""
	var sc: Script = n.get_script()
	if sc and sc.resource_path.get_file() == "dummy.gd":
		return "dummy"
	if n == game.storage:
		return "storage"
	if game.home:
		for id in game.home.nodes:
			if game.home.nodes[id] == n and n != game.home and String(id) in ["workbench", "rug", "cot"]:
				return "home_" + String(id)
	return ""


func _node_of(key: String) -> Node3D:
	if key == "storage":
		return game.storage
	if key == "dummy":
		for c in game.get_children():
			var sc: Script = c.get_script()
			if sc and sc.resource_path.get_file() == "dummy.gd":
				return c
		return null
	if key.begins_with("home_") and game.home:
		var n = game.home.nodes.get(key.substr(5))
		return n if n is Node3D else null
	return null


## Подсказка для HUD (добавляется к подсказке цели).
func hint(target: Object) -> String:
	if held:
		return "[B] Поставить"
	return "[B] Взять в руки" if key_of(target) != "" else ""


## Чей перенос: игрок 2 в Split-Screen (who) или игрок 1.
func _pl():
	return who if who != null else game.player


## B: взять / поставить (split.gd зовёт для игрока 2 от его лица).
func toggle() -> void:
	if held:
		_drop()
	else:
		_pick()


func _unhandled_input(e: InputEvent) -> void:
	if who != null or not e.is_action_pressed("carry") or e.is_echo():
		return
	if game == null or not game.alive or _pl() == null or not _pl().active or game.window_open():
		return
	get_viewport().set_input_as_handled()
	if held:
		_drop()
	else:
		_pick()


func _aim() -> Object:
	var cam: Camera3D = _pl().cam
	var from := cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from - cam.global_transform.basis.z * REACH)
	q.collision_mask = 1
	q.exclude = [_pl().get_rid()]
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.collider if hit else null


func _pick() -> void:
	var t = _aim()
	if key_of(t) == "":
		return
	if t == game.storage and game.loot_window and game.loot_window.open:
		return
	held = t
	if held is CollisionObject3D:
		held_layer = (held as CollisionObject3D).collision_layer
		held_mask = (held as CollisionObject3D).collision_mask
		(held as CollisionObject3D).collision_layer = 0
		(held as CollisionObject3D).collision_mask = 0
	yaw_off = held.global_rotation.y - _pl().global_rotation.y
	_pl().carrying = true
	game.play_ui("pickup", -17.0, 0.8)   # мягкий шорох, без гула (промпт 16.11 00:20)
	game.hud.toast("Несёшь: B — поставить", Color(0.85, 0.85, 0.75))


func _hold_pos() -> Vector3:
	var p: Node3D = _pl()
	var fwd := -p.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var base := p.global_position
	var want := base + fwd * HOLD_D
	# не просовываем объект сквозь стену
	var q := PhysicsRayQueryParameters3D.create(base + Vector3(0, 0.5, 0), want + Vector3(0, 0.5, 0))
	q.collision_mask = 1
	q.exclude = [p.get_rid()]
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		want = base + fwd * maxf(0.4, base.distance_to(Vector3(hit.position.x, base.y, hit.position.z)) - 0.45)
	return want


func _process(_delta: float) -> void:
	if held == null:
		return
	if not is_instance_valid(held) or (who == null and not game.alive):
		_release()
		return
	var p := _hold_pos()
	held.global_position = Vector3(p.x, _pl().global_position.y + HOLD_LIFT, p.z)
	held.global_rotation.y = _pl().global_rotation.y + yaw_off
	blocked = is_blocked(held, Transform3D(Basis(Vector3.UP, held.global_rotation.y), _drop_pos()))
	_overlay(_ov_red if blocked else _ov_green)


## Куда встанет объект, если отпустить: под точкой удержания на полу.
func _drop_pos() -> Vector3:
	var p := _hold_pos()
	var y: float = _pl().global_position.y
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, y + 1.0, p.z), Vector3(p.x, y - 2.0, p.z))
	q.collision_mask = 1
	q.exclude = [_pl().get_rid()]
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		y = hit.position.y
	return Vector3(p.x, y, p.z)


## Пересекается ли объект n, поставленный в xf, с миром/объектами/игроками. Формы берутся из его CollisionShape3D,
## сжатые на FIT_TOL. Плоские объекты (ковёр) игроков не боятся — по ним можно ходить. Используется и в bunker_home.gd.
func is_blocked(n: Node3D, xf: Transform3D, exclude: Array = []) -> bool:
	if n == null:
		return false
	var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
	var inv := n.global_transform.affine_inverse()
	var ex: Array = exclude.duplicate()
	if n is CollisionObject3D:
		ex.append((n as CollisionObject3D).get_rid())
	var shapes: Array = []
	var flat := true
	for c in n.find_children("*", "CollisionShape3D", true, false):
		var cs := c as CollisionShape3D
		if cs.disabled or cs.shape == null:
			continue
		var sh := _shrunk(cs.shape)
		if sh == null:
			continue
		shapes.append([sh, inv * cs.global_transform])
		if _height(cs.shape) > 0.1:
			flat = false
	for s in shapes:
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = s[0]
		var t: Transform3D = xf * s[1]
		t.basis = t.basis.orthonormalized()
		t.origin.y += FIT_LIFT
		q.transform = t
		q.collision_mask = FIT_MASK if not flat else 1
		q.exclude = ex
		for h in space.intersect_shape(q, 8):
			var col = h.get("collider")
			if flat and col is CharacterBody3D:
				continue   # игроки/враги на ковре не мешают
			return true
	return false


func _height(sh: Shape3D) -> float:
	if sh is BoxShape3D:
		return (sh as BoxShape3D).size.y
	if sh is CylinderShape3D:
		return (sh as CylinderShape3D).height
	if sh is CapsuleShape3D:
		return (sh as CapsuleShape3D).height
	if sh is SphereShape3D:
		return (sh as SphereShape3D).radius * 2.0
	return 1.0


func _shrunk(sh: Shape3D) -> Shape3D:
	var d := FIT_TOL * 2.0
	if sh is BoxShape3D:
		var b := BoxShape3D.new()
		var sz: Vector3 = (sh as BoxShape3D).size
		b.size = Vector3(maxf(sz.x - d, sz.x * 0.4), maxf(sz.y - d, sz.y * 0.4), maxf(sz.z - d, sz.z * 0.4))
		return b
	if sh is CylinderShape3D:
		var c := CylinderShape3D.new()
		c.radius = maxf((sh as CylinderShape3D).radius - FIT_TOL, (sh as CylinderShape3D).radius * 0.4)
		c.height = maxf((sh as CylinderShape3D).height - d, (sh as CylinderShape3D).height * 0.4)
		return c
	if sh is CapsuleShape3D:
		var k := CapsuleShape3D.new()
		k.radius = maxf((sh as CapsuleShape3D).radius - FIT_TOL, (sh as CapsuleShape3D).radius * 0.4)
		k.height = maxf((sh as CapsuleShape3D).height - d, k.radius * 2.0)
		return k
	if sh is SphereShape3D:
		var sp := SphereShape3D.new()
		sp.radius = maxf((sh as SphereShape3D).radius - FIT_TOL, (sh as SphereShape3D).radius * 0.4)
		return sp
	return sh


## Подсветка переносимого объекта: красная — нельзя поставить, лёгкий зелёный — можно.
func _overlay(m: Material) -> void:
	if m == _ov_on or held == null:
		return
	_ov_on = m
	for c in held.find_children("*", "GeometryInstance3D", true, false):
		if c is Label3D:
			continue
		(c as GeometryInstance3D).material_overlay = m


func _ov_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _drop() -> void:
	var p := _drop_pos()
	if is_blocked(held, Transform3D(Basis(Vector3.UP, held.global_rotation.y), p)):
		game.play_ui("buzz", -14.0)
		game.hud.toast("Здесь не поставить — мешает", Color(1.0, 0.5, 0.4))
		return
	held.global_position = p
	var key := key_of(held)
	(share if share != null else self).moved[key] = [held.global_position.x, held.global_position.y, held.global_position.z, held.global_rotation.y]
	game.play_ui("thud", -23.0, 1.8)    # тихий высокий стук — низкий гул давил на уши
	_release()


func _release() -> void:
	if held and is_instance_valid(held):
		_overlay(null)
	_ov_on = null
	blocked = false
	if held and is_instance_valid(held) and held is CollisionObject3D:
		(held as CollisionObject3D).collision_layer = held_layer
		(held as CollisionObject3D).collision_mask = held_mask
	held = null
	if _pl():
		_pl().carrying = false


func to_save() -> Dictionary:
	return moved.duplicate(true)


func from_save(d: Dictionary) -> void:
	if held:
		_release()
	moved = {}
	for k in d:
		var v: Array = d[k]
		moved[String(k)] = v
		var n := _node_of(String(k))
		if n and v.size() >= 4:
			n.global_position = Vector3(float(v[0]), float(v[1]), float(v[2]))
			n.global_rotation.y = float(v[3])
