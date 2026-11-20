extends StaticBody3D
## Автомат «CASHY BOX» в подвале деревни (был «ФОРТУНА», промпт 15.11 23:01; переделан — промпт 20.11 11:51):
## элитный корпус (чёрный лак, золото, изумруд, стопки монет), поле 3×3, 5 линий — три ряда и две диагонали.
## Символы: вишня, лимон (после вишни), слива, арбуз, алмаз, семёрка; три в линию — PAY×ставка за каждую линию.
## «Бонуски» (изумрудная монета B) считаются по всему полю: одна — ничего, две — 3 бесплатные крутки,
## три и больше — бонус-игра: 8 бесплатных круток с удвоенным выигрышем.
## Короны: три в линию — ДЖЕКПОТ (банк-счётчик уменьшается на 1 с каждой платной крутки, на нуле корона встаёт
## сама; в сейве — village.gd), три и больше по полю — мини-джекпот.
## Бонус-игру можно купить в красном магазине деревни (village_shop.gd): BONUS_BUY круток по текущей ставке.
## В сети автомат общий (промпт 18.11 02:13, slot/slot_net.gd): крутки, джекпот, бесплатные крутки,
## бонус-игра и ставка — одни для всех; монеты и бонуски-подарки достаются тому, кто крутил.
## Живее (промпт 16.11 00:17): бегущие лампы по рамке и вывеске, рычаг дёргается, барабаны размыты в крутке
## и пружинят при остановке; две короны/звезды/семёрки на первых барабанах — третий крутится дольше («интрига»)
## с нарастающим тоном; выигрыш — подсветка символов, табло со счётчиком монет, фонтан монет из лотка;
## бонус-игра — фиолетовый экран и маячок; джекпот — сирена, стробоскоп, ливень монет. Звуки — свои (синтез).

const Sym := preload("res://scripts/slot/slot_symbols.gd")
const Items := preload("res://scripts/items.gd")
const Sfx := preload("res://scripts/core/sfx.gd")
const COST := 20
const SYMS := ["cherry", "plum", "grape", "diamond", "seven", "bonus", "jack"]   # лимона нет (промпт 20.11 14:34)
## веса и выплаты под 3×3 и 5 линий (отдача ~100%, как была у ФОРТУНЫ)
const WEIGHT := {"cherry": 18.0, "plum": 14.0, "grape": 12.0, "diamond": 9.0, "seven": 6.0, "bonus": 6.0, "jack": 6.0}
const PAY := {"cherry": 30, "plum": 50, "grape": 80, "diamond": 200, "seven": 500}
## клетка поля = барабан*3 + ряд; линии — три ряда и две диагонали
const LINES := [[0, 3, 6], [1, 4, 7], [2, 5, 8], [0, 4, 8], [2, 4, 6]]
const FREE_2 := 2             # две бонуски — бесплатные крутки (вне бонус-игры)
const FREE_2_BONUS := 3       # две бонуски во время бонус-игры
const FREE_3 := 8             # три бонуски — бонус-игра
const BONUS_BUY := 20         # покупка бонус-игры: столько круток по ставке (промпт 20.11 11:53)
const MINI_JACK := 100
const JACK_WIN := 300
## ставка (промпт 18.11 01:03): крутка стоит COST×ставка, денежные выигрыши (линии, мини-джекпот, джекпот) ×ставка.
## Переключается кнопкой «СТАВКА» слева на полке автомата; пока идут бесплатные крутки — не меняется.
const BETS := [1, 2, 3, 5, 10]
const JACK_BASE := 100
## промпт 16.11 03:16: бонус-игра ×1.5 (было ×2); после первых 777 они перебрасываются с шансом SEVENS_REROLL
const BONUS_MULT := 2.0
const SEVENS_REROLL := 0.85
const SlotSounds := preload("res://scripts/slot/slot_sounds.gd")   # общие звуки рычага/монет
## крутка ×0.8 (промпт 16.11 04:18): было 1.1 / 0.38 / 1.5, скорость ленты 9 → 11.25, петля звука ×1.25
const SPIN_T := 0.88
const STEP_T := 0.3
const TEASE_T := 1.2          # «интрига»: третий барабан крутится дольше
const REEL_V := 11.25         # скорость ленты, клеток/с
const DEC_T := 0.45           # торможение барабана (плавно, с лёгким перекатом)
const DEC_T_TEASE := 1.4      # торможение третьего барабана в «интриге» — медленно доползает
const EASE_C1 := 1.3          # перекат при остановке (easeOutBack)
const W := 480
const H := 450
## экран 3×3: барабаны с X0, клетка CW×CH, сверху полоса названия и банка, снизу — табло
const X0 := 26.0
const CW := 136.0
const GAP := 10.0
const TOP := 44.0
const CH := 108.0
const INK := Color(0.09, 0.05, 0.04)

var game
var jackpot := JACK_BASE
var jackpots := {}
var bet := 1                # ставка из BETS (сейв — village.gd)
var bet_l: Label3D
var free_spins := 0
var bonus_game := false      # идёт бонус-игра (выигрыш ×BONUS_MULT)
var sevens_hit := false      # 777 уже выпадали (сейв — village.gd)
var busy := false
var spin_mine := true        # эту крутку дёрнул я (иначе — другой игрок по сети)
var net_queue: Array = []    # чужие крутки, пришедшие пока крутились барабаны
var t := 0.0
var result := ["cherry", "grape", "plum", "grape", "seven", "diamond", "plum", "cherry", "plum"]
var shown := ["seven", "seven", "seven", "seven", "seven", "seven", "seven", "seven", "seven"]
var strip := [0, 0, 0]                 # лента крутящегося барабана (индекс в SYMS)
var win_lines: Array = []              # выигравшие линии (индексы LINES)
var reel_p := [0.0, 0.0, 0.0]          # пройдено лентой, клеток (0 — старое поле, reel_end — новое)
var reel_end := [3, 3, 3]
var reel_v := [REEL_V, REEL_V, REEL_V]  # скорость до торможения
var reel_dec := [0.0, 0.0, 0.0]        # когда начинает тормозить
var reel_d := [DEC_T, DEC_T, DEC_T]    # сколько тормозит
var reel_vel := [0.0, 0.0, 0.0]        # текущая скорость (для размытия)
var reel_clunk := [false, false, false]
var fast := false                      # быстрые крутки ×3 (тумблер слева, slot/fast_switch.gd)
var spin_sp := 1.0
var reel_done := [true, true, true]
var tease := false
var win_mask := [false, false, false, false, false, false, false, false, false]
var msg := "CASHY BOX · 5 ЛИНИЙ · СПИН 20"
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

func _get_jackpot(b := -1) -> int:
	var key := bet if b < 0 else b
	return int(jackpots.get(key, JACK_BASE))


func _set_jackpot(val: int, b := -1) -> void:
	var key := bet if b < 0 else b
	jackpots[key] = val
	if key == bet:
		jackpot = val


func _ready() -> void:
	# элитный корпус (промпт 20.11 11:51): чёрный лак, полированное золото, изумрудные вставки
	var body := _mat(Color(0.035, 0.035, 0.04), 0.6, 0.22)
	var gold := _mat(Color(0.95, 0.74, 0.3), 1.0, 0.18)
	var emerald := _mat(Color(0.03, 0.3, 0.17), 0.5, 0.3)
	var dark := _mat(Color(0.02, 0.02, 0.02), 0.0, 0.9)
	_box(Vector3(1.04, 0.06, 0.7), Vector3(0, 0.03, 0), gold)                  # золотой цоколь
	_box(Vector3(0.95, 0.86, 0.62), Vector3(0, 0.49, 0), body)
	_box(Vector3(0.78, 0.5, 0.02), Vector3(0, 0.58, 0.312), emerald)           # изумрудная панель внизу
	_box(Vector3(0.82, 0.02, 0.03), Vector3(0, 0.84, 0.315), gold)
	_box(Vector3(0.82, 0.02, 0.03), Vector3(0, 0.32, 0.315), gold)
	_box(Vector3(0.9, 0.95, 0.5), Vector3(0, 1.37, -0.05), body)
	_box(Vector3(1.0, 0.06, 0.66), Vector3(0, 0.92, 0.0), gold)               # полка
	_box(Vector3(1.0, 0.36, 0.55), Vector3(0, 2.03, -0.05), body)             # вывеска
	_box(Vector3(0.94, 0.3, 0.02), Vector3(0, 2.03, 0.226), emerald)
	for y in [1.86, 2.2]:
		_box(Vector3(1.02, 0.025, 0.57), Vector3(0, y, -0.05), gold)
	for sx in [-0.47, 0.47]:
		_box(Vector3(0.05, 1.86, 0.07), Vector3(sx, 1.0, 0.29), gold)          # золотые колонны
		var knob := MeshInstance3D.new()
		var ks := SphereMesh.new()
		ks.radius = 0.045
		ks.height = 0.09
		knob.mesh = ks
		knob.material_override = gold
		knob.position = Vector3(sx, 1.95, 0.29)
		add_child(knob)
	# стопки золотых монет по углам вывески
	var coin_m := CylinderMesh.new()
	coin_m.top_radius = 0.055
	coin_m.bottom_radius = 0.055
	coin_m.height = 0.016
	coin_m.radial_segments = 16
	coin_m.rings = 1
	for st in [[-0.4, 6], [0.4, 4], [-0.3, 3], [0.31, 2]]:
		for k in int(st[1]):
			var cmi := MeshInstance3D.new()
			cmi.mesh = coin_m
			cmi.material_override = gold
			cmi.position = Vector3(float(st[0]) + randf_range(-0.006, 0.006), 2.222 + k * 0.017, 0.05)
			add_child(cmi)
	_box(Vector3(0.74, 0.7, 0.02), Vector3(0, 1.38, 0.2), dark)       # рамка экрана
	_box(Vector3(0.55, 0.12, 0.14), Vector3(0, 0.22, 0.3), dark)      # лоток
	_box(Vector3(0.6, 0.03, 0.18), Vector3(0, 0.3, 0.32), gold)       # козырёк лотка
	# крупный знак $ на изумрудной панели
	var dollar := Label3D.new()
	dollar.text = "$"
	dollar.font_size = 96
	dollar.pixel_size = 0.003
	dollar.modulate = Color(1.0, 0.82, 0.35)
	dollar.outline_size = 10
	dollar.outline_modulate = Color(0.02, 0.12, 0.06)
	dollar.position = Vector3(0, 0.6, 0.325)
	add_child(dollar)
	# рычаг сбоку — на шарнире, при крутке дёргается вниз
	_box(Vector3(0.08, 0.12, 0.12), Vector3(0.5, 1.05, 0.05), gold)
	lever = Node3D.new()
	lever.position = Vector3(0.54, 1.05, 0.05)
	add_child(lever)
	var stick := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.035, 0.48, 0.035)
	stick.mesh = bm
	stick.material_override = gold
	stick.position = Vector3(0, 0.24, 0)
	lever.add_child(stick)
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.12
	ball.mesh = sm
	ball.material_override = _glow(Color(0.1, 0.85, 0.4), 1.2)
	ball.position = Vector3(0, 0.5, 0)
	lever.add_child(ball)
	# экран: SubViewport с полем 3×3
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
	sm2.albedo_color = Color(0.8, 0.8, 0.8)   # приглушён — не слепит (промпт 20.11 14:19)
	scr.material_override = sm2
	scr.position = Vector3(0, 1.38, 0.212)
	add_child(scr)
	# лампы: по рамке экрана и над вывеской — бегут огоньки
	var bs := SphereMesh.new()
	bs.radius = 0.017
	bs.height = 0.034
	bs.radial_segments = 8
	bs.rings = 4
	var pts: Array = []
	for k in 9:
		pts.append(Vector3(-0.36 + k * 0.09, 1.715, 0.215))
	for k in 6:
		pts.append(Vector3(0.375, 1.62 - k * 0.096, 0.215))
	for k in 9:
		pts.append(Vector3(0.36 - k * 0.09, 1.045, 0.215))
	for k in 6:
		pts.append(Vector3(-0.375, 1.14 + k * 0.096, 0.215))
	for p in pts:
		bulbs.append(_bulb(bs, p))
	for k in 11:
		top_bulbs.append(_bulb(bs, Vector3(-0.45 + k * 0.09, 2.2, 0.245)))
	# вывеска и банк
	sign_l = Label3D.new()
	sign_l.text = "CASHY BOX"
	sign_l.font_size = 64
	sign_l.pixel_size = 0.0024
	sign_l.modulate = Color(1.0, 0.82, 0.35)
	sign_l.outline_size = 10
	sign_l.outline_modulate = Color(0.02, 0.1, 0.05)
	sign_l.position = Vector3(0, 2.08, 0.24)
	add_child(sign_l)
	jack_l = Label3D.new()
	jack_l.font_size = 32
	jack_l.pixel_size = 0.0022
	jack_l.modulate = Color(0.55, 1.0, 0.7)
	jack_l.outline_size = 6
	jack_l.position = Vector3(0, 1.94, 0.24)
	add_child(jack_l)
	# маячок сверху: крутится в бонус-игре и на джекпоте
	beacon = Node3D.new()
	beacon.position = Vector3(0, 2.215, -0.05)
	add_child(beacon)
	beacon_mat = _glow(Color(0.15, 0.9, 0.4), 0.2)
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
	beacon_l.light_color = Color(0.2, 1.0, 0.45)
	beacon_l.light_energy = 0.0
	beacon_l.spot_range = 8.0
	beacon_l.spot_angle = 22.0
	beacon.add_child(beacon_l)
	lamp = OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.78, 0.4)
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
	bx.size = Vector3(1.0, 2.3, 0.66)
	cs.shape = bx
	cs.position = Vector3(0, 1.15, 0)
	add_child(cs)
	for i in 9:
		shown[i] = _roll()
	_build_bet_button(gold)
	# тумблер быстрых круток на левой стенке (промпт 20.11 14:35)
	var sw := preload("res://scripts/slot/fast_switch.gd").new()
	sw.setup(self, 0.03)
	sw.position = Vector3(-0.475, 0.74, 0.05)
	add_child(sw)


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
	mi.material_override = _glow(Color(0.1, 0.7, 0.35), 1.2)
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
		bet_l.text = "×%d" % bet


func bet_prompt() -> String:
	if busy:
		return ""
	if free_spins > 0:
		return "Ставка ×%d — не меняется, пока идут бесплатные крутки" % bet
	return "[F] Ставка %d" % [COST * bet]


func cycle_bet() -> void:
	if busy or free_spins > 0:
		return
	bet = BETS[(BETS.find(bet) + 1) % BETS.size()]
	jackpot = _get_jackpot(bet)
	_update_bet_label()
	send("f_bet", [bet])
	_sfx("win", -14.0, 0.8 + 0.1 * BETS.find(bet))
	msg = "СТАВКА ×%d — КРУТКА %d МОНЕТ" % [bet, COST * bet]
	msg_col = Color(0.95, 0.85, 0.5)


## Ставка из сейва (неизвестная — ×1).
func set_bet(b: int) -> void:
	bet = b if BETS.has(b) else 1
	jackpot = _get_jackpot(bet)
	_update_bet_label()


# ---------- сеть: автомат общий (slot/slot_net.gd, промпт 18.11 02:13) ----------

## Узел /root/SlotNet или null в одиночной игре.
func snet() -> Node:
	if game == null or not is_instance_valid(game) or game.get("net") == null:
		return null
	return get_tree().root.get_node_or_null("SlotNet")


func send(method: String, args: Array = []) -> void:
	var n := snet()
	if n:
		n.callv("rpc", [method] + args)


## Крутка другого игрока: пока крутятся барабаны, ждёт очереди (_process).
func net_spin(res: Array, free_used: bool) -> void:
	if busy or not net_queue.is_empty():
		net_queue.append([res, free_used])
		return
	_spin_start(res, free_used, false)


## Всё состояние автомата (хост — вошедшему игроку).
func net_state_dict() -> Dictionary:
	return {"jackpot": _get_jackpot(bet), "jackpots": jackpots.duplicate(), "free": free_spins, "bonus": bonus_game, "sevens": sevens_hit, "bet": bet}


func net_state(d: Dictionary) -> void:
	if d.has("jackpots") and d["jackpots"] is Dictionary:
		for k in d["jackpots"]:
			jackpots[int(k)] = int(d["jackpots"][k])
	elif d.has("jackpot"):
		_set_jackpot(int(d["jackpot"]), int(d.get("bet", bet)))
	free_spins = int(d.get("free", free_spins))
	bonus_game = bool(d.get("bonus", bonus_game))
	sevens_hit = bool(d.get("sevens", sevens_hit))
	set_bet(int(d.get("bet", bet)))
	


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
		return "[F] CASHY BOX — бесплатная крутка (%d)" % free_spins
	var cost := COST * bet
	return "[F] Крутить CASHY BOX ×%d — %d монет" % [bet, cost] if g.inv.coins >= cost else "CASHY BOX ×%d: нужно %d монет" % [bet, cost]


func interact(g) -> void:
	if busy or not net_queue.is_empty():
		return
	var free_used := free_spins > 0
	if not free_used:
		if g.inv.coins < COST * bet:
			g.hud.toast("Не хватает монет")
			return
		g.inv.remove("coin", COST * bet)
	var res: Array = []
	for i in 9:
		res.append(_roll())
	if _get_jackpot(bet) <= 0:   # банк на нуле — короны встают в средний ряд
		for k in LINES[1]:
			res[k] = "jack"
	if sevens_hit:   # после первых 777 линия семёрок перебрасывается с шансом SEVENS_REROLL
		for _n in 5:
			var l := _line_of(res, "seven")
			if l.is_empty() or randf() >= SEVENS_REROLL:
				break
			var s := _roll()
			while s == "seven":
				s = _roll()
			res[l[2]] = s
	_spin_start(res, free_used, true)
	send("f_spin", [res, free_used])


## Первая линия (LINES) из трёх символов id; пусто — такой нет.
func _line_of(res: Array, id: String) -> Array:
	for l in LINES:
		if res[l[0]] == id and res[l[1]] == id and res[l[2]] == id:
			return l
	return []


## Крутка: mine — своя, иначе чужая по сети (символы разыграл тот, кто дёрнул рычаг).
func _spin_start(res: Array, free_used: bool, mine: bool) -> void:
	spin_mine = mine
	if free_used:
		free_spins = maxi(0, free_spins - 1)
	else:
		_set_jackpot(maxi(0, _get_jackpot(bet) - 1), bet)
		bonus_game = false
	busy = true
	t = 0.0
	win_t = 99.0
	tier = 0
	banner = ""
	win_lines.clear()
	for i in 9:
		result[i] = String(res[i]) if i < res.size() else _roll()
		win_mask[i] = false
	# интрига: две бонуски на первых барабанах или начало линии из корон/семёрок — третий крутится дольше
	tease = result.slice(0, 6).count("bonus") >= 2
	for l in LINES:
		if result[l[0]] == result[l[1]] and result[l[0]] in ["jack", "seven"]:
			tease = true
	_plan_reels()
	msg = "БОНУС-ИГРА: ×2.0  (осталось %d)" % free_spins if bonus_game else "..."
	msg_col = Color(0.95, 0.85, 0.5)
	lever_t = 0.0
	SlotSounds.play3d(self, SlotSounds.lever(), lever.global_position, -7.0, randf_range(1.0, 1.08))
	snd.stream = sounds["spin"]
	snd.volume_db = -10.0
	snd.pitch_scale = 1.44 if bonus_game else 1.25
	snd.play()


func _stop_at(i: int) -> float:
	return (SPIN_T + i * STEP_T + (TEASE_T if tease and i == 2 else 0.0)) / spin_sp


## План крутки: лента едет с постоянной скоростью, потом плавно тормозит (easeOutBack) ровно на клетку
## reel_end, где лежат новые символы. Скорость подогнана, чтобы торможение начиналось без рывка.
func _plan_reels() -> void:
	spin_sp = 3.0 if fast else 1.0
	var k := EASE_C1 + 3.0   # f'(0) у easeOutBack
	for i in 3:
		reel_done[i] = false
		reel_clunk[i] = false
		reel_p[i] = 0.0
		reel_vel[i] = 0.0
		strip[i] = randi() % SYMS.size()
		var d := (DEC_T_TEASE if tease and i == 2 else DEC_T) / spin_sp
		var cruise := _stop_at(i) - d
		var v := REEL_V * (2.0 if fast else 1.0)
		reel_end[i] = maxi(ceili(v * cruise + v * d / k), 3)
		reel_v[i] = float(reel_end[i]) / (cruise + d / k)
		reel_d[i] = d
		reel_dec[i] = cruise


## Положение ленты барабана i в момент tt крутки.
func _reel_pos(i: int, tt: float) -> float:
	var v: float = reel_v[i]
	if tt < reel_dec[i]:
		return v * tt
	var y := clampf((tt - reel_dec[i]) / reel_d[i], 0.0, 1.0) - 1.0
	var f := 1.0 + (EASE_C1 + 1.0) * y * y * y + EASE_C1 * y * y
	var p0: float = v * reel_dec[i]
	return p0 + (float(reel_end[i]) - p0) * f


## Символ клетки ленты k: у конца — новое поле, у начала — старое, между — заполнитель.
func _reel_sym(i: int, k: int) -> String:
	var e: int = reel_end[i]
	if k <= e and k >= e - 2:
		return String(result[i * 3 + e - k])
	if k <= 0 and k >= -2:
		return String(shown[i * 3 - k])
	return String(SYMS[posmod(k * 3 + int(strip[i]), SYMS.size())])


func _process(delta: float) -> void:
	jack_l.text = "ДЖЕКПОТ %d" % _get_jackpot(bet)
	blink += delta
	win_t += delta
	# рычаг: рывок вниз и пружиной назад
	lever_t += delta
	var lk := clampf(lever_t / 0.5, 0.0, 1.0)
	lever.rotation.x = sin(PI * lk) * 1.1 * (1.0 - lk * 0.3) if lever_t < 0.5 else 0.0
	if busy:
		t += delta
		for i in 3:
			if reel_done[i]:
				continue
			var prev: float = reel_p[i]
			reel_p[i] = _reel_pos(i, t)
			reel_vel[i] = (float(reel_p[i]) - prev) / maxf(delta, 0.0001)
			var x: float = (t - float(reel_dec[i])) / float(reel_d[i])
			if not reel_clunk[i] and x >= 1.0 - EASE_C1 / (EASE_C1 + 1.0):   # символы встали на место — «клац»
				reel_clunk[i] = true
				_sfx("stop", -4.0, 0.9 + i * 0.08)
				if i == 1 and tease:
					_sfx("tease", -6.0)
					msg = "?!  ?!  ?!"
					msg_col = Color(1.0, 0.5, 0.3)
			if x >= 1.0:
				reel_done[i] = true
				reel_p[i] = float(reel_end[i])
				for r in 3:
					shown[i * 3 + r] = result[i * 3 + r]
		if reel_done[2]:
			busy = false
			snd.stop()
			_payout()
			if spin_mine and free_spins <= 0 and game and game.inv.coins < COST:
				preload("res://scripts/slot/slot_machine.gd").pity(game)
	elif not net_queue.is_empty():   # чужая крутка, пришедшая пока крутились барабаны
		var q: Array = net_queue.pop_front()
		_spin_start(q[0], bool(q[1]), false)
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


## Лампы, свет и маячок: золотые и изумрудные огоньки через один; в покое бегут медленно, в крутке — быстро,
## на выигрыше мигают все сразу.
func _lights(delta: float) -> void:
	var showing := win_t < (1.6 if tier == 1 else 3.2 if tier == 2 else 5.0) and tier > 0
	var base := Color(1.0, 0.78, 0.3)
	var alt := Color(0.3, 1.0, 0.55)
	if bonus_game or free_spins > 0:
		base = Color(0.75, 0.4, 1.0)
		alt = Color(1.0, 0.8, 0.4)
	var speed := 4.0 if not busy else 16.0
	var head := int(blink * speed)
	for k in bulbs.size():
		var on := (k + head) % 4 == 0 or (k + head) % 4 == 2
		var col := base if k % 2 == 0 else alt
		if showing:
			on = fmod(blink * (6.0 if tier < 3 else 12.0), 1.0) < 0.5
			if tier == 3:
				col = Color.from_hsv(fmod(blink * 1.5 + k / 30.0, 1.0), 0.8, 1.0)
		bulbs[k].emission = col
		bulbs[k].albedo_color = col if on else col.darkened(0.6)
		bulbs[k].emission_energy_multiplier = 1.2 if on else 0.12
	for k in top_bulbs.size():
		var on := (k + (head >> 1)) % 2 == 0 if not showing else fmod(blink * 8.0 + k * 0.5, 1.0) < 0.5
		top_bulbs[k].emission = base if k % 2 == 0 else alt
		top_bulbs[k].emission_energy_multiplier = 1.0 if on else 0.15
	var pulse := 0.7 + (0.2 * sin(blink * 9.0) if busy else 0.08 * sin(blink * 2.0))
	if showing:
		pulse = 0.8 + (0.7 if fmod(blink * (5.0 if tier < 3 else 14.0), 1.0) < 0.5 else 0.15) * (0.6 if tier == 1 else 1.0)
	lamp.light_energy = pulse
	lamp.light_color = base if not (showing and tier == 3) else Color.from_hsv(fmod(blink, 1.0), 0.6, 1.0)
	var sign_c := Color(1.0, 0.82, 0.35)
	sign_l.modulate = sign_c if not showing else sign_c.lerp(Color(1, 1, 1), 0.5 + 0.5 * sin(blink * 20.0))
	jack_l.modulate = Color(0.55, 1.0, 0.7) if not (showing and tier == 3) else Color.from_hsv(fmod(blink * 2.0, 1.0), 0.7, 1.0)
	var beacon_on := bonus_game or free_spins > 0 or (showing and tier >= 2)
	beacon.rotation.y += delta * (9.0 if beacon_on else 0.0)
	beacon_l.light_energy = lerpf(beacon_l.light_energy, 2.5 if beacon_on else 0.0, 1.0 - exp(-6.0 * delta))
	beacon_l.light_color = Color(0.7, 0.3, 1.0) if bonus_game or free_spins > 0 else Color(0.2, 1.0, 0.45)
	beacon_l.rotation.x = -0.5
	beacon_mat.emission_energy_multiplier = 1.5 if beacon_on else 0.15


## Выплата: три одинаковых в любой из 5 линий — PAY за линию; короны в линию — джекпот, три по полю — мини;
## бонуски по полю: одна — ничего, две — FREE_2 круток, три+ — бонус-игра. Денежное ×ставка (и ×2 в бонус-игре).
func _payout() -> void:
	var r: Array = result
	var mult := BONUS_MULT if bonus_game else 1.0
	var win := 0
	var lines: Array = []
	var jacks := r.count("jack")
	var bonus := r.count("bonus")
	tier = 0
	banner = ""
	win_lines.clear()
	for i in 9:
		win_mask[i] = false
	var jack_line := false
	for li in LINES.size():
		var l: Array = LINES[li]
		var s := String(r[l[0]])
		if String(r[l[1]]) != s or String(r[l[2]]) != s:
			continue
		if s == "jack":
			jack_line = true
		elif PAY.has(s):
			win += int(PAY[s])
			if s == "seven":
				sevens_hit = true
			if s in ["seven", "diamond"] and tier < 2:
				tier = 2
				banner = "777" if s == "seven" else "БРИЛЛИАНТЫ!"
		else:
			continue
		win_lines.append(li)
		for k in l:
			win_mask[k] = true
	if jack_line:
		win += JACK_WIN
		_set_jackpot(JACK_BASE, bet)
		lines.append("ДЖЕКПОТ!")
		tier = 3
		banner = "ДЖЕКПОТ!!!"
		if game:
			if spin_mine:
				game.hud.toast("ДЖЕКПОТ НА CASHY BOX: +%d" % roundi(win * mult * bet), Color(1.0, 0.8, 0.3))
			else:
				game.hud.toast("ДЖЕКПОТ НА CASHY BOX сорвал другой игрок", Color(1.0, 0.8, 0.3))
	elif jacks >= 3:
		win += MINI_JACK
		lines.append("МИНИ-ДЖЕКПОТ")
		tier = maxi(tier, 2)
		banner = "МИНИ-ДЖЕКПОТ"
		for i in 9:
			win_mask[i] = win_mask[i] or r[i] == "jack"
	if bonus >= 3:
		free_spins += FREE_3
		bonus_game = true
		lines.append("БОНУС-ИГРА: %d круток ×2" % FREE_3)
		tier = maxi(tier, 2)
		if banner == "":
			banner = "БОНУС-ИГРА!"
	elif bonus == 2:
		var f2 := FREE_2_BONUS if bonus_game else FREE_2
		free_spins += f2
		lines.append("БОНУС: +%d крутки" % f2)
		tier = maxi(tier, 2)
		if banner == "":
			banner = "+%d КРУТКИ" % f2
	if bonus >= 2:
		for i in 9:
			win_mask[i] = win_mask[i] or r[i] == "bonus"
	if win_lines.size() > 1:
		lines.append("ЛИНИЙ: %d" % win_lines.size())
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
		if spin_mine:
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


# ---------- покупка бонус-игры (красный магазин деревни, промпт 20.11 11:53) ----------

## Цена бонус-игры: BONUS_BUY круток по текущей ставке.
func bonus_buy_price() -> int:
	return BONUS_BUY * COST * bet


## Почему бонус-игру сейчас не купить ("" — можно).
func bonus_buy_block() -> String:
	if busy or not net_queue.is_empty():
		return "CASHY BOX крутится — подожди."
	if free_spins > 0:
		return "Ещё идут бесплатные крутки (%d)." % free_spins
	return ""


## Купить бонус-игру: списать монеты и сразу дать FREE_3 круток ×BONUS_MULT по текущей ставке.
func buy_bonus(g) -> bool:
	var price := bonus_buy_price()
	if bonus_buy_block() != "" or g.inv.count("coin") < price:
		return false
	g.inv.remove("coin", price)
	_grant_bonus()
	send("f_buy", [])
	return true


## Бонус-игру купил другой игрок (сеть).
func net_bonus_buy() -> void:
	_grant_bonus()


func _grant_bonus() -> void:
	free_spins += FREE_3
	bonus_game = true
	msg = "БОНУС-ИГРА КУПЛЕНА: %d КРУТОК ×2" % FREE_3
	msg_col = Color(0.85, 0.65, 1.0)
	tier = 0
	_sfx("bonus", -2.0)


## Иконка бонуски для магазина.
func draw_bonus_icon(ci: CanvasItem, r: Rect2) -> void:
	_sym(ci, "bonus", r)


## Монеты фонтаном из лотка (вид; сами монеты уже в сумке).
func _coin_fountain(amount: int) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.25 if amount > 40 else 0.6
	p.amount = amount
	p.lifetime = 1.3 if amount < 60 else 2.2
	p.position = Vector3(0, 0.29, 0.36)
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


# ---------- экран 3×3 ----------

## Клетка k поля (барабан k/3, ряд k%3), dy — сдвиг пружинки.
func _cell_rect(k: int, dy := 0.0) -> Rect2:
	var i := int(k / 3.0)
	return Rect2(X0 + i * (CW + GAP), TOP + (k % 3) * CH + dy, CW, CH)


## Квадрат символа внутри клетки.
func _sym_rect(cell: Rect2) -> Rect2:
	var s := minf(cell.size.x, cell.size.y) - 14.0
	return Rect2(cell.get_center() - Vector2(s, s) / 2.0, Vector2(s, s))


## Где линия li выходит к номеркам слева и справа: Vector2(y слева, y справа).
func _line_y(li: int) -> Vector2:
	var reel_h := CH * 3.0
	match li:
		3:
			return Vector2(TOP + 14.0, TOP + reel_h - 14.0)
		4:
			return Vector2(TOP + reel_h - 14.0, TOP + 14.0)
	var y := TOP + li * CH + CH / 2.0
	return Vector2(y, y)


func _draw_screen() -> void:
	var c := screen
	var bonus_mode := bonus_game or free_spins > 0
	var bg := Color(0.015, 0.06, 0.035) if not bonus_mode else Color(0.1, 0.03, 0.16)
	var goldc := Color(0.95, 0.76, 0.32)
	var font := ThemeDB.fallback_font
	var reel_h := CH * 3.0
	c.draw_rect(Rect2(0, 0, W, H), bg)
	# фон — тонкая золотая «гильоширная» сетка, как на купюре
	for k in 14:
		var x := k * 40.0 - 60.0 + fmod(blink * 5.0, 40.0)
		c.draw_line(Vector2(x, 0), Vector2(x + 120.0, H), Color(goldc, 0.07), 1.0)
		c.draw_line(Vector2(x + 120.0, 0), Vector2(x, H), Color(goldc, 0.05), 1.0)
	if bonus_mode:
		# звёздочки по фону бонус-игры
		for k in 18:
			var sx := fmod(k * 83.0 + blink * 20.0, float(W))
			var sy := fmod(k * 47.0, float(H))
			c.draw_circle(Vector2(sx, sy), 1.5 + sin(blink * 5.0 + k), Color(0.9, 0.7, 1.0, 0.5))
	var showing := tier > 0 and win_t < 6.0
	for i in 3:
		var x := X0 + i * (CW + GAP)
		var box := Rect2(x, TOP, CW, reel_h)
		var face := Color(0.78, 0.74, 0.64)
		var teasing: bool = tease and i == 2 and not reel_done[2] and reel_done[1]
		if teasing:
			face = face.lerp(Color(0.55, 0.85, 0.6), 0.15 + 0.15 * sin(blink * 18.0))
		c.draw_rect(box, face)
		if not reel_done[i]:
			# крутится: лента едет вниз, поверх — полосы «размытия»
			var pp: float = reel_p[i]
			var base := floori(pp)
			var off := (pp - base) * CH
			var blur := clampf(absf(float(reel_vel[i])) / REEL_V, 0.0, 1.0)   # к остановке размытие уходит
			for j in range(-1, 3):
				_sym(c, _reel_sym(i, base - j), _sym_rect(Rect2(x, TOP + j * CH + off, CW, CH)), 1.0, Color(1, 1, 1, 1.0 - 0.3 * blur))
			if blur > 0.05:
				for s in 9:
					var yy := fmod(pp * CH * 1.7 + s * 37.0, reel_h)
					c.draw_rect(Rect2(x, TOP + yy, CW, 6), Color(1, 1, 1, 0.12 * blur))
		else:
			# остановился: выигрышные клетки пульсируют и светятся
			for r in 3:
				var k := i * 3 + r
				var cell := _cell_rect(k)
				var sc := 1.0
				if showing and win_mask[k]:
					sc = 1.0 + 0.09 * absf(sin(win_t * 7.0))
					c.draw_rect(cell.grow(-4), Color(1.0, 0.85, 0.3, 0.22 + 0.12 * sin(win_t * 10.0)))
				_sym(c, String(shown[k]), _sym_rect(cell), sc)
		# объём барабана: тени сверху и снизу, тонкие разделители клеток
		for s in 6:
			var a := 0.2 * (1.0 - s / 6.0)
			c.draw_rect(Rect2(x, TOP + s * 6.0, CW, 6.0), Color(0, 0, 0, a))
			c.draw_rect(Rect2(x, TOP + reel_h - (s + 1) * 6.0, CW, 6.0), Color(0, 0, 0, a))
		for r in [1, 2]:
			c.draw_line(Vector2(x + 8, TOP + r * CH), Vector2(x + CW - 8, TOP + r * CH), Color(0.72, 0.56, 0.25, 0.5), 1.5)
	# маски над и под барабанами (туда вылезают крутящиеся символы)
	c.draw_rect(Rect2(0, 0, W, TOP), bg)
	c.draw_rect(Rect2(0, TOP + reel_h, W, H - TOP - reel_h), bg)
	# рамки барабанов: тёмная тень и золото; выигрышные клетки — яркая мигающая рамка
	for i in 3:
		var x := X0 + i * (CW + GAP)
		var box := Rect2(x, TOP, CW, reel_h)
		var frame := goldc
		if tease and i == 2 and not reel_done[2] and reel_done[1]:
			frame = Color(0.2, 1.0, 0.5) if fmod(blink * 10.0, 1.0) < 0.5 else Color(1.0, 0.9, 0.4)
		c.draw_rect(box.grow(4), Color(0.25, 0.16, 0.04), false, 3.0)
		c.draw_rect(box, frame, false, 4.0)
		c.draw_rect(box.grow(-3), Color(1.0, 0.95, 0.7, 0.6), false, 1.0)
		if showing:
			for r in 3:
				if win_mask[i * 3 + r]:
					var fc := Color(0.95, 0.82, 0.45) if fmod(win_t * 6.0, 1.0) < 0.5 else Color(0.35, 0.75, 0.48)
					c.draw_rect(_cell_rect(i * 3 + r).grow(-2), fc, false, 5.0)
	# выигравшие линии — золотые ломаные через клетки
	if showing:
		for li in win_lines:
			var ys := _line_y(li)
			var pts := PackedVector2Array([Vector2(22, ys.x)])
			for k in LINES[li]:
				pts.append(_cell_rect(k).get_center())
			pts.append(Vector2(W - 22, ys.y))
			c.draw_polyline(pts, Color(0.1, 0.05, 0.0, 0.6), 9.0)
			c.draw_polyline(pts, Color(1.0, 0.85, 0.25, 0.65 + 0.35 * sin(win_t * 12.0)), 5.0)
	# номерки линий слева и справа
	for li in LINES.size():
		var ys := _line_y(li)
		var on: bool = showing and li in win_lines
		var tc := Color(0.5, 0.4, 0.18)
		if on:
			tc = Color(0.3, 1.0, 0.5) if fmod(win_t * 6.0, 1.0) < 0.5 else goldc
		for side in 2:
			var tx := 3.0 if side == 0 else W - 21.0
			var ty: float = ys.x if side == 0 else ys.y
			c.draw_rect(Rect2(tx, ty - 9.0, 18, 18), tc)
			c.draw_rect(Rect2(tx, ty - 9.0, 18, 18), Color(0.1, 0.06, 0.0), false, 1.0)
			c.draw_string(font, Vector2(tx, ty + 5.0), str(li + 1), HORIZONTAL_ALIGNMENT_CENTER, 18, 14, Color(0.06, 0.04, 0.0))
	# верхняя полоса: название и банк
	c.draw_rect(Rect2(0, 0, W, TOP - 8), Color(0, 0, 0, 0.35))
	c.draw_line(Vector2(0, TOP - 8), Vector2(W, TOP - 8), goldc, 2.0)
	c.draw_string_outline(font, Vector2(12, 28), "CASHY BOX", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, 5, Color(0.02, 0.1, 0.05))
	c.draw_string(font, Vector2(12, 28), "CASHY BOX", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, goldc)
	c.draw_string(font, Vector2(0, 27), "ДЖЕКПОТ %d" % _get_jackpot(bet), HORIZONTAL_ALIGNMENT_RIGHT, W - 12, 18, Color(0.55, 1.0, 0.7))
	# крупный выигрыш: табло поверх барабанов, счётчик монет
	if showing and (tier >= 2 or win_amount > 0) and win_t < 4.5:
		var a := clampf(win_t * 4.0, 0.0, 1.0) * clampf((4.5 - win_t) * 2.0, 0.0, 1.0)
		var by := TOP + reel_h / 2.0 - 31.0
		c.draw_rect(Rect2(0, by, W, 62), Color(0, 0, 0, 0.62 * a))
		c.draw_line(Vector2(0, by), Vector2(W, by), Color(goldc, a), 2.0)
		c.draw_line(Vector2(0, by + 62), Vector2(W, by + 62), Color(goldc, a), 2.0)
		if banner != "":
			var bc := Color(1.0, 0.85, 0.3, a)
			if tier == 3:
				bc = Color.from_hsv(fmod(win_t * 1.2, 1.0), 0.75, 1.0, a)
			var fs := 34 if tier < 3 else int(36 + 4 * sin(win_t * 9.0))
			c.draw_string_outline(font, Vector2(0, by + 34), banner, HORIZONTAL_ALIGNMENT_CENTER, W, fs, 6, Color(0.02, 0.12, 0.05, a))
			c.draw_string(font, Vector2(0, by + 34), banner, HORIZONTAL_ALIGNMENT_CENTER, W, fs, bc)
		if win_amount > 0:
			var tx := "+%d" % count_shown
			c.draw_string_outline(font, Vector2(0, by + 58 if banner != "" else by + 44), tx, HORIZONTAL_ALIGNMENT_CENTER, W, 24 if banner != "" else 36, 5, Color(0, 0, 0, a))
			c.draw_string(font, Vector2(0, by + 58 if banner != "" else by + 44), tx, HORIZONTAL_ALIGNMENT_CENTER, W, 24 if banner != "" else 36, Color(1.0, 0.95, 0.6, a))
	# джекпот — стробоскоп по всему экрану
	if showing and tier == 3 and win_t < 3.0 and fmod(win_t * 8.0, 1.0) < 0.3:
		c.draw_rect(Rect2(0, 0, W, H), Color(1.0, 1.0, 0.9, 0.1))
	# нижнее табло: сообщение и ставка
	var my := TOP + reel_h + 10.0
	c.draw_line(Vector2(0, my), Vector2(W, my), goldc, 2.0)
	var col := msg_col
	if not busy and msg_col.r > 0.99:
		col.a = 0.6 + 0.4 * sin(blink * 8.0)
	c.draw_string(font, Vector2(0, my + 32), msg, HORIZONTAL_ALIGNMENT_CENTER, W, 22, col)
	c.draw_string(font, Vector2(0, my + 60), "5 ЛИНИЙ  ·  СТАВКА ×%d  ·  КРУТКА %d" % [bet, COST * bet], HORIZONTAL_ALIGNMENT_CENTER, W, 15, Color(goldc, 0.75))


## Символ в квадрате r: бонуска и корона — свои (элитные), остальные — slot_symbols.gd.
func _sym(ci: CanvasItem, id: String, r: Rect2, sc := 1.0, tint := Color(1, 1, 1, 1)) -> void:
	var ctr := r.get_center()
	var s := r.size.x
	ci.draw_set_transform(ctr * (1.0 - sc), 0.0, Vector2(sc, sc))
	match id:
		"bonus":   # изумрудная монета «B» в золотом сиянии
			var pts := PackedVector2Array()
			for k in 16:
				var a := -PI / 2.0 + TAU * k / 16.0 + sin(blink * 2.0) * 0.06
				pts.append(ctr + Vector2(cos(a), sin(a)) * s * (0.48 if k % 2 == 0 else 0.36))
			ci.draw_colored_polygon(pts, Color(1.0, 0.8, 0.25) * tint)
			ci.draw_polyline(pts + PackedVector2Array([pts[0]]), INK * tint, 2.5)
			ci.draw_circle(ctr, s * 0.33, INK * tint)
			ci.draw_circle(ctr, s * 0.3, Color(0.85, 0.62, 0.2) * tint)
			ci.draw_circle(ctr, s * 0.25, Color(0.05, 0.42, 0.22) * tint)
			ci.draw_circle(ctr + Vector2(-s * 0.04, -s * 0.04), s * 0.19, Color(0.1, 0.58, 0.32) * tint)
			ci.draw_arc(ctr, s * 0.25, 0, TAU, 24, Color(1.0, 0.85, 0.35) * tint, 1.5)
			var fs := maxi(int(s * 0.36), 8)
			var bp := ctr + Vector2(-s * 0.5, fs * 0.36)
			ci.draw_string_outline(ThemeDB.fallback_font, bp, "B", HORIZONTAL_ALIGNMENT_CENTER, s, fs, 4, INK * tint)
			ci.draw_string(ThemeDB.fallback_font, bp, "B", HORIZONTAL_ALIGNMENT_CENTER, s, fs, Color(1.0, 0.88, 0.4) * tint)
			ci.draw_rect(Rect2(ctr + Vector2(-s * 0.17, -s * 0.18), Vector2(s * 0.05, s * 0.05)), Color(1, 1, 1, 0.8) * tint)
		"jack":   # золотая корона с камнями
			var crown := PackedVector2Array([ctr + Vector2(-s * 0.4, s * 0.22), ctr + Vector2(-s * 0.44, -s * 0.22), ctr + Vector2(-s * 0.2, -s * 0.02),
				ctr + Vector2(0, -s * 0.36), ctr + Vector2(s * 0.2, -s * 0.02), ctr + Vector2(s * 0.44, -s * 0.22), ctr + Vector2(s * 0.4, s * 0.22)])
			ci.draw_polyline(crown + PackedVector2Array([crown[0]]), INK * tint, 6.0)
			ci.draw_colored_polygon(crown, Color(0.97, 0.75, 0.25) * tint)
			ci.draw_colored_polygon(PackedVector2Array([ctr + Vector2(0, -s * 0.36), ctr + Vector2(s * 0.2, -s * 0.02), ctr + Vector2(s * 0.44, -s * 0.22),
				ctr + Vector2(s * 0.4, s * 0.22), ctr + Vector2(0, s * 0.22)]), Color(0.78, 0.52, 0.12) * tint)
			ci.draw_rect(Rect2(ctr + Vector2(-s * 0.43, s * 0.11), Vector2(s * 0.86, s * 0.15)), INK * tint)
			ci.draw_rect(Rect2(ctr + Vector2(-s * 0.4, s * 0.13), Vector2(s * 0.8, s * 0.1)), Color(1.0, 0.84, 0.38) * tint)
			var gems: Array[Color] = [Color(0.85, 0.1, 0.15), Color(0.1, 0.75, 0.35), Color(0.2, 0.4, 0.95)]
			for k in 3:
				var gp := ctr + Vector2((k - 1) * s * 0.25, s * 0.18)
				ci.draw_circle(gp, s * 0.05, INK * tint)
				ci.draw_circle(gp, s * 0.035, gems[k] * tint)
				ci.draw_circle(gp + Vector2(-s * 0.012, -s * 0.012), s * 0.01, Color(1, 1, 1, 0.9) * tint)
			# жемчужины на зубцах поблёскивают
			for k in [1, 3, 5]:
				ci.draw_circle(crown[k], s * 0.06, INK * tint)
				ci.draw_circle(crown[k], s * (0.04 + 0.008 * sin(blink * 6.0 + k)), Color(1.0, 0.97, 0.82) * tint)
		_:
			Sym.draw(ci, id, r)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
