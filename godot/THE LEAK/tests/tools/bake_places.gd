extends "res://tests/smoke.gd"
## Инструмент расстановки (без окна, запуск — scripts/bake-places.sh):
##   1) строит мир как в игре, 2) пишет превью моделей scenes/props/preview/*.tscn и превью мест scenes/locations/preview/*.tscn
##   (только видимые меши, без скриптов и коллизий — для редактора), 3) если сцены места scenes/locations/<место>.tscn ещё нет —
##   создаёт её с метками на текущих местах объектов. Уже существующие сцены мест НЕ перезаписывает (их правят руками в редакторе),
##   разве что с аргументом -- --force.

const Spot := preload("res://scripts/world/prop_spot.gd")
const VISUAL := ["Node3D", "MeshInstance3D", "MultiMeshInstance3D", "Label3D", "Decal", "Sprite3D",
	"CSGBox3D", "CSGCylinder3D", "CSGSphere3D", "CSGPolygon3D", "CSGTorus3D", "CSGMesh3D", "CSGCombiner3D"]
const BODY := ["StaticBody3D", "AnimatableBody3D", "RigidBody3D", "Area3D", "CharacterBody3D", "Marker3D"]

var force := "--force" in OS.get_cmdline_user_args()
var written: PackedStringArray = []


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	await _frames(30)
	main.call("_enter_game")
	await _frames(10)
	for c in main.get_children():
		if c.has_method("save_now"):
			game = c
	await _skip_intro()
	var v = game.get("village")
	v.call("_ensure_lake")
	v.call("_ensure_city")
	await _frames(20)
	var G = game
	var Main = main
	var Surf = load("res://scripts/locations/bunker/surface_build.gd")
	var Lake = load("res://scripts/locations/lake/lake_camp.gd")
	var CityS = load("res://scripts/locations/city/city.gd")
	var VB = load("res://scripts/locations/village/village_build.gd")
	var WS = load("res://scripts/world/wood_source.gd")
	var lake: Node3D = v.lake
	var city: Node3D = v.city
	# место -> [корень координат, [[имя метки, узел-источник или Transform3D, превью-ключ, пояснение]]]
	var spec := {
		"bunker": [main, [
			["KillBox", main.slot, "killbox", "автомат KILLBOX (фон главного меню)"],
			["Shop", main.get_node("Shop"), "shop", "Trinkets Market бункера"],
			["MenuCam", Transform3D(Basis(), Main.MENU_CAM_POS), "", "камера главного меню"],
			["MenuCamLook", Transform3D(Basis(), Main.MENU_CAM_LOOK), "", "куда смотрит камера меню"],
			["PlayerStart", Transform3D(Basis(Vector3.UP, -PI / 2.0), G.START), "", "старт игрока (новая игра и «Начать заново»)"],
			["Dummy", G.knife_dummy, "dummy", "манекен с ножом"],
			["Safe", G.safe, "safe", "сейф (открывается тремя семёрками)"],
			["Storage", G.storage, "storage", "сундук-хранилище"],
			["Tape", G.tape, "tape", "изолента на доске выплат"],
			["ExitSign", _child_with(G, "exit_sign.gd"), "exit_sign", "табличка над выходом к лестнице"],
			["CarPark", Transform3D(Basis(Vector3.UP, Surf.CAR_YAW), Surf.CAR_POS), "car", "старая машина на поляне"],
			["EnemySpots", _group(G.ENEMY_SPOTS), "", "точки появления врагов на поляне"],
			["StoneBunker", _group(G.STONE_BUNKER), "stone_pile", "кучки камней в бункере (кандидаты)"],
			["StoneSurface", _group(G.STONE_SURFACE), "stone_pile", "кучки камней на поляне"],
			["Trees", _group(WS.TREES), "tree", "деревья (топорик); высота — по земле"],
			["Boards", _group(WS.BOARDS), "boards", "кучи досок; высота — по земле"],
		]],
		"village": [v, [
			["CashyBox", v.bonus_slot, "cashy_box", "автомат CASHY BOX"],
			["VillageShop", v.shop, "village_shop", "Trinkets Market деревни"],
			["VillageStorage", v.storage, "storage", "сундук-хранилище деревни"],
			["Stall", Transform3D(Basis(), VB.STALL), "", "место, где глохнет машина (въезд в деревню, /tp деревня)"],
		]],
		"lake": [lake, [
			["LakeShop", lake.get_node("LakeShop"), "lake_shop", "Trinkets Market у озера"],
			["Klev", _child_with(lake, "lake_slot.gd"), "klev", "автомат КЛЁВ"],
			["CarPark", Transform3D(Basis(Vector3.UP, Lake.CAR_YAW), Lake.CAR_POS), "car", "где встаёт машина"],
			["Fire", Transform3D(Basis(), Lake.FIRE), "", "костёр лагеря"],
		]],
		"city": [city, [
			["CityShop", city.get_node("CityShop"), "city_shop", "Trinkets Market города"],
			["Radiation", _child_with(city, "city_slot.gd"), "radiation", "автомат РАДИАЦИЯ"],
			["CarPark", Transform3D(Basis(Vector3.UP, CityS.CAR_YAW), CityS.CAR_POS), "car", "где встаёт машина"],
		]],
	}
	# превью моделей
	var prev_src := {"killbox": main.slot, "shop": main.get_node("Shop"), "dummy": G.knife_dummy, "safe": G.safe,
		"storage": G.storage, "tape": G.tape, "exit_sign": _child_with(G, "exit_sign.gd"), "car": G.car,
		"stone_pile": _child_with(G, "stone_pile.gd"), "tree": _wood(G, "tree"), "boards": _wood(G, "boards"),
		"cashy_box": v.bonus_slot, "village_shop": v.shop, "lake_shop": lake.get_node("LakeShop"),
		"klev": _child_with(lake, "lake_slot.gd"), "city_shop": city.get_node("CityShop"), "radiation": _child_with(city, "city_slot.gd")}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://scenes/props/preview"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://scenes/locations/preview"))
	for k in prev_src:
		if prev_src[k] == null:
			_fail("нет источника превью " + k)
			continue
		_save(_visual(prev_src[k], true), "res://scenes/props/preview/%s.tscn" % k)
	# превью мест: всё видимое, кроме объектов со скриптами (их показывают метки)
	# бункер в редакторе и так строит свой скрипт (@tool level.gd) — превью из одного узла с этим скриптом
	var lv := Node3D.new()
	lv.name = "BunkerLevel"
	lv.set_script(load("res://scripts/locations/bunker/level.gd"))
	_save(lv, "res://scenes/locations/preview/bunker.tscn")
	# остальные места строятся кодом только в игре — снимок видимых мешей, двоичный (.scn), в сборку не входит
	_save(_visual(v, false, [lake, city]), "res://scenes/locations/preview/village.scn")
	_save(_visual(lake, false), "res://scenes/locations/preview/lake.scn")
	_save(_visual(city, false), "res://scenes/locations/preview/city.scn")
	# сцены мест
	for loc in spec:
		var path := "res://scenes/locations/%s.tscn" % loc
		if ResourceLoader.exists(path) and not force:
			print("BAKE keep ", path)
			continue
		var frame: Node3D = spec[loc][0]
		var root := Node3D.new()
		root.name = loc.capitalize().replace(" ", "")
		var pv := Spot.new()
		pv.name = "Preview"
		pv.note = "превью места в редакторе (в игре не создаётся)"
		pv.preview = "res://scenes/locations/preview/%s.%s" % [loc, "tscn" if loc == "bunker" else "scn"]
		root.add_child(pv)
		pv.owner = root
		for s in spec[loc][1]:
			var src = s[1]
			if src is Array:
				var grp := Node3D.new()
				grp.name = s[0]
				root.add_child(grp)
				grp.owner = root
				for i in src.size():
					var m := _spot(str(i + 1), src[i], s[2], s[3])
					grp.add_child(m)
					m.owner = root
			else:
				var t: Transform3D
				if src is Transform3D:
					t = src
				elif src is Node3D:
					t = frame.global_transform.affine_inverse() * (src as Node3D).global_transform
				else:
					_fail("нет узла для метки %s/%s" % [loc, s[0]])
					continue
				var m2 := _spot(s[0], t, s[2], s[3])
				root.add_child(m2)
				m2.owner = root
		_save(root, path)
	print("BAKE written ", written.size())
	get_tree().quit(1 if fails.size() > 0 else 0)


func _spot(nm: String, t: Transform3D, prev: String, note: String) -> Node3D:
	var m := Spot.new()
	m.name = nm
	m.transform = t
	m.note = note
	if prev != "":
		m.preview = "res://scenes/props/preview/%s.tscn" % prev
	return m


func _group(pts: Array) -> Array:
	var out: Array = []
	for p in pts:
		out.append(Transform3D(Basis(), p))
	return out


func _child_with(parent: Node, script_file: String) -> Node3D:
	for c in parent.get_children():
		var s = c.get_script()
		if s and s.resource_path.get_file() == script_file:
			return c
	return null


func _wood(g: Node, kind: String) -> Node3D:
	for c in g.get_children():
		var s = c.get_script()
		if s and s.resource_path.get_file() == "wood_source.gd" and c.get("kind") == kind:
			return c
	return null


## Видимая копия поддерева: меши, CSG, надписи, декали; тела — пустые Node3D; без скриптов, коллизий, света, звука.
## prop — копия модели объекта (вместе с детьми-скриптами), иначе узлы со скриптами пропускаются (их показывают метки).
func _visual(src: Node, prop: bool, skip: Array = []) -> Node3D:
	var root := Node3D.new()
	root.name = String(src.name) + "Preview"
	for c in src.get_children():
		_copy_into(c, root, root, prop, skip)
	return root


func _copy_into(n: Node, parent: Node, owner_: Node, prop: bool, skip: Array) -> void:
	if n in skip or not n is Node3D:
		return
	if not prop and n.get_script() != null:
		return
	if n is GeometryInstance3D and not (n as GeometryInstance3D).visible:
		return
	var cls := n.get_class()
	var copy: Node3D
	if cls in VISUAL:
		copy = (n as Node).duplicate(0) as Node3D   # без детей, сигналов, групп и скриптов
		for ch in copy.get_children():
			copy.remove_child(ch)
			ch.free()
		if copy.get_script() != null:
			copy.set_script(null)
	elif cls in BODY or n.get_script() != null:
		copy = Node3D.new()
	else:
		return   # свет, звук, частицы, камеры, коллизии
	copy.name = n.name
	copy.transform = (n as Node3D).transform
	copy.visible = (n as Node3D).visible
	parent.add_child(copy)
	copy.owner = owner_
	for c in n.get_children():
		_copy_into(c, copy, owner_, prop, skip)


func _save(root: Node, path: String) -> void:
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err == OK:
		err = ResourceSaver.save(ps, path)
	if err != OK:
		_fail("не сохранилось %s (%d)" % [path, err])
	else:
		written.append(path)
		print("BAKE ", path, " ", FileAccess.get_file_as_bytes(path).size() / 1024, " КБ")
	root.free()
