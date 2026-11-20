extends "res://scripts/shop/shop.gd"
## Второй Trinkets Market — в подвале деревни (промпт 16.11 00:17). Тот же магазин (товары, цены, продажа,
## вкладки), только стоит в другом месте. game.shop пока открыт этот — указывает на него (окно открыто →
## game.window_open() видит его), после закрытия — снова на магазин бункера.

var main_shop                         # магазин бункера (game.shop до открытия этого)


## красный Trinkets Market (промпт 16.11 03:04) — корпус, вывеска, свет и окно в красной гамме (shop_model._tint)
func _ready() -> void:
	red = true
	super()


func interact(g) -> void:
	if not opened and g.shop != self:
		main_shop = g.shop
		g.shop = self
	super(g)


func _close() -> void:
	super()
	if game and main_shop and game.shop == self:
		game.shop = main_shop


## «Слот-Машина» красного магазина (промпт 20.11 11:53): прокачек KILLBOX нет, пока одна покупка —
## бонуска CASHY BOX: сразу бонус-игра, цена ×BONUS_BUY от ставки (крутки по текущей ставке).
func _build_slot_tab() -> void:
	var v = game.get("village") if game else null
	var slot = v.bonus_slot if v else null
	if slot == null:
		content.add_child(_label("Автомата нет", 18, Color(0.7, 0.7, 0.7)))
		return
	_section("CASHY BOX")
	var g := _grid()
	var price: int = slot.bonus_buy_price()
	var reason: String = slot.bonus_buy_block()
	if reason == "" and not _can_pay(price):
		reason = "Не хватает монет."
	var desc := "Сразу запускает бонус-игру CASHY BOX: %d бесплатных круток, выигрыш ×2. Ставка ×%d, цена — ×%d от ставки (крутка %d монет)." % [
		slot.FREE_3, slot.bet, slot.BONUS_BUY, slot.COST * slot.bet]
	_cell(g, func(ci: Control, r: Rect2): slot.draw_bonus_icon(ci, r), price, "Бонуска CASHY BOX", desc, reason, _buy_bonus.bind(slot))
	# гаранты символов на несколько круток (промпт 20.11 18:07)
	_section("ГАРАНТЫ CASHY BOX")
	var g2 := _grid()
	var names := {"cherry": "вишня", "plum": "слива", "grape": "арбуз", "diamond": "алмаз"}
	for sym in slot.GUAR:
		var s := String(sym)
		var gp: int = slot.guar_price(s)
		var why := "CASHY BOX крутится — подожди." if slot.busy else ("Не хватает монет." if not _can_pay(gp) else "")
		var left := int(slot.guar.get(s, 0))
		var d2 := "Каждую крутку (и бесплатную) один символ «%s» встаёт на поле. %d круток, цена по ставке ×%d. Пока действует — ставку не сменить.%s" % [
			names.get(s, s), int(slot.GUAR[s][0]), slot.bet, (" Осталось: %d." % left) if left > 0 else ""]
		_cell(g2, func(ci: Control, r: Rect2): slot.draw_sym_icon(ci, s, r), gp, "Гарант: %s ×%d" % [names.get(s, s), int(slot.GUAR[s][0])], d2, why, _buy_guar.bind(slot, s))


## Покупка гаранта символа CASHY BOX.
func _buy_guar(slot, sym: String) -> void:
	if slot.buy_guar(game, sym):
		info_l.text = "Гарант куплен: %d круток" % int(slot.GUAR[sym][0])
		game.play_ui("coin", -10.0)
	else:
		info_l.text = "Не получилось купить"
		game.play_ui("buzz", -14.0)
	_refresh()


func _buy_bonus(slot) -> void:
	if slot.buy_bonus(game):
		info_l.text = "Бонус-игра CASHY BOX: %d круток ×2" % slot.FREE_3
		game.play_ui("coin", -10.0)
	else:
		info_l.text = "Не получилось купить"
		game.play_ui("buzz", -14.0)
	_refresh()
