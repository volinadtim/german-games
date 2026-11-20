extends StaticBody3D
## Автомат «РАДИАЦИЯ» в городе (city.gd, промпт 20.11 18:44) — слот четвёртой локации.
## Поле 3×3, 5 линий (три ряда и две диагонали), три одинаковых в линию — PAY×ставка.
## Хлам по рангу (RANK): банка → шина → крыса → противогаз → неоновая семёрка.
## БОЧКА — дикий символ (заменяет любой в линии) и мутаген: после остановки барабанов каждая бочка
## по очереди даёт зелёную вспышку, и соседи по кресту мутируют на ранг выше.
## СЧЁТЧИК ГЕЙГЕРА: каждая бочка — +1; полный (GEIGER) — ВЫБРОС: всё поле +1 ранг и выигрыш ×2.
## Ставка — кнопка на полке слева. По сети не синхронизируется, счётчик не сохраняется.
const _D_RADIATION := preload("res://data/slots/radiation.tres")   # настройки — правятся в Инспекторе

const Sfx := preload("res://scripts/core/sfx.gd")
const Perks := preload("res://scripts/systems/perks.gd")
const SlotSounds := preload("res://scripts/slot/slot_sounds.gd")
static var COST: int = _D_RADIATION.spin_price
static var BETS: Array = _D_RADIATION.bets
static var RANK: Array = _D_RADIATION.mutation_ranks
static var SYMS: Array = _D_RADIATION.ids()
static var WEIGHT: Dictionary = _D_RADIATION.weights()
static var PAY: Dictionary = _D_RADIATION.pays_3()
static var LINES: Array = _D_RADIATION.lines_table()
static var GEIGER: int = _D_RADIATION.geiger_max
static var PROFIT_CAP: int = _D_RADIATION.profit_cap
static var SPIN_T: float = _D_RADIATION.spin_time
static var STEP_T: float = _D_RADIATION.step_time
static var MUT_T: float = _D_RADIATION.mutation_time
static var BURST_T: float = _D_RADIATION.burst_time
static var W: int = _D_RADIATION.screen_w
static var H: int = _D_RADIATION.screen_h
static var X0: float = _D_RADIATION.field_x0
static var CW: float = _D_RADIATION.cell_w
static var GAP: float = _D_RADIATION.cell_gap
static var TOP: float = _D_RADIATION.field_top
static var CH: float = _D_RADIATION.cell_h
static var FIELD_B := TOP + CH * 3.0

var game
var bet := 1
var busy := false
var profit := 0
var grid: Array = ["can", "rat", "tire", "mask", "barrel", "neon", "tire", "can", "rat"]
var flash: Array = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var col_stop: Array = [true, true, true]
var phase := "show"                    # spin / mutate / burst / show
var pt := 0.0
var t := 0.0
var spin_t := 0.0
var barrels: Array = []
var mut_i := 0
var mut_done := false
var geiger := 0
var mult := 1
var win_mask: Array = [false, false, false, false, false, false, false, false, false]
var win_lines: Array = []
var msg := "Брось монету — поищи в хламе"
var msg_col := Color(0.75, 1.0, 0.55)
var banner := ""
var banner_t := 9.0
var vp: SubViewport
var screen: Control
var lever: Node3D
var lever_t := 9.0
var bet_l: Label3D
var lamp: OmniLight3D
var ooze: MeshInstance3D
var bulbs: Array = []
var fx: Array = []
var sounds := {}
var spin_snd: AudioStreamPlayer3D
var smog: Array = []


## Корпус: ржавый ящик с жёлто-чёрной полосой, бочка с зелёной жижей сверху, рычаг, экран, кнопка ставки.
func _ready() -> void:
	var body := _mat(Color(0.3, 0.31, 0.28), 0.4, 0.7)
	var rust := _mat(Color(0.45, 0.25, 0.12), 0.3, 0.9)
	var yel := _mat(Color(0.95, 0.78, 0.1), 0.2, 0.6)
	var dark := _mat(Color(0.02, 0.02, 0.03), 0.0, 0.9)
	_box(Vector3(1.04, 0.08, 0.7), Vector3(0, 0.04, 0), rust)
	_box(Vector3(0.95, 0.86, 0.62), Vector3(0, 0.49, 0), body)
	for i in 8:
		_box(Vector3(0.118, 0.12, 0.02), Vector3(-0.415 + i * 0.1186, 0.78, 0.312), yel if i % 2 == 0 else dark)
	_box(Vector3(0.9, 0.95, 0.5), Vector3(0, 1.37, -0.05), body)
	_box(Vector3(1.0, 0.06, 0.66), Vector3(0, 0.92, 0.0), rust)                # полка
	_box(Vector3(1.0, 0.36, 0.55), Vector3(0, 2.03, -0.05), body)              # вывеска
	_box(Vector3(0.94, 0.3, 0.02), Vector3(0, 2.03, 0.226), _glow(Color(0.08, 0.2, 0.04), 0.6))
	_box(Vector3(0.74, 0.7, 0.02), Vector3(0, 1.38, 0.2), dark)                # рамка экрана
	_box(Vector3(0.55, 0.12, 0.14), Vector3(0, 0.22, 0.3), dark)               # лоток
	_box(Vector3(0.6, 0.03, 0.18), Vector3(0, 0.3, 0.32), yel)
	var sign_l := Label3D.new()
	sign_l.text = "РАДИАЦИЯ"
	sign_l.font_size = 64
	sign_l.pixel_size = 0.0021
	sign_l.modulate = Color(0.55, 1.0, 0.3)
	sign_l.outline_size = 10
	sign_l.outline_modulate = Color(0.05, 0.08, 0.02)
	sign_l.position = Vector3(0, 2.03, 0.24)
	add_child(sign_l)
	# бочка на крыше, из неё сочится зелёная жижа
	var barrel := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.17
	cm.bottom_radius = 0.17
	cm.height = 0.42
	barrel.mesh = cm
	barrel.material_override = yel
	barrel.position = Vector3(0.28, 2.42, -0.05)
	add_child(barrel)
	for y in [-0.12, 0.12]:
		var band := MeshInstance3D.new()
		var bc := CylinderMesh.new()
		bc.top_radius = 0.175
		bc.bottom_radius = 0.175
		bc.height = 0.03
		band.mesh = bc
		band.material_override = dark
		band.position = barrel.position + Vector3(0, y, 0)
		add_child(band)
	ooze = MeshInstance3D.new()
	var om := SphereMesh.new()
	om.radius = 0.15
	om.height = 0.12
	ooze.mesh = om
	ooze.material_override = _glow(Color(0.35, 1.0, 0.15), 1.6)
	ooze.position = barrel.position + Vector3(0, 0.22, 0)
	add_child(ooze)
	# рычаг с зелёным шаром
	_box(Vector3(0.08, 0.12, 0.12), Vector3(0.5, 1.05, 0.05), rust)
	lever = Node3D.new()
	lever.position = Vector3(0.54, 1.05, 0.05)
	add_child(lever)
	var stick := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.035, 0.48, 0.035)
	stick.mesh = bm
	stick.material_override = rust
	stick.position = Vector3(0, 0.24, 0)
	lever.add_child(stick)
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.12
	ball.mesh = sm
	ball.material_override = _glow(Color(0.35, 1.0, 0.15), 1.0)
	ball.position = Vector3(0, 0.5, 0)
	lever.add_child(ball)
	# экран
	vp = SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	screen = Control.new()
	screen.size = Vector2(W, H)
	screen.draw.connect(_draw_screen)
	vp.add_child(screen)
	var q := QuadMesh.new()
	q.size = Vector2(0.66, 0.62)
	var scr := MeshInstance3D.new()
	scr.mesh = q
	var sm2 := StandardMaterial3D.new()
	sm2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm2.albedo_texture = vp.get_texture()
	sm2.albedo_color = Color(0.82, 0.82, 0.82)
	scr.material_override = sm2
	scr.position = Vector3(0, 1.38, 0.212)
	add_child(scr)
	var bs := SphereMesh.new()
	bs.radius = 0.017
	bs.height = 0.034
	bs.radial_segments = 8
	bs.rings = 4
	for k in 9:
		_bulb(bs, Vector3(-0.36 + k * 0.09, 1.715, 0.215))
	for k in 6:
		_bulb(bs, Vector3(0.375, 1.62 - k * 0.096, 0.215))
	for k in 9:
		_bulb(bs, Vector3(0.36 - k * 0.09, 1.045, 0.215))
	for k in 6:
		_bulb(bs, Vector3(-0.375, 1.14 + k * 0.096, 0.215))
	lamp = OmniLight3D.new()
	lamp.light_color = Color(0.5, 1.0, 0.3)
	lamp.light_energy = 0.9
	lamp.omni_range = 4.0
	lamp.position = Vector3(0, 1.6, 0.7)
	add_child(lamp)
	spin_snd = AudioStreamPlayer3D.new()
	spin_snd.unit_size = 4.0
	spin_snd.max_distance = 30.0
	spin_snd.position = Vector3(0, 1.0, 0.3)
	add_child(spin_snd)
	for k in 3:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 5.0
		p.max_distance = 32.0
		p.position = Vector3(0, 1.4, 0.3)
		add_child(p)
		fx.append(p)
	_make_sounds()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(1.0, 2.3, 0.66)
	cs.shape = bx
	cs.position = Vector3(0, 1.15, 0)
	add_child(cs)
	_build_bet_button(yel)
	for k in 10:
		smog.append(Vector3(randf() * W, randf() * H, randf_range(40.0, 110.0)))


## Кнопка ставки — отдельное тело, торчит перед корпусом (луч взгляда попадает в неё раньше автомата).
class BetButton extends StaticBody3D:
	var slot
	func get_prompt(_g) -> String:
		return slot.bet_prompt()
	func interact(_g) -> void:
		slot.cycle_bet()


## Кнопка «СТАВКА» на полке слева.
func _build_bet_button(m: Material) -> void:
	var b := BetButton.new()
	b.slot = self
	b.position = Vector3(-0.3, 0.98, 0.36)
	add_child(b)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.18, 0.06, 0.08)
	mi.mesh = bm
	mi.material_override = m
	b.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.2, 0.09, 0.1)
	cs.shape = sh
	b.add_child(cs)
	bet_l = Label3D.new()
	bet_l.font_size = 36
	bet_l.pixel_size = 0.002
	bet_l.modulate = Color(0.05, 0.05, 0.02)
	bet_l.position = Vector3(0, 0, 0.042)
	b.add_child(bet_l)
	_update_bet_label()


## Надпись на кнопке ставки.
func _update_bet_label() -> void:
	if bet_l:
		bet_l.text = "×%d" % bet


## Подсказка у кнопки ставки.
func bet_prompt() -> String:
	if busy:
		return ""
	var i := BETS.find(bet)
	return "[F] Ставка РАДИАЦИЯ: ×%d → ×%d" % [bet, int(BETS[(i + 1) % BETS.size()])]


## Следующая ставка по кругу (во время крутки — нельзя).
func cycle_bet() -> void:
	if busy:
		return
	var i := BETS.find(bet)
	bet = int(BETS[(i + 1) % BETS.size()])
	_update_bet_label()
	_sfx("stop", -8.0, 1.6)


# ---------- корпус ----------

## Материал корпуса.
func _mat(c: Color, metal := 0.0, rough := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m


## Светящийся материал.
func _glow(c: Color, e: float) -> StandardMaterial3D:
	var m := _mat(c, 0.0, 0.5)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	return m


## Ящик корпуса.
func _box(size: Vector3, pos: Vector3, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	add_child(mi)


## Лампочка на рамке (материал — в bulbs, мигает в _process).
func _bulb(mesh: Mesh, p: Vector3) -> void:
	var m := _glow(Color(0.4, 1.0, 0.25) if bulbs.size() % 2 == 0 else Color(1.0, 0.85, 0.15), 0.4)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = p
	add_child(mi)
	bulbs.append(m)


# ---------- звуки ----------

## Ноты: [частота, начало, длина] — синус с затуханием.
func _notes(list: Array, dur: float, decay := 6.0) -> PackedFloat32Array:
	var r := Sfx.RATE
	var n := int(dur * r)
	var b := PackedFloat32Array()
	b.resize(n)
	for e in list:
		var f: float = e[0]
		var i0 := int(float(e[1]) * r)
		var i1 := mini(n, int((float(e[1]) + float(e[2]) + 0.3) * r))
		for i in range(i0, i1):
			var tt := float(i - i0) / r
			b[i] += (sin(TAU * f * tt) + 0.3 * sin(TAU * 2.0 * f * tt)) * exp(-tt * decay) * minf(tt * 200.0, 1.0) * 0.45
	return b


## Синтез звуков: крутка (треск), стоп, разряд мутации, щелчки Гейгера, гул выброса, выигрыши.
func _make_sounds() -> void:
	var r := Sfx.RATE
	var rng := RandomNumberGenerator.new()
	rng.seed = 88
	var n := int(1.0 * r)
	var spin := PackedFloat32Array()
	spin.resize(n)
	for i in n:
		var tt := float(i) / r
		var seg := fmod(tt * 16.0, 1.0) / 16.0
		spin[i] = rng.randf_range(-1, 1) * exp(-seg * 600.0) * 0.7 + sin(TAU * 60.0 * tt) * 0.12
	var st := Sfx._wav(spin, 0.5)
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_end = n - int(r * 0.03)
	sounds["spin"] = st
	var m := int(0.22 * r)
	var stop := PackedFloat32Array()
	stop.resize(m)
	for i in m:
		var tt := float(i) / r
		stop[i] = sin(TAU * 110.0 * tt) * exp(-tt * 26.0) + rng.randf_range(-1, 1) * exp(-tt * 200.0) * 0.7
	sounds["stop"] = Sfx._wav(stop, 0.8)
	# разряд: пила с растущим тоном и жужжанием
	m = int(0.5 * r)
	var zap := PackedFloat32Array()
	zap.resize(m)
	var ph := 0.0
	for i in m:
		var tt := float(i) / r
		ph += (180.0 + tt * 900.0) / r
		var saw := fmod(ph, 1.0) * 2.0 - 1.0
		zap[i] = (saw * 0.5 + rng.randf_range(-1, 1) * 0.25) * exp(-tt * 5.0) * minf(tt * 60.0, 1.0)
	sounds["zap"] = Sfx._wav(zap, 0.6)
	# Гейгер: случайные сухие щелчки
	m = int(0.5 * r)
	var gc := PackedFloat32Array()
	gc.resize(m)
	var gi := 0
	while gi < m:
		for j in mini(int(r * 0.002), m - gi):
			gc[gi + j] = rng.randf_range(-1, 1) * exp(-float(j) / r * 2500.0)
		gi += int(r * rng.randf_range(0.012, 0.06))
	sounds["geiger"] = Sfx._wav(gc, 0.7)
	# выброс: низкий гул + шипение
	m = int(1.8 * r)
	var bu := PackedFloat32Array()
	bu.resize(m)
	var lp := 0.0
	for k in m:
		var tt := float(k) / r
		lp = lerpf(lp, rng.randf_range(-1, 1), 0.08)
		bu[k] = (sin(TAU * (45.0 + tt * 20.0) * tt) * 0.6 + lp * 1.5) * sin(PI * tt / 1.8)
	sounds["burst"] = Sfx._wav(bu, 0.85)
	sounds["win"] = Sfx._wav(_notes([[440.0, 0.0, 0.2], [554.0, 0.09, 0.2], [659.0, 0.18, 0.35]], 0.6), 0.7)
	var big := []
	var up_notes := [330.0, 440.0, 554.0, 659.0, 554.0, 659.0, 880.0]
	for k in up_notes.size():
		big.append([up_notes[k], k * 0.08, 0.2])
	for f in [440.0, 554.0, 659.0, 880.0]:
		big.append([f, 0.6, 0.9])
	sounds["big"] = Sfx._wav(_notes(big, 1.6, 3.0), 0.75)
	sounds["miss"] = Sfx._wav(_notes([[220.0, 0.0, 0.16], [175.0, 0.13, 0.3]], 0.45, 7.0), 0.45)


## Звук из пула трёх плееров.
func _sfx(id: String, db := 0.0, pitch := 1.0) -> void:
	if fx.is_empty():
		return
	var p: AudioStreamPlayer3D = fx[0]
	for f in fx:
		if not f.playing:
			p = f
			break
	p.stream = sounds[id]
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()


# ---------- игра ----------

## Подсказка у автомата.
func get_prompt(g) -> String:
	if busy:
		return ""
	var cost := Perks.cost(COST * bet)
	if g.inv.coins >= cost:
		return "[F] РАДИАЦИЯ ×%d — крутить за %d монет" % [bet, cost]
	return "РАДИАЦИЯ ×%d: нужно %d монет" % [bet, cost]


## Дёрнуть рычаг: платим и крутим.
func interact(g) -> void:
	if busy:
		return
	game = g
	var cost := Perks.cost(COST * bet)   # прокачка «Скидка» (systems/perks.gd)
	if g.inv.coins < cost:
		g.hud.toast("Не хватает монет")
		return
	g.inv.remove("coin", cost)
	profit -= cost
	_spin_start()


## Случайный символ по весам.
func _roll() -> String:
	var sum := 0.0
	for s in SYMS:
		sum += float(WEIGHT[s])
	var x := randf() * sum
	for s in SYMS:
		x -= float(WEIGHT[s])
		if x <= 0.0:
			return s
	return "can"


## Старт крутки: результат известен сразу, колонки останавливаются по очереди.
func _spin_start() -> void:
	busy = true
	phase = "spin"
	spin_t = 0.0
	lever_t = 0.0
	mult = 1
	banner = ""
	win_lines = []
	for k in 9:
		grid[k] = _roll()
		flash[k] = 0.0
		win_mask[k] = false
	col_stop = [false, false, false]
	msg = "Крутим..."
	msg_col = Color(0.75, 1.0, 0.55)
	spin_snd.stream = sounds["spin"]
	spin_snd.volume_db = -6.0
	spin_snd.play()
	SlotSounds.play3d(self, SlotSounds.lever(), lever.global_position, -7.0, randf_range(1.0, 1.08))


## Колонки останавливаются через STEP_T одна за другой.
func _tick_spin(delta: float) -> void:
	spin_t += delta
	for i in 3:
		if not col_stop[i] and spin_t >= SPIN_T + i * STEP_T:
			col_stop[i] = true
			_sfx("stop", -6.0, 1.0 + i * 0.06)
	if col_stop[2]:
		spin_snd.stop()
		barrels = []
		for k in 9:
			if grid[k] == "barrel":
				barrels.append(k)
		if barrels.is_empty():
			_finish()
			return
		phase = "mutate"
		pt = 0.0
		mut_i = 0
		mut_done = false


## Соседи клетки по кресту (k = колонка×3 + ряд).
func _cross(k: int) -> Array:
	@warning_ignore("integer_division")
	var c := k / 3
	var r := k % 3
	var out: Array = []
	for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		var cc: int = c + d.x
		var rr: int = r + d.y
		if cc >= 0 and cc < 3 and rr >= 0 and rr < 3:
			out.append(cc * 3 + rr)
	return out


## Символ на ранг выше (неон и бочка не растут). true — вырос.
func _mutate(k: int) -> bool:
	var i := RANK.find(String(grid[k]))
	if i < 0 or i >= RANK.size() - 1:
		return false
	grid[k] = RANK[i + 1]
	flash[k] = 1.0
	return true


## Бочки по очереди: вспышка, соседи мутируют, Гейгер +1. Полный счётчик — выброс.
func _tick_mutate(delta: float) -> void:
	pt += delta
	if not mut_done and pt >= MUT_T * 0.45:
		mut_done = true
		for nb in _cross(int(barrels[mut_i])):
			_mutate(nb)
		geiger = mini(geiger + 1, GEIGER)
		_sfx("zap", -4.0, 1.0 + mut_i * 0.08)
		_sfx("geiger", -5.0)
	if pt < MUT_T:
		return
	mut_i += 1
	pt = 0.0
	mut_done = false
	if mut_i < barrels.size():
		return
	if geiger >= GEIGER:
		phase = "burst"
		_banner("ВЫБРОС!  ×2")
		_sfx("burst", -2.0)
	else:
		_finish()


## Выброс: всё поле +1 ранг, выигрыш ×2, счётчик в ноль.
func _tick_burst(delta: float) -> void:
	pt += delta
	if not mut_done and pt >= BURST_T * 0.4:
		mut_done = true
		for k in 9:
			_mutate(k)
		mult = 2
		geiger = 0
		_sfx("geiger", 0.0, 1.3)
	if pt >= BURST_T:
		_finish()


## Подсчёт линий (бочка — дикая) и выплата.
func _finish() -> void:
	var win := 0
	win_lines = []
	for li in LINES.size():
		var ln: Array = LINES[li]
		var sym := ""
		var ok := true
		for k in ln:
			var s := String(grid[k])
			if s == "barrel":
				continue
			if sym == "":
				sym = s
			elif s != sym:
				ok = false
				break
		if not ok:
			continue
		if sym == "":
			sym = "barrel"
		win += int(PAY[sym]) * bet
		win_lines.append(li)
		for k in ln:
			win_mask[k] = true
	win *= mult
	win = clampi(win, 0, maxi(PROFIT_CAP - profit, 0))
	profit += win
	if win > 0:
		msg = "+%d МОНЕТ%s" % [win, "  (ВЫБРОС ×2)" if mult > 1 else ""]
		msg_col = Color(1.0, 0.85, 0.3)
		if game:
			game.inv.add("coin", win)
		var big := win >= 8 * COST * bet
		if big and banner == "":
			_banner("МУТАНТ-ДЖЕКПОТ!")
		_coin_fountain(30 if big else 10)
		_sfx("big" if big else "win", -3.0)
	else:
		msg = "Один хлам..."
		msg_col = Color(0.6, 0.68, 0.5)
		_sfx("miss", -8.0)
	busy = false
	phase = "show"
	pt = 0.0


## Крупная надпись поверх поля.
func _banner(s: String) -> void:
	banner = s
	banner_t = 0.0


## Монеты фонтаном из лотка (вид; сами монеты уже в сумке).
func _coin_fountain(amount: int) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.6
	p.amount = amount
	p.lifetime = 1.3
	p.position = Vector3(0, 0.29, 0.36)
	p.direction = Vector3(0, 1.0, 0.8)
	p.spread = 28.0
	p.initial_velocity_min = 1.8
	p.initial_velocity_max = 3.4
	p.gravity = Vector3(0, -9.0, 0)
	p.angular_velocity_min = -720.0
	p.angular_velocity_max = 720.0
	p.particle_flag_rotate_y = true
	var cm := CylinderMesh.new()
	cm.top_radius = 0.022
	cm.bottom_radius = 0.022
	cm.height = 0.005
	cm.radial_segments = 10
	cm.rings = 1
	var m := _glow(Color(0.95, 0.75, 0.25), 0.6)
	m.metallic = 0.9
	cm.material = m
	p.mesh = cm
	add_child(p)
	p.emitting = true
	get_tree().create_timer(p.lifetime + 1.0).timeout.connect(p.queue_free)


# ---------- кадр ----------

## Кадр: рычаг, жижа на бочке, лампы, смог на экране и текущая фаза.
func _process(delta: float) -> void:
	t += delta
	banner_t += delta
	lever_t += delta
	if lever:
		lever.rotation.x = 0.9 * sin(clampf(lever_t / 0.4, 0.0, 1.0) * PI)
	if ooze:
		var s := 1.0 + 0.08 * sin(t * 3.0) + (0.25 if phase == "burst" else 0.0)
		ooze.scale = Vector3(s, s * (1.0 + 0.15 * sin(t * 5.0)), s)
	var spd := 1.0 if phase == "show" else 3.0
	for k in bulbs.size():
		var m: StandardMaterial3D = bulbs[k]
		m.emission_energy_multiplier = 2.2 if (int(t * 5.0 * spd) + k) % 3 == 0 else 0.25
	if lamp:
		lamp.light_energy = 0.9 + (1.5 * absf(sin(t * 12.0)) if phase == "burst" else 0.0)
	for k in 9:
		flash[k] = maxf(0.0, float(flash[k]) - delta * 1.2)
	for k in smog.size():
		var b: Vector3 = smog[k]
		b.x += delta * (8.0 + float(k) * 1.5)
		if b.x - b.z > W:
			b = Vector3(-b.z, randf() * H, randf_range(40.0, 110.0))
		smog[k] = b
	match phase:
		"spin":
			_tick_spin(delta)
		"mutate":
			_tick_mutate(delta)
		"burst":
			_tick_burst(delta)
	if screen:
		screen.queue_redraw()


# ---------- экран ----------

## Прямоугольник клетки k (колонка×3 + ряд).
func _cell(k: int) -> Rect2:
	@warning_ignore("integer_division")
	var c := k / 3
	var r := k % 3
	return Rect2(X0 + c * (CW + GAP), TOP + r * CH, CW, CH - 6.0)


## Весь экран: смог, поле, вспышки бочек, линии, счётчик Гейгера, надписи.
func _draw_screen() -> void:
	var c := screen
	var font := ThemeDB.fallback_font
	c.draw_rect(Rect2(0, 0, W, H), Color(0.1, 0.12, 0.06))
	for b in smog:
		c.draw_circle(Vector2(b.x, b.y), b.z, Color(0.6, 0.65, 0.2, 0.07))
	c.draw_string(font, Vector2(0, 38), "РАДИАЦИЯ", HORIZONTAL_ALIGNMENT_CENTER, W, 34, Color(0.55, 1.0, 0.3))
	var blink := fmod(t * 4.0, 1.0) < 0.6
	for k in 9:
		var r := _cell(k)
		c.draw_rect(r, Color(0.05, 0.06, 0.04))
		var s := String(grid[k])
		var off := 0.0
		var a := 1.0
		@warning_ignore("integer_division")
		var col := k / 3
		if phase == "spin" and not col_stop[col]:
			s = SYMS[(int(t * 16.0) + k * 5) % SYMS.size()]
			off = fmod(t * 700.0 + k * 31.0, CH) - CH * 0.5
			a = 0.65
		_sym(c, s, Rect2(r.position + Vector2(0, off * 0.4), r.size), a)
		if float(flash[k]) > 0.0:
			c.draw_rect(r, Color(0.4, 1.0, 0.25, float(flash[k]) * 0.55))
		if phase == "show" and win_mask[k] and blink:
			c.draw_rect(r, Color(1.0, 0.85, 0.3), false, 4.0)
	if phase == "show":
		for li in win_lines:
			var ln: Array = LINES[li]
			var pts := PackedVector2Array()
			for k in ln:
				pts.append(_cell(int(k)).get_center())
			c.draw_polyline(pts, Color(1.0, 0.85, 0.3, 0.8), 4.0)
	if phase == "mutate" and mut_i < barrels.size():
		var cc := _cell(int(barrels[mut_i])).get_center()
		var q := pt / MUT_T
		c.draw_arc(cc, q * CW * 1.3, 0.0, TAU, 48, Color(0.4, 1.0, 0.2, 1.0 - q), 8.0)
		c.draw_circle(cc, 30.0 * (1.0 - q), Color(0.6, 1.0, 0.3, 0.6 * (1.0 - q)))
	if phase == "burst":
		c.draw_rect(Rect2(0, 0, W, H), Color(0.4, 1.0, 0.15, 0.25 + 0.2 * sin(t * 18.0)))
	# счётчик Гейгера
	var gy := FIELD_B + 8.0
	c.draw_string(font, Vector2(X0, gy + 20.0), "ГЕЙГЕР", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.7, 0.85, 0.5))
	var seg_w := 22.0
	for k in GEIGER:
		var on := k < geiger
		var col_g := Color(0.35, 1.0, 0.2) if k < GEIGER - 3 else Color(1.0, 0.3, 0.15)
		c.draw_rect(Rect2(X0 + 90.0 + k * (seg_w + 4.0), gy + 4.0, seg_w, 20.0), col_g if on else Color(0.15, 0.18, 0.12))
	c.draw_string(font, Vector2(0, gy + 56.0), msg, HORIZONTAL_ALIGNMENT_CENTER, W, 24, msg_col)
	c.draw_string(font, Vector2(0, gy + 84.0), "ставка ×%d   бочка — дикая, мутирует соседей" % bet, HORIZONTAL_ALIGNMENT_CENTER, W, 15, Color(0.55, 0.62, 0.45))
	if banner != "" and banner_t < 2.6:
		var bc := Color.from_hsv(0.28 + 0.08 * sin(t * 8.0), 0.8, 1.0)
		c.draw_rect(Rect2(0, H * 0.36, W, 70.0), Color(0, 0, 0, 0.7))
		c.draw_string(font, Vector2(0, H * 0.36 + 50.0), banner, HORIZONTAL_ALIGNMENT_CENTER, W, 42, bc)


## Треугольный сектор знака радиации.
func _wedge(c: CanvasItem, p: Vector2, r0: float, r1: float, a0: float, a1: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 7:
		var a := lerpf(a0, a1, float(i) / 6.0)
		pts.append(p + Vector2(cos(a), sin(a)) * r1)
	for i in 7:
		var a := lerpf(a1, a0, float(i) / 6.0)
		pts.append(p + Vector2(cos(a), sin(a)) * r0)
	c.draw_colored_polygon(pts, col)


## Символ в клетке: банка, шина, крыса, противогаз, неоновая 7, бочка.
func _sym(c: CanvasItem, id: String, r: Rect2, a: float) -> void:
	var p := r.get_center()
	var s := minf(r.size.x, r.size.y) * 0.38
	match id:
		"can":
			c.draw_rect(Rect2(p - Vector2(s * 0.45, s * 0.7), Vector2(s * 0.9, s * 1.4)), Color(0.55, 0.58, 0.62, a))
			c.draw_rect(Rect2(p - Vector2(s * 0.45, s * 0.25), Vector2(s * 0.9, s * 0.5)), Color(0.75, 0.2, 0.15, a))
			c.draw_line(p + Vector2(-s * 0.45, -s * 0.7), p + Vector2(s * 0.45, -s * 0.7), Color(0.8, 0.82, 0.85, a), 3.0)
			c.draw_line(p + Vector2(-s * 0.2, s * 0.3), p + Vector2(s * 0.1, s * 0.5), Color(0.35, 0.25, 0.15, a), 3.0)
		"tire":
			c.draw_circle(p, s * 0.85, Color(0.08, 0.08, 0.08, a))
			for i in 12:
				var an := TAU * i / 12.0
				c.draw_line(p + Vector2(cos(an), sin(an)) * s * 0.6, p + Vector2(cos(an), sin(an)) * s * 0.85, Color(0.25, 0.25, 0.25, a), 3.0)
			c.draw_circle(p, s * 0.38, Color(0.45, 0.45, 0.48, a))
			c.draw_circle(p, s * 0.14, Color(0.1, 0.1, 0.1, a))
		"rat":
			var fur := Color(0.45, 0.42, 0.4, a)
			c.draw_set_transform(p + Vector2(-s * 0.1, s * 0.15), 0.0, Vector2(1.5, 1.0))
			c.draw_circle(Vector2.ZERO, s * 0.42, fur)
			c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			c.draw_circle(p + Vector2(s * 0.55, -s * 0.05), s * 0.25, fur)
			c.draw_circle(p + Vector2(s * 0.45, -s * 0.3), s * 0.12, Color(0.85, 0.55, 0.55, a))
			c.draw_circle(p + Vector2(s * 0.62, -s * 0.1), s * 0.06, Color(1.0, 0.15, 0.1, a))
			var tail := PackedVector2Array()
			for i in 8:
				var u := float(i) / 7.0
				tail.append(p + Vector2(-s * 0.7 - u * s * 0.5, s * 0.2 + sin(u * 5.0 + t * 4.0) * s * 0.15))
			c.draw_polyline(tail, Color(0.85, 0.55, 0.55, a), 3.0)
		"mask":
			c.draw_circle(p, s * 0.75, Color(0.25, 0.32, 0.2, a))
			for sx in [-1.0, 1.0]:
				c.draw_circle(p + Vector2(sx * s * 0.32, -s * 0.18), s * 0.22, Color(0.05, 0.05, 0.05, a))
				c.draw_circle(p + Vector2(sx * s * 0.32 - s * 0.06, -s * 0.24), s * 0.06, Color(0.8, 0.9, 1.0, a * 0.8))
			c.draw_circle(p + Vector2(0, s * 0.42), s * 0.28, Color(0.12, 0.12, 0.12, a))
			c.draw_circle(p + Vector2(0, s * 0.42), s * 0.16, Color(0.4, 0.4, 0.38, a))
		"neon":
			var font := ThemeDB.fallback_font
			var glow := Color(1.0, 0.2, 0.8, a * (0.25 + 0.15 * sin(t * 9.0)))
			for o in [Vector2(-3, 0), Vector2(3, 0), Vector2(0, -3), Vector2(0, 3)]:
				c.draw_string(font, Vector2(r.position.x, p.y + 30.0) + o, "7", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 84, glow)
			c.draw_string(font, Vector2(r.position.x, p.y + 30.0), "7", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 84, Color(1.0, 0.75, 0.95, a))
		"barrel":
			c.draw_rect(Rect2(p - Vector2(s * 0.6, s * 0.85), Vector2(s * 1.2, s * 1.7)), Color(0.95, 0.78, 0.1, a))
			for y in [-0.5, 0.5]:
				c.draw_rect(Rect2(p + Vector2(-s * 0.6, s * y - 3.0), Vector2(s * 1.2, 6.0)), Color(0.1, 0.1, 0.05, a))
			var ink := Color(0.08, 0.08, 0.04, a)
			for i in 3:
				var a0 := -PI / 2.0 + TAU * i / 3.0 - 0.5
				_wedge(c, p, s * 0.14, s * 0.45, a0, a0 + 1.0, ink)
			c.draw_circle(p, s * 0.09, ink)
			c.draw_circle(p + Vector2(0, -s * 0.85), s * 0.3, Color(0.35, 1.0, 0.15, a * (0.7 + 0.3 * sin(t * 4.0))))
