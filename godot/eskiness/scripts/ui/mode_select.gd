extends RefCounted
## Выбор режима игры при новой игре (промпт 18.11 00:52). Номер режима — game_base.gd: MODE_REAL / MODE_NORMAL / MODE_CASUAL.
## В сетевой игре режим выбирает хост в лобби (net_lobby.gd), он рассылается всем (net_session.gd: lobby_mode).

const NAMES := ["Реализм", "По умолчанию", "Казуальный"]
const HINTS := [
	"Минимальный интерфейс, правила как обычно. Фильтр Нюхича меняется вручную.",
	"Как сейчас. Фильтр Нюхича меняется вручную.",
	"Батарейки, патроны и фильтры ставятся сами — при перезарядке (R) и с фонариком.",
]


## Заполнить страницу меню box: заголовок, три режима с пояснениями и «Назад».
## on_pick(mode: int) — выбран режим.
static func fill(menu, box: VBoxContainer, on_pick: Callable, on_back: Callable) -> void:
	for c in box.get_children():
		c.queue_free()
	box.add_child(menu._title("РЕЖИМ ИГРЫ", 60))
	box.add_child(menu._gap(18))
	for m in NAMES.size():
		var b: Button = menu._button(NAMES[m], on_pick.bind(m))
		b.custom_minimum_size = Vector2(340, 58)
		box.add_child(b)
		var h := Label.new()
		h.text = HINTS[m]
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		h.custom_minimum_size = Vector2(520, 0)
		h.size_flags_horizontal = Control.SIZE_SHRINK_END
		h.add_theme_font_size_override("font_size", 16)
		h.add_theme_color_override("font_color", Color(0.7, 0.66, 0.6))
		box.add_child(h)
		box.add_child(menu._gap(6))
	box.add_child(menu._gap(10))
	box.add_child(menu._button("Назад", on_back))
