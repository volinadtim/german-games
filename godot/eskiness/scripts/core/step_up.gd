extends RefCounted
## Ступеньки для CharacterBody3D (промпт 03:51): невысокие уступы (ступени, бордюры, пороги, обломки
## до ~0.4 м) тело переступает само, без прыжка, а со ступеньки спускается без падения.
## Подъём: тест движения вперёд (упёрлись в стенку, а не в склон) → вверх → вперёд на радиус → вниз до опоры.
## Стены выше MAX_H не трогаем — тест вниз возвращает на исходный пол, подъёма нет.
## Возвращают смещение по высоте, чтобы камеру/модель можно было сгладить.

const MAX_H := 0.4
const FWD := 0.35        # насколько заглядываем вперёд с поднятой позиции (чуть больше радиуса капсулы)
const WALL_NY := 0.7     # нормаль с y меньше — стенка/уступ; больше — пол или склон (его ведёт move_and_slide)


## До move_and_slide: если впереди уступ, поднимает тело на его высоту. Возвращает подъём (м) или 0.
static func step_up(b: CharacterBody3D, grounded: bool, delta: float, max_h := MAX_H) -> float:
	if not grounded or b.velocity.y > 0.01:
		return 0.0
	var hv := Vector3(b.velocity.x, 0.0, b.velocity.z)
	if hv.length() < 0.2:
		return 0.0
	var dir := hv.normalized()
	var xf := b.global_transform
	var r := KinematicCollision3D.new()
	# 1. впереди препятствие с крутой гранью
	if not b.test_move(xf, dir * (hv.length() * delta + 0.04), r, 0.001, false, 4):
		return 0.0
	var wall := false
	for i in r.get_collision_count():
		if r.get_normal(i).y < WALL_NY and r.get_normal(i).dot(dir) < -0.3:
			wall = true
	if not wall:
		return 0.0
	# 2. вверх (под низким потолком — сколько получится)
	var up := max_h
	if b.test_move(xf, Vector3.UP * max_h, r):
		up = r.get_travel().y
	if up < 0.05:
		return 0.0
	xf.origin.y += up
	# 3. вперёд над уступом
	var fwd := dir * FWD
	if b.test_move(xf, fwd, r):
		fwd = r.get_travel()
	if fwd.dot(dir) < 0.08:
		return 0.0
	xf.origin += fwd
	# 4. вниз до опоры
	if not b.test_move(xf, Vector3.DOWN * (up + 0.02), r):
		return 0.0
	if r.get_normal().y < 0.5:
		return 0.0
	var h := up + r.get_travel().y
	if h < 0.03 or h > max_h:
		return 0.0
	b.global_position.y += h + 0.005
	return h


## После move_and_slide: шли по полу и сошли с уступа (не прыжок) — сразу ставим на пол ниже,
## если он не дальше max_h. Возвращает спуск (м) или 0.
static func step_down(b: CharacterBody3D, was_grounded: bool, max_h := MAX_H) -> float:
	if not was_grounded or b.is_on_floor() or b.velocity.y > 0.01:
		return 0.0
	var r := KinematicCollision3D.new()
	if not b.test_move(b.global_transform, Vector3.DOWN * max_h, r):
		return 0.0
	if r.get_normal().y < WALL_NY:
		return 0.0
	var d := -r.get_travel().y
	if d < 0.01:
		return 0.0
	b.global_position.y -= d
	b.velocity.y = 0.0
	b.apply_floor_snap()
	return d
