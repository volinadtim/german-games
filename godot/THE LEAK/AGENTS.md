# Правила для агентов, которые правят THE LEAK (папка godot/THE LEAK)

Бриф агента короткий и ссылается сюда. Всё ниже — обязательно.

## Порядок работы
- Воркеру диспетчера `git pull` не нужен — worktree уже обновлён. В сессии приложения: `git pull -q --rebase origin main`. Отправка — только `scripts/ship.sh "сообщение" [файлы]` (коммит + rebase + push, печатает одну строку). Без PR и веток.
- Коммит короткий, по-русски (строку Co-Authored-By добавляет `ship.sh`).
- `.godot/` не коммитить; `*.uid` и `*.import` — коммитить. Временные файлы (`zz_*`, тестовые сцены) не коммитить.
- Проверка: `scripts/gd-check.sh` (печатает OK или только ошибки; `--import` — после новых ассетов; её же запускает `ship.sh`). После правок в управлении, данных, сценах или сразу в нескольких зонах — ещё `scripts/smoke.sh --compare` (без окна, ~15 с: все локации, пол под игроком, окна, сплитскрин, управление, F8; сверка с `tests/baseline.json`). Godot напрямую не запускать — он выводит десятки килобайт шума.
- **Где что лежит — сначала карта:** `grep -n -i "<слово>" godot/THE LEAK/CODEMAP.md` (строки вида `scripts/car/car_drive.gd:1077 at_trunk(g) — описание`), потом Read только нужного куска (offset/limit). Нет карты — `python scripts/codemap.py`. Большие `.gd` целиком не читать, `ls`/`wc -l` для поиска не нужны.
- Новой функции — строка `## что делает` над ней (из неё строится карта).
- Любой длинный вывод режь: `| tail -20`, `| head -40`.

## Чего НЕ делать
- **Никаких скриншотов, своих тестовых скриптов, симуляций и прогонов игры** (кроме `gd-check.sh` и `smoke.sh`). Тестирует Герман сам.
- Не трогать сейвы игрока (`user://save_1..3.json`, `user://saves/`, `settings.cfg`, `controls.cfg`); старые сейвы должны грузиться.
- Не скачивать файлы и шрифты из интернета, не менять системные настройки.
- В чужих файлах — только минимальные правки (хук, пара строк), аккуратно с rebase.

## Отчёт
- Раздел в `ANSWER.md` пишет сам `ship.sh`: `ANSWER_AT="ЧЧ:ММ" ANSWER="что сделано; что проверить" scripts/ship.sh "msg" файлы` (время промпта МСК). Отдельно ANSWER.md не читать и не править.
- Меньше шагов: поиск по карте одной командой, все нужные куски одним сообщением (несколько Read), все правки одним сообщением, проверка+коммит — одним `ship.sh` (gd-check внутри).
- Ответ основной сессии — **1–2 строки**: хеш коммита и что не проверено. Без пересказа.

## Три правила архитектуры (обязательно)
1. **Кнопки — только в `data/controls/bindings.cfg`.** В коде нет `KEY_*`/`JOY_*` и `InputMap.add_action`: ввод спрашиваем только через
   autoload `Controls` — `Controls.pressed(игрок, "jump")`, `Controls.just_pressed(...)`, `Controls.vector(...)`,
   `Controls.event(e, "interact")` в `_input`. Новое действие — секция в `bindings.cfg` (label, group, keys, pad, modes, hint).
   Подсказка игроку — `"{interact} — открыть"` (или старое `"[F]"`) через `hud.prompt` / `Controls.hint()`: кнопка подставится
   под текущий ввод (клавиатура / Xbox / DualSense) и с переназначением игрока. Окно или слой ввода — `Controls.mode_on("inventory", self)`.
   Исключения (слой устройств): `scripts/controls/*`, `scripts/network/split.gd` (геймпад игрока 2), страницы переназначения кнопок.
2. **Настраиваемые числа — только в данных `data/`, в типизированных ресурсах.** Баланс, цены, шансы, урон, скорости, тексты —
   в `.tres`, у каждого файла свой класс в `scripts/data/<область>/` (`KillboxConfig`, `PlayerConfig`, `ShopsConfig`…):
   `@export` с `##`-подсказкой по-русски (видна в Инспекторе при наведении), `@export_group` по смыслу («Цены и крутки», «Шансы»,
   «Выплаты»…, геометрия — в группе «… (не баланс)»), `@export_range` где есть разумные пределы. Сущности списком — вложенные
   ресурсы (Type Object): символ автомата `SlotSymbol`/`KillboxSymbol`, уровень окна `SlotWindowLevel`, товар `ShopItem`,
   оружие `MeleeWeapon`, вид мутанта `MutantKind`, ветка навыков `PerkBranch`, настройка `SettingDef`, рецепт `CraftRecipe`.
   Скрипт читает `static var X: float = _D_<ИМЯ>.поле` (или метод класса, собирающий прежний словарь: `_D_KILLBOX.pay_table()`).
   Новое число — `@export` с подсказкой в нужном классе + значение в `.tres`, не `const` в коде. Не полагайся на значение по
   умолчанию в классе: Godot не пишет в `.tres` поля, равные умолчанию, — смена умолчания тихо меняет баланс.
   Предмет — `data/items/<id>.tres`, `scripts/data/item_type.gd`. Проверка «значения не поменялись» при переделке чтения —
   `tests/tools/data_snapshot.tscn -- check res://tests/tools/data_before.json` (снимок 348 значений на 20.11).
3. **Расстановка — только в сценах `scenes/`.** Где стоит объект — метка в `scenes/locations/<место>.tscn`
   (`scripts/world/prop_spot.gd`, превью модели видно в редакторе); код берёт `Places.pos/yaw/points/spots("место", "Метка")`
   (`scripts/world/places.gd`). Объект — заготовка `scenes/props/<объект>.tscn`, создаётся `preload(...).instantiate()`.
   Новый объект на карте — метка в сцене места, а не `Vector3(...)` в коде. Превью пересобирает `scripts/bake-places.sh`
   (сцены мест он не перезаписывает, только дописывает недостающие метки).

## Кто за что отвечает (зоны = папки)
Зона — это папка; правим в своей папке, в чужих — только минимальные хуки. Пути от `godot/THE LEAK/`.
| Зона | Папки и главные файлы |
|---|---|
| **Управление** | `scripts/controls/` (`controls.gd` — фасад, `bindings.gd` — таблица, `modes.gd` — стек режимов, `router.gd` — устройства по игрокам и Steam Input, `glyphs.gd` — имена кнопок, `gamepad.gd` — кнопки геймпада, `ui_nav.gd` — рамка в меню, `key_hint.gd` — подписи), `data/controls/bindings.cfg`; страницы настроек — `scripts/ui/menu.gd` (клавиатура), `scripts/ui/gamepad_page.gd` |
| **Данные** | `data/` (`balance/` — игрок, рывок, подкат, игра, уровни, перки, машина; `weapons/`; `enemies/`; `slots/` — KILLBOX, CASHY BOX, КЛЁВ, РАДИАЦИЯ (символы — внутри автомата); `shops/`; `items/`; `settings/` — настройки по умолчанию), классы ресурсов — `scripts/data/` (по папкам: `slots/`, `balance/`, `weapons/`, `enemies/`, `shops/`, `settings/`, `items/`) |
| **Сцены** | `scenes/locations/` (bunker, village, lake, city — метки расстановки; `preview/` — снимки для редактора), `scenes/props/` (заготовки), `scripts/world/places.gd`, `scripts/world/prop_spot.gd`, `tests/tools/bake_places.gd` |
| Проверка и отчёты | `tests/smoke.gd` + `scripts/smoke.sh` (снимок `tests/baseline.json`), `scripts/systems/bug_report.gd` (F8, `/where`, подсказка про Steam Input) |
| Автоматы | `scripts/slot/` (KILLBOX: `slot_machine.gd` ← `slot_machine_board.gd` ← `slot_machine_model.gd` ← `slot_machine_base.gd`; CASHY BOX `bonus_slot.gd`, КЛЁВ `lake_slot.gd`, РАДИАЦИЯ `city_slot.gd`, `slot_symbols.gd`, `slot_net.gd`, `fast_switch.gd`); числа — `data/slots/` |
| Магазины | `scripts/shop/` (`shop.gd` ← `shop_ui.gd` ← `shop_model.gd`; `village_shop.gd`, `lake_shop.gd`, `city_shop.gd`); ассортимент и цены — `data/shops/shops.tres` |
| Предметы, инвентарь, крафт | `scripts/items/` (`items.gd`, `inventory.gd`), `scripts/player/gasmask.gd`, `flashlight.gd`, `scripts/world/stone_pile.gd`; предметы — `data/items/` |
| Оружие | `scripts/weapons/` (`gun.gd`, `weapons.gd`, `stone_throw.gd`); числа — `data/weapons/` |
| Интерфейс | `scripts/ui/` (`hud.gd`, `loot_window.gd`, `sell_window.gd`, `menu.gd`, `touch_controls.gd`, `icon_button.gd`, `sketch_map.gd`, `console.gd`, `chat.gd`), `scripts/core/graphics.gd` |
| Игрок | `scripts/player/` (`player.gd` ← `player_combat.gd` ← `player_anim.gd` ← `player_model.gd` ← `player_base.gd`, `dash.gd`, `slide.gd`); числа — `data/balance/player.tres`, `dash.tres`, `slide.tres` |
| Враги | `scripts/enemy/` (`enemy.gd` ← `enemy_combat.gd` ← `enemy_nav.gd` ← `enemy_model.gd` ← `enemy_base.gd`; `mutant.gd` ← `mutant_base.gd`); числа — `data/enemies/` |
| Сеть | `scripts/network/` (`net.gd` ← `net_session.gd` ← `net_world.gd` ← `net_objects.gd` ← `net_base.gd`, `net_lobby.gd`, `split.gd` — сплитскрин, `voip.gd`) |
| Бункер (1-я локация) | `scripts/locations/bunker/` (`level.gd` ← `level_decor.gd` ← `level_geometry.gd`, `atmosphere.gd`, `surface.gd` ← `surface_build.gd`, `bunker_home.gd`…); места — `scenes/locations/bunker.tscn` |
| Машина | `scripts/car/` (`car.gd` ← `car_drive.gd` ← `car_model.gd`); числа — `data/balance/car.tres` |
| Деревня (2-я) | `scripts/locations/village/` (`village.gd` ← `village_build.gd`, `old_fence.gd`, `village_net.gd`); места — `scenes/locations/village.tscn` |
| Лагерь у озера (3-я) | `scripts/locations/lake/` (`lake_camp.gd`, `lake_base.gd`, `lake_spot.gd`, `lake_dive.gd`); места — `scenes/locations/lake.tscn` |
| Город (4-я) | `scripts/locations/city/city.gd`; места — `scenes/locations/city.tscn` |
| Мир: ящики, кувшины, манекен, перенос | `scripts/world/` (`chest.gd`, `jar.gd` ← `jar_model.gd`, `dummy.gd`, `carry.gd`, `build_kit.gd`, `pickup.gd`, `pickup_mesh.gd`, `wood_source.gd`) |
| Общие (правки осторожно) | `scripts/core/` (`game.gd` ← `game_save.gd` ← `game_items.gd` ← `game_world.gd` ← `game_base.gd`; `main.gd`, `sfx.gd`, `fx.gd`, `ambience.gd`), `scripts/systems/` (`save.gd`, `skills.gd`, `levels.gd`, `perks.gd`, `revive.gd`) |

Крупные скрипты разбиты цепочкой наследования: `x.gd extends "x_часть.gd" extends …` — главный файл (`x.gd`) наследует части;
переменные/константы — в самой нижней части. Новую функцию кладём в часть по смыслу; часть может вызывать только свои и нижележащие функции.
