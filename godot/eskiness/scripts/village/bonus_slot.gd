extends StaticBody3D
## Автомат «ФОРТУНА» в подвале деревни (промпт 15.11 23:01): три барабана, одна линия, крутка — 5 монет.
## Обычные награды — три одинаковых символа (вишня 15 … семёрка 100), две вишни — 5 монет.
## «Бонуски» (звезда B): одна — мелкий подарок (патроны, фильтр, бинт, тушёнка), две — 3 бесплатные крутки,
## три — бонус-игра: 8 бесплатных круток с удвоенным выигрышем.
## Джекпоты (корона J): две — мини-джекпот 25 монет, три — ДЖЕКПОТ: весь банк (растёт на 1 с каждой платной
## крутки, начинается со 150; в сейве — village.gd).
## Автомат у каждого игрока свой (монеты свои), в сети не синхронизируется.

const Sym := preload("res://scripts/slot/slot_symbols.gd")
const Items := preload("res://scripts/items.gd")
const COST := 5
const SYMS := ["cherry", "lemon", "plum", "grape", "diamond", "seven", "bonus", "jack"]
const WEIGHT := {"cherry": 24.0, "lemon": 20.0, "plum": 16.0, "grape": 12.0, "diamond": 9.0, "seven": 6.0, "bonus": 9.0, "jack": 4.0}
const PAY := {"cherry": 15, "lemon": 20, "plum": 25, "grape": 35, "diamond": 60, "seven": 100}
const GIFTS := [["ammo", 4], ["filter", 1], ["bandage", 1], ["canned", 1], ["ammo", 6], ["coin", 8]]
const JACK_BASE := 150
const SPIN_T := 1.1
const STEP_T := 0.38

var game
var jackpot := JACK_BASE
var free_spins := 0
var bonus_game := false      # идёт бонус-игра (выигрыш ×2)
var busy := false
var t := 0.0
var result := ["cherry", "lemon", "plum"]
var shown := ["seven", "seven", "seven"]
var reel_off := [0.0, 0.0, 0.0]
var reel_done := [true, true, true]
var msg := "КРУТКА 5 МОНЕТ"
var msg_col := Color(0.95, 0.85, 0.5)
var blink := 0.0
var screen: Control
var vp: SubViewport
var jack_l: Label3D
var lamp: OmniLight3D
var snd: AudioStreamPlayer3D


func _ready() -> void:
	var body := _mat(Color(0.1, 0.2, 0.16), 0.5, 0.5)
	var gold := _mat(Color(0.8, 0.62, 0.25), 0.9, 0.35)
	var dark := _mat(Color(0.04, 0.04, 0.04), 0.0, 0.9)
	_box(Vector3(0.95, 0.9, 0.62), Vector3(0, 0.45, 0), body)
	_box(Vector3(0.9, 0.95, 0.5), Vector3(0, 1.37, -0.05), body)
	_box(Vector3(1.0, 0.06, 0.66), Vector3(0, 0.92, 0.0), gold)
	_box(Vector3(1.0, 0.3, 0.55), Vector3(0, 1.98, -0.05), _mat(Color(0.3, 0.05, 0.06), 0.3, 0.5))
	for sx in [-0.47, 0.47]:
		_box(Vector3(0.04, 1.85, 0.06), Vector3(sx, 1.0, 0.29), gold)
	_box(Vector3(0.8, 0.36, 0.02), Vector3(0, 1.42, 0.2), dark)   # рамка экрана
	_box(Vector3(0.55, 0.12, 0.14), Vector3(0, 0.25, 0.3), dark)  # лоток
	# рычаг сбоку
	_box(Vector3(0.05, 0.5, 0.05), Vector3(0.52, 1.25, 0.05), gold)
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.12
	ball.mesh = sm
	ball.material_override = _glow(Color(0.9, 0.1, 0.1), 1.2)
	ball.position = Vector3(0.52, 1.52, 0.05)
	add_child(ball)
	# экран: SubViewport с барабанами
	vp = SubViewport.new()
	vp.size = Vector2i(480, 220)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	screen = Control.new()
	screen.size = Vector2(480, 220)
	screen.draw.connect(_draw_screen)
	vp.add_child(screen)
	var q := QuadMesh.new()
	q.size = Vector2(0.76, 0.34)
	var scr := MeshInstance3D.new()
	scr.mesh = q
	var sm2 := StandardMaterial3D.new()
	sm2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm2.albedo_texture = vp.get_texture()
	scr.material_override = sm2
	scr.position = Vector3(0, 1.42, 0.212)
	add_child(scr)
	# вывеска и банк
	var sign_l := Label3D.new()
	sign_l.text = "ФОРТУНА"
	sign_l.font_size = 64
	sign_l.pixel_size = 0.0032
	sign_l.modulate = Color(1.0, 0.8, 0.3)
	sign_l.outline_size = 8
	sign_l.outline_modulate = Color(0.4, 0.05, 0.0)
	sign_l.position = Vector3(0, 1.99, 0.23)
	add_child(sign_l)
	jack_l = Label3D.new()
	jack_l.font_size = 36
	jack_l.pixel_size = 0.0025
	jack_l.modulate = Color(1.0, 0.35, 0.25)
	jack_l.outline_size = 6
	jack_l.position = Vector3(0, 1.75, 0.212)
	add_child(jack_l)
	lamp = OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.7, 0.35)
	lamp.light_energy = 0.9
	lamp.omni_range = 4.0
	lamp.position = Vector3(0, 1.6, 0.7)
	add_child(lamp)
	snd = AudioStreamPlayer3D.new()
	snd.unit_size = 4.0
	snd.position = Vector3(0, 1.0, 0.3)
	add_child(snd)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.0, 2.1, 0.66)
	cs.shape = bs
	cs.position = Vector3(0, 1.05, 0)
	add_child(cs)
	for i in 3:
		shown[i] = _roll()


func _mat(c: Color, metal := 0.0, rough := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m


func _glow(c: Color, e: float) -> StandardMaterial3D:
	var m := _mat(c)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	return m


func _box(size: Vector3, pos: Vector3, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	add_child(mi)


func _roll() -> String:
	var total := 0.0
	for s in SYMS:
		total += float(WEIGHT[s])
	var r := randf() * total
	for s in SYMS:
		r -= float(WEIGHT[s])
		if r <= 0.0:
			return s
	return "cherry"


# ---------- взаимодействие ----------

func get_prompt(g) -> String:
	if busy:
		return ""
	if free_spins > 0:
		return "[E] ФОРТУНА — бесплатная крутка (%d)" % free_spins
	return "[E] Крутить ФОРТУНУ — %d монет" % COST if g.inv.coins >= COST else "ФОРТУНА: нужно %d монет" % COST


func interact(g) -> void:
	if busy:
		return
	if free_spins > 0:
		free_spins -= 1
	elif g.inv.coins >= COST:
		g.inv.remove("coin", COST)
		jackpot += 1
		bonus_game = false
	else:
		g.hud.toast("Не хватает монет")
		return
	busy = true
	t = 0.0
	for i in 3:
		result[i] = _roll()
		reel_done[i] = false
	msg = "БОНУС-ИГРА: ×2  (осталось %d)" % free_spins if bonus_game else "..."
	msg_col = Color(0.95, 0.85, 0.5)
	g.play_at("click", global_position + Vector3(0.5, 1.3, 0), -8.0, 0.7)


func _process(delta: float) -> void:
	jack_l.text = "ДЖЕКПОТ %d" % jackpot
	blink += delta
	lamp.light_energy = 0.9 + (0.6 * sin(blink * 9.0) if busy else 0.1 * sin(blink * 2.0))
	if busy:
		t += delta
		for i in 3:
			if reel_done[i]:
				continue
			reel_off[i] = fmod(reel_off[i] + delta * 9.0, 1.0)
			if fmod(t, 0.09) < delta:
				shown[i] = SYMS[randi() % SYMS.size()]
			if t > SPIN_T + i * STEP_T:
				reel_done[i] = true
				reel_off[i] = 0.0
				shown[i] = result[i]
				if game:
					game.play_at("tick", global_position + Vector3(0, 1.4, 0.3), -6.0, 0.8 + i * 0.1)
		if reel_done[2]:
			busy = false
			_payout()
	screen.queue_redraw()


func _payout() -> void:
	var r: Array = result
	var mult := 2 if bonus_game else 1
	var win := 0
	var lines: Array = []
	var jacks := r.count("jack")
	var bonus := r.count("bonus")
	if jacks == 3:
		win += jackpot
		lines.append("ДЖЕКПОТ!")
		jackpot = JACK_BASE
		if game:
			game.play_ui("jingle", -2.0, 0.8)
			game.hud.toast("ДЖЕКПОТ НА ФОРТУНЕ: +%d" % win, Color(1.0, 0.8, 0.3))
	elif jacks == 2:
		win += 25
		lines.append("МИНИ-ДЖЕКПОТ")
	if r[0] == r[1] and r[1] == r[2] and PAY.has(r[0]):
		win += int(PAY[r[0]])
	elif r.count("cherry") == 2:
		win += 5
	if bonus == 3:
		free_spins += 8
		bonus_game = true
		lines.append("БОНУС-ИГРА: 8 круток ×2")
	elif bonus == 2:
		free_spins += 3
		lines.append("БОНУС: +3 крутки")
	elif bonus == 1:
		var gift: Array = GIFTS[randi() % GIFTS.size()]
		if game:
			var left: int = game.inv.add(gift[0], gift[1])
			if left > 0:
				game.spawn_loot(gift[0], left, global_transform * Vector3(0, 0.4, 0.5), global_transform.basis * Vector3(0, 1, 1.5), 0.3)
			game.hud.toast("ФОРТУНА: бонуска — %s" % Items.item_name(gift[0]), Color(0.75, 0.9, 1.0))
		lines.append("бонуска")
	win *= mult
	if free_spins == 0:
		bonus_game = false
	if win > 0 and game:
		game.inv.add("coin", win)
		game.play_ui("coin", -6.0)
		lines.push_front("+%d МОНЕТ" % win)
	if lines.is_empty():
		msg = "МИМО"
		msg_col = Color(0.7, 0.65, 0.6)
	else:
		msg = "  ·  ".join(lines)
		msg_col = Color(1.0, 0.85, 0.35)
	if free_spins > 0:
		msg += "   (бесплатно: %d)" % free_spins


# ---------- экран ----------

func _draw_screen() -> void:
	var c := screen
	c.draw_rect(Rect2(0, 0, 480, 220), Color(0.03, 0.02, 0.02))
	var font := ThemeDB.fallback_font
	for i in 3:
		var x := 18.0 + i * 152.0
		var box := Rect2(x, 14, 140, 150)
		c.draw_rect(box, Color(0.92, 0.88, 0.78))
		var off: float = reel_off[i] * 150.0
		_sym(shown[i], Rect2(x + 10, 24 + off, 120, 120))
		if not reel_done[i]:
			_sym(SYMS[(SYMS.find(shown[i]) + 3) % SYMS.size()], Rect2(x + 10, 24 + off - 150, 120, 120))
			c.draw_rect(Rect2(x, 14, 140, 150), Color(1, 1, 1, 0.15))
		c.draw_rect(Rect2(x, 0, 140, 14), Color(0.03, 0.02, 0.02))
		c.draw_rect(Rect2(x, 164, 140, 20), Color(0.03, 0.02, 0.02))
		c.draw_rect(box, Color(0.75, 0.55, 0.2), false, 4.0)
	c.draw_line(Vector2(10, 89), Vector2(470, 89), Color(0.9, 0.15, 0.1, 0.5), 2.0)
	var col := msg_col
	if not busy and msg_col.r > 0.99:
		col.a = 0.6 + 0.4 * sin(blink * 8.0)
	c.draw_string(font, Vector2(0, 208), msg, HORIZONTAL_ALIGNMENT_CENTER, 480, 22, col)


func _sym(id: String, r: Rect2) -> void:
	var c := screen
	match id:
		"bonus":
			var pts := PackedVector2Array()
			var ctr := r.get_center()
			for k in 10:
				var a := -PI / 2.0 + TAU * k / 10.0
				var rad := r.size.x * (0.45 if k % 2 == 0 else 0.2)
				pts.append(ctr + Vector2(cos(a), sin(a)) * rad)
			c.draw_colored_polygon(pts, Color(0.95, 0.72, 0.15))
			c.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.45, 0.25, 0.05), 4.0)
			c.draw_string(ThemeDB.fallback_font, ctr + Vector2(-60, 14), "B", HORIZONTAL_ALIGNMENT_CENTER, 120, 40, Color(0.35, 0.12, 0.02))
		"jack":
			var ctr := r.get_center()
			var s := r.size.x
			var crown := PackedVector2Array([ctr + Vector2(-s * 0.4, s * 0.25), ctr + Vector2(-s * 0.42, -s * 0.2), ctr + Vector2(-s * 0.2, 0),
				ctr + Vector2(0, -s * 0.32), ctr + Vector2(s * 0.2, 0), ctr + Vector2(s * 0.42, -s * 0.2), ctr + Vector2(s * 0.4, s * 0.25)])
			c.draw_colored_polygon(crown, Color(0.85, 0.1, 0.12))
			c.draw_polyline(crown + PackedVector2Array([crown[0]]), Color(0.95, 0.75, 0.2), 5.0)
			c.draw_string(ThemeDB.fallback_font, ctr + Vector2(-60, s * 0.2), "J", HORIZONTAL_ALIGNMENT_CENTER, 120, 34, Color(1.0, 0.85, 0.3))
		_:
			Sym.draw(c, id, r)
