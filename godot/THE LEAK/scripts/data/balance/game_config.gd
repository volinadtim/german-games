@tool
class_name GameConfig
extends Resource
## Общее по игре (scripts/core/game_base.gd). Файл — data/balance/game.tres.

@export_group("Враги на поляне")
## Через сколько секунд появляется новый враг.
@export_range(0.0, 600.0, 1.0) var respawn := 75.0
## Доля быстрых врагов («Шныга») на поляне, 0..1.
@export_range(0.0, 1.0, 0.01) var fast_share := 0.4

@export_group("Кувшины снаружи")
## Сколько кувшинов снаружи одновременно, не больше.
@export_range(0, 50, 1) var out_jars_max := 4
## Новый кувшин снаружи — раз в столько секунд.
@export_range(0.0, 600.0, 1.0) var out_jar_every := 25.0

@export_group("Кровотечение и починка")
## Сколько длится кровотечение, с.
@export_range(0.0, 120.0, 0.5) var bleed_time := 10.0
## Урон кровотечения в секунду.
@export_range(0.0, 50.0, 0.5) var bleed_dps := 3.0
## Один заряд ремкомплекта возвращает такую долю прочности (0.5 — +50%).
@export_range(0.0, 1.0, 0.05) var repair_part := 0.5

@export_group("Сохранения")
## Автосохранение раз в столько секунд.
@export_range(10.0, 3600.0, 10.0) var autosave := 120.0
## Аварийная копия сейва — раз в столько секунд.
@export_range(5.0, 3600.0, 5.0) var crash_save := 30.0

@export_group("Расстановка (не баланс)")
## Места, куда не ставить кувшины в бункере: [точка, радиус м].
@export var chest_avoid: Array = []
## Руины снаружи (точки).
@export var ruins: Array[Vector3] = []
