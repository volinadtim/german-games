extends RefCounted
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
	"key": {"name": "Ржавый ключ", "desc": "Открывает сейф в юго-восточной комнате.", "stack": 1,
		"icon": "key", "color": Color(0.62, 0.42, 0.26)},
	"knuckles": {"name": "Кастет", "desc": "Надеть: удары в полтора раза сильнее.", "stack": 1,
		"icon": "knuckles", "color": Color(0.58, 0.58, 0.6)},
	"nut": {"name": "Гайка", "desc": "Бесполезный хлам. Можно выбросить.", "stack": 20,
		"icon": "nut", "color": Color(0.46, 0.46, 0.46)},
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
		"key":
			var w := maxf(2.0, s * 0.07)
			ci.draw_arc(c + Vector2(-s * 0.2, 0), s * 0.13, 0.0, TAU, 20, col, w, true)
			ci.draw_line(c + Vector2(-s * 0.07, 0), c + Vector2(s * 0.34, 0), col, w)
			ci.draw_line(c + Vector2(s * 0.22, 0), c + Vector2(s * 0.22, s * 0.12), col, w)
			ci.draw_line(c + Vector2(s * 0.31, 0), c + Vector2(s * 0.31, s * 0.09), col, w)
		"knuckles":
			ci.draw_rect(Rect2(c + Vector2(-s * 0.34, s * 0.04), Vector2(s * 0.68, s * 0.14)), dark)
			for k in 4:
				var p := c + Vector2((k - 1.5) * s * 0.17, -s * 0.06)
				ci.draw_arc(p, s * 0.075, 0.0, TAU, 14, col, maxf(2.0, s * 0.045), true)
		"nut":
			var pts := PackedVector2Array()
			for k in 6:
				var a := TAU * k / 6.0 + PI / 6.0
				pts.append(c + Vector2(cos(a), sin(a)) * s * 0.3)
			ci.draw_colored_polygon(pts, col)
			ci.draw_circle(c, s * 0.12, Color(0.08, 0.08, 0.08))


## Маленькая 3D-модель предмета (для лежащих на полу вещей).
static func make_mesh(id: String) -> MeshInstance3D:
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
		"key":
			var bm := BoxMesh.new()
			bm.size = Vector3(0.15, 0.015, 0.04)
			mi.mesh = bm
			m.metallic = 0.6
			m.emission_energy_multiplier = 0.6
		"knuckles":
			var bm := BoxMesh.new()
			bm.size = Vector3(0.13, 0.03, 0.05)
			mi.mesh = bm
			m.metallic = 0.8
			m.roughness = 0.4
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
