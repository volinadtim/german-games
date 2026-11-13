extends AudioStreamPlayer
## Фоновый гул заброшки: низкий шум + сетевое гудение ламп. Генерируется на лету.

const RATE := 22050.0

var playback: AudioStreamGeneratorPlayback
var lp := 0.0
var lp2 := 0.0
var ph := 0.0


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.3
	stream = gen
	volume_db = -6.0
	play()
	playback = get_stream_playback()


func _process(_delta: float) -> void:
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
