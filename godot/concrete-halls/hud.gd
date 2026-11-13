extends CanvasLayer
## HUD (тестовые механики): здоровье, монеты, заряд фонарика, прицел-точка, подсказка «[E] …»,
## всплывающие сообщения слева сверху, красная виньетка при уроне и экран смерти.

const Items := preload("res://items.gd")

var hp := 100.0
var hp_max := 100.0
var hp_lag := 100.0          # «догоняющая» светлая полоска
var coins := 0
var battery := 1.0
var light_on := false
var knuckles := false
var inv  # inventory.gd — для хотбара 1–5
var hurt := 0.0
var t := 0.0

var paint: Control
var prompt_l: Label
var toasts: VBoxContainer
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


func _process(delta: float) -> void:
	t += delta
	hp_lag = move_toward(hp_lag, hp, delta * 25.0) if hp_lag > hp else hp
	hurt = move_toward(hurt, 0.0, delta * 1.6)
	var low := 0.0
	if hp < hp_max * 0.3 and hp > 0.0:
		low = (0.25 + 0.15 * sin(t * 4.0)) * (1.0 - hp / (hp_max * 0.3))
	vignette.modulate.a = maxf(hurt, low)
	paint.queue_redraw()


func set_hp(v: float, mx: float) -> void:
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


func toast(text: String, col := Color(0.88, 0.86, 0.8)) -> void:
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


func show_death(on: bool) -> void:
	var tw := create_tween().set_parallel()
	tw.tween_property(death_bg, "color:a", 0.75 if on else 0.0, 1.2 if on else 0.6)
	tw.tween_property(death_l, "modulate:a", 1.0 if on else 0.0, 1.5 if on else 0.4)


func _paint() -> void:
	var sz := paint.size
	var f := ThemeDB.fallback_font
	# прицел — едва заметная точка
	paint.draw_circle(sz / 2.0, 2.0, Color(1, 1, 1, 0.35))

	# здоровье
	var x := 28.0
	var y := sz.y - 46.0
	var w := 260.0
	paint.draw_string_outline(f, Vector2(x, y - 8), "ЗДОРОВЬЕ  %d" % int(ceil(hp)), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(0, 0, 0, 0.7))
	paint.draw_string(f, Vector2(x, y - 8), "ЗДОРОВЬЕ  %d" % int(ceil(hp)), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.8, 0.78, 0.72))
	paint.draw_rect(Rect2(x - 2, y - 2, w + 4, 18), Color(0, 0, 0, 0.6))
	paint.draw_rect(Rect2(x, y, w * hp_lag / hp_max, 14), Color(0.85, 0.7, 0.55, 0.6))
	paint.draw_rect(Rect2(x, y, w * hp / hp_max, 14), Color(0.62, 0.12, 0.08))
	paint.draw_rect(Rect2(x, y, w * hp / hp_max, 4), Color(0.8, 0.25, 0.18))

	# монеты
	Items.draw_icon(paint, "coin", Rect2(x - 4, y - 66, 34, 34))
	var ct := "× %d" % coins
	paint.draw_string_outline(f, Vector2(x + 36, y - 42), ct, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 5, Color(0, 0, 0, 0.7))
	paint.draw_string(f, Vector2(x + 36, y - 42), ct, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.9, 0.78, 0.5))
	if knuckles:
		Items.draw_icon(paint, "knuckles", Rect2(x + 120, y - 66, 34, 34))

	# хотбар 1–5 внизу по центру
	if inv:
		var cell := 50.0
		var gap := 6.0
		var x0 := sz.x / 2.0 - (cell * 5 + gap * 4) / 2.0
		var y0 := sz.y - cell - 18.0
		for k in 5:
			var r := Rect2(x0 + k * (cell + gap), y0, cell, cell)
			var id: String = inv.hotbar[k]
			var cnt: int = inv.count(id) if id != "" else 0
			var worn: bool = id != "" and Items.equip_slot(id) != "" and inv.equip[Items.equip_slot(id)] == id
			paint.draw_rect(r, Color(0, 0, 0, 0.5))
			paint.draw_rect(r, Color(0.95, 0.75, 0.4, 0.9) if worn else Color(1, 1, 1, 0.18), false, 2.0 if worn else 1.0)
			if id != "":
				Items.draw_icon(paint, id, r.grow(-9))
				if cnt == 0:
					paint.draw_rect(r.grow(-1), Color(0, 0, 0, 0.6))
				elif cnt > 1:
					paint.draw_string_outline(f, r.position + Vector2(0, cell - 4), str(cnt), HORIZONTAL_ALIGNMENT_RIGHT, cell - 4, 13, 3, Color(0, 0, 0, 0.8))
					paint.draw_string(f, r.position + Vector2(0, cell - 4), str(cnt), HORIZONTAL_ALIGNMENT_RIGHT, cell - 4, 13, Color(0.92, 0.9, 0.84))
			paint.draw_string_outline(f, r.position + Vector2(4, 14), str(k + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 3, Color(0, 0, 0, 0.8))
			paint.draw_string(f, r.position + Vector2(4, 14), str(k + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.8, 0.45))

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
