extends StaticBody3D
## Кустарная турель (промпт 20.11 18:32): стальная труба-самопал на треноге из металлолома, крутится на подшипнике
## из гаек. Сама находит ближайшего врага (группы "enemies" и "mutants") в радиусе RANGE и в прямой видимости
## и стреляет пистолетными патронами — слабо (DMG за выстрел), но без устали. F у турели — зарядить патроны
## из инвентаря (до MAX_AMMO). Общая: строится и в бункере (bunker_home.gd), и где угодно ещё —
## `var t = preload("res://scripts/world/scrap_turret.gd").new(); t.game = game; parent.add_child(t)`.
const FxS := preload("res://scripts/core/fx.gd")
const RANGE := 13.0
const DMG := 7.0
const RATE := 0.85        # секунд между выстрелами
const MAX_AMMO := 40
const TURN := 4.0         # рад/с поворот ствола

static var _shot: AudioStreamWAV

var game
var ammo := 12
var cool := 0.0
var scan := 0.0
var target: Node3D
var head: Node3D          # поворотная часть (ствол)
var flash: OmniLight3D
var voice: AudioStreamPlayer3D


func _ready() -> void:
	_build()
	if _shot == null:
		_shot = preload("res://scripts/gun.gd")._shot_sound()
	voice = AudioStreamPlayer3D.new()
	voice.max_distance = 40.0
	voice.position = Vector3(0, 0.9, 0)
	add_child(voice)


## F у турели — подсказка: сколько патронов.
func get_prompt(_g) -> String:
	return "[F] Кустарная турель — зарядить (%d/%d)" % [ammo, MAX_AMMO]


## Забить патроны из инвентаря до MAX_AMMO.
func interact(g) -> void:
	var have: int = g.inv.count("ammo")
	var n := mini(have, MAX_AMMO - ammo)
	if n <= 0:
		g.play_ui("buzz", -14.0)
		g.hud.toast("Турель полна" if ammo >= MAX_AMMO else "Нет патронов", Color(1.0, 0.6, 0.4))
		return
	g.inv.remove("ammo", n)
	ammo += n
	g.play_ui("click", -6.0, 0.8)
	g.hud.toast("Турель: %d патронов" % ammo, Color(0.8, 0.9, 0.7))


func _physics_process(delta: float) -> void:
	if game == null or head == null:
		return
	cool = maxf(cool - delta, 0.0)
	scan -= delta
	if scan <= 0.0:
		scan = 0.3
		target = _find()
	if target == null or not is_instance_valid(target) or not _alive(target):
		target = null
		head.rotation.y += delta * 0.4   # медленно осматривается
		return
	var to := target.global_position - head.global_position
	var want := atan2(-to.x, -to.z) - global_rotation.y
	var diff := wrapf(want - head.rotation.y, -PI, PI)
	head.rotation.y += clampf(diff, -TURN * delta, TURN * delta)
	if absf(diff) < 0.12 and cool <= 0.0:
		_fire()


func _alive(e: Node) -> bool:
	var s := String(e.get("state"))
	return s != "dead" and s != "rise" and not bool(e.get("calm"))


## Ближайший живой враг в радиусе и в прямой видимости.
func _find() -> Node3D:
	var best: Node3D = null
	var bd := RANGE
	for grp in ["enemies", "mutants"]:
		for e in get_tree().get_nodes_in_group(grp):
			if not (e is Node3D) or not _alive(e):
				continue
			var d: float = (e as Node3D).global_position.distance_to(global_position)
			if d < bd and _sees(e):
				bd = d
				best = e
	return best


func _sees(e: Node3D) -> bool:
	var from := global_position + Vector3(0, 0.95, 0)
	var h := float(e.get("height")) if e.get("height") != null else 1.6
	var q := PhysicsRayQueryParameters3D.create(from, e.global_position + Vector3(0, h * 0.6, 0))
	q.collision_mask = 1
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or hit.collider == e


func _fire() -> void:
	if ammo <= 0:
		cool = 2.0
		game.play_at("click", global_position, -10.0, 1.4)
		return
	ammo -= 1
	cool = RATE
	voice.stream = _shot
	voice.volume_db = -4.0
	voice.pitch_scale = randf_range(1.15, 1.3)   # короткий ствол — звук выше и суше пистолета
	voice.play()
	flash.light_energy = 3.0
	create_tween().tween_property(flash, "light_energy", 0.0, 0.08)
	var dir := (target.global_position - global_position).normalized()
	if randf() < 0.2:
		return   # самопал косит — каждый пятый мимо
	_hurt(target, DMG * randf_range(0.85, 1.15), dir)


## Урон без износа оружия игрока: у хоста/в одиночке — сразу, у клиента — просим хоста (как удар игрока).
func _hurt(e: Node, dmg: float, dir: Vector3) -> void:
	if bool(e.get("net_puppet")):
		if e.has_method("_hit_fx"):
			e._hit_fx(dmg, dir)
		if e.is_in_group("mutants"):
			var vn = get_tree().root.get_node_or_null("VillageNet")
			if vn:
				vn.rpc_id(1, "v_mut_hit", int(e.get_meta("nid", -1)), dmg, dir)
		elif game.net:
			game.net.enemy_hit(e, dmg, dir)
		return
	e.apply_hit(dmg, dir)


func to_save() -> int:
	return ammo


# ---------- модель ----------

func _m(c: Color, rough := 0.7, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _box(p: Node3D, size: Vector3, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	p.add_child(mi)
	return mi


func _cyl(p: Node3D, r: float, h: float, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 10
	mi.mesh = cm
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	p.add_child(mi)
	return mi


## Тренога из ржавых уголков, ящик-«казённик» с изолентой, труба-ствол, банка-магазин сбоку.
func _build() -> void:
	var rust := _m(Color(0.42, 0.26, 0.16), 0.9, 0.3)
	var steel := _m(Color(0.42, 0.43, 0.44), 0.45, 0.7)
	var dark := _m(Color(0.16, 0.16, 0.16), 0.6, 0.5)
	var tape := _m(Color(0.2, 0.3, 0.6), 0.6)
	for k in 3:
		var a := TAU * k / 3.0
		var leg := _box(self, Vector3(0.05, 0.85, 0.05), Vector3(sin(a) * 0.22, 0.38, cos(a) * 0.22), rust)
		leg.rotation = Vector3(cos(a) * 0.45, 0, -sin(a) * 0.45)
	_cyl(self, 0.09, 0.12, Vector3(0, 0.78, 0), dark)          # «подшипник» из гаек
	head = Node3D.new()
	head.position = Vector3(0, 0.88, 0)
	add_child(head)
	_box(head, Vector3(0.2, 0.16, 0.34), Vector3(0, 0.04, 0.02), rust)
	_box(head, Vector3(0.21, 0.04, 0.1), Vector3(0, 0.05, 0.05), tape)
	_cyl(head, 0.035, 0.7, Vector3(0, 0.07, -0.45), steel, Vector3(PI / 2, 0, 0))
	_cyl(head, 0.05, 0.08, Vector3(0, 0.07, -0.78), dark, Vector3(PI / 2, 0, 0))
	_cyl(head, 0.05, 0.12, Vector3(0.15, 0.04, 0.05), _m(Color(0.55, 0.5, 0.3), 0.5, 0.6))   # банка-магазин
	_box(head, Vector3(0.03, 0.06, 0.03), Vector3(0, 0.15, -0.3), dark)                      # мушка
	flash = OmniLight3D.new()
	flash.position = Vector3(0, 0.07, -0.9)
	flash.light_color = Color(1.0, 0.75, 0.4)
	flash.omni_range = 4.0
	flash.light_energy = 0.0
	head.add_child(flash)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.6, 1.05, 0.6)
	cs.shape = bs
	cs.position = Vector3(0, 0.525, 0)
	add_child(cs)
