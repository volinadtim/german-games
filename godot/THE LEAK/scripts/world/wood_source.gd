extends StaticBody3D
## Сухое дерево или куча старых досок на поляне (промпт 16.11 02:42): бей топориком (hatchet в руке) — деревяшки.
## Дерево: HITS_TREE ударов на деревяшку, запас 4; кончилось — остаётся пень, через REGROW с дерево снова целое.
## Доски: HITS_BOARDS ударов, запас 3, разобранная куча исчезает и тоже возвращается через REGROW.
## Без топорика — подсказка. Ставит spawn_all (game.gd), в сейв не пишется (запас восстанавливается).

const Items := preload("res://scripts/items/items.gd")
const HITS_TREE := 3
const HITS_BOARDS := 2
const REGROW := 240.0
## места на поляне (у руин и по краям; game._free_spot_near сдвигает от препятствий)
const TREES := [Vector3(26.5, 0, 14.0), Vector3(44.5, 0, 8.0), Vector3(22.5, 0, -5.5), Vector3(40.0, 0, -14.0), Vector3(47.0, 0, -6.5)]
const BOARDS := [Vector3(27.0, 0, -7.0), Vector3(37.5, 0, 9.5), Vector3(43.0, 0, -1.0)]

var game
var kind := "tree"         # tree | boards
var seed_ := 0
var left := 4
var hits := 0
var regrow_t := 0.0
var full: Node3D           # целое дерево / куча
var stump: Node3D          # пень (у дерева)
var shape: CollisionShape3D
var _hint_t := 0.0


static func spawn_all(g) -> void:
	var sf: Node = null
	var level: Node = g.get_parent().get_node_or_null("Level")
	if level:
		for c in level.get_children():
			if c.has_method("height"):
				sf = c
	if sf == null:
		return
	g._collect_obstacles()
	var k := 0
	for arr in [TREES, BOARDS]:
		for p in arr:
			var q: Vector3 = p
			q.y = sf.height(q.x, q.z)
			q = g._free_spot_near(q, 0.6, sf)
			var w = load("res://scripts/world/wood_source.gd").new()
			w.game = g
			w.kind = "tree" if arr == TREES else "boards"
			w.seed_ = k
			w.position = q
			g.add_child(w)
			k += 1


func _ready() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 7700 + seed_
	rotation.y = r.randf() * TAU
	left = 4 if kind == "tree" else 3
	shape = CollisionShape3D.new()
	add_child(shape)
	if kind == "tree":
		_build_tree(r)
	else:
		_build_boards(r)
	_set_state(true)


func _m(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.95
	return m


func _cyl(parent: Node3D, r0: float, r1: float, h: float, m: Material) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.bottom_radius = r0
	cm.top_radius = r1
	cm.height = h
	cm.radial_segments = 8
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = m
	parent.add_child(mi)
	return mi


func _build_tree(r: RandomNumberGenerator) -> void:
	var bark := _m(Color(0.27, 0.22, 0.17) * r.randf_range(0.85, 1.1))
	full = Node3D.new()
	add_child(full)
	var h := r.randf_range(2.6, 3.6)
	var trunk := _cyl(full, 0.2, 0.09, h, bark)
	trunk.position.y = h / 2
	trunk.rotation.z = r.randf_range(-0.06, 0.06)
	# голые сучья
	for k in r.randi_range(3, 5):
		var bl := r.randf_range(0.6, 1.2)
		var br := _cyl(full, 0.06, 0.02, bl, bark)
		var y := r.randf_range(h * 0.45, h * 0.9)
		var ang := r.randf() * TAU
		br.rotation = Vector3(r.randf_range(0.6, 1.1), ang, 0)
		br.position = Vector3(0, y, 0) + br.transform.basis.y * bl / 2
	stump = Node3D.new()
	add_child(stump)
	var st := _cyl(stump, 0.22, 0.2, 0.35, bark)
	st.position.y = 0.17
	var top := _cyl(stump, 0.19, 0.19, 0.02, _m(Color(0.62, 0.5, 0.33)))
	top.position.y = 0.355


func _build_boards(r: RandomNumberGenerator) -> void:
	full = Node3D.new()
	add_child(full)
	for k in 6:
		var bm := BoxMesh.new()
		bm.size = Vector3(r.randf_range(1.2, 1.8), 0.04, r.randf_range(0.14, 0.2))
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.material_override = _m(Color(0.42, 0.32, 0.2) * r.randf_range(0.75, 1.15))
		@warning_ignore("integer_division")
		mi.position = Vector3(r.randf_range(-0.1, 0.1), 0.03 + (k / 2) * 0.045, -0.16 + (k % 2) * 0.24 + r.randf_range(-0.04, 0.04))
		mi.rotation = Vector3(r.randf_range(-0.05, 0.05), r.randf_range(-0.25, 0.25), r.randf_range(-0.04, 0.04))
		full.add_child(mi)
	stump = null


func _set_state(whole: bool) -> void:
	full.visible = whole
	if stump:
		stump.visible = not whole
	var bs := BoxShape3D.new()
	if kind == "tree":
		bs.size = Vector3(0.45, 3.0, 0.45) if whole else Vector3(0.45, 0.36, 0.45)
		shape.position.y = bs.size.y / 2
		shape.disabled = false
	else:
		bs.size = Vector3(1.6, 0.18, 0.6)
		shape.position.y = 0.09
		shape.disabled = not whole
	shape.shape = bs


func _process(delta: float) -> void:
	_hint_t = maxf(_hint_t - delta, 0.0)
	if left > 0:
		return
	regrow_t -= delta
	if regrow_t <= 0.0 and (game == null or game.player == null or game.player.global_position.distance_to(global_position) > 8.0):
		left = 4 if kind == "tree" else 3
		hits = 0
		_set_state(true)


func get_prompt(_g) -> String:
	return ""   # подсказку «бей топориком (ЛКМ)» убрали (промпт 18.11 01:01)


func interact(g) -> void:
	if left > 0:
		g.hud.toast("Возьми топорик в руку и бей ЛКМ")


func take_hit(_dmg: float, _dir: Vector3) -> void:
	if game == null or left <= 0:
		return
	var p = game.player
	var hand := "left" if p != null and p.last_arm == 0 else "right"
	if String(game.inv.equip[hand]) != "hatchet":
		if _hint_t <= 0.0:
			_hint_t = 3.0
			game.hud.toast("Нужен топорик — купи в магазине («Инструменты»)")
		return
	game.weapon_hit()   # топорик изнашивается
	hits += 1
	var tw := create_tween()
	tw.tween_property(full, "rotation:z", 0.03, 0.04)
	tw.tween_property(full, "rotation:z", 0.0, 0.2).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	game.play_at("thud", global_position + Vector3(0, 1.0, 0), -10.0, 1.3)
	if hits < (HITS_TREE if kind == "tree" else HITS_BOARDS):
		return
	hits = 0
	left -= 1
	if game.inv.add("wood", 1) > 0:
		var pk = game._make_pickup("wood", 1, global_position + Vector3(0, 0.8, 0), Vector3(0, 1.5, 0))
		pk.need_leave = false
		game.hud.toast("Нет места — деревяшка на земле")
	else:
		game.hud.toast("+ Деревяшка", Color(0.85, 0.8, 0.65))
		game.play_ui("pickup", -12.0, 0.9)
	if left <= 0:
		regrow_t = REGROW
		_set_state(false)
		game.play_at("creak", global_position + Vector3(0, 1.0, 0), -8.0, 0.7)
