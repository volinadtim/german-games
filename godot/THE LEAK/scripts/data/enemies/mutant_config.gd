@tool
class_name MutantConfig
extends Resource
## Мутанты (scripts/enemy/mutant_base.gd). Файл — data/enemies/mutant.tres.

@export_group("Виды")
## Виды мутантов: здоровье, скорость, рост, цвета.
@export var kinds: Array[MutantKind] = []

@export_group("Урон")
## Плевун: урон плевка.
@export_range(0.0, 200.0, 0.5) var spit_dmg := 11.0
## Плевун: перезарядка плевка, с.
@export_range(0.0, 30.0, 0.1) var spit_cd := 2.3
## Таран: урон разгона.
@export_range(0.0, 200.0, 0.5) var charge_dmg := 28.0
## Таран: скорость разгона, м/с.
@export_range(0.0, 50.0, 0.5) var charge_speed := 11.5
## Таран: урон удара об землю.
@export_range(0.0, 200.0, 0.5) var slam_dmg := 18.0
## Тень: урон из засады.
@export_range(0.0, 200.0, 0.5) var stalk_dmg := 9.0
## Тень: урон взмаха.
@export_range(0.0, 200.0, 0.5) var swipe_dmg := 6.0

@export_group("Зрение и погоня")
## Дальность зрения, м.
@export_range(0.0, 100.0, 0.5) var sight := 15.0
## Дальше стольких метров от дома не уходит.
@export_range(0.0, 200.0, 0.5) var leash := 38.0
## Высота земли, на которой живут мутанты, м (игрок ниже неё на 1 м и больше — не преследуют).
@export var ground_y := 4.0


## id -> {name, hp, speed, h, skin, glow}
func kinds_table() -> Dictionary:
	var out := {}
	for k in kinds:
		out[k.id] = k.to_dict()
	return out
