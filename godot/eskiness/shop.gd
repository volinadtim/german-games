extends StaticBody3D
## Магазин снаряжения «Trinkets Market» — зелёный торговый автомат слева от KILLBOX.
## E — открыть окно: покупка за монеты по вкладкам (промпт 14.11 17:21): «Оружие», «Одежда» (снаряжение),
## «Расходники» (еда, хилки, батарейки), «Слот-Машина» (окно KILLBOX и гарантированные символы) — порядок и имя с промпта 14.11 18:35;
## справа — кнопка окна продажи (sell_window.gd, промпт 14.11 18:06: почти всё за полцены).
## Интерфейс взаимодействия (его дёргает game.gd): get_prompt(game) -> String, interact(game).

const Weapons := preload("res://weapons.gd")
const Items := preload("res://items.gd")

var game
var ui: CanvasLayer
var sell_win                  # sell_window.gd
var coins_l: Label
var info_l: Label
var tip_l: RichTextLabel       # подсказка товара у курсора (промпты 14.11 19:10, 19:26)
var tip_panel: PanelContainer
var tip_hide_t := 0.0          # долгий тап: подсказка сама прячется через пару секунд
var markup_l: Label           # красная плашка «Наценка за мухлёж» (game.gd: markup_pct)
var opened := false
var tab := 0                  # открытая вкладка (TABS)
var tab_btns: Array[Button] = []
var content: VBoxContainer    # содержимое вкладки — пересобирается при переключении и покупке

const TABS := ["Оружие", "Одежда", "Расходники", "Слот-Машина"]
## расходники (промпт 14.11 17:21): [id, цена]. Батарейки и сухари — дёшево, хилки дороже.
## Экономика: старт 50 монет, кувшин даёт 1–4, хлам продаётся за 2–5.
const CONSUMABLES := [["battery", 3], ["rusk", 2], ["water", 3], ["soda", 5], ["choco", 5], ["canned", 6],
	["pills", 5], ["bandage", 6], ["medkit", 20], ["repair_weapon", 30], ["repair_gear", 25]]


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
	if sell_win and sell_win.open:
		sell_win.close()
	opened = false
	if ui:
		ui.visible = false
	if game and game.player:
		game.player.active = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(e: InputEvent) -> void:
	if sell_win and sell_win.open:
		return   # Esc / E закрывает сначала окно продажи (sell_window.gd)
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
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 12)
	panel.add_child(cols)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	cols.add_child(box)
	var head := _label("TRINKETS MARKET", 24, Color(0.55, 1.0, 0.6))
	head.add_theme_font_override("font", sign_font())
	box.add_child(head)
	coins_l = _label("", 17, Color(0.92, 0.8, 0.5))
	box.add_child(coins_l)
	markup_l = _label("", 14, Color(1.0, 0.88, 0.85))
	var msb := StyleBoxFlat.new()
	msb.bg_color = Color(0.55, 0.06, 0.04, 0.9)
	msb.set_content_margin_all(6)
	msb.set_corner_radius_all(3)
	markup_l.add_theme_stylebox_override("normal", msb)
	markup_l.visible = false
	markup_l.custom_minimum_size = Vector2(408, 0)
	box.add_child(markup_l)
	# вкладки-категории
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 3)
	box.add_child(tabs)
	var group := ButtonGroup.new()
	for i in TABS.size():
		var tb := Button.new()
		tb.text = TABS[i]
		tb.toggle_mode = true
		tb.button_group = group
		tb.button_pressed = i == tab
		tb.focus_mode = Control.FOCUS_NONE
		tb.add_theme_font_size_override("font_size", 14)
		tb.pressed.connect(_show_tab.bind(i))
		tabs.add_child(tb)
		tab_btns.append(tb)
	# вкладка прокручивается, если не влезает (на «Слот-Машине» много строк)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(412, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6)
	scroll.add_child(content)
	# подсказка у курсора: название, описание, причина недоступности (промпт 14.11 19:26)
	tip_panel = PanelContainer.new()
	tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(0.05, 0.04, 0.03, 0.96)
	tsb.border_color = Color(0.95, 0.6, 0.3, 0.9)
	tsb.set_border_width_all(1)
	tsb.set_corner_radius_all(4)
	tsb.set_content_margin_all(8)
	tip_panel.add_theme_stylebox_override("panel", tsb)
	tip_l = RichTextLabel.new()
	tip_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_l.bbcode_enabled = true
	tip_l.fit_content = true
	tip_l.scroll_active = false
	tip_l.custom_minimum_size = Vector2(260, 0)
	tip_l.add_theme_font_size_override("normal_font_size", 14)
	tip_l.add_theme_font_size_override("bold_font_size", 16)
	tip_l.add_theme_color_override("default_color", Color(0.88, 0.86, 0.8))
	tip_panel.add_child(tip_l)
	tip_panel.visible = false
	ui.add_child(tip_panel)
	info_l = _label("", 15, Color(0.8, 0.78, 0.7))
	info_l.custom_minimum_size = Vector2(408, 0)
	box.add_child(info_l)
	# внизу: обновить все ящики уровня (сейф не трогаем) и закрыть
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 6)
	box.add_child(bottom)
	var close := Button.new()
	close.text = "Закрыть (E / Esc)"
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 16)
	close.pressed.connect(_close)
	bottom.add_child(close)
	# продажа (промпты 14.11 18:06, 18:35): кнопка в правом нижнем углу, пояснения — в самом окне продажи
	var sell_b := Button.new()
	sell_b.text = "Продажа"   # промпт 14.11 19:11
	sell_b.custom_minimum_size = Vector2(130, 0)
	sell_b.focus_mode = Control.FOCUS_NONE
	sell_b.add_theme_font_size_override("font_size", 16)
	sell_b.add_theme_color_override("font_color", Color(1.0, 0.7, 0.45))
	sell_b.pressed.connect(_open_sell)
	bottom.add_child(sell_b)


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
	var mp: int = game.markup_pct()
	markup_l.visible = mp > 0
	markup_l.text = "Наценка за мухлёж: +%d%% на следующую покупку (цены уже с ней)" % mp
	_rebuild_tab.call_deferred()   # кнопка, по которой кликнули, ещё в сигнале


func _show_tab(i: int) -> void:
	tab = i
	if i < tab_btns.size():
		tab_btns[i].set_pressed_no_signal(true)
	_rebuild_tab()


## Товары открытой вкладки: сетка в 3 колонки (промпт 14.11 19:10) — крупная иконка, под ней цена.
## Наведение (или долгий тап) — название и описание во всплывающем окошке у курсора; клик — купить.
## Недоступное затемнено, причина — в подсказке.
func _rebuild_tab() -> void:
	if content == null:
		return
	for c in content.get_children():
		content.remove_child(c)
		c.queue_free()
	_set_tip("")
	match tab:
		0, 1:
			var grid := _grid()
			for e in Weapons.SHOP:
				var id: String = e[0]
				if Items.ITEMS[id].get("weapon", false) == (tab == 0):
					_item_cell(grid, id, int(e[1]))
		2:
			var grid := _grid()
			for e in CONSUMABLES:
				_item_cell(grid, String(e[0]), int(e[1]))
		3:
			_build_slot_tab()


func _grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	content.add_child(g)
	return g


func _section(t: String) -> void:
	content.add_child(_label(t, 15, Color(1.0, 0.45, 0.3)))


func _can_pay(price: int) -> bool:
	return game.inv.count("coin") >= game.marked_price(price)


func _item_cell(grid: GridContainer, id: String, price: int) -> void:
	var reason := ""
	if Items.ITEMS[id].has("equip") and game.inv.count(id) > 0:
		reason = "Уже есть."
	elif not _can_pay(price):
		reason = "Не хватает монет."
	_cell(grid, func(ci: Control, r: Rect2): Items.draw_icon(ci, id, r), price,
		Items.item_name(id), Items.ITEMS[id]["desc"], reason, func(): _buy(id, price))


## Ячейка товара. draw_fn(ci, rect) рисует иконку; price < 0 — без цены (подпись в desc).
func _cell(grid: GridContainer, draw_fn: Callable, price: int, title: String, desc: String,
		reason: String, on_buy: Callable, price_text := "") -> void:
	var b := Button.new()
	b.custom_minimum_size = Vector2(130, 82)
	b.focus_mode = Control.FOCUS_NONE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.1, 0.08, 0.95)
	sb.border_color = Color(0.4, 0.28, 0.16, 0.8)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	var sh := sb.duplicate() as StyleBoxFlat
	sh.bg_color = Color(0.22, 0.16, 0.1, 0.95)
	sh.border_color = Color(0.95, 0.6, 0.3, 0.95)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sh)
	b.add_theme_stylebox_override("pressed", sh)
	var icon := Control.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.position = Vector2(41, 4)
	icon.size = Vector2(48, 48)
	icon.draw.connect(func(): draw_fn.call(icon, Rect2(Vector2.ZERO, icon.size)))
	b.add_child(icon)
	var pl := Label.new()
	pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pl.position = Vector2(0, 54)
	pl.size = Vector2(130, 24)
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pl.add_theme_font_size_override("font_size", 15)
	var red: bool = price >= 0 and game.markup_pct() > 0
	pl.text = price_text if price_text != "" else (_coins(game.marked_price(price)) if price >= 0 else "")
	pl.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4) if red else Color(0.95, 0.82, 0.5))
	b.add_child(pl)
	if reason != "":
		b.modulate = Color(0.5, 0.5, 0.5)
	var tip := "[b]%s[/b]\n%s" % [title, desc]
	if reason != "":
		tip += "\n[color=#ff8a70]%s[/color]" % reason
	b.mouse_entered.connect(func(): _set_tip(tip))
	b.mouse_exited.connect(func(): _set_tip(""))
	# долгий тап (телефон): показать подсказку и не покупать
	var held := [0]
	b.button_down.connect(func():
		held[0] = Time.get_ticks_msec()
		_set_tip(tip))
	b.button_up.connect(func():
		if Time.get_ticks_msec() - int(held[0]) > 450:
			tip_hide_t = 2.5)
	b.pressed.connect(func():
		if Time.get_ticks_msec() - int(held[0]) > 450:
			return
		if reason != "":
			info_l.text = reason
			game.play_ui("buzz", -14.0)
			return
		on_buy.call())
	grid.add_child(b)


## «1 монета», «3 монеты», «5 монет».
static func _coins(n: int) -> String:
	var m10 := n % 10
	var m100 := n % 100
	if m10 == 1 and m100 != 11:
		return "%d монета" % n
	if m10 >= 2 and m10 <= 4 and (m100 < 12 or m100 > 14):
		return "%d монеты" % n
	return "%d монет" % n


func _set_tip(t: String) -> void:
	if tip_l == null:
		return
	tip_hide_t = 0.0
	tip_panel.visible = t != ""
	if t != "":
		tip_l.text = t
		tip_panel.reset_size()
		_place_tip()


## Окошко подсказки — справа-снизу от курсора (пальца); у края экрана — с другой стороны.
func _place_tip() -> void:
	var vp := get_viewport().get_visible_rect().size
	var m := get_viewport().get_mouse_position()
	var sz := tip_panel.get_combined_minimum_size()
	var p := m + Vector2(18, 18)
	if p.x + sz.x > vp.x - 4:
		p.x = m.x - sz.x - 12
	if p.y + sz.y > vp.y - 4:
		p.y = m.y - sz.y - 12
	tip_panel.position = Vector2(clampf(p.x, 4, maxf(4, vp.x - sz.x - 4)), clampf(p.y, 4, maxf(4, vp.y - sz.y - 4)))


func _process(delta: float) -> void:
	if tip_panel == null or not tip_panel.visible:
		return
	if not opened:
		tip_panel.visible = false
		return
	if tip_hide_t > 0.0:
		tip_hide_t -= delta
		if tip_hide_t <= 0.0:
			tip_panel.visible = false
			return
	else:
		_place_tip()


## Вкладка «Слот-Машина»: прокачка окна KILLBOX, гарантированные символы ×1/×2/×3, шанс комбинации.
func _build_slot_tab() -> void:
	var SM := preload("res://slot_machine.gd")
	var SymS := preload("res://slot_symbols.gd")
	var slot = game.slot if game else null
	if slot == null:
		content.add_child(_label("Автомата нет", 18, Color(0.7, 0.7, 0.7)))
		return
	var lv: int = slot.level
	_section("ОКНО KILLBOX")
	var g1 := _grid()
	var nxt := mini(lv + 1, SM.MAX_LEVEL)
	var up_reason := ""
	var up_price: int = slot.upgrade_price()
	if lv >= SM.MAX_LEVEL:
		up_reason = "Уже максимум."
	elif not _can_pay(up_price):
		up_reason = "Не хватает монет."
	_cell(g1, func(ci: Control, r: Rect2): _draw_window(ci, r, nxt, lv), up_price if lv < SM.MAX_LEVEL else -1,
		"Окно %s → %s" % [SM.level_name(lv), SM.level_name(nxt)] if lv < SM.MAX_LEVEL else "Окно %s" % SM.level_name(lv),
		"Больше клеток — больше линий. С каждым окном в барабанах новый символ: арбуз на 2×3, алмаз на 3×3; семёрки (сейф) и шестёрки — только на 3×5.",
		up_reason, _buy_upgrade, "максимум" if lv >= SM.MAX_LEVEL else "")
	_section("ЗАЩИТА ОТ 666")
	var ga := _grid()
	var ap: int = SM.APPLE_PRICE
	_cell(ga, func(ci: Control, r: Rect2): Items.draw_icon(ci, "rot_apple", r), ap,
		"Гнилое яблоко", "Купи и скорми KILLBOX (E, глядя в пасть). При следующих «666» автомат не заберёт монеты — ни из кармана, ни из лотка; защита сгорает. Можно держать до 2. Шестёрки бывают только на окне 3×5. Сейчас защит: %d." % slot.shield,
		"" if _can_pay(ap) else "Не хватает монет.", func(): _buy("rot_apple", ap))
	var gmax: int = SM.GUAR_MAX[lv - 1]
	_section("ГАРАНТИРОВАННЫЙ СИМВОЛ ×1 / ×2 / ×3")
	var g2 := _grid()
	for sym in SM.LUCK:
		var d: Array = SM.LUCK[sym]
		var need: int = SM.sym_level(sym)
		var left := _luck_left(slot, sym)
		for k in range(1, 4):
			var price := int(d[k])
			var reason := ""
			if lv < need:
				reason = "Символа ещё нет — откроется на окне %s." % SM.level_name(need)
			elif k > gmax:
				reason = "×%d — с окна %s." % [k, SM.level_name(SM.GUAR_MAX.find(k) + 1)]
			elif not _can_pay(price):
				reason = "Не хватает монет."
			var desc := "На %d круток: после каждого прокрута %d таких символа встают в открытые клетки, где их нет (выигрыш не ломают)." % [int(d[0]), k]
			if left > 0:
				desc += " Сейчас действует ещё %d круток." % left
			_cell(g2, func(ci: Control, r: Rect2): _draw_sym(ci, r, sym, "×%d" % k), price,
				"Гарант: %s ×%d" % [SymS.NAMES[sym], k], desc, reason, _buy_luck.bind(sym, price, k))
	_section("ШАНС КОМБИНАЦИИ")
	var g3 := _grid()
	for sym in SM.BOOST:
		var d: Array = SM.BOOST[sym]
		var need: int = SM.sym_level(sym)
		var price := int(d[1])
		var reason := ""
		if lv < need:
			reason = "Символа ещё нет — откроется на окне %s." % SM.level_name(need)
		elif not _can_pay(price):
			reason = "Не хватает монет."
		var left := 0
		if slot.boost.has(sym):
			left = int(slot.boost[sym])
		var desc := "На %d круток %s чаще «липнет» к такому же слева — 3 в ряд выпадают заметно чаще." % [int(d[0]), SymS.NAMES[sym].to_lower()]
		if left > 0:
			desc += " Сейчас действует ещё %d круток." % left
		_cell(g3, func(ci: Control, r: Rect2): _draw_sym(ci, r, sym, "↑"), price,
			"Чаще: %s" % SymS.NAMES[sym], desc, reason, _buy_boost.bind(sym, price))


## Иконка символа автомата с подписью в углу (×2, ↑).
func _draw_sym(ci: Control, r: Rect2, sym: String, badge: String) -> void:
	preload("res://slot_symbols.gd").draw(ci, sym, r.grow(-4))
	var f := ThemeDB.fallback_font
	var p := Vector2(r.end.x - 26, r.end.y - 4)
	ci.draw_rect(Rect2(p + Vector2(-4, -18), Vector2(30, 22)), Color(0.1, 0.05, 0.03, 0.85))
	ci.draw_string(f, p, badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(1.0, 0.85, 0.4))


## Мини-сетка окна 3×5: открытые на уровне lv клетки — светлые, новые (уровень cur → lv) — оранжевые.
func _draw_window(ci: Control, r: Rect2, lv: int, cur: int) -> void:
	var SM := preload("res://slot_machine.gd")
	var cw := r.size.x / 5.0
	var chh := r.size.y / 3.0 * 0.8
	var y0 := r.position.y + r.size.y * 0.1
	ci.draw_rect(Rect2(r.position + Vector2(-2, y0 - r.position.y - 2), Vector2(r.size.x + 4, chh * 3 + 4)), Color(0.55, 0.42, 0.2))
	for row in 3:
		for c in 5:
			var col := Color(0.18, 0.18, 0.19)
			if SM.is_open(cur, row, c):
				col = Color(0.85, 0.8, 0.7)
			elif SM.is_open(lv, row, c):
				col = Color(1.0, 0.55, 0.2)
			ci.draw_rect(Rect2(r.position.x + c * cw + 1, y0 + row * chh + 1, cw - 2, chh - 2), col)


func _luck_left(slot, sym: String) -> int:
	if slot and slot.luck.has(sym):
		return int(slot.luck[sym]["left"])
	return 0


func _buy_upgrade() -> void:
	if game.slot == null:
		return
	var base: int = game.slot.upgrade_price()
	var extra: int = game.marked_price(base) - base
	if game.inv.count("coin") < base + extra:
		info_l.text = "Не хватает монет"
		game.play_ui("buzz", -14.0)
		return
	if game.slot.buy_upgrade():
		if extra > 0:
			game.inv.remove("coin", extra)
			game.markup_used()
		info_l.text = "Окно KILLBOX: %s" % game.slot.level_name(game.slot.level)
	else:
		info_l.text = "Не хватает монет"
	_refresh()


## Окно продажи поверх магазина.
func _open_sell() -> void:
	if sell_win == null:
		sell_win = load("res://sell_window.gd").new()
		sell_win.game = game
		sell_win.shop = self
		add_child(sell_win)
	sell_win.show_window()


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


func _buy_luck(sym: String, price: int, k := 1) -> void:
	if game.slot == null:
		return
	price = game.marked_price(price)
	if game.inv.count("coin") < price:
		info_l.text = "Не хватает монет"
		game.play_ui("buzz", -14.0)
		return
	game.inv.remove("coin", price)
	game.slot.add_luck(sym, k)
	game.markup_used()
	info_l.text = "Гарант: %s ×%d" % [preload("res://slot_symbols.gd").NAMES[sym], k]
	game.play_ui("coin", -10.0)
	_refresh()


func _buy_boost(sym: String, price: int) -> void:
	if game.slot == null:
		return
	price = game.marked_price(price)
	if game.inv.count("coin") < price:
		info_l.text = "Не хватает монет"
		game.play_ui("buzz", -14.0)
		return
	game.inv.remove("coin", price)
	game.slot.add_boost(sym)
	game.markup_used()
	info_l.text = "Шанс комбинации: %s" % preload("res://slot_symbols.gd").NAMES[sym]
	game.play_ui("coin", -10.0)
	_refresh()


func _buy(id: String, price: int) -> void:
	price = game.marked_price(price)
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
	if game.markup_pct() > 0:
		info_l.text += " (с наценкой +%d%%)" % game.markup_pct()
	game.markup_used()
	_vend(id)
	if id == "gasmask" and game.gasmask:
		game.gasmask.on_bought()
	game.play_ui("coin", -10.0)
	_refresh()
