extends Node3D
## Развитие лагеря у озера (промпт 20.11 18:32): стройплощадки вокруг костра — подойди, [F] открывает окно стройки (материалы есть/не хватает, «Построить»)
## (без чертежей и верстака). Свои постройки лагеря + общие из world/build_kit.gd (турель, мешки, лампа на столбе).
## Состояние — в сейве village.lake_d.built. В сети стройка рассылается всем (village_net.gd: v_lake_build),
## выдачу припасов и урон кольев считает хост.
const Spot := preload("res://scripts/locations/lake/lake_spot.gd")
const Kit := preload("res://scripts/world/build_kit.gd")
const Items := preload("res://scripts/items/items.gd")
const G := 4.0
const FIRE := Vector3(20.0, G, 1210.0)
const STAKE_R := 11.0
## [id, название, что даёт, материалы ({} — из build_kit.gd), место, поворот]
const BUILDS := [
	["lean", "Навес с лежанкой", "под навесом лечишься", {"wood": 6, "twine": 2}, Vector3(16.5, G, 1205.5), 0.6],
	["smoke", "Коптильня", "раз в 2 мин — тушёнка или сухпаёк", {"wood": 4, "stone": 5}, Vector3(8.5, G, 1205.0), 0.3],
	["barrel", "Бочка для дождевой воды", "раз в 1.5 мин — бутылка воды", {"scrap": 3, "tape": 1, "wood": 2}, Vector3(23.5, G, 1218.5), 0.0],
	["herbs", "Сушилка для трав", "раз в 2.5 мин — бинт или таблетки", {"wood": 3, "twine": 3, "glass": 1}, Vector3(9.5, G, 1215.0), 1.4],
	["stakes", "Колья вокруг костра", "мутанты у костра ранятся о колья", {"wood": 8, "nut": 4}, Vector3(17.0, G, 1214.5), 0.0],
	["turret", "Кустарная турель", "сама стреляет по врагам, [F] — зарядить", {}, Vector3(36.0, G, 1204.0), PI],
	["sandbags", "Мешки с песком", "укрытие от плевков", {}, Vector3(35.5, G, 1208.5), PI],
	["lamp", "Лампа на столбе", "свет у костра ночью", {}, Vector3(21.0, G, 1213.5), 0.0],
]
## Что выдают постройки: id -> [период, предметы]
const PROD := {"smoke": [120.0, ["canned", "ration"]], "barrel": [90.0, ["water"]], "herbs": [150.0, ["bandage", "pills"]]}

var village                  # village.gd (оттуда game)
var built := {}              # id -> true
var sites := {}              # id -> стройплощадка (lake_spot.gd)
var prod_t := {}             # id -> секунд до выдачи
var prod := {}               # id -> выданная вещь (пока лежит — новую не даём)
var stake_t := 0.0
var win: CanvasLayer         # окно строительства
var win_b: Array
var win_open := false
var win_t := 0


func _ready() -> void:
	name = "LakeBase"
	for i in BUILDS.size():
		_site(i)


func _g():
	return village.get("game") if village else null


## Материалы постройки: свои или из чертежа build_kit.gd.
func cost(b: Array) -> Dictionary:
	if not (b[3] as Dictionary).is_empty():
		return b[3]
	for k in Kit.BLUEPRINTS:
		if k[0] == b[0]:
			return k[4]
	return {}


## Стройплощадка: колышек с табличкой и надписью.
func _site(i: int) -> void:
	var b: Array = BUILDS[i]
	var s := Spot.new()
	s.host = self
	s.idx = i
	s.position = b[4]
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.5, 1.2, 0.5)
	cs.shape = bs
	cs.position.y = 0.6
	s.add_child(cs)
	var wood := _m(Color(0.42, 0.3, 0.18))
	_box(s, Vector3(0.1, 1.1, 0.1), Vector3(0, 0.55, 0), wood)
	_box(s, Vector3(0.5, 0.3, 0.04), Vector3(0, 0.95, 0.06), _m(Color(0.6, 0.48, 0.3)))
	for c in [Vector3(-0.9, 0, -0.9), Vector3(0.9, 0, -0.9), Vector3(-0.9, 0, 0.9), Vector3(0.9, 0, 0.9)]:
		_box(s, Vector3(0.06, 0.4, 0.06), c + Vector3(0, 0.2, 0), wood)
	var l := Label3D.new()
	l.text = "Стройплощадка\n" + String(b[1])
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.pixel_size = 0.004
	l.font_size = 40
	l.outline_size = 8
	l.modulate = Color(1.0, 0.85, 0.5)
	l.position.y = 1.55
	l.visibility_range_end = 14.0
	s.add_child(l)
	add_child(s)
	sites[b[0]] = s


func _need_text(b: Array, g) -> String:
	var parts: PackedStringArray = []
	var c := cost(b)
	for id in c:
		parts.append("%s %d/%d" % [Items.item_name(String(id)), g.inv.count(String(id)) if g else 0, int(c[id])])
	return ", ".join(parts)


func spot_prompt(s, g) -> String:
	var b: Array = BUILDS[s.idx]
	return "[F] Строить: %s — %s  (%s)" % [b[1], b[2], _need_text(b, g)]


func spot_use(s, g) -> void:
	var b: Array = BUILDS[s.idx]
	if built.has(b[0]) or win_open or g.window_open():
		return
	_open_win(b, g)


## Строим: списать материалы и поставить (в сети — рассылкой).
func _do_build(b: Array, g) -> void:
	if built.has(b[0]):
		return
	var c := cost(b)
	for id in c:
		if g.inv.count(String(id)) < int(c[id]):
			g.play_ui("buzz", -14.0)
			g.hud.toast("Не хватает: " + _need_text(b, g), Color(1.0, 0.6, 0.45))
			return
	for id in c:
		g.inv.remove(String(id), int(c[id]))
	if g.net:
		preload("res://scripts/locations/village/village_net.gd").ensure(g).rpc("v_lake_build", String(b[0]))
	else:
		build(String(b[0]), true)


## Окно строительства: что нужно (есть/не хватает) и кнопка «Построить».
func _open_win(b: Array, g) -> void:
	_close_win(false)
	win_b = b
	win_open = true
	win_t = Time.get_ticks_msec()
	g.set_meta("lake_win", true)
	g.player.active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	win = CanvasLayer.new()
	win.layer = 20
	add_child(win)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.45)
	win.add_child(dim)
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.075, 0.06, 0.96)
	sb.border_color = Color(0.85, 0.55, 0.25)
	sb.set_border_width_all(3)
	sb.set_content_margin_all(18)
	pc.add_theme_stylebox_override("panel", sb)
	pc.set_anchors_preset(Control.PRESET_CENTER)
	pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pc.grow_vertical = Control.GROW_DIRECTION_BOTH
	pc.custom_minimum_size = Vector2(440, 0)
	dim.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	pc.add_child(vb)
	vb.add_child(_lbl("СТРОЙКА: " + String(b[1]).to_upper(), 24, Color(1.0, 0.85, 0.5)))
	vb.add_child(_lbl(String(b[2]), 17, Color(0.85, 0.82, 0.75)))
	vb.add_child(_lbl("Нужны материалы:", 18, Color(0.95, 0.9, 0.78)))
	var ok := true
	var c := cost(b)
	for id in c:
		var have: int = g.inv.count(String(id))
		var enough := have >= int(c[id])
		ok = ok and enough
		vb.add_child(_lbl("%s %s: %d / %d%s" % ["✔" if enough else "✘", Items.item_name(String(id)), have, int(c[id]), "" if enough else "  (не хватает %d)" % (int(c[id]) - have)], 19, Color(0.6, 0.95, 0.5) if enough else Color(1.0, 0.5, 0.4)))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(hb)
	var bb := Button.new()
	bb.text = "Построить"
	bb.custom_minimum_size = Vector2(170, 44)
	bb.disabled = not ok
	bb.pressed.connect(func():
		_do_build(b, g)
		_close_win())
	hb.add_child(bb)
	var cb := Button.new()
	cb.text = "Закрыть"
	cb.custom_minimum_size = Vector2(130, 44)
	cb.pressed.connect(_close_win)
	hb.add_child(cb)


func _lbl(t: String, sz: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	return l


func _close_win(restore := true) -> void:
	if win and is_instance_valid(win):
		win.queue_free()
	win = null
	var was := win_open
	win_open = false
	var g = _g()
	if g:
		g.set_meta("lake_win", false)
		if was and restore and g.player and g.alive:
			g.player.active = true
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(e: InputEvent) -> void:
	if not win_open:
		return
	if e.is_pressed() and not e.is_echo() and (Controls.event(e, "ui_cancel") or Controls.event(e, "interact") or Controls.event(e, "inventory")):
		get_viewport().set_input_as_handled()
		if Time.get_ticks_msec() - win_t > 300:
			_close_win()


## Поставить постройку (у всех игроков; fx — со звуком и надписью, без — загрузка сейва).
func build(id: String, fx := false) -> void:
	if built.has(id):
		return
	var b: Array = []
	for k in BUILDS:
		if k[0] == id:
			b = k
	if b.is_empty():
		return
	built[id] = true
	var s = sites.get(id)
	if s and is_instance_valid(s):
		s.queue_free()
	sites.erase(id)
	var n: Node3D
	match id:
		"lean":
			n = _lean()
		"smoke":
			n = _smoke()
		"barrel":
			n = _barrel()
		"herbs":
			n = _herbs()
		"stakes":
			_stakes()
		"lamp":
			n = Node3D.new()
			var post := _m(Color(0.32, 0.24, 0.15))
			_box(n, Vector3(0.14, 2.9, 0.14), Vector3(0, 1.45, 0), post)
			_box(n, Vector3(0.7, 0.08, 0.08), Vector3(0.35, 2.85, 0), post)
			var lamp = Kit.make("lamp", _g())
			if lamp:
				lamp.position = Vector3(0.62, 2.85, 0)
				n.add_child(lamp)
		_:
			n = Kit.make(id, _g())
	if n:
		n.position = b[4]
		n.rotation.y = float(b[5])
		add_child(n)
	prod_t[id] = 20.0
	var g = _g()
	if fx and g:
		g.play_at("thud", b[4], -4.0, 0.9)
		g.hud.toast("Построено: %s — %s" % [b[1], b[2]], Color(0.7, 0.95, 0.6))


func _process(delta: float) -> void:
	var g = _g()
	if g == null or g.player == null:
		return
	# навес: рядом с ним лечишься
	if built.has("lean") and g.alive and g.player.global_position.distance_to(BUILDS[0][4]) < 4.0:
		g.heal(1.5 * delta)
	if g.net and not g.net.is_host():
		return
	for id in PROD:
		if not built.has(id):
			continue
		prod_t[id] = float(prod_t.get(id, 0.0)) - delta
		if prod_t[id] > 0.0:
			continue
		prod_t[id] = float(PROD[id][0])
		var old = prod.get(id)
		if old != null and is_instance_valid(old) and not old.taken:
			continue
		var b: Array = []
		for k in BUILDS:
			if k[0] == id:
				b = k
		var at: Vector3 = (b[4] as Vector3) + Basis(Vector3.UP, float(b[5])) * Vector3(0, 0.5, 1.2)
		var p = g._make_pickup(String((PROD[id][1] as Array).pick_random()), 1, at, Vector3.ZERO)
		p.angular_velocity = Vector3.ZERO
		p.life = 1.0e9
		prod[id] = p
	# колья: мутант, подошедший к костру, ранится
	if built.has("stakes"):
		stake_t -= delta
		if stake_t <= 0.0:
			stake_t = 1.5
			for m in get_tree().get_nodes_in_group("mutants"):
				if m.state == "dead" or m.net_puppet:
					continue
				var dv: Vector3 = m.global_position - FIRE
				dv.y = 0.0
				if dv.length() < STAKE_R + 0.8:
					m.apply_hit(8.0, -dv.normalized())


# ---------- модели ----------

func _m(c: Color, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _box(p: Node3D, size: Vector3, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	p.add_child(mi)
	return mi


## Навес: четыре столба, скат из досок, лежанка с одеялом.
func _lean() -> Node3D:
	var n := Node3D.new()
	var wood := _m(Color(0.36, 0.26, 0.16))
	for c in [Vector3(-1.1, 0.8, -0.9), Vector3(1.1, 0.8, -0.9)]:
		_box(n, Vector3(0.12, 1.6, 0.12), c, wood)
	for c in [Vector3(-1.1, 1.05, 0.9), Vector3(1.1, 1.05, 0.9)]:
		_box(n, Vector3(0.12, 2.1, 0.12), c, wood)
	_box(n, Vector3(2.5, 0.06, 2.1), Vector3(0, 1.85, 0), _m(Color(0.3, 0.34, 0.22)), Vector3(-0.24, 0, 0))
	_box(n, Vector3(0.9, 0.22, 1.9), Vector3(0, 0.11, 0), _m(Color(0.45, 0.33, 0.2)))
	_box(n, Vector3(0.85, 0.08, 1.3), Vector3(0, 0.26, 0.25), _m(Color(0.25, 0.35, 0.3)))
	_box(n, Vector3(0.5, 0.12, 0.3), Vector3(0, 0.28, -0.7), _m(Color(0.75, 0.72, 0.65)))
	return n


## Коптильня: каменное основание, дощатая камера, труба и дымок.
func _smoke() -> Node3D:
	var n := Node3D.new()
	_box(n, Vector3(1.2, 0.5, 1.2), Vector3(0, 0.25, 0), _m(Color(0.42, 0.42, 0.4)))
	_box(n, Vector3(1.0, 1.1, 1.0), Vector3(0, 1.05, 0), _m(Color(0.3, 0.22, 0.14)))
	_box(n, Vector3(1.25, 0.08, 1.25), Vector3(0, 1.64, 0), _m(Color(0.22, 0.18, 0.12)))
	_box(n, Vector3(0.2, 0.6, 0.2), Vector3(0.25, 1.95, 0.2), _m(Color(0.2, 0.2, 0.2)))
	var pt := CPUParticles3D.new()
	pt.amount = 14
	pt.lifetime = 3.0
	pt.position = Vector3(0.25, 2.3, 0.2)
	pt.direction = Vector3.UP
	pt.spread = 12.0
	pt.gravity = Vector3(0.15, 0.5, 0)
	pt.initial_velocity_min = 0.3
	pt.initial_velocity_max = 0.6
	pt.scale_amount_min = 0.6
	pt.scale_amount_max = 1.4
	var sm := SphereMesh.new()
	sm.radius = 0.15
	sm.height = 0.3
	var mat := _m(Color(0.6, 0.6, 0.6, 0.35))
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.material = mat
	pt.mesh = sm
	n.add_child(pt)
	return n


## Бочка с водой и жестяным жёлобом.
func _barrel() -> Node3D:
	var n := Node3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.4
	cm.bottom_radius = 0.4
	cm.height = 1.0
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = _m(Color(0.25, 0.32, 0.38), 0.6)
	mi.position.y = 0.5
	n.add_child(mi)
	var top := CylinderMesh.new()
	top.top_radius = 0.36
	top.bottom_radius = 0.36
	top.height = 0.02
	var w := MeshInstance3D.new()
	w.mesh = top
	w.material_override = _m(Color(0.2, 0.35, 0.45), 0.1)
	w.position.y = 0.95
	n.add_child(w)
	_box(n, Vector3(0.2, 0.05, 0.9), Vector3(0, 1.15, -0.4), _m(Color(0.5, 0.5, 0.48), 0.5), Vector3(0.3, 0, 0))
	return n


## Сушилка: две стойки, перекладина, пучки трав.
func _herbs() -> Node3D:
	var n := Node3D.new()
	var wood := _m(Color(0.38, 0.27, 0.16))
	_box(n, Vector3(0.1, 1.7, 0.1), Vector3(-0.9, 0.85, 0), wood)
	_box(n, Vector3(0.1, 1.7, 0.1), Vector3(0.9, 0.85, 0), wood)
	_box(n, Vector3(2.0, 0.08, 0.08), Vector3(0, 1.62, 0), wood)
	var herb := _m(Color(0.32, 0.45, 0.2))
	for i in 6:
		_box(n, Vector3(0.14, 0.4, 0.14), Vector3(-0.75 + 0.3 * i, 1.35, 0), herb, Vector3(0, 0, 0.15 * (i % 2 * 2 - 1)))
	return n


## Колья кругом у костра, остриём наружу.
func _stakes() -> void:
	var n := Node3D.new()
	n.position = FIRE
	add_child(n)
	var m := _m(Color(0.42, 0.32, 0.2))
	for i in 22:
		var a := TAU * float(i) / 22.0
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.07
		cm.height = 1.3
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.material_override = m
		var tangent := Vector3(-sin(a), 0, cos(a))
		mi.transform = Transform3D(Basis(tangent, 0.5), Vector3(cos(a) * STAKE_R, 0.5, sin(a) * STAKE_R))
		n.add_child(mi)
