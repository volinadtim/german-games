extends AnimatableBody3D
## Дверь на самом выходе из бункера на поверхность — в проёме будки после лестницы (промпт 18.11 01:38,
## было неверно: стояла в начале лестницы, у таблички про противогаз). E — открыть/закрыть.
## Пока у игрока нет Нюхича (в сумке или на лице) и дверь ни разу не открывалась — не открывается:
## по центру экрана «Я не хочу открывать это, пока не получу противогаз». Враги подходят — дверь распахивается сама.
## Проём: surface_build.gd X_OUT 21, G 4 (пол площадки), TW 1.1 (полуширина). Создаётся из game.gd.

const HINGE := Vector3(21.0, 4.0, -1.1)
const W := 2.14
const H := 2.3
const OPEN_ANG := -PI / 2.0 * 0.92   # створка открывается внутрь будки (−X), там после лестницы ровный пол

var game
var is_open := false
var was_opened := false              # открывали хоть раз — дальше без проверки
var tw: Tween
var wheel_tw: Tween
var wheel: Node3D
var snd: AudioStreamPlayer3D
var check_t := 0.0
var msg_layer: CanvasLayer
var msg_l: Label
var msg_tw: Tween


func _ready() -> void:
	position = HINGE
	sync_to_physics = false
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.5, 0.52, 0.55)
	steel.roughness = 0.35
	steel.metallic = 0.9
	_part(Vector3(0.1, H, W), Vector3(0, H / 2.0, W / 2.0), steel)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.1, 0.1, 0.11)
	dark.metallic = 0.7
	dark.roughness = 0.5
	# рёбра жёсткости бронедвери с обеих сторон
	for y in [0.35, H - 0.35]:
		_part(Vector3(0.13, 0.08, W - 0.1), Vector3(0, y, W / 2.0), dark)
	_build_wheel(steel, dark)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.08, H, W)
	cs.shape = sh
	cs.position = Vector3(0, H / 2.0, W / 2.0)
	add_child(cs)
	snd = AudioStreamPlayer3D.new()
	snd.position = Vector3(0, 1.2, W / 2.0)
	snd.unit_size = 4.0
	snd.max_distance = 34.0
	add_child(snd)


## Круглая вентильная ручка по центру створки (как на бункерной/сейфовой двери), с обеих сторон —
## отдельный узел, чтобы крутить его независимо от самой двери (визуально «откручивают» перед открытием.
func _build_wheel(steel: Material, dark: Material) -> void:
	wheel = Node3D.new()
	wheel.position = Vector3(0, H / 2.0, W / 2.0)
	add_child(wheel)
	for sx in [-1.0, 1.0]:
		var hub := MeshInstance3D.new()
		var hub_m := CylinderMesh.new()
		hub_m.top_radius = 0.05
		hub_m.bottom_radius = 0.05
		hub_m.height = 0.1
		hub.mesh = hub_m
		hub.material_override = dark
		hub.rotation_degrees = Vector3(0, 0, 90)
		hub.position = Vector3(sx * 0.1, 0, 0)
		wheel.add_child(hub)
		var ring := MeshInstance3D.new()
		var ring_m := TorusMesh.new()
		ring_m.inner_radius = 0.18
		ring_m.outer_radius = 0.24
		ring.mesh = ring_m
		ring.material_override = steel
		ring.rotation_degrees = Vector3(0, 0, 90)
		ring.position = Vector3(sx * 0.1, 0, 0)
		wheel.add_child(ring)
		for i in range(4):
			var spoke := MeshInstance3D.new()
			var spoke_m := BoxMesh.new()
			spoke_m.size = Vector3(0.03, 0.4, 0.03)
			spoke.mesh = spoke_m
			spoke.material_override = steel
			spoke.position = Vector3(sx * 0.1, 0, 0)
			spoke.rotation_degrees = Vector3(45.0 + 90.0 * i, 0, 0)
			wheel.add_child(spoke)


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
	return g.inv != null and g.inv.count("gasmask") + g.inv.count("gasmask2") > 0


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
	if wheel_tw:
		wheel_tw.kill()
	wheel_tw = create_tween()
	var turns := wheel.rotation.x + (1.0 if on else -1.0) * PI * 3.0
	wheel_tw.tween_property(wheel, "rotation:x", turns, 0.7).set_trans(Tween.TRANS_LINEAR)
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
	var c := Vector3(21.0, 4.0, 0.0)
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
