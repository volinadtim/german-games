extends CanvasLayer
## Внутриигровая консоль: F1 — открыть/закрыть, Enter — выполнить, ↑/↓ — история, Esc — закрыть.
## Пока открыта, ввод игрока не обрабатывается (player.active = false, инвентарь выключен).
## Создаётся из game.gd (setup) — у каждого игрока своя, команды действуют на локального игрока.
## Новая команда: register("имя", "описание", func(args: PackedStringArray) -> void).
## Читерская команда (money/get/noclip/god и т.п.): register_cheat(...) — работает только после /cheats on.

const Items := preload("res://scripts/items/items.gd")
const VillageBuild := preload("res://scripts/locations/village/village_build.gd")
const LakeCampS := preload("res://scripts/locations/lake/lake_camp.gd")
const CityS := preload("res://scripts/locations/city/city.gd")
const SUGG_ROWS := 8      # сколько строк подсказок /get видно сразу

var game   # core/game.gd
var open := false
var sugg_l: RichTextLabel   # подсказки предметов над полем (после «/get »)
var sugg: Array = []        # id подходящих предметов
var sugg_tp := false       # подсказки — места для /tp, а не предметы
var sugg_i := -1            # выделенный
var commands := {}        # имя -> {"desc": String, "fn": Callable, "cheat": bool}
var cheats_on := false   # /cheats on|off — разблокирует читерские команды
var history: PackedStringArray = []
var hist_i := 0

var root: Control
var log_l: RichTextLabel
var edit: LineEdit

var _prev_mouse := Input.MOUSE_MODE_CAPTURED

var _freecam: Camera3D = null
var _prev_cam: Camera3D = null
var _freecam_rot := Vector2.ZERO
var _freecam_speed := 10.0


func _ready() -> void:
	layer = 90
	_build_ui()
	register("help", "список команд", _cmd_help)
	register("clear", "очистить лог", func(_a: PackedStringArray): log_l.clear())
	register("cheats", "/cheats on|off — включить/выключить читерские команды", _cmd_cheats)
	register_cheat("money", "/money [кол-во] — выдать монеты (по умолчанию 100)", _cmd_money)
	register_cheat("get", "/get [предмет] [кол-во] — выдать предмет (Tab — подсказки, места нет — под ноги)", _cmd_get)
	register_cheat("noclip", "/noclip — полёт сквозь стены вкл/выкл (WASD, Пробел — вверх, Ctrl — вниз, Shift — быстрее)", _cmd_noclip)
	register_cheat("ncspeed", "/ncspeed [x] — скорость полёта в noclip (по умолчанию 8; также колёсико мыши)", _cmd_ncspeed)
	register_cheat("tp", "/tp бункер|деревня|озеро|город — телепорт (Tab — список мест)", _cmd_tp)
	register_cheat("god", "/god — неуязвимость (урон и отравление не берут) вкл/выкл", _cmd_god)
	register_cheat("freecam", "/freecam — свободная камера вкл/выкл (WASD, Пробел/Ctrl, Shift, Колёсико — скорость)", _cmd_freecam)
	register_cheat("time", "/time [час 0-24 | day | night | dawn | dusk | reset] — время суток", _cmd_time)
	register_cheat("timespeed", "/timespeed [x] — скорость смены суток (1 — обычно, 0 — стоп, 10 — быстро)", _cmd_timespeed)
	register_cheat("slowmo", "/slowmo [x] — скорость всей игры (1 — обычно, 0.3 — замедление, 2 — ускорение)", _cmd_slowmo)
	register_cheat("stat", "/stat [dmg|speed|jump|taken|reset] [x] — множители урона, скорости, прыжка, получаемого урона", _cmd_stat)
	print_line("[color=#9a9]Консоль. /help — список команд.[/color]")
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if _freecam == null or not is_instance_valid(_freecam) or open:
		return
	var dir := Vector3.ZERO
	var mv := Controls.vector(null, "move_left", "move_right", "move_forward", "move_back")
	dir.x = mv.x
	dir.z = mv.y
	if Controls.pressed(null, "fly_up"): dir.y += 1.0
	if Controls.pressed(null, "fly_down"): dir.y -= 1.0
	if dir != Vector3.ZERO:
		dir = dir.normalized()
		var mult := 3.0 if Controls.pressed(null, "sprint") else 1.0
		var basis := _freecam.global_transform.basis
		_freecam.global_position += (basis.x * dir.x + basis.z * dir.z + Vector3.UP * dir.y) * _freecam_speed * mult * delta


func register(name_: String, desc: String, fn: Callable) -> void:
	commands[name_] = {"desc": desc, "fn": fn, "cheat": false}


## Читерская команда — доступна только после /cheats on (run() проверяет cheats_on).
func register_cheat(name_: String, desc: String, fn: Callable) -> void:
	commands[name_] = {"desc": desc, "fn": fn, "cheat": true}


func print_line(t: String) -> void:
	log_l.append_text(t + "\n")


func _build_ui() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP   # клики не уходят в игру
	root.visible = false
	add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.04, 0.85)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 0.42
	root.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 12
	box.offset_top = 10
	box.offset_right = -12
	box.offset_bottom = -10
	bg.add_child(box)
	log_l = RichTextLabel.new()
	log_l.bbcode_enabled = true
	log_l.scroll_following = true
	log_l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_l.add_theme_font_size_override("normal_font_size", 16)
	log_l.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(log_l)
	sugg_l = RichTextLabel.new()
	sugg_l.bbcode_enabled = true
	sugg_l.fit_content = true
	sugg_l.scroll_active = false
	sugg_l.visible = false
	sugg_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sugg_l.add_theme_font_size_override("normal_font_size", 16)
	box.add_child(sugg_l)
	edit = LineEdit.new()
	edit.text_changed.connect(func(_t: String): _update_sugg())
	edit.placeholder_text = "/help"
	edit.add_theme_font_size_override("font_size", 18)
	edit.keep_editing_on_text_submit = true
	edit.text_submitted.connect(_submit)
	box.add_child(edit)


func _input(e: InputEvent) -> void:
	if game != null and game.player != null and game.player.noclip and not open and e is InputEventMouseButton and e.pressed 			and (_freecam == null or not is_instance_valid(_freecam)):
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			game.player.nc_speed = clampf(game.player.nc_speed * 1.25, 1.0, 300.0)
			get_viewport().set_input_as_handled()
			return
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			game.player.nc_speed = clampf(game.player.nc_speed / 1.25, 1.0, 300.0)
			get_viewport().set_input_as_handled()
			return
	if _freecam != null and is_instance_valid(_freecam) and not open:
		if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_freecam_rot.y -= e.relative.x * 0.0025
			_freecam_rot.x = clampf(_freecam_rot.x - e.relative.y * 0.0025, -PI * 0.49, PI * 0.49)
			_freecam.rotation = Vector3(_freecam_rot.x, _freecam_rot.y, 0.0)
			get_viewport().set_input_as_handled()
			return
		elif e is InputEventMouseButton and e.pressed:
			if e.button_index == MOUSE_BUTTON_WHEEL_UP:
				_freecam_speed = clampf(_freecam_speed * 1.25, 1.0, 200.0)
				get_viewport().set_input_as_handled()
				return
			elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_freecam_speed = clampf(_freecam_speed / 1.25, 1.0, 200.0)
				get_viewport().set_input_as_handled()
				return
	if not (e is InputEventKey and e.pressed):
		return
	if Controls.event(e, "console"):
		get_viewport().set_input_as_handled()
		toggle()
		return
	if not open:
		return
	# кнопки поля ввода — встроенные действия ui_* (Esc, ↑, ↓, Tab, Enter)
	var k := ""
	for a in ["ui_cancel", "ui_up", "ui_down", "ui_focus_next", "ui_focus_prev", "ui_text_submit"]:
		if Controls.event(e, a, true) and k == "":
			k = a
	match k:
		"ui_cancel":
			get_viewport().set_input_as_handled()
			close()
		"ui_up":
			get_viewport().set_input_as_handled()
			_hist(-1)
		"ui_down":
			get_viewport().set_input_as_handled()
			_hist(1)
		"ui_focus_next", "ui_focus_prev":
			get_viewport().set_input_as_handled()   # не уводить фокус с поля
			_sugg_tab(-1 if e.shift_pressed else 1)
		"ui_text_submit":
			# подсказка выделена, а в поле ещё не она — сначала подставить, второй Enter выполнит
			if sugg_l.visible and sugg_i >= 0 and _norm(edit.text) != _norm(_sugg_text(sugg_i)):
				get_viewport().set_input_as_handled()
				_apply_sugg()


func toggle() -> void:
	if open:
		close()
	else:
		show_console()


func show_console() -> void:
	if open or game == null or game.player == null:
		return
	open = true
	Controls.mode_on("console", self)   # консоль глушит все игровые кнопки (scripts/controls/modes.gd)
	root.visible = true
	_prev_mouse = Input.mouse_mode
	game.player.set_lock("console", true)   # независимая блокировка: не перетирает кат-сцены (промпт 16.11 04:51)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hist_i = history.size()
	edit.clear()
	_update_sugg()
	edit.grab_focus.call_deferred()


func close() -> void:
	if not open:
		return
	open = false
	Controls.mode_off("console", self)
	root.visible = false
	edit.release_focus()
	if game and game.player:
		game.player.set_lock("console", false)
	if _freecam != null and is_instance_valid(_freecam):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = _prev_mouse


func _hist(d: int) -> void:
	if history.is_empty():
		return
	hist_i = clampi(hist_i + d, 0, history.size())
	edit.text = history[hist_i] if hist_i < history.size() else ""
	edit.caret_column = edit.text.length()
	_update_sugg()


func _submit(t: String) -> void:
	t = t.strip_edges()
	edit.clear()
	_update_sugg()
	if t == "":
		return
	if history.is_empty() or history[history.size() - 1] != t:
		history.append(t)
	hist_i = history.size()
	print_line("[color=#ccc]> %s[/color]" % t)
	run(t)


func run(t: String) -> void:
	var parts := t.trim_prefix("/").split(" ", false)
	if parts.is_empty():
		return
	var cmd := parts[0].to_lower()
	if not commands.has(cmd):
		print_line("[color=#e77]Нет команды «%s». /help — список.[/color]" % cmd)
		return
	if commands[cmd]["cheat"] and not cheats_on:
		print_line("[color=#e77]Читы выключены. /cheats on — включить.[/color]")
		return
	commands[cmd]["fn"].call(parts.slice(1))


func _cmd_help(_a: PackedStringArray) -> void:
	var names := commands.keys()
	names.sort()
	for n in names:
		var tag := " [color=#a77](чит)[/color]" if commands[n]["cheat"] else ""
		print_line("[color=#fd6]/%s[/color] — %s%s" % [n, commands[n]["desc"], tag])


func _cmd_cheats(a: PackedStringArray) -> void:
	if a.is_empty() or not (a[0].to_lower() in ["on", "off"]):
		print_line("[color=#e77]/cheats on|off[/color]")
		return
	cheats_on = a[0].to_lower() == "on"
	if not cheats_on:
		Engine.time_scale = 1.0
		SurfaceBuild.cheat_set_time(-2.0, 1.0)
		if game and game.player:
			for v in ["cheat_dmg", "cheat_spd", "cheat_jump", "cheat_taken"]:
				game.player.set(v, 1.0)
	if not cheats_on and game and game.god:
		game.god = false
	if not cheats_on and _freecam != null:
		_disable_freecam()
	if game and game.has_method("save_now"):
		game.save_now()
	print_line("[color=#9e9]Читы: %s[/color]" % ("вкл" if cheats_on else "выкл"))


func _cmd_god(_a: PackedStringArray) -> void:
	if game == null:
		return
	game.god = not game.god
	if game.has_method("save_now"):
		game.save_now()
	print_line("[color=#9e9]Godmode: %s[/color]" % ("вкл" if game.god else "выкл"))


const SurfaceBuild := preload("res://scripts/locations/bunker/surface_build.gd")
const STAT_KEYS := {"dmg": "cheat_dmg", "damage": "cheat_dmg", "урон": "cheat_dmg", "speed": "cheat_spd", "скорость": "cheat_spd",
	"jump": "cheat_jump", "прыжок": "cheat_jump", "taken": "cheat_taken", "armor": "cheat_taken"}


## /time — показать или задать время суток (часы 0-24 или слова), reset — обычные часы.
func _cmd_time(a: PackedStringArray) -> void:
	if a.size() == 0:
		var cur_h := SurfaceBuild.cheat_day_now() * 24.0
		print_line("[color=#9e9]Время: %02d:%02d, скорость суток ×%s[/color]" % [int(cur_h), int(fmod(cur_h, 1.0) * 60.0), SurfaceBuild.cheat_time_speed])
		return
	var w := a[0].to_lower()
	var named := {"day": 12.0, "noon": 12.0, "день": 12.0, "night": 0.0, "midnight": 0.0, "ночь": 0.0,
		"dawn": 6.0, "morning": 7.0, "утро": 7.0, "рассвет": 6.0, "dusk": 18.0, "evening": 19.0, "вечер": 19.0, "закат": 18.0}
	if w == "reset":
		SurfaceBuild.cheat_set_time(-2.0, 1.0)
		print_line("[color=#9e9]Время: обычные часы[/color]")
		return
	var h := -1.0
	if named.has(w):
		h = named[w]
	elif w.contains(":"):
		var hm := w.split(":")
		h = hm[0].to_float() + hm[1].to_float() / 60.0
	elif w.is_valid_float():
		h = w.to_float()
	if h < 0.0:
		print_line("[color=#e77]/time 14 | 6:30 | day | night | reset[/color]")
		return
	SurfaceBuild.cheat_set_time(fposmod(h, 24.0) / 24.0, -1.0)
	print_line("[color=#9e9]Время суток → %s[/color]" % w)


## /timespeed — скорость смены суток (0 — время стоит).
func _cmd_timespeed(a: PackedStringArray) -> void:
	if a.size() == 0 or not a[0].is_valid_float():
		print_line("[color=#e77]/timespeed 10  (сейчас ×%s)[/color]" % SurfaceBuild.cheat_time_speed)
		return
	SurfaceBuild.cheat_set_time(-1.0, maxf(a[0].to_float(), 0.0))
	print_line("[color=#9e9]Скорость суток ×%s[/color]" % SurfaceBuild.cheat_time_speed)


## /slowmo — Engine.time_scale (вся игра медленнее/быстрее).
func _cmd_slowmo(a: PackedStringArray) -> void:
	var x := 1.0 if a.size() == 0 or not a[0].is_valid_float() else clampf(a[0].to_float(), 0.05, 5.0)
	Engine.time_scale = x
	print_line("[color=#9e9]Скорость игры ×%s[/color]" % x)


## /stat — множители характеристик игрока (урон, скорость, прыжок, получаемый урон).
func _cmd_stat(a: PackedStringArray) -> void:
	if game == null or game.player == null:
		return
	var p = game.player
	if a.size() == 0:
		print_line("[color=#9e9]Урон ×%s, скорость ×%s, прыжок ×%s, получаемый урон ×%s[/color]" % [p.cheat_dmg, p.cheat_spd, p.cheat_jump, p.cheat_taken])
		return
	var k := a[0].to_lower()
	if k == "reset":
		for v in ["cheat_dmg", "cheat_spd", "cheat_jump", "cheat_taken"]:
			p.set(v, 1.0)
		print_line("[color=#9e9]Характеристики сброшены[/color]")
		return
	if not STAT_KEYS.has(k) or a.size() < 2 or not a[1].is_valid_float():
		print_line("[color=#e77]/stat dmg 5 | speed 2 | jump 1.5 | taken 0.5 | reset[/color]")
		return
	var x := clampf(a[1].to_float(), 0.0, 100.0)
	p.set(STAT_KEYS[k], x)
	print_line("[color=#9e9]%s ×%s[/color]" % [k, x])


func _cmd_money(a: PackedStringArray) -> void:
	var n := 100
	if a.size() > 0:
		if not a[0].is_valid_int():
			print_line("[color=#e77]Нужно число: /money 500[/color]")
			return
		n = a[0].to_int()
	if game == null or game.inv == null:
		return
	if n < 0:
		n = -mini(-n, game.inv.coins)   # отнять можно не больше, чем есть
	game.inv.coins += n
	game.inv._after_change()   # кошелёк в инвентаре + HUD (inv.changed)
	if game.has_method("save_now"):
		game.save_now()
	print_line("[color=#9e9]Монеты %+d → %d[/color]" % [n, game.inv.coins])


func _cmd_noclip(_a: PackedStringArray) -> void:
	if game == null or game.player == null:
		return
	var p = game.player
	p.noclip = not p.noclip
	p.velocity = Vector3.ZERO
	if game.has_method("save_now"):
		game.save_now()
	print_line("[color=#9e9]Noclip: %s[/color]" % ("вкл" if p.noclip else "выкл"))

func _cmd_ncspeed(a: PackedStringArray) -> void:
	if game == null or game.player == null:
		return
	if a.size() > 0 and String(a[0]).is_valid_float():
		game.player.nc_speed = clampf(float(a[0]), 1.0, 300.0)
	print_line("[color=#9e9]Скорость noclip: %.1f[/color]" % game.player.nc_speed)

## места для /tp: [главное имя, псевдонимы, точка на земле у центра локации] (мир бесшовный; лагерь и город смещены на OFF)
func _tp_places() -> Array:
	return [
		["бункер", ["bunker"], game.START],
		["деревня", ["village"], VillageBuild.STALL + Vector3(2.5, 0.0, -2.0)],
		["озеро", ["lake", "лагерь", "camp"], LakeCampS.OFF + LakeCampS.CAR_POS + Vector3(2.5, 0.0, -1.5)],
		["город", ["city"], CityS.OFF + CityS.CAR_POS + Vector3(2.5, 0.0, -1.5)],
	]


## Поставить точку на землю: луч вниз от точки (без игрока).
func _tp_ground(p: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 6.0, 0), p + Vector3(0, -10.0, 0))
	q.collision_mask = 1
	q.exclude = [game.player.get_rid()]
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		return hit.position + Vector3(0, 0.3, 0)
	return p + Vector3(0, 0.3, 0)


## /tp — телепорт игрока в одну из локаций.
func _cmd_tp(a: PackedStringArray) -> void:
	if game == null or game.player == null:
		return
	var k := _norm(" ".join(a))
	var places := _tp_places()
	var found: Array = []
	for pl in places:
		if k != "" and (k == pl[0] or k in pl[1]):
			found = pl
	if found.is_empty():
		var names: PackedStringArray = []
		for pl in places:
			names.append("%s (%s)" % [pl[0], pl[1][0]])
		print_line("[color=#e99]/tp [место]: %s[/color]" % ", ".join(names))
		return
	var to := _tp_ground(found[2])
	game.player.global_position = to
	game.player.velocity = Vector3.ZERO
	if game.has_method("save_now"):
		game.save_now()
	print_line("[color=#9e9]Телепорт: %s[/color]" % found[0])

func _cmd_freecam(_a: PackedStringArray) -> void:
	if _freecam != null and is_instance_valid(_freecam):
		_disable_freecam()
		if game and game.has_method("save_now"):
			game.save_now()
		print_line("[color=#9e9]Freecam: выкл[/color]")
	elif _enable_freecam():
		if game and game.has_method("save_now"):
			game.save_now()
		print_line("[color=#9e9]Freecam: вкл (закройте консоль F1 для полёта)[/color]")
	else:
		print_line("[color=#e77]Не удалось найти активную 3D-камеру.[/color]")


func _enable_freecam() -> bool:
	var cur := get_viewport().get_camera_3d() if get_viewport() else null
	if cur == null:
		return false
	_prev_cam = cur
	_freecam = Camera3D.new()
	_freecam.fov = cur.fov
	_freecam.near = cur.near
	_freecam.far = cur.far
	get_tree().current_scene.add_child(_freecam)
	_freecam.global_transform = cur.global_transform
	var euler := _freecam.global_transform.basis.get_euler()
	_freecam_rot = Vector2(euler.x, euler.y)
	_freecam.rotation = Vector3(_freecam_rot.x, _freecam_rot.y, 0.0)
	_freecam.make_current()
	if game and game.player:
		game.player.set_lock("freecam", true)
		if game.player.has_method("set_head_visible"):
			game.player.set_head_visible(true)
	return true


func _disable_freecam() -> void:
	if _freecam != null and is_instance_valid(_freecam):
		_freecam.queue_free()
	_freecam = null
	if _prev_cam != null and is_instance_valid(_prev_cam):
		_prev_cam.make_current()
	_prev_cam = null
	if game and game.player:
		game.player.set_lock("freecam", false)
		if game.player.has_method("set_head_visible"):
			game.player.set_head_visible(false)


# ---------- /get ----------

## Нормализация для сравнения: регистр, ё→е, лишние пробелы.
func _norm(s: String) -> String:
	return " ".join(s.to_lower().replace("ё", "е").split(" ", false))


## id по игровому названию или внутреннему id ("" — не нашли).
func _find_item(q: String) -> String:
	q = _norm(q)
	if q == "":
		return ""
	if Items.ITEMS.has(q):
		return q
	for id in Items.ITEMS:
		if _norm(Items.ITEMS[id]["name"]) == q:
			return id
	return ""


## Разбор аргументов: [id, кол-во]; последнее слово-число — количество.
func _parse_get(a: PackedStringArray) -> Array:
	var n := 1
	var words := Array(a)
	if words.size() > 1 and String(words[-1]).is_valid_int():
		n = String(words.pop_back()).to_int()
	return [_find_item(" ".join(words)), n]


## Экипировку из /get надеваем сразу (промпт 18.11 01:42): оружие — в свободную руку, одежду/рюкзак/противогаз —
## в свой слот. Занятые слоты не трогаем: остаток идёт в сумку, а что не влезло — на пол (_cmd_get).
## Возвращает, сколько штук разошлось по слотам.
func _equip_cheat(id: String, n: int) -> int:
	if game == null or game.inv == null:
		return 0
	var eq := Items.equip_slot(id)
	if eq == "":
		return 0
	var inv = game.inv
	var where: Array = ["right", "left"] if eq == "hand" else [eq]
	var done := 0
	for sl in where:
		if done >= n or not inv.equip.has(sl) or String(inv.equip[sl]) != "":
			continue
		inv.equip[sl] = id
		inv.equip_dur[sl] = Items.max_dur(id)
		inv.update_blocks()
		if game.has_method("_apply_equip"):
			game._apply_equip(sl)
		done += 1
	if done > 0:
		inv.notify()
	return done


func _cmd_get(a: PackedStringArray) -> void:
	if a.is_empty():
		print_line("[color=#e77]/get [предмет] [кол-во] — например: /get аптечка 3[/color]")
		return
	var r := _parse_get(a)
	var id: String = r[0]
	var n: int = clampi(r[1], 1, 9999)
	if id == "":
		print_line("[color=#e77]Нет предмета «%s». Наберите /get и смотрите подсказки.[/color]" % " ".join(a))
		return
	if game == null or game.inv == null or game.player == null:
		return
	var worn := _equip_cheat(id, n)        # экипировку — сразу надеть/в руку (промпт 18.11 01:42)
	var left: int = game.inv.add(id, n - worn) if n - worn > 0 else 0
	if left > 0 and game.has_method("_make_pickup"):   # не влезло — бросить под ноги
		var fwd: Vector3 = -game.player.global_transform.basis.z
		var pos: Vector3 = game.player.global_position + Vector3(0, 1.0, 0) + fwd * 0.4
		var p = game._make_pickup(id, left, pos, fwd * 1.0 + Vector3(0, 0.5, 0))
		if p:
			p.need_leave = true
	if game.has_method("save_now"):
		game.save_now()
	var nm := Items.item_name(id)
	var extra := " [color=#9cd](надето: %d)[/color]" % worn if worn > 0 else ""
	if left > 0:
		print_line("[color=#9e9]+%d %s[/color]%s [color=#db8](%d не влезло — под ногами)[/color]" % [n - left, nm, extra, left])
	else:
		print_line("[color=#9e9]+%d %s[/color]%s" % [n, nm, extra])


## Текст поля для подсказки i.
func _sugg_text(i: int) -> String:
	if sugg_tp:
		return "/tp " + String(sugg[i])
	return "/get " + String(Items.ITEMS[sugg[i]]["name"]) + " "


## Пересчитать подсказки по набранному тексту (вызывается при вводе пользователем).
func _update_sugg() -> void:
	sugg.clear()
	sugg_i = -1
	sugg_tp = false
	var t := edit.text
	var tl := t.to_lower()
	if (tl == "/tp" or tl.begins_with("/tp ")) and game != null:
		var q2 := _norm(t.substr(3))
		for pl in _tp_places():
			if q2 == "" or String(pl[0]).begins_with(q2) or pl[1].any(func(x): return String(x).begins_with(q2)):
				sugg.append(pl[0])
		sugg_tp = true
		if not sugg.is_empty():
			sugg_i = 0
		_draw_sugg()
		return
	if not t.to_lower().begins_with("/get "):
		sugg_l.visible = false
		return
	var rest := t.substr(5)
	var words := rest.split(" ", false)
	# название уже введено полностью (дальше пробел или количество) — подсказки не нужны
	if _find_item(rest) != "" and rest.ends_with(" "):
		sugg_l.visible = false
		return
	if words.size() > 1 and words[-1].is_valid_int() and _parse_get(words)[0] != "":
		sugg_l.visible = false
		return
	var q := _norm(rest)
	var first: Array = []
	var other: Array = []
	for id in Items.ITEMS:
		var nm := _norm(Items.ITEMS[id]["name"])
		if q == "" or nm.begins_with(q) or String(id).begins_with(q):
			first.append(id)
		elif nm.contains(q) or String(id).contains(q):
			other.append(id)
	var by_name := func(x, y): return _norm(Items.ITEMS[x]["name"]) < _norm(Items.ITEMS[y]["name"])
	first.sort_custom(by_name)
	other.sort_custom(by_name)
	sugg = first + other
	if not sugg.is_empty():
		sugg_i = 0
	_draw_sugg()


func _draw_sugg() -> void:
	sugg_l.clear()
	if sugg.is_empty():
		sugg_l.append_text("[color=#a77]  нет такого %s[/color]" % ("места" if sugg_tp else "предмета"))
		sugg_l.visible = true
		return
	if sugg_tp:
		var tl2: PackedStringArray = []
		for i in sugg.size():
			tl2.append(("[bgcolor=#3a3520][color=#fd6]▶ %s[/color][/bgcolor]" if i == sugg_i else "[color=#ccc]  %s[/color]") % sugg[i])
		sugg_l.append_text("
".join(tl2))
		sugg_l.visible = true
		return
	@warning_ignore("integer_division")
	var from := clampi(sugg_i - SUGG_ROWS / 2, 0, maxi(0, sugg.size() - SUGG_ROWS))
	var to := mini(from + SUGG_ROWS, sugg.size())
	var lines: PackedStringArray = []
	if from > 0:
		lines.append("[color=#777]  … ещё %d выше[/color]" % from)
	for i in range(from, to):
		var nm := String(Items.ITEMS[sugg[i]]["name"])
		if i == sugg_i:
			lines.append("[bgcolor=#3a3520][color=#fd6]▶ %s[/color] [color=#998]%s[/color][/bgcolor]" % [nm, sugg[i]])
		else:
			lines.append("[color=#ccc]  %s[/color] [color=#777]%s[/color]" % [nm, sugg[i]])
	if to < sugg.size():
		lines.append("[color=#777]  … ещё %d ниже (Tab / Shift+Tab)[/color]" % (sugg.size() - to))
	sugg_l.append_text("\n".join(lines))
	sugg_l.visible = true


## Tab: первый раз подставляет выделенный, дальше листает (Shift — назад) и сразу подставляет.
func _sugg_tab(d: int) -> void:
	if not sugg_l.visible or sugg.is_empty():
		return
	if _norm(edit.text) == _norm(_sugg_text(sugg_i)):
		sugg_i = wrapi(sugg_i + d, 0, sugg.size())
	edit.text = _sugg_text(sugg_i)
	edit.caret_column = edit.text.length()
	_draw_sugg()


## Enter: подставить выделенный и спрятать список (следующий Enter выполнит команду).
func _apply_sugg() -> void:
	edit.text = _sugg_text(sugg_i)
	edit.caret_column = edit.text.length()
	sugg.clear()
	sugg_i = -1
	sugg_l.visible = false
