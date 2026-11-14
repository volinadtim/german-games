extends CanvasLayer
## HUD (тестовые механики): здоровье, монеты, заряд фонарика, прицел-точка, подсказка «[E] …»,
## всплывающие сообщения, красная виньетка при уроне и экран смерти.
## Сообщения: важные (деньги, урон, кровотечение, блок, поломки, KILLBOX) — крупно внизу по центру над хотбаром,
## стопкой, с плавным появлением; остальные — мелко слева сверху. Важность — параметр toast(..., important)
## или по тексту сообщения (IMPORTANT_WORDS), чтобы старые вызовы работали без правок.

const Items := preload("res://items.gd")

## прицел-точка в центре (меню «Настройки» → «Прицел»)
static var show_crosshair := true
var hp := 100.0
var hp_max := 100.0
var hp_lag := 100.0          # «догоняющая» светлая полоска
var coins := 0
var battery := 1.0
var light_on := false
var has_light := false     # фонарик есть в инвентаре — показываем заряд
signal restart_pressed
signal menu_pressed      # экран победы → «В главное меню»
var restart_b: Button
var knuckles := false
var inv  # inventory.gd — для хотбара 1–5
var cheat_l: Label
var bleed := 0.0          # сколько ещё течёт кровь (game.gd: _glass)
var buffs := {}           # активные баффы (game.gd: buffs)
var hurt := 0.0
var t := 0.0

var paint: Control
var prompt_l: Label
var toasts: VBoxContainer
var big_toasts: VBoxContainer   # важные — внизу по центру
var dmg_acc := 0.0               # копим урон от ударов, чтобы показать одной строкой
var dmg_t := 0.0
const IMPORTANT_WORDS := ["монет", "+", "KILLBOX", "777", "шестёр", "Кровотеч", "Стекло", "Сломан", "БЛОК", "КРИТ", "урон", "сейф", "Сейф"]
var vignette: TextureRect
var death_bg: ColorRect
var death_l: Label


func _ready() -> void:
	layer = 0
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	vignette = TextureRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	var g := Gradient.new()
	g.set_color(0, Color(0.45, 0.0, 0.0, 0.0))
	g.set_offset(0, 0.55)
	g.set_color(1, Color(0.4, 0.02, 0.0, 0.9))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.05, 0.5)
	gt.width = 256
	gt.height = 256
	vignette.texture = gt
	vignette.modulate.a = 0.0
	root.add_child(vignette)

	paint = Control.new()
	paint.set_anchors_preset(Control.PRESET_FULL_RECT)
	paint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paint.draw.connect(_paint)
	root.add_child(paint)

	prompt_l = Label.new()
	prompt_l.set_anchors_preset(Control.PRESET_CENTER)
	prompt_l.position = Vector2(-300, 50)
	prompt_l.size = Vector2(600, 40)
	prompt_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_l.add_theme_font_size_override("font_size", 22)
	prompt_l.add_theme_color_override("font_color", Color(0.92, 0.88, 0.78))
	prompt_l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	prompt_l.add_theme_constant_override("outline_size", 6)
	root.add_child(prompt_l)

	toasts = VBoxContainer.new()
	toasts.position = Vector2(28, 24)
	toasts.add_theme_constant_override("separation", 4)
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toasts)

	big_toasts = VBoxContainer.new()
	big_toasts.anchor_left = 0.5
	big_toasts.anchor_right = 0.5
	big_toasts.anchor_top = 1.0
	big_toasts.anchor_bottom = 1.0
	big_toasts.offset_left = -420
	big_toasts.offset_right = 420
	big_toasts.offset_top = -330
	big_toasts.offset_bottom = -100
	big_toasts.alignment = BoxContainer.ALIGNMENT_END
	big_toasts.add_theme_constant_override("separation", 2)
	big_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(big_toasts)

	cheat_l = Label.new()
	cheat_l.anchor_left = 0.0
	cheat_l.anchor_right = 1.0
	cheat_l.anchor_top = 1.0
	cheat_l.anchor_bottom = 1.0
	cheat_l.offset_top = -130
	cheat_l.offset_bottom = -88
	cheat_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cheat_l.text = "Мухлёжники будут наказаны..."
	cheat_l.add_theme_font_size_override("font_size", 34)
	cheat_l.add_theme_color_override("font_color", Color(0.9, 0.1, 0.06))
	cheat_l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	cheat_l.add_theme_constant_override("outline_size", 8)
	cheat_l.visible = false
	root.add_child(cheat_l)

	death_bg = ColorRect.new()
	death_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	death_bg.color = Color(0.08, 0.0, 0.0, 0.0)
	death_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(death_bg)
	death_l = Label.new()
	death_l.set_anchors_preset(Control.PRESET_FULL_RECT)
	death_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	death_l.text = "ТЫ ПОГИБ"
	death_l.add_theme_font_size_override("font_size", 84)
	death_l.add_theme_color_override("font_color", Color(0.75, 0.2, 0.15))
	death_l.modulate.a = 0.0
	root.add_child(death_l)
	restart_b = Button.new()
	restart_b.text = "Начать заново"
	restart_b.add_theme_font_size_override("font_size", 30)
	restart_b.anchor_left = 0.5
	restart_b.anchor_right = 0.5
	restart_b.anchor_top = 0.5
	restart_b.anchor_bottom = 0.5
	restart_b.offset_left = -150
	restart_b.offset_right = 150
	restart_b.offset_top = 80
	restart_b.offset_bottom = 140
	restart_b.focus_mode = Control.FOCUS_NONE
	restart_b.visible = false
	restart_b.pressed.connect(func(): restart_pressed.emit())
	root.add_child(restart_b)


func _process(delta: float) -> void:
	t += delta
	if dmg_acc > 0.0:
		dmg_t -= delta
		if dmg_t <= 0.0:
			toast("−%d здоровья" % int(round(dmg_acc)), Color(1.0, 0.32, 0.25), true)
			dmg_acc = 0.0
	hp_lag = move_toward(hp_lag, hp, delta * 25.0) if hp_lag > hp else hp
	hurt = move_toward(hurt, 0.0, delta * 1.6)
	var low := 0.0
	if hp < hp_max * 0.3 and hp > 0.0:
		low = (0.25 + 0.15 * sin(t * 4.0)) * (1.0 - hp / (hp_max * 0.3))
	vignette.modulate.a = maxf(hurt, low)
	paint.queue_redraw()
	if cheat_l.visible:
		cheat_l.modulate.a = 0.75 + 0.25 * sin(t * 5.0)


func set_hp(v: float, mx: float) -> void:
	# заметный удар (а не тиканье яда или кровотечения) — копим и показываем внизу «−N»
	if v < hp - 0.5:
		dmg_acc += hp - v
		dmg_t = 0.3
	hp = v
	hp_max = mx


func set_coins(n: int) -> void:
	coins = n


func set_battery(v: float, on: bool) -> void:
	battery = v
	light_on = on


func prompt(text: String) -> void:
	if prompt_l.text != text:
		prompt_l.text = text


func hurt_flash(amount := 0.75) -> void:
	hurt = maxf(hurt, amount)


func toast(text: String, col := Color(0.88, 0.86, 0.8), important = null) -> void:
	var imp: bool = _is_important(text) if important == null else bool(important)
	if imp:
		_big_toast(text, col)
		return
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 5)
	toasts.add_child(l)
	while toasts.get_child_count() > 6:
		var old := toasts.get_child(0)
		toasts.remove_child(old)
		old.queue_free()
	var tw := l.create_tween()
	tw.tween_interval(2.4)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)


func _is_important(text: String) -> bool:
	for w in IMPORTANT_WORDS:
		if text.contains(w):
			return true
	return false


## Важное сообщение внизу по центру: выплывает снизу и проявляется, держится, тает. Новые — снизу стопки.
func _big_toast(text: String, col: Color) -> void:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(840, 38)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = text
	l.size = Vector2(840, 38)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 27)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 8)
	l.position.y = 14.0
	l.modulate.a = 0.0
	holder.add_child(l)
	big_toasts.add_child(holder)
	while big_toasts.get_child_count() > 4:
		var old := big_toasts.get_child(0)
		big_toasts.remove_child(old)
		old.queue_free()
	var tw := l.create_tween()
	tw.set_parallel()
	tw.tween_property(l, "modulate:a", 1.0, 0.18)
	tw.tween_property(l, "position:y", 0.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(2.6)
	tw.chain().tween_property(l, "modulate:a", 0.0, 0.7)
	tw.chain().tween_callback(holder.queue_free)


## Красная надпись внизу по центру, пока живы монстры-наказание.
func block_flash() -> void:
	toast("БЛОК!", Color(0.6, 0.85, 1.0), true)
	hurt = 0.0


func cheat_warning(on: bool) -> void:
	cheat_l.visible = on


func show_death(on: bool) -> void:
	restart_b.visible = on
	var tw := create_tween().set_parallel()
	tw.tween_property(death_bg, "color:a", 0.75 if on else 0.0, 1.2 if on else 0.6)
	tw.tween_property(death_l, "modulate:a", 1.0 if on else 0.0, 1.5 if on else 0.4)


## Кат-сцена (отъезд на машине, car.gd): прячем полоски, хотбар, прицел и сообщения.
func set_cinematic(on: bool) -> void:
	paint.visible = not on
	prompt_l.visible = not on
	toasts.visible = not on
	big_toasts.visible = not on
	cheat_l.visible = cheat_l.visible and not on


## Экран победы: экран темнеет, «ТЫ ВЫБРАЛСЯ», статистика и кнопки «В главное меню» / «Начать заново».
func show_win(stats: String) -> void:
	set_cinematic(true)
	var root: Control = paint.get_parent()
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.0, 0.0, 0.0)
	root.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	box.modulate.a = 0.0
	root.add_child(box)
	var title := Label.new()
	title.text = "ТЫ ВЫБРАЛСЯ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 84)
	title.add_theme_color_override("font_color", Color(0.92, 0.78, 0.5))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	title.add_theme_constant_override("outline_size", 10)
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Старая машина завелась с третьего раза и увезла тебя прочь от бункера."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 22)
	sub.add_theme_color_override("font_color", Color(0.72, 0.68, 0.6))
	box.add_child(sub)
	var st := Label.new()
	st.text = stats
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	st.add_theme_font_size_override("font_size", 24)
	st.add_theme_color_override("font_color", Color(0.85, 0.82, 0.74))
	box.add_child(st)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 18)
	box.add_child(gap)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	box.add_child(row)
	for b in [["В главное меню", func(): menu_pressed.emit()], ["Начать заново", func(): restart_pressed.emit()]]:
		var bt := Button.new()
		bt.text = b[0]
		bt.custom_minimum_size = Vector2(300, 60)
		bt.add_theme_font_size_override("font_size", 28)
		bt.focus_mode = Control.FOCUS_NONE
		bt.pressed.connect(b[1])
		row.add_child(bt)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween()
	tw.tween_property(bg, "color:a", 1.0, 2.2)
	tw.tween_property(box, "modulate:a", 1.0, 1.2)
	tw.tween_callback(func(): Input.mouse_mode = Input.MOUSE_MODE_VISIBLE)


func _paint() -> void:
	var sz := paint.size
	var f := ThemeDB.fallback_font
	# прицел — едва заметная точка
	if show_crosshair:
		paint.draw_circle(sz / 2.0, 2.0, Color(1, 1, 1, 0.35))

	# здоровье
	var x := 28.0
	# здоровье и хотбар — крупнее прежнего (~×1.25)
	var y := sz.y - 50.0
	var w := 330.0
	paint.draw_string_outline(f, Vector2(x, y - 9), "ЗДОРОВЬЕ  %d" % int(ceil(hp)), HORIZONTAL_ALIGNMENT_LEFT, -1, 19, 5, Color(0, 0, 0, 0.7))
	paint.draw_string(f, Vector2(x, y - 9), "ЗДОРОВЬЕ  %d" % int(ceil(hp)), HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(0.8, 0.78, 0.72))
	paint.draw_rect(Rect2(x - 2, y - 2, w + 4, 22), Color(0, 0, 0, 0.6))
	paint.draw_rect(Rect2(x, y, w * hp_lag / hp_max, 18), Color(0.85, 0.7, 0.55, 0.6))
	paint.draw_rect(Rect2(x, y, w * hp / hp_max, 18), Color(0.62, 0.12, 0.08))
	paint.draw_rect(Rect2(x, y, w * hp / hp_max, 5), Color(0.8, 0.25, 0.18))

	# кровотечение: мигающая капля справа от полоски здоровья
	if bleed > 0.0:
		var a := 0.55 + 0.45 * sin(t * 8.0)
		var dc := Vector2(x + w + 22, y + 9)
		paint.draw_circle(dc, 8.0, Color(0.85, 0.08, 0.05, a))
		paint.draw_colored_polygon(PackedVector2Array([dc + Vector2(-7, -3), dc + Vector2(7, -3), dc + Vector2(0, -18)]), Color(0.85, 0.08, 0.05, a))
		var bt := "КРОВОТЕЧЕНИЕ %d с" % int(ceil(bleed))
		paint.draw_string_outline(f, Vector2(x + w + 36, y + 14), bt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(0, 0, 0, 0.8))
		paint.draw_string(f, Vector2(x + w + 36, y + 14), bt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.0, 0.3, 0.22, 0.6 + 0.4 * a))

	# баффы еды и напитков: значок предмета, сила и таймер
	var bx0 := x
	for k in buffs:
		var bd: Dictionary = buffs[k]
		var r := Rect2(bx0, y - 130, 40, 40)
		paint.draw_rect(r, Color(0, 0, 0, 0.55))
		paint.draw_rect(r, Color(0.5, 0.8, 1.0, 0.8) if k == "speed" else Color(0.9, 0.75, 0.4, 0.8), false, 2.0)
		Items.draw_icon(paint, bd["icon"], r.grow(-6))
		var lbl := ("+%d%%" if k == "speed" else "−%d%%") % int(float(bd["power"]) * 100)
		paint.draw_string_outline(f, r.position + Vector2(0, -4), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 3, Color(0, 0, 0, 0.8))
		paint.draw_string(f, r.position + Vector2(0, -4), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.95, 0.9, 0.75))
		var tt := "%d" % int(ceil(float(bd["time"])))
		paint.draw_string_outline(f, r.position + Vector2(0, 38), tt, HORIZONTAL_ALIGNMENT_RIGHT, 38, 13, 3, Color(0, 0, 0, 0.8))
		paint.draw_string(f, r.position + Vector2(0, 38), tt, HORIZONTAL_ALIGNMENT_RIGHT, 38, 13, Color(1, 1, 1))
		bx0 += 48.0

	# монеты
	Items.draw_icon(paint, "coin", Rect2(x - 4, y - 72, 34, 34))
	var ct := "× %d" % coins
	paint.draw_string_outline(f, Vector2(x + 36, y - 48), ct, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 5, Color(0, 0, 0, 0.7))
	paint.draw_string(f, Vector2(x + 36, y - 48), ct, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.9, 0.78, 0.5))
	if knuckles:
		Items.draw_icon(paint, "knuckles", Rect2(x + 120, y - 72, 34, 34))

	# хотбар 1–5 внизу по центру
	if inv:
		var cell := 64.0
		var gap := 8.0
		var x0 := sz.x / 2.0 - (cell * 5 + gap * 4) / 2.0
		var y0 := sz.y - cell - 18.0
		for k in 5:
			var r := Rect2(x0 + k * (cell + gap), y0, cell, cell)
			var id: String = inv.hotbar[k]
			var cnt: int = inv.count(id) if id != "" else 0
			var worn: bool = id != "" and inv.equip.values().has(id)
			paint.draw_rect(r, Color(0, 0, 0, 0.5))
			paint.draw_rect(r, Color(0.95, 0.75, 0.4, 0.9) if worn else Color(1, 1, 1, 0.18), false, 2.0 if worn else 1.0)
			if id != "":
				Items.draw_icon(paint, id, r.grow(-11))
				if cnt == 0:
					paint.draw_rect(r.grow(-1), Color(0, 0, 0, 0.6))
				elif cnt > 1:
					paint.draw_string_outline(f, r.position + Vector2(0, cell - 5), str(cnt), HORIZONTAL_ALIGNMENT_RIGHT, cell - 5, 16, 4, Color(0, 0, 0, 0.8))
					paint.draw_string(f, r.position + Vector2(0, cell - 5), str(cnt), HORIZONTAL_ALIGNMENT_RIGHT, cell - 5, 16, Color(0.92, 0.9, 0.84))
			paint.draw_string_outline(f, r.position + Vector2(5, 17), str(k + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color(0, 0, 0, 0.8))
			paint.draw_string(f, r.position + Vector2(5, 17), str(k + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.8, 0.45))

	if has_light:
		# фонарик (справа снизу)
		var bx := sz.x - 28.0 - 140.0
		var by := sz.y - 46.0
		var lbl := "ФОНАРИК" + ("" if light_on else " (F)")
		paint.draw_string_outline(f, Vector2(bx, by - 8), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(0, 0, 0, 0.7))
		paint.draw_string(f, Vector2(bx, by - 8), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.8, 0.78, 0.72) if light_on else Color(0.55, 0.54, 0.5))
		paint.draw_rect(Rect2(bx - 2, by - 2, 144, 14), Color(0, 0, 0, 0.6))
		var bc := Color(0.75, 0.68, 0.4) if battery > 0.2 else Color(0.75, 0.3, 0.15)
		if not light_on:
			bc = bc.darkened(0.4)
		paint.draw_rect(Rect2(bx, by, 140 * battery, 10), bc)
