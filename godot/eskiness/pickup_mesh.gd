extends RefCounted
## Модели лежащих предметов (pickup.gd): маленькие узнаваемые 3D-формы из нескольких деталей,
## примерно в 2.8 раза крупнее прежних кубиков. Для предметов без своей модели — иконка-спрайт
## (рисуется items.gd: draw_icon), оружие и снаряжение — модели weapons.gd, чуть крупнее.

const Items := preload("res://items.gd")
const SCALE := 2.8          # ×2 к прежним 1.4 (промпт 14.11 18:12)
const WEAPON_SCALE := 1.875  # оружие и снаряжение — ×1.5 к прежним 1.25, чтобы не стали гигантскими
## Визуал приподнят над низом коллизии, чтобы нижние грани не совпадали с полом (иначе мерцают, как было с кувшинами).
const LIFT := 0.008
const LIFT_FLAT := 0.014     # тонкие плоские вещи (монеты, фото, плитка…)
const FLAT := ["coin", "photo", "choco", "glass", "wallet", "nut", "gear", "tape", "rusk"]

## Есть ли у предмета своя модель здесь.
const MODELS := ["coin", "bandage", "pills", "canned", "water", "soda", "rusk", "choco", "battery",
	"nut", "gear", "wallet", "tape", "wood", "glass", "medkit", "photo", "scrap"]
## Предметы с моделью weapons.gd (через Items.make_mesh).
const WEAPON_LIKE := ["bat", "pipe", "crowbar", "machete", "knife", "shield", "gasmask", "filter"]

static var _icon_cache := {}


## Узел модели и размер коробки столкновений: [Node3D, Vector3].
static func make(id: String) -> Array:
	if id in WEAPON_LIKE:
		var w := Items.make_mesh(id)
		w.scale = Vector3.ONE * WEAPON_SCALE
		var s := (Vector3(0.7, 0.06, 0.06) if id in ["bat", "pipe", "crowbar", "machete", "knife"] else Vector3(0.2, 0.1, 0.2)) * WEAPON_SCALE
		w.position.y += LIFT
		return [w, s]
	if id in MODELS:
		var root := Node3D.new()
		var size: Vector3 = _build(root, id)
		root.position.y = LIFT_FLAT if id in FLAT else LIFT
		return [root, size]
	return _sprite(id)


# ---------- детали ----------

static func _mat(col: Color, metal := 0.0, rough := 0.6, glow := 0.22) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metal
	m.roughness = rough
	# лёгкое свечение — чтобы лут было видно в темноте
	m.emission_enabled = true
	m.emission = Color(col.r, col.g, col.b)
	m.emission_energy_multiplier = glow
	if col.a < 0.99:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


static func _add(root: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	root.add_child(mi)
	return mi


static func _cyl(r: float, h: float, segs := 20, r_bottom := -1.0) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r if r_bottom < 0.0 else r_bottom
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c


static func _box(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b


## Собрать модель в root (в «единичном» масштабе, потом root.scale = SCALE). Возвращает размер коробки.
static func _build(root: Node3D, id: String) -> Vector3:
	var col: Color = Items.ITEMS[id]["color"] if Items.ITEMS.has(id) else Color.WHITE
	var size := Vector3(0.1, 0.05, 0.1)
	match id:
		"coin":
			# монета: диск с ободком и выпуклым центром
			var gold := _mat(col, 0.85, 0.32, 0.3)
			_add(root, _cyl(0.05, 0.01, 24), gold)
			_add(root, _cyl(0.034, 0.013, 24), _mat(col.darkened(0.2), 0.85, 0.4, 0.25))
			_add(root, _cyl(0.016, 0.015, 12), gold)
			size = Vector3(0.1, 0.015, 0.1)
		"bandage":
			# рулон бинта на боку, с тёмной втулкой и свисающим концом
			var cloth := _mat(col, 0.0, 0.95, 0.2)
			_add(root, _cyl(0.04, 0.065, 20), cloth, Vector3.ZERO, Vector3(0, 0, PI / 2))
			_add(root, _cyl(0.014, 0.067, 12), _mat(Color(0.35, 0.3, 0.25), 0.0, 0.9, 0.05), Vector3.ZERO, Vector3(0, 0, PI / 2))
			_add(root, _box(Vector3(0.05, 0.003, 0.06)), cloth, Vector3(0.0, -0.037, 0.05), Vector3(0.15, 0, 0))
			size = Vector3(0.065, 0.08, 0.1)
		"pills":
			# баночка таблеток: оранжевая банка, белая крышка, этикетка
			_add(root, _cyl(0.024, 0.06, 18), _mat(Color(0.75, 0.42, 0.12, 0.92), 0.0, 0.3, 0.25))
			_add(root, _cyl(0.0245, 0.03, 18), _mat(Color(0.92, 0.9, 0.85), 0.0, 0.8, 0.2), Vector3(0, -0.004, 0))
			_add(root, _cyl(0.026, 0.02, 18), _mat(Color(0.95, 0.95, 0.93), 0.0, 0.5, 0.25), Vector3(0, 0.038, 0))
			_add(root, _box(Vector3(0.012, 0.012, 0.002)), _mat(Color(0.8, 0.15, 0.1), 0.0, 0.6, 0.2), Vector3(0, -0.004, 0.025))
			size = Vector3(0.052, 0.085, 0.052)
		"canned":
			# тушёнка: жестяная банка с ободками и красной этикеткой
			var tin := _mat(col, 0.8, 0.35, 0.18)
			_add(root, _cyl(0.04, 0.075, 24), tin)
			_add(root, _cyl(0.0405, 0.05, 24), _mat(Color(0.62, 0.16, 0.1), 0.0, 0.7, 0.2))
			_add(root, _cyl(0.0395, 0.03, 24), _mat(Color(0.85, 0.75, 0.45), 0.0, 0.7, 0.2))   # жёлтая полоса
			_add(root, _cyl(0.042, 0.005, 24), tin, Vector3(0, 0.036, 0))
			_add(root, _cyl(0.042, 0.005, 24), tin, Vector3(0, -0.036, 0))
			size = Vector3(0.084, 0.078, 0.084)
		"water":
			# бутылка воды на боку: прозрачная голубая, горлышко, синяя крышка, этикетка
			var b := Node3D.new()
			b.rotation.z = PI / 2
			root.add_child(b)
			var glass := _mat(Color(0.6, 0.78, 0.9, 0.55), 0.0, 0.08, 0.15)
			_add(b, _cyl(0.03, 0.12, 20), glass)
			_add(b, _cyl(0.011, 0.035, 16, 0.03), glass, Vector3(0, 0.077, 0))
			_add(b, _cyl(0.013, 0.014, 16), _mat(Color(0.15, 0.3, 0.75), 0.0, 0.5, 0.25), Vector3(0, 0.1, 0))
			_add(b, _cyl(0.0305, 0.045, 20), _mat(Color(0.25, 0.5, 0.8), 0.0, 0.6, 0.2), Vector3(0, -0.01, 0))
			size = Vector3(0.21, 0.062, 0.062)
		"soda":
			# газировка: красная банка, серебряные крышка и дно, белая полоса
			var alu := _mat(Color(0.78, 0.78, 0.8), 0.9, 0.3, 0.15)
			_add(root, _cyl(0.028, 0.085, 22), _mat(col, 0.6, 0.35, 0.25))
			_add(root, _cyl(0.0285, 0.014, 22), _mat(Color(0.95, 0.93, 0.9), 0.3, 0.5, 0.2), Vector3(0, 0.01, 0))
			_add(root, _cyl(0.024, 0.008, 22, 0.028), alu, Vector3(0, 0.046, 0))
			_add(root, _cyl(0.028, 0.008, 22, 0.024), alu, Vector3(0, -0.046, 0))
			_add(root, _box(Vector3(0.012, 0.002, 0.006)), alu, Vector3(0.006, 0.051, 0))   # язычок
			size = Vector3(0.058, 0.1, 0.058)
		"rusk":
			# сухарь: ломоть хлеба с тёмной коркой по краю
			var crumb := _mat(col.lightened(0.15), 0.0, 0.95, 0.2)
			var crust := _mat(col.darkened(0.35), 0.0, 0.9, 0.15)
			_add(root, _box(Vector3(0.09, 0.025, 0.06)), crumb)
			_add(root, _box(Vector3(0.094, 0.027, 0.012)), crust, Vector3(0, 0, 0.032))
			_add(root, _cyl(0.03, 0.027, 14), crust, Vector3(-0.045, 0, 0.0), Vector3.ZERO).scale = Vector3(0.5, 1, 1.05)
			_add(root, _box(Vector3(0.012, 0.004, 0.01)), crust, Vector3(0.015, 0.014, -0.01))
			size = Vector3(0.11, 0.028, 0.075)
		"choco":
			# шоколадка: обёртка и надорванный конец с дольками, кусочек фольги
			var wrap := _mat(Color(0.5, 0.1, 0.08), 0.0, 0.5, 0.22)
			var ch := _mat(col, 0.0, 0.55, 0.15)
			_add(root, _box(Vector3(0.075, 0.014, 0.06)), wrap, Vector3(-0.022, 0, 0))
			_add(root, _box(Vector3(0.076, 0.0145, 0.012)), _mat(Color(0.9, 0.8, 0.4), 0.2, 0.5, 0.25), Vector3(-0.022, 0, 0))   # полоса на обёртке
			_add(root, _box(Vector3(0.008, 0.015, 0.06)), _mat(Color(0.8, 0.8, 0.82), 0.9, 0.25, 0.2), Vector3(0.019, 0, 0))   # фольга
			_add(root, _box(Vector3(0.04, 0.009, 0.058)), ch, Vector3(0.042, -0.002, 0))
			for i in 2:
				for j in 3:
					_add(root, _box(Vector3(0.016, 0.004, 0.016)), ch, Vector3(0.033 + i * 0.019, 0.004, -0.019 + j * 0.019))
			size = Vector3(0.12, 0.015, 0.06)
		"battery":
			# батарейка на боку: тёмно-зелёный корпус, медный торец, «плюс»
			var b := Node3D.new()
			b.rotation.z = PI / 2
			root.add_child(b)
			_add(b, _cyl(0.017, 0.06, 18), _mat(col, 0.3, 0.5, 0.22), Vector3(0, -0.01, 0))
			_add(b, _cyl(0.0172, 0.02, 18), _mat(Color(0.75, 0.5, 0.25), 0.85, 0.3, 0.25), Vector3(0, 0.03, 0))
			_add(b, _cyl(0.006, 0.006, 10), _mat(Color(0.8, 0.8, 0.82), 0.9, 0.3, 0.2), Vector3(0, 0.043, 0))
			size = Vector3(0.092, 0.035, 0.035)
		"nut":
			# гайка: шестигранник с отверстием
			var steel := _mat(col, 0.85, 0.4, 0.2)
			_add(root, _cyl(0.026, 0.017, 6), steel)
			_add(root, _cyl(0.011, 0.019, 14), _mat(Color(0.05, 0.05, 0.05), 0.5, 0.6, 0.0))
			size = Vector3(0.052, 0.018, 0.052)
		"gear":
			# шестерёнка: диск, 10 зубцов, ступица с отверстием
			var steel := _mat(col, 0.8, 0.4, 0.2)
			_add(root, _cyl(0.036, 0.012, 24), steel)
			for k in 10:
				var a := TAU * k / 10.0
				_add(root, _box(Vector3(0.012, 0.012, 0.01)), steel, Vector3(cos(a), 0, sin(a)) * 0.04, Vector3(0, -a, 0))
			_add(root, _cyl(0.015, 0.016, 16), _mat(col.darkened(0.25), 0.8, 0.4, 0.15))
			_add(root, _cyl(0.007, 0.018, 10), _mat(Color(0.05, 0.05, 0.05), 0.5, 0.6, 0.0))
			size = Vector3(0.09, 0.016, 0.09)
		"wallet":
			# кошелёк: кожаный, клапан, строчка, металлическая застёжка
			_add(root, _box(Vector3(0.09, 0.018, 0.068)), _mat(col, 0.0, 0.8, 0.2))
			_add(root, _box(Vector3(0.09, 0.006, 0.03)), _mat(col.darkened(0.25), 0.0, 0.75, 0.15), Vector3(0, 0.011, -0.018))
			_add(root, _box(Vector3(0.086, 0.0185, 0.002)), _mat(col.lightened(0.35), 0.0, 0.9, 0.15), Vector3(0, 0, 0.032))
			_add(root, _cyl(0.005, 0.004, 10), _mat(Color(0.82, 0.72, 0.4), 0.9, 0.3, 0.3), Vector3(0, 0.015, -0.003))
			size = Vector3(0.09, 0.025, 0.07)
		"tape":
			# изолента: синий моток, картонная втулка, дырка
			_add(root, _cyl(0.04, 0.026, 24), _mat(col, 0.0, 0.25, 0.25))
			_add(root, _cyl(0.024, 0.028, 20), _mat(Color(0.7, 0.6, 0.42), 0.0, 0.9, 0.15))
			_add(root, _cyl(0.021, 0.03, 20), _mat(Color(0.04, 0.04, 0.05), 0.0, 1.0, 0.0))
			_add(root, _box(Vector3(0.02, 0.026, 0.002)), _mat(col.lightened(0.1), 0.0, 0.25, 0.2), Vector3(0.008, 0, 0.041), Vector3(0, -0.2, 0))   # отлипший край
			size = Vector3(0.08, 0.028, 0.08)
		"wood":
			# деревяшка: обломок доски с волокнами, щепой на конце и гвоздём
			var w := _mat(col, 0.0, 0.9, 0.18)
			_add(root, _box(Vector3(0.16, 0.022, 0.05)), w)
			_add(root, _box(Vector3(0.05, 0.022, 0.022)), w, Vector3(0.1, 0, -0.012), Vector3(0, 0.12, 0))   # щепа
			_add(root, _box(Vector3(0.035, 0.02, 0.014)), w, Vector3(0.095, 0, 0.016), Vector3(0, -0.2, 0))
			for z in [-0.012, 0.008]:
				_add(root, _box(Vector3(0.15, 0.002, 0.003)), _mat(col.darkened(0.35), 0.0, 0.9, 0.1), Vector3(-0.004, 0.0115, z))
			_add(root, _cyl(0.003, 0.03, 8), _mat(Color(0.45, 0.42, 0.4), 0.85, 0.5, 0.15), Vector3(-0.06, 0.015, 0))
			_add(root, _cyl(0.006, 0.002, 10), _mat(Color(0.45, 0.42, 0.4), 0.85, 0.5, 0.15), Vector3(-0.06, 0.03, 0))
			size = Vector3(0.2, 0.03, 0.06)
		"glass":
			# кусочки стекла: два прозрачных острых осколка
			var gm := _mat(Color(col.r, col.g, col.b, 0.5), 0.0, 0.05, 0.3)
			gm.cull_mode = BaseMaterial3D.CULL_DISABLED
			var p1 := PrismMesh.new()
			p1.size = Vector3(0.05, 0.075, 0.004)
			_add(root, p1, gm, Vector3(0, 0, 0), Vector3(-PI / 2, 0.3, 0))
			var p2 := PrismMesh.new()
			p2.size = Vector3(0.03, 0.05, 0.004)
			p2.left_to_right = 0.2
			_add(root, p2, gm, Vector3(0.03, 0.003, 0.02), Vector3(-PI / 2, -1.1, 0))
			size = Vector3(0.08, 0.01, 0.08)
		"medkit":
			# аптечка: светлый чемоданчик, красный крест, ручка
			var shell := _mat(Color(0.82, 0.8, 0.74), 0.0, 0.6, 0.18)
			var red := _mat(col, 0.0, 0.6, 0.3)
			_add(root, _box(Vector3(0.17, 0.085, 0.12)), shell)
			_add(root, _box(Vector3(0.172, 0.006, 0.122)), _mat(Color(0.5, 0.48, 0.44), 0.0, 0.7, 0.1), Vector3(0, 0.012, 0))   # шов крышки
			_add(root, _box(Vector3(0.05, 0.002, 0.016)), red, Vector3(0, 0.043, 0))
			_add(root, _box(Vector3(0.016, 0.002, 0.05)), red, Vector3(0, 0.043, 0))
			_add(root, _box(Vector3(0.05, 0.012, 0.008)), _mat(Color(0.2, 0.2, 0.2), 0.3, 0.6, 0.05), Vector3(0, 0.0, -0.064))
			size = Vector3(0.17, 0.088, 0.13)
		"photo":
			# старое фото: белая рамка, выцветшая сепия
			_add(root, _box(Vector3(0.075, 0.003, 0.095)), _mat(Color(0.88, 0.85, 0.76), 0.0, 0.9, 0.2))
			_add(root, _box(Vector3(0.062, 0.001, 0.07)), _mat(Color(0.48, 0.38, 0.26), 0.0, 0.9, 0.15), Vector3(0, 0.0018, -0.006))
			_add(root, _box(Vector3(0.062, 0.001, 0.025)), _mat(Color(0.3, 0.24, 0.17), 0.0, 0.9, 0.1), Vector3(0, 0.0022, 0.016))
			size = Vector3(0.075, 0.006, 0.095)
		"scrap":
			# металлолом: несколько гнутых ржавых пластин и прут
			var rust := _mat(col, 0.6, 0.75, 0.15)
			_add(root, _box(Vector3(0.09, 0.006, 0.04)), rust, Vector3(-0.02, 0, 0), Vector3(0, 0.3, 0.15))
			_add(root, _box(Vector3(0.06, 0.006, 0.035)), _mat(col.lightened(0.15), 0.7, 0.6, 0.15), Vector3(0.035, 0.008, 0.01), Vector3(0.2, -0.5, -0.2))
			_add(root, _cyl(0.004, 0.11, 8), _mat(col.darkened(0.3), 0.7, 0.6, 0.12), Vector3(0, 0.012, -0.005), Vector3(0, 0.9, PI / 2))
			size = Vector3(0.13, 0.03, 0.07)
	root.scale = Vector3.ONE * SCALE
	return size * SCALE


## Иконка предмета (items.gd: draw_icon) на билборде — для предметов без своей модели.
static func _sprite(id: String) -> Array:
	var spr := Sprite3D.new()
	spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	spr.pixel_size = 0.52 / 128.0
	spr.shaded = false
	spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	spr.position.y = 0.26 + LIFT
	spr.modulate = Color(0.85, 0.85, 0.85)
	if _icon_cache.has(id):
		spr.texture = _icon_cache[id]
	else:
		_render_icon.call_deferred(spr, id)
	return [spr, Vector3(0.4, 0.52, 0.4)]


## Нарисовать иконку один раз во вьюпорте 128×128 и закэшировать текстуру.
static func _render_icon(spr: Sprite3D, id: String) -> void:
	if not is_instance_valid(spr) or not spr.is_inside_tree():
		return
	if _icon_cache.has(id):
		spr.texture = _icon_cache[id]
		return
	var vp := SubViewport.new()
	vp.size = Vector2i(128, 128)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var cv := Control.new()
	cv.size = Vector2(128, 128)
	cv.draw.connect(func(): Items.draw_icon(cv, id, Rect2(4, 4, 120, 120)))
	vp.add_child(cv)
	spr.add_child(vp)
	spr.texture = vp.get_texture()
	await RenderingServer.frame_post_draw
	if not is_instance_valid(vp):
		return
	var img := vp.get_texture().get_image()
	if img != null and not img.is_empty():
		img.generate_mipmaps()
		var tex := ImageTexture.create_from_image(img)
		_icon_cache[id] = tex
		if is_instance_valid(spr):
			spr.texture = tex
	vp.queue_free()
