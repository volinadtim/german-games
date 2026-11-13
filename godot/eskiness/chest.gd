extends StaticBody3D
## Ящик с лутом / сейф (сундуки). E — открыть: крышка (или дверца сейфа) откидывается со скрипом,
## лут вылетает наружу и подбирается, когда подойдёшь. Лут — случайный из таблицы LOOT + гарантированный extra.
## Интерфейс взаимодействия (его дёргает game.gd): get_prompt(game) -> String, interact(game).

## [предмет, вес, мин, макс]
const LOOT := [
	["bandage", 16, 1, 3],
	["medkit", 7, 1, 1],
	["pills", 10, 1, 2],
	["canned", 9, 1, 2],
	["water", 12, 1, 2],
	["rusk", 14, 1, 4],
	["battery", 12, 1, 2],
	["wallet", 6, 1, 1],
	["nut", 10, 1, 4],
	["scrap", 9, 1, 3],
	["gear", 8, 1, 2],
	["tape", 7, 1, 2],
	["photo", 4, 1, 1],
	["wood", 12, 1, 1],
	["glass", 9, 1, 1],
	["coin", 16, 5, 15],
]

var kind := "crate"            # crate | safe
var extra: Array = []          # гарантированный лут: [[id, n], ...]
var locked := false            # сейф: открывается только тремя семёрками на автомате (force_open)
var random_loot := true
var opened := false
var hinge: Node3D
var snd: AudioStreamPlayer3D


func _ready() -> void:
	if kind == "safe":
		_build_safe()
	else:
		_build_crate()
	snd = AudioStreamPlayer3D.new()
	snd.position.y = 0.5
	snd.unit_size = 4.0
	add_child(snd)


func _mat(c: Color, metal := 0.0, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m


func _part(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func _collide(size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	add_child(cs)


## Деревянный ящик с железными полосами; перед — +Z.
func _build_crate() -> void:
	var wood := _mat(Color(0.24, 0.16, 0.095))
	var wood_dark := _mat(Color(0.1, 0.07, 0.045))
	var metal := _mat(Color(0.16, 0.155, 0.15), 0.6, 0.55)
	var w := 0.9
	var d := 0.55
	var h := 0.42
	# корпус из стенок, чтобы было видно, что внутри пусто
	_part(self, Vector3(w, 0.04, d), Vector3(0, 0.02, 0), wood_dark)
	_part(self, Vector3(w, h, 0.04), Vector3(0, h / 2, d / 2 - 0.02), wood)
	_part(self, Vector3(w, h, 0.04), Vector3(0, h / 2, -d / 2 + 0.02), wood)
	_part(self, Vector3(0.04, h, d), Vector3(w / 2 - 0.02, h / 2, 0), wood)
	_part(self, Vector3(0.04, h, d), Vector3(-w / 2 + 0.02, h / 2, 0), wood)
	_part(self, Vector3(w - 0.08, 0.02, d - 0.08), Vector3(0, 0.05, 0), wood_dark)
	for x in [-0.3, 0.3]:
		_part(self, Vector3(0.06, h + 0.01, d + 0.015), Vector3(x, h / 2, 0), metal)
	_part(self, Vector3(0.1, 0.12, 0.02), Vector3(0, h - 0.08, d / 2 + 0.01), metal)
	hinge = Node3D.new()
	hinge.position = Vector3(0, h, -d / 2)
	add_child(hinge)
	_part(hinge, Vector3(w + 0.02, 0.08, d + 0.02), Vector3(0, 0.04, d / 2), wood)
	for x in [-0.3, 0.3]:
		_part(hinge, Vector3(0.06, 0.085, d + 0.03), Vector3(x, 0.04, d / 2), metal)
	_collide(Vector3(w, h + 0.08, d), Vector3(0, (h + 0.08) / 2, 0))


## Сейф: железный шкаф с круглой ручкой-штурвалом; дверца на петлях слева.
func _build_safe() -> void:
	var steel := _mat(Color(0.16, 0.19, 0.17), 0.55, 0.5)
	var inner := _mat(Color(0.05, 0.05, 0.05))
	var brass := _mat(Color(0.55, 0.42, 0.22), 0.8, 0.35)
	var w := 0.7
	var h := 0.95
	var d := 0.6
	_part(self, Vector3(w, h, 0.05), Vector3(0, h / 2, -d / 2 + 0.025), steel)
	_part(self, Vector3(0.05, h, d), Vector3(w / 2 - 0.025, h / 2, 0), steel)
	_part(self, Vector3(0.05, h, d), Vector3(-w / 2 + 0.025, h / 2, 0), steel)
	_part(self, Vector3(w, 0.05, d), Vector3(0, h - 0.025, 0), steel)
	_part(self, Vector3(w, 0.08, d), Vector3(0, 0.04, 0), steel)
	_part(self, Vector3(w - 0.1, h - 0.13, 0.02), Vector3(0, h / 2, -d / 2 + 0.06), inner)
	_part(self, Vector3(w - 0.1, 0.02, d - 0.1), Vector3(0, h * 0.5, 0), steel)
	hinge = Node3D.new()
	hinge.position = Vector3(-w / 2, 0, d / 2)
	add_child(hinge)
	_part(hinge, Vector3(w, h, 0.06), Vector3(w / 2, h / 2, 0.03), steel)
	var dial := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.07
	cm.bottom_radius = 0.07
	cm.height = 0.03
	dial.mesh = cm
	dial.material_override = brass
	dial.rotation.x = PI / 2
	dial.position = Vector3(w * 0.68, h * 0.58, 0.075)
	hinge.add_child(dial)
	_part(hinge, Vector3(0.04, 0.16, 0.04), Vector3(w * 0.68, h * 0.36, 0.08), brass)
	_part(hinge, Vector3(0.1, 0.06, 0.01), Vector3(w * 0.68, h * 0.8, 0.065), brass)
	_collide(Vector3(w, h, d + 0.06), Vector3(0, h / 2, 0.03))


func get_prompt(game) -> String:
	if opened:
		return ""
	if locked:
		return "Сейф заперт  (откроют три семёрки на KILLBOX)"
	if kind == "safe":
		return "[E] Открыть сейф"
	return "[E] Открыть ящик"


func interact(game) -> void:
	if opened:
		return
	if locked:
		game.hud.toast("Заперто. Сейф откроют три семёрки на автомате KILLBOX.")
		game.play_at("buzz", global_position, -14.0)
		var tw := create_tween()
		tw.tween_property(hinge, "rotation:y", -0.03, 0.05)
		tw.tween_property(hinge, "rotation:y", 0.0, 0.08)
		return
	opened = true
	collision_layer = 1
	snd.stream = game.snd["creak"][randi() % 2]
	snd.volume_db = -8.0
	snd.pitch_scale = randf_range(0.9, 1.1) * (0.8 if kind == "safe" else 1.0)
	snd.play()
	var tw := create_tween()
	if kind == "safe":
		tw.tween_property(hinge, "rotation:y", -1.9, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		tw.tween_property(hinge, "rotation:x", -1.95, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	get_tree().create_timer(0.35).timeout.connect(_spill.bind(game))


## Открыть без проверки замка (три семёрки на автомате).
func force_open(game) -> void:
	locked = false
	interact(game)


## Закрыть ящик заново (магазин: «Обновить все ящики»). Лут выпадет новый — он выбирается при открытии.
func reset() -> void:
	if kind == "safe" or not opened:
		return
	opened = false
	var tw := create_tween()
	tw.tween_property(hinge, "rotation:x", 0.0, 0.6).set_trans(Tween.TRANS_SINE)


func _spill(game) -> void:
	var items: Array = extra.duplicate()
	if random_loot:
		items += _roll()
	var fwd := global_transform.basis.z
	var pos := global_transform * Vector3(0, 0.45 if kind == "safe" else 0.35, 0.1)
	for it in items:
		var vel := fwd * randf_range(1.2, 2.0) + Vector3(0, randf_range(2.5, 3.5), 0)
		game.spawn_loot(it[0], it[1], pos, vel, 0.8)


func _roll() -> Array:
	var out: Array = [["coin", randi_range(10, 25)]]
	var total := 0
	for e in LOOT:
		total += int(e[1])
	for k in randi_range(3, 5):
		var r := randi() % total
		for e in LOOT:
			r -= int(e[1])
			if r < 0:
				out.append([e[0], randi_range(int(e[2]), int(e[3]))])
				break
	return out
