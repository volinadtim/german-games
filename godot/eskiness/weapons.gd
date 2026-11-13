extends RefCounted
## Оружие ближнего боя из магазина: урон (множитель к удару кулаком), дальность, цена и 3D-модель.
## Модель строится кодом; длинная ось — +Y, рукоять в начале координат.

const WEAPONS := {
	"bat": {"mult": 2.0, "reach": 1.5, "price": 40},
	"pipe": {"mult": 2.5, "reach": 1.55, "price": 60},
	"crowbar": {"mult": 3.0, "reach": 1.45, "price": 90},
	"machete": {"mult": 3.6, "reach": 1.5, "price": 140},
	"knife": {"mult": 2.4, "reach": 1.25, "price": 0},     # крафт: деревяшка + стекло + изолента
}

# что продаёт магазин, по порядку
const SHOP := [["bat", 40], ["pipe", 60], ["crowbar", 90], ["machete", 140], ["gasmask", 50], ["filter", 25]]


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
			var rub := _m(Color(0.16, 0.18, 0.15))
			var face := SphereMesh.new()
			face.radius = 0.1
			face.height = 0.16
			var mi := MeshInstance3D.new()
			mi.mesh = face
			mi.material_override = rub
			root.add_child(mi)
			for sx in [-0.04, 0.04]:
				var g := _cyl(root, 0.026, 0.026, 0.012, 0.0, _m(Color(0.4, 0.45, 0.4), 0.3, 0.1))
				g.rotation.x = PI / 2
				g.position = Vector3(sx, 0.025, -0.07)
			var f := _cyl(root, 0.035, 0.035, 0.06, 0.0, _m(Color(0.3, 0.32, 0.25), 0.4, 0.5))
			f.rotation.x = PI / 2
			f.position = Vector3(0, -0.05, -0.1)
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
		"knife":
			ci.draw_line(a, a.lerp(b, 0.42), Color(0.5, 0.35, 0.2), w * 1.3)
			ci.draw_line(a.lerp(b, 0.25), a.lerp(b, 0.36), Color(0.15, 0.22, 0.5), w * 1.6)
			var tip := b
			var base := a.lerp(b, 0.42)
			var nrm := Vector2(s * 0.07, s * 0.07)
			ci.draw_colored_polygon(PackedVector2Array([base + nrm, base - nrm, tip]), Color(0.62, 0.8, 0.78, 0.85))
		"gasmask":
			ci.draw_circle(c, s * 0.3, col)
			ci.draw_circle(c + Vector2(-s * 0.12, -s * 0.06), s * 0.08, Color(0.55, 0.62, 0.55))
			ci.draw_circle(c + Vector2(s * 0.12, -s * 0.06), s * 0.08, Color(0.55, 0.62, 0.55))
			ci.draw_circle(c + Vector2(0, s * 0.17), s * 0.1, col.darkened(0.4))
		"filter":
			ci.draw_rect(Rect2(c - Vector2(s * 0.2, s * 0.26), Vector2(s * 0.4, s * 0.52)), col)
			ci.draw_rect(Rect2(c - Vector2(s * 0.1, s * 0.34), Vector2(s * 0.2, s * 0.1)), col.darkened(0.4))
