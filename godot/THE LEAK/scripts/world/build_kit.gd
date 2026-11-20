extends RefCounted
## Общие постройки по чертежам (промпт 20.11 18:32): модели без привязки к месту — их ставят бункер (bunker_home.gd)
## и лагерь у озера (village/lake_camp.gd). make(id, game) возвращает узел в начале координат, родитель ставит
## position/rotation и add_child. Описания/цены чертежей — BLUEPRINTS ниже (bunker_home.gd берёт их к себе).
const Turret := preload("res://scripts/world/scrap_turret.gd")

## [id, название, описание, цена чертежа, материалы {id: штук}, нужен верстак, нужен инструмент (не тратится)]
const BLUEPRINTS := [
	["turret", "Кустарная турель", "Самопал из трубы на треноге: сам стреляет по врагам в 13 м слабыми выстрелами пистолетных патронов. F — зарядить (до 40).",
		70, {"pipe": 1, "scrap": 3, "nut": 4, "tape": 1}, true, ""],
	["sandbags", "Мешки с песком", "Полукруглая баррикада по пояс: за ней удобно прятаться, враги обходят.",
		25, {"twine": 2, "scrap": 1}, true, ""],
	["rack", "Стеллаж", "Железный стеллаж у стены с банками, ящиками и канистрой — порядок и уют.",
		30, {"scrap": 3, "nut": 2, "wood": 2}, true, ""],
	["lamp", "Лампа под потолком", "Лампочка в жестяном абажуре на проводе: тёплый свет на всю комнату.",
		35, {"scrap": 1, "tape": 1}, true, ""],
]


## Узел постройки (без позиции). game нужен турели. Неизвестный id — null.
static func make(id: String, game) -> Node3D:
	match id:
		"turret":
			var t := Turret.new()
			t.game = game
			return t
		"sandbags":
			return _sandbags()
		"rack":
			return _rack()
		"lamp":
			return _lamp()
	return null


static func _m(c: Color, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


static func _box(p: Node3D, size: Vector3, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	p.add_child(mi)
	return mi


static func _col(b: CollisionObject3D, size: Vector3, pos: Vector3, rot := Vector3.ZERO) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	cs.rotation = rot
	b.add_child(cs)


## Мешки с песком: дуга из трёх рядов мешков (капсулы-приплюснутые боксы), высота ~0.9 м, ширина ~2 м.
static func _sandbags() -> Node3D:
	var b := StaticBody3D.new()
	var r := RandomNumberGenerator.new()
	r.seed = 3218
	for row in 3:
		var n := 5 - row
		for k in n:
			var t := (k - (n - 1) / 2.0) / 5.0
			var a := t * 1.1
			var m := _m(Color(0.55, 0.48, 0.33).darkened(r.randf() * 0.15), 1.0)
			_box(b, Vector3(0.44, 0.24, 0.3), Vector3(sin(a) * 2.0, 0.13 + row * 0.25, 2.0 - cos(a) * 2.0 - 0.2),
					m, Vector3(r.randf_range(-0.05, 0.05), -a + r.randf_range(-0.1, 0.1), r.randf_range(-0.04, 0.04)))
	_col(b, Vector3(2.1, 0.8, 0.45), Vector3(0, 0.4, -0.08))
	return b


## Стеллаж: 4 стойки, 3 полки, на полках банки, ящик и канистра.
static func _rack() -> Node3D:
	var b := StaticBody3D.new()
	var steel := _m(Color(0.32, 0.36, 0.34), 0.55, 0.6)
	for sx in [-0.55, 0.55]:
		for sz in [-0.2, 0.2]:
			_box(b, Vector3(0.04, 1.8, 0.04), Vector3(sx, 0.9, sz), steel)
	for y in [0.15, 0.8, 1.45]:
		_box(b, Vector3(1.14, 0.03, 0.44), Vector3(0, y, 0), steel)
	var jar := _m(Color(0.6, 0.55, 0.3), 0.3, 0.2)
	for k in 4:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.05
		cm.bottom_radius = 0.05
		cm.height = 0.14
		mi.mesh = cm
		mi.material_override = jar
		mi.position = Vector3(-0.4 + k * 0.17, 0.89, 0.05)
		b.add_child(mi)
	_box(b, Vector3(0.4, 0.25, 0.32), Vector3(0.25, 1.59, 0), _m(Color(0.45, 0.33, 0.2)))
	_box(b, Vector3(0.3, 0.38, 0.16), Vector3(-0.3, 0.36, 0), _m(Color(0.5, 0.15, 0.1), 0.6, 0.3))
	_box(b, Vector3(0.36, 0.2, 0.3), Vector3(0.25, 0.27, 0), _m(Color(0.35, 0.37, 0.25)))
	_col(b, Vector3(1.2, 1.8, 0.48), Vector3(0, 0.9, 0))
	return b


## Лампа: провод сверху вниз 0.8 м, жестяной абажур, тёплая лампочка с OmniLight. Узел ставить в точку потолка.
static func _lamp() -> Node3D:
	var root := Node3D.new()
	_box(root, Vector3(0.012, 0.8, 0.012), Vector3(0, -0.4, 0), _m(Color(0.1, 0.1, 0.1)))
	var shade := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.06
	cm.bottom_radius = 0.22
	cm.height = 0.16
	shade.mesh = cm
	shade.material_override = _m(Color(0.3, 0.38, 0.3), 0.5, 0.5)
	shade.position = Vector3(0, -0.86, 0)
	root.add_child(shade)
	var bulb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.1
	bulb.mesh = sm
	var bm := _m(Color(1.0, 0.9, 0.6))
	bm.emission_enabled = true
	bm.emission = Color(1.0, 0.8, 0.5)
	bm.emission_energy_multiplier = 3.0
	bulb.material_override = bm
	bulb.position = Vector3(0, -0.95, 0)
	root.add_child(bulb)
	var l := OmniLight3D.new()
	l.position = Vector3(0, -1.0, 0)
	l.light_color = Color(1.0, 0.82, 0.55)
	l.light_energy = 1.4
	l.omni_range = 7.0
	l.shadow_enabled = true
	root.add_child(l)
	return root
