@tool
class_name StoneConfig
extends Resource
## Бросок камня (scripts/weapons/stone_throw.gd). Файл — data/weapons/stone.tres.

## Скорость брошенного камня, м/с.
@export_range(0.0, 100.0, 0.5) var speed := 15.0
## Задержка между бросками, с.
@export_range(0.0, 10.0, 0.05) var cooldown := 0.55
## Руки, которыми можно бросать.
@export var hand_slots: Array[String] = []
