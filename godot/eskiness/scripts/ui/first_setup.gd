extends Control
## Первая настройка картинки (промпт 00:20 16.11): когда игрок впервые выбирает слот (промпт 00:31).
## Промпт 02:26: один общий ползунок яркости (сводит гамму и яркость) и эталон, как в других играх —
## три значка на чёрном: «едва видно», «видно», «хорошо видно». Значки считаются той же формулой, что и
## постобработка (post.gdshader), — меню поверх неё, поэтому цвет пересчитываем сами. Постеризация — селектор ниже.
## Превью живое: за меню — 3D-сцена. Отметка «настроено» — [setup] done в user://settings.cfg.

const CFG := "user://settings.cfg"
## Исходная яркость значков (0..1, как цвет на экране до постобработки); левый при 50% еле отличим от чёрного.
const REF := [0.022, 0.07, 0.17]
const REF_NAMES := ["едва видно", "видно", "хорошо видно"]

var menu        # menu.gd
var refs: Array = []
var val_l: Label


## Значок-эталон: ромб с вырезом и точкой на чёрной плашке.
class RefIcon extends Control:
	var lum := 0.0
	var bg := 0.0

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(bg, bg, bg))
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.36
		var col := Color(lum, lum, lum)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), col)
		var r2 := r * 0.55
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r2), c + Vector2(r2, 0), c + Vector2(0, r2), c + Vector2(-r2, 0)]), Color(bg, bg, bg))
		draw_circle(c, r * 0.17, col)


static func done() -> bool:
	var cf := ConfigFile.new()
	return cf.load(CFG) == OK and bool(cf.get_value("setup", "done", false))


## Общий ползунок t (0..1, середина — по умолчанию) -> [гамма, яркость].
static func curve(t: float) -> Vector2:
	if t < 0.5:
		var k := t * 2.0
		return Vector2(lerpf(0.7, 1.0, k), lerpf(0.85, 1.0, k))
	var k2 := (t - 0.5) * 2.0
	return Vector2(lerpf(1.0, 1.6, k2), lerpf(1.0, 1.25, k2))


## Обратно: положение ползунка по текущей гамме.
static func from_gamma(g: float) -> float:
	if g < 1.0:
		return clampf((g - 0.7) / 0.3 * 0.5, 0.0, 0.5)
	return clampf(0.5 + (g - 1.0) / 0.6 * 0.5, 0.5, 1.0)


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
	var st: StyleBoxFlat = menu._style(Color(0.03, 0.02, 0.02, 0.86), Color(0.45, 0.08, 0.05, 0.85))
	st.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", st)
	col.add_child(panel)
	col.add_child(menu._gap(40))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(640, 0)
	panel.add_child(box)
	box.add_child(menu._title("НАСТРОЙКА КАРТИНКИ", 44))
	box.add_child(menu._subtitle("Двигайте ползунок, пока левый значок не станет едва различим."))

	# эталон: три значка с подписями
	var ref_row := HBoxContainer.new()
	ref_row.alignment = BoxContainer.ALIGNMENT_CENTER
	ref_row.add_theme_constant_override("separation", 18)
	box.add_child(ref_row)
	for i in REF.size():
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		ref_row.add_child(cell)
		var ic := RefIcon.new()
		ic.custom_minimum_size = Vector2(150, 110)
		cell.add_child(ic)
		refs.append(ic)
		var cap: Label = menu._subtitle(REF_NAMES[i])
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.add_theme_font_size_override("font_size", 19)
		cell.add_child(cap)

	# общий ползунок яркости
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	row.add_child(menu._row_name("Яркость"))
	var s: HSlider = menu.make_slider(0.0, 1.0, 0.01, from_gamma(float(menu.values["gamma"])))
	row.add_child(s)
	val_l = menu.value_label()
	row.add_child(val_l)
	s.value_changed.connect(_on_slider)

	box.add_child(menu.setting_row("posterize"))

	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(btns)
	var ok_b: Button = menu._button("Готово", _finish)
	ok_b.custom_minimum_size = Vector2(220, 52)
	btns.add_child(ok_b)
	_on_slider(s.value, false)


func _on_slider(t: float, apply := true) -> void:
	val_l.text = "%d%%" % int(round(t * 100.0))
	if apply:
		var gb := curve(t)
		menu.values["gamma"] = gb.x
		menu.values["brightness"] = gb.y
		menu.apply_settings()
	_update_refs()


## Цвет значков — как его выдаст post.gdshader при текущих яркости, контрасте и гамме.
func _update_refs() -> void:
	for i in refs.size():
		refs[i].lum = _post(REF[i])
		refs[i].bg = _post(0.0)
		refs[i].queue_redraw()


func _post(x: float) -> float:
	var v: Dictionary = menu.values
	var c: float = x * float(v["brightness"])
	c = clampf((c - 0.5) * float(v["contrast"]) + 0.5, 0.0, 1.0)
	return pow(c, 1.0 / float(v["gamma"]))


func _finish() -> void:
	menu._save()
	var cf := ConfigFile.new()
	cf.load(CFG)
	cf.set_value("setup", "done", true)
	cf.save(CFG)
	menu.setup_finished()
