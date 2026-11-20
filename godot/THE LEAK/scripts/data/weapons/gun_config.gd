@tool
class_name GunConfig
extends Resource
## Огнестрел (scripts/weapons/gun.gd): числа пистолета; у других стволов — свои множители в предметах (data/items).
## Файл — data/weapons/guns.tres.

@export_group("Урон")
## Урон пули (по бетоннику с 95 HP — 3 попадания).
@export_range(0.0, 500.0, 0.5) var damage := 40.0
## Хэдшот — множитель урона.
@export_range(1.0, 10.0, 0.1) var head_mult := 2.5
## До этой дистанции урон полный, м.
@export_range(0.0, 500.0, 1.0) var full_dmg_dist := 20.0
## Дальше урон падает линейно до «Урон вдали» на этой дистанции, м.
@export_range(0.0, 500.0, 1.0) var far_dmg_dist := 50.0
## Множитель урона вдали.
@export_range(0.0, 1.0, 0.01) var far_dmg_mult := 0.5
## Дальность выстрела, м.
@export_range(0.0, 1000.0, 1.0) var range_m := 120.0

@export_group("Стрельба и патроны")
## Патронов в магазине.
@export_range(1, 200, 1) var mag_size := 8
## Задержка между выстрелами, с.
@export_range(0.0, 5.0, 0.01) var fire_cd := 0.28
## Перезарядка, с.
@export_range(0.0, 10.0, 0.05) var reload_time := 1.7
## Прочность: столько выстрелов до поломки.
@export_range(1.0, 10000.0, 1.0) var durability := 60.0
## Столько держать Enter — извлечь магазин, с.
@export var eject_time := 0.5
## Радиус, в котором враги слышат выстрел, м.
@export_range(0.0, 500.0, 1.0) var hear_radius := 28.0

@export_group("Точность и прицел")
## Разброс от бедра, рад.
@export_range(0.0, 0.5, 0.001) var spread_hip := 0.03
## Разброс в прицеле, рад (0.01 — на 100 м уходит на ~1 м).
@export_range(0.0, 0.5, 0.001) var spread_aim := 0.01
## Разброс в боевой стойке, рад.
@export_range(0.0, 0.5, 0.001) var spread_stance := 0.045
## Множитель поля зрения в прицеле.
@export_range(0.1, 1.0, 0.01) var aim_fov := 0.7
## ПКМ короче этого (с) — клик (переключить прицел), дольше — держать (от бедра).
@export var aim_tap_time := 0.22

@export_group("Модули")
## Слоты модулей: id, подпись, какие предметы-модули туда встают. Статы модулей — в предметах ("ms").
@export var mod_slots: Array[GunModSlot] = []
## СЛУЖЕБНОЕ, НЕ МЕНЯТЬ: вес кода модулей в прочности ствола из сейва (dur = код × это + …). Изменишь — сломаются сейвы.
@export var mod_code_weight := 100.0

@export_group("Модель и звук (не баланс)")
## Высота центра линзы коллиматора над началом модели пистолета, м.
@export var optic_h := 0.1435
## Точка коллиматора: вперёд по стволу от начала модели, м.
@export var dot_x := 0.08
## От бедра пистолет настолько ниже линии взгляда, м.
@export var hip_h := 0.17
## Линия механического прицела (целик и мушка), м.
@export var iron_h := 0.137
## Скорость, с которой оружие догоняет камеру.
@export var lag_speed := 14.0
## Дальше этого (рад) оружие не отстаёт от камеры.
@export var lag_max := 0.1
## Руки, в которых может быть ствол.
@export var hand_slots: Array[String] = []
## Звуки перезарядки: [секунда, событие].
@export var reload_events: Array = []
## Звуки перезарядки включены.
@export var reload_sounds := false
## Не больше стольких звуков выстрела одновременно.
@export var max_sounds := 4
## Частота синтеза звуков, Гц.
@export var sample_rate := 22050


## [[id, подпись, [модули]], …]
func mod_slots_table() -> Array:
	var out: Array = []
	for s in mod_slots:
		out.append([s.id, s.title, Array(s.mods)])
	return out
