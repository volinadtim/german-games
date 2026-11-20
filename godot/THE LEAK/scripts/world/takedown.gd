extends Node
## Стелс-добивание (промпт 16.11 03:13): подошёл к мелкому врагу сзади — вприсядку или пока он тебя
## не заметил — E: один удар (стойка, удар правой), над врагом «666», враг падает сразу.
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
			if not is_instance_valid(e):
				continue
			# сначала дешёвая проверка расстояния — дальние враги отсеиваются без строк и get()
			var to: Vector3 = (e as Node3D).global_position - pp
			if absf(to.y) > 1.0:
				continue
			to.y = 0.0
			var d := to.length()
			if d > best_d or d < 0.05:
				continue
			if float(e.get("height")) >= SMALL_H:
				continue
			var s := String(e.get("state"))
			if s in BUSY or not (p.crouched or s in UNAWARE):
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
	return "Удар в спину [F]" if target != null else ""


func interact(_g) -> void:
	if busy or target == null or not is_instance_valid(target):
		return
	_strike(target)


func _strike(e: Node) -> void:
	busy = true
	var p = game.player
	# сам удар — только анимация: тело врага на время убираем из лучей, чтобы кулак не нанёс
	# свой урон и не вывел «МОЩНО!»; убивает добивание ниже (666, промпт 16.11 03:36)
	var body := e as CollisionObject3D
	var layer := body.collision_layer if body else 0
	if body:
		body.collision_layer = 0
	if not p.fists:
		p.toggle_fists()
		await get_tree().create_timer(0.32, false).timeout
	var t := 0.0
	while p.punching and t < 0.6:
		await get_tree().process_frame
		t += get_process_delta_time()
	p.fist_blend = maxf(p.fist_blend, 0.95)
	p.punch(1, 0.0)
	await get_tree().create_timer(0.13, false).timeout
	if is_instance_valid(e) and String(e.get("state")) != "dead":
		if body:
			body.collision_layer = layer
		var en := e as Node3D
		var dir: Vector3 = en.global_position - p.global_position
		dir.y = 0.0
		dir = dir.normalized()
		game.play_at("thud", en.global_position + Vector3(0, 0.6, 0), -7.9, 0.75)   # тише: 04:06 −3.5 дБ, 04:24 ещё −15% (−1.4 дБ)
		if bool(e.get("net_puppet")):
			e.take_hit(666.0, dir)
		else:
			e.hp = 0.5
			e.apply_hit(666.0, dir)   # «666» над врагом, падает и умирает
			if String(e.get("state")) != "dead" and e.has_method("_die"):
				e._die(dir)
		killed.emit(e)
		# труп уходит в пол и исчезает, как при обычной смерти: без физики, чтобы пол не выталкивал его обратно
		get_tree().create_timer(7.9, false).timeout.connect(_sink.bind(e))
	elif is_instance_valid(e) and body:
		body.collision_layer = layer
	busy = false


func _sink(e) -> void:
	if not is_instance_valid(e):
		return
	e.set_physics_process(false)
	var tw: Tween = e.create_tween()
	tw.tween_property(e, "position:y", (e as Node3D).position.y - 0.9, 3.0)
	tw.tween_callback(e.queue_free)
