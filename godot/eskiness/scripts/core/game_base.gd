extends Node3D
# Часть game.gd: константы, состояние, звуки, клавиши.
const Player := preload("res://scripts/player/player.gd")
const Hud := preload("res://scripts/hud.gd")
const Inventory := preload("res://scripts/inventory.gd")
const Items := preload("res://scripts/items.gd")
const LootWindow := preload("res://scripts/loot_window.gd")
const GlassFloor := preload("res://scripts/level/glass_floor.gd")
const Save := preload("res://scripts/systems/save.gd")
const Fx := preload("res://scripts/core/fx.gd")
const Pickup := preload("res://scripts/world/pickup.gd")
const Flashlight := preload("res://scripts/player/flashlight.gd")
const TapeSpot := preload("res://scripts/level/tape_spot.gd")
const StonePile := preload("res://scripts/stone_pile.gd")
var tape  # моток изоленты у доски выплат — один на игру
const Enemy := preload("res://scripts/enemy/enemy.gd")
const Dummy := preload("res://scripts/world/dummy.gd")
const Chest := preload("res://scripts/world/chest.gd")
const Jar := preload("res://scripts/world/jar.gd")
const Surface := preload("res://scripts/level/surface.gd")
const SlotMachine := preload("res://scripts/slot/slot_machine.gd")
const Shop := preload("res://scripts/shop/shop.gd")
const GasMask := preload("res://scripts/player/gasmask.gd")
const Gun := preload("res://scripts/gun.gd")
var gun   # gun.gd — пистолет
const StoneThrow := preload("res://scripts/stone_throw.gd")
var stone_throw   # stone_throw.gd — бросок камня (камень в руке: ПКМ держать — прицел, ЛКМ — бросок)
var chat   # ui/chat.gd — чат (T)
var revive   # systems/revive.gd — эффекты смерти, подъём союзника, лечение с полоской
const Sfx := preload("res://scripts/core/sfx.gd")
const Audio := preload("res://scripts/core/audio.gd")
var audio   # core/audio.gd — пул голосов и лимитер (звуки прерывают друг друга, 18.11 01:47)
const Sfx2 := preload("res://scripts/core/sfx_extra.gd")
const Car := preload("res://scripts/car/car.gd")
var car   # старая машина (car.gd): ключ в сейфе; уехать — в деревню, дальше на ней можно ездить
const Village := preload("res://scripts/village/village.gd")
const VillageNet := preload("res://scripts/village/village_net.gd")
var village   # вторая локация — деревня (village.gd)
var play_time := 0.0   # сколько играл (для экрана победы, в сейве)
var won := false

# включение механик
const USE_ENEMIES := true
const USE_DUMMY := true
const USE_CHESTS := true
const USE_SLOTS := true
const USE_FLASHLIGHT := true

const MAX_HP := 100.0
const START := Vector3(-10.5, 0.05, 0.0)
## манекен и сундук — в комнате с KILLBOX слева от магазина (shop.gd у main.gd: x −4.05, z 8.5)
const DUMMY_POS := Vector3(-2.75, 0.0, 7.75)
const STORAGE_POS := Vector3(-1.35, 0.0, 8.55)
## враги бродят по поляне наверху (выход из бункера — лестница в восточном торце коридора)
const ENEMY_SPOTS := [Vector3(28.0, 4.1, 7.0), Vector3(36.0, 4.1, -6.0), Vector3(40.0, 4.1, 4.0), Vector3(31.0, 4.1, -10.0)]
const RESPAWN := 40.0
const FAST_SHARE := 0.4   # доля быстрых врагов («Шныга», enemy.gd kind = "fast") на поляне

## Режим игры (промпт 18.11 00:52), выбирается при новой игре / хостом в лобби, в сейве "mode":
## 0 — реализм (минимальный интерфейс, фильтр меняется вручную), 1 — по умолчанию (фильтр вручную),
## 2 — казуальный (батарейки, патроны, фильтры — сами из сумки).
const MODE_REAL := 0
const MODE_NORMAL := 1
const MODE_CASUAL := 2
var mode := MODE_NORMAL


func casual() -> bool:
	return mode == MODE_CASUAL


var player: Player
var shop_on := true      # Trinkets Market включён (промпт 16.11 04:30): в новой игре — после первых круток; сейв "shop_on"
var shop_cue_done := false   # подсказка «звуки с улицы» после первого магазина (world/shop_cue.gd); сейв "shop_cue_done"
var knife_dummy: Node = null   # манекен с ножом в стартовой комнате (промпт 18.11 01:07)
var dummy_knife_taken := false   # нож из него уже вытащен (в сейве)
var intro_wake_done := false   # пробуждение (лежит → встаёт) уже показано — при загрузке не повторяем (промпт 18.11 01:10)
var intro_done := true   # вступление пройдено (world/intro.gd); автомат включён — в сейве "intro_done"
var takedown   # world/takedown.gd — стелс-добивание мелких врагов сзади на E
var hud: Hud
var net = null   # net.gd в сетевой игре (выставляет main.gd до setup), иначе null
var inv: Inventory
var flashlight: Flashlight
var hp := MAX_HP
var alive := true
var god := false   # godmode из консоли (/cheats on → /god): урон и отравление не берут
var focus: Object = null
var snd := {}
var ui_player: AudioStreamPlayer
var full_toast_t := 0.0
var safe: Chest
var slot: SlotMachine
var shop: Shop
var gasmask: GasMask


# ---------- кувшины и колбы: случайная расстановка (промпты 14.11 00:06 и 00:08) ----------
## Каждая новая игра: 5–8 групп по 1–3 кувшина/колбы у стен комнат бункера и 3–5 групп у руин на поляне,
## разных форм и размеров (jar.gd). Разбиваются ударом — лут выпадает на пол.
## Не ставим у проёмов, автомата, магазина, сейфа, манекена, завалов и стекла; пересечения проверяет физика.
## Расстановка (место, вид, размер, рисунок, разбит ли) пишется в сейв (jars).
const CHEST_AVOID := [[Vector3(-6.0, 0, 8.5), 1.9], [Vector3(-4.05, 0, 8.5), 1.7], [Vector3(-11.5, 0, 5.6), 1.4],
	[Vector3(-2.75, 0, 7.75), 1.2], [Vector3(-2.4, 0, -5.4), 1.2], [Vector3(-1.35, 0, 8.55), 1.2], [Vector3(-10.8, 0, -4.3), 1.8], [Vector3(-7.7, 0, -7.7), 1.5], [Vector3(-8.6, 0, -2.9), 1.4], [Vector3(-10.6, 0, -6.0), 1.4], [Vector3(-6.95, 0, 8.66), 1.0], [Vector3(-10.5, 0, 0), 1.5],
	[Vector3(-6, 0, -1.6), 1.6], [Vector3(-6, 0, 1.6), 1.6], [Vector3(6, 0, -1.6), 1.6], [Vector3(6, 0, 1.6), 1.6],
	[Vector3(0, 0, 5.5), 1.6], [Vector3(-8.5, 0, 5.5), 1.0], [Vector3(8.5, 0, 5.5), 1.0],
	# завалы из level.gd
	[Vector3(-10, 0, -7.5), 1.4], [Vector3(-3, 0, -4), 1.4], [Vector3(2.5, 0, -7.8), 1.4], [Vector3(10, 0, -3.5), 1.4],
	[Vector3(-10.5, 0, 8), 1.4], [Vector3(-2.5, 0, 3.5), 1.4], [Vector3(3, 0, 8), 1.4], [Vector3(10.8, 0, 3.5), 1.4],
	[Vector3(11.0, 0, -6.8), 1.4], [Vector3(-5.5, 0, -8.3), 1.6], [Vector3(7.5, 0, 8.2), 1.5]]
const RUINS := [Vector3(26, 0, -9), Vector3(38, 0, 7), Vector3(35, 0, -12), Vector3(24, 0, 9), Vector3(42, 0, -3)]
var jars: Array = []


# ---------- кувшины снаружи (промпт 14.11 17:35) ----------
## На поляне одновременно не больше OUT_JARS_MAX целых кувшинов. Раз в OUT_JAR_EVERY с, если целых меньше,
## появляется ещё один — в случайном месте поляны: не в будке, не впритык к другим кувшинам и препятствиям,
## не ближе 6 м к игроку (чтобы не возникал на глазах). Старые разбитые снаружи убираем (осколки), держим ≤ 6.
const OUT_JARS_MAX := 4   # было 5 — кувшинов на 20% меньше (промпт 18.11 01:08)
const OUT_JAR_EVERY := 25.0
@warning_ignore("unused_private_class_variable")
var _out_jar_t := OUT_JAR_EVERY


func _make_sounds() -> void:
	snd["coin"] = [Sfx2.coin(0), Sfx2.coin(1), Sfx2.coin(2)]
	snd["creak"] = [Sfx2.creak(0), Sfx2.creak(1)]
	snd["creak_close"] = [Sfx2.creak_close(0), Sfx2.creak_close(1)]
	snd["click"] = [Sfx2.click()]
	snd["tick"] = [Sfx2.tick()]
	snd["clunk"] = [Sfx2.clunk()]
	snd["jingle"] = [Sfx2.jingle()]
	snd["buzz"] = [Sfx2.buzz()]
	snd["growl"] = [Sfx2.growl(0), Sfx2.growl(1), Sfx2.growl(2)]
	snd["thud"] = [Sfx2.thud()]
	snd["pickup"] = [Sfx2.pickup()]
	snd["estep"] = [Sfx.step(10), Sfx.step(11), Sfx.step(12), Sfx.step(13)]   # шаги врагов
	snd["whoosh"] = [Sfx.whoosh(1), Sfx.whoosh(2)]
	snd["hurt"] = [Sfx.exhale(1), Sfx.exhale(3)]


func play_ui(name_: String, db: float, pitch := 1.0) -> void:
	if audio != null and not audio.ui_ok(name_):
		return   # тот же звук уже прозвучал миллисекунду назад — не множим
	var set_: Array = snd[name_]
	ui_player.stream = set_[randi() % set_.size()]
	ui_player.volume_db = db
	ui_player.pitch_scale = pitch * randf_range(0.95, 1.05)
	ui_player.play()


## Разовый 3D-звук через общий пул (core/audio.gd): голосов ограниченное число,
## одинаковый звук из той же точки прерывает сам себя.
func play_at(name_: String, pos: Vector3, db: float, pitch := 1.0) -> void:
	var set_: Array = snd[name_]
	var st: AudioStream = set_[randi() % set_.size()]
	var p2 := pitch * randf_range(0.95, 1.05)
	if audio != null:
		audio.play_3d(st, pos, db, p2, name_)
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = st
	p.volume_db = db
	Audio.setup_3d(p)
	p.pitch_scale = p2
	add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


func _setup_input() -> void:
	_add_keys("interact", [KEY_F])
	_add_keys("inventory", [KEY_TAB, KEY_I])
	_add_keys("flashlight", [KEY_0])
	_add_keys("quick_heal", [KEY_0])   # промпт 18.11 02:27: быстрый хил/подъём союзника — с Q на F (Q/E заняты наклонами)
	_add_keys("lean_left", [KEY_Q])
	_add_keys("lean_right", [KEY_E])


func _add_keys(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


# ---------- стекло и кровотечение (промпт 20:02) ----------
## Битое стекло на полу (те же места, что в level.gd: _floor_litter): наступил — −5 здоровья
## и кровотечение 10 с по 3 в секунду. Повторный наступ обновляет таймер. Снимает бинт или аптечка.
var loot_window: LootWindow   # окно лута ящиков и сейфа
var storage: Chest            # сундук-хранилище
var home                      # world/bunker_home.gd — постройки по чертежам
var carry                     # world/carry.gd — перенос объектов в руках (B)
var glass_floor: GlassFloor   # кучки стекла (glass_floor.gd), случайные каждую новую игру
const BLEED_TIME := 10.0
const BLEED_DPS := 3.0
var on_glass := false
var last_feet_pos := Vector3.INF
var glass_cd := 0.0
var bleed_t := 0.0


# ---------- предмет из хотбара в руке (промпт 18.11 01:16) ----------
## Клавиша 1–5 — берём предмет в руку, применяем удержанием ЛКМ (полоска в revive.gd).
## Отпустили раньше — отмена, полоска дошла — предмет использован (game_items.gd: hb_press / hb_release).
var hb_hand := ""     # id предмета в руке ("" — руки свободны)
var hb_lmb := false   # ЛКМ держат


# ---------- баффы еды и напитков (промпт 20:06) ----------
## buffs[тип] = {"power": доля, "time": осталось, "icon": предмет}; тип — resist (еда) или speed (напитки).
## Новый бафф того же типа: сила — бо́льшая из двух, время — бо́льшее из двух.
var buffs := {}


# ---------- ремкомплекты (промпт 14.11 17:59) ----------

const REPAIR_PART := 0.5    # один заряд — +50% прочности


# ---------- каменные кучки (промпт 14.11 19:22) ----------

## Где лежат кучки: в бункере у завалов (level.gd: _debris) и наверху у руин (surface.gd: _ruins).
const STONE_BUNKER := [Vector3(-9.2, 0.0, -6.8), Vector3(3.3, 0.0, -7.1), Vector3(10.1, 0.0, 2.9)]
const STONE_SURFACE := [Vector3(27.8, 0.0, -9.5), Vector3(36.6, 0.0, 8.6), Vector3(42.5, 0.0, -1.2)]
var stone_piles: Array = []


var chests: Array = []
## что куплено в Trinkets Market (id, по штуке) — «666» забирает одну такую экипировку (slot_machine.gd)
var shop_bought: Array = []


# ---------- сохранения (промпт 23:39) ----------
## Сколько угодно сейвов (save.gd, промпт 18.11 02:00); id сейва — save_slot. Автосейв: каждые 2 минуты, после каждой крутки KILLBOX (и сразу после оплаты —
## перезагрузка не откатит проигрыш), при выходе в меню и при закрытии окна.
const AUTOSAVE := 120.0
const CRASH_SAVE := 30.0     # как часто обновляется аварийная копия (save.gd: write_crash)
var save_slot := ""
var from_save := false      # игра началась загрузкой сейва (своего или присланного хостом)
var autosave_t := AUTOSAVE
var crash_t := CRASH_SAVE
var loading := false


func _v3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


func _to_v3(a) -> Vector3:
	if not (a is Array and a.size() == 3):
		return Vector3.ZERO
	var v := Vector3(float(a[0]), float(a[1]), float(a[2]))
	if v.z > 430.0:   # старые сейвы: деревня была на 360 м дальше (промпт 16.11 02:16)
		v.z -= 360.0
	return v
