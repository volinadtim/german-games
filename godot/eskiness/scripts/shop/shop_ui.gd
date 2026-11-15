extends "res://scripts/shop/shop_model.gd"
# Часть shop.gd: окно магазина — вкладки, сетка товаров, подсказки, вкладка «Слот-Машина».


func _close() -> void:
	if sell_win and sell_win.open:
		sell_win.close()
	opened = false
	if ui:
		ui.visible = false
	if game and game.player:
		game.player.active = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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
	coins_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	box.add_child(coins_l)
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
	content.custom_minimum_size = Vector2(400, 0)
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
	info_l.custom_minimum_size = Vector2(408, 22)
	info_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	info_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
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


func _label(t: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _refresh() -> void:
	coins_l.text = "Монет: %d" % game.inv.count("coin")
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
		0:
			var grid := _grid()
			for e in Weapons.SHOP:
				var id: String = e[0]
				if Items.ITEMS[id].get("weapon", false):
					_item_cell(grid, id, int(e[1]))
		1:
			_sub_tabs()
			var grid := _grid()
			for id in CLOTHES[sub][1]:
				_item_cell(grid, String(id), _price(String(id)))
		2:
			var grid := _grid()
			for e in CONSUMABLES:
				if not String(e[0]) in CLOTHES[4][1]:
					_item_cell(grid, String(e[0]), int(e[1]))
		3:
			_build_slot_tab()


## Ряд подвкладок «Одежды» (внутри прокрутки, ширина ≤ 400 — окно не растёт).
func _sub_tabs() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	content.add_child(row)
	var group := ButtonGroup.new()
	for i in CLOTHES.size():
		var b := Button.new()
		b.text = CLOTHES[i][0]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == sub
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(func():
			sub = i
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
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	content.add_child(l)


func _can_pay(price: int) -> bool:
	return game.inv.count("coin") >= price


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
	pl.text = price_text if price_text != "" else (_coins(price) if price >= 0 else "")
	pl.add_theme_color_override("font_color", Color(0.95, 0.82, 0.5))
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
		return int(slot.luck[sym]["left"])
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
		sell_win = load("res://sell_window.gd").new()
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
