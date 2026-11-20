extends Node3D
## Точка входа: уровень, меню (камера смотрит на игровой автомат), переход в игру.

const Player := preload("res://scripts/player/player.gd")
const Menu := preload("res://scripts/ui/menu.gd")
const Ambience := preload("res://scripts/core/ambience.gd")
const Game := preload("res://scripts/core/game.gd")   # тестовые механики (боёвка, лут, инвентарь, автомат…)
const SlotMachine := preload("res://scripts/slot/slot_machine.gd")
const TouchControls := preload("res://scripts/ui/touch_controls.gd")   # экранное управление (телефон)

## Меню: неподвижная камера под углом к игровому автомату KILLBOX (он стоит в юго-западной комнате).
const SLOT_POS := Vector3(-6.0, 0.0, 8.5)
const MENU_CAM_POS := Vector3(-5.0, 1.5, 6.3)    # с другой стороны автомата — магазин не в кадре
const MENU_CAM_LOOK := Vector3(-7.45, 1.35, 8.2)

var menu_cam: Camera3D
var menu_bg: CanvasLayer          # фон главного меню (ui/menu_scene.gd), убирается при входе в игру
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
		pass   # масштаб интерфейса теперь ставит menu.gd (_apply_ui_scale, ползунок «Размер интерфейса»)

	# уровень (и освещение/окружение) — узел Level в main.tscn, он виден и в редакторе
	_ensure_level()
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
		# доска висела под углом и одним краем отходила от стены на 16 см — ровно и вплотную (промпт 14.11 18:46)
		slot_board.rotation.y = 0.0
		slot_board.position.z = SlotMachine.BOARD_POS.z - 0.072
	# магазин оружия — слева от автомата (если смотреть на автомат)
	var shop := preload("res://scripts/shop/shop.gd").new()
	shop.name = "Shop"
	shop.position = SLOT_POS + Vector3(1.95, 0.0, 0.0)
	shop.rotation.y = PI
	add_child(shop)

	menu_cam = Camera3D.new()
	menu_cam.fov = 62.0
	add_child(menu_cam)
	menu_cam.current = true
	_update_fly(0.0, true)
	# фон меню — ночной бункер с персонажем (ui/menu_scene.gd, промпт 20.11 18:55); мир под ним не рисуем
	menu_bg = preload("res://scripts/ui/menu_scene.gd").new()
	add_child(menu_bg)
	menu_cam.cull_mask = 0

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
	post_mat.shader = preload("res://shaders/post.gdshader")
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
	# вернулись в меню из сетевой игры — выходим из комнаты
	var nt := get_tree().root.get_node_or_null("Net")
	if nt and nt.in_game:
		nt.leave()
	# «Начать заново» после смерти (game.gd: restart) — сразу в игру, минуя меню
	if Engine.has_meta("eskiness_autostart"):
		Engine.remove_meta("eskiness_autostart")
		# сразу в мир, меню не мелькает (промпт 03:18): тот же слот, новая игра; затемнение выше само уходит
		menu.visible = false
		in_game = true
		_enter_game.call_deferred()


## Узел Level без скрипта бункера (редактор пересохранил main.tscn со старым путём после переноса скриптов) — пересоздаём его,
## иначе бункер без стен и пола, игрок падает (промпт 19:20).
func _ensure_level() -> void:
	var lv := get_node_or_null("Level")
	if lv != null and lv.get_script() != null:
		return
	push_warning("main.tscn: у узла Level нет скрипта уровня — создаю заново (locations/bunker/level.gd)")
	if lv != null:
		remove_child(lv)
		lv.free()
	var n := Node3D.new()
	n.name = "Level"
	n.set_script(load("res://scripts/locations/bunker/level.gd"))
	add_child(n)
	move_child(n, 0)


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
	if menu_bg:
		menu_bg.queue_free()
		menu_bg = null
	menu_cam.cull_mask = 0xFFFFF
	menu.net_box.visible = false   # страница сети не ловит Esc в игре (иначе net.leave() — вылет из комнаты)
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
	# сетевая игра (net.gd): комната открыта / подключены — игра общая
	var nt := get_tree().root.get_node_or_null("Net")
	if nt and nt.active():
		game.net = nt
	add_child(game)
	game.setup(player)
	menu.apply_settings()  # качество графики — и для узлов, созданных игрой (фонарик, лампы)
	# экранное управление — только на телефонах (или с флагом запуска `-- --touch`)
	if TouchControls.wanted():
		var tc := TouchControls.new()
		tc.setup(player, game)
		add_child(tc)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	preload("res://scripts/network/split.gd").attach(self)   # сплитскрин: второй игрок, экран пополам


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and Controls.event(event, "hide_ui"):
		_toggle_ui()   # F10 (переназначается) — скрыть/показать весь интерфейс (кроме меню)
		return
	if Controls.event(event, "toggle_fullscreen"):
		if menu:
			menu.toggle_fullscreen()   # режим экрана хранится в настройках меню
		else:
			toggle_fullscreen()


var ui_hidden := false


func _toggle_ui() -> void:
	ui_hidden = not ui_hidden
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CanvasLayer and (n == menu or n.layer < 0):   # меню и эффекты графики (постобработка, маска, split-экраны) не прячем
			continue
		if n is CanvasLayer:
			if ui_hidden:
				n.set_meta("f10_vis", n.visible)
				n.visible = false
			else:
				n.visible = bool(n.get_meta("f10_vis", true))
			continue
		stack.append_array(n.get_children())


static func toggle_fullscreen() -> void:
	var m := DisplayServer.window_get_mode()
	if m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


## Действия и клавиши создаёт autoload Controls (scripts/controls/controls.gd) по data/controls/bindings.cfg.
func _setup_input() -> void:
	pass


## Доска выплат автомата — дочерний узел, стоящий в BOARD_POS.
func _find_board() -> Node3D:
	for c in slot.get_children():
		if c is Node3D and (c as Node3D).position.distance_to(SlotMachine.BOARD_POS) < 0.01:
			return c
	return null
