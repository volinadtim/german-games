extends StaticBody3D
## Кучка камней (промпт 14.11 19:22): E — взять 1 камень. В кучке 3–5 камней, пустая исчезает.
## Сколько осталось — в сейве (game.gd: stone_piles). Интерфейс для game.gd: get_prompt(game), interact(game).

var game
var left := 4
var seed_ := 0
var rocks: Array = []        # видимые камни, убираются по одному
var shape: CollisionShape3D


func _ready() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 9100 + seed_
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.41, 0.38)
	mat.roughness = 0.95
	# 6 булыжников горкой: сверху — те, что берутся первыми
	for k in 6:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = r.randf_range(0.07, 0.12)
		sm.height = sm.radius * r.randf_range(1.2, 1.7)
		sm.radial_segments = 7
		sm.rings = 3
		mi.mesh = sm
		var m := mat.duplicate() as StandardMaterial3D
		m.albedo_color = mat.albedo_color * r.randf_range(0.8, 1.15)
		mi.material_override = m
		var ang := r.randf() * TAU
		var rad := 0.0 if k == 5 else r.randf_range(0.08, 0.22)
		mi.position = Vector3(cos(ang) * rad, sm.height * 0.35 + (0.1 if k == 5 else 0.0), sin(ang) * rad)
		mi.rotation = Vector3(r.randf_range(-0.4, 0.4), r.randf() * TAU, r.randf_range(-0.4, 0.4))
		add_child(mi)
		rocks.append(mi)
	rocks.reverse()   # верхний камень — первый
	shape = CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.6, 0.3, 0.6)
	shape.shape = bs
	shape.position.y = 0.15
	add_child(shape)
	set_left(left)


func get_prompt(_g) -> String:
	return "[E] Взять камень (%d)" % left if left > 0 else ""


func interact(g) -> void:
	if left <= 0:
		return
	if g.inv.add("stone", 1) > 0:
		g.hud.toast("Сумка полна")
		return
	g.hud.toast("+ Камень", Color(0.85, 0.85, 0.8))
	g.play_ui("thud", -14.0, 1.4)
	set_left(left - 1)


## Сколько камней осталось; видно столько же булыжников (последний — вся кучка), пустая кучка пропадает.
func set_left(n: int) -> void:
	left = maxi(n, 0)
	var show := 6 if left >= 5 else left
	for k in rocks.size():
		rocks[k].visible = k >= rocks.size() - show
	if shape:
		shape.set_deferred("disabled", left <= 0)
