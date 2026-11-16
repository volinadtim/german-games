extends Node
## Выносливость игрока (промпт 16.11 03:03). Только у локального игрока (в сети — у каждого своя).
## Бег (Shift) тратит, прыжок — немного. На нуле бег заблокирован до UNLOCK.
## Восстановление после короткой паузы, стоя быстрее, чем на ходу.
## Полоска над хотбаром: появляется при трате, плавно гаснет, когда полная. F10 прячет (CanvasLayer).
## Тяжёлое дыхание при истощении — тихое; в противогазе глуше и ниже (шина «MaskBreath» из gasmask.gd).

const Sfx := preload("res://scripts/core/sfx.gd")
const DRAIN := 1.0 / 7.0        # полная полоска — ~7 с бега
const JUMP_COST := 0.07
const REGEN_WALK := 1.0 / 10.0  # на ходу — ~10 с до полной
const REGEN_IDLE := 1.0 / 5.0   # стоя — ~5 с
const REGEN_DELAY := 0.9        # пауза перед восстановлением
const UNLOCK := 0.25            # после истощения бег снова можно с 25%

var player   # player.gd (родитель)
var value := 1.0
var exhausted := false
var delay := 0.0
var alpha := 0.0
var pant := 0.0                 # 0..1 — насколько тяжело дышим
var layer: CanvasLayer
var ui: Control
var voice: AudioStreamPlayer
var breaths: Array = []
var breath_t := 0.0
var breath_n := 0


func _ready() -> void:
	player = get_parent()
	layer = CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	var m = get_tree().current_scene
	if m != null and "ui_hidden" in m and bool(m.ui_hidden):
		layer.set_meta("f10_vis", true)
		layer.visible = false
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.draw.connect(_draw_bar)
	layer.add_child(ui)
	voice = AudioStreamPlayer.new()
	voice.max_polyphony = 2
	add_child(voice)
	breaths = [Sfx.inhale(), Sfx.inhale(true)]


func can_sprint() -> bool:
	return not exhausted and value > 0.0


func can_jump() -> bool:
	return value >= JUMP_COST


func jump() -> void:
	value = maxf(value - JUMP_COST, 0.0)
	delay = REGEN_DELAY
	if value <= 0.0:
		exhausted = true


func tick(delta: float, sprinting: bool, moving: bool) -> void:
	if sprinting:
		value -= DRAIN * delta
		delay = REGEN_DELAY
		if value <= 0.0:
			value = 0.0
			exhausted = true
	elif delay > 0.0:
		delay -= delta
	else:
		value = minf(value + (REGEN_WALK if moving else REGEN_IDLE) * delta, 1.0)
	if exhausted and value >= UNLOCK:
		exhausted = false
	# дыхание: тяжёлое при истощении, затихает по мере восстановления
	var want := 1.0 if exhausted else clampf((0.3 - value) / 0.3, 0.0, 0.6)
	pant = move_toward(pant, want, delta * (1.5 if want > pant else 0.12))


func _process(delta: float) -> void:
	var show: bool = value < 0.999 and player != null and bool(player.active)
	alpha = move_toward(alpha, 1.0 if show else 0.0, delta * (4.0 if show else 1.2))
	ui.visible = alpha > 0.01
	if ui.visible:
		ui.queue_redraw()
	_breathe(delta)


func _breathe(delta: float) -> void:
	if pant < 0.05:
		breath_t = 0.0
		return
	breath_t -= delta
	if breath_t > 0.0:
		return
	breath_n += 1
	var exhale := breath_n % 2 == 0
	breath_t = lerpf(1.3, 0.42, pant) * randf_range(0.85, 1.15)
	var gm = player.game.gasmask if player != null and player.game != null else null
	var masked: bool = gm != null and bool(gm.worn)
	voice.bus = "MaskBreath" if masked and AudioServer.get_bus_index("MaskBreath") >= 0 else "Master"
	voice.stream = breaths[1 if exhale else 0]
	voice.volume_db = lerpf(-36.0, -24.0, pant) + (2.0 if masked else 0.0) + randf_range(-2.0, 1.5)
	voice.pitch_scale = (0.74 if masked else 1.05) * lerpf(1.0, 1.25, pant) * randf_range(0.93, 1.07)
	voice.play()


## Тонкая полоска чуть выше хотбара (хотбар hud.gd: ячейки 64, отступ 18; заряд удара — выше, player_combat.gd).
func _draw_bar() -> void:
	var sz := ui.size
	var w := 160.0
	var h := 3.0
	var x0 := sz.x / 2.0 - w / 2.0
	var y0 := sz.y - 64.0 - 18.0 - 8.0
	var a := alpha * 0.8
	var col := Color(0.95, 0.45, 0.35) if exhausted else Color(0.92, 0.9, 0.82)
	ui.draw_rect(Rect2(x0 - 1, y0 - 1, w + 2, h + 2), Color(0, 0, 0, 0.45 * a))
	ui.draw_rect(Rect2(x0, y0, w, h), Color(1, 1, 1, 0.08 * a))
	ui.draw_rect(Rect2(x0, y0, w * value, h), Color(col.r, col.g, col.b, 0.85 * a))
	if exhausted:
		# метка порога, с которого снова можно бежать
		ui.draw_rect(Rect2(x0 + w * UNLOCK - 0.5, y0 - 1, 1, h + 2), Color(1, 1, 1, 0.5 * a))
