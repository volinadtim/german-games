extends RefCounted
## Уровни и опыт (промпт 20.11 18:48): опыт за убийства, первый обыск ящика/сундука, выигрыши в автоматах.
## Каждый новый уровень — очко атрибута; атрибуты качаются в окне прокачки (systems/skills.gd, K) разделом
## «АТРИБУТЫ», у каждого лимит MAX_ATTR. Данные живут в skills (xp, attrs) и сохраняются вместе с ним.
## Множители читаются отовсюду статически через preload. Split-Screen: уровень общий на экран.

const MAX_ATTR := 5
const MAX_LEVEL := 26   # 25 очков = все атрибуты до лимита
## атрибуты: [id, название, что даёт один уровень]
const ATTRS := [
	["speed", "Скорость", "+4% скорости ходьбы и бега"],
	["melee", "Ближний бой", "+8% урона кулаками и холодным оружием"],
	["steady", "Твёрдая рука", "−12% качания ствола огнестрела"],
	["resist", "Стойкость", "−5% получаемого урона"],
	["hp", "Здоровье", "+10 к максимуму здоровья"],
]
const XP_KILL := 12
const XP_KILL_HEAVY := 25
const XP_LOOT := 4

static var skills: Node = null   # systems/skills.gd текущей игры


## Подключить к окну прокачки: раздел «АТРИБУТЫ» (game.gd после создания skills).
static func register(s: Node) -> void:
	skills = s
	s.add_section("АТРИБУТЫ", func(): return items())


## Карточки атрибутов: уровень/лимит и кнопка за очко.
static func items() -> Array:
	var out: Array = []
	for a in ATTRS:
		var l := attr(a[0])
		out.append({"id": "attr_" + String(a[0]), "attr": a[0],
			"name": "%s  %d/%d" % [a[1], l, MAX_ATTR] + ("  (максимум)" if l >= MAX_ATTR else ""),
			"desc": "За уровень: " + String(a[2])})
	return out


## Опыт, нужный с уровня n на n+1.
static func need(n: int) -> int:
	return 40 + 25 * (n - 1)


## Текущий уровень по накопленному опыту.
static func level() -> int:
	var x := xp()
	var n := 1
	while n < MAX_LEVEL and x >= need(n):
		x -= need(n)
		n += 1
	return n


## Опыт внутри текущего уровня: [набрано, нужно] (нужно 0 — максимум).
static func progress() -> Array:
	var x := xp()
	var n := 1
	while n < MAX_LEVEL and x >= need(n):
		x -= need(n)
		n += 1
	return [x, need(n) if n < MAX_LEVEL else 0]


## Всего опыта.
static func xp() -> int:
	return int(skills.xp) if skills != null and is_instance_valid(skills) else 0


## Уровень атрибута (0..MAX_ATTR).
static func attr(id: String) -> int:
	if skills == null or not is_instance_valid(skills):
		return 0
	return int(skills.attrs.get(id, 0))


## Свободные очки атрибутов.
static func points() -> int:
	var used := 0
	for a in ATTRS:
		used += attr(a[0])
	return maxi(level() - 1 - used, 0)


## Начислить опыт; на новом уровне — тост «прокачай атрибут».
static func add_xp(n: int, why := "") -> void:
	if n <= 0 or skills == null or not is_instance_valid(skills):
		return
	var was := level()
	skills.xp = int(skills.xp) + n
	var now := level()
	var g = skills.game
	if g == null or g.hud == null:
		return
	if now > was:
		g.hud.toast("НОВЫЙ УРОВЕНЬ %d! K — прокачать атрибут" % now, Color(0.55, 0.9, 1.0))
		g.play_ui("coin", -6.0, 1.6)
		if g.has_method("save_now"):
			g.call_deferred("save_now")
	elif why != "":
		g.hud.toast("+%d опыта · %s" % [n, why], Color(0.6, 0.8, 0.95))
	if skills.open:
		skills._rebuild()


## Прокачать атрибут за очко. true — получилось.
static func upgrade(id: String) -> bool:
	if points() <= 0 or attr(id) >= MAX_ATTR:
		return false
	skills.attrs[id] = attr(id) + 1
	apply()
	return true


## Применить атрибуты к игре (максимум здоровья).
static func apply() -> void:
	if skills == null or not is_instance_valid(skills) or skills.game == null:
		return
	var g = skills.game
	g.MAX_HP = 100.0 + 10.0 * attr("hp")
	g.hp = minf(g.hp, g.MAX_HP)
	if g.hud:
		g.hud.set_hp(g.hp, g.MAX_HP, true)


## Убит враг: опыт, если добил свой игрок (или выстрел/бросок без автора вне сети).
static func on_kill(enemy: Node, by: Variant) -> void:
	if skills == null or not is_instance_valid(skills) or skills.game == null:
		return
	var g = skills.game
	var mine := false
	if by != null and is_instance_valid(by):
		var sp = g.get_meta("split", null)
		mine = by == g.player or (sp != null and by == sp.pp)
	else:
		mine = g.get("net") == null
	if mine:
		add_xp(XP_KILL_HEAVY if str(enemy.get("kind")) == "heavy" else XP_KILL)


## Множитель скорости ходьбы/бега.
static func speed_k() -> float:
	return 1.0 + 0.04 * attr("speed")


## Множитель урона ближнего боя.
static func melee_k() -> float:
	return 1.0 + 0.08 * attr("melee")


## Множитель качания ствола (gun.gd).
static func sway_k() -> float:
	return 1.0 - 0.12 * attr("steady")


## Множитель получаемого урона.
static func resist_k() -> float:
	return 1.0 - 0.05 * attr("resist")
