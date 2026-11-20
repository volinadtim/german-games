extends "res://scripts/shop/shop_ui.gd"
## Магазин снаряжения «Trinkets Market» — зелёный торговый автомат слева от KILLBOX.
## E — открыть окно: покупка за монеты по вкладкам (промпт 14.11 17:21): «Оружие», «Одежда» (снаряжение),
## «Расходники» (еда, хилки, батарейки), «Слот-Машина» (окно KILLBOX и гарантированные символы) — порядок и имя с промпта 14.11 18:35;
## справа — кнопка окна продажи (sell_window.gd, промпт 14.11 18:06: почти всё за полцены).
## Интерфейс взаимодействия (его дёргает game.gd): get_prompt(game) -> String, interact(game).


func _ready() -> void:
	_build()


func get_prompt(_game) -> String:
	if not powered:
		return ""
	return "[F] Trinkets Market"


## Питание (промпт 16.11 04:30): в новой игре магазин выключен — экран, вывеска и свет погашены,
## E не работает; включается со звуком, как KILLBOX, после первых круток (slot_machine.gd).
var powered := true
var _glow_e := {}


func _power_parts() -> Array:
	var mats: Array = []
	var lights: Array = []
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is Light3D:
			lights.append(n)
		elif n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var list: Array = [mi.material_override]
			if mi.mesh:
				for i in mi.mesh.get_surface_count():
					list.append(mi.get_surface_override_material(i))
					list.append(mi.mesh.surface_get_material(i))
			for m in list:
				if m is StandardMaterial3D and (m as StandardMaterial3D).emission_enabled and not m in mats:
					mats.append(m)
	return [mats, lights]


func set_powered(on: bool, fx := false) -> void:
	if on == powered and not fx:
		return
	var parts := _power_parts()
	if not on:
		powered = false
		if opened:
			_close()
		for m in parts[0]:
			if not _glow_e.has(m):
				_glow_e[m] = (m as StandardMaterial3D).emission_energy_multiplier
			(m as StandardMaterial3D).emission_energy_multiplier = 0.0
		for l in parts[1]:
			(l as Light3D).visible = false
		return
	if not fx:
		_power_apply(parts, true)
		return
	if game:
		game.play_at("clunk", global_position + Vector3(0, 1.0, 0.4), -8.9, 0.8)
		game.play_at("buzz", global_position + Vector3(0, 1.2, 0.4), -14.9, 0.9)
	var tw := create_tween()
	for k in [true, false, true, false]:
		tw.tween_callback(_power_apply.bind(parts, k))
		tw.tween_interval(0.07 if k else 0.12)
	tw.tween_callback(_power_apply.bind(parts, true))
	tw.tween_callback(func():
		if game:
			game.play_at("jingle", global_position + Vector3(0, 1.2, 0.4), -12.9)
			game.hud.toast("Trinkets Market заработал", Color(0.55, 1.0, 0.6)))


func _power_apply(parts: Array, on: bool) -> void:
	powered = on
	for m in parts[0]:
		(m as StandardMaterial3D).emission_energy_multiplier = float(_glow_e.get(m, 1.0)) if on else 0.0
	for l in parts[1]:
		(l as Light3D).visible = on


## Открыть магазин сразу на вкладке i (верстак дома открывает «Чертежи»).
func open_tab(g, i: int) -> void:
	game = g
	if opened:
		return
	_last_toggle = Time.get_ticks_msec()
	tab = i
	from_bench = true
	_open()
	_show_tab(i)


func interact(g) -> void:
	game = g
	if not powered and not opened:
		return
	if Time.get_ticks_msec() - _last_toggle < 350:
		return
	_last_toggle = Time.get_ticks_msec()
	if opened:
		_close()
	else:
		from_bench = false
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
	if opened and (Controls.event(e, "ui_cancel") or Controls.event(e, "interact") or Controls.event(e, "inventory")):
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
	var n_open := 0
	for c in game.chests:
		if is_instance_valid(c) and c.opened:
			n_open += 1
	if n_open == 0:
		info_l.text = "Все ящики и так закрыты"
		return
	if game.inv.count("coin") < CHEST_REFRESH:
		info_l.text = "Не хватает монет"
		game.play_ui("buzz", -14.0)
		return
	game.inv.remove("coin", CHEST_REFRESH)
	game.refresh_chests()
	info_l.text = "Ящики обновлены: %d" % n_open
	game.hud.toast("Ящики на уровне снова полны", Color(0.9, 0.8, 0.55))
	game.play_ui("creak", -10.0, 0.8)
	_refresh()
