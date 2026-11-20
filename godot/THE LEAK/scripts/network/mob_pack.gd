extends RefCounted
## Враги и мутанты по сети компактно (промпт 20.11 18:41): 7 чисел float32 на моба вместо массива
## со строками состояния и вида. Неизвестные строки уходят отдельным словарём xs: nid → [состояние, вид].

const STATES := ["idle", "chase", "investigate", "return", "crawl", "dead", "windup", "leap", "leap_prep",
	"leap_rec", "recover", "rise", "stagger", "throw", "spit", "swipe", "lunge", "charge", "roar",
	"slam_prep", "spit_prep", "flee", "stunned"]
const KINDS := ["heavy", "fast", "spitter", "charger", "stalker"]


## Добавляет моба в посылку: nid, код (состояние + 256·вид + 65536·охотник), x, y, z, поворот, hp.
static func put(buf: PackedFloat32Array, xs: Dictionary, nid: int, kind: String, pos: Vector3, rot: float, state: String, hp: float, hunter := false) -> void:
	var si: int = STATES.find(state)
	var ki: int = KINDS.find(kind)
	if si < 0 or ki < 0:
		xs[nid] = [state, kind]
	var code: int = (si if si >= 0 else 255) + 256 * (ki if ki >= 0 else 255) + (65536 if hunter else 0)
	buf.append(float(nid))
	buf.append(float(code))
	buf.append(pos.x)
	buf.append(pos.y)
	buf.append(pos.z)
	buf.append(rot)
	buf.append(hp)


## Посылка обратно в строки [nid, вид, позиция, поворот, состояние, hp, охотник] — как раньше слались массивы.
static func rows(buf: PackedFloat32Array, xs: Dictionary) -> Array:
	var out: Array = []
	var i := 0
	while i + 6 < buf.size():
		var nid := int(buf[i])
		var code := int(buf[i + 1])
		var si: int = code & 255
		var ki: int = (code >> 8) & 255
		var x: Array = xs.get(nid, ["", ""])
		var st: String = STATES[si] if si < STATES.size() else String(x[0])
		var kd: String = KINDS[ki] if ki < KINDS.size() else String(x[1])
		out.append([nid, kd, Vector3(buf[i + 2], buf[i + 3], buf[i + 4]), buf[i + 5], st, buf[i + 6], (code & 65536) != 0])
		i += 7
	return out
