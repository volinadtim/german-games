extends Node
## Выносливость игрока (промпт 16.11 03:03). Только у локального игрока (в сети — у каждого своя).
## Бег (Shift) тратит, прыжок и рывок — немного. Стоит потратить ниже порога UNLOCK (любым из
## этих действий) — дальше тратить нельзя, даже если бросил сразу: нужно сначала восстановить
## стамину обратно до UNLOCK, и только тогда снова можно тратить (промпт 18.11 02:48).
## Восстановление после короткой паузы, стоя быстрее, чем на ходу.
## Полоска над хотбаром: появляется при трате, плавно гаснет, когда полная; красная ниже порога. F10 прячет (CanvasLayer).
## Звука дыхания нет (убран, промпт 04:14).

const DRAIN := 1.0 / 7.0        # полная полоска — ~7 с бега
const JUMP_COST := 0.15      # прыжок после слайда (как было)
const JUMP_COST_PLAIN := 0.11  # обычный прыжок чуть дешевле (14:36)
const DASH_COST := 0.2     # рывок (dash.gd)
const REGEN_WALK := 1.25 / 10.0 # на ходу — ~8 с до полной (+25%, 14:36)
const REGEN_IDLE := 1.25 / 5.0  # стоя — ~4 с (+25%)
const REGEN_DELAY := 0.9        # пауза перед восстановлением
const UNLOCK := 0.25            # после истощения бег снова можно с 25%
const Perks := preload("res://scripts/systems/perks.gd")

var player   # player.gd (родитель)
var value := 1.0
var exhausted := false
var delay := 0.0
var alpha := 0.0
var layer: CanvasLayer
var ui: Control


func _ready() -> void:
	player = get_parent()
	# в машине игрок выключен (car_drive.gd: PROCESS_MODE_DISABLED) — выносливость всё равно тикает (промпт 16.11 21:41)
	process_mode = Node.PROCESS_MODE_PAUSABLE
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


func can_sprint() -> bool:
	return not exhausted and value > 0.0


func can_jump() -> bool:
	return not exhausted and value >= JUMP_COST_PLAIN


func jump(cost: float = JUMP_COST_PLAIN) -> void:
	value = maxf(value - cost / Perks.stamina_k(), 0.0)
	delay = REGEN_DELAY
	if value < UNLOCK:
		exhausted = true


func can_dash() -> bool:
	return not exhausted and value >= DASH_COST


## подкат (слайд): стоит в 3 раза дешевле рывка
func slide() -> void:
	value = maxf(value - DASH_COST / 3.0 / Perks.stamina_k(), 0.0)
	delay = REGEN_DELAY
	if value < UNLOCK:
		exhausted = true


func dash() -> void:
	value = maxf(value - DASH_COST / Perks.stamina_k(), 0.0)
	delay = REGEN_DELAY
	if value < UNLOCK:
		exhausted = true


func tick(delta: float, sprinting: bool, moving: bool) -> void:
	if sprinting:
		value -= DRAIN / Perks.stamina_k() * delta
		delay = REGEN_DELAY
		if value <= 0.0:
			value = 0.0
			exhausted = true   # стамина кончилась в ноль — принудительно останавливаем бег
	else:
		if value < DASH_COST:
			exhausted = true   # блокируем только если не хватает даже на рывок (0.2)
		if delay > 0.0:
			delay -= delta
		else:
			value = minf(value + (REGEN_WALK if moving else REGEN_IDLE) * Perks.stamina_k() * delta, 1.0)
	if exhausted and value >= UNLOCK:
		exhausted = false


func _process(delta: float) -> void:
	if player != null and player.process_mode == Node.PROCESS_MODE_DISABLED:
		tick(delta, false, false)   # сидит в машине — отдыхает, как стоя
	var show: bool = value < 0.999 and player != null and bool(player.active)
	alpha = move_toward(alpha, 1.0 if show else 0.0, delta * (4.0 if show else 1.2))
	ui.visible = alpha > 0.01
	if ui.visible:
		ui.queue_redraw()


## Тонкая полоска чуть выше хотбара (хотбар hud.gd: ячейки 64, отступ 18; заряд удара — под прицелом, player_combat.gd).
func _draw_bar() -> void:
	var sz := ui.size
	var w := 160.0
	var h := 4.5
	var x0 := sz.x / 2.0 - w / 2.0
	var y0 := sz.y - 64.0 - 18.0 - 14.0   # 04:25: чуть выше
	var a := alpha * 0.8
	var col := Color(0.95, 0.45, 0.35) if (exhausted or value < UNLOCK) else Color(0.92, 0.9, 0.82)
	ui.draw_rect(Rect2(x0 - 1, y0 - 1, w + 2, h + 2), Color(0, 0, 0, 0.45 * a))
	ui.draw_rect(Rect2(x0, y0, w, h), Color(1, 1, 1, 0.08 * a))
	ui.draw_rect(Rect2(x0, y0, w * value, h), Color(col.r, col.g, col.b, 0.85 * a))
	# метка порога, с которого можно бежать (всегда видна, не только когда выдохся — 18.11 02:18)
	ui.draw_rect(Rect2(x0 + w * UNLOCK - 0.5, y0 - 1, 1, h + 2), Color(1, 1, 1, 0.5 * a))
