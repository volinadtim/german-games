extends RefCounted
## Процедурные звуки тестовых механик (без файлов): монета, скрип крышки, щелчок фонарика,
## тик барабана, мелодия выигрыша, отказ, рык врага, падение тела, подбор предмета.

const Sfx := preload("res://sfx.gd")
const RATE := 22050


static func _buf(sec: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(RATE * sec))
	return b


## Монетка: короткий металлический «дзынь» с отскоком.
static func coin(variant: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + variant
	var buf := _buf(0.3)
	var f1 := rng.randf_range(2300.0, 2900.0)
	var f2 := f1 * rng.randf_range(1.48, 1.56)
	var f3 := f1 * rng.randf_range(2.2, 2.4)
	var hit2 := rng.randf_range(0.05, 0.09)
	for i in buf.size():
		var t := float(i) / RATE
		var v := 0.0
		for k in 2:
			var h := 0.0 if k == 0 else hit2
			if t < h:
				continue
			var tt := t - h
			var a := 1.0 if k == 0 else 0.4
			v += a * (sin(TAU * f1 * tt) * exp(-tt * 24.0) + 0.6 * sin(TAU * f2 * tt) * exp(-tt * 32.0) + 0.3 * sin(TAU * f3 * tt) * exp(-tt * 45.0))
			v += a * (rng.randf() * 2.0 - 1.0) * exp(-tt * 400.0) * 0.8
		buf[i] = v
	return Sfx._wav(buf, 0.5)


## Скрип старой крышки/дверцы: прерывистое трение с плавающей частотой.
static func creak(variant: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1100 + variant
	var buf := _buf(0.8)
	var bp1 := Sfx.Svf.new(rng.randf_range(650.0, 900.0), 3.0)
	var bp2 := Sfx.Svf.new(rng.randf_range(1400.0, 1800.0), 2.5)
	var ph := 0.0
	var f0 := rng.randf_range(45.0, 70.0)
	for i in buf.size():
		var t := float(i) / RATE
		var f := f0 + 40.0 * sin(t * 4.0 + variant) + 30.0 * t
		ph += f / RATE
		var imp := 0.0
		if ph >= 1.0:
			ph -= 1.0
			imp = rng.randf_range(0.5, 1.0)
		var env := smoothstep(0.0, 0.05, t) * (1.0 - smoothstep(0.5, 0.78, t)) * (0.6 + 0.4 * sin(t * 9.0))
		buf[i] = (bp1.bp(imp) + bp2.bp(imp) * 0.6 + (rng.randf() * 2.0 - 1.0) * 0.01) * env
	return Sfx._wav(buf, 0.55)


## Щелчок кнопки фонарика.
static func click() -> AudioStreamWAV:
	var buf := _buf(0.07)
	var bp := Sfx.Svf.new(3200.0, 1.5)
	var bp2 := Sfx.Svf.new(1200.0, 1.2)
	var second := int(RATE * 0.02)
	for i in buf.size():
		var imp := 1.0 if i == 0 else (0.5 if i == second else 0.0)
		buf[i] = bp.bp(imp) + bp2.bp(imp) * 0.5
	return Sfx._wav(buf, 0.6)


## Тик барабана игрового автомата.
static func tick() -> AudioStreamWAV:
	var buf := _buf(0.04)
	var bp := Sfx.Svf.new(2000.0, 2.0)
	var lp := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 1200
	for i in buf.size():
		var t := float(i) / RATE
		var imp := 1.0 if i == 0 else 0.0
		lp += ((rng.randf() * 2.0 - 1.0) - lp) * 0.3
		buf[i] = bp.bp(imp) + lp * exp(-t * 200.0) * 0.4
	return Sfx._wav(buf, 0.5)


## Глухой стук остановки барабана.
static func clunk() -> AudioStreamWAV:
	var buf := _buf(0.12)
	var bp := Sfx.Svf.new(500.0, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1250
	var lp := 0.0
	for i in buf.size():
		var t := float(i) / RATE
		lp += ((rng.randf() * 2.0 - 1.0) - lp) * 0.1
		buf[i] = bp.bp(1.0 if i == 0 else 0.0) * 0.8 + lp * 4.0 * exp(-t * 40.0)
	return Sfx._wav(buf, 0.6)


## Мелодия выигрыша: несколько мягких «квадратных» нот вверх.
static func jingle() -> AudioStreamWAV:
	var notes := [392.0, 494.0, 587.0, 784.0, 587.0, 784.0]
	var nd := 0.11
	var buf := _buf(nd * notes.size() + 0.5)
	var lp := 0.0
	var last := notes.size() - 1
	for i in buf.size():
		var t := float(i) / RATE
		var k := mini(int(t / nd), last)
		var f: float = notes[k]
		var tt := t - k * nd
		var tone := signf(sin(TAU * f * t)) * 0.4 + sin(TAU * f * t)
		var env := exp(-tt * (3.5 if k == last else 9.0)) * minf(tt / 0.004, 1.0)
		lp += (tone * env - lp) * 0.22
		buf[i] = lp
	return Sfx._wav(buf, 0.5)


## Отказ: два низких гудка.
static func buzz() -> AudioStreamWAV:
	var buf := _buf(0.42)
	var lp := 0.0
	var lp2 := 0.0
	for i in buf.size():
		var t := float(i) / RATE
		var on := 1.0 if (t < 0.15 or (t > 0.22 and t < 0.38)) else 0.0
		var x := signf(sin(TAU * 92.0 * t)) * on
		lp += (x - lp) * 0.1
		lp2 += (lp - lp2) * 0.1
		buf[i] = lp2
	return Sfx._wav(buf, 0.5)


## Низкий хриплый рык врага.
static func growl(variant: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1300 + variant
	var dur := rng.randf_range(0.9, 1.3)
	var buf := _buf(dur)
	var bp := Sfx.Svf.new(rng.randf_range(240.0, 340.0), 1.2)
	var bp2 := Sfx.Svf.new(rng.randf_range(550.0, 700.0), 1.5)
	var f0 := rng.randf_range(50.0, 70.0)
	var am_f := rng.randf_range(11.0, 17.0)
	var ph := 0.0
	for i in buf.size():
		var t := float(i) / RATE
		var w := rng.randf() * 2.0 - 1.0
		ph = fmod(ph + f0 * (1.0 + 0.15 * sin(t * 7.0 + variant)) / RATE, 1.0)
		var x := (ph * 2.0 - 1.0) * 0.6 + w * 0.5
		var am := 0.6 + 0.4 * sin(TAU * am_f * t)
		var env := smoothstep(0.0, 0.12, t) * (1.0 - smoothstep(dur * 0.6, dur, t))
		buf[i] = (bp.bp(x) + bp2.bp(x) * 0.3) * am * env
	return Sfx._wav(buf, 0.75)


## Падение тяжёлого тела + осыпающаяся крошка.
static func thud() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1400
	var buf := _buf(0.9)
	var lp1 := 0.0
	var lp2 := 0.0
	var grit := Sfx.Svf.new(2600.0, 0.7)
	for i in buf.size():
		var t := float(i) / RATE
		var w := rng.randf() * 2.0 - 1.0
		lp1 += (w - lp1) * 0.035
		lp2 += (lp1 - lp2) * 0.035
		var v := lp2 * 14.0 * (Sfx._env(t, 0.0, 0.003, 11.0) + 0.5 * Sfx._env(t, 0.13, 0.003, 14.0))
		var dens := 0.08 * Sfx._env(t, 0.02, 0.05, 3.5)
		var imp := rng.randf_range(-1.0, 1.0) if rng.randf() < dens else 0.0
		v += grit.bp(imp) * 0.6
		buf[i] = v
	return Sfx._wav(buf, 0.9)


## Подбор предмета: короткий шорох и лёгкий щелчок.
static func pickup() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1500
	var buf := _buf(0.18)
	var bp := Sfx.Svf.new(1500.0, 0.8)
	var bp2 := Sfx.Svf.new(2600.0, 1.5)
	for i in buf.size():
		var t := float(i) / RATE
		var w := rng.randf() * 2.0 - 1.0
		var env := sin(clampf(t / 0.12, 0.0, 1.0) * PI)
		buf[i] = bp.bp(w) * env * 0.5 + bp2.bp(1.0 if i == int(RATE * 0.1) else 0.0)
	return Sfx._wav(buf, 0.5)
