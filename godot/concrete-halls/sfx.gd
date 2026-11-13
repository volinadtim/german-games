extends RefCounted
## Процедурные звуки (без файлов): шаги, взмах кулака, выдох, вдох, удар.
## Всё строится из шума и мягких фильтров — без резонансов и дискретного эха, чтобы не звенело.

const RATE := 22050


class Svf:
	## Мягкий полосовой фильтр (state variable filter).
	var low := 0.0
	var band := 0.0
	var f := 0.1
	var q := 1.0

	func _init(fc: float, quality: float) -> void:
		set_fc(fc)
		q = 1.0 / quality

	func set_fc(fc: float) -> void:
		f = 2.0 * sin(PI * clampf(fc, 20.0, RATE * 0.2) / RATE)

	func bp(x: float) -> float:
		low += f * band
		var high := x - low - q * band
		band += f * high
		return band


static func _env(t: float, start: float, attack: float, decay: float) -> float:
	if t < start:
		return 0.0
	var tt := t - start
	return minf(tt / attack, 1.0) * exp(-tt * decay)


static func _wav(buf: PackedFloat32Array, gain := 0.9) -> AudioStreamWAV:
	var n := buf.size()
	var peak := 0.0001
	for v in buf:
		peak = maxf(peak, absf(v))
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var fade := minf(1.0, float(n - i) / (RATE * 0.03))
		data.encode_s16(i * 2, int(clampf(buf[i] / peak * gain * fade, -1.0, 1.0) * 32000.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = RATE
	st.stereo = false
	st.data = data
	return st


## Шаг ботинка по камню: глухой удар пятки, перекат на носок, хруст песчинок под подошвой,
## короткий шорох и рассеянный (не «бочковой») хвост помещения.
static func step(variant: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 300 + variant
	var n := int(RATE * 0.32)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var toe_t := rng.randf_range(0.055, 0.09)
	var toe_a := rng.randf_range(0.35, 0.6)
	var lp1 := 0.0
	var lp2 := 0.0
	var tail := 0.0
	var grit := Svf.new(rng.randf_range(2200.0, 3200.0), 0.7)
	var scrape := Svf.new(rng.randf_range(900.0, 1400.0), 0.8)
	for i in n:
		var t := float(i) / RATE
		var w := rng.randf() * 2.0 - 1.0
		lp1 += (w - lp1) * 0.08
		lp2 += (lp1 - lp2) * 0.08
		var e_heel := _env(t, 0.0, 0.004, 48.0)
		var e_toe := _env(t, toe_t, 0.003, 65.0)
		var v := lp2 * 7.0 * (e_heel + e_toe * toe_a)
		# хруст: редкие случайные импульсы, гуще в момент касания
		var dens := 0.35 * e_heel + 0.25 * e_toe
		var imp := rng.randf_range(-1.0, 1.0) if rng.randf() < dens * 0.25 else 0.0
		v += grit.bp(imp) * 0.9
		v += scrape.bp(w) * 0.06 * exp(-pow((t - 0.07) / 0.04, 2.0))
		tail += (w - tail) * 0.15
		v += tail * 0.025 * _env(t, 0.008, 0.02, 14.0)
		buf[i] = v
	return _wav(buf, 0.85)


## Взмах кулака: шум с плавающей полосой.
static func whoosh(variant: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 400 + variant
	var dur := rng.randf_range(0.18, 0.26)
	var n := int(RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var f := Svf.new(500.0, 0.9)
	var f0 := rng.randf_range(350.0, 500.0)
	var f1 := rng.randf_range(1100.0, 1700.0)
	for i in n:
		var x := float(i) / n
		f.set_fc(lerpf(f0, f1, sin(x * PI)))
		var env := pow(sin(x * PI), 2.0) * (1.0 - x * 0.4)
		buf[i] = f.bp(rng.randf() * 2.0 - 1.0) * env
	return _wav(buf, 0.6)


## Выдох при ударе: «хх» с лёгким голосовым призвуком.
static func exhale(variant: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 500 + variant
	var n := int(RATE * 0.32)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var f1 := Svf.new(rng.randf_range(850.0, 1150.0), 1.6)
	var f2 := Svf.new(rng.randf_range(2300.0, 2800.0), 2.0)
	var fv := Svf.new(rng.randf_range(600.0, 750.0), 2.5)
	var pitch := rng.randf_range(105.0, 140.0)
	var ph := 0.0
	var voice := rng.randf_range(0.15, 0.35)
	for i in n:
		var t := float(i) / RATE
		var w := rng.randf() * 2.0 - 1.0
		var env := _env(t, 0.0, 0.015, 9.0)
		ph = fmod(ph + pitch * (1.0 - t * 0.6) / RATE, 1.0)
		var glott := (1.0 - ph * 2.0) * _env(t, 0.0, 0.01, 22.0)
		buf[i] = (f1.bp(w) + f2.bp(w) * 0.45) * env + fv.bp(glott) * voice
	return _wav(buf, 0.7)


## Короткий вдох носом/ртом при поднятии рук.
static func inhale(reverse := false) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 600
	var n := int(RATE * 0.5)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var f1 := Svf.new(1500.0, 1.3)
	var f2 := Svf.new(3400.0, 1.0)
	var lo1 := 0.0
	var lo2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var w := rng.randf() * 2.0 - 1.0
		lo1 += (w - lo1) * 0.03      # ~100 Гц — лёгкий басовый призвук
		lo2 += (lo1 - lo2) * 0.03
		var env := smoothstep(0.0, 0.3, t) * (1.0 - smoothstep(0.32, 0.48, t))
		# верха чуть урезаны (вторая полоса тише и ниже), бас добавлен совсем немного
		buf[i] = (f1.bp(w) + f2.bp(w) * 0.25 + lo2 * 1.2) * env
	if reverse:
		buf.reverse()
	return _wav(buf, 0.45)


## Удар кулаком во что-то твёрдое: глухой шлепок + хруст пыли.
static func impact(variant: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 700 + variant
	var n := int(RATE * 0.22)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp1 := 0.0
	var lp2 := 0.0
	var smack := Svf.new(rng.randf_range(700.0, 1000.0), 0.8)
	var grit := Svf.new(2800.0, 0.7)
	for i in n:
		var t := float(i) / RATE
		var w := rng.randf() * 2.0 - 1.0
		lp1 += (w - lp1) * 0.06
		lp2 += (lp1 - lp2) * 0.06
		var v := lp2 * 9.0 * _env(t, 0.0, 0.002, 38.0)
		v += smack.bp(w) * 0.5 * _env(t, 0.0, 0.001, 90.0)
		var imp := rng.randf_range(-1.0, 1.0) if rng.randf() < 0.1 * _env(t, 0.005, 0.005, 30.0) else 0.0
		v += grit.bp(imp) * 0.7
		buf[i] = v
	return _wav(buf, 0.9)


## Тихий шум-«подложка» для шага: мягкий шорох, затухающий вместе со звуком шага.
static func step_noise() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 800
	var n := int(RATE * 0.6)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var w := rng.randf() * 2.0 - 1.0
		lp += (w - lp) * 0.35
		buf[i] = lp * _env(t, 0.0, 0.004, 7.0)
	return _wav(buf, 0.9)
