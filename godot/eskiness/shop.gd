extends StaticBody3D
## Магазин снаряжения «Trinkets Market» — зелёный торговый автомат слева от KILLBOX.
## E — открыть окно: покупка за монеты (оружие, одежда, противогаз, фильтры, фонарик), скупка хлама, обновление ящиков.
## Интерфейс взаимодействия (его дёргает game.gd): get_prompt(game) -> String, interact(game).

const Weapons := preload("res://weapons.gd")
const Items := preload("res://items.gd")

var game
var ui: CanvasLayer
var sell_box: VBoxContainer
var coins_l: Label
var info_l: Label
var opened := false


const CHEST_REFRESH := 80   # «Обновить все ящики»

func _ready() -> void:
	_build()


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
	m.shader = preload("res://worn_metal.gdshader")
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
	scr.text = "ВЫБОР"
	scr.font_size = 32
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
	title.font = sign_font()
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


func get_prompt(_game) -> String:
	return "[E] Trinkets Market"


var _last_toggle := -10000   # защита от «закликивания» E: окно не переключается чаще раза в 0.35 с


func interact(g) -> void:
	game = g
	if Time.get_ticks_msec() - _last_toggle < 350:
		return
	_last_toggle = Time.get_ticks_msec()
	if opened:
		_close()
	else:
		_open()


# ---------- окно магазина ----------

func _open() -> void:
	if ui == null:
		_build_ui()
	opened = true
	ui.visible = true
	game.player.active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()


func _close() -> void:
	opened = false
	if ui:
		ui.visible = false
	if game and game.player:
		game.player.active = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(e: InputEvent) -> void:
	if opened and (e.is_action_pressed("ui_cancel") or e.is_action_pressed("interact") or e.is_action_pressed("inventory")):
		get_viewport().set_input_as_handled()
		if e.is_echo() or Time.get_ticks_msec() - _last_toggle < 350:
			return
		_last_toggle = Time.get_ticks_msec()
		_close()


func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 5
	add_child(ui)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(center)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.06, 0.05, 0.95)
	sb.border_color = Color(0.6, 0.3, 0.15, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 26)
	panel.add_child(cols)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	cols.add_child(box)
	# скупка хлама (промпт 20:06): правая колонка
	var sell_col := VBoxContainer.new()
	sell_col.add_theme_constant_override("separation", 8)
	sell_col.custom_minimum_size = Vector2(300, 0)
	cols.add_child(sell_col)
	sell_col.add_child(_label("СКУПКА ХЛАМА", 28, Color(1.0, 0.6, 0.35)))
	sell_col.add_child(_label("1–3 монеты за штуку", 15, Color(0.65, 0.63, 0.58)))
	sell_box = VBoxContainer.new()
	sell_box.add_theme_constant_override("separation", 6)
	sell_col.add_child(sell_box)
	var all_b := Button.new()
	all_b.text = "Продать весь хлам"
	all_b.focus_mode = Control.FOCUS_NONE
	all_b.add_theme_font_size_override("font_size", 20)
	all_b.pressed.connect(_sell_all_junk)
	sell_col.add_child(all_b)
	# удача для KILLBOX (промпт 23:57): +50% к шансу символа на несколько круток
	sell_col.add_child(_label(" ", 8, Color.WHITE))
	sell_col.add_child(_label("ГАРАНТ KILLBOX", 28, Color(1.0, 0.45, 0.3)))
	sell_col.add_child(_label("после каждой крутки +1 символ в окне", 14, Color(0.65, 0.63, 0.58)))
	var SM := preload("res://slot_machine.gd")
	var SymS := preload("res://slot_symbols.gd")
	for sym in SM.LUCK:
		var d: Array = SM.LUCK[sym]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var ic := Control.new()
		ic.custom_minimum_size = Vector2(32, 32)
		ic.draw.connect(func(): SymS.draw(ic, sym, Rect2(Vector2.ZERO, ic.size)))
		row.add_child(ic)
		var l := _label("%s — %d круток" % [SymS.NAMES[sym], int(d[0])], 16, Color(0.88, 0.86, 0.8))
		l.custom_minimum_size = Vector2(170, 0)
		row.add_child(l)
		var b := Button.new()
		b.text = "%d" % int(d[1])
		b.custom_minimum_size = Vector2(56, 30)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(_buy_luck.bind(sym, int(d[1])))
		row.add_child(b)
		sell_col.add_child(row)
	var head := _label("TRINKETS MARKET", 30, Color(0.55, 1.0, 0.6))
	head.add_theme_font_override("font", sign_font())
	box.add_child(head)
	coins_l = _label("", 22, Color(0.92, 0.8, 0.5))
	box.add_child(coins_l)
	var goods := GridContainer.new()
	goods.columns = 2
	goods.add_theme_constant_override("h_separation", 18)
	goods.add_theme_constant_override("v_separation", 6)
	box.add_child(goods)
	for entry in Weapons.SHOP:
		var id: String = entry[0]
		var price: int = entry[1]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var icon := Control.new()
		icon.custom_minimum_size = Vector2(36, 36)
		icon.draw.connect(func(): Items.draw_icon(icon, id, Rect2(Vector2.ZERO, icon.size)))
		row.add_child(icon)
		var text := VBoxContainer.new()
		text.custom_minimum_size = Vector2(230, 0)
		text.add_theme_constant_override("separation", 0)
		text.add_child(_label(Items.item_name(id), 18, Color(0.9, 0.88, 0.82)))
		var d := _label(Items.ITEMS[id]["desc"], 13, Color(0.65, 0.63, 0.58))
		d.custom_minimum_size = Vector2(230, 0)
		text.add_child(d)
		row.add_child(text)
		var buy := Button.new()
		buy.text = "%d" % price
		buy.custom_minimum_size = Vector2(64, 34)
		buy.focus_mode = Control.FOCUS_NONE
		buy.add_theme_font_size_override("font_size", 18)
		buy.pressed.connect(func(): _buy(id, price))
		row.add_child(buy)
		goods.add_child(row)
	info_l = _label("", 18, Color(0.8, 0.78, 0.7))
	box.add_child(info_l)
	# внизу: обновить все ящики уровня (сейф не трогаем) и закрыть
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	box.add_child(bottom)
	var close := Button.new()
	close.text = "Закрыть (E / Esc)"
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 20)
	close.pressed.connect(_close)
	bottom.add_child(close)


## Шрифт вывески «Trinkets Market» (промпт 14.11 17:19): узкий жирный «вывесочный» —
## Bahnschrift из Windows, если нет — Impact / Arial Black / Roboto Condensed.
static var _sign_font: SystemFont
static func sign_font() -> SystemFont:
	if _sign_font == null:
		_sign_font = SystemFont.new()
		_sign_font.font_names = PackedStringArray(["Bahnschrift", "Impact", "Arial Black", "Roboto Condensed", "sans-serif"])
		_sign_font.font_weight = 700
		_sign_font.font_stretch = 75
	return _sign_font


func _label(t: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _refresh() -> void:
	coins_l.text = "Монет: %d" % game.inv.count("coin")
	_rebuild_sell()


## Список вещей из сумки, которые магазин покупает (поле price в items.gd).
func _rebuild_sell() -> void:
	if sell_box == null:
		return
	for c in sell_box.get_children():
		c.queue_free()
	var shown := {}
	for s in game.inv.slots:
		if s == null or shown.has(s["id"]) or not Items.ITEMS[s["id"]].has("price"):
			continue
		var id: String = s["id"]
		shown[id] = true
		var n: int = game.inv.count(id)
		var price: int = Items.ITEMS[id]["price"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var icon := Control.new()
		icon.custom_minimum_size = Vector2(34, 34)
		icon.draw.connect(func(): Items.draw_icon(icon, id, Rect2(Vector2.ZERO, icon.size)))
		row.add_child(icon)
		var l := _label("%s ×%d — по %d" % [Items.item_name(id), n, price], 17, Color(0.88, 0.86, 0.8))
		l.custom_minimum_size = Vector2(170, 0)
		row.add_child(l)
		var b := Button.new()
		b.text = "Продать"
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(func(): _sell(id, game.inv.count(id)))
		row.add_child(b)
		sell_box.add_child(row)
	if shown.is_empty():
		sell_box.add_child(_label("В сумке нет ничего на продажу", 16, Color(0.6, 0.58, 0.54)))


func _sell(id: String, n: int) -> int:
	var price: int = Items.ITEMS[id]["price"]
	n = mini(n, game.inv.count(id))
	if n <= 0 or not game.inv.remove(id, n):
		return 0
	game.inv.add("coin", n * price)
	info_l.text = "Продано: %s ×%d — +%d монет" % [Items.item_name(id), n, n * price]
	game.play_ui("coin", -10.0, 1.1)
	_refresh()
	return n * price


## «Продать весь хлам» — только то, что помечено как хлам (изоленту не трогаем: она нужна для ножика).
func _sell_all_junk() -> void:
	var total := 0
	for id in Items.ITEMS:
		if Items.ITEMS[id].get("junk", false) and game.inv.count(id) > 0:
			total += _sell(id, game.inv.count(id))
	info_l.text = "Весь хлам продан: +%d монет" % total if total > 0 else "Хлама в сумке нет"



func _refresh_chests() -> void:
	var opened := 0
	for c in game.chests:
		if is_instance_valid(c) and c.opened:
			opened += 1
	if opened == 0:
		info_l.text = "Все ящики и так закрыты"
		return
	if game.inv.count("coin") < CHEST_REFRESH:
		info_l.text = "Не хватает монет"
		game.play_ui("buzz", -14.0)
		return
	game.inv.remove("coin", CHEST_REFRESH)
	game.refresh_chests()
	info_l.text = "Ящики обновлены: %d" % opened
	game.hud.toast("Ящики на уровне снова полны", Color(0.9, 0.8, 0.55))
	game.play_ui("creak", -10.0, 0.8)
	_refresh()


func _buy_luck(sym: String, price: int) -> void:
	if game.slot == null:
		return
	if game.inv.count("coin") < price:
		info_l.text = "Не хватает монет"
		game.play_ui("buzz", -14.0)
		return
	game.inv.remove("coin", price)
	game.slot.add_luck(sym)
	info_l.text = "Гарант: %s" % preload("res://slot_symbols.gd").NAMES[sym]
	game.play_ui("coin", -10.0)
	_refresh()


func _buy(id: String, price: int) -> void:
	if game.inv.count("coin") < price:
		info_l.text = "Не хватает монет"
		game.play_ui("buzz", -14.0)
		return
	if Items.ITEMS[id].has("equip") and game.inv.count(id) > 0:
		info_l.text = "%s уже есть" % Items.item_name(id)
		return
	game.inv.remove("coin", price)
	var left: int = game.inv.add(id, 1)
	if left > 0:
		game.inv.add("coin", price)
		info_l.text = "Инвентарь полон"
		return
	info_l.text = "Куплено: %s" % Items.item_name(id)
	_vend(id)
	if id == "gasmask" and game.gasmask:
		game.gasmask.on_bought()
	game.play_ui("coin", -10.0)
	_refresh()
