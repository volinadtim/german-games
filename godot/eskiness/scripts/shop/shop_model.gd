extends StaticBody3D
# Часть shop.gd: константы, состояние, 3D-модель торгового автомата, витрина, шрифты.
const Weapons := preload("res://scripts/weapons.gd")
const Items := preload("res://scripts/items.gd")

var game
var ui: CanvasLayer
var sell_win                  # sell_window.gd
var coins_l: Label
var info_l: Label
var tip_l: RichTextLabel       # подсказка товара у курсора (промпты 14.11 19:10, 19:26)
var tip_panel: PanelContainer
var tip_hide_t := 0.0          # долгий тап: подсказка сама прячется через пару секунд
var opened := false
var tab := 0                  # открытая вкладка (TABS)
var tab_btns: Array[Button] = []
var content: VBoxContainer    # содержимое вкладки — пересобирается при переключении и покупке

const TABS := ["Оружие", "Одежда", "Расходники", "Инструменты", "Слот-Машина", "Чертежи"]
## подвкладки «Расходников» во всех магазинах (промпт 16.11 02:57); цены — CONSUMABLES
const CONS_SUBS := [
	["Пропитание", ["rusk", "water", "soda", "choco", "canned"]],
	["Медицина", ["pills", "bandage", "medkit"]],
	["Починка", ["repair_weapon", "repair_gear", "battery"]],
]
var sub_c := 0                # открытая подвкладка «Расходников»
## только магазин в подвале деревни (village_shop.gd): вкладки «Патроны» и «Магазины» после «Инструментов»
const VILLAGE_TABS := ["Патроны", "Магазины"]
const AMMO_SHOP := [["ammo", 3]]
const MAG_SHOP := [["mag", 30]]   # магазин с 8 патронами
## «Инструменты» (промпт 16.11 02:42): фонарик, метла, нормальный молоток, топорик (рубит деревья на поляне — surface.gd)
const TOOLS := [["flashlight", 35], ["broom", 30], ["steel_hammer", 45], ["hatchet", 55]]
## расходники (промпт 14.11 17:21): [id, цена]. Батарейки и сухари — дёшево, хилки дороже.
## Экономика: старт 50 монет, кувшин даёт 1–4, хлам продаётся за 2–5.
const CONSUMABLES := [["battery", 3], ["rusk", 2], ["water", 3], ["soda", 5], ["choco", 5], ["canned", 6],
	["pills", 5], ["bandage", 6], ["medkit", 20], ["repair_weapon", 30], ["repair_gear", 25]]
## подвкладки «Одежды» (промпт 14.11 21:14): [название, товары]. Цены — Weapons.SHOP / CONSUMABLES (_price).
## Обувь — отдельная подвкладка «Ботинки»; ремкомплект одежды — в «Расходниках»; фонарик и метла — в «Инструментах»
## (промпт 16.11 02:42). «Снаряжение» — последняя (CLOTHES[-1]).
const CLOTHES := [
	["Голова", ["ushanka", "helmet", "moto_helmet"]],
	["Верх", ["kurtka", "jacket", "vest"]],
	["Низ", ["jeans", "pants", "wpants"]],
	["Ботинки", ["sneakers", "boots"]],
	["Перчатки", ["gloves", "tac_gloves"]],
	["Снаряжение", ["gasmask", "filter", "backpack"]],
]
var sub := 0                  # открытая подвкладка «Одежды» (CLOTHES)


const CHEST_REFRESH := 80   # «Обновить все ящики»


func _mat(c: Color, metal := 0.0, rough := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m


func _box(size: Vector3, pos: Vector3, m: Material, collide := false) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.position = pos
		add_child(cs)


## Торговый автомат «Trinkets Market»: высокий зелёный корпус (облупленная краска — worn_metal.gdshader),
## витрина за мутным стеклом с полками и спиралями, на спиралях — маленькие модели товаров,
## справа панель с кнопками и щелью для монет, внизу лоток выдачи, сверху светящаяся вывеска.
## Купленный товар падает с витрины в лоток (_vend), а в инвентарь кладётся сразу.
## Перед — +Z.
const W := 1.0          # ширина
const H := 2.15         # высота корпуса
const D := 0.7          # глубина
const WIN_X0 := -0.47   # витрина по X
const WIN_X1 := 0.17
const SHELF_Y := [1.78, 1.44, 1.1, 0.76]
const TRAY_Y := 0.3
var shelf_pos := {}     # id товара -> где он лежит на витрине
var _noise_tex: NoiseTexture2D


func _worn(c: Color, chrome := false, wear := 0.3) -> ShaderMaterial:
	if _noise_tex == null:
		var n := FastNoiseLite.new()
		n.seed = 91
		n.frequency = 0.045
		n.fractal_octaves = 3
		_noise_tex = NoiseTexture2D.new()
		_noise_tex.width = 128
		_noise_tex.height = 128
		_noise_tex.seamless = true
		_noise_tex.noise = n
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/worn_metal.gdshader")
	m.set_shader_parameter("n_px", _noise_tex)
	m.set_shader_parameter("n_lin", _noise_tex)
	m.set_shader_parameter("paint_color", c)
	m.set_shader_parameter("chrome", 1.0 if chrome else 0.0)
	m.set_shader_parameter("wear", wear)
	m.set_shader_parameter("rust", 0.65)
	m.set_shader_parameter("dust", 0.6)
	return m


func _build() -> void:
	var green := _worn(Color(0.1, 0.27, 0.15), false, 0.3)
	var steel := _worn(Color(0.5, 0.52, 0.5), true)
	var dark := _mat(Color(0.03, 0.035, 0.03))
	var inside := _mat(Color(0.12, 0.13, 0.12), 0.3, 0.7)
	# корпус: задняя стенка, бока, верх, низ, панель справа, перемычка над лотком
	_box(Vector3(W, H, 0.05), Vector3(0, H / 2, -D / 2 + 0.025), green)
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.05, H, D), Vector3((W / 2 - 0.025) * sx, H / 2, 0), green)
	_box(Vector3(W, 0.06, D), Vector3(0, H - 0.03, 0), green)
	_box(Vector3(W, 0.12, D), Vector3(0, 0.06, 0), green)
	_box(Vector3(W / 2 - WIN_X1, H - 0.18, 0.06), Vector3((WIN_X1 + W / 2) / 2, H / 2 + 0.03, D / 2 - 0.03), green)
	_box(Vector3(WIN_X1 + W / 2, 0.42, 0.06), Vector3((WIN_X1 - W / 2) / 2, 0.33, D / 2 - 0.03), green)
	_box(Vector3(WIN_X1 + W / 2, 0.07, 0.06), Vector3((WIN_X1 - W / 2) / 2, H - 0.095, D / 2 - 0.03), green)
	# внутренности витрины
	_box(Vector3(WIN_X1 - WIN_X0, 1.55, 0.02), Vector3((WIN_X0 + WIN_X1) / 2, 1.3, -D / 2 + 0.06), inside)
	for y in SHELF_Y:
		_box(Vector3(WIN_X1 - WIN_X0, 0.015, D - 0.14), Vector3((WIN_X0 + WIN_X1) / 2, y - 0.09, 0.0), steel)
		# ценники вдоль края полки
		_box(Vector3(WIN_X1 - WIN_X0, 0.03, 0.005), Vector3((WIN_X0 + WIN_X1) / 2, y - 0.1, D / 2 - 0.075), _mat(Color(0.75, 0.72, 0.62)))
	# товары на спиралях: 4 полки × 4 места
	var goods: Array = []
	for e in Weapons.SHOP:
		goods.append(e[0])
	for i in mini(goods.size(), 16):
		@warning_ignore("integer_division")
		var row := i / 4
		var col := i % 4
		var x := WIN_X0 + 0.08 + col * 0.16
		var y: float = SHELF_Y[row] - 0.06
		var pos := Vector3(x, y, 0.08)
		shelf_pos[goods[i]] = pos
		_coil(Vector3(x, y - 0.02, 0.02), steel)
		var mini_ := _mini(goods[i])
		mini_.position = pos + Vector3(0, 0.02, 0)
		add_child(mini_)
	# мутное зеленоватое стекло витрины
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.5, 0.6, 0.52, 0.1)
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.roughness = 0.2
	gm.metallic_specular = 0.8
	var glass := MeshInstance3D.new()
	var gq := QuadMesh.new()
	gq.size = Vector2(WIN_X1 - WIN_X0, 1.55)
	glass.mesh = gq
	glass.material_override = gm
	glass.position = Vector3((WIN_X0 + WIN_X1) / 2, 1.3, D / 2 - 0.01)
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glass)
	# лоток выдачи: тёмная ниша с откидной заслонкой
	_box(Vector3(0.5, 0.16, 0.02), Vector3(-0.15, TRAY_Y, D / 2 + 0.005), dark)
	_box(Vector3(0.52, 0.04, 0.03), Vector3(-0.15, TRAY_Y + 0.1, D / 2 + 0.01), steel)
	# панель справа: экранчик, кнопки 4×3, щель для монет, возврат монет
	var px := (WIN_X1 + W / 2) / 2
	var screen_m := _mat(Color(0.05, 0.12, 0.06))
	screen_m.emission_enabled = true
	screen_m.emission = Color(0.3, 0.9, 0.4)
	screen_m.emission_energy_multiplier = 0.35
	_box(Vector3(0.22, 0.08, 0.01), Vector3(px, 1.62, D / 2 + 0.005), screen_m)
	var scr := Label3D.new()
	scr.text = "BUY"
	scr.font = model_font()
	scr.font_size = 34
	scr.pixel_size = 0.0018
	scr.modulate = Color(0.5, 1.0, 0.55)
	scr.outline_size = 0
	scr.position = Vector3(px, 1.62, D / 2 + 0.012)
	add_child(scr)
	var btn := _worn(Color(0.6, 0.6, 0.55), true)
	for r in 4:
		for c in 3:
			_box(Vector3(0.05, 0.04, 0.02), Vector3(px - 0.07 + c * 0.07, 1.48 - r * 0.07, D / 2 + 0.01), btn)
	_box(Vector3(0.05, 0.1, 0.02), Vector3(px, 1.12, D / 2 + 0.01), steel)
	_box(Vector3(0.012, 0.06, 0.01), Vector3(px, 1.12, D / 2 + 0.021), dark)
	_box(Vector3(0.1, 0.06, 0.03), Vector3(px, 0.92, D / 2 + 0.01), dark)
	# вывеска сверху
	var sign_m := _mat(Color(0.04, 0.09, 0.05))
	sign_m.emission_enabled = true
	sign_m.emission = Color(0.12, 0.5, 0.2)
	sign_m.emission_energy_multiplier = 0.45
	_box(Vector3(W + 0.04, 0.26, 0.12), Vector3(0, H + 0.13, 0.12), sign_m)
	_box(Vector3(W + 0.06, 0.02, 0.14), Vector3(0, H + 0.27, 0.12), steel)
	var title := Label3D.new()
	title.text = "Trinkets Market"
	title.font = model_font()
	title.font_size = 64
	title.pixel_size = 0.00175
	title.outline_size = 6
	title.outline_modulate = Color(0.02, 0.1, 0.03)
	title.modulate = Color(0.6, 1.0, 0.62)
	title.shaded = false
	title.position = Vector3(0, H + 0.13, 0.185)
	add_child(title)
	# свет витрины и вывески — тусклый зелёный
	var l := OmniLight3D.new()
	l.light_color = Color(0.55, 1.0, 0.6)
	l.light_energy = 0.4
	l.omni_range = 3.0
	l.position = Vector3(-0.15, 1.6, D / 2 + 0.4)
	add_child(l)
	var inner := OmniLight3D.new()
	inner.light_color = Color(0.75, 1.0, 0.8)
	inner.light_energy = 0.12
	inner.omni_range = 1.2
	inner.position = Vector3(-0.15, 1.95, 0.05)
	add_child(inner)
	# коллизия
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(W, H + 0.3, D)
	cs.shape = bs
	cs.position = Vector3(0, (H + 0.3) / 2, 0)
	add_child(cs)


## Спираль-держатель товара: несколько колец вдоль глубины полки.
func _coil(pos: Vector3, m: Material) -> void:
	for k in 5:
		var tm := TorusMesh.new()
		tm.inner_radius = 0.045
		tm.outer_radius = 0.052
		tm.rings = 12
		tm.ring_segments = 6
		var mi := MeshInstance3D.new()
		mi.mesh = tm
		mi.material_override = m
		mi.rotation.x = PI / 2
		mi.position = pos + Vector3(0, 0, -0.18 + k * 0.07)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


## Маленькая модель товара, вписанная в ~13 см.
func _mini(id: String) -> Node3D:
	var n: Node3D = Items.make_mesh(id)
	var box := AABB()
	var first := true
	var meshes: Array = n.find_children("*", "MeshInstance3D", true, false)
	if n is MeshInstance3D:
		meshes.append(n)
	for mi in meshes:
		if (mi as MeshInstance3D).mesh == null:
			continue
		var bb: AABB = (mi as MeshInstance3D).mesh.get_aabb()
		if mi != n:
			bb = (mi as Node3D).transform * bb
		box = bb if first else box.merge(bb)
		first = false
	var holder := Node3D.new()
	holder.add_child(n)
	var mx := maxf(box.size.x, maxf(box.size.y, box.size.z))
	holder.scale = Vector3.ONE * (0.15 / maxf(mx, 0.01))
	n.position = -(n.transform * box.get_center())
	return holder


## Покупка: копия товара падает с витрины в лоток и пропадает.
func _vend(id: String) -> void:
	var from: Vector3 = shelf_pos.get(id, Vector3(-0.15, 1.4, 0.08))
	var m := _mini(id)
	m.position = from + Vector3(0, 0.02, 0.06)
	add_child(m)
	var tw := create_tween()
	tw.tween_property(m, "position:z", from.z + 0.12, 0.35).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(m, "rotation:z", 0.4, 0.35)
	tw.tween_property(m, "position", Vector3(from.x * 0.5 - 0.08, TRAY_Y + 0.02, D / 2 - 0.08), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(m, "rotation:x", 1.8, 0.45)
	tw.tween_callback(_vend_thud)
	tw.tween_interval(1.2)
	tw.tween_callback(m.queue_free)


func _vend_thud() -> void:
	if game:
		game.play_at("thud", global_transform * Vector3(0, TRAY_Y, D / 2), -12.0, 1.8)


@warning_ignore("unused_private_class_variable")
var _last_toggle := -10000   # защита от «закликивания» E: окно не переключается чаще раза в 0.35 с


## Шрифт вывески «Trinkets Market» (промпт 14.11 17:19): узкий жирный «вывесочный» —
## Bahnschrift из Windows, если нет — Impact / Arial Black / Roboto Condensed.
## Шрифт надписей на самой модели автомата-магазина (промпт 14.11 19:36): FONT_PICK — имя системного шрифта.
const FONT_PICK := "Courier New"   # ретро «печатный»; на Android — monospace
static var _model_font: SystemFont
static func model_font() -> SystemFont:
	if _model_font == null:
		_model_font = SystemFont.new()
		_model_font.font_names = PackedStringArray([FONT_PICK, "monospace"])
		_model_font.font_weight = 800
	return _model_font


static var _sign_font: SystemFont
static func sign_font() -> SystemFont:
	if _sign_font == null:
		_sign_font = SystemFont.new()
		_sign_font.font_names = PackedStringArray(["Bahnschrift", "Impact", "Arial Black", "Roboto Condensed", "sans-serif"])
		_sign_font.font_weight = 700
		_sign_font.font_stretch = 75
	return _sign_font


## Цена товара: из Weapons.SHOP, иначе из CONSUMABLES.
static func _price(id: String) -> int:
	for e in Weapons.SHOP:
		if e[0] == id:
			return int(e[1])
	for e in CONSUMABLES:
		if e[0] == id:
			return int(e[1])
	for e in TOOLS + AMMO_SHOP + MAG_SHOP:
		if e[0] == id:
			return int(e[1])
	return 0


## Вкладки этого магазина: в деревне — ещё «Патроны» и «Магазины» после «Инструментов».
func tab_names() -> Array:
	var t: Array = TABS.duplicate()
	if "main_shop" in self:
		var at := t.find("Инструменты") + 1
		for k in VILLAGE_TABS.size():
			t.insert(at + k, VILLAGE_TABS[k])
	return t


## «1 монета», «3 монеты», «5 монет».
static func _coins(n: int) -> String:
	var m10 := n % 10
	var m100 := n % 100
	if m10 == 1 and m100 != 11:
		return "%d монета" % n
	if m10 >= 2 and m10 <= 4 and (m100 < 12 or m100 > 14):
		return "%d монеты" % n
	return "%d монет" % n
