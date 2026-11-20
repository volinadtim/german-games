extends CanvasLayer
## Карта-зарисовывалка (промпт 20.11 18:42): продаётся в лагере у озера (shop_model.gd: TIER 2).
## Пока предмет "sketch_map" есть у игрока (сумка/руки), карта зарисовывает клетки вокруг него — туман войны:
## видно только то, где он проходил. Всё в мировых координатах XZ — работает на любой локации и в бесшовном мире.
## M — открыть/закрыть, ЛКМ — метка, ПКМ — убрать метку, колесо — масштаб, перетаскивание — сдвиг.
## Сейв: game_save.gd, ключ "sketch_map" (to_save / from_save). Миникарту GPS (hud.gd) не трогает.

const CELL := 4.0            # сторона клетки, м
const REVEAL := 22.0         # радиус зарисовки вокруг игрока, м
const RAYS_PER_FRAME := 48   # сколько клеток зарисовывать за кадр
const MAX_MARKS := 40

var game                     # game.gd
var cells := {}              # Vector2i → int: тип (0 земля, 1 постройка/стена, 2 пусто) + 4 * высота в полуметрах
var marks: Array = []        # [x, z] — метки игрока в мировых координатах
var open := false
var queue: Array = []        # клетки, ждущие зарисовки
var queued := {}
var last_cell := Vector2i(1 << 30, 0)
var view_c := Vector2.ZERO   # центр вида (мир X, Z)
var zoom := 3.0              # пикселей на метр
var drag := false
var drag_moved := 0.0
var paint: Control


func _ready() -> void:
	layer = 40
	paint = Control.new()
	paint.set_anchors_preset(Control.PRESET_FULL_RECT)
	paint.mouse_filter = Control.MOUSE_FILTER_STOP
	paint.draw.connect(_draw_map)
	paint.gui_input.connect(_gui)
	add_child(paint)
	visible = false


## Есть ли карта у игрока (в сумке или в руках).
func owned() -> bool:
	return game != null and game.inv != null and game.inv.count("sketch_map") > 0


## Клетка карты для мировой точки X, Z.
func _cell(x: float, z: float) -> Vector2i:
	return Vector2i(int(floor(x / CELL)), int(floor(z / CELL)))


func _process(_dt: float) -> void:
	if game == null or game.player == null or not is_instance_valid(game.player) or not game.player.is_inside_tree():
		return
	if not owned():
		return
	var p: Vector3 = game.player.global_position
	var pc := _cell(p.x, p.z)
	if pc != last_cell:
		last_cell = pc
		var r := int(ceil(REVEAL / CELL))
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if dx * dx + dz * dz > r * r:
					continue
				var k := pc + Vector2i(dx, dz)
				if not cells.has(k) and not queued.has(k):
					queued[k] = true
					queue.append(k)
		if queue.size() > 3000:   # телепорт / быстрая езда — старые хвосты не нужны
			for i in queue.size() - 1500:
				queued.erase(queue[i])
			queue = queue.slice(queue.size() - 1500)
	var n := mini(RAYS_PER_FRAME, queue.size())
	if n > 0:
		var space: PhysicsDirectSpaceState3D = game.player.get_world_3d().direct_space_state
		for i in n:
			var k: Vector2i = queue.pop_back()
			queued.erase(k)
			if not cells.has(k):
				cells[k] = _probe(space, k, p.y)
	if open:
		paint.queue_redraw()


## Зарисовать клетку: луч сверху вниз — пол, крыша или стена (луч начался внутри неё).
func _probe(space: PhysicsDirectSpaceState3D, k: Vector2i, py: float) -> int:
	var c := Vector2((k.x + 0.5) * CELL, (k.y + 0.5) * CELL)
	var q := PhysicsRayQueryParameters3D.create(Vector3(c.x, py + 3.0, c.y), Vector3(c.x, py - 40.0, c.y))
	q.hit_from_inside = true
	q.exclude = [game.player.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return 2
	var hy: float = hit.position.y
	var nrm: Vector3 = hit.normal
	var typ := 1 if nrm.y < 0.7 else 0
	return typ + 4 * int(round(hy * 2.0))


## Открыть карту на клавишу M (если она куплена).
func _unhandled_input(e: InputEvent) -> void:
	if open or not _map_key(e):
		return
	if game == null or not game.alive or game.player == null or game.window_open():
		return
	if not owned():
		if game.hud:
			game.hud.toast("Нет карты — продаётся в лагере у озера", Color(0.9, 0.7, 0.4))
		return
	show_map()
	get_viewport().set_input_as_handled()


## Пока карта открыта: M / Esc закрывают.
func _input(e: InputEvent) -> void:
	if not open:
		return
	if _map_key(e) or (Controls.event(e, "ui_cancel") and not e.is_echo()):
		close()
		get_viewport().set_input_as_handled()


## Нажата клавиша карты (действие "world_map", без него — M).
func _map_key(e: InputEvent) -> bool:
	if e.is_echo() or not e.is_pressed():
		return false
	return Controls.event(e, "world_map")


## Открыть окно карты — по центру игрок.
func show_map() -> void:
	open = true
	visible = true
	var p: Vector3 = game.player.global_position
	view_c = Vector2(p.x, p.z)
	game.player.active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	paint.queue_redraw()


## Закрыть окно карты.
func close() -> void:
	if not open:
		return
	open = false
	visible = false
	drag = false
	if game and game.player and game.alive:
		game.player.active = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Мышь в окне: перетаскивание, метки, масштаб.
func _gui(e: InputEvent) -> void:
	var c := paint.size / 2.0
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				drag = true
				drag_moved = 0.0
			else:
				if drag and drag_moved < 6.0:
					_add_mark(view_c + (mb.position - c) / zoom)
				drag = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_remove_mark(mb.position)
		elif mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var wp := view_c + (mb.position - c) / zoom
			zoom = clampf(zoom * (1.2 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.2), 0.4, 14.0)
			view_c = wp - (mb.position - c) / zoom
		paint.queue_redraw()
	elif e is InputEventMouseMotion and drag:
		var mm := e as InputEventMouseMotion
		view_c -= mm.relative / zoom
		drag_moved += mm.relative.length()
		paint.queue_redraw()


## Поставить метку в мировой точке X, Z.
func _add_mark(w: Vector2) -> void:
	if marks.size() >= MAX_MARKS:
		if game.hud:
			game.hud.toast("Меток слишком много (%d) — убери лишние ПКМ" % MAX_MARKS, Color(0.9, 0.6, 0.4))
		return
	marks.append([w.x, w.y])


## Убрать ближайшую к экранной точке метку.
func _remove_mark(sp: Vector2) -> void:
	var c := paint.size / 2.0
	var best := -1
	var bd := 16.0
	for i in marks.size():
		var mp := c + (Vector2(float(marks[i][0]), float(marks[i][1])) - view_c) * zoom
		var d := mp.distance_to(sp)
		if d < bd:
			bd = d
			best = i
	if best >= 0:
		marks.remove_at(best)


## Рисунок карты: клетки, метки, игрок, подсказка.
func _draw_map() -> void:
	var sz := paint.size
	var f := ThemeDB.fallback_font
	paint.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.07, 0.06, 0.05, 0.95))
	var c := sz / 2.0
	var cs := CELL * zoom
	var paper := Color(0.86, 0.8, 0.64)
	for k in cells:
		var pos: Vector2 = c + (Vector2(k) * CELL - view_c) * zoom
		if pos.x > sz.x or pos.y > sz.y or pos.x < -cs or pos.y < -cs:
			continue
		var v: int = cells[k]
		var typ := posmod(v, 4)
		var col: Color
		if typ == 0:
			var hh: int = (v - typ) >> 2
			col = paper.darkened(0.07 * posmod(int(floor(hh / 3.0)), 3))   # полосы высоты по 1.5 м — как горизонтали
		elif typ == 1:
			col = Color(0.4, 0.31, 0.22)
		else:
			col = Color(0.42, 0.52, 0.6)
		paint.draw_rect(Rect2(pos, Vector2(cs + 0.6, cs + 0.6)), col)
	# метки
	for i in marks.size():
		var mp: Vector2 = c + (Vector2(float(marks[i][0]), float(marks[i][1])) - view_c) * zoom
		paint.draw_line(mp, mp + Vector2(0, -22), Color(0.15, 0.1, 0.05), 2.0)
		paint.draw_colored_polygon(PackedVector2Array([mp + Vector2(0, -22), mp + Vector2(14, -17), mp + Vector2(0, -12)]), Color(0.85, 0.12, 0.08))
		paint.draw_circle(mp, 3.0, Color(0.15, 0.1, 0.05))
		paint.draw_string_outline(f, mp + Vector2(4, 14), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 3, Color(0, 0, 0, 0.8))
		paint.draw_string(f, mp + Vector2(4, 14), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.9, 0.8))
	# игрок — стрелка по взгляду камеры
	if game and game.player and is_instance_valid(game.player):
		var p: Vector3 = game.player.global_position
		var pp: Vector2 = c + (Vector2(p.x, p.z) - view_c) * zoom
		var fw := Vector2(0, -1)
		var cam := get_viewport().get_camera_3d()
		if cam:
			var f3 := -cam.global_transform.basis.z
			if Vector2(f3.x, f3.z).length() > 0.01:
				fw = Vector2(f3.x, f3.z).normalized()
		var sd := Vector2(-fw.y, fw.x)
		var tri := PackedVector2Array([pp + fw * 12.0, pp - fw * 7.0 + sd * 7.0, pp - fw * 7.0 - sd * 7.0])
		paint.draw_colored_polygon(tri, Color(0.1, 0.55, 0.2))
		paint.draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Color(0, 0, 0, 0.8), 1.5)
	paint.draw_string_outline(f, Vector2(24, 40), "Карта", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, 5, Color(0, 0, 0, 0.8))
	paint.draw_string(f, Vector2(24, 40), "Карта", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, paper)
	var hint := "M / Esc — закрыть   ЛКМ — метка   ПКМ — убрать метку   колесо — масштаб   тащить — сдвиг"
	paint.draw_string_outline(f, Vector2(24, sz.y - 24), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color(0, 0, 0, 0.8))
	paint.draw_string(f, Vector2(24, sz.y - 24), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.85, 0.82, 0.72))


## Для сейва: клетки плоским массивом [x, z, v, ...] и метки.
func to_save() -> Dictionary:
	var flat: Array = []
	for k in cells:
		flat.append(k.x)
		flat.append(k.y)
		flat.append(cells[k])
	return {"c": flat, "m": marks.duplicate(true)}


## Из сейва (старые сейвы без карты — пусто).
func from_save(d: Dictionary) -> void:
	cells.clear()
	queue.clear()
	queued.clear()
	last_cell = Vector2i(1 << 30, 0)
	var flat: Array = d.get("c", [])
	var i := 0
	while i + 2 < flat.size():
		cells[Vector2i(int(flat[i]), int(flat[i + 1]))] = int(flat[i + 2])
		i += 3
	marks.clear()
	for m in d.get("m", []):
		if m is Array and m.size() >= 2:
			marks.append([float(m[0]), float(m[1])])
