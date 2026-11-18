# Правила для агентов, которые правят eskiNess

Бриф агента короткий и ссылается сюда. Всё ниже — обязательно.

## Порядок работы
- Воркеру диспетчера `git pull` не нужен — worktree уже обновлён. В сессии приложения: `git pull -q --rebase origin main`. Отправка — только `scripts/ship.sh "сообщение" [файлы]` (коммит + rebase + push, печатает одну строку). Без PR и веток.
- Коммит короткий, по-русски (строку Co-Authored-By добавляет `ship.sh`).
- `.godot/` не коммитить; `*.uid` и `*.import` — коммитить. Временные файлы (`zz_*`, тестовые сцены) не коммитить.
- Единственная проверка: `scripts/gd-check.sh` (печатает OK или только ошибки; `--import` — после новых ассетов). Godot напрямую не запускать — он выводит десятки килобайт шума.
- **Где что лежит — сначала карта:** `grep -n -i "<слово>" godot/eskiness/CODEMAP.md` (строки вида `scripts/car/car_drive.gd:1077 at_trunk(g) — описание`), потом Read только нужного куска (offset/limit). Нет карты — `python scripts/codemap.py`. Большие `.gd` целиком не читать, `ls`/`wc -l` для поиска не нужны.
- Новой функции — строка `## что делает` над ней (из неё строится карта).
- Любой длинный вывод режь: `| tail -20`, `| head -40`.

## Чего НЕ делать
- **Никаких скриншотов, тестовых скриптов, симуляций и прогонов игры.** Тестирует Герман сам.
- Не трогать сейвы игрока (`user://save_1..3.json`, `settings.cfg`).
- Не скачивать файлы и шрифты из интернета, не менять системные настройки.
- В чужих файлах — только минимальные правки (хук, пара строк), аккуратно с rebase.

## Отчёт
- Раздел в `ANSWER.md` пишет сам `ship.sh`: `ANSWER_AT="ЧЧ:ММ" ANSWER="что сделано; что проверить" scripts/ship.sh "msg" файлы` (время промпта МСК). Отдельно ANSWER.md не читать и не править.
- Меньше шагов: поиск по карте одной командой, все нужные куски одним сообщением (несколько Read), все правки одним сообщением, проверка+коммит — одним `ship.sh` (gd-check внутри).
- Ответ основной сессии — **1–2 строки**: хеш коммита и что не проверено. Без пересказа.

## Кто за что отвечает (файлы)
Пути от `scripts/`. Крупные скрипты разбиты цепочкой наследования: `x.gd extends "x_часть.gd" extends …` — главный файл (`x.gd`, его грузят preload/сцены) наследует части; переменные/константы — в самой нижней части. Новую функцию кладём в часть по смыслу; часть может вызывать только свои и нижележащие функции.
| Зона | Файлы |
|---|---|
| Автомат KILLBOX, доска выплат, лоток, баланс | `slot/slot_machine.gd` ← `slot_machine_board.gd` ← `slot_machine_model.gd` ← `slot_machine_base.gd`, `slot/slot_symbols.gd` |
| Магазин | `shop/shop.gd` ← `shop_ui.gd` ← `shop_model.gd` |
| Инвентарь, предметы, крафт, продажа, Нюхич, пистолет | `inventory.gd`, `items.gd`, `weapons.gd`, `loot_window.gd`, `sell_window.gd`, `hud.gd`, `gun.gd`, `stone_pile.gd`, `stone_throw.gd`, `player/gasmask.gd`, `player/flashlight.gd` |
| Игрок, бой | `player/player.gd` ← `player_combat.gd` ← `player_anim.gd` ← `player_model.gd` ← `player_base.gd` |
| Враги | `enemy/enemy.gd` ← `enemy_combat.gd` ← `enemy_nav.gd` ← `enemy_model.gd` ← `enemy_base.gd` |
| Меню, управление, подбор, модели лута, графика | `ui/menu.gd`, `ui/touch_controls.gd`, `ui/icon_button.gd`, `world/pickup.gd`, `world/pickup_mesh.gd`, `core/graphics.gd` |
| Сеть | `network/net.gd` ← `net_session.gd` ← `net_world.gd` ← `net_objects.gd` ← `net_base.gd`, `network/net_lobby.gd` |
| Уровень, свет, атмосфера, поляна | `level/level.gd` ← `level_decor.gd` ← `level_geometry.gd`; `level/atmosphere.gd` ← `atmosphere_assets.gd`; `level/surface.gd` ← `surface_build.gd`; `level/flicker_light.gd`, `level/glass_floor.gd`, `level/tape_spot.gd` |
| Машина (кат-сцена, места, двери, вождение, бензин) | `car/car.gd` ← `car_drive.gd` ← `car_model.gd` |
| Деревня — 2-я локация (дорога, дома, подвал, задание), автомат ФОРТУНА, мутанты, сеть машины/деревни | `village/village.gd` ← `village_build.gd`; `village/bonus_slot.gd`; `village/mutant.gd` ← `mutant_base.gd`; `village/village_net.gd` (/root/VillageNet) |
| Мир: ящики, кувшины, манекен, дом (чертежи) | `world/chest.gd`, `world/jar.gd` ← `jar_model.gd`, `world/dummy.gd`, `world/bunker_home.gd`, `world/carry.gd` (перенос на B) |
| Общие (правки осторожно) | `core/game.gd` ← `game_save.gd` ← `game_items.gd` ← `game_world.gd` ← `game_base.gd`; `core/main.gd`, `core/sfx.gd`, `core/sfx_extra.gd`, `core/fx.gd`, `core/ambience.gd`, `systems/save.gd` |
