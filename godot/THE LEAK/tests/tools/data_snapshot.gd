extends Node
## Снимок настраиваемых значений (одноразовый инструмент перехода DataTable -> типизированные ресурсы).
##   godot --headless --path "godot/THE LEAK" res://tests/tools/data_snapshot.tscn -- save <файл.json>
##     ищет в scripts/ строки `static var X… = _D_….v("X")` и пишет значения этих static var (var_to_str);
##   godot … res://tests/tools/data_snapshot.tscn -- check <файл.json>
##     берёт тот же список (скрипт, имя) и сравнивает текущие значения со снимком. Печатает SNAP OK / SNAP DIFF.

var _re := RegEx.create_from_string("^static var ([A-Za-z_0-9]+)[^=]*= *_D_[A-Z_0-9]+\\.v\\(")


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var mode: String = args[0] if args.size() > 0 else ""
	var path: String = args[1] if args.size() > 1 else ""
	if mode == "save":
		var out := {}
		for f in _scripts("res://scripts"):
			var names: Array = []
			for line in FileAccess.get_file_as_string(f).split("\n"):
				var m := _re.search(line)
				if m:
					names.append(m.get_string(1))
			if names.is_empty():
				continue
			var s: GDScript = load(f)
			var vals := {}
			for n in names:
				vals[n] = _ser(s.get(n))
			out[f] = vals
		var fa := FileAccess.open(path, FileAccess.WRITE)
		fa.store_string(JSON.stringify(out, " ", false))
		var cnt := 0
		for f in out:
			cnt += out[f].size()
		print("SNAP SAVED %d values in %d scripts" % [cnt, out.size()])
	elif mode == "check":
		var snap: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var bad := 0
		var cnt := 0
		for f in snap:
			var s: GDScript = load(f)
			for n in snap[f]:
				cnt += 1
				var now := _ser(s.get(n))
				if now != snap[f][n] and _sorted(now) == _sorted(snap[f][n]):
					print("SNAP ORDER %s %s (те же значения, другой порядок ключей словаря)" % [f, n])
				elif now != snap[f][n] and _loose(now) == _loose(snap[f][n]):
					print("SNAP TYPE %s %s (только int/float): %s -> %s" % [f, n, snap[f][n], now])
				elif now != snap[f][n]:
					bad += 1
					print("SNAP DIFF %s %s\n  было:  %s\n  стало: %s" % [f, n, snap[f][n], now])
		print("SNAP OK %d values" % cnt if bad == 0 else "SNAP DIFF %d of %d" % [bad, cnt])
	get_tree().quit()


func _scripts(dir: String) -> Array:
	var out: Array = []
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir + "/" + d))
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	return out


## Как var_to_str, но словари — в порядке ключей (var_to_str сортирует ключи, а порядок важен: доска выплат, списки).
static func _ser(v) -> String:
	if v is Dictionary:
		var parts: PackedStringArray = []
		for k in v:
			parts.append(_ser(k) + ": " + _ser(v[k]))
		return "{" + ", ".join(parts) + "}"
	if v is Array:
		var parts2: PackedStringArray = []
		for x in v:
			parts2.append(_ser(x))
		return "[" + ", ".join(parts2) + "]"
	return var_to_str(v)


## Без разницы int/float: «6.0» -> «6».
static func _loose(s: String) -> String:
	return RegEx.create_from_string("(?<![0-9.])([0-9]+)\\.0(?![0-9])").sub(s, "$1", true)


## Снимок -> var_to_str (тот сортирует ключи словарей): сравнение без учёта порядка ключей.
static func _sorted(s: String) -> String:
	return var_to_str(str_to_var(s))
