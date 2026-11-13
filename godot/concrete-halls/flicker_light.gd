@tool
extends OmniLight3D
## Лампа: ровный тёплый свет; у «больных» ламп — редкие случайные сбои (одно моргание, серия или долгий провал).

@export var base_energy := 0.8
@export var flicker := true
@export var lamp_mat: StandardMaterial3D

var _t := 0.0
var _off := 0.0        # сколько ещё лампа «провалена»
var _blinks := 0       # сколько морганий осталось в текущей серии
var _next := 0.0       # до следующего события
var _dim := 0.0        # глубина текущего провала
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(false)   # в редакторе не мигаем
		light_energy = base_energy
	_rng.randomize()
	_t = _rng.randf_range(0.0, 100.0)
	_next = _rng.randf_range(3.0, 15.0)


func _process(delta: float) -> void:
	_t += delta
	var k := 0.985 + 0.015 * sin(_t * 47.0) * sin(_t * 3.1)
	if flicker:
		if _off > 0.0:
			_off -= delta
			k *= _dim
		else:
			_next -= delta
			if _next <= 0.0:
				if _blinks <= 0:
					_blinks = [1, 1, 2, 3, 5][_rng.randi_range(0, 4)]
				_blinks -= 1
				_dim = _rng.randf_range(0.0, 0.45)
				_off = _rng.randf_range(0.04, 0.18) if _rng.randf() < 0.85 else _rng.randf_range(0.6, 1.8)
				if _blinks > 0:
					_next = _rng.randf_range(0.05, 0.25)
				else:
					_next = _rng.randf_range(4.0, 25.0)
	light_energy = base_energy * k
	if lamp_mat:
		lamp_mat.emission_energy_multiplier = 1.5 * k
