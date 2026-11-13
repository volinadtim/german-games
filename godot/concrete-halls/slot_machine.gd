extends StaticBody3D
## Игровой автомат «Однорукий» (слоты): E — бросить монету и дёрнуть рычаг.
## Три барабана крутятся и останавливаются по очереди. Выплата:
##   7-7-7 — 30 монет, $-$-$ — 12, любые три одинаковых — 6, пара — 1 (монета назад).
## Монеты высыпаются в лоток. Автомат — единственный свет в тёмной комнате.

const SYMBOLS := ["7", "$", "Ж", "Ф", "Ы"]
const WEIGHTS := [1, 2, 3, 3, 3]
const COLORS := [Color(0.85, 0.15, 0.1), Color(0.9, 0.7, 0.2), Color(0.3, 0.6, 0.3), Color(0.35, 0.45, 0.75), Color(0.6, 0.35, 0.6)]

var game  # game.gd
var busy := false
var spin_t := 0.0
var tick_t := 0.0
var stops: Array[float] = []
var result: Array[int] = [0, 0, 0]
var stopped: Array[bool] = [true, true, true]
var reels: Array[Label3D] = []
var lever: Node3D
var bulbs: Array[StandardMaterial3D] = []
var light: OmniLight3D
var screen: Label3D
var party := 0.0
var t := 0.0
var snd: AudioStreamPlayer3D
var snd2: AudioStreamPlayer3D


func _ready() -> void:
	_build()
	snd = AudioStreamPlayer3D.new()
	snd.position = Vector3(0, 1.0, 0.3)
	snd.unit_size = 4.0
	add_child(snd)
	snd2 = AudioStreamPlayer3D.new()
	snd2.position = Vector3(0, 1.0, 0.3)
	snd2.unit_size = 4.0
	add_child(snd2)


func _mat(c: Color, metal := 0.0, rough := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


## Перед автомата — +Z.
func _build() -> void:
	var body := _mat(Color(0.26, 0.07, 0.05), 0.4, 0.5)
	var trim := _mat(Color(0.45, 0.36, 0.2), 0.8, 0.35)
	var black := _mat(Color(0.02, 0.02, 0.02))
	_box(self, Vector3(0.8, 1.2, 0.6), Vector3(0, 0.6, 0), body)
	_box(self, Vector3(0.86, 0.36, 0.66), Vector3(0, 1.38, 0), body)
	_box(self, Vector3(0.88, 0.04, 0.68), Vector3(0, 1.2, 0), trim)
	_box(self, Vector3(0.88, 0.04, 0.68), Vector3(0, 1.56, 0), trim)
	# окно барабанов
	_box(self, Vector3(0.66, 0.34, 0.02), Vector3(0, 0.98, 0.3), trim)
	_box(self, Vector3(0.62, 0.3, 0.02), Vector3(0, 0.98, 0.305), black)
	var face := _mat(Color(0.75, 0.7, 0.6), 0.0, 0.6)
	face.emission_enabled = true
	face.emission = Color(1.0, 0.85, 0.6)
	face.emission_energy_multiplier = 0.35
	for i in 3:
		var x := (i - 1) * 0.2
		_box(self, Vector3(0.17, 0.26, 0.01), Vector3(x, 0.98, 0.315), face)
		var l := Label3D.new()
		l.text = SYMBOLS[randi() % SYMBOLS.size()]
		l.font_size = 120
		l.pixel_size = 0.0015
		l.outline_size = 0
		l.shaded = false
		l.position = Vector3(x, 0.98, 0.322)
		l.modulate = COLORS[SYMBOLS.find(l.text)]
		add_child(l)
		reels.append(l)
	# вывеска
	var sign_l := Label3D.new()
	sign_l.text = "ОДНОРУКИЙ"
	sign_l.font_size = 64
	sign_l.pixel_size = 0.0022
	sign_l.outline_size = 6
	sign_l.outline_modulate = Color(0.2, 0.05, 0.0)
	sign_l.modulate = Color(1.0, 0.72, 0.35)
	sign_l.position = Vector3(0, 1.4, 0.335)
	add_child(sign_l)
	screen = Label3D.new()
	screen.text = "1 МОНЕТА — 1 ИГРА"
	screen.font_size = 32
	screen.pixel_size = 0.0018
	screen.outline_size = 0
	screen.modulate = Color(0.85, 0.75, 0.5)
	screen.position = Vector3(0, 0.74, 0.305)
	add_child(screen)
	# лампочки по верху вывески
	for k in 9:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.3, 0.2, 0.1)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.65, 0.3)
		m.emission_energy_multiplier = 1.0
		var b := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.022
		sm.height = 0.044
		b.mesh = sm
		b.material_override = m
		b.position = Vector3(-0.36 + k * 0.09, 1.6, 0.31)
		add_child(b)
		bulbs.append(m)
	# прорезь для монет и лоток
	_box(self, Vector3(0.12, 0.08, 0.02), Vector3(0.22, 0.72, 0.305), trim)
	_box(self, Vector3(0.05, 0.012, 0.03), Vector3(0.22, 0.72, 0.315), black)
	_box(self, Vector3(0.5, 0.06, 0.2), Vector3(0, 0.3, 0.36), trim)
	_box(self, Vector3(0.46, 0.14, 0.02), Vector3(0, 0.36, 0.45), trim)
	# рычаг справа
	lever = Node3D.new()
	lever.position = Vector3(0.43, 0.9, 0.05)
	add_child(lever)
	var rod := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.018
	cm.bottom_radius = 0.018
	cm.height = 0.45
	rod.mesh = cm
	rod.material_override = trim
	rod.position = Vector3(0.03, 0.22, 0)
	lever.add_child(rod)
	var ball := MeshInstance3D.new()
	var bs := SphereMesh.new()
	bs.radius = 0.05
	bs.height = 0.1
	ball.mesh = bs
	ball.material_override = _mat(Color(0.6, 0.08, 0.05), 0.2, 0.3)
	ball.position = Vector3(0.03, 0.46, 0)
	lever.add_child(ball)
	_box(self, Vector3(0.06, 0.12, 0.12), Vector3(0.42, 0.9, 0.05), trim)

	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.62, 0.32)
	light.light_energy = 0.7
	light.omni_range = 4.5
	light.shadow_enabled = true
	light.position = Vector3(0, 1.3, 0.75)
	add_child(light)

	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.86, 1.58, 0.66)
	cs.shape = shape
	cs.position = Vector3(0, 0.79, 0)
	add_child(cs)


func get_prompt(_game) -> String:
	return "" if busy else "[E] Сыграть (1 монета)"


func interact(g) -> void:
	game = g
	if busy:
		return
	if not g.inv.remove("coin", 1):
		g.hud.toast("Нет монет")
		g.play_at("buzz", global_position, -14.0)
		screen.text = "НУЖНА МОНЕТА"
		return
	busy = true
	spin_t = 0.0
	screen.text = "УДАЧИ..."
	stops = [0.9, 1.35, 1.8]
	stopped = [false, false, false]
	for i in 3:
		result[i] = _weighted()
	g.play_at("coin", global_position + Vector3(0.2, 0.7, 0.3), -10.0)
	var tw := create_tween()
	tw.tween_property(lever, "rotation:x", 1.1, 0.18).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(lever, "rotation:x", 0.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _weighted() -> int:
	var total := 0
	for w in WEIGHTS:
		total += int(w)
	var r := randi() % total
	for i in WEIGHTS.size():
		r -= int(WEIGHTS[i])
		if r < 0:
			return i
	return 0


func _process(delta: float) -> void:
	t += delta
	# лампочки: бегущий огонёк, при выигрыше — быстро мигают все
	party = maxf(party - delta, 0.0)
	for k in bulbs.size():
		var on: bool
		if party > 0.0:
			on = int(t * 10.0) % 2 == k % 2
		else:
			on = int(t * 3.0) % 3 != k % 3
		bulbs[k].emission_energy_multiplier = 1.6 if on else 0.15
	light.light_energy = 0.7 + (0.35 * sin(t * 30.0) if party > 0.0 else 0.04 * sin(t * 2.3))
	if not busy or game == null:
		return
	spin_t += delta
	tick_t -= delta
	var spinning := false
	for i in 3:
		if stopped[i]:
			continue
		if spin_t >= stops[i]:
			stopped[i] = true
			_show(i, result[i])
			game.play_at("clunk", reels[i].global_position, -8.0)
		else:
			spinning = true
	if spinning and tick_t <= 0.0:
		tick_t = 0.065
		for i in 3:
			if not stopped[i]:
				_show(i, randi() % SYMBOLS.size())
		snd.stream = game.snd["tick"][0]
		snd.volume_db = -16.0
		snd.pitch_scale = randf_range(0.9, 1.1)
		snd.play()
	if not spinning:
		_payout()


func _show(i: int, s: int) -> void:
	reels[i].text = SYMBOLS[s]
	reels[i].modulate = COLORS[s]


func _payout() -> void:
	var a := result[0]
	var b := result[1]
	var c := result[2]
	var win := 0
	if a == b and b == c:
		win = 30 if a == 0 else (12 if a == 1 else 6)
	elif a == b or b == c or a == c:
		win = 1
	if win > 1:
		screen.text = "ВЫИГРЫШ: %d" % win
		party = 2.5
		snd2.stream = game.snd["jingle"][0]
		snd2.volume_db = -10.0
		snd2.pitch_scale = 1.0
		snd2.play()
		game.hud.toast("Автомат: выигрыш %d монет!" % win, Color(1.0, 0.8, 0.4))
	elif win == 1:
		screen.text = "ПАРА — МОНЕТА НАЗАД"
	else:
		screen.text = "ПУСТО"
	if win > 0:
		var tray := global_transform * Vector3(0, 0.45, 0.4)
		var fwd := global_transform.basis.z
		game.spawn_loot("coin", win, tray, fwd * 1.2 + Vector3(0, 1.2, 0), 0.5)
	busy = false
