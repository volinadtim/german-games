extends StaticBody3D
## Игровой автомат KILLBOX (слоты): E — крутка за 10 монет.
## Окно 3 ряда × 4 барабана. Барабаны — настоящие цилиндры с отпечатанной лентой символов,
## вращаются и останавливаются по очереди. 5 выигрышных линий (LINES): 3 ряда и 2 центральных мостика.
## На линии выигрывают одинаковые символы подряд слева направо: минимум 3, максимум 4.
##   3 шестёрки где угодно в окне — автомат забирает все монеты, оставляет 10 (выпадают редко).
##   3 семёрки подряд на линии — открывают сейф; если сейф уже открыт — 100 монет.
## 4 семёрки или 4 шестёрки в окне не выпадают никогда (исключены при генерации).
## Справа от автомата на стене — доска выплат. Автомат стоит в тёмной комнате и мерцает.

const Sym := preload("res://slot_symbols.gd")

const COST := 10
const REELS := 4
## лента барабана (одна на все барабаны, у каждого свой сдвиг): семёрки далеко друг от друга,
## поэтому в окне одного барабана больше одной семёрки не бывает
const STRIP := ["cherry", "seven", "lemon", "plum", "cherry", "grape", "six", "lemon", "seven", "cherry", "diamond", "plum"]
## линии: для каждого барабана слева направо — ряд (0 верх, 1 середина, 2 низ)
const LINES := [
	[1, 1, 1, 1], [0, 0, 0, 0], [2, 2, 2, 2],
	[1, 0, 0, 1], [1, 2, 2, 1],
]
## доля раскладов с тремя шестёрками, которые всё-таки остаются (остальные перебрасываются)
const SIX_KEEP := 0.35
## выплаты за линию: символ -> {сколько подряд слева: монет}
const PAY := {
	"cherry": {3: 15, 4: 40},
	"lemon": {3: 20, 4: 50},
	"plum": {3: 25, 4: 60},
	"grape": {3: 35, 4: 90},
	"diamond": {3: 60, 4: 200},
	"seven": {3: 100},
}
const R := 0.19            # радиус барабана
const RW := 0.125          # ширина барабана
const REEL_Y := 0.98
const REEL_Z := 0.07
const TEX := 128           # пикселей на символ в ленте
const K := 1.3             # во сколько раз автомат больше «базового»
const PED := 0.25          # высота подиума
const RIG_Z := 0.1         # сдвиг вперёд, чтобы задняя стенка не уходила в стену
## доска выплат на стене справа от автомата (в координатах автомата)
const BOARD_POS := Vector3(1.45, 1.6, -0.25)
const BOARD_PX := Vector2i(900, 980)
const BOARD_M := Vector2(1.35, 1.47)

var game  # game.gd (выставляет game.gd; в меню — null)
var busy := false
var reels: Array[Node3D] = []
var stops: Array[int] = [0, 0, 0, 0]
var last_cell: Array[int] = [0, 0, 0, 0]
var spinning: Array[bool] = [false, false, false, false]
var lever: Node3D
var bulbs: Array[StandardMaterial3D] = []
const USE_LEDS := false     # цветные RGB-огоньки по краям корпуса (убраны по просьбе, 19:27)
var leds: Array[StandardMaterial3D] = []
var rig: Node3D
var light: OmniLight3D
var screen: Label3D
var party := 0.0
var t := 0.0
var tick_t := 0.0
var snd: AudioStreamPlayer3D
var snd2: AudioStreamPlayer3D


func _ready() -> void:
	_build()
	_build_board()
	snd = AudioStreamPlayer3D.new()
	snd.position = Vector3(0, 1.0, 0.3)
	snd.unit_size = 4.0
	add_child(snd)
	snd2 = AudioStreamPlayer3D.new()
	snd2.position = Vector3(0, 1.0, 0.3)
	snd2.unit_size = 4.0
	add_child(snd2)
	for i in REELS:
		stops[i] = randi() % STRIP.size()
		reels[i].rotation.x = _angle_for(stops[i])


func _mat(c: Color, metal := 0.0, rough := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


## Перед автомата — +Z.
func _build() -> void:
	var body := _mat(Color(0.34, 0.035, 0.05), 0.45, 0.4)
	var trim := _mat(Color(0.75, 0.56, 0.22), 0.9, 0.28)
	var black := _mat(Color(0.015, 0.015, 0.015))
	# всё видимое — в rig: он увеличен в K раз и стоит на подиуме
	rig = Node3D.new()
	rig.scale = Vector3.ONE * K
	rig.position = Vector3(0, PED, RIG_Z)
	add_child(rig)
	_build_extras(body, trim, black)
	# корпус: низ, полость под барабаны (бока, задник, рамка окна), верх, вывеска
	_box(rig, Vector3(0.8, 0.8, 0.6), Vector3(0, 0.4, 0), body)
	for sx in [-1.0, 1.0]:
		_box(rig, Vector3(0.1, 0.4, 0.6), Vector3(0.35 * sx, 0.98, 0), body)
	_box(rig, Vector3(0.6, 0.4, 0.1), Vector3(0, 0.98, -0.25), black)
	_box(rig, Vector3(0.8, 0.04, 0.6), Vector3(0, 1.18, 0), body)
	_box(rig, Vector3(0.62, 0.05, 0.05), Vector3(0, 1.14, 0.275), trim)
	_box(rig, Vector3(0.62, 0.05, 0.05), Vector3(0, 0.82, 0.275), trim)
	_box(rig, Vector3(0.62, 0.035, 0.12), Vector3(0, 1.17, 0.21), black)
	_box(rig, Vector3(0.62, 0.035, 0.12), Vector3(0, 0.79, 0.21), black)
	for k in 3:
		_box(rig, Vector3(0.018, 0.28, 0.04), Vector3((k - 1) * 0.145, REEL_Y, 0.275), trim)
	for sx in [-1.0, 1.0]:
		_box(rig, Vector3(0.025, 0.32, 0.05), Vector3(0.3 * sx, REEL_Y, 0.275), trim)
	_box(rig, Vector3(0.86, 0.36, 0.66), Vector3(0, 1.38, 0), body)
	_box(rig, Vector3(0.88, 0.04, 0.68), Vector3(0, 1.2, 0), trim)
	_box(rig, Vector3(0.88, 0.04, 0.68), Vector3(0, 1.56, 0), trim)

	# барабаны: лента символов рисуется в SubViewport и натягивается на цилиндр
	var sv := SubViewport.new()
	sv.size = Vector2i(TEX, TEX * STRIP.size())
	sv.transparent_bg = false
	sv.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(sv)
	var art := Control.new()
	art.size = Vector2(sv.size)
	art.draw.connect(func() -> void:
		art.draw_rect(Rect2(Vector2.ZERO, art.size), Color(0.76, 0.72, 0.64))
		for i in STRIP.size():
			var r := Rect2(0, i * TEX, TEX, TEX)
			art.draw_rect(Rect2(0, i * TEX, TEX, 2), Color(0.7, 0.64, 0.55))
			Sym.draw(art, STRIP[i], r.grow(-14))
		# серая вуаль поверх ленты — символы блеклые, выцветшие
		art.draw_rect(Rect2(Vector2.ZERO, art.size), Color(0.55, 0.52, 0.48, 0.3)))
	sv.add_child(art)
	var reel_mat := StandardMaterial3D.new()
	reel_mat.albedo_texture = sv.get_texture()
	reel_mat.albedo_color = Color(0.82, 0.8, 0.77)
	reel_mat.roughness = 0.7
	reel_mat.emission_enabled = true
	reel_mat.emission_texture = sv.get_texture()
	reel_mat.emission = Color(0.85, 0.8, 0.72)
	reel_mat.emission_energy_multiplier = 0.16
	var mesh := _reel_mesh()
	for i in REELS:
		var r := MeshInstance3D.new()
		r.mesh = mesh
		r.material_override = reel_mat
		r.position = Vector3((i - 1.5) * 0.145, REEL_Y, REEL_Z)
		rig.add_child(r)
		reels.append(r)

	# вывеска
	var sign_l := Label3D.new()
	sign_l.text = "KILLBOX"
	sign_l.font_size = 72
	sign_l.pixel_size = 0.0021
	sign_l.outline_size = 8
	sign_l.outline_modulate = Color(0.15, 0.0, 0.0)
	sign_l.modulate = Color(1.0, 0.3, 0.15)
	sign_l.position = Vector3(0, 1.39, 0.335)
	rig.add_child(sign_l)
	screen = Label3D.new()
	screen.text = "КРУТКА — %d МОНЕТ" % COST
	screen.font_size = 40
	screen.pixel_size = 0.0009
	screen.outline_size = 0
	screen.width = 600.0
	screen.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	screen.modulate = Color(0.95, 0.78, 0.45)
	screen.position = Vector3(-0.05, 0.71, 0.316)
	rig.add_child(screen)
	_box(rig, Vector3(0.58, 0.1, 0.01), Vector3(-0.05, 0.71, 0.3), black)
	# лампочки по верху вывески
	for k in 9:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.3, 0.2, 0.1)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.55, 0.25)
		var b := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.022
		sm.height = 0.044
		b.mesh = sm
		b.material_override = m
		b.position = Vector3(-0.36 + k * 0.09, 1.6, 0.31)
		rig.add_child(b)
		bulbs.append(m)
	# прорезь для монет и лоток
	_box(rig, Vector3(0.08, 0.1, 0.02), Vector3(0.3, 0.71, 0.305), trim)
	_box(rig, Vector3(0.012, 0.06, 0.01), Vector3(0.3, 0.71, 0.318), black)
	_box(rig, Vector3(0.5, 0.06, 0.2), Vector3(0, 0.3, 0.36), trim)
	_box(rig, Vector3(0.46, 0.14, 0.02), Vector3(0, 0.36, 0.45), trim)
	# рычаг справа
	lever = Node3D.new()
	lever.position = Vector3(0.43, 0.9, 0.05)
	rig.add_child(lever)
	var rod := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.018
	cm.bottom_radius = 0.018
	cm.height = 0.45
	rod.mesh = cm
	rod.material_override = trim
	rod.position = Vector3(0.03, 0.22, 0)
	lever.add_child(rod)
	var ball := MeshInstance3D.new()
	var bs := SphereMesh.new()
	bs.radius = 0.05
	bs.height = 0.1
	ball.mesh = bs
	ball.material_override = _mat(Color(0.6, 0.08, 0.05), 0.2, 0.3)
	ball.position = Vector3(0.03, 0.46, 0)
	lever.add_child(ball)
	_box(rig, Vector3(0.06, 0.12, 0.12), Vector3(0.42, 0.9, 0.05), trim)

	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.5, 0.28)
	light.light_energy = 1.0
	light.omni_range = 6.0
	light.shadow_enabled = true
	light.position = Vector3(0, 1.3, 0.75)
	rig.add_child(light)

	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	var top := PED + 2.0 * K
	shape.size = Vector3(0.9 * K, top, 0.68 * K)
	cs.shape = shape
	cs.position = Vector3(0, top / 2.0, RIG_Z)
	add_child(cs)


## Подиум, надстройка «777» с лампами, цветные бегущие огни по бокам корпуса.
func _build_extras(body: Material, trim: Material, black: Material) -> void:
	# подиум (вне rig — в мировых метрах)
	var ped := _mat(Color(0.08, 0.06, 0.05), 0.3, 0.6)
	_box(self, Vector3(0.9 * K + 0.06, PED, 0.68 * K + 0.06), Vector3(0, PED / 2.0, RIG_Z), ped)
	_box(self, Vector3(0.9 * K + 0.08, 0.03, 0.68 * K + 0.08), Vector3(0, PED, RIG_Z), trim)
	# надстройка над вывеской
	_box(rig, Vector3(0.62, 0.32, 0.5), Vector3(0, 1.74, -0.02), body)
	_box(rig, Vector3(0.66, 0.035, 0.54), Vector3(0, 1.91, -0.02), trim)
	_box(rig, Vector3(0.5, 0.2, 0.01), Vector3(0, 1.74, 0.235), black)
	var crown := Label3D.new()
	crown.text = "777"
	crown.font_size = 96
	crown.pixel_size = 0.0019
	crown.outline_size = 10
	crown.outline_modulate = Color(0.3, 0.2, 0.0)
	crown.modulate = Color(1.0, 0.85, 0.3)
	crown.shaded = false
	crown.position = Vector3(0, 1.74, 0.245)
	rig.add_child(crown)
	# цветные огни: по передним рёбрам корпуса и вдоль надстройки
	var palette := [Color(1, 0.15, 0.1), Color(1, 0.55, 0.1), Color(1, 0.9, 0.2), Color(0.2, 1, 0.35), Color(0.2, 0.8, 1), Color(0.6, 0.3, 1)]
	var spots: Array = []
	for k in 14:
		var y := 0.06 + k * 0.105
		spots.append(Vector3(-0.415, y, 0.305))
		spots.append(Vector3(0.415, y, 0.305))
	for k in 7:
		spots.append(Vector3(-0.27 + k * 0.09, 1.86, 0.235))
	for i in (spots.size() if USE_LEDS else 0):
		var m := StandardMaterial3D.new()
		var col: Color = palette[(i / 2) % palette.size()]
		m.albedo_color = col.darkened(0.6)
		m.emission_enabled = true
		m.emission = col
		var bl := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.016
		sm.height = 0.032
		bl.mesh = sm
		bl.material_override = m
		bl.position = spots[i]
		rig.add_child(bl)
		leds.append(m)
	# хромированные полосы по бокам
	for sx in [-1.0, 1.0]:
		_box(rig, Vector3(0.012, 1.5, 0.02), Vector3(0.43 * sx, 0.78, 0.29), trim)


## Цилиндр барабана вдоль оси X с развёрткой: v = 0..1 по окружности (сверху вниз по ленте).
func _reel_mesh() -> ArrayMesh:
	var k := 48
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in k:
		var a0 := TAU * j / k
		var a1 := TAU * (j + 1) / k
		var p00 := Vector3(-RW / 2, -R * sin(a0), R * cos(a0))
		var p10 := Vector3(RW / 2, -R * sin(a0), R * cos(a0))
		var p01 := Vector3(-RW / 2, -R * sin(a1), R * cos(a1))
		var p11 := Vector3(RW / 2, -R * sin(a1), R * cos(a1))
		var n0 := Vector3(0, -sin(a0), cos(a0))
		var n1 := Vector3(0, -sin(a1), cos(a1))
		var v0 := float(j) / k
		var v1 := float(j + 1) / k
		for vert in [[p00, n0, Vector2(0, v0)], [p10, n0, Vector2(1, v0)], [p11, n1, Vector2(1, v1)],
				[p00, n0, Vector2(0, v0)], [p11, n1, Vector2(1, v1)], [p01, n1, Vector2(0, v1)]]:
			st.set_normal(vert[1])
			st.set_uv(vert[2])
			st.add_vertex(vert[0])
	return st.commit()


## Угол барабана, при котором символ i стоит в среднем ряду (выше — i-1, ниже — i+1).
func _angle_for(i: int) -> float:
	return -TAU * (i + 0.5) / STRIP.size()


## Доска выплат на стене справа от автомата.
func _build_board() -> void:
	var sv := SubViewport.new()
	sv.size = BOARD_PX
	sv.transparent_bg = false
	sv.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(sv)
	var art := Control.new()
	art.size = Vector2(sv.size)
	art.draw.connect(_draw_board.bind(art))
	sv.add_child(art)
	var frame := _mat(Color(0.75, 0.56, 0.22), 0.9, 0.3)
	var back := _mat(Color(0.1, 0.06, 0.04), 0.0, 0.9)
	var board := Node3D.new()
	board.position = BOARD_POS
	board.rotation.y = -0.12
	add_child(board)
	var bw := BOARD_M.x + 0.08
	_box(board, Vector3(bw, 1.56, 0.03), Vector3(0, 0, -0.012), back)
	for sy in [-1.0, 1.0]:
		_box(board, Vector3(bw, 0.03, 0.04), Vector3(0, 0.775 * sy, 0), frame)
	for sx in [-1.0, 1.0]:
		_box(board, Vector3(0.03, 1.58, 0.04), Vector3(bw / 2.0 * sx, 0, 0), frame)
	var q := QuadMesh.new()
	q.size = BOARD_M
	var m := StandardMaterial3D.new()
	m.albedo_texture = sv.get_texture()
	m.emission_enabled = true
	m.emission_texture = sv.get_texture()
	m.emission_energy_multiplier = 0.35
	m.roughness = 0.9
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.position.z = 0.007
	board.add_child(mi)


## Строка, ужатая по ширине: шрифт уменьшается, пока текст не влезет.
func _fit(ci: Control, pos: Vector2, text: String, width: float, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var f := ThemeDB.fallback_font
	var fs := size
	while fs > 10 and f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
		fs -= 1
	ci.draw_string(f, pos, text, align, width, fs, col)


func _draw_board(ci: Control) -> void:
	var w := 600.0          # левая колонка — выплаты, правая — линии
	var pad := 34.0
	var inner := w - pad * 2.0
	ci.draw_rect(Rect2(Vector2.ZERO, ci.size), Color(0.12, 0.05, 0.05))
	ci.draw_rect(Rect2(Vector2(10, 10), ci.size - Vector2(20, 20)), Color(0.85, 0.62, 0.25), false, 4.0)
	ci.draw_rect(Rect2(Vector2(18, 18), ci.size - Vector2(36, 36)), Color(0.85, 0.2, 0.15, 0.6), false, 2.0)
	_fit(ci, Vector2(pad, 82), "KILLBOX", inner, 64, Color(1.0, 0.35, 0.2), HORIZONTAL_ALIGNMENT_CENTER)
	_fit(ci, Vector2(pad, 124), "ТАБЛИЦА ВЫПЛАТ", inner, 30, Color(1.0, 0.82, 0.4), HORIZONTAL_ALIGNMENT_CENTER)
	_fit(ci, Vector2(pad, 158), "крутка %d монет · подряд слева направо на линии" % COST, inner, 20, Color(0.8, 0.72, 0.6), HORIZONTAL_ALIGNMENT_CENTER)
	var y := 184.0
	var text_col := Color(0.95, 0.9, 0.78)
	var rows := ["diamond", "grape", "plum", "lemon", "cherry"]
	for k in rows.size():
		var id: String = rows[k]
		if k % 2 == 0:
			ci.draw_rect(Rect2(pad - 8, y - 4, inner + 16, 92), Color(1, 1, 1, 0.04))
		var pays: Dictionary = PAY[id]
		Sym.draw(ci, id, Rect2(pad, y, 84, 84))
		var parts := PackedStringArray()
		for n in [4, 3, 2]:
			if pays.has(n):
				parts.append("×%d — %d" % [n, pays[n]])
		_fit(ci, Vector2(pad + 100, y + 54), "    ".join(parts), inner - 100, 30, text_col)
		y += 100.0
	y += 6.0
	ci.draw_line(Vector2(pad, y), Vector2(w - pad, y), Color(0.85, 0.62, 0.25, 0.7), 2.0)
	y += 18.0
	for k in 3:
		Sym.draw(ci, "seven", Rect2(pad + k * 62, y, 62, 62))
	_fit(ci, Vector2(pad + 200, y + 28), "×3 на линии — открывают сейф", inner - 200, 24, Color(1.0, 0.85, 0.4))
	_fit(ci, Vector2(pad + 200, y + 58), "сейф уже открыт — 100 монет", inner - 200, 22, text_col)
	y += 96.0
	for k in 3:
		Sym.draw(ci, "six", Rect2(pad + k * 62, y, 62, 62))
	_fit(ci, Vector2(pad + 200, y + 28), "×3 где угодно в окне —", inner - 200, 24, Color(1.0, 0.3, 0.2))
	_fit(ci, Vector2(pad + 200, y + 58), "автомат забирает всё, кроме 10", inner - 200, 22, Color(1.0, 0.3, 0.2))
	y += 92.0
	_fit(ci, Vector2(pad, y + 20), "4 семёрки и 4 шестёрки не выпадают никогда", inner, 19, Color(0.7, 0.62, 0.52), HORIZONTAL_ALIGNMENT_CENTER)
	# правая колонка: 9 линий схемами 4×3
	var x0 := w
	var cw := ci.size.x - w - pad
	ci.draw_line(Vector2(x0 - 4, 40), Vector2(x0 - 4, ci.size.y - 40), Color(0.85, 0.62, 0.25, 0.5), 2.0)
	_fit(ci, Vector2(x0, 82), "ЛИНИИ", cw, 44, Color(1.0, 0.82, 0.4), HORIZONTAL_ALIGNMENT_CENTER)
	_fit(ci, Vector2(x0, 120), "3 ряда и 2 мостика", cw, 20, Color(0.8, 0.72, 0.6), HORIZONTAL_ALIGNMENT_CENTER)
	var names := ["ряд", "ряд", "ряд", "мостик", "мостик"]
	var cell := 18.0
	for li in LINES.size():
		var gx := x0 + 14 + (li % 3) * 88.0
		var gy := 150.0 + (li / 3) * 128.0
		var line: Array = LINES[li]
		for c in 4:
			for r in 3:
				var on: bool = int(line[c]) == r
				ci.draw_rect(Rect2(gx + c * cell, gy + r * cell, cell - 2, cell - 2), Color(1.0, 0.45, 0.2) if on else Color(1, 1, 1, 0.08))
		for c in 3:
			var a := Vector2(gx + c * cell + cell / 2 - 1, gy + int(line[c]) * cell + cell / 2 - 1)
			var b := Vector2(gx + (c + 1) * cell + cell / 2 - 1, gy + int(line[c + 1]) * cell + cell / 2 - 1)
			ci.draw_line(a, b, Color(1.0, 0.85, 0.4), 2.0)
		_fit(ci, Vector2(gx, gy + 3 * cell + 22), "%d %s" % [li + 1, names[li]], 4 * cell + 8, 15, Color(0.85, 0.8, 0.7))
	var ry := 150.0 + 2 * 128.0 + 20
	for t_ in ["Выигрыш — 3 или 4", "одинаковых символа", "подряд слева направо", "на линии.", "", "Каждая линия платит", "отдельно — выигрыши", "складываются."]:
		_fit(ci, Vector2(x0 + 10, ry), t_, cw - 10, 21, Color(0.9, 0.84, 0.72))
		ry += 30.0


func get_prompt(_game) -> String:
	return "" if busy else "[E] Крутить KILLBOX (%d монет)" % COST


func interact(g) -> void:
	game = g
	if busy:
		return
	if not g.inv.remove("coin", COST):
		g.hud.toast("Нужно %d монет" % COST)
		g.play_at("buzz", global_position, -14.0)
		screen.text = "НУЖНО %d МОНЕТ" % COST
		return
	busy = true
	screen.text = "КРУТИТСЯ..."
	if g.has_method("cheat_check"):
		g.cheat_check()
	_roll_stops()
	g.play_at("coin", global_position + Vector3(0.0, 0.7, 0.0), -10.0)
	var tw := create_tween()
	tw.tween_property(lever, "rotation:x", 1.1, 0.18).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(lever, "rotation:x", 0.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for i in REELS:
		spinning[i] = true
		var cur := reels[i].rotation.x
		var target := _angle_for(stops[i])
		# барабан крутится вниз (угол растёт): минимум 3 оборота + по обороту на каждый следующий
		var turns := 3.0 + i
		target += TAU * ceil((cur - target) / TAU + turns)
		var rt := create_tween()
		rt.tween_interval(0.15 + i * 0.05)
		rt.tween_property(reels[i], "rotation:x", target, 1.3 + i * 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		rt.tween_callback(_reel_stopped.bind(i))


## Случайные остановки; 4 семёрки или 4 шестёрки в окне исключаем перебросом.
func _roll_stops() -> void:
	for attempt in 100:
		for i in REELS:
			stops[i] = randi() % STRIP.size()
		var g := grid()
		var sevens := 0
		var sixes := 0
		for row in g:
			sevens += row.count("seven")
			sixes += row.count("six")
		if sevens > 3 or sixes > 3:
			continue
		if sixes == 3 and randf() > SIX_KEEP:
			continue
		return


## Видимое окно: 3 ряда по 4 символа (сверху вниз).
func grid() -> Array:
	var n := STRIP.size()
	var rows: Array = []
	for r in 3:
		var row: Array = []
		for i in REELS:
			row.append(STRIP[(stops[i] + r - 1 + n) % n])
		rows.append(row)
	return rows


func _reel_stopped(i: int) -> void:
	spinning[i] = false
	if game:
		game.play_at("clunk", reels[i].global_position, -8.0)
	if not spinning.has(true):
		_payout()


func _process(delta: float) -> void:
	t += delta
	# лампочки: бегущий огонёк, при выигрыше — быстро мигают все
	party = maxf(party - delta, 0.0)
	for k in bulbs.size():
		var on: bool
		if party > 0.0:
			on = int(t * 10.0) % 2 == k % 2
		else:
			on = int(t * 3.0) % 3 != k % 3
		bulbs[k].emission_energy_multiplier = 1.6 if on else 0.15
	# цветные огни: волна снизу вверх, при выигрыше — вспышки
	for i in leds.size():
		var w := sin(t * 5.0 - float(i / 2) * 0.6)
		if party > 0.0:
			leds[i].emission_energy_multiplier = 2.2 if (int(t * 12.0) + i) % 3 == 0 else 0.3
		else:
			leds[i].emission_energy_multiplier = 0.4 + 1.4 * maxf(w, 0.0)
	# свечение мерцает и переливается от янтарного к красному
	var flick := 0.06 * sin(t * 2.3) + 0.04 * sin(t * 7.1) + (0.12 if randf() < 0.02 else 0.0)
	light.light_energy = 0.8 + flick + (0.35 * sin(t * 30.0) if party > 0.0 else 0.0)
	light.light_color = Color.from_hsv(0.045 + 0.03 * sin(t * 0.6), 0.75, 1.0)
	# тики при прохождении символов
	if busy and game:
		tick_t -= delta
		for i in REELS:
			if not spinning[i]:
				continue
			var cell := int(floor(reels[i].rotation.x * STRIP.size() / TAU))
			if cell != last_cell[i]:
				last_cell[i] = cell
				if tick_t <= 0.0:
					tick_t = 0.05
					snd.stream = game.snd["tick"][0]
					snd.volume_db = -17.0
					snd.pitch_scale = randf_range(0.9, 1.1)
					snd.play()


func _payout() -> void:
	busy = false
	var g := grid()
	var sixes := 0
	for row in g:
		sixes += row.count("six")
	if sixes >= 3:
		var have: int = game.inv.count("coin")
		var lost := maxi(have - 10, 0)
		if lost > 0:
			game.inv.remove("coin", lost)
		screen.text = "666 — KILLBOX ЗАБРАЛ %d" % lost
		game.hud.toast("Три шестёрки! Автомат забрал %d монет" % lost, Color(1.0, 0.35, 0.25))
		game.play_at("buzz", global_position, -6.0, 0.7)
		game.hud.hurt_flash(0.5)
		return
	var win := 0
	var sevens := false
	var won_lines := PackedStringArray()
	for li in LINES.size():
		var line: Array = LINES[li]
		var first: String = g[int(line[0])][0]
		var n := 1
		while n < REELS and g[int(line[n])][n] == first:
			n += 1
		if first == "seven" and n >= 3:
			sevens = true
			won_lines.append(str(li + 1))
		elif first != "seven" and PAY.has(first) and PAY[first].has(n):
			win += int(PAY[first][n])
			won_lines.append(str(li + 1))
	var msg := ""
	if sevens:
		if game.open_safe():
			msg = "777 — СЕЙФ ОТКРЫТ!"
			game.hud.toast("Три семёрки! Где-то щёлкнул замок сейфа…", Color(1.0, 0.85, 0.4))
		else:
			win += int(PAY["seven"][3])
	if win > 0:
		msg = (msg + " ") if msg != "" else ""
		msg += "ВЫИГРЫШ: %d" % win
		var tray := rig.global_transform * Vector3(0, 0.45, 0.4)
		var fwd := global_transform.basis.z
		game.spawn_loot("coin", win, tray, fwd * 1.2 + Vector3(0, 1.2, 0), 0.5)
		game.hud.toast("KILLBOX: выигрыш %d монет" % win, Color(1.0, 0.8, 0.4))
	if sevens or win >= 30:
		party = 2.5
		snd2.stream = game.snd["jingle"][0]
		snd2.volume_db = -10.0
		snd2.play()
	if won_lines.size() > 0:
		msg += "  (линии %s)" % ", ".join(won_lines)
	screen.text = msg if msg != "" else "ПУСТО"
