extends CanvasLayer
## «Нюхич» — самодельный противогаз (ключ предмета остался "gasmask") и отравленный воздух наверху.
## G — надеть/снять (слот «Лицо» в инвентаре, туда же можно перетащить мышью). Фильтр работает 100 с, только пока ты наверху в маске;
## кончился — автоматически ставится следующий из инвентаря.
## Наверху без защиты копится «отравление» tox (0..1): замедление, искажения в глазах, быстрая потеря здоровья.
## Если быстро вернуться в бункер — выжить можно: в бункере эффекты спадают постепенно.
## Промпт 14.11 18:03: новый вид изнутри (толстая резина, два круглых окуляра в металлических обоймах,
## царапины, разводы, конденсат от дыхания), плавное надевание/снятие и плавные эффекты.

const FILTER_TIME := 100.0
const TOX_UP := 1.0 / 3.0      # до полного отравления ~3 с (дебаффы нарастают быстро)
const TOX_DOWN := 1.0 / 12.0   # спадает ~12 с
const PUT_TIME := 0.7          # надеть / снять, с
const FILTER_LOW := 12.0       # за столько секунд до конца фильтра стекло начинает запотевать

var game
var worn := false
var filter_left := 0.0
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
	var Sfx := preload("res://sfx.gd")
	breaths = [Sfx.inhale(), Sfx.inhale(true)]
	if not InputMap.has_action("gasmask"):
		InputMap.add_action("gasmask")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_G
		InputMap.action_add_event("gasmask", ev)


## Вид изнутри «Нюхича»: толстая чёрная резина почти на пол-экрана, два круглых окуляра в металлических
## обоймах (с бликом и винтами), между ними и снизу — перемычка носа и клапан.
## Стекло: к ободу темнеет и размывается, разводы и царапины, по краям — конденсат, который дышит вместе с тобой.
## put — анимация надевания (рамка наезжает из-за краёв экрана, экран на миг темнеет), fog — запотевание.
func _mask_shader() -> Shader:
	var s := Shader.new()
	s.code = """shader_type canvas_item;
uniform sampler2D scr : hint_screen_texture, filter_linear_mipmap;
uniform float put = 1.0;     // 0..1 надевание
uniform float fog = 0.0;     // 0..1 запотевание (фильтр садится)
uniform float breath = 0.0;  // 0..1 выдох — конденсат по краям
const float R = 0.285;       // радиус стекла (доля высоты экрана)
const float RING = 0.05;     // металлическая обойма
const float CX = 0.245;      // центры окуляров по горизонтали
const float CY = -0.035;

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

void fragment() {
	float a = smoothstep(0.0, 1.0, put);
	float asp = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 p = SCREEN_UV - 0.5;
	p.x *= asp;
	// надевание: маска «наезжает» на лицо — рамка приходит из-за краёв экрана
	p /= mix(3.2, 1.0, a);
	p.y += (1.0 - a) * 0.06;
	vec2 cl = vec2(-CX, CY);
	vec2 cr = vec2(CX, CY);
	float dl = length(p - cl);
	float dr = length(p - cr);
	vec2 c = dl < dr ? cl : cr;
	float d = min(dl, dr);
	vec2 q = p - c;
	float side = c.x < 0.0 ? -1.0 : 1.0;
	// перемычка носа и клапан снизу между окулярами
	float nose = length((p - vec2(0.0, 0.47)) / vec2(0.13, 0.36));
	float valve = length((p - vec2(0.0, 0.43)) / vec2(0.075, 0.075));
	// резина: почти чёрная, с лёгкой фактурой и складками
	float tex = fbm(p * 38.0) * 0.5 + fbm(p * vec2(4.0, 14.0)) * 0.5;
	vec3 rubber = vec3(0.012, 0.013, 0.012) + vec3(0.018, 0.019, 0.017) * tex;
	vec3 col;
	if (d > R + RING || nose < 1.0) {
		col = rubber;
		// складка резины вокруг обоймы — чуть светлее
		float fold = smoothstep(0.03, 0.0, abs(d - (R + RING + 0.022))) * clamp(-q.y / R + 0.3, 0.0, 1.0);
		col += vec3(0.022) * fold * step(1.0, nose);
		if (valve < 1.0) {
			// клапан выдоха: тёмная решётка
			float grill = step(0.5, fract((p.x + 0.2) * 70.0));
			col = mix(vec3(0.03, 0.032, 0.03), vec3(0.008), grill * step(valve, 0.8));
			col += vec3(0.03) * smoothstep(0.85, 1.0, valve);
		}
	} else if (d > R) {
		// металлическая обойма: тёмная сталь, скос внутрь, блик сверху, четыре винта
		float k = (d - R) / RING;
		float bevel = smoothstep(0.0, 0.35, k) * smoothstep(1.0, 0.6, k);
		float top = clamp(-q.y / d, 0.0, 1.0);
		col = vec3(0.045, 0.047, 0.045) + vec3(0.07, 0.072, 0.068) * bevel * pow(top, 2.0);
		col += vec3(0.02) * noise(vec2(atan(q.y, q.x) * 40.0, k * 4.0));
		col *= 0.65 + 0.35 * smoothstep(0.0, 0.25, k);
		for (int i = 0; i < 4; i++) {
			float ang = 0.785 + float(i) * 1.5708;
			vec2 sp = c + vec2(cos(ang), sin(ang)) * (R + RING * 0.5);
			float sd = length(p - sp);
			col = mix(col, vec3(0.1, 0.1, 0.095) * (0.6 + 0.6 * clamp(-(p.y - sp.y) / 0.01, 0.0, 1.0)), smoothstep(0.009, 0.006, sd));
		}
	} else {
		float e = smoothstep(R * 0.45, R, d);          // 0 в центре, 1 у обоймы
		// конденсат: туманная кайма у краёв, дышит; при садящемся фильтре ползёт к центру
		float cn = fbm(p * 9.0 + vec2(0.0, TIME * 0.02));
		float cond = smoothstep(0.55 - 0.45 * fog - 0.12 * breath, 1.0, e + cn * 0.35) * (0.28 + 0.4 * breath + 0.55 * fog);
		cond = clamp(cond, 0.0, 0.95);
		vec2 cuv = vec2(c.x / asp, c.y) + 0.5;
		vec2 uv = SCREEN_UV + (cuv - SCREEN_UV) * 0.05 * e * e;   // стягивание к центру окуляра
		uv += (vec2(fbm(p * 22.0), fbm(p * 22.0 + 5.3)) - 0.5) * 0.006 * cond;
		vec3 col0 = textureLod(scr, uv, 1.8 * e + 3.5 * cond).rgb;
		// старое стекло: чуть зеленит и темнеет к ободу
		col = col0 * mix(vec3(1.0), vec3(0.86, 0.92, 0.84), 0.6) * (1.0 - 0.45 * e * e);
		// конденсат — молочная муть
		col = mix(col, col * 0.6 + vec3(0.16, 0.17, 0.16), cond);
		// разводы: большие мутные пятна от пальцев и высохших капель
		float sm = smoothstep(0.55, 0.85, fbm(q * 7.0 + side * 3.7));
		col = mix(col, col * 0.85 + vec3(0.06, 0.065, 0.06), sm * 0.35);
		// следы капель: маленькие светлые кольца
		for (int i = 0; i < 5; i++) {
			float fi = float(i) + (side > 0.0 ? 10.0 : 0.0);
			vec2 dp = c + (vec2(hash1(fi * 5.1), hash1(fi * 9.3)) - 0.5) * R * 1.4;
			float rr = 0.006 + 0.01 * hash1(fi * 2.7);
			col += vec3(0.05) * smoothstep(0.0025, 0.0, abs(length(p - dp) - rr));
		}
		// царапины: тонкие штрихи разной длины
		for (int i = 0; i < 11; i++) {
			float fi = float(i) + (side > 0.0 ? 20.0 : 0.0);
			vec2 sa = c + (vec2(hash1(fi * 3.1), hash1(fi * 7.7)) - 0.5) * R * 1.5;
			float ang = hash1(fi * 13.3) * 3.1416;
			vec2 u = vec2(cos(ang), sin(ang));
			float len = 0.015 + 0.06 * hash1(fi * 1.9);
			float t = clamp(dot(p - sa, u), -len, len);
			float dist = length(p - sa - u * t);
			col += vec3(0.08) * smoothstep(0.0013, 0.0, dist) * (0.35 + 0.65 * hash1(fi));
		}
		// блик дугой сверху-снаружи
		vec2 dir = q / max(d, 0.0001);
		float arc = smoothstep(0.014, 0.0, abs(d - (R - 0.03))) * pow(clamp(-dir.y * 0.8 + side * dir.x * 0.4, 0.0, 1.0), 3.0);
		col += vec3(0.09, 0.1, 0.09) * arc;
		// тень от обоймы
		col *= 1.0 - 0.6 * smoothstep(R - 0.025, R, d);
	}
	// на середине надевания экран темнеет (резина у глаз)
	col *= 1.0 - 0.75 * sin(3.1416 * a);
	COLOR = vec4(col, smoothstep(0.0, 0.12, put));
}"""
	return s


func on_bought() -> void:
	filter_left = FILTER_TIME
	game.hud.toast("Нюхич с фильтром. G — надеть", Color(0.7, 0.85, 0.6))


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
	# надел — глубокий вдох через фильтр; снял — выдох
	voice.stream = breaths[0 if worn else 1]
	voice.volume_db = -13.0
	voice.pitch_scale = 0.72 if worn else 0.9
	voice.play()
	breath_t = 1.4
	game.hud.toast("Нюхич надет" if worn else "Нюхич снят", Color(0.75, 0.85, 0.7))


func _outside() -> float:
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
	if worn and game.inv.count("gasmask") == 0:
		worn = false
	# анимация надевания / снятия
	put = move_toward(put, 1.0 if worn else 0.0, delta / PUT_TIME)
	overlay.visible = put > 0.0
	var out: bool = _outside() > 0.5 and game.alive
	# фильтр тратится только наверху и в маске
	if worn and out:
		filter_left -= delta
		if filter_left <= 0.0:
			if game.inv.count("filter") > 0:
				game.inv.remove("filter", 1)
				filter_left = FILTER_TIME
				game.hud.toast("Новый фильтр (осталось %d)" % game.inv.count("filter"), Color(0.75, 0.85, 0.7))
				game.play_ui("click", -8.0, 0.5)
			else:
				filter_left = 0.0
	var protected := worn and filter_left > 0.0
	if out and not protected:
		tox = minf(tox + TOX_UP * delta, 1.0)
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
	if worn:
		breath_t -= delta
		if breath_t <= 0.0:
			breath_t = lerpf(1.7, 1.15, fog)   # фильтр садится — дышишь чаще и тяжелее
			breath_n += 1
			var exhale := breath_n % 2 == 1
			voice.stream = breaths[1 if exhale else 0]
			voice.volume_db = lerpf(-22.0, -16.0, fog)
			voice.pitch_scale = lerpf(0.8, 0.68, fog)
			voice.play()
			if exhale:
				breath = 1.0
	mat.set_shader_parameter("breath", breath)
	mat.set_shader_parameter("put", put)
	mat.set_shader_parameter("fog", fog)
	_status(out, protected)


## Подсказка сверху: при смене смысла плавно проявляется заново.
func _status(out: bool, protected: bool) -> void:
	var kind := ""
	var text := ""
	var col := Color.WHITE
	if out and not protected:
		kind = "bad" if not worn else "empty"
		text = "ВОЗДУХ ОТРАВЛЕН — вернись в бункер или надень Нюхич (G)" if not worn else "ФИЛЬТР КОНЧИЛСЯ — купи фильтры"
		col = Color(1.0, 0.45, 0.35)
	elif worn:
		kind = "low" if filter_left < FILTER_LOW and out else "filter"
		text = "Фильтр: %d с%s" % [int(ceil(filter_left)), "" if game.inv.count("filter") == 0 else "  (+%d)" % game.inv.count("filter")]
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
