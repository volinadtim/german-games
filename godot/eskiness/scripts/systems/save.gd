extends RefCounted
## Сохранения (промпт 18.11 02:00): сколько угодно сейвов, каждый — свой файл user://saves/<id>.json.
## Старые слоты user://save_1..3.json видны как сейвы с id «1».."3" и продолжают работать как раньше.
## Что именно пишется — решает game.gd (save_state / load_state).
## Какой сейв играть, menu.gd передаёт через Engine meta:
##   eskiness_slot — id сейва (String), eskiness_load — true, если его надо загрузить,
##   eskiness_crash — true, если грузить аварийную копию (<id>.crash.json).
## Аварийная копия пишется при вылете игры (game.gd: NOTIFICATION_CRASH) и основной сейв не перезаписывает.

const DIR := "user://saves"
const LEGACY := 3            # прежние слоты save_1..save_3
const CFG := "user://settings.cfg"
const SLOTS := LEGACY        # совместимость со старым кодом


static func path(id: String) -> String:
	if id.is_valid_int() and int(id) >= 1 and int(id) <= LEGACY:
		return "user://save_%d.json" % int(id)
	return "%s/%s.json" % [DIR, id]


## Аварийная копия рядом с сейвом — отдельный файл, основной не трогает.
static func crash_path(id: String) -> String:
	return path(id).trim_suffix(".json") + ".crash.json"


static func exists(id: String) -> bool:
	return id != "" and FileAccess.file_exists(path(id))


static func crash_exists(id: String) -> bool:
	return id != "" and FileAccess.file_exists(crash_path(id))


static func new_id() -> String:
	var t := Time.get_datetime_dict_from_system(false)
	var base := "g%04d%02d%02d_%02d%02d%02d" % [t["year"], t["month"], t["day"], t["hour"], t["minute"], t["second"]]
	var id := base
	var k := 1
	while exists(id):
		id = "%s_%d" % [base, k]
		k += 1
	return id


static func write(id: String, data: Dictionary) -> void:
	_write_file(path(id), data)


## Аварийное сохранение: тот же сейв, но в отдельный файл (вылет игры не ломает основной).
static func write_crash(id: String, data: Dictionary) -> void:
	data = data.duplicate()
	data["crash"] = true
	_write_file(crash_path(id), data)


static func _write_file(p: String, data: Dictionary) -> void:
	data["saved_at"] = Time.get_datetime_string_from_system(false, true)
	DirAccess.make_dir_recursive_absolute(DIR)
	var txt := JSON.stringify(data)
	# сначала во временный файл, потом подменяем: вылет посреди записи не портит сейв
	var f := FileAccess.open(p + ".tmp", FileAccess.WRITE)
	if f == null:
		return
	f.store_string(txt)
	f.close()
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	DirAccess.rename_absolute(ProjectSettings.globalize_path(p + ".tmp"), ProjectSettings.globalize_path(p))


## Нормальный выход из игры: аварийная копия больше не нужна.
static func clear_crash(id: String) -> void:
	var p := crash_path(id)
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


static func read(id: String) -> Dictionary:
	return _read_file(path(id))


static func read_crash(id: String) -> Dictionary:
	return _read_file(crash_path(id))


static func _read_file(p: String) -> Dictionary:
	if not FileAccess.file_exists(p):
		return {}
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


static func delete(id: String) -> void:
	for p in [path(id), crash_path(id)]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	if last() == id:
		set_last("")


## Все сейвы: сначала самые свежие (по времени файла). Старые слоты — вместе с новыми.
static func list() -> Array:
	var out: Array = []
	for i in range(1, LEGACY + 1):
		var p := "user://save_%d.json" % i
		if FileAccess.file_exists(p):
			out.append({"id": str(i), "t": FileAccess.get_modified_time(p)})
	var d := DirAccess.open(DIR)
	if d:
		for fn in d.get_files():
			if not fn.ends_with(".json") or fn.ends_with(".crash.json") or fn.ends_with(".tmp"):
				continue
			out.append({"id": fn.trim_suffix(".json"), "t": FileAccess.get_modified_time("%s/%s" % [DIR, fn])})
	out.sort_custom(func(a, b): return int(a["t"]) > int(b["t"]))
	return out.map(func(e): return String(e["id"]))


## Подпись для меню: «14.11 00:12 · 120 монет · 80 hp» или «пусто».
static func summary(id: String) -> String:
	var d := read(id)
	if d.is_empty():
		return "пусто"
	return describe(d)


static func describe(d: Dictionary) -> String:
	if d.is_empty():
		return "пусто"
	var t: String = String(d.get("saved_at", ""))
	var when := ""
	if t.length() >= 16:
		when = "%s.%s %s" % [t.substr(8, 2), t.substr(5, 2), t.substr(11, 5)]
	return "%s · %d монет · %d hp" % [when, int(d.get("coins", 0)), int(ceil(float(d.get("hp", 0))))]


## Последняя сессия — её продолжает кнопка «Продолжить».
static func last() -> String:
	var cf := ConfigFile.new()
	var id := ""
	if cf.load(CFG) == OK:
		id = String(cf.get_value("game", "last_save", ""))
	if exists(id):
		return id
	var all := list()
	return String(all[0]) if not all.is_empty() else ""


static func set_last(id: String) -> void:
	var cf := ConfigFile.new()
	cf.load(CFG)
	cf.set_value("game", "last_save", id)
	cf.save(CFG)


static func slot() -> String:
	return String(Engine.get_meta("eskiness_slot", ""))
