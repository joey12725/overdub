class_name AudioFormulas
extends RefCounted
## Which Harmonograph formulas level designers may assign to a cassette layer (MUSIC-02), and the
## extra layer-shaping keys the audio module reads from TrackMusicDef.params (prototype
## src/audio/formulas.ts). Pure data derived from the engine catalogue; no nodes.

## Categories whose formulas produce a pitch contour. "Harmony" formulas describe chord choice /
## voicing and "Expression" formulas are velocity ramps, so as a layer's main contour they would
## produce a static or saw-tooth line; they are deliberately not offered.
const CONTOUR_CATEGORIES: Array[String] = [HGFormula.CATEGORY_NUMBER, HGFormula.CATEGORY_DYNAMICAL, HGFormula.CATEGORY_GEOMETRY]
## A drum layer's formula drives its hat lane through a hit threshold, so gate formulas suit it too.
const DRUM_CATEGORIES: Array[String] = [HGFormula.CATEGORY_NUMBER, HGFormula.CATEGORY_DYNAMICAL, HGFormula.CATEGORY_GEOMETRY, HGFormula.CATEGORY_RHYTHM]

## Role defaults for the layer-shaping keys. AudioDirector builds its channels from these, so the
## values listed to content authors are the values actually used.
const ROLE_DEFAULTS: Dictionary = {
	# Eighth-note line with a tresillo-like E(5,8) gate; strong beats lean on chord tones.
	&"melody": {"rate": 0.5, "pulses": 5, "steps": 8, "gravity": 0.5, "contour": 0.15},
	# Tresillo E(3,8) on chord tones only.
	&"bass": {"rate": 0.5, "pulses": 3, "steps": 8, "gravity": 0.8, "contour": 0.1},
	# One chord per half bar at 1x; register follows the formula.
	&"chord": {"rate": 2.0, "pulses": 1, "steps": 1, "gravity": 0.5, "contour": 0.2},
	# Sixteenth-note kit.
	&"drums": {"rate": 0.25, "pulses": 1, "steps": 1, "gravity": 0.0, "contour": 0.0},
}

## Layer-shaping keys accepted in TrackMusicDef.params alongside the formula's own parameters.
## None of them collides with an engine formula parameter, so one flat params map carries both.
const LAYER_KEYS: Array[String] = ["rate", "register", "pulses", "steps", "gravity", "contour", "cycle", "phrase", "threshold", "density"]

## Role defaults used when a level names a formula that is unknown or unsuitable for its role.
const FALLBACK_FORMULA: Dictionary = {&"melody": "sine", &"bass": "triangle", &"chord": "sine", &"drums": "euclid"}

static var _allowed: Dictionary = {}


## One entry of list_music_formulas().
class Info:
	extends RefCounted
	var id: String = ""
	var name: String = ""
	var category: String = ""
	## The engine's own one-line equation.
	var equation: String = ""
	## Roles this formula is safe for (MusicRole.*).
	var roles: Array[StringName] = []
	var params: Array[HGParamDef] = []


## Descriptions of the layer-shaping keys, for content tooling (formulas.ts LAYER_PARAMS).
static func layer_params() -> Array[Dictionary]:
	var all_roles: Array = [MusicRole.MELODY, MusicRole.BASS, MusicRole.CHORD, MusicRole.DRUMS]
	var pitched: Array = [MusicRole.MELODY, MusicRole.BASS, MusicRole.CHORD]
	return [
		{"key": "rate", "label": "Step length", "min": 0.25, "max": 4.0, "step": 0.0, "roles": all_roles,
			"default": _per_role("rate", all_roles),
			"description": "Beats per step at 1x tape speed; snapped to a power of two (0.25, 0.5, 1, 2, 4) so every tape speed stays on the master grid."},
		{"key": "register", "label": "Octave shift", "min": -1.0, "max": 1.0, "step": 1.0, "roles": pitched, "default": 0.0,
			"description": "Moves the layer range by whole octaves."},
		{"key": "pulses", "label": "Gate pulses", "min": 1.0, "max": 16.0, "step": 1.0, "roles": pitched,
			"default": _per_role("pulses", pitched),
			"description": "Euclidean gate E(pulses, steps): how many steps of each gate cycle sound."},
		{"key": "steps", "label": "Gate steps", "min": 1.0, "max": 16.0, "step": 1.0, "roles": pitched,
			"default": _per_role("steps", pitched),
			"description": "Length of the Euclidean gate cycle in steps."},
		{"key": "gravity", "label": "Chord gravity", "min": 0.0, "max": 1.0, "step": 0.01, "roles": [MusicRole.MELODY, MusicRole.BASS],
			"default": _per_role("gravity", [MusicRole.MELODY, MusicRole.BASS]),
			"description": "How strongly metrically strong steps are pulled onto chord tones (bass always plays chord tones)."},
		{"key": "contour", "label": "Arch blend", "min": 0.0, "max": 0.8, "step": 0.01, "roles": pitched,
			"default": _per_role("contour", pitched),
			"description": "Blend of a phrase-long arch over the raw formula contour (smooths wild formulas)."},
		{"key": "cycle", "label": "Cycle", "min": 4.0, "max": 64.0, "step": 1.0, "roles": all_roles, "default": 16.0,
			"description": "Period P (in steps) for wave formulas and for retrograde reflection."},
		{"key": "phrase", "label": "Phrase", "min": 4.0, "max": 32.0, "step": 1.0, "roles": pitched, "default": 16.0,
			"description": "Phrase length in steps; the last step of each phrase cadences on the chord root."},
		{"key": "threshold", "label": "Hit threshold", "min": 0.15, "max": 0.95, "step": 0.01, "roles": [MusicRole.DRUMS], "default": 0.5,
			"description": "Formula height needed for a hat hit: the drum layer's formula plays its hat lane."},
		{"key": "density", "label": "Groove density", "min": 0.25, "max": 2.0, "step": 0.05, "roles": [MusicRole.DRUMS], "default": 1.0,
			"description": "Scales the genre groove pulses (kick, snare, perc)."},
	]


static func _per_role(key: String, roles: Array) -> Dictionary:
	var out := {}
	for r: StringName in roles:
		out[String(r)] = ROLE_DEFAULTS[r][key]
	return out


static func _roles_for(category: String) -> Array[StringName]:
	var roles: Array[StringName] = []
	if CONTOUR_CATEGORIES.has(category):
		roles.append_array([MusicRole.MELODY, MusicRole.BASS, MusicRole.CHORD])
	if DRUM_CATEGORIES.has(category):
		roles.append(MusicRole.DRUMS)
	return roles


## Every engine formula a level designer may use for some role, with its parameters.
static func list_music_formulas() -> Array[Info]:
	var out: Array[Info] = []
	for f: HGFormula in Harmonograph.catalogue():
		var roles := _roles_for(f.category)
		# "groove" is a drum-only formula: its value is a kit pattern, not a contour.
		if f.id == "groove":
			roles = [MusicRole.DRUMS]
		if roles.is_empty():
			continue
		var info := Info.new()
		info.id = f.id
		info.name = f.name
		info.category = f.category
		info.equation = f.equation
		info.roles = roles
		info.params = f.params
		out.append(info)
	return out


static func is_music_formula_allowed(role: StringName, id: String) -> bool:
	if _allowed.is_empty():
		for info: Info in list_music_formulas():
			_allowed[info.id] = info.roles
	var roles: Array = _allowed.get(id, [])
	return roles.has(role)


## The formula a layer will actually use (falls back rather than failing a level load).
static func resolve_formula(role: StringName, id: String) -> String:
	if is_music_formula_allowed(role, id):
		return id
	return FALLBACK_FORMULA.get(role, "sine")


## Splits TrackMusicDef.params into [formula params (engine-cleaned), layer params].
static func split_params(formula: String, params: Dictionary[String, float]) -> Array[Dictionary]:
	var formula_raw: Dictionary[String, float] = {}
	var layer: Dictionary[String, float] = {}
	for k: String in params:
		var v: float = params[k]
		if is_nan(v) or is_inf(v):
			continue
		if LAYER_KEYS.has(k):
			layer[k] = v
		else:
			formula_raw[k] = v
	return [Harmonograph.clean_params(formula, formula_raw), layer]
