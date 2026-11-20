extends RefCounted
## Глифы подсказок: имя клавиши / кнопки для трёх видов ввода — клавиатура и мышь, Xbox, DualSense (PlayStation).
## Godot (SDL) нумерует кнопки по положению: 0 — нижняя (A / ✕), 1 — правая (B / ○), 2 — левая (X / □), 3 — верхняя (Y / △).

const KB := "kb"
const XBOX := "xbox"
const PS := "ps"
const MOD := 4   # JOY_BUTTON_BACK — модификатор «Back + кнопка»

const MOUSE := {1: "ЛКМ", 2: "ПКМ", 3: "Колёсико", 4: "Колесо вверх", 5: "Колесо вниз", 8: "Мышь 4", 9: "Мышь 5"}
const KEYS := {32: "Пробел", 4194325: "Shift", 4194326: "Ctrl", 4194328: "Alt", 4194306: "Tab",
	4194319: "←", 4194321: "→", 4194320: "↑", 4194322: "↓"}
const XBOX_BTN := {0: "A", 1: "B", 2: "X", 3: "Y", 4: "Back", 5: "Guide", 6: "Start", 7: "L3", 8: "R3",
	9: "LB", 10: "RB", 11: "↑", 12: "↓", 13: "←", 14: "→", 15: "Share"}
const PS_BTN := {0: "✕", 1: "○", 2: "□", 3: "△", 4: "Create", 5: "PS", 6: "Options", 7: "L3", 8: "R3",
	9: "L1", 10: "R1", 11: "↑", 12: "↓", 13: "←", 14: "→", 15: "Mute", 20: "Тачпад"}


## Клавиатура/мышь: "k:N" / "m:N" -> «F», «Пробел», «ЛКМ»; "" -> «—».
static func kb_name(spec: String) -> String:
	var p := spec.split(":")
	if p.size() != 2:
		return "—"
	var n := int(p[1])
	if p[0] == "m":
		return MOUSE.get(n, "Мышь %d" % n)
	if KEYS.has(n):
		return KEYS[n]
	# физический код = клавиша на американской раскладке (латинские буквы при любой раскладке)
	var s := OS.get_keycode_string(n as Key)
	return s if s != "" else "?"


## Геймпад: "b:N" / "c:N" / "t:L" -> «A», «Back + A», «LT» (или ✕, Create + ✕, L2 для DualSense).
static func pad_name(spec: String, kind := XBOX) -> String:
	if spec == "":
		return "—"
	var p := spec.split(":")
	if p.size() != 2:
		return "?"
	if p[0] == "t":
		if kind == PS:
			return "L2" if p[1] == "L" else "R2"
		return "LT" if p[1] == "L" else "RT"
	var n := btn_name(int(p[1]), kind)
	return (btn_name(MOD, kind) + " + " + n) if p[0] == "c" else n


static func btn_name(b: int, kind := XBOX) -> String:
	if kind == PS:
		return PS_BTN.get(b, "Кнопка %d" % b)
	return XBOX_BTN.get(b, "Кнопка %d" % b)
