extends Node
## Отчёт для разработчиков (autoload «BugReport»): клавиша «Отчёт» (F8, data/controls/bindings.cfg) сохраняет в
## user://reports/<дата_время>/ скриншот (screen.png) и report.txt: место и координаты игрока, куда смотрит,
## устройство ввода, признаки Steam Input, версия и коммит, последние ошибки и предупреждения.
## Ещё: подсказка игроку, если похоже, что Steam Input перехватывает геймпад (scripts/controls/router.gd).

const Router := preload("res://scripts/controls/router.gd")
const KEEP := 60   # сколько последних ошибок помнить

var _log: ErrLog
var _steam_hint_done := false
var _mouse_while_pad := 0   # движений мыши подряд при нажатом геймпаде (Steam Input шлёт мышь вместо стика)


class ErrLog extends Logger:
	var lines: PackedStringArray = []
	var mx := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
		var kind := "ПРЕДУПРЕЖДЕНИЕ" if error_type == ERROR_TYPE_WARNING else "ОШИБКА"
		_add("%s %s: %s (%s:%d %s)" % [Time.get_time_string_from_system(), kind, rationale if rationale != "" else code, file, line, function])

	func _log_message(message: String, error: bool) -> void:
		if error:
			_add(Time.get_time_string_from_system() + " " + message.strip_edges())

	func _add(t: String) -> void:
		mx.lock()
		lines.append(t)
		if lines.size() > KEEP:
			lines = lines.slice(lines.size() - KEEP)
		mx.unlock()

	func last() -> PackedStringArray:
		mx.lock()
		var c := lines.duplicate()
		mx.unlock()
		return c


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_log = ErrLog.new()
	OS.add_logger(_log)


func _ready() -> void:
	Input.joy_connection_changed.connect(func(_d, _c): _steam_check.call_deferred())


func _input(e: InputEvent) -> void:
	if Controls.event(e, "report"):
		get_viewport().set_input_as_handled()
		save_report.call_deferred()
		return
	# геймпад приходит как мышь: Steam Input с «рабочим столом» вместо игровой раскладки
	if e is InputEventMouseMotion and e.device != 77 and Input.get_connected_joypads().is_empty() and OS.has_environment("SteamAppId"):
		_mouse_while_pad += 1


## Найти игру (core/game.gd) в текущей сцене.
func _game() -> Node:
	var cs := get_tree().current_scene
	if cs == null:
		return null
	for c in cs.get_children():
		if c.has_method("save_now"):
			return c
	return null


## Где игрок: ближайшая из точек /tp (console.gd) + флаги деревни (озеро, город).
static func location_of(game) -> String:
	if game == null or game.player == null:
		return "меню"
	var v = game.get("village")
	if v != null and bool(v.get("at_city")):
		return "город"
	if v != null and bool(v.get("at_lake")):
		return "озеро"
	var con: Node = null
	for c in game.get_children():
		if c.has_method("_tp_places"):
			con = c
	if con == null:
		return "?"
	var best := "?"
	var bd := INF
	for pl in con.call("_tp_places"):
		var d: float = (game.player.global_position as Vector3).distance_to(pl[2])
		if d < bd:
			bd = d
			best = str(pl[0])
	return best


## Что под прицелом: луч из камеры игрока на 60 м. [узел, точка, расстояние] или [].
static func aim_hit(game) -> Array:
	if game == null or game.player == null or game.player.get("cam") == null:
		return []
	var cam: Camera3D = game.player.cam
	var from := cam.global_position
	var to := from - cam.global_transform.basis.z * 60.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [game.player.get_rid()]
	q.collide_with_areas = true
	var hit: Dictionary = cam.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return []
	return [hit.collider, hit.position, from.distance_to(hit.position)]


static func node_desc(n: Object) -> String:
	if n == null:
		return "—"
	var s = n.get_script()
	var sc: String = s.resource_path.trim_prefix("res://") if s else ""
	var nm := String(n.name) if n is Node else str(n)
	var path := str((n as Node).get_path()) if n is Node and (n as Node).is_inside_tree() else ""
	var gp := ""
	if n is Node3D:
		gp = " в " + _v(n.global_position)
	return "%s%s%s  %s" % [nm, (" (" + sc + ")") if sc != "" else "", gp, path]


static func _v(p: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [p.x, p.y, p.z]


## Коммит игры: .git рядом с проектом (у Германа игра запускается из папки репозитория).
static func commit() -> String:
	var dir := ProjectSettings.globalize_path("res://").rstrip("/")
	for i in 5:
		var g := dir + "/.git"
		var gd := g
		if FileAccess.file_exists(g):   # worktree: в .git лежит «gitdir: …»
			gd = FileAccess.get_file_as_string(g).strip_edges().trim_prefix("gitdir:").strip_edges()
		if DirAccess.dir_exists_absolute(gd):
			var head := FileAccess.get_file_as_string(gd + "/HEAD").strip_edges()
			if head.begins_with("ref:"):
				var ref := head.trim_prefix("ref:").strip_edges()
				var h := FileAccess.get_file_as_string(gd + "/" + ref).strip_edges()
				if h == "" and FileAccess.file_exists(gd + "/commondir"):
					var common := gd + "/" + FileAccess.get_file_as_string(gd + "/commondir").strip_edges()
					h = FileAccess.get_file_as_string(common + "/" + ref).strip_edges()
				return "%s (%s)" % [h.left(10), ref.get_file()]
			return head.left(10)
		dir = dir.get_base_dir()
	return "неизвестно (не из папки репозитория)"


func device_text() -> String:
	var t := "последний ввод: %s" % Controls.kind()
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		t += "; геймпадов не видно"
	for d in pads:
		t += "; геймпад %d: %s (%s)" % [d, Input.get_joy_name(d), str(Input.get_joy_info(d))]
	var st := []
	for k in ["SteamAppId", "SteamGameId", "SteamClientLaunch", "SteamOverlayGameId"]:
		if OS.has_environment(k):
			st.append(k)
	t += "\nSteam: %s; похоже на перехват Steam Input: %s; движений мыши без геймпада под Steam: %d" % [
		", ".join(st) if not st.is_empty() else "не запущен", "да" if Router.steam_input_suspect() else "нет", _mouse_while_pad]
	return t


## F8: скриншот и report.txt в user://reports/<время>/.
func save_report() -> void:
	await get_tree().process_frame   # кадр с закрытой консолью (frame_post_draw без окна не приходит)
	var stamp := Time.get_datetime_string_from_system(false, false).replace(":", "-").replace("T", "_")
	var dir := "user://reports/" + stamp
	DirAccess.make_dir_recursive_absolute(dir)
	if DisplayServer.get_name() != "headless":   # без окна (smoke.sh) картинки нет
		var img := get_viewport().get_texture().get_image()
		if img:
			img.save_png(dir + "/screen.png")
	var g := _game()
	var t := PackedStringArray()
	t.append("THE LEAK — отчёт %s" % Time.get_datetime_string_from_system(false, true))
	t.append("версия: %s, коммит: %s, Godot %s, %s" % [str(ProjectSettings.get_setting("application/config/version", "—")), commit(),
		Engine.get_version_info().get("string", ""), OS.get_name()])
	t.append("место: " + location_of(g))
	if g != null and g.player != null:
		var p: Node3D = g.player
		t.append("игрок: %s, поворот %.1f°, взгляд %.1f°" % [_v(p.global_position), rad_to_deg(p.rotation.y), rad_to_deg(p.head.rotation.x) if p.get("head") else 0.0])
		var hit := aim_hit(g)
		t.append("под прицелом: " + (node_desc(hit[0]) + "  точка " + _v(hit[1]) + ", %.1f м" % hit[2] if not hit.is_empty() else "ничего (60 м)"))
		t.append("режим ввода: " + Controls.mode())
	t.append(device_text())
	t.append("")
	t.append("последние ошибки и предупреждения:")
	var errs := _log.last()
	t.append("\n".join(errs) if not errs.is_empty() else "нет")
	var f := FileAccess.open(dir + "/report.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(t) + "\n")
		f.close()
	var where := ProjectSettings.globalize_path(dir)
	print("Отчёт: " + where)
	if g != null and g.get("hud") != null:
		g.hud.toast("Отчёт сохранён: " + where)


## Подсказка игроку: похоже, Steam Input перехватывает геймпад.
func _steam_check() -> void:
	if _steam_hint_done or not Router.steam_input_suspect():
		return
	var g := _game()
	if g == null or g.get("hud") == null:
		return
	_steam_hint_done = true
	g.hud.toast("Похоже, геймпад перехватывает Steam Input. В Steam: свойства игры → Контроллер → «Отключить Steam Input».",
		Color(1.0, 0.85, 0.5), true)


## Вызывает game.gd после запуска игры: проверка Steam Input.
func game_started() -> void:
	_steam_check.call_deferred()
