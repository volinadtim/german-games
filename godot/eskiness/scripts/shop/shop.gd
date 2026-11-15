extends "res://scripts/shop/shop_ui.gd"
## Магазин снаряжения «Trinkets Market» — зелёный торговый автомат слева от KILLBOX.
## E — открыть окно: покупка за монеты по вкладкам (промпт 14.11 17:21): «Оружие», «Одежда» (снаряжение),
## «Расходники» (еда, хилки, батарейки), «Слот-Машина» (окно KILLBOX и гарантированные символы) — порядок и имя с промпта 14.11 18:35;
## справа — кнопка окна продажи (sell_window.gd, промпт 14.11 18:06: почти всё за полцены).
## Интерфейс взаимодействия (его дёргает game.gd): get_prompt(game) -> String, interact(game).


func _ready() -> void:
	_build()


func get_prompt(_game) -> String:
	return "[E] Trinkets Market"


## Открыть магазин сразу на вкладке i (верстак дома открывает «Чертежи»).
func open_tab(g, i: int) -> void:
	game = g
	if opened:
		return
	_last_toggle = Time.get_ticks_msec()
	tab = i
	_open()
	_show_tab(i)


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


func _input(e: InputEvent) -> void:
	if sell_win and sell_win.open:
		return   # Esc / E закрывает сначала окно продажи (sell_window.gd)
	if opened and (e.is_action_pressed("ui_cancel") or e.is_action_pressed("interact") or e.is_action_pressed("inventory")):
		get_viewport().set_input_as_handled()
		if e.is_echo() or Time.get_ticks_msec() - _last_toggle < 350:
			return
		_last_toggle = Time.get_ticks_msec()
		_close()


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
