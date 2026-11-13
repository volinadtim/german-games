extends StaticBody3D
## Ящик с лутом / сейф (сундуки). E — открыть: крышка (или дверца сейфа) откидывается со скрипом,
## лут вылетает наружу и подбирается, когда подойдёшь. Лут — случайный из таблицы LOOT + гарантированный extra.
## Интерфейс взаимодействия (его дёргает game.gd): get_prompt(game) -> String, interact(game).

const Fx := preload("res://fx.gd")

## [предмет, вес, мин, макс]
const LOOT := [
	["bandage", 16, 1, 3],
	["medkit", 7, 1, 1],
	["pills", 10, 1, 2],
	["canned", 9, 1, 2],
	["water", 12, 1, 2],
	["rusk", 14, 1, 4],
	["choco", 7, 1, 1],
	["soda", 6, 1, 1],
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

var kind := "crate"            # crate | safe | storage (сундук-хранилище, промпт 00:08)
var extra: Array = []          # гарантированный лут: [[id, n], ...]
var locked := false            # сейф: открывается только тремя семёрками на автомате (force_open)
var random_loot := true
var opened := false
var contents: Array = []       # что лежит внутри: [[id, n], ...] (окно лута, промпт 00:07)
var game                       # game.gd — для ломания ящика
const CRATE_HP := 30.0
var hp := CRATE_HP
var broken := false
var hinge: Node3D
var snd: AudioStreamPlayer3D


func _ready() -> void:
	if kind == "safe":
		_build_safe()
	else:
		_build_crate()
	if kind == "storage":
		random_loot = false
		# сундук: окованный, с навесным замком — отличается от ящиков
		_part(self, Vector3(0.12, 0.14, 0.03), Vector3(0, 0.33, 0.29), _mat(Color(0.55, 0.42, 0.2), 0.8, 0.35))
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
	if kind == "storage":
		return "[E] Сундук (%d)" % contents.size() if not contents.is_empty() else "[E] Сундук"
	if broken:
		return ""
	if opened:
		return "[E] Обыскать (%d)" % contents.size() if not contents.is_empty() else ""
	if locked:
		return "Сейф заперт  (откроют три семёрки на KILLBOX)"
	if kind == "safe":
		return "[E] Открыть сейф"
	return "[E] Открыть ящик"


func interact(game) -> void:
	if kind == "storage":
		if not opened:
			opened = true
			snd.stream = game.snd["creak"][randi() % 2]
			snd.volume_db = -16.0
			snd.play()
			create_tween().tween_property(hinge, "rotation:x", -1.95, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		game.open_loot(self)
		return
	if opened:
		if not contents.is_empty() and game.has_method("open_loot"):
			game.open_loot(self)
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
	snd.volume_db = -15.0
	snd.pitch_scale = randf_range(0.9, 1.1) * (0.8 if kind == "safe" else 1.0)
	snd.play()
	var tw := create_tween()
	if kind == "safe":
		tw.tween_property(hinge, "rotation:y", -1.9, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		tw.tween_property(hinge, "rotation:x", -1.95, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_fill()
	if not silent_open and game.has_method("open_loot"):
		get_tree().create_timer(0.35).timeout.connect(game.open_loot.bind(self))


var silent_open := false


## Набрать содержимое: гарантированный лут + случайный.
func _fill() -> void:
	contents = []
	for it in extra:
		contents.append([String(it[0]), int(it[1])])
	if random_loot:
		for it in _roll():
			contents.append([String(it[0]), int(it[1])])


## Открыть без проверки замка (три семёрки на автомате): дверца открывается, лут ждёт внутри.
func force_open(game) -> void:
	locked = false
	silent_open = true
	interact(game)
	silent_open = false


## Состояние из сохранения: открыт / сломан — без звука и без выпадения лута.
func restore(was_opened: bool, was_broken: bool, items: Array = []) -> void:
	contents = []
	for it in items:
		contents.append([String(it[0]), int(it[1])])
	if was_broken and kind != "safe":
		broken = true
		opened = true
		for c in get_children():
			if c is Node3D and not c is AudioStreamPlayer3D:
				c.visible = false
			if c is CollisionShape3D:
				c.set_deferred("disabled", true)
	elif was_opened:
		opened = true
		locked = false
		if kind == "safe":
			hinge.rotation.y = -1.9
		else:
			hinge.rotation.x = -1.95


## Закрыть ящик заново (магазин: «Обновить все ящики»). Лут выпадет новый — он выбирается при открытии.
func reset() -> void:
	if broken:
		broken = false
		hp = CRATE_HP
		for c in get_children():
			if c is Node3D and not c is AudioStreamPlayer3D:
				c.visible = true
			if c is CollisionShape3D:
				c.set_deferred("disabled", false)
		hinge.rotation = Vector3.ZERO
		opened = false
		contents = []
		return
	if kind == "safe" or not opened:
		return
	opened = false
	contents = []
	var tw := create_tween()
	tw.tween_property(hinge, "rotation:x", 0.0, 0.6).set_trans(Tween.TRANS_SINE)


## Удар кулаком или оружием: ящик трещит, летят щепки; на нуле разваливается —
## выпадает его лут (если не открыт) и 1–2 деревяшки. Сейф не ломается.
## Окно сундука закрыто — крышка опускается.
func on_loot_closed() -> void:
	if kind != "storage":
		return
	opened = false
	create_tween().tween_property(hinge, "rotation:x", 0.0, 0.5).set_trans(Tween.TRANS_SINE)


func take_hit(dmg: float, dir: Vector3) -> void:
	if kind == "safe" or kind == "storage" or broken:
		return
	if game:
		game.weapon_hit()
	hp -= dmg
	Fx.dust_burst(get_parent(), global_position + Vector3(0, 0.35, 0) - dir * 0.3, Color(0.42, 0.29, 0.16), 10)
	var p0 := position
	var tw := create_tween()
	tw.tween_property(self, "position", p0 + Vector3(dir.x, 0, dir.z).normalized() * 0.03, 0.04)
	tw.tween_property(self, "position", p0, 0.08)
	if game:
		game.play_at("creak", global_position, -18.0, 1.8)
	if hp <= 0.0:
		_break()


func _break() -> void:
	broken = true
	for c in get_children():
		if c is Node3D and not c is AudioStreamPlayer3D:
			c.visible = false
		if c is CollisionShape3D:
			c.set_deferred("disabled", true)
	Fx.dust_burst(get_parent(), global_position + Vector3(0, 0.3, 0), Color(0.45, 0.31, 0.17), 34)
	if game:
		game.play_at("thud", global_position, -6.0, 1.5)
		if not opened:
			_fill()
		_spill(game)
		contents = []
		game.spawn_loot("wood", randi_range(1, 2), global_position + Vector3(0, 0.4, 0), Vector3(0, 2.2, 0), 1.2)
	opened = true


func _spill(game) -> void:
	var items: Array = contents
	var fwd := global_transform.basis.z
	var pos := global_transform * Vector3(0, 0.45 if kind == "safe" else 0.35, 0.1)
	for it in items:
		var vel := fwd * randf_range(1.2, 2.0) + Vector3(0, randf_range(2.5, 3.5), 0)
		game.spawn_loot(it[0], it[1], pos, vel, 0.8)


## За раз из ящика — 3–5 разных позиций (монеты всегда одна из них), в каждой немного штук:
## чаще всего минимум из таблицы. Что и с какими шансами выпадает — по-прежнему таблица LOOT.
func _roll() -> Array:
	var positions := randi_range(3, 5)
	var out: Array = [["coin", randi_range(3, 8)]]
	var total := 0
	for e in LOOT:
		total += int(e[1])
	var tries := 0
	while out.size() < positions and tries < 60:
		tries += 1
		var r := randi() % total
		for e in LOOT:
			r -= int(e[1])
			if r < 0:
				var id: String = e[0]
				var dup := id == "coin"
				for o in out:
					dup = dup or o[0] == id
				if not dup:
					var cnt := int(e[2]) if randf() < 0.75 else mini(int(e[2]) + 1, int(e[3]))
					out.append([id, cnt])
				break
	return out
