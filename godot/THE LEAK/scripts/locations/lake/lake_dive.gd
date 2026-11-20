extends Node3D
## Озеро в лагере (промпт 20.11 18:33, переделано 20.11 19:07): настоящая чаша глубиной DEPTH прямо под водой.
## Зашёл в воду — плывёшь (без телепорта), к берегу — вылезаешь сам (подтягивание у стенки).
## Без акваланга — только по поверхности. С аквалангом (items.gd: scuba) — ныряешь куда смотришь
## (Пробел — вверх, Ctrl — вниз), воздух AIR с тратится только пока голова под водой; в godmode не тратится.
## Кончился воздух — выталкивает наверх; на поверхности и после выхода из воды всё сбрасывается.
## Под водой — свой туман/свет камеры (_env), подводный фонарь (dive_light) — прожектор от камеры.
## На дне — ценный лут (LOOT, пополняется раз в REGEN с). Игрок зовёт swim_tick из player.gd (группа lake_water).

const AIR := 60.0
const DEPTH := 7.0           # дно ниже воды на столько метров
const LAKE_R := 15.0         # радиус воды (lake_camp.gd: LAKE_R)
const FLOAT := 1.3           # на плаву ноги ниже воды на столько (голова над водой)
const SWIM := 3.2
const SWIM_FAST := 5.2
const MAX_LOOT := 6
const REGEN := 45.0          # раз в столько секунд на дне появляется новая находка
## [id, от, до, вес]
const LOOT := [["coin", 15, 45, 30], ["ammo_box", 1, 1, 10], ["medkit_army", 1, 1, 6], ["filter2", 1, 2, 10],
	["kevlar_helmet", 1, 1, 3], ["plate_vest", 1, 1, 2], ["fire_axe", 1, 1, 3], ["battery", 2, 4, 10], ["energy", 1, 2, 8]]

var center := Vector3.ZERO   # центр воды на уровне поверхности, мировые координаты (lake_camp.gd: LAKE_C + OFF)
var game
var bottom: Node3D           # чаша озера (top_level, мировые координаты)
var sw := {}                 # player -> {"air", "under", "light", "spot", "climb", "warned"}
var loot: Array = []         # лежащие на дне pickup.gd
var regen_t := 0.0
var started := false
var tint: CanvasLayer
var air_l: Label


func _ready() -> void:
	add_to_group("lake_water")
	_build_bottom()


## Уровень воды (мир).
func surf() -> float:
	return center.y + 0.04


## Центр дна.
func bottom_c() -> Vector3:
	return Vector3(center.x, surf() - DEPTH, center.z)


## Плавание игрока p за кадр. false — игрок не в воде (обычная физика player.gd).
func swim_tick(p, delta: float) -> bool:
	var pos: Vector3 = p.global_position
	var sy := surf()
	var inside := Vector2(pos.x - center.x, pos.z - center.z).length() < LAKE_R - 0.15 \
		and pos.y < sy - 0.25 and pos.y > sy - DEPTH - 3.0
	if not inside:
		if sw.has(p):
			_leave(p)
		return false
	if game == null:
		game = p.game
	if not sw.has(p):
		sw[p] = {"air": AIR, "under": false, "light": null, "spot": null, "climb": 0.0, "warned": false}
	var s: Dictionary = sw[p]
	var scuba: bool = game != null and game.inv != null and game.inv.count("scuba") > 0
	var can_dive: bool = scuba and float(s["air"]) > 0.0
	var float_y := sy - FLOAT
	var inp := Vector2.ZERO
	var up := 0.0
	var fast := false
	if p.active:
		inp = p.ia.get_vector("move_left", "move_right", "move_forward", "move_back")
		if p.ia.is_action_pressed("jump"):
			up += 1.0
		if p.ia.is_action_pressed("crouch"):
			up -= 1.0
		fast = p.ia.is_action_pressed("sprint")
	var dir: Vector3
	if can_dive:
		var b: Basis = p.cam.global_transform.basis
		dir = b.x * inp.x + b.z * inp.y   # плывём куда смотрим
	else:
		dir = p.global_transform.basis * Vector3(inp.x, 0, inp.y)
		if up < 0.0 and not s["warned"] and p == (game.player if game else null):
			s["warned"] = true
			_hint("Без акваланга не нырнуть — только плавать. Акваланг — Trinkets Market #3." if not scuba
				else "Воздуха нет — всплыви, баллон наполнится.", 4.0)
	dir.y += up
	if dir.length() > 1.0:
		dir = dir.normalized()
	var target := dir * (SWIM_FAST if fast else SWIM)
	if not can_dive:
		target.y = clampf((float_y - pos.y) * 3.0, -2.0, 3.0)   # держит на поверхности / выталкивает
	elif pos.y > float_y - 0.15 and target.y > -0.3:
		target.y = minf(target.y, (float_y - pos.y) * 3.0)      # выше поверхности не выплыть
	s["climb"] = maxf(0.0, float(s["climb"]) - delta)
	if p.is_on_wall() and inp.length() > 0.1 and pos.y > float_y - 0.5:
		s["climb"] = 0.35   # у стенки на поверхности — подтянуться на берег
	if float(s["climb"]) > 0.0:
		var push: Vector3 = p.global_transform.basis * Vector3(inp.x, 0, inp.y)
		p.velocity = Vector3(push.x * 3.0, 6.5, push.z * 3.0)
	else:
		p.velocity = p.velocity.lerp(target, 1.0 - exp(-4.0 * delta))
	p.move_and_slide()
	p._animate(delta, p.global_transform.basis.inverse() * p.velocity, false)
	# голова под водой: воздух, туман, фонарь
	var under: bool = p.cam.global_position.y < sy
	if under and can_dive and not (game != null and game.god):
		s["air"] = float(s["air"]) - delta
		if float(s["air"]) <= 0.0:
			s["air"] = 0.0
			s["warned"] = false
			_hint("Воздух кончился — всплывай!", 3.0)
	if not under and scuba:
		s["air"] = AIR   # на поверхности баллон снова полный
		s["warned"] = false
	if under != bool(s["under"]):
		s["under"] = under
		_set_under(p, s, under)
	return true


## Голова ушла под воду / вынырнула: туман камеры и фонарь.
func _set_under(p, s: Dictionary, on: bool) -> void:
	if on:
		p.cam.environment = _env(p)
		if game and game.inv and game.inv.count("dive_light") > 0:
			var sp := SpotLight3D.new()
			sp.light_color = Color(0.85, 0.95, 1.0)
			sp.spot_range = 18.0
			sp.spot_angle = 32.0
			sp.light_energy = 3.0
			p.cam.add_child(sp)
			s["spot"] = sp
			var l := OmniLight3D.new()
			l.light_color = Color(0.7, 0.9, 1.0)
			l.omni_range = 5.0
			l.light_energy = 0.8
			p.cam.add_child(l)
			s["light"] = l
	else:
		if is_instance_valid(p.cam):
			p.cam.environment = null
		for k in ["spot", "light"]:
			if s[k] != null and is_instance_valid(s[k]):
				s[k].queue_free()
			s[k] = null


## Подводное окружение: копия обычного, мутно-зелёный туман на ~25 м, рассеянный свет — видно и ночью.
func _env(p) -> Environment:
	var src: Environment = p.cam.get_world_3d().environment if p.cam.get_world_3d() else null
	var e: Environment = src.duplicate() if src else Environment.new()
	var fog := Color(0.16, 0.42, 0.46)
	e.background_mode = Environment.BG_COLOR
	e.background_color = fog
	e.fog_enabled = true
	e.fog_light_color = fog
	e.fog_light_energy = 1.0
	e.fog_density = 0.03   # ~30 м видно (промпт 19:11 — светлее и дальше)
	e.fog_height_density = 0.0
	e.fog_sky_affect = 1.0
	e.fog_aerial_perspective = 0.0
	e.volumetric_fog_enabled = false
	e.ssr_enabled = false
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.8, 0.82)
	e.ambient_light_energy = 1.3
	return e


## Вышел из воды: фонарь, туман и воздух — как до озера.
func _leave(p) -> void:
	var s: Dictionary = sw[p]
	sw.erase(p)
	if is_instance_valid(p):
		_set_under(p, s, false)


func _process(delta: float) -> void:
	for p in sw.keys():
		if not is_instance_valid(p):
			sw.erase(p)
	if game != null:
		regen_t += delta
		if not started or regen_t >= REGEN:
			_top_up()
	_overlay()


## Лёгкий синий фильтр и запас воздуха — пока голова под водой у игрока этого экрана.
func _overlay() -> void:
	var me = game.player if game else null
	var on: bool = me != null and sw.has(me) and bool(sw[me]["under"])
	if not on:
		if tint:
			tint.visible = false
		return
	if tint == null:
		tint = CanvasLayer.new()
		tint.layer = 3
		var cr := ColorRect.new()
		cr.color = Color(0.05, 0.3, 0.4, 0.08)
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
	var a: float = sw[me]["air"]
	air_l.visible = game.inv != null and game.inv.count("scuba") > 0
	air_l.text = "Воздух: ∞" if game.god else "Воздух: %d с" % ceili(a)
	air_l.modulate = Color(1.0, 0.35, 0.3) if a < 10.0 and not game.god else Color(0.75, 0.95, 1.0)


func _hint(text: String, t := 4.0) -> void:
	if game and game.village:
		game.village.hint(text, t)


## Разложить находки на дне: в первый раз — полный набор, потом по одной раз в REGEN с.
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
		var rad := randf_range(2.0, LAKE_R - 2.0)
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


## Чаша озера под водой: дно, стенки (коллизия — толстые плиты до края дыры в земле лагеря, lake_camp.gd: _ground),
## «потолок» воды снизу, камни, водоросли, затонувшая лодка, мутный свет.
func _build_bottom() -> void:
	bottom = Node3D.new()
	bottom.name = "LakeBottom"
	bottom.top_level = true   # center — в мировых координатах (лагерь сдвинут, lake_camp.gd: OFF)
	add_child(bottom)
	var c := bottom_c()
	var sy := surf()
	var fl := CylinderMesh.new()
	fl.top_radius = LAKE_R + 0.5
	fl.bottom_radius = LAKE_R + 0.5
	fl.height = 0.2
	fl.radial_segments = 40
	_mesh(fl, _mat(Color(0.3, 0.3, 0.2)), c - Vector3(0, 0.1, 0))
	_solid(c - Vector3(0, 0.6, 0), Vector3(LAKE_R * 2.0 + 24.0, 1.0, LAKE_R * 2.0 + 24.0))
	var wall := CylinderMesh.new()
	wall.top_radius = LAKE_R
	wall.bottom_radius = LAKE_R - 0.4
	wall.height = DEPTH
	wall.cap_top = false
	wall.cap_bottom = false
	wall.radial_segments = 48
	_mesh(wall, _mat(Color(0.22, 0.26, 0.2)), c + Vector3(0, DEPTH / 2.0, 0))
	# стенки: 32 плиты от кромки воды наружу на 10 м, верх — уровень земли (закрывают дыру в земле лагеря)
	var top := sy - 0.04
	for i in 32:
		var a := TAU * float(i) / 32.0
		var r := LAKE_R + 5.0
		_solid(Vector3(c.x + cos(a) * r, (top + c.y - 1.0) / 2.0, c.z + sin(a) * r), Vector3(10.0, top - c.y + 1.0, 5.6), -a)
	# поверхность снизу — светлая, видно куда всплывать
	var ceil_m := StandardMaterial3D.new()
	ceil_m.albedo_color = Color(0.35, 0.65, 0.72)
	ceil_m.emission_enabled = true
	ceil_m.emission = Color(0.18, 0.42, 0.5)
	var cp := CylinderMesh.new()
	cp.top_radius = LAKE_R
	cp.bottom_radius = LAKE_R
	cp.height = 0.01
	cp.cap_top = false
	cp.radial_segments = 48
	_mesh(cp, ceil_m, Vector3(c.x, sy - 0.03, c.z))
	# камни и водоросли
	var rock_m := _mat(Color(0.32, 0.34, 0.3))
	var weed_m := _mat(Color(0.2, 0.45, 0.22))
	for i in 14:
		var a := randf() * TAU
		var r := randf_range(3.0, LAKE_R - 1.0)
		var sm := SphereMesh.new()
		sm.radius = randf_range(0.3, 0.9)
		sm.height = sm.radius * 1.2
		_mesh(sm, rock_m, c + Vector3(cos(a) * r, 0.1, sin(a) * r))
	for i in 50:
		var a := randf() * TAU
		var r := randf_range(2.0, LAKE_R - 0.6)
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.05
		cm.height = randf_range(0.8, 3.0)
		_mesh(cm, weed_m, c + Vector3(cos(a) * r, cm.height / 2.0, sin(a) * r), Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3)))
	# затонувшая лодка
	var boat_m := _mat(Color(0.34, 0.25, 0.15))
	var bp := c + Vector3(-6.0, 0.0, 4.0)
	var bb := BoxMesh.new()
	bb.size = Vector3(1.4, 0.15, 3.6)
	_mesh(bb, boat_m, bp + Vector3(0, 0.15, 0), Vector3(0, 0.6, 0.25))
	_solid(bp + Vector3(0, 0.3, 0), Vector3(1.4, 0.6, 3.6), 0.6)
	# мутный свет сверху
	var l := OmniLight3D.new()
	l.light_color = Color(0.5, 0.8, 0.9)
	l.omni_range = LAKE_R * 1.6
	l.light_energy = 2.0
	l.shadow_enabled = false
	l.position = Vector3(c.x, sy - 1.5, c.z)
	bottom.add_child(l)
