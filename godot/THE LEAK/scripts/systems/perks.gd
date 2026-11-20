extends RefCounted
## Пассивное древо прокачки (промпт 20.11 18:06): за монеты — удача, выносливость, скидка на всё, мотор машины.
## Живёт в общем окне прокачки (systems/skills.gd, K) разделом «ПАССИВНЫЕ»: у каждой ветки видна карточка
## следующего уровня. Купленный уровень — навык "<ветка>_<N>" в skills.owned (сохраняется вместе с ним).
## Множители читаются отовсюду статически через preload. В сети у каждого свои уровни.
const _D_PERKS := preload("res://data/balance/perks.tres")   # настраиваемые числа этого скрипта (scripts/data/data_table.gd)

## ветки: [id, название, что даёт один уровень, цены уровней 1..N]
static var TREE: Array = _D_PERKS.v("TREE")

static var skills: Node = null   # systems/skills.gd текущей игры


## Подключить к окну прокачки: раздел «ПАССИВНЫЕ» (game.gd после создания skills).
static func register(s: Node) -> void:
	skills = s
	s.add_section("ПАССИВНЫЕ", func(): return items())


## Карточки раздела: по одной на ветку — следующий уровень (или последний купленный).
static func items() -> Array:
	var out: Array = []
	for b in TREE:
		var l := level(b[0])
		var n: int = b[3].size()
		var k := mini(l + 1, n)
		out.append({"id": "%s_%d" % [b[0], k], "name": "%s  %d/%d" % [b[1], l, n] + ("  (максимум)" if l >= n else ""),
			"desc": "За уровень: " + String(b[2]), "cost": int(b[3][k - 1]), "nodisc": true})
	return out


## Текущий уровень ветки (сколько подряд куплено "<id>_1", "<id>_2"…).
static func level(id: String) -> int:
	if skills == null or not is_instance_valid(skills):
		return 0
	var l := 0
	while skills.has("%s_%d" % [id, l + 1]):
		l += 1
	return l


## Множитель удачи (монеты и шансы редкого лута).
static func luck() -> float:
	return 1.0 + 0.15 * level("luck")


## Множитель запаса/восстановления стамины.
static func stamina_k() -> float:
	return 1.0 + 0.12 * level("stamina")


## Цена со скидкой (не меньше 1, если была платной).
static func cost(p: int) -> int:
	if p <= 0:
		return p
	return maxi(1, roundi(p * (1.0 - 0.04 * level("discount"))))


## Множитель максимальной скорости машины.
static func car_speed() -> float:
	return 1.0 + 0.06 * level("car")


## Множитель расхода бензина.
static func car_fuel() -> float:
	return 1.0 - 0.1 * level("car")
