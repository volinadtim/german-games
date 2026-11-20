extends Node
## Голосовой чат в сетевой игре (промпт 16.11 21:47): держишь X — микрофон слышат остальные.
## Узел /root/Net/Voip (у всех одинаковый путь — для rpc). Микрофон: AudioStreamMicrophone на заглушённой
## шине «VoipMic» с AudioEffectCapture; кадры сжимаются в моно 16 кГц int16 и уходят всем (через хоста).
## Голос другого игрока звучит из его модели (AudioStreamPlayer3D + AudioStreamGenerator), ник над головой
## зеленеет, пока он говорит. Нужен audio/driver/enable_input = true (project.godot).

const RATE := 16000.0
const BUS := "VoipMic"

static var voice_vol := 0.6   # ползунок «Громкость голоса» (menu.gd), 0..1

var net                       # /root/Net
var mic: AudioStreamPlayer
var capture: AudioEffectCapture
var talking := false
var src_pos := 0.0            # дробная позиция пересэмплирования (между кадрами)
const VOICE_CHUNK := 640      # байт = 20 мс при RATE 16 кГц, 16 бит
var vbuf := PackedByteArray() # накопленный звук до отправки
var layer: CanvasLayer
var badge: Label
var heard := {}               # peer_id -> сколько ещё подсвечивать ник (с)


func _ready() -> void:
	net = get_parent()
	process_mode = Node.PROCESS_MODE_ALWAYS
	# действие «voice» и его клавиша — из data/controls/bindings.cfg (Controls)
	var bi := AudioServer.get_bus_index(BUS)
	if bi < 0:
		AudioServer.add_bus()
		bi = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bi, BUS)
		AudioServer.set_bus_mute(bi, true)   # себя не слышим; захват идёт до заглушения
		AudioServer.add_bus_effect(bi, AudioEffectCapture.new())
	capture = AudioServer.get_bus_effect(bi, 0) as AudioEffectCapture
	layer = CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	badge = Label.new()
	badge.text = "● ГОЛОС"
	badge.add_theme_font_size_override("font_size", 18)
	badge.add_theme_color_override("font_color", Color(0.55, 1.0, 0.55))
	badge.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	badge.add_theme_constant_override("outline_size", 6)
	badge.position = Vector2(20, 20)
	badge.visible = false
	layer.add_child(badge)


func _in_game() -> bool:
	return net.active() and net.game != null and is_instance_valid(net.game)


func _typing() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


func _process(delta: float) -> void:
	_fade_nicks(delta)
	var want := _in_game() and Input.is_action_pressed("voice") and not _typing() and not get_tree().paused
	if want and mic == null:
		mic = AudioStreamPlayer.new()
		mic.stream = AudioStreamMicrophone.new()
		mic.bus = BUS
		add_child(mic)
		mic.play()
		capture.clear_buffer()
	if want != talking:
		if talking and vbuf.size() > 0 and net != null and net.peer:
			rpc("voice_pkt", vbuf)   # дослать хвост фразы
		vbuf = PackedByteArray()
		talking = want
		badge.visible = want
		capture.clear_buffer()
		src_pos = 0.0
	if not _in_game() and mic != null:
		mic.queue_free()   # вне сетевой игры микрофон не держим
		mic = null
	if not talking:
		if capture.get_frames_available() > 0:
			capture.clear_buffer()
		return
	var n := capture.get_frames_available()
	if n <= 0:
		return
	var frames := capture.get_buffer(n)
	var step := AudioServer.get_mix_rate() / RATE
	var out := PackedByteArray()
	out.resize(int(float(n) / step) * 2 + 4)
	var k := 0
	var p := src_pos
	while p < float(n) and k + 1 < out.size():
		var f: Vector2 = frames[int(p)]
		var s := clampf((f.x + f.y) * 0.5 * 1.6, -1.0, 1.0)   # чуть громче: микрофоны обычно тихие
		out.encode_s16(k, int(s * 32767.0))
		k += 2
		p += step
	src_pos = p - float(n)
	out.resize(k)
	# копим ~20 мс звука и шлём одним пакетом, а не пакет на каждый кадр (на 144 Гц — втрое меньше пакетов)
	vbuf.append_array(out)
	if vbuf.size() >= VOICE_CHUNK:
		rpc("voice_pkt", vbuf)
		vbuf = PackedByteArray()


@rpc("any_peer", "unreliable_ordered", "call_remote")
func voice_pkt(data: PackedByteArray) -> void:
	var id := multiplayer.get_remote_sender_id()
	var pp = net.puppets.get(id)
	if pp == null or not is_instance_valid(pp):
		return
	var sp: AudioStreamPlayer3D = pp.get_meta("voice") if pp.has_meta("voice") else null
	if sp == null or not is_instance_valid(sp):
		sp = AudioStreamPlayer3D.new()
		var g := AudioStreamGenerator.new()
		g.mix_rate = RATE
		g.buffer_length = 0.4
		sp.stream = g
		sp.position.y = 1.6
		sp.unit_size = 2.5      # тише и быстрее затухает с расстоянием (промпт 16.11 22:11)
		sp.max_distance = 22.0
		pp.add_child(sp)
		pp.set_meta("voice", sp)
	sp.volume_db = linear_to_db(maxf(voice_vol, 0.0001))
	if not sp.playing:
		sp.play()
	var pb := sp.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb == null:
		return
	var cnt := mini(data.size() >> 1, pb.get_frames_available())
	for i in cnt:
		var v := float(data.decode_s16(i * 2)) / 32767.0
		pb.push_frame(Vector2(v, v))
	heard[id] = 0.3
	if pp.has_meta("nick"):
		(pp.get_meta("nick") as Label3D).modulate = Color(0.55, 1.0, 0.55)


func _fade_nicks(delta: float) -> void:
	for id in heard.keys():
		heard[id] -= delta
		if heard[id] > 0.0:
			continue
		heard.erase(id)
		var pp = net.puppets.get(id)
		if pp != null and is_instance_valid(pp) and pp.has_meta("nick"):
			(pp.get_meta("nick") as Label3D).modulate = Color(0.95, 0.9, 0.8)
