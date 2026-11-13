extends Button
## Нарисованная иконка: "sound" (вкл/выкл звук) или "screen" (полный экран / окно).

var kind := "sound"


func _init(k := "sound") -> void:
	kind = k
	flat = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(48, 48)
	tooltip_text = "Звук" if k == "sound" else "Полный экран / окно (F11)"


func _draw() -> void:
	var c := Color(0.92, 0.91, 0.86, 1.0 if is_hovered() else 0.7)
	var o := size / 2.0
	draw_circle(o, 23.0, Color(0, 0, 0, 0.4))
	if kind == "sound":
		var pts := PackedVector2Array([
			o + Vector2(-12, -5), o + Vector2(-6, -5), o + Vector2(2, -12),
			o + Vector2(2, 12), o + Vector2(-6, 5), o + Vector2(-12, 5),
		])
		draw_colored_polygon(pts, c)
		if not AudioServer.is_bus_mute(0):
			draw_arc(o + Vector2(2, 0), 6.0, -0.9, 0.9, 12, c, 2.0, true)
			draw_arc(o + Vector2(2, 0), 11.0, -0.9, 0.9, 16, c, 2.0, true)
		else:
			draw_line(o + Vector2(6, -6), o + Vector2(14, 6), c, 2.5, true)
			draw_line(o + Vector2(14, -6), o + Vector2(6, 6), c, 2.5, true)
	else:
		var m := DisplayServer.window_get_mode()
		var full := m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				var s := Vector2(sx, sy)
				if full:
					# «свернуть»: уголки смотрят внутрь
					var p := o + s * 4.0
					draw_line(p, p + Vector2(sx * 7.0, 0), c, 2.5)
					draw_line(p, p + Vector2(0, sy * 7.0), c, 2.5)
				else:
					# «развернуть»: уголки по краям
					var p := o + s * 11.0
					draw_line(p, p - Vector2(sx * 7.0, 0), c, 2.5)
					draw_line(p, p - Vector2(0, sy * 7.0), c, 2.5)
