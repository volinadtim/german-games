extends OmniLight3D
## Лампа: ровный свет с лёгким дрожанием или мерцание с короткими провалами.

var base_energy := 1.5
var flicker := true
var lamp_mat: StandardMaterial3D

var _t := 0.0
var _off := 0.0
var _next := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_t = _rng.randf_range(0.0, 100.0)
	_next = _rng.randf_range(0.5, 4.0)


func _process(delta: float) -> void:
	_t += delta
	var k := 1.0
	if flicker:
		if _off > 0.0:
			_off -= delta
			k = _rng.randf_range(0.0, 0.2)
		else:
			_next -= delta
			if _next <= 0.0:
				_off = _rng.randf_range(0.04, 0.4)
				# иногда серия быстрых морганий, иногда долгая пауза
				_next = _rng.randf_range(0.05, 0.3) if _rng.randf() < 0.5 else _rng.randf_range(1.5, 6.0)
			k = 0.88 + 0.12 * sin(_t * 23.0) * sin(_t * 7.3)
	else:
		k = 0.97 + 0.03 * sin(_t * 50.0)
	light_energy = base_energy * k
	if lamp_mat:
		lamp_mat.emission_energy_multiplier = 3.0 * k
