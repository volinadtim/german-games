extends RefCounted
## Символы автомата KILLBOX: фрукты, алмаз, семёрка, шестёрка. Рисуются кодом в любой CanvasItem
## (лента барабана и доска выплат — через SubViewport).
## Стиль — «нарисовано тушью»: толстый тёмный контур, два-три плоских тона без градиентов, блик точкой,
## у вишни и семёрки — потёки, лимон с гнильцой, у шестёрки в петле тлеет красный глаз.

const IDS := ["cherry", "lemon", "plum", "grape", "diamond", "seven", "six"]
const NAMES := {
	"cherry": "Вишня", "lemon": "Лимон", "plum": "Слива", "grape": "Виноград",
	"diamond": "Алмаз", "seven": "Семёрка", "six": "Шестёрка",
}
const INK := Color(0.09, 0.05, 0.04)


static func draw(ci: CanvasItem, id: String, r: Rect2) -> void:
	var c := r.get_center()
	var s := minf(r.size.x, r.size.y)
	var w := maxf(s * 0.055, 2.0)       # толщина контура
	match id:
		"cherry":
			var top := c + Vector2(s * 0.08, -s * 0.36)
			var a := c + Vector2(-s * 0.18, s * 0.12)
			var b := c + Vector2(s * 0.2, s * 0.16)
			for p in [a, b]:
				_stroke(ci, [p + Vector2(0, -s * 0.12), (p + top) / 2.0 + Vector2(-s * 0.03, 0), top], s * 0.05, w, Color(0.3, 0.28, 0.1))
			_leaf(ci, top, top + Vector2(s * 0.28, -s * 0.04), s * 0.09, w, Color(0.3, 0.4, 0.14))
			_ball(ci, a, s * 0.16, w, Color(0.62, 0.05, 0.07), Color(0.36, 0.02, 0.04))
			_ball(ci, b, s * 0.16, w, Color(0.62, 0.05, 0.07), Color(0.36, 0.02, 0.04))
			_drip(ci, b + Vector2(s * 0.03, s * 0.15), s * 0.13, s * 0.035, w, Color(0.5, 0.03, 0.05))
		"lemon":
			var pts := PackedVector2Array()
			for k in 28:
				var ang := TAU * k / 28.0
				var rx := s * 0.34 * (1.0 + 0.16 * pow(absf(cos(ang)), 10.0))
				pts.append(c + Vector2(cos(ang) * rx, sin(ang) * s * 0.24).rotated(-0.25))
			_poly(ci, pts, w, Color(0.52, 0.42, 0.08))
			ci.draw_colored_polygon(_scaled(pts, c + Vector2(-s * 0.05, -s * 0.04), 0.78), Color(0.8, 0.68, 0.18))
			# гнильца: тёмные пятна
			for p in [Vector2(0.12, 0.06), Vector2(0.2, -0.02), Vector2(0.05, 0.12)]:
				ci.draw_circle(c + p * s, s * 0.035, Color(0.3, 0.27, 0.08))
			ci.draw_rect(Rect2(c + Vector2(-s * 0.16, -s * 0.1), Vector2(s * 0.06, s * 0.04)), Color(0.98, 0.9, 0.55))
		"plum":
			var p := c + Vector2(0, s * 0.05)
			_stroke(ci, [p + Vector2(0, -s * 0.26), p + Vector2(s * 0.05, -s * 0.4)], s * 0.045, w, Color(0.3, 0.22, 0.1))
			_ball(ci, p, s * 0.29, w, Color(0.42, 0.16, 0.46), Color(0.24, 0.07, 0.28))
			ci.draw_arc(p + Vector2(s * 0.06, 0), s * 0.2, -1.1, 1.1, 10, Color(0.2, 0.05, 0.24), w * 0.6)
			_leaf(ci, p + Vector2(s * 0.03, -s * 0.3), p + Vector2(-s * 0.24, -s * 0.38), s * 0.08, w, Color(0.3, 0.4, 0.14))
		"grape":
			var berries: Array[Vector2] = []
			for k in 9:
				var row: int = [0, 0, 0, 1, 1, 1, 2, 2, 3][k]
				var col: int = [0, 1, 2, 0, 1, 2, 0, 1, 0][k]
				var cnt: int = [3, 3, 3, 3, 3, 3, 2, 2, 1][k]
				berries.append(c + Vector2((col - (cnt - 1) / 2.0) * s * 0.17, (row - 1.2) * s * 0.155))
			_stroke(ci, [c + Vector2(0, -s * 0.3), c + Vector2(s * 0.05, -s * 0.43)], s * 0.045, w, Color(0.3, 0.22, 0.1))
			# сначала все контуры, потом заливки — гроздь читается одним силуэтом
			for p in berries:
				ci.draw_circle(p, s * 0.095 + w, INK)
			for p in berries:
				ci.draw_circle(p, s * 0.095, Color(0.24, 0.32, 0.08))
				ci.draw_circle(p + Vector2(-s * 0.018, -s * 0.018), s * 0.065, Color(0.45, 0.58, 0.16))
			_leaf(ci, c + Vector2(s * 0.02, -s * 0.34), c + Vector2(s * 0.3, -s * 0.38), s * 0.09, w, Color(0.3, 0.4, 0.14))
		"diamond":
			var pts := PackedVector2Array([c + Vector2(-s * 0.36, -s * 0.1), c + Vector2(-s * 0.2, -s * 0.3),
				c + Vector2(s * 0.2, -s * 0.3), c + Vector2(s * 0.36, -s * 0.1), c + Vector2(0, s * 0.38)])
			_poly(ci, pts, w, Color(0.2, 0.48, 0.6))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.36, -s * 0.1), c + Vector2(-s * 0.2, -s * 0.3), c + Vector2(0, -s * 0.3), c + Vector2(-s * 0.1, -s * 0.1)]), Color(0.45, 0.78, 0.88))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.1, -s * 0.1), c + Vector2(s * 0.12, -s * 0.1), c + Vector2(0, s * 0.38)]), Color(0.32, 0.64, 0.78))
			for e in [[Vector2(-0.36, -0.1), Vector2(0.36, -0.1)], [Vector2(-0.1, -0.1), Vector2(0, 0.38)], [Vector2(0.12, -0.1), Vector2(0, 0.38)], [Vector2(0, -0.3), Vector2(-0.1, -0.1)], [Vector2(0, -0.3), Vector2(0.12, -0.1)]]:
				ci.draw_line(c + e[0] * s, c + e[1] * s, INK, w * 0.5)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.2, -s * 0.24), Vector2(s * 0.06, s * 0.06)), Color(0.95, 1.0, 1.0))
		"seven":
			var pts := PackedVector2Array([c + Vector2(-0.32, -0.38) * s, c + Vector2(0.34, -0.38) * s, c + Vector2(0.34, -0.22) * s,
				c + Vector2(0.02, 0.4) * s, c + Vector2(-0.22, 0.4) * s, c + Vector2(0.1, -0.2) * s, c + Vector2(-0.32, -0.2) * s])
			_poly(ci, pts, w * 1.3, Color(0.7, 0.06, 0.05))
			# светлая кромка сверху и тень по стойке
			ci.draw_line(c + Vector2(-0.28, -0.33) * s, c + Vector2(0.3, -0.33) * s, Color(0.95, 0.35, 0.2), w * 0.8)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0.27, -0.2) * s, c + Vector2(0.33, -0.22) * s, c + Vector2(0.02, 0.4) * s, c + Vector2(-0.05, 0.4) * s]), Color(0.42, 0.02, 0.03))
			# трещина и потёки
			ci.draw_polyline(PackedVector2Array([c + Vector2(-0.12, -0.38) * s, c + Vector2(-0.08, -0.31) * s, c + Vector2(-0.13, -0.26) * s, c + Vector2(-0.09, -0.2) * s]), INK, w * 0.5)
			_drip(ci, c + Vector2(-0.24, -0.2) * s, s * 0.16, s * 0.03, w, Color(0.62, 0.05, 0.05))
			_drip(ci, c + Vector2(0.18, -0.2) * s, s * 0.1, s * 0.028, w, Color(0.62, 0.05, 0.05))
		"six":
			var ink := Color(0.42, 0.02, 0.03)
			var fill := Color(0.12, 0.09, 0.09)
			var loop := c + Vector2(0, s * 0.14)
			var curve := _bezier(loop + Vector2(-s * 0.21, 0), c + Vector2(-s * 0.26, -s * 0.42), c + Vector2(s * 0.2, -s * 0.36), 10)
			ci.draw_arc(loop, s * 0.2, 0, TAU, 24, ink, s * 0.17)
			ci.draw_polyline(curve, ink, s * 0.17)
			ci.draw_arc(loop, s * 0.2, 0, TAU, 24, fill, s * 0.1)
			ci.draw_polyline(curve, fill, s * 0.1)
			# тлеющий глаз в петле
			ci.draw_circle(loop, s * 0.06, Color(0.5, 0.03, 0.03))
			ci.draw_circle(loop, s * 0.03, Color(1.0, 0.35, 0.15))


## Шарик ягоды: контур, тень, основной тон чуть выше-левее, квадратный блик.
static func _ball(ci: CanvasItem, p: Vector2, rad: float, w: float, fill: Color, shade: Color) -> void:
	ci.draw_circle(p, rad + w, INK)
	ci.draw_circle(p, rad, shade)
	ci.draw_circle(p + Vector2(-rad * 0.16, -rad * 0.16), rad * 0.78, fill)
	ci.draw_rect(Rect2(p + Vector2(-rad * 0.55, -rad * 0.55), Vector2(rad * 0.28, rad * 0.28)), fill.lightened(0.55))


## Многоугольник с тёмным контуром.
static func _poly(ci: CanvasItem, pts: PackedVector2Array, w: float, fill: Color) -> void:
	var closed := pts.duplicate()
	closed.append(pts[0])
	ci.draw_polyline(closed, INK, w * 2.0)
	for p in pts:
		ci.draw_circle(p, w, INK)
	ci.draw_colored_polygon(pts, fill)


## Линия с контуром (черенок, стебель).
static func _stroke(ci: CanvasItem, pts: Array, width: float, w: float, col: Color) -> void:
	var pa := PackedVector2Array(pts)
	ci.draw_polyline(pa, INK, width + w * 2.0)
	ci.draw_polyline(pa, col, width)


static func _leaf(ci: CanvasItem, a: Vector2, b: Vector2, wid: float, w: float, col: Color) -> void:
	var n := (b - a).orthogonal().normalized() * wid
	var pts := PackedVector2Array([a, (a + b) / 2.0 + n, b, (a + b) / 2.0 - n * 0.4])
	_poly(ci, pts, w * 0.8, col)
	ci.draw_line(a, b, INK, w * 0.5)


## Потёк: полоска вниз с каплей на конце.
static func _drip(ci: CanvasItem, from: Vector2, length: float, wid: float, w: float, col: Color) -> void:
	var to := from + Vector2(0, length)
	ci.draw_line(from, to, INK, wid + w * 2.0)
	ci.draw_circle(to, wid * 1.3 + w, INK)
	ci.draw_line(from, to, col, wid)
	ci.draw_circle(to, wid * 1.3, col)


static func _scaled(pts: PackedVector2Array, center: Vector2, k: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(center + (p - center) * k)
	return out


static func _bezier(a: Vector2, b: Vector2, c: Vector2, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / n
		out.append(a.lerp(b, t).lerp(b.lerp(c, t), t))
	return out
