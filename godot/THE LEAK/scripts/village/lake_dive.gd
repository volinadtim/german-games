extends StaticBody3D
## Озеро в лагере (промпт 20.11 18:33): невидимая стенка по кромке воды и погружение.
## С аквалангом (items.gd: scuba) в сумке — [F] у воды: игрок уходит на дно (отдельная «яма» глубоко под
## лагерем, синий фильтр на экране), воздуха на AIR с. На дне — ценный лут (LOOT, пополняется раз в REGEN с).
## [F] у троса буя или кончился воздух — всплыть на берег, где нырял. Подводный фонарь (dive_light) — свет на дне.

const AIR := 60.0
const DEPTH := 60.0          # дно ниже воды на столько метров
const FLOOR_R := 13.0
const MAX_LOOT := 6
const REGEN := 45.0          # раз в столько секунд на дне появляется новая находка
## [id, от, до, вес]
const LOOT := [["coin", 15, 45, 30], ["ammo_box", 1, 1, 10], ["medkit_army", 1, 1, 6], ["filter2", 1, 2, 10],
	["kevlar_helmet", 1, 1, 3], ["plate_vest", 1, 1, 2], ["fire_axe", 1, 1, 3], ["battery", 2, 4, 10], ["energy", 1, 2, 8]]

var center := Vector3.ZERO   # центр воды (lake_camp.gd: LAKE_C)
var game
var bottom: Node3D           # подводная яма (строится при первом погружении)
var divers := {}             # player -> {"air": сек, "back": Vector3, "light": OmniLight3D}
var loot: Array = []         # лежащие на дне pickup.gd
var regen_t := 0.0
var started := false
var tint: CanvasLayer
var air_l: Label


## Трос буя на дне: [F] — всплыть.
class Rope extends StaticBody3D:
	var dive

	func get_prompt(_g) -> String:
		return "[F] Всплыть"

	func interact(g) -> void:
		dive.surface(g.player)


## Центр дна.
func bottom_c() -> Vector3:
	return center - Vector3(0, DEPTH, 0)


func get_prompt(g) -> String:
	if g.inv.count("scuba") > 0:
		return "[F] Нырнуть с аквалангом"
	return "Озеро. Нырнуть — нужен акваланг (Trinkets Market #3)"


## [F] у воды: нырнуть, если есть акваланг.
func interact(g) -> void:
	game = g
	var p = g.player
	if p == null or divers.has(p):
		return
	if g.inv.count("scuba") <= 0:
		_hint("Нужен акваланг — продаётся в Trinkets Market #3, вкладка «Одежда» → «Снаряжение».")
		g.play_ui("buzz", -14.0)
		return
	if bottom == null:
		_build_bottom()
	_top_up()
	var d := {"air": AIR, "back": p.global_position, "light": null}
	if g.inv.count("dive_light") > 0:
		var l := OmniLight3D.new()
		l.light_color = Color(0.85, 0.95, 1.0)
		l.omni_range = 11.0
		l.light_energy = 2.2
		l.position = Vector3(0, 1.4, 0)
		p.add_child(l)
		d["light"] = l
	divers[p] = d
	p.global_position = bottom_c() + Vector3(2.0, 0.4, 0.0)
	p.velocity = Vector3.ZERO
	_hint("Под водой. Воздуха — %d с. Собирай находки на дне; [F] у троса буя — всплыть." % int(AIR), 6.0)


## Всплыть на берег, где нырял.
func surface(p, no_air := false) -> void:
	if not divers.has(p):
		return
	var d: Dictionary = divers[p]
	divers.erase(p)
	if d["light"] != null and is_instance_valid(d["light"]):
		d["light"].queue_free()
	if is_instance_valid(p):
		p.global_position = (d["back"] as Vector3) + Vector3(0, 0.3, 0)
		p.velocity = Vector3.ZERO
	_hint("Воздух кончился — пришлось всплыть." if no_air else "Всплыл.", 3.0)


func _process(delta: float) -> void:
	regen_t += delta
	for p in divers.keys():
		if not is_instance_valid(p):
			divers.erase(p)
			continue
		divers[p]["air"] -= delta
		if divers[p]["air"] <= 0.0:
			surface(p, true)
	_overlay()


## Синий фильтр и запас воздуха — пока под водой игрок этого экрана.
func _overlay() -> void:
	var me = game.player if game else null
	var on := me != null and divers.has(me)
	if not on:
		if tint:
			tint.visible = false
		return
	if tint == null:
		tint = CanvasLayer.new()
		tint.layer = 3
		var cr := ColorRect.new()
		cr.color = Color(0.04, 0.22, 0.36, 0.38)
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tint.add_child(cr)
		air_l = Label.new()
		air_l.add_theme_font_size_override("font_size", 26)
		air_l.add_theme_color_override("font_outline_color", Color.BLACK)
		air_l.add_theme_constant_override("outline_size", 6)
		air_l.set_anchors_preset(Control.PRESET_CENTER_TOP)
		air_l.position = Vector2(-90, 18)
		tint.add_child(air_l)
		add_child(tint)
	tint.visible = true
	var a: float = divers[me]["air"]
	air_l.text = "Воздух: %d с" % ceili(a)
	air_l.modulate = Color(1.0, 0.35, 0.3) if a < 10.0 else Color(0.75, 0.95, 1.0)


func _hint(text: String, t := 4.0) -> void:
	if game and game.village:
		game.village.hint(text, t)


## Разложить находки на дне: при первом погружении — полный набор, потом по одной раз в REGEN с.
func _top_up() -> void:
	loot = loot.filter(func(x): return is_instance_valid(x) and not x.taken)
	var add := MAX_LOOT if not started else int(regen_t / REGEN)
	started = true
	if add > 0:
		regen_t = 0.0
	add = mini(add, MAX_LOOT - loot.size())
	var total := 0
	for e in LOOT:
		total += int(e[3])
	for i in add:
		var r := randi() % total
		var e: Array = LOOT[0]
		for x in LOOT:
			r -= int(x[3])
			if r < 0:
				e = x
				break
		var a := randf() * TAU
		var rad := randf_range(3.0, FLOOR_R - 1.5)
		var pos := bottom_c() + Vector3(cos(a) * rad, 0.4, sin(a) * rad)
		loot.append(game._make_pickup(String(e[0]), randi_range(int(e[1]), int(e[2])), pos, Vector3.ZERO))


func _mat(c: Color, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _mesh(m: Mesh, mat: Material, p: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = p
	mi.rotation = rot
	bottom.add_child(mi)
	return mi


func _solid(center_: Vector3, size: Vector3, yaw := 0.0) -> void:
	var b := StaticBody3D.new()
	b.position = center_
	b.rotation.y = yaw
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	bottom.add_child(b)


## Дно озера: ил, стенки, «поверхность» над головой, камни, водоросли, затонувшая лодка, трос буя, свет.
func _build_bottom() -> void:
	bottom = Node3D.new()
	bottom.name = "LakeBottom"
	get_parent().add_child(bottom)
	var c := bottom_c()
	var h := 8.0
	var fl := CylinderMesh.new()
	fl.top_radius = FLOOR_R + 1.0
	fl.bottom_radius = FLOOR_R + 1.0
	fl.height = 0.2
	_mesh(fl, _mat(Color(0.2, 0.22, 0.16)), c - Vector3(0, 0.1, 0))
	_solid(c - Vector3(0, 0.6, 0), Vector3(FLOOR_R * 2.0 + 4.0, 1.0, FLOOR_R * 2.0 + 4.0))
	var wall := CylinderMesh.new()
	wall.top_radius = FLOOR_R + 0.5
	wall.bottom_radius = FLOOR_R + 1.0
	wall.height = h
	wall.cap_top = false
	wall.cap_bottom = false
	wall.radial_segments = 40
	_mesh(wall, _mat(Color(0.08, 0.2, 0.22)), c + Vector3(0, h / 2.0, 0))
	for i in 20:
		var a := TAU * float(i) / 20.0
		_solid(c + Vector3(cos(a) * (FLOOR_R + 0.3), h / 2.0, sin(a) * (FLOOR_R + 0.3)), Vector3(1.0, h, 4.6), -a)
	_solid(c + Vector3(0, h + 0.5, 0), Vector3(FLOOR_R * 2.0 + 4.0, 1.0, FLOOR_R * 2.0 + 4.0))
	var top := PlaneMesh.new()
	top.size = Vector2(FLOOR_R * 2.0 + 2.0, FLOOR_R * 2.0 + 2.0)
	var tm := _mat(Color(0.3, 0.6, 0.7), 0.1)
	tm.emission_enabled = true
	tm.emission = Color(0.12, 0.3, 0.38)
	_mesh(top, tm, c + Vector3(0, h - 0.05, 0))
	# камни и водоросли
	var rock_m := _mat(Color(0.25, 0.27, 0.25))
	var weed_m := _mat(Color(0.16, 0.36, 0.18))
	for i in 14:
		var a := randf() * TAU
		var r := randf_range(4.0, FLOOR_R - 0.5)
		var sm := SphereMesh.new()
		sm.radius = randf_range(0.3, 0.9)
		sm.height = sm.radius * 1.2
		_mesh(sm, rock_m, c + Vector3(cos(a) * r, 0.1, sin(a) * r))
	for i in 40:
		var a := randf() * TAU
		var r := randf_range(2.5, FLOOR_R)
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.05
		cm.height = randf_range(0.8, 2.4)
		_mesh(cm, weed_m, c + Vector3(cos(a) * r, cm.height / 2.0, sin(a) * r), Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3)))
	# затонувшая лодка
	var boat_m := _mat(Color(0.28, 0.2, 0.12))
	var bp := c + Vector3(-6.0, 0.0, 4.0)
	var bb := BoxMesh.new()
	bb.size = Vector3(1.4, 0.15, 3.6)
	_mesh(bb, boat_m, bp + Vector3(0, 0.15, 0), Vector3(0, 0.6, 0.25))
	_solid(bp + Vector3(0, 0.3, 0), Vector3(1.4, 0.6, 3.6), 0.6)
	# трос буя — [F] всплыть
	var rope := Rope.new()
	rope.dive = self
	rope.position = c + Vector3(0, h / 2.0, 0)
	var rcs := CollisionShape3D.new()
	var rs := CylinderShape3D.new()
	rs.radius = 0.25
	rs.height = h
	rcs.shape = rs
	rope.add_child(rcs)
	bottom.add_child(rope)
	var rm := CylinderMesh.new()
	rm.top_radius = 0.04
	rm.bottom_radius = 0.04
	rm.height = h
	var rope_m := _mat(Color(0.9, 0.55, 0.15))
	rope_m.emission_enabled = true
	rope_m.emission = Color(0.5, 0.25, 0.05)
	_mesh(rm, rope_m, c + Vector3(0, h / 2.0, 0))
	var anchor := BoxMesh.new()
	anchor.size = Vector3(0.6, 0.4, 0.6)
	_mesh(anchor, _mat(Color(0.3, 0.3, 0.32)), c + Vector3(0, 0.2, 0))
	# мутный свет сверху
	var l := OmniLight3D.new()
	l.light_color = Color(0.45, 0.75, 0.9)
	l.omni_range = FLOOR_R * 2.2
	l.light_energy = 0.9
	l.position = c + Vector3(0, h - 1.0, 0)
	bottom.add_child(l)
