extends StaticBody3D
## Автомат «ФОРТУНА» в подвале деревни (промпт 15.11 23:01): три барабана, одна линия, крутка — 5 монет.
## Обычные награды — три одинаковых символа (вишня 15 … семёрка 100), две вишни — 5 монет.
## «Бонуски» (звезда B): одна — мелкий подарок (патроны, фильтр, бинт, тушёнка), две — 3 бесплатные крутки,
## три — бонус-игра: 8 бесплатных круток с удвоенным выигрышем.
## Джекпоты (корона J): две — мини-джекпот 25 монет, три — ДЖЕКПОТ: весь банк (уменьшается на 1 с каждой платной
## крутки, начинается со 1060; в сейве — village.gd).
## Автомат у каждого игрока свой (монеты свои), в сети не синхронизируется.
## Живее (промпт 16.11 00:17): бегущие лампы по рамке и вывеске, рычаг дёргается, барабаны размыты в крутке
## и пружинят при остановке; две короны/звезды/семёрки на первых барабанах — третий крутится дольше («интрига»)
## с нарастающим тоном; выигрыш — подсветка символов, табло со счётчиком монет, фонтан монет из лотка;
## бонус-игра — фиолетовый экран и маячок; джекпот — сирена, стробоскоп, ливень монет. Звуки — свои (синтез).

const Sym := preload("res://scripts/slot/slot_symbols.gd")
const Items := preload("res://scripts/items.gd")
const Sfx := preload("res://scripts/core/sfx.gd")
const COST := 15
const SYMS := ["cherry", "lemon", "plum", "grape", "diamond", "seven", "bonus", "jack"]
const WEIGHT := {"cherry": 1.0, "lemon": 20.0, "plum": 16.0, "grape": 12.0, "diamond": 9.0, "seven": 8.0, "bonus": 8.0, "jack": 16.0}
const PAY := {"cherry": 15, "lemon": 25, "plum": 35, "grape": 50, "diamond": 80, "seven": 100}
## ставка (промпт 18.11 01:03): крутка стоит COST×ставка, денежные выигрыши (линии, мини-джекпот, джекпот) ×ставка.
## Переключается кнопкой «СТАВКА» слева на полке автомата; пока идут бесплатные крутки — не меняется.
const BETS := [1, 2, 5, 10]
const GIFTS := [["filter", 1], ["medkit", 1], ["fuel", 1], ["ammo", 18], ["coin", 30]]
const JACK_BASE := 100
## промпт 16.11 03:16: бонус-игра ×1.5 (было ×2); после первых 777 они перебрасываются с шансом SEVENS_REROLL
const BONUS_MULT := 1.5
const SEVENS_REROLL := 0.85
const SlotSounds := preload("res://scripts/slot/slot_sounds.gd")   # общие звуки рычага/монет
## крутка ×0.8 (промпт 16.11 04:18): было 1.1 / 0.38 / 1.5, скорость ленты 9 → 11.25, петля звука ×1.25
const SPIN_T := 0.88
const STEP_T := 0.3
const TEASE_T := 1.2          # «интрига»: третий барабан крутится дольше
const W := 480
const H := 220

var game
var jackpot := JACK_BASE
var bet := 1                # ставка из BETS (сейв — village.gd)
var bet_l: Label3D
var free_spins := 0
var bonus_game := false      # идёт бонус-игра (выигрыш ×BONUS_MULT)
var sevens_hit := false      # 777 уже выпадали (сейв — village.gd)
var busy := false
var t := 0.0
var result := ["cherry", "lemon", "plum"]
var shown := ["seven", "seven", "seven"]
var reel_off := [0.0, 0.0, 0.0]
var reel_done := [true, true, true]
var bounce := [9.0, 9.0, 9.0]          # время с остановки барабана (пружинка)
var tease := false
var win_mask := [false, false, false]
var msg := "КРУТКА 15 МОНЕТ"
var msg_col := Color(0.95, 0.85, 0.5)
var blink := 0.0
# показ выигрыша
var tier := 0                # 0 — мимо, 1 — мелкий, 2 — крупный/бонус, 3 — джекпот
var win_amount := 0
var win_t := 99.0
var count_shown := 0
var banner := ""
var coin_tick := 0.0

var screen: Control
var vp: SubViewport
var jack_l: Label3D
var sign_l: Label3D
var lamp: OmniLight3D
var snd: AudioStreamPlayer3D          # крутка (петля)
var fx: Array[AudioStreamPlayer3D] = []
var lever: Node3D
var lever_t := 9.0
var bulbs: Array[StandardMaterial3D] = []
var top_bulbs: Array[StandardMaterial3D] = []
var beacon: Node3D
var beacon_l: SpotLight3D
var beacon_mat: StandardMaterial3D
var sounds := {}


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
	_box(Vector3(0.6, 0.03, 0.18), Vector3(0, 0.33, 0.32), gold)  # козырёк лотка
	# рычаг сбоку — на шарнире, при крутке дёргается вниз
	_box(Vector3(0.08, 0.12, 0.12), Vector3(0.5, 1.05, 0.05), gold)
	lever = Node3D.new()
	lever.position = Vector3(0.54, 1.05, 0.05)
	add_child(lever)
	var stick := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.035, 0.48, 0.035)
	stick.mesh = bm
	stick.material_override = _mat(Color(0.75, 0.75, 0.72), 0.9, 0.3)
	stick.position = Vector3(0, 0.24, 0)
	lever.add_child(stick)
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.12
	ball.mesh = sm
	ball.material_override = _glow(Color(0.9, 0.1, 0.1), 1.2)
	ball.position = Vector3(0, 0.5, 0)
	lever.add_child(ball)
	# экран: SubViewport с барабанами
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
	q.size = Vector2(0.76, 0.34)
	var scr := MeshInstance3D.new()
	scr.mesh = q
	var sm2 := StandardMaterial3D.new()
	sm2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm2.albedo_texture = vp.get_texture()
	scr.material_override = sm2
	scr.position = Vector3(0, 1.42, 0.212)
	add_child(scr)
	# лампы: по рамке экрана и над вывеской — бегут огоньки
	var bs := SphereMesh.new()
	bs.radius = 0.017
	bs.height = 0.034
	bs.radial_segments = 8
	bs.rings = 4
	var pts: Array = []
	for k in 9:
		pts.append(Vector3(-0.4 + k * 0.1, 1.615, 0.215))
	for k in 3:
		pts.append(Vector3(0.415, 1.52 - k * 0.1, 0.215))
	for k in 9:
		pts.append(Vector3(0.4 - k * 0.1, 1.225, 0.215))
	for k in 3:
		pts.append(Vector3(-0.415, 1.32 + k * 0.1, 0.215))
	for p in pts:
		bulbs.append(_bulb(bs, p))
	for k in 11:
		top_bulbs.append(_bulb(bs, Vector3(-0.45 + k * 0.09, 2.15, 0.23)))
	# вывеска и банк
	sign_l = Label3D.new()
	sign_l.text = "БИШBARMAK"
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
	# маячок сверху: крутится в бонус-игре и на джекпоте
	beacon = Node3D.new()
	beacon.position = Vector3(0, 2.2, -0.05)
	add_child(beacon)
	beacon_mat = _glow(Color(0.9, 0.15, 0.1), 0.2)
	var cm := CylinderMesh.new()
	cm.top_radius = 0.06
	cm.bottom_radius = 0.08
	cm.height = 0.12
	var bmi := MeshInstance3D.new()
	bmi.mesh = cm
	bmi.material_override = beacon_mat
	bmi.position.y = 0.06
	beacon.add_child(bmi)
	beacon_l = SpotLight3D.new()
	beacon_l.position = Vector3(0, 0.07, 0)
	beacon_l.light_color = Color(1.0, 0.2, 0.1)
	beacon_l.light_energy = 0.0
	beacon_l.spot_range = 8.0
	beacon_l.spot_angle = 22.0
	beacon.add_child(beacon_l)
	lamp = OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.7, 0.35)
	lamp.light_energy = 0.9
	lamp.omni_range = 4.0
	lamp.position = Vector3(0, 1.6, 0.7)
	add_child(lamp)
	snd = AudioStreamPlayer3D.new()
	snd.unit_size = 4.0
	snd.max_distance = 30.0
	snd.position = Vector3(0, 1.0, 0.3)
	add_child(snd)
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
	bx.size = Vector3(1.0, 2.1, 0.66)
	cs.shape = bx
	cs.position = Vector3(0, 1.05, 0)
	add_child(cs)
	for i in 3:
		shown[i] = _roll()
	_build_bet_button(gold)


## Кнопка ставки — отдельное тело перед корпусом (луч взгляда попадает в неё раньше автомата).
class BetButton extends StaticBody3D:
	var slot
	func get_prompt(_g) -> String:
		return slot.bet_prompt()
	func interact(_g) -> void:
		slot.cycle_bet()


func _build_bet_button(gold: Material) -> void:
	var b := BetButton.new()
	b.slot = self
	b.position = Vector3(-0.3, 1.0, 0.36)
	add_child(b)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.24, 0.1, 0.08)
	mi.mesh = bm
	mi.material_override = _glow(Color(0.9, 0.2, 0.15), 1.2)
	b.add_child(mi)
	var rim := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(0.27, 0.13, 0.06)
	rim.mesh = rm
	rim.material_override = gold
	rim.position = Vector3(0, 0, -0.015)
	b.add_child(rim)
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(0.28, 0.16, 0.12)
	cs.shape = bx
	b.add_child(cs)
	bet_l = Label3D.new()
	bet_l.font_size = 40
	bet_l.pixel_size = 0.0022
	bet_l.outline_size = 6
	bet_l.modulate = Color(1.0, 0.95, 0.7)
	bet_l.position = Vector3(0, 0, 0.045)
	b.add_child(bet_l)
	_update_bet_label()


func _update_bet_label() -> void:
	if bet_l:
		bet_l.text = "СТАВКА ×%d" % bet


func bet_prompt() -> String:
	if busy:
		return ""
	if free_spins > 0:
		return "Ставка ×%d — не меняется, пока идут бесплатные крутки" % bet
	var nx: int = BETS[(BETS.find(bet) + 1) % BETS.size()]
	return "[E] Ставка ×%d (крутка %d монет) → ×%d" % [bet, COST * bet, nx]


func cycle_bet() -> void:
	if busy or free_spins > 0:
		return
	bet = BETS[(BETS.find(bet) + 1) % BETS.size()]
	_update_bet_label()
	_sfx("win", -14.0, 0.8 + 0.1 * BETS.find(bet))
	msg = "СТАВКА ×%d — КРУТКА %d МОНЕТ" % [bet, COST * bet]
	msg_col = Color(0.95, 0.85, 0.5)


## Ставка из сейва (неизвестная — ×1).
func set_bet(b: int) -> void:
	bet = b if BETS.has(b) else 1
	_update_bet_label()


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


func _bulb(mesh: Mesh, p: Vector3) -> StandardMaterial3D:
	var m := _glow(Color(1.0, 0.75, 0.3), 0.3)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = p
	add_child(mi)
	return m


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


# ---------- звуки (синтез) ----------

## Нота: [частота, начало, длина]; мягкий «квадрат» (основной тон + нечётные гармоники).
static func _notes(notes: Array, total: float, bright := 0.35, decay := 6.0) -> PackedFloat32Array:
	var n := int(total * Sfx.RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for e in notes:
		var f: float = e[0]
		var s0 := int(float(e[1]) * Sfx.RATE)
		var ln := int(float(e[2]) * Sfx.RATE)
		for i in range(s0, mini(s0 + ln, n)):
			var tt := float(i - s0) / Sfx.RATE
			var env := minf(tt / 0.006, 1.0) * exp(-tt * decay) * minf(1.0, float(s0 + ln - i) / (Sfx.RATE * 0.02))
			var ph := TAU * f * tt
			buf[i] += (sin(ph) + bright * sin(ph * 3.0) / 3.0 + bright * 0.6 * sin(ph * 5.0) / 5.0) * env
	return buf


func _make_sounds() -> void:
	var r := Sfx.RATE
	# крутка: трещотка барабанов (щелчки 16 раз в секунду) + гул мотора; петля
	var n := int(1.0 * r)
	var spin := PackedFloat32Array()
	spin.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	for i in n:
		var tt := float(i) / r
		var seg := fmod(tt * 16.0, 1.0) / 16.0
		spin[i] = rng.randf_range(-1, 1) * exp(-seg * 600.0) * 0.8 + sin(TAU * 95.0 * tt) * 0.12 + sin(TAU * 190.0 * tt) * 0.05
	var st := Sfx._wav(spin, 0.55)
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_end = n - int(r * 0.03)
	sounds["spin"] = st
	# остановка барабана: глухой «клац»
	var m := int(0.22 * r)
	var stop := PackedFloat32Array()
	stop.resize(m)
	for i in m:
		var tt := float(i) / r
		stop[i] = sin(TAU * 130.0 * tt) * exp(-tt * 28.0) + rng.randf_range(-1, 1) * exp(-tt * 260.0) * 0.7
	sounds["stop"] = Sfx._wav(stop, 0.8)
	# мелкий выигрыш: до-ми-соль
	sounds["win"] = Sfx._wav(_notes([[523.0, 0.0, 0.2], [659.0, 0.09, 0.2], [784.0, 0.18, 0.35]], 0.6), 0.7)
	# крупный выигрыш: восходящий проигрыш и аккорд
	var big := []
	var up_notes := [523.0, 659.0, 784.0, 1047.0, 784.0, 1047.0, 1319.0]
	for k in up_notes.size():
		big.append([up_notes[k], k * 0.08, 0.2])
	for f in [523.0, 659.0, 784.0, 1047.0]:
		big.append([f, 0.6, 0.9])
	sounds["big"] = Sfx._wav(_notes(big, 1.6, 0.4, 3.0), 0.75)
	# бонус: волшебная лесенка вверх с переливами
	var bon := []
	for k in 12:
		bon.append([440.0 * pow(2.0, k / 7.0), k * 0.05, 0.25])
	for k in 6:
		bon.append([1760.0 + 220.0 * (k % 3), 0.65 + k * 0.07, 0.15])
	sounds["bonus"] = Sfx._wav(_notes(bon, 1.3, 0.2, 5.0), 0.7)
	# джекпот: сирена (два тона) + колокольчики
	var jn := int(2.4 * r)
	var jb := PackedFloat32Array()
	jb.resize(jn)
	var ph := 0.0
	for i in jn:
		var tt := float(i) / r
		var f := 700.0 if fmod(tt, 0.4) < 0.2 else 940.0
		ph += TAU * f / r
		jb[i] = (sin(ph) + 0.3 * sin(ph * 3.0)) * 0.45 * minf(1.0, (2.4 - tt) * 2.0)
	var bells := _notes([[1568.0, 0.0, 0.5], [2093.0, 0.25, 0.5], [1568.0, 0.5, 0.5], [2093.0, 0.75, 0.5],
		[2637.0, 1.0, 0.8], [2093.0, 1.4, 0.8], [3136.0, 1.7, 0.7]], 2.4, 0.1, 4.0)
	for i in jn:
		jb[i] += bells[i] * 0.7
	sounds["jack"] = Sfx._wav(jb, 0.8)
	# интрига: тон ползёт вверх с дрожью
	var tn := int(TEASE_T * r)
	var tb := PackedFloat32Array()
	tb.resize(tn)
	ph = 0.0
	for i in tn:
		var tt := float(i) / r
		var f := lerpf(260.0, 880.0, tt / TEASE_T)
		ph += TAU * f / r
		tb[i] = sin(ph) * (0.6 + 0.4 * sin(TAU * 11.0 * tt)) * minf(tt * 4.0, 1.0)
	sounds["tease"] = Sfx._wav(tb, 0.5)
	# «мимо»: два понижающихся тона
	sounds["miss"] = Sfx._wav(_notes([[392.0, 0.0, 0.16], [311.0, 0.13, 0.3]], 0.45, 0.5, 7.0), 0.45)


func _sfx(id: String, db := 0.0, pitch := 1.0) -> void:
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

func get_prompt(g) -> String:
	if busy:
		return ""
	if free_spins > 0:
		return "[E] ФОРТУНА — бесплатная крутка (%d)" % free_spins
	var cost := COST * bet
	return "[E] Крутить ФОРТУНУ ×%d — %d монет" % [bet, cost] if g.inv.coins >= cost else "ФОРТУНА ×%d: нужно %d монет" % [bet, cost]


func interact(g) -> void:
	if busy:
		return
	if free_spins > 0:
		free_spins -= 1
	elif g.inv.coins >= COST * bet:
		g.inv.remove("coin", COST * bet)
		jackpot = maxi(0, jackpot - 1)
		bonus_game = false
	else:
		g.hud.toast("Не хватает монет")
		return
	busy = true
	t = 0.0
	win_t = 99.0
	tier = 0
	banner = ""
	for i in 3:
		result[i] = _roll()
	if jackpot <= 0:
		result = ["jack", "jack", "jack"]
	if sevens_hit and result.count("seven") == 3 and randf() < SEVENS_REROLL:
		result[2] = _roll()
		while result[2] == "seven":
			result[2] = _roll()
	for i in 3:
		reel_done[i] = false
		win_mask[i] = false
	# две короны / звезды / семёрки на первых барабанах — третий крутится дольше
	tease = result[0] == result[1] and result[0] in ["jack", "bonus", "seven"]
	msg = "БОНУС-ИГРА: ×1.5  (осталось %d)" % free_spins if bonus_game else "..."
	msg_col = Color(0.95, 0.85, 0.5)
	lever_t = 0.0
	SlotSounds.play3d(self, SlotSounds.lever(), lever.global_position, -7.0, randf_range(1.0, 1.08))
	snd.stream = sounds["spin"]
	snd.volume_db = -10.0
	snd.pitch_scale = 1.44 if bonus_game else 1.25
	snd.play()


func _stop_at(i: int) -> float:
	return SPIN_T + i * STEP_T + (TEASE_T if tease and i == 2 else 0.0)


func _process(delta: float) -> void:
	jack_l.text = "ДЖЕКПОТ %d" % jackpot
	blink += delta
	win_t += delta
	bounce[0] += delta
	bounce[1] += delta
	bounce[2] += delta
	# рычаг: рывок вниз и пружиной назад
	lever_t += delta
	var lk := clampf(lever_t / 0.5, 0.0, 1.0)
	lever.rotation.x = sin(PI * lk) * 1.1 * (1.0 - lk * 0.3) if lever_t < 0.5 else 0.0
	if busy:
		t += delta
		var teasing: bool = tease and reel_done[1] and not reel_done[2]
		for i in 3:
			if reel_done[i]:
				continue
			var spd := 11.25 * (0.6 if teasing and i == 2 and t > _stop_at(2) - 0.4 else 1.0)
			reel_off[i] = fmod(reel_off[i] + delta * spd, 1.0)
			if fmod(t, 0.056) < delta:
				shown[i] = SYMS[randi() % SYMS.size()]
			if t > _stop_at(i):
				reel_done[i] = true
				reel_off[i] = 0.0
				bounce[i] = 0.0
				shown[i] = result[i]
				_sfx("stop", -4.0, 0.9 + i * 0.08)
				if i == 1 and tease:
					_sfx("tease", -6.0)
					msg = "?!  ?!  ?!"
					msg_col = Color(1.0, 0.5, 0.3)
		if reel_done[2]:
			busy = false
			snd.stop()
			_payout()
			if free_spins <= 0 and game and game.inv.coins < COST:
				preload("res://scripts/slot/slot_machine.gd").pity(game)
	_lights(delta)
	# счётчик выигрыша бежит, звенят монеты
	if win_amount > 0 and count_shown < win_amount:
		var dur := clampf(0.5 + win_amount / 80.0, 0.6, 3.0)
		count_shown = mini(win_amount, int(ceil(win_amount * clampf(win_t / dur, 0.0, 1.0))))
		coin_tick -= delta
		if coin_tick <= 0.0 and game:
			coin_tick = 0.07 if tier < 3 else 0.045
			SlotSounds.play3d(self, SlotSounds.clink(), global_position + Vector3(0, 0.35, 0.36), -12.0, randf_range(0.92, 1.12))
	screen.queue_redraw()


## Лампы, свет и маячок: в покое огоньки бегут медленно, в крутке — быстро, на выигрыше мигают все сразу.
func _lights(delta: float) -> void:
	var showing := win_t < (1.6 if tier == 1 else 3.2 if tier == 2 else 5.0) and tier > 0
	var base := Color(1.0, 0.75, 0.3)
	if bonus_game or free_spins > 0:
		base = Color(0.75, 0.4, 1.0)
	var speed := 4.0 if not busy else 16.0
	var head := int(blink * speed)
	for k in bulbs.size():
		var on := (k + head) % 4 == 0
		var col := base
		if showing:
			on = fmod(blink * (6.0 if tier < 3 else 12.0), 1.0) < 0.5
			if tier == 3:
				col = Color.from_hsv(fmod(blink * 1.5 + k / 24.0, 1.0), 0.8, 1.0)
		bulbs[k].emission = col
		bulbs[k].albedo_color = col if on else col.darkened(0.6)
		bulbs[k].emission_energy_multiplier = 2.4 if on else 0.15
	for k in top_bulbs.size():
		var on := (k + (head >> 1)) % 2 == 0 if not showing else fmod(blink * 8.0 + k * 0.5, 1.0) < 0.5
		top_bulbs[k].emission = base
		top_bulbs[k].emission_energy_multiplier = 2.0 if on else 0.2
	var pulse := 0.9 + (0.6 * sin(blink * 9.0) if busy else 0.1 * sin(blink * 2.0))
	if showing:
		pulse = 1.0 + (1.6 if fmod(blink * (5.0 if tier < 3 else 14.0), 1.0) < 0.5 else 0.2) * (0.6 if tier == 1 else 1.0)
	lamp.light_energy = pulse
	lamp.light_color = base if not (showing and tier == 3) else Color.from_hsv(fmod(blink, 1.0), 0.6, 1.0)
	sign_l.modulate = Color(1.0, 0.8, 0.3) if not showing else Color(1.0, 0.8, 0.3).lerp(Color(1, 1, 1), 0.5 + 0.5 * sin(blink * 20.0))
	jack_l.modulate = Color(1.0, 0.35, 0.25) if not (showing and tier == 3) else Color.from_hsv(fmod(blink * 2.0, 1.0), 0.7, 1.0)
	var beacon_on := bonus_game or free_spins > 0 or (showing and tier >= 2)
	beacon.rotation.y += delta * (9.0 if beacon_on else 0.0)
	beacon_l.light_energy = lerpf(beacon_l.light_energy, 4.0 if beacon_on else 0.0, 1.0 - exp(-6.0 * delta))
	beacon_l.light_color = Color(0.7, 0.3, 1.0) if bonus_game or free_spins > 0 else Color(1.0, 0.2, 0.1)
	beacon_l.rotation.x = -0.5
	beacon_mat.emission_energy_multiplier = 2.5 if beacon_on else 0.2


func _payout() -> void:
	var r: Array = result
	var mult := BONUS_MULT if bonus_game else 1.0
	var win := 0
	var lines: Array = []
	var jacks := r.count("jack")
	var bonus := r.count("bonus")
	tier = 0
	banner = ""
	for i in 3:
		win_mask[i] = false
	if jacks == 3:
		win += jackpot
		lines.append("ДЖЕКПОТ!")
		jackpot = JACK_BASE
		tier = 3
		banner = "ДЖЕКПОТ!!!"
		if game:
			game.hud.toast("ДЖЕКПОТ НА ФОРТУНЕ: +%d" % roundi(win * mult * bet), Color(1.0, 0.8, 0.3))
	elif jacks == 2:
		win += 25
		lines.append("МИНИ-ДЖЕКПОТ")
		tier = 2
		banner = "МИНИ-ДЖЕКПОТ"
	if jacks >= 2:
		for i in 3:
			win_mask[i] = win_mask[i] or r[i] == "jack"
	if r[0] == r[1] and r[1] == r[2] and PAY.has(r[0]):
		win += int(PAY[r[0]])
		win_mask = [true, true, true]
		if r[0] == "seven":
			sevens_hit = true
		if r[0] in ["seven", "diamond"] and tier < 2:
			tier = 2
			banner = "777" if r[0] == "seven" else "БРИЛЛИАНТЫ!"
	elif r.count("cherry") == 2:
		win += 5
		for i in 3:
			win_mask[i] = win_mask[i] or r[i] == "cherry"
	if bonus == 3:
		free_spins += 8
		bonus_game = true
		lines.append("БОНУС-ИГРА: 8 круток ×1.5")
		tier = maxi(tier, 2)
		if banner == "":
			banner = "БОНУС-ИГРА!"
	elif bonus == 2:
		free_spins += 3
		lines.append("БОНУС: +3 крутки")
		tier = maxi(tier, 2)
		if banner == "":
			banner = "+3 КРУТКИ"
	elif bonus == 1:
		var gift: Array = GIFTS[randi() % GIFTS.size()]
		if game:
			var left: int = game.inv.add(gift[0], gift[1])
			if left > 0:
				game.spawn_loot(gift[0], left, global_transform * Vector3(0, 0.4, 0.5), global_transform.basis * Vector3(0, 1, 1.5), 0.3)
			game.hud.toast("ФОРТУНА: бонуска — %s" % Items.item_name(gift[0]), Color(0.75, 0.9, 1.0))
		lines.append("бонуска")
		tier = maxi(tier, 1)
	if bonus >= 1:
		for i in 3:
			win_mask[i] = win_mask[i] or r[i] == "bonus"
	win = roundi(win * mult * bet)   # ставка умножает денежный выигрыш
	if free_spins == 0:
		bonus_game = false
	if win > 0 and tier == 0:
		tier = 2 if win >= 40 * bet else 1
		if tier == 2 and banner == "":
			banner = "КРУПНЫЙ ВЫИГРЫШ"
	win_amount = win
	count_shown = 0
	win_t = 0.0
	coin_tick = 0.0
	if win > 0 and game:
		game.inv.add("coin", win)
		lines.push_front("+%d МОНЕТ" % win)
		_coin_fountain(10 if tier == 1 else 28 if tier == 2 else 90)
	# звук по силе выигрыша
	if tier == 3:
		_sfx("jack", 0.0)
	elif bonus >= 2:
		_sfx("bonus", -2.0)
	elif tier == 2:
		_sfx("big", -2.0)
	elif tier == 1:
		_sfx("win", -4.0)
	else:
		_sfx("miss", -8.0)
	if lines.is_empty():
		msg = "МИМО"
		msg_col = Color(0.7, 0.65, 0.6)
	else:
		msg = "  ·  ".join(lines)
		msg_col = Color(1.0, 0.85, 0.35)
	if free_spins > 0:
		msg += "   (бесплатно: %d)" % free_spins


## Монеты фонтаном из лотка (вид; сами монеты уже в сумке).
func _coin_fountain(amount: int) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.25 if amount > 40 else 0.6
	p.amount = amount
	p.lifetime = 1.3 if amount < 60 else 2.2
	p.position = Vector3(0, 0.32, 0.36)
	p.direction = Vector3(0, 1.0, 0.8)
	p.spread = 28.0
	p.initial_velocity_min = 1.8
	p.initial_velocity_max = 3.4 if amount < 60 else 4.5
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
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.95, 0.75, 0.25)
	m.metallic = 0.9
	m.roughness = 0.3
	m.emission_enabled = true
	m.emission = Color(1.0, 0.7, 0.2)
	m.emission_energy_multiplier = 0.6
	cm.material = m
	p.mesh = cm
	add_child(p)
	p.emitting = true
	get_tree().create_timer(p.lifetime + 1.0).timeout.connect(p.queue_free)


# ---------- экран ----------

func _draw_screen() -> void:
	var c := screen
	var bonus_mode := bonus_game or free_spins > 0
	var bg := Color(0.03, 0.02, 0.02) if not bonus_mode else Color(0.1, 0.03, 0.16)
	c.draw_rect(Rect2(0, 0, W, H), bg)
	var font := ThemeDB.fallback_font
	if bonus_mode:
		# звёздочки по фону бонус-игры
		for k in 14:
			var sx := fmod(k * 83.0 + blink * 20.0, float(W))
			var sy := fmod(k * 47.0, 200.0)
			c.draw_circle(Vector2(sx, sy), 1.5 + sin(blink * 5.0 + k), Color(0.9, 0.7, 1.0, 0.5))
	var showing := tier > 0 and win_t < 6.0
	for i in 3:
		var x := 18.0 + i * 152.0
		var box := Rect2(x, 14, 140, 150)
		var face := Color(0.92, 0.88, 0.78)
		var teasing: bool = tease and i == 2 and not reel_done[2] and reel_done[1]
		if teasing:
			face = face.lerp(Color(1.0, 0.6, 0.4), 0.3 + 0.3 * sin(blink * 18.0))
		c.draw_rect(box, face)
		if not reel_done[i]:
			# крутится: три символа подряд едут вниз, поверх — полосы «размытия»
			var off: float = reel_off[i] * 150.0
			var k0 := SYMS.find(shown[i])
			for j in range(-1, 2):
				var sid: String = SYMS[(k0 + j * 3 + SYMS.size() * 3) % SYMS.size()]
				_sym(sid, Rect2(x + 10, 24 + off - j * 150.0, 120, 120), 1.0, Color(1, 1, 1, 0.75))
			for s in 6:
				var yy := fmod(off * 1.7 + s * 27.0, 150.0)
				c.draw_rect(Rect2(x, 14 + yy, 140, 6), Color(1, 1, 1, 0.22))
		else:
			# остановился: пружинит; выигрышный — пульсирует и светится
			var b: float = bounce[i]
			var dy := sin(b * 22.0) * exp(-b * 9.0) * 16.0
			var sc := 1.0
			if showing and win_mask[i]:
				sc = 1.0 + 0.09 * absf(sin(win_t * 7.0))
				var gl := Color(1.0, 0.85, 0.3, 0.35 + 0.25 * sin(win_t * 10.0))
				c.draw_rect(box.grow(-4), gl)
			_sym(shown[i], Rect2(x + 10, 24 + dy, 120, 120), sc, Color(1, 1, 1, 1))
		c.draw_rect(Rect2(x, 0, 140, 14), bg)
		c.draw_rect(Rect2(x, 164, 140, 22), bg)
		var frame := Color(0.75, 0.55, 0.2)
		if showing and win_mask[i]:
			frame = Color(1.0, 0.95, 0.5) if fmod(win_t * 6.0, 1.0) < 0.5 else Color(1.0, 0.4, 0.1)
		elif teasing:
			frame = Color(1.0, 0.25, 0.1) if fmod(blink * 10.0, 1.0) < 0.5 else Color(1.0, 0.9, 0.4)
		c.draw_rect(box, frame, false, 4.0 if not (showing and win_mask[i]) else 6.0)
	var line_col := Color(0.9, 0.15, 0.1, 0.5)
	if showing:
		line_col = Color(1.0, 0.9, 0.3, 0.6 + 0.4 * sin(win_t * 12.0))
	c.draw_line(Vector2(10, 89), Vector2(W - 10, 89), line_col, 2.0 if not showing else 4.0)
	# крупный выигрыш: табло поверх барабанов, счётчик монет
	if showing and (tier >= 2 or win_amount > 0) and win_t < 4.5:
		var a := clampf(win_t * 4.0, 0.0, 1.0) * clampf((4.5 - win_t) * 2.0, 0.0, 1.0)
		var by := 60.0
		c.draw_rect(Rect2(0, by, W, 62), Color(0, 0, 0, 0.62 * a))
		if banner != "":
			var bc := Color(1.0, 0.85, 0.3, a)
			if tier == 3:
				bc = Color.from_hsv(fmod(win_t * 1.2, 1.0), 0.75, 1.0, a)
			var fs := 34 if tier < 3 else int(36 + 4 * sin(win_t * 9.0))
			c.draw_string_outline(font, Vector2(0, by + 34), banner, HORIZONTAL_ALIGNMENT_CENTER, W, fs, 6, Color(0.3, 0.05, 0.0, a))
			c.draw_string(font, Vector2(0, by + 34), banner, HORIZONTAL_ALIGNMENT_CENTER, W, fs, bc)
		if win_amount > 0:
			var tx := "+%d" % count_shown
			c.draw_string_outline(font, Vector2(0, by + 58 if banner != "" else by + 44), tx, HORIZONTAL_ALIGNMENT_CENTER, W, 24 if banner != "" else 36, 5, Color(0, 0, 0, a))
			c.draw_string(font, Vector2(0, by + 58 if banner != "" else by + 44), tx, HORIZONTAL_ALIGNMENT_CENTER, W, 24 if banner != "" else 36, Color(1.0, 0.95, 0.6, a))
	# джекпот — стробоскоп по всему экрану
	if showing and tier == 3 and win_t < 3.0 and fmod(win_t * 8.0, 1.0) < 0.3:
		c.draw_rect(Rect2(0, 0, W, H), Color(1.0, 1.0, 0.9, 0.25))
	var col := msg_col
	if not busy and msg_col.r > 0.99:
		col.a = 0.6 + 0.4 * sin(blink * 8.0)
	c.draw_string(font, Vector2(0, 208), msg, HORIZONTAL_ALIGNMENT_CENTER, W, 22, col)


func _sym(id: String, r: Rect2, sc := 1.0, tint := Color(1, 1, 1, 1)) -> void:
	var c := screen
	var ctr := r.get_center()
	c.draw_set_transform(ctr * (1.0 - sc), 0.0, Vector2(sc, sc))
	match id:
		"bonus":
			var pts := PackedVector2Array()
			for k in 10:
				var a := -PI / 2.0 + TAU * k / 10.0 + (sin(blink * 3.0) * 0.08)
				var rad := r.size.x * (0.45 if k % 2 == 0 else 0.2)
				pts.append(ctr + Vector2(cos(a), sin(a)) * rad)
			c.draw_colored_polygon(pts, Color(0.95, 0.72, 0.15) * tint)
			c.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.45, 0.25, 0.05) * tint, 4.0)
			c.draw_string(ThemeDB.fallback_font, ctr + Vector2(-60, 14), "B", HORIZONTAL_ALIGNMENT_CENTER, 120, 40, Color(0.35, 0.12, 0.02) * tint)
		"jack":
			var s := r.size.x
			var crown := PackedVector2Array([ctr + Vector2(-s * 0.4, s * 0.25), ctr + Vector2(-s * 0.42, -s * 0.2), ctr + Vector2(-s * 0.2, 0),
				ctr + Vector2(0, -s * 0.32), ctr + Vector2(s * 0.2, 0), ctr + Vector2(s * 0.42, -s * 0.2), ctr + Vector2(s * 0.4, s * 0.25)])
			c.draw_colored_polygon(crown, Color(0.85, 0.1, 0.12) * tint)
			c.draw_polyline(crown + PackedVector2Array([crown[0]]), Color(0.95, 0.75, 0.2) * tint, 5.0)
			# камешки на зубцах поблёскивают
			for k in [1, 3, 5]:
				c.draw_circle(crown[k], 5.0 + 1.5 * sin(blink * 6.0 + k), Color(1.0, 0.95, 0.6) * tint)
			c.draw_string(ThemeDB.fallback_font, ctr + Vector2(-60, s * 0.2), "J", HORIZONTAL_ALIGNMENT_CENTER, 120, 34, Color(1.0, 0.85, 0.3) * tint)
		_:
			Sym.draw(c, id, r)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
