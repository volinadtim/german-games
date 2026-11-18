extends Node
## Фонарик (фишка). Промпт 18.11 02:27: работает только в руке — взять его в руку (хотбар или слот руки)
## и нажать кнопку мыши этой руки (ЛКМ — левая, ПКМ — правая). Убрали из руки — гаснет, даже если забыли
## выключить. Индикатора заряда нет: ориентир — мерцание света на последних процентах.
## В «Казуальном» мерцаний нет, батарейка садится в 2 раза медленнее и меняется сама из сумки.

const DRAIN := 1.0 / 225.0   # полный заряд ~3.75 мин (в казуальном — вдвое дольше)
const ENERGY := 3.0
const BLINK_FROM := 0.22     # с этого заряда свет мерцает — пора менять батарейку

var game  # game.gd
var light: SpotLight3D
var on := false
var charge := 0.6
var blink := 0.0


func attach(cam: Camera3D) -> void:
	light = SpotLight3D.new()
	light.position = Vector3(0.0, -0.04, -0.05)
	light.spot_range = 18.0
	light.spot_angle = 27.0
	light.spot_angle_attenuation = 0.9
	light.light_color = Color(1.0, 0.86, 0.66)
	light.light_energy = ENERGY
	light.shadow_enabled = true
	light.visible = false
	cam.add_child(light)


## В какой руке фонарик: "left" / "right" / "" (не в руке — не светит).
func hand() -> String:
	if game == null or game.inv == null:
		return ""
	for sl in ["right", "left"]:
		if game.inv.equip[sl] == "flashlight":
			return sl
	return ""


## Кнопка руки с фонариком: вкл/выкл.
func toggle() -> void:
	if hand() == "":
		game.hud.toast("Фонарик светит только в руке — возьми его в руку")
		return
	if not on and charge <= 0.0 and not _auto_battery():
		game.hud.toast("Батарейка села — нужна новая")
		game.play_ui("click", -16.0)
		return
	on = not on
	light.visible = on
	game.play_ui("click", -14.0)


func recharge() -> void:
	charge = 1.0


## Казуальный режим (промпт 18.11 00:52): села батарейка — сама ставится новая из сумки.
func _auto_battery() -> bool:
	if not game.casual() or game.inv.count("battery") == 0:
		return false
	game.inv.remove("battery", 1)
	charge = 1.0
	game.hud.toast("Новая батарейка (осталось %d)" % game.inv.count("battery"), Color(0.9, 0.85, 0.55))
	return true


func _process(delta: float) -> void:
	if light == null:
		return
	var casual: bool = game.casual()
	if on and hand() == "":
		on = false   # убрали из руки (или потеряли) — гаснет сам
	if not on:
		light.visible = false
		return
	light.visible = true
	charge = maxf(charge - DRAIN * (0.5 if casual else 1.0) * delta, 0.0)
	if charge <= 0.0 and not _auto_battery():
		on = false
		light.visible = false
		game.hud.toast("Фонарик погас — батарейка села")
		return
	if casual:
		light.light_energy = ENERGY   # в казуальном свет ровный, без мерцаний и подсказок
		return
	var e := ENERGY * clampf(charge * 5.0, 0.4, 1.0)
	if charge < BLINK_FROM:
		blink -= delta
		if blink <= 0.0:
			blink = randf_range(0.03, 0.4)
		if blink < 0.06:
			e *= 0.15
	light.light_energy = e
