extends Control
## Первая настройка картинки (промпт 00:20 16.11): при первом запуске, до главного меню, по шагам —
## 1) постеризация, 2) гамма и яркость. Превью живое: за меню — 3D-сцена, постобработка меняется сразу.
## Отметка «настроено» — [setup] done в user://settings.cfg (menu.gd: _save эту секцию не трогает).

const CFG := "user://settings.cfg"
## [заголовок, подсказка, ползунки]
const STEPS := [
	["Шаг 1 из 2 · Постеризация", "Сколько ступенек у цвета. Двигайте ползунок и смотрите на сцену за меню.", ["posterize"]],
	["Шаг 2 из 2 · Гамма и яркость", "Тени должны остаться тёмными, но детали в них — различимыми.", ["gamma", "brightness"]],
]

var menu        # menu.gd
var step := 0
var pages: Array = []
var title_l: Label
var hint_l: Label
var back_b: Button
var next_b: Button


static func done() -> bool:
	var cf := ConfigFile.new()
	return cf.load(CFG) == OK and bool(cf.get_value("setup", "done", false))


func _init(m) -> void:
	menu = m
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# панель внизу экрана — сцена над ней видна целиком
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_END
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var st: StyleBoxFlat = menu._style(Color(0.03, 0.02, 0.02, 0.82), Color(0.45, 0.08, 0.05, 0.85))
	st.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", st)
	col.add_child(panel)
	col.add_child(menu._gap(40))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	box.add_child(menu._title("НАСТРОЙКА КАРТИНКИ", 44))
	title_l = menu._subtitle("")
	box.add_child(title_l)
	hint_l = menu._subtitle("")
	box.add_child(hint_l)
	for s in STEPS:
		var pg := VBoxContainer.new()
		pg.add_theme_constant_override("separation", 6)
		for key in s[2]:
			pg.add_child(menu._slider_row(key))
		box.add_child(pg)
		pages.append(pg)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 16)
	btns.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(btns)
	back_b = menu._button("Назад", func(): _go(step - 1))
	next_b = menu._button("Далее", func(): _go(step + 1))
	for b in [back_b, next_b]:
		b.custom_minimum_size = Vector2(220, 52)
		btns.add_child(b)
	_go(0)


func _go(i: int) -> void:
	if i >= STEPS.size():
		_finish()
		return
	step = clampi(i, 0, STEPS.size() - 1)
	title_l.text = STEPS[step][0]
	hint_l.text = STEPS[step][1]
	for k in pages.size():
		pages[k].visible = k == step
	back_b.visible = step > 0
	next_b.text = ("Готово" if step == STEPS.size() - 1 else "Далее").to_upper()


func _finish() -> void:
	menu._save()
	var cf := ConfigFile.new()
	cf.load(CFG)
	cf.set_value("setup", "done", true)
	cf.save(CFG)
	menu.setup_finished()
