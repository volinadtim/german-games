extends Node
## Split-Screen в одной игре (промпт 18.11 00:41, переделка 00:58): одно окно, экран пополам —
## слева игрок 1 (клавиатура+мышь; при двух геймпадах ещё и первый геймпад), справа игрок 2 (свой геймпад).
## Без второй копии игры и без лобби: обычная одиночная игра из слота, в которой появляется второй игрок.
## Как в сетевой игре: игрок 2 — модель player.gd (puppet), которую водит этот узел; враги выбирают
## ближайшего живого (enemy.gd / mutant.gd → pick_target); кат-сцены и машина показываются в обеих половинах,
## после них игрок 2 встаёт рядом с игроком 1.
## Свой HUD у игрока 1 (все слои интерфейса игры переносятся в левую половину), у игрока 2 — здоровье и прицел.
## Инвентаря и предметов у игрока 2 пока нет: кулаки, бег, прыжок, присед.
## Создаёт main.gd (_enter_game), если в меню выбран «Split-Screen» (pending). Узел — ребёнок main.

const PlayerScript := preload("res://scripts/player/player.gd")
const PUPPET_LAYER := 512
const HEAD1 := 1 << 19       # голова игрока 1: видна игроку 2, не видна себе
const HEAD2 := 1 << 18       # голова игрока 2: видна игроку 1
const MAX_HP := 100.0
const RESPAWN_T := 10.0

static var pending := false  # menu.gd: следующий запуск игры — сплитскрин
static var inst: Node        # для gamepad.gd: какой геймпад у игрока 1
static var swap_pads := false   # gamepad.gd (настройки): поменять геймпады игроков местами

var main
var game
var p1                       # player.gd игрока 1
var pp                       # player.gd (puppet) игрока 2
var body: CharacterBody3D    # физика игрока 2 (невидимая капсула)
var svs: Array = []          # [левый, правый] SubViewport
var cams: Array = []
var screens: CanvasLayer
var hud2: Control
var hp_l: Label
var info_l: Label
var flash: ColorRect
var tgt: Target2

var yaw := 0.0
var pitch := 0.0
var hp := MAX_HP
var alive := true
var dead_t := 0.0
var crouch := false
var crouch_hold := false
var sprint_latch := false
var jump_q := false
var mirrored := true
var sweep_t := 0.0
var head_paths: Array = []


## Цель для врагов (как RemoteTarget в net_base.gd): player, alive, damage_player.
class Target2:
	var player: CharacterBody3D
	var alive := true
	var split

	func damage_player(amount: float, from: Vector3) -> void:
		split.damage2(amount, from)


static func pad_device(for_p2: bool) -> int:
	var pads := Input.get_connected_joypads()
	if pads.size() >= 2:
		var i1 := 1 if swap_pads else 0   # третий и следующие геймпады не используются
		return pads[1 - i1] if for_p2 else pads[i1]
	if for_p2:
		return pads[0] if pads.size() == 1 else -1
	return -2


## main.gd: игра создана — добавить второго игрока и разделить экран.
static func attach(m) -> void:
	if not pending or m.get("player") == null:
		return
	var g = null
	for c in m.get_children():
		if c.has_method("save_now"):
			g = c
	if g == null:
		return
	var s := Node.new()
	s.set_script(load("res://scripts/network/split.gd"))
	s.name = "Split"
	s.main = m
	s.game = g
	s.p1 = m.player
	m.add_child(s)


func _ready() -> void:
	inst = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000   # камеры копируем после всех
	game.set_meta("split", self)
	Input.set_ignore_joypad_on_unfocused_application(false)
	Input.joy_connection_changed.connect(func(_d, _c): _pad_changed())
	_build_screens()
	_spawn_p2()
	_pad_changed()


func _exit_tree() -> void:
	if inst == self:
		inst = null
	get_tree().root.disable_3d = false
	if is_instance_valid(game):
		game.remove_meta("split")
	_pad_changed()


func _pad_changed() -> void:
	var menu = main.get("menu") if is_instance_valid(main) else null
	if menu and menu.get("pad"):
		menu.pad.apply_map()


# ---------- экран ----------

func _build_screens() -> void:
	var root := get_tree().root
	var world := root.find_world_3d()
	screens = CanvasLayer.new()
	screens.layer = -50   # под всем интерфейсом; сам корень 3D больше не рисует
	add_child(screens)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	screens.add_child(row)
	for i in 2:
		var cont := SubViewportContainer.new()
		cont.stretch = true
		cont.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cont.size_flags_vertical = Control.SIZE_EXPAND_FILL
		cont.mouse_filter = Control.MOUSE_FILTER_PASS   # обзор мышью игрока 1 доходит до player.gd
		row.add_child(cont)
		var sv := SubViewport.new()
		sv.world_3d = world
		sv.audio_listener_enable_3d = i == 0   # звук — от игрока 1
		sv.handle_input_locally = true
		cont.add_child(sv)
		var c := Camera3D.new()
		sv.add_child(c)
		c.current = true
		svs.append(sv)
		cams.append(c)
	root.disable_3d = true
	# интерфейс игрока 2
	var l2 := CanvasLayer.new()
	svs[1].add_child(l2)
	hud2 = Control.new()
	hud2.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l2.add_child(hud2)
	flash = ColorRect.new()
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(0.7, 0.0, 0.0, 0.0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud2.add_child(flash)
	var cross := Label.new()
	cross.text = "+"
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cross.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cross.add_theme_font_size_override("font_size", 22)
	cross.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	hud2.add_child(cross)
	var name_l := _lbl("ИГРОК 2", 20)
	name_l.position = Vector2(16, 10)
	hud2.add_child(name_l)
	hp_l = _lbl("", 28)
	hp_l.anchor_top = 1.0
	hp_l.anchor_bottom = 1.0
	hp_l.offset_left = 20
	hp_l.offset_top = -56
	hud2.add_child(hp_l)
	info_l = _lbl("", 26)
	info_l.set_anchors_preset(Control.PRESET_CENTER_TOP)
	info_l.offset_top = 90
	info_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hud2.add_child(info_l)


## Интерфейс в половинке экрана (промпт 20.11 14:53): мельче, чем на весь экран, чтобы HUD и окна
## помещались в узкую высокую половину. 2D рисуется в увеличенной логической области (size_2d_override)
## и ужимается в SubViewport; ползунок «Интерфейс в Split-Screen» (menu.gd: ui_scale_split) — поправка.
func _fit_ui() -> void:
	var menu = main.get("menu")
	var pct: float = float(menu.values.get("ui_scale_split", 100.0)) / 100.0 if menu and menu.get("values") != null else 1.0
	for sv in svs:
		var s := Vector2(sv.size)
		if s.x < 2.0 or s.y < 2.0:
			continue
		var k := clampf(minf(s.x / 1100.0, s.y / 620.0), 0.6, 1.0) * pct
		var want := Vector2i((s / maxf(k, 0.3)).round())
		if want == Vector2i(s):
			want = Vector2i.ZERO   # масштаб 1 — без подмены
		if sv.size_2d_override != want:
			sv.size_2d_override = want
			sv.size_2d_override_stretch = true


func _lbl(t: String, fs: int) -> Label:
	var l := Label.new()
	l.text = t
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", Color(0.95, 0.88, 0.78))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 6)
	return l


func _copy_cam(dst: Camera3D, src: Camera3D, hide_mask: int) -> void:
	dst.global_transform = src.global_transform
	dst.fov = src.fov
	dst.near = src.near
	dst.far = src.far
	dst.h_offset = src.h_offset
	dst.v_offset = src.v_offset
	dst.environment = src.environment
	dst.attributes = src.attributes
	dst.cull_mask = src.cull_mask & ~hide_mask


## Все слои интерфейса игры (HUD, инвентарь, окна…) — в левую половину. Меню, затемнения main и кат-сцены — на весь экран.
func _sweep_layers() -> void:
	for n in main.find_children("*", "CanvasLayer", true, false):
		if n.get_parent() == main or n.has_meta("split_moved") or _keep_full(n):
			continue
		n.set_meta("split_moved", true)
		n.set_meta("split_owner", n.get_parent())
		n.reparent(svs[0], false)
	# хозяин слоя удалён (машина, окно…) — удаляем и слой, раньше он ушёл бы вместе с хозяином
	for n in svs[0].get_children():
		if n.has_meta("split_owner") and not is_instance_valid(n.get_meta("split_owner")):
			n.queue_free()


func _keep_full(n: Node) -> bool:
	var a: Node = n
	while a and a != main:
		if a == self or a == main.get("menu"):
			return true
		var sc = a.get_script()
		if sc and (sc.resource_path.ends_with("intro.gd") or sc.resource_path.ends_with("cutscene_skip.gd")):
			return true
		a = a.get_parent()
	return false


## Голова игрока 1 (у себя только тень) — видимой для камеры игрока 2; голову игрока 2 прячем от его камеры.
func _heads() -> void:
	if head_paths.is_empty():
		for m in p1.find_children("*", "GeometryInstance3D", true, false):
			if (m as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
				head_paths.append(p1.get_path_to(m))
	for path in head_paths:
		var m = p1.get_node_or_null(path)
		if m and m.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			m.layers = HEAD1
		var m2 = pp.get_node_or_null(path) if pp else null
		if m2:
			m2.layers = HEAD2


# ---------- игрок 2 ----------

func _spawn_p2() -> void:
	var at: Vector3 = p1.global_position + p1.global_transform.basis.x * 1.0
	yaw = p1.rotation.y
	body = CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	body.add_child(cs)
	body.collision_layer = 0
	body.collision_mask = p1.collision_mask
	game.get_parent().add_child(body)
	body.global_position = at
	pp = PlayerScript.new()
	pp.puppet = true
	pp.name = "Player2"
	pp.position = at
	pp.rotation.y = yaw
	pp.net_pos = at
	pp.net_yaw = yaw
	game.get_parent().add_child(pp)
	pp.cam.current = false
	pp.collision_layer = PUPPET_LAYER
	pp.collision_mask = 0
	tgt = Target2.new()
	tgt.player = pp
	tgt.split = self


## enemy.gd / mutant.gd: ближайший живой игрок.
func pick_target(e) -> Object:
	var best: Object = game
	var bd := INF
	if game.alive:
		bd = e.global_position.distance_to(p1.global_position) - (1.5 if e.tg == game else 0.0)
	if alive and is_instance_valid(pp):
		var d: float = e.global_position.distance_to(pp.global_position) - (1.5 if e.tg == tgt else 0.0)
		if d < bd:
			best = tgt
	return best


func damage2(amount: float, _from: Vector3) -> void:
	if not alive:
		return
	hp -= amount
	flash.color.a = 0.45
	if hp <= 0.0:
		hp = 0.0
		alive = false
		tgt.alive = false
		dead_t = RESPAWN_T
		pp.visible = false
		pp.collision_layer = 0


func _respawn() -> void:
	hp = MAX_HP
	alive = true
	tgt.alive = true
	pp.visible = true
	pp.collision_layer = PUPPET_LAYER
	_to_p1()


## Поставить игрока 2 рядом с игроком 1 (после кат-сцены, машины, смерти, отставания).
func _to_p1() -> void:
	var at: Vector3 = p1.global_position - p1.global_transform.basis.z * -1.2 + p1.global_transform.basis.x * 0.8
	body.global_position = at
	body.velocity = Vector3.ZERO
	pp.global_position = at
	pp.net_pos = at
	yaw = p1.rotation.y
	pitch = 0.0


func _dev() -> int:
	return pad_device(true)


func _input(e: InputEvent) -> void:
	var dev := _dev()
	if dev < 0 or e.device != dev:
		return
	var spec := ""
	var pressed := false
	var menu = main.get("menu")
	var pad = menu.pad if menu else null
	if pad == null or pad.capturing:
		return
	if e is InputEventJoypadButton:
		if e.button_index == JOY_BUTTON_START:
			if e.pressed and pad.only_device != dev:
				pad._tap("ui_cancel", dev)   # пауза с геймпада игрока 2
			return
		spec = "b:%d" % e.button_index
		if Input.is_joy_button_pressed(dev, pad.MOD) and e.button_index != pad.MOD:
			spec = "c:%d" % e.button_index
		pressed = e.pressed
	elif e is InputEventJoypadMotion and (e.axis == JOY_AXIS_TRIGGER_LEFT or e.axis == JOY_AXIS_TRIGGER_RIGHT):
		var side := "L" if e.axis == JOY_AXIS_TRIGGER_LEFT else "R"
		var was: bool = get_meta("trig_" + side, false)
		var on: bool = e.axis_value > (0.3 if was else 0.5)
		if on == was:
			return
		set_meta("trig_" + side, on)
		spec = "t:" + side
		pressed = on
	else:
		return
	for a in pad.p2._actions(spec):   # у игрока 2 своя раскладка (gamepad.gd: p2)
		_act2(a, pressed)


func _act2(a: String, pressed: bool) -> void:
	if a == "crouch":
		crouch_hold = pressed
	if not pressed or not alive or mirrored or get_tree().paused:
		return
	match a:
		"jump":
			jump_q = true
		"crouch_toggle":
			crouch = not crouch
		"sprint":
			sprint_latch = true
			crouch = false
		"fists":
			pp.toggle_fists()
		"attack_left", "attack_right":
			var arm := 0 if a == "attack_left" else 1
			if not pp.fists:
				pp.toggle_fists()
			elif not pp.punching:
				pp.punch(arm)
				get_tree().create_timer(0.17).timeout.connect(_land_punch.bind(arm))


## Удар игрока 2: у puppet урон не считается (как в сети) — считаем здесь лучом из его головы.
func _land_punch(arm: int) -> void:
	if not is_instance_valid(pp) or not alive:
		return
	var reach := 1.0 * (1.0 + 0.75 * clampf(-pitch, 0.0, 1.0))
	var hit: Dictionary = pp._hit_scan(pp.cam.global_position, reach)
	if hit.is_empty() or hit.collider == pp or hit.collider == body:
		return
	if hit.collider.has_method("take_hit") and hit.collider != p1:
		hit.collider.take_hit(pp.PUNCH_BASE * pp.HAND_DMG[arm], -pp.cam.global_transform.basis.z)


func _stick(dev: int, x: JoyAxis, y: JoyAxis) -> Vector2:
	var v := Vector2(Input.get_joy_axis(dev, x), Input.get_joy_axis(dev, y))
	var l := v.length()
	if l < 0.18:
		return Vector2.ZERO
	var k := (minf(l, 1.0) - 0.18) / 0.82
	return v / l * k


func _physics_process(delta: float) -> void:
	if not is_instance_valid(pp) or not is_instance_valid(p1) or get_tree().paused:
		return
	var dev := _dev()
	var pad = main.menu.pad.p2 if main.get("menu") and main.menu.pad else null   # настройки игрока 2
	var swapped: bool = pad != null and pad.swapped()
	var mv := Vector2.ZERO
	var lk := Vector2.ZERO
	if dev >= 0 and alive and not mirrored:
		mv = _stick(dev, JOY_AXIS_RIGHT_X if swapped else JOY_AXIS_LEFT_X, JOY_AXIS_RIGHT_Y if swapped else JOY_AXIS_LEFT_Y)
		lk = _stick(dev, JOY_AXIS_LEFT_X if swapped else JOY_AXIS_RIGHT_X, JOY_AXIS_LEFT_Y if swapped else JOY_AXIS_RIGHT_Y)
	var sens: float = (pad.sens if pad else 1.0) * PlayerScript.look_sens
	if pad and pad.invert_y:
		lk.y = -lk.y
	lk = lk * lk.length()
	yaw -= lk.x * 3.3 * sens * delta
	pitch = clampf(pitch - lk.y * 2.4 * sens * delta, -1.5, 1.4)
	if mv.length() < 0.05:
		sprint_latch = false
	var crouched := crouch or crouch_hold
	var speed: float = PlayerScript.WALK * (0.5 if crouched else 1.0)
	if sprint_latch and not crouched and mv.y < -0.1:
		speed = PlayerScript.SPRINT
	var basis := Basis(Vector3.UP, yaw)
	var hv := basis * Vector3(mv.x, 0, mv.y) * speed
	body.velocity.x = hv.x
	body.velocity.z = hv.z
	if body.is_on_floor():
		if jump_q and not crouched:
			body.velocity.y = PlayerScript.JUMP
	else:
		body.velocity.y -= PlayerScript.GRAVITY * delta
	jump_q = false
	body.move_and_slide()
	# модель игрока 2 — как у сетевого игрока
	pp.net_pos = body.global_position
	pp.net_yaw = yaw
	pp.net_pitch = pitch
	pp.net_vel = body.velocity
	pp.net_sprint = Vector2(body.velocity.x, body.velocity.z).length() > PlayerScript.WALK + 0.4
	pp.net_crouch = crouched
	# отстал (упал, застрял) — к игроку 1
	if not mirrored and body.global_position.distance_to(p1.global_position) > 40.0:
		_to_p1()


func _process(delta: float) -> void:
	if not is_instance_valid(p1) or not is_instance_valid(pp):
		return
	sweep_t -= delta
	if sweep_t <= 0.0:
		sweep_t = 0.3
		_sweep_layers()
		_heads()
		_fit_ui()
	var root := get_tree().root
	var src := root.get_camera_3d()
	if src == null or not is_instance_valid(src):
		return
	_copy_cam(cams[0], src, HEAD1)
	# кат-сцена, машина и т.п. (камера не игрока 1) — у обоих одно и то же
	var was := mirrored
	mirrored = src != p1.cam
	if mirrored:
		_copy_cam(cams[1], src, HEAD1)
	else:
		if was and body.global_position.distance_to(p1.global_position) > 6.0:
			_to_p1()
		_copy_cam(cams[1], pp.cam, HEAD2)
	# HUD игрока 2
	flash.color.a = maxf(flash.color.a - delta * 1.5, 0.0)
	hp_l.text = "♥ %d" % int(ceil(hp))
	hp_l.visible = not mirrored
	if not alive:
		dead_t -= delta
		info_l.text = "Игрок 2 погиб. Возрождение через %d с" % int(ceil(dead_t))
		if dead_t <= 0.0:
			_respawn()
	elif _dev() < 0:
		info_l.text = "Подключите геймпад для игрока 2"
	else:
		info_l.text = ""
