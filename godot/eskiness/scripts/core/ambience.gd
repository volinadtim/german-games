extends AudioStreamPlayer
## Фоновый гул заброшки: низкий шум + сетевое гудение ламп. Генерируется на лету.
## Звучит только внутри (бункер, подвал): снаружи плавно гаснет — там ветер (surface.gd, _feed_wind).
## Внутри на шине Master включается лёгкое эхо (реверб), снаружи выключается (промпт 17.11 02:50).
## out_k — общий плавный коэффициент «снаружи» (0 — внутри, 1 — на улице), его читают шаги игрока.

const RATE := 22050.0
const HUM_DB := -18.0
const REVERB_WET := 0.14

static var out_k := 0.0

var playback: AudioStreamGeneratorPlayback
var lp := 0.0
var lp2 := 0.0
var ph := 0.0
var surface: Node
var reverb: AudioEffectReverb
var reverb_idx := -1


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.3
	stream = gen
	volume_db = HUM_DB
	play()
	playback = get_stream_playback()
	_setup_reverb()


func _setup_reverb() -> void:
	var bi := AudioServer.get_bus_index("Master")
	for e in AudioServer.get_bus_effect_count(bi):
		if AudioServer.get_bus_effect(bi, e) is AudioEffectReverb:
			reverb = AudioServer.get_bus_effect(bi, e)
			reverb_idx = e
	if reverb == null:
		reverb = AudioEffectReverb.new()
		reverb.room_size = 0.42
		reverb.damping = 0.6
		reverb.spread = 0.8
		reverb.hipass = 0.15
		reverb.predelay_msec = 35.0
		reverb.predelay_feedback = 0.25
		reverb.dry = 1.0
		reverb.wet = REVERB_WET
		AudioServer.add_bus_effect(bi, reverb)
		reverb_idx = AudioServer.get_bus_effect_count(bi) - 1


## Насколько камера снаружи: спрашиваем у поверхности (surface.gd: _outside), её ищем один раз.
func _outside_now() -> float:
	if surface == null or not is_instance_valid(surface):
		surface = get_tree().root.find_child("Surface", true, false)
		if surface == null or not surface.has_method("_outside"):
			surface = null
			return 0.0
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return 0.0
	return surface._outside(cam.global_position)


func _process(delta: float) -> void:
	out_k = lerpf(out_k, _outside_now(), 1.0 - exp(-2.0 * delta))
	var inside := 1.0 - out_k
	volume_db = HUM_DB + linear_to_db(maxf(inside, 0.001))
	if reverb:
		reverb.wet = REVERB_WET * inside
		AudioServer.set_bus_effect_enabled(0, reverb_idx, inside > 0.02)
	if playback == null:
		return
	var n := playback.get_frames_available()
	for i in n:
		var w := randf() * 2.0 - 1.0
		lp += (w - lp) * 0.02
		lp2 += (lp - lp2) * 0.05
		ph = fmod(ph + TAU * 50.0 / RATE, TAU)
		var s := lp2 * 2.5 + sin(ph) * 0.03 + sin(ph * 2.0) * 0.02 + sin(ph * 3.0) * 0.008
		playback.push_frame(Vector2(s, s))
