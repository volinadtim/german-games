extends RefCounted
## Символы автомата KILLBOX: фрукты, алмаз, семёрка, шестёрка. Рисуются кодом в любой CanvasItem
## (лента барабана и доска выплат — через SubViewport).

const IDS := ["cherry", "lemon", "plum", "grape", "diamond", "seven", "six"]
const NAMES := {
	"cherry": "Вишня", "lemon": "Лимон", "plum": "Слива", "grape": "Виноград",
	"diamond": "Алмаз", "seven": "Семёрка", "six": "Шестёрка",
}


static func draw(ci: CanvasItem, id: String, r: Rect2) -> void:
	var c := r.get_center()
	var s := minf(r.size.x, r.size.y)
	match id:
		"cherry":
			var stem := Color(0.25, 0.4, 0.15)
			ci.draw_line(c + Vector2(-s * 0.18, s * 0.08), c + Vector2(s * 0.05, -s * 0.32), stem, s * 0.05)
			ci.draw_line(c + Vector2(s * 0.2, s * 0.12), c + Vector2(s * 0.05, -s * 0.32), stem, s * 0.05)
			var leaf := PackedVector2Array([c + Vector2(s * 0.05, -s * 0.32), c + Vector2(s * 0.3, -s * 0.38), c + Vector2(s * 0.12, -s * 0.24)])
			ci.draw_colored_polygon(leaf, Color(0.3, 0.55, 0.2))
			for p in [c + Vector2(-s * 0.18, s * 0.18), c + Vector2(s * 0.2, s * 0.22)]:
				ci.draw_circle(p, s * 0.16, Color(0.45, 0.02, 0.05))
				ci.draw_circle(p, s * 0.13, Color(0.78, 0.08, 0.1))
				ci.draw_circle(p + Vector2(-s * 0.05, -s * 0.05), s * 0.035, Color(1, 0.7, 0.7))
		"lemon":
			var pts := PackedVector2Array()
			for k in 32:
				var a := TAU * k / 32.0
				var rx := s * 0.36 * (1.0 + 0.12 * pow(absf(cos(a)), 8.0))
				pts.append(c + Vector2(cos(a) * rx, sin(a) * s * 0.25))
			ci.draw_colored_polygon(pts, Color(0.95, 0.8, 0.15))
			ci.draw_circle(c + Vector2(-s * 0.1, -s * 0.08), s * 0.05, Color(1, 0.95, 0.6))
		"plum":
			ci.draw_circle(c + Vector2(0, s * 0.04), s * 0.3, Color(0.3, 0.1, 0.35))
			ci.draw_circle(c + Vector2(0, s * 0.04), s * 0.26, Color(0.5, 0.2, 0.55))
			ci.draw_arc(c + Vector2(s * 0.04, s * 0.04), s * 0.2, -1.2, 1.2, 12, Color(0.38, 0.12, 0.42), s * 0.03)
			ci.draw_circle(c + Vector2(-s * 0.1, -s * 0.06), s * 0.05, Color(0.8, 0.6, 0.85))
			ci.draw_line(c + Vector2(0, -s * 0.24), c + Vector2(s * 0.06, -s * 0.36), Color(0.3, 0.25, 0.1), s * 0.04)
		"grape":
			for k in 9:
				var row: int = [0, 0, 0, 1, 1, 1, 2, 2, 3][k]
				var col: int = [0, 1, 2, 0, 1, 2, 0, 1, 0][k]
				var cnt: int = [3, 3, 3, 3, 3, 3, 2, 2, 1][k]
				var p := c + Vector2((col - (cnt - 1) / 2.0) * s * 0.17, (row - 1.3) * s * 0.16)
				ci.draw_circle(p, s * 0.1, Color(0.18, 0.28, 0.08))
				ci.draw_circle(p, s * 0.085, Color(0.45, 0.65, 0.2))
			ci.draw_line(c + Vector2(0, -s * 0.3), c + Vector2(s * 0.04, -s * 0.42), Color(0.35, 0.25, 0.1), s * 0.04)
		"diamond":
			var top := c + Vector2(0, -s * 0.22)
			var pts := PackedVector2Array([c + Vector2(-s * 0.36, -s * 0.08), c + Vector2(-s * 0.2, -s * 0.28),
				c + Vector2(s * 0.2, -s * 0.28), c + Vector2(s * 0.36, -s * 0.08), c + Vector2(0, s * 0.36)])
			ci.draw_colored_polygon(pts, Color(0.3, 0.75, 0.95))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.36, -s * 0.08), c + Vector2(s * 0.36, -s * 0.08), c + Vector2(0, s * 0.36)]), Color(0.15, 0.5, 0.8))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.12, -s * 0.08), c + Vector2(s * 0.12, -s * 0.08), c + Vector2(0, s * 0.36)]), Color(0.45, 0.85, 1.0))
			ci.draw_line(top + Vector2(-s * 0.1, 0), top + Vector2(s * 0.05, 0), Color(1, 1, 1, 0.8), s * 0.03)
		"seven", "six":
			var f := ThemeDB.fallback_font
			var txt := "7" if id == "seven" else "6"
			var fs := int(s * 0.95)
			var col := Color(0.9, 0.1, 0.08) if id == "seven" else Color(0.12, 0.1, 0.1)
			var outline := Color(0.98, 0.8, 0.25) if id == "seven" else Color(0.75, 0.05, 0.05)
			var base := Vector2(r.position.x, c.y + s * 0.33)
			ci.draw_string_outline(f, base, txt, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, int(s * 0.1), outline)
			ci.draw_string(f, base, txt, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, col)
