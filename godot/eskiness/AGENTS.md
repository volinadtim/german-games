# Правила для агентов, которые правят eskiNess

Бриф агента короткий и ссылается сюда. Всё ниже — обязательно.

## Порядок работы
- Перед работой: `git pull --rebase origin main`. После: коммит → `git pull --rebase origin main` → `git push origin HEAD:main`. Без PR и веток.
- Коммит короткий, по-русски, в конце строка `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- `.godot/` не коммитить; `*.uid` и `*.import` — коммитить. Временные файлы (`zz_*`, тестовые сцены) не коммитить.
- Godot — команда `godot`. Единственная проверка: `godot --headless --path godot/eskiness --quit-after 120` без `SCRIPT ERROR`.

## Чего НЕ делать
- **Никаких скриншотов, тестовых скриптов, симуляций и прогонов игры.** Тестирует Герман сам.
- Не трогать сейвы игрока (`user://save_1..3.json`, `settings.cfg`).
- Не скачивать файлы и шрифты из интернета, не менять системные настройки.
- В чужих файлах — только минимальные правки (хук, пара строк), аккуратно с rebase.

## Отчёт
- В корневой `ANSWER.md` — сверху раздел `## ЧЧ:ММ — тема` (время промпта МСК): что сделано и что проверить Герману, по-русски, коротко. Разделы других агентов не трогать.
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
| Машина | `car/car.gd` ← `car_model.gd` |
| Мир: ящики, кувшины, манекен, дом (чертежи) | `world/chest.gd`, `world/jar.gd` ← `jar_model.gd`, `world/dummy.gd`, `world/bunker_home.gd`, `world/carry.gd` (перенос на B) |
| Общие (правки осторожно) | `core/game.gd` ← `game_save.gd` ← `game_items.gd` ← `game_world.gd` ← `game_base.gd`; `core/main.gd`, `core/sfx.gd`, `core/sfx_extra.gd`, `core/fx.gd`, `core/ambience.gd`, `systems/save.gd` |
