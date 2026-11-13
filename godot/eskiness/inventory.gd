extends CanvasLayer
## Инвентарь: 10 ячеек (монеты — отдельный кошелёк, места не занимают), слоты экипировки
## (левая и правая рука — оружие или щит, голова — противогаз, кастет), привязка предметов к 1–5 и крафт.
## Tab / I — открыть/закрыть. Игра НЕ ставится на паузу: мир идёт дальше.
##   ЛКМ по ячейке — использовать/надеть; ПКМ — выбросить: щелчок — 1 шт., удержание — счётчик растёт,
##   отпустил — выброшено столько (Shift+ПКМ — весь стак). Так же и с монетами в кошельке;
##   перетаскивание мышью: между ячейками, в слоты экипировки и обратно, за пределы окна — выбросить;
##   навести на предмет и нажать 1–5 — привязать к хотбару.
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
signal message(text: String)

const Items := preload("res://items.gd")
const BAG := 10
const COLS := 5
const SLOT := 76.0
const EQUIP := ["left", "right", "head", "hands"]
const EQUIP_NAMES := {"left": "Левая рука", "right": "Правая рука", "head": "Голова", "hands": "Кастет"}

var slots: Array = []            # null или {"id": String, "n": int}
var coins := 0
var equip := {"left": "", "right": "", "head": "", "hands": ""}
var hotbar: Array = ["", "", "", "", ""]
var open := false
var enabled := true
var hover = null                 # int — ячейка сумки, String — слот экипировки
var root: Control
var info_name: Label
var info_desc: Label
var slot_nodes: Array = []
var craft_box: VBoxContainer
var _press_key = null
var hold_key = null              # что выбрасываем удержанием ПКМ: номер ячейки или "coin"
var hold_t := 0.0
var hold_n := 1
var hold_max := 1
var hold_l: Label
var wallet_l: Label


## Ячейка: key — номер в сумке (int) или имя слота экипировки (String).
class Slot extends Control:
	const Items := preload("res://items.gd")
	var inv
	var key

	func _ready() -> void:
		custom_minimum_size = Vector2(76, 76)
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
		draw_rect(r, Color(0.09, 0.06, 0.03, 0.75) if is_eq else Color(0.0, 0.0, 0.0, 0.5))
		draw_rect(r, Color(0.9, 0.7, 0.4, 0.6 if hovered else 0.25) if is_eq else Color(1, 1, 1, 0.45 if hovered else 0.12), false, 1.0)
		var f := ThemeDB.fallback_font
		var id := item_id()
		if id == "":
			if is_eq:
				draw_string(f, Vector2(0, size.y / 2 + 5), inv.EQUIP_NAMES[key], HORIZONTAL_ALIGNMENT_CENTER, size.x, 12, Color(0.6, 0.55, 0.45, 0.7))
			return
		Items.draw_icon(self, id, r.grow(-12))
		if not is_eq:
			var n: int = inv.slots[key]["n"]
			if n > 1:
				draw_string_outline(f, Vector2(4, size.y - 6), str(n), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 9, 17, 4, Color(0, 0, 0, 0.8))
				draw_string(f, Vector2(4, size.y - 6), str(n), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 9, 17, Color(0.92, 0.9, 0.84))
		var hk: int = inv.hotbar.find(id)
		if hk >= 0:
			draw_string_outline(f, Vector2(5, 17), str(hk + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(0, 0, 0, 0.8))
			draw_string(f, Vector2(5, 17), str(hk + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.0, 0.8, 0.4))

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT and item_id() != "":
			if key is String:
				inv.drop_equipped_requested.emit(key)
			else:
				if e.shift_pressed:
					inv.drop_requested.emit(key, true)
				else:
					inv.start_hold(key, int(inv.slots[key]["n"]))

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
		return data is Dictionary and data.has("inv_key")

	func _drop_data(_at: Vector2, data: Variant) -> void:
		inv.move(data["inv_key"], key)


## Кошелёк: монеты места в сумке не занимают. ПКМ (удержание) — выбросить сколько-то монет.
class Wallet extends HBoxContainer:
	var inv

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT and inv.coins > 0:
			if e.shift_pressed:
				inv.drop_coins_requested.emit(inv.coins)
			else:
				inv.start_hold("coin", inv.coins)


## Картинка предмета (превью перетаскивания, крафт).
class Icon extends Control:
	const Items := preload("res://items.gd")
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
		return data is Dictionary and data.has("inv_key")

	func _drop_data(_at: Vector2, data: Variant) -> void:
		var k = data["inv_key"]
		if k is String:
			inv.drop_equipped_requested.emit(k)
		else:
			inv.drop_requested.emit(k, true)


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
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var panel := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.07, 0.065, 0.06, 0.93)
	st.border_color = Color(1, 1, 1, 0.14)
	st.set_border_width_all(1)
	st.set_corner_radius_all(3)
	st.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", st)
	center.add_child(panel)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 28)
	panel.add_child(hb)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	hb.add_child(vb)
	vb.add_child(_label("ИНВЕНТАРЬ", 34, Color(0.86, 0.85, 0.8)))
	vb.add_child(_label("ЭКИПИРОВКА", 15, Color(0.75, 0.6, 0.4)))
	var eq := HBoxContainer.new()
	eq.add_theme_constant_override("separation", 6)
	vb.add_child(eq)
	for k in EQUIP:
		var s := Slot.new()
		s.inv = self
		s.key = k
		eq.add_child(s)
		slot_nodes.append(s)
	vb.add_child(_label("СУМКА (%d)" % BAG, 15, Color(0.6, 0.6, 0.56)))
	var grid := GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	vb.add_child(grid)
	for i in BAG:
		var s := Slot.new()
		s.inv = self
		s.key = i
		grid.add_child(s)
		slot_nodes.append(s)
	var wallet := Wallet.new()
	wallet.inv = self
	wallet.mouse_filter = Control.MOUSE_FILTER_STOP
	wallet.add_theme_constant_override("separation", 8)
	var wi := Icon.new()
	wi.id = "coin"
	wi.custom_minimum_size = Vector2(30, 30)
	wi.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wallet.add_child(wi)
	wallet_l = _label("", 20, Color(0.92, 0.8, 0.5))
	wallet_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wallet.add_child(wallet_l)
	vb.add_child(wallet)
	info_name = _label(" ", 21, Color(0.9, 0.82, 0.62))
	vb.add_child(info_name)
	info_desc = _label(" ", 16, Color(0.72, 0.71, 0.67))
	info_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_desc.custom_minimum_size = Vector2(COLS * (SLOT + 6), 42)
	vb.add_child(info_desc)
	var hint := _label("ЛКМ — использовать / надеть / снять    ПКМ — выбросить (держи — больше, Shift — всё)\nперетащи мышью в слот или за окно    навёл + 1–5 — на хотбар    Tab — закрыть", 13, Color(0.55, 0.55, 0.52))
	vb.add_child(hint)

	var cb := VBoxContainer.new()
	cb.add_theme_constant_override("separation", 10)
	cb.custom_minimum_size = Vector2(250, 0)
	hb.add_child(cb)
	cb.add_child(_label("КРАФТ", 34, Color(0.86, 0.85, 0.8)))
	hold_l = _label("", 18, Color(1.0, 0.85, 0.5))
	hold_l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	hold_l.add_theme_constant_override("outline_size", 6)
	hold_l.visible = false
	hold_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hold_l)
	craft_box = VBoxContainer.new()
	craft_box.add_theme_constant_override("separation", 14)
	cb.add_child(craft_box)


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
		row.add_child(_label(Items.item_name(out), 20, Color(0.92, 0.88, 0.75)))
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
		elif not get_tree().paused:
			show_inventory()
		else:
			return
		get_viewport().set_input_as_handled()
	elif open and e.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif open and hold_key != null and e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
		_finish_hold()
	elif open:
		for k in 5:
			if e.is_action_pressed("hot_%d" % (k + 1)):
				_bind_hover(k)
				get_viewport().set_input_as_handled()
		# ЛКМ (нажал и отпустил на той же ячейке, без перетаскивания) — использовать / снять
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_press_key = hover
			elif hover != null and typeof(_press_key) == typeof(hover) and _press_key == hover and not get_viewport().gui_is_dragging():
				if hover is int and slots[hover] != null:
					use_requested.emit(hover)
				elif hover is String and equip[hover] != "":
					unequip_requested.emit(hover, -1)


## Удержание ПКМ: счётчик выброса растёт всё быстрее, отпустил — выбросили.
func start_hold(key, mx: int) -> void:
	hold_key = key
	hold_t = 0.0
	hold_n = 1
	hold_max = maxi(mx, 1)
	_update_hold_label()


func _process(delta: float) -> void:
	if hold_key == null:
		return
	hold_t += delta
	if hold_t > 0.25:
		hold_n = mini(hold_max, 1 + int(pow((hold_t - 0.25) * 4.0, 1.6)))
	_update_hold_label()


func _update_hold_label() -> void:
	var nm := "монет"
	if hold_key is int:
		nm = Items.item_name(slots[hold_key]["id"]) if slots[hold_key] != null else ""
	hold_l.text = "Выбросить: %d / %d  %s" % [hold_n, hold_max, nm]
	hold_l.visible = true
	hold_l.position = root.get_local_mouse_position() + Vector2(18, -8)


func _finish_hold() -> void:
	var k = hold_key
	hold_key = null
	hold_l.visible = false
	if k is String:
		drop_coins_requested.emit(hold_n)
	elif slots[k] != null:
		drop_count_requested.emit(k, hold_n)


func _bind_hover(k: int) -> void:
	if hover == null:
		return
	var id := ""
	if hover is String:
		id = equip[hover]
	elif slots[hover] != null:
		id = slots[hover]["id"]
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
	set_hover(null)


func close() -> void:
	if not open:
		return
	open = false
	root.visible = false
	hover = null
	hold_key = null
	hold_l.visible = false
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


## Перетаскивание: from/to — номер ячейки или имя слота экипировки.
func move(from, to) -> void:
	if typeof(from) == typeof(to) and from == to:
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


# ---------- данные ----------

## Добавить предметы; возвращает, сколько не влезло. Монеты идут в кошелёк.
func add(id: String, n: int) -> int:
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
		wallet_l.text = "Монеты: %d   (ПКМ — выбросить)" % coins
	if open:
		set_hover(hover)
		_rebuild_craft()
	changed.emit()
