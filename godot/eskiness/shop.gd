extends StaticBody3D
## Магазин оружия ближнего боя (слева от игрового автомата): прилавок, стена с оружием, вывеска.
## E — открыть окно магазина; там покупка за монеты (оружие, противогаз, фильтры).
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


## Перед магазина — +Z.
func _build() -> void:
	var wood := _mat(Color(0.32, 0.22, 0.14))
	var dark := _mat(Color(0.16, 0.12, 0.09))
	# прилавок
	_box(Vector3(1.9, 0.95, 0.55), Vector3(0, 0.475, 0.45), wood, true)
	_box(Vector3(2.0, 0.05, 0.62), Vector3(0, 0.975, 0.45), dark)
	# задняя стенка-перфорация с оружием
	_box(Vector3(2.1, 2.1, 0.06), Vector3(0, 1.25, -0.2), _mat(Color(0.24, 0.2, 0.16)), true)
	for k in 6:
		_box(Vector3(2.0, 0.015, 0.02), Vector3(0, 0.45 + k * 0.35, -0.165), dark)
	var ids := ["bat", "pipe", "crowbar", "machete"]
	for i in ids.size():
		var w := Weapons.make(ids[i])
		w.position = Vector3(-0.72 + i * 0.48, 1.0, -0.13)
		w.rotation.z = 0.12 * (1 if i % 2 == 0 else -1)
		add_child(w)
		var tag := Label3D.new()
		tag.text = "%d" % Weapons.WEAPONS[ids[i]]["price"]
		tag.font_size = 40
		tag.pixel_size = 0.002
		tag.modulate = Color(0.95, 0.85, 0.5)
		tag.position = Vector3(-0.72 + i * 0.48, 0.82, -0.12)
		add_child(tag)
	# противогаз на прилавке
	var gm := Weapons.make("gasmask")
	gm.position = Vector3(0.62, 1.08, 0.42)
	gm.rotation.y = 0.5
	add_child(gm)
	# вывеска
	var sign_bg := _mat(Color(0.12, 0.05, 0.04))
	sign_bg.emission_enabled = true
	sign_bg.emission = Color(0.5, 0.12, 0.05)
	sign_bg.emission_energy_multiplier = 0.4
	_box(Vector3(1.5, 0.3, 0.04), Vector3(0, 2.45, -0.15), sign_bg)
	var title := Label3D.new()
	title.text = "СНАРЯЖЕНИЕ"
	title.font_size = 80
	title.pixel_size = 0.0019
	title.modulate = Color(1.0, 0.55, 0.3)
	title.outline_size = 0
	title.position = Vector3(0, 2.45, -0.12)
	add_child(title)
	# своя тусклая лампа
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.7, 0.45)
	l.light_energy = 0.7
	l.omni_range = 3.2
	l.position = Vector3(0, 2.2, 0.6)
	add_child(l)


func get_prompt(_game) -> String:
	return "E — магазин снаряжения"


func interact(g) -> void:
	game = g
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
	if opened and (e.is_action_pressed("ui_cancel") or e.is_action_pressed("interact")):
		get_viewport().set_input_as_handled()
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
	box.add_child(_label("МАГАЗИН СНАРЯЖЕНИЯ", 28, Color(1.0, 0.6, 0.35)))
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
	var rb := Button.new()
	rb.text = "Обновить все ящики — %d мон." % CHEST_REFRESH
	rb.tooltip_text = "Открытые ящики закроются и снова наполнятся лутом. Сейф не меняется."
	rb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rb.focus_mode = Control.FOCUS_NONE
	rb.add_theme_font_size_override("font_size", 20)
	rb.pressed.connect(_refresh_chests)
	bottom.add_child(rb)
	var close := Button.new()
	close.text = "Закрыть (E / Esc)"
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 20)
	close.pressed.connect(_close)
	bottom.add_child(close)


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
	if id == "gasmask" and game.gasmask:
		game.gasmask.on_bought()
	game.play_ui("coin", -10.0)
	_refresh()
