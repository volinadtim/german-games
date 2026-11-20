@tool
class_name EnemyConfig
extends Resource
## Враги бункера и поляны (scripts/enemy/enemy_base.gd и наследники). Файл — data/enemies/enemy.tres.

@export_group("Здоровье и урон")
## Здоровье.
@export_range(1.0, 1000.0, 1.0) var max_hp := 95.0
## Урон удара.
@export_range(0.0, 200.0, 0.5) var damage := 16.0
## Урон спокойному врагу со спины — множитель.
@export_range(1.0, 10.0, 0.1) var backstab := 2.5
## Перезарядка абилок (прыжок Шныги, камень бетонника), с.
@export_range(0.0, 120.0, 0.5) var ability_cd := 12.0
## Шныга: урон прыжка на игрока.
@export_range(0.0, 200.0, 0.5) var leap_dmg := 11.0
## Бетонник: урон брошенного камня.
@export_range(0.0, 200.0, 0.5) var rock_dmg := 13.0
## С какого расстояния начинает удар, м.
@export var attack_range := 1.35
## Докуда достаёт удар, м.
@export var hit_range := 1.8

@export_group("Скорость")
## Скорость в погоне, м/с.
@export_range(0.0, 20.0, 0.05) var speed := 2.1
## Скорость, когда бродит, м/с.
@export_range(0.0, 20.0, 0.05) var wander_speed := 0.85

@export_group("Зрение и слух")
## Дальность зрения, м.
@export_range(0.0, 100.0, 0.5) var sight := 9.0
## Угол зрения (половина конуса), градусов.
@export_range(0.0, 180.0, 1.0) var fov_deg := 65.0
## Вприсядку игрок виден с меньшей доли дальности (0.4 — 40%).
@export_range(0.0, 1.0, 0.01) var sight_crouch := 0.4
## Сзади/сбоку замечает игрока вплотную — ближе стольких метров.
@export var near_feel := 1.8
## То же вприсядку, м.
@export var near_feel_crouch := 0.9
## За сколько секунд замечает игрока вплотную.
@export var notice_near := 0.3
## … и на краю дальности зрения, с.
@export var notice_far := 2.2
## Сколько секунд помнит, где видел игрока последний раз.
@export var memory_time := 12.0

@export_group("Погоня")
## Дальше стольких метров от дома не уходит.
@export var leash := 14.0
## Потерял из виду на столько секунд — возвращается.
@export var lose_time := 8.0
## Дольше этого без вида игрока — точно сдаётся, с.
@export var chase_max := 45.0

@export_group("Появление из земли (не баланс)")
## Проявление, с.
@export var rise_fade := 0.55
## Всплыл грудью вверх, с.
@export var rise_up := 1.45
## Резко встал на ноги, с.
@export var rise_drop := 1.7
## Всё появление, с.
@export var rise_time := 2.0

@export_group("Путь по бункеру (не баланс)")
## Дверные проёмы: [центр, направление сквозь проём].
@export var doors: Array = []
## Полуширина проёма, м.
@export var door_half := 0.85
## Точки пути: между ними ищется кратчайший путь.
@export var waypoints: Array[Vector3] = []
