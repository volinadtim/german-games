extends Node
## Держит окно в рамках экрана (промпт 00:32): если окно больше ~90% области родителя
## (обычно CenterContainer на весь экран), уменьшает его масштаб вокруг центра.
## Пересчитывается при изменении размера окна игры и самого окна.
## Подключение: preload("res://scripts/ui/ui_fit.gd").attach(panel)

const FRAC := 0.9

var target: Control


static func attach(c: Control) -> void:
	var f: Node = load("res://scripts/ui/ui_fit.gd").new()
	f.set("target", c)
	c.add_child(f)


func _ready() -> void:
	target.resized.connect(_fit)
	target.visibility_changed.connect(_fit)
	var p := target.get_parent()
	if p is Control:
		# Окно больше экрана растягивает CenterContainer по своему минимуму; по умолчанию он растёт
		# вправо-вниз от (0,0), и окно съезжает вниз — масштаб вокруг центра его уже не спасал
		# (промпт 02:33, окно продажи). Растём в обе стороны — центр контейнера остаётся в центре экрана.
		(p as Control).grow_horizontal = Control.GROW_DIRECTION_BOTH
		(p as Control).grow_vertical = Control.GROW_DIRECTION_BOTH
		(p as Control).resized.connect(_fit)
	get_viewport().size_changed.connect(_fit)
	_fit.call_deferred()


func _fit() -> void:
	if not is_instance_valid(target):
		return
	var area := target.get_viewport_rect().size
	var p := target.get_parent()
	if p is Control and (p as Control).size.x > 0 and (p as Control).size.y > 0:
		area = area.min((p as Control).size)
	var s := target.size.max(target.get_combined_minimum_size())
	if s.x <= 0 or s.y <= 0 or area.x <= 0 or area.y <= 0:
		return
	var k := minf(1.0, minf(area.x * FRAC / s.x, area.y * FRAC / s.y))
	target.pivot_offset = target.size * 0.5
	target.scale = Vector2(k, k)
