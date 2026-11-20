extends CanvasLayer
## «Нюхич» — самодельный противогаз (ключ предмета остался "gasmask") и отравленный воздух наверху.
## G — надеть/снять (слот «Лицо» в инвентаре, туда же можно перетащить мышью). Фильтр работает 100 с, только пока ты наверху в маске;
## кончился — автоматически ставится следующий из инвентаря.
## Наверху без защиты копится «отравление» tox (0..1): замедление, искажения в глазах, быстрая потеря здоровья.
## Если быстро вернуться в бункер — выжить можно: в бункере эффекты спадают постепенно.
## Промпт 14.11 18:03 / 18:30: панорамная маска (широкий обзор, линзы слиты без шва), царапины, разводы,
## конденсат от дыхания, плавное надевание/снятие и плавные эффекты.

const Items := preload("res://scripts/items.gd")

const FILTER_TIME := 100.0
const FILTER_TIME2 := 200.0    # большой армейский фильтр (деревня, промпт 18.11 01:28)
const TOX_UP := 1.0 / 3.0      # до полного отравления ~3 с (дебаффы нарастают быстро)
const TOX_DOWN := 1.0 / 12.0   # спадает ~12 с
const PUT_TIME := 0.7          # надеть / снять, с
const FILTER_LOW := 12.0       # за столько секунд до конца фильтра стекло начинает запотевать

var game
var worn := false
var filter_left := 0.0
var filter_max := FILTER_TIME   # ёмкость стоящего фильтра: 100 (обычный) или 200 (большой)
var tox := 0.0
var tox_vis := 0.0             # сглаженное отравление для экрана (без рывков)
var put := 0.0                 # 0 — маски нет на лице, 1 — надета (анимация)
var fog := 0.0                 # запотевание: садится фильтр / кончился
var surface: Node
var overlay: ColorRect
var mat: ShaderMaterial
var status_l: Label
var status_kind := ""
var breath_t := 0.0
var breath_n := 0
var breath := 0.0              # 0..1 после выдоха — конденсат по краям стекла
var voice: AudioStreamPlayer
var breaths: Array = []
var breath_lp: AudioEffectLowPassFilter   # тембр дыхания меняется от вдоха к вдоху (шина «MaskBreath»)
var breath_eq: AudioEffectEQ6
var cough_p: AudioStreamPlayer   # кашель от отравленного воздуха (промпт 04:26)
var coughs: Array = []
var cough_t := 1.5
var cough_left := 0            # сколько покашливаний осталось в текущем приступе


func _ready() -> void:
	layer = -1   # ниже HUD (слой 0): интерфейс виден поверх маски
	overlay = ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat = ShaderMaterial.new()
	mat.shader = _mask_shader()
	overlay.material = mat
	overlay.visible = false
	add_child(overlay)
	status_l = Label.new()
	status_l.anchor_left = 0.5
	status_l.anchor_right = 0.5
	status_l.offset_left = -300
	status_l.offset_right = 300
	status_l.offset_top = 60
	status_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_l.add_theme_font_size_override("font_size", 20)
	status_l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	add_child(status_l)
	voice = AudioStreamPlayer.new()
	add_child(voice)
	var Sfx := preload("res://scripts/core/sfx.gd")
	breaths = [Sfx.inhale(), Sfx.inhale(true)]
	cough_p = AudioStreamPlayer.new()
	add_child(cough_p)
	for v in 4:
		coughs.append(_cough_sound(v))
	_breath_bus()
	if not InputMap.has_action("gasmask"):
		InputMap.add_action("gasmask")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_V
		InputMap.action_add_event("gasmask", ev)


## Своя шина для дыхания: фильтр + эквалайзер, каждый вдох — чуть другой тембр.
func _breath_bus() -> void:
	var bi := AudioServer.get_bus_index("MaskBreath")
	if bi < 0:
		AudioServer.add_bus()
		bi = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bi, "MaskBreath")
		AudioServer.set_bus_send(bi, "Master")
		AudioServer.add_bus_effect(bi, AudioEffectLowPassFilter.new())
		AudioServer.add_bus_effect(bi, AudioEffectEQ6.new())
	for e in AudioServer.get_bus_effect_count(bi):
		var fx := AudioServer.get_bus_effect(bi, e)
		if fx is AudioEffectLowPassFilter:
			breath_lp = fx
		elif fx is AudioEffectEQ6:
			breath_eq = fx
	voice.bus = "MaskBreath"


## Случайный тембр очередного вдоха: срез верхов, бубнение низов, «резина» в середине.
func _vary_timbre() -> void:
	if breath_lp:
		breath_lp.cutoff_hz = randf_range(1300.0, 3200.0)
		breath_lp.resonance = randf_range(0.5, 0.9)
	if breath_eq:
		breath_eq.set_band_gain_db(0, randf_range(-2.0, 3.0))    # 32 Гц
		breath_eq.set_band_gain_db(1, randf_range(-1.0, 4.0))    # 100 Гц
		breath_eq.set_band_gain_db(2, randf_range(-4.0, 3.0))    # 320 Гц
		breath_eq.set_band_gain_db(3, randf_range(-5.0, 2.0))    # 1 кГц
		breath_eq.set_band_gain_db(4, randf_range(-8.0, 0.0))    # 3.2 кГц
		breath_eq.set_band_gain_db(5, randf_range(-12.0, -3.0))  # 10 кГц


## Вид изнутри «Нюхича» (промпт 14.11 18:30): две большие линзы плавно слиты в одну панорамную область
## (~80% экрана), чёрная резина только по краям и в углах, у переносицы — мягкая тень сверху и снизу, без линии.
## Стекло: к краю темнеет и мягко размывается (виньетка), размытые разводы-запотевания, по краям — конденсат, который дышит вместе с тобой.
## put — анимация надевания (рамка наезжает из-за краёв экрана, экран на миг темнеет), fog — запотевание.
func _mask_shader() -> Shader:
	var s := Shader.new()
	s.code = """shader_type canvas_item;
uniform sampler2D scr : hint_screen_texture, filter_linear_mipmap;
uniform float put = 1.0;     // 0..1 надевание
uniform float fog = 0.0;     // 0..1 запотевание (фильтр садится)
uniform float breath = 0.0;  // 0..1 выдох — конденсат по краям
uniform float wide = 0.0;    // 1 — армейский «Шлемыч»: панорамное стекло, чище и шире обзор
// две большие линзы, плавно слитые в одну панорамную (промпт 14.11 18:30: обзор шире, без линии по центру)
const vec2 RAD = vec2(0.6, 0.53);   // полуоси линзы (доля высоты экрана)
const float CX = 0.34;              // центры линз по горизонтали
const float CY = -0.02;
const float K = 0.35;               // мягкость слияния линз

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float hash1(float n) { return fract(sin(n) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.07; a *= 0.5; }
	return v;
}
// гладкий минимум: две линзы сливаются без шва
float smin(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

void fragment() {
	float a = smoothstep(0.0, 1.0, put);
	float asp = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 p = SCREEN_UV - 0.5;
	p.x *= asp;
	// надевание: маска «наезжает» на лицо — рамка приходит из-за краёв экрана
	p /= mix(2.6, 1.0, a) * mix(1.0, 1.32, wide);   // армейская маска — стекло шире
	p.y += (1.0 - a) * 0.05;
	vec2 cl = vec2(-CX, CY);
	vec2 cr = vec2(CX, CY);
	float fl = length((p - cl) / RAD);
	float fr = length((p - cr) / RAD);
	float f = smin(fl, fr, K) + 0.08;         // <1 — стекло, к 1 — край линзы
	// «центр» плавно переезжает от левой линзы к правой — без разрыва посередине
	float w = smoothstep(-0.25, 0.25, p.x);
	vec2 c = mix(cl, cr, w);
	// у переносицы: мягкая тень сверху и снизу посередине (без жёсткой перемычки)
	float nose = smoothstep(0.22, 0.0, abs(p.x)) * (smoothstep(0.22, 0.5, p.y) * 0.85 + smoothstep(-0.3, -0.5, p.y) * 0.5) * (1.0 - 0.85 * wide);
	float glass = 1.0 - smoothstep(0.86, 1.04, f);   // 1 — стекло, 0 — резина, переход мягкий
	// резина по краям: почти чёрная, с лёгкой фактурой
	float tex = fbm(p * 38.0) * 0.5 + fbm(p * vec2(4.0, 14.0)) * 0.5;
	vec3 rubber = vec3(0.012, 0.013, 0.012) + vec3(0.016, 0.017, 0.015) * tex;
	// стекло
	float e = smoothstep(0.5, 1.0, f);            // 0 в середине, 1 у края
	float cn = fbm(p * 9.0 + vec2(0.0, TIME * 0.02));
	float cond = smoothstep(0.6 - 0.5 * fog - 0.1 * breath, 1.05, e + cn * 0.3) * (0.15 + 0.4 * breath + 0.6 * fog);
	cond = clamp(cond, 0.0, 0.95) * (1.0 - 0.5 * wide);
	vec2 cuv = vec2(c.x / asp, c.y) + 0.5;
	vec2 uv = SCREEN_UV + (cuv - SCREEN_UV) * 0.035 * e * e;   // лёгкое стягивание к центрам линз
	uv += (vec2(fbm(p * 22.0), fbm(p * 22.0 + 5.3)) - 0.5) * 0.006 * cond;
	vec3 col = textureLod(scr, uv, 1.6 * e * e + 3.5 * cond).rgb;
	col *= mix(vec3(1.0), vec3(0.88, 0.93, 0.86), 0.55) * (1.0 - 0.4 * e * e);
	col = mix(col, col * 0.6 + vec3(0.16, 0.17, 0.16), cond);
	// разводы: мутные пятна от пальцев и высохших капель
	float sm = smoothstep(0.55, 0.85, fbm(p * 6.0 + 3.7));
	col = mix(col, col * 0.85 + vec3(0.06, 0.065, 0.06), sm * 0.3 * (1.0 - 0.75 * wide));
	// мягкое запотевание: размытые пятна-облака, без чётких линий и кружков
	float haze = smoothstep(0.35, 0.9, fbm(p * 2.3 + vec2(1.7, 0.0) + vec2(0.0, TIME * 0.006)));
	vec3 soft = textureLod(scr, uv, 3.0 + 2.0 * e).rgb;
	col = mix(col, soft * 0.85 + vec3(0.05, 0.055, 0.05), haze * (0.18 + 0.25 * e) * (1.0 - 0.7 * wide));
	// мягкая виньетка: к краю линзы сильнее размыто и чуть светлее от конденсата
	float vig = smoothstep(0.45, 1.0, f);
	vec3 edge = textureLod(scr, uv, 4.5).rgb * 0.7 + vec3(0.04, 0.045, 0.04);
	col = mix(col, edge, vig * 0.55 * (1.0 - 0.45 * wide));
	// мягкий блик сверху у края каждой линзы
	float hl = smoothstep(0.1, 0.0, abs(fl - 0.88)) * smoothstep(0.0, -0.3, p.y - CY) * smoothstep(0.1, -0.35, p.x);
	float hr = smoothstep(0.1, 0.0, abs(fr - 0.88)) * smoothstep(0.0, -0.3, p.y - CY) * smoothstep(-0.1, 0.35, p.x);
	col += vec3(0.05, 0.055, 0.05) * max(hl, hr);
	col *= 1.0 - 0.55 * nose;
	col = mix(rubber, col, glass);
	// на середине надевания экран темнеет (резина у глаз)
	col *= 1.0 - 0.75 * sin(3.1416 * a);
	COLOR = vec4(col, smoothstep(0.0, 0.12, put));
}"""
	return s


## Противогазы: "gasmask" — самодельный Нюхич, "gasmask2" — армейский Шлемыч (лучше обзор),
## "snyuhatel5088" — Снюхатель5088 для города (сейф у озера); все в слот «Лицо».
static func is_mask(id: String) -> bool:
	return id == "gasmask" or id == "gasmask2" or id == "snyuhatel5088"


## Есть ли у игрока хоть какой-то противогаз.
func has_mask() -> bool:
	return game != null and game.inv != null and game.inv.count("gasmask") + game.inv.count("gasmask2") + game.inv.count("snyuhatel5088") > 0


## Какой противогаз надет ("" — никакой).
func mask_id() -> String:
	if game == null or game.inv == null:
		return ""
	var id := String(game.inv.equip["face"])
	return id if is_mask(id) else ""


## Сколько фильтров в сумке (любых).
func filters_left() -> int:
	return game.inv.count("filter") + game.inv.count("filter2")


## Какой фильтр поставить следующим: сначала обычные, большие — в запас.
func _next_filter() -> String:
	if game.inv.count("filter") > 0:
		return "filter"
	return "filter2" if game.inv.count("filter2") > 0 else ""


static func filter_cap(fid: String) -> float:
	return FILTER_TIME2 if fid == "filter2" else FILTER_TIME


func on_bought() -> void:
	filter_max = FILTER_TIME
	filter_left = FILTER_TIME
	game.hud.toast("Нюхич с фильтром. V — надеть", Color(0.7, 0.85, 0.6))


## Сменить фильтр вручную (режимы «Реализм» и «По умолчанию», промпт 18.11 00:52): «Сменить фильтр» у фильтра
## в инвентаре или хотбар. Остаток старого фильтра пропадает.
func change_filter(fid := "filter") -> void:
	if not has_mask():
		game.hud.toast("Нет противогаза — фильтр некуда ставить")
		return
	if game.inv.count(fid) == 0:
		game.hud.toast("Нет фильтров")
		return
	var cap := filter_cap(fid)
	if filter_left >= cap - 0.5:
		game.hud.toast("Фильтр и так новый")
		return
	game.inv.remove(fid, 1)
	_drop_old_filter()
	filter_max = cap
	filter_left = cap
	game.hud.toast("%s: %d с (осталось %d)" % [Items.item_name(fid), int(cap), game.inv.count(fid)], Color(0.75, 0.85, 0.7))
	game.play_ui("click", -8.0, 0.5)


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("gasmask") and game and game.alive:
		game.toggle_gasmask()


## Надет ли противогаз — управляет слот «Лицо» в инвентаре (game.gd: _apply_equip).
## instant — без анимации и звука (загрузка сейва).
func set_worn(on: bool, instant := false) -> void:
	if instant:
		worn = on
		put = 1.0 if on else 0.0
		overlay.visible = on
		return
	if on == worn:
		return
	worn = on
	overlay.visible = true
	if not visible:
		return   # кат-сцена (game.gd: begin_escape) — без звуков маски
	# надел — глубокий вдох через фильтр; снял — выдох
	voice.stream = breaths[0 if worn else 1]
	_vary_timbre()
	voice.volume_db = -17.0
	voice.pitch_scale = (0.72 if worn else 0.9) * randf_range(0.95, 1.05)
	voice.play()
	breath_t = 1.4


var city_warn_t := 0.0


func _outside() -> float:
	# в салоне машины воздух тот же, что снаружи (промпт 16.11 02:43) — без маски травишься
	if surface == null:
		var level: Node = game.get_parent().get_node_or_null("Level")
		if level:
			for c in level.get_children():
				if c.has_method("_outside"):
					surface = c
		if surface == null:
			return 0.0
	return surface._outside(game.player.cam.global_position)


func _process(delta: float) -> void:
	if game == null or game.player == null:
		return
	if worn and not has_mask():
		worn = false
	# анимация надевания / снятия
	put = move_toward(put, 1.0 if worn else 0.0, delta / PUT_TIME)
	overlay.visible = put > 0.0
	# у озера воздух чистый — можно без противогаза (промпт 20.11 18:31)
	# город — самый грязный (промпт 20.11 18:35): дышать только в Снюхателе5088, фильтр горит быстрее, травит сильнее
	const CityL := preload("res://scripts/village/city.gd")
	var city: bool = CityL.in_city(game.player.global_position)
	var out: bool = _outside() > 0.5 and game.alive and (city or not preload("res://scripts/village/lake_camp.gd").clean_air(game.player.global_position))
	# фильтр тратится только наверху и в маске
	if worn and out:
		# деревня — зона менее заражённая: фильтр тратится на 40% медленнее (промпт 20.11 11:57)
		var village_k := 0.6 if preload("res://scripts/village/village.gd").near_village(game.player.global_position) else 1.0
		if city:
			village_k = 1.5
		filter_left -= delta * village_k
		if filter_left <= 0.0:
			# казуальный режим — следующий фильтр ставится сам; реализм и по умолчанию — вручную (change_filter)
			var nf := _next_filter()
			if game.casual() and nf != "":
				game.inv.remove(nf, 1)
				filter_max = filter_cap(nf)
				filter_left = filter_max
				_drop_old_filter()
				game.hud.toast("Новый фильтр: %d с (осталось %d)" % [int(filter_max), game.inv.count(nf)], Color(0.75, 0.85, 0.7))
				game.play_ui("click", -8.0, 0.5)
			else:
				filter_left = 0.0
	var protected := worn and filter_left > 0.0
	if city and protected and String(game.inv.equip["face"]) != CityL.MASK:
		protected = false
		city_warn_t -= delta
		if city_warn_t <= 0.0:
			city_warn_t = 6.0
			game.hud.toast("Этот противогаз смог не держит — нужен " + CityL.MASK_NAME, Color(0.95, 0.6, 0.4))
	if out and not protected and not game.god:   # godmode — без загрязнения воздуха
		tox = minf(tox + TOX_UP * delta * (1.5 if city else 1.0), 1.0)
	else:
		tox = maxf(tox - TOX_DOWN * delta, 0.0)
	# урон: наверху быстро, в бункере остатки отравления ещё немного жгут
	if tox > 0.0 and game.alive:
		var rate := (3.0 + 8.0 * tox) if (out and not protected) else 3.0 * tox * tox
		game.drain_hp(rate * delta)
	# замедление и искажения: на экран идёт сглаженное значение — эффекты нарастают и спадают без рывков
	tox_vis = lerpf(tox_vis, tox, 1.0 - exp(-delta * 2.5))
	# множители перемножаются: отравление × бафф скорости от напитка (game.gd: buff_mult)
	game.player.speed_mult = (1.0 - 0.55 * tox_vis) * game.buff_mult("speed")
	if game.player.post_mat:
		game.player.post_mat.set_shader_parameter("toxic", tox_vis)
	# запотевание: фильтр садится (последние FILTER_LOW с наверху) или кончился
	var fog_want := 0.0
	if worn and out:
		fog_want = clampf(1.0 - filter_left / FILTER_LOW, 0.0, 1.0)
	fog = lerpf(fog, fog_want, 1.0 - exp(-delta * 1.2))
	# дыхание в маске: вдох / выдох, на выдохе стекло запотевает по краям
	breath = maxf(breath - delta * 0.55, 0.0)
	if not visible:
		# кат-сцена (посадка / поездка / поломка) — маска молчит
		if voice.playing:
			voice.stop()
	elif worn:
		breath_t -= delta
		if breath_t <= 0.0:
			breath_n += 1
			var exhale := breath_n % 2 == 1
			# реже и неровно: после выдоха пауза длиннее; фильтр садится — дышишь чаще и тяжелее
			breath_t = lerpf(2.5 if exhale else 1.7, 1.4, fog) * randf_range(0.78, 1.3)
			voice.stream = breaths[1 if exhale else 0]
			_vary_timbre()
			voice.volume_db = lerpf(-29.0, -21.0, fog) + randf_range(-3.0, 2.0)
			voice.pitch_scale = lerpf(0.8, 0.68, fog) * randf_range(0.92, 1.08)
			voice.play()
			if exhale:
				breath = randf_range(0.7, 1.0)
	_cough_tick(delta, out and not protected and visible and game.alive)
	mat.set_shader_parameter("breath", breath)
	mat.set_shader_parameter("put", put)
	mat.set_shader_parameter("fog", fog)
	mat.set_shader_parameter("wide", 1.0 if mask_id() in ["gasmask2", "snyuhatel5088"] else 0.0)
	_status(out, protected)


## Старый грязный фильтр (промпт 16.11 02:45): откручивается у подбородка и падает на землю
## физическим мусором, через ~10 с тает и исчезает.
func _drop_old_filter() -> void:
	var cam: Camera3D = game.player.cam
	var world: Node = game.get_parent()
	if cam == null or world == null:
		return
	var body := RigidBody3D.new()
	body.collision_layer = 0
	body.collision_mask = 1
	body.mass = 0.3
	body.freeze = true
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.045
	sh.height = 0.07
	cs.shape = sh
	body.add_child(cs)
	var dirty := StandardMaterial3D.new()
	dirty.albedo_color = Color(0.22, 0.2, 0.15)
	dirty.roughness = 0.95
	dirty.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var cm := CylinderMesh.new()
	cm.top_radius = 0.045
	cm.bottom_radius = 0.045
	cm.height = 0.07
	cm.radial_segments = 14
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = dirty
	body.add_child(mi)
	# решётка-торец и резьба — чуть темнее
	var grime := StandardMaterial3D.new()
	grime.albedo_color = Color(0.08, 0.075, 0.06)
	grime.roughness = 1.0
	grime.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var cap := CylinderMesh.new()
	cap.top_radius = 0.035
	cap.bottom_radius = 0.035
	cap.height = 0.012
	cap.radial_segments = 12
	for y in [0.037, -0.037]:
		var c := MeshInstance3D.new()
		c.mesh = cap
		c.material_override = grime
		c.position.y = y
		body.add_child(c)
	world.add_child(body)
	var b := cam.global_transform.basis
	body.global_position = cam.global_position - b.z * 0.18 - b.y * 0.17
	body.global_basis = b * Basis(Vector3.RIGHT, PI / 2.0)   # ось фильтра — вперёд, от лица
	game.play_ui("click", -10.0, 0.7)
	# откручивается: пара оборотов на месте, потом падает
	var tw := body.create_tween()
	tw.tween_method(func(k: float):
		if is_instance_valid(cam):
			var bb := cam.global_transform.basis
			body.global_position = cam.global_position - bb.z * (0.18 + 0.05 * k) - bb.y * 0.17
			body.global_basis = bb * Basis(Vector3.RIGHT, PI / 2.0) * Basis(Vector3.UP, k * TAU * 1.5)
		, 0.0, 1.0, 0.45)
	tw.tween_callback(func():
		body.freeze = false
		var fb := cam.global_transform.basis if is_instance_valid(cam) else Basis.IDENTITY
		body.linear_velocity = -fb.z * 0.8 + Vector3(randf_range(-0.3, 0.3), -0.3, 0)
		body.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6)))
	tw.tween_interval(9.0)
	tw.tween_method(func(a: float):
		dirty.albedo_color.a = a
		grime.albedo_color.a = a
		, 1.0, 0.0, 1.2)
	tw.tween_callback(body.queue_free)


## Подсказка сверху: при смене смысла плавно проявляется заново.
func _status(out: bool, protected: bool) -> void:
	if not game.alive:
		status_l.text = ""   # умер — не путать «отравление проходит» с экраном смерти
		status_kind = ""
		return
	var kind := ""
	var text := ""
	var col := Color.WHITE
	if out and not protected:
		kind = "bad" if not worn else "empty"
		text = "Загрязнение воздуха" if not worn else "Фильтр больше не фильтрует"
		if worn and filters_left() > 0:
			text = "Поменяй фильтр"
		col = Color(1.0, 0.45, 0.35)
	elif worn and game.mode == game.MODE_REAL:
		pass   # реализм: без счётчика фильтра — о конце предупреждает запотевание стекла
	elif worn:
		kind = "low" if filter_left < FILTER_LOW and out else "filter"
		text = "Фильтр: %d с%s" % [int(ceil(filter_left)), "" if filters_left() == 0 else "  (+%d)" % filters_left()]
		col = Color(0.95, 0.75, 0.45) if kind == "low" else Color(0.75, 0.85, 0.7)
	elif tox > 0.05:
		kind = "heal"
		text = "Отравление проходит…"
		col = Color(0.85, 0.8, 0.5)
	if kind != status_kind:
		status_kind = kind
		status_l.modulate.a = 0.0
	if text != "":
		status_l.text = text
		status_l.add_theme_color_override("font_color", col)
		status_l.modulate.a = minf(status_l.modulate.a + get_process_delta_time() * 3.0, 1.0)
	else:
		status_l.text = ""


## Кашель (промпт 04:26): задыхаешься (наверху без Нюхича или кончился фильтр) — тихие приглушённые
## покашливания приступами по 1–3, с паузами и разной высотой; чем сильнее отравление, тем чаще.
func _cough_tick(delta: float, choking: bool) -> void:
	if not choking or tox < 0.12:
		cough_left = 0
		cough_t = maxf(cough_t, randf_range(0.8, 1.6))
		return
	cough_t -= delta
	if cough_t > 0.0:
		return
	if cough_left <= 0:
		cough_left = 1 + int(randf() < 0.6) + int(randf() < 0.3 * tox)
	cough_left -= 1
	cough_p.stream = coughs[randi() % coughs.size()]
	cough_p.volume_db = randf_range(-27.0, -22.0) + (2.0 if worn else 0.0)
	cough_p.pitch_scale = randf_range(0.88, 1.1)
	cough_p.play()
	if cough_left > 0:
		cough_t = randf_range(0.2, 0.34)
	else:
		cough_t = lerpf(7.0, 3.2, tox) * randf_range(0.75, 1.35)


## Одно покашливание: короткий шумовой толчок через «горло» (две форманты) + низкий хрип голоса,
## всё срезано по верхам — звук глухой, будто в кулак.
static func _cough_sound(variant: int) -> AudioStreamWAV:
	var Sfx := preload("res://scripts/core/sfx.gd")
	var rng := RandomNumberGenerator.new()
	rng.seed = 4260 + variant
	var dur := rng.randf_range(0.2, 0.3)
	var n := int(Sfx.RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var f1 := Sfx.Svf.new(rng.randf_range(380.0, 520.0), 1.6)
	var f2 := Sfx.Svf.new(rng.randf_range(1100.0, 1500.0), 1.4)
	var f0 := rng.randf_range(110.0, 150.0)
	var ph := 0.0
	var lp1 := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / Sfx.RATE
		var w := rng.randf() * 2.0 - 1.0
		# резкий взрыв и спад, в конце — короткий хвост-выдох
		var env := smoothstep(0.0, 0.012, t) * (exp(-t * 18.0) * 0.85 + 0.15 * (1.0 - smoothstep(0.0, dur, t)))
		ph += (f0 * (1.0 - 0.25 * t / dur)) / Sfx.RATE
		var buzz := (fmod(ph, 1.0) * 2.0 - 1.0) * exp(-t * 22.0)
		var v := f1.bp(w) * 0.9 + f2.bp(w) * 0.35 + buzz * 0.25
		lp1 += (v - lp1) * 0.22     # приглушаем верха
		lp2 += (lp1 - lp2) * 0.22
		buf[i] = lp2 * env
	return Sfx._wav(buf, 0.5)
