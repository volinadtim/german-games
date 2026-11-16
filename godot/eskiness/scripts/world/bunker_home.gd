extends Node3D
## Дом в бункере — северо-западная комната (сундук теперь у магазина). Постройки по чертежам (промпт 15.11 23:10):
## чертёж покупается в Trinkets Market (вкладка «Чертежи»), потом там же или у верстака (E) строится из материалов.
## Всё, кроме верстака и уборки, требует верстак. Состояние — в сейве (game_save.gd: "blueprints"):
## id -> 1 чертёж куплен, 2 построено. Постройки стоят на своих местах в комнате.
const Items := preload("res://scripts/items.gd")

## внутренние грани стен комнаты (level_geometry.gd: X0 -12, ZN -9, CW 1.6, T 0.3)
const RX0 := -11.85
const RX1 := -0.15
const RZ0 := -8.85
const RZ1 := -1.75
const H := 3.2
const DOOR_X := -6.0     # проём в коридор на южной стене
const DOOR_W := 1.7
const DOOR_H := 2.3
## [id, название, описание, цена чертежа, материалы {id: штук}, нужен верстак, нужен инструмент (не тратится)]
const BLUEPRINTS := [
	["workbench", "Верстак", "Крепкий стол с тисками у стены дома. На нём строится всё остальное; E у верстака — открыть чертежи.",
		25, {"wood": 4, "nut": 2}, false, ""],
	["clean", "Уборка бункера", "Вымести дом: обломки, пыль, мусор и паутина в северо-западной комнате пропадут.",
		15, {}, false, "broom"],
	["wallpaper", "Обои", "Поклеить на стены дома выцветшие обои в цветочек.",
		30, {"tape": 2}, true, ""],
	["rug", "Ковёр", "Старый узорчатый ковёр посреди комнаты.",
		20, {"twine": 2}, true, ""],
	["cot", "Раскладушка", "Раскладушка с одеялом у стены — уютнее, почти как дома.",
		35, {"wood": 3, "scrap": 2}, true, ""],
]

var game
var state := {}          # id -> 1 куплен / 2 построен
var nodes := {}          # id -> построенный узел
var hidden_junk: Array = []


static func info(id: String) -> Array:
	for b in BLUEPRINTS:
		if b[0] == id:
			return b
	return []


func status(id: String) -> int:
	return int(state.get(id, 0))


func buy(id: String) -> void:
	if status(id) == 0:
		state[id] = 1


## Почему нельзя построить ("" — можно).
func build_reason(id: String) -> String:
	var b := info(id)
	if b.is_empty():
		return "Нет такого чертежа."
	if status(id) == 0:
		return "Сначала купи чертёж."
	if status(id) == 2:
		return "Уже построено."
	if bool(b[5]) and status("workbench") != 2:
		return "Нужен верстак."
	if String(b[6]) != "" and game.inv.count(String(b[6])) <= 0:
		return "Нужна %s." % Items.item_name(String(b[6])).to_lower()
	for m in b[4]:
		if game.inv.count(String(m)) < int(b[4][m]):
			return "Не хватает: %s (%d/%d)." % [Items.item_name(String(m)), game.inv.count(String(m)), int(b[4][m])]
	return ""


## Материалы строкой: «Деревяшка ×4, Гайка ×2».
static func materials_text(id: String) -> String:
	var b := info(id)
	var parts: PackedStringArray = []
	for m in b[4]:
		parts.append("%s ×%d" % [Items.item_name(String(m)), int(b[4][m])])
	if String(b[6]) != "":
		parts.append("%s (не тратится)" % Items.item_name(String(b[6])))
	return ", ".join(parts) if not parts.is_empty() else "ничего"


func build(id: String) -> bool:
	if build_reason(id) != "":
		return false
	var b := info(id)
	_apply(id)
	# место постройки занято (сундук/манекен/игрок/другая постройка) — не строим (промпт 16.11 04:28)
	var n = nodes.get(id)
	if n is CollisionObject3D and n != self and game.carry and game.carry.is_blocked(n, n.global_transform):
		nodes.erase(id)
		n.queue_free()
		game.play_ui("buzz", -14.0)
		game.hud.toast("Место для постройки занято — освободи его", Color(1.0, 0.5, 0.4))
		return false
	for m in b[4]:
		game.inv.remove(String(m), int(b[4][m]))
	state[id] = 2
	if game.has_method("play_ui"):
		game.play_ui("thud", -8.0, 0.9)
	return true


func to_save() -> Dictionary:
	return state.duplicate()


func from_save(d: Dictionary) -> void:
	state = {}
	for k in d:
		state[String(k)] = int(d[k])
	for k in state:
		if int(state[k]) == 2:
			_apply(String(k))


func _apply(id: String) -> void:
	if nodes.has(id):
		return
	match id:
		"workbench":
			nodes[id] = _workbench()
		"clean":
			nodes[id] = self
			_clean()
		"wallpaper":
			nodes[id] = _wallpaper()
		"rug":
			nodes[id] = _rug()
		"cot":
			nodes[id] = _cot()


# ---------- постройки ----------

func _mat(c: Color, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _part(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func _collide(body: StaticBody3D, size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	body.add_child(cs)


## Верстак у северной стены: столешница из досок, ножки, полка, тиски, молоток и доска с инструментами.
class Bench extends StaticBody3D:
	var home

	func get_prompt(_game) -> String:
		return "[E] Верстак — чертежи"

	func interact(g) -> void:
		if g.shop and g.shop.has_method("open_tab"):
			g.shop.open_tab(g, g.shop.tab_names().find("Чертежи"))


func _workbench() -> Node3D:
	var b := Bench.new()
	b.home = self
	b.position = Vector3(-8.6, 0.0, RZ0 + 0.4)
	add_child(b)
	var wood := _mat(Color(0.42, 0.29, 0.17))
	var dark := _mat(Color(0.25, 0.17, 0.1))
	var steel := _mat(Color(0.45, 0.46, 0.47), 0.45, 0.7)
	for k in 4:
		_part(b, Vector3(1.6 / 4.0 - 0.01, 0.06, 0.7), Vector3(-0.6 + k * 0.4, 0.88, 0), wood)
	for sx in [-0.74, 0.74]:
		for sz in [-0.3, 0.3]:
			_part(b, Vector3(0.07, 0.85, 0.07), Vector3(sx, 0.425, sz), dark)
	_part(b, Vector3(1.5, 0.04, 0.6), Vector3(0, 0.22, 0), dark)
	# тиски и молоток
	_part(b, Vector3(0.16, 0.12, 0.14), Vector3(0.6, 0.97, 0.18), steel)
	_part(b, Vector3(0.04, 0.04, 0.22), Vector3(0.6, 1.0, 0.32), steel)
	_part(b, Vector3(0.26, 0.03, 0.03), Vector3(-0.3, 0.93, 0.12), dark)
	_part(b, Vector3(0.05, 0.05, 0.1), Vector3(-0.18, 0.94, 0.12), steel)
	# доска с инструментами на стене
	_part(b, Vector3(1.2, 0.7, 0.03), Vector3(0, 1.55, -0.36), _mat(Color(0.5, 0.4, 0.28)))
	for k in 4:
		_part(b, Vector3(0.04, 0.3 - k * 0.04, 0.02), Vector3(-0.4 + k * 0.27, 1.55, -0.33), steel)
	_collide(b, Vector3(1.6, 0.95, 0.75), Vector3(0, 0.475, 0))
	return b


## Уборка: прячем мелкие обломки, пыль, мусор и паутину уровня внутри комнаты (level.gd строит их своими узлами).
func _clean() -> void:
	var level: Node = game.get_parent().get_node_or_null("Level") if game else null
	if level == null:
		return
	for c in level.get_children():
		if c is Decal:
			if _in_room((c as Decal).global_position) and (c as Decal).size.y < 0.5:
				_hide(c)
		elif c is MultiMeshInstance3D:
			var mm: MultiMesh = (c as MultiMeshInstance3D).multimesh
			if mm == null:
				continue
			var xf_root: Transform3D = (c as Node3D).global_transform
			for i in mm.instance_count:
				var t := mm.get_instance_transform(i)
				var p: Vector3 = xf_root * t.origin
				if _in_room(p) and p.y < 0.3:
					mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.0001), t.origin))
		elif c is MeshInstance3D:
			# паутина в углах: треугольник у потолка
			var mi := c as MeshInstance3D
			if mi.mesh is ArrayMesh and mi.mesh.get_aabb().size.y < 1.2:
				var cen: Vector3 = mi.global_transform * mi.mesh.get_aabb().get_center()
				if _in_room(cen) and cen.y > 2.0:
					_hide(c)
		elif c is Node3D and c.get_child_count() >= 1 and c.get_child(0) is MeshInstance3D:
			var m0 := c.get_child(0) as MeshInstance3D
			if m0.mesh is BoxMesh:
				var sz: Vector3 = (m0.mesh as BoxMesh).size
				var p: Vector3 = (c as Node3D).global_position
				if _in_room(p) and p.y < 1.0 and sz.y < 1.0 and maxf(sz.x, sz.z) <= 2.5:
					_hide(c)


func _in_room(p: Vector3) -> bool:
	return p.x > RX0 - 0.2 and p.x < RX1 + 0.2 and p.z > RZ0 - 0.2 and p.z < RZ1 + 0.2


func _hide(n: Node) -> void:
	(n as Node3D).visible = false
	if n is CollisionObject3D:
		(n as CollisionObject3D).collision_layer = 0
		(n as CollisionObject3D).collision_mask = 0
	hidden_junk.append(n)


## Обои: выцветшие полосы с цветочками — процедурная текстура, тонкие панели на 1 см от стен.
func _wallpaper() -> Node3D:
	var root := Node3D.new()
	add_child(root)
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var base := Color(0.62, 0.55, 0.42)
	var stripe := Color(0.52, 0.47, 0.36)
	for y in 64:
		for x in 64:
			@warning_ignore("integer_division")
			var c := stripe if (x / 8) % 2 == 0 else base
			c = c.darkened(randf() * 0.06)
			img.set_pixel(x, y, c)
	# цветочки в шахматном порядке
	for fp in [Vector2i(16, 16), Vector2i(48, 48)]:
		for dx in range(-3, 4):
			for dy in range(-3, 4):
				if absi(dx) + absi(dy) <= 3 and (absi(dx) == 0 or absi(dy) == 0 or absi(dx) + absi(dy) == 2):
					img.set_pixel(fp.x + dx, fp.y + dy, Color(0.55, 0.25, 0.22))
		img.set_pixel(fp.x, fp.y, Color(0.8, 0.7, 0.3))
	# потёки и грязь снизу
	for x in 64:
		for y in range(54, 64):
			img.set_pixel(x, y, img.get_pixel(x, y).darkened(0.12 + (y - 54) * 0.015))
	var tex := ImageTexture.create_from_image(img)
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.9, 0.9, 0.9)
	m.roughness = 0.95
	var e := 0.012
	# западная и восточная стены (вдоль Z), северная (вдоль X), южная — вокруг проёма
	_panel(root, Vector3(RX0 + e, H / 2, (RZ0 + RZ1) / 2), Vector3(0.004, H, RZ1 - RZ0), m)
	_panel(root, Vector3(RX1 - e, H / 2, (RZ0 + RZ1) / 2), Vector3(0.004, H, RZ1 - RZ0), m)
	_panel(root, Vector3((RX0 + RX1) / 2, H / 2, RZ0 + e), Vector3(RX1 - RX0, H, 0.004), m)
	var dl := DOOR_X - DOOR_W / 2
	var dr := DOOR_X + DOOR_W / 2
	_panel(root, Vector3((RX0 + dl) / 2, H / 2, RZ1 - e), Vector3(dl - RX0, H, 0.004), m)
	_panel(root, Vector3((dr + RX1) / 2, H / 2, RZ1 - e), Vector3(RX1 - dr, H, 0.004), m)
	_panel(root, Vector3(DOOR_X, (DOOR_H + H) / 2, RZ1 - e), Vector3(DOOR_W, H - DOOR_H, 0.004), m)
	return root


func _panel(parent: Node3D, pos: Vector3, size: Vector3, m: Material) -> void:
	var mi := _part(parent, size, pos, m)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Ковёр посреди комнаты: бордовый с каймой и ромбом.
func _rug() -> Node3D:
	var root := StaticBody3D.new()   # тонкое тело — чтобы ковёр можно было взять в руки (carry.gd)
	root.position = Vector3(-6.0, 0.0, -5.3)
	add_child(root)
	var img := Image.create(48, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 48:
			var edge := mini(mini(x, 47 - x), mini(y, 31 - y))
			var c := Color(0.42, 0.1, 0.08)
			if edge < 2:
				c = Color(0.65, 0.5, 0.3)
			elif edge < 4:
				c = Color(0.2, 0.08, 0.06)
			elif absf(x - 23.5) / 20.0 + absf(y - 15.5) / 12.0 < 0.75 and absf(x - 23.5) / 20.0 + absf(y - 15.5) / 12.0 > 0.55:
				c = Color(0.75, 0.55, 0.25)
			elif absf(x - 23.5) / 20.0 + absf(y - 15.5) / 12.0 < 0.25:
				c = Color(0.15, 0.25, 0.35)
			img.set_pixel(x, y, c.darkened(randf() * 0.1))
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.roughness = 1.0
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(3.0, 2.0)
	mi.mesh = pm
	mi.material_override = m
	mi.position = Vector3(0, 0.006, 0)
	root.add_child(mi)
	_collide(root, Vector3(3.0, 0.012, 2.0), Vector3(0, 0.006, 0))
	return root


## Раскладушка у восточной стены: рама из трубок, брезент, одеяло и подушка.
func _cot() -> Node3D:
	var b := StaticBody3D.new()
	b.position = Vector3(RX1 - 0.5, 0.0, -6.3)
	add_child(b)
	var steel := _mat(Color(0.35, 0.37, 0.36), 0.5, 0.6)
	var canvas := _mat(Color(0.3, 0.33, 0.22))
	var blanket := _mat(Color(0.45, 0.2, 0.15))
	for sz in [-0.9, 0.9]:
		for sx in [-0.3, 0.3]:
			_part(b, Vector3(0.03, 0.4, 0.03), Vector3(sx, 0.2, sz), steel)
	for sx in [-0.32, 0.32]:
		_part(b, Vector3(0.035, 0.035, 1.9), Vector3(sx, 0.4, 0), steel)
	_part(b, Vector3(0.62, 0.03, 1.85), Vector3(0, 0.41, 0), canvas)
	_part(b, Vector3(0.64, 0.06, 1.1), Vector3(0, 0.45, 0.3), blanket)
	_part(b, Vector3(0.45, 0.09, 0.28), Vector3(0, 0.47, -0.72), _mat(Color(0.75, 0.72, 0.65)))
	_collide(b, Vector3(0.7, 0.5, 1.9), Vector3(0, 0.25, 0))
	return b
