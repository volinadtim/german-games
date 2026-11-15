extends RigidBody3D
## Предмет на полу (тестовые механики): физическое тельце. Подбирается на E издалека (до ~2.8 м):
## game.gd ищет лежащий предмет под прицелом, подсказка «[E] Взять: …», предмет летит к игроку.
## И любые вещи подбираются сами, если встать на них / подойти ближе 1 м (промпт 18:44) — сразу, без задержки.
## Выброшенное самим игроком (и не взятое из окна лута) само не подбирается никогда — только по E (промпт 19:03).
## Лежит 3.5 минуты, последние 5 с мигает и исчезает; ключ от машины не исчезает (промпт 19:04).
## Сумка полна — сообщение не чаще раза в 3 с (game.collect).

const Items := preload("res://scripts/items.gd")
const PickupMesh := preload("res://scripts/pickup_mesh.gd")
const REACH := 3.0   # дальность подбора на E, м

var game  # game.gd
var id := "coin"
var n := 1
var age := 0.0
var need_leave := false   # выбросил сам игрок — сам не подбирается никогда, только по E (промпт 19:03; в сейве)
const LIFE := 210.0       # лежит на полу 3.5 мин, потом исчезает (промпт 19:04; ключ от машины — никогда)
const FADE := 5.0         # последние секунды мигает
var life := LIFE          # сколько осталось (в сейве)
var taken := false   # уже летит к игроку (в сохранение не попадает)
var model: Node3D
var model_base := Vector3.ZERO   # положение визуала без подъёма
var lift := 0.0                  # подъём визуала над полом — по мировой вертикали, как бы предмет ни лёг
var box: CollisionShape3D
var settled := false             # улёгся: выровнен на грань по полу и заморожен (не качается, не толкается)
var slow_t := 0.0
var last_ok := Vector3.INF       # последняя точка, где под предметом была земля (на случай провала сквозь неё)
var ok_check := 0


func _ready() -> void:
	add_to_group("pickup")
	collision_layer = 4
	collision_mask = 1
	mass = 0.2
	continuous_cd = false
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.1      # было 0.25 — плоские вещи от упругости бесконечно качались на полу
	pm.friction = 0.9
	physics_material_override = pm
	angular_damp = 2.5   # гасит покачивание, кувыркаться в полёте всё равно успевает
	linear_damp = 0.3
	var made: Array = PickupMesh.make(id)
	model = made[0]
	add_child(model)
	# PickupMesh уже поднял визуал по своей оси; запоминаем подъём и дальше держим его по мировой вертикали
	lift = PickupMesh.LIFT_FLAT if id in PickupMesh.FLAT else PickupMesh.LIFT
	model_base = model.position - Vector3(0, lift, 0)
	var s: Vector3 = made[1]
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	var pad := Vector3.ONE * PickupMesh.PAD * 2.0
	bs.size = Vector3(maxf(s.x, 0.04), maxf(s.y, 0.03), maxf(s.z, 0.04)) + (Vector3.ZERO if model is Sprite3D else pad)
	cs.shape = bs
	if model is Sprite3D:
		cs.position.y = s.y * 0.5
	add_child(cs)
	box = cs
	# игрок не толкает предметы (раньше мог запихать их в стену): тело игрока для них «прозрачно»
	if game != null and game.player != null:
		add_collision_exception_with(game.player)
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC


func _physics_process(delta: float) -> void:
	age += delta
	# непрерывная проверка столкновений — только в быстром полёте (чтобы не пролететь сквозь землю);
	# на полу она заставляла тонкие вещи (осколок стекла) бесконечно качаться и ползти (промпт 18:29)
	continuous_cd = linear_velocity.length() > 2.5
	if not taken and not settled:
		# лёг на бок — визуал всё равно приподнят вверх по миру (тело без масштаба: inverse = transposed)
		model.position = model_base + global_transform.basis.transposed() * Vector3(0, lift, 0)
		slow_t = slow_t + delta if linear_velocity.length() < 0.6 else 0.0
		if age > 0.3 and (slow_t > 0.25 or age > 4.0):
			_settle()
		_guard_fall()
	if not taken and id != "car_key":
		life -= delta
		if life <= 0.0:
			queue_free()
			return
		if life < FADE:
			# мигает всё чаще перед исчезновением
			model.visible = fmod(life, 0.1 + 0.3 * life / FADE) > 0.08
	# подбор вплотную — каждый кадр по расстоянию, сразу (стоишь рядом — вещь подлетит, едва упав)
	if taken or need_leave or game == null or not game.alive or age < 0.15:
		return
	var pp: Vector3 = game.player.global_position
	var d := Vector2(pp.x - global_position.x, pp.z - global_position.z).length()
	var dy := global_position.y - pp.y
	if d < 1.0 and dy > -0.4 and dy < 1.9:
		if game.net and game.net.take(self):
			return
		var left: int = game.collect(id, n, self)
		if left <= 0:
			_fly_to(game)
		else:
			n = left


## Проскочил сквозь землю (быстрое падение тонкой вещи на склон поляны) — вернуть туда, где земля была под ним.
func _guard_fall() -> void:
	if settled:
		return
	ok_check += 1
	if last_ok != Vector3.INF and global_position.y < last_ok.y - 3.0:
		global_position = last_ok + Vector3(0, 0.25, 0)
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		return
	if ok_check % 5 != 0:
		return
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.05, 0), global_position - Vector3(0, 2.0, 0))
	q.collision_mask = 1
	if game != null and game.player != null:
		q.exclude = [game.player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		last_ok = global_position


## Уложить на пол и заморозить: ближайшая к вертикали ось коробки становится строго вертикальной (лежит на грани),
## низ коробки — на 1 мм над полом под предметом. Так нет ни покачивания и ползания тонких вещей, ни дёрганья,
## ни утопания в пол (физика Godot разрешает телам проваливаться в пол до 1 см) — промпты 18:29 / 18:36.
func _settle() -> void:
	var b := global_transform.basis.orthonormalized()
	var best := 1
	for i in 3:
		if absf(b[i].y) > absf(b[best].y):
			best = i
	var up := Vector3(0, signf(b[best].y) if b[best].y != 0.0 else 1.0, 0)
	var nb := (Basis(Quaternion(b[best].normalized(), up)) * b).orthonormalized()
	var center := global_position + nb * box.position
	var q := PhysicsRayQueryParameters3D.create(center + Vector3(0, 0.3, 0), center - Vector3(0, 0.6, 0))
	q.collision_mask = 1
	if game != null and game.player != null:
		q.exclude = [game.player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		if age > 4.0:
			slow_t = 0.0   # висит над пустотой (или ещё падает) — ждём дальше
			age = 0.31
		return
	if (hit.normal as Vector3).y < 0.6:
		return   # упёрся в стену/крутой склон — пусть физика ещё подвигает
	var h: Vector3 = (box.shape as BoxShape3D).size * 0.5
	var below := absf(nb[0].y) * h.x + absf(nb[1].y) * h.y + absf(nb[2].y) * h.z
	var dy: float = hit.position.y + 0.001 - (center.y - below)
	if absf(dy) > 0.08:
		return   # далеко от пола — ещё не улёгся
	settled = true
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = Transform3D(nb, global_position + Vector3(0, dy, 0))
	model.position = model_base + nb.transposed() * Vector3(0, lift, 0)


func get_prompt(_g) -> String:
	if taken:
		return ""
	var nm := Items.item_name(id)
	return "[E] Взять: %s ×%d" % [nm, n] if n > 1 else "[E] Взять: %s" % nm


## E: в инвентарь. Не влезло ничего — сообщение «Инвентарь полон», предмет остаётся лежать.
func interact(g) -> void:
	if taken:
		return
	g.full_toast_t = 0.0   # на нажатие E сообщение о полной сумке показываем всегда
	if g.net and g.net.take(self):
		return
	var left: int = g.collect(id, n, self)
	if left >= n:
		return
	if left > 0:
		n = left   # взяли часть — остаток лежит
		return
	_fly_to(g)


## Предмет коротко летит к груди игрока, уменьшаясь, и исчезает.
func _fly_to(g, to: Node3D = null) -> void:
	taken = true
	remove_from_group("pickup")
	collision_layer = 0
	collision_mask = 0
	freeze = true
	var tw := create_tween().set_parallel()
	if to == null:
		to = g.player   # в сети — может лететь к другому игроку (net.gd)
	var target: Vector3 = to.global_position + Vector3(0, 1.1, 0)
	tw.tween_method(func(k: float) -> void:
		if is_instance_valid(to):
			target = to.global_position + Vector3(0, 1.1, 0)
		global_position = global_position.lerp(target, k), 0.0, 1.0, 0.22).set_ease(Tween.EASE_IN)
	tw.tween_property(model, "scale", model.scale * 0.3, 0.22)
	tw.chain().tween_callback(queue_free)
