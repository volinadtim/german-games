extends CanvasLayer
## HUD (тестовые механики): здоровье, монеты, заряд фонарика, прицел-точка, подсказка «[E] …»,
## всплывающие сообщения, красная виньетка при уроне и экран смерти.
## Сообщения: важные (деньги, урон, кровотечение, блок, поломки, KILLBOX) — крупно внизу по центру над хотбаром,
## стопкой, с плавным появлением; остальные — мелко слева сверху. Важность — параметр toast(..., important)
## или по тексту сообщения (IMPORTANT_WORDS), чтобы старые вызовы работали без правок.

const Items := preload("res://scripts/items.gd")

## прицел-точка в центре (меню «Настройки» → «Прицел»)
static var show_crosshair := true
static var gun_cross := false   # пистолет в руке — прицел рисует gun.gd
var hp := 100.0
var hp_max := 100.0
var hp_lag := 100.0          # «догоняющая» светлая полоска
var hp_full_t := 0.0         # сколько времени здоровье уже полное — для задержки перед угасанием (промпт 18.11 02:16)
var hp_alpha := 1.0          # прозрачность полоски здоровья: угасает, если давно полная, во всех режимах
var coins := 0
var battery := 1.0
var light_on := false
var minimal := false      # режим «Реализм» (game.gd: mode): только полоска здоровья и подсказки
var has_light := false     # фонарик есть в инвентаре — показываем заряд
signal restart_pressed
signal menu_pressed      # экран победы → «В главное меню»
var death_on := false            # показан экран смерти — курсор держим видимым (game.gd _process)
var restart_b: Button
var death_menu_b: Button
var knuckles := false
var inv  # inventory.gd — для хотбара 1–5
var hand := ""            # предмет из хотбара в руке (game_items.gd: hb_hand) — подсвечиваем ячейку
var bleed := 0.0          # сколько ещё течёт кровь (game.gd: _glass)
var buffs := {}           # активные баффы (game.gd: buffs)
var hurt := 0.0
var hit_edge := 0.0        # короткое покраснение по краям от удара (промпт 04:26)
var hit_vig: TextureRect
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
	# покраснение краёв от удара: узкая яркая кайма, гаснет за ~0.3 с
	hit_vig = TextureRect.new()
	hit_vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	hit_vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hit_vig.stretch_mode = TextureRect.STRETCH_SCALE
	var hg := Gradient.new()
	hg.set_color(0, Color(0.8, 0.0, 0.0, 0.0))
	hg.set_offset(0, 0.68)
	hg.set_color(1, Color(0.85, 0.04, 0.02, 0.75))
	var hgt := GradientTexture2D.new()
	hgt.gradient = hg
	hgt.fill = GradientTexture2D.FILL_RADIAL
	hgt.fill_from = Vector2(0.5, 0.5)
	hgt.fill_to = Vector2(1.0, 0.5)
	hgt.width = 256
	hgt.height = 256
	hit_vig.texture = hgt
	hit_vig.modulate.a = 0.0
	root.add_child(hit_vig)

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
	death_menu_b = Button.new()   # «Выйти в главное меню» под «Начать заново» (промпт 03:18)
	death_menu_b.text = "Выйти в главное меню"
	death_menu_b.add_theme_font_size_override("font_size", 26)
	death_menu_b.anchor_left = 0.5
	death_menu_b.anchor_right = 0.5
	death_menu_b.anchor_top = 0.5
	death_menu_b.anchor_bottom = 0.5
	death_menu_b.focus_mode = Control.FOCUS_NONE
	death_menu_b.visible = false
	death_menu_b.offset_left = -170
	death_menu_b.offset_right = 170
	death_menu_b.offset_top = 156
	death_menu_b.offset_bottom = 216
	death_menu_b.pressed.connect(func(): menu_pressed.emit())
	root.add_child(death_menu_b)


func _process(delta: float) -> void:
	t += delta
	if dmg_acc > 0.0:
		dmg_t -= delta
		if dmg_t <= 0.0:
			toast("−%d здоровья" % int(round(dmg_acc)), Color(1.0, 0.32, 0.25), true)
			dmg_acc = 0.0
	hp_lag = move_toward(hp_lag, hp, delta * 25.0) if hp_lag > hp else hp
	if hp >= hp_max - 0.01:
		hp_full_t += delta
	else:
		hp_full_t = 0.0
		hp_alpha = 1.0
	var hp_target := 0.0 if hp_full_t > 2.5 else 1.0
	hp_alpha = move_toward(hp_alpha, hp_target, delta * (0.5 if hp_target < hp_alpha else 4.0))
	hurt = move_toward(hurt, 0.0, delta * 1.6)
	var low := 0.0
	if hp < hp_max * 0.3 and hp > 0.0:
		low = (0.25 + 0.15 * sin(t * 4.0)) * (1.0 - hp / (hp_max * 0.3))
	vignette.modulate.a = maxf(hurt, low)
	hit_edge = move_toward(hit_edge, 0.0, delta * 3.2)
	hit_vig.modulate.a = hit_edge * hit_edge
	paint.queue_redraw()


func set_hp(v: float, mx: float, instant := false) -> void:
	# загрузка сейва — сразу, без «догоняющей» полоски и «−N здоровья» (промпт 16.11 05:45)
	if instant:
		hp = v
		hp_max = mx
		hp_lag = v
		dmg_acc = 0.0
		return
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
	hit_edge = maxf(hit_edge, clampf(amount * 1.2, 0.5, 1.0))


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


func block_flash() -> void:
	toast("БЛОК!", Color(0.6, 0.85, 1.0), true)
	hurt = 0.0


func show_death(on: bool) -> void:
	death_on = on
	restart_b.visible = on
	death_menu_b.visible = on
	if on:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE   # курсор нужен сразу — по кнопкам (18.11 01:42)
	var tw := create_tween().set_parallel()
	tw.tween_property(death_bg, "color:a", 0.75 if on else 0.0, 1.2 if on else 0.6)
	tw.tween_property(death_l, "modulate:a", 1.0 if on else 0.0, 1.5 if on else 0.4)


## Кат-сцена (отъезд на машине, car.gd): прячем полоски, хотбар, прицел и сообщения.
## После кат-сцены интерфейс проявляется плавно, за 0.8 с (промпт 16.11 03:51).
var cine_tw: Tween


func set_cinematic(on: bool) -> void:
	if cine_tw and cine_tw.is_valid():
		cine_tw.kill()
	var was_hidden := not paint.visible
	for c in [paint, prompt_l, toasts, big_toasts]:
		(c as CanvasItem).visible = not on
	if on or not was_hidden:
		for c in [paint, prompt_l, toasts, big_toasts]:
			(c as CanvasItem).modulate.a = 1.0
		return
	cine_tw = create_tween().set_parallel(true)
	for c in [paint, prompt_l, toasts, big_toasts]:
		(c as CanvasItem).modulate.a = 0.0
		cine_tw.tween_property(c, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE)


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
	if show_crosshair and not gun_cross and not minimal:
		paint.draw_circle(sz / 2.0, 2.0, Color(1, 1, 1, 0.35))

	# здоровье
	var x := 28.0
	# здоровье и хотбар — крупнее прежнего (~×1.25)
	var y := sz.y - 50.0
	var w := 330.0
	_draw_hp(x, y, w, 20.0, f)

	# кровотечение: мигающая капля справа от полоски здоровья
	if bleed > 0.0:
		var a := 0.55 + 0.45 * sin(t * 8.0)
		var dc := Vector2(x + w + 22, y + 9)
		paint.draw_circle(dc, 8.0, Color(0.85, 0.08, 0.05, a))
		paint.draw_colored_polygon(PackedVector2Array([dc + Vector2(-7, -3), dc + Vector2(7, -3), dc + Vector2(0, -18)]), Color(0.85, 0.08, 0.05, a))
	if bleed > 0.0 and not minimal:
		var a := 0.55 + 0.45 * sin(t * 8.0)
		var bt := "КРОВОТЕЧЕНИЕ %d с" % int(ceil(bleed))
		paint.draw_string_outline(f, Vector2(x + w + 36, y + 14), bt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(0, 0, 0, 0.8))
		paint.draw_string(f, Vector2(x + w + 36, y + 14), bt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.0, 0.3, 0.22, 0.6 + 0.4 * a))

	if minimal:
		return   # реализм: без баффов, монет, хотбара и заряда фонарика
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
			var in_hand: bool = id != "" and id == hand
			paint.draw_rect(r, Color(0.1, 0.16, 0.1, 0.55) if in_hand else Color(0, 0, 0, 0.5))
			var bc := Color(1, 1, 1, 0.18)
			var bw := 1.0
			if in_hand:
				bc = Color(0.6, 0.95, 0.5, 0.95)
				bw = 3.0
			elif worn:
				bc = Color(0.95, 0.75, 0.4, 0.9)
				bw = 2.0
			paint.draw_rect(r, bc, false, bw)
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


## Полоска здоровья (промпт 18.11 02:15: «слишком простая», во всех режимах одна и та же):
## стальная плашка со скошенными углами и заклёпками, утопленный паз, заливка с градиентом и бликом,
## деления по 25 единиц, яркая кромка у края заливки, «догоняющая» светлая полоска от только что
## полученного урона и красный пульс на малом здоровье. В «Реализме» — без подписи и цифр.
func _draw_hp(x: float, y: float, w: float, h: float, f: Font) -> void:
	if hp_alpha <= 0.002:
		return   # здоровье полное и давно не менялось — плашка угасла (промпт 18.11 02:16)
	var fa := Color(1, 1, 1, hp_alpha)
	var frac := clampf(hp / maxf(hp_max, 1.0), 0.0, 1.0)
	var lag := clampf(hp_lag / maxf(hp_max, 1.0), 0.0, 1.0)
	var fw := w * frac
	var pad := 4.0
	# плашка со скошенными углами (слева сверху и справа снизу)
	var cut := 7.0
	var l := x - pad
	var r := x + w + pad
	var tp := y - pad
	var bt := y + h + pad
	var plate := PackedVector2Array([
		Vector2(l + cut, tp), Vector2(r, tp), Vector2(r, bt - cut),
		Vector2(r - cut, bt), Vector2(l, bt), Vector2(l, tp + cut)])
	paint.draw_colored_polygon(plate, Color(0, 0, 0, 0.5) * fa)                     # тень/подложка
	paint.draw_colored_polygon(_shift(plate, Vector2(0.0, -1.0)), Color(0.15, 0.145, 0.135, 0.92) * fa)
	paint.draw_polyline(_loop(_shift(plate, Vector2(0.0, -1.0))), Color(0.44, 0.42, 0.38, 0.75) * fa, 1.0)
	# заклёпки по углам
	for rv in [Vector2(l + 5.0, bt - 4.0), Vector2(r - 4.0, tp + 4.0), Vector2(r - 4.0, bt - 8.0), Vector2(l + 9.0, tp + 3.0)]:
		paint.draw_circle(rv, 2.0, Color(0.1, 0.1, 0.09, 0.9) * fa)
		paint.draw_circle(rv + Vector2(-0.4, -0.6), 1.4, Color(0.56, 0.54, 0.49, 0.95) * fa)
	# утопленный паз
	paint.draw_rect(Rect2(x, y, w, h), Color(0.055, 0.05, 0.05, 0.92) * fa)
	paint.draw_rect(Rect2(x, y, w, 1.0), Color(0, 0, 0, 0.6) * fa)
	# «догоняющая» полоска: только что потерянное здоровье
	if lag > frac:
		paint.draw_rect(Rect2(x + fw, y + 1.0, w * (lag - frac), h - 2.0), Color(0.95, 0.86, 0.72, 0.5) * fa)
	# цвет заливки: от бурого к алому по мере потери, пульс на малом здоровье
	var col := Color(0.52, 0.1, 0.07).lerp(Color(0.78, 0.17, 0.1), 1.0 - frac)
	if frac < 0.3:
		col = col.lerp(Color(0.95, 0.3, 0.14), (0.55 + 0.45 * sin(t * 6.0)) * (1.0 - frac / 0.3))
	if fw > 1.0:
		paint.draw_rect(Rect2(x, y + 1.0, fw, h - 2.0), col * fa)
		paint.draw_rect(Rect2(x, y + 1.0, fw, (h - 2.0) * 0.4), col.lightened(0.16) * fa)        # глянец сверху
		paint.draw_rect(Rect2(x, y + h * 0.74, fw, h * 0.26 - 1.0), col.darkened(0.34) * fa)     # тень снизу
		paint.draw_rect(Rect2(x, y + 2.0, fw, 1.5), Color(1, 1, 1, 0.22) * fa)                   # блик
		# яркая кромка у края заливки
		paint.draw_rect(Rect2(x + fw - 2.5, y + 1.0, 2.5, h - 2.0), Color(1.0, 0.78, 0.6, 0.85) * fa)
		paint.draw_rect(Rect2(x + fw - 6.0, y + 1.0, 3.5, h - 2.0), Color(1.0, 0.6, 0.4, 0.25) * fa)
	# деления: крупные по 25 единиц, мелкие — по 10
	for k in 9:
		var kx := x + w * (k + 1) / 10.0
		paint.draw_rect(Rect2(kx, y + 1.0, 1.0, 4.0), Color(0, 0, 0, 0.4) * fa)
	for k in 3:
		var kx := x + w * (k + 1) / 4.0
		paint.draw_rect(Rect2(kx, y + 1.0, 1.0, h - 2.0), Color(0, 0, 0, 0.4) * fa)
	paint.draw_rect(Rect2(x, y, w, h), Color(0.03, 0.03, 0.03, 0.85) * fa, false, 1.0)
	if minimal:
		return   # «Реализм»: без подписи и цифр
	paint.draw_string_outline(f, Vector2(x + 1.0, y - 11.0), "ЗДОРОВЬЕ", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.75) * fa)
	paint.draw_string(f, Vector2(x + 1.0, y - 11.0), "ЗДОРОВЬЕ", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.72, 0.7, 0.64) * fa)
	var num := "%d" % int(ceil(hp))
	paint.draw_string_outline(f, Vector2(x, y + h - 4.0), num, HORIZONTAL_ALIGNMENT_RIGHT, w - 6.0, 17, 5, Color(0, 0, 0, 0.85) * fa)
	paint.draw_string(f, Vector2(x, y + h - 4.0), num, HORIZONTAL_ALIGNMENT_RIGHT, w - 6.0, 17, Color(0.95, 0.92, 0.86) * fa)


## Сдвинуть точки полигона (плашка рисуется дважды: тень и металл).
static func _shift(pts: PackedVector2Array, d: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p + d)
	return out


## Замкнуть контур для draw_polyline.
static func _loop(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	out.append(pts[0])
	return out
