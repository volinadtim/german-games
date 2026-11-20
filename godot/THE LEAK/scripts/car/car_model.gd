extends StaticBody3D
# Часть car.gd: константы, состояние, 3D-модель машины, материалы и примитивы, дым.
const Surface := preload("res://scripts/level/surface.gd")
const WornMetal := preload("res://shaders/worn_metal.gdshader")
const Sfx2 := preload("res://scripts/core/sfx_extra.gd")
const Items := preload("res://scripts/items.gd")

const WHEEL_R := 0.29
const WHEELS := [Vector3(0.69, WHEEL_R, 1.22), Vector3(-0.69, WHEEL_R, 1.22), Vector3(0.69, WHEEL_R, -1.22), Vector3(-0.69, WHEEL_R, -1.22)]
const FLAT := 3                 # спущенное колесо — заднее правое
const FLAT_SAG := 0.08          # насколько осел угол
const CRANK_AT := 0.5           # через сколько после «сел» включается стартер
const DRIVE_AT := CRANK_AT + Sfx2.STARTER_CATCH + 1.5
const CAM_OFF := Vector3(1.4, 2.7, -6.6)   # камера кат-сцены: сзади-слева, сверху

var game                        # game.gd
var surface: Node               # surface.gd — высота земли
var rig: Node3D                 # всё видимое (трясётся при заводке, корпус-коллизия — сам StaticBody)
var wheels: Array[Node3D] = []
var worn_mats: Array[ShaderMaterial] = []
var head_l: SpotLight3D
var lens_mat: StandardMaterial3D
var tail_mat: StandardMaterial3D
var smoke: CPUParticles3D
var driver: Node3D
var cam: Camera3D
var starter: AudioStreamPlayer
var engine: AudioStreamPlayer
var _noise_tex: NoiseTexture2D

var state := "idle"             # idle → board → start → drive → done; после деревни — parked (car_drive.gd)
var t := 0.0
var speed := 0.0
var start_pos := Vector3.ZERO
var yaw := 0.0
var caught := false
var win_called := false

# ---------- двери, места, вождение (промпт 15.11 23:01) ----------
## места: 0 — водитель (+X спереди), 1 — переднее пассажирское, 2 — сзади слева (+X), 3 — сзади справа
## глаза водителя — у руля (было на 0.56 м дальше, у самой спинки)
const SEAT_EYE := [Vector3(0.36, 1.21, 0.1), Vector3(-0.36, 1.21, 0.02), Vector3(0.36, 1.22, -0.8), Vector3(-0.36, 1.22, -0.8)]
const SEAT_HIP := [Vector3(0.36, 0.86, -0.12), Vector3(-0.36, 0.86, -0.12), Vector3(0.36, 0.86, -0.8), Vector3(-0.36, 0.86, -0.8)]
## двери: [сторона, петля z, длина]; дверь i — у места i
const DOORS := [[1.0, 0.86, 1.08], [-1.0, 0.86, 1.08], [1.0, -0.24, 0.86], [-1.0, -0.24, 0.86]]
const EXIT := [Vector3(1.45, 0, 0.25), Vector3(-1.45, 0, 0.25), Vector3(1.45, 0, -0.7), Vector3(-1.45, 0, -0.7)]
## лючок бензобака — слева сзади, за задней аркой: заправка только с прицела на него (car.gd, промпт 18.11 01:46)
const FUEL_CAP := Vector3(-0.83, 0.58, -1.68)
const DOOR_OPEN := 1.15         # на сколько радиан открывается дверь
const MAX_F := 13.0             # скорость вперёд, м/с
const MAX_R := 4.0              # назад
const ACC := 4.2
const BRAKE := 15.0          # тормозной путь на 40% короче (05:59)
const ROLL := 1.6
const TURN := 1.25
const FUEL_USE := 1.0 / 300.0   # полный бак — ~5 мин газа (05:59: вдвое экономнее)
## управление (промпт 16.11 05:13): велосипедная модель поворота, сцепление шин, занос, ручник
const WHEELBASE := 2.44         # колёсная база (передняя ось — задняя)
const A_LAT := 24.0             # предел бокового сцепления шин, м/с²: в обычной езде не скользит
const A_LAT_HB := 2.6           # с ручником зад сорван — машину несёт боком (00:37: было 4 — резко гасло)
const HB_DECEL := 0.8           # торможение ручником без газа (только задние — они же ведущие)
const HB_DECEL_GAS := 0.3       # ручник + газ: в дрифте скорость почти держится (00:37: ручник не останавливает резко)
const DRIFT_YAW := 3.6          # предел скорости вращения в заносе, рад/с (пончики; 00:44 — было 2.6)
const CRASH_MIN := 5.0          # с какой скорости удар о препятствие ранит сидящих, м/с
const CRASH_DMG := 3.0          # урон сидящим = (скорость - CRASH_MIN) * CRASH_DMG (на 13 м/с — 24)
const RAM_SELF := 0.35          # наезд на врага: сидящие теряют rel * RAM_SELF (немного)
const HIT_MIN := 3.0            # с какой относительной скорости удар машиной ранит моба, м/с
const HIT_DMG := 7.0            # урон = относительная скорость * HIT_DMG
const SWITCH_T := 0.75          # пересадка с пассажирского за руль, с
const NEXT_SEATS := [[1, 2], [0, 3], [0, 3], [1, 2]]   # соседние места: рядом и спереди/сзади (промпт 18.11 01:00)
var switch_from := 1            # откуда пересаживаемся (seat_dir == 2)
var doors: Array[Node3D] = []
var door_gaps: Array[Node3D] = []
var trunk_lid: Node3D                 # крышка багажника на петлях (анимация открытия)
var trunk_well: Node3D                # тёмная ниша внутри багажника (видна, когда крышка поднята)
var trunk_k := 0.0                    # 0 — закрыт, 1 — открыт
var trunk_want := 0.0
const TRUNK_OPEN := 1.15              # на сколько поднимается крышка, рад
var door_k := [0.0, 0.0, 0.0, 0.0]   # 0 — закрыта, 1 — открыта
var door_want := [0.0, 0.0, 0.0, 0.0]
var figures: Array[Node3D] = []      # силуэты людей для кат-сцены посадки
var seats := [0, 0, 0, 0]            # кто сидит: id игрока (в одиночной — 1), 0 — пусто
var my_seat := -1                    # где сидит свой игрок (-1 — снаружи)
var seat_anim := 0.0                 # 0..1: посадка/выход (камера едет между местом и улицей)
var seat_dir := 0                    # 1 — садится, -1 — выходит, 0 — сидит/снаружи
var seat_from := Vector3.ZERO        # откуда едет камера при посадке (мир)
## Прочность кузова (промпт 18.11 01:25): мобы агрятся на машину и бьют по ней. На нуле машина сломана —
## мотор не заводится, пока не починишь молотком (каменным или слесарным из магазина «Инструменты»).
const CAR_MAX_HP := 160.0
const CAR_SEAT_R := 1.5          # удар ближе этого к голове сидящего задевает и его
const CAR_SEAT_DMG := 0.4        # какая доля урона достаётся сидящему рядом с местом удара
const CAR_REPAIR := 0.34         # сколько прочности возвращает один удар молотком (доля от максимума)
var car_hp := CAR_MAX_HP
var broken := false
var fuel := 0.0                      # бак 0..1 (кат-сцена: последний бензин)
var escaped := false                 # уже уезжала с поляны (в сейве)
var ign_key: Node3D                  # ключ в замке зажигания: виден, когда ключ использован (= escaped)
var engine_on := false
var steer := 0.0
var carried: Array = []              # предметы в салоне едут вместе с машиной: [pickup, локальный transform]
var net_t := 0.0
var net_pos := Vector3.ZERO          # сеть: машину ведёт другой игрок
var net_yaw := 0.0
var net_drive := false
var bump_cd := 0.0
var slip := 0.0                       # боковая скорость (занос), м/с; speed — вдоль машины
var yaw_rate := 0.0                   # скорость поворота, рад/с
var thr_s := 0.0                      # педаль газа/тормоза (плавно)
var hand := false                     # ручник зажат
var acc_s := 0.0                      # продольное ускорение (сглаженное) — для «клевка» кузова
var roll_vis := 0.0                   # крен кузова в повороте (рисуем на rig)
var pitch_vis := 0.0
var look_yaw := 0.0                   # yaw машины в прошлом кадре: на сколько повернула — на столько и взгляд сидящего
const LOOK_MAX := 2.3                 # насколько можно отвернуться от «вперёд по машине», рад (~130°: видно двери)
var fuel_ui: CanvasLayer              # шкала бензина, пока сидишь в машине
var fuel_bar: ColorRect
var fuel_l: Label
var drive_t := 0.0                    # время езды — для шума сцепления задних колёс
var brake_k := 0.0                    # насколько жмём тормоз (S на ходу вперёд) 0..1
var drift_on := false                 # идёт занос (для случайности на его старте)
## Багажник (промпт 18.11 00:47): хранилище сзади машины, окно как у сундука (loot_window, kind = storage).
class Trunk extends RefCounted:
	var contents: Array = []
	var kind := "storage"
	var loot_title := "БАГАЖНИК"
	var car

	func on_loot_closed() -> void:
		if car and is_instance_valid(car):
			car.trunk_closed()

var trunk := Trunk.new()
var drift_dir := 1.0                  # куда ехали на старте заноса (+1 вперёд): вращение не разворачивается после 90°
var drift_mul := 1.0                  # случайный коэффициент этого заноса (0.8..1.2)
var grip_noise := 0.0                 # плавающее сцепление задних колёс (среднее), -1..1
var grip_k := 1.0                     # сцепление задней оси 0..1: ручник срывает, отпустил — плавно возвращается
var car_vel := Vector3.ZERO           # скорость машины в мире (для удара по мобам)
var wheel_spin := 0.0                 # задний привод: пробуксовка задних колёс, м/с (только вид)
var wheel_rim: Node3D                 # обод руля: крутится по steer (промпт 18.11 01:20)
var wheel_hands: Array[Node3D] = []   # кисти на руле: видны, когда водитель держит руль
var hands_k := 0.0                    # руки на руле 0..1 (плавно)
var lean := 0.0                       # высунулся из окна 0..1 (промпт 18.11 01:20)
var lean_on := false                  # держит клавишу «высунуться»
var lean_kick := 0.0                  # накопленный толчок заноса, пока высунут
const LEAN_T := 0.35                  # время высовывания, с
const LEAN_OUT := 0.44                # на сколько глаза уходят в окно, м
var village                          # village.gd
## Бернаут и быстрый старт (промпт 18.11 01:30): стоя на ручнике дать газ — задние (ведущие)
## колёса буксуют на месте, копится раскрутка burn_k; отпустил ручник с газом — рывок со старта.
const BURN_T := 1.1                   # за сколько секунд колёса раскручиваются до предела, с
const BURN_SPIN := 13.0               # добавка к видимой скорости задних колёс при бернауте, м/с
const BURN_V := 1.3                   # до какой скорости бернаут считается «с места», м/с
const LAUNCH_T := 1.3                 # сколько длится рывок быстрого старта, с
const LAUNCH_ACC := 2.2               # во сколько раз сильнее разгон на рывке (сверх обычного)
var burn_k := 0.0                     # раскрутка колёс на ручнике 0..1
var launch_t := 0.0                   # остаток рывка быстрого старта, с
var hand_prev := false                # ручник в прошлом кадре (отпустил — рывок)
var tyre: AudioStreamPlayer           # визг буксующих шин
var tyre_smoke: Array[CPUParticles3D] = []   # дым из-под задних колёс


## Положение машины на неровной земле: высота — средняя по колёсам, наклон — по разнице спереди/сзади
## и слева/справа; угол со спущенным колесом ниже (sag).
## Ввод игрока заблокирован (freecam, консоль, чат, кат-сцена — player.set_lock): машина его не слушает.
func ctl_locked() -> bool:
	return game != null and game.player != null and not game.player.input_locks.is_empty()


func _fit(p: Vector3, a: float, sag: bool) -> Transform3D:
	var yb := Basis(Vector3.UP, a)
	var h: Array[float] = []
	for i in 4:
		var w: Vector3 = p + yb * Vector3(WHEELS[i].x, 0, WHEELS[i].z)
		h.append(surface.height(w.x, w.z) - (FLAT_SAG if sag and i == FLAT else 0.0))
	var front := (h[0] + h[1]) / 2.0
	var rear := (h[2] + h[3]) / 2.0
	var left := (h[0] + h[2]) / 2.0
	var right := (h[1] + h[3]) / 2.0
	var pitch := -atan((front - rear) / 2.44)
	var roll := atan((left - right) / 1.38)
	var b := yb * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, roll)
	return Transform3D(b, Vector3(p.x, (front + rear) / 2.0 - 0.01, p.z))


# ---------- модель ----------

func _build() -> void:
	var paint := _worn(Color(0.3, 0.44, 0.46), false, 0.22, 0.9, 0.45)      # выцветшая «морская волна»
	var primer := _worn(Color(0.42, 0.17, 0.12), false, 0.12, 0.6, 0.35)    # дверь от другой машины, в грунте
	var chrome := _worn(Color(0.62, 0.61, 0.58), true, 0.0, 0.8, 0.6)
	var steel := _worn(Color(0.2, 0.2, 0.19), false, 0.2, 0.7, 0.4)        # крашеные диски
	var dark := _mat(Color(0.035, 0.033, 0.03), 0.0, 0.95)
	var rubber := _mat(Color(0.05, 0.048, 0.045), 0.0, 0.95)
	var rust := _mat(Color(0.24, 0.1, 0.045), 0.3, 1.0)
	var seat := _mat(Color(0.3, 0.17, 0.1), 0.0, 0.65)                      # коричневый дерматин
	var glass := _mat(Color(0.12, 0.15, 0.14, 0.5), 0.3, 0.12)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var dirty := _mat(Color(0.3, 0.28, 0.22, 0.75), 0.0, 0.8)               # заднее стекло в грязи
	dirty.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	# колёса
	for i in 4:
		var w := Node3D.new()
		w.position = WHEELS[i]
		rig.add_child(w)
		wheels.append(w)
		var side := signf(WHEELS[i].x)
		_cyl(w, WHEEL_R, 0.18, Vector3.ZERO, rubber, 18)
		_cyl(w, 0.175, 0.19, Vector3(0.002 * side, 0, 0), steel, 14)
		if i != 1:   # переднего правого колпака нет
			_cyl(w, 0.11, 0.2, Vector3(0.004 * side, 0, 0), chrome, 14)
		# протектор — поперечные полоски, видно, как крутится колесо
		for k in 8:
			var a := TAU * k / 8.0
			var tb := _box(Vector3(0.185, 0.03, 0.05), Vector3(0, sin(a), cos(a)) * WHEEL_R, rubber, Vector3(PI / 2 - a, 0, 0), w)
			tb.material_override = dark
		if i == FLAT:
			# спущенная резина распласталась по земле
			_box(Vector3(0.24, 0.07, 0.42), Vector3(0, -WHEEL_R + 0.04, 0), rubber, Vector3.ZERO, w)

	# кузов: низ, пороги, фартуки под бамперами
	_box(Vector3(1.6, 0.44, 4.0), Vector3(0, 0.64, 0), paint)
	_box(Vector3(1.56, 0.16, 1.55), Vector3(0, 0.34, 0), paint)
	_box(Vector3(1.56, 0.12, 0.42), Vector3(0, 0.36, 1.79), paint)
	_box(Vector3(1.56, 0.12, 0.42), Vector3(0, 0.36, -1.79), paint)
	# капот и багажник — чуть выпуклые крышки с зазором
	_box(Vector3(1.46, 0.035, 1.1), Vector3(0, 0.875, 1.42), paint, Vector3(0.012, 0, 0))
	# крышка багажника на петлях у спинки заднего сиденья (анимация — car_drive.gd _trunk_tick)
	trunk_lid = Node3D.new()
	trunk_lid.position = Vector3(0, 0.873, -1.13)
	rig.add_child(trunk_lid)
	_box(Vector3(1.46, 0.035, 0.84), Vector3(0, 0.002, -0.42), paint, Vector3(0, 0, 0.01), trunk_lid)
	_box(Vector3(1.4, 0.012, 0.78), Vector3(0, -0.02, -0.42), dark, Vector3.ZERO, trunk_lid)   # изнутри крышка тёмная
	trunk_well = _box(Vector3(1.38, 0.01, 0.76), Vector3(0, 0.868, -1.55), dark)                # тёмный проём под крышкой
	trunk_well.visible = false
	_box(Vector3(1.5, 0.006, 0.02), Vector3(0, 0.861, 0.86), dark)
	_box(Vector3(1.5, 0.006, 0.02), Vector3(0, 0.861, -1.13), dark)
	# колёсные арки — тёмные выемки над колёсами, по краю рыжая гниль
	for wp in WHEELS:
		var sx := signf(wp.x)
		_box(Vector3(0.008, 0.2, 0.72), Vector3(0.802 * sx, 0.5, wp.z), dark)
		_box(Vector3(0.01, 0.05, 0.78), Vector3(0.803 * sx, 0.61, wp.z), rust)
	# лючок бензобака: в него надо навести прицел, чтобы залить канистру
	_box(Vector3(0.006, 0.21, 0.21), Vector3(0.802 * signf(FUEL_CAP.x), FUEL_CAP.y, FUEL_CAP.z), dark)
	_box(Vector3(0.016, 0.17, 0.17), Vector3(0.808 * signf(FUEL_CAP.x), FUEL_CAP.y, FUEL_CAP.z), chrome)
	_box(Vector3(0.02, 0.05, 0.05), Vector3(0.812 * signf(FUEL_CAP.x), FUEL_CAP.y + 0.01, FUEL_CAP.z), dark)
	# дыры от ржавчины на порогах и низу дверей
	_box(Vector3(0.01, 0.07, 0.3), Vector3(0.803, 0.39, -0.45), rust)
	_box(Vector3(0.01, 0.05, 0.18), Vector3(0.804, 0.38, -0.47), dark)
	_box(Vector3(0.01, 0.09, 0.22), Vector3(-0.803, 0.47, 0.55), rust)
	_box(Vector3(0.01, 0.06, 0.4), Vector3(-0.803, 0.36, -0.3), rust)

	# двери: швы, ручки, правая передняя — в красном грунте
	for sx in [1.0, -1.0]:
		for z in [0.86, -0.24, -1.1]:
			_box(Vector3(0.006, 0.42, 0.012), Vector3(0.802 * sx, 0.65, z), dark)
		_box(Vector3(0.006, 0.012, 1.96), Vector3(0.802 * sx, 0.44, -0.12), dark)
		_box(Vector3(0.02, 0.03, 0.12), Vector3(0.81 * sx, 0.8, -0.1), chrome)
		_box(Vector3(0.02, 0.03, 0.12), Vector3(0.81 * sx, 0.8, -0.96), chrome)
		# молдинг вдоль борта
		_box(Vector3(0.015, 0.02, 3.9), Vector3(0.806 * sx, 0.72, 0), chrome)
	_box(Vector3(0.012, 0.4, 1.08), Vector3(-0.805, 0.645, 0.31), primer)

	# салон: пол-«ванна» по линии окон, сиденья, торпедо, руль
	_box(Vector3(1.4, 0.02, 1.95), Vector3(0, 0.865, -0.22), dark)
	for sx in [1.0, -1.0]:
		_box(Vector3(0.52, 0.1, 0.5), Vector3(0.36 * sx, 0.92, -0.02), seat)
		_box(Vector3(0.5, 0.4, 0.1), Vector3(0.36 * sx, 1.08, -0.3), seat, Vector3(-0.15, 0, 0))
		_box(Vector3(0.26, 0.1, 0.08), Vector3(0.36 * sx, 1.27, -0.34), seat, Vector3(-0.15, 0, 0))
	_box(Vector3(1.24, 0.1, 0.5), Vector3(0, 0.92, -0.78), seat)
	_box(Vector3(1.24, 0.44, 0.1), Vector3(0, 1.1, -1.02), seat, Vector3(-0.2, 0, 0))
	_box(Vector3(1.38, 0.14, 0.26), Vector3(0, 0.94, 0.68), dark)
	var tor := TorusMesh.new()
	tor.inner_radius = 0.15
	tor.outer_radius = 0.18
	tor.rings = 16
	tor.ring_segments = 6
	# руль на наклонной рулевой колонке: крутится вместе с рулём (wheel_rim), на нём — руки водителя
	var col := Node3D.new()
	col.position = Vector3(0.36, 1.04, 0.46)
	col.rotation.x = -1.05
	rig.add_child(col)
	wheel_rim = Node3D.new()
	col.add_child(wheel_rim)
	var wheel_mi := MeshInstance3D.new()
	wheel_mi.mesh = tor
	wheel_mi.material_override = dark
	wheel_rim.add_child(wheel_mi)
	for sa in [0.0, TAU / 3.0, TAU * 2.0 / 3.0]:
		var sp := _box(Vector3(0.155, 0.014, 0.02), Vector3.ZERO, dark, Vector3.ZERO, wheel_rim)
		sp.position = Vector3(cos(sa), 0.0, -sin(sa)) * 0.082
		sp.rotation.y = sa
	_box(Vector3(0.05, 0.02, 0.05), Vector3.ZERO, chrome, Vector3.ZERO, wheel_rim)
	# кисти на руле (видны водителю от первого лица), прячутся, когда руки заняты — car_drive.gd
	var skin := _mat(Color(0.64, 0.47, 0.37), 0.0, 0.85)
	var sleeve := _mat(Color(0.26, 0.24, 0.21), 0.0, 0.9)
	wheel_hands.clear()
	for sx in [-1.0, 1.0]:
		var hd := Node3D.new()
		hd.position = Vector3(0.16 * sx, 0.015, 0.0)
		wheel_rim.add_child(hd)
		_box(Vector3(0.075, 0.075, 0.1), Vector3.ZERO, skin, Vector3.ZERO, hd)
		_box(Vector3(0.05, 0.045, 0.07), Vector3(0.0, -0.045, 0.02), skin, Vector3(0.4, 0.0, 0.0), hd)
		_box(Vector3(0.085, 0.085, 0.14), Vector3(0.05 * sx, 0.02, 0.07), sleeve, Vector3.ZERO, hd)
		wheel_hands.append(hd)
		hd.visible = false
	_box(Vector3(0.03, 0.03, 0.22), Vector3(0.36, 1.0, 0.56), dark, Vector3(-0.5, 0, 0))
	_build_ign_key(chrome)
	# водитель — тёмный силуэт, появляется в кат-сцене
	driver = Node3D.new()
	driver.visible = false
	rig.add_child(driver)
	var who := _mat(Color(0.06, 0.055, 0.05), 0.0, 0.9)
	_box(Vector3(0.42, 0.32, 0.24), Vector3(0.36, 1.02, -0.14), who, Vector3.ZERO, driver)
	var hs := SphereMesh.new()
	hs.radius = 0.1
	hs.height = 0.22
	var head := MeshInstance3D.new()
	head.mesh = hs
	head.material_override = who
	head.position = Vector3(0.36, 1.23, -0.12)
	driver.add_child(head)

	# крыша, стойки, стёкла
	_box(Vector3(1.38, 0.06, 1.48), Vector3(0, 1.37, -0.22), paint)
	_box(Vector3(1.4, 0.02, 0.03), Vector3(0, 1.335, 0.52), chrome)   # водосток над лобовым
	for sx in [1.0, -1.0]:
		_beam(Vector3(0.7 * sx, 0.87, 0.86), Vector3(0.67 * sx, 1.36, 0.51), 0.07, 0.06, paint)    # A
		_beam(Vector3(0.71 * sx, 0.87, -0.22), Vector3(0.68 * sx, 1.36, -0.22), 0.07, 0.1, paint)  # B
		_beam(Vector3(0.7 * sx, 0.87, -1.13), Vector3(0.67 * sx, 1.36, -0.94), 0.07, 0.16, paint)  # C
	# лобовое выбито: снизу торчит неровная кромка с осколками
	var wa := Vector3(0, 0.88, 0.85)
	var wb := Vector3(0, 1.34, 0.52)
	_beam(wa, wa.lerp(wb, 0.16), 0.01, 1.34, glass)
	var shard_rng := RandomNumberGenerator.new()
	shard_rng.seed = 18
	for k in 9:
		var x := -0.62 + k * 0.155 + shard_rng.randf_range(-0.04, 0.04)
		var hgt := shard_rng.randf_range(0.04, 0.16) if k != 2 and k != 7 else shard_rng.randf_range(0.2, 0.32)
		var pm := PrismMesh.new()
		pm.size = Vector3(shard_rng.randf_range(0.08, 0.16), hgt, 0.006)
		pm.left_to_right = shard_rng.randf()
		var base := wa.lerp(wb, 0.15)
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		mi.material_override = glass
		var up := (wb - wa).normalized()
		mi.transform = Transform3D(Basis(Vector3.RIGHT, up, Vector3.RIGHT.cross(up)), base + Vector3(x, 0, 0) + up * hgt * 0.5)
		rig.add_child(mi)
	# боковые стёкла: водительского нет — только огрызок у двери
	_box(Vector3(0.01, 0.42, 0.68), Vector3(-0.69, 1.1, 0.16), glass)
	_box(Vector3(0.01, 0.07, 0.68), Vector3(0.69, 0.9, 0.16), glass)
	_box(Vector3(0.01, 0.42, 0.66), Vector3(0.69, 1.1, -0.6), glass)
	_box(Vector3(0.01, 0.42, 0.66), Vector3(-0.69, 1.1, -0.6), dirty)
	_beam(Vector3(0, 0.88, -1.12), Vector3(0, 1.34, -0.95), 0.01, 1.3, dirty)
	# зеркало только водительское
	_box(Vector3(0.12, 0.02, 0.02), Vector3(0.82, 0.93, 0.76), chrome)
	_box(Vector3(0.05, 0.08, 0.12), Vector3(0.88, 0.97, 0.76), chrome, Vector3(0, 0.2, 0))

	# перед: решётка, фары (левая разбита), бампер с клыками, номер
	_box(Vector3(1.0, 0.17, 0.03), Vector3(0, 0.7, 2.005), dark)
	for y in [0.79, 0.61]:
		_box(Vector3(1.04, 0.02, 0.035), Vector3(0, y, 2.01), chrome)
	for y in [0.66, 0.7, 0.74]:
		_box(Vector3(0.98, 0.01, 0.03), Vector3(0, y, 2.012), chrome)
	lens_mat = _mat(Color(0.75, 0.72, 0.6), 0.0, 0.2)
	lens_mat.emission_enabled = true
	lens_mat.emission = Color(1.0, 0.85, 0.55)
	lens_mat.emission_energy_multiplier = 0.0
	for sx in [1.0, -1.0]:
		var hp := Vector3(0.64 * sx, 0.71, 2.0)
		_cyl_z(Vector3(hp.x, hp.y, hp.z + 0.01), 0.108, 0.035, chrome)
		if sx > 0:
			_cyl_z(Vector3(hp.x, hp.y, hp.z + 0.022), 0.09, 0.02, dark)      # пустая глазница
			var pm := PrismMesh.new()
			pm.size = Vector3(0.07, 0.06, 0.005)
			var sh := MeshInstance3D.new()
			sh.mesh = pm
			sh.material_override = glass
			sh.position = Vector3(hp.x + 0.03, hp.y - 0.05, hp.z + 0.035)
			rig.add_child(sh)
		else:
			_cyl_z(Vector3(hp.x, hp.y, hp.z + 0.024), 0.09, 0.02, lens_mat)
	_box(Vector3(1.66, 0.08, 0.06), Vector3(0, 0.45, 2.04), chrome)
	for sx in [1.0, -1.0]:
		_box(Vector3(0.05, 0.15, 0.05), Vector3(0.33 * sx, 0.47, 2.08), chrome)
	_plate(Vector3(0, 0.34, 2.05))

	# зад: фонари (правый треснул), гнутый бампер, номер, выхлопная труба
	tail_mat = _mat(Color(0.5, 0.06, 0.04), 0.0, 0.3)
	tail_mat.emission_enabled = true
	tail_mat.emission = Color(0.9, 0.08, 0.03)
	tail_mat.emission_energy_multiplier = 0.1
	_box(Vector3(0.28, 0.14, 0.03), Vector3(0.6, 0.7, -2.005), tail_mat)
	_box(Vector3(0.28, 0.14, 0.03), Vector3(-0.6, 0.7, -2.005), tail_mat)
	_box(Vector3(0.12, 0.08, 0.034), Vector3(-0.66, 0.68, -2.006), dark, Vector3(0, 0, 0.3))
	_box(Vector3(1.66, 0.08, 0.06), Vector3(0, 0.43, -2.04), chrome, Vector3(0, 0.04, -0.07))
	_plate(Vector3(0, 0.6, -2.025), true)
	_cyl_z(Vector3(-0.45, 0.25, -1.96), 0.03, 0.25, rust)
	smoke = CPUParticles3D.new()
	smoke.position = Vector3(-0.45, 0.25, -2.1)
	smoke.amount = 26
	smoke.lifetime = 2.2
	smoke.direction = Vector3(0, 0.4, -1)
	smoke.spread = 25.0
	smoke.initial_velocity_min = 0.5
	smoke.initial_velocity_max = 1.1
	smoke.gravity = Vector3(0, 0.35, 0)
	smoke.damping_min = 0.4
	smoke.damping_max = 0.8
	smoke.scale_amount_min = 0.8
	smoke.scale_amount_max = 2.2
	smoke.local_coords = false
	smoke.mesh = _smoke_mesh(Color(0.2, 0.2, 0.2, 0.3))
	_smoke_fade(smoke)
	smoke.emitting = false
	rig.add_child(smoke)
	# дым из-под задних (ведущих) колёс: бернаут, рывок со старта, занос (18.11 01:30)
	for i in 2:
		var ts := CPUParticles3D.new()
		ts.position = Vector3(WHEELS[2 + i].x, 0.08, WHEELS[2 + i].z - 0.1)
		ts.amount = 22
		ts.lifetime = 1.5
		ts.direction = Vector3(0, 0.5, -1)
		ts.spread = 50.0
		ts.initial_velocity_min = 0.8
		ts.initial_velocity_max = 2.2
		ts.gravity = Vector3(0, 0.5, 0)
		ts.damping_min = 1.2
		ts.damping_max = 2.4
		ts.scale_amount_min = 0.7
		ts.scale_amount_max = 2.0
		ts.local_coords = false
		ts.mesh = _smoke_mesh(Color(0.72, 0.7, 0.66, 0.26))
		_smoke_fade(ts)
		ts.emitting = false
		rig.add_child(ts)
		tyre_smoke.append(ts)
	head_l = SpotLight3D.new()
	head_l.position = Vector3(-0.64, 0.71, 2.1)
	head_l.rotation = Vector3(-0.08, PI, 0)
	head_l.light_color = Color(1.0, 0.86, 0.6)
	head_l.light_energy = 0.0
	head_l.spot_range = 22.0
	head_l.spot_angle = 28.0
	head_l.shadow_enabled = true
	rig.add_child(head_l)

	_build_doors(paint, primer, chrome, dark)
	# осколки водительского стекла в траве у двери
	for k in 6:
		var pm := PrismMesh.new()
		pm.size = Vector3(shard_rng.randf_range(0.04, 0.09), shard_rng.randf_range(0.05, 0.1), 0.004)
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		mi.material_override = glass
		mi.position = Vector3(shard_rng.randf_range(0.95, 1.5), 0.02, shard_rng.randf_range(-0.2, 0.6))
		mi.rotation = Vector3(-PI / 2 + shard_rng.randf_range(-0.2, 0.2), shard_rng.randf() * TAU, 0)
		add_child(mi)


## Номерной знак: грязно-белая табличка с чёрными знаками (старого образца: «буква цифры буквы»).
func _plate(pos: Vector3, rear := false) -> void:
	var z := 1.0 if not rear else -1.0
	_box(Vector3(0.52, 0.12, 0.012), pos, _mat(Color(0.62, 0.6, 0.52), 0.0, 0.8))
	var ink := _mat(Color(0.04, 0.04, 0.04), 0.0, 0.9)
	var xs := [-0.2, -0.13, -0.06, 0.01, 0.08, 0.15, 0.21]
	for k in xs.size():
		var tall := k >= 1 and k <= 4
		_box(Vector3(0.035, 0.07 if tall else 0.05, 0.004), pos + Vector3(float(xs[k]) * z, -0.005 if not tall else 0.0, 0.008 * z), ink)


## Четыре двери на петлях: панель с ручкой поверх борта; когда дверь открыта — в борту тёмный проём.
func _build_doors(paint: Material, primer: Material, chrome: Material, dark: Material) -> void:
	for i in 4:
		var side: float = DOORS[i][0]
		var hz: float = DOORS[i][1]
		var ln: float = DOORS[i][2]
		var gap := _box(Vector3(0.012, 0.44, ln - 0.04), Vector3(0.806 * side, 0.65, hz - ln / 2.0), dark)
		gap.visible = false
		door_gaps.append(gap)
		var pv := Node3D.new()
		pv.position = Vector3(0.818 * side, 0.43, hz)
		rig.add_child(pv)
		doors.append(pv)
		var m := primer if i == 1 else paint
		_box(Vector3(0.026, 0.45, ln - 0.02), Vector3(0, 0.225, -ln / 2.0), m, Vector3.ZERO, pv)
		_box(Vector3(0.022, 0.03, ln - 0.1), Vector3(-0.08 * side, 0.92, -ln / 2.0 - 0.02), m, Vector3.ZERO, pv)   # рамка окна
		_box(Vector3(0.022, 0.42, 0.03), Vector3(-0.07 * side, 0.7, -ln + 0.03), m, Vector3.ZERO, pv)
		_box(Vector3(0.02, 0.03, 0.12), Vector3(0.012 * side, 0.37, -ln + 0.16), chrome, Vector3.ZERO, pv)


## Силуэт человека для кат-сцены (тёмная фигура): начало координат — таз; legs — ноги (сидя — вперёд).
func _figure() -> Node3D:
	var who := _mat(Color(0.06, 0.055, 0.05), 0.0, 0.9)
	var f := Node3D.new()
	f.visible = false
	rig.add_child(f)
	_box(Vector3(0.4, 0.34, 0.22), Vector3(0, 0.17, 0), who, Vector3.ZERO, f)
	var hs := SphereMesh.new()
	hs.radius = 0.1
	hs.height = 0.22
	var head := MeshInstance3D.new()
	head.mesh = hs
	head.material_override = who
	head.position = Vector3(0, 0.42, 0.02)
	f.add_child(head)
	var legs := Node3D.new()
	legs.name = "Legs"
	f.add_child(legs)
	for sx in [-0.1, 0.1]:
		_box(Vector3(0.13, 0.78, 0.14), Vector3(sx, -0.39, 0), who, Vector3.ZERO, legs)
	return f


## Столкновения «коробкой с дыркой»: низ кузова, сиденья, торпедо, крыша, борта — внутри салона
## можно сидеть, и вещи лежат на сиденьях.
func _hollow_collision() -> void:
	_collide(Vector3(1.64, 0.62, 4.12), Vector3(0, 0.57, 0))
	_collide(Vector3(0.52, 0.1, 0.5), Vector3(0.36, 0.92, -0.02))
	_collide(Vector3(0.52, 0.1, 0.5), Vector3(-0.36, 0.92, -0.02))
	_collide(Vector3(1.24, 0.1, 0.5), Vector3(0, 0.92, -0.78))
	_collide(Vector3(1.38, 0.14, 0.26), Vector3(0, 0.94, 0.68))
	_collide(Vector3(1.42, 0.08, 1.52), Vector3(0, 1.37, -0.22))
	for sx in [1.0, -1.0]:
		_collide(Vector3(0.06, 0.48, 2.0), Vector3(0.72 * sx, 1.12, -0.13))
	_collide(Vector3(1.42, 0.48, 0.06), Vector3(0, 1.12, 0.74))
	_collide(Vector3(1.42, 0.48, 0.06), Vector3(0, 1.12, -1.06))


# ---------- помощники ----------

func _noise() -> NoiseTexture2D:
	if _noise_tex == null:
		var n := FastNoiseLite.new()
		n.seed = 2101
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 0.05
		n.fractal_octaves = 3
		_noise_tex = NoiseTexture2D.new()
		_noise_tex.width = 128
		_noise_tex.height = 128
		_noise_tex.seamless = true
		_noise_tex.noise = n
	return _noise_tex


func _worn(c: Color, chrome := false, wear := 0.3, rust := 0.6, dust := 0.6) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WornMetal
	m.set_shader_parameter("n_px", _noise())
	m.set_shader_parameter("n_lin", _noise())
	m.set_shader_parameter("paint_color", c)
	m.set_shader_parameter("chrome", 1.0 if chrome else 0.0)
	m.set_shader_parameter("wear", wear)
	m.set_shader_parameter("rust", rust)
	m.set_shader_parameter("dust", dust)
	m.set_shader_parameter("rust_color", Color(0.36, 0.16, 0.06))
	m.set_shader_parameter("base_y", position.y)
	worn_mats.append(m)
	return m


## Ключ в замке зажигания справа от рулевой колонки (промпт 16.11 02:45): головка, бородка, брелок.
func _build_ign_key(chrome: Material) -> void:
	ign_key = Node3D.new()
	ign_key.position = Vector3(0.22, 0.985, 0.55)
	ign_key.rotation = Vector3(-0.35, 0, 0.25)
	ign_key.visible = false
	rig.add_child(ign_key)
	var brass := _mat(Color(0.7, 0.55, 0.25), 0.8, 0.35)
	_box(Vector3(0.05, 0.05, 0.03), Vector3(0, 0.0, 0.035), _mat(Color(0.05, 0.05, 0.05), 0.0, 0.7), Vector3.ZERO, ign_key)   # замок
	_box(Vector3(0.008, 0.012, 0.035), Vector3(0, 0, 0.0), brass, Vector3.ZERO, ign_key)        # бородка в замке
	_box(Vector3(0.006, 0.032, 0.026), Vector3(0, 0, -0.03), brass, Vector3.ZERO, ign_key)      # головка
	_box(Vector3(0.004, 0.014, 0.012), Vector3(0, -0.022, -0.042), chrome, Vector3.ZERO, ign_key)  # кольцо
	_box(Vector3(0.012, 0.03, 0.02), Vector3(0, -0.048, -0.046), _mat(Color(0.55, 0.12, 0.1), 0.0, 0.6), Vector3(0.2, 0, 0), ign_key)  # брелок


func _mat(c: Color, metal := 0.0, rough := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m


func _box(size: Vector3, pos: Vector3, m: Material, rot := Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	(parent if parent else rig).add_child(mi)
	return mi


## Брусок от точки a до точки b (стойки, наклонные стёкла): толщина thick, ширина вдоль X — wide.
func _beam(a: Vector3, b: Vector3, thick: float, wide: float, m: Material) -> MeshInstance3D:
	var d := b - a
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(wide, d.length(), thick)
	mi.mesh = bm
	mi.material_override = m
	var up := d.normalized()
	var fwd := Vector3.RIGHT.cross(up).normalized()
	mi.transform = Transform3D(Basis(Vector3.RIGHT, up, fwd).orthonormalized(), (a + b) / 2.0)
	rig.add_child(mi)
	return mi


## Цилиндр поперёк машины (ось X) — колёса.
func _cyl(parent: Node3D, r: float, h: float, pos: Vector3, m: Material, segs := 16) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = segs
	cm.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = m
	mi.position = pos
	mi.rotation.z = PI / 2
	parent.add_child(mi)
	return mi


## Цилиндр вдоль машины (ось Z) — фары, труба.
func _cyl_z(pos: Vector3, r: float, h: float, m: Material) -> MeshInstance3D:
	var mi := _cyl(rig, r, h, pos, m, 16)
	mi.rotation = Vector3(PI / 2, 0, 0)
	return mi


func _smoke_mesh(c: Color) -> Mesh:
	var bm := BoxMesh.new()
	bm.size = Vector3(0.1, 0.1, 0.1)
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 1.0
	m.metallic_specular = 0.0
	bm.material = m
	return bm


## Дым тает и чуть растёт к концу жизни.
func _smoke_fade(p: CPUParticles3D) -> void:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = g
	var cv := Curve.new()
	cv.add_point(Vector2(0, 0.6))
	cv.add_point(Vector2(1, 1.6))
	p.scale_amount_curve = cv


func _collide(size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	add_child(cs)
