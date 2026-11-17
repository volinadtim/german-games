extends AnimatableBody3D
## Дверь в проёме к лестнице на поверхность (промпт 18.11 01:05). E — открыть/закрыть.
## Пока у игрока нет Нюхича (в сумке или на лице) и дверь ни разу не открывалась — не открывается:
## по центру экрана «Я не хочу открывать это, пока не получу противогаз». Враги подходят — дверь распахивается сама.
## Проём: level_geometry.gd X1 12, T 0.3, DOOR_W 1.7, DOOR_H 2.3. Создаётся из game.gd.

const HINGE := Vector3(12.0, 0.0, -0.85)
const W := 1.66
const H := 2.26
const OPEN_ANG := -PI / 2.0 * 0.92   # створка открывается в коридор (−X): к лестнице мешают ступени

var game
var is_open := false
var was_opened := false              # открывали хоть раз — дальше без проверки
var tw: Tween
var snd: AudioStreamPlayer3D
var check_t := 0.0
var msg_layer: CanvasLayer
var msg_l: Label
var msg_tw: Tween


func _ready() -> void:
	position = HINGE
	sync_to_physics = false
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.3, 0.27, 0.22)
	wood.roughness = 0.85
	wood.metallic = 0.35
	_part(Vector3(0.06, H, W), Vector3(0, H / 2.0, W / 2.0), wood)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.14, 0.13, 0.12)
	dark.metallic = 0.6
	dark.roughness = 0.6
	# рёбра жёсткости и ручки с обеих сторон
	for y in [0.35, H / 2.0, H - 0.35]:
		_part(Vector3(0.09, 0.08, W - 0.1), Vector3(0, y, W / 2.0), dark)
	for sx in [-1.0, 1.0]:
		_part(Vector3(0.08, 0.04, 0.16), Vector3(sx * 0.07, 1.0, W - 0.18), dark)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.08, H, W)
	cs.shape = sh
	cs.position = Vector3(0, H / 2.0, W / 2.0)
	add_child(cs)
	snd = AudioStreamPlayer3D.new()
	snd.position = Vector3(0, 1.2, W / 2.0)
	snd.unit_size = 4.0
	add_child(snd)


func _part(size: Vector3, pos: Vector3, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	add_child(mi)


func get_prompt(_g) -> String:
	return "[E] Закрыть дверь" if is_open else "[E] Открыть дверь"


func interact(g) -> void:
	if is_open:
		_set_open(false)
		return
	if not was_opened and not _has_mask(g):
		_say("Я не хочу открывать это, пока не получу противогаз")
		return
	_set_open(true)


func _has_mask(g) -> bool:
	if g == null:
		return true
	if g.gasmask and g.gasmask.worn:
		return true
	return g.inv != null and g.inv.count("gasmask") > 0


func _set_open(on: bool) -> void:
	if on == is_open:
		return
	is_open = on
	if on:
		was_opened = true
	if tw:
		tw.kill()
	tw = create_tween()
	tw.tween_property(self, "rotation:y", OPEN_ANG if on else 0.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if game and game.snd.has("creak"):
		snd.stream = game.snd["creak" if on else "creak_close"][randi() % 2]
		snd.volume_db = -12.0
		snd.pitch_scale = 0.7
		snd.play()


func _physics_process(delta: float) -> void:
	# враги (охотник с поляны) не должны упираться в закрытую дверь — открываем перед ними
	check_t -= delta
	if is_open or check_t > 0.0:
		return
	check_t = 0.2
	var c := Vector3(12.0, 0.0, 0.0)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Node3D and is_instance_valid(e) and (e as Node3D).global_position.distance_to(c) < 3.0:
			_set_open(true)
			return


## Мысль игрока по центру экрана: проявляется, держится ~2.5 с, тает.
func _say(text: String) -> void:
	if msg_layer == null:
		msg_layer = CanvasLayer.new()
		msg_layer.layer = 20
		add_child(msg_layer)
		msg_l = Label.new()
		msg_l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		msg_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		msg_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		msg_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		msg_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		msg_l.add_theme_font_size_override("font_size", 30)
		msg_l.add_theme_color_override("font_color", Color(0.93, 0.9, 0.82))
		msg_l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		msg_l.add_theme_constant_override("outline_size", 8)
		msg_layer.add_child(msg_l)
	msg_l.text = text
	if msg_tw:
		msg_tw.kill()
	msg_l.modulate.a = 0.0
	msg_tw = create_tween()
	msg_tw.tween_property(msg_l, "modulate:a", 1.0, 0.25)
	msg_tw.tween_interval(2.5)
	msg_tw.tween_property(msg_l, "modulate:a", 0.0, 0.6)
