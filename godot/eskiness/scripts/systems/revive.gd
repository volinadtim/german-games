extends Node
## Смерть и подъём (промпты 03:06, 03:07). Создаётся в game.gd (game.revive).
## - Эффекты смерти: тёмно-красный виньет и приглушённый звук (фильтр на шине Master).
## - Сеть: упавший не возрождается сам — лежит, союзник поднимает его медициной (навести на тело, E
##   или использовать бинт/аптечку). Чем сильнее лечение, тем больше здоровья у поднятого.
##   Если лежат все — обычная смерть и возрождение (net_world.gd, dead_t).
## - Лечение и подъём не мгновенные: полоска прогресса, прерывается движением или уроном.

const Items := preload("res://scripts/items.gd")
const Gun := preload("res://scripts/gun.gd")
const REVIVE_R := 2.6       # м, с какого расстояния можно поднять
const REVIVE_MULT := 1.2    # здоровье поднятого = лечение предмета × это
const DEATH_SCREEN := 1.6   # с, через сколько после падения показывать экран смерти

var game
var downed := false         # сеть: лежим и ждём союзника

# полоска действия
var ch_on := false
var ch_t := 0.0
var ch_dur := 1.0
var ch_hp := 0.0
var ch_snd := 0.0
var ch_kneel := false
var ch_done: Callable
var ch_valid: Callable
var bar_layer: CanvasLayer
var bar_box: Control
var bar_fill: ColorRect
var bar_l: Label

# эффекты смерти
var fx_layer: CanvasLayer
var fx_mat: ShaderMaterial
var fx_tw: Tween
var lp: AudioEffectLowPassFilter
var amp: AudioEffectAmplify
var mute_tw: Tween


func _ready() -> void:
	fx_layer = CanvasLayer.new()
	fx_layer.layer = -1          # под HUD (layer 0), поверх 3D
	add_child(fx_layer)
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float k = 0.0;
void fragment() {
	vec2 uv = (UV - 0.5) * vec2(1.35, 1.0);
	float v = smoothstep(0.18, 0.8, length(uv));
	vec3 c = mix(vec3(0.02, 0.0, 0.0), vec3(0.38, 0.0, 0.0), v);
	COLOR = vec4(c, clamp(k * (0.32 + v * 0.75), 0.0, 0.93));
}
"""
	fx_mat.shader = sh
	r.material = fx_mat
	fx_layer.add_child(r)

	bar_layer = CanvasLayer.new()
	bar_layer.layer = 1
	add_child(bar_layer)
	bar_box = Control.new()
	bar_box.anchor_left = 0.5
	bar_box.anchor_right = 0.5
	bar_box.anchor_top = 1.0
	bar_box.anchor_bottom = 1.0
	bar_box.offset_left = -170
	bar_box.offset_right = 170
	bar_box.offset_top = -215
	bar_box.offset_bottom = -170
	bar_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_box.visible = false
	bar_layer.add_child(bar_box)
	bar_l = Label.new()
	bar_l.position = Vector2(0, 0)
	bar_l.size = Vector2(340, 24)
	bar_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar_l.add_theme_font_size_override("font_size", 17)
	bar_l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	bar_l.add_theme_constant_override("outline_size", 5)
	bar_box.add_child(bar_l)
	var bg := ColorRect.new()
	bg.position = Vector2(0, 28)
	bg.size = Vector2(340, 12)
	bg.color = Color(0, 0, 0, 0.6)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_box.add_child(bg)
	bar_fill = ColorRect.new()
	bar_fill.position = Vector2(2, 30)
	bar_fill.size = Vector2(0, 8)
	bar_fill.color = Color(0.55, 0.85, 0.5)
	bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_box.add_child(bar_fill)


func _exit_tree() -> void:
	_unmuffle()


# ---------- смерть ----------

## game._die: виньет, звук глохнет; в одиночке экран смерти — после падения.
func on_died() -> void:
	_stop("")
	_fx(true)
	if game.net == null:
		_death_screen_later()


func _death_screen_later() -> void:
	await get_tree().create_timer(DEATH_SCREEN).timeout
	if is_instance_valid(game) and not game.alive and not game.won:
		game.hud.show_death(true)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _fx(on: bool) -> void:
	if fx_tw:
		fx_tw.kill()
	fx_tw = create_tween()
	fx_tw.tween_property(fx_mat, "shader_parameter/k", 1.0 if on else 0.0, 2.2 if on else 0.6)
	if mute_tw:
		mute_tw.kill()
	if on and lp == null:
		lp = AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 20000.0
		amp = AudioEffectAmplify.new()
		AudioServer.add_bus_effect(0, lp)
		AudioServer.add_bus_effect(0, amp)
	if lp == null:
		return
	mute_tw = create_tween().set_parallel()
	mute_tw.tween_property(lp, "cutoff_hz", 600.0 if on else 20000.0, 1.6 if on else 0.6)
	mute_tw.tween_property(amp, "volume_db", -9.0 if on else 0.0, 1.6 if on else 0.6)
	if not on:
		mute_tw.chain().tween_callback(_unmuffle)


func _unmuffle() -> void:
	for i in range(AudioServer.get_bus_effect_count(0) - 1, -1, -1):
		var e := AudioServer.get_bus_effect(0, i)
		if e == lp or e == amp:
			AudioServer.remove_bus_effect(0, i)
	lp = null
	amp = null


## Сеть: есть ли живой союзник, который может поднять.
func can_be_revived() -> bool:
	var net = game.net
	if net == null:
		return false
	for id in net.puppets:
		var pp = net.puppets[id]
		if pp != null and is_instance_valid(pp) and not pp.dying and bool(pp.get_meta("alive", true)):
			return true
	return false


func set_downed() -> void:
	downed = true


## Нас подняли (net_world.gd → net_revive).
func revived(amount: float, who: String) -> void:
	if not downed or game.alive:
		return
	downed = false
	game.alive = true
	game.hp = clampf(amount, 1.0, game.MAX_HP)
	game.bleed_t = 0.0
	game.hud.set_hp(game.hp, game.MAX_HP)
	game.inv.enabled = true
	game.player.active = true
	game.player.end_death()
	if game.net and game.net.info_l:
		game.net.info_l.text = ""
	_fx(false)
	game.hud.toast("Вас поднял %s (+%d здоровья)" % [who, int(game.hp)], Color(0.75, 0.9, 0.65))
	game.play_ui("pickup", -10.0, 0.7)


## Сеть: обычное возрождение у старта (net_world.gd _respawn).
func on_respawn() -> void:
	downed = false
	_fx(false)


# ---------- подъём союзника ----------

## Лежащий союзник, на которого смотрим (копия игрока из сети), или null.
func ally_down() -> Object:
	var net = game.net
	if net == null or not game.alive or game.player == null:
		return null
	var cam: Camera3D = game.player.cam
	var from := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var best: Object = null
	var best_a := 99.0
	for id in net.puppets:
		var pp = net.puppets[id]
		if pp == null or not is_instance_valid(pp) or not pp.dying:
			continue
		var c: Vector3 = pp.global_position + pp.global_basis * Vector3(pp.death_side * 0.6, 0.25, 0.0)
		var to := c - from
		var d := to.length()
		if d > REVIVE_R or d < 0.05:
			continue
		var a := fwd.angle_to(to)
		if a > maxf(deg_to_rad(24.0), atan(0.7 / d)) or a >= best_a:
			continue
		best = pp
		best_a = a
	return best


## Самая сильная медицина в инвентаре (id или "").
func best_med() -> String:
	var best := ""
	var bv := 0.0
	for id in Items.ITEMS:
		if not Items.ITEMS[id].has("heal") or game.inv.count(id) == 0:
			continue
		var v: float = Items.ITEMS[id]["heal"]
		if v > bv:
			best = id
			bv = v
	return best


func _ally_name(pp) -> String:
	return String(game.net.players.get(int(pp.get_meta("peer", 0)), "союзника"))


## Поднять союзника, на которого смотрим, предметом id ("" — лучшим). false — союзника под прицелом нет.
func try_revive_with(id: String) -> bool:
	var pp = ally_down()
	if pp == null:
		return false
	if ch_on:
		return true
	if id == "":
		id = best_med()
	if id == "":
		game.hud.toast("Нечем поднять — нужна медицина")
		return true
	var hv: float = Items.ITEMS[id]["heal"]
	var amount := clampf(hv * REVIVE_MULT, 10.0, game.MAX_HP)
	var peer := int(pp.get_meta("peer", 0))
	var nm := _ally_name(pp)
	_channel(3.0 + hv / 25.0, "Поднимаете %s: %s" % [nm, Items.item_name(id)],
			func(): _finish_revive(pp, peer, id, amount, nm),
			func() -> bool: return is_instance_valid(pp) and pp.dying and game.player.global_position.distance_to(pp.global_position) < REVIVE_R + 0.8,
			true)
	return true


func _finish_revive(pp, peer: int, id: String, amount: float, nm: String) -> void:
	if game.inv.count(id) <= 0 or not is_instance_valid(pp) or not pp.dying:
		return
	game.take_one(id)   # предмет может быть в руке, а не в сумке
	game.net.rpc_id(peer, "net_revive", amount)
	game.hud.toast("Вы подняли %s (+%d здоровья)" % [nm, int(amount)], Color(0.75, 0.9, 0.65))
	game.play_ui("pickup", -10.0, 0.75)


# ---------- лечение ----------

## Лечение предметом id с полоской (game_items.gd use_item / _quick_heal).
func heal_channel(id: String) -> void:
	var hv: float = Items.ITEMS[id]["heal"]
	_channel(1.0 + hv / 25.0, Items.item_name(id), func(): _finish_heal(id), Callable(), false)
	ch_walk = id == "bandage"


func _finish_heal(id: String) -> void:
	if game.inv.count(id) <= 0 or not game.alive:
		return
	var def: Dictionary = Items.ITEMS[id]
	var stops: bool = id in ["bandage", "medkit"] and game.bleed_t > 0.0
	game.take_one(id)   # предмет может быть в руке, а не в сумке
	game.heal(def["heal"])
	if stops:
		game.stop_bleeding()
	game.hud.toast("%s: +%d здоровья" % [Items.item_name(id), int(def["heal"])], Color(0.7, 0.9, 0.6))
	game.play_ui("pickup", -12.0, 0.8)


## Применение предмета из руки: полоска идёт, пока держат кнопку этой руки (game_items.gd hb_press).
## Отпустили (или предмет убрали из руки) — ch_valid возвращает false, полоска гаснет, предмет цел.
func use_channel(id: String) -> void:
	_channel(Items.use_time(id), "Применяет: %s" % Items.item_name(id),
		func(): _finish_use(id), func(): return game.hb_lmb and game.hb_key() != null, false)
	ch_walk = true
	ch_silent = true


func _finish_use(id: String) -> void:
	if not game.alive:
		return
	var k = game.hb_key()   # предмет применяют прямо из руки (промпт 18.11 02:27)
	if k == null:
		game.hb_clear("Предмет кончился")
		return
	game.use_item(k, true)
	game.hb_after_use(id)


## Снять полоску без сообщения (предмет убрали из руки).
func cancel_channel() -> void:
	_stop("")


# ---------- полоска действия ----------

var ch_walk := false   # полоска не прерывается шагом (бинт)
var ch_silent := false # отпустили ЛКМ — гасим полоску молча (хотбар в руке)


func _channel(dur: float, text: String, done: Callable, valid: Callable, kneel: bool) -> void:
	if ch_on:
		return
	ch_walk = false
	ch_silent = false
	ch_on = true
	ch_t = 0.0
	ch_dur = dur
	ch_done = done
	ch_valid = valid
	ch_hp = game.hp
	ch_snd = 0.0
	bar_l.text = text
	bar_fill.size.x = 0.0
	bar_box.visible = true
	if game.inv.open:
		game.inv.close()
	var p = game.player
	if p.fists:
		p.toggle_fists()
	ch_kneel = kneel and not p.crouch_toggled
	if ch_kneel:
		p.crouch_toggled = true   # к лежащему — на колено (виден и другим: флаг приседа)
	game.play_ui("whoosh", -22.0, 1.5)


func _stop(msg: String) -> void:
	if not ch_on:
		return
	ch_on = false
	bar_box.visible = false
	var p = game.player
	if p and is_instance_valid(p):
		if ch_kneel:
			p.crouch_toggled = false
		if not p.dying:
			p.head.rotation.z = 0.0
	ch_kneel = false
	if msg != "":
		game.hud.toast(msg, Color(1.0, 0.7, 0.5))


func _process(delta: float) -> void:
	if game == null or game.player == null:
		return
	if downed:
		if not can_be_revived():
			downed = false   # лежат все — обычная смерть и возрождение
			game.net.dead_t = game.net.RESPAWN_T
		elif game.net.info_l:
			game.net.info_l.text = "Вы тяжело ранены. Союзник может поднять вас медициной"
	if ch_on:
		_channel_tick(delta)
	elif game.alive and game.focus == null and not game.window_open():
		var pp = ally_down()
		if pp != null:
			var med := best_med()
			if med != "":
				game.hud.prompt("E — поднять %s (%s)" % [_ally_name(pp), Items.item_name(med)])
			else:
				game.hud.prompt("%s ранен — нужна медицина, чтобы поднять" % _ally_name(pp))


func _channel_tick(delta: float) -> void:
	var p = game.player
	var why := ""
	if not game.alive:
		_stop("")
		return
	# бинт можно на ходу, но не на бегу (промпт 16.11 05:12); остальное — стоя
	var walk_ok: bool = ch_walk and not Input.is_action_pressed("sprint") 			and Vector2(p.velocity.x, p.velocity.z).length() < p.WALK * maxf(1.0, float(p.speed_mult)) + 0.6   # с баффами скорости одежды (05:39)
	var moving: bool = Input.get_vector("move_left", "move_right", "move_forward", "move_back").length() > 0.2 			or Vector2(p.velocity.x, p.velocity.z).length() > 1.2
	# в машине (car_drive.gd) игрок стоит, а едет машина: пассажиру ничего не мешает (бинтуется на ходу),
	# водителю — руль, газ, ручник и пересадка за руль: начал рулить — перевязка отменяется (промпт 18.11 00:49)
	var seat: int = p.get_meta("car_seat", -1)
	if seat >= 0:
		walk_ok = true
		var car = game.get("car")
		moving = seat == 0 and (Gun.steering() or (car != null and is_instance_valid(car) and int(car.seat_dir) == 2))
		if moving:
			walk_ok = false
	if seat < 0 and Input.is_action_just_pressed("jump") or (moving and not walk_ok):
		why = "Прервано: руль" if seat == 0 else ("Прервано: бег" if ch_walk else "Прервано: движение")
	elif game.hp < ch_hp - 0.9:   # кровотечение капает понемногу — прерывает только настоящий урон
		why = "Прервано: урон"
	elif ch_valid.is_valid() and not ch_valid.call():
		why = "~" if ch_silent else "Прервано"   # «~» — тихая отмена (отпустили ЛКМ)
	ch_hp = game.hp
	if why != "":
		_stop("" if why == "~" else why)
		return
	ch_t += delta
	bar_fill.size.x = 336.0 * clampf(ch_t / ch_dur, 0.0, 1.0)
	# анимация: лёгкое покачивание взгляда, звук возни с бинтом/упаковкой
	p.head.rotation.z = sin(ch_t * 4.2) * 0.03
	ch_snd -= delta
	if ch_snd <= 0.0:
		ch_snd = randf_range(0.35, 0.6)
		if randf() < 0.6:
			game.play_ui("whoosh", -27.0, randf_range(1.8, 2.6))
		else:
			game.play_ui("tick", -24.0, randf_range(0.6, 0.9))
	if ch_t >= ch_dur:
		var d := ch_done
		_stop("")
		if d.is_valid():
			d.call()


func _unhandled_input(e: InputEvent) -> void:
	if game == null or not game.alive or game.player == null or game.window_open():
		return
	if e.is_action_pressed("interact") and not e.is_echo() and not ch_on and game.focus == null:
		if try_revive_with(""):
			get_viewport().set_input_as_handled()
