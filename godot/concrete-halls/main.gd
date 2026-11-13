extends Node3D
## Точка входа: уровень, меню с пролётом камеры, переход в игру.

const Player := preload("res://player.gd")
const Menu := preload("res://menu.gd")
const Ambience := preload("res://ambience.gd")
const Game := preload("res://game.gd")   # тестовые механики (боёвка, лут, инвентарь, автомат…)

const FLY_POINTS := [
	Vector3(-6.0, 1.8, -7.5),
	Vector3(-6.3, 1.6, -3.5),
	Vector3(-6.0, 1.6, -1.2),
	Vector3(-3.5, 1.5, 0.2),
	Vector3(3.5, 1.5, -0.2),
	Vector3(6.0, 1.6, 2.0),
	Vector3(6.3, 1.8, 5.0),
	Vector3(5.0, 2.0, 7.5),
]

var menu_cam: Camera3D
var curve: Curve3D
var fly_t := 0.0
var fly_yaw := 0.0
var in_game := false
var player: CharacterBody3D
var menu: CanvasLayer
var fade: ColorRect
var post_mat: ShaderMaterial


func _ready() -> void:
	_setup_input()

	# уровень (и освещение/окружение) — узел Level в main.tscn, он виден и в редакторе
	add_child(Ambience.new())

	curve = Curve3D.new()
	for i in FLY_POINTS.size():
		var prev: Vector3 = FLY_POINTS[max(i - 1, 0)]
		var next: Vector3 = FLY_POINTS[min(i + 1, FLY_POINTS.size() - 1)]
		var h := (next - prev) * 0.25
		curve.add_point(FLY_POINTS[i], -h, h)

	menu_cam = Camera3D.new()
	menu_cam.fov = 70.0
	add_child(menu_cam)
	menu_cam.current = true
	_update_fly(0.0, true)

	menu = Menu.new()
	add_child(menu)
	menu.play_pressed.connect(_start_game)

	# постобработка (постеризация, размытие ударов) — под меню и затемнением
	var pl := CanvasLayer.new()
	pl.layer = -1
	add_child(pl)
	var post := ColorRect.new()
	post.set_anchors_preset(Control.PRESET_FULL_RECT)
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_mat = ShaderMaterial.new()
	post_mat.shader = preload("res://post.gdshader")
	post.material = post_mat
	pl.add_child(post)
	menu.post_mat = post_mat
	menu.apply_settings()

	var fl := CanvasLayer.new()
	fl.layer = 10
	add_child(fl)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 1)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fl.add_child(fade)
	create_tween().tween_property(fade, "color:a", 0.0, 1.5)


func _process(delta: float) -> void:
	if not in_game:
		_update_fly(delta, false)


func _update_fly(delta: float, snap: bool) -> void:
	fly_t += delta
	var length := curve.get_baked_length()
	var w := PI * 0.9 / length  # средняя скорость ~0.9 м/с
	var u := length * (0.5 - 0.5 * cos(fly_t * w))
	var dir_sign := 1.0 if sin(fly_t * w) >= 0.0 else -1.0
	var pos := curve.sample_baked(u, true)
	var tng := (curve.sample_baked(min(u + 0.5, length), true) - curve.sample_baked(max(u - 0.5, 0.0), true)) * dir_sign
	var want := atan2(-tng.x, -tng.z) if tng.length() > 0.01 else fly_yaw
	if snap:
		fly_yaw = want
	else:
		fly_yaw = lerp_angle(fly_yaw, want, 1.0 - exp(-0.8 * delta))
	menu_cam.position = pos + Vector3(0, sin(fly_t * 0.7) * 0.05, 0)
	menu_cam.rotation = Vector3(-0.05 + sin(fly_t * 0.37) * 0.04, fly_yaw + sin(fly_t * 0.23) * 0.12, sin(fly_t * 0.31) * 0.015)


func _start_game() -> void:
	if in_game:
		return
	in_game = true
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.7)
	tw.tween_callback(_enter_game)
	tw.tween_interval(0.35)
	tw.tween_property(fade, "color:a", 0.0, 0.9)


func _enter_game() -> void:
	menu.visible = false
	menu.in_game = true
	player = Player.new()
	player.position = Vector3(-10.5, 0.05, 0.0)
	player.rotation.y = -PI / 2.0
	add_child(player)
	player.cam.current = true
	player.active = true
	player.post_mat = post_mat
	var game := Game.new()
	add_child(game)
	game.setup(player)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		toggle_fullscreen()


static func toggle_fullscreen() -> void:
	var m := DisplayServer.window_get_mode()
	if m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _setup_input() -> void:
	_add_keys("move_forward", [KEY_W, KEY_UP])
	_add_keys("move_back", [KEY_S, KEY_DOWN])
	_add_keys("move_left", [KEY_A, KEY_LEFT])
	_add_keys("move_right", [KEY_D, KEY_RIGHT])
	_add_keys("sprint", [KEY_SHIFT])
	_add_keys("jump", [KEY_SPACE])
	_add_keys("toggle_fullscreen", [KEY_F11])


func _add_keys(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
