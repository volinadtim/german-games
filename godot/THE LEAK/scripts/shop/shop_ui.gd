extends "res://scripts/shop/shop_model.gd"
# Часть shop.gd: окно магазина — вкладки, сетка товаров, подсказки, вкладка «Слот-Машина».
const Perks := preload("res://scripts/systems/perks.gd")


func _close() -> void:
	if sell_win and sell_win.open:
		sell_win.close()
	opened = false
	if ui:
		ui.visible = false
	if game and game.player:
		game.player.active = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if not from_bench and game.has_method("shop_cue"):
			game.call_deferred("shop_cue")   # первый раз — камера к улице и звуки монстров (промпт 16.11 21:55)


## Окно в стиле лавки (промпт 15.11 23:10): полосатый навес с вывеской и крестиком справа сверху,
## категории — столбиком слева, справа — витрина с товарами; внизу ценник с монетами и кнопка «Продажа».
const C_GREEN := Color(0.16, 0.42, 0.22)
const C_CREAM := Color(0.86, 0.8, 0.62)
const C_WOOD := Color(0.24, 0.15, 0.08)
const SIGN_W := 330.0   # ширина таблички с названием на навесе


func _sb(bg: Color, border := Color(0, 0, 0, 0), bw := 0, r := 4, m := 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(r)
	sb.set_content_margin_all(m)
	return sb


func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 5
	add_child(ui)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent): preload("res://scripts/loot_window.gd")._click_away(dim, e, _close))   # клик мимо — закрыть (промпт 02:15)
	ui.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE   # клики мимо окна — в dim
	ui.add_child(center)
	var panel := PanelContainer.new()
	var psb := _sb(_tint(Color(0.1, 0.07, 0.045, 0.97)), _tint(Color(0.45, 0.3, 0.15)), 3, 6, 0)
	psb.shadow_color = Color(0, 0, 0, 0.5)
	psb.shadow_size = 12
	panel.add_theme_stylebox_override("panel", psb)
	center.add_child(panel)
	preload("res://scripts/ui/ui_fit.gd").attach(panel)   # окно в рамках экрана (промпт 00:32)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	panel.add_child(root)
	# навес: зелёно-кремовые полосы с фестонами снизу, на нём вывеска и крестик
	var awning := Control.new()
	awning.custom_minimum_size = Vector2(600, 62)
	awning.draw.connect(func(): _draw_awning(awning))
	root.add_child(awning)
	# вывеска: «#1» — бункер, «#2» — подвал деревни (промпт 04:36); шрифт ужимается, чтобы надпись
	# целиком влезала в табличку (SIGN_W); остальное окно масштабирует ui_fit, пропорции сохраняются
	var head := _label("TRINKETS MARKET #%d" % (2 if "main_shop" in self else 1), 30, _tint(Color(0.75, 1.0, 0.72)))
	head.add_theme_font_override("font", sign_font())
	head.add_theme_color_override("font_outline_color", _tint(Color(0.02, 0.08, 0.03)))
	head.add_theme_constant_override("outline_size", 6)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.autowrap_mode = TextServer.AUTOWRAP_OFF
	head.clip_text = true
	var fs := 30
	while fs > 12 and sign_font().get_string_size(head.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 6 > SIGN_W - 24:
		fs -= 1
	head.add_theme_font_size_override("font_size", fs)
	# по табличке: по центру навеса, сверху 8, высота 62 − 12 (фестоны) − 14
	head.anchor_left = 0.5
	head.anchor_right = 0.5
	head.offset_left = -SIGN_W / 2 + 4
	head.offset_right = SIGN_W / 2 - 4
	head.offset_top = 8
	head.offset_bottom = 44
	awning.add_child(head)
	var x := Button.new()
	x.focus_mode = Control.FOCUS_NONE
	preload("res://scripts/ui/key_hint.gd").attach(x, "Закрыть (F / Esc)", "Закрыть ({b:1})", "tooltip_text")
	x.custom_minimum_size = Vector2(34, 34)
	x.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	x.position = Vector2(600 - 42, 6)
	x.size = Vector2(34, 34)
	x.add_theme_stylebox_override("normal", _sb(Color(0.45, 0.1, 0.07), Color(0.95, 0.85, 0.6), 2, 17, 0))
	x.add_theme_stylebox_override("hover", _sb(Color(0.7, 0.15, 0.08), Color(1, 0.95, 0.7), 2, 17, 0))
	x.add_theme_stylebox_override("pressed", _sb(Color(0.35, 0.07, 0.05), Color(1, 0.95, 0.7), 2, 17, 0))
	x.draw.connect(func():
		var c := x.size / 2
		x.draw_line(c + Vector2(-7, -7), c + Vector2(7, 7), Color(1, 0.95, 0.85), 3.0, true)
		x.draw_line(c + Vector2(7, -7), c + Vector2(-7, 7), Color(1, 0.95, 0.85), 3.0, true))
	x.pressed.connect(_close)
	awning.add_child(x)
	var body_m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		body_m.add_theme_constant_override("margin_" + side, 10)
	root.add_child(body_m)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body_m.add_child(body)
	# слева: категории столбиком, под ними — ценник с монетами и «Продажа»
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(150, 0)
	left.add_theme_constant_override("separation", 4)
	body.add_child(left)
	var group := ButtonGroup.new()
	var names := tab_names()
	for i in names.size():
		var tb := Button.new()
		tb.text = names[i]
		tb.toggle_mode = true
		tb.button_group = group
		tb.button_pressed = i == tab
		tb.focus_mode = Control.FOCUS_NONE
		tb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		tb.custom_minimum_size = Vector2(150, 38)
		tb.add_theme_font_size_override("font_size", 16)
		tb.add_theme_stylebox_override("normal", _sb(_tint(Color(0.17, 0.11, 0.06)), _tint(Color(0.35, 0.24, 0.12)), 1, 4, 8))
		tb.add_theme_stylebox_override("hover", _sb(_tint(Color(0.25, 0.17, 0.09)), _tint(Color(0.7, 0.5, 0.25)), 1, 4, 8))
		var on := _sb(_tint(C_GREEN), _tint(Color(0.6, 1.0, 0.6)), 2, 4, 8)
		on.border_width_left = 6
		tb.add_theme_stylebox_override("pressed", on)
		tb.add_theme_stylebox_override("hover_pressed", on)
		tb.add_theme_color_override("font_color", C_CREAM)
		tb.add_theme_color_override("font_pressed_color", Color(1, 1, 0.9))
		tb.add_theme_color_override("font_hover_pressed_color", Color(1, 1, 0.9))
		tb.pressed.connect(_show_tab.bind(i))
		left.add_child(tb)
		tab_btns.append(tb)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)
	coins_l = _label("", 18, Color(0.25, 0.16, 0.05))
	coins_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	coins_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coins_l.add_theme_stylebox_override("normal", _sb(Color(0.93, 0.8, 0.45), Color(0.55, 0.38, 0.12), 2, 3, 6))
	left.add_child(coins_l)
	# продажа (промпты 14.11 18:06, 18:35): пояснения — в самом окне продажи
	var sell_b := Button.new()
	sell_b.text = "Продажа"
	sell_b.custom_minimum_size = Vector2(150, 38)
	sell_b.focus_mode = Control.FOCUS_NONE
	sell_b.add_theme_font_size_override("font_size", 17)
	sell_b.add_theme_color_override("font_color", Color(1.0, 0.8, 0.5))
	sell_b.add_theme_stylebox_override("normal", _sb(Color(0.4, 0.17, 0.07), Color(0.85, 0.5, 0.25), 2, 4, 6))
	sell_b.add_theme_stylebox_override("hover", _sb(Color(0.55, 0.24, 0.1), Color(1.0, 0.7, 0.35), 2, 4, 6))
	sell_b.add_theme_stylebox_override("pressed", _sb(Color(0.3, 0.12, 0.05), Color(1.0, 0.7, 0.35), 2, 4, 6))
	sell_b.pressed.connect(_open_sell)
	left.add_child(sell_b)
	# справа: витрина (тёмное дерево), прокрутка, если не влезает
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	body.add_child(right)
	var shelf := PanelContainer.new()
	shelf.add_theme_stylebox_override("panel", _sb(Color(0.06, 0.045, 0.03), _tint(C_WOOD.lightened(0.15)), 2, 4, 6))
	right.add_child(shelf)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(416, 330)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shelf.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.custom_minimum_size = Vector2(400, 0)
	content.add_theme_constant_override("separation", 6)
	scroll.add_child(content)
	info_l = _label("", 15, Color(0.8, 0.78, 0.7))
	info_l.custom_minimum_size = Vector2(416, 22)
	info_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	info_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	right.add_child(info_l)
	# подсказка у курсора: название, описание, причина недоступности (промпт 14.11 19:26)
	tip_panel = PanelContainer.new()
	tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_panel.add_theme_stylebox_override("panel", _sb(Color(0.05, 0.04, 0.03, 0.96), Color(0.95, 0.6, 0.3, 0.9), 1, 4, 8))
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


## Навес: полосы и полукруглые фестоны снизу.
func _draw_awning(ci: Control) -> void:
	var w := ci.size.x
	var hh := ci.size.y - 12.0
	var n := 12
	var sw := w / n
	for i in n:
		var col := _tint(C_GREEN) if i % 2 == 0 else C_CREAM
		ci.draw_rect(Rect2(i * sw, 0, sw, hh), col)
		ci.draw_circle(Vector2(i * sw + sw / 2, hh), sw / 2, col)
	ci.draw_rect(Rect2(0, 0, w, 5), _tint(Color(0.08, 0.2, 0.1)))
	ci.draw_rect(Rect2(0, hh - 2, w, 2), Color(0, 0, 0, 0.18))
	# вывеска-табличка под надпись
	var bw := SIGN_W
	ci.draw_rect(Rect2((w - bw) / 2, 8, bw, hh - 14), _tint(Color(0.05, 0.12, 0.06, 0.92)))
	ci.draw_rect(Rect2((w - bw) / 2, 8, bw, hh - 14), _tint(Color(0.5, 1.0, 0.55, 0.8)), false, 2.0)


func _label(t: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _refresh() -> void:
	coins_l.text = "◉ %s" % _coins(game.inv.count("coin"))
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
	var names := tab_names()
	match String(names[tab]) if tab < names.size() else "":
		"Оружие":
			# подвкладки «Огнестрел» (только деревня) и «Холодное оружие» (промпт 20.11 14:27)
			var melee: Array = []
			for e in Weapons.SHOP:
				if Items.ITEMS[String(e[0])].get("weapon", false):
					melee.append(String(e[0]))
			var subs := shown_subs([["Огнестрел", GUN_IDS], ["Холодное оружие", melee]])
			sub_g = clampi(sub_g, 0, subs.size() - 1)
			if subs.size() > 1:
				_sub_tabs(subs, sub_g, func(i: int): sub_g = i)
			var grid := _grid()
			for id in subs[sub_g][1]:
				if sells(String(id)):   # монтировка/мачете — не в бункере (04:35)
					_item_cell(grid, String(id), _price(String(id)))
		"Одежда":
			_sub_tabs(CLOTHES, sub, func(i: int): sub = i)
			var grid := _grid()
			for id in CLOTHES[sub][1]:
				if not sells(String(id)):
					continue
				_item_cell(grid, String(id), _price(String(id)))
		"Расходники":
			# подвкладки «Пропитание», «Медицина», «Починка» (промпт 16.11 02:57)
			var csubs := shown_subs(CONS_SUBS)   # «Патроны» — только в деревне
			sub_c = clampi(sub_c, 0, csubs.size() - 1)
			_sub_tabs(csubs, sub_c, func(i: int): sub_c = i)
			var grid := _grid()
			for id in csubs[sub_c][1]:
				# аптечки, тушёнка, газировка — только в магазине деревни (промпты 16.11 02:47, 03:13)
				if not sells(String(id)):
					continue
				_item_cell(grid, String(id), _price(String(id)))
		"Инструменты":
			var grid := _grid()
			for e in TOOLS:
				_item_cell(grid, String(e[0]), _price(String(e[0])))
		"Слот-Машина":
			_build_slot_tab()
		"Чертежи":
			_build_blueprint_tab()


## Ряд подвкладок (внутри прокрутки, ширина ≤ 400 — окно не растёт): list — [[название, товары], ...].
func _sub_tabs(list: Array, cur: int, pick: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	content.add_child(row)
	var group := ButtonGroup.new()
	for i in list.size():
		var b := Button.new()
		b.text = list[i][0]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == cur
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(func():
			pick.call(i)
			_rebuild_tab.call_deferred())
		row.add_child(b)



func _grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	content.add_child(g)
	return g


func _section(t: String) -> void:
	var l := _label(t, 15, Color(1.0, 0.45, 0.3))
	l.custom_minimum_size = Vector2(400, 0)   # длинный заголовок раздела — переносом, не за витрину
	content.add_child(l)


func _can_pay(price: int) -> bool:
	return game.inv.count("coin") >= price


func _item_cell(grid: GridContainer, id: String, price: int) -> void:
	price = Perks.cost(price)   # прокачка «Скидка» (systems/perks.gd)
	var reason := ""
	if not _can_pay(price):
		reason = "Не хватает монет."
	_cell(grid, func(ci: Control, r: Rect2): Items.draw_icon(ci, id, r), price,
		Items.item_name(id) + (" ×%d" % AMMO_PACK if id == "ammo" else ""), preload("res://scripts/ui/gamepad.gd").pad_text(Items.ITEMS[id]["desc"]), reason, func(): _buy(id, price))


## Замочек на закрытом товаре.
func _draw_lock(ci: Control, r: Rect2) -> void:
	var c := r.get_center()
	var col := Color(0.75, 0.62, 0.35)
	var dark := Color(0.2, 0.13, 0.07)
	ci.draw_arc(c + Vector2(0, -4), 9.0, PI, TAU, 16, col, 3.0)
	ci.draw_line(c + Vector2(-9, -4), c + Vector2(-9, 2), col, 3.0)
	ci.draw_line(c + Vector2(9, -4), c + Vector2(9, 2), col, 3.0)
	ci.draw_rect(Rect2(c + Vector2(-13, 2), Vector2(26, 18)), col)
	ci.draw_circle(c + Vector2(0, 9), 3.0, dark)
	ci.draw_rect(Rect2(c + Vector2(-1, 10), Vector2(2, 6)), dark)


## Ячейка товара. draw_fn(ci, rect) рисует иконку; price < 0 — без цены (подпись в desc).
func _cell(grid: GridContainer, draw_fn: Callable, price: int, title: String, desc: String,
		reason: String, on_buy: Callable, price_text := "") -> void:
	var b := Button.new()
	b.custom_minimum_size = Vector2(130, 82)
	b.focus_mode = Control.FOCUS_NONE
	var sb := _sb(_tint(Color(0.2, 0.13, 0.07, 0.95)), _tint(Color(0.42, 0.28, 0.14, 0.9)), 1, 4, 0)
	sb.border_width_bottom = 5
	var sh := _sb(_tint(Color(0.28, 0.19, 0.1, 0.95)), _tint(Color(0.6, 1.0, 0.6, 0.95)), 2, 4, 0)
	sh.border_width_bottom = 5
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
	pl.clip_text = true
	pl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	pl.text = price_text if price_text != "" else (_coins(price) if price >= 0 else "")
	pl.add_theme_color_override("font_color", Color(0.95, 0.82, 0.5))
	b.add_child(pl)
	if reason != "":
		b.modulate = Color(0.5, 0.5, 0.5)
	var tip := "[b]%s[/b]\n%s" % [title, desc]
	if title == "":
		tip = ""   # закрытый товар — без подсказки
	elif reason != "":
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


func _set_tip(t: String) -> void:
	if tip_l == null:
		return
	tip_hide_t = 0.0
	tip_panel.visible = t != ""
	if t != "":
		tip_l.text = t
		# ширина окошка по длине текста: короче текст — уже строки (промпт 18.11 02:33)
		tip_l.custom_minimum_size.x = clampf(140.0 + sqrt(float(t.length())) * 16.0, 190.0, 380.0)
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


## Вкладка «Слот-Машина»: прокачка окна KILLBOX, гарантированные символы ×1/×2/×3, шанс комбинации.
func _build_slot_tab() -> void:
	var SM := preload("res://scripts/slot/slot_machine.gd")
	var SymS := preload("res://scripts/slot/slot_symbols.gd")
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
		"Больше клеток — больше линий. С каждым окном в барабанах новый символ: арбуз на 2×3, алмаз на 3×4; семёрки (сейф) и шестёрки — только на 3×5.",
		up_reason, _buy_upgrade, "максимум" if lv >= SM.MAX_LEVEL else "")
	_section("ЗАЩИТА ОТ 666")
	var ga := _grid()
	var ap: int = Perks.cost(SM.APPLE_PRICE)
	if not SM.syms_for(lv).has("six"):
		# до шестёрок — замочек без подсказки (промпт 16.11 02:18)
		_cell(ga, _draw_lock, -1, "", "", "Закрыто.", func(): pass)
	else:
		_cell(ga, func(ci: Control, r: Rect2): Items.draw_icon(ci, "rot_apple", r), ap,
			"Гнилое яблоко", "Защищает от шестёрок. Его надо скормить KILLBOX.",
			"Уже куплено." if game.apple_bought else ("" if _can_pay(ap) else "Не хватает монет."),
			func():
				if not game.apple_bought and _can_pay(ap):
					game.apple_bought = true
					_buy("rot_apple", ap))
	var gmax: int = SM.GUAR_MAX[lv - 1]
	_section("ГАРАНТИРОВАННЫЙ СИМВОЛ ×1 / ×2 / ×3")
	var g2 := _grid()
	for sym in SM.LUCK:
		var d: Array = SM.LUCK[sym]
		var need: int = SM.sym_level(sym)
		var left := _luck_left(slot, sym)
		for k in range(1, d.size()):   # алмаз/семёрка — только ×1
			var price := Perks.cost(int(d[k]))
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
		var price := Perks.cost(int(d[1]))
		var reason := ""
		if lv < need:
			reason = "Символа ещё нет — откроется на окне %s." % SM.level_name(need)
		elif not _can_pay(price):
			reason = "Не хватает монет."
		var left := 0
		if slot.boost.has(sym):
			left = int(slot.boost[sym])
		var desc := "На %d круток %s чаще «липнет» к такому же — 3 в ряд и по диагонали выпадают заметно чаще." % [int(d[0]), SymS.NAMES[sym].to_lower()]
		if left > 0:
			desc += " Сейчас действует ещё %d круток." % left
		_cell(g3, func(ci: Control, r: Rect2): _draw_sym(ci, r, sym, "↑"), price,
			"Чаще: %s" % SymS.NAMES[sym], desc, reason, _buy_boost.bind(sym, price))


## Вкладка «Чертежи» (промпт 15.11 23:10): купить чертёж → построить дома из материалов (bunker_home.gd).
func _build_blueprint_tab() -> void:
	var home = game.home if game else null
	if home == null:
		content.add_child(_label("Дома нет", 18, Color(0.7, 0.7, 0.7)))
		return
	var hint := _label("Купи чертёж, собери материалы — и строй (здесь или у верстака дома).", 14, Color(0.7, 0.68, 0.6))
	content.add_child(hint)
	var g := _grid()
	for b in home.BLUEPRINTS:
		var id: String = b[0]
		var st: int = home.status(id)
		var desc := "%s\nМатериалы: %s." % [b[2], home.materials_text(id)]
		if bool(b[5]):
			desc += " Нужен верстак."
		var reason := ""
		var price := -1
		var ptxt := ""
		var title := "Чертёж: %s" % b[1]
		var cb: Callable
		if st == 0:
			price = Perks.cost(int(b[3]))
			reason = "" if _can_pay(price) else "Не хватает монет."
			cb = _buy_blueprint.bind(id, price)
		elif st == 1:
			reason = home.build_reason(id)
			ptxt = "Построить"
			cb = _build_bp.bind(id)
		else:
			reason = "Уже построено."
			ptxt = "Построено"
			cb = func(): pass
		_cell(g, func(ci: Control, r: Rect2): _draw_blueprint(ci, r, id, st), price, title, desc, reason, cb, ptxt)


func _buy_blueprint(id: String, price: int) -> void:
	if game.inv.count("coin") < price:
		info_l.text = "Не хватает монет"
		game.play_ui("buzz", -14.0)
		return
	game.inv.remove("coin", price)
	game.home.buy(id)
	info_l.text = "Чертёж куплен: %s" % game.home.info(id)[1]
	game.play_ui("coin", -10.0)
	_refresh()


func _build_bp(id: String) -> void:
	if game.home.build(id):
		info_l.text = "Построено: %s" % game.home.info(id)[1]
		game.hud.toast("Дома: %s" % game.home.info(id)[1], Color(0.7, 0.95, 0.7))
	_refresh()


## Иконка чертежа: синий лист в клетку с белым контуром постройки.
func _draw_blueprint(ci: Control, r: Rect2, id: String, st: int) -> void:
	var p := r.grow(-3)
	ci.draw_rect(p, Color(0.12, 0.3, 0.6) if st < 2 else Color(0.2, 0.4, 0.25))
	for k in range(1, 6):
		ci.draw_line(Vector2(p.position.x + p.size.x * k / 6.0, p.position.y), Vector2(p.position.x + p.size.x * k / 6.0, p.end.y), Color(1, 1, 1, 0.12))
		ci.draw_line(Vector2(p.position.x, p.position.y + p.size.y * k / 6.0), Vector2(p.end.x, p.position.y + p.size.y * k / 6.0), Color(1, 1, 1, 0.12))
	var c := p.get_center()
	var s := p.size.x
	var w := Color(0.95, 0.97, 1.0)
	match id:
		"workbench":
			ci.draw_rect(Rect2(c + Vector2(-s * 0.35, -s * 0.05), Vector2(s * 0.7, s * 0.08)), w, false, 2.0)
			ci.draw_line(c + Vector2(-s * 0.3, s * 0.03), c + Vector2(-s * 0.3, s * 0.32), w, 2.0)
			ci.draw_line(c + Vector2(s * 0.3, s * 0.03), c + Vector2(s * 0.3, s * 0.32), w, 2.0)
			ci.draw_rect(Rect2(c + Vector2(s * 0.12, -s * 0.18), Vector2(s * 0.12, s * 0.13)), w, false, 2.0)
		"clean":
			ci.draw_line(c + Vector2(s * 0.25, -s * 0.32), c + Vector2(-s * 0.05, s * 0.12), w, 2.0)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.05, s * 0.08), c + Vector2(s * 0.05, s * 0.16), c + Vector2(-s * 0.12, s * 0.34), c + Vector2(-s * 0.3, s * 0.2)]), Color(w, 0.6))
		"wallpaper":
			ci.draw_rect(Rect2(c - Vector2(s * 0.28, s * 0.3), Vector2(s * 0.56, s * 0.6)), w, false, 2.0)
			for k in 3:
				ci.draw_circle(c + Vector2(-s * 0.15 + k * s * 0.15, -s * 0.1 + (k % 2) * s * 0.2), s * 0.05, Color(1.0, 0.6, 0.6))
		"rug":
			ci.draw_rect(Rect2(c - Vector2(s * 0.34, s * 0.2), Vector2(s * 0.68, s * 0.4)), w, false, 2.0)
			ci.draw_polyline(PackedVector2Array([c + Vector2(0, -s * 0.13), c + Vector2(s * 0.2, 0), c + Vector2(0, s * 0.13), c + Vector2(-s * 0.2, 0), c + Vector2(0, -s * 0.13)]), w, 2.0)
		"cot":
			ci.draw_line(c + Vector2(-s * 0.36, 0), c + Vector2(s * 0.36, 0), w, 2.0)
			ci.draw_line(c + Vector2(-s * 0.3, 0), c + Vector2(-s * 0.15, s * 0.25), w, 2.0)
			ci.draw_line(c + Vector2(s * 0.3, 0), c + Vector2(s * 0.15, s * 0.25), w, 2.0)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.34, -s * 0.1), Vector2(s * 0.16, s * 0.08)), w, false, 2.0)
	if st == 2:
		ci.draw_polyline(PackedVector2Array([p.end - Vector2(s * 0.3, s * 0.18), p.end - Vector2(s * 0.2, s * 0.08), p.end - Vector2(s * 0.04, s * 0.3)]), Color(0.5, 1.0, 0.5), 3.0)


## Иконка символа автомата с подписью в углу (×2, ↑).
func _draw_sym(ci: Control, r: Rect2, sym: String, badge: String) -> void:
	preload("res://scripts/slot/slot_symbols.gd").draw(ci, sym, r.grow(-4))
	var f := ThemeDB.fallback_font
	var p := Vector2(r.end.x - 26, r.end.y - 4)
	ci.draw_rect(Rect2(p + Vector2(-4, -18), Vector2(30, 22)), Color(0.1, 0.05, 0.03, 0.85))
	ci.draw_string(f, p, badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(1.0, 0.85, 0.4))


## Мини-сетка окна 3×5: открытые на уровне lv клетки — светлые, новые (уровень cur → lv) — оранжевые.
func _draw_window(ci: Control, r: Rect2, lv: int, cur: int) -> void:
	var SM := preload("res://scripts/slot/slot_machine.gd")
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
		return slot.luck_total(sym)
	return 0


func _buy_upgrade() -> void:
	if game.slot == null:
		return
	var base: int = game.slot.upgrade_price()
	if game.inv.count("coin") < base:
		info_l.text = "Не хватает монет"
		game.play_ui("buzz", -14.0)
		return
	if game.slot.buy_upgrade():
		info_l.text = "Окно KILLBOX: %s" % game.slot.level_name(game.slot.level)
	else:
		info_l.text = "Не хватает монет"
	_refresh()


## Окно продажи поверх магазина.
func _open_sell() -> void:
	if sell_win == null:
		sell_win = load("res://scripts/sell_window.gd").new()
		sell_win.game = game
		sell_win.shop = self
		add_child(sell_win)
	sell_win.show_window()


func _buy_luck(sym: String, price: int, k := 1) -> void:
	if game.slot == null:
		return
	if game.inv.count("coin") < price:
		info_l.text = "Не хватает монет"
		game.play_ui("buzz", -14.0)
		return
	game.inv.remove("coin", price)
	game.slot.add_luck(sym, k)
	info_l.text = "Гарант: %s ×%d" % [preload("res://scripts/slot/slot_symbols.gd").NAMES[sym], k]
	game.play_ui("coin", -10.0)
	_refresh()


func _buy_boost(sym: String, price: int) -> void:
	if game.slot == null:
		return
	if game.inv.count("coin") < price:
		info_l.text = "Не хватает монет"
		game.play_ui("buzz", -14.0)
		return
	game.inv.remove("coin", price)
	game.slot.add_boost(sym)
	info_l.text = "Шанс комбинации: %s" % preload("res://scripts/slot/slot_symbols.gd").NAMES[sym]
	game.play_ui("coin", -10.0)
	_refresh()


func _buy(id: String, price: int) -> void:
	if game.inv.count("coin") < price:
		info_l.text = "Не хватает монет"
		game.play_ui("buzz", -14.0)
		return
	game.inv.remove("coin", price)
	if Items.ITEMS[id].has("equip"):
		# одежда/снаряжение (промпт 05:37): без лимита; надеть → в сумку → на пол, покупку не отменяем
		if id == "gasmask" and game.gasmask:
			game.gasmask.on_bought()
		var where: String = game.give_gear(id, -1.0, true)   # лучше надетого — сразу надевается
		info_l.text = "Куплено: %s%s" % [Items.item_name(id),
			{"equip": " — надето", "bag": " — в ячейках", "floor": " — на полу"}[where]]
		game.shop_bought.append(id)
		_vend(id)
		game.play_ui("coin", -10.0)
		_refresh()
		return
	var qty: int = AMMO_PACK if id == "ammo" else 1   # патроны — набором (05:11)
	# магазин продаётся пустым (05:11), пистолет — без магазина и целый (dur 0; прочность — gun.gd)
	var left: int = game.inv.add(id, qty, 0.0 if id in ["mag", "pistol"] else -1.0)
	info_l.text = "Куплено: %s" % Items.item_name(id)
	if left > 0:
		# нет места (общей сумки нет, промпт 16.11 06:03) — покупка на полу рядом
		var e := {"id": id, "n": left}
		if id == "mag" or id == "pistol":
			e["dur"] = 0.0
		game.drop_spilled([e])
		info_l.text += " — на полу"
	if Items.ITEMS[id].has("equip") or Items.ITEMS[id].get("weapon", false):
		game.shop_bought.append(id)
	_vend(id)
	if id == "gasmask" and game.gasmask:
		game.gasmask.on_bought()
	game.play_ui("coin", -10.0)
	_refresh()
