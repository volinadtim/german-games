extends Node3D
## Точка входа: уровень, меню (камера смотрит на игровой автомат), переход в игру.

const Player := preload("res://player.gd")
const Menu := preload("res://menu.gd")
const Ambience := preload("res://ambience.gd")
const Game := preload("res://game.gd")   # тестовые механики (боёвка, лут, инвентарь, автомат…)
const SlotMachine := preload("res://slot_machine.gd")
const TouchControls := preload("res://touch_controls.gd")   # экранное управление (телефон)

## Меню: неподвижная камера под углом к игровому автомату KILLBOX (он стоит в юго-западной комнате).
const SLOT_POS := Vector3(-6.0, 0.0, 8.5)
const MENU_CAM_POS := Vector3(-5.0, 1.5, 6.3)    # с другой стороны автомата — магазин не в кадре
const MENU_CAM_LOOK := Vector3(-7.45, 1.35, 8.2)

var menu_cam: Camera3D
var slot_board: Node3D
var fly_t := 0.0
var slot: Node3D
var in_game := false
var player: CharacterBody3D
var menu: CanvasLayer
var fade: ColorRect
var post_mat: ShaderMaterial


func _ready() -> void:
	_setup_input()
	# телефон: интерфейс крупнее, но так, чтобы окна влезали при любом соотношении сторон
	if TouchControls.wanted():
		TouchControls.fit_ui(get_window())
		get_window().size_changed.connect(func(): TouchControls.fit_ui(get_window()))

	# уровень (и освещение/окружение) — узел Level в main.tscn, он виден и в редакторе
	add_child(Ambience.new())

	# игровой автомат — часть сцены меню (фон), в игре game.gd берёт его же
	slot = SlotMachine.new()
	slot.name = "SlotMachine"
	slot.position = SLOT_POS
	slot.rotation.y = PI
	add_child(slot)
	# доска выплат в главном меню не видна — появляется, когда начинается игра
	slot_board = _find_board()
	if slot_board:
		slot_board.visible = false
	# магазин оружия — слева от автомата (если смотреть на автомат)
	var shop := preload("res://shop.gd").new()
	shop.name = "Shop"
	shop.position = SLOT_POS + Vector3(1.95, 0.0, 0.0)
	shop.rotation.y = PI
	add_child(shop)

	menu_cam = Camera3D.new()
	menu_cam.fov = 62.0
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


## Камера меню стоит на месте, только чуть «дышит».
func _update_fly(delta: float, _snap: bool) -> void:
	fly_t += delta
	menu_cam.position = MENU_CAM_POS + Vector3(sin(fly_t * 0.31) * 0.01, sin(fly_t * 0.7) * 0.012, 0)
	menu_cam.look_at_from_position(menu_cam.position, MENU_CAM_LOOK + Vector3(sin(fly_t * 0.23) * 0.02, 0, 0))


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
	if slot_board:
		slot_board.visible = true
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
	# экранное управление — только на телефонах (или с флагом запуска `-- --touch`)
	if TouchControls.wanted():
		var tc := TouchControls.new()
		tc.setup(player, game)
		add_child(tc)
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


## Доска выплат автомата — дочерний узел, стоящий в BOARD_POS.
func _find_board() -> Node3D:
	for c in slot.get_children():
		if c is Node3D and (c as Node3D).position.distance_to(SlotMachine.BOARD_POS) < 0.01:
			return c
	return null
