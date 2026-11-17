extends Node
## Центральный микшер разовых звуков (промпт 18.11 01:47).
## Зачем: раньше каждый звук создавал свой AudioStreamPlayer3D, спам (сундук, багажник, рычаг)
## плодил десятки голосов, они складывались и били по ушам. Теперь:
##  - фиксированный пул 3D-голосов, новые звуки отбирают самый старый голос;
##  - одинаковый звук из одного места не складывается, а прерывает сам себя;
##  - есть глобальный бюджет новых звуков в кадр — звуковую атаку не устроить;
##  - на Master всегда последним стоит жёсткий лимитер (−3 дБ), оглохнуть нельзя.
## Узел живёт в группе "audio_mixer", чтобы статические помощники (slot_sounds.gd) его находили.

const GROUP := "audio_mixer"
const VOICES := 14            # сколько разовых 3D-звуков может звучать одновременно
const SAME_MIN := 0.06        # тот же звук чаще — просто игнорируем
const UI_MIN := 0.05          # тот же интерфейсный звук чаще — игнорируем
const BUDGET := 5             # не больше столько новых голосов за BUDGET_WIN
const BUDGET_WIN := 0.1
const MAX_DIST := 38.0        # дальше звук не слышно (раньше тянулся через всю карту)
const UNIT := 4.0
const CEIL_DB := -3.0

var _pool: Array[AudioStreamPlayer3D] = []
var _key: Array[String] = []
var _at: Array[float] = []
var _ui_last := {}
var _recent: Array[float] = []
var _lim: AudioEffectHardLimiter
var _check := 0.0


func _ready() -> void:
	add_to_group(GROUP)
	for i in VOICES:
		var p := AudioStreamPlayer3D.new()
		setup_3d(p)
		add_child(p)
		_pool.append(p)
		_key.append("")
		_at.append(-99.0)
	_ensure_limiter()


## Единые настройки затухания для любого 3D-звука в игре.
static func setup_3d(p: AudioStreamPlayer3D) -> void:
	p.unit_size = UNIT
	p.max_distance = MAX_DIST
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.max_polyphony = 1
	p.panning_strength = 1.0


func _process(delta: float) -> void:
	_check -= delta
	if _check <= 0.0:
		_check = 2.0
		_ensure_limiter()


## Лимитер на Master держим последним в цепочке: другие системы (реверб, эффекты смерти)
## добавляют свои эффекты позже, и без этого их выход шёл бы мимо лимитера.
func _ensure_limiter() -> void:
	var n := AudioServer.get_bus_effect_count(0)
	var idx := -1
	for e in n:
		if AudioServer.get_bus_effect(0, e) is AudioEffectHardLimiter:
			idx = e
			break
	if idx < 0:
		_lim = AudioEffectHardLimiter.new()
		_lim.ceiling_db = CEIL_DB
		_lim.pre_gain_db = 0.0
		AudioServer.add_bus_effect(0, _lim)
		return
	if idx < n - 1:
		var fx := AudioServer.get_bus_effect(0, idx)
		AudioServer.remove_bus_effect(0, idx)
		AudioServer.add_bus_effect(0, fx)


func _budget_ok(now: float) -> bool:
	while not _recent.is_empty() and now - _recent[0] > BUDGET_WIN:
		_recent.remove_at(0)
	return _recent.size() < BUDGET


## Разовый 3D-звук. key — «источник» звука: повтор с тем же ключом не складывается,
## а перезапускает тот же голос (спам сундука/багажника больше не наслаивается).
func play_3d(st: AudioStream, pos: Vector3, db: float, pitch := 1.0, key := "") -> void:
	if st == null:
		return
	var now := float(Time.get_ticks_msec()) * 0.001
	var k := key if key != "" else "%d" % st.get_instance_id()
	k += "@%d,%d,%d" % [roundi(pos.x * 0.5), roundi(pos.y * 0.5), roundi(pos.z * 0.5)]
	var slot := -1
	for i in _pool.size():
		if _key[i] == k and _pool[i].playing:
			if now - _at[i] < SAME_MIN:
				return
			slot = i
			break
	if slot < 0:
		if not _budget_ok(now):
			return
		var oldest := 0.0
		for i in _pool.size():
			if not _pool[i].playing:
				slot = i
				break
			if now - _at[i] > oldest:
				oldest = now - _at[i]
				slot = i
		_recent.append(now)
	var p := _pool[slot]
	_key[slot] = k
	_at[slot] = now
	p.stop()
	p.stream = st
	p.volume_db = db
	p.pitch_scale = pitch
	p.global_position = pos
	p.play()


## Нелокализованный звук интерфейса: тот же звук не чаще UI_MIN.
func ui_ok(name_: String) -> bool:
	var now := float(Time.get_ticks_msec()) * 0.001
	var last: float = _ui_last.get(name_, -99.0)
	if now - last < UI_MIN:
		return false
	_ui_last[name_] = now
	return true
