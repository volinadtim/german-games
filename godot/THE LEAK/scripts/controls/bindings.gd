extends RefCounted
## Таблица управления: data/controls/bindings.cfg (умолчания) + user://controls.cfg (переназначения игрока).
## Паттерн Configuration Object: всё про кнопки — здесь, скрипты знают только имена действий.
## Спецификации: клавиатура/мышь "k:<physical_keycode>" | "m:<кнопка мыши>"; геймпад "b:N" | "c:N" (Back + N) | "t:L"/"t:R".

const TABLE := "res://data/controls/bindings.cfg"
const USER := "user://controls.cfg"
const LEGACY := "user://settings.cfg"   # до controls.cfg переназначения лежали здесь ([controls], [pad]/[pad2] custom)
const ALL_MODES := ["game", "car", "inventory", "menu", "console"]

var order: Array[String] = []    # действия в порядке таблицы
var rows := {}                   # действие -> {label, group, keys, pad, pad_axis, pad_raw, modes, hint}
var kb_user := {}                # действие -> [основная, альтернативная] (только изменённые игроком)
var pad_user := {}               # "pad"/"pad2" -> {действие: спецификация} — «Свой» пресет геймпада
var hint_keys := {}              # "F" -> "interact": буква старой подсказки «[F]» -> действие


func load_table() -> void:
	var cf := ConfigFile.new()
	if cf.load(TABLE) != OK:
		push_error("controls: не читается " + TABLE)
		return
	order.clear()
	rows.clear()
	hint_keys.clear()
	for a in cf.get_sections():
		var r := {
			"label": str(cf.get_value(a, "label", a)),
			"group": str(cf.get_value(a, "group", "")),
			"keys": Array(cf.get_value(a, "keys", [])),
			"pad": str(cf.get_value(a, "pad", "")),
			"pad_axis": str(cf.get_value(a, "pad_axis", "")),
			"pad_raw": bool(cf.get_value(a, "pad_raw", false)),
			"modes": Array(cf.get_value(a, "modes", ["game", "car", "inventory"])),
			"hint": Array(cf.get_value(a, "hint", [])),
		}
		rows[a] = r
		order.append(a)
		for h in r["hint"]:
			if not hint_keys.has(str(h)):
				hint_keys[str(h)] = a


## Переназначения игрока. Нет controls.cfg — переносим из старого settings.cfg (его не трогаем: старые сборки читают его).
func load_user() -> void:
	kb_user.clear()
	pad_user = {"pad": {}, "pad2": {}}
	var cf := ConfigFile.new()
	if cf.load(USER) == OK:
		for a in cf.get_section_keys("keys") if cf.has_section("keys") else []:
			var v = cf.get_value("keys", a)
			if v is Array and not v.is_empty():
				kb_user[a] = v
		for sec in ["pad", "pad2"]:
			var c = cf.get_value(sec, "custom", {})
			pad_user[sec] = c if c is Dictionary else {}
	else:
		_migrate_legacy()
	_fix_old()


func save_user() -> void:
	var cf := ConfigFile.new()
	for a in kb_user:
		cf.set_value("keys", a, kb_user[a])
	for sec in pad_user:
		cf.set_value(sec, "custom", pad_user[sec])
	cf.save(USER)


func _migrate_legacy() -> void:
	var cf := ConfigFile.new()
	if cf.load(LEGACY) != OK:
		return
	if cf.has_section("controls"):
		for a in cf.get_section_keys("controls"):
			var v = cf.get_value("controls", a)
			if v is Array and not v.is_empty():
				kb_user[a] = v
	for sec in ["pad", "pad2"]:
		var c = cf.get_value(sec, "custom", {})
		pad_user[sec] = c if c is Dictionary else {}
	if not kb_user.is_empty() or not pad_user["pad"].is_empty() or not pad_user["pad2"].is_empty():
		save_user()


## Старые сохранённые значения, которые Герман велел сбросить (раньше это делал menu.gd: _load).
func _fix_old() -> void:
	# «Удар» → «Удар левой» (промпт 18:57)
	if kb_user.has("attack"):
		if not kb_user.has("attack_left"):
			kb_user["attack_left"] = kb_user["attack"]
		kb_user.erase("attack")
	# стойка на СКМ (промпт 16.11 02:15): сохранённая V и старые «fists_down»/«throw_stone» сбрасываются
	if kb_user.has("fists") and "k:86" in kb_user["fists"]:
		kb_user.erase("fists")
	kb_user.erase("fists_down")
	# противогаз перенесён с G на V, сброс — только G (промпт 18:13)
	if kb_user.get("gasmask", []) == ["k:71"]:
		kb_user.erase("gasmask")
	if kb_user.has("drop_mode") and "k:72" in kb_user["drop_mode"]:
		kb_user.erase("drop_mode")
	kb_user.erase("throw_stone")
	for a in kb_user.keys():
		if not rows.has(a) or str(rows[a]["group"]) == "":
			kb_user.erase(a)   # действия, которых больше нет (или не переназначаются)
	# новые действия — в старый «Свой» пресет геймпада, если их кнопка там свободна
	for sec in pad_user:
		var c: Dictionary = pad_user[sec]
		if c.is_empty():
			continue
		c.erase("pad_cursor")   # курсор в игре убран (промпт 20.11 15:04)
		for a in ["drop_mode", "hot_wheel", "toggle_cursor"]:
			var d := str(rows.get(a, {}).get("pad", ""))
			if d != "" and not c.has(a) and not d in c.values():
				c[a] = d


## Клавиши по умолчанию: всегда [основная, альтернативная] ("" — нет).
func kb_default(a: String) -> Array:
	var k: Array = rows[a]["keys"] if rows.has(a) else []
	return [str(k[0]) if k.size() > 0 else "", str(k[1]) if k.size() > 1 else ""]


## Клавиши сейчас (с переназначением игрока). Действия со своими тремя и больше клавишами — все из таблицы.
func kb_of(a: String) -> Array:
	if kb_user.has(a):
		var b: Array = kb_user[a].duplicate()
		while b.size() < 2:
			b.append("")
		return b.slice(0, 2)
	if rows.has(a) and (rows[a]["keys"] as Array).size() > 2:
		return (rows[a]["keys"] as Array).duplicate()
	return kb_default(a)


## Геймпад по умолчанию: действие -> спецификация (кроме pad_raw — их проверяют окна сами).
func pad_defaults() -> Dictionary:
	var d := {}
	for a in order:
		var r: Dictionary = rows[a]
		if str(r["pad"]) != "" and not bool(r["pad_raw"]):
			d[a] = str(r["pad"])
	return d


## Оси ходьбы: действие -> ["lx"|"ly"|"none", ±1.0].
func pad_axes() -> Dictionary:
	var d := {}
	for a in order:
		var s := str(rows[a]["pad_axis"])
		if s.length() >= 2:
			d[a] = [s.left(s.length() - 1), -1.0 if s.ends_with("-") else 1.0]
	return d


static func spec_event(spec: String) -> InputEvent:
	var p := spec.split(":")
	if p.size() != 2:
		return null
	if p[0] == "k":
		var ev := InputEventKey.new()
		ev.physical_keycode = int(p[1]) as Key
		return ev
	if p[0] == "m":
		var mb := InputEventMouseButton.new()
		mb.button_index = int(p[1]) as MouseButton
		return mb
	return null
