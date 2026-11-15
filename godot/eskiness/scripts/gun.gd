extends Node
## Пистолет (промпт 14.11 19:49): старый обшарпанный, лежит в сейфе вместе с магазином и патронами.
## В правой руке (промпт 22:53): ЛКМ (attack_left, player_combat.gd: charge_begin) — выстрел; ПКМ держать — прицел
## (пистолет к глазу, зум, точнее). Хитскан из камеры.
## Магазин — отдельная вещь: вставленный пропадает из инвентаря. R — вставить самый полный магазин из сумки
## (старый — в сумку); перетащить магазин на пистолет — то же; патроны на магазин — дозарядить его;
## зажать Enter (действие «mag_eject») — извлечь магазин в сумку.
## dur пистолета: 0 — магазина нет, 1 + n — вставлен магазин с n патронами (так dur всегда >= 0 и не теряется
## при выбрасывании/сундуках/сейве). dur магазина — просто патроны в нём (0..CAP).
## Выстрел слышат враги вокруг и бегут на звук. Счётчик «в магазине / в сумке» — справа от хотбара.

const Items := preload("res://scripts/items.gd")
const Fx := preload("res://scripts/core/fx.gd")
const CAP := 8                   # патронов в магазине
const DMG := 40.0                # по бетоннику (95 HP) — 3 попадания
const RANGE := 80.0
const FIRE_CD := 0.28
const RELOAD_T := 1.5
const HEAR_R := 28.0             # радиус, в котором враги слышат выстрел
const EJECT_T := 0.5             # столько держать Enter — извлечь магазин
const AIM_FOV := 0.7             # множитель поля зрения в прицеле
const SPREAD_HIP := 0.03         # разброс от бедра, рад
const SPREAD_AIM := 0.004
const RATE := 22050

var game
var cd := 0.0
var reloading := false
var voice: AudioStreamPlayer
var snd_shot: AudioStreamWAV
var snd_click: AudioStreamWAV
var snd_mag: AudioStreamWAV
var ui: CanvasLayer
var count_l: Label
var _empty_told := false
var aiming := false
var aim_k := 0.0                 # 0..1 — насколько пистолет поднят к глазу
var eject_t := 0.0
var _eject_lock := false         # Enter держат после извлечения — ждём отпускания


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
	snd_mag = _click_sound(0.06, 900.0)
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


func armed() -> bool:
	return game != null and game.inv.equip["right"] == "pistol"


func rounds() -> int:
	return mag_rounds(game.inv.get_dur("right")) if armed() else 0


func loaded() -> bool:
	return armed() and has_mag(game.inv.get_dur("right"))


func fov_mult() -> float:
	return lerpf(1.0, AIM_FOV, aim_k)


func _process(delta: float) -> void:
	cd -= delta
	if game == null:
		return
	var p = game.player
	var can: bool = armed() and game.alive and p != null and p.active and not game.inv.open \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	aiming = can and not reloading and Input.is_action_pressed("attack_right")
	aim_k = move_toward(aim_k, 1.0 if aiming else 0.0, delta * 6.0)
	# зажать Enter — извлечь магазин
	var ej: bool = InputMap.has_action("mag_eject") and Input.is_action_pressed("mag_eject")
	if can and loaded() and not reloading and ej and not _eject_lock:
		eject_t += delta
		if eject_t >= EJECT_T:
			eject_t = 0.0
			_eject_lock = true
			eject("right")
	else:
		eject_t = 0.0
		if not ej:
			_eject_lock = false
	count_l.visible = armed() and game.alive
	if count_l.visible:
		var r := rounds()
		if not loaded():
			count_l.text = "НЕТ МАГАЗИНА  (R)"
		elif eject_t > 0.0:
			count_l.text = "ИЗВЛЕЧЬ… %d%%" % int(eject_t / EJECT_T * 100.0)
		else:
			count_l.text = "%s  %d / %d" % ["ПЕРЕЗАРЯДКА" if reloading else "ПАТРОНЫ", r, CAP]
		count_l.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35) if r == 0 else Color(0.95, 0.88, 0.7))
	_aim()


## Пистолет в кулаке смотрит стволом туда же, куда камера (хват из костей кисти рассчитан на биту/нож).
## Положение — от руки, поворот — от камеры, с лёгким наклоном; во время перезарядки — её анимация.
func _aim() -> void:
	if not armed() or reloading:
		return
	var p = game.player
	var n = p.weapon_nodes[1]
	if n == null or not is_instance_valid(n):
		return
	var cb: Basis = p.cam.global_transform.basis.orthonormalized()
	var sc: Vector3 = (n as Node3D).global_transform.basis.get_scale()
	var tilt := 1.0 - aim_k
	var b := Basis(-cb.z, cb.y, cb.x).rotated(cb.x, -0.06 * tilt).rotated(cb.y, 0.05 * tilt)   # +X модели — вперёд, +Y — вверх
	var gt: Transform3D = (n as Node3D).global_transform
	gt.basis = Basis(b.x * sc.x, b.y * sc.y, b.z * sc.z)
	if aim_k > 0.0:
		# прицел: мушка по центру экрана, чуть ниже глаза (ствол — 0.11 над рукоятью, см. _muzzle)
		var eye: Vector3 = p.cam.global_position - cb.z * 0.36 - cb.y * (0.11 * sc.y + 0.035)
		gt.origin = gt.origin.lerp(eye, aim_k)
	(n as Node3D).global_transform = gt


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("reload") and not e.is_echo() and armed() and game.player.active and game.alive:
		reload()


# ---------- выстрел ----------

func fire() -> void:
	var p = game.player
	if not armed() or reloading or cd > 0.0 or not game.alive:
		return
	cd = FIRE_CD
	var r := rounds()
	if r <= 0:
		_play(snd_click, -6.0, 1.0)
		if not _empty_told:
			_empty_told = true
			game.hud.toast("Нет магазина — R" if not loaded() else "Пусто — R, сменить магазин; Enter (держать) — вынуть")
		return
	_empty_told = false
	game.inv.equip_dur["right"] = pistol_dur(true, r - 1)
	_play(snd_shot, -1.0, randf_range(0.95, 1.05))
	var cam: Camera3D = p.cam
	var from := cam.global_position
	var spread := lerpf(SPREAD_HIP, SPREAD_AIM, aim_k)
	var dir := (-cam.global_transform.basis.z).rotated(cam.global_transform.basis.x, randf_range(-spread, spread)) \
			.rotated(cam.global_transform.basis.y, randf_range(-spread, spread))
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * RANGE)
	q.exclude = [p.get_rid()]
	q.collision_mask = 1 | 512   # 512 — другие игроки в сети (огонь по своим)
	var hit: Dictionary = p.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		if hit.collider.has_method("take_hit"):
			# урон пулей — не износ оружия в руке (game.gd: weapon_hit смотрит на last_arm)
			var la: int = p.last_arm
			p.last_arm = -1
			hit.collider.take_hit(DMG, dir)
			p.last_arm = la
		else:
			_impact(hit.position, hit.normal)
	_flash()
	_recoil()
	_eject()
	_alert(p.global_position)
	if game.net:
		game.net.shot(_muzzle())   # сеть: выстрел видят и слышат другие, враги у хоста слышат
	if game.inv.open:
		game.inv._refresh()


## Отдача: камера дёргается вверх и чуть в сторону, наполовину возвращается.
func _recoil() -> void:
	var p = game.player
	var kick := randf_range(0.035, 0.05)
	p.head.rotation.x = clampf(p.head.rotation.x + kick, -1.5, 1.4)
	p.rotate_y(randf_range(-0.012, 0.012))
	var back: float = p.head.rotation.x - kick * 0.6
	var tw: Tween = p.create_tween()
	tw.tween_property(p.head, "rotation:x", back, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var tw2: Tween = p.create_tween()
	tw2.tween_property(p.cam, "rotation:z", randf_range(-0.02, 0.02), 0.03)
	tw2.tween_property(p.cam, "rotation:z", 0.0, 0.14)


func _muzzle() -> Vector3:
	var p = game.player
	var n = p.weapon_nodes[1]
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
	var cur := rounds()
	var had := loaded()
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
	_play(snd_mag, -6.0, 0.8)
	_reload_anim()
	await get_tree().create_timer(RELOAD_T).timeout
	reloading = false
	if not armed():
		return
	if best >= game.inv.slots.size():
		return
	insert_mag(best, "right", false)
	_play(snd_mag, -5.0, 1.25)


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
		game.hud.toast("Магазин извлечён — сумка полна, упал на пол")
	else:
		game.hud.toast("Магазин извлечён: %d / %d" % [n, CAP], Color(0.9, 0.85, 0.7))
	inv.notify()


## Пистолет уходит вниз и поворачивается, потом возвращается.
func _reload_anim() -> void:
	var n = game.player.weapon_nodes[1]
	if n == null or not is_instance_valid(n):
		return
	var t0: Transform3D = n.transform
	var tw: Tween = n.create_tween()
	tw.tween_property(n, "rotation:z", n.rotation.z - 0.9, 0.3).set_trans(Tween.TRANS_SINE)
	tw.tween_interval(0.5)
	tw.tween_callback(func(): _play(snd_click, -8.0, 0.7))
	tw.tween_interval(0.35)
	tw.tween_property(n, "transform", t0, 0.3).set_trans(Tween.TRANS_SINE)


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
