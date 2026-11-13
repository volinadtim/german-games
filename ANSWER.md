# Последний ответ

**Промпт:** «Godot при каждой догрузке просит перезагрузить файл с диска, потому что открыт проект» (из чата Claude)

## Что сделано
- `scripts/auto-pull.ps1` при запуске сам включает в Godot настройку **Auto Reload Scripts on External Change** — после этого изменённые скрипты перезагружаются молча, без вопроса.
- Если Godot в этот момент открыт, скрипт напишет жёлтым «Godot is open…» — тогда закрой Godot один раз и перезапусти автообновление.

## Что сделать на том компьютере
1. Закрыть окно автообновления и Godot.
2. Запустить `%USERPROFILE%\german-games\scripts\auto-pull.bat` — уже из склонированной папки, так скрипт всегда свежий.
3. Должна появиться зелёная строка «Godot: auto-reload of changed scripts turned on». Открыть Godot.

Вручную то же самое: Editor → Editor Settings → Text Editor → Behavior → Files → ✓ Auto Reload Scripts on External Change.

## Игра
`godot/concrete-halls` («Бетон») — без изменений, описание в истории коммитов.
