class_name DlgStoryData
extends RefCounted
## Loader and validator for data/story/story.json (format: docs/story/INTEGRATION.md). Node-free.
## Missing sections are empty, never errors: the story layer is optional and every lookup returns an
## empty array when there is nothing to say.
##
##   var story := DlgStoryData.load_file()            # res://data/story/story.json
##   story.level_lines("01-soft-open", "intro")       # Array[DlgLine]
##   story.barks("death"); story.once_lines("firstDeath"); story.ending_lines()
##   story.character("opal")                          # DlgStoryData.Character (name, color...)

const DEFAULT_PATH := "res://data/story/story.json"
## The hard cut in the ending (INTEGRATION.md: fade between line 6 and line 7, 1-based).
const ENDING_CUT_INDEX := 6
## Characters heard through Moxie's headphones get the radio treatment unless story.json says
## otherwise with "radio": false on the character.
const DEFAULT_RADIO: Array[String] = ["opal", "archivist"]
## INTEGRATION.md promises at most 76 characters per line (two box lines of about 45).
const MAX_LINE_CHARS := 76


class Character:
	extends RefCounted
	var id: String = ""
	var name: String = ""
	var color: Color = Color("#f3ead8")
	var portraits: Array[String] = []
	var radio: bool = false
	## Portrait side: true = left (Moxie), false = right (everyone else; INTEGRATION.md).
	var left: bool = false
	## Mirror the portrait horizontally. Off by default: the busts are drawn facing the text already
	## (Moxie faces right, Opal / Tolliver face left, the Archivist is frontal) and INTEGRATION.md
	## forbids mirroring Moxie (asymmetric face paint and strap). story.json may set "mirror": true.
	var mirror: bool = false


var path: String = ""
var characters: Dictionary[String, Character] = {}
var levels: Dictionary = {}
var once: Dictionary = {}
var bark_table: Dictionary = {}
var ending: Array[DlgLine] = []
var stinger: Array[DlgLine] = []
var chapters: Array = []
var tagline: String = ""
## Load problems (missing file, bad JSON). Content problems come from validate().
var errors: Array[String] = []


static func load_file(p_path: String = DEFAULT_PATH) -> DlgStoryData:
	var s := DlgStoryData.new()
	s.path = p_path
	if not FileAccess.file_exists(p_path):
		s.errors.append("story file missing: %s" % p_path)
		return s
	var txt := FileAccess.get_file_as_string(p_path)
	var parsed: Variant = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		s.errors.append("story file is not a JSON object: %s" % p_path)
		return s
	s.load_dict(parsed)
	return s


static func from_dict(d: Dictionary) -> DlgStoryData:
	var s := DlgStoryData.new()
	s.load_dict(d)
	return s


func load_dict(d: Dictionary) -> void:
	characters.clear()
	var chars: Variant = d.get("characters", [])
	if chars is Array:
		for c: Variant in chars:
			if not (c is Dictionary):
				continue
			var cd: Dictionary = c
			var ch := Character.new()
			ch.id = str(cd.get("id", ""))
			if ch.id == "":
				continue
			ch.name = str(cd.get("name", ch.id.capitalize()))
			var col := str(cd.get("color", ""))
			if col != "" and Color.html_is_valid(col):
				ch.color = Color.html(col)
			var ps: Variant = cd.get("portraits", [])
			if ps is Array:
				for p: Variant in ps:
					ch.portraits.append(str(p))
			ch.radio = cd.get("radio", DEFAULT_RADIO.has(ch.id)) == true
			ch.left = cd.get("side", "left" if ch.id == "moxie" else "right") == "left"
			ch.mirror = cd.get("mirror", false) == true
			characters[ch.id] = ch
	levels = d.get("levels", {}) if d.get("levels", {}) is Dictionary else {}
	once = d.get("once", {}) if d.get("once", {}) is Dictionary else {}
	bark_table = d.get("barks", {}) if d.get("barks", {}) is Dictionary else {}
	ending = DlgLine.list_from(d.get("ending", []))
	stinger = DlgLine.list_from(d.get("stinger", []))
	chapters = d.get("chapters", []) if d.get("chapters", []) is Array else []
	var title: Variant = d.get("title", {})
	tagline = str((title as Dictionary).get("tagline", "")) if title is Dictionary else ""


## The character, or a stand-in built from the id (so an unknown speaker still renders).
func character(id: String) -> Character:
	if characters.has(id):
		return characters[id]
	var ch := Character.new()
	ch.id = id
	ch.name = id.capitalize() if id != "" else "?"
	ch.left = id == "moxie"
	return ch


## levels[level_id][section] ("intro", "outro", "firstDeath", "firstDesync", "idle", ...).
func level_lines(level_id: String, section: String) -> Array[DlgLine]:
	var lv: Variant = levels.get(level_id, {})
	if lv is Dictionary:
		return DlgLine.list_from((lv as Dictionary).get(section, []))
	var none: Array[DlgLine] = []
	return none


func has_level_section(level_id: String, section: String) -> bool:
	return not level_lines(level_id, section).is_empty()


func once_lines(key: String) -> Array[DlgLine]:
	return DlgLine.list_from(once.get(key, []))


func barks(key: String) -> Array[DlgLine]:
	return DlgLine.list_from(bark_table.get(key, []))


## The ending with the hard cut marked on line ENDING_CUT_INDEX + 1 (0-based index 6).
func ending_lines() -> Array[DlgLine]:
	var out: Array[DlgLine] = []
	for i in ending.size():
		var l := ending[i].copy()
		l.cut_before = i == ENDING_CUT_INDEX or l.cut_before
		out.append(l)
	return out


## Content problems: unknown speaker, unknown expression, over-long lines, empty lines. Every line
## everywhere is checked. Returns human-readable strings ("levels.01-soft-open.intro[2]: ...").
func validate() -> Array[String]:
	var out: Array[String] = []
	for lk: Variant in _sorted_keys(levels):
		var lv: Variant = levels[lk]
		if not (lv is Dictionary):
			out.append("levels.%s: not an object" % lk)
			continue
		for sk: Variant in _sorted_keys(lv):
			_check_list("levels.%s.%s" % [lk, sk], (lv as Dictionary)[sk], out)
	for ok: Variant in _sorted_keys(once):
		_check_list("once.%s" % ok, once[ok], out)
	for bk: Variant in _sorted_keys(bark_table):
		_check_list("barks.%s" % bk, bark_table[bk], out)
	var raw_end: Array = []
	for l: DlgLine in ending:
		raw_end.append(l.to_dict())
	_check_list("ending", raw_end, out)
	var raw_st: Array = []
	for l: DlgLine in stinger:
		raw_st.append(l.to_dict())
	_check_list("stinger", raw_st, out)
	return out


func _check_list(where: String, v: Variant, out: Array[String]) -> void:
	if not (v is Array):
		out.append("%s: not an array" % where)
		return
	var arr: Array = v
	for i in arr.size():
		var l := DlgLine.from_dict(arr[i])
		var at := "%s[%d]" % [where, i]
		if l == null:
			out.append("%s: not an object" % at)
			continue
		if not characters.has(l.who):
			out.append("%s: unknown speaker '%s'" % [at, l.who])
		elif not characters[l.who].portraits.has(l.expression):
			out.append("%s: '%s' has no expression '%s'" % [at, l.who, l.expression])
		if l.line.strip_edges() == "":
			out.append("%s: empty line" % at)
		elif l.line.length() > MAX_LINE_CHARS:
			out.append("%s: %d characters (max %d)" % [at, l.line.length(), MAX_LINE_CHARS])


static func _sorted_keys(d: Dictionary) -> Array:
	var ks := d.keys()
	ks.sort()
	return ks
