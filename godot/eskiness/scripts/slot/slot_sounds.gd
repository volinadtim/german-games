## Общие процедурные звуки автоматов (KILLBOX и ФОРТУНА), промпт 16.11 04:18:
## звон монет о металлический лоток и механический рывок рычага. Генерируются один раз и кэшируются.
extends RefCounted

const RATE := 22050

static var _tray: Array = []
static var _clinks: Array = []
static var _lever_wav: AudioStreamWAV


## Одна монетка бьётся о металл: неровные моды диска (быстро гаснут, верхние — быстрее),
## короткий мягкий щелчок удара и глухой отклик лотка. Плюс 1–2 затухающих подскока.
static func _clink(buf: PackedFloat32Array, at: float, amp: float, f0: float, rng: RandomNumberGenerator, tray_k := 1.0) -> void:
	var ratios := [1.0, 1.73, 2.33, 3.04]
	var amps := [1.0, 0.55, 0.32, 0.18]
	var decs := [26.0, 38.0, 55.0, 80.0]
	var hits := [[0.0, 1.0]]
	var t_b := rng.randf_range(0.025, 0.05)
	hits.append([t_b, rng.randf_range(0.25, 0.4)])
	if rng.randf() < 0.6:
		hits.append([t_b + rng.randf_range(0.015, 0.03), rng.randf_range(0.08, 0.16)])
	for h in hits:
		var st := int((at + float(h[0])) * RATE)
		var a: float = amp * float(h[1])
		var f := f0 * rng.randf_range(0.97, 1.03)
		var ph := [rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU]
		var lp := 0.0
		var n := int(0.18 * RATE)
		for i in n:
			var k := st + i
			if k >= buf.size():
				break
			var tt := float(i) / RATE
			var att := minf(1.0, tt / 0.0015)   # без щелчка в атаке — не режет
			var v := 0.0
			for m in 4:
				v += sin(TAU * f * ratios[m] * tt + ph[m]) * amps[m] * exp(-tt * decs[m])
			# мягкий шумовой «тик» удара, пропущенный через фильтр
			lp += ((rng.randf() * 2.0 - 1.0) - lp) * 0.3
			v += lp * exp(-tt * 400.0) * 0.6
			# лоток: глухое металлическое «тонк»
			v += (sin(TAU * 640.0 * tt) * 0.5 + sin(TAU * 1130.0 * tt) * 0.3) * exp(-tt * 34.0) * 0.45 * tray_k
			buf[k] += v * a * att


static func _to_wav(buf: PackedFloat32Array, gain: float) -> AudioStreamWAV:
	var peak := 0.0001
	for v in buf:
		peak = maxf(peak, absf(v))
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	var lp := 0.0
	for i in buf.size():
		lp += (buf[i] - lp) * 0.55   # срезаем самый верх — звон без резкости
		var fade := minf(1.0, float(buf.size() - i) / (RATE * 0.04))
		data.encode_s16(i * 2, int(clampf(lp / peak * gain * fade, -1.0, 1.0) * 32000.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = RATE
	st.stereo = false
	st.data = data
	return st


## Пачка монет в лоток (3 варианта): 10–14 звяков с разной высотой, гуще в начале, в конце — дозвякивание.
static func tray() -> AudioStreamWAV:
	if _tray.is_empty():
		for v in 3:
			var rng := RandomNumberGenerator.new()
			rng.seed = 7100 + v
			var buf := PackedFloat32Array()
			buf.resize(int(0.85 * RATE))
			var cnt := rng.randi_range(10, 14)
			var at := 0.0
			for c in cnt:
				var late := float(c) / cnt
				_clink(buf, at, rng.randf_range(0.45, 1.0) * (1.0 - late * 0.5), rng.randf_range(2300.0, 3600.0), rng)
				at += rng.randf_range(0.015, 0.035) + late * rng.randf_range(0.0, 0.05)
			_tray.append(_to_wav(buf, 0.7))
	return _tray[randi() % _tray.size()]


## Одиночный звяк монетки (4 варианта) — для счётчика выигрыша.
static func clink() -> AudioStreamWAV:
	if _clinks.is_empty():
		for v in 4:
			var rng := RandomNumberGenerator.new()
			rng.seed = 7200 + v
			var buf := PackedFloat32Array()
			buf.resize(int(0.3 * RATE))
			_clink(buf, 0.0, 1.0, rng.randf_range(2400.0, 3400.0), rng, 0.7)
			_clinks.append(_to_wav(buf, 0.6))
	return _clinks[randi() % _clinks.size()]


## Рывок рычага (~0.75 с): вниз — храповик (6 щелчков-лязгов) под скрип пружины, внизу упор;
## назад — пружина скрипит, сжимаясь, и в конце глухой стук рычага о покой.
static func lever() -> AudioStreamWAV:
	if _lever_wav:
		return _lever_wav
	var rng := RandomNumberGenerator.new()
	rng.seed = 4180
	var n := int(0.8 * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	# скрип пружины: прерывистое трение (stick-slip) — импульсы, возбуждающие металлические резонансы
	var creak := [[0.0, 0.17, 70.0, 120.0, 0.35], [0.22, 0.56, 130.0, 60.0, 0.5]]
	for cr in creak:
		var t0: float = cr[0]
		var t1: float = cr[1]
		var tp := t0
		while tp < t1:
			var u := (tp - t0) / (t1 - t0)
			var rate: float = lerpf(cr[2], cr[3], u) * rng.randf_range(0.85, 1.15)
			var a: float = cr[4] * sin(PI * u) * rng.randf_range(0.6, 1.0)
			var st := int(tp * RATE)
			for i in int(0.012 * RATE):
				var k := st + i
				if k >= n:
					break
				var tt := float(i) / RATE
				buf[k] += (sin(TAU * 1750.0 * tt) * 0.6 + sin(TAU * 2900.0 * tt) * 0.3 + sin(TAU * 980.0 * tt) * 0.4) * exp(-tt * 420.0) * a
			tp += 1.0 / rate
	# храповик: резкие, но короткие металлические щелчки при ходе вниз, затем пара мягче при возврате
	var clicks := [0.02, 0.048, 0.074, 0.098, 0.12, 0.14, 0.3, 0.38, 0.45]
	for ci in clicks.size():
		var tc: float = clicks[ci]
		var back := ci >= 6
		var a := (0.5 if back else 0.9) * rng.randf_range(0.8, 1.0)
		var f := rng.randf_range(2300.0, 2700.0) * (0.85 if back else 1.0)
		var st := int(tc * RATE)
		var lp := 0.0
		for i in int(0.05 * RATE):
			var k := st + i
			if k >= n:
				break
			var tt := float(i) / RATE
			lp += ((rng.randf() * 2.0 - 1.0) - lp) * 0.5
			var v := lp * exp(-tt * 600.0) * 0.8
			v += (sin(TAU * f * tt) * 0.6 + sin(TAU * f * 1.48 * tt) * 0.3) * exp(-tt * 140.0)
			v += sin(TAU * 420.0 * tt) * exp(-tt * 60.0) * 0.35   # лязг корпуса
			buf[k] += v * a * minf(1.0, tt / 0.0008)
	# упор внизу (~0.18 с) и глухой стук в конце (~0.6 с): низкое тело + приглушённый шум
	for th in [[0.18, 0.55, 110.0], [0.6, 1.0, 85.0]]:
		var st := int(float(th[0]) * RATE)
		var lp := 0.0
		for i in int(0.2 * RATE):
			var k := st + i
			if k >= n:
				break
			var tt := float(i) / RATE
			var f: float = float(th[2]) * (1.0 - tt * 1.2)
			lp += ((rng.randf() * 2.0 - 1.0) - lp) * 0.08
			var v := sin(TAU * f * tt) * exp(-tt * 20.0) + sin(TAU * f * 2.1 * tt) * exp(-tt * 35.0) * 0.35
			v += lp * exp(-tt * 45.0) * 2.0
			buf[k] += v * float(th[1]) * 1.3 * minf(1.0, tt / 0.002)
	_lever_wav = _to_wav(buf, 0.85)
	return _lever_wav


## Разовый 3D-звук от узла (сам удаляется).
static func play3d(parent: Node3D, st: AudioStream, pos: Vector3, db: float, pitch := 1.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = st
	p.volume_db = db
	p.unit_size = 4.0
	p.pitch_scale = pitch
	parent.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()
