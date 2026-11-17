extends RefCounted
const Weapons := preload("res://scripts/weapons.gd")
## Справочник предметов (тестовые механики): название, описание, размер стака, иконка и 3D-модель.
## Иконки и модели рисуются кодом, файлов нет.

const ITEMS := {
	"coin": {"name": "Монета", "desc": "Старая монета. Её ест игровой автомат.", "stack": 999,
		"icon": "coin", "color": Color(0.86, 0.66, 0.3)},
	"medkit": {"name": "Аптечка", "desc": "Восстанавливает 50 здоровья.", "stack": 5,
		"icon": "medkit", "color": Color(0.72, 0.16, 0.12), "heal": 50.0},
	"bandage": {"name": "Бинт", "desc": "Восстанавливает 20 здоровья.", "stack": 10,
		"icon": "bandage", "color": Color(0.84, 0.8, 0.7), "heal": 20.0},
	# еда — сопротивление урону, напитки — скорость (game.gd: buffs). Лечат только аптечка, бинт, таблетки.
	"rusk": {"name": "Сухарь", "desc": "Еда: −10% входящего урона на 30 с.", "stack": 10,
		"icon": "rusk", "color": Color(0.6, 0.42, 0.22), "buff": "resist", "power": 0.10, "time": 30.0},
	"choco": {"name": "Шоколадка", "desc": "Еда: −20% входящего урона на 60 с.", "stack": 6,
		"icon": "choco", "color": Color(0.36, 0.2, 0.12), "buff": "resist", "power": 0.20, "time": 60.0},
	"soda": {"name": "Газировка", "desc": "Напиток: +30% к скорости на 60 с.", "stack": 6,
		"icon": "soda", "color": Color(0.75, 0.2, 0.15), "buff": "speed", "power": 0.30, "time": 60.0},
	"broom": {"name": "Метла с совком", "desc": "Использовать у битого стекла — вымести его.", "stack": 1,
		"icon": "broom", "color": Color(0.6, 0.48, 0.25)},
	"flashlight": {"name": "Фонарик", "desc": "F или клавиша хотбара — включить. Нужны батарейки.", "stack": 1,
		"icon": "flashlight", "color": Color(0.3, 0.32, 0.3)},
	"battery": {"name": "Батарейка", "desc": "Полностью заряжает фонарик (F).", "stack": 10,
		"icon": "battery", "color": Color(0.34, 0.44, 0.3)},
	"knuckles": {"name": "Кастет", "desc": "Руки: удар кулаком ×1.5.", "stack": 1,
		"icon": "knuckles", "color": Color(0.58, 0.58, 0.6), "equip": "hands", "fist": 1.5},
	# одежда (магазин снаряжения): слот и небольшой эффект
	# каска, ватник, штаны изнашиваются от ударов по игроку (game.gd: damage_player), сапоги — от ударов и стекла (не от ходьбы)
	"helmet": {"name": "Каска", "desc": "Голова: −10% урона. Изнашивается от ударов.", "stack": 1,
		"icon": "helmet", "color": Color(0.78, 0.6, 0.15), "equip": "head", "armor": 0.10, "dur": 60},
	"jacket": {"name": "Ватник", "desc": "Тело: −15% урона. Изнашивается от ударов.", "stack": 1,
		"icon": "jacket", "color": Color(0.24, 0.27, 0.21), "equip": "body", "armor": 0.15, "dur": 80},
	"gloves": {"name": "Рабочие перчатки", "desc": "Руки: удар кулаком ×1.2.", "stack": 1,
		"icon": "gloves", "color": Color(0.55, 0.48, 0.32), "equip": "hands", "fist": 1.2},
	"pants": {"name": "Рабочие штаны", "desc": "Ноги: −10% урона. Изнашиваются от ударов.", "stack": 1,
		"icon": "pants", "color": Color(0.2, 0.24, 0.32), "equip": "legs", "armor": 0.10, "dur": 80},
	"boots": {"name": "Кирзовые сапоги", "desc": "Обувь: +15% к скорости, стекло не ранит. Изнашиваются от ходьбы и стекла.", "stack": 1,
		"icon": "boots", "color": Color(0.17, 0.13, 0.1), "equip": "feet", "glassproof": true, "dur": 100, "speed": 0.15},
	# одежда на выбор (промпт 14.11 21:14): дешёвая/слабая и дорогая/крепкая в каждом слоте
	"ushanka": {"name": "Шапка-ушанка", "desc": "Голова: −4% урона. Дёшево и тепло. Изнашивается от ударов.", "stack": 1,
		"icon": "ushanka", "color": Color(0.4, 0.3, 0.2), "equip": "head", "armor": 0.04, "dur": 40},
	"moto_helmet": {"name": "Мотошлем", "desc": "Голова: −16% урона. Закрытый, с визором. Изнашивается от ударов.", "stack": 1,
		"icon": "moto_helmet", "color": Color(0.62, 0.12, 0.1), "equip": "head", "armor": 0.16, "dur": 90},
	"kurtka": {"name": "Куртка", "desc": "Тело: −8% урона. Лёгкая, на молнии. Изнашивается от ударов.", "stack": 1,
		"icon": "kurtka", "color": Color(0.22, 0.2, 0.18), "equip": "body", "armor": 0.08, "dur": 60},
	"vest": {"name": "Бронежилет-самоделка", "desc": "Тело: −24% урона, но −5% к скорости. Стальные пластины на ремнях. Изнашивается от ударов.", "stack": 1,
		"icon": "vest", "color": Color(0.3, 0.32, 0.26), "equip": "body", "armor": 0.24, "dur": 120, "speed": -0.05},
	"jeans": {"name": "Джинсы", "desc": "Ноги: −6% урона. Изнашиваются от ударов.", "stack": 1,
		"icon": "jeans", "color": Color(0.22, 0.32, 0.55), "equip": "legs", "armor": 0.06, "dur": 60},
	"wpants": {"name": "Ватные штаны", "desc": "Ноги: −14% урона. Толстые, стёганые. Изнашиваются от ударов.", "stack": 1,
		"icon": "wpants", "color": Color(0.26, 0.28, 0.22), "equip": "legs", "armor": 0.14, "dur": 100},
	"sneakers": {"name": "Кеды", "desc": "Обувь: +25% к скорости, но стекло ранит. Изнашиваются от ударов.", "stack": 1,
		"icon": "sneakers", "color": Color(0.2, 0.3, 0.5), "equip": "feet", "dur": 50, "speed": 0.25},
	"tac_gloves": {"name": "Тактические перчатки", "desc": "Руки: удар кулаком ×1.4 — кастетные накладки на костяшках.", "stack": 1,
		"icon": "tac_gloves", "color": Color(0.14, 0.14, 0.13), "equip": "hands", "fist": 1.4},
	# ремкомплекты: dur — заряды (3), один заряд чинит 50% прочности вещи (game.gd: repair)
	"repair_weapon": {"name": "Ремкомплект оружия", "desc": "3 заряда, каждый чинит оружие на 50%. Нажать — самое побитое оружие; или перетащить на нужное.", "stack": 1,
		"icon": "repair_weapon", "color": Color(0.6, 0.2, 0.15), "repair": "weapon", "dur": 3},
	"repair_gear": {"name": "Ремкомплект одежды", "desc": "3 заряда, каждый чинит одежду (голова, тело, ноги, обувь) на 50%. Нажать — самую потрёпанную; или перетащить на нужную.", "stack": 1,
		"icon": "repair_gear", "color": Color(0.3, 0.42, 0.5), "repair": "gear", "dur": 3},
	"backpack": {"name": "Рюкзак", "desc": "Спина: отсек 3×5 для вещей. Снимешь — вещи из него переложатся в карманы.", "stack": 1,
		"icon": "backpack", "color": Color(0.38, 0.34, 0.2), "equip": "back", "bag": [3, 5]},
	# стартовая одежда (промпт 16.11 06:03): общей сумки нет — вещи только в одежде и на спине
	"sack": {"name": "Вещмешок", "desc": "Спина: простой мешок с лямками, отсек 3×3.", "stack": 1,
		"icon": "sack", "color": Color(0.42, 0.4, 0.28), "equip": "back", "bag": [3, 3]},
	"tshirt": {"name": "Футболка", "desc": "Тело: простая футболка, без защиты. Нагрудный карман на 2 клетки.", "stack": 1,
		"icon": "tshirt", "color": Color(0.55, 0.55, 0.5), "equip": "body"},
	"canned": {"name": "Тушёнка", "desc": "Еда: −30% входящего урона на 90 с.", "stack": 5,
		"icon": "canned", "color": Color(0.55, 0.56, 0.58), "buff": "resist", "power": 0.30, "time": 90.0},
	"water": {"name": "Бутылка воды", "desc": "Напиток: +15% к скорости на 30 с.", "stack": 6,
		"icon": "water", "color": Color(0.45, 0.6, 0.7), "buff": "speed", "power": 0.15, "time": 30.0},
	# гнилое яблоко (промпт 14.11 19:23): скормить KILLBOX — при следующих «666» он не заберёт монеты
	"rot_apple": {"name": "Гнилое яблоко", "desc": "Защищает от шестёрок. Его надо скормить KILLBOX.", "stack": 5,
		"icon": "rot_apple", "color": Color(0.55, 0.16, 0.1)},
	"pills": {"name": "Обезболивающее", "desc": "Блистер таблеток. +15 здоровья.", "stack": 8,
		"icon": "pills", "color": Color(0.85, 0.85, 0.82), "heal": 15.0},
	"wallet": {"name": "Старый кошелёк", "desc": "Открыть: внутри 10–40 монет.", "stack": 5,
		"icon": "wallet", "color": Color(0.32, 0.2, 0.12)},
	"scrap": {"name": "Металлолом", "desc": "Гнутые железки. Хлам — магазин купит за 3 монеты.", "stack": 20, "price": 3, "junk": true,
		"icon": "scrap", "color": Color(0.4, 0.33, 0.28)},
	"gear": {"name": "Шестерёнка", "desc": "Из какого-то механизма. Хлам — магазин купит за 3 монеты.", "stack": 20, "price": 3, "junk": true,
		"icon": "gear", "color": Color(0.55, 0.5, 0.4)},
	"tape": {"name": "Изолента", "desc": "Синяя. Нужна для ножика. Магазин купит за 2 монеты.", "stack": 10, "price": 2,
		"icon": "tape", "color": Color(0.2, 0.3, 0.6)},
	"photo": {"name": "Старое фото", "desc": "Люди в касках у входа в бункер. Лица выцвели. Магазин купит за 5 монет.", "stack": 5, "price": 5, "junk": true,
		"icon": "photo", "color": Color(0.75, 0.68, 0.55)},
	"nut": {"name": "Гайка", "desc": "Бесполезный хлам. Магазин купит за 2 монеты.", "stack": 20, "price": 2, "junk": true,
		"icon": "nut", "color": Color(0.46, 0.46, 0.46)},
	# оружие ближнего боя из магазина (weapons.gd): «использовать» — взять в правую руку
	"bat": {"name": "Бита", "desc": "Деревянная бита. Урон ×2.0, бьёт чуть дальше.", "stack": 1,
		"icon": "bat", "color": Color(0.55, 0.38, 0.22), "weapon": true, "dur": 40},
	"pipe": {"name": "Труба", "desc": "Стальная труба. Урон ×2.5.", "stack": 1,
		"icon": "pipe", "color": Color(0.42, 0.43, 0.44), "weapon": true, "dur": 60},
	"crowbar": {"name": "Монтировка", "desc": "Тяжёлая, красная. Урон ×3.0.", "stack": 1,
		"icon": "crowbar", "color": Color(0.6, 0.14, 0.1), "weapon": true, "dur": 80},
	"machete": {"name": "Мачете", "desc": "Широкий клинок. Урон ×3.6.", "stack": 1,
		"icon": "machete", "color": Color(0.62, 0.63, 0.62), "weapon": true, "dur": 70},
	"shield": {"name": "Щит", "desc": "В левой руке — 50% блокирует удар. В правой — бьёт краем (чуть слабее биты).", "stack": 1,
		"icon": "shield", "color": Color(0.38, 0.39, 0.4), "weapon": true, "dur": 40},
	"knife": {"name": "Ножик", "desc": "Самодельный: деревяшка, осколок стекла, изолента. Урон ×2.2.", "stack": 1,
		"icon": "knife", "color": Color(0.55, 0.7, 0.68), "weapon": true, "dur": 15},
	# пистолет из сейфа (промпт 14.11 19:49, gun.gd): dur — патроны в нём / в магазине (rounds)
	"pistol": {"name": "Пистолет", "desc": "Старый обшарпанный пистолет. ПКМ держать — от бедра, ПКМ клик — прицел, с ПКМ ЛКМ — выстрел, без — удар рукоятью. Два пистолета стреляют по очереди. R — сменить магазин, Enter (держать) — вынуть магазин. Магазин можно перетащить на пистолет.", "stack": 1,
		"icon": "pistol", "color": Color(0.24, 0.24, 0.23), "weapon": true, "gun": true, "rounds": true, "dur": 9},   # dur: 0 — без магазина, 1+n — n патронов (gun.gd)
	"mag": {"name": "Магазин", "desc": "Пистолетный магазин на 8 патронов. Перетащи на пистолет или R с пистолетом в руке — вставить. Перетащи на него патроны — зарядить.", "stack": 1,
		"icon": "mag", "color": Color(0.2, 0.2, 0.2), "rounds": true, "dur": 8},
	"ammo": {"name": "Патроны", "desc": "Пистолетные патроны. Перетащи на магазин — зарядить его.", "stack": 40,
		"icon": "ammo", "color": Color(0.78, 0.6, 0.25)},
	# материалы для крафта
	# камень — с каменных кучек (stone_pile.gd, E), бечёвка — из кувшинов и врагов (промпт 14.11 19:22)
	"stone": {"name": "Камень", "desc": "Увесистый булыжник. Нужен для молотка. Возьми в руку: ПКМ держать — прицел с траекторией, ЛКМ — бросить (отвлечь врагов); без ПКМ — бить камнем.", "stack": 10,
		"icon": "stone", "color": Color(0.46, 0.45, 0.42), "weapon": true},   # в руке — stone_throw.gd
	"twine": {"name": "Бечёвка", "desc": "Моток грубой верёвки. Для крафта: молоток, кастет.", "stack": 10,
		"icon": "twine", "color": Color(0.7, 0.6, 0.4)},
	# молоток: оружие на 6 ударов и инструмент — без него не скрафтить заточку, кастет и дубину
	"hammer": {"name": "Молоток", "desc": "Камень на палке. Урон ×2.2, но всего 6 ударов. Инструмент: заточка, кастет, дубина (крафт тратит прочность).", "stack": 1,
		"icon": "hammer", "color": Color(0.46, 0.45, 0.42), "weapon": true, "dur": 6},
	# инструменты из магазина (промпт 16.11 02:42, вкладка «Инструменты»)
	"steel_hammer": {"name": "Слесарный молоток", "desc": "Стальной боёк на крепкой ручке. Урон ×2.6, 40 ударов. Инструмент: заменяет каменный молоток в крафте.", "stack": 1,
		"icon": "steel_hammer", "color": Color(0.55, 0.56, 0.58), "weapon": true, "dur": 40, "tool_of": "hammer"},
	"hatchet": {"name": "Топорик", "desc": "Небольшой топор. Урон ×2.9. На поляне — руби сухие деревья и старые доски (ЛКМ с топориком в руке): деревяшки.", "stack": 1,
		"icon": "hatchet", "color": Color(0.6, 0.62, 0.63), "weapon": true, "dur": 50},
	"shiv": {"name": "Заточка", "desc": "Металлолом, отбитый молотком в острое жало. Урон ×2.7, быстрая.", "stack": 1,
		"icon": "shiv", "color": Color(0.5, 0.48, 0.46), "weapon": true, "dur": 25},
	"spiked_club": {"name": "Дубина с гвоздями", "desc": "Доски, сбитые гайками и болтами. Урон ×3.2, бьёт широко.", "stack": 1,
		"icon": "spiked_club", "color": Color(0.45, 0.32, 0.2), "weapon": true, "dur": 35},
	"wood": {"name": "Деревяшка", "desc": "Обломок доски. Нужна для крафта.", "stack": 5,
		"icon": "wood", "color": Color(0.5, 0.35, 0.2)},
	"glass": {"name": "Кусочек стекла", "desc": "Острый осколок. Нужен для крафта.", "stack": 5,
		"icon": "glass", "color": Color(0.6, 0.78, 0.76)},
	# противогаз (G — надеть/снять) и фильтры к нему
	"gasmask": {"name": "Нюхич", "desc": "Самодельный противогаз «Нюхич»: резина, два окуляра, шланг к фильтру. Лицо (вместе с каской). G — надеть/снять. Наверху без него не выжить.", "stack": 1,
		"icon": "gasmask", "color": Color(0.22, 0.25, 0.2), "equip": "face"},
	"filter": {"name": "Фильтр", "desc": "Сменный фильтр для Нюхича: 100 секунд наверху.", "stack": 10,
		"icon": "filter", "color": Color(0.36, 0.38, 0.3)},
	# ключ от ржавой машины на поляне (car.gd) — лежит в сейфе; завести машину и уехать = победа
	"car_key": {"name": "Ключ от машины", "desc": "От старой легковушки на поляне. Подойди к ней — [E] завести и уехать.", "stack": 1,
		"icon": "car_key", "color": Color(0.7, 0.55, 0.25), "quest": true},
	# бензин для машины — в деревне (village.gd); E у машины — залить, полный бак
	"fuel": {"name": "Канистра бензина", "desc": "Помятая канистра с бензином. Подойди к машине — [E] залить, полный бак.", "stack": 2,
		"icon": "fuel", "color": Color(0.62, 0.12, 0.08)},
}


## Рецепты крафта: что получится и что нужно.
## tool — инструмент (не тратится, а теряет прочность wear), промпт 14.11 19:22.
const RECIPES := [
	{"out": "knife", "need": {"wood": 1, "glass": 1, "tape": 1}},
	{"out": "hammer", "need": {"stone": 1, "wood": 1, "twine": 1}},
	{"out": "shiv", "need": {"scrap": 2}, "tool": "hammer", "wear": 1},
	{"out": "knuckles", "need": {"gear": 1, "twine": 1}, "tool": "hammer", "wear": 1},
	{"out": "spiked_club", "need": {"wood": 2, "nut": 3}, "tool": "hammer", "wear": 2},
]


## Размер предмета в ячейках сумки [ширина, высота] (промпт 16.11 02:42); нет в списке — 1×1.
## Пробел при перетаскивании поворачивает (inventory.gd).
const SIZES := {
	"pistol": [2, 2], "medkit": [2, 2], "shield": [2, 2], "fuel": [2, 2], "backpack": [2, 2], "sack": [2, 2], "tshirt": [2, 1],
	"bat": [1, 3], "pipe": [1, 3], "crowbar": [1, 3], "machete": [1, 3], "spiked_club": [1, 3], "broom": [1, 3],
	"knife": [1, 2], "shiv": [1, 2], "hammer": [1, 2], "steel_hammer": [1, 2], "hatchet": [1, 2],
	"flashlight": [1, 2], "water": [1, 2], "soda": [1, 2], "wood": [1, 2], "gasmask": [2, 2],
	"repair_weapon": [2, 1], "repair_gear": [2, 1], "canned": [1, 1],
	"helmet": [2, 2], "moto_helmet": [2, 2], "ushanka": [2, 1],
	"jacket": [2, 2], "kurtka": [2, 2], "vest": [2, 2],
	"pants": [2, 2], "jeans": [2, 2], "wpants": [2, 2],
	"boots": [2, 2], "sneakers": [2, 1],
}

## Отдельные ячейки хранения у одежды (промпт 16.11 02:42): [ширина, высота] блока карманов.
## Рюкзак — "bag" в ITEMS (свой блок).
const POCKETS := {
	"kurtka": [2, 1], "jacket": [2, 2], "vest": [3, 1],
	"jeans": [2, 1], "pants": [2, 1], "wpants": [1, 2], "tshirt": [2, 1],
}


## Чем можно заменить инструмент рецепта: сам он и вещи с "tool_of" (слесарный молоток вместо каменного).
static func tool_ids(tid: String) -> Array:
	var out: Array = []
	for id in ITEMS:
		if String(ITEMS[id].get("tool_of", "")) == tid:
			out.append(id)
	out.append(tid)
	return out


static func size_of(id: String) -> Vector2i:
	var a = SIZES.get(id, [1, 1])
	return Vector2i(int(a[0]), int(a[1]))


## Блок ячеек, который даёт надетая вещь (рюкзак, карманы); (0,0) — никакого.
static func block_of(id: String) -> Vector2i:
	if id == "" or not ITEMS.has(id):
		return Vector2i.ZERO
	var a = ITEMS[id].get("bag", POCKETS.get(id, null))
	if a is Array:
		return Vector2i(int(a[0]), int(a[1]))
	if a != null:   # старый формат рюкзака: число ячеек
		return Vector2i(4, 3)
	return Vector2i.ZERO


## Куда надевается предмет: hand (левая или правая рука), head (голова), face (противогаз), back (рюкзак), hands (кастет) или "".
static func equip_slot(id: String) -> String:
	if not ITEMS.has(id):
		return ""
	if ITEMS[id].has("weapon"):
		return "hand"
	return String(ITEMS[id].get("equip", ""))


## Подходит ли предмет в слот экипировки (left/right/head/hands).
static func fits(id: String, slot: String) -> bool:
	var k := equip_slot(id)
	if slot == "left" or slot == "right":
		return k == "hand" or holdable(id)
	return k != "" and k == slot


## Любой предмет можно взять в руку, как оружие (промпт 18.11 00:27): бьёт им как дубинкой-слабачкой.
static func holdable(id: String) -> bool:
	return ITEMS.has(id) and id != "coin"


## Каким ремкомплектом чинится: "weapon", "gear" (одежда с прочностью) или "".
static func repairable(id: String) -> String:
	if not ITEMS.has(id) or max_dur(id) <= 0.0 or ITEMS[id].has("repair") or ITEMS[id].has("rounds"):
		return ""
	if ITEMS[id].has("weapon"):
		return "weapon"
	return "gear" if ITEMS[id].has("equip") else ""


## Прочность предмета (0 — вечный): оружие ломается от ударов, сапоги — от ударов и стекла (не от ходьбы).
static func max_dur(id: String) -> float:
	return float(ITEMS[id].get("dur", 0)) if ITEMS.has(id) else 0.0


static func item_name(id: String) -> String:
	return ITEMS[id]["name"] if ITEMS.has(id) else id


## Иконка предмета в прямоугольнике r (рисуется на любом CanvasItem в его _draw / сигнале draw).
static func draw_icon(ci: CanvasItem, id: String, r: Rect2) -> void:
	if not ITEMS.has(id):
		return
	var c := r.get_center()
	var s := minf(r.size.x, r.size.y)
	var col: Color = ITEMS[id]["color"]
	var dark := col.darkened(0.45)
	if String(ITEMS[id]["icon"]) in ["bat", "pipe", "crowbar", "machete", "knife", "shield", "gasmask", "filter", "hammer", "steel_hammer", "hatchet", "shiv", "spiked_club", "pistol"]:
		Weapons.draw_icon(ci, String(ITEMS[id]["icon"]), r, col)
		return
	match String(ITEMS[id]["icon"]):
		"fuel":
			var body := Rect2(c - Vector2(s * 0.28, s * 0.3), Vector2(s * 0.56, s * 0.66))
			ci.draw_rect(body, dark)
			ci.draw_rect(body.grow(-s * 0.03), col)
			ci.draw_line(c + Vector2(-s * 0.2, -s * 0.2), c + Vector2(s * 0.2, s * 0.3), dark, maxf(1.5, s * 0.04))
			ci.draw_line(c + Vector2(s * 0.2, -s * 0.2), c + Vector2(-s * 0.2, s * 0.3), dark, maxf(1.5, s * 0.04))
			ci.draw_rect(Rect2(c + Vector2(-s * 0.18, -s * 0.42), Vector2(s * 0.24, s * 0.1)), dark)
			ci.draw_rect(Rect2(c + Vector2(s * 0.12, -s * 0.4), Vector2(s * 0.1, s * 0.12)), Color(0.3, 0.3, 0.28))
		"rot_apple":
			preload("res://scripts/slot/slot_symbols.gd").draw(ci, "rot_apple", r)
		"coin":
			ci.draw_circle(c, s * 0.34, dark)
			ci.draw_circle(c, s * 0.29, col)
			ci.draw_arc(c, s * 0.19, 0.0, TAU, 24, col.darkened(0.25), maxf(1.5, s * 0.04), true)
			ci.draw_line(c + Vector2(0, -s * 0.1), c + Vector2(0, s * 0.1), col.darkened(0.3), maxf(1.5, s * 0.05))
		"medkit":
			var box := Rect2(c - Vector2(s * 0.38, s * 0.28), Vector2(s * 0.76, s * 0.56))
			ci.draw_rect(box, Color(0.8, 0.77, 0.7))
			ci.draw_rect(Rect2(c - Vector2(s * 0.12, s * 0.38), Vector2(s * 0.24, s * 0.12)), Color(0.35, 0.33, 0.3))
			ci.draw_rect(Rect2(c - Vector2(s * 0.06, s * 0.19), Vector2(s * 0.12, s * 0.38)), col)
			ci.draw_rect(Rect2(c - Vector2(s * 0.19, s * 0.06), Vector2(s * 0.38, s * 0.12)), col)
		"bandage":
			# скатка марли сбоку: узкий плотный рулон, бумажная лента с красным крестом, хвостик вниз (промпт 18:36)
			var gz := col.darkened(0.08)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(s * 0.12, s * 0.06), c + Vector2(s * 0.24, s * 0.06),
				c + Vector2(s * 0.4, s * 0.36), c + Vector2(s * 0.28, s * 0.38)]), gz.darkened(0.1))
			ci.draw_rect(Rect2(c - Vector2(s * 0.26, s * 0.13), Vector2(s * 0.46, s * 0.26)), gz)
			ci.draw_circle(c + Vector2(-s * 0.26, 0), s * 0.13, gz.darkened(0.12))
			ci.draw_circle(c + Vector2(s * 0.2, 0), s * 0.13, gz.lightened(0.05))
			ci.draw_arc(c + Vector2(s * 0.2, 0), s * 0.07, 0.0, TAU * 0.8, 16, gz.darkened(0.25), maxf(1.0, s * 0.02), true)
			for k in 4:
				var x := -s * 0.2 + k * s * 0.11
				ci.draw_line(c + Vector2(x, -s * 0.12), c + Vector2(x, s * 0.12), gz.darkened(0.15), maxf(1.0, s * 0.012))
			ci.draw_rect(Rect2(c - Vector2(s * 0.09, s * 0.14), Vector2(s * 0.15, s * 0.28)), Color(0.74, 0.65, 0.48))
			ci.draw_rect(Rect2(c + Vector2(-s * 0.04, -s * 0.07), Vector2(s * 0.05, s * 0.14)), Color(0.75, 0.14, 0.1))
			ci.draw_rect(Rect2(c + Vector2(-s * 0.085, -s * 0.025), Vector2(s * 0.14, s * 0.05)), Color(0.75, 0.14, 0.1))
		"choco":
			# как моделька: тёмно-красная обёртка с жёлтой полосой, фольга, надорванный конец с дольками (промпт 19:12)
			var box := Rect2(c - Vector2(s * 0.38, s * 0.2), Vector2(s * 0.44, s * 0.4))
			ci.draw_rect(box, Color(0.5, 0.1, 0.08))
			ci.draw_rect(Rect2(box.position + Vector2(0, s * 0.16), Vector2(box.size.x, s * 0.08)), Color(0.9, 0.8, 0.4))
			ci.draw_rect(Rect2(c + Vector2(s * 0.06, -s * 0.2), Vector2(s * 0.05, s * 0.4)), Color(0.8, 0.8, 0.82))   # фольга
			ci.draw_rect(Rect2(c + Vector2(s * 0.11, -s * 0.18), Vector2(s * 0.27, s * 0.36)), col)
			for i in 2:
				for j in 3:
					ci.draw_rect(Rect2(c + Vector2(s * (0.13 + i * 0.125), s * (-0.16 + j * 0.115)), Vector2(s * 0.1, s * 0.095)), col.lightened(0.12))
		"soda":
			var body := Rect2(c - Vector2(s * 0.17, s * 0.3), Vector2(s * 0.34, s * 0.6))
			ci.draw_rect(body, col)
			ci.draw_rect(Rect2(body.position, Vector2(body.size.x, s * 0.06)), Color(0.7, 0.7, 0.72))
			ci.draw_rect(Rect2(body.position + Vector2(0, s * 0.54), Vector2(body.size.x, s * 0.06)), Color(0.7, 0.7, 0.72))
			ci.draw_line(c + Vector2(-s * 0.1, -s * 0.05), c + Vector2(s * 0.1, s * 0.05), Color(1, 1, 1, 0.8), maxf(1.5, s * 0.05))
		"rusk":
			var box := Rect2(c - Vector2(s * 0.32, s * 0.2), Vector2(s * 0.64, s * 0.4))
			ci.draw_rect(box, col)
			ci.draw_rect(box, dark, false, maxf(1.5, s * 0.04))
			for k in 4:
				ci.draw_circle(c + Vector2((k - 1.5) * s * 0.14, (k % 2 - 0.5) * s * 0.12), s * 0.03, dark)
		"battery":
			var body := Rect2(c - Vector2(s * 0.16, s * 0.3), Vector2(s * 0.32, s * 0.64))
			ci.draw_rect(Rect2(c - Vector2(s * 0.07, s * 0.38), Vector2(s * 0.14, s * 0.1)), Color(0.6, 0.6, 0.58))
			ci.draw_rect(body, col)
			ci.draw_rect(Rect2(body.position, Vector2(body.size.x, s * 0.16)), Color(0.75, 0.5, 0.25))   # медный торец, как у модельки
			ci.draw_line(c + Vector2(-s * 0.08, -s * 0.06), c + Vector2(s * 0.08, -s * 0.06), Color(0.9, 0.85, 0.6), maxf(1.5, s * 0.04))
			ci.draw_line(c + Vector2(0, -s * 0.14), c + Vector2(0, s * 0.02), Color(0.9, 0.85, 0.6), maxf(1.5, s * 0.04))
		"knuckles":
			ci.draw_rect(Rect2(c + Vector2(-s * 0.34, s * 0.04), Vector2(s * 0.68, s * 0.14)), dark)
			for k in 4:
				var p := c + Vector2((k - 1.5) * s * 0.17, -s * 0.06)
				ci.draw_arc(p, s * 0.075, 0.0, TAU, 14, col, maxf(2.0, s * 0.045), true)
		"canned":
			var box := Rect2(c - Vector2(s * 0.24, s * 0.3), Vector2(s * 0.48, s * 0.6))
			ci.draw_rect(box, col)
			ci.draw_rect(Rect2(box.position + Vector2(0, s * 0.14), Vector2(box.size.x, s * 0.3)), Color(0.5, 0.18, 0.12))
			ci.draw_line(box.position, box.position + Vector2(box.size.x, 0), col.lightened(0.3), maxf(1.5, s * 0.04))
		"water":
			ci.draw_rect(Rect2(c - Vector2(s * 0.06, s * 0.38), Vector2(s * 0.12, s * 0.1)), Color(0.2, 0.4, 0.75))
			ci.draw_rect(Rect2(c - Vector2(s * 0.16, s * 0.27), Vector2(s * 0.32, s * 0.62)), col)
			ci.draw_rect(Rect2(c - Vector2(s * 0.16, s * 0.0), Vector2(s * 0.32, s * 0.35)), col.darkened(0.25))
		"pills":
			# баночка, как моделька (pickup_mesh.gd): оранжевая банка, белая крышка, белая этикетка с красным крестом (промпт 19:12)
			var jar := Rect2(c - Vector2(s * 0.2, s * 0.2), Vector2(s * 0.4, s * 0.56))
			ci.draw_rect(jar, Color(0.75, 0.42, 0.12))
			ci.draw_rect(Rect2(jar.position + Vector2(s * 0.04, s * 0.02), Vector2(s * 0.06, jar.size.y - s * 0.04)), Color(0.9, 0.62, 0.3))   # блик
			ci.draw_rect(Rect2(jar.position + Vector2(0, s * 0.18), Vector2(jar.size.x, s * 0.24)), Color(0.92, 0.9, 0.85))
			ci.draw_rect(Rect2(c + Vector2(-s * 0.025, s * 0.2), Vector2(s * 0.05, s * 0.16)), Color(0.8, 0.15, 0.1))
			ci.draw_rect(Rect2(c + Vector2(-s * 0.08, s * 0.255), Vector2(s * 0.16, s * 0.05)), Color(0.8, 0.15, 0.1))
			ci.draw_rect(Rect2(c - Vector2(s * 0.23, s * 0.38), Vector2(s * 0.46, s * 0.18)), Color(0.95, 0.95, 0.93))   # крышка
			for k in 5:
				var x := -s * 0.19 + k * s * 0.095
				ci.draw_line(c + Vector2(x, -s * 0.37), c + Vector2(x, -s * 0.21), Color(0.75, 0.75, 0.72), maxf(1.0, s * 0.015))
		"wallet":
			var box := Rect2(c - Vector2(s * 0.34, s * 0.24), Vector2(s * 0.68, s * 0.48))
			ci.draw_rect(box, col)
			ci.draw_rect(Rect2(c + Vector2(s * 0.1, -s * 0.08), Vector2(s * 0.24, s * 0.16)), col.lightened(0.15))
			ci.draw_circle(c + Vector2(s * 0.2, 0), s * 0.04, Color(0.8, 0.65, 0.3))
		"scrap":
			ci.draw_line(c + Vector2(-s * 0.3, s * 0.2), c + Vector2(s * 0.1, -s * 0.25), col, maxf(3.0, s * 0.1))
			ci.draw_line(c + Vector2(-s * 0.1, -s * 0.2), c + Vector2(s * 0.3, s * 0.2), col.darkened(0.2), maxf(3.0, s * 0.1))
			ci.draw_rect(Rect2(c + Vector2(-s * 0.25, s * 0.05), Vector2(s * 0.2, s * 0.2)), col.lightened(0.1))
		"gear":
			var pts := PackedVector2Array()
			for k in 16:
				var a := TAU * k / 16.0
				var rr := s * (0.34 if k % 2 == 0 else 0.26)
				pts.append(c + Vector2(cos(a), sin(a)) * rr)
			ci.draw_colored_polygon(pts, col)
			ci.draw_circle(c, s * 0.1, Color(0.08, 0.08, 0.08))
		"tape":
			ci.draw_circle(c, s * 0.32, col)
			ci.draw_circle(c, s * 0.16, Color(0.75, 0.7, 0.6))
			ci.draw_circle(c, s * 0.12, Color(0.08, 0.08, 0.08))
		"photo":
			var box := Rect2(c - Vector2(s * 0.3, s * 0.34), Vector2(s * 0.6, s * 0.68))
			ci.draw_rect(box, col)
			ci.draw_rect(box.grow(-s * 0.06), Color(0.3, 0.27, 0.22))
			ci.draw_circle(c + Vector2(-s * 0.1, -s * 0.06), s * 0.07, col.darkened(0.2))
			ci.draw_circle(c + Vector2(s * 0.1, -s * 0.06), s * 0.07, col.darkened(0.2))
		"wood":
			var a := c + Vector2(-s * 0.32, s * 0.18)
			var b := c + Vector2(s * 0.32, -s * 0.18)
			ci.draw_line(a, b, col, maxf(4.0, s * 0.2))
			ci.draw_line(a.lerp(b, 0.2), a.lerp(b, 0.8), col.darkened(0.3), maxf(1.0, s * 0.03))
		"glass":
			var pts := PackedVector2Array([c + Vector2(-s * 0.2, s * 0.3), c + Vector2(-s * 0.05, -s * 0.34),
				c + Vector2(s * 0.24, -s * 0.1), c + Vector2(s * 0.1, s * 0.32)])
			ci.draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.75))
			ci.draw_line(c + Vector2(-s * 0.05, -s * 0.2), c + Vector2(s * 0.05, s * 0.1), Color(1, 1, 1, 0.8), maxf(1.0, s * 0.03))
		"broom":
			ci.draw_line(c + Vector2(-s * 0.3, -s * 0.36), c + Vector2(s * 0.08, s * 0.12), Color(0.5, 0.36, 0.2), maxf(2.0, s * 0.06))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, s * 0.06), c + Vector2(s * 0.16, -s * 0.06),
				c + Vector2(s * 0.36, s * 0.22), c + Vector2(s * 0.16, s * 0.36)]), col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.38, s * 0.2), Vector2(s * 0.3, s * 0.14)), Color(0.3, 0.32, 0.3))
		"flashlight":
			ci.draw_rect(Rect2(c + Vector2(-s * 0.32, -s * 0.08), Vector2(s * 0.42, s * 0.16)), col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(s * 0.1, -s * 0.08), c + Vector2(s * 0.3, -s * 0.16),
				c + Vector2(s * 0.3, s * 0.16), c + Vector2(s * 0.1, s * 0.08)]), col.lightened(0.2))
			ci.draw_rect(Rect2(c + Vector2(s * 0.3, -s * 0.15), Vector2(s * 0.05, s * 0.3)), Color(1.0, 0.92, 0.6))
			ci.draw_rect(Rect2(c + Vector2(-s * 0.12, -s * 0.13), Vector2(s * 0.08, s * 0.05)), Color(0.7, 0.2, 0.15))
		"helmet":
			ci.draw_arc(c + Vector2(0, s * 0.08), s * 0.3, PI, TAU, 16, col, s * 0.02)
			var dome := PackedVector2Array()
			for k in 17:
				var a := PI + PI * k / 16.0
				dome.append(c + Vector2(cos(a) * s * 0.3, s * 0.08 + sin(a) * s * 0.3))
			ci.draw_colored_polygon(dome, col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.4, s * 0.06), Vector2(s * 0.8, s * 0.08)), col.darkened(0.25))
		"tshirt":
			# футболка: короткие рукава, вырез
			var tb := PackedVector2Array([c + Vector2(-s * 0.18, -s * 0.3), c + Vector2(s * 0.18, -s * 0.3), c + Vector2(s * 0.38, -s * 0.16),
				c + Vector2(s * 0.3, -s * 0.02), c + Vector2(s * 0.22, -s * 0.06), c + Vector2(s * 0.22, s * 0.32), c + Vector2(-s * 0.22, s * 0.32),
				c + Vector2(-s * 0.22, -s * 0.06), c + Vector2(-s * 0.3, -s * 0.02), c + Vector2(-s * 0.38, -s * 0.16)])
			ci.draw_colored_polygon(tb, col)
			ci.draw_arc(c + Vector2(0, -s * 0.3), s * 0.08, 0.0, PI, 10, col.darkened(0.4), maxf(1.5, s * 0.03))
		"sack":
			# вещмешок: горловина на шнурке, мешок, лямка
			ci.draw_line(c + Vector2(-s * 0.08, -s * 0.3), c + Vector2(s * 0.08, -s * 0.3), dark, maxf(2.0, s * 0.05))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.08, -s * 0.28), c + Vector2(s * 0.08, -s * 0.28),
				c + Vector2(s * 0.3, s * 0.05), c + Vector2(s * 0.26, s * 0.34), c + Vector2(-s * 0.26, s * 0.34), c + Vector2(-s * 0.3, s * 0.05)]), col)
			ci.draw_line(c + Vector2(-s * 0.06, -s * 0.24), c + Vector2(-s * 0.32, s * 0.3), col.darkened(0.35), maxf(1.5, s * 0.04))
		"jacket":
			var body := PackedVector2Array([c + Vector2(-s * 0.2, -s * 0.32), c + Vector2(s * 0.2, -s * 0.32), c + Vector2(s * 0.4, -s * 0.1),
				c + Vector2(s * 0.3, s * 0.0), c + Vector2(s * 0.22, -s * 0.06), c + Vector2(s * 0.22, s * 0.34), c + Vector2(-s * 0.22, s * 0.34),
				c + Vector2(-s * 0.22, -s * 0.06), c + Vector2(-s * 0.3, s * 0.0), c + Vector2(-s * 0.4, -s * 0.1)])
			ci.draw_colored_polygon(body, col)
			ci.draw_line(c + Vector2(0, -s * 0.3), c + Vector2(0, s * 0.33), col.darkened(0.45), maxf(1.5, s * 0.03))
			for k in 4:
				ci.draw_line(c + Vector2(-s * 0.2, -s * 0.18 + k * s * 0.12), c + Vector2(s * 0.2, -s * 0.18 + k * s * 0.12), col.darkened(0.25), maxf(1.0, s * 0.02))
		"repair_weapon", "repair_gear":
			# чемоданчик с ручкой; на крышке — гаечный ключ (оружие) или катушка с иглой (одежда)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.1, -s * 0.3), Vector2(s * 0.2, s * 0.08)), dark)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.36, -s * 0.22), Vector2(s * 0.72, s * 0.5)), col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.36, -s * 0.22), Vector2(s * 0.72, s * 0.08)), col.darkened(0.25))
			var mark := Color(0.85, 0.83, 0.78)
			if id == "repair_weapon":
				ci.draw_line(c + Vector2(-s * 0.18, s * 0.18), c + Vector2(s * 0.12, -s * 0.06), mark, maxf(2.0, s * 0.07))
				ci.draw_circle(c + Vector2(s * 0.15, -s * 0.09), s * 0.08, mark)
				ci.draw_circle(c + Vector2(s * 0.19, -s * 0.13), s * 0.04, col)
			else:
				ci.draw_rect(Rect2(c + Vector2(-s * 0.12, -s * 0.08), Vector2(s * 0.16, s * 0.26)), mark)
				ci.draw_rect(Rect2(c + Vector2(-s * 0.15, -s * 0.1), Vector2(s * 0.22, s * 0.04)), dark)
				ci.draw_rect(Rect2(c + Vector2(-s * 0.15, s * 0.16), Vector2(s * 0.22, s * 0.04)), dark)
				ci.draw_line(c + Vector2(s * 0.12, -s * 0.1), c + Vector2(s * 0.22, s * 0.2), mark, maxf(1.0, s * 0.025))
		"mag":
			# магазин: чуть наклонный корпус, сверху виден патрон
			var body := PackedVector2Array([c + Vector2(-s * 0.12, -s * 0.3), c + Vector2(s * 0.08, -s * 0.3),
				c + Vector2(s * 0.16, s * 0.32), c + Vector2(-s * 0.04, s * 0.32)])
			ci.draw_colored_polygon(body, col.lightened(0.15))
			ci.draw_rect(Rect2(c + Vector2(-s * 0.06, s * 0.32), Vector2(s * 0.26, s * 0.05)), col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.08, -s * 0.38), Vector2(s * 0.12, s * 0.08)), Color(0.8, 0.62, 0.25))
		"ammo":
			for k in 3:
				var x := c.x + (k - 1) * s * 0.2
				ci.draw_rect(Rect2(Vector2(x - s * 0.06, c.y - s * 0.05), Vector2(s * 0.12, s * 0.3)), col)
				ci.draw_circle(Vector2(x, c.y - s * 0.07), s * 0.06, Color(0.65, 0.42, 0.25))
				ci.draw_rect(Rect2(Vector2(x - s * 0.065, c.y + s * 0.22), Vector2(s * 0.13, s * 0.04)), col.darkened(0.3))
		"stone":
			var pts := PackedVector2Array()
			for k in 9:
				var ang := TAU * k / 9.0
				var rr := s * (0.3 + 0.05 * sin(k * 2.3))
				pts.append(c + Vector2(cos(ang) * rr * 1.15, sin(ang) * rr * 0.85 + s * 0.04))
			ci.draw_colored_polygon(pts, col)
			ci.draw_circle(c + Vector2(-s * 0.08, -s * 0.06), s * 0.09, col.lightened(0.15))
			ci.draw_line(c + Vector2(s * 0.05, s * 0.02), c + Vector2(s * 0.2, s * 0.12), dark, maxf(1.0, s * 0.03))
		"twine":
			ci.draw_circle(c, s * 0.3, col.darkened(0.15))
			ci.draw_circle(c, s * 0.1, Color(0.12, 0.1, 0.08))
			for k in 6:
				var yy := -s * 0.25 + k * s * 0.1
				ci.draw_line(c + Vector2(-s * 0.26, yy), c + Vector2(s * 0.26, yy + s * 0.05), col.lightened(0.1), maxf(1.0, s * 0.025))
			ci.draw_line(c + Vector2(s * 0.25, s * 0.15), c + Vector2(s * 0.42, s * 0.38), col, maxf(1.5, s * 0.035))
		"backpack":
			# лямки, корпус, клапан с пряжкой, боковой карман
			var strap := col.darkened(0.35)
			ci.draw_arc(c + Vector2(0, -s * 0.24), s * 0.12, PI, TAU, 12, strap, maxf(2.0, s * 0.05))
			ci.draw_rect(Rect2(c + Vector2(-s * 0.27, -s * 0.24), Vector2(s * 0.54, s * 0.6)), col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.27, -s * 0.24), Vector2(s * 0.54, s * 0.22)), col.darkened(0.2))
			ci.draw_rect(Rect2(c + Vector2(-s * 0.05, -s * 0.05), Vector2(s * 0.1, s * 0.08)), Color(0.7, 0.62, 0.4))
			ci.draw_rect(Rect2(c + Vector2(-s * 0.18, s * 0.12), Vector2(s * 0.36, s * 0.18)), col.darkened(0.12))
			ci.draw_line(c + Vector2(-s * 0.18, s * 0.12), c + Vector2(s * 0.18, s * 0.12), dark, maxf(1.0, s * 0.02))
		"gloves":
			ci.draw_rect(Rect2(c + Vector2(-s * 0.18, -s * 0.05), Vector2(s * 0.36, s * 0.36)), col)
			for k in 4:
				ci.draw_rect(Rect2(c + Vector2(-s * 0.18 + k * s * 0.09, -s * 0.32), Vector2(s * 0.075, s * 0.3)), col)
			ci.draw_rect(Rect2(c + Vector2(s * 0.18, -s * 0.02), Vector2(s * 0.14, s * 0.08)), col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.2, s * 0.22), Vector2(s * 0.4, s * 0.08)), col.darkened(0.3))
		"pants":
			var p := PackedVector2Array([c + Vector2(-s * 0.26, -s * 0.34), c + Vector2(s * 0.26, -s * 0.34), c + Vector2(s * 0.3, s * 0.36),
				c + Vector2(s * 0.06, s * 0.36), c + Vector2(0, -s * 0.06), c + Vector2(-s * 0.06, s * 0.36), c + Vector2(-s * 0.3, s * 0.36)])
			ci.draw_colored_polygon(p, col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.26, -s * 0.34), Vector2(s * 0.52, s * 0.06)), col.darkened(0.35))
		"boots":
			var p := PackedVector2Array([c + Vector2(-s * 0.2, -s * 0.34), c + Vector2(s * 0.06, -s * 0.34), c + Vector2(s * 0.06, s * 0.06),
				c + Vector2(s * 0.36, s * 0.14), c + Vector2(s * 0.36, s * 0.32), c + Vector2(-s * 0.2, s * 0.32)])
			ci.draw_colored_polygon(p, col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.22, s * 0.26), Vector2(s * 0.6, s * 0.08)), Color(0.05, 0.04, 0.03))
		"ushanka":
			# меховой купол, отворот спереди, уши по бокам, красная звёздочка
			var fur := col.lightened(0.15)
			for sx in [-1.0, 1.0]:
				ci.draw_rect(Rect2(c + Vector2(sx * s * 0.36 - s * 0.08, -s * 0.02), Vector2(s * 0.16, s * 0.34)), fur)
			var dome := PackedVector2Array()
			for k in 17:
				var a := PI + PI * k / 16.0
				dome.append(c + Vector2(cos(a) * s * 0.32, s * 0.04 + sin(a) * s * 0.3))
			ci.draw_colored_polygon(dome, col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.36, -s * 0.06), Vector2(s * 0.72, s * 0.16)), fur)
			for k in 6:
				ci.draw_line(c + Vector2(-s * 0.32 + k * s * 0.13, -s * 0.05), c + Vector2(-s * 0.3 + k * s * 0.13, s * 0.09), fur.darkened(0.2), maxf(1.0, s * 0.02))
			ci.draw_circle(c + Vector2(0, s * 0.02), s * 0.04, Color(0.8, 0.15, 0.1))
		"moto_helmet":
			# закрытый шлем сбоку: круглый корпус, тёмный визор, вырез снизу
			ci.draw_circle(c + Vector2(0, -s * 0.02), s * 0.34, col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.04, -s * 0.12), c + Vector2(s * 0.34, -s * 0.12),
				c + Vector2(s * 0.32, s * 0.1), c + Vector2(s * 0.02, s * 0.08)]), Color(0.1, 0.12, 0.16))
			ci.draw_line(c + Vector2(s * 0.04, -s * 0.08), c + Vector2(s * 0.26, -s * 0.08), Color(0.5, 0.6, 0.7, 0.8), maxf(1.0, s * 0.03))
			ci.draw_rect(Rect2(c + Vector2(-s * 0.3, s * 0.22), Vector2(s * 0.56, s * 0.08)), col.darkened(0.45))
			ci.draw_arc(c + Vector2(0, -s * 0.02), s * 0.25, PI * 1.1, PI * 1.45, 8, col.lightened(0.3), maxf(1.0, s * 0.03))
		"kurtka", "vest":
			var body := PackedVector2Array([c + Vector2(-s * 0.2, -s * 0.32), c + Vector2(s * 0.2, -s * 0.32), c + Vector2(s * 0.4, -s * 0.1),
				c + Vector2(s * 0.3, s * 0.0), c + Vector2(s * 0.22, -s * 0.06), c + Vector2(s * 0.22, s * 0.34), c + Vector2(-s * 0.22, s * 0.34),
				c + Vector2(-s * 0.22, -s * 0.06), c + Vector2(-s * 0.3, s * 0.0), c + Vector2(-s * 0.4, -s * 0.1)])
			if id == "vest":
				# без рукавов: корпус, стальные пластины, ремни
				body = PackedVector2Array([c + Vector2(-s * 0.14, -s * 0.34), c + Vector2(s * 0.14, -s * 0.34), c + Vector2(s * 0.26, -s * 0.2),
					c + Vector2(s * 0.26, s * 0.34), c + Vector2(-s * 0.26, s * 0.34), c + Vector2(-s * 0.26, -s * 0.2)])
			ci.draw_colored_polygon(body, col)
			if id == "vest":
				var plate := Color(0.55, 0.56, 0.55)
				ci.draw_rect(Rect2(c + Vector2(-s * 0.2, -s * 0.16), Vector2(s * 0.4, s * 0.22)), plate)
				ci.draw_rect(Rect2(c + Vector2(-s * 0.2, s * 0.09), Vector2(s * 0.4, s * 0.18)), plate.darkened(0.12))
				for k in 4:
					ci.draw_circle(c + Vector2(-s * 0.16 + (k % 2) * s * 0.32, -s * 0.12 + (1.0 if k >= 2 else 0.0) * s * 0.36), s * 0.02, Color(0.25, 0.24, 0.22))
				ci.draw_line(c + Vector2(-s * 0.26, s * 0.0), c + Vector2(s * 0.26, s * 0.0), Color(0.15, 0.12, 0.08), maxf(2.0, s * 0.05))
			else:
				ci.draw_line(c + Vector2(0, -s * 0.28), c + Vector2(0, s * 0.33), Color(0.75, 0.72, 0.65), maxf(1.5, s * 0.03))   # молния
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.2, -s * 0.32), c + Vector2(0, -s * 0.2),
					c + Vector2(s * 0.2, -s * 0.32), c + Vector2(s * 0.12, -s * 0.38), c + Vector2(-s * 0.12, -s * 0.38)]), col.darkened(0.3))   # воротник
				for sx in [-1.0, 1.0]:
					ci.draw_line(c + Vector2(sx * s * 0.08, s * 0.14), c + Vector2(sx * s * 0.18, s * 0.14), col.lightened(0.25), maxf(1.0, s * 0.025))   # карманы
		"jeans", "wpants":
			var p := PackedVector2Array([c + Vector2(-s * 0.26, -s * 0.34), c + Vector2(s * 0.26, -s * 0.34), c + Vector2(s * 0.3, s * 0.36),
				c + Vector2(s * 0.06, s * 0.36), c + Vector2(0, -s * 0.06), c + Vector2(-s * 0.06, s * 0.36), c + Vector2(-s * 0.3, s * 0.36)])
			ci.draw_colored_polygon(p, col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.26, -s * 0.34), Vector2(s * 0.52, s * 0.06)), col.darkened(0.35))
			if id == "jeans":
				var st := Color(0.85, 0.6, 0.25)   # рыжая строчка, заклёпки
				for sx in [-1.0, 1.0]:
					ci.draw_line(c + Vector2(sx * s * 0.22, -s * 0.26), c + Vector2(sx * s * 0.25, s * 0.34), st, maxf(1.0, s * 0.015))
				ci.draw_arc(c + Vector2(-s * 0.18, -s * 0.28), s * 0.08, 0.0, PI / 2, 6, st, maxf(1.0, s * 0.015))
				ci.draw_arc(c + Vector2(s * 0.18, -s * 0.28), s * 0.08, PI / 2, PI, 6, st, maxf(1.0, s * 0.015))
			else:
				for k in 5:
					var yy := -s * 0.2 + k * s * 0.12
					ci.draw_line(c + Vector2(-s * 0.27, yy), c + Vector2(-s * 0.04, yy), col.darkened(0.3), maxf(1.0, s * 0.02))
					ci.draw_line(c + Vector2(s * 0.04, yy), c + Vector2(s * 0.27, yy), col.darkened(0.3), maxf(1.0, s * 0.02))
		"sneakers":
			# низкий кед: тканевый верх, белая подошва и носок, шнурки
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.36, -s * 0.06), c + Vector2(-s * 0.1, -s * 0.12),
				c + Vector2(s * 0.12, s * 0.02), c + Vector2(s * 0.38, s * 0.1), c + Vector2(s * 0.38, s * 0.2), c + Vector2(-s * 0.36, s * 0.2)]), col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.38, s * 0.18), Vector2(s * 0.78, s * 0.1)), Color(0.9, 0.88, 0.84))
			ci.draw_circle(c + Vector2(s * 0.32, s * 0.15), s * 0.07, Color(0.9, 0.88, 0.84))
			for k in 3:
				var x := -s * 0.08 + k * s * 0.08
				ci.draw_line(c + Vector2(x, -s * 0.06 + k * s * 0.04), c + Vector2(x + s * 0.06, -s * 0.02 + k * s * 0.04), Color(0.95, 0.95, 0.95), maxf(1.0, s * 0.025))
		"tac_gloves":
			# как рабочие, но чёрные, с вырезами и стальными накладками на костяшках
			ci.draw_rect(Rect2(c + Vector2(-s * 0.18, -s * 0.05), Vector2(s * 0.36, s * 0.36)), col)
			for k in 4:
				ci.draw_rect(Rect2(c + Vector2(-s * 0.18 + k * s * 0.09, -s * 0.32), Vector2(s * 0.075, s * 0.3)), col)
				ci.draw_rect(Rect2(c + Vector2(-s * 0.18 + k * s * 0.09, -s * 0.32), Vector2(s * 0.075, s * 0.08)), Color(0.75, 0.6, 0.48))
			ci.draw_rect(Rect2(c + Vector2(s * 0.18, -s * 0.02), Vector2(s * 0.14, s * 0.08)), col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.2, -s * 0.08), Vector2(s * 0.4, s * 0.08)), Color(0.55, 0.56, 0.58))
			for k in 4:
				ci.draw_circle(c + Vector2(-s * 0.14 + k * s * 0.09, -s * 0.04), s * 0.03, Color(0.78, 0.78, 0.8))
			ci.draw_rect(Rect2(c + Vector2(-s * 0.2, s * 0.22), Vector2(s * 0.4, s * 0.08)), Color(0.3, 0.32, 0.28))
		"nut":
			var pts := PackedVector2Array()
			for k in 6:
				var a := TAU * k / 6.0 + PI / 6.0
				pts.append(c + Vector2(cos(a), sin(a)) * s * 0.3)
			ci.draw_colored_polygon(pts, col)
			ci.draw_circle(c, s * 0.12, Color(0.08, 0.08, 0.08))
		"car_key":
			# ключ по диагонали: чёрная пластмассовая головка, стальное жало с бородкой, кольцо и латунная бирка
			var d := Vector2(1, 1).normalized()          # вдоль жала
			var n := Vector2(-d.y, d.x)                  # поперёк
			var hc := c - d * s * 0.12
			var head := PackedVector2Array([hc - d * s * 0.14 - n * s * 0.12, hc + d * s * 0.06 - n * s * 0.12,
				hc + d * s * 0.06 + n * s * 0.12, hc - d * s * 0.14 + n * s * 0.12])
			ci.draw_colored_polygon(head, Color(0.08, 0.08, 0.08))
			ci.draw_line(hc - d * s * 0.1 - n * s * 0.08, hc - d * s * 0.1 + n * s * 0.08, Color(0.3, 0.3, 0.3), maxf(1.0, s * 0.03))
			var b0 := hc + d * s * 0.06
			var b1 := b0 + d * s * 0.36
			var steel := Color(0.72, 0.73, 0.72)
			ci.draw_colored_polygon(PackedVector2Array([b0 - n * s * 0.05, b1 - n * s * 0.05, b1 + d * s * 0.03, b1 + n * s * 0.03, b0 + n * s * 0.05]), steel)
			for k in 3:
				var tp := b0.lerp(b1, 0.3 + 0.22 * k)
				ci.draw_colored_polygon(PackedVector2Array([tp + n * s * 0.04, tp + d * s * 0.04 + n * s * 0.1, tp + d * s * 0.08 + n * s * 0.04]), steel.darkened(0.15))
			ci.draw_line(b0, b1, steel.darkened(0.35), maxf(1.0, s * 0.02))
			var rc := hc - d * s * 0.2
			ci.draw_arc(rc, s * 0.08, 0.0, TAU, 16, Color(0.6, 0.6, 0.58), maxf(1.5, s * 0.03), true)
			var tg := rc + Vector2(-s * 0.12, s * 0.02)
			ci.draw_rect(Rect2(tg - Vector2(s * 0.08, 0), Vector2(s * 0.13, s * 0.2)), col)
			ci.draw_circle(tg + Vector2(-s * 0.015, s * 0.04), s * 0.02, Color(0.1, 0.08, 0.05))


## Маленькая 3D-модель предмета (для лежащих на полу вещей).
static func make_mesh(id: String) -> Node3D:
	if id in ["bat", "pipe", "crowbar", "machete", "knife", "shield", "gasmask", "filter", "hammer", "steel_hammer", "hatchet", "shiv", "spiked_club", "pistol"]:
		var w := Weapons.make(id)
		if id in ["bat", "pipe", "crowbar", "machete", "knife", "hammer", "steel_hammer", "hatchet", "shiv", "spiked_club"]:
			w.rotation.z = PI / 2   # на полу оружие лежит
		elif id == "pistol":
			# пистолет лежит на боку (модель — в плоскости XY): плоская сторона вниз, по центру коробки
			w.rotation.x = -PI / 2
			w.position = Vector3(-0.065, 0.014, 0.065)
		return w
	var col: Color = ITEMS[id]["color"] if ITEMS.has(id) else Color.WHITE
	var mi := MeshInstance3D.new()
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.6
	# лёгкое свечение — чтобы лут было видно в темноте
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 0.25
	match id:
		"coin":
			var cm := CylinderMesh.new()
			cm.top_radius = 0.05
			cm.bottom_radius = 0.05
			cm.height = 0.014
			cm.radial_segments = 16
			mi.mesh = cm
			m.metallic = 0.8
			m.roughness = 0.35
		"medkit":
			var bm := BoxMesh.new()
			bm.size = Vector3(0.24, 0.12, 0.17)
			mi.mesh = bm
			m.albedo_color = Color(0.75, 0.72, 0.66)
			m.emission = col
		"bandage":
			var cm := CylinderMesh.new()
			cm.top_radius = 0.04
			cm.bottom_radius = 0.04
			cm.height = 0.07
			mi.mesh = cm
		"rusk":
			var bm := BoxMesh.new()
			bm.size = Vector3(0.09, 0.035, 0.065)
			mi.mesh = bm
		"battery":
			var cm := CylinderMesh.new()
			cm.top_radius = 0.022
			cm.bottom_radius = 0.022
			cm.height = 0.1
			mi.mesh = cm
		"knuckles":
			var bm := BoxMesh.new()
			bm.size = Vector3(0.13, 0.03, 0.05)
			mi.mesh = bm
			m.metallic = 0.8
			m.roughness = 0.4
		"soda":
			var cm := CylinderMesh.new()
			cm.top_radius = 0.033
			cm.bottom_radius = 0.033
			cm.height = 0.12
			mi.mesh = cm
			m.metallic = 0.6
		"choco":
			var bm := BoxMesh.new()
			bm.size = Vector3(0.12, 0.015, 0.06)
			mi.mesh = bm
		"canned", "water", "tape":
			var cm := CylinderMesh.new()
			cm.top_radius = 0.045 if id != "water" else 0.035
			cm.bottom_radius = cm.top_radius
			cm.height = {"canned": 0.09, "water": 0.22, "tape": 0.04}[id]
			mi.mesh = cm
			m.metallic = 0.6 if id == "canned" else 0.0
		"pills", "wallet", "photo", "scrap":
			var bm := BoxMesh.new()
			bm.size = {"pills": Vector3(0.1, 0.012, 0.06), "wallet": Vector3(0.12, 0.025, 0.09),
				"photo": Vector3(0.1, 0.004, 0.13), "scrap": Vector3(0.18, 0.03, 0.06)}[id]
			mi.mesh = bm
		"wood":
			var bm := BoxMesh.new()
			bm.size = Vector3(0.22, 0.03, 0.05)
			mi.mesh = bm
		"glass":
			var pm := PrismMesh.new()
			pm.size = Vector3(0.06, 0.09, 0.006)
			mi.mesh = pm
			mi.rotation.x = -PI / 2
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color = Color(col.r, col.g, col.b, 0.6)
			m.roughness = 0.1
		"broom":
			var bm := BoxMesh.new()
			bm.size = Vector3(0.6, 0.03, 0.12)
			mi.mesh = bm
		"flashlight":
			var cm := CylinderMesh.new()
			cm.top_radius = 0.03
			cm.bottom_radius = 0.022
			cm.height = 0.16
			mi.mesh = cm
			mi.rotation.z = PI / 2
		"helmet", "ushanka":
			var sm := SphereMesh.new()
			sm.radius = 0.13
			sm.height = 0.14
			sm.is_hemisphere = true
			mi.mesh = sm
			if id == "ushanka":
				m.roughness = 1.0
		"moto_helmet":
			var sm := SphereMesh.new()
			sm.radius = 0.14
			sm.height = 0.26
			mi.mesh = sm
			m.roughness = 0.3
		"jacket", "pants", "kurtka", "vest", "jeans", "wpants", "tshirt":
			var bm := BoxMesh.new()
			bm.size = Vector3(0.4, 0.06, 0.32) if id in ["jacket", "kurtka", "vest", "tshirt"] else Vector3(0.3, 0.05, 0.42)
			if id == "vest":
				bm.size = Vector3(0.34, 0.08, 0.36)
				m.metallic = 0.4
			mi.mesh = bm
		"boots", "sneakers":
			var bm := BoxMesh.new()
			bm.size = Vector3(0.12, 0.22, 0.26) if id == "boots" else Vector3(0.11, 0.09, 0.26)
			mi.mesh = bm
		"backpack", "sack":
			var bm := BoxMesh.new()
			bm.size = Vector3(0.28, 0.36, 0.14) if id == "backpack" else Vector3(0.26, 0.3, 0.16)
			mi.mesh = bm
		"repair_weapon", "repair_gear":
			var bm := BoxMesh.new()
			bm.size = Vector3(0.2, 0.08, 0.14)
			mi.mesh = bm
		"gloves", "tac_gloves":
			var bm := BoxMesh.new()
			bm.size = Vector3(0.12, 0.03, 0.17)
			mi.mesh = bm
		"gear":
			var cm := CylinderMesh.new()
			cm.top_radius = 0.05
			cm.bottom_radius = 0.05
			cm.height = 0.015
			cm.radial_segments = 12
			mi.mesh = cm
			m.metallic = 0.7
		_:
			var cm := CylinderMesh.new()
			cm.top_radius = 0.03
			cm.bottom_radius = 0.03
			cm.height = 0.02
			cm.radial_segments = 6
			mi.mesh = cm
			m.metallic = 0.7
	mi.material_override = m
	return mi
