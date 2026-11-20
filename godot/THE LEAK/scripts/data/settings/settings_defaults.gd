@tool
class_name SettingsDefaults
extends Resource
## Настройки меню и значения по умолчанию (scripts/ui/menu.gd). Файл — data/settings/defaults.tres.

## Все настройки по порядку в меню: подпись, минимум, максимум, шаг, по умолчанию.
@export var settings: Array[SettingDef] = []
## Ключи категории «Основное» (остальное, кроме «Прицела», — в «Экран и графика»).
@export var general_keys: Array[String] = []
## Ключи категории «Прицел».
@export var aim_keys: Array[String] = []
## Разрешения окна: первое (0, 0) — авто (под экран).
@export var resolutions: Array[Vector2i] = []


## key -> [подпись, мин, макс, шаг, по умолчанию]
func settings_table() -> Dictionary:
	var out := {}
	for s in settings:
		out[s.key] = [s.title, s.min_value, s.max_value, s.step, s.default_value]
	return out
