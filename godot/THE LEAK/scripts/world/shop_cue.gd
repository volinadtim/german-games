extends Node
## Подсказка после первого закрытия магазина (промпт 16.11 21:55): управление ~2.8 с заблокировано,
## камера плавно поворачивается к выходу на улицу (лестница у x ≈ 12, z ≈ 0), оттуда тихо доносятся
## шебуршание и рык монстров. Один раз за игру (game.shop_cue_done в сейве); в сети — только у себя.
const Sfx := preload("res://scripts/core/sfx.gd")
const EB := preload("res://scripts/enemy/enemy_base.gd")
const EXIT := Vector3(12.5, 1.2, 0.0)   # выход к лестнице (enemy_base.gd DOORS: проём x = 12)
const DUR := 2.8

var game
var t := 0.0
var snd: AudioStreamPlayer3D
var cues := [[0.15, "step"], [0.45, "growl"], [0.9, "step"], [1.2, "step"], [1.6, "screech"], [2.0, "step"]]
var next := 0
var pl                    # кто закрыл магазин (сплитскрин: может быть игрок 2 — у обоих его камера)
var hd                    # его HUD


func start() -> void:
	pl = game.player
	hd = game.hud
	var p = pl
	add_to_group("cutscene")   # пропуск (ui/cutscene_skip.gd)
	game.close_windows()
	p.set_lock("shop_cue", true)
	if hd and hd.has_method("set_cinematic"):
		hd.set_cinematic(true)
	snd = AudioStreamPlayer3D.new()
	snd.unit_size = 4.0
	snd.max_distance = 40.0
	snd.max_polyphony = 3
	game.add_child(snd)
	snd.global_position = EXIT


func _process(delta: float) -> void:
	if game == null or not is_instance_valid(pl) or not game.alive:
		_finish()
		return
	t += delta
	var p = pl
	var k := 1.0 - exp(-2.6 * delta)
	if t < DUR - 0.4:
		var v: Vector3 = EXIT - p.cam.global_position
		p.rotation.y = lerp_angle(p.rotation.y, atan2(-v.x, -v.z), k)
		p.head.rotation.x = lerpf(p.head.rotation.x, clampf(atan2(v.y, Vector2(v.x, v.z).length()), -1.2, 1.0), k)
	while next < cues.size() and t >= float(cues[next][0]):
		_sound(String(cues[next][1]))
		next += 1
	if t >= DUR:
		_finish()


func can_skip() -> bool:
	return t < DUR and is_processing()


func skip_cut() -> void:
	_finish()


func skip_shared() -> bool:
	return false


## Шорохи — приглушённые шаги-волочение, рык и визг — как у обычных врагов (enemy_combat.gd _growl), не громче.
func _sound(kind: String) -> void:
	if snd == null:
		return
	match kind:
		"step":
			snd.stream = Sfx.step(randi() % 4)
			snd.volume_db = -12.0
			snd.pitch_scale = randf_range(0.55, 0.75)
		"growl":
			var g: Array = game.snd["growl"]
			snd.stream = g[randi() % g.size()]
			snd.volume_db = -8.0
			snd.pitch_scale = randf_range(0.85, 1.0)
		"screech":
			snd.stream = EB._screech(randi() % 3)
			snd.volume_db = -10.0
			snd.pitch_scale = randf_range(0.9, 1.05)
	snd.play()


func _finish() -> void:
	if game and is_instance_valid(pl):
		pl.set_lock("shop_cue", false)
		if is_instance_valid(hd) and hd.has_method("set_cinematic"):
			hd.set_cinematic(false)
		if pl == game.player and pl.input_locks.is_empty() and not game.window_open():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if is_instance_valid(snd):
		var s := snd
		get_tree().create_timer(2.0).timeout.connect(func(): if is_instance_valid(s): s.queue_free())
	set_process(false)
	queue_free()
