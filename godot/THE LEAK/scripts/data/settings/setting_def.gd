@tool
class_name SettingDef
extends Resource
## Настройка в меню: ползунок или переключатель (min/max/step), значение по умолчанию.

## Ключ в settings.cfg игрока — не менять.
@export var key := ""
## Подпись в меню.
@export var title := ""
## Минимум.
@export var min_value := 0.0
## Максимум.
@export var max_value := 1.0
## Шаг.
@export var step := 1.0
## По умолчанию.
@export var default_value := 0.0
