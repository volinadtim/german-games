extends RefCounted
## Оружие ближнего боя из магазина: урон (множитель к удару кулаком), дальность, цена и 3D-модель.
## Модель строится кодом; длинная ось — +Y, рукоять в начале координат.

const WEAPONS := {
	"bat": {"mult": 2.0, "reach": 1.5, "price": 40},
	"pipe": {"mult": 2.5, "reach": 1.55, "price": 60},
	"crowbar": {"mult": 3.0, "reach": 1.45, "price": 90},
	"machete": {"mult": 3.6, "reach": 1.5, "price": 140},
	"shield": {"mult": 1.8, "reach": 1.2, "price": 70},   # в левой — блок 50%, в правой — бьют краем
	"knife": {"mult": 2.4, "reach": 1.25, "price": 0},     # крафт: деревяшка + стекло + изолента
	# крафт с молотком (промпт 14.11 19:22)
	"hammer": {"mult": 2.2, "reach": 1.3, "price": 0},     # камень + деревяшка + бечёвка; 6 ударов
	"shiv": {"mult": 2.7, "reach": 1.25, "price": 0},      # молоток + металлолом ×2
	"spiked_club": {"mult": 3.2, "reach": 1.5, "price": 0}, # молоток + деревяшка ×2 + гайки ×3
	"pistol": {"mult": 1.6, "reach": 1.15, "price": 0},     # стреляет gun.gd; это — удар рукоятью (левой)
}

# что продаёт магазин, по порядку
const SHOP := [["bat", 40], ["pipe", 60], ["crowbar", 90], ["machete", 140], ["shield", 70], ["gasmask", 50], ["filter", 25], ["flashlight", 35], ["broom", 30],
	["helmet", 45], ["jacket", 60], ["gloves", 30], ["pants", 35], ["boots", 40], ["backpack", 70],
	# одежда на выбор (промпт 14.11 21:14), подвкладки «Одежды» — shop.gd: CLOTHES
	["ushanka", 15], ["moto_helmet", 90], ["kurtka", 30], ["vest", 120], ["jeans", 20], ["wpants", 55],
	["sneakers", 25], ["tac_gloves", 75]]


static func _m(c: Color, metal := 0.0, rough := 0.7) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m


static func _cyl(root: Node3D, r0: float, r1: float, h: float, y: float, m: Material) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r1
	cm.bottom_radius = r0
	cm.height = h
	cm.radial_segments = 10
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = m
	mi.position.y = y
	root.add_child(mi)
	return mi


static func _box(root: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	root.add_child(mi)
	return mi


static func make(id: String) -> Node3D:
	var root := Node3D.new()
	match id:
		"bat":
			var wood := _m(Color(0.55, 0.38, 0.22))
			_cyl(root, 0.017, 0.017, 0.2, -0.02, _m(Color(0.12, 0.1, 0.09)))     # обмотка рукояти
			_cyl(root, 0.018, 0.036, 0.55, 0.32, wood)
			_cyl(root, 0.036, 0.03, 0.08, 0.63, wood)
		"pipe":
			var steel := _m(Color(0.36, 0.37, 0.38), 0.8, 0.45)
			_cyl(root, 0.02, 0.02, 0.75, 0.25, steel)
			_cyl(root, 0.027, 0.027, 0.06, 0.6, steel)                            # муфта на конце
			_cyl(root, 0.022, 0.022, 0.14, -0.06, _m(Color(0.15, 0.2, 0.35)))     # изолента на рукояти
		"crowbar":
			var red := _m(Color(0.55, 0.12, 0.08), 0.6, 0.5)
			_cyl(root, 0.013, 0.013, 0.66, 0.24, red)
			var hook := _box(root, Vector3(0.025, 0.12, 0.025), Vector3(0, 0.6, -0.04), red)
			hook.rotation.x = 0.9
			var tip := _box(root, Vector3(0.03, 0.06, 0.012), Vector3(0, -0.12, 0.02), red)
			tip.rotation.x = -0.4
		"machete":
			_cyl(root, 0.017, 0.017, 0.15, -0.03, _m(Color(0.08, 0.07, 0.06)))
			_box(root, Vector3(0.06, 0.012, 0.012), Vector3(0, 0.05, 0), _m(Color(0.3, 0.3, 0.3), 0.7, 0.5))
			var blade := _box(root, Vector3(0.045, 0.45, 0.004), Vector3(0.008, 0.29, 0), _m(Color(0.62, 0.63, 0.62), 0.9, 0.3))
			blade.rotation.z = -0.03
		"shield":
			# щит из листа железа на деревянной основе; лицо — +Z, верх — +Y, начало — у ремня на предплечье
			var plate := _m(Color(0.32, 0.33, 0.34), 0.7, 0.45)
			var wood := _m(Color(0.35, 0.24, 0.14))
			var rust := _m(Color(0.4, 0.2, 0.1), 0.4, 0.7)
			_box(root, Vector3(0.34, 0.46, 0.012), Vector3(0, 0.05, 0.045), wood)
			_box(root, Vector3(0.32, 0.44, 0.008), Vector3(0, 0.05, 0.056), plate)
			for sy in [-1.0, 1.0]:
				_box(root, Vector3(0.35, 0.025, 0.02), Vector3(0, 0.05 + 0.225 * sy, 0.055), rust)
			for sx in [-1.0, 1.0]:
				_box(root, Vector3(0.025, 0.47, 0.02), Vector3(0.17 * sx, 0.05, 0.055), rust)
			var boss := _cyl(root, 0.05, 0.05, 0.02, 0.0, plate)
			boss.rotation.x = PI / 2
			boss.position = Vector3(0, 0.05, 0.068)
			_box(root, Vector3(0.06, 0.14, 0.02), Vector3(0, 0.0, 0.025), _m(Color(0.12, 0.1, 0.08)))
		"pistol":
			# рукоять — в кулаке (вдоль +Y), затвор и ствол — сверху, вперёд по +X; потёртая воронёная сталь
			var blk := _m(Color(0.3, 0.3, 0.29), 0.75, 0.5)
			var worn := _m(Color(0.5, 0.49, 0.46), 0.85, 0.35)
			var grip := _box(root, Vector3(0.03, 0.11, 0.026), Vector3(-0.005, 0.045, 0), _m(Color(0.14, 0.1, 0.07), 0.0, 0.8))
			grip.rotation.z = -0.25
			_box(root, Vector3(0.17, 0.032, 0.026), Vector3(0.055, 0.112, 0), blk)
			_box(root, Vector3(0.12, 0.004, 0.027), Vector3(0.07, 0.128, 0), worn)     # стёртая кромка затвора
			_box(root, Vector3(0.16, 0.02, 0.022), Vector3(0.05, 0.088, 0), worn)
			var mz := _cyl(root, 0.007, 0.007, 0.012, 0.0, _m(Color(0.05, 0.05, 0.05)))
			mz.rotation.z = PI / 2
			mz.position = Vector3(0.14, 0.11, 0)
			var tg := _box(root, Vector3(0.04, 0.006, 0.01), Vector3(0.035, 0.062, 0), blk)
			tg.rotation.z = 0.2
			_box(root, Vector3(0.006, 0.02, 0.01), Vector3(0.03, 0.072, 0), worn)        # спуск
		"hammer":
			# палка, на конце камень, примотанный бечёвкой
			_cyl(root, 0.016, 0.014, 0.42, 0.13, _m(Color(0.5, 0.36, 0.2)))
			var st := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.06
			sm.height = 0.1
			sm.radial_segments = 8
			sm.rings = 4
			st.mesh = sm
			st.material_override = _m(Color(0.46, 0.45, 0.42), 0.0, 0.9)
			st.position = Vector3(0, 0.34, 0)
			st.scale = Vector3(1.4, 0.9, 1.0)
			root.add_child(st)
			for k in 3:
				_cyl(root, 0.019, 0.019, 0.012, 0.28 + k * 0.02, _m(Color(0.7, 0.6, 0.4)))
		"shiv":
			# рукоять из тряпки, жало — заострённая ржавая пластина
			_cyl(root, 0.016, 0.016, 0.11, 0.02, _m(Color(0.3, 0.26, 0.2)))
			var bl := MeshInstance3D.new()
			var pm := PrismMesh.new()
			pm.size = Vector3(0.04, 0.2, 0.008)
			bl.mesh = pm
			bl.material_override = _m(Color(0.5, 0.48, 0.46), 0.7, 0.45)
			bl.position = Vector3(0, 0.17, 0)
			root.add_child(bl)
		"spiked_club":
			# сбитые доски, из которых торчат болты
			var wood2 := _m(Color(0.45, 0.32, 0.2))
			_box(root, Vector3(0.05, 0.62, 0.035), Vector3(-0.012, 0.28, 0), wood2)
			_box(root, Vector3(0.04, 0.4, 0.03), Vector3(0.02, 0.4, 0.01), _m(Color(0.4, 0.28, 0.17)))
			var steel := _m(Color(0.5, 0.5, 0.5), 0.8, 0.4)
			for k in 6:
				var nl := _cyl(root, 0.005, 0.005, 0.08, 0.0, steel)
				nl.rotation.z = PI / 2 if k % 2 == 0 else 0.0
				nl.rotation.x = 0.0 if k % 2 == 0 else PI / 2
				nl.position = Vector3(0.0, 0.3 + k * 0.05, 0.0)
		"knife":
			# рукоять — деревяшка, примотанная изолентой к осколку стекла
			_box(root, Vector3(0.03, 0.14, 0.022), Vector3(0, 0.02, 0), _m(Color(0.5, 0.35, 0.2)))
			_cyl(root, 0.021, 0.021, 0.035, 0.03, _m(Color(0.15, 0.22, 0.5), 0.0, 0.4))
			_cyl(root, 0.021, 0.021, 0.03, 0.085, _m(Color(0.15, 0.22, 0.5), 0.0, 0.4))
			var gl := _m(Color(0.62, 0.8, 0.78, 0.55), 0.2, 0.05)
			gl.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			gl.cull_mode = BaseMaterial3D.CULL_DISABLED
			var pm := PrismMesh.new()
			pm.size = Vector3(0.04, 0.17, 0.006)
			pm.left_to_right = 0.3
			var bl := MeshInstance3D.new()
			bl.mesh = pm
			bl.material_override = gl
			bl.position.y = 0.17
			root.add_child(bl)
		"gasmask":
			# «Нюхич»: резиновый шлем-маска, два круглых окуляра в стальных обоймах, гофрированный шланг к банке фильтра
			var rub := _m(Color(0.1, 0.11, 0.1), 0.0, 0.55)
			var face := SphereMesh.new()
			face.radius = 0.1
			face.height = 0.22
			var mi := MeshInstance3D.new()
			mi.mesh = face
			mi.material_override = rub
			mi.scale = Vector3(1.0, 1.0, 0.85)
			root.add_child(mi)
			var steel := _m(Color(0.32, 0.33, 0.31), 0.8, 0.35)
			var glass := _m(Color(0.35, 0.45, 0.38, 0.75), 0.3, 0.05)
			glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			for sx in [-0.042, 0.042]:
				var ring := MeshInstance3D.new()
				var tm := TorusMesh.new()
				tm.inner_radius = 0.022
				tm.outer_radius = 0.032
				tm.rings = 12
				tm.ring_segments = 6
				ring.mesh = tm
				ring.material_override = steel
				ring.rotation.x = PI / 2
				ring.position = Vector3(sx, 0.03, -0.08)
				root.add_child(ring)
				var g := _cyl(root, 0.023, 0.023, 0.006, 0.0, glass)
				g.rotation.x = PI / 2
				g.position = Vector3(sx, 0.03, -0.08)
			# клапан на носу
			var v := _cyl(root, 0.022, 0.026, 0.03, 0.0, _m(Color(0.06, 0.06, 0.06), 0.2, 0.6))
			v.rotation.x = PI / 2
			v.position = Vector3(0, -0.04, -0.095)
			# гофра: кольца вниз и вбок
			for k in 7:
				var hz := MeshInstance3D.new()
				var tm2 := TorusMesh.new()
				tm2.inner_radius = 0.008
				tm2.outer_radius = 0.016
				tm2.rings = 8
				tm2.ring_segments = 5
				hz.mesh = tm2
				hz.material_override = rub
				hz.position = Vector3(0.01 * k, -0.07 - 0.018 * k, -0.09 + 0.006 * k)
				hz.rotation.z = 0.25
				root.add_child(hz)
			# банка фильтра на конце шланга
			var f := _cyl(root, 0.034, 0.034, 0.07, 0.0, _m(Color(0.28, 0.3, 0.22), 0.5, 0.5))
			f.position = Vector3(0.08, -0.22, -0.05)
			_cyl(root, 0.02, 0.02, 0.012, 0.0, steel).position = Vector3(0.08, -0.18, -0.05)
		"filter":
			_cyl(root, 0.035, 0.035, 0.06, 0.0, _m(Color(0.3, 0.32, 0.25), 0.4, 0.5))
			_cyl(root, 0.02, 0.02, 0.015, 0.035, _m(Color(0.25, 0.25, 0.25), 0.6, 0.4))
	return root


## Иконка для инвентаря и магазина (рисуется из items.gd).
static func draw_icon(ci: CanvasItem, id: String, r: Rect2, col: Color) -> void:
	var c := r.get_center()
	var s := minf(r.size.x, r.size.y)
	var w := maxf(2.0, s * 0.08)
	var a := c + Vector2(-s * 0.32, s * 0.32)
	var b := c + Vector2(s * 0.32, -s * 0.32)
	match id:
		"bat":
			ci.draw_line(a, a.lerp(b, 0.3), Color(0.12, 0.1, 0.09), w)
			ci.draw_line(a.lerp(b, 0.3), b, col, w * 1.8)
		"pipe":
			ci.draw_line(a, b, col, w * 1.1)
			ci.draw_line(a, a.lerp(b, 0.2), Color(0.15, 0.2, 0.35), w * 1.3)
		"crowbar":
			ci.draw_line(a, b, col, w * 0.8)
			ci.draw_line(b, b + Vector2(-s * 0.14, -s * 0.02), col, w * 0.8)
		"machete":
			ci.draw_line(a, a.lerp(b, 0.28), Color(0.1, 0.09, 0.08), w * 1.1)
			ci.draw_line(a.lerp(b, 0.3), b, Color(0.7, 0.71, 0.7), w * 2.0)
		"shield":
			var rr := Rect2(c - Vector2(s * 0.26, s * 0.34), Vector2(s * 0.52, s * 0.68))
			ci.draw_rect(rr, col)
			ci.draw_rect(rr, col.darkened(0.5), false, maxf(2.0, s * 0.05))
			ci.draw_circle(c, s * 0.08, col.lightened(0.3))
		"pistol":
			# вид сбоку: затвор, рукоять наклонно, спусковая скоба
			var sl := Rect2(c + Vector2(-s * 0.36, -s * 0.24), Vector2(s * 0.7, s * 0.17))
			ci.draw_rect(sl, col.lightened(0.15))
			ci.draw_line(sl.position + Vector2(s * 0.05, s * 0.04), sl.position + Vector2(s * 0.55, s * 0.04), col.lightened(0.45), maxf(1.0, s * 0.02))
			var gp := PackedVector2Array([c + Vector2(-s * 0.32, -s * 0.07), c + Vector2(-s * 0.1, -s * 0.07),
				c + Vector2(-s * 0.04, s * 0.36), c + Vector2(-s * 0.26, s * 0.36)])
			ci.draw_colored_polygon(gp, Color(0.3, 0.22, 0.15))
			ci.draw_arc(c + Vector2(s * 0.03, -s * 0.03), s * 0.08, 0.0, PI, 10, col.lightened(0.15), maxf(1.5, s * 0.03))
			ci.draw_circle(c + Vector2(s * 0.34, -s * 0.16), s * 0.025, Color(0.05, 0.05, 0.05))
		"hammer":
			ci.draw_line(a, a.lerp(b, 0.78), Color(0.5, 0.36, 0.2), w)
			var hd := a.lerp(b, 0.8)
			ci.draw_circle(hd, s * 0.15, col)
			ci.draw_circle(hd + Vector2(-s * 0.04, -s * 0.04), s * 0.06, col.lightened(0.15))
			ci.draw_line(hd + Vector2(-s * 0.1, s * 0.1), hd + Vector2(s * 0.02, s * 0.12), Color(0.7, 0.6, 0.4), w * 0.6)
		"shiv":
			ci.draw_line(a, a.lerp(b, 0.38), Color(0.3, 0.26, 0.2), w * 1.4)
			var base2 := a.lerp(b, 0.38)
			var nrm2 := Vector2(s * 0.06, s * 0.06)
			ci.draw_colored_polygon(PackedVector2Array([base2 + nrm2, base2 - nrm2, b]), col)
			ci.draw_line(base2, b, col.lightened(0.3), maxf(1.0, w * 0.3))
		"spiked_club":
			ci.draw_line(a, b, col, w * 1.6)
			for k in 4:
				var p := a.lerp(b, 0.5 + k * 0.12)
				ci.draw_line(p + Vector2(-s * 0.07, -s * 0.07), p + Vector2(s * 0.07, s * 0.07), Color(0.75, 0.75, 0.75), maxf(1.5, w * 0.35))
		"knife":
			ci.draw_line(a, a.lerp(b, 0.42), Color(0.5, 0.35, 0.2), w * 1.3)
			ci.draw_line(a.lerp(b, 0.25), a.lerp(b, 0.36), Color(0.15, 0.22, 0.5), w * 1.6)
			var tip := b
			var base := a.lerp(b, 0.42)
			var nrm := Vector2(s * 0.07, s * 0.07)
			ci.draw_colored_polygon(PackedVector2Array([base + nrm, base - nrm, tip]), Color(0.62, 0.8, 0.78, 0.85))
		"gasmask":
			# «Нюхич»: тёмная резиновая маска, два окуляра в стальных обоймах, гофра к банке фильтра
			var rubber := Color(0.11, 0.12, 0.11)
			ci.draw_rect(Rect2(c + Vector2(s * 0.12, s * 0.2), Vector2(s * 0.2, s * 0.22)), Color(0.3, 0.32, 0.24))
			ci.draw_rect(Rect2(c + Vector2(s * 0.15, s * 0.17), Vector2(s * 0.14, s * 0.04)), Color(0.4, 0.4, 0.38))
			for k in 4:
				ci.draw_circle(c + Vector2(s * (0.02 + 0.045 * k), s * (0.2 + 0.0 * k)), s * 0.045, rubber.lightened(0.08 * (k % 2)))
			var hood := PackedVector2Array()
			for k in 20:
				var ang := TAU * k / 20.0
				hood.append(c + Vector2(cos(ang) * s * 0.36, sin(ang) * s * 0.33) + Vector2(-s * 0.06, -s * 0.06))
			ci.draw_colored_polygon(hood, rubber)
			for sx in [-0.2, 0.08]:
				var e := c + Vector2(s * sx, -s * 0.1)
				ci.draw_circle(e, s * 0.12, Color(0.42, 0.43, 0.41))
				ci.draw_circle(e, s * 0.088, Color(0.32, 0.4, 0.34))
				ci.draw_circle(e + Vector2(-s * 0.03, -s * 0.03), s * 0.025, Color(0.6, 0.68, 0.62))
			ci.draw_circle(c + Vector2(-s * 0.06, s * 0.12), s * 0.07, Color(0.05, 0.05, 0.05))
		"filter":
			ci.draw_rect(Rect2(c - Vector2(s * 0.2, s * 0.26), Vector2(s * 0.4, s * 0.52)), col)
			ci.draw_rect(Rect2(c - Vector2(s * 0.1, s * 0.34), Vector2(s * 0.2, s * 0.1)), col.darkened(0.4))
