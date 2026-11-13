extends Node
## Фонарик (фишка): F — вкл/выкл. Батарейка садится (~2.5 мин на полный заряд),
## на последних 15% свет слабеет и мигает. Батарейка из лута заряжает полностью.

const DRAIN := 1.0 / 150.0
const ENERGY := 2.4

var game  # game.gd
var light: SpotLight3D
var on := false
var charge := 0.6
var blink := 0.0


func attach(cam: Camera3D) -> void:
	light = SpotLight3D.new()
	light.position = Vector3(0.0, -0.04, -0.05)
	light.spot_range = 15.0
	light.spot_angle = 27.0
	light.spot_angle_attenuation = 0.9
	light.light_color = Color(1.0, 0.86, 0.66)
	light.light_energy = ENERGY
	light.shadow_enabled = true
	light.visible = false
	cam.add_child(light)


func toggle() -> void:
	if not on and charge <= 0.0:
		game.hud.toast("Батарейка села")
		game.play_ui("click", -16.0)
		return
	on = not on
	light.visible = on
	game.play_ui("click", -14.0)


func recharge() -> void:
	charge = 1.0


func _process(delta: float) -> void:
	if light == null:
		return
	if on:
		charge = maxf(charge - DRAIN * delta, 0.0)
		if charge <= 0.0:
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
