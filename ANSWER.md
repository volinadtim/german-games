# Последний ответ

**Промпт:** «у Германа Godot из Steam» (из чата Claude)

## Что сделано
- Godot из Steam хранит настройки в `steamapps\common\Godot Engine\editor_data\`, а не в `%APPDATA%` — поэтому скрипт молчал.
- `scripts/auto-pull.ps1` теперь ищет их во всех библиотеках Steam (любой диск), плюс в `%APPDATA%\Godot`, рядом с godot.exe и по ярлыкам.
- Скрипт всегда пишет строку про Godot: «turned on», «already on» или жёлтое «not found / Godot is open».

## Что сделать на том компьютере
1. Закрыть окно автообновления и Godot.
2. Запустить `%USERPROFILE%\german-games\scripts\auto-pull.bat`.
3. Посмотреть строку про Godot:
   - зелёная — готово, открывать Godot;
   - «not found» — открыть Godot один раз, закрыть, перезапустить скрипт; или включить вручную: Editor → Editor Settings → Text Editor → Behavior → Files → ✓ Auto Reload Scripts on External Change.

## Игра
`godot/concrete-halls` («Бетон») — без изменений.
