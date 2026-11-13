extends RefCounted
## Сохранения: 3 слота в user://save_1..3.json. Что именно пишется — решает game.gd (save_state / load_state).
## Какой слот играть и грузить ли его, menu.gd передаёт через Engine meta:
##   eskiness_slot — номер слота (1..3), eskiness_load — true, если слот надо загрузить.

const SLOTS := 3


static func path(i: int) -> String:
	return "user://save_%d.json" % i


static func exists(i: int) -> bool:
	return FileAccess.file_exists(path(i))


static func write(i: int, data: Dictionary) -> void:
	data["saved_at"] = Time.get_datetime_string_from_system(false, true)
	var f := FileAccess.open(path(i), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


static func read(i: int) -> Dictionary:
	if not exists(i):
		return {}
	var f := FileAccess.open(path(i), FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


static func delete(i: int) -> void:
	if exists(i):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path(i)))


## Подпись для меню: «14.11 00:12 · 120 монет · 80 hp» или «пусто».
static func summary(i: int) -> String:
	var d := read(i)
	if d.is_empty():
		return "пусто"
	var t: String = String(d.get("saved_at", ""))
	var when := ""
	if t.length() >= 16:
		when = "%s.%s %s" % [t.substr(8, 2), t.substr(5, 2), t.substr(11, 5)]
	return "%s · %d монет · %d hp" % [when, int(d.get("coins", 0)), int(ceil(float(d.get("hp", 0))))]


static func slot() -> int:
	return int(Engine.get_meta("eskiness_slot", 1))
