extends Node
## Пистолет (промпт 14.11 19:49): старый обшарпанный, лежит в сейфе вместе с магазином и патронами.
## В правой руке (промпт 22:53, режимы — 16.11 00:22): просто так не стреляет. ПКМ держать — от бедра (ЛКМ стреляет,
## пока держишь, разброс больше); ПКМ клик — прицел по мушке (переключатель: пистолет к глазу, зум, точнее), в нём ЛКМ стреляет.
## Шаги качают ствол: прицел на экране и точка попадания смещаются (sway). Прицел рисуем сами (hud.gd: gun_cross).
## Хитскан из камеры. Два пистолета (обе руки) — стреляют по очереди, свой магазин у каждого.
## Без ПКМ ЛКМ — удар рукоятью (player_combat.gd). Позы рук — player_anim.gd: _gun_pose.
## Магазин — отдельная вещь: вставленный пропадает из инвентаря. R — вставить самый полный магазин из сумки
## (старый — в сумку); перетащить магазин на пистолет — то же; патроны на магазин — дозарядить его;
## зажать Enter (действие «mag_eject») — извлечь магазин в сумку.
## dur пистолета: 0 — магазина нет, 1 + n — вставлен магазин с n патронами (так dur всегда >= 0 и не теряется
## при выбрасывании/сундуках/сейве). dur магазина — просто патроны в нём (0..CAP).
## Выстрел слышат враги вокруг и бегут на звук. Счётчик «в магазине / в сумке» — справа от хотбара.

const Items := preload("res://scripts/items.gd")
const Fx := preload("res://scripts/core/fx.gd")
const Hud := preload("res://scripts/hud.gd")
const Weapons := preload("res://scripts/weapons.gd")
const CAP := 8                   # патронов в магазине
const DMG := 40.0                # по бетоннику (95 HP) — 3 попадания
const RANGE := 80.0
const HEAD_MULT := 2.5           # хэдшот (промпт 18.11 00:56)
# урон падает с дистанцией (промпт 18.11 01:16): до FULL_D — полный, дальше линейно до FAR_MULT на FAR_D и дальше
const DMG_FULL_D := 10.0
const DMG_FAR_D := 45.0
const DMG_FAR_MULT := 0.35
const FIRE_CD := 0.28
const RELOAD_T := 1.7             # фазы анимации — player_anim.gd: _reload_pose, звуки — REL_EVENTS
const HEAR_R := 28.0             # радиус, в котором враги слышат выстрел
const EJECT_T := 0.5             # столько держать Enter — извлечь магазин
const AIM_FOV := 0.7             # множитель поля зрения в прицеле
const SPREAD_HIP := 0.03         # разброс от бедра, рад
const SPREAD_AIM := 0.004
const SPREAD_STANCE := 0.02      # в боевой стойке — примерно в центр экрана (промпт 05:34)
const TAP_T := 0.22              # ПКМ короче — клик (переключить прицел), дольше — держать (от бедра)
const RATE := 22050

var game
var cd := 0.0
var hand_cd := [0.0, 0.0]        # задержка выстрела по рукам в стойке (stance_fire)
var reloading := false
var voice: AudioStreamPlayer
var snd_shot: AudioStreamWAV
var snd_click: AudioStreamWAV
var snd_headshot: AudioStreamWAV
var snd_mag: AudioStreamWAV
var ui: CanvasLayer
var count_l: Label
var _empty_told := false
var aiming := false
var aim_k := 0.0                 # 0..1 — насколько пистолет поднят к глазу
var eject_t := 0.0
var _eject_lock := false         # Enter держат после извлечения — ждём отпускания
var rmb := false                 # ПКМ нажата (player_combat.gd: charge_begin/charge_release, и мышь, и тач)
var rmb_t := 0.0
var ads := false                 # прицел по мушке (клик ПКМ)
var hip := false                 # от бедра (ПКМ держат)
var sway := Vector2.ZERO         # качание ствола от шагов и дыхания: (рысканье, тангаж), рад
var sway_t := 0.0
var cross: Control
var _ready_told := false
## Инерция оружия в прицеле (промпт 02:49): поворот пистолета и рук догоняет камеру с лагом.
## Камера и попадание (по центру) — без задержки. lag_b — поворот «лаг относительно камеры» в мировых осях.
const LAG_SPEED := 14.0
const LAG_MAX := 0.1             # рад — дальше оружие не отстаёт
var lag_q := Quaternion.IDENTITY
var lag_b := Basis.IDENTITY
var _lag_init := false
## Два пистолета (промпт 16.11 02:04): управление то же, стреляют по очереди, у каждого свой магазин.
## Рука h: 0 — левая, 1 — правая (как player.weapon_nodes).
const SLOTS := ["left", "right"]
var next_hand := 1
var _hand := 1                   # из какого стреляли последним (вспышка, гильза)
var _reload_h := 1               # какой перезаряжается
## Перезарядка (промпт 16.11 02:37): фаза 0..1 → player.gun_rel_k; звуки по фазе: защёлка и выход магазина,
## вставка, затвор назад, затвор вперёд. Магазин в руке — отдельный меш, старый магазин падает на пол.
const REL_EVENTS := [[0.02, "release"], [0.55, "insert"], [0.79, "rack_back"], [0.87, "rack_fwd"]]
var _rel_t := 0.0
var _rel_had := false
var _rel_ev := 0
var _rel_mag: MeshInstance3D
var snd_release: AudioStreamWAV
var snd_insert: AudioStreamWAV
var snd_rack_back: AudioStreamWAV
var snd_rack_fwd: AudioStreamWAV


## dur пистолета → патроны / есть ли магазин (см. шапку).
static func has_mag(d: float) -> bool:
	return d >= 0.5


static func mag_rounds(d: float) -> int:
	return maxi(int(round(d)) - 1, 0)


static func pistol_dur(has: bool, n: int) -> float:
	return float(n + 1) if has else 0.0


func _ready() -> void:
	voice = AudioStreamPlayer.new()
	add_child(voice)
	snd_shot = _shot_sound()
	snd_click = _click_sound(0.035, 2600.0)
	snd_headshot = _layered([[0.0, "tick", 0.03, 3200.0, 0.9], [0.004, "ring", 0.22, 1700.0, 0.45], [0.0, "thump", 0.09, 150.0, 0.9]])
	snd_mag = _click_sound(0.06, 900.0)
	snd_release = _layered([[0.0, "tick", 0.02, 3400.0, 0.7], [0.004, "ring", 0.12, 4100.0, 0.25],
			[0.03, "scrape", 0.09, 2200.0, 0.55], [0.11, "thump", 0.08, 260.0, 0.35]])
	snd_insert = _layered([[0.0, "scrape", 0.07, 1800.0, 0.5], [0.07, "thump", 0.09, 170.0, 1.0],
			[0.07, "tick", 0.025, 2300.0, 0.9], [0.072, "ring", 0.1, 3300.0, 0.3], [0.1, "tick", 0.012, 4200.0, 0.45]])
	snd_rack_back = _layered([[0.0, "tick", 0.015, 2900.0, 0.6], [0.005, "scrape", 0.08, 3000.0, 0.65],
			[0.08, "tick", 0.02, 2000.0, 0.7], [0.082, "ring", 0.08, 5200.0, 0.2]])
	snd_rack_fwd = _layered([[0.0, "scrape", 0.025, 3500.0, 0.4], [0.025, "tick", 0.03, 2600.0, 1.0],
			[0.025, "thump", 0.07, 210.0, 0.8], [0.027, "ring", 0.22, 3700.0, 0.35], [0.027, "ring", 0.16, 6100.0, 0.18]])
	ui = CanvasLayer.new()
	ui.layer = 1
	add_child(ui)
	count_l = Label.new()
	count_l.anchor_left = 0.5
	count_l.anchor_right = 0.5
	count_l.anchor_top = 1.0
	count_l.anchor_bottom = 1.0
	count_l.offset_left = 196
	count_l.offset_right = 400
	count_l.offset_top = -70
	count_l.offset_bottom = -30
	count_l.add_theme_font_size_override("font_size", 26)
	count_l.add_theme_color_override("font_color", Color(0.95, 0.88, 0.7))
	count_l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	count_l.add_theme_constant_override("outline_size", 6)
	count_l.visible = false
	ui.add_child(count_l)
	cross = Control.new()
	cross.set_anchors_preset(Control.PRESET_FULL_RECT)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cross.draw.connect(_draw_cross)
	ui.add_child(cross)


func armed() -> bool:
	return game != null and (game.inv.equip["right"] == "pistol" or game.inv.equip["left"] == "pistol")


## Руки с пистолетом (правая первой).
func hands() -> Array[int]:
	var r: Array[int] = []
	if game == null:
		return r
	for h in [1, 0]:
		if game.inv.equip[SLOTS[h]] == "pistol":
			r.append(h)
	return r


func dual() -> bool:
	return hands().size() == 2


func rounds_in(h: int) -> int:
	return mag_rounds(game.inv.get_dur(SLOTS[h])) if game.inv.equip[SLOTS[h]] == "pistol" else 0


func loaded_in(h: int) -> bool:
	return game.inv.equip[SLOTS[h]] == "pistol" and has_mag(game.inv.get_dur(SLOTS[h]))


func rounds() -> int:
	var n := 0
	for h in hands():
		n += rounds_in(h)
	return n


func loaded() -> bool:
	for h in hands():
		if loaded_in(h):
			return true
	return false


## Где пистолет в режиме прицела (eye/cb — камера): руки вытянуты вперёд (промпт 02:49); один — мушка
## (верх затвора — ~0.13 над рукоятью, weapons.gd) ровно на линии взгляда по центру; два — пистолеты по бокам.
static func ads_point(eye: Vector3, cb: Basis, h: int, two: bool, scy := 1.0) -> Vector3:
	if two:
		var side := -1.0 if h == 0 else 1.0
		return eye - cb.z * 0.64 - cb.y * 0.15 + cb.x * side * 0.1
	return eye - cb.z * 0.6 - cb.y * 0.132 * scy


func fov_mult() -> float:
	return lerpf(1.0, AIM_FOV, aim_k)


func _process(delta: float) -> void:
	cd -= delta
	hand_cd[0] -= delta
	hand_cd[1] -= delta
	if game == null:
		return
	var p = game.player
	var can: bool = armed() and game.alive and p != null and (p.active or car_can()) and not game.inv.open \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not p.fists   # в стойке не целимся: клик — stance_fire (05:34)
	if not can:
		ads = false
		hip = false
		rmb = false
	elif rmb:
		rmb_t += delta
		hip = rmb_t >= TAP_T and not ads
	aiming = can and not reloading and ads
	aim_k = move_toward(aim_k, 1.0 if aiming else 0.0, delta * 6.0)
	if p != null:
		p.gun_mode = (2 if ads else (1 if hip else 0)) if can else 0   # поза рук (player_anim.gd: _gun_pose), уходит в сеть
	_update_sway(delta)
	_update_lag(delta)
	# зажать Enter — извлечь магазин (с двумя — сначала из правого)
	var ej: bool = InputMap.has_action("mag_eject") and Input.is_action_pressed("mag_eject")
	if can and loaded() and not reloading and ej and not _eject_lock:
		eject_t += delta
		if eject_t >= EJECT_T:
			eject_t = 0.0
			_eject_lock = true
			eject(SLOTS[1] if loaded_in(1) else SLOTS[0])
	else:
		eject_t = 0.0
		if not ej:
			_eject_lock = false
	count_l.visible = armed() and game.alive and game.mode != game.MODE_REAL   # реализм — без счётчика патронов
	if count_l.visible:
		var r := rounds()
		if not loaded():
			count_l.text = "НЕТ МАГАЗИНА  (R)"
		elif eject_t > 0.0:
			count_l.text = "ИЗВЛЕЧЬ… %d%%" % int(eject_t / EJECT_T * 100.0)
		elif dual():
			var pr := func(h: int) -> String: return str(rounds_in(h)) if loaded_in(h) else "—"
			count_l.text = "%s  Л %s · П %s" % ["ПЕРЕЗАРЯДКА" if reloading else "ПАТРОНЫ", pr.call(0), pr.call(1)]
		else:
			count_l.text = "%s  %d / %d" % ["ПЕРЕЗАРЯДКА" if reloading else "ПАТРОНЫ", r, CAP]
		count_l.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35) if r == 0 else Color(0.95, 0.88, 0.7))
	_reload_tick(delta)
	_aim()
	_car_view(delta)
	Hud.gun_cross = armed() and game.alive
	cross.queue_redraw()


## ПКМ нажата/отпущена (из player_combat.gd). Короткий клик — переключить прицел, долгое удержание — от бедра.
func rmb_input(down: bool) -> void:
	if down:
		rmb = true
		rmb_t = 0.0
		return
	if not rmb:
		return
	rmb = false
	if rmb_t < TAP_T and armed() and not reloading:
		ads = not ads
	hip = false


## Готов к стрельбе: прицел по мушке или ПКМ держат (от бедра).
func ready_to_fire() -> bool:
	return ads or hip


## Качание ствола: на ходу — восьмёркой в такт шагам (сильнее от бедра), стоя — лёгкое дыхание.
func _update_sway(delta: float) -> void:
	var p = game.player
	if p == null:
		return
	sway_t += delta
	var walk: float = clampf(p.bob, 0.0, 1.5)
	var g: float = p.gait * TAU
	var k: float = lerpf(1.0, 0.4, aim_k) * (1.0 - 0.45 * p.crouch)
	var want: Vector2 = Vector2(sin(g) * 0.022, (0.5 - absf(cos(g))) * 0.03) * walk * k
	want += Vector2(sin(sway_t * 0.7) * 0.0025, sin(sway_t * 1.13 + 0.6) * 0.003) * k
	sway = sway.lerp(want, 1.0 - exp(-14.0 * delta))


## Оружие догоняет поворот камеры: сглаженный поворот, отставание не больше LAG_MAX; в силе — по aim_k.
func _update_lag(delta: float) -> void:
	var p = game.player
	if p == null or p.cam == null:
		return
	var cq := Quaternion(p.cam.global_transform.basis.orthonormalized())
	if not _lag_init:
		_lag_init = true
		lag_q = cq
	lag_q = lag_q.slerp(cq, 1.0 - exp(-LAG_SPEED * delta)).normalized()
	var ang := lag_q.angle_to(cq)
	if ang > LAG_MAX:
		lag_q = cq.slerp(lag_q, LAG_MAX / ang).normalized()
	lag_b = Basis(Quaternion.IDENTITY.slerp((lag_q * cq.inverse()).normalized(), aim_k))


## Куда смотрит ствол (камера + качание).
func aim_dir() -> Vector3:
	var cb: Basis = game.player.cam.global_transform.basis.orthonormalized()
	return (-cb.z).rotated(cb.y, -sway.x).rotated(cb.x, sway.y).normalized()


## Прицел: от бедра — крестик с зазором по разбросу, в прицеле — ничего (целимся мушкой),
## опущен — тусклое кольцо. Центр — туда, куда смотрит ствол (с качанием).
func _draw_cross() -> void:
	if not armed() or not game.alive or game.player == null or game.inv.open:
		return
	if not Hud.show_crosshair:
		return   # «Настройки» → «Прицел» выключен — прицела пистолета тоже нет (промпт 02:37)
	var cam: Camera3D = game.player.cam
	var c: Vector2 = cross.size / 2.0
	var pt := cam.global_position + aim_dir() * 20.0
	if not cam.is_position_behind(pt):
		c = cam.unproject_position(pt) * cross.size / Vector2(cross.get_viewport_rect().size)
	if aim_k > 0.6:
		if dual():
			cross.draw_circle(c, 2.0, Color(0, 0, 0, 0.5))   # с двумя мушки не видно — точка
			cross.draw_circle(c, 1.3, Color(1, 1, 1, 0.85))
		return
	var col := Color(1, 1, 1, 0.8)
	var sh := Color(0, 0, 0, 0.5)
	if hip and not reloading:
		var px := tan(SPREAD_HIP * 1.4) / tan(deg_to_rad(cam.fov) * 0.5) * cross.size.y * 0.5
		var gap := maxf(px, 6.0)
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			cross.draw_line(c + d * gap, c + d * (gap + 9.0), sh, 4.0)
			cross.draw_line(c + d * gap, c + d * (gap + 9.0), col, 2.0)
		cross.draw_circle(c, 1.5, col)
	else:
		cross.draw_arc(c, 7.0, 0.0, TAU, 20, Color(1, 1, 1, 0.3), 1.5)


## Пистолет в кулаке смотрит стволом туда же, куда камера (хват из костей кисти рассчитан на биту/нож).
## Положение — от руки, поворот — от камеры, с лёгким наклоном; во время перезарядки — её анимация.
## Пистолет опущен (без ПКМ) — обычный хват (им же бьют рукоятью); поднят — плавно доворачивается к камере (вес позы рук).
func _aim() -> void:
	if not armed():
		return
	var p = game.player
	var w: float = maxf(clampf(p.gun_hip_w + p.gun_ads_w, 0.0, 1.0), aim_k)
	if w <= 0.0 and p.gun_rel_w <= 0.0:
		return
	var cb: Basis = lag_b * p.cam.global_transform.basis.orthonormalized()   # с инерцией в прицеле
	for h in hands():
		var n = p.weapon_nodes[h]
		if n == null or not is_instance_valid(n) or not (n as Node3D).is_inside_tree():
			continue
		var sc: Vector3 = (n as Node3D).global_transform.basis.get_scale()
		var tilt := 1.0 - aim_k
		var side := -1.0 if h == 0 else 1.0
		var b := Basis(-cb.z, cb.y, cb.x).rotated(cb.x, -0.06 * tilt).rotated(cb.y, 0.05 * tilt * side)   # +X модели — вперёд, +Y — вверх
		b = b.rotated(cb.y, -sway.x).rotated(cb.x, sway.y)   # ствол качается с шагами — туда же уходит пуля
		var gt: Transform3D = (n as Node3D).global_transform
		var wh := w
		if h == _reload_h and p.gun_rel_w > 0.0:
			# перезарядка: рукоять наклонена шахтой магазина ко второй руке, ствол чуть вверх
			var rb := Basis(-cb.z, cb.y, cb.x).rotated(cb.z, -side * 0.6).rotated(cb.x, 0.3)
			var rw := smoothstep(0.0, 1.0, p.gun_rel_w)
			b = b.slerp(rb, rw) if w > 0.0 else rb
			wh = maxf(w, rw)
		b = gt.basis.orthonormalized().slerp(b, wh)
		gt.basis = Basis(b.x * sc.x, b.y * sc.y, b.z * sc.z)
		# положение не трогаем: пистолет висит на кисти (рукоять в кулаке), к точке прицела его ведёт IK руки (player_anim.gd)
		(n as Node3D).global_transform = gt


func _unhandled_input(e: InputEvent) -> void:
	if game == null or game.player == null:
		return
	if e.is_action_pressed("reload") and not e.is_echo() and armed() and (game.player.active or car_can()) and game.alive:
		reload()
	# в машине игрок выключен (car_drive.gd) — ЛКМ/ПКМ ловим сами: стрельба из окна
	if car_seat() < 0 or not armed() or not game.alive or game.window_open() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if e.is_action_released("attack_right"):
		rmb_input(false)
	elif not car_can():
		return
	elif e.is_action_pressed("attack_right") and not e.is_echo():
		rmb_input(true)
	elif e.is_action_pressed("attack_left") and not e.is_echo():
		fire()
	else:
		return
	get_viewport().set_input_as_handled()


# ---------- стрельба из машины (промпт 18.11 00:49) ----------

var car_vm: Array = [null, null]   # пистолеты у камеры, пока сидишь в машине (тело в салоне спрятано)


## Место своего игрока в машине (сидит, не садится/выходит), -1 — не в машине.
func car_seat() -> int:
	var c = game.get("car") if game != null else null
	if c == null or not is_instance_valid(c) or int(c.my_seat) < 0 or int(c.seat_dir) != 0:
		return -1
	return int(c.my_seat)


## Водитель рулит: газ/тормоз/руль/ручник нажаты.
static func steering() -> bool:
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back").length() > 0.2 \
			or Input.is_action_pressed("handbrake" if InputMap.has_action("handbrake") else "jump")


## Можно стрелять из машины: пассажир — всегда, водитель — пока не рулит (стоит или катится сам).
func car_can() -> bool:
	var s := car_seat()
	return s > 0 or (s == 0 and not steering())


## Пистолет у камеры в салоне: от бедра — внизу сбоку, в прицеле — мушкой к глазу, водитель рулит — опущен.
func _car_view(delta: float) -> void:
	var p = game.player
	var on: bool = p != null and armed() and game.alive and car_seat() >= 0 and not game.inv.open
	var hs := hands()
	for h in 2:
		var n = car_vm[h]
		if not on or not h in hs:
			if n != null and is_instance_valid(n):
				n.visible = false
			continue
		var side := -1.0 if h == 0 else 1.0
		if n == null or not is_instance_valid(n):
			n = Weapons.make("pistol")
			for mi in n.find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			p.cam.add_child(n)
			car_vm[h] = n
			n.position = Vector3(0.24 * side, -0.48, -0.3)
		n.visible = true
		var two := hs.size() == 2
		var want := Vector3(0.2 * side, -0.27, -0.4).lerp(Vector3(0.07 * side if two else 0.0, -0.145, -0.32), aim_k)
		if not car_can():
			want = Vector3(0.24 * side, -0.48, -0.3)
		if reloading and h == _reload_h:
			want += Vector3(-0.06 * side, -0.12, 0.06) * sin(clampf(_rel_t / RELOAD_T, 0.0, 1.0) * PI)
		n.position = n.position.lerp(want, 1.0 - exp(-12.0 * delta))
		# +X модели — вперёд (к -Z камеры), +Y — вверх; качание — как у пули (aim_dir)
		n.basis = Basis(Vector3(0, 0, -1), Vector3.UP, Vector3(1, 0, 0)) \
				.rotated(Vector3.UP, -sway.x).rotated(Vector3.RIGHT, sway.y + 0.05 * (1.0 - aim_k))


# ---------- выстрел ----------

func fire() -> void:
	if not armed() or reloading or cd > 0.0 or not game.alive:
		return
	if not ready_to_fire():
		if not _ready_told:
			_ready_told = true
			game.hud.toast("Стрелять: ПКМ держать — от бедра, ПКМ клик — прицел", Color(0.9, 0.85, 0.7))
		return
	cd = FIRE_CD
	# два пистолета — по очереди (пустой пропускаем)
	var hs := hands()
	var h: int = hs[0]
	if hs.size() == 2:
		cd = FIRE_CD * 0.6
		h = next_hand
		if rounds_in(h) <= 0 and rounds_in(1 - h) > 0:
			h = 1 - h
		next_hand = 1 - h
	var r := rounds_in(h)
	if r <= 0:
		_play(snd_click, -6.0, 1.0)
		if not _empty_told:
			_empty_told = true
			game.hud.toast("Нет магазина — R" if not loaded() else "Пусто — R, сменить магазин; Enter (держать) — вынуть")
		return
	_empty_told = false
	_shoot(h, lerpf(SPREAD_HIP, SPREAD_AIM, aim_k))


## Боевая стойка (промпт 05:34): клик — выстрел рукой h примерно в центр экрана, без прицеливания.
## У каждой руки свой магазин и своя задержка — два пистолета стреляют независимо (ЛКМ — левый, ПКМ — правый).
## false — патронов нет (или пистолета нет): тогда этой рукой бьют рукоятью (player_combat.gd).
func stance_fire(h: int) -> bool:
	if not armed() or not game.alive or rounds_in(h) <= 0:
		return false
	if reloading or hand_cd[h] > 0.0:
		return true   # выстрел не готов — клик съеден, рукоятью не бьём
	hand_cd[h] = FIRE_CD
	_shoot(h, SPREAD_STANCE)
	return true


## Сам выстрел из руки h с разбросом spread (патрон уже есть).
func _shoot(h: int, spread: float) -> void:
	var p = game.player
	p.make_noise(p.NOISE_SHOT)   # выстрел слышно далеко и сквозь стены (enemy.gd _hears)
	var r := rounds_in(h)
	_hand = h
	game.inv.equip_dur[SLOTS[h]] = pistol_dur(true, r - 1)
	_play(snd_shot, -1.0, randf_range(0.95, 1.05))
	var cam: Camera3D = p.cam
	var from := cam.global_position
	var dir := (-cam.global_transform.basis.z).rotated(cam.global_transform.basis.x, randf_range(-spread, spread)) \
			.rotated(cam.global_transform.basis.y, randf_range(-spread, spread))
	_bullet_hit(from, dir)
	_flash()
	_recoil()
	_eject()
	_alert(p.global_position)
	if game.net:
		game.net.shot(_muzzle())   # сеть: выстрел видят и слышат другие, враги у хоста слышат
	if game.inv.open:
		game.inv._refresh()


## Попадание пули (промпт 18.11 00:56 — хитбоксы и хэдшоты).
## Враги и мутанты: капсула физики не совпадает с моделью (сгорбленные, руки торчат при замахе), поэтому
## пулю проверяем по самим частям модели (коробки мешей, следуют за анимацией): мимо модели — пролетает
## насквозь, даже если задела капсулу; попала в руку вне капсулы — засчитано. Голова (meta "headshot") — ×HEAD_MULT.
## Остальные цели (игроки по сети, манекен, ящики) — по физике; у игрока по сети голова — верх капсулы.
func _bullet_hit(from: Vector3, dir: Vector3) -> void:
	var p = game.player
	var ex: Array[RID] = [p.get_rid()]
	if car_seat() >= 0:
		ex.append(game.car.get_rid())   # из салона — сквозь свою машину (стрельба из окна)
	var cands: Array = []
	for g in ["enemies", "mutants"]:
		for e in p.get_tree().get_nodes_in_group(g):
			if e is CollisionObject3D and is_instance_valid(e):
				ex.append((e as CollisionObject3D).get_rid())
				if (e as CollisionObject3D).collision_layer & 1 and String(e.get("state")) != "dead":
					cands.append(e)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * RANGE)
	q.exclude = ex
	q.collision_mask = 1 | 512   # 512 — другие игроки в сети (огонь по своим)
	var hit: Dictionary = p.get_world_3d().direct_space_state.intersect_ray(q)
	var wall_d: float = from.distance_to(hit.position) if not hit.is_empty() else RANGE
	# ближайшая часть модели врага до стены
	var best_t := wall_d
	var best_e: Node3D = null
	var best_head := false
	for e in cands:
		var en := e as Node3D
		var to_e := en.global_position - from
		var along := to_e.dot(dir)
		if along < -1.0 or along > best_t + 1.5:
			continue
		if (to_e - dir * along).length() > 3.0:   # луч далеко от врага — части не проверяем
			continue
		var r := _model_hit(en, from, dir, best_t)
		if r.size() > 0 and float(r[0]) < best_t:
			best_t = float(r[0])
			best_e = en
			best_head = bool(r[1])
	var la: int = p.last_arm
	p.last_arm = -1   # урон пулей — не износ оружия в руке (game.gd: weapon_hit смотрит на last_arm)
	if best_e:
		_deal(best_e, from + dir * best_t, dir, best_head, from)
	elif not hit.is_empty():
		if hit.collider.has_method("take_hit"):
			var head := false
			if hit.collider.get("puppet") == true and hit.collider.get("col_cap") is CapsuleShape3D:
				var top: float = (hit.collider.col_cap as CapsuleShape3D).height
				head = (hit.collider as Node3D).to_local(hit.position).y > top - 0.32
			_deal(hit.collider, hit.position, dir, head, from)
		else:
			_impact(hit.position, hit.normal)
	p.last_arm = la


## Множитель урона по дистанции выстрела (вблизи — полный, далеко — DMG_FAR_MULT).
static func dist_mult(d: float) -> float:
	if d <= DMG_FULL_D:
		return 1.0
	var k: float = clampf((d - DMG_FULL_D) / (DMG_FAR_D - DMG_FULL_D), 0.0, 1.0)
	return lerpf(1.0, DMG_FAR_MULT, k)


## Урон цели; хэдшот — ×HEAD_MULT, свой звук и вспышка «В ГОЛОВУ», дальний выстрел — слабее (dist_mult).
func _deal(target: Object, pos: Vector3, dir: Vector3, head: bool, from: Vector3 = Vector3.INF) -> void:
	var dm := 1.0 if from == Vector3.INF else dist_mult(from.distance_to(pos))
	target.take_hit(DMG * dm * (HEAD_MULT if head else 1.0), dir)
	if not head:
		return
	_play(snd_headshot, -2.0, randf_range(0.95, 1.08))
	Fx.dust_burst(game, pos, Color(0.45, 0.06, 0.04), 18)
	Fx.popup_text(game, pos + Vector3(0, 0.35, 0), "В ГОЛОВУ!", Color(1.0, 0.3, 0.2), 1.2)


## Луч по частям модели врага: [t, голова?] ближайшего меша или [] — промах.
## Каждая часть — коробка её меша в своих локальных координатах (поворот и анимация учтены), чуть ужатая
## (сферы/капсулы меньше своей коробки). Полоска здоровья не считается.
func _model_hit(en: Node3D, from: Vector3, dir: Vector3, max_t: float) -> Array:
	var bar = en.get("bar")
	var best := max_t
	var head := false
	var found := false
	var stack: Array = [en]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n == bar or (n is Node3D and not (n as Node3D).visible):
			continue
		for c in n.get_children():
			stack.append(c)
		if not (n is MeshInstance3D) or (n as MeshInstance3D).mesh == null:
			continue
		var mi := n as MeshInstance3D
		var ab := mi.mesh.get_aabb()
		ab = ab.grow(-0.08 * minf(ab.size.x, minf(ab.size.y, ab.size.z)))
		var inv := mi.global_transform.affine_inverse()
		var lf: Vector3 = inv * from
		var ld: Vector3 = inv.basis * dir
		var t := _ray_box(lf, ld, ab)
		if t < 0.0:
			continue
		# t — в локальном масштабе меша; переводим в мировое расстояние
		var wt := (mi.global_transform * (lf + ld * t)).distance_to(from)
		if wt < best:
			best = wt
			found = true
			head = _under_head(mi, en)
	return [best, head] if found else []


static func _under_head(n: Node, root: Node) -> bool:
	while n and n != root:
		if n.has_meta("headshot"):
			return true
		n = n.get_parent()
	return false


## Пересечение луча с коробкой (slab): t входа (>= 0) или -1.
static func _ray_box(o: Vector3, d: Vector3, ab: AABB) -> float:
	var tmin := 0.0
	var tmax := 1e9
	for i in 3:
		var lo: float = ab.position[i]
		var hi: float = ab.end[i]
		if absf(d[i]) < 1e-8:
			if o[i] < lo or o[i] > hi:
				return -1.0
			continue
		var t1: float = (lo - o[i]) / d[i]
		var t2: float = (hi - o[i]) / d[i]
		if t1 > t2:
			var tt := t1
			t1 = t2
			t2 = tt
		tmin = maxf(tmin, t1)
		tmax = minf(tmax, t2)
		if tmin > tmax:
			return -1.0
	return tmin


## Отдача: камера дёргается вверх и чуть в сторону, наполовину возвращается.
func _recoil() -> void:
	var p = game.player
	var kick := randf_range(0.035, 0.05)
	p.head.rotation.x = clampf(p.head.rotation.x + kick, -1.5, 1.4)
	p.rotate_y(randf_range(-0.012, 0.012))
	var back: float = p.head.rotation.x - kick * 0.6
	var tw: Tween = create_tween()   # не p.create_tween(): в машине игрок выключен — твин бы встал
	tw.tween_property(p.head, "rotation:x", back, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var tw2: Tween = create_tween()
	tw2.tween_property(p.cam, "rotation:z", randf_range(-0.02, 0.02), 0.03)
	tw2.tween_property(p.cam, "rotation:z", 0.0, 0.14)


func _muzzle() -> Vector3:
	var p = game.player
	var vm = car_vm[_hand]
	if car_seat() >= 0 and vm != null and is_instance_valid(vm) and (vm as Node3D).visible:
		return (vm as Node3D).global_transform * Vector3(0.14, 0.11, 0.0)
	var n = p.weapon_nodes[_hand]
	if n and is_instance_valid(n):
		return (n as Node3D).global_transform * Vector3(0.15, 0.11, 0.0)
	return p.cam.global_position - p.cam.global_transform.basis.z * 0.6 - p.cam.global_transform.basis.y * 0.15


## Вспышка у дула: свет на пару кадров и яркий «цветок».
func _flash() -> void:
	var pos := _muzzle()
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.75, 0.4)
	l.light_energy = 5.0
	l.omni_range = 7.0
	game.add_child(l)
	l.global_position = pos
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.08
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.85, 0.5, 0.9)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	game.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3(1.6, 0.8, 0.8)
	var tw := mi.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.07)
	tw.parallel().tween_property(mi, "scale", Vector3.ONE * 0.2, 0.06)
	tw.tween_callback(l.queue_free)
	tw.tween_callback(mi.queue_free)


## Попадание в стену: искры, пыль и тёмная выбоина (исчезает через 30 с).
func _impact(pos: Vector3, nrm: Vector3) -> void:
	Fx.dust_burst(game, pos + nrm * 0.03, Color(0.45, 0.43, 0.4), 10)
	for k in 6:
		var s := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.012, 0.012, 0.012)
		s.mesh = bm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1.0, 0.8, 0.4)
		s.material_override = m
		game.add_child(s)
		s.global_position = pos + nrm * 0.02
		var v := (nrm + Vector3(randf_range(-0.8, 0.8), randf_range(-0.3, 0.9), randf_range(-0.8, 0.8))).normalized() * randf_range(0.25, 0.6)
		var tw := s.create_tween()
		tw.tween_property(s, "global_position", s.global_position + v, 0.18).set_ease(Tween.EASE_OUT)
		tw.tween_callback(s.queue_free)
	var hole := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.05, 0.05)
	hole.mesh = qm
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(0.05, 0.045, 0.04, 0.9)
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.roughness = 1.0
	hole.material_override = hm
	game.add_child(hole)
	hole.global_position = pos + nrm * 0.004
	var up := Vector3.UP if absf(nrm.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	hole.look_at(hole.global_position - nrm, up)
	hole.rotate_object_local(Vector3.FORWARD, randf() * TAU)
	var tw2 := hole.create_tween()
	tw2.tween_interval(30.0)
	tw2.tween_property(hm, "albedo_color:a", 0.0, 2.0)
	tw2.tween_callback(hole.queue_free)


## Гильза вылетает вправо-вверх, падает на пол и через 4 с исчезает.
func _eject() -> void:
	var p = game.player
	var b := RigidBody3D.new()
	b.collision_layer = 0
	b.collision_mask = 1
	b.mass = 0.01
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.006
	sh.height = 0.022
	cs.shape = sh
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0055
	cm.bottom_radius = 0.0055
	cm.height = 0.02
	cm.radial_segments = 8
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.8, 0.62, 0.25)
	m.metallic = 0.9
	m.roughness = 0.3
	mi.material_override = m
	b.add_child(mi)
	game.add_child(b)
	b.global_position = _muzzle() - p.cam.global_transform.basis.z * -0.08
	var right: Vector3 = p.cam.global_transform.basis.x
	b.linear_velocity = right * randf_range(1.6, 2.4) + Vector3.UP * randf_range(1.8, 2.6)
	b.angular_velocity = Vector3(randf_range(-20, 20), randf_range(-20, 20), randf_range(-20, 20))
	get_tree().create_timer(4.0).timeout.connect(b.queue_free)


## Шум: враги в радиусе HEAR_R, которые стоят или бродят, бегут на звук (к игроку).
func _alert(at: Vector3) -> void:
	for n in game.get_children():
		if n is CharacterBody3D and n.has_method("take_hit") and n.has_method("_set_state"):
			var st = n.get("state")
			if st in ["idle", "return"] and n.global_position.distance_to(at) < HEAR_R:
				n._set_state("chase")


# ---------- перезарядка ----------

## R: вставить самый полный магазин из сумки (старый — в сумку на его место). Россыпью в пистолет не заряжается.
func reload() -> void:
	if reloading or not armed():
		return
	# два пистолета — перезаряжаем тот, где меньше (без магазина — первым)
	var hs := hands()
	var rh: int = hs[0]
	for h in hs:
		var sc_h: int = rounds_in(h) if loaded_in(h) else -1
		var sc_r: int = rounds_in(rh) if loaded_in(rh) else -1
		if sc_h < sc_r:
			rh = h
	var slot: String = SLOTS[rh]
	var cur := rounds_in(rh)
	var had := loaded_in(rh)
	# казуальный режим (промпт 18.11 00:52): магазины не нужны — патроны из сумки сразу в пистолет
	if game.casual() and game.inv.count("ammo") > 0 and cur < CAP:
		_casual_reload(rh, slot, cur)
		return
	var best := -1
	var best_n := cur if had else -1
	for i in game.inv.slots.size():
		var s = game.inv.slots[i]
		if s != null and s["id"] == "mag":
			var n := int(round(float(s.get("dur", CAP))))
			if n > best_n:
				best_n = n
				best = i
	if best < 0:
		_play(snd_click, -8.0, 0.8)
		if had and cur >= CAP:
			game.hud.toast("Магазин полон")
		elif game.inv.count("mag") > 0:
			game.hud.toast("Запасные магазины не полнее — набей их: перетащи патроны на магазин")
		else:
			game.hud.toast("Нет магазина" if game.inv.count("ammo") <= 0 else "Нет магазина — патроны заряжаются в магазин")
		return
	reloading = true
	_reload_h = rh
	_rel_t = 0.0
	_rel_ev = 0
	_rel_had = had
	game.player.gun_rel_h = rh
	game.player.gun_rel_k = 0.0
	await get_tree().create_timer(RELOAD_T).timeout
	reloading = false
	_reload_end()
	if game.inv.equip[slot] != "pistol":
		return
	if best >= game.inv.slots.size():
		return
	insert_mag(best, slot, false)


func _casual_reload(rh: int, slot: String, _cur: int) -> void:
	reloading = true
	_reload_h = rh
	_rel_t = 0.0
	_rel_ev = 0
	_rel_had = false   # старый магазин не выпадает
	game.player.gun_rel_h = rh
	game.player.gun_rel_k = 0.0
	await get_tree().create_timer(RELOAD_T).timeout
	reloading = false
	_reload_end()
	if game.inv.equip[slot] != "pistol":
		return
	var now := rounds_in(rh) if loaded_in(rh) else 0
	var take := mini(CAP - now, game.inv.count("ammo"))
	if take <= 0:
		return
	game.inv.remove("ammo", take)
	game.inv.equip_dur[slot] = pistol_dur(true, now + take)
	game.hud.toast("Заряжено: %d / %d" % [now + take, CAP], Color(0.9, 0.85, 0.7))
	game.inv.notify()


## Вставить магазин из ячейки mag_idx в пистолет (слот "right"/"left" или номер ячейки с пистолетом).
## Магазин пропадает из сумки; если в пистолете был магазин — он ложится на место вставленного.
func insert_mag(mag_idx: int, target, sound := true) -> bool:
	var inv = game.inv
	var ms = inv.slots[mag_idx]
	if ms == null or ms["id"] != "mag":
		return false
	if target is String:
		if inv.equip[target] != "pistol":
			return false
	else:
		var ps = inv.slots[target]
		if ps == null or ps["id"] != "pistol":
			return false
	var pd: float = inv.get_dur(target)
	var n := int(round(float(ms.get("dur", CAP))))
	if has_mag(pd):
		inv.slots[mag_idx] = {"id": "mag", "n": 1, "dur": float(mag_rounds(pd))}
	else:
		inv.slots[mag_idx] = null
	if target is String:
		inv.equip_dur[target] = pistol_dur(true, n)
	else:
		inv.slots[target]["dur"] = pistol_dur(true, n)
	if sound:
		_play(snd_mag, -6.0, 1.2)
	game.hud.toast("Магазин вставлен: %d / %d" % [n, CAP], Color(0.9, 0.85, 0.7))
	inv.notify()
	return true


## Извлечь магазин из пистолета (слот или ячейка) в сумку; сумка полна — на пол.
func eject(target) -> void:
	var inv = game.inv
	var pd: float = inv.get_dur(target)
	if target is String:
		if inv.equip[target] != "pistol" or not has_mag(pd):
			return
		inv.equip_dur[target] = 0.0
	else:
		if inv.slots[target] == null or inv.slots[target]["id"] != "pistol" or not has_mag(pd):
			return
		inv.slots[target]["dur"] = 0.0
	var n := mag_rounds(pd)
	_play(snd_mag, -6.0, 0.9)
	if inv.add("mag", 1, float(n)) > 0:
		var p = game.player
		var fwd: Vector3 = -p.global_transform.basis.z
		var pk = game._make_pickup("mag", 1, p.global_position + Vector3(0, 1.1, 0) + fwd * 0.4, fwd * 1.2 + Vector3(0, 0.6, 0))
		pk.need_leave = true
		pk.set_meta("dur", float(n))
		game.hud.toast("Магазин извлечён — нет места, упал на пол")
	else:
		game.hud.toast("Магазин извлечён: %d / %d" % [n, CAP], Color(0.9, 0.85, 0.7))
	inv.notify()


## Ход перезарядки: фаза для позы рук, звуки по фазе, магазин во второй руке, старый магазин падает.
func _reload_tick(delta: float) -> void:
	var p = game.player
	if not reloading or p == null:
		_reload_end()
		return
	_rel_t += delta
	var k := clampf(_rel_t / RELOAD_T, 0.0, 1.0)
	p.gun_rel_k = k
	while _rel_ev < REL_EVENTS.size() and k >= float(REL_EVENTS[_rel_ev][0]):
		var ev: String = REL_EVENTS[_rel_ev][1]
		_rel_ev += 1
		match ev:
			"release":
				if _rel_had:
					_rel_play(snd_release, 2.0, randf_range(0.97, 1.03))
					_drop_old_mag()
			"insert":
				_rel_play(snd_insert, 3.0, randf_range(0.97, 1.03))
			"rack_back":
				_rel_play(snd_rack_back, 2.0, randf_range(0.97, 1.03))
			"rack_fwd":
				_rel_play(snd_rack_fwd, 4.0, randf_range(0.97, 1.03))
	# новый магазин: виден в свободной руке, пока его несут от пояса и вставляют
	var j := 1 - _reload_h
	var gn = p.weapon_nodes[_reload_h]
	var show: bool = k > 0.24 and k < 0.6 and p.weapon_ids[j] == "" and gn != null and is_instance_valid(gn) \
			and (gn as Node3D).is_inside_tree() and j < p.fist_fx.size()
	if not show:
		if _rel_mag != null and is_instance_valid(_rel_mag):
			_rel_mag.visible = false
		return
	if _rel_mag == null or not is_instance_valid(_rel_mag):
		_rel_mag = _mag_mesh()
		game.add_child(_rel_mag)
	_rel_mag.visible = true
	var gb: Basis = (gn as Node3D).global_transform.basis.orthonormalized()
	# магазин в кулаке, выровнен по рукояти (наклон рукояти — weapons.gd), верх — к шахте
	var mb := gb * Basis(Vector3.BACK, -0.25)
	_rel_mag.global_transform = Transform3D(mb, p.fist_fx[j].global_position + mb.y * 0.03)


func _reload_end() -> void:
	if _rel_mag != null and is_instance_valid(_rel_mag):
		_rel_mag.queue_free()
	_rel_mag = null
	if game != null and game.player != null:
		game.player.gun_rel_k = -1.0


## Магазин: тёмная коробка с торчащим патроном (центр — середина, вверх — +Y).
static func _mag_mesh() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.026, 0.085, 0.018)
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.2, 0.2, 0.2)
	m.metallic = 0.7
	m.roughness = 0.5
	mi.material_override = m
	var c := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0045
	cm.bottom_radius = 0.0045
	cm.height = 0.016
	c.mesh = cm
	var bm2 := StandardMaterial3D.new()
	bm2.albedo_color = Color(0.8, 0.62, 0.25)
	bm2.metallic = 0.9
	c.material_override = bm2
	c.rotation.z = PI / 2
	c.position = Vector3(0.004, 0.046, 0)
	mi.add_child(c)
	return mi


## Старый магазин выскальзывает из рукояти и падает (только картинка — сам он ложится в сумку).
func _drop_old_mag() -> void:
	var p = game.player
	if car_seat() >= 0:
		return   # в салоне старый магазин падает под ноги — не видно
	var gn = p.weapon_nodes[_reload_h]
	if gn == null or not is_instance_valid(gn) or not (gn as Node3D).is_inside_tree():
		return
	var b := RigidBody3D.new()
	b.collision_layer = 0
	b.collision_mask = 1
	b.mass = 0.1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.026, 0.085, 0.018)
	cs.shape = sh
	b.add_child(cs)
	b.add_child(_mag_mesh())
	game.add_child(b)
	var g: Transform3D = (gn as Node3D).global_transform
	var gb := g.basis.orthonormalized() * Basis(Vector3.BACK, -0.25)
	b.global_transform = Transform3D(gb, g * Vector3(-0.02, -0.04, 0))
	b.linear_velocity = -gb.y * 1.2
	b.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))
	get_tree().create_timer(5.0).timeout.connect(b.queue_free)


## «Снарядить» в меню магазина или патроны, перетащенные на магазин: набить патронами из сумки.
func fill_mag(idx: int) -> void:
	var s = game.inv.slots[idx]
	if s == null or s["id"] != "mag":
		return
	var cur := int(round(float(s.get("dur", CAP))))
	var take := mini(CAP - cur, game.inv.count("ammo"))
	if cur >= CAP:
		game.hud.toast("Магазин и так полон")
		return
	if take <= 0:
		game.hud.toast("Нет патронов")
		return
	game.inv.remove("ammo", take)
	s["dur"] = float(cur + take)
	_play(snd_mag, -8.0, 1.4)
	game.hud.toast("Магазин: %d / %d" % [cur + take, CAP], Color(0.9, 0.85, 0.7))
	game.inv.notify()


# ---------- звуки (процедурные) ----------

## Звуки перезарядки пока выключены (промпт 16.11 05:10) — вернуть: RELOAD_SND = true.
const RELOAD_SND := false
func _rel_play(s: AudioStream, db: float, pitch: float) -> void:
	if RELOAD_SND:
		_play(s, db, pitch)


func _play(s: AudioStream, db: float, pitch: float) -> void:
	var a := AudioStreamPlayer.new()
	a.stream = s
	a.volume_db = db
	a.pitch_scale = pitch
	add_child(a)
	a.play()
	a.finished.connect(a.queue_free)


## Хлопок: резкий шумовой удар, низкий «бум» и эхо бункера (три затухающих отражения).
static func _shot_sound() -> AudioStreamWAV:
	var r := RandomNumberGenerator.new()
	r.seed = 49
	var n := int(RATE * 1.3)
	var dry := PackedFloat32Array()
	dry.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var w := r.randf() * 2.0 - 1.0
		lp += (w - lp) * 0.35
		var crack := w * exp(-t * 60.0)
		var body := lp * exp(-t * 14.0) * 0.8
		var boom := sin(TAU * 62.0 * t * (1.0 - t * 0.8)) * exp(-t * 11.0) * 0.9
		dry[i] = crack + body + boom
	var out := dry.duplicate()
	for e in [[0.11, 0.38], [0.24, 0.22], [0.39, 0.12], [0.57, 0.06]]:
		var off := int(RATE * float(e[0]))
		var lp2 := 0.0
		for i in range(n - off):
			lp2 += (dry[i] - lp2) * 0.18     # отражения глуше
			out[i + off] += lp2 * float(e[1])
	return _wav(out, 0.9)


## Многослойный механический звук: слои [начало с, вид, длина с, частота, громкость].
## tick — короткий металлический щелчок, ring — звон металла (неровные обертоны), scrape — скольжение металла
## по металлу (полосовой шум), thump — глухой удар корпусом.
static func _layered(layers: Array) -> AudioStreamWAV:
	var total := 0.0
	for l in layers:
		total = maxf(total, float(l[0]) + float(l[2]))
	var n := int(RATE * (total + 0.03))
	var buf := PackedFloat32Array()
	buf.resize(n)
	var r := RandomNumberGenerator.new()
	r.seed = 77
	for l in layers:
		var st := int(RATE * float(l[0]))
		var ln := int(RATE * float(l[2]))
		var kind: String = l[1]
		var f: float = l[3]
		var amp: float = l[4]
		var lp := 0.0
		var lp2 := 0.0
		var a := clampf(f / RATE * TAU, 0.01, 0.95)
		for i in ln:
			if st + i >= n:
				break
			var t := float(i) / RATE
			var u := float(i) / ln
			var v := 0.0
			match kind:
				"tick":
					var w := r.randf() * 2.0 - 1.0
					lp += (w - lp) * 0.6
					v = (w - lp) * 0.7 * exp(-t * 260.0) + sin(TAU * f * t) * exp(-t * 180.0) * 0.6
				"ring":
					v = (sin(TAU * f * t) + 0.6 * sin(TAU * f * 1.47 * t + 0.4) + 0.35 * sin(TAU * f * 2.31 * t + 1.1)) \
							* exp(-t * 4.0 / float(l[2])) * 0.5
				"scrape":
					var w2 := r.randf() * 2.0 - 1.0
					lp += (w2 - lp) * a
					lp2 += (lp - lp2) * a * 0.5
					var grit := 0.6 + 0.4 * sin(TAU * 140.0 * t + r.randf() * 0.3)
					v = (lp - lp2) * 2.5 * sin(PI * u) * grit
				"thump":
					var w3 := r.randf() * 2.0 - 1.0
					lp += (w3 - lp) * 0.08
					v = (sin(TAU * f * t * (1.0 - 0.3 * u)) + lp * 1.5) * exp(-t * 45.0)
			buf[st + i] += v * amp
	# тесное эхо бункера
	var out := buf.duplicate()
	for e in [[0.045, 0.22], [0.09, 0.12]]:
		var off := int(RATE * float(e[0]))
		for i in range(n - off):
			out[i + off] += buf[i] * float(e[1])
	return _wav(out, 0.95)


static func _click_sound(len_s: float, freq: float) -> AudioStreamWAV:
	var n := int(RATE * len_s)
	var b := PackedFloat32Array()
	b.resize(n)
	var r := RandomNumberGenerator.new()
	r.seed = int(freq)
	for i in n:
		var t := float(i) / RATE
		b[i] = (sin(TAU * freq * t) * 0.6 + (r.randf() * 2.0 - 1.0) * 0.4) * exp(-t * 120.0)
	return _wav(b, 0.7)


static func _wav(buf: PackedFloat32Array, peak: float) -> AudioStreamWAV:
	var mx := 0.0001
	for v in buf:
		mx = maxf(mx, absf(v))
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, int(clampf(buf[i] / mx * peak, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	return w
