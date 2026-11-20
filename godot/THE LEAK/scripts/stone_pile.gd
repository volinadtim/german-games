extends StaticBody3D
## Кучка камней (промпт 14.11 19:22): E — взять 1 камень. В кучке 3–5 камней, пустая исчезает. Камни не пересекаются.
## Сколько осталось — в сейве (game.gd: stone_piles). Интерфейс для game.gd: get_prompt(game), interact(game).

const LAYER := 2048   # слой кучек: только для луча взаимодействия
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
	# булыжники не пересекаются (промпт 22:53): нижний ряд — по кругу без касаний, верхний ложится сверху
	# (сплюснутые сферы — эллипсоиды с полуосями r, hh, r; поворот только вокруг вертикали — форма та же)
	var placed: Array = []   # [центр, r, hh]
	for k in 5:
		var rr := r.randf_range(0.065, 0.1) if k < 4 else r.randf_range(0.06, 0.08)
		var hh := rr * r.randf_range(0.6, 0.82)
		var pos := Vector3.ZERO
		var ok := false
		if k < 4:
			for t in 40:
				var ang := r.randf() * TAU
				var rad := r.randf_range(0.06, 0.24)
				pos = Vector3(cos(ang) * rad, hh, sin(ang) * rad)
				ok = true
				for q in placed:
					if Vector2(pos.x - q[0].x, pos.z - q[0].z).length() < rr + q[1] + 0.006:
						ok = false
						break
				if ok:
					break
		if not ok:
			pos = Vector3(r.randf_range(-0.03, 0.03), hh, r.randf_range(-0.03, 0.03))
			pos.y = _rest_y(pos, rr, hh, placed)
		placed.append([pos, rr, hh])
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = rr
		sm.height = hh * 2.0
		sm.radial_segments = 7
		sm.rings = 3
		mi.mesh = sm
		var m := mat.duplicate() as StandardMaterial3D
		m.albedo_color = mat.albedo_color * r.randf_range(0.8, 1.15)
		mi.material_override = m
		mi.position = pos
		mi.rotation = Vector3(0.0, r.randf() * TAU, 0.0)
		add_child(mi)
		rocks.append(mi)
	rocks.reverse()   # верхний камень — первый
	shape = CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.6, 0.3, 0.6)
	shape.shape = bs
	shape.position.y = 0.15
	add_child(shape)
	# не мешает проходу (промпт 03:34): свой слой, игрок и враги (маска 1) проходят сквозь;
	# луч E в game.gd смотрит и этот слой
	collision_layer = LAYER
	collision_mask = 0
	set_left(left)


func get_prompt(_g) -> String:
	return "[F] Взять камень (%d)" % left if left > 0 else ""


func interact(g) -> void:
	if left <= 0:
		return
	if g.inv.add("stone", 1) > 0:
		g.hud.toast("Нет места")
		return
	g.hud.toast("+ Камень", Color(0.85, 0.85, 0.8))
	g.play_ui("thud", -14.0, 1.4)
	set_left(left - 1)


## Сколько камней осталось; видно столько же булыжников (последний — вся кучка), пустая кучка пропадает.
func set_left(n: int) -> void:
	left = maxi(n, 0)
	var shown := mini(left, rocks.size())
	for k in rocks.size():
		rocks[k].visible = k >= rocks.size() - shown
	if shape:
		shape.set_deferred("disabled", left <= 0)


## Высота центра камня (полуоси r, hh) в точке pos, чтобы он лёг на уже уложенные и не врезался в них.
static func _rest_y(pos: Vector3, rr: float, hh: float, placed: Array) -> float:
	var lo := hh
	if not _hits(Vector3(pos.x, lo, pos.z), rr, hh, placed):
		return lo
	var hi := lo + 0.4
	for i in 14:
		var mid := (lo + hi) * 0.5
		if _hits(Vector3(pos.x, mid, pos.z), rr, hh, placed):
			lo = mid
		else:
			hi = mid
	return hi + 0.003


## Пересекается ли эллипсоид с уложенными: точки поверхности одного внутри другого (в обе стороны).
static func _hits(c: Vector3, rr: float, hh: float, placed: Array) -> bool:
	for q in placed:
		if _pts_inside(c, rr, hh, q[0], q[1], q[2]) or _pts_inside(q[0], q[1], q[2], c, rr, hh):
			return true
	return false


static func _pts_inside(c: Vector3, rr: float, hh: float, o: Vector3, orr: float, ohh: float) -> bool:
	for la in 7:
		var th := PI * (float(la) / 6.0 - 0.5)
		for lo in 10:
			var ph := TAU * float(lo) / 10.0
			var p := c + Vector3(cos(th) * cos(ph) * rr, sin(th) * hh, cos(th) * sin(ph) * rr)
			var d := p - o
			if (d.x * d.x + d.z * d.z) / (orr * orr) + d.y * d.y / (ohh * ohh) < 1.0:
				return true
	return false
