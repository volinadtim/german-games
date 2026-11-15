extends CanvasLayer
## Инвентарь: 10 ячеек (+5 с рюкзаком; монеты — отдельный кошелёк), снаряжение на силуэте человека
## (голова, лицо — противогаз, спина — рюкзак, тело, руки, ноги, обувь, левая и правая рука — оружие/щит), хотбар 1–5 и крафт.
## Tab / I — открыть/закрыть, игра не на паузе.
##   ЛКМ — использовать / надеть / снять; ПКМ — меню действий (промпт 14.11 19:07);
##   Shift+ПКМ — выбросить 1 шт., Shift + держать ПКМ — выбросить всю стопку (кольцо на ячейке);
##   перетаскивание мышью между ячейками и в слоты снаряжения, за окно — выбросить (стопка — спросит сколько);
##   палец: долгое нажатие — то же меню; навёл + 1–5 — хотбар.
##   Хотбар (ссылки на предметы, hud.gd рисует внизу): пока окно открыто, на его ячейки можно перетащить предмет,
##   ячейку хотбара — на другую (обмен) или обратно в сумку / за окно (отвязать).
## Сам инвентарь хранит данные и шлёт сигналы; что делает предмет — решает game.gd.

signal changed
signal use_requested(idx: int)
signal drop_requested(idx: int, all: bool)
signal drop_count_requested(idx: int, n: int)
signal drop_coins_requested(n: int)
signal equip_requested(idx: int, slot: String)
signal unequip_requested(slot: String, to_idx: int)
signal drop_equipped_requested(slot: String)
signal craft_requested(recipe: int)
signal repair_requested(kit_idx: int, target)   # target — номер ячейки или слот экипировки
signal message(text: String)

const Items := preload("res://scripts/items.gd")
const Gun := preload("res://scripts/gun.gd")
const BAG := 10                  # ячеек без рюкзака
const BAG_MAX := 15              # с рюкзаком (items.gd: "bag" — сколько добавляет)
const COLS := 5
const SLOT := 76.0
const EQUIP := ["head", "face", "back", "body", "hands", "legs", "feet", "left", "right"]
const EQUIP_NAMES := {"head": "Голова", "face": "Лицо", "back": "Спина", "body": "Тело", "hands": "Руки", "legs": "Ноги", "feet": "Обувь",
	"left": "Левая", "right": "Правая"}
## где слоты стоят на силуэте (вид со спины: левая рука слева)
const DOLL_POS := {"head": Vector2(113, 4), "face": Vector2(16, 4), "back": Vector2(210, 4), "body": Vector2(113, 92), "left": Vector2(16, 92), "right": Vector2(210, 92),
	"hands": Vector2(210, 180), "legs": Vector2(113, 180), "feet": Vector2(113, 266)}
const HOLD_TIME := 0.4                  # Shift + держать ПКМ столько — выбросить всю стопку
const TOUCH_HOLD := 0.5                 # палец: столько держать на ячейке — меню действий

var slots: Array = []            # null или {"id": String, "n": int}
var coins := 0
var equip := {"head": "", "face": "", "back": "", "body": "", "hands": "", "legs": "", "feet": "", "left": "", "right": ""}
var hotbar: Array = ["", "", "", "", ""]
var equip_dur := {}             # прочность надетого: слот -> значение
var open := false
var enabled := true
var hover = null                 # int — ячейка сумки, String — слот экипировки
var root: Control
var info_name: Label
var info_desc: Label
var slot_nodes: Array = []
var bag_nodes: Array = []        # ячейки сумки (BAG_MAX штук; лишние без рюкзака скрыты)
var bag_l: Label
var craft_box: VBoxContainer
var _press_key = null
var game  # game.gd — чтобы не открываться поверх магазина
var hold_key = null              # что выбрасываем удержанием ПКМ: номер ячейки или "coin"
var hold_t := 0.0
var touch_key = null             # палец держит эту ячейку (долгое нажатие = выбросить)
var touch_t := 0.0
var touch_sel = null             # последняя ячейка, которой коснулись (для привязки к хотбару без наведения)
var wallet_l: Label
var dlg: PanelContainer           # окно «сколько выбросить»
var dlg_title: Label
var dlg_slider: HSlider
var dlg_val: Label
var dlg_key = null
var menu_bg: Control              # меню действий (ПКМ): прозрачная подложка — клик мимо закрывает
var menu: PanelContainer
var menu_box: VBoxContainer
var menu_key = null
var touch_pos := Vector2.ZERO
var hot_nodes: Array = []         # ячейки хотбара поверх hud.gd, пока открыт инвентарь


## Ячейка: key — номер в сумке (int) или имя слота экипировки (String).
class Slot extends Control:
	const Items := preload("res://scripts/items.gd")
	var inv
	var key
	var px := 76.0

	func _ready() -> void:
		custom_minimum_size = Vector2(px, px)
		size = Vector2(px, px)
		mouse_entered.connect(func(): inv.set_hover(key))
		mouse_exited.connect(func(): inv.set_hover(null))

	func item_id() -> String:
		if key is String:
			return inv.equip[key]
		var s = inv.slots[key]
		return "" if s == null else String(s["id"])

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var hovered: bool = typeof(inv.hover) == typeof(key) and inv.hover == key
		var is_eq: bool = key is String
		var extra: bool = not is_eq and int(key) >= inv.BAG   # ячейка рюкзака
		draw_rect(r, Color(0.09, 0.06, 0.03, 0.75) if is_eq else (Color(0.12, 0.09, 0.04, 0.6) if extra else Color(0.0, 0.0, 0.0, 0.5)))
		draw_rect(r, Color(0.9, 0.7, 0.4, 0.6 if hovered else 0.25) if is_eq else Color(1, 1, 1, 0.45 if hovered else 0.12), false, 1.0)
		var f := ThemeDB.fallback_font
		var id := item_id()
		if id == "":
			if is_eq:
				draw_string(f, Vector2(0, size.y / 2 + 5), inv.EQUIP_NAMES[key], HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, Color(0.6, 0.55, 0.45, 0.75))
			return
		Items.draw_icon(self, id, r.grow(-12))
		# полоска прочности
		var mx := Items.max_dur(id)
		if mx > 0.0:
			var fr := clampf(float(inv.get_dur(key)) / mx, 0.0, 1.0)
			if id == "pistol":
				fr = float(Gun.mag_rounds(inv.get_dur(key))) / Gun.CAP
			draw_rect(Rect2(6, size.y - 9, size.x - 12, 4), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(6, size.y - 9, (size.x - 12) * fr, 4), Color(0.85, 0.25, 0.15).lerp(Color(0.45, 0.85, 0.35), fr))
		if Items.ITEMS[id].has("rounds"):
			# пистолет / магазин: патронов внутри
			var rt := "%d/%d" % [int(round(inv.get_dur(key))), int(mx)]
			if id == "pistol":
				var pd: float = inv.get_dur(key)
				rt = "%d/%d" % [Gun.mag_rounds(pd), Gun.CAP] if Gun.has_mag(pd) else "без маг."
			draw_string_outline(f, Vector2(4, size.y - 12), rt, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 9, 15, 4, Color(0, 0, 0, 0.8))
			draw_string(f, Vector2(4, size.y - 12), rt, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 9, 15, Color(0.95, 0.85, 0.55))
		elif Items.ITEMS[id].has("repair"):
			# ремкомплект: сколько зарядов осталось
			var ch := "×%d" % int(ceil(inv.get_dur(key)))
			draw_string_outline(f, Vector2(4, size.y - 12), ch, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 9, 16, 4, Color(0, 0, 0, 0.8))
			draw_string(f, Vector2(4, size.y - 12), ch, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 9, 16, Color(0.95, 0.85, 0.55))
		elif not is_eq:
			var n: int = inv.slots[key]["n"]
			if n > 1:
				draw_string_outline(f, Vector2(4, size.y - 6), str(n), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 9, 17, 4, Color(0, 0, 0, 0.8))
				draw_string(f, Vector2(4, size.y - 6), str(n), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 9, 17, Color(0.92, 0.9, 0.84))
		# Shift + держать ПКМ: кольцо заполняется — на полном выбросится вся стопка
		if typeof(inv.hold_key) == typeof(key) and inv.hold_key == key:
			var fr2 := clampf(inv.hold_t / inv.HOLD_TIME, 0.0, 1.0)
			draw_rect(r, Color(0.6, 0.1, 0.05, 0.25 * fr2))
			draw_arc(size / 2, size.x * 0.4, -PI / 2, -PI / 2 + TAU * fr2, 32, Color(1.0, 0.45, 0.3, 0.95), 4.0, true)
		var hk: int = inv.hotbar.find(id)
		if hk >= 0:
			draw_string_outline(f, Vector2(5, 17), str(hk + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(0, 0, 0, 0.8))
			draw_string(f, Vector2(5, 17), str(hk + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.0, 0.8, 0.4))

	func _gui_input(e: InputEvent) -> void:
		# палец (мышь, эмулированная из касаний): долгое нажатие — как ПКМ, выбросить
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.device == InputEvent.DEVICE_ID_EMULATION:
			if e.pressed:
				inv.touch_sel = key
				inv.set_hover(key)
				if item_id() != "":
					inv.touch_key = key
					inv.touch_t = 0.0
					inv.touch_pos = get_global_mouse_position()
			else:
				inv.touch_key = null
		# ПКМ — меню действий; Shift+ПКМ — выбросить 1, Shift + держать — всю стопку
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT and item_id() != "":
			if e.shift_pressed:
				if key is String:
					inv.drop_equipped_requested.emit(key)
				else:
					inv.start_hold(key, int(inv.slots[key]["n"]))
			else:
				inv.open_menu(key, get_global_mouse_position())
			accept_event()

	func _get_drag_data(_at: Vector2) -> Variant:
		var id := item_id()
		if id == "":
			return null
		var pv := Icon.new()
		pv.id = id
		pv.size = Vector2(60, 60)
		pv.position = Vector2(-30, -30)
		var holder := Control.new()
		holder.add_child(pv)
		set_drag_preview(holder)
		return {"inv_key": key}

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and (data.has("inv_key") or data.has("hot"))

	func _drop_data(_at: Vector2, data: Variant) -> void:
		if data.has("hot"):
			inv.unbind_hot(int(data["hot"]))
			return
		inv.move(data["inv_key"], key)


## Ячейка хотбара 1–5 поверх нарисованной hud.gd (только пока открыт инвентарь): цель перетаскивания.
class HotSlot extends Control:
	const Items := preload("res://scripts/items.gd")
	var inv
	var k := 0
	var dragging := false
	var over := false

	func _ready() -> void:
		mouse_entered.connect(_set_over.bind(true))
		mouse_exited.connect(_set_over.bind(false))

	func _set_over(v: bool) -> void:
		over = v
		queue_redraw()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_DRAG_BEGIN:
			dragging = true
			queue_redraw()
		elif what == NOTIFICATION_DRAG_END:
			dragging = false
			queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var id: String = inv.hotbar[k]
		draw_rect(r, Color(0.05, 0.04, 0.03, 0.85))
		if id != "":
			Items.draw_icon(self, id, r.grow(-11))
			var cnt: int = inv.count(id)
			if cnt == 0:
				draw_rect(r.grow(-1), Color(0, 0, 0, 0.6))
			elif cnt > 1:
				var f0 := ThemeDB.fallback_font
				draw_string_outline(f0, Vector2(0, size.y - 5), str(cnt), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 5, 16, 4, Color(0, 0, 0, 0.8))
				draw_string(f0, Vector2(0, size.y - 5), str(cnt), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 5, 16, Color(0.92, 0.9, 0.84))
		var f := ThemeDB.fallback_font
		draw_string_outline(f, Vector2(5, 17), str(k + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color(0, 0, 0, 0.8))
		draw_string(f, Vector2(5, 17), str(k + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.8, 0.45))
		# пока тащишь предмет — ячейки подсвечены как цели
		var a := 0.95 if (dragging and over) else (0.7 if dragging else 0.25)
		draw_rect(r, Color(1.0, 0.75, 0.35, a), false, 3.0 if dragging else 1.0)
		if dragging:
			draw_rect(r, Color(1.0, 0.75, 0.35, 0.18 if over else 0.08))

	func _get_drag_data(_at: Vector2) -> Variant:
		var id: String = inv.hotbar[k]
		if id == "":
			return null
		var pv := Icon.new()
		pv.id = id
		pv.size = Vector2(56, 56)
		pv.position = Vector2(-28, -28)
		var holder := Control.new()
		holder.add_child(pv)
		set_drag_preview(holder)
		return {"hot": k}

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and (data.has("inv_key") or data.has("hot"))

	func _drop_data(_at: Vector2, data: Variant) -> void:
		if data.has("hot"):
			inv.swap_hot(int(data["hot"]), k)
		else:
			inv.bind_hot(data["inv_key"], k)


## Силуэт человека под слотами снаряжения.
class Doll extends Control:
	func _draw() -> void:
		var c := Color(1, 1, 1, 0.07)
		draw_circle(Vector2(145, 40), 30, c)
		draw_rect(Rect2(108, 76, 74, 104), c)
		for sx in [-1.0, 1.0]:
			draw_line(Vector2(145 + 40 * sx, 84), Vector2(145 + 92 * sx, 150), c, 16.0)
			draw_line(Vector2(145 + 92 * sx, 150), Vector2(145 + 98 * sx, 210), c, 13.0)
			draw_line(Vector2(145 + 18 * sx, 180), Vector2(145 + 24 * sx, 330), c, 22.0)


## Картинка предмета (превью перетаскивания, крафт).
class Icon extends Control:
	const Items := preload("res://scripts/items.gd")
	var id := ""
	var dim := false

	func _draw() -> void:
		Items.draw_icon(self, id, Rect2(Vector2.ZERO, size))
		if dim:
			draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))


## Фон вокруг окна: бросить сюда предмет — выбросить его на пол.
class DropZone extends ColorRect:
	var inv

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and (data.has("inv_key") or data.has("hot"))

	func _drop_data(_at: Vector2, data: Variant) -> void:
		if data.has("hot"):
			inv.unbind_hot(int(data["hot"]))
			return
		var k = data["inv_key"]
		if k is String:
			inv.drop_equipped_requested.emit(k)
		elif inv.slots[k] != null and int(inv.slots[k]["n"]) > 1:
			inv.open_drop_dialog(k)     # стопка — «Сколько выбросить?»
		else:
			inv.drop_requested.emit(k, true)

	# клик мимо окна (по затемнению) — закрыть; событие съедено, в игру не уходит (промпт 02:15)
	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			accept_event()
			if inv.dlg.visible:
				inv.dlg.visible = false
			else:
				inv.close()


func _ready() -> void:
	layer = 2
	process_mode = Node.PROCESS_MODE_ALWAYS
	slots.resize(BAG)
	for k in 5:
		_add_key("hot_%d" % (k + 1), KEY_1 + k)
	_build_ui()
	root.visible = false


func _add_key(action: String, key: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)


func _build_ui() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var shade := DropZone.new()
	shade.inv = self
	shade.color = Color(0, 0, 0, 0.35)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_bottom = -92   # окно — над хотбаром (ячейки 1–5 внизу остаются видны для перетаскивания)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var panel := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.07, 0.065, 0.06, 0.93)
	st.border_color = Color(1, 1, 1, 0.14)
	st.set_border_width_all(1)
	st.set_corner_radius_all(3)
	st.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", st)
	center.add_child(panel)
	preload("res://scripts/ui/ui_fit.gd").attach(panel)   # окно в рамках экрана (промпт 00:32)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 28)
	panel.add_child(hb)

	# снаряжение на силуэте
	var dc := VBoxContainer.new()
	dc.add_theme_constant_override("separation", 10)
	hb.add_child(dc)
	dc.add_child(_label("СНАРЯЖЕНИЕ", 34, Color(0.86, 0.85, 0.8)))
	var doll := Doll.new()
	doll.custom_minimum_size = Vector2(290, 340)
	dc.add_child(doll)
	for k in EQUIP:
		var s := Slot.new()
		s.inv = self
		s.key = k
		s.px = 64.0
		s.position = DOLL_POS[k]
		doll.add_child(s)
		slot_nodes.append(s)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	hb.add_child(vb)
	vb.add_child(_label("ИНВЕНТАРЬ", 34, Color(0.86, 0.85, 0.8)))
	bag_l = _label("СУМКА (%d)" % BAG, 15, Color(0.6, 0.6, 0.56))
	vb.add_child(bag_l)
	var grid := GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.custom_minimum_size = Vector2(0, (SLOT + 6) * 3 - 6)   # место под 3 ряда: с рюкзаком окно не растёт
	vb.add_child(grid)
	for i in BAG_MAX:
		var s := Slot.new()
		s.inv = self
		s.key = i
		s.visible = i < slots.size()
		grid.add_child(s)
		slot_nodes.append(s)
		bag_nodes.append(s)
	var wallet := HBoxContainer.new()
	wallet.add_theme_constant_override("separation", 10)
	var wi := Icon.new()
	wi.id = "coin"
	wi.custom_minimum_size = Vector2(30, 30)
	wallet.add_child(wi)
	wallet_l = _label("", 20, Color(0.92, 0.8, 0.5))
	wallet_l.custom_minimum_size = Vector2(170, 0)
	wallet.add_child(wallet_l)
	var wb := Button.new()
	wb.text = "Выбросить монеты"
	wb.focus_mode = Control.FOCUS_NONE
	wb.add_theme_font_size_override("font_size", 16)
	wb.pressed.connect(open_drop_dialog.bind("coin"))
	wallet.add_child(wb)
	vb.add_child(wallet)
	# название и описание фиксированного размера (промпт 14.11 19:28): окно не прыгает при наведении
	info_name = _label(" ", 21, Color(0.9, 0.82, 0.62))
	info_name.clip_text = true
	info_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info_name.custom_minimum_size = Vector2(COLS * (SLOT + 6), 30)
	vb.add_child(info_name)
	info_desc = _label(" ", 16, Color(0.72, 0.71, 0.67))
	info_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_desc.max_lines_visible = 3
	info_desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info_desc.clip_text = true
	info_desc.custom_minimum_size = Vector2(COLS * (SLOT + 6), 3 * 27)
	info_desc.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	vb.add_child(info_desc)
	var hint_text := "ЛКМ — использовать    ПКМ — действия    Tab — закрыть\nShift+ПКМ — выбросить 1 (держать — всю стопку)\nЗа окно — выбросить    На ячейки 1–5 внизу — хотбар"
	if preload("res://scripts/ui/touch_controls.gd").wanted():
		hint_text = "Нажать — использовать    Подержать — действия
Перетащить — переложить    Коснулся предмета + ячейка 1–5 внизу — хотбар"
	var hint := _label(hint_text, 14, Color(0.55, 0.55, 0.52))
	vb.add_child(hint)

	var cb := VBoxContainer.new()
	cb.add_theme_constant_override("separation", 10)
	cb.custom_minimum_size = Vector2(250, 0)
	hb.add_child(cb)
	cb.add_child(_label("КРАФТ", 34, Color(0.86, 0.85, 0.8)))
	# рецептов много (молоток и что им делается) — список прокручивается
	var cscroll := ScrollContainer.new()
	cscroll.custom_minimum_size = Vector2(290, 380)
	cscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER   # длинные подписи не расширяют окно
	cb.add_child(cscroll)
	craft_box = VBoxContainer.new()
	craft_box.add_theme_constant_override("separation", 8)
	craft_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cscroll.add_child(craft_box)
	for k in 5:
		var hs := HotSlot.new()
		hs.inv = self
		hs.k = k
		root.add_child(hs)
		hot_nodes.append(hs)
	_build_drop_dialog()
	_build_menu()


## Окно «сколько выбросить»: ползунок и кнопка.
func _build_drop_dialog() -> void:
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cc)
	dlg = PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.1, 0.085, 0.07, 0.98)
	st.border_color = Color(0.9, 0.7, 0.4, 0.6)
	st.set_border_width_all(2)
	st.set_corner_radius_all(4)
	st.set_content_margin_all(18)
	dlg.add_theme_stylebox_override("panel", st)
	cc.add_child(dlg)
	preload("res://scripts/ui/ui_fit.gd").attach(dlg)   # окно в рамках экрана (промпт 00:32)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	dlg.add_child(v)
	dlg_title = _label("", 22, Color(0.92, 0.88, 0.75))
	dlg_title.clip_text = true
	dlg_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	dlg_title.custom_minimum_size = Vector2(400, 0)
	v.add_child(dlg_title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	dlg_slider = HSlider.new()
	dlg_slider.custom_minimum_size = Vector2(260, 30)
	dlg_slider.min_value = 1
	dlg_slider.step = 1
	dlg_slider.focus_mode = Control.FOCUS_NONE
	row.add_child(dlg_slider)
	dlg_val = _label("1", 22, Color(1.0, 0.85, 0.5))
	dlg_val.custom_minimum_size = Vector2(50, 0)
	row.add_child(dlg_val)
	var pm := HBoxContainer.new()
	pm.add_theme_constant_override("separation", 8)
	v.add_child(pm)
	for d in [["−", -1], ["+", 1], ["Всё", 0]]:
		var b := Button.new()
		b.text = d[0]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(56, 34)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 18)
		var step: int = d[1]
		b.pressed.connect(func(): dlg_slider.value = dlg_slider.max_value if step == 0 else dlg_slider.value + step)
		pm.add_child(b)
	dlg_slider.value_changed.connect(func(x: float): dlg_val.text = str(int(x)))
	var bb := HBoxContainer.new()
	bb.add_theme_constant_override("separation", 10)
	v.add_child(bb)
	var ok := Button.new()
	ok.text = "ОК"
	ok.focus_mode = Control.FOCUS_NONE
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ok.add_theme_font_size_override("font_size", 18)
	ok.pressed.connect(_confirm_drop)
	bb.add_child(ok)
	var no := Button.new()
	no.text = "Отмена"
	no.focus_mode = Control.FOCUS_NONE
	no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	no.add_theme_font_size_override("font_size", 18)
	no.pressed.connect(func(): dlg.visible = false)
	bb.add_child(no)
	dlg.visible = false


## key — номер ячейки или "coin".
func open_drop_dialog(key) -> void:
	var mx := coins if key is String else (int(slots[key]["n"]) if slots[key] != null else 0)
	if mx <= 0:
		return
	dlg_key = key
	dlg_title.text = "Сколько выбросить? %s" % ("Монеты" if key is String else Items.item_name(slots[key]["id"]))
	dlg_slider.max_value = mx
	dlg_slider.value = mx
	dlg_val.text = str(mx)
	dlg.visible = true


func _confirm_drop() -> void:
	dlg.visible = false
	var n := int(dlg_slider.value)
	if dlg_key is String:
		drop_coins_requested.emit(n)
	elif slots[dlg_key] != null:
		drop_count_requested.emit(dlg_key, n)


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _rebuild_craft() -> void:
	for c in craft_box.get_children():
		c.queue_free()
	for r in Items.RECIPES.size():
		var rec: Dictionary = Items.RECIPES[r]
		var out: String = rec["out"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var ic := Icon.new()
		ic.id = out
		ic.custom_minimum_size = Vector2(48, 48)
		row.add_child(ic)
		var on := _label(Items.item_name(out), 20, Color(0.92, 0.88, 0.75))
		on.clip_text = true
		on.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		on.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		on.custom_minimum_size.x = 60
		row.add_child(on)
		craft_box.add_child(row)
		var ok := true
		var need: Dictionary = rec["need"]
		for id in need:
			var have := count(id)
			var n: int = need[id]
			ok = ok and have >= n
			var nr := HBoxContainer.new()
			nr.add_theme_constant_override("separation", 6)
			var ni := Icon.new()
			ni.id = id
			ni.dim = have < n
			ni.custom_minimum_size = Vector2(30, 30)
			nr.add_child(ni)
			nr.add_child(_label("%s  %d/%d" % [Items.item_name(id), mini(have, n), n], 15, Color(0.7, 0.85, 0.6) if have >= n else Color(0.85, 0.5, 0.4)))
			craft_box.add_child(nr)
		if rec.has("tool"):
			# инструмент не тратится, но теряет прочность
			var tid: String = rec["tool"]
			var have_t := count(tid) > 0
			ok = ok and have_t
			var trow := HBoxContainer.new()
			trow.add_theme_constant_override("separation", 6)
			var ti := Icon.new()
			ti.id = tid
			ti.dim = not have_t
			ti.custom_minimum_size = Vector2(30, 30)
			trow.add_child(ti)
			trow.add_child(_label("%s (−%d прочности)" % [Items.item_name(tid), int(rec.get("wear", 1))], 15, Color(0.7, 0.85, 0.6) if have_t else Color(0.85, 0.5, 0.4)))
			craft_box.add_child(trow)
		var b := Button.new()
		b.text = "Скрафтить"
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = not ok
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(func(): craft_requested.emit(r))
		craft_box.add_child(b)


func _input(e: InputEvent) -> void:
	if not enabled:
		return
	if e.is_action_pressed("inventory"):
		if open:
			close()
		elif game and game.shop and game.shop.opened:
			return   # Tab в магазине закрывает магазин (shop.gd), инвентарь поверх не открываем
		elif not get_tree().paused:
			show_inventory()
		else:
			return
		get_viewport().set_input_as_handled()
	elif open and menu_bg.visible:
		# пока открыто меню действий — только Esc (клик мимо ловит подложка)
		if e.is_action_pressed("ui_cancel"):
			close_menu()
			get_viewport().set_input_as_handled()
	elif open and e.is_action_pressed("ui_cancel"):
		if dlg.visible:
			dlg.visible = false
		else:
			close()
		get_viewport().set_input_as_handled()
	elif open and hold_key != null and e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
		_finish_hold()
	elif open:
		for k in 5:
			if e.is_action_pressed("hot_%d" % (k + 1)):
				_bind_hover(k)
				get_viewport().set_input_as_handled()
		# ячейку под курсором считаем по геометрии, а не по mouse_entered: после перетаскивания Godot
		# не шлёт mouse_entered, наведение «залипало» на старой ячейке и клики уходили не туда (промпт 22:53)
		if e is InputEventMouseMotion and not dlg.visible:
			var hk = _slot_at()
			if not _same(hk, hover):
				set_hover(hk)
		# ЛКМ (нажал и отпустил на той же ячейке, без перетаскивания) — использовать / снять
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not dlg.visible:
			var at = _slot_at()
			if e.pressed:
				_press_key = at
				if not _same(at, hover):
					set_hover(at)
			else:
				var pk = _press_key
				_press_key = null
				if at != null and _same(pk, at) and not get_viewport().gui_is_dragging():
					if at is int and slots[at] != null:
						use_requested.emit(at)
					elif at is String and equip[at] != "":
						unequip_requested.emit(at, -1)


## Ячейка (номер или слот экипировки) под курсором; null — мимо.
func _slot_at():
	for n in slot_nodes:
		var c: Control = n
		if c.is_visible_in_tree() and Rect2(Vector2.ZERO, c.size).has_point(c.get_local_mouse_position()):
			return c.key
	return null


static func _same(a, b) -> bool:
	return typeof(a) == typeof(b) and a == b


## Shift+ПКМ: отпустил быстро — выбросить 1 шт.; продержал HOLD_TIME — всю стопку.
func start_hold(key, _mx: int) -> void:
	hold_key = key
	hold_t = 0.0


func _process(delta: float) -> void:
	_touch_hold(delta)
	if hold_key == null:
		return
	hold_t += delta
	_refresh()   # кольцо удержания на ячейке
	if hold_t >= HOLD_TIME:
		var k = hold_key
		hold_key = null
		if k is int and slots[k] != null:
			drop_requested.emit(k, true)
		_refresh()


## Палец держат на ячейке TOUCH_HOLD секунд и не тащат — меню действий.
func _touch_hold(delta: float) -> void:
	if touch_key == null:
		return
	if not open or get_viewport().gui_is_dragging():
		touch_key = null
		return
	touch_t += delta
	if touch_t < TOUCH_HOLD:
		return
	var k = touch_key
	touch_key = null
	_press_key = null   # отпускание пальца уже не «использовать»
	if (k is String and equip[k] != "") or (k is int and slots[k] != null):
		open_menu(k, touch_pos)


func _finish_hold() -> void:
	var k = hold_key
	hold_key = null
	_finish_hold_key(k)
	_refresh()


func _finish_hold_key(k) -> void:
	if k is int and slots[k] != null:
		drop_count_requested.emit(k, 1)


# ---------- меню действий (ПКМ / долгий тап) ----------

func _build_menu() -> void:
	menu_bg = Control.new()
	menu_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	menu_bg.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			close_menu())
	menu_bg.visible = false
	root.add_child(menu_bg)
	menu = PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.1, 0.085, 0.07, 0.98)
	st.border_color = Color(0.9, 0.7, 0.4, 0.55)
	st.set_border_width_all(1)
	st.set_corner_radius_all(3)
	st.set_content_margin_all(6)
	menu.add_theme_stylebox_override("panel", st)
	menu_bg.add_child(menu)
	menu_box = VBoxContainer.new()
	menu_box.add_theme_constant_override("separation", 2)
	menu.add_child(menu_box)


## Что делает «использовать» для этой вещи ("" — нечего).
func _use_label(id: String) -> String:
	var d: Dictionary = Items.ITEMS[id]
	if d.has("repair"):
		return "Починить…"
	if d.has("weapon"):
		return "Взять в руку"
	if d.has("equip"):
		return "Надеть"
	if d.has("buff"):
		return "Съесть" if d["buff"] == "resist" else "Выпить"
	if d.has("heal"):
		return "Выпить" if id == "pills" else "Лечиться"
	if id == "mag":
		return "Снарядить"
	return {"wallet": "Открыть", "flashlight": "Включить / выключить", "battery": "Зарядить фонарик",
		"broom": "Подмести стекло"}.get(id, "")


## Меню у курсора: пункты по типу вещи в ячейке / слоте.
func open_menu(key, at: Vector2) -> void:
	hold_key = null
	for c in menu_box.get_children():
		menu_box.remove_child(c)
		c.queue_free()
	var acts: Array = []   # [текст, действие]
	var title := ""
	if key is String:
		if equip[key] == "":
			return
		title = Items.item_name(equip[key])
		if equip[key] == "pistol" and Gun.has_mag(get_dur(key)):
			acts.append(["Извлечь магазин", "eject"])
		acts.append(["Снять", "unequip"])
		acts.append(["Выбросить", "drop_eq"])
	else:
		var s = slots[key]
		if s == null:
			return
		var id: String = s["id"]
		var n := int(s["n"])
		title = Items.item_name(id) + ("  ×%d" % n if n > 1 else "")
		var ul := _use_label(id)
		if ul != "":
			acts.append([ul, "use"])
		if id == "pistol" and Gun.has_mag(get_dur(key)):
			acts.append(["Извлечь магазин", "eject"])
		if id == "mag" and (equip["right"] == "pistol" or equip["left"] == "pistol"):
			acts.append(["Вставить в пистолет", "insert_mag"])
		if n > 1:
			acts.append(["Разделить", "split"])
		acts.append(["Выбросить 1", "drop1"])
		if n > 1:
			acts.append(["Выбросить всё", "drop_all"])
	acts.append(["Отмена", "cancel"])
	var tl := _label(title, 15, Color(0.75, 0.7, 0.6))
	tl.clip_text = true
	tl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tl.custom_minimum_size = Vector2(190, 0)
	menu_box.add_child(tl)
	# пункта «На хотбар» нет (промпт 14.11 19:20) — на хотбар только перетаскиванием
	for a in acts:
		var b := Button.new()
		b.text = a[0]
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(190, 32)
		b.add_theme_font_size_override("font_size", 18)
		var act: String = a[1]
		if act.begins_with("drop"):
			b.add_theme_color_override("font_color", Color(1.0, 0.6, 0.5))
		b.pressed.connect(_menu_pick.bind(key, act))
		menu_box.add_child(b)
	menu_key = key
	menu_bg.visible = true
	menu.reset_size()
	# у курсора, но не за краем экрана
	var vs := get_viewport().get_visible_rect().size
	var sz := menu.get_combined_minimum_size()
	menu.position = Vector2(clampf(at.x + 4, 0, vs.x - sz.x), clampf(at.y + 4, 0, vs.y - sz.y))
	set_hover(key)


func close_menu() -> void:
	if menu_bg and menu_bg.visible:
		menu_bg.visible = false
		menu_key = null
		_press_key = null


func _menu_pick(key, act: String) -> void:
	close_menu()
	match act:
		"use":
			if key is int and slots[key] != null:
				use_requested.emit(key)
		"split":
			split(key)
		"eject":
			if game and game.gun:
				game.gun.eject(key)
		"insert_mag":
			if game and game.gun and key is int:
				game.gun.insert_mag(key, "right" if equip["right"] == "pistol" else "left")
		"drop1":
			if key is int and slots[key] != null:
				drop_count_requested.emit(key, 1)
		"drop_all":
			if key is int and slots[key] != null:
				drop_requested.emit(key, true)
		"unequip":
			unequip_requested.emit(key, -1)
		"drop_eq":
			drop_equipped_requested.emit(key)


## Разделить стопку пополам: половина (меньшая) — в первую свободную ячейку.
func split(idx: int) -> void:
	var s = slots[idx]
	if s == null or int(s["n"]) < 2:
		return
	var j := free_cell()
	if j < 0:
		message.emit("Нет свободной ячейки")
		return
	@warning_ignore("integer_division")
	var half := int(s["n"]) / 2
	s["n"] = int(s["n"]) - half
	slots[j] = {"id": s["id"], "n": half}
	_after_change()


## Привязать к ячейке хотбара hk предмет из ячейки сумки / слота снаряжения key.
func bind_hot(key, hk: int) -> void:
	var id := ""
	if key is String:
		id = equip[key]
	elif key is int and key < slots.size() and slots[key] != null:
		id = slots[key]["id"]
	if id == "":
		return
	var old := hotbar.find(id)
	if old >= 0:
		hotbar[old] = ""
	hotbar[hk] = id
	message.emit("%s → клавиша %d" % [Items.item_name(id), hk + 1])
	_after_change()


func swap_hot(a: int, b: int) -> void:
	if a == b:
		return
	var t: String = hotbar[a]
	hotbar[a] = hotbar[b]
	hotbar[b] = t
	_after_change()


func unbind_hot(k: int) -> void:
	if hotbar[k] == "":
		return
	message.emit("%s отвязан от %d" % [Items.item_name(hotbar[k]), k + 1])
	hotbar[k] = ""
	_after_change()


## Ячейки хотбара — там же, где их рисует hud.gd (внизу по центру).
func _place_hot() -> void:
	var sz := root.size
	var cell := 64.0
	var gap := 8.0
	var x0 := sz.x / 2.0 - (cell * 5 + gap * 4) / 2.0
	for k in hot_nodes.size():
		var hs: Control = hot_nodes[k]
		hs.position = Vector2(x0 + k * (cell + gap), sz.y - cell - 18.0)
		hs.size = Vector2(cell, cell)
		hs.queue_redraw()


func _bind_hover(k: int) -> void:
	var h = hover if hover != null else touch_sel
	if h == null:
		return
	var id := ""
	if h is String:
		id = equip[h]
	elif slots[h] != null:
		id = slots[h]["id"]
	if id == "":
		return
	if hotbar[k] == id:
		hotbar[k] = ""
		message.emit("%s отвязан от %d" % [Items.item_name(id), k + 1])
	else:
		var old := hotbar.find(id)
		if old >= 0:
			hotbar[old] = ""
		hotbar[k] = id
		message.emit("%s → клавиша %d" % [Items.item_name(id), k + 1])
	_after_change()


func show_inventory() -> void:
	open = true
	root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_rebuild_craft()
	_place_hot()
	set_hover(null)


func close() -> void:
	if not open:
		return
	open = false
	root.visible = false
	hover = null
	hold_key = null
	touch_key = null
	touch_sel = null
	dlg.visible = false
	close_menu()
	if not get_tree().paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func set_hover(k) -> void:
	hover = k
	var id := ""
	var n := 0
	if k is String:
		id = equip[k]
		n = 1
	elif k is int and slots[k] != null:
		id = slots[k]["id"]
		n = slots[k]["n"]
	if id != "":
		info_name.text = "%s  ×%d" % [Items.item_name(id), n] if n > 1 else Items.item_name(id)
		info_desc.text = Items.ITEMS[id]["desc"]
	else:
		info_name.text = " "
		info_desc.text = " "
	_refresh()


func _refresh() -> void:
	for n in slot_nodes:
		n.queue_redraw()
	for n in hot_nodes:
		n.queue_redraw()


## Перетаскивание: from/to — номер ячейки или имя слота экипировки.
func move(from, to) -> void:
	if typeof(from) == typeof(to) and from == to:
		return
	# ремкомплект перетащили на вещь — починить её
	if from is int and slots[from] != null and Items.ITEMS[slots[from]["id"]].has("repair"):
		var tid := ""
		if to is String:
			tid = equip[to]
		elif slots[to] != null:
			tid = slots[to]["id"]
		if tid != "" and Items.repairable(tid) != "":
			repair_requested.emit(from, to)
			return
	# пистолет: магазин на пистолет — вставить; патроны на магазин — дозарядить (промпт 22:53)
	if from is int and slots[from] != null and game and game.gun:
		var fid: String = slots[from]["id"]
		var tid2 := ""
		if to is String:
			tid2 = equip[to]
		elif slots[to] != null:
			tid2 = slots[to]["id"]
		if fid == "mag" and tid2 == "pistol":
			game.gun.insert_mag(from, to)
			return
		if fid == "ammo" and tid2 == "mag" and to is int:
			game.gun.fill_mag(to)
			return
	if from is int and to is int:
		var a = slots[from]
		var b = slots[to]
		if a != null and b != null and a["id"] == b["id"]:
			var mx: int = Items.ITEMS[a["id"]]["stack"]
			var take := mini(int(a["n"]), mx - int(b["n"]))
			b["n"] += take
			a["n"] -= take
			if a["n"] <= 0:
				slots[from] = null
		else:
			slots[from] = b
			slots[to] = a
		_after_change()
	elif from is int and to is String:
		var s = slots[from]
		if s == null:
			return
		if not Items.fits(s["id"], to):
			message.emit("%s сюда не надеть" % Items.item_name(s["id"]))
			return
		equip_requested.emit(from, to)
	elif from is String and to is int:
		unequip_requested.emit(from, to)
	elif from is String and to is String:
		_swap_equip(from, to)


## Слот экипировки → другой слот (левая рука ↔ правая): меняем местами вместе с прочностью.
func _swap_equip(a: String, b: String) -> void:
	var ia: String = equip[a]
	var ib: String = equip[b]
	if ia == "":
		return
	if not Items.fits(ia, b) or (ib != "" and not Items.fits(ib, a)):
		message.emit("%s сюда не надеть" % Items.item_name(ia))
		return
	var da = equip_dur.get(a)
	var db = equip_dur.get(b)
	equip[a] = ib
	equip[b] = ia
	equip_dur.erase(a)
	equip_dur.erase(b)
	if db != null and ib != "":
		equip_dur[a] = db
	if da != null:
		equip_dur[b] = da
	if game:
		game._apply_equip(a)
		game._apply_equip(b)
	_after_change()


# ---------- данные ----------

## Сколько ячеек в сумке (рюкзак добавляет). Уменьшать — только когда лишние пусты (free_extra).
func set_capacity(n: int) -> void:
	n = clampi(n, BAG, BAG_MAX)
	slots.resize(n)
	for i in bag_nodes.size():
		bag_nodes[i].visible = i < n
	if bag_l:
		bag_l.text = "СУМКА (%d)" % n if n == BAG else "СУМКА (%d + %d в рюкзаке)" % [BAG, n - BAG]
	if hover is int and hover >= n:
		hover = null
	if touch_sel is int and touch_sel >= n:
		touch_sel = null


## Переложить вещи из ячеек рюкзака в свободные основные (стаки сливаются). true — рюкзак пуст.
func free_extra() -> bool:
	var ok := true
	for i in range(BAG, slots.size()):
		var s = slots[i]
		if s == null:
			continue
		var mx: int = Items.ITEMS[s["id"]]["stack"]
		if not s.has("dur"):
			for j in BAG:
				var t = slots[j]
				if t != null and t["id"] == s["id"] and not t.has("dur") and int(t["n"]) < mx:
					var take := mini(int(s["n"]), mx - int(t["n"]))
					t["n"] += take
					s["n"] -= take
					if s["n"] <= 0:
						break
		if s["n"] <= 0:
			slots[i] = null
			continue
		var j := free_cell(BAG)
		if j >= 0:
			slots[j] = s
			slots[i] = null
		else:
			ok = false
	_after_change()
	return ok


## Первая свободная ячейка среди первых limit (-1 — все); -1 — нет.
func free_cell(limit := -1) -> int:
	var n := slots.size() if limit < 0 else mini(limit, slots.size())
	for i in n:
		if slots[i] == null:
			return i
	return -1

## Прочность предмета в ячейке (int) или в слоте снаряжения (String).
func get_dur(key) -> float:
	if key is String:
		var eid: String = equip[key]
		return float(equip_dur.get(key, Items.max_dur(eid)))
	var s = slots[key]
	if s == null:
		return 0.0
	return float(s.get("dur", Items.max_dur(s["id"])))


## Добавить предметы; возвращает, сколько не влезло. Монеты идут в кошелёк.
## dur — прочность (для оружия/сапог, подобранных с пола), -1 — новая вещь.
func add(id: String, n: int, dur := -1.0) -> int:
	if id == "coin":
		coins += n
		_after_change()
		return 0
	var mx: int = Items.ITEMS[id]["stack"]
	for s in slots:
		if n <= 0:
			break
		if s != null and s["id"] == id and s["n"] < mx:
			var take := mini(n, mx - int(s["n"]))
			s["n"] += take
			n -= take
	while n > 0:
		var i := slots.find(null)
		if i == -1:
			break
		var take := mini(n, mx)
		slots[i] = {"id": id, "n": take}
		if dur >= 0.0:
			slots[i]["dur"] = dur
		n -= take
	_after_change()
	return n


## Сколько есть (в сумке + надето; монеты — в кошельке).
func count(id: String) -> int:
	if id == "coin":
		return coins
	var c := 0
	for s in slots:
		if s != null and s["id"] == id:
			c += int(s["n"])
	for k in equip:
		if equip[k] == id:
			c += 1
	return c


func bag_index(id: String) -> int:
	for i in slots.size():
		if slots[i] != null and slots[i]["id"] == id:
			return i
	return -1


## Убрать n штук из сумки (с последних стаков). false — если столько нет.
func remove(id: String, n: int) -> bool:
	if id == "coin":
		if coins < n:
			return false
		coins -= n
		_after_change()
		return true
	var have := 0
	for s in slots:
		if s != null and s["id"] == id:
			have += int(s["n"])
	if have < n:
		return false
	for i in range(slots.size() - 1, -1, -1):
		var s = slots[i]
		if n <= 0:
			break
		if s != null and s["id"] == id:
			var take := mini(n, int(s["n"]))
			s["n"] -= take
			n -= take
			if s["n"] <= 0:
				slots[i] = null
	_after_change()
	return true


## Забрать из ячейки idx до n штук; возвращает [id, сколько забрали].
func take_at(idx: int, n: int) -> Array:
	var s = slots[idx]
	if s == null:
		return ["", 0]
	var take := mini(n, int(s["n"]))
	s["n"] -= take
	var id: String = s["id"]
	if s["n"] <= 0:
		slots[idx] = null
	_after_change()
	return [id, take]


func notify() -> void:
	_after_change()


func _after_change() -> void:
	if wallet_l:
		wallet_l.text = "Монеты: %d" % coins
	if open:
		set_hover(hover)
		_rebuild_craft()
	changed.emit()
