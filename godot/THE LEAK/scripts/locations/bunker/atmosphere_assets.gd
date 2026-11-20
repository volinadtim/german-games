@tool
extends Node3D
# Часть atmosphere.gd: константы, состояние, процедурные звуки и текстуры.
const Sfx := preload("res://scripts/core/sfx.gd")
const MothShader := preload("res://shaders/moth.gdshader")
const RATE := 22050

# из level.gd
const H := 3.2
const ZN := -9.0
const T := 0.3

var level: Node3D
var rng := RandomNumberGenerator.new()
var t := 0.0
var drips: Array = []          # [{pos, wait, phase, drop, splash, snd}]
var drip_snds: Array[AudioStreamWAV] = []
var far_player: AudioStreamPlayer3D
var far_snds: Array[AudioStreamWAV] = []
var far_wait := 0.0
var broken_base := Transform3D()


func _moth_tex() -> ImageTexture:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var body := Color(0.55, 0.5, 0.42)
	var wing := Color(0.95, 0.9, 0.8)
	for y in range(2, 7):
		img.set_pixel(3, y, body)
		img.set_pixel(4, y, body)
	for p in [Vector2i(1, 2), Vector2i(2, 2), Vector2i(0, 3), Vector2i(1, 3), Vector2i(2, 3), Vector2i(1, 4), Vector2i(2, 4),
			Vector2i(5, 2), Vector2i(6, 2), Vector2i(5, 3), Vector2i(6, 3), Vector2i(7, 3), Vector2i(5, 4), Vector2i(6, 4)]:
		img.set_pixelv(p, wing)
	return ImageTexture.create_from_image(img)


## Жужжание у лампы: тонкое «зз» крылышек с плавающей высотой и громкостью + слабый сетевой гул дросселя.
## Петля туда-обратно — без щелчков на стыке.
func _buzz_loop() -> AudioStreamWAV:
	var r := RandomNumberGenerator.new()
	r.seed = 77
	var n := RATE * 3
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ph := 0.0
	var hum := 0.0
	var amp := 0.5
	var amp_t := 0.5
	var drift := 0.0
	var f := Sfx.Svf.new(700.0, 0.8)
	for i in n:
		var tt := float(i) / RATE
		if i % 600 == 0:
			amp_t = r.randf_range(0.0, 1.0) if r.randf() < 0.7 else 0.0
		amp += (amp_t - amp) * 0.0015
		drift += (r.randf_range(-1.0, 1.0) - drift) * 0.001
		var fq := 210.0 + 30.0 * sin(tt * 4.1) + 60.0 * drift
		ph = fmod(ph + fq / RATE, 1.0)
		var saw := ph * 2.0 - 1.0
		hum = fmod(hum + 100.0 / RATE, 1.0)
		buf[i] = f.bp(saw) * amp * 1.5 + sin(hum * TAU) * 0.03
	return _loop_wav(buf, 0.6)


## «Плюх» капли в лужицу: короткий тон, скользящий вверх (как у пузырька), щелчок касания и мягкий хвост помещения.
func _drip_sound(variant: int) -> AudioStreamWAV:
	var r := RandomNumberGenerator.new()
	r.seed = 1200 + variant
	var n := int(RATE * 0.6)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var f0 := r.randf_range(900.0, 1400.0)
	var ph := 0.0
	var tail := 0.0
	var tail2 := 0.0
	for i in n:
		var tt := float(i) / RATE
		var fq := f0 * (1.0 + tt / 0.025)
		ph = fmod(ph + minf(fq, 4000.0) / RATE, 1.0)
		var tone := sin(ph * TAU) * Sfx._env(tt, 0.0, 0.001, 70.0)
		var click := (r.randf() * 2.0 - 1.0) * Sfx._env(tt, 0.0, 0.0005, 400.0) * 0.4
		var w := r.randf() * 2.0 - 1.0
		tail += (w - tail) * 0.25
		tail2 += (tail - tail2) * 0.3
		buf[i] = tone + click + tail2 * 0.06 * Sfx._env(tt, 0.004, 0.02, 7.0)
	return Sfx._wav(buf, 0.8)


## Шипение пара: шум в высокой полосе с медленно «дышащей» силой струи.
func _hiss_loop() -> AudioStreamWAV:
	var r := RandomNumberGenerator.new()
	r.seed = 88
	var n := RATE * 4
	var buf := PackedFloat32Array()
	buf.resize(n)
	var f1 := Sfx.Svf.new(3200.0, 0.6)
	var f2 := Sfx.Svf.new(1600.0, 0.7)
	var g := 0.6
	var gt := 0.6
	for i in n:
		if i % 2000 == 0:
			gt = r.randf_range(0.35, 1.0)
		g += (gt - g) * 0.0006
		var w := r.randf() * 2.0 - 1.0
		buf[i] = (f1.bp(w) + f2.bp(w) * 0.4) * g
	return _loop_wav(buf, 0.5)


## Далёкий лязг железа: несколько негармоничных призвуков, срезанных фильтром, и длинный размытый хвост.
func _far_clank(variant: int) -> AudioStreamWAV:
	var r := RandomNumberGenerator.new()
	r.seed = 1300 + variant
	var n := int(RATE * 2.5)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var parts := []
	var base := r.randf_range(180.0, 320.0)
	for k in 5:
		parts.append([base * [1.0, 1.59, 2.31, 3.17, 4.4][k] * r.randf_range(0.97, 1.03), r.randf_range(0.0, 1.0), r.randf_range(3.0, 9.0) + k * 2.0])
	var hits := [0.0]
	if r.randf() < 0.6:
		hits.append(r.randf_range(0.15, 0.4))
	var lp := 0.0
	var tail := 0.0
	var tail2 := 0.0
	for i in n:
		var tt := float(i) / RATE
		var v := 0.0
		for h in hits:
			var e := Sfx._env(tt, h, 0.002, 1.0)
			if e <= 0.0:
				continue
			for p in parts:
				v += sin(TAU * p[0] * (tt - h) + p[1]) * exp(-(tt - h) * p[2]) * (0.7 if h > 0.0 else 1.0)
		lp += (v - lp) * 0.12            # далеко — верхи съедены
		var w := r.randf() * 2.0 - 1.0
		tail += (w - tail) * 0.04
		tail2 += (tail - tail2) * 0.05
		buf[i] = lp * 0.25 + tail2 * 1.2 * Sfx._env(tt, 0.01, 0.15, 1.6)
	return Sfx._wav(buf, 0.8)


## Стон трубы где-то в толще бетона: низкий тон, медленно плывущий по высоте, с шершавой модуляцией.
func _far_groan(variant: int) -> AudioStreamWAV:
	var r := RandomNumberGenerator.new()
	r.seed = 1400 + variant
	var dur := r.randf_range(2.2, 3.2)
	var n := int(RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var f0 := r.randf_range(55.0, 80.0)
	var f1 := f0 * r.randf_range(0.75, 1.3)
	var ph := 0.0
	var rough := 0.0
	var lp := 0.0
	for i in n:
		var tt := float(i) / RATE
		var x := tt / dur
		var fq := lerpf(f0, f1, smoothstep(0.0, 1.0, x)) + sin(tt * 5.0) * 2.0
		ph = fmod(ph + fq / RATE, 1.0)
		rough += (r.randf_range(-1.0, 1.0) - rough) * 0.01
		var v := (sin(ph * TAU) + 0.4 * sin(ph * TAU * 2.0) + 0.2 * sin(ph * TAU * 3.0)) * (0.8 + rough * 1.5)
		lp += (v - lp) * 0.08
		var env := sin(x * PI) * sin(x * PI)
		buf[i] = lp * env
	return Sfx._wav(buf, 0.7)


## Глухой гул, будто где-то далеко осела плита.
func _far_rumble() -> AudioStreamWAV:
	var r := RandomNumberGenerator.new()
	r.seed = 1500
	var n := int(RATE * 3.0)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var l1 := 0.0
	var l2 := 0.0
	var l3 := 0.0
	for i in n:
		var tt := float(i) / RATE
		var w := r.randf() * 2.0 - 1.0
		l1 += (w - l1) * 0.02
		l2 += (l1 - l2) * 0.02
		l3 += (l2 - l3) * 0.05
		buf[i] = l3 * Sfx._env(tt, 0.0, 0.4, 1.3)
	return Sfx._wav(buf, 0.8)


## Пятно с рваным краем: шум, обрезанный по кругу; крупные «пиксели», как у остальных текстур.
func _blob_tex(seed_: int) -> ImageTexture:
	var n := FastNoiseLite.new()
	n.seed = seed_
	n.frequency = 0.12
	n.fractal_octaves = 2
	const S := 32
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	for y in S:
		for x in S:
			var r := Vector2(x - S / 2.0 + 0.5, y - S / 2.0 + 0.5).length() / (S / 2.0)
			var v := 1.0 - r + n.get_noise_2d(x, y) * 0.55
			var a := 1.0 if v > 0.35 else (0.5 if v > 0.22 else 0.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var tex := ImageTexture.create_from_image(img)
	return tex


func _loop_wav(buf: PackedFloat32Array, gain: float) -> AudioStreamWAV:
	var n := buf.size()
	var peak := 0.0001
	for v in buf:
		peak = maxf(peak, absf(v))
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(buf[i] / peak * gain, -1.0, 1.0) * 32000.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = RATE
	st.data = data
	st.loop_mode = AudioStreamWAV.LOOP_PINGPONG
	st.loop_begin = 0
	st.loop_end = n
	return st
