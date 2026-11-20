extends RefCounted
## Стек режимов ввода. Каждый открытый «слой» (окно, консоль, пауза, машина) включает свой режим со своим владельцем;
## действует самый важный из включённых: console > menu > inventory > car > game. Владелец удалён — его режим снимается сам
## (окно закрылось не тем путём — ввод не «залипает»).
##   console   — консоль и чат: глушит всё, кроме своих кнопок;
##   menu      — пауза/главное меню: игровые действия не работают;
##   inventory — инвентарь и окна (магазин, лут, продажа, прокачка, карта): работают свои кнопки окна и всё,
##               что в таблице помечено режимом inventory (ходьба и прочее работают как раньше);
##   car       — за рулём / в машине;  game — пешком.

const PRIORITY := ["game", "car", "inventory", "menu", "console"]

var _on := {}   # режим -> {instance_id владельца: WeakRef}


func set_mode(mode: String, owner: Object, on: bool) -> bool:
	var before := top()
	if not _on.has(mode):
		_on[mode] = {}
	var id := owner.get_instance_id()
	if on:
		_on[mode][id] = weakref(owner)
	else:
		_on[mode].erase(id)
	return top() != before


func top() -> String:
	for i in range(PRIORITY.size() - 1, 0, -1):
		var m: String = PRIORITY[i]
		if _alive(m):
			return m
	return "game"


func is_on(mode: String) -> bool:
	return mode == "game" or _alive(mode)


func _alive(mode: String) -> bool:
	if not _on.has(mode):
		return false
	var d: Dictionary = _on[mode]
	for id in d.keys():
		var w: WeakRef = d[id]
		var o = w.get_ref()
		if o == null or (o is Node and not (o as Node).is_inside_tree()):
			d.erase(id)
	return not d.is_empty()
