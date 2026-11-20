@tool
class_name DashConfig
extends Resource
## Рывок (scripts/player/dash.gd). Файл — data/balance/dash.tres.

## Скорость в начале рывка, м/с.
@export_range(0.0, 50.0, 0.5) var speed := 18.0
## Длительность рывка, с.
@export_range(0.0, 2.0, 0.01) var time := 0.18
## Задержка между рывками, с.
@export_range(0.0, 10.0, 0.05) var cooldown := 0.8
## Нажатие Shift короче этого (с) — рывок; дольше — бег.
@export_range(0.0, 1.0, 0.01) var tap_max := 0.12
