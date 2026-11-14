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


## Страшный звук «тебя поймали на мухлеже» (промпт 14.11 17:26), ~3.5 с:
## глухой удар с гулом, под ним биения низкого дрона, сверху ползёт вверх визгливый расстроенный «струнный» кластер,
## в конце — хриплый выдох-шёпот. Всё в миноре и мимо нот.
static func dread() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6666
	var dur := 3.6
	var buf := _buf(dur)
	var lp := 0.0
	var bp := Sfx.Svf.new(1400.0, 3.0)
	var hiss := Sfx.Svf.new(2600.0, 1.4)
	var ph: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var detune := [1.0, 1.059, 1.414, 1.5]   # кластер: прима, малая секунда, тритон, квинта
	for i in buf.size():
		var t := float(i) / RATE
		var w := rng.randf() * 2.0 - 1.0
		var v := 0.0
		# удар: низкий «бум» с падающей частотой + шумовая вспышка
		var bf := 70.0 * exp(-t * 3.0) + 32.0
		v += sin(TAU * bf * t) * exp(-t * 2.2) * 0.9
		lp += (w - lp) * 0.05
		v += lp * 3.0 * exp(-t * 6.0)
		# дрон с биениями
		v += (sin(TAU * 41.0 * t) + sin(TAU * 43.3 * t)) * 0.18 * smoothstep(0.0, 0.6, t) * (1.0 - smoothstep(dur - 0.8, dur, t))
		# визгливый кластер, ползёт вверх и дрожит
		var rise := 380.0 * pow(2.0, t * 0.55) * (1.0 + 0.012 * sin(TAU * 6.5 * t))
		var cl := 0.0
		for k in 4:
			ph[k] = fmod(ph[k] + rise * float(detune[k]) / RATE, 1.0)
			cl += (ph[k] * 2.0 - 1.0)
		var ce := smoothstep(0.25, 1.6, t) * (1.0 - smoothstep(dur - 0.7, dur, t))
		v += bp.bp(cl * 0.5) * ce * 0.55
		# хриплый выдох-шёпот в конце
		var we := smoothstep(2.2, 2.7, t) * (1.0 - smoothstep(3.1, dur, t))
		v += hiss.bp(w) * we * (0.6 + 0.4 * sin(TAU * 9.0 * t)) * 0.7
		buf[i] = v
	return Sfx._wav(buf, 0.9)


## Старая машина заводится (car.gd), ~5.6 с: две неудачные попытки стартера «чух-чух-чух»
## (аккумулятор подсел — вторая медленнее), третья схватывает: мотор чихает, рокочет,
## перегазовка и неровный холостой ход.
const STARTER_CATCH := 3.55   # на какой секунде мотор завёлся (car.gd трясёт машину и пускает дым)
static func starter() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var dur := 5.6
	var buf := _buf(dur)
	var cranks := [[0.0, 0.85, 5.6], [1.25, 0.95, 4.6], [2.55, 1.0, 5.3]]   # начало, длительность, «чухов» в секунду
	var chuh := Sfx.Svf.new(520.0, 1.3)
	var body := Sfx.Svf.new(140.0, 1.6)
	var exh := Sfx.Svf.new(260.0, 1.1)
	var ph_m := 0.0
	var ph_c := 0.0
	var ph_e := 0.0
	var since := 1.0
	var lp := 0.0
	for i in buf.size():
		var t := float(i) / RATE
		var w := rng.randf() * 2.0 - 1.0
		var v := 0.0
		# стартер: визг моторчика, тормозится на каждом сжатии; «чух» — шумовой выдох после сжатия
		for c in cranks:
			var tl := t - float(c[0])
			if tl < 0.0 or tl > float(c[1]):
				continue
			var env := smoothstep(0.0, 0.05, tl) * (1.0 - smoothstep(float(c[1]) - 0.08, float(c[1]), tl))
			ph_c += float(c[2]) * (0.9 + 0.2 * tl) / RATE
			var comp := pow(0.5 + 0.5 * cos(TAU * ph_c), 6.0)          # 1 — поршень упёрся
			var fm := 190.0 * (1.0 - 0.35 * comp)
			ph_m = fmod(ph_m + fm / RATE, 1.0)
			var whine := sin(TAU * ph_m) + 0.5 * sin(TAU * ph_m * 2.0) + 0.25 * sin(TAU * ph_m * 3.0)
			var rel := pow(0.5 + 0.5 * cos(TAU * (ph_c - 0.18)), 10.0)  # сразу после сжатия
			v += whine * 0.16 * env * (0.6 + 0.4 * comp)
			v += chuh.bp(w) * rel * env * 1.6
			v += body.bp(w * rel) * env * 1.2
		# мотор: вспышки цилиндров — глухие толчки с шумом выхлопа
		if t > STARTER_CATCH:
			var te := t - STARTER_CATCH
			# сначала чихает редко, потом перегазовка и неровный холостой
			var ff := lerpf(9.0, 46.0, smoothstep(0.0, 0.7, te)) * (1.0 - 0.38 * smoothstep(0.9, 1.6, te))
			ff *= 1.0 + 0.08 * sin(TAU * 1.3 * te) + 0.05 * sin(TAU * 3.1 * te)
			ph_e += ff / RATE
			if ph_e >= 1.0:
				ph_e -= 1.0
				since = 0.0
				if rng.randf() < 0.07 and te > 0.6:
					since = 0.5       # пропуск зажигания — старый мотор
			since += 1.0 / RATE
			var thump := sin(TAU * 62.0 * since) * exp(-since * 38.0)
			var env_e := smoothstep(0.0, 0.08, te) * (1.0 - smoothstep(dur - 0.4, dur, t))
			lp += (w - lp) * 0.08
			v += (thump * 0.9 + exh.bp(w * exp(-since * 25.0)) * 1.5 + lp * 0.25) * env_e
		buf[i] = v
	return Sfx._wav(buf, 0.85)


## Рокот мотора на ходу: бесшовная петля 2 с (car.gd крутит её, поднимая pitch_scale при разгоне).
static func engine_loop() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4343
	var period := RATE / 30     # 30 вспышек в секунду: за 2 с ровно 60, петля сходится
	var total := RATE * 3
	var exh := Sfx.Svf.new(240.0, 1.1)
	var lp := 0.0
	var raw := PackedFloat32Array()
	raw.resize(total)
	for i in total:
		var since := float(i % period) / RATE
		var w := rng.randf() * 2.0 - 1.0
		lp += (w - lp) * 0.07
		var thump := sin(TAU * 58.0 * since) * exp(-since * 34.0)
		raw[i] = thump * 0.8 + exh.bp(w * exp(-since * 22.0)) * 1.4 + lp * 0.3
	# берём последние 2 с — фильтры уже «разогреты», края петли совпадают по фазе вспышек
	var n := RATE * 2
	var peak := 0.0001
	for i in n:
		peak = maxf(peak, absf(raw[total - n + i]))
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(raw[total - n + i] / peak * 0.8, -1.0, 1.0) * 32000.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = RATE
	st.stereo = false
	st.data = data
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_begin = 0
	st.loop_end = n
	return st
