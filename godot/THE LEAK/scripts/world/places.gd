extends RefCounted
## Расстановка из сцен (паттерн Service Locator для мест): где стоит объект — решает сцена scenes/locations/<место>.tscn,
## а не код. В сцене — метки (scripts/world/prop_spot.gd): их двигают мышкой в редакторе, превью модели видно сразу.
##   Places.xf("bunker", "Safe") -> Transform3D метки в координатах места;
##   Places.pos("village", "CashyBox") -> Vector3;  Places.yaw(...) -> поворот по Y;
##   Places.points("bunker", "EnemySpots") -> позиции всех меток внутри группы (по порядку);
##   Places.put(узел, "bunker", "Safe") — поставить узел на метку.
## Места: bunker (Main: бункер и поляна), village (узел Village), lake (LakeCamp — без смещения OFF), city (City — без OFF).
## Сцена читается один раз: положения меток запоминаются, сами узлы сразу удаляются.

const DIR := "res://scenes/locations/"

static var _xf := {}     # место -> {путь метки: Transform3D относительно корня}
static var _kids := {}   # место -> {путь группы: [пути детей по порядку]}


static func _load(loc: String) -> void:
	if _xf.has(loc):
		return
	_xf[loc] = {}
	_kids[loc] = {}
	var ps: PackedScene = load(DIR + loc + ".tscn")
	if ps == null:
		push_error("Places: нет сцены " + DIR + loc + ".tscn")
		return
	var root := ps.instantiate()
	_walk(loc, root, "", Transform3D.IDENTITY)
	root.free()


static func _walk(loc: String, n: Node, path: String, parent_xf: Transform3D) -> void:
	var list: Array = []
	for c in n.get_children():
		if not c is Node3D:
			continue
		var p := (path + "/" if path != "" else "") + String(c.name)
		var t: Transform3D = parent_xf * (c as Node3D).transform
		_xf[loc][p] = t
		list.append(p)
		_walk(loc, c, p, t)
	_kids[loc][path] = list


## Положение метки относительно корня сцены места.
static func xf(loc: String, path: String) -> Transform3D:
	_load(loc)
	if not _xf[loc].has(path):
		push_error("Places: в %s.tscn нет метки %s" % [loc, path])
		return Transform3D.IDENTITY
	return _xf[loc][path]


static func pos(loc: String, path: String) -> Vector3:
	return xf(loc, path).origin


static func yaw(loc: String, path: String) -> float:
	return xf(loc, path).basis.get_euler().y


static func put(n: Node3D, loc: String, path: String) -> void:
	n.transform = xf(loc, path)


## Позиции меток-детей группы (EnemySpots/1, EnemySpots/2…) по порядку.
static func points(loc: String, group: String) -> Array:
	_load(loc)
	var out: Array = []
	for p in _kids[loc].get(group, []):
		out.append((_xf[loc][p] as Transform3D).origin)
	if out.is_empty():
		push_error("Places: в %s.tscn нет меток в группе %s" % [loc, group])
	return out
