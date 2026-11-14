extends CanvasLayer
## Противогаз и отравленный воздух наверху.
## G — надеть/снять (слот «Лицо» в инвентаре, туда же можно перетащить мышью). Фильтр работает 90 с, только пока ты наверху в маске;
## кончился — автоматически ставится следующий из инвентаря.
## Наверху без защиты копится «отравление» tox (0..1): замедление, искажения в глазах, быстрая потеря здоровья.
## Если быстро вернуться в бункер — выжить можно: в бункере эффекты спадают постепенно.

const FILTER_TIME := 100.0
const TOX_UP := 1.0 / 3.0      # до полного отравления ~3 с (дебаффы нарастают быстро)
const TOX_DOWN := 1.0 / 12.0   # спадает ~12 с

var game
var worn := false
var filter_left := 0.0
var tox := 0.0
var surface: Node
var overlay: ColorRect
var status_l: Label
var breath_t := 0.0
var voice: AudioStreamPlayer
var breaths: Array = []


func _ready() -> void:
	layer = -1   # ниже HUD (слой 0): интерфейс виден поверх маски
	overlay = ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = _mask_shader()
	overlay.material = sm
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


## Вид изнутри противогаза: два крупных окуляра в чёрной резиновой маске с чёткой кромкой и перемычкой у носа.
## Стекло: к краю чуть мутнеет и размывается, картинка у кромки слегка «стягивается» к центру,
## блик дугой сверху-слева и несколько тонких царапин.
func _mask_shader() -> Shader:
	var s := Shader.new()
	s.code = """shader_type canvas_item;
uniform sampler2D scr : hint_screen_texture, filter_linear_mipmap;
const float R = 0.46;      // радиус окуляра (доля высоты экрана)
const float RIM = 0.03;    // ширина резиновой кромки
const float CX = 0.29;     // центры окуляров по горизонтали

float hash(float n) { return fract(sin(n) * 43758.5453); }

void fragment() {
	float asp = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 p = SCREEN_UV - 0.5;
	p.x *= asp;
	vec2 cl = vec2(-CX, 0.02);
	vec2 cr = vec2(CX, 0.02);
	float dl = length((p - cl) * vec2(1.0, 1.1));
	float dr = length((p - cr) * vec2(1.0, 1.1));
	vec2 c = dl < dr ? cl : cr;
	float d = min(dl, dr);
	// перемычка у носа: снизу между окулярами
	float bridge = step(length((p - vec2(0.0, 0.56)) / vec2(0.12, 0.34)), 1.0);
	if (d > R || bridge > 0.5) {
		COLOR = vec4(0.012, 0.014, 0.012, 1.0);
	} else if (d > R - RIM) {
		// кромка: тёмная резина с едва заметным отсветом сверху
		float k = (d - (R - RIM)) / RIM;
		float top = clamp(-(p.y - c.y) / R, 0.0, 1.0);
		COLOR = vec4(vec3(0.03 + 0.05 * top * (1.0 - k)), 1.0);
	} else {
		float e = smoothstep(R * 0.55, R - RIM, d);      // 0 в центре, 1 у кромки
		vec2 cuv = vec2(c.x / asp, c.y) + 0.5;
		vec2 uv = SCREEN_UV + (cuv - SCREEN_UV) * 0.035 * e * e;   // лёгкое стягивание к центру
		vec3 col = textureLod(scr, uv, 2.2 * e).rgb;
		// муть у краёв: чуть светлее и зеленовато-серая
		col = mix(col, col * 0.75 + vec3(0.05, 0.06, 0.05), 0.35 * e);
		// блик дугой сверху-слева
		vec2 dir = normalize(p - c + vec2(0.0001));
		float arc = smoothstep(0.018, 0.0, abs(d - (R - RIM - 0.045))) * pow(clamp(-(dir.x + dir.y) * 0.72, 0.0, 1.0), 4.0);
		col += vec3(0.1, 0.11, 0.1) * arc;
		// царапины: короткие тонкие штрихи
		for (int i = 0; i < 7; i++) {
			float fi = float(i);
			vec2 a = c + (vec2(hash(fi * 3.1), hash(fi * 7.7)) - 0.5) * R * 1.3;
			float ang = hash(fi * 13.3) * 3.1416;
			vec2 u = vec2(cos(ang), sin(ang));
			float t = clamp(dot(p - a, u), -0.05, 0.05);
			float dist = length(p - a - u * t);
			col += vec3(0.07) * smoothstep(0.0012, 0.0, dist) * (0.5 + 0.5 * hash(fi));
		}
		COLOR = vec4(col, 1.0);
	}
}"""
	return s


func on_bought() -> void:
	filter_left = FILTER_TIME
	game.hud.toast("Противогаз с фильтром. G — надеть", Color(0.7, 0.85, 0.6))


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("gasmask") and game and game.alive:
		game.toggle_gasmask()


## Надет ли противогаз — управляет слот «Лицо» в инвентаре (game.gd: _apply_equip).
func set_worn(on: bool) -> void:
	if on == worn:
		return
	worn = on
	overlay.visible = worn
	game.hud.toast("Противогаз надет" if worn else "Противогаз снят", Color(0.75, 0.85, 0.7))


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
		overlay.visible = false
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
	# замедление и искажения
	# множители перемножаются: отравление × бафф скорости от напитка (game.gd: buff_mult)
	game.player.speed_mult = (1.0 - 0.55 * tox) * game.buff_mult("speed")
	if game.player.post_mat:
		game.player.post_mat.set_shader_parameter("toxic", tox)
	# дыхание в маске
	if worn:
		breath_t -= delta
		if breath_t <= 0.0:
			breath_t = 1.7
			voice.stream = breaths[int(Time.get_ticks_msec() / 1700) % 2]
			voice.volume_db = -22.0
			voice.pitch_scale = 0.8
			voice.play()
	# подсказки
	if out and not protected:
		status_l.text = "ВОЗДУХ ОТРАВЛЕН — вернись в бункер или надень противогаз (G)" if not worn else "ФИЛЬТР КОНЧИЛСЯ — купи фильтры"
		status_l.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
	elif worn:
		status_l.text = "Фильтр: %d с%s" % [int(ceil(filter_left)), "" if game.inv.count("filter") == 0 else "  (+%d)" % game.inv.count("filter")]
		status_l.add_theme_color_override("font_color", Color(0.75, 0.85, 0.7))
	elif tox > 0.05:
		status_l.text = "Отравление проходит…"
		status_l.add_theme_color_override("font_color", Color(0.85, 0.8, 0.5))
	else:
		status_l.text = ""
