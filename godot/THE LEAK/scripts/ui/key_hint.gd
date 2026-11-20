extends Node
## Подсказки клавиш на кнопках и надписях окон под последний ввод (промпт 20.11 15:14): с геймпада — кнопки геймпада,
## с клавиатуры/мыши — клавиши. Имена кнопок и «последний ввод» — из ui/gamepad.gd (pad_text, spec_name, nav.pad_used).
## Текст для геймпада: «{действие}» или «{b:N}» — имя кнопки по текущей раскладке; пустой — Gamepad.pad_text(текст клавиатуры).
## attach() вешает узел-ребёнок на контрол: он сам обновляет text / tooltip_text при смене ввода.

const Pad := preload("res://scripts/ui/gamepad.gd")

var kb := ""
var pad_t := ""
var prop := "text"
var _t := 0.0


## Последний ввод — геймпад (не клавиатура/мышь).
static func is_pad() -> bool:
	var i = Pad.inst
	return i != null and is_instance_valid(i) and i.nav != null and i.nav.pad_used and not i.nav.by_kb


## Текст под текущий ввод: kb — для клавиатуры, pad — для геймпада ({действие}/{b:N}); pad пустой — pad_text(kb).
static func fmt(kb_text: String, pad_text := "") -> String:
	if not is_pad():
		return kb_text
	if pad_text == "":
		return Pad.pad_text(kb_text)
	var re := RegEx.create_from_string("\\{([a-z_0-9:]+)\\}")
	var out := pad_text
	var ms := re.search_all(pad_text)
	for i in range(ms.size() - 1, -1, -1):
		var m: RegExMatch = ms[i]
		var tok := m.get_string(1)
		var nm := Pad.spec_name(tok) if ":" in tok else Pad.spec_name(Pad.inst.spec_of(tok))
		out = out.substr(0, m.get_start()) + nm + out.substr(m.get_end())
	return out


## Повесить подсказку на контрол c: prop — "text" или "tooltip_text". Обновляется сама.
static func attach(c: Node, kb_text: String, pad_text := "", property := "text") -> void:
	for ch in c.get_children():
		if ch.get_script() == load("res://scripts/ui/key_hint.gd"):
			ch.queue_free()
	var n = load("res://scripts/ui/key_hint.gd").new()
	n.kb = kb_text
	n.pad_t = pad_text
	n.prop = property
	c.set(property, fmt(kb_text, pad_text))
	c.add_child(n)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.2
	var p := get_parent()
	if p == null or not p.is_visible_in_tree():
		return
	var s := fmt(kb, pad_t)
	if str(p.get(prop)) != s:
		p.set(prop, s)
