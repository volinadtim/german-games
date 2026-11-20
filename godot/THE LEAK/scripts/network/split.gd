extends Node
## Split-Screen в одной игре (промпт 18.11 00:41, переделка 00:58): одно окно, экран пополам —
## слева игрок 1 (клавиатура+мышь; при двух геймпадах ещё и первый геймпад), справа игрок 2 (свой геймпад).
## Без второй копии игры и без лобби: обычная одиночная игра из слота, в которой появляется второй игрок.
## Игрок 2 — такой же player.gd, как игрок 1 (промпт 20.11 15:00: звуки, заряд ударов, бег, подкат…), только ввод
## у него не Input, а PadInput: этот узел пишет туда кнопки и стик его геймпада (player_base.gd: ia). Враги выбирают
## ближайшего живого (enemy.gd / mutant.gd → pick_target); кат-сцены и машина показываются в обеих половинах,
## после них игрок 2 встаёт рядом с игроком 1.
## Свой HUD у игрока 1 (все слои интерфейса игры переносятся в левую половину), у игрока 2 — такой же hud.gd
## (здоровье, прицел, миникарта; промпт 20.11 14:59). Миникарты меньше и ближе, хотбар игрока 1 — только в Tab.
## Кат-сцену видят оба (камера игрока 1 у обоих), пропуск — когда удержали оба (ui/cutscene_skip.gd).
## Инвентаря и предметов у игрока 2 пока нет: кулаки, бег, прыжок, присед.
## Создаёт main.gd (_enter_game), если в меню выбран «Split-Screen» (pending). Узел — ребёнок main.

const PlayerScript := preload("res://scripts/player/player.gd")
const HudScript := preload("res://scripts/hud.gd")
const MM_K := 0.8            # миникарта в половинке: на 20% меньше и на 20% ближе
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
var pp                       # player.gd игрока 2 (не puppet: сам ходит, бьёт, звучит)
var pi: PadInput             # его ввод
var svs: Array = []          # [левый, правый] SubViewport
var cams: Array = []
var screens: CanvasLayer
var hud2: Control
var hud_p2                   # hud.gd игрока 2 — тот же интерфейс, что у игрока 1
var info_l: Label
var tgt: Target2

var hp := MAX_HP
var alive := true
var dead_t := 0.0
var can_was := false
var mirrored := true
var sweep_t := 0.0
var head_paths: Array = []
var head_paths2: Array = []
var posts: Array = []        # [левая, правая] постобработка (линза, виньетка, размытие ударов) — у каждого своя
var main_post: CanvasItem    # общая постобработка main.gd — в Split-Screen спрятана
const POST_SHARED := ["levels", "brightness", "gamma", "distort", "aberration", "vignette"]   # настройки меню — общие
var jump_down := false       # игрок 2 держит прыжок — голос за пропуск кат-сцены


## Ввод игрока 2 для player.gd вместо Input: те же методы (is_action_pressed, is_action_just_pressed, get_vector),
## состояние пишет split.gd с геймпада игрока 2. «Только что нажато» — отдельно для физического и обычного кадра.
class PadInput:
	var held := {}
	var pend := {}             # действие|p или |f → время нажатия, мс (ещё не прочитано в этом контексте)
	var seen := {}             # действие|контекст → номер кадра, в котором нажатие прочитано
	var move := Vector2.ZERO   # левый стик (ходьба)
	var sprint_latch := false  # бег: нажал — бежит, пока не отпустит стик (как раньше у игрока 2)

	func press(a: String, on: bool) -> void:
		if on and not held.get(a, false):
			var t := Time.get_ticks_msec()
			pend[a + "|p"] = t
			pend[a + "|f"] = t
			if a == "sprint":
				sprint_latch = true
		held[a] = on

	func release_all() -> void:
		held.clear()
		pend.clear()
		sprint_latch = false
		move = Vector2.ZERO

	func is_action_pressed(a: StringName, _exact := false) -> bool:
		if a == &"sprint" and sprint_latch:
			return true
		return held.get(String(a), false)

	func is_action_just_pressed(a: StringName, _exact := false) -> bool:
		var phys := Engine.is_in_physics_frame()
		var key := String(a) + ("|p" if phys else "|f")
		var fr: int = Engine.get_physics_frames() if phys else Engine.get_process_frames()
		if pend.has(key):
			if Time.get_ticks_msec() - int(pend[key]) < 300:
				seen[key] = fr
			pend.erase(key)
		return seen.get(key, -1) == fr

	func get_vector(neg_x: StringName, _px: StringName, _ny: StringName, _py: StringName, _dz := -1.0) -> Vector2:
		return move if neg_x == &"move_left" else Vector2.ZERO   # обзор крутит split.gd сам


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
	if is_instance_valid(main_post):
		main_post.visible = true
	if is_instance_valid(p1) and is_instance_valid(main):
		p1.post_mat = main.get("post_mat")
	if inst == self:
		inst = null
	get_tree().root.disable_3d = false
	if is_instance_valid(game):
		game.remove_meta("split")
		var g1 = game.get("hud")
		if g1:
			g1.hot_tab_only = false
			g1.mm_size = 180.0
			g1.mm_range = 50.0
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
	row.add_theme_constant_override("separation", 0)
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
	_build_posts()
	# интерфейс игрока 2: тот же hud.gd, что у игрока 1, плюс строка «погиб / подключите геймпад»
	hud_p2 = HudScript.new()
	hud_p2.no_gun = true
	svs[1].add_child(hud_p2)
	hud_p2.set_hp(hp, MAX_HP, true)
	var g1 = game.get("hud")
	for h in [g1, hud_p2]:
		if h:
			h.mm_size = 180.0 * MM_K
			h.mm_range = 50.0 * MM_K
	if g1:
		g1.hot_tab_only = true
	var l2 := CanvasLayer.new()
	l2.layer = 5
	svs[1].add_child(l2)
	hud2 = Control.new()
	hud2.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l2.add_child(hud2)
	info_l = _lbl("", 26)
	info_l.set_anchors_preset(Control.PRESET_CENTER_TOP)
	info_l.offset_top = 90
	info_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hud2.add_child(info_l)


## Эффект линзы у каждого свой (промпт 20.11 15:06): общая постобработка main.gd прячется, в каждой половине —
## своя копия (CanvasLayer -1 под HUD), центр линзы и виньетка — по своей половине, размытие удара и отравление —
## от своего игрока (player.post_mat). Настройки изображения из меню копируются с общей (_sync_posts).
func _build_posts() -> void:
	var mp: ShaderMaterial = main.get("post_mat")
	if mp == null:
		return
	for c in main.get_children():
		if c is CanvasLayer:
			for r in c.get_children():
				if r is ColorRect and r.material == mp:
					main_post = r
	if main_post:
		main_post.visible = false
	for i in 2:
		var l := CanvasLayer.new()
		l.layer = -1
		svs[i].add_child(l)
		var r := ColorRect.new()
		r.set_anchors_preset(Control.PRESET_FULL_RECT)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.material = mp.duplicate()
		l.add_child(r)
		posts.append(r.material)
	p1.post_mat = posts[0]
	_sync_posts()


func _sync_posts() -> void:
	var mp: ShaderMaterial = main.get("post_mat")
	if mp == null or posts.is_empty():
		return
	for m in posts:
		for k in POST_SHARED:
			var v = mp.get_shader_parameter(k)
			if v != null:
				m.set_shader_parameter(k, v)
	if is_instance_valid(pp) and pp.post_mat != posts[1]:
		pp.post_mat = posts[1]
	if is_instance_valid(p1) and p1.post_mat != posts[0]:
		p1.post_mat = posts[0]


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


## Все слои интерфейса игры (HUD, инвентарь, окна…) — в левую половину, слои игрока 2 — в правую. Меню, затемнения main и кат-сцены — на весь экран.
func _sweep_layers() -> void:
	for n in main.find_children("*", "CanvasLayer", true, false):
		if n.get_parent() == main or n.has_meta("split_moved") or _keep_full(n):
			continue
		n.set_meta("split_moved", true)
		n.set_meta("split_owner", n.get_parent())
		# слои игрока 2 (заряд удара, выносливость) — в его половину
		n.reparent(svs[1] if is_instance_valid(pp) and pp.is_ancestor_of(n) else svs[0], false)
	# хозяин слоя удалён (машина, окно…) — удаляем и слой, раньше он ушёл бы вместе с хозяином
	for sv in svs:
		for n in sv.get_children():
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


## Голова каждого игрока (у себя только тень) — видимой для камеры другого: игрок 1 на слое HEAD1, игрок 2 — HEAD2.
func _heads() -> void:
	_head_of(p1, HEAD1, head_paths)
	if is_instance_valid(pp):
		_head_of(pp, HEAD2, head_paths2)


func _head_of(pl: Node, layer: int, paths: Array) -> void:
	if paths.is_empty():
		for m in pl.find_children("*", "GeometryInstance3D", true, false):
			if (m as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
				paths.append(pl.get_path_to(m))
	for path in paths:
		var m = pl.get_node_or_null(path)
		if m and m.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			m.layers = layer


# ---------- игрок 2 ----------

func _spawn_p2() -> void:
	var at: Vector3 = p1.global_position + p1.global_transform.basis.x * 1.0
	pi = PadInput.new()
	pp = PlayerScript.new()
	pp.ia = pi
	pp.name = "Player2"
	pp.position = at
	pp.rotation.y = p1.rotation.y
	game.get_parent().add_child(pp)
	pp.cam.current = false
	pp.collision_layer = PUPPET_LAYER
	pp.collision_mask = p1.collision_mask
	pp.active = true
	hud_p2.mm_player = pp
	pp.add_to_group("allies")
	p1.add_to_group("allies")
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
	if hp <= 0.0:
		hp = 0.0
	hud_p2.set_hp(hp, MAX_HP)
	var k := clampf(amount / 25.0, 0.3, 1.0)   # как hud.hurt_flash, но вибрирует геймпад игрока 2
	hud_p2.hurt = maxf(hud_p2.hurt, k)
	hud_p2.hit_edge = maxf(hud_p2.hit_edge, clampf(k * 1.2, 0.5, 1.0))
	var pad = main.menu.pad if main.get("menu") else null
	if _dev() >= 0 and pad and bool(pad.get("vibration")):
		Input.start_joy_vibration(_dev(), k * 0.6, k, 0.12 + k * 0.25)
	if hp <= 0.0:
		alive = false
		tgt.alive = false
		dead_t = RESPAWN_T
		pp.visible = false
		pp.collision_layer = 0
		pp.charging = -1


func _respawn() -> void:
	hp = MAX_HP
	hud_p2.set_hp(hp, MAX_HP, true)
	alive = true
	tgt.alive = true
	pp.visible = true
	pp.collision_layer = PUPPET_LAYER
	_to_p1()


## Поставить игрока 2 рядом с игроком 1 (после кат-сцены, машины, смерти, отставания).
func _to_p1() -> void:
	var at: Vector3 = p1.global_position - p1.global_transform.basis.z * -1.2 + p1.global_transform.basis.x * 0.8
	pp.global_position = at
	pp.velocity = Vector3.ZERO
	pp.rotation.y = p1.rotation.y
	pp.head.rotation.x = 0.0


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
			if e.pressed and pad.only_device != dev and pad.ui_owner != dev:
				var in_game := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
				pad._tap("ui_cancel", dev)   # пауза с геймпада игрока 2
				if in_game:
					pad.set_deferred("ui_owner", dev)   # открыл паузу — меню водит его геймпад (после этого события)
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


## Кнопка игрока 2 → его player.gd: как _unhandled_input игрока 1 (стойка, заряд удара), остальное — через PadInput.
func _act2(a: String, pressed: bool) -> void:
	if a == "jump":
		jump_down = pressed
	if not is_instance_valid(pp):
		return
	if not pressed:
		pi.press(a, false)
		if a == "attack_left" or a == "attack_right":
			pp.charge_release(0 if a == "attack_left" else 1)
		return
	if not alive or mirrored or get_tree().paused:
		return
	pi.press(a, true)
	match a:
		"fists":
			if not pp.carrying:
				pp.charging = -1
				pp.toggle_fists()
		"attack_left", "attack_right":
			if not pp.carrying:
				pp.charge_begin(0 if a == "attack_left" else 1)


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
	var can := dev >= 0 and alive and not mirrored
	pp.set_lock("split", not can)
	if can != can_was:
		can_was = can
		pi.release_all()
		pp.charging = -1
	if not can:
		return
	var swapped: bool = pad != null and pad.swapped()
	var mv := _stick(dev, JOY_AXIS_RIGHT_X if swapped else JOY_AXIS_LEFT_X, JOY_AXIS_RIGHT_Y if swapped else JOY_AXIS_LEFT_Y)
	var lk := _stick(dev, JOY_AXIS_LEFT_X if swapped else JOY_AXIS_RIGHT_X, JOY_AXIS_LEFT_Y if swapped else JOY_AXIS_RIGHT_Y)
	pi.move = mv
	if mv.length() < 0.05:
		pi.sprint_latch = false
	var sens: float = (pad.sens if pad else 1.0) * PlayerScript.look_sens
	if pad and pad.invert_y:
		lk.y = -lk.y
	lk = lk * lk.length()
	pp.rotate_y(-lk.x * 3.3 * sens * delta)
	pp.head.rotation.x = clampf(pp.head.rotation.x - lk.y * 2.4 * sens * delta, -1.5, 1.4)
	# отстал (упал, застрял) — к игроку 1
	if pp.global_position.distance_to(p1.global_position) > 40.0:
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
		_sync_posts()
	var root := get_tree().root
	var src := root.get_camera_3d()
	if src == null or not is_instance_valid(src):
		return
	_copy_cam(cams[0], src, HEAD1)
	# кат-сцена, машина и т.п. (камера не игрока 1) — у обоих одно и то же
	var was := mirrored
	# кат-сцена на камере игрока 1 (пробуждение, монстрик, магазин) — тоже у обоих
	mirrored = src != p1.cam or _in_cut()
	if mirrored:
		_copy_cam(cams[1], src, HEAD1)
	else:
		if was and pp.global_position.distance_to(p1.global_position) > 6.0:
			_to_p1()
		_copy_cam(cams[1], pp.cam, HEAD2)
	# HUD игрока 2 — как у игрока 1
	var g1 = game.get("hud")
	if g1:
		hud_p2.coins = g1.coins
		hud_p2.minimal = g1.minimal
	if mirrored != was:
		hud_p2.set_cinematic(mirrored)
	if not alive:
		dead_t -= delta
		info_l.text = "Игрок 2 погиб. Возрождение через %d с" % int(ceil(dead_t))
		if dead_t <= 0.0:
			_respawn()
	elif _dev() < 0:
		info_l.text = "Подключите геймпад для игрока 2"
	else:
		info_l.text = ""


## Идёт кат-сцена, которую можно пропустить (группа "cutscene", ui/cutscene_skip.gd).
func _in_cut() -> bool:
	for n in get_tree().get_nodes_in_group("cutscene"):
		if is_instance_valid(n) and n.is_inside_tree() and n.can_skip():
			return true
	return false


## ui/cutscene_skip.gd: игрок 2 держит пропуск (прыжок на своём геймпаде). -1 — геймпада нет, голос не нужен.
func skip_state() -> int:
	if _dev() < 0:
		return -1
	return 1 if jump_down else 0
