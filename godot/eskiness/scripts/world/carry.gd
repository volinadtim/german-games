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


func _ready() -> void:
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


func _unhandled_input(e: InputEvent) -> void:
	if not e.is_action_pressed("carry") or e.is_echo():
		return
	if game == null or not game.alive or game.player == null or not game.player.active or game.window_open():
		return
	get_viewport().set_input_as_handled()
	if held:
		_drop()
	else:
		_pick()


func _aim() -> Object:
	var cam: Camera3D = game.player.cam
	var from := cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from - cam.global_transform.basis.z * REACH)
	q.collision_mask = 1
	q.exclude = [game.player.get_rid()]
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
	yaw_off = held.global_rotation.y - game.player.global_rotation.y
	game.player.carrying = true
	game.play_ui("pickup", -17.0, 0.8)   # мягкий шорох, без гула (промпт 16.11 00:20)
	game.hud.toast("Несёшь: B — поставить", Color(0.85, 0.85, 0.75))


func _hold_pos() -> Vector3:
	var p: Node3D = game.player
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
	if not is_instance_valid(held) or not game.alive:
		_release()
		return
	var p := _hold_pos()
	held.global_position = Vector3(p.x, game.player.global_position.y + HOLD_LIFT, p.z)
	held.global_rotation.y = game.player.global_rotation.y + yaw_off


func _drop() -> void:
	var p := _hold_pos()
	var y: float = game.player.global_position.y
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, y + 1.0, p.z), Vector3(p.x, y - 2.0, p.z))
	q.collision_mask = 1
	q.exclude = [game.player.get_rid()]
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		y = hit.position.y
	held.global_position = Vector3(p.x, y, p.z)
	var key := key_of(held)
	moved[key] = [held.global_position.x, held.global_position.y, held.global_position.z, held.global_rotation.y]
	game.play_ui("thud", -23.0, 1.8)    # тихий высокий стук — низкий гул давил на уши
	_release()


func _release() -> void:
	if held and is_instance_valid(held) and held is CollisionObject3D:
		(held as CollisionObject3D).collision_layer = held_layer
		(held as CollisionObject3D).collision_mask = held_mask
	held = null
	if game.player:
		game.player.carrying = false


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
