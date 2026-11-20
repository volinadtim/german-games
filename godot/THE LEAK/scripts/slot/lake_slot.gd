extends StaticBody3D
## Автомат «КЛЁВ» в лагере у озера (lake_camp.gd, промпт 20.11 18:34) — самый необычный слот:
## на экране — подводный мир, и после остановки барабанов внутри поля идут анимированные события,
## которые меняют выигрыш. Поле 3×3, 5 линий (три ряда и две диагонали), три одинаковых в линию — PAY×ставка.
## Рыбы (окунь, щука, сом) несут ценник. РЫБАК закидывает леску к каждой рыбе на поле, подтягивает её
## и кладёт ценник в «УЛОВ»; два рыбака — улов ×2 (три — ×3).
## События (по порядку, до выплаты):
##  ЩУКА-РАЗБОЙНИЦА (PIKE_CHANCE, если рыб >= 2) — проплывает по ряду, глотает всех рыб в нём
##    и встаёт в конце ряда с ценником «сумма ×2»;
##  УТКА (DUCK_CHANCE, если рыбы есть, а рыбака нет) — пролетает, ныряет в клетку, оттуда выныривает рыбак;
##  САДОК — каждая пойманная рыба падает в садок справа; полный (BUCKET) — «УХА!»: UHA_PAY×ставка.
## Ставка — кнопка на полке слева. По сети не синхронизируется, садок не сохраняется.

const Sfx := preload("res://scripts/core/sfx.gd")
const Perks := preload("res://scripts/systems/perks.gd")
const SlotSounds := preload("res://scripts/slot/slot_sounds.gd")
const COST := 25
const BETS := [1, 2, 3, 5, 10]
const SYMS := ["worm", "float", "boot", "perch", "pike", "catfish", "fisher"]
const WEIGHT := {"worm": 20.0, "float": 16.0, "boot": 14.0, "perch": 10.0, "pike": 6.0, "catfish": 2.0, "fisher": 2.5}
const PAY := {"worm": 20, "float": 40, "perch": 60, "pike": 120, "catfish": 250, "fisher": 400}
const FISH_VAL := {"perch": [2, 3, 5, 5, 8, 10], "pike": [8, 10, 10, 15, 20, 30], "catfish": [20, 40, 40, 80, 150]}
const LINES := [[0, 3, 6], [1, 4, 7], [2, 5, 8], [0, 4, 8], [2, 4, 6]]
const PIKE_CHANCE := 0.15
const DUCK_CHANCE := 0.22
const BUCKET := 15
const UHA_PAY := 60
const PROFIT_CAP := 10000
const SPIN_T := 0.9
const STEP_T := 0.32
const PIKE_T := 2.4
const DUCK_T := 1.9
const DUCK_DIVE := 1.35
const CAST_T := 0.3
const PULL_T := 0.62
const JOB_T := 0.85
const UHA_T := 2.2
const W := 480
const H := 450
const X0 := 22.0
const CW := 120.0
const GAP := 8.0
const TOP := 46.0
const CH := 106.0
const FIELD_B := TOP + CH * 3.0
const INK := Color(0.06, 0.05, 0.05)

var game
var bet := 1
var busy := false
var profit := 0
var grid: Array = ["worm", "perch", "float", "boot", "fisher", "pike", "float", "worm", "catfish"]
var vals: Array = [0, 5, 0, 0, 0, 15, 0, 0, 40]
var strips: Array = [[], [], []]       # ленты барабанов: [символ, ценник]
var reel_q := [1.0, 1.0, 1.0]          # положение ленты (1 — показан результат)
var reel_dist := [10, 14, 18]
var reel_done := [true, true, true]
var phase := "show"                    # spin / pike / duck / collect / uha / show
var pt := 0.0                          # время внутри фазы
var t := 0.0
var spin_t := 0.0
var catch_sum := 0                     # улов крутки (без ставки)
var line_win := 0
var uha_win := 0
var nf := 1                            # рыбаков на поле
var win_mask := [false, false, false, false, false, false, false, false, false]
var win_lines: Array = []
var bucket := 0
var msg := "Брось монету — проверь клёв"
var msg_col := Color(0.75, 0.9, 1.0)
var banner := ""
var banner_t := 9.0
var pike_target := -1
var pike_eaten: Array = []
var pike_sum := 0
var duck_cell := -1
var jobs: Array = []                   # [клетка рыбака, клетка рыбы]
var job_i := 0
var job_gain := 0
var col_speed := 1.0
var reel_flag := false
var gone: Array = []                   # клетки, которые не рисуются (рыба съедена / поймана)
var vp: SubViewport
var screen: Control
var lever: Node3D
var lever_t := 9.0
var bet_l: Label3D
var hang: Node3D
var fish_kick := 0.0
var lamp: OmniLight3D
var bulbs: Array = []
var fx: Array = []
var sounds := {}
var spin_snd: AudioStreamPlayer3D
var bubbles: Array = []


func _ready() -> void:
	var body := _mat(Color(0.05, 0.15, 0.23), 0.3, 0.5)
	var wood := _mat(Color(0.45, 0.3, 0.16), 0.0, 0.85)
	var brass := _mat(Color(0.85, 0.66, 0.3), 1.0, 0.3)
	var dark := _mat(Color(0.02, 0.02, 0.03), 0.0, 0.9)
	_box(Vector3(1.04, 0.08, 0.7), Vector3(0, 0.04, 0), wood)                 # мостки-цоколь
	_box(Vector3(0.95, 0.86, 0.62), Vector3(0, 0.49, 0), body)
	for y in [0.2, 0.42, 0.64]:
		_box(Vector3(0.97, 0.07, 0.02), Vector3(0, y, 0.312), wood)          # доски на передней стенке
	_box(Vector3(0.9, 0.95, 0.5), Vector3(0, 1.37, -0.05), body)
	_box(Vector3(1.0, 0.06, 0.66), Vector3(0, 0.92, 0.0), wood)              # полка
	_box(Vector3(1.0, 0.36, 0.55), Vector3(0, 2.03, -0.05), body)            # вывеска
	_box(Vector3(0.94, 0.3, 0.02), Vector3(0, 2.03, 0.226), _mat(Color(0.92, 0.88, 0.74)))
	for sx in [-0.47, 0.47]:
		_box(Vector3(0.06, 1.86, 0.07), Vector3(sx, 1.0, 0.29), wood)        # столбы
	_box(Vector3(0.74, 0.7, 0.02), Vector3(0, 1.38, 0.2), dark)               # рамка экрана
	_box(Vector3(0.55, 0.12, 0.14), Vector3(0, 0.22, 0.3), dark)              # лоток
	_box(Vector3(0.6, 0.03, 0.18), Vector3(0, 0.3, 0.32), brass)
	# спасательный круг на вывеске
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.075
	tm.outer_radius = 0.125
	ring.mesh = tm
	ring.material_override = _mat(Color(0.95, 0.35, 0.1))
	ring.rotation.x = PI / 2.0
	ring.position = Vector3(0.36, 2.03, 0.25)
	add_child(ring)
	var sign_l := Label3D.new()
	sign_l.text = "КЛЁВ"
	sign_l.font_size = 72
	sign_l.pixel_size = 0.0024
	sign_l.modulate = Color(0.06, 0.25, 0.42)
	sign_l.outline_size = 8
	sign_l.outline_modulate = Color(1.0, 1.0, 1.0)
	sign_l.position = Vector3(-0.07, 2.03, 0.24)
	add_child(sign_l)
	# удочка над автоматом, на леске болтается рыба
	var rod := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.008
	rm.bottom_radius = 0.018
	rm.height = 1.1
	rod.mesh = rm
	rod.material_override = wood
	rod.rotation.z = -0.95
	rod.position = Vector3(-0.45, 2.21, 0.0) + Vector3(sin(0.95), cos(0.95), 0) * 0.55
	add_child(rod)
	hang = Node3D.new()
	hang.position = Vector3(-0.45, 2.21, 0.0) + Vector3(sin(0.95), cos(0.95), 0) * 1.1
	add_child(hang)
	var ln := MeshInstance3D.new()
	var lb := BoxMesh.new()
	lb.size = Vector3(0.004, 0.42, 0.004)
	ln.mesh = lb
	ln.material_override = _mat(Color(0.9, 0.9, 0.9))
	ln.position.y = -0.21
	hang.add_child(ln)
	var fsh := MeshInstance3D.new()
	var fs := SphereMesh.new()
	fs.radius = 0.07
	fs.height = 0.14
	fsh.mesh = fs
	fsh.material_override = _mat(Color(0.55, 0.62, 0.45), 0.4, 0.35)
	fsh.scale = Vector3(0.6, 2.2, 1.0)
	fsh.position.y = -0.55
	hang.add_child(fsh)
	var tail := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(0.01, 0.08, 0.12)
	tail.mesh = tb
	tail.material_override = fsh.material_override
	tail.position.y = -0.73
	hang.add_child(tail)
	# рычаг с красно-белым поплавком
	_box(Vector3(0.08, 0.12, 0.12), Vector3(0.5, 1.05, 0.05), brass)
	lever = Node3D.new()
	lever.position = Vector3(0.54, 1.05, 0.05)
	add_child(lever)
	var stick := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.035, 0.48, 0.035)
	stick.mesh = bm
	stick.material_override = brass
	stick.position = Vector3(0, 0.24, 0)
	lever.add_child(stick)
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.12
	ball.mesh = sm
	ball.material_override = _glow(Color(0.95, 0.15, 0.1), 0.8)
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
	# лампы-огоньки по рамке экрана
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
	lamp.light_color = Color(0.45, 0.8, 1.0)
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
	_build_bet_button(brass)
	for k in 14:
		bubbles.append(Vector3(randf() * W, randf() * H, randf_range(2.0, 6.0)))


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
	bet_l.modulate = Color(0.05, 0.1, 0.2)
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
	return "[F] Ставка КЛЁВ: ×%d → ×%d" % [bet, int(BETS[(i + 1) % BETS.size()])]


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
	var m := _glow(Color(0.4, 0.85, 1.0) if bulbs.size() % 2 == 0 else Color(1.0, 0.95, 0.8), 0.4)
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


## Синтез всех звуков автомата: крутка, стоп, всплеск, чавк щуки, кряк, трещотка катушки, выигрыши.
func _make_sounds() -> void:
	var r := Sfx.RATE
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	# крутка: трещотка + бульканье; петля
	var n := int(1.0 * r)
	var spin := PackedFloat32Array()
	spin.resize(n)
	for i in n:
		var tt := float(i) / r
		var seg := fmod(tt * 14.0, 1.0) / 14.0
		spin[i] = rng.randf_range(-1, 1) * exp(-seg * 550.0) * 0.7 + sin(TAU * (180.0 + 60.0 * sin(TAU * 6.0 * tt)) * tt) * 0.08
	var st := Sfx._wav(spin, 0.5)
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_end = n - int(r * 0.03)
	sounds["spin"] = st
	# остановка барабана
	var m := int(0.22 * r)
	var stop := PackedFloat32Array()
	stop.resize(m)
	for i in m:
		var tt := float(i) / r
		stop[i] = sin(TAU * 140.0 * tt) * exp(-tt * 28.0) + rng.randf_range(-1, 1) * exp(-tt * 260.0) * 0.6
	sounds["stop"] = Sfx._wav(stop, 0.8)
	# всплеск: шум через простой фильтр
	m = int(0.6 * r)
	var sp := PackedFloat32Array()
	sp.resize(m)
	var lp := 0.0
	for i in m:
		var tt := float(i) / r
		var nz := rng.randf_range(-1, 1)
		lp = lerpf(lp, nz, 0.22)
		sp[i] = (lp * 1.8 + nz * 0.12) * exp(-tt * 6.0) * minf(tt * 80.0, 1.0)
	sounds["splash"] = Sfx._wav(sp, 0.8)
	# чавк щуки: два глухих удара
	m = int(0.35 * r)
	var ch := PackedFloat32Array()
	ch.resize(m)
	for i in m:
		var tt := float(i) / r
		var a := 0.0
		for s0 in [0.0, 0.13]:
			if tt >= s0:
				var u: float = tt - s0
				a += sin(TAU * (95.0 - u * 120.0) * u) * exp(-u * 30.0) + rng.randf_range(-1, 1) * exp(-u * 90.0) * 0.5
		ch[i] = a * 0.7
	sounds["chomp"] = Sfx._wav(ch, 0.85)
	# кряк: пила с падающим тоном, два раза
	m = int(0.5 * r)
	var qk := PackedFloat32Array()
	qk.resize(m)
	var ph := 0.0
	for i in m:
		var tt := float(i) / r
		var u := fmod(tt, 0.25)
		var f := 430.0 - u * 600.0
		ph += f / r
		var saw := fmod(ph, 1.0) * 2.0 - 1.0
		qk[i] = saw * (sin(PI * minf(u / 0.18, 1.0)) if u < 0.18 else 0.0) * 0.55
	sounds["quack"] = Sfx._wav(qk, 0.6)
	# катушка: частые щелчки с растущим тоном
	m = int(0.4 * r)
	var rl := PackedFloat32Array()
	rl.resize(m)
	for i in m:
		var tt := float(i) / r
		var seg := fmod(tt * 30.0, 1.0) / 30.0
		rl[i] = rng.randf_range(-1, 1) * exp(-seg * 500.0) * 0.6 + sin(TAU * (1200.0 + tt * 900.0) * tt) * exp(-seg * 300.0) * 0.2
	sounds["reel"] = Sfx._wav(rl, 0.55)
	sounds["win"] = Sfx._wav(_notes([[523.0, 0.0, 0.2], [659.0, 0.09, 0.2], [784.0, 0.18, 0.35]], 0.6), 0.7)
	var big := []
	var up_notes := [392.0, 523.0, 659.0, 784.0, 659.0, 784.0, 1047.0]
	for k in up_notes.size():
		big.append([up_notes[k], k * 0.08, 0.2])
	for f in [523.0, 659.0, 784.0, 1047.0]:
		big.append([f, 0.6, 0.9])
	sounds["big"] = Sfx._wav(_notes(big, 1.6, 3.0), 0.75)
	sounds["miss"] = Sfx._wav(_notes([[330.0, 0.0, 0.16], [262.0, 0.13, 0.3]], 0.45, 7.0), 0.45)


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


# ---------- взаимодействие ----------

## Подсказка у автомата.
func get_prompt(g) -> String:
	if busy:
		return ""
	var cost := Perks.cost(COST * bet)
	if g.inv.coins >= cost:
		return "[F] КЛЁВ ×%d — закинуть за %d монет" % [bet, cost]
	return "КЛЁВ ×%d: нужно %d монет" % [bet, cost]


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
	var total := 0.0
	for s in SYMS:
		total += float(WEIGHT[s])
	var r := randf() * total
	for s in SYMS:
		r -= float(WEIGHT[s])
		if r <= 0.0:
			return String(s)
	return "worm"


## Ценник рыбы (0 — не рыба).
func _val(s: String) -> int:
	if not FISH_VAL.has(s):
		return 0
	var arr: Array = FISH_VAL[s]
	return int(arr[randi() % arr.size()])


## Новая крутка: результат, ленты барабанов, сброс событий.
func _spin_start() -> void:
	busy = true
	phase = "spin"
	spin_t = 0.0
	pt = 0.0
	catch_sum = 0
	line_win = 0
	uha_win = 0
	banner = ""
	pike_target = -1
	pike_eaten.clear()
	pike_sum = 0
	duck_cell = -1
	jobs.clear()
	gone.clear()
	win_lines.clear()
	for k in 9:
		win_mask[k] = false
	var ng: Array = []
	var nv: Array = []
	for k in 9:
		var s := _roll()
		ng.append(s)
		nv.append(_val(s))
	# лента: [0] запас, [1..3] новый результат, дальше случайные, последние три — старое поле
	for i in 3:
		var stp: Array = []
		var rs := _roll()
		stp.append([rs, _val(rs)])
		for r in 3:
			stp.append([ng[i * 3 + r], nv[i * 3 + r]])
		var dist: int = int(reel_dist[i])
		for _k in dist - 3:
			var s2 := _roll()
			stp.append([s2, _val(s2)])
		for r in 3:
			stp.append([grid[i * 3 + r], vals[i * 3 + r]])
		strips[i] = stp
		reel_q[i] = float(stp.size() - 3)
		reel_done[i] = false
	grid = ng
	vals = nv
	msg = "Клюёт?.."
	msg_col = Color(0.75, 0.9, 1.0)
	lever_t = 0.0
	SlotSounds.play3d(self, SlotSounds.lever(), lever.global_position, -7.0, randf_range(1.0, 1.08))
	spin_snd.stream = sounds["spin"]
	spin_snd.volume_db = -10.0
	spin_snd.play()


## Клетки, где лежит символ id.
func _cells_of(id: String) -> Array:
	var out: Array = []
	for k in 9:
		if grid[k] == id:
			out.append(k)
	return out


## Клетки с рыбой (у неё есть ценник).
func _fish_cells() -> Array:
	var out: Array = []
	for k in 9:
		if int(vals[k]) > 0:
			out.append(k)
	return out


## Барабаны встали: решаем, приплывёт ли щука.
func _after_spin() -> void:
	var fish := _fish_cells()
	if fish.size() >= 2 and randf() < PIKE_CHANCE:
		# ряд, где рыб больше всего; щука встаёт в самой правой клетке ряда без рыбака
		var best := -1
		var best_n := 0
		for row in 3:
			var cnt := 0
			for i in 3:
				if int(vals[i * 3 + row]) > 0:
					cnt += 1
			if cnt > best_n:
				best_n = cnt
				best = row
		if best >= 0:
			for i in [2, 1, 0]:
				if grid[i * 3 + best] != "fisher":
					pike_target = i * 3 + best
					break
			if pike_target >= 0:
				for i in 3:
					var k := i * 3 + best
					if k <= pike_target and int(vals[k]) > 0:
						pike_eaten.append(k)
				phase = "pike"
				pt = 0.0
				_banner("ЩУКА-РАЗБОЙНИЦА!")
				_sfx("splash", -4.0, 0.7)
				return
	_after_pike()


## После щуки: если рыбака нет, может прилететь утка.
func _after_pike() -> void:
	if _cells_of("fisher").is_empty() and not _fish_cells().is_empty() and randf() < DUCK_CHANCE:
		var spots: Array = []
		for k in 9:
			if int(vals[k]) == 0:
				spots.append(k)
		if spots.is_empty():
			spots = _fish_cells()
		duck_cell = int(spots[randi() % spots.size()])
		phase = "duck"
		pt = 0.0
		_banner("УТКА!")
		_sfx("quack", -3.0)
		return
	_start_collect()


## Считаем линии и запускаем вытягивание рыбы рыбаками.
func _start_collect() -> void:
	_eval_lines()
	jobs.clear()
	var fishers := _cells_of("fisher")
	nf = fishers.size()
	var fish := _fish_cells()
	if nf > 0:
		for n in fish.size():
			jobs.append([fishers[n % nf], fish[n]])
	job_i = 0
	pt = 0.0
	reel_flag = false
	if jobs.is_empty():
		_after_collect()
		return
	phase = "collect"
	col_speed = clampf(jobs.size() / 4.0, 1.0, 2.2)
	_banner("КЛЮЁТ!" if nf == 1 else "%d РЫБАКА — УЛОВ ×%d" % [nf, nf])
	_sfx("splash", -10.0, 1.4)


## Три одинаковых в линию — PAY×ставка.
func _eval_lines() -> void:
	line_win = 0
	win_lines.clear()
	for li in LINES.size():
		var l: Array = LINES[li]
		var s := String(grid[l[0]])
		if not PAY.has(s) or grid[l[1]] != s or grid[l[2]] != s:
			continue
		line_win += int(PAY[s]) * bet
		win_lines.append(li)
		for k in l:
			win_mask[k] = true


## Улов собран: пойманные рыбы оставляют круги на воде; полный садок — уха.
func _after_collect() -> void:
	for k in gone:
		grid[k] = "ripple"
		vals[k] = 0
	gone.clear()
	if bucket >= BUCKET:
		phase = "uha"
		pt = 0.0
		uha_win = UHA_PAY * bet
		_banner("УХА! +%d" % uha_win)
		_sfx("big", -2.0, 0.9)
		return
	_payout()


## Большая надпись поверх поля.
func _banner(s: String) -> void:
	banner = s
	banner_t = 0.0


## Выплата: линии + улов×ставка + уха.
func _payout() -> void:
	var catch_w := catch_sum * bet
	var win := line_win + catch_w + uha_win
	win = clampi(win, 0, maxi(PROFIT_CAP - profit, 0))
	profit += win
	var parts: Array = []
	if line_win > 0:
		parts.append("линии %d" % line_win)
	if catch_w > 0:
		parts.append("улов %d" % catch_w)
	if uha_win > 0:
		parts.append("уха %d" % uha_win)
	if win > 0:
		msg = "+%d МОНЕТ  (%s)" % [win, ", ".join(parts)]
		msg_col = Color(1.0, 0.85, 0.35)
		if game:
			game.inv.add("coin", win)
		var big := win >= 8 * COST * bet
		_coin_fountain(30 if big else 10)
		_sfx("big" if big else "win", -3.0)
		fish_kick = 1.0 if big else 0.5
	else:
		msg = "Не клюёт..."
		msg_col = Color(0.65, 0.72, 0.8)
		_sfx("miss", -8.0)
	busy = false
	phase = "show"
	pt = 0.0


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

## Кадр: рычаг, рыба на удочке, лампы, пузыри и текущая фаза крутки.
func _process(delta: float) -> void:
	t += delta
	banner_t += delta
	lever_t += delta
	if lever:
		lever.rotation.x = 0.9 * sin(clampf(lever_t / 0.4, 0.0, 1.0) * PI)
	fish_kick = maxf(0.0, fish_kick - delta * 0.4)
	if hang:
		hang.rotation.z = sin(t * 1.6) * 0.18
		hang.rotation.x = sin(t * 13.0) * 0.6 * fish_kick
	var spd := 1.0 if phase == "show" else 3.0
	for k in bulbs.size():
		var m: StandardMaterial3D = bulbs[k]
		m.emission_energy_multiplier = 2.2 if (int(t * 5.0 * spd) + k) % 3 == 0 else 0.25
	for k in bubbles.size():
		var b: Vector3 = bubbles[k]
		b.y -= delta * (20.0 + b.z * 6.0)
		b.x += sin(t * 2.0 + k) * delta * 8.0
		if b.y < 0.0:
			b = Vector3(randf() * W, H + 10.0, randf_range(2.0, 6.0))
		bubbles[k] = b
	match phase:
		"spin":
			_tick_spin(delta)
		"pike":
			_tick_pike(delta)
		"duck":
			_tick_duck(delta)
		"collect":
			_tick_collect(delta)
		"uha":
			pt += delta
			if pt >= UHA_T:
				bucket = 0
				_payout()
	if screen:
		screen.queue_redraw()


## Барабаны: лента едет вниз и тормозит, после стопа — пружинка.
func _tick_spin(delta: float) -> void:
	spin_t += delta
	var all := true
	for i in 3:
		var tt := SPIN_T + i * STEP_T
		var dist := float(reel_dist[i])
		if spin_t < tt:
			reel_q[i] = 1.0 + dist * pow(1.0 - spin_t / tt, 2.2)
			all = false
			continue
		if not reel_done[i]:
			reel_done[i] = true
			_sfx("stop", -6.0, 1.0 + i * 0.06)
		var tau := spin_t - tt
		if tau < 0.3:
			reel_q[i] = 1.0 - 0.16 * sin(PI * tau / 0.3) * (1.0 - tau / 0.3)
			all = false
		else:
			reel_q[i] = 1.0
	if all:
		spin_snd.stop()
		_after_spin()


## Где сейчас голова щуки (x на экране).
func _pike_x() -> float:
	var tx := _cell(pike_target).get_center().x + CW * 0.4
	return lerpf(-CW * 0.2, tx, smoothstep(0.0, 1.0, pt / PIKE_T))


## Щука плывёт по ряду и глотает рыб, которых проходит головой.
func _tick_pike(delta: float) -> void:
	pt += delta
	var hx := _pike_x()
	for k in pike_eaten:
		if not (k in gone) and hx >= _cell(k).get_center().x:
			gone.append(k)
			pike_sum += int(vals[k])
			_sfx("chomp", -3.0, randf_range(0.9, 1.1))
	if pt < PIKE_T:
		return
	for k in pike_eaten:
		grid[k] = "ripple"
		vals[k] = 0
	gone.clear()
	grid[pike_target] = "pike"
	vals[pike_target] = pike_sum * 2
	_banner("ЩУКА ×2: %d" % (pike_sum * 2 * bet))
	_sfx("splash", -6.0, 0.9)
	_after_pike()


## Утка летит, ныряет в клетку — там появляется рыбак.
func _tick_duck(delta: float) -> void:
	pt += delta
	if pt >= DUCK_DIVE and grid[duck_cell] != "fisher":
		grid[duck_cell] = "fisher"
		vals[duck_cell] = 0
		_sfx("splash", -2.0, 1.1)
	if pt >= DUCK_T:
		_start_collect()


## Рыбак по очереди закидывает леску к рыбе и тянет её к себе.
func _tick_collect(delta: float) -> void:
	pt += delta * col_speed
	var job: Array = jobs[job_i]
	var fk: int = job[1]
	if pt >= CAST_T and not reel_flag:
		reel_flag = true
		_sfx("reel", -6.0, randf_range(0.95, 1.1))
	if pt >= PULL_T and not (fk in gone):
		gone.append(fk)
		job_gain = int(vals[fk]) * nf
		catch_sum += job_gain
		bucket = mini(bucket + 1, BUCKET)
		SlotSounds.play3d(self, SlotSounds.clink(), global_position + Vector3(0, 1.3, 0.3), -10.0, randf_range(0.95, 1.15))
	if pt >= JOB_T:
		job_i += 1
		pt = 0.0
		reel_flag = false
		if job_i >= jobs.size():
			_after_collect()
		else:
			_sfx("splash", -14.0, 1.5)


# ---------- экран ----------

## Клетка k (барабан k/3, ряд k%3).
func _cell(k: int) -> Rect2:
	var i := int(k / 3.0)
	return Rect2(X0 + i * (CW + GAP), TOP + (k % 3) * CH, CW, CH)


## Квадрат символа внутри клетки.
func _inner(cell: Rect2) -> Rect2:
	var s := minf(cell.size.x, cell.size.y) - 12.0
	return Rect2(cell.get_center() - Vector2(s, s) / 2.0, Vector2(s, s))


## Кончик удочки рыбака в клетке k.
func _tip(k: int) -> Vector2:
	var r := _inner(_cell(k))
	return r.get_center() + Vector2(r.size.x * 0.42, -r.size.x * 0.42)


## Леска с провисом от a до b.
func _line(c: CanvasItem, a: Vector2, b: Vector2, sag: float) -> void:
	var mid := (a + b) / 2.0 + Vector2(0, sag)
	var pts := PackedVector2Array()
	for k in 13:
		var u := k / 12.0
		pts.append(a.lerp(mid, u).lerp(mid.lerp(b, u), u))
	c.draw_polyline(pts, Color(0.92, 0.95, 1.0, 0.9), 1.6)


## Рисует экран: вода, барабаны, события, садок, табло и надпись.
func _draw_screen() -> void:
	var c := screen
	var font := ThemeDB.fallback_font
	# вода: от светлой к тёмной, волны и пузыри
	for k in 12:
		c.draw_rect(Rect2(0, k * H / 12.0, W, H / 12.0 + 1.0), Color(0.06, 0.3, 0.42).lerp(Color(0.01, 0.07, 0.14), k / 11.0))
	for wv in 3:
		var pts := PackedVector2Array()
		for k in 25:
			var x := k * 20.0
			pts.append(Vector2(x, 80.0 + wv * 110.0 + sin(x * 0.03 + t * 1.5 + wv) * 6.0))
		c.draw_polyline(pts, Color(0.5, 0.85, 1.0, 0.08), 2.0)
	for b in bubbles:
		c.draw_arc(Vector2(b.x, b.y), b.z, 0, TAU, 10, Color(0.7, 0.9, 1.0, 0.3), 1.2)
	# клетки
	for k in 9:
		var col := Color(0.0, 0.04, 0.09, 0.35)
		if phase == "show" and win_mask[k] and fmod(t, 0.5) < 0.3:
			col = Color(1.0, 0.8, 0.3, 0.35)
		c.draw_rect(_cell(k).grow(-2.0), col)
	# символы
	if phase == "spin":
		for i in 3:
			var q: float = reel_q[i]
			var base := int(floor(q))
			var fr := q - base
			var stp: Array = strips[i]
			for j in 4:
				var idx := base + j
				if idx < 0 or idx >= stp.size():
					continue
				var e: Array = stp[idx]
				var r := Rect2(X0 + i * (CW + GAP), TOP + (j - fr) * CH, CW, CH)
				_sym(c, String(e[0]), _inner(r), int(e[1]))
	else:
		var cur := -1
		if phase == "collect" and job_i < jobs.size() and pt >= CAST_T:
			cur = int(jobs[job_i][1])
		for k in 9:
			if k in gone or k == cur:
				continue
			var sc := 1.0
			if phase == "duck" and k == duck_cell and pt >= DUCK_DIVE:
				sc = clampf((pt - DUCK_DIVE) / 0.3, 0.05, 1.0)
			_sym(c, String(grid[k]), _inner(_cell(k)), int(vals[k]), sc)
	# маски сверху и снизу (обрезают ленты)
	var panel := Color(0.02, 0.08, 0.13)
	var brass := Color(0.88, 0.7, 0.35)
	c.draw_rect(Rect2(0, 0, W, TOP), panel)
	c.draw_rect(Rect2(0, FIELD_B, W, H - FIELD_B), panel)
	c.draw_line(Vector2(0, TOP), Vector2(W, TOP), brass, 2.0)
	c.draw_line(Vector2(0, FIELD_B), Vector2(W, FIELD_B), brass, 2.0)
	c.draw_string(font, Vector2(0, 34), "~ К Л Ё В ~", HORIZONTAL_ALIGNMENT_CENTER, W, 30, Color(1.0, 0.86, 0.45))
	# выигравшие линии
	if phase == "show" and fmod(t, 0.5) < 0.35:
		for li in win_lines:
			var l: Array = LINES[li]
			var pts := PackedVector2Array()
			for k in l:
				pts.append(_cell(k).get_center())
			c.draw_polyline(pts, Color(1.0, 0.85, 0.3, 0.8), 4.0)
	# события
	if phase == "pike":
		_draw_pike(c, font)
	elif phase == "duck":
		_draw_duck(c)
	elif phase == "collect" and job_i < jobs.size():
		_draw_catch(c, font)
	_draw_keepnet(c, font)
	# табло
	c.draw_string(font, Vector2(10, FIELD_B + 30), msg, HORIZONTAL_ALIGNMENT_CENTER, W - 20, 19, msg_col)
	c.draw_string(font, Vector2(14, H - 14), "УЛОВ: %d" % (catch_sum * bet), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.6, 0.95, 1.0))
	c.draw_string(font, Vector2(0, H - 14), "СТАВКА ×%d" % bet, HORIZONTAL_ALIGNMENT_RIGHT, W - 14, 22, brass)
	# большая надпись
	if banner != "" and banner_t < 1.8:
		var a := 1.0 - maxf(0.0, banner_t - 1.3) / 0.5
		var fs := int(40.0 * (0.6 + 0.4 * minf(banner_t / 0.15, 1.0)))
		var y := TOP + CH * 1.6
		c.draw_string_outline(font, Vector2(0, y), banner, HORIZONTAL_ALIGNMENT_CENTER, W, fs, 8, Color(INK, a))
		c.draw_string(font, Vector2(0, y), banner, HORIZONTAL_ALIGNMENT_CENTER, W, fs, Color(1.0, 0.9, 0.4, a))


## Щука: плывёт по ряду, ценник растёт от проглоченных рыб.
func _draw_pike(c: CanvasItem, font: Font) -> void:
	var pl := CW * 1.6
	var y := _cell(pike_target).get_center().y
	var hx := _pike_x()
	var p := Vector2(hx - pl * 0.45, y + sin(t * 9.0) * 3.0)
	_fish(c, p, pl, CH * 0.45, Color(0.33, 0.5, 0.24), Color(0.78, 0.82, 0.55), "pike")
	# пасть хлопает
	var mouth := p + Vector2(pl * 0.45, CH * 0.03)
	var o := absf(sin(t * 14.0)) * CH * 0.08
	c.draw_colored_polygon(PackedVector2Array([mouth + Vector2(-pl * 0.12, 0), mouth + Vector2(0, -o), mouth + Vector2(0, o)]), INK)
	if pike_sum > 0:
		var txt := "%d ×2" % (pike_sum * bet)
		c.draw_string_outline(font, p + Vector2(-60, -CH * 0.3), txt, HORIZONTAL_ALIGNMENT_CENTER, 120, 24, 6, INK)
		c.draw_string(font, p + Vector2(-60, -CH * 0.3), txt, HORIZONTAL_ALIGNMENT_CENTER, 120, 24, Color(1.0, 0.85, 0.3))


## Утка: летит над водой, ныряет, по воде круги.
func _draw_duck(c: CanvasItem) -> void:
	var tc := _cell(duck_cell).get_center()
	var p: Vector2
	if pt < 1.0:
		p = Vector2(-40, TOP - 6).lerp(Vector2(tc.x, TOP + 14), pt) + Vector2(0, sin(pt * 12.0) * 5.0)
	elif pt < DUCK_DIVE:
		p = Vector2(tc.x, TOP + 14).lerp(tc, (pt - 1.0) / (DUCK_DIVE - 1.0))
	else:
		var u := (pt - DUCK_DIVE) / (DUCK_T - DUCK_DIVE)
		for k in 3:
			var rr := (u + k * 0.25) * 60.0
			c.draw_arc(tc, rr, 0, TAU, 24, Color(0.8, 0.95, 1.0, maxf(0.0, 0.8 - u - k * 0.2)), 2.0)
		return
	var s := 46.0
	var flap := sin(t * 22.0)
	var bd := PackedVector2Array()
	for k in 16:
		var a := TAU * k / 16.0
		bd.append(p + Vector2(cos(a) * s * 0.5, sin(a) * s * 0.28))
	c.draw_colored_polygon(bd, Color(0.55, 0.4, 0.25))
	c.draw_polyline(bd + PackedVector2Array([bd[0]]), INK, 2.0)
	c.draw_colored_polygon(PackedVector2Array([p + Vector2(-s * 0.15, -s * 0.05), p + Vector2(s * 0.2, -s * 0.05),
		p + Vector2(0, -s * 0.05 - s * 0.45 * flap)]), Color(0.4, 0.3, 0.2))
	var hd := p + Vector2(s * 0.45, -s * 0.22)
	c.draw_circle(hd, s * 0.19, INK)
	c.draw_circle(hd, s * 0.17, Color(0.1, 0.5, 0.25))
	c.draw_colored_polygon(PackedVector2Array([hd + Vector2(s * 0.12, -s * 0.04), hd + Vector2(s * 0.38, s * 0.02), hd + Vector2(s * 0.12, s * 0.08)]), Color(1.0, 0.6, 0.1))
	c.draw_circle(hd + Vector2(s * 0.05, -s * 0.05), s * 0.035, INK)


## Леска рыбака и рыба, которую тянут.
func _draw_catch(c: CanvasItem, font: Font) -> void:
	var job: Array = jobs[job_i]
	var fi: int = job[0]
	var fk: int = job[1]
	var tip := _tip(fi)
	var fr := _inner(_cell(fk))
	var fc := fr.get_center()
	if pt < CAST_T:
		var e := pt / CAST_T
		_line(c, tip, tip.lerp(fc, e), 30.0 * e)
	elif pt < PULL_T:
		var e := smoothstep(CAST_T, PULL_T, pt)
		var p := fc.lerp(tip, e)
		_line(c, tip, p, 12.0 * (1.0 - e))
		var r := fr
		r.position += p - fc
		_sym(c, String(grid[fk]), r, int(vals[fk]), 1.0 - 0.5 * e)
	else:
		var a := 1.0 - (pt - PULL_T) / (JOB_T - PULL_T)
		var tp := tip + Vector2(-60, -(pt - PULL_T) * 120.0)
		var txt := "+%d" % (job_gain * bet)
		c.draw_string_outline(font, tp, txt, HORIZONTAL_ALIGNMENT_CENTER, 120, 26, 6, Color(INK, a))
		c.draw_string(font, tp, txt, HORIZONTAL_ALIGNMENT_CENTER, 120, 26, Color(1.0, 0.88, 0.35, a))


## Садок справа: рыбки складываются стопкой; полный — уха.
func _draw_keepnet(c: CanvasItem, font: Font) -> void:
	var x0 := X0 + 3.0 * (CW + GAP) + 2.0
	var x1 := W - 6.0
	var y0 := TOP + 24.0
	var y1 := FIELD_B - 4.0
	var full := bucket >= BUCKET
	var net_col := Color(0.85, 0.75, 0.5, 0.5) if not (full and fmod(t, 0.3) < 0.15) else Color(1.0, 0.85, 0.3, 0.9)
	c.draw_string(font, Vector2(x0 - 4, TOP + 18), "САДОК", HORIZONTAL_ALIGNMENT_CENTER, x1 - x0 + 8, 14, Color(0.85, 0.8, 0.6))
	c.draw_rect(Rect2(x0, y0, x1 - x0, y1 - y0), Color(0.0, 0.03, 0.06, 0.4))
	for k in 5:
		var x := lerpf(x0, x1, k / 4.0)
		c.draw_line(Vector2(x, y0), Vector2(x, y1), net_col, 1.0)
	for k in 13:
		var y := lerpf(y0, y1, k / 12.0)
		c.draw_line(Vector2(x0, y), Vector2(x1, y), net_col, 1.0)
	c.draw_rect(Rect2(x0, y0, x1 - x0, y1 - y0), net_col, false, 2.0)
	var cx := (x0 + x1) / 2.0
	for n in bucket:
		var y := y1 - 12.0 - n * 17.0
		var off := Vector2.ZERO
		if phase == "uha":
			off = Vector2(sin(n * 2.3) * pt * 40.0, -pt * pt * 90.0 * (1.0 + n * 0.05))
		var cols: Array = [Color(0.55, 0.65, 0.3), Color(0.35, 0.5, 0.25), Color(0.45, 0.42, 0.38)]
		_fish(c, Vector2(cx + (4.0 if n % 2 == 0 else -4.0), y) + off, 42.0, 13.0, cols[n % 3], Color(0.85, 0.85, 0.7), "")
	c.draw_string(font, Vector2(x0 - 4, y1 + 0.0 - 2.0 - bucket * 17.0 - 18.0), "%d/%d" % [bucket, BUCKET], HORIZONTAL_ALIGNMENT_CENTER, x1 - x0 + 8, 13, Color(0.8, 0.95, 1.0, 0.8))
	if phase == "uha":
		for k in 5:   # пар от ухи
			var u := fmod(t * 0.8 + k * 0.2, 1.0)
			c.draw_circle(Vector2(cx + sin(t * 3.0 + k) * 12.0, y1 - u * (y1 - y0)), 6.0 + u * 10.0, Color(1, 1, 1, 0.25 * (1.0 - u)))


## Рыба: тело-эллипс, светлое брюхо, хвост, глаз; kind — полоски окуня, пятна щуки, усы сома.
func _fish(c: CanvasItem, p: Vector2, ln: float, h: float, body: Color, belly: Color, kind: String) -> void:
	var tail := PackedVector2Array([p + Vector2(-ln * 0.38, 0), p + Vector2(-ln * 0.62, -h * 0.55), p + Vector2(-ln * 0.55, 0), p + Vector2(-ln * 0.62, h * 0.55)])
	c.draw_colored_polygon(tail, body.darkened(0.25))
	c.draw_polyline(tail + PackedVector2Array([tail[0]]), INK, 2.0)
	var pts := PackedVector2Array()
	for k in 22:
		var a := TAU * k / 22.0
		pts.append(p + Vector2(cos(a) * ln * 0.45, sin(a) * h * 0.5))
	c.draw_colored_polygon(pts, body)
	var bl := PackedVector2Array()
	for k in 12:
		var a := PI * k / 11.0
		bl.append(p + Vector2(cos(a) * ln * 0.4, h * 0.05 + sin(a) * h * 0.38))
	c.draw_colored_polygon(bl, belly)
	match kind:
		"perch":
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(-ln * 0.2, -h * 0.45), p + Vector2(-ln * 0.05, -h * 0.85), p + Vector2(ln * 0.12, -h * 0.45)]), Color(0.9, 0.3, 0.15))
			for k in 4:
				var x := p.x - ln * 0.2 + k * ln * 0.12
				c.draw_line(Vector2(x, p.y - h * 0.45), Vector2(x, p.y + h * 0.15), body.darkened(0.55), 3.0)
		"pike":
			for k in 5:
				c.draw_circle(p + Vector2(-ln * 0.25 + k * ln * 0.12, -h * 0.12 + (k % 2) * h * 0.14), h * 0.06, belly.lightened(0.2))
		"catfish":
			for d in [-1.0, 1.0]:
				c.draw_line(p + Vector2(ln * 0.42, h * 0.08), p + Vector2(ln * 0.66, h * (0.1 + 0.25 * d)), INK, 2.0)
	c.draw_polyline(pts + PackedVector2Array([pts[0]]), INK, 2.5)
	var eye := p + Vector2(ln * 0.28, -h * 0.12)
	c.draw_circle(eye, maxf(h * 0.11, 1.5), Color(1, 1, 1))
	c.draw_circle(eye + Vector2(1, 0), maxf(h * 0.06, 1.0), INK)


## Символ id в квадрате r; v — ценник рыбы (×ставка), sc — масштаб от центра.
func _sym(c: CanvasItem, id: String, r: Rect2, v: int, sc := 1.0) -> void:
	var p := r.get_center()
	var s := r.size.x
	c.draw_set_transform(p * (1.0 - sc), 0.0, Vector2(sc, sc))
	match id:
		"worm":
			var pts := PackedVector2Array()
			for k in 10:
				pts.append(p + Vector2((-0.36 + 0.08 * k) * s, sin(k * 0.9 + t * 4.0) * s * 0.1))
			c.draw_polyline(pts, INK, s * 0.17)
			c.draw_polyline(pts, Color(0.95, 0.5, 0.55), s * 0.12)
			c.draw_circle(pts[9], s * 0.08, INK)
			c.draw_circle(pts[9], s * 0.065, Color(0.98, 0.58, 0.62))
			c.draw_circle(pts[9] + Vector2(s * 0.02, -s * 0.02), s * 0.015, INK)
		"float":
			var fp := p + Vector2(0, sin(t * 3.0 + p.x) * 3.0)
			c.draw_line(fp + Vector2(0, -s * 0.45), fp + Vector2(0, s * 0.35), INK, 3.0)
			c.draw_circle(fp, s * 0.22, INK)
			c.draw_circle(fp, s * 0.2, Color(0.97, 0.97, 0.95))
			var up := PackedVector2Array()
			for k in 13:
				var a := PI + PI * k / 12.0
				up.append(fp + Vector2(cos(a), sin(a)) * s * 0.2)
			c.draw_colored_polygon(up, Color(0.9, 0.12, 0.1))
		"boot":
			var bt := PackedVector2Array([p + Vector2(-0.18, -0.38) * s, p + Vector2(0.08, -0.38) * s, p + Vector2(0.08, 0.1) * s,
				p + Vector2(0.36, 0.18) * s, p + Vector2(0.36, 0.38) * s, p + Vector2(-0.18, 0.38) * s])
			c.draw_colored_polygon(bt, Color(0.36, 0.26, 0.16))
			c.draw_polyline(bt + PackedVector2Array([bt[0]]), INK, 2.5)
			c.draw_line(p + Vector2(-0.18, 0.32) * s, p + Vector2(0.36, 0.32) * s, INK, 3.0)
			c.draw_circle(p + Vector2(0.3, 0.45) * s + Vector2(0, fmod(t * 20.0, 10.0)), 2.5, Color(0.6, 0.85, 1.0, 0.8))
		"perch":
			_fish(c, p + Vector2(0, -s * 0.08), s * 0.62, s * 0.38, Color(0.6, 0.68, 0.3), Color(0.92, 0.88, 0.6), "perch")
		"pike":
			_fish(c, p + Vector2(0, -s * 0.08), s * 0.86, s * 0.26, Color(0.33, 0.5, 0.24), Color(0.78, 0.82, 0.55), "pike")
		"catfish":
			_fish(c, p + Vector2(0, -s * 0.08), s * 0.8, s * 0.42, Color(0.3, 0.28, 0.27), Color(0.6, 0.58, 0.52), "catfish")
		"fisher":
			c.draw_line(p + Vector2(0.1, 0.12) * s, p + Vector2(0.42, -0.42) * s, INK, 4.5)
			c.draw_line(p + Vector2(0.1, 0.12) * s, p + Vector2(0.42, -0.42) * s, Color(0.6, 0.4, 0.18), 2.5)
			var coat := PackedVector2Array([p + Vector2(-0.28, 0.45) * s, p + Vector2(-0.2, 0.04) * s, p + Vector2(0.2, 0.04) * s, p + Vector2(0.28, 0.45) * s])
			c.draw_colored_polygon(coat, Color(1.0, 0.78, 0.1))
			c.draw_polyline(coat + PackedVector2Array([coat[0]]), INK, 2.5)
			c.draw_circle(p + Vector2(0.12, 0.14) * s, s * 0.06, Color(0.96, 0.78, 0.6))
			c.draw_circle(p + Vector2(0, -0.08) * s, s * 0.17, INK)
			c.draw_circle(p + Vector2(0, -0.08) * s, s * 0.15, Color(0.96, 0.78, 0.6))
			c.draw_circle(p + Vector2(0, -0.0) * s, s * 0.09, Color(0.62, 0.45, 0.3))   # борода
			for ex in [-0.05, 0.05]:
				c.draw_circle(p + Vector2(ex, -0.11) * s, s * 0.018, INK)
			var hat := PackedVector2Array([p + Vector2(-0.32, -0.13) * s, p + Vector2(-0.14, -0.36) * s, p + Vector2(0.14, -0.36) * s, p + Vector2(0.32, -0.13) * s])
			c.draw_colored_polygon(hat, Color(1.0, 0.78, 0.1))
			c.draw_polyline(hat + PackedVector2Array([hat[0]]), INK, 2.5)
		"ripple":
			for k in 2:
				var rr := s * (0.15 + 0.13 * k + 0.04 * sin(t * 3.0 + k))
				var el := PackedVector2Array()
				for j in 21:
					var a := TAU * j / 20.0
					el.append(p + Vector2(cos(a) * rr, sin(a) * rr * 0.4))
				c.draw_polyline(el, Color(0.7, 0.9, 1.0, 0.35), 1.5)
	if v > 0:
		var tr := Rect2(p + Vector2(-s * 0.32, s * 0.24), Vector2(s * 0.64, s * 0.22))
		c.draw_rect(tr, INK)
		c.draw_rect(tr.grow(-2.0), Color(1.0, 0.82, 0.3))
		c.draw_string(ThemeDB.fallback_font, Vector2(tr.position.x, tr.end.y - 5.0), str(v * bet), HORIZONTAL_ALIGNMENT_CENTER, tr.size.x, 18, INK)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
