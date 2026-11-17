class_name MenuFormat
extends RefCounted
## Node-free text formatting for gear, weapons and levels (prototype ui/menus/format.ts). Everything a
## player reads about an item's mechanics is produced here so it can be tested headless
## (APPAREL-03, WEAPON-01..04). Never instantiated.

## U+2212 minus, as the prototype prints negative deltas.
const MINUS := "−"


# ───────────────────────────── slots ─────────────────────────────

class SlotLabel:
	extends RefCounted
	## Big label on the slot tile. APPAREL-03 requires these categories be plainly identified.
	var title: String
	## What kind of thing goes there.
	var kind: String
	## Short code for compact places (paper-doll pins).
	var short: String
	## Which mechanics this category tends to touch (APPAREL-01 category descriptions).
	var touches: String

	func _init(p_title: String, p_kind: String, p_short: String, p_touches: String) -> void:
		title = p_title
		kind = p_kind
		short = p_short
		touches = p_touches


static var _slot_labels: Dictionary[StringName, SlotLabel] = {}


static func slot_label(slot: StringName) -> SlotLabel:
	if _slot_labels.is_empty():
		_slot_labels[GearSlot.HELMET] = SlotLabel.new("HELMET / HEADGEAR", "Headgear", "HEAD", "Enemy awareness, hazard protection, beat readability")
		_slot_labels[GearSlot.TOP] = SlotLabel.new("TOP", "Shirt / top / jacket", "TOP", "Impact, interaction reach, desync behaviour")
		_slot_labels[GearSlot.PANTS] = SlotLabel.new("PANTS", "Legwear", "LEGS", "Acceleration, control, momentum retention, dodge recovery")
		_slot_labels[GearSlot.SHOES] = SlotLabel.new("SHOES", "Footwear", "FEET", "Speed, traction, dodge character, momentum transfer")
		_slot_labels[GearSlot.MELEE] = SlotLabel.new("MELEE", "Melee weapon", "MEL", "Reach, arc, swing timing, knockback and stagger")
		_slot_labels[GearSlot.RANGED] = SlotLabel.new("RANGED", "Ranged weapon", "RNG", "Projectile behaviour, speed, range, penetration")
	if _slot_labels.has(slot):
		return _slot_labels[slot]
	var s := String(slot).to_upper()
	return SlotLabel.new(s, String(slot).capitalize(), s.left(4), "")


# ───────────────────────────── numbers ─────────────────────────────

## Fixed digits, then trailing zeros trimmed: 1.50 -> "1.5", 2.00 -> "2" (JS toFixed semantics).
static func num(n: float, digits: int = 2) -> String:
	if is_nan(n) or is_inf(n):
		return "—"
	var s := ("%." + str(digits) + "f") % n
	if digits > 0 and s.contains("."):
		while s.ends_with("0"):
			s = s.left(s.length() - 1)
		if s.ends_with("."):
			s = s.left(s.length() - 1)
	return s


## Local ticks -> seconds at 1x (ticks are recorded at LOCAL_HZ in wall time; TIME-02).
static func ticks_to_seconds(ticks: float) -> String:
	return "%s s" % num(ticks / OD.LOCAL_HZ, 2)


static func speed_label(s: float) -> String:
	return "½×" if s == 0.5 else "%s×" % num(s, 2)


## OD.EndMode -> "Stop" / "Repeat" / "Reverse".
static func end_mode_label(m: int) -> String:
	match m:
		OD.EndMode.STOP:
			return "Stop"
		OD.EndMode.REPEAT:
			return "Repeat"
		OD.EndMode.REVERSE:
			return "Reverse"
	return "?"


static func theme_label(t: StringName) -> String:
	match t:
		LevelTheme.UPPER:
			return "Upper ruins"
		LevelTheme.MID:
			return "Retrofit layer"
		LevelTheme.LOWER:
			return "Inscribed depths"
		LevelTheme.CORE:
			return "The core"
	return String(t).capitalize()


## Percent delta for multipliers: 1.1 -> "+10%", 0.85 -> "−15%".
static func pct(mul: float) -> String:
	var d := roundi((mul - 1.0) * 100.0)
	if d == 0:
		return "±0%"
	return "+%d%%" % d if d > 0 else "%s%d%%" % [MINUS, absi(d)]


# ───────────────────────────── stat mods & abilities ─────────────────────────────

## Prototype stat key -> player label, in declaration order (= StatMods.KEY_TO_FIELD order).
const MOD_LABELS: Dictionary[String, String] = {
	"moveSpeed": "Run speed",
	"accel": "Acceleration",
	"momentumRetention": "Momentum kept on turns",
	"dodgeDistance": "Dodge distance",
	"dodgeIframes": "Dodge invulnerability",
	"dodgeCooldown": "Dodge cooldown",
	"meleeImpact": "Melee impact",
	"damage": "Damage",
	"knockback": "Knockback",
	"knockbackCap": "Max knockback",
	"stagger": "Stagger",
	"approachBonus": "Running-strike bonus",
	"sparkSpeed": "Recovery spark speed",
	"interactRadiusAdd": "Interact reach",
	"projectileSpeed": "Projectile speed",
	"rangedCooldown": "Ranged cooldown",
}
## Lower values are better for the player (cooldowns).
const MOD_LOWER_IS_BETTER: Array[String] = ["dodgeCooldown", "rangedCooldown"]
## Additive mods measured in a unit.
const MOD_ADD_UNITS: Dictionary[String, String] = {"interactRadiusAdd": "tiles"}


static func mod_keys() -> Array[String]:
	var out: Array[String] = []
	out.assign(MOD_LABELS.keys())
	return out


static func mod_label(key: String) -> String:
	return MOD_LABELS.get(key, key)


## Neutral value of a modifier (1 for multipliers, 0 for adds).
static func mod_neutral(key: String) -> float:
	return StatMods.identity_of(key)


static func format_mod_value(key: String, v: float) -> String:
	if StatMods.is_additive(key):
		var unit: String = MOD_ADD_UNITS.get(key, "")
		var sgn := "+" if v > 0.0 else (MINUS if v < 0.0 else "±")
		return "%s%s%s" % [sgn, num(absf(v)), (" " + unit) if not unit.is_empty() else ""]
	return pct(v)


## +1 if the change helps the player, -1 if it hurts, 0 if neutral.
static func mod_direction(key: String, from: float, to: float) -> int:
	if absf(to - from) < 1e-9:
		return 0
	var up := 1 if to > from else -1
	return -up if MOD_LOWER_IS_BETTER.has(key) else up


static func _mod_value(mods: StatMods, key: String) -> float:
	return mods.get_stat(key) if mods != null else mod_neutral(key)


## "Run speed +10%", "Interact reach +0.75 tiles". Neutral mods are omitted.
static func mod_lines(mods: StatMods) -> Array[String]:
	var out: Array[String] = []
	if mods == null:
		return out
	for key in mod_keys():
		var v := mods.get_stat(key)
		if absf(v - mod_neutral(key)) < 1e-9:
			continue
		out.append("%s %s" % [mod_label(key), format_mod_value(key, v)])
	return out


const ABILITY_TEXT: Dictionary[StringName, Array] = {
	&"manualDesync": ["Manual desync", "Ability button knocks this self out of sync on purpose."],
	&"lowProfile": ["Low profile", "Enemies treat you as farther away than you are."],
	&"loudmouth": ["Loudmouth", "Enemies treat you as nearer than you are — draws aggro."],
	&"beatSight": ["Beat sight", "Upcoming enemy attack beats show on the master ruler."],
	&"laserProof": ["Laser-proof", "Laser beams do not kill you."],
	&"heavyStep": ["Heavy step", "Standing on heavy plates holds them down."],
	&"phaseDodge": ["Phase dodge", "Dodge passes through enemies and low barriers."],
	&"slideStrike": ["Slide strike", "Ending a dodge into a strike adds momentum."],
	&"parry": ["Parry", "Heavy attacks reflect projectiles inside the swing arc."],
	&"killRefresh": ["Kill refresh", "A melee kill refunds your dodge cooldown."],
}


static func ability_name(a: StringName) -> String:
	return ABILITY_TEXT[a][0] if ABILITY_TEXT.has(a) else String(a)


static func ability_text(a: StringName) -> String:
	return ABILITY_TEXT[a][1] if ABILITY_TEXT.has(a) else ""


static func ability_line(a: StringName) -> String:
	return "%s: %s" % [ability_name(a), ability_text(a)] if ABILITY_TEXT.has(a) else String(a)


# ───────────────────────────── weapons ─────────────────────────────

class StatRow:
	extends RefCounted
	var label: String
	var value: String

	func _init(p_label: String, p_value: String) -> void:
		label = p_label
		value = p_value


static func _swing_row(name: String, s: MeleeSwingDef) -> StatRow:
	var total := s.windup + s.active + s.recover
	return StatRow.new(name, "%s windup · %s hit · %s recover (%s total at 1×)" % [
		ticks_to_seconds(s.windup), ticks_to_seconds(s.active), ticks_to_seconds(s.recover), ticks_to_seconds(total)])


## Qualitative word for an efficiency multiplier, so "1.4×" reads as a character, not a spreadsheet.
static func eff_word(eff: float) -> String:
	if eff >= 1.35:
		return "very high"
	if eff >= 1.1:
		return "high"
	if eff > 0.9:
		return "standard"
	if eff > 0.65:
		return "low"
	return "very low"


static func melee_style_name(style: StringName) -> String:
	match style:
		MeleeStyle.BLADE:
			return "Blade"
		MeleeStyle.BLUNT:
			return "Blunt"
		MeleeStyle.WHIP:
			return "Whip"
		MeleeStyle.GAUNTLET:
			return "Gauntlet"
	return String(style).capitalize()


## Readable numbers for a melee weapon (WEAPON-04: reach, arc, windup, recovery, impact, stagger,
## knockback).
static func melee_stat_rows(m: MeleeWeaponDef) -> Array[StatRow]:
	return [
		StatRow.new("Style", melee_style_name(m.style)),
		StatRow.new("Reach", "%s tiles" % num(m.reach)),
		StatRow.new("Arc", "%s°" % num(m.arc_deg, 0)),
		_swing_row("Light", m.light),
		_swing_row("Heavy", m.heavy),
		StatRow.new("Impact", "light %s · heavy %s" % [num(m.light.impact), num(m.heavy.impact)]),
		StatRow.new("Damage", "%s× (%s)" % [num(m.damage_eff), eff_word(m.damage_eff)]),
		StatRow.new("Knockback", "%s× (%s)" % [num(m.knockback_eff), eff_word(m.knockback_eff)]),
		StatRow.new("Stagger", "%s× (%s)" % [num(m.stagger_eff), eff_word(m.stagger_eff)]),
	]


## Ranged archetype -> [name, blurb, inherent downside].
const ARCHETYPE: Dictionary[StringName, Array] = {
	&"missile": [
		"Homing missile",
		"Locks the nearest enemy once, at launch, and tracks it.",
		# WEAPON-02: the slowness is the point.
		"Very slow, and never retargets — the fight has time to change before it lands.",
	],
	&"pierce": [
		"Piercing shot",
		"Fast straight shot that passes through enemies in a line.",
		"Flies dead straight with no tracking; it must be aimed into the line.",
	],
	&"phase": [
		"Phase shot",
		"Passes through walls and closed doors.",
		"Flies straight with no tracking; walls never stop it, so neither does cover you meant to hide behind.",
	],
	&"arc": [
		"Lobbed shot",
		"Arcs over low cover and enemies, hitting a small area where it lands.",
		"Lands where you aimed, not where the target went — slow to arrive.",
	],
	&"burst": [
		"Burst",
		"Several projectiles in a spread at short range.",
		"Short range; the spread thins out with distance.",
	],
}


static func archetype_name(a: StringName) -> String:
	return ARCHETYPE[a][0] if ARCHETYPE.has(a) else String(a).capitalize()


static func archetype_blurb(a: StringName) -> String:
	return ARCHETYPE[a][1] if ARCHETYPE.has(a) else ""


## The weapon's stated downside. Item data may carry its own (GearItem.downside); otherwise the
## archetype's inherent trade-off is stated, plus any numeric outliers that a player would feel.
static func ranged_downside(r: RangedWeaponDef, item_downside: String = "") -> String:
	if not item_downside.is_empty():
		return item_downside
	var extra: Array[String] = []
	if r.cooldown >= OD.LOCAL_HZ:
		extra.append("long cooldown (%s)" % ticks_to_seconds(r.cooldown))
	if r.commit >= OD.LOCAL_HZ / 3.0:
		extra.append("you are committed for %s per shot" % ticks_to_seconds(r.commit))
	var base: String = ARCHETYPE[r.archetype][2] if ARCHETYPE.has(r.archetype) else ""
	if extra.is_empty():
		return base
	return ("%s Also: %s." % [base, "; ".join(extra)]).strip_edges()


## Readable numbers for a ranged weapon (WEAPON-01..03).
static func ranged_stat_rows(r: RangedWeaponDef) -> Array[StatRow]:
	var speed_note := ""
	if r.speed < 4.0:
		speed_note = " (very slow)"
	elif r.speed >= 14.0:
		speed_note = " (fast)"
	var rows: Array[StatRow] = [
		StatRow.new("Type", archetype_name(r.archetype)),
		StatRow.new("Behaviour", archetype_blurb(r.archetype)),
		StatRow.new("Speed", "%s tiles/s%s" % [num(r.speed, 1), speed_note]),
		StatRow.new("Range", "%s tiles" % num(r.max_range, 1)),
		StatRow.new("Impact", num(r.impact)),
		StatRow.new("Fire", "%s commit · %s cooldown" % [ticks_to_seconds(r.commit), ticks_to_seconds(r.cooldown)]),
	]
	if r.count > 1:
		rows.append(StatRow.new("Spread", "%d projectiles over %s°" % [r.count, num(r.spread_deg, 0)]))
	if r.pierce > 0:
		rows.append(StatRow.new("Pierce", "passes through %d %s" % [r.pierce, "enemy" if r.pierce == 1 else "enemies"]))
	if r.passes_walls:
		rows.append(StatRow.new("Walls", "passes through walls and closed doors"))
	if r.lobbed:
		rows.append(StatRow.new("Trajectory", "lobbed over low cover"))
	if r.turn_rate > 0.0:
		rows.append(StatRow.new("Homing", "%s°/s turn, one lock at launch" % num(r.turn_rate * 180.0 / PI, 0)))
	if r.blast > 0.0:
		rows.append(StatRow.new("Blast", "%s tile radius" % num(r.blast)))
	if r.has_min_range and r.min_range > 0.0:
		rows.append(StatRow.new("Min range", "never lands closer than %s tiles" % num(r.min_range)))
	return rows


## Every player-readable mechanical line for an item, effect first (APPAREL-03).
static func item_detail_rows(item: GearItem) -> Array[StatRow]:
	var rows: Array[StatRow] = []
	if item.melee != null:
		rows.append_array(melee_stat_rows(item.melee))
	if item.ranged != null:
		rows.append_array(ranged_stat_rows(item.ranged))
		rows.append(StatRow.new("Downside", ranged_downside(item.ranged, item.downside)))
	for line in mod_lines(item.mods):
		var i := line.rfind(" ")
		rows.append(StatRow.new(line.left(i), line.substr(i + 1)))
	for a in item.abilities:
		rows.append(StatRow.new(ability_name(a), ability_text(a)))
	return rows


## Compact one-liner for weapon cards in lists; "" for apparel.
static func weapon_headline(item: GearItem) -> String:
	if item.melee != null:
		var m := item.melee
		return "%s · reach %s · %s° arc · light %s windup" % [
			melee_style_name(m.style), num(m.reach), num(m.arc_deg, 0), ticks_to_seconds(m.light.windup)]
	if item.ranged != null:
		var r := item.ranged
		return "%s · %s tiles/s · %s tiles" % [archetype_name(r.archetype), num(r.speed, 1), num(r.max_range, 1)]
	return ""


# ───────────────────────────── comparison ─────────────────────────────

class CompareRow:
	extends RefCounted
	var label: String
	var from: String
	var to: String
	## +1 better for the player, -1 worse, 0 unchanged / not comparable.
	var dir: int

	func _init(p_label: String, p_from: String, p_to: String, p_dir: int) -> void:
		label = p_label
		from = p_from
		to = p_to
		dir = p_dir


static func _cmp_num(label: String, a: float, b: float, fmt: Callable, lower_is_better: bool = false) -> CompareRow:
	var d := 0 if absf(b - a) < 1e-9 else (1 if b > a else -1)
	return CompareRow.new(label, fmt.call(a), fmt.call(b), -d if lower_is_better else d)


static func _cmp_swing(name: String, a: MeleeSwingDef, b: MeleeSwingDef) -> Array[CompareRow]:
	var ta := a.windup + a.active + a.recover
	var tb := b.windup + b.active + b.recover
	var secs := func(n: float) -> String: return ticks_to_seconds(n)
	return [
		_cmp_num("%s windup" % name, a.windup, b.windup, secs, true),
		_cmp_num("%s total" % name, ta, tb, secs, true),
		_cmp_num("%s impact" % name, a.impact, b.impact, func(n: float) -> String: return num(n)),
	]


static func _yes_no(v: bool) -> String:
	return "yes" if v else "no"


## Comparison of a candidate against the currently equipped item of the same slot. Rows that are
## identical are kept only when they help orient the reader (weapons always show their core numbers).
static func compare_items(equipped: GearItem, candidate: GearItem) -> Array[CompareRow]:
	var rows: Array[CompareRow] = []
	var tiles := func(n: float) -> String: return "%s tiles" % num(n)
	var mul := func(n: float) -> String: return "%s×" % num(n)
	var plain := func(n: float) -> String: return num(n)
	var whole := func(n: float) -> String: return str(roundi(n))
	var secs := func(n: float) -> String: return ticks_to_seconds(n)
	if equipped.melee != null and candidate.melee != null:
		var a := equipped.melee
		var b := candidate.melee
		rows.append(_cmp_num("Reach", a.reach, b.reach, tiles))
		rows.append(_cmp_num("Arc", a.arc_deg, b.arc_deg, func(n: float) -> String: return "%s°" % num(n, 0)))
		rows.append_array(_cmp_swing("Light", a.light, b.light))
		rows.append_array(_cmp_swing("Heavy", a.heavy, b.heavy))
		rows.append(_cmp_num("Damage", a.damage_eff, b.damage_eff, mul))
		rows.append(_cmp_num("Knockback", a.knockback_eff, b.knockback_eff, mul))
		rows.append(_cmp_num("Stagger", a.stagger_eff, b.stagger_eff, mul))
	if equipped.ranged != null and candidate.ranged != null:
		var a := equipped.ranged
		var b := candidate.ranged
		rows.append(CompareRow.new("Type", archetype_name(a.archetype), archetype_name(b.archetype), 0))
		rows.append(_cmp_num("Speed", a.speed, b.speed, func(n: float) -> String: return "%s t/s" % num(n, 1)))
		rows.append(_cmp_num("Range", a.max_range, b.max_range, func(n: float) -> String: return "%s tiles" % num(n, 1)))
		rows.append(_cmp_num("Impact", a.impact, b.impact, plain))
		rows.append(_cmp_num("Cooldown", a.cooldown, b.cooldown, secs, true))
		rows.append(_cmp_num("Commit", a.commit, b.commit, secs, true))
		if a.pierce != b.pierce:
			rows.append(_cmp_num("Pierce", a.pierce, b.pierce, whole))
		if a.count != b.count:
			rows.append(_cmp_num("Projectiles", a.count, b.count, whole))
		if a.blast != b.blast:
			rows.append(_cmp_num("Blast", a.blast, b.blast, tiles))
		if a.passes_walls != b.passes_walls:
			rows.append(CompareRow.new("Through walls", _yes_no(a.passes_walls), _yes_no(b.passes_walls), 0))
		if a.lobbed != b.lobbed:
			rows.append(CompareRow.new("Lobbed", _yes_no(a.lobbed), _yes_no(b.lobbed), 0))
	for key in mod_keys():
		var va := _mod_value(equipped.mods, key)
		var vb := _mod_value(candidate.mods, key)
		if absf(va - vb) < 1e-9:
			continue
		rows.append(CompareRow.new(mod_label(key), format_mod_value(key, va), format_mod_value(key, vb), mod_direction(key, va, vb)))
	for a in equipped.abilities:
		if not candidate.abilities.has(a):
			rows.append(CompareRow.new(ability_name(a), "yes", "lost", -1))
	for b in candidate.abilities:
		if not equipped.abilities.has(b):
			rows.append(CompareRow.new(ability_name(b), "—", "gained", 1))
	return rows
