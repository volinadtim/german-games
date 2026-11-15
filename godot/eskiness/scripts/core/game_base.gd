extends Node3D
# Часть game.gd: константы, состояние, звуки, клавиши, наценка за мухлёж.
const Player := preload("res://scripts/player/player.gd")
const Hud := preload("res://scripts/hud.gd")
const Inventory := preload("res://scripts/inventory.gd")
const Items := preload("res://scripts/items.gd")
const LootWindow := preload("res://scripts/loot_window.gd")
const GlassFloor := preload("res://scripts/glass_floor.gd")
const Save := preload("res://scripts/systems/save.gd")
const Fx := preload("res://scripts/fx.gd")
const Pickup := preload("res://scripts/pickup.gd")
const Flashlight := preload("res://scripts/flashlight.gd")
const TapeSpot := preload("res://scripts/tape_spot.gd")
const StonePile := preload("res://scripts/stone_pile.gd")
var tape  # моток изоленты у доски выплат — один на игру
const Enemy := preload("res://scripts/enemy/enemy.gd")
const Dummy := preload("res://scripts/dummy.gd")
const Chest := preload("res://scripts/chest.gd")
const Jar := preload("res://scripts/jar.gd")
const Surface := preload("res://scripts/surface.gd")
const SlotMachine := preload("res://scripts/slot/slot_machine.gd")
const Shop := preload("res://scripts/shop/shop.gd")
const GasMask := preload("res://scripts/gasmask.gd")
const Gun := preload("res://scripts/gun.gd")
var gun   # gun.gd — пистолет
const StoneThrow := preload("res://scripts/stone_throw.gd")
var stone_throw   # stone_throw.gd — бросок камня (T)
const Sfx := preload("res://scripts/sfx.gd")
const Sfx2 := preload("res://scripts/sfx_extra.gd")
const Car := preload("res://scripts/car/car.gd")
var car   # старая машина на поляне (car.gd): ключ в сейфе, уехать = победа
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
## враги бродят по поляне наверху (выход из бункера — лестница в восточном торце коридора)
const ENEMY_SPOTS := [Vector3(28.0, 4.1, 7.0), Vector3(36.0, 4.1, -6.0), Vector3(40.0, 4.1, 4.0), Vector3(31.0, 4.1, -10.0)]
const RESPAWN := 40.0
const FAST_SHARE := 0.4   # доля быстрых врагов («Шныга», enemy.gd kind = "fast") на поляне

var player: Player
var hud: Hud
var net = null   # net.gd в сетевой игре (выставляет main.gd до setup), иначе null
var inv: Inventory
var flashlight: Flashlight
var hp := MAX_HP
var alive := true
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
const CHEST_AVOID := [[Vector3(-6.0, 0, 8.5), 1.9], [Vector3(-4.05, 0, 8.5), 1.7], [Vector3(11.5, 0, 7.0), 1.4],
	[Vector3(-8.0, 0, -3.6), 1.3], [Vector3(-6.95, 0, 8.66), 1.0], [Vector3(-10.5, 0, 0), 1.5],
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
const OUT_JARS_MAX := 5
const OUT_JAR_EVERY := 25.0
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
	snd["dread"] = [Sfx2.dread()]
	snd["estep"] = [Sfx.step(10), Sfx.step(11), Sfx.step(12), Sfx.step(13)]   # шаги врагов
	snd["whoosh"] = [Sfx.whoosh(1), Sfx.whoosh(2)]
	snd["hurt"] = [Sfx.exhale(1), Sfx.exhale(3)]


func play_ui(name_: String, db: float, pitch := 1.0) -> void:
	var set_: Array = snd[name_]
	ui_player.stream = set_[randi() % set_.size()]
	ui_player.volume_db = db
	ui_player.pitch_scale = pitch * randf_range(0.95, 1.05)
	ui_player.play()


func play_at(name_: String, pos: Vector3, db: float, pitch := 1.0) -> void:
	var set_: Array = snd[name_]
	var p := AudioStreamPlayer3D.new()
	p.stream = set_[randi() % set_.size()]
	p.volume_db = db
	p.unit_size = 4.0
	p.pitch_scale = pitch * randf_range(0.95, 1.05)
	add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


func _setup_input() -> void:
	_add_keys("interact", [KEY_E])
	_add_keys("inventory", [KEY_TAB, KEY_I])
	_add_keys("flashlight", [KEY_F])
	_add_keys("quick_heal", [KEY_Q])


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
var glass_floor: GlassFloor   # кучки стекла (glass_floor.gd), случайные каждую новую игру
const BLEED_TIME := 10.0
const BLEED_DPS := 3.0
var on_glass := false
var last_feet_pos := Vector3.INF
var glass_cd := 0.0
var bleed_t := 0.0


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


# ---------- анти-мухлёж ----------
## Выбросил много монет (CHEAT_DROP+), оставил себе мало (≤ CHEAT_KEEP) и пошёл крутить KILLBOX —
## с поверхности по лестнице спускаются 5 монстров и охотятся на игрока прямо в бункере.
## Подобрал выброшенные монеты обратно — счётчик уменьшается.
const CHEAT_DROP := 10        # стартовых монет мало, поэтому порог низкий (промпт 23:59)
const CHEAT_KEEP := 20
var dropped_coins := 0
var chests: Array = []
var hunters: Array = []


## Наценка за мухлёж (промпт 14.11 18:10): каждая поимка +1 к cheat_count; на одну следующую покупку
## в Trinkets Market цена × (1 + 10% × cheat_count), вверх. Купил — наценка снята до следующей поимки.
var cheat_count := 0
var markup_pending := false


func markup_pct() -> int:
	return 10 * cheat_count if markup_pending else 0


func marked_price(p: int) -> int:
	return (p * (100 + markup_pct()) + 99) / 100


func markup_used() -> void:
	markup_pending = false


## Вызывает автомат после оплаты крутки. true — мухлёж пойман.
func cheat_check() -> bool:
	if dropped_coins < CHEAT_DROP or inv.coins > CHEAT_KEEP or dropped_coins < inv.coins:
		return false
	dropped_coins = 0
	cheat_count += 1
	markup_pending = true
	hud.cheat_warning(true)
	play_ui("dread", -1.0, 1.0)  # страшный звук за мухлёж (промпт 14.11 17:26)
	_spawn_hunters()
	return true


func _spawn_hunters(count := 3) -> void:
	if net and not net.is_host():
		net.request_hunters(count)   # враги в сети живут у хоста
		return
	for k in count:
		var e := Enemy.new()
		e.game = self
		e.position = Vector3(20.0 - (k % 2) * 0.8, 4.1, -0.6 + (k % 3) * 0.6)
		e.rotation.y = PI / 2.0
		add_child(e)
		e.make_hunter()
		hunters.append(e)
		e.died.connect(_hunter_died)
		await get_tree().create_timer(0.6).timeout


func _hunter_died(e: Node) -> void:
	hunters.erase(e)
	if hunters.is_empty():
		hud.cheat_warning(false)


# ---------- сохранения (промпт 23:39) ----------
## 3 слота (save.gd). Автосейв: каждые 2 минуты, после каждой крутки KILLBOX (и сразу после оплаты —
## перезагрузка не откатит проигрыш), при выходе в меню и при закрытии окна.
const AUTOSAVE := 120.0
var save_slot := 1
var autosave_t := AUTOSAVE
var loading := false


func _v3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


func _to_v3(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2])) if a is Array and a.size() == 3 else Vector3.ZERO
