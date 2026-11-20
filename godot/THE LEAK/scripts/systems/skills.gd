extends CanvasLayer
## Древо прокачки (промпт 20.11 18:06): окно на K, навыки покупаются за монеты.
## Разделы добавляются через add_section() — активные навыки здесь, пассивные (удача, стамина…) может
## добавить другой скрипт: game.skills.add_section("ПАССИВНЫЕ", [{id, name, desc, cost, req}]).
## Купленное — owned {id: уровень}; проверка — has(id) / level(id). Сохраняется в сейв ("skills").

const WIN_CD := 10   # «двойной выигрыш»: после срабатывания ждёт столько наград

var game
var open := false
var owned := {}          # id → уровень (1 = куплен)
var win_cd := 0          # сколько наград осталось до перезарядки «двойного выигрыша»
var sections: Array = [] # [{title, items: [{id, name, desc, cost, req}]}]
var _cols: HBoxContainer
var _coins_l: Label


func _ready() -> void:
	layer = 20
	visible = false
	if not InputMap.has_action("skills"):
		InputMap.add_action("skills")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_K
		InputMap.action_add_event("skills", ev)
	add_section("АКТИВНЫЕ НАВЫКИ", [
		{"id": "slide", "name": "Подкат", "cost": 30,
			"desc": "Присед на бегу — скольжение, прыжок из него даёт рывок вперёд"},
		{"id": "double_jump", "name": "Двойной прыжок", "cost": 60, "req": "slide",
			"desc": "Ещё один прыжок в воздухе"},
		{"id": "double_win", "name": "Двойной выигрыш", "cost": 120, "req": "double_jump",
			"desc": "Следующая награда KILLBOX ×2. Перезарядка — %d наград" % WIN_CD},
	])
	_build()


## Добавить раздел навыков (колонку окна). items: [{id, name, desc, cost, req?}]
func add_section(title: String, items: Array) -> void:
	for s in sections:
		if s["title"] == title:
			s["items"] = items
			_rebuild()
			return
	sections.append({"title": title, "items": items})
	_rebuild()


## Куплен ли навык.
func has(id: String) -> bool:
	return int(owned.get(id, 0)) > 0


## Уровень навыка (0 — не куплен).
func level(id: String) -> int:
	return int(owned.get(id, 0))


## Награда KILLBOX своего спина: true — удвоить её (навык заряжен), иначе отсчёт перезарядки.
func on_reward() -> bool:
	if not has("double_win"):
		return false
	if win_cd <= 0:
		win_cd = WIN_CD
		if game and game.hud:
			game.hud.toast("Двойной выигрыш! Перезарядка — %d наград" % WIN_CD, Color(1.0, 0.85, 0.3))
		return true
	win_cd -= 1
	if win_cd == 0 and game and game.hud:
		game.hud.toast("Двойной выигрыш заряжен", Color(1.0, 0.85, 0.3))
	return false


## Данные для сейва.
func to_save() -> Dictionary:
	return {"owned": owned.duplicate(), "win_cd": win_cd}


## Загрузка из сейва.
func from_save(d: Dictionary) -> void:
	owned = {}
	var o: Dictionary = d.get("owned", {})
	for k in o:
		owned[String(k)] = int(o[k])
	win_cd = int(d.get("win_cd", 0))
	_rebuild()


## Открыть окно.
func show_window() -> void:
	if open or game == null or not game.alive or game.window_open():
		return
	open = true
	visible = true
	game.player.active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_rebuild()


## Закрыть окно.
func close() -> void:
	if not open:
		return
	open = false
	visible = false
	if game and game.player and game.alive:
		game.player.active = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(e: InputEvent) -> void:
	if e.is_echo() or not e.is_pressed():
		return
	if open:
		if e.is_action_pressed("skills") or e.is_action_pressed("ui_cancel") or e.is_action_pressed("inventory"):
			close()
			get_viewport().set_input_as_handled()
	elif e.is_action_pressed("skills"):
		show_window()
		if open:
			get_viewport().set_input_as_handled()


## Каркас окна: затемнение, панель, заголовок, монеты, колонки разделов.
func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(cc)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.07, 0.96)
	sb.border_color = Color(0.55, 0.45, 0.25)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", sb)
	cc.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var t := _label("ПРОКАЧКА", 28, Color(1.0, 0.82, 0.4))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(t)
	_coins_l = _label("", 20, Color(1.0, 0.85, 0.45))
	top.add_child(_coins_l)
	var x := Button.new()
	x.text = "  ✕  "
	x.focus_mode = Control.FOCUS_NONE
	x.pressed.connect(close)
	top.add_child(x)
	_cols = HBoxContainer.new()
	_cols.add_theme_constant_override("separation", 24)
	v.add_child(_cols)
	v.add_child(_label("K — закрыть", 14, Color(0.6, 0.6, 0.55)))
	_rebuild()


## Перестроить колонки навыков (после покупки, загрузки, нового раздела).
func _rebuild() -> void:
	if _cols == null:
		return
	for c in _cols.get_children():
		c.queue_free()
	if game and game.inv:
		_coins_l.text = "Монеты: %d   " % game.inv.coins
	for s in sections:
		var col := VBoxContainer.new()
		col.custom_minimum_size = Vector2(300, 0)
		col.add_theme_constant_override("separation", 10)
		_cols.add_child(col)
		col.add_child(_label(s["title"], 20, Color(0.86, 0.85, 0.8)))
		for it in s["items"]:
			col.add_child(_card(it))


## Карточка навыка: название, описание, кнопка покупки или статус.
func _card(it: Dictionary) -> Control:
	var id: String = it["id"]
	var box := VBoxContainer.new()
	var got := has(id)
	var req: String = it.get("req", "")
	var locked := req != "" and not has(req)
	var nm: String = it["name"]
	if id == "double_win" and got:
		nm += "  (заряжен)" if win_cd <= 0 else "  (ещё %d наград)" % win_cd
	box.add_child(_label(nm, 18, Color(0.5, 1.0, 0.55) if got else (Color(0.55, 0.55, 0.5) if locked else Color(0.95, 0.93, 0.88))))
	var d := _label(String(it.get("desc", "")), 14, Color(0.7, 0.7, 0.65))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(300, 0)
	box.add_child(d)
	if not got:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		var cost := int(it.get("cost", 0))
		if locked:
			b.text = "Сначала: %s" % _name_of(req)
			b.disabled = true
		else:
			b.text = "Изучить — %d монет" % cost
			b.disabled = game == null or game.inv == null or game.inv.coins < cost
			b.pressed.connect(func(): _buy(id, cost))
		box.add_child(b)
	return box


## Купить навык за монеты.
func _buy(id: String, cost: int) -> void:
	if has(id) or game == null or game.inv.coins < cost:
		return
	if cost > 0 and not game.inv.remove("coin", cost):
		return
	owned[id] = 1
	game.play_ui("coin", -8.0, 1.2)
	game.hud.toast("Навык изучен: %s" % _name_of(id), Color(0.5, 1.0, 0.55))
	if game.has_method("save_now"):
		game.call_deferred("save_now")
	_rebuild()


## Название навыка по id (из всех разделов).
func _name_of(id: String) -> String:
	for s in sections:
		for it in s["items"]:
			if it["id"] == id:
				return it["name"]
	return id


func _label(t: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l
