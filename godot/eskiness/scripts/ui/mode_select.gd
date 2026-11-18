extends RefCounted
## Выбор режима игры при новой игре (промпт 18.11 00:52). Номер режима — game_base.gd: MODE_REAL / MODE_NORMAL / MODE_CASUAL.
## В сетевой игре режим выбирает хост в лобби (net_lobby.gd), он рассылается всем (net_session.gd: lobby_mode).
## Пояснение режима — не постоянная подпись, а окошко у курсора при наведении на кнопку (промпт 18.11 02:33),
## почти непрозрачное, шириной по длине текста (короче текст — уже окошко, длиннее — чуть шире).

const NAMES := ["Реализм", "По умолчанию", "Казуальный"]
const HINTS := [   # подписи (промпт 18.11 01:00): у стандартного — без подписи
	"Для тех, кто хочет посложнее",
	"",
	"Фильтры, фонарики, патроны - всё делается за вас",
]


## Заполнить страницу меню box: заголовок, три режима с пояснением у курсора и «Назад».
## on_pick(mode: int) — выбран режим.
static func fill(menu, box: VBoxContainer, on_pick: Callable, on_back: Callable) -> void:
	for c in box.get_children():
		c.queue_free()
	var old: Node = menu.get_node_or_null("ModeTip")
	if old != null:
		old.queue_free()
	var tip_panel := PanelContainer.new()
	tip_panel.name = "ModeTip"
	tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.05, 0.05, 0.05, 0.96)
	st.border_color = Color(0.95, 0.6, 0.3, 0.9)
	st.set_border_width_all(1)
	st.set_corner_radius_all(4)
	st.set_content_margin_all(9)
	tip_panel.add_theme_stylebox_override("panel", st)
	tip_panel.visible = false
	var tip_l := Label.new()
	tip_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_l.add_theme_font_size_override("font_size", 16)
	tip_l.add_theme_color_override("font_color", Color(0.86, 0.82, 0.74))
	tip_panel.add_child(tip_l)
	menu.add_child(tip_panel)

	box.add_child(menu._title("РЕЖИМ ИГРЫ", 60))
	box.add_child(menu._gap(18))
	for m in NAMES.size():
		var b: Button = menu._button(NAMES[m], on_pick.bind(m))
		b.custom_minimum_size = Vector2(340, 58)
		box.add_child(b)
		box.add_child(menu._gap(6))
		if HINTS[m] == "":
			continue
		var hint: String = HINTS[m]
		b.mouse_entered.connect(func():
			tip_l.text = hint
			# ширина по длине текста: короткое описание — уже окошко, длинное — чуть шире
			tip_l.custom_minimum_size.x = clampf(130.0 + sqrt(float(hint.length())) * 15.0, 170.0, 360.0)
			tip_panel.visible = true
			tip_panel.reset_size()
			var vp: Vector2 = menu.get_viewport().get_visible_rect().size
			var p := b.get_global_rect().position + Vector2(b.size.x + 14.0, 0.0)
			var sz := tip_panel.get_combined_minimum_size()
			if p.x + sz.x > vp.x - 4.0:
				p.x = b.get_global_rect().position.x - sz.x - 14.0
			p.y = clampf(p.y, 4.0, maxf(4.0, vp.y - sz.y - 4.0))
			tip_panel.position = p)
		b.mouse_exited.connect(func(): tip_panel.visible = false)
	box.add_child(menu._gap(4))
	box.add_child(menu._button("Назад", on_back))
