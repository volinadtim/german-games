extends RefCounted
const Weapons := preload("res://weapons.gd")
## Справочник предметов (тестовые механики): название, описание, размер стака, иконка и 3D-модель.
## Иконки и модели рисуются кодом, файлов нет.

const ITEMS := {
	"coin": {"name": "Монета", "desc": "Старая монета. Её ест игровой автомат.", "stack": 999,
		"icon": "coin", "color": Color(0.86, 0.66, 0.3)},
	"medkit": {"name": "Аптечка", "desc": "Восстанавливает 50 здоровья.", "stack": 5,
		"icon": "medkit", "color": Color(0.72, 0.16, 0.12), "heal": 50.0},
	"bandage": {"name": "Бинт", "desc": "Восстанавливает 20 здоровья.", "stack": 10,
		"icon": "bandage", "color": Color(0.84, 0.8, 0.7), "heal": 20.0},
	"rusk": {"name": "Сухарь", "desc": "Чёрствый, но съедобный. +8 здоровья.", "stack": 10,
		"icon": "rusk", "color": Color(0.6, 0.42, 0.22), "heal": 8.0},
	"battery": {"name": "Батарейка", "desc": "Полностью заряжает фонарик (F).", "stack": 10,
		"icon": "battery", "color": Color(0.34, 0.44, 0.3)},
	"knuckles": {"name": "Кастет", "desc": "Надеть: удары в полтора раза сильнее.", "stack": 1,
		"icon": "knuckles", "color": Color(0.58, 0.58, 0.6)},
	"canned": {"name": "Тушёнка", "desc": "Банка без этикетки. +30 здоровья.", "stack": 5,
		"icon": "canned", "color": Color(0.55, 0.56, 0.58), "heal": 30.0},
	"water": {"name": "Бутылка воды", "desc": "Мутноватая, но пить можно. +10 здоровья.", "stack": 6,
		"icon": "water", "color": Color(0.45, 0.6, 0.7), "heal": 10.0},
	"pills": {"name": "Обезболивающее", "desc": "Блистер таблеток. +15 здоровья.", "stack": 8,
		"icon": "pills", "color": Color(0.85, 0.85, 0.82), "heal": 15.0},
	"wallet": {"name": "Старый кошелёк", "desc": "Открыть: внутри 10–40 монет.", "stack": 5,
		"icon": "wallet", "color": Color(0.32, 0.2, 0.12)},
	"scrap": {"name": "Металлолом", "desc": "Гнутые железки. Хлам.", "stack": 20,
		"icon": "scrap", "color": Color(0.4, 0.33, 0.28)},
	"gear": {"name": "Шестерёнка", "desc": "Из какого-то механизма. Хлам.", "stack": 20,
		"icon": "gear", "color": Color(0.55, 0.5, 0.4)},
	"tape": {"name": "Изолента", "desc": "Синяя. Хлам, но приятно иметь.", "stack": 10,
		"icon": "tape", "color": Color(0.2, 0.3, 0.6)},
	"photo": {"name": "Старое фото", "desc": "Люди в касках у входа в бункер. Лица выцвели.", "stack": 5,
		"icon": "photo", "color": Color(0.75, 0.68, 0.55)},
	"nut": {"name": "Гайка", "desc": "Бесполезный хлам. Можно выбросить.", "stack": 20,
		"icon": "nut", "color": Color(0.46, 0.46, 0.46)},
	# оружие ближнего боя из магазина (weapons.gd): «использовать» — взять в правую руку
	"bat": {"name": "Бита", "desc": "Деревянная бита. Урон ×2.0, бьёт чуть дальше.", "stack": 1,
		"icon": "bat", "color": Color(0.55, 0.38, 0.22), "weapon": true},
	"pipe": {"name": "Труба", "desc": "Стальная труба. Урон ×2.5.", "stack": 1,
		"icon": "pipe", "color": Color(0.42, 0.43, 0.44), "weapon": true},
	"crowbar": {"name": "Монтировка", "desc": "Тяжёлая, красная. Урон ×3.0.", "stack": 1,
		"icon": "crowbar", "color": Color(0.6, 0.14, 0.1), "weapon": true},
	"machete": {"name": "Мачете", "desc": "Широкий клинок. Урон ×3.6.", "stack": 1,
		"icon": "machete", "color": Color(0.62, 0.63, 0.62), "weapon": true},
	# противогаз (G — надеть/снять) и фильтры к нему
	"gasmask": {"name": "Противогаз", "desc": "G — надеть/снять. Наверху без него плохо.", "stack": 1,
		"icon": "gasmask", "color": Color(0.22, 0.25, 0.2)},
	"filter": {"name": "Фильтр", "desc": "Сменный фильтр противогаза: 90 секунд наверху.", "stack": 10,
		"icon": "filter", "color": Color(0.36, 0.38, 0.3)},
}


static func item_name(id: String) -> String:
	return ITEMS[id]["name"] if ITEMS.has(id) else id


## Иконка предмета в прямоугольнике r (рисуется на любом CanvasItem в его _draw / сигнале draw).
static func draw_icon(ci: CanvasItem, id: String, r: Rect2) -> void:
	if not ITEMS.has(id):
		return
	var c := r.get_center()
	var s := minf(r.size.x, r.size.y)
	var col: Color = ITEMS[id]["color"]
	var dark := col.darkened(0.45)
	if String(ITEMS[id]["icon"]) in ["bat", "pipe", "crowbar", "machete", "gasmask", "filter"]:
		Weapons.draw_icon(ci, String(ITEMS[id]["icon"]), r, col)
		return
	match String(ITEMS[id]["icon"]):
		"coin":
			ci.draw_circle(c, s * 0.34, dark)
			ci.draw_circle(c, s * 0.29, col)
			ci.draw_arc(c, s * 0.19, 0.0, TAU, 24, col.darkened(0.25), maxf(1.5, s * 0.04), true)
			ci.draw_line(c + Vector2(0, -s * 0.1), c + Vector2(0, s * 0.1), col.darkened(0.3), maxf(1.5, s * 0.05))
		"medkit":
			var box := Rect2(c - Vector2(s * 0.38, s * 0.28), Vector2(s * 0.76, s * 0.56))
			ci.draw_rect(box, Color(0.8, 0.77, 0.7))
			ci.draw_rect(Rect2(c - Vector2(s * 0.12, s * 0.38), Vector2(s * 0.24, s * 0.12)), Color(0.35, 0.33, 0.3))
			ci.draw_rect(Rect2(c - Vector2(s * 0.06, s * 0.19), Vector2(s * 0.12, s * 0.38)), col)
			ci.draw_rect(Rect2(c - Vector2(s * 0.19, s * 0.06), Vector2(s * 0.38, s * 0.12)), col)
		"bandage":
			ci.draw_rect(Rect2(c + Vector2(0, s * 0.05), Vector2(s * 0.38, s * 0.16)), col.darkened(0.1))
			ci.draw_circle(c, s * 0.27, col)
			ci.draw_arc(c, s * 0.18, 0.0, TAU, 24, col.darkened(0.2), maxf(1.0, s * 0.03), true)
			ci.draw_circle(c, s * 0.08, col.darkened(0.5))
		"rusk":
			var box := Rect2(c - Vector2(s * 0.32, s * 0.2), Vector2(s * 0.64, s * 0.4))
			ci.draw_rect(box, col)
			ci.draw_rect(box, dark, false, maxf(1.5, s * 0.04))
			for k in 4:
				ci.draw_circle(c + Vector2((k - 1.5) * s * 0.14, (k % 2 - 0.5) * s * 0.12), s * 0.03, dark)
		"battery":
			var body := Rect2(c - Vector2(s * 0.16, s * 0.3), Vector2(s * 0.32, s * 0.64))
			ci.draw_rect(Rect2(c - Vector2(s * 0.07, s * 0.38), Vector2(s * 0.14, s * 0.1)), Color(0.6, 0.6, 0.58))
			ci.draw_rect(body, col)
			ci.draw_rect(Rect2(body.position + Vector2(0, s * 0.42), Vector2(body.size.x, s * 0.22)), Color(0.15, 0.15, 0.15))
			ci.draw_line(c + Vector2(-s * 0.08, -s * 0.06), c + Vector2(s * 0.08, -s * 0.06), Color(0.9, 0.85, 0.6), maxf(1.5, s * 0.04))
			ci.draw_line(c + Vector2(0, -s * 0.14), c + Vector2(0, s * 0.02), Color(0.9, 0.85, 0.6), maxf(1.5, s * 0.04))
		"knuckles":
			ci.draw_rect(Rect2(c + Vector2(-s * 0.34, s * 0.04), Vector2(s * 0.68, s * 0.14)), dark)
			for k in 4:
				var p := c + Vector2((k - 1.5) * s * 0.17, -s * 0.06)
				ci.draw_arc(p, s * 0.075, 0.0, TAU, 14, col, maxf(2.0, s * 0.045), true)
		"canned":
			var box := Rect2(c - Vector2(s * 0.24, s * 0.3), Vector2(s * 0.48, s * 0.6))
			ci.draw_rect(box, col)
			ci.draw_rect(Rect2(box.position + Vector2(0, s * 0.14), Vector2(box.size.x, s * 0.3)), Color(0.5, 0.18, 0.12))
			ci.draw_line(box.position, box.position + Vector2(box.size.x, 0), col.lightened(0.3), maxf(1.5, s * 0.04))
		"water":
			ci.draw_rect(Rect2(c - Vector2(s * 0.06, s * 0.38), Vector2(s * 0.12, s * 0.1)), Color(0.2, 0.4, 0.75))
			ci.draw_rect(Rect2(c - Vector2(s * 0.16, s * 0.27), Vector2(s * 0.32, s * 0.62)), col)
			ci.draw_rect(Rect2(c - Vector2(s * 0.16, s * 0.0), Vector2(s * 0.32, s * 0.35)), col.darkened(0.25))
		"pills":
			var box := Rect2(c - Vector2(s * 0.34, s * 0.22), Vector2(s * 0.68, s * 0.44))
			ci.draw_rect(box, Color(0.7, 0.72, 0.75))
			for k in 6:
				ci.draw_circle(c + Vector2((k % 3 - 1) * s * 0.2, (k / 3 - 0.5) * s * 0.2), s * 0.07, col)
		"wallet":
			var box := Rect2(c - Vector2(s * 0.34, s * 0.24), Vector2(s * 0.68, s * 0.48))
			ci.draw_rect(box, col)
			ci.draw_rect(Rect2(c + Vector2(s * 0.1, -s * 0.08), Vector2(s * 0.24, s * 0.16)), col.lightened(0.15))
			ci.draw_circle(c + Vector2(s * 0.2, 0), s * 0.04, Color(0.8, 0.65, 0.3))
		"scrap":
			ci.draw_line(c + Vector2(-s * 0.3, s * 0.2), c + Vector2(s * 0.1, -s * 0.25), col, maxf(3.0, s * 0.1))
			ci.draw_line(c + Vector2(-s * 0.1, -s * 0.2), c + Vector2(s * 0.3, s * 0.2), col.darkened(0.2), maxf(3.0, s * 0.1))
			ci.draw_rect(Rect2(c + Vector2(-s * 0.25, s * 0.05), Vector2(s * 0.2, s * 0.2)), col.lightened(0.1))
		"gear":
			var pts := PackedVector2Array()
			for k in 16:
				var a := TAU * k / 16.0
				var rr := s * (0.34 if k % 2 == 0 else 0.26)
				pts.append(c + Vector2(cos(a), sin(a)) * rr)
			ci.draw_colored_polygon(pts, col)
			ci.draw_circle(c, s * 0.1, Color(0.08, 0.08, 0.08))
		"tape":
			ci.draw_circle(c, s * 0.32, col)
			ci.draw_circle(c, s * 0.16, Color(0.75, 0.7, 0.6))
			ci.draw_circle(c, s * 0.12, Color(0.08, 0.08, 0.08))
		"photo":
			var box := Rect2(c - Vector2(s * 0.3, s * 0.34), Vector2(s * 0.6, s * 0.68))
			ci.draw_rect(box, col)
			ci.draw_rect(box.grow(-s * 0.06), Color(0.3, 0.27, 0.22))
			ci.draw_circle(c + Vector2(-s * 0.1, -s * 0.06), s * 0.07, col.darkened(0.2))
			ci.draw_circle(c + Vector2(s * 0.1, -s * 0.06), s * 0.07, col.darkened(0.2))
		"nut":
			var pts := PackedVector2Array()
			for k in 6:
				var a := TAU * k / 6.0 + PI / 6.0
				pts.append(c + Vector2(cos(a), sin(a)) * s * 0.3)
			ci.draw_colored_polygon(pts, col)
			ci.draw_circle(c, s * 0.12, Color(0.08, 0.08, 0.08))


## Маленькая 3D-модель предмета (для лежащих на полу вещей).
static func make_mesh(id: String) -> Node3D:
	if id in ["bat", "pipe", "crowbar", "machete", "gasmask", "filter"]:
		var w := Weapons.make(id)
		if id in ["bat", "pipe", "crowbar", "machete"]:
			w.rotation.z = PI / 2   # на полу оружие лежит
		return w
	var col: Color = ITEMS[id]["color"] if ITEMS.has(id) else Color.WHITE
	var mi := MeshInstance3D.new()
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.6
	# лёгкое свечение — чтобы лут было видно в темноте
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 0.25
	match id:
		"coin":
			var cm := CylinderMesh.new()
			cm.top_radius = 0.05
			cm.bottom_radius = 0.05
			cm.height = 0.014
			cm.radial_segments = 16
			mi.mesh = cm
			m.metallic = 0.8
			m.roughness = 0.35
		"medkit":
			var bm := BoxMesh.new()
			bm.size = Vector3(0.24, 0.12, 0.17)
			mi.mesh = bm
			m.albedo_color = Color(0.75, 0.72, 0.66)
			m.emission = col
		"bandage":
			var cm := CylinderMesh.new()
			cm.top_radius = 0.04
			cm.bottom_radius = 0.04
			cm.height = 0.07
			mi.mesh = cm
		"rusk":
			var bm := BoxMesh.new()
			bm.size = Vector3(0.09, 0.035, 0.065)
			mi.mesh = bm
		"battery":
			var cm := CylinderMesh.new()
			cm.top_radius = 0.022
			cm.bottom_radius = 0.022
			cm.height = 0.1
			mi.mesh = cm
		"knuckles":
			var bm := BoxMesh.new()
			bm.size = Vector3(0.13, 0.03, 0.05)
			mi.mesh = bm
			m.metallic = 0.8
			m.roughness = 0.4
		"canned", "water", "tape":
			var cm := CylinderMesh.new()
			cm.top_radius = 0.045 if id != "water" else 0.035
			cm.bottom_radius = cm.top_radius
			cm.height = {"canned": 0.09, "water": 0.22, "tape": 0.04}[id]
			mi.mesh = cm
			m.metallic = 0.6 if id == "canned" else 0.0
		"pills", "wallet", "photo", "scrap":
			var bm := BoxMesh.new()
			bm.size = {"pills": Vector3(0.1, 0.012, 0.06), "wallet": Vector3(0.12, 0.025, 0.09),
				"photo": Vector3(0.1, 0.004, 0.13), "scrap": Vector3(0.18, 0.03, 0.06)}[id]
			mi.mesh = bm
		"gear":
			var cm := CylinderMesh.new()
			cm.top_radius = 0.05
			cm.bottom_radius = 0.05
			cm.height = 0.015
			cm.radial_segments = 12
			mi.mesh = cm
			m.metallic = 0.7
		_:
			var cm := CylinderMesh.new()
			cm.top_radius = 0.03
			cm.bottom_radius = 0.03
			cm.height = 0.02
			cm.radial_segments = 6
			mi.mesh = cm
			m.metallic = 0.7
	mi.material_override = m
	return mi
