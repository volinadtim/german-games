extends Node
## Фонарик (фишка): F — вкл/выкл. Батарейка садится (~3.75 мин на полный заряд, промпт 18.11 00:50),
## на последних 15% свет слабеет и мигает. Батарейка из лута заряжает полностью.

const DRAIN := 1.0 / 225.0
const ENERGY := 3.0

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


func toggle() -> void:
	if not on and game.inv.count("flashlight") == 0:
		game.hud.toast("Фонарика нет — он в магазине снаряжения")
		return
	if not on and charge <= 0.0 and not _auto_battery():
		game.hud.toast("Батарейка села")
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
	var have: bool = game.inv.count("flashlight") > 0
	game.hud.has_light = have
	if on and not have:
		on = false
		light.visible = false
	if on:
		charge = maxf(charge - DRAIN * delta, 0.0)
		if charge <= 0.0 and not _auto_battery():
			on = false
			light.visible = false
			game.hud.toast("Фонарик погас — батарейка села")
		var e := ENERGY * clampf(charge * 5.0, 0.4, 1.0)
		if charge < 0.15:
			blink -= delta
			if blink <= 0.0:
				blink = randf_range(0.03, 0.4)
			if blink < 0.06:
				e *= 0.15
		light.light_energy = e
	game.hud.set_battery(charge, on)
