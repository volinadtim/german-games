extends Node
## Держит окно в рамках экрана (промпт 00:32): если окно больше ~90% области родителя
## (обычно CenterContainer на весь экран), уменьшает его масштаб вокруг центра.
## Пересчитывается при изменении размера окна игры и самого окна.
## Общий формат для всех общих окон (промпт 18.11 02:35): пока окно открыто, масштаб считается
## от самого большого размера содержимого за это открытие — переключение вкладок/категорий
## (настройки, магазин) с меньшим контентом не меняет видимый масштаб/ширину окна.
## При новом открытии (окно/его CanvasLayer стали видимы) запомненный размер сбрасывается.
## Подключение: preload("res://scripts/ui/ui_fit.gd").attach(panel)

const FRAC := 0.9

var target: Control
var _max_size := Vector2.ZERO
var _was_visible := false


static func attach(c: Control) -> void:
	var f: Node = load("res://scripts/ui/ui_fit.gd").new()
	f.set("target", c)
	c.add_child(f)


func _ready() -> void:
	target.resized.connect(_fit)
	target.visibility_changed.connect(_fit)
	var p := target.get_parent()
	while p:
		if p is Control:
			# Окно больше экрана растягивает CenterContainer по своему минимуму; по умолчанию он растёт
			# вправо-вниз от (0,0), и окно съезжает вниз — масштаб вокруг центра его уже не спасал
			# (промпт 02:33, окно продажи). Растём в обе стороны — центр контейнера остаётся в центре экрана.
			(p as Control).grow_horizontal = Control.GROW_DIRECTION_BOTH
			(p as Control).grow_vertical = Control.GROW_DIRECTION_BOTH
			(p as Control).resized.connect(_fit)
		if p.has_signal("visibility_changed"):
			p.visibility_changed.connect(_fit)   # CanvasLayer-окно (лут, продажа, магазин) скрывается выше panel
		p = p.get_parent()
	get_viewport().size_changed.connect(_fit)
	_fit.call_deferred()


## Видимо ли окно: is_visible_in_tree() не учитывает CanvasLayer-предков (это не CanvasItem),
## поэтому для окон вроде лута/продажи/магазина (CanvasLayer.visible) проверяем их отдельно.
func _is_open() -> bool:
	if not target.is_visible_in_tree():
		return false
	var p := target.get_parent()
	while p:
		if p is CanvasLayer and not p.visible:
			return false
		p = p.get_parent()
	return true


func _fit() -> void:
	if not is_instance_valid(target):
		return
	var vis := _is_open()
	if vis and not _was_visible:
		_max_size = Vector2.ZERO   # новое открытие окна — считаем масштаб заново от текущего содержимого
	_was_visible = vis
	if not vis:
		return
	var area := target.get_viewport_rect().size
	var p := target.get_parent()
	if p is Control and (p as Control).size.x > 0 and (p as Control).size.y > 0:
		area = area.min((p as Control).size)
	var s := target.size.max(target.get_combined_minimum_size())
	if s.x <= 0 or s.y <= 0 or area.x <= 0 or area.y <= 0:
		return
	_max_size = _max_size.max(s)
	var k := minf(1.0, minf(area.x * FRAC / _max_size.x, area.y * FRAC / _max_size.y))
	target.pivot_offset = target.size * 0.5
	target.scale = Vector2(k, k)
