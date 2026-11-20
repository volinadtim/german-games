@tool
class_name PlayerConfig
extends Resource
## Игрок (scripts/player/player_base.gd). Файл — data/balance/player.tres.

@export_group("Движение")
## Скорость ходьбы, м/с.
@export_range(0.0, 20.0, 0.1) var walk_speed := 3.4
## Скорость бега, м/с.
@export_range(0.0, 20.0, 0.1) var sprint_speed := 5.4
## Ходьба вприсядку — доля от обычной скорости (0.45 — 45%).
@export_range(0.0, 1.0, 0.01) var crouch_speed := 0.45
## Разгон с места до шага, м/с² (16 — ~0.2 с).
@export_range(0.0, 100.0, 0.5) var accel_walk := 16.0
## Разгон с шага до бега, м/с².
@export_range(0.0, 100.0, 0.5) var accel_sprint := 10.0
## Торможение с шага, м/с² (40 — стоп за ~0.09 с).
@export_range(0.0, 100.0, 0.5) var decel_walk := 40.0
## Торможение с бега, м/с².
@export_range(0.0, 100.0, 0.5) var decel_sprint := 30.0
## Торможение при смене направления и с бега на шаг, м/с².
@export_range(0.0, 100.0, 0.5) var decel_turn := 22.0
## Скорость прыжка вверх, м/с (5 — ~0.55 м).
@export_range(0.0, 20.0, 0.1) var jump_speed := 5.0
## Гравитация, м/с².
@export_range(0.0, 50.0, 0.5) var gravity := 22.0
## Вниз падаем быстрее, чем взлетаем (множитель гравитации при падении) — прыжок не «плывёт».
@export_range(1.0, 5.0, 0.05) var fall_mult := 1.35

@export_group("Присед")
## Насколько опускается таз, м.
@export var crouch_hip := 0.28
## Насколько опускается камера, м.
@export var crouch_cam := 0.45
## Высота капсулы в приседе, м (стоя 1.8).
@export var crouch_height := 1.15

@export_group("Бой")
## Урон кулака (вид удара на урон не влияет).
@export_range(0.0, 200.0, 0.5) var punch_base := 8.0
## Множитель урона по рукам: [левая, правая]. Левая — урон чуть ниже.
@export var hand_dmg: Array[float] = []
## Шанс крита по рукам: [левая, правая]. Левая — чаще.
@export var hand_crit: Array[float] = []
## Множитель урона крита.
@export_range(1.0, 10.0, 0.1) var crit_mult := 2.0
## Заряженный удар: время полного заряда, с.
@export_range(0.0, 10.0, 0.05) var charge_max := 1.5
## Заряженный удар: прибавка к множителю урона за полный заряд.
@export_range(0.0, 10.0, 0.05) var charge_gain := 1.5
## Нажатие короче этого (с) — обычный удар без заряда.
@export_range(0.0, 1.0, 0.01) var tap_time := 0.12
## Урон кулаков по видам удара: вид -> урон.
@export var punch_dmg: Dictionary[String, float] = {}

@export_group("Шум (слышат враги)")
## Радиус, в котором враги слышат шаги, м.
@export_range(0.0, 100.0, 0.5) var noise_walk := 5.0
## Бег, м.
@export_range(0.0, 100.0, 0.5) var noise_sprint := 10.0
## Шаги вприсядку, м.
@export_range(0.0, 100.0, 0.1) var noise_crouch := 0.5
## Прыжок (короткий всплеск), м.
@export_range(0.0, 100.0, 0.5) var noise_jump := 6.0
## Удар, м.
@export_range(0.0, 100.0, 0.5) var noise_punch := 5.0
## Выстрел, м.
@export_range(0.0, 200.0, 0.5) var noise_shot := 25.0

@export_group("Камера и звук")
## Чувствительность мыши (рад на пиксель, до множителя из настроек).
@export var mouse_sens := 0.0022
## Поворот стрелками, рад/с.
@export var key_turn := 2.4
## Высота камеры, м.
@export var cam_y := 1.4
## Поле зрения по умолчанию, градусов.
@export_range(30.0, 120.0, 1.0) var fov := 75.0
## Громкость шага относительно ходьбы, дБ.
@export var step_db := -23.0

@export_group("Анимация (не баланс)")
## Модель чуть позади камеры, чтобы лицо не лезло в кадр, м.
@export var model_z := 0.02
## Доля сгиба кулака, когда пальцы обхватывают рукоять (толще рукоять — меньше): предмет -> 0..1.
@export var grip_curl: Dictionary[String, float] = {}
## Конец оружия (по длинной оси) — от него тянется след удара: предмет -> м.
@export var weapon_tip: Dictionary[String, float] = {}
## Предметы в руке без боевой стойки ближнего боя ("" — пустые руки).
@export var melee_stance_skip: Array[String] = []
## Ключевые позы ударов кулаком: вид -> [позы руки Vector4].
@export var punches: Dictionary = {}
## Взмахи оружием: набор -> список взмахов {wind — замах, hit — удар, thru — проводка (позы руки), tw — поворот корпуса,
## t — длительности [замах, удар, проводка, возврат], rc — выпад плеча, wf — сгиб кисти, blur — вид следа}.
@export var swings: Dictionary = {}
