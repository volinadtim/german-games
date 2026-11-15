@tool
extends "res://scripts/level/surface_build.gd"
## Выход из бункера и поверхность.
##   Из восточного торца коридора (x = 12) — проём, за ним лестничный марш вверх (по ступеням — пологий пандус
##   для коллизии) и бетонная будка-выход на поляне. Поляна с центром CENTER, по краям холмы, мрачное красное небо.
##   Окружение (свет, туман, небо) плавно переключается, когда камера выходит наружу, — внутри бункера остаётся темно.
## Создаётся из level.gd (_ready).


func _ready() -> void:
	name = "Surface"
	rng.seed = 91
	hn.seed = 5
	hn.frequency = 0.045
	hn.fractal_octaves = 2
	hn2.seed = 9
	hn2.frequency = 0.11
	hn2.fractal_octaves = 1
	wall_mat = level.wall_mat
	floor_mat = level.floor_mat
	grass_mat = ShaderMaterial.new()
	grass_mat.shader = GrassShader
	for p in ["noise_big", "noise_big_px", "noise_fine_px", "noise_cell_px"]:
		grass_mat.set_shader_parameter(p, wall_mat.get_shader_parameter(p))
	_stairs()
	_hut()
	_ground()
	_tufts()
	_ruins()
	_sky_and_sun()
	if not Engine.is_editor_hint():
		_wind()


## 0 — внутри бункера, 1 — снаружи. В проходе лестницы — плавно по мере подъёма.
func _outside(p: Vector3) -> float:
	if p.x > X_WALL - 0.3 and p.x < X_OUT + 0.5 and absf(p.z) < 2.2:
		return smoothstep(HUT_X0, X_OUT - 0.5, p.x)
	if p.y > G - 0.5:
		return 1.0
	return 0.0


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var k := _outside(cam.global_position)
	out_k = lerpf(out_k, k, 1.0 - exp(-3.0 * delta))
	_apply_env(out_k)
	_feed_wind()


# ---------- ветер снаружи ----------

func _wind() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.3
	wind = AudioStreamPlayer.new()
	wind.stream = gen
	wind.volume_db = -60.0
	add_child(wind)
	wind.play()
	wind_pb = wind.get_stream_playback()


func _feed_wind() -> void:
	if wind_pb == null:
		return
	var n := wind_pb.get_frames_available()
	for i in n:
		w_t += 1.0 / 22050.0
		var g := 0.55 + 0.3 * sin(w_t * 0.31) + 0.15 * sin(w_t * 0.83 + 1.0)
		var w := randf() * 2.0 - 1.0
		w_lp += (w - w_lp) * (0.02 + 0.03 * g)
		w_lp2 += (w_lp - w_lp2) * 0.15
		var s := w_lp2 * 3.0 * g
		wind_pb.push_frame(Vector2(s, s))
