extends Node
## Одноразовый конвертер DataTable (словарь values) -> типизированные ресурсы. Переписывает data/**/*.tres на месте.
##   godot --headless --path "godot/THE LEAK" res://tests/tools/convert_data.tscn -- <таблица> [<таблица>…]
## Проверка 1:1 — tests/tools/data_snapshot.tscn (снимок static var до и после).

var used := {}   # ключи старой таблицы, которые перенесены


func _ready() -> void:
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/tools/data_map.json"))
	for t in OS.get_cmdline_user_args():
		if spec.has(t):
			_conv_spec(t, spec[t])
		elif has_method("_conv_" + t):
			call("_conv_" + t)
		else:
			push_error("нет конвертера " + t)
	get_tree().quit()


## Старое значение по ключу (словари — в исходном порядке).
func _v(old: Resource, key: String):
	used[key] = true
	return old.call("v", key)


## Простые поля: {СТАРЫЙ_КЛЮЧ: "поле"}.
func _map(res: Resource, old: Resource, m: Dictionary) -> void:
	for k in m:
		var val = _v(old, k)
		var cur = res.get(m[k])
		if cur is Dictionary and cur.is_typed():
			cur.clear()
			for kk in val:
				cur[kk] = _cast(val[kk], cur.get_typed_value_builtin())
		elif cur is Array and cur.is_typed():
			cur.clear()
			for x in val:
				cur.append(_cast(x, cur.get_typed_builtin()))
		else:
			res.set(m[k], val)
		if typeof(res.get(m[k])) != typeof(cur):
			push_error("%s: %s — тип %s, а в старом %s" % [res.resource_path, m[k], type_string(typeof(cur)), type_string(typeof(val))])


func _cast(x, t: int):
	if t == TYPE_PACKED_INT32_ARRAY:
		return PackedInt32Array(x)
	if t == TYPE_FLOAT:
		return float(x)
	return x


func _save(res: Resource, old: Resource, path: String) -> void:
	for k in old.get("values"):
		if not used.has(k):
			push_error("%s: ключ %s не перенесён" % [path, k])
	used.clear()
	var err := ResourceSaver.save(res, path)
	print("CONV %s -> %s (%s)" % [path, res.get_script().get_global_name(), error_string(err)])


# ---------- автоматы ----------

func _conv_slots() -> void:
	var names: Dictionary = _v(load("res://data/slots/symbols.tres"), "NAMES")
	used.clear()
	_conv_killbox(names)
	_conv_cashy(names)
	_conv_klev()
	_conv_radiation()


func _conv_killbox(names: Dictionary) -> void:
	var path := "res://data/slots/killbox.tres"
	var old := load(path)
	var c := KillboxConfig.new()
	_map(c, old, {"COST": "spin_price", "STICK": "stick", "STICK_BOOST": "stick_boost", "WIN_CUT": "win_cut",
		"SEVENS_RARE_W": "sevens_rare_weight", "SEVENS_REROLL": "sevens_reroll", "PAIR_MAX_LEVEL": "pair_max_level",
		"HIGH_PAY_FROM": "high_pay_from_level", "HIGH_PAY_MULT": "high_pay_mult", "PROFIT_CAP": "profit_cap",
		"CHAIN": "chain_mults", "CHAIN_DIST": "chain_dist", "CHAIN_IDLE": "chain_idle", "SHIELD_MAX": "shield_max",
		"APPLE_PRICE": "apple_price", "STRIP": "strip", "TRAY_MAX": "tray_max", "CAP_TEXT": "cap_text",
		"CAP_CHARS": "cap_chars", "CAP_SPEED": "cap_speed", "CUT_LEN": "cutscene_len", "R": "reel_radius",
		"RW": "reel_width", "REEL_Y": "reel_y", "REEL_Z": "reel_z", "TEX": "strip_tex_px", "K": "scale",
		"PED": "podium_h", "RIG_Z": "rig_z", "EX": "body_extra", "PITCH": "reel_pitch", "HL_COLORS": "highlight_colors",
		"TRAY_X": "tray_x", "TRAY_Z0": "tray_z0", "TRAY_Z1": "tray_z1"})
	var w: Dictionary = _v(old, "WEIGHTS")
	var pay: Dictionary = _v(old, "PAY")
	var pay2: Dictionary = _v(old, "PAY2")
	var luck: Dictionary = _v(old, "LUCK")
	var boost: Dictionary = _v(old, "BOOST")
	for id in _v(old, "SYM_ORDER"):
		var s := KillboxSymbol.new()
		s.id = id
		s.title = names.get(id, id)
		s.weight = w.get(id, 0.0)
		var p: Dictionary = pay.get(id, {})
		s.pay_3 = p.get(3, 0)
		s.pay_4 = p.get(4, 0)
		s.pay_5 = p.get(5, 0)
		s.pay_pair = pay2.get(id, 0)
		if luck.has(id):
			s.guarantee_spins = luck[id][0]
			for x in luck[id].slice(1):
				s.guarantee_prices.append(x)
		if boost.has(id):
			s.boost_spins = boost[id][0]
			s.boost_price = boost[id][1]
		c.symbols.append(s)
	for pk in _v(old, "PACKS"):
		var sp := SlotSpinPack.new()
		sp.spins = pk[0]
		sp.price = pk[1]
		c.packs.append(sp)
	var ls: Array = _v(old, "LEVEL_SYMS")
	var gm: Array = _v(old, "GUAR_MAX")
	var lv: Array = _v(old, "LEVELS")
	for i in lv.size():
		var l := SlotWindowLevel.new()
		l.rows = lv[i][0]
		l.reels = lv[i][1]
		l.price = lv[i][2]
		l.symbols = ls[i]
		l.guarantee_max = gm[i]
		c.levels.append(l)
	# выводятся из уровней (последний уровень — полное окно)
	for k in ["MAX_LEVEL", "REELS", "ROWS"]:
		_v(old, k)
	_save(c, old, path)


func _grid(c: GridSlotConfig, old: Resource) -> void:
	_map(c, old, {"COST": "spin_price", "BETS": "bets", "LINES": "lines", "PROFIT_CAP": "profit_cap",
		"SPIN_T": "spin_time", "STEP_T": "step_time", "W": "screen_w", "H": "screen_h", "X0": "field_x0",
		"CW": "cell_w", "GAP": "cell_gap", "TOP": "field_top", "CH": "cell_h"})


func _base_sym(s: SlotSymbol, id: String, old: Resource, names: Dictionary) -> void:
	s.id = id
	s.title = names.get(id, id)
	s.weight = _v(old, "WEIGHT").get(id, 0.0)
	s.pay_3 = _v(old, "PAY").get(id, 0)


const CASHY_NAMES := {"bonus": "Бонуска", "jack": "Корона"}
const KLEV_NAMES := {"worm": "Червяк", "float": "Поплавок", "boot": "Сапог", "perch": "Окунь", "pike": "Щука",
	"catfish": "Сом", "fisher": "Рыбак"}
const RAD_NAMES := {"can": "Банка", "tire": "Шина", "rat": "Крыса", "mask": "Противогаз", "neon": "Неоновая 7",
	"barrel": "Бочка"}


func _conv_cashy(names: Dictionary) -> void:
	var path := "res://data/slots/cashy_box.tres"
	var old := load(path)
	var c := CashyBoxConfig.new()
	_grid(c, old)
	_map(c, old, {"FREE_2": "free_spins_2", "FREE_2_BONUS": "free_spins_2_in_bonus", "FREE_3": "bonus_game_spins",
		"BONUS_MULT": "bonus_game_mult", "BONUS_BUY": "bonus_buy_spins", "JACK_BASE": "jackpot_start",
		"JACK_WIN": "jackpot_win", "MINI_JACK": "mini_jackpot", "SEVENS_REROLL": "sevens_reroll",
		"TEASE_T": "tease_time", "REEL_V": "reel_speed", "DEC_T": "stop_time", "DEC_T_TEASE": "stop_time_tease",
		"EASE_C1": "stop_overshoot"})
	var nm := names.merged(CASHY_NAMES)
	var guar: Dictionary = _v(old, "GUAR")
	for id in _v(old, "SYMS"):
		var s := CashySymbol.new()
		_base_sym(s, id, old, nm)
		if guar.has(id):
			s.guarantee_spins = guar[id][0]
			s.guarantee_price = guar[id][1]
		c.symbols.append(s)
	_save(c, old, path)


func _conv_klev() -> void:
	var path := "res://data/slots/klev.tres"
	var old := load(path)
	var c := KlevConfig.new()
	_grid(c, old)
	_map(c, old, {"PIKE_CHANCE": "pike_chance", "DUCK_CHANCE": "duck_chance", "BUCKET": "bucket_size",
		"UHA_PAY": "uha_pay", "PIKE_T": "pike_time", "DUCK_T": "duck_time", "DUCK_DIVE": "duck_dive",
		"CAST_T": "cast_time", "PULL_T": "pull_time", "JOB_T": "catch_time", "UHA_T": "uha_time"})
	var fv: Dictionary = _v(old, "FISH_VAL")
	for id in _v(old, "SYMS"):
		var s := KlevSymbol.new()
		_base_sym(s, id, old, KLEV_NAMES)
		for x in fv.get(id, []):
			s.catch_values.append(x)
		c.symbols.append(s)
	_save(c, old, path)


func _conv_radiation() -> void:
	var path := "res://data/slots/radiation.tres"
	var old := load(path)
	var c := RadiationConfig.new()
	_grid(c, old)
	_map(c, old, {"RANK": "mutation_ranks", "GEIGER": "geiger_max", "MUT_T": "mutation_time", "BURST_T": "burst_time"})
	for id in _v(old, "SYMS"):
		var s := SlotSymbol.new()
		_base_sym(s, id, old, RAD_NAMES)
		c.symbols.append(s)
	_save(c, old, path)


# ---------- таблицы по data_map.json: простые поля — по карте, "=…" — в _post_<таблица> ----------

func _conv_spec(t: String, sp: Dictionary) -> void:
	var path: String = sp["path"]
	var old := load(path)
	var cls: Resource = null
	for g in ProjectSettings.get_global_class_list():
		if g["class"] == sp["class"]:
			cls = load(g["path"]).new()
	var simple := {}
	for k in sp["map"]:
		if not String(sp["map"][k]).begins_with("="):
			simple[k] = sp["map"][k]
	_map(cls, old, simple)
	if has_method("_post_" + t):
		call("_post_" + t, cls, old)
	_save(cls, old, path)


func _post_levels(c: LevelsConfig, old: Resource) -> void:
	for a in _v(old, "ATTRS"):
		var la := LevelAttr.new()
		la.id = a[0]
		la.title = a[1]
		la.desc = a[2]
		c.attrs.append(la)


func _post_perks(c: PerksConfig, old: Resource) -> void:
	for a in _v(old, "TREE"):
		var b := PerkBranch.new()
		b.id = a[0]
		b.title = a[1]
		b.desc = a[2]
		for x in a[3]:
			b.costs.append(x)
		c.branches.append(b)


func _post_mutant(c: MutantConfig, old: Resource) -> void:
	var kinds: Dictionary = _v(old, "KINDS")
	for id in kinds:
		var d: Dictionary = kinds[id]
		var k := MutantKind.new()
		k.id = id
		k.title = d["name"]
		k.hp = d["hp"]
		k.speed = d["speed"]
		k.height = d["h"]
		k.skin = d["skin"]
		k.glow = d["glow"]
		c.kinds.append(k)


func _post_guns(c: GunConfig, old: Resource) -> void:
	for a in _v(old, "MOD_SLOTS"):
		var s := GunModSlot.new()
		s.id = a[0]
		s.title = a[1]
		for x in a[2]:
			s.mods.append(x)
		c.mod_slots.append(s)


func _items(arr: Array, src: Array) -> void:
	for a in src:
		var it := ShopItem.new()
		it.id = a[0]
		it.price = a[1]
		arr.append(it)


func _sections(arr: Array, src: Array) -> void:
	for a in src:
		var s := ShopSection.new()
		s.title = a[0]
		for x in a[1]:
			s.items.append(x)
		arr.append(s)


func _post_melee(c: MeleeConfig, old: Resource) -> void:
	var w: Dictionary = _v(old, "WEAPONS")
	for id in w:
		var m := MeleeWeapon.new()
		m.id = id
		m.dmg_mult = w[id]["mult"]
		m.reach = w[id]["reach"]
		m.price = w[id]["price"]
		c.weapons.append(m)
	_items(c.shop, _v(old, "SHOP"))


func _post_shops(c: ShopsConfig, old: Resource) -> void:
	_items(c.ammo, _v(old, "AMMO_SHOP"))
	_items(c.mags, _v(old, "MAG_SHOP"))
	_items(c.guns, _v(old, "GUN_SHOP"))
	_items(c.mods, _v(old, "MOD_SHOP"))
	_items(c.tools, _v(old, "TOOLS"))
	_items(c.consumables, _v(old, "CONSUMABLES"))
	_sections(c.consumable_sections, _v(old, "CONS_SUBS"))
	_sections(c.clothes, _v(old, "CLOTHES"))


func _post_defaults(c: SettingsDefaults, old: Resource) -> void:
	var st: Dictionary = _v(old, "SETTINGS")
	for k in st:
		var d := SettingDef.new()
		d.key = k
		d.title = st[k][0]
		d.min_value = st[k][1]
		d.max_value = st[k][2]
		d.step = st[k][3]
		d.default_value = st[k][4]
		c.settings.append(d)


func _post_tables(c: ItemTables, old: Resource) -> void:
	for r in _v(old, "RECIPES"):
		var cr := CraftRecipe.new()
		cr.out = r["out"]
		for k in r["need"]:
			cr.need[k] = r["need"][k]
		cr.tool_id = r.get("tool", "")
		cr.wear = r.get("wear", 0)
		c.recipes.append(cr)
	for pair in [["SIZES", c.sizes], ["POCKETS", c.pockets]]:
		var src: Dictionary = _v(old, pair[0])
		for k in src:
			pair[1][k] = Vector2i(src[k][0], src[k][1])
