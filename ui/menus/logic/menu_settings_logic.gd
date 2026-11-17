class_name MenuSettingsLogic
extends MenuSource
## Settings screen logic (prototype ui/menus/logic.ts SettingsLogic). Values change optimistically
## (shown at once) and leave as `setting` intents; the game's set_settings() echo overwrites them with
## the authoritative values. Erasing the save needs a confirm step that defaults to "keep".

const VOLUME_STEP := 0.05
const AV_OFFSET_STEP := 5
## Bluetooth headphones commonly add 150–250 ms; leave headroom both ways.
const AV_OFFSET_MIN := -300
const AV_OFFSET_MAX := 300

const KIND_VOLUME: StringName = &"volume"
const KIND_OFFSET: StringName = &"offset"
const KIND_TOGGLE: StringName = &"toggle"
const KIND_CHOICE: StringName = &"choice"

## Rendering quality. Not a SaveSettings field in the contract yet: the row emits
## UiIntent.setting("quality", "auto" | "high" | "low") and reads the value back from
## set_settings() when SaveSettings has a `quality` property (String / StringName).
const QUALITY_KEY := "quality"
const QUALITY_OPTIONS: Array[String] = ["auto", "high", "low"]

## Settings the UI offers that SaveSettings may not have yet (data/accessibility/options.json and
## docs/DIALOGUE.md "Save data"): prototype key -> SaveSettings field. Each row emits
## UiIntent.setting(key, value); the value is read back from set_settings() when SaveSettings has
## the field, else the UI keeps it for the session (and applies the UI-side effect itself).
const EXTRA_FIELDS: Dictionary = {
	"quality": "quality",
	"cassettePalette": "cassette_palette",
	"highContrast": "high_contrast",
	"reduceFlashing": "reduce_flashing",
	"shakeScale": "shake_scale",
	"textScale": "text_scale",
	"holdMode": "hold_mode",
	"voices": "voices",
	"barks": "barks",
	"coachMarks": "coach_marks",
	"textSpeed": "text_speed",
}


class SettingRow:
	extends RefCounted
	## SaveSettings key in prototype spelling (also the menu entry id).
	var key: String
	var label: String
	## KIND_*
	var kind: StringName
	var help: String
	## KIND_CHOICE: the values, and their chip labels.
	var options: Array = []
	var option_labels: Array[String] = []
	## Value when neither SaveSettings nor the session has one.
	var default: Variant = null
	## Section heading shown above this row ("" = same section as the row before).
	var section: String = ""

	func _init(p_key: String, p_label: String, p_kind: StringName, p_help: String) -> void:
		key = p_key
		label = p_label
		kind = p_kind
		help = p_help

	func choice(p_options: Array, p_labels: Array[String], p_default: Variant) -> SettingRow:
		options = p_options
		option_labels = p_labels
		default = p_default
		return self

	func toggle(p_default: bool) -> SettingRow:
		default = p_default
		return self

	func in_section(t: String) -> SettingRow:
		section = t
		return self


static var _rows: Array[SettingRow] = []


static func setting_rows() -> Array[SettingRow]:
	if _rows.is_empty():
		_rows = [
			SettingRow.new("master", "Master volume", KIND_VOLUME, "Everything.").in_section("SOUND & PICTURE"),
			SettingRow.new("music", "Music", KIND_VOLUME, "The four cassette layers and the world groove."),
			SettingRow.new("sfx", "Sound effects", KIND_VOLUME, "Hits, steps, doors — they still land on the beat."),
			SettingRow.new("avOffsetMs", "Audio / visual offset", KIND_OFFSET,
				"Delays the picture to match late audio (e.g. Bluetooth headphones). Positive = picture later."),
			SettingRow.new("screenShake", "Screen shake", KIND_TOGGLE, "Camera kick on heavy impacts."),
			SettingRow.new("patterns", "Cassette patterns", KIND_TOGGLE,
				"Adds a pattern to each cassette (A stripes, B dots, C chevrons, D grid) so tapes read without colour."),
			SettingRow.new(QUALITY_KEY, "Quality", KIND_CHOICE,
				"Rendering detail. Auto lets the game pick for this machine; Low is lighter on older GPUs.").choice(
				["auto", "high", "low"], ["AUTO", "HIGH", "LOW"], "auto"),
			SettingRow.new("cassettePalette", "Cassette colours", KIND_CHOICE,
				"Standard, or a high-contrast set that also separates the four tapes by lightness.").choice(
				["default", "high_contrast"], ["STANDARD", "HIGH CONTRAST"], "default").in_section("READABILITY"),
			SettingRow.new("highContrast", "High-contrast outlines", KIND_TOGGLE,
				"Thicker outlines and a light rim around selves, enemies, sparks and hazards.").toggle(false),
			SettingRow.new("reduceFlashing", "Reduce flashing", KIND_TOGGLE,
				"Removes full-screen flashes, strobing lights and flicker. States stay readable through shapes and outlines.").toggle(false),
			SettingRow.new("shakeScale", "Shake strength", KIND_CHOICE,
				"How hard the camera kicks on heavy impacts when screen shake is on.").choice(
				[1.0, 0.4], ["FULL", "REDUCED"], 1.0),
			SettingRow.new("textScale", "Text size", KIND_CHOICE, "Size of dialogue, hints and menu text.").choice(
				[1.0, 1.15, 1.3, 1.5], ["100%", "115%", "130%", "150%"], 1.0),
			SettingRow.new("holdMode", "Hold actions", KIND_CHOICE,
				"Hold to confirm, or press once to arm and again to confirm.").choice(
				["hold", "press"], ["HOLD", "PRESS TWICE"], "hold"),
			SettingRow.new("voices", "Character voices", KIND_TOGGLE, "Spoken lines in dialogue and barks.").toggle(true).in_section("STORY & HINTS"),
			SettingRow.new("voiceVolume", "Voice volume", KIND_VOLUME, "Spoken lines, apart from music and sound effects."),
			SettingRow.new("barks", "Barks", KIND_TOGGLE, "Short quips from Moxie and the radio while you play.").toggle(true),
			SettingRow.new("coachMarks", "Coach marks", KIND_TOGGLE, "One-line tips pointing at the thing they explain. Each shows once.").toggle(true),
			SettingRow.new("textSpeed", "Text speed", KIND_CHOICE, "How fast dialogue types on.").choice(
				[0.75, 1.0, 1.5, 2.5], ["SLOW", "NORMAL", "FAST", "FASTEST"], 1.0),
		]
	return _rows


static func row(key: String) -> SettingRow:
	for r in setting_rows():
		if r.key == key:
			return r
	return null


static func format_setting(key: String, v: Variant) -> String:
	var r := row(key)
	if r != null and r.kind == KIND_CHOICE and not r.option_labels.is_empty():
		for i in r.options.size():
			if _same(r.options[i], v):
				return r.option_labels[i]
	if v is bool:
		return "On" if v else "Off"
	if v is String or v is StringName:
		return String(v).capitalize()
	if key == "avOffsetMs":
		var ms := roundi(float(v))
		return "%s%d ms" % ["+" if ms > 0 else (MenuFormat.MINUS if ms < 0 else ""), absi(ms)]
	return "%d%%" % roundi(float(v) * 100.0)


var settings: SaveSettings = SaveSettings.new()
## "auto" / "high" / "low" (see QUALITY_KEY).
var quality: String = "auto"
var confirming_erase: bool = false
## Values of EXTRA_FIELDS keys SaveSettings does not hold (kept for the session).
var extras: Dictionary = {}

var _emit: Callable
var _leave: Callable
var _focus_req: String = ""


func _init(emit: Callable, leave: Callable) -> void:
	_emit = emit
	_leave = leave


func set_model(s: SaveSettings) -> void:
	settings = s.copy()
	if QUALITY_KEY in s:
		var q := String(s.get(QUALITY_KEY))
		if QUALITY_OPTIONS.has(q):
			quality = q
	# The echo is authoritative for every extra the save already holds.
	for key: String in EXTRA_FIELDS:
		var field: String = EXTRA_FIELDS[key]
		if key != QUALITY_KEY and field in s:
			var v: Variant = s.get(field)
			if v != null:
				extras[key] = v


static func _same(a: Variant, b: Variant) -> bool:
	if (a is float or a is int) and (b is float or b is int):
		return is_equal_approx(float(a), float(b))
	if (a is String or a is StringName) and (b is String or b is StringName):
		return String(a) == String(b)
	return typeof(a) == typeof(b) and a == b


static func is_extra(key: String) -> bool:
	return EXTRA_FIELDS.has(key) and key != QUALITY_KEY


func on_show() -> void:
	confirming_erase = false


## Current value by key (float for volumes / offset, bool for toggles, String for quality).
func value_of(key: String) -> Variant:
	if key == QUALITY_KEY:
		return quality
	if is_extra(key):
		var r := row(key)
		return extras.get(key, r.default if r != null else null)
	var v: Variant = settings.get_by_key(key)
	if key == "avOffsetMs":
		return float(v)
	return v


## 0..1 position of a numeric setting on its slider.
func fraction_of(key: String) -> float:
	var v := float(value_of(key))
	if key == "avOffsetMs":
		return (v - AV_OFFSET_MIN) / float(AV_OFFSET_MAX - AV_OFFSET_MIN)
	return clampf(v, 0.0, 1.0)


static func snap_value(key: String, v: float) -> float:
	var out: float
	if key == "avOffsetMs":
		out = roundf(clampf(v, AV_OFFSET_MIN, AV_OFFSET_MAX) / AV_OFFSET_STEP) * AV_OFFSET_STEP
	else:
		# Volumes are stored on a 0.05 grid so repeated nudges never accumulate float drift.
		out = roundf(clampf(v, 0.0, 1.0) / VOLUME_STEP) * VOLUME_STEP
	return roundf(out * 1000.0) / 1000.0


## Set an absolute value (mouse drag on a slider, a toggle, a quality pick). Emits only real changes.
func set_value(key: String, value: Variant) -> void:
	if key == QUALITY_KEY:
		var q := String(value)
		if not QUALITY_OPTIONS.has(q) or q == quality:
			return
		quality = q
		_emit.call(UiIntent.setting(key, q))
		return
	if is_extra(key):
		var r := row(key)
		var nv: Variant = value
		if r != null and r.kind == KIND_TOGGLE:
			if not (nv is bool):
				return
		elif r != null and r.kind == KIND_CHOICE:
			var ok := false
			for o: Variant in r.options:
				if _same(o, nv):
					nv = o
					ok = true
			if not ok:
				return
		if _same(value_of(key), nv):
			return
		extras[key] = nv
		_emit.call(UiIntent.setting(key, nv))
		return
	var v: Variant = value
	if v is float or v is int:
		v = snap_value(key, float(v))
	var cur: Variant = value_of(key)
	if cur == null:
		return
	if typeof(cur) == typeof(v) and cur == v:
		return
	# Shown immediately; the game's set_settings() echo overwrites it with the authoritative value.
	if not settings.set_by_key(key, v):
		return
	_emit.call(UiIntent.setting(key, v))


func nudge(key: String, delta: int) -> void:
	var cur: Variant = value_of(key)
	var r := row(key)
	if key == QUALITY_KEY:
		var i := QUALITY_OPTIONS.find(quality)
		set_value(key, QUALITY_OPTIONS[posmod(i + delta, QUALITY_OPTIONS.size())])
	elif r != null and r.kind == KIND_CHOICE and not r.options.is_empty():
		var at := 0
		for i in r.options.size():
			if _same(r.options[i], cur):
				at = i
		set_value(key, r.options[posmod(at + delta, r.options.size())])
	elif cur is bool:
		set_value(key, not cur)
	else:
		var step: float = AV_OFFSET_STEP if key == "avOffsetMs" else VOLUME_STEP
		set_value(key, float(cur) + delta * step)


func menu() -> MenuDef:
	var entries: Array[MenuEntry] = []
	var rows := setting_rows()
	for row in rows.size():
		var r := rows[row]
		var key := r.key
		var e := MenuEntry.make(key, row, 0)
		e.on_adjust(func(d: int) -> void: nudge(key, d))
		if r.kind == KIND_TOGGLE or r.kind == KIND_CHOICE:
			e.accept = func() -> void: nudge(key, 1)
		entries.append(e)
	var erase_row := rows.size()
	if confirming_erase:
		entries.append(MenuEntry.make("erase-no", erase_row, 0, _cancel_erase))
		entries.append(MenuEntry.make("erase-yes", erase_row, 1, func() -> void:
			confirming_erase = false
			_focus_req = "erase"
			_emit.call(UiIntent.simple(UiIntentType.ERASE_SAVE))))
	else:
		entries.append(MenuEntry.make("erase", erase_row, 0, func() -> void:
			confirming_erase = true
			# Land on "keep" so a double press can never erase a save.
			_focus_req = "erase-no"))
	entries.append(MenuEntry.make("back", erase_row + 1, 0, func() -> void: _leave.call()))
	return MenuDef.make(entries, _back, "master")


func take_focus_request() -> String:
	var r := _focus_req
	_focus_req = ""
	return r


func _back() -> void:
	if confirming_erase:
		_cancel_erase()
	else:
		_leave.call()


func _cancel_erase() -> void:
	confirming_erase = false
	_focus_req = "erase"
