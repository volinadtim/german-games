extends CharacterBody3D
# Часть mutant.gd: константы, состояние, модели трёх видов, полоска здоровья, плевок.
@warning_ignore("unused_signal")
signal died(m: Node)

const Fx := preload("res://scripts/core/fx.gd")
const Gibs := preload("res://scripts/world/gibs.gd")
const G := 4.0

## Параметры видов: здоровье, скорость, рост, цвет кожи, свечение
const KINDS := {
	"spitter": {"name": "Плевун", "hp": 48.0, "speed": 3.1, "h": 1.6, "skin": Color(0.32, 0.36, 0.22), "glow": Color(0.55, 0.9, 0.2)},
	"charger": {"name": "Таран", "hp": 150.0, "speed": 2.3, "h": 2.15, "skin": Color(0.33, 0.17, 0.12), "glow": Color(1.0, 0.35, 0.1)},
	"stalker": {"name": "Тень", "hp": 62.0, "speed": 5.0, "h": 1.95, "skin": Color(0.08, 0.08, 0.1), "glow": Color(0.75, 0.85, 1.0)},
}
const SIGHT := 15.0
const LEASH := 38.0
const SPIT_DMG := 11.0
const SPIT_CD := 2.3
const CHARGE_DMG := 28.0
const CHARGE_SPEED := 11.5
const SLAM_DMG := 18.0
const STALK_DMG := 9.0
const SWIPE_DMG := 6.0

var game                  # game.gd
var tg                    # цель: game или сетевой игрок (net.gd: RemoteTarget)
var kind := "spitter"     # выставить до add_child
var home := Vector3.ZERO
var net_puppet := false
var net_pos := Vector3.ZERO
var net_rot := 0.0
var hp := 50.0
var max_hp := 50.0
var speed := 3.0
var height := 1.6
var state := "idle"
var st := 0.0
var cool := 0.0
var knock := Vector3.ZERO
var wander_to := Vector3.ZERO
var wander_t := 0.0
var walk_ph := 0.0
var avoid := 0.0          # угол отворота от препятствия
var avoid_t := 0.0
var strafe := 1.0
var charge_dir := Vector3.ZERO
var hits_done := 0
var vis_t := 0.0          # Тень: сколько ещё видна после удара
var alpha := 1.0
var voice_t := 2.0

var vis: Node3D
var torso: Node3D
var head: Node3D
var arms: Array[Node3D] = []
var legs: Array[Node3D] = []
var sack: MeshInstance3D  # Плевун: зоб с кислотой
var mats: Array[StandardMaterial3D] = []
var glow_mat: StandardMaterial3D
var bar: Node3D
var bar_fg: MeshInstance3D
var bar_t := 0.0
var voice: AudioStreamPlayer3D


func _set_state(s: String) -> void:
	state = s
	st = 0.0


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	mats.append(m)
	return m


func _part(parent: Node3D, mesh: Mesh, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _bx(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b


func _sp(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 6
	return s


## Конечность: узел-сустав в pos, кость вниз длиной ln.
func _limb(parent: Node3D, pos: Vector3, ln: float, w: float, m: Material) -> Node3D:
	var j := Node3D.new()
	j.position = pos
	parent.add_child(j)
	_part(j, _bx(Vector3(w, ln, w)), Vector3(0, -ln / 2.0, 0), m)
	return j


func _build() -> void:
	var k: Dictionary = KINDS[kind]
	var skin := _mat(k["skin"])
	var dark := _mat((k["skin"] as Color).darkened(0.4))
	glow_mat = StandardMaterial3D.new()
	glow_mat.albedo_color = k["glow"]
	glow_mat.emission_enabled = true
	glow_mat.emission = k["glow"]
	glow_mat.emission_energy_multiplier = 2.0
	vis = Node3D.new()
	vis.rotation.y = PI   # модель смотрит в +Z, а «вперёд» у врагов — −Z
	add_child(vis)
	torso = Node3D.new()
	vis.add_child(torso)
	head = Node3D.new()
	head.set_meta("headshot", true)   # хэдшот пулей (gun.gd _bullet_hit)
	match kind:
		"spitter":
			# сгорбленный, тонкие лапы, раздутый светящийся зоб под челюстью
			torso.position = Vector3(0, 0.85, 0)
			_part(torso, _bx(Vector3(0.45, 0.55, 0.35)), Vector3(0, 0.25, 0.05), skin, Vector3(0.5, 0, 0))
			head.position = Vector3(0, 0.6, 0.3)
			torso.add_child(head)
			_part(head, _sp(0.16), Vector3.ZERO, skin)
			sack = _part(head, _sp(0.17), Vector3(0, -0.15, 0.08), glow_mat)
			for sx in [-0.09, 0.09]:
				_part(head, _sp(0.035), Vector3(sx, 0.05, 0.14), glow_mat)
			for sx in [-0.28, 0.28]:
				arms.append(_limb(torso, Vector3(sx, 0.4, 0.15), 0.7, 0.08, dark))
				legs.append(_limb(vis, Vector3(sx * 0.6, 0.85, 0), 0.85, 0.11, dark))
		"charger":
			# горой: широкая спина, маленькая голова, огромные руки, костяной нарост-таран на лбу
			torso.position = Vector3(0, 1.0, 0)
			_part(torso, _bx(Vector3(1.05, 0.85, 0.75)), Vector3(0, 0.45, 0), skin, Vector3(0.25, 0, 0))
			_part(torso, _bx(Vector3(0.8, 0.3, 0.5)), Vector3(0, 0.95, -0.1), dark)
			head.position = Vector3(0, 0.75, 0.42)
			torso.add_child(head)
			_part(head, _sp(0.2), Vector3.ZERO, skin)
			_part(head, _bx(Vector3(0.32, 0.16, 0.24)), Vector3(0, 0.12, 0.12), _mat(Color(0.65, 0.6, 0.5)))
			for sx in [-0.08, 0.08]:
				_part(head, _sp(0.03), Vector3(sx, 0.0, 0.18), glow_mat)
			for sx in [-0.62, 0.62]:
				arms.append(_limb(torso, Vector3(sx, 0.75, 0.1), 1.05, 0.26, skin))
				legs.append(_limb(vis, Vector3(sx * 0.45, 1.0, 0), 1.0, 0.24, dark))
		"stalker":
			# высокая тонкая тень, длинные руки до колен, бледные глаза; почти прозрачная, пока крадётся
			torso.position = Vector3(0, 1.1, 0)
			_part(torso, _bx(Vector3(0.36, 0.6, 0.2)), Vector3(0, 0.3, 0), skin)
			head.position = Vector3(0, 0.78, 0.04)
			torso.add_child(head)
			_part(head, _bx(Vector3(0.18, 0.28, 0.2)), Vector3.ZERO, skin)
			for sx in [-0.05, 0.05]:
				_part(head, _sp(0.022), Vector3(sx, 0.03, 0.1), glow_mat)
			for sx in [-0.24, 0.24]:
				arms.append(_limb(torso, Vector3(sx, 0.55, 0), 1.15, 0.07, skin))
				legs.append(_limb(vis, Vector3(sx * 0.5, 1.1, 0), 1.1, 0.09, skin))
			for m in mats:
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# коллизия
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.55 if kind == "charger" else 0.32
	cap.height = height
	cs.shape = cap
	cs.position.y = height / 2.0
	add_child(cs)
	# полоска здоровья
	bar = Node3D.new()
	bar.position.y = height + 0.35
	add_child(bar)
	_bar_quad(Color(0, 0, 0, 0.6), Vector2(0.8, 0.09), 0.0)
	bar_fg = _bar_quad(Color(0.85, 0.25, 0.15), Vector2(0.76, 0.06), 0.001)
	bar.visible = false


func _bar_quad(col: Color, size: Vector2, z: float) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	q.center_offset = Vector3(0, 0, z)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.albedo_color = col
	q.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bar.add_child(mi)
	return mi


## Прозрачность Тени (0 — невидима).
func _set_alpha(a: float) -> void:
	if kind != "stalker":
		return
	alpha = a
	for m in mats:
		var c := m.albedo_color
		c.a = a
		m.albedo_color = c
	glow_mat.emission_energy_multiplier = lerpf(0.6, 2.0, a)


## Кислотный плевок: светящийся комок летит по дуге; real — с уроном (у хоста или без сети).
func _spit(from: Vector3, vel: Vector3, real: bool) -> void:
	var g := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _sp(0.11)
	mi.material_override = glow_mat
	g.add_child(mi)
	var lt := OmniLight3D.new()
	lt.light_color = KINDS["spitter"]["glow"]
	lt.light_energy = 0.8
	lt.omni_range = 2.5
	g.add_child(lt)
	game.add_child(g)
	g.global_position = from
	var v := vel
	var life := 0.0
	var me := self
	var t: SceneTree = game.get_tree()
	while is_instance_valid(g) and life < 3.0:
		await t.physics_frame
		if not is_instance_valid(g) or not is_instance_valid(game):
			return
		var dt := 1.0 / Engine.physics_ticks_per_second
		life += dt
		v.y -= 9.0 * dt
		var np := g.global_position + v * dt
		var q := PhysicsRayQueryParameters3D.create(g.global_position, np)
		q.collision_mask = 1
		if is_instance_valid(me):
			q.exclude = [me.get_rid()]
		var hit := g.get_world_3d().direct_space_state.intersect_ray(q)
		if real and is_instance_valid(me) and me.tg and me.tg.alive:
			var pp: Vector3 = me.tg.player.global_position + Vector3(0, 1.0, 0)
			var on_me: bool = hit and hit.collider == me.tg.player
			if on_me or np.distance_to(pp) < 0.65:
				me.tg.damage_player(SPIT_DMG, g.global_position)
				hit = {"position": np}
		if hit:
			Fx.dust_burst(game, hit.position, Color(0.45, 0.8, 0.2), 14)
			g.queue_free()
			return
		g.global_position = np
	if is_instance_valid(g):
		g.queue_free()
