extends Resource
## Таблица настроек (паттерн Configuration Object): имя -> значение. Файлы — data/**/*.tres, правятся в инспекторе Godot.
## Скрипт читает их при загрузке: `static var WALK: float = _D.v("WALK")` — в коде чисел не остаётся.
## Имена совпадают с прежними константами скриптов (WALK, JUMP, PAY…), так по коду легко найти, где число используется.
## order — исходный порядок ключей словарей (Godot сохраняет .tres с ключами по алфавиту, а порядок важен:
## доска выплат, вкладки, списки). Новый ключ, добавленный в инспекторе, встаёт в конец.

@export var values: Dictionary = {}
@export var order: Dictionary = {}   ## имя -> {"_": [ключи по порядку], ключ: {…вложенный порядок}}


## Значение по имени (словари — в исходном порядке ключей).
func v(key: String):
	if not values.has(key):
		push_error("%s: нет значения %s" % [resource_path, key])
		return null
	return _ordered(values[key], order.get(key, {}))


static func _ordered(val, spec):
	if val is Dictionary and spec is Dictionary and not spec.is_empty():
		var out := {}
		for k in spec.get("_", []):
			if val.has(k):
				out[k] = _ordered(val[k], spec.get(k, {}))
		for k in val:
			if not out.has(k):
				out[k] = val[k]
		return out
	if val is Array and spec is Dictionary and spec.has("[]"):
		var arr: Array = []
		for x in val:
			arr.append(_ordered(x, spec["[]"]))
		return arr
	return val


## Порядок ключей значения (для инструмента выгрузки).
static func order_of(val) -> Dictionary:
	if val is Dictionary:
		var spec := {"_": val.keys()}
		for k in val:
			var s := order_of(val[k])
			if not s.is_empty():
				spec[k] = s
		return spec
	if val is Array:
		for x in val:
			if x is Dictionary or x is Array:
				var s2 := order_of(x)
				if not s2.is_empty():
					return {"[]": s2}   # у элементов массива одинаковые ключи — берём порядок первого
	return {}
