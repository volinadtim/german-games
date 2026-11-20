extends RefCounted
## Роутер устройств: какой ввод у какого игрока и что сейчас в руках у игрока 1.
## Сплитскрин (network/split.gd): игрок 1 — клавиатура и мышь (и первый геймпад, если их два), игрок 2 — геймпад.
## Вид ввода для подсказок — по последнему вводу (ui/ui_nav.gd: pad_used / by_kb, ui/gamepad.gd: ps).

const Glyphs := preload("res://scripts/controls/glyphs.gd")
const Split := preload("res://scripts/network/split.gd")
const Pad := preload("res://scripts/controls/gamepad.gd")


## Вид последнего ввода игрока 1: "kb" | "xbox" | "ps".
static func kind() -> String:
	var i = Pad.inst
	if i == null or not is_instance_valid(i) or i.nav == null or not i.nav.pad_used or i.nav.by_kb:
		return Glyphs.KB
	return Glyphs.PS if Pad.ps else Glyphs.XBOX


## Вид ввода игрока idx (1 или 2): у игрока 2 в сплитскрине — всегда геймпад.
static func kind_of(idx: int) -> String:
	if idx == 2:
		var d := Split.pad_device(true)
		return Glyphs.PS if d >= 0 and Pad.is_ps(d) else Glyphs.XBOX
	return kind()


## Геймпад игрока idx: номер устройства, -1 — любой, -2 — никакой (только клавиатура и мышь).
static func pad_of(idx: int) -> int:
	if Split.inst == null or not is_instance_valid(Split.inst):
		return -1 if idx == 1 else -2
	return Split.pad_device(idx == 2)


## Похоже, что Steam Input перехватил геймпад: Steam запущен (переменные окружения его оверлея),
## а Godot геймпадов не видит или видит только виртуальный «Steam Virtual Gamepad» / мышь-эмуляцию.
static func steam_input_suspect() -> bool:
	var steam := OS.has_environment("SteamAppId") or OS.has_environment("SteamGameId") or OS.has_environment("SteamClientLaunch") \
		or OS.has_environment("SteamOverlayGameId")
	var pads := Input.get_connected_joypads()
	for d in pads:
		var n := (Input.get_joy_name(d) + " " + str(Input.get_joy_info(d).get("raw_name", ""))).to_lower()
		if "steam" in n and "virtual" in n:
			return true
	return steam and pads.is_empty()
