class_name SaveSettings
extends RefCounted
## Player settings (types.ts SaveData['settings']). Defaults are the prototype's DEFAULT_SETTINGS
## (game/save.ts). Clamping / validation of loaded values is the save module's job.
##
## The first six fields are the prototype's. The rest are the Godot game's options
## (data/accessibility/options.json, docs/DIALOGUE.md "Save data", the audio voice options and the
## render quality). They are written to JSON only when they differ from their default, so a save
## that never touched them is byte-for-byte the prototype's format, and an old save simply loads
## them as defaults.

var master: float = 0.8
var music: float = 0.8
var sfx: float = 0.8
## Extra audio->visual delay in ms (e.g. Bluetooth).
var av_offset_ms: int = 0
var screen_shake: bool = true
## Colour-blind friendly cassette patterns.
var patterns: bool = false

# ── Godot game options (written only when not at their default) ──
## AccessKit set id: "default" or "high_contrast".
var cassette_palette: String = "default"
## Thicker outlines and a light rim (actors, world, HUD).
var high_contrast: bool = false
## No large-area flashes, steady lamps, calmer pulses.
var reduce_flashing: bool = false
## Screen-shake strength when screen_shake is on (1 full, 0.4 reduced).
var shake_scale: float = 1.0
## Text size multiplier (dialogue, hints, menus).
var text_scale: float = 1.0
## "hold" (hold to confirm) or "press" (press once to arm, again to confirm).
var hold_mode: String = "hold"
## Spoken lines (dialogue, barks, count-in).
var voices: bool = true
## Short quips while playing.
var barks: bool = true
## One-line onboarding tips.
var coach_marks: bool = true
## Dialogue typing speed multiplier.
var text_speed: float = 1.0
## Voice volume 0..1.
var voice_volume: float = 1.0
## Render quality: "auto", "high" or "low".
var quality: String = "auto"

const CASSETTE_PALETTES: Array[String] = ["default", "high_contrast"]
const HOLD_MODES: Array[String] = ["hold", "press"]
const QUALITIES: Array[String] = ["auto", "high", "low"]
## Allowed ranges of the numeric options (values outside are clamped).
const SHAKE_SCALE_RANGE: Vector2 = Vector2(0.0, 1.0)
const TEXT_SCALE_RANGE: Vector2 = Vector2(0.75, 2.0)
const TEXT_SPEED_RANGE: Vector2 = Vector2(0.25, 4.0)

## Prototype key (JSON, UiIntent 'setting' key) -> field name.
const KEY_TO_FIELD: Dictionary[String, StringName] = {
	"master": &"master",
	"music": &"music",
	"sfx": &"sfx",
	"avOffsetMs": &"av_offset_ms",
	"screenShake": &"screen_shake",
	"patterns": &"patterns",
	"cassettePalette": &"cassette_palette",
	"highContrast": &"high_contrast",
	"reduceFlashing": &"reduce_flashing",
	"shakeScale": &"shake_scale",
	"textScale": &"text_scale",
	"holdMode": &"hold_mode",
	"voices": &"voices",
	"barks": &"barks",
	"coachMarks": &"coach_marks",
	"textSpeed": &"text_speed",
	"voiceVolume": &"voice_volume",
	"quality": &"quality",
}

## The prototype's six keys: always written.
const PROTOTYPE_KEYS: Array[String] = ["master", "music", "sfx", "avOffsetMs", "screenShake", "patterns"]


## Value by prototype key ("avOffsetMs"); null for an unknown key.
func get_by_key(key: String) -> Variant:
	var f: StringName = KEY_TO_FIELD.get(key, &"")
	return get(f) if f != &"" else null


## Set by prototype key with type coercion (float/int/bool/String as the field needs). Returns false
## for an unknown key or a value of the wrong kind (or a choice outside its list).
func set_by_key(key: String, value: Variant) -> bool:
	match key:
		"master", "music", "sfx", "voiceVolume":
			if not ODJson.is_number(value):
				return false
			set(KEY_TO_FIELD[key], float(value))
		"avOffsetMs":
			if not ODJson.is_number(value):
				return false
			av_offset_ms = roundi(float(value))
		"shakeScale", "textScale", "textSpeed":
			if not ODJson.is_number(value):
				return false
			var f := float(value)
			if is_nan(f) or is_inf(f):
				return false
			var r: Vector2 = SHAKE_SCALE_RANGE if key == "shakeScale" else (TEXT_SCALE_RANGE if key == "textScale" else TEXT_SPEED_RANGE)
			set(KEY_TO_FIELD[key], clampf(f, r.x, r.y))
		"screenShake", "patterns", "highContrast", "reduceFlashing", "voices", "barks", "coachMarks":
			if not (value is bool):
				return false
			set(KEY_TO_FIELD[key], value)
		"cassettePalette", "holdMode", "quality":
			if not (value is String or value is StringName):
				return false
			var s := String(value)
			var allowed: Array[String] = CASSETTE_PALETTES if key == "cassettePalette" else (HOLD_MODES if key == "holdMode" else QUALITIES)
			if not allowed.has(s):
				return false
			set(KEY_TO_FIELD[key], s)
		_:
			return false
	return true


func copy() -> SaveSettings:
	var o := SaveSettings.new()
	for key: String in KEY_TO_FIELD:
		var f: StringName = KEY_TO_FIELD[key]
		o.set(f, get(f))
	return o


## Missing / wrong-typed keys keep the defaults.
static func from_dict(d: Dictionary) -> SaveSettings:
	var o := SaveSettings.new()
	o.master = ODJson.num(d, "master", o.master)
	o.music = ODJson.num(d, "music", o.music)
	o.sfx = ODJson.num(d, "sfx", o.sfx)
	o.av_offset_ms = ODJson.integer(d, "avOffsetMs", o.av_offset_ms)
	o.screen_shake = ODJson.boolean(d, "screenShake", o.screen_shake)
	o.patterns = ODJson.boolean(d, "patterns", o.patterns)
	o.apply_extras(d)
	return o


## Read the Godot-only options from a JSON dictionary through set_by_key (invalid values are
## ignored and keep the current value).
func apply_extras(d: Dictionary) -> void:
	for key: String in KEY_TO_FIELD:
		if PROTOTYPE_KEYS.has(key) or not d.has(key):
			continue
		set_by_key(key, d[key])


func to_dict() -> Dictionary:
	var out := {
		"master": master,
		"music": music,
		"sfx": sfx,
		"avOffsetMs": av_offset_ms,
		"screenShake": screen_shake,
		"patterns": patterns,
	}
	var def := SaveSettings.new()
	for key: String in KEY_TO_FIELD:
		if PROTOTYPE_KEYS.has(key):
			continue
		var f: StringName = KEY_TO_FIELD[key]
		var v: Variant = get(f)
		if v != def.get(f):
			out[key] = v
	return out
