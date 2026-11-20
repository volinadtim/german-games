extends "res://scripts/enemy/enemy_combat.gd"
const StepUp := preload("res://scripts/core/step_up.gd")
## Враг «Бетонник» (боёвка): сутулая фигура из бетона с тлеющими глазами и торчащей арматурой.
## Заметил игрока (видит и ближе 9 м) — идёт к нему, обходя стены через проёмы, замахивается и бьёт.
## На поверхности (спавн выше уровня земли) — бродит по поляне и гонится напрямую.
## От ударов кулаком отлетает и сбивается, умирая — рассыпает монеты и иногда предмет.
## Интерфейс урона: take_hit(урон, направление) — его вызывает player.gd при попадании.
## Два вида (kind, промпт 14.11 18:08): "heavy" — бетонник, медленный и тяжёлый;
## "fast" — «Шныга»: низкий худой, бегает рывками-прыжками, визжит, бьёт слабее и ближе, хлипкий.


func _apply_kind() -> void:
	if kind == "fast":
		speed = 4.3          # в среднем: быстрее шага игрока (3.4), медленнее бега (5.4)
		attack_range = 0.95
		hit_range = 1.3
		damage = 8.0         # было 6
		max_hp = 34.0        # было 43 (−20%, промпт 14.11 20:33)
		windup_t = 0.3
		cool_t = 0.8
		height = 1.45
	hp = max_hp


func _ready() -> void:
	tg = game
	_apply_kind()
	add_to_group("enemies")
	ability_cd = randf_range(3.0, 6.0)
	avoid_side = -1.0 if randf() < 0.5 else 1.0
	home = global_position
	target = home
	surface = home.y > Surface.G - 1.0
	wander_t = randf_range(0.0, 3.0)
	floor_snap_length = 0.3
	_build()
	voice = AudioStreamPlayer3D.new()
	voice.unit_size = 2.0
	voice.max_distance = 20.0   # не слышно через пол-уровня (промпт 17.11 02:50)
	voice.position.y = height * 0.8
	add_child(voice)
	body_snd = AudioStreamPlayer3D.new()
	body_snd.unit_size = 2.0
	body_snd.max_distance = 16.0
	body_snd.position.y = 1.0
	add_child(body_snd)


func _physics_process(delta: float) -> void:
	if net_puppet:
		_puppet_tick(delta)
		return
	if game.net:
		tg = game.net.pick_target(self)
	elif game.has_meta("split"):
		tg = game.get_meta("split").pick_target(self)   # сплитскрин: ближайший из двух игроков
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	st += delta
	cool -= delta
	ability_cd -= delta
	knock = knock.lerp(Vector3.ZERO, 1.0 - exp(-6.0 * delta))
	bar_t -= delta
	bar.visible = state != "dead" and bar_t > 0.0

	var want := Vector3.ZERO
	var ppos: Vector3 = tg.player.global_position
	var to := ppos - global_position
	to.y = 0.0
	var d := to.length()
	# цель сидит в машине: достаём через кузов (дальше обычного) и агримся на шум мотора
	var car_t = _car_tgt()
	var ar: float = attack_range + (1.2 if car_t != null else 0.0)
	match state:
		"dead":
			pass
		"crawl":
			want = _crawl(delta, d, ppos)
		"idle":
			if hunter and tg.alive:
				_set_state("chase")
			elif car_t != null and tg.alive and d < (22.0 if _car_noisy(car_t) else 11.0) 					and (not surface or Surface.on_meadow(ppos)):
				_set_state("chase")   # машина рядом (и тем более гудит) — идёт к ней
				_growl()
			elif (not surface or Surface.on_meadow(ppos)) and _notice(ppos, d, delta):
				_set_state("chase")
				_growl()
			elif (not surface or Surface.on_meadow(ppos)) and _hears(ppos, d):
				_heard(ppos, d)
			elif surface and _zone(global_position) != 0:
				_set_state("return")
			elif surface:
				want = _wander(delta)
			elif Vector2(home.x - global_position.x, home.z - global_position.z).length() > 0.6:
				want = _steer(home, delta) * speed * 0.6
		"chase":
			growl_t -= delta
			if growl_t <= 0.0:
				_growl()
			# в погоне видит дальше; не видит и не слышит — идёт по памяти (last_known)
			var sensed := hunter or d < NEAR_FEEL or _sees(ppos, d, SIGHT * 1.6) or _hears(ppos, d)
			if sensed:
				last_known = ppos
				mem_t = 0.0
			else:
				mem_t += delta
			if surface and not hunter:
				# видит — агро держится; не видит дольше LOSE_T — сдаётся
				# пока идёт в зону игрока (лестница, бункер), «потерю» не считаем — он идёт по следу
				if sensed:
					lost_t = 0.0
					blind_t = 0.0
				else:
					blind_t += delta
					if _zone(global_position) == _zone(ppos):
						lost_t += delta
			if not tg.alive or (not hunter and not surface and global_position.distance_to(home) > LEASH) 					or (surface and not hunter and (lost_t > LOSE_T or blind_t > CHASE_MAX or (_zone(ppos) == 0 and not _in_bounds(ppos) and d > 10.0))):
				lost_t = 0.0
				blind_t = 0.0
				_set_state("return" if surface and _zone(global_position) != 0 else "idle")
			elif not sensed:
				var lk := Vector2(last_known.x - global_position.x, last_known.z - global_position.z).length()
				if lk < 1.0 or mem_t > MEM_T:
					# дошёл до места, где видел последний раз, — никого: озирается и уходит (investigate)
					probe = last_known
					probe_wait = 0.0
					think = 0.0
					_set_state("investigate")
				else:
					want = _steer(last_known, delta) * speed * 0.9
			elif _try_ability(d, ppos):
				pass
			else:
				var goal := _chase_goal(ppos, d)
				var flanking := goal.distance_to(ppos) > 0.1
				# заходит сбоку — не бьёт, пока не встанет на свою точку
				var in_place := not flanking or Vector2(goal.x - global_position.x, goal.z - global_position.z).length() < 0.45
				if d < ar and cool <= 0.0 and in_place:
					_set_state("windup")
				elif d > ar * 0.8 or not in_place:
					want = _steer(goal, delta) * speed * _dash(delta)
				else:
					_face(to, delta)
		"windup":
			_face(to, delta)
			if st > windup_t:
				_strike(d, to)
				_set_state("recover")
		"recover":
			if st > (0.7 if kind == "heavy" else 0.45):
				_set_state("chase")
		"leap_prep":
			# Шныга присела перед прыжком (телеграф)
			_face(to, delta)
			if st > 0.3:
				var lead: Vector3 = ppos + tg.player.velocity * 0.35
				var fl := lead - global_position
				fl.y = 0.0
				# в бункере — низкий прыжок (макушка ≈ 1.8 м: не в потолок и не в притолоку)
				var low := _zone(global_position) == 2
				leap_vel = (fl / (0.36 if low else 0.5)).limit_length(13.0)
				velocity.y = 3.6 if low else 5.0
				leap_hit = false
				_set_state("leap")
		"leap":
			want = leap_vel
			if not leap_hit and d < 1.15 and absf(ppos.y - global_position.y) < 1.5:
				leap_hit = true
				tg.damage_player(LEAP_DMG, global_position)
			if st > 0.15 and is_on_floor():
				_set_state("leap_rec")
		"leap_rec":
			# приземлилась — короткая уязвимость: стоит, не бьёт
			if st > 0.8:
				_set_state("chase")
		"throw":
			# бетонник: замах и бросок камня
			_face(to, delta)
			if st > 0.6 and not thrown:
				thrown = true
				if not _throw_rock(ppos):
					ability_cd = 3.0   # дуга перекрылась за время замаха — не бросает
			if st > 1.0:
				_set_state("chase")
		"investigate":
			# услышал камень (hear_stone): идёт к месту падения, стоит там, озирается, потом назад
			if (not surface or Surface.on_meadow(ppos) or _zone(global_position) == _zone(ppos)) and _notice(ppos, d, delta):
				_set_state("chase")
				_growl()
			elif (not surface or Surface.on_meadow(ppos) or _zone(global_position) == _zone(ppos)) and _hears(ppos, d) and probe.distance_to(ppos) > 1.5:
				_heard(ppos, d)
			elif st > 20.0 or probe_wait > 2.6:
				_set_state("return" if surface and _zone(global_position) != 0 else "idle")
			elif probe_wait <= 0.0 and Vector2(probe.x - global_position.x, probe.z - global_position.z).length() > 0.9:
				want = _steer(probe, delta) * speed * 0.75
			else:
				probe_wait += delta
				rotation.y += sin(probe_wait * 2.4) * 1.6 * delta
		"stagger":
			if st > (0.4 if kind == "heavy" else 0.3):
				_set_state("chase")
		"return":
			# назад на поляну: через лестницу и будку; увидел игрока — снова в погоню
			if _notice(ppos, d, delta):
				_set_state("chase")
				_growl()
			elif _hears(ppos, d):
				_heard(ppos, d)
			elif _zone(global_position) == 0:
				wander_t = 0.0
				_set_state("idle")
			else:
				want = _steer(Vector3(25.0, Surface.G, 0.0), delta) * speed * 0.7
	if surface and not hunter and state != "leap":
		want = _keep_in(want)   # за пределы первой локации не выходит (промпт 18.11 01:01)
	_check_stuck(delta, want)
	if surface and state == "idle" and want != Vector3.ZERO and Surface.in_hut(global_position + want.normalized() * 0.7, 0.3):
		want = Vector3.ZERO
	velocity.x = want.x + knock.x
	velocity.z = want.z + knock.z
	var was_floor := is_on_floor()
	vis_step -= StepUp.step_up(self, was_floor, delta)   # ступеньки (промпт 03:51)
	move_and_slide()
	vis_step += StepUp.step_down(self, was_floor)
	vis_step = clampf(vis_step, -0.5, 0.5) * exp(-10.0 * delta)
	_animate(delta, want.length())
	_footsteps(delta)


## Услышал игрока: рядом — сразу погоня, издалека — идёт проверить место шума.
func _heard(ppos: Vector3, d: float) -> void:
	if d < 3.0:
		_set_state("chase")
		_growl()
		return
	probe = ppos
	probe_wait = 0.0
	think = 0.0
	if state != "investigate":
		_set_state("investigate")
	else:
		st = 0.0


## Заблудший (world/intro.gd, начало новой игры): ползёт по crawl_path и в конце замирает, игрока не ищет.
## Замечает, только если тот шумит рядом (идёт не вприсядку ближе 2.5 м, бежит — 5 м), подошёл вплотную или стоит перед глазами.
const CRAWL_SPEED := 0.6
var crawl_path: Array = []
var crawl_i := 0


func _crawl(delta: float, d: float, ppos: Vector3) -> Vector3:
	if crawl_wait:
		return Vector3.ZERO
	var pl = tg.player
	var pv := Vector2(pl.velocity.x, pl.velocity.z).length()
	var loud_r := 0.0 if bool(pl.get("crouched")) or pv < 0.6 else (5.0 if pv > 4.0 else 2.5)   # шаг 2.5 м, бег 5 м
	var fwd := -global_transform.basis.z
	var to := ppos - global_position
	to.y = 0.0
	var seen := d < 5.0 and fwd.dot(to.normalized()) > 0.7
	if not calm and tg.alive and (d < loud_r or d < 0.5 or seen) and _clear(global_position, ppos):
		_set_state("chase")
		_growl()
		return Vector3.ZERO
	if crawl_i >= crawl_path.size() or (crawl_stop > 0.0 and crawl_t >= crawl_stop):
		# остановился: стоит, покачивается и отворачивается от игрока — ждёт
		var away := global_position - ppos
		away.y = 0.0
		rotation.y = lerp_angle(rotation.y, atan2(-away.x, -away.z), 1.0 - exp(-1.5 * delta))
		return Vector3.ZERO
	crawl_t += delta
	var goal: Vector3 = crawl_path[crawl_i]
	if Vector2(goal.x - global_position.x, goal.z - global_position.z).length() < 0.35:
		crawl_i += 1
		return Vector3.ZERO
	return _steer(goal, delta) * crawl_speed


## Сделать охотником (наказание за мухлёж): гонится всегда, без привязи к дому и поляне.
func make_hunter() -> void:
	hunter = true
	surface = false
	_set_state("chase")
	_growl()


# ---------- сеть: копия врага у клиента ----------

## Новое состояние с хоста: позиция, поворот, состояние ИИ, здоровье.
func net_apply(pos: Vector3, rot: float, s: String, h: float) -> void:
	net_pos = pos
	net_rot = rot
	if h < hp - 0.01:
		bar_t = 4.0
	hp = h
	if bar_fg:
		bar_fg.scale.x = maxf(hp / max_hp, 0.0)
	if s == state:
		return
	if s == "dead":
		var back := global_transform.basis.z
		_die(Vector3(back.x, 0, back.z).normalized())
		return
	if s == "chase" and state in ["idle", "return"]:
		_growl()
	elif s == "recover" and state == "windup":
		_play(body_snd, game.snd["whoosh"], -6.0 if kind == "heavy" else -9.0, 0.7 if kind == "heavy" else 1.15)
	_set_state(s)


func _puppet_tick(delta: float) -> void:
	if state == "dead":
		return
	st += delta
	bar_t -= delta
	bar.visible = bar_t > 0.0
	knock = Vector3.ZERO
	var old := global_position
	if global_position.distance_to(net_pos) > 4.0:
		global_position = net_pos
	else:
		global_position = global_position.lerp(net_pos, 1.0 - exp(-12.0 * delta))
	rotation.y = lerp_angle(rotation.y, net_rot, 1.0 - exp(-12.0 * delta))
	velocity = (global_position - old) / maxf(delta, 0.001)
	var spd := Vector2(velocity.x, velocity.z).length()
	if kind == "fast" and state == "chase":
		_dash(delta)
	_animate(delta, spd)
	_footsteps(delta)
