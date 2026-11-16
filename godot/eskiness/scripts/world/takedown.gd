extends Node
## Стелс-добивание (промпт 16.11 03:13): подошёл к мелкому врагу сзади — вприсядку или пока он тебя
## не заметил — E: один удар (стойка, удар правой с полным зарядом), враг падает сразу.
## Мелкие — ниже 1.7 м: «Шныга» (enemy.gd kind fast) и «Плевун» (village/mutant.gd spitter).
## game.gd спрашивает candidate() каждый кадр и ставит этот узел в focus — E вызывает interact().

const REACH := 1.7
const SMALL_H := 1.7
## враг ничего не подозревает (подходить можно и не вприсядку)
const UNAWARE := ["idle", "investigate", "return", "crawl"]
## в этих состояниях не добить даже со спины (прыжок, замах, бросок…)
const BUSY := ["dead", "windup", "leap", "leap_prep", "throw", "spit", "swipe", "lunge", "charge", "roar", "slam_prep", "spit_prep"]

signal killed(enemy: Node)

var game
var busy := false
var target: Node = null


## Враг, которого сейчас можно добить (или null).
func candidate() -> Node:
	target = null
	if busy or game == null or not game.alive:
		return null
	var p = game.player
	if p == null or p.carrying or not p.active:
		return null
	var pp: Vector3 = p.global_position
	var look: Vector3 = -p.cam.global_transform.basis.z
	look.y = 0.0
	look = look.normalized()
	var best_d := REACH
	for g in ["enemies", "mutants"]:
		for e in game.get_tree().get_nodes_in_group(g):
			if not is_instance_valid(e) or float(e.get("height")) >= SMALL_H:
				continue
			var s := String(e.get("state"))
			if s in BUSY or not (p.crouched or s in UNAWARE):
				continue
			var to: Vector3 = (e as Node3D).global_position - pp
			if absf(to.y) > 1.0:
				continue
			to.y = 0.0
			var d := to.length()
			if d > best_d or d < 0.05:
				continue
			var n := to / d
			var efwd: Vector3 = -(e as Node3D).global_transform.basis.z
			efwd.y = 0.0
			# игрок за спиной врага и смотрит на него
			if efwd.normalized().dot(n) < 0.35 or look.dot(n) < 0.55:
				continue
			best_d = d
			target = e
	return target


func get_prompt(_g) -> String:
	return "E — добить" if target != null else ""


func interact(_g) -> void:
	if busy or target == null or not is_instance_valid(target):
		return
	_strike(target)


func _strike(e: Node) -> void:
	busy = true
	var p = game.player
	if not p.fists:
		p.toggle_fists()
		await get_tree().create_timer(0.3, false).timeout
	var t := 0.0
	while p.punching and t < 0.6:
		await get_tree().process_frame
		t += get_process_delta_time()
	p.punch(1, 1.0)
	await get_tree().create_timer(0.13, false).timeout
	if is_instance_valid(e) and String(e.get("state")) != "dead":
		var dir: Vector3 = (e as Node3D).global_position - p.global_position
		dir.y = 0.0
		e.take_hit(float(e.get("max_hp")) * 3.0 + 50.0, dir.normalized())
		killed.emit(e)
	busy = false
