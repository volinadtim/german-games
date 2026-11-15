extends "res://scripts/slot/slot_machine_model.gd"
# Часть slot_machine.gd: доска выплат и окно покупки круток.


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
	board_sv = sv
	board_art = art
	var frame := _worn(Color(0.62, 0.5, 0.26), true, 0.0, 0.6, 0.5)
	var back := _worn(Color(0.12, 0.08, 0.05), false, 0.2, 0.4, 0.5)
	var board := Node3D.new()
	board.position = BOARD_POS
	board.rotation.y = -0.12
	add_child(board)
	board_node = board
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
	_fit(ci, Vector2(pad, 158), "%d крутки — %d монет, %d — %d · окно %s (ур. %d из %d)" % [PACKS[0][0], PACKS[0][1], PACKS[1][0], PACKS[1][1], level_name(level), level, MAX_LEVEL], inner, 20, Color(0.8, 0.72, 0.6), HORIZONTAL_ALIGNMENT_CENTER)
	var y := 184.0
	var text_col := Color(0.95, 0.9, 0.78)
	var rows := ["diamond", "grape", "plum", "lemon", "cherry"]
	for k in rows.size():
		var id: String = rows[k]
		if k % 2 == 0:
			ci.draw_rect(Rect2(pad - 8, y - 4, inner + 16, 92), Color(1, 1, 1, 0.04))
		var pays: Dictionary = PAY[id]   # выплаты — для текущего окна (pay_for)
		Sym.draw(ci, id, Rect2(pad, y, 84, 84))
		if not syms_for(level).has(id):
			ci.draw_rect(Rect2(pad - 8, y - 4, inner + 16, 92), Color(0.12, 0.05, 0.05, 0.75))
			_fit(ci, Vector2(pad + 100, y + 54), "появится на окне %s" % level_name(sym_level(id)), inner - 160, 26, Color(0.7, 0.62, 0.52))
			y += 100.0
			continue
		var parts := PackedStringArray()
		for n in [5, 4, 3]:
			if pays.has(n) and n <= int(LEVELS[level - 1][1]):
				parts.append("×%d — %d" % [n, pay_for(id, n, level)])
		if level <= PAIR_MAX_LEVEL and PAY2.has(id):
			parts.append("×2 — %d" % int(PAY2[id]))
		_fit(ci, Vector2(pad + 100, y + 54), "    ".join(parts), inner - 160, 30, text_col)
		_fit(ci, Vector2(w - pad - 70, y + 54), "%.0f%%" % float(WEIGHTS[id]), 66, 18, Color(0.7, 0.62, 0.52), HORIZONTAL_ALIGNMENT_RIGHT)
		y += 100.0
	y += 6.0
	ci.draw_line(Vector2(pad, y), Vector2(w - pad, y), Color(0.85, 0.62, 0.25, 0.7), 2.0)
	y += 18.0
	# семёрки и шестёрки: до 3×5 их на доске нет совсем; во время кат-сцены — проявляются (rev7, rev6)
	var show76 := syms_for(level).has("seven") and (not reveal_pending or cut_active)
	var p7 := rev7 if cut_active else (1.0 if show76 else 0.0)
	var p6 := rev6 if cut_active else (1.0 if show76 else 0.0)
	var bg := Color(0.12, 0.05, 0.05)
	if p7 > 0.0:
		for k in 3:
			Sym.draw(ci, "seven", Rect2(pad + k * 62, y, 62, 62))
		_fit(ci, Vector2(pad + 200, y + 28), "×3 на линии — открывают сейф", inner - 200, 24, Color(1.0, 0.85, 0.4))
		_fit(ci, Vector2(pad + 200, y + 58), "сейф уже открыт — %d монет" % int(PAY["seven"][3]), inner - 200, 22, text_col)
		if p7 < 1.0:
			# изящно: проявление сверху вниз, по кромке — золотое сияние и блёстки
			var edge := y - 6.0 + 84.0 * p7
			ci.draw_rect(Rect2(pad - 8, edge, inner + 16, y + 80.0 - edge), bg)
			ci.draw_rect(Rect2(pad - 8, edge - 3, inner + 16, 6), Color(1.0, 0.85, 0.4, 0.8))
			ci.draw_rect(Rect2(pad - 8, edge - 12, inner + 16, 24), Color(1.0, 0.8, 0.3, 0.18))
			var gr := RandomNumberGenerator.new()
			gr.seed = int(cut_t * 30.0)
			for k in 26:
				var sp := Vector2(gr.randf_range(pad, w - pad), edge + gr.randf_range(-30, 10))
				var sz := gr.randf_range(2.0, 5.0)
				ci.draw_rect(Rect2(sp - Vector2(sz, 0.6), Vector2(sz * 2, 1.2)), Color(1, 0.95, 0.7, 0.9))
				ci.draw_rect(Rect2(sp - Vector2(0.6, sz), Vector2(1.2, sz * 2)), Color(1, 0.95, 0.7, 0.9))
	y += 96.0
	if p6 > 0.0:
		var sh := Vector2.ZERO
		if p6 < 1.0:   # зловещая дрожь
			sh = Vector2(randf_range(-3, 3), randf_range(-2, 2))
		for k in 3:
			Sym.draw(ci, "six", Rect2(pad + k * 62 + sh.x, y + sh.y, 62, 62))
		_fit(ci, Vector2(pad + 200, y + 28) + sh, "×3 где угодно в окне —", inner - 200, 24, Color(1.0, 0.3, 0.2))
		_fit(ci, Vector2(pad + 200, y + 58) - sh, "автомат забирает всё, кроме 10", inner - 200, 22, Color(1.0, 0.3, 0.2))
		if p6 < 1.0:
			# проявление «кровью»: тёмная завеса с рваными подтёками, сползающими вниз
			var poly := PackedVector2Array([Vector2(pad - 8, y + 80), Vector2(w - pad + 8, y + 80)])
			var gr := RandomNumberGenerator.new()
			gr.seed = 66
			var xs := 24
			for k in range(xs, -1, -1):
				var x := pad - 8 + (inner + 16) * k / float(xs)
				var drip := gr.randf_range(0.0, 1.0)
				var ey := y - 6.0 + 86.0 * clampf(p6 * (0.6 + drip * 0.8), 0.0, 1.0)
				poly.append(Vector2(x, ey))
			ci.draw_colored_polygon(poly, bg)
			for k in xs:
				var x := pad - 8 + (inner + 16) * (k + 0.5) / float(xs)
				var ey := y - 6.0 + 86.0 * clampf(p6 * (0.6 + gr.randf_range(0.0, 1.0) * 0.8), 0.0, 1.0)
				ci.draw_rect(Rect2(x - 2, y - 6, 4, ey - y + 6), Color(0.55, 0.0, 0.0, 0.55))
			ci.draw_rect(Rect2(pad - 8, y - 8, inner + 16, 92), Color(1.0, 0.0, 0.0, 0.12 + 0.12 * sin(cut_t * 40.0)))
	y += 92.0
	_fit(ci, Vector2(pad, y + 20), "СЕРИЯ ПОБЕД: ×1 → ×1.25 → ×1.5 → ×2 · проигрыш, уход или 30 с без крутки — сброс", inner, 19, Color(0.7, 0.62, 0.52), HORIZONTAL_ALIGNMENT_CENTER)
	# правая колонка: линии открытого окна схемами 5×3 (закрытые клетки — тёмные)
	var x0 := w
	var cw := ci.size.x - w - pad
	ci.draw_line(Vector2(x0 - 4, 40), Vector2(x0 - 4, ci.size.y - 40), Color(0.85, 0.62, 0.25, 0.5), 2.0)
	_fit(ci, Vector2(x0, 82), "ЛИНИИ", cw, 44, Color(1.0, 0.82, 0.4), HORIZONTAL_ALIGNMENT_CENTER)
	_fit(ci, Vector2(x0, 120), "окно %s · линий: %d" % [level_name(level), lines_for(level).size()], cw, 20, Color(0.8, 0.72, 0.6), HORIZONTAL_ALIGNMENT_CENTER)
	var names := {"row": "ряд", "v": "галочка", "diag": "диагональ", "bridge": "мостик"}
	var cell := 17.0
	var lines := lines_for(level)
	for li in lines.size():
		var gx := x0 + 10 + (li % 3) * 88.0
		@warning_ignore("integer_division")
		var gy := 146.0 + (li / 3) * 100.0
		var line: Array = lines[li][0]
		for c in REELS:
			for r in ROWS:
				var on: bool = line.has([r, c])
				var col := Color(1.0, 0.45, 0.2) if on else (Color(1, 1, 1, 0.12) if is_open(level, r, c) else Color(1, 1, 1, 0.03))
				ci.draw_rect(Rect2(gx + c * cell, gy + r * cell, cell - 2, cell - 2), col)
		for j in line.size() - 1:
			var p0: Array = line[j]
			var p1: Array = line[j + 1]
			var pa := Vector2(gx + int(p0[1]) * cell + cell / 2 - 1, gy + int(p0[0]) * cell + cell / 2 - 1)
			var pb := Vector2(gx + int(p1[1]) * cell + cell / 2 - 1, gy + int(p1[0]) * cell + cell / 2 - 1)
			ci.draw_line(pa, pb, Color(1.0, 0.85, 0.4), 2.0)
		_fit(ci, Vector2(gx, gy + 3 * cell + 20), "%d %s" % [li + 1, names[lines[li][1]]], 5 * cell + 6, 14, Color(0.85, 0.8, 0.7))
	var ry := 146.0 + 5 * 100.0 + 14
	for t_ in ["Ряды: 3–5 одинаковых подряд.", "Галочки, диагонали: все 3.", "Мостики: только все 4.", "Под заслонками не играет.", "Пара (×2, не вишни) — +2,", "только на 1×3.", "Гаранты и шансы — в магазине.", "Гнилое яблоко спасёт от 666."]:
		_fit(ci, Vector2(x0 + 10, ry), t_, cw - 10, 20, Color(0.9, 0.84, 0.72))
		ry += 28.0
	if dark6 > 0.0:   # перед шестёрками доска на миг темнеет
		ci.draw_rect(Rect2(Vector2.ZERO, ci.size), Color(0, 0, 0, dark6))


func _mult_str(m: float) -> String:
	return ("%.2f" % m).trim_suffix("0").trim_suffix("0").trim_suffix(".")


## Экран автомата между крутками: сколько круток осталось, множитель серии и гарантированные символы.
func _update_screen_hint() -> void:
	if credits <= 0 and luck.is_empty() and boost.is_empty() and streak <= 0 and shield <= 0:
		return
	var parts := PackedStringArray()
	if streak > 0:
		parts.append("СЕРИЯ %d → ×%s" % [streak, _mult_str(chain_mult(streak))])
	if credits > 0:
		parts.append("КРУТОК: %d" % credits)
	for k in luck:
		parts.append("%s ГАРАНТ ×%d (%d)" % [Sym.NAMES[k].to_upper(), int(luck[k]["k"]), int(luck[k]["left"])])
	for k in boost:
		parts.append("%s ЧАЩЕ (%d)" % [Sym.NAMES[k].to_upper(), int(boost[k])])
	if shield > 0:
		parts.append("ЗАЩИТА 666 ×%d" % shield)
	screen.text = (screen.text + "\n" if screen.text != "" else "") + " · ".join(parts)


# ---------- покупка круток (окно) ----------

func _open_packs() -> void:
	if pack_ui == null:
		_build_packs()
	pack_open = true
	pack_ui.visible = true
	pack_info.text = "Монет: %d" % game.inv.coins
	_refresh_pack_up()
	game.player.active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_packs() -> void:
	pack_open = false
	if pack_ui:
		pack_ui.visible = false
	if game and game.player:
		game.player.active = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_packs() -> void:
	pack_ui = CanvasLayer.new()
	pack_ui.layer = 5
	add_child(pack_ui)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	pack_ui.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	pack_ui.add_child(cc)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.03, 0.02, 0.96)
	sb.border_color = Color(0.85, 0.2, 0.1, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", sb)
	cc.add_child(panel)
	preload("res://scripts/ui/ui_fit.gd").attach(panel)   # окно в рамках экрана (промпт 00:32)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var lbl := Label.new()
	lbl.text = "KILLBOX — КРУТКИ"
	lbl.add_theme_font_size_override("font_size", 30)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.25))
	v.add_child(lbl)
	# окно фиксированного размера при любом тексте (промпт 14.11 19:28)
	panel.custom_minimum_size = Vector2(460, 0)
	pack_info = Label.new()
	pack_info.custom_minimum_size = Vector2(416, 28)
	pack_info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	pack_info.clip_text = true
	pack_info.add_theme_font_size_override("font_size", 20)
	pack_info.add_theme_color_override("font_color", Color(0.92, 0.8, 0.5))
	v.add_child(pack_info)
	for pk in PACKS:
		var b := Button.new()
		b.text = "%d крутки — %d монет" % [pk[0], pk[1]] if int(pk[0]) < 5 else "%d круток — %d монет" % [pk[0], pk[1]]
		b.custom_minimum_size = Vector2(320, 48)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(_buy_pack.bind(int(pk[0]), int(pk[1])))
		v.add_child(b)
	pack_up = Button.new()
	pack_up.custom_minimum_size = Vector2(416, 48)
	pack_up.clip_text = true
	pack_up.focus_mode = Control.FOCUS_NONE
	pack_up.add_theme_font_size_override("font_size", 20)
	pack_up.pressed.connect(_pack_upgrade)
	v.add_child(pack_up)
	var c := Button.new()
	c.text = "Закрыть (E / Esc)"
	c.focus_mode = Control.FOCUS_NONE
	c.add_theme_font_size_override("font_size", 18)
	c.pressed.connect(close_packs)
	v.add_child(c)
	pack_ui.visible = false


func _buy_pack(n: int, price: int) -> void:
	if busy:
		return
	if not game.inv.remove("coin", price):
		pack_info.text = "Не хватает монет (есть %d)" % game.inv.coins
		game.play_ui("buzz", -14.0)
		return
	close_packs()
	# монеты уже списаны — крутки зачисляем сразу в сейв, а на экране — после того, как 3 монетки
	# залетят в монетоприёмник (промпт 14.11 17:40)
	credits += n
	game.save_now()
	busy = true
	screen.text = "ОПЛАТА..."
	_coin_toss(3, func():
		busy = false
		game.hud.toast("KILLBOX: +%d круток" % n, Color(1.0, 0.8, 0.4))
		screen.text = ""
		_update_screen_hint())


## Монетки из руки игрока по дуге в монетоприёмник, одна за другой, каждая со звоном; потом done.
func _coin_toss(count: int, done: Callable) -> void:
	var slot_pos := rig.global_transform * Vector3(0.3 + EX, 0.71, 0.33)
	var from := slot_pos + global_transform.basis.z * 1.2 + Vector3(0, -0.3, 0)
	if game and game.player and game.player.get("cam"):
		var cam: Camera3D = game.player.cam
		from = cam.global_position - cam.global_transform.basis.z * 0.45 + Vector3(0, -0.2, 0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.86, 0.66, 0.3)
	m.metallic = 0.85
	m.roughness = 0.35
	var cm := CylinderMesh.new()
	cm.top_radius = 0.022
	cm.bottom_radius = 0.022
	cm.height = 0.006
	cm.radial_segments = 12
	cm.rings = 1
	var dur := 0.42
	var gap := 0.28
	for k in count:
		var coin := MeshInstance3D.new()
		coin.mesh = cm
		coin.material_override = m
		coin.visible = false
		if get_tree().current_scene:
			get_tree().current_scene.add_child(coin)
		else:
			add_child(coin)
		coin.global_position = from
		var a := from + Vector3(randf_range(-0.03, 0.03), 0, randf_range(-0.03, 0.03))
		var mid := (a + slot_pos) / 2.0 + Vector3(0, 0.35, 0)
		var tw := create_tween()
		tw.tween_interval(k * gap)
		tw.tween_callback(func(): coin.visible = true)
		tw.tween_method(func(ts: float):
			var p := a.lerp(mid, ts).lerp(mid.lerp(slot_pos, ts), ts)
			coin.global_position = p
			coin.rotation = Vector3(ts * 9.0, 0.3, ts * 4.0), 0.0, 1.0, dur)
		var last := k == count - 1
		tw.tween_callback(func():
			if game:
				game.play_at("coin", slot_pos, -8.0, 1.0 + 0.08 * k)
			coin.queue_free()
			if last:
				done.call())


func _refresh_pack_up() -> void:
	if pack_up == null:
		return
	pack_up.text = upgrade_text()
	pack_up.disabled = level >= MAX_LEVEL


func _pack_upgrade() -> void:
	if buy_upgrade():
		pack_info.text = "Окно прокачано: %s" % level_name(level)
	else:
		pack_info.text = "Не хватает монет (есть %d)" % game.inv.coins
	_refresh_pack_up()


## Цена следующего уровня (0 — уже максимум).
func upgrade_price() -> int:
	return int(LEVELS[level][2]) if level < MAX_LEVEL else 0


func upgrade_text() -> String:
	if level >= MAX_LEVEL:
		return "Окно %s — максимум" % level_name(level)
	return "Окно %s (ур. %d) → %s — %d монет" % [level_name(level), level, level_name(level + 1), upgrade_price()]


## Купить следующий уровень окна. false — максимум или не хватает монет.
func buy_upgrade() -> bool:
	if level >= MAX_LEVEL or game == null:
		return false
	if not game.inv.remove("coin", upgrade_price()):
		game.play_ui("buzz", -14.0)
		return false
	set_level(level + 1)
	if level >= MAX_LEVEL:
		reveal_pending = true   # кат-сцена — когда закроются окна (магазин/покупка)
		_redraw_board()
	game.play_ui("coin", -10.0)
	game.hud.toast("KILLBOX: окно %s" % level_name(level), Color(1.0, 0.8, 0.4))
	game.save_now()
	return true
