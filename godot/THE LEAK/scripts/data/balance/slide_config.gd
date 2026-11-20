@tool
class_name SlideConfig
extends Resource
## Подкат (scripts/player/slide.gd). Файл — data/balance/slide.tres.

## Минимальная скорость для начала подката, м/с.
@export_range(0.0, 20.0, 0.1) var min_start_speed := 5.2
## Импульс при входе в подкат (множитель скорости).
@export_range(1.0, 5.0, 0.05) var start_boost := 1.8
## Предел скорости при разгоне с горы, м/с.
@export_range(0.0, 50.0, 0.5) var max_speed := 16.5
## Скорость ниже этой — выход из подката, м/с.
@export_range(0.0, 20.0, 0.1) var stop_speed := 2.4
## Трение на ровной поверхности.
@export_range(0.0, 50.0, 0.5) var friction_flat := 7.5
## Ускорение/торможение от наклона поверхности.
@export_range(0.0, 100.0, 0.5) var slope_accel := 18.0
## Подруливание влево/вправо в подкате.
@export_range(0.0, 20.0, 0.1) var steer_force := 3.5
## Задержка перед следующим подкатом, с.
@export_range(0.0, 10.0, 0.05) var cooldown := 0.65
## Прыжок из подката: множитель горизонтальной скорости.
@export_range(0.0, 5.0, 0.01) var jump_fwd_mult := 1.45
## Прыжок из подката: множитель высоты.
@export_range(0.0, 5.0, 0.01) var jump_up_mult := 1.12
