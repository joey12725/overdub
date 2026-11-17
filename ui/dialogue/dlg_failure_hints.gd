class_name DlgFailureHints
extends RefCounted
## Failure hints for the decision screen (docs/ONBOARDING.md "Failure hints";
## data/onboarding/failure_hints.json). Node-free.
##
## Each note of a failed resolved run (Outcome.notes, written by core/objective.gd) is matched
## against the `ignore` regexes, then against `hints` in file order; the first whose regex matches the
## whole note is its hint. A note's signature is the hint id plus the values of the capture groups in
## `signature` (never the beat). Streaks per level visit: after each failed run, signatures present
## get +1 and absent ones are dropped; a win clears everything; retry / commit / reset do not.
## on_resolved() returns the hint to show on the next decision screen: of the signatures with a
## streak >= showAfter whose hint has not been shown this visit, the earliest hint in file order.
##
##   var h := DlgFailureHints.load_file()
##   h.begin_level(level_id)
##   var line := h.on_resolved(outcome)      # "" = nothing to say

const DEFAULT_PATH := "res://data/onboarding/failure_hints.json"

class Hint:
	extends RefCounted
	var id: String = ""
	var re: RegEx = null
	var signature: Array[String] = []
	var text: String = ""
	var order: int = 0


## One classified note.
class Match:
	extends RefCounted
	var hint: Hint = null
	var signature: String = ""
	var tape: String = ""
	var note: String = ""


var show_after: int = 2
var hints: Array[Hint] = []
var ignores: Array[RegEx] = []
var errors: Array[String] = []
## The hint chosen by the last on_resolved() (null = none) and the note it matched.
var last: Match = null
var _streak: Dictionary[String, int] = {}
var _shown: Dictionary[String, bool] = {}


static func load_file(p_path: String = DEFAULT_PATH) -> DlgFailureHints:
	var h := DlgFailureHints.new()
	if not FileAccess.file_exists(p_path):
		h.errors.append("failure hints missing: %s" % p_path)
		return h
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(p_path))
	if parsed is Dictionary:
		h.load_data(parsed)
	else:
		h.errors.append("failure hints are not a JSON object: %s" % p_path)
	return h


func load_data(d: Dictionary) -> void:
	hints.clear()
	ignores.clear()
	var rules: Variant = d.get("rules", {})
	if rules is Dictionary:
		show_after = int((rules as Dictionary).get("showAfter", show_after))
	for ig: Variant in d.get("ignore", []):
		if ig is Dictionary:
			var re := _compile(str((ig as Dictionary).get("match", "")), "ignore %s" % (ig as Dictionary).get("id", "?"))
			if re != null:
				ignores.append(re)
	var arr: Variant = d.get("hints", [])
	if not (arr is Array):
		errors.append("failure hints: no 'hints' array")
		return
	for i in (arr as Array).size():
		var e: Variant = (arr as Array)[i]
		if not (e is Dictionary):
			continue
		var ed: Dictionary = e
		var h := Hint.new()
		h.id = str(ed.get("id", "hint-%d" % i))
		h.order = i
		h.text = str(ed.get("text", ""))
		h.re = _compile(str(ed.get("match", "")), h.id)
		var sig: Variant = ed.get("signature", [])
		if sig is Array:
			for s: Variant in sig:
				h.signature.append(str(s))
		if h.re == null:
			continue
		for s: String in h.signature:
			if not h.re.get_names().has(s):
				errors.append("%s: signature group '%s' is not in its regex" % [h.id, s])
		hints.append(h)


func _compile(src: String, what: String) -> RegEx:
	if src == "":
		errors.append("%s: no regex" % what)
		return null
	var re := RegEx.new()
	if re.compile(src) != OK:
		errors.append("%s: regex does not compile" % what)
		return null
	return re


## Start of a level visit: streaks and shown hints reset.
func begin_level(_level_id: String = "") -> void:
	_streak.clear()
	_shown.clear()
	last = null


## The hint a note resolves to (null when ignored or unmatched).
func classify(note: String) -> Match:
	for ig: RegEx in ignores:
		if _full(ig, note) != null:
			return null
	for h: Hint in hints:
		var m := _full(h.re, note)
		if m == null:
			continue
		var out := Match.new()
		out.hint = h
		out.note = note
		var parts: Array[String] = [h.id]
		for s: String in h.signature:
			parts.append(m.get_string(s))
		out.signature = "|".join(parts)
		if h.re.get_names().has("tape"):
			out.tape = m.get_string("tape")
		return out
	return null


static func _full(re: RegEx, s: String) -> RegExMatch:
	var m := re.search(s)
	if m != null and m.get_start() == 0 and m.get_end() == s.length():
		return m
	return null


## Record a resolved run; returns the hint text for the next decision screen ("" = none).
func on_resolved(outcome: Outcome) -> String:
	last = null
	if outcome == null:
		return ""
	if outcome.win:
		_streak.clear()
		return ""
	var present: Dictionary[String, Match] = {}
	for note: String in outcome.notes:
		var m := classify(note)
		if m != null and not present.has(m.signature):
			present[m.signature] = m
	var next: Dictionary[String, int] = {}
	for sig: String in present:
		next[sig] = _streak.get(sig, 0) + 1
	_streak = next
	var best: Match = null
	for sig: String in present:
		var m: Match = present[sig]
		if _streak[sig] < show_after or _shown.has(m.hint.id):
			continue
		if best == null or m.hint.order < best.hint.order:
			best = m
	if best == null:
		return ""
	_shown[best.hint.id] = true
	last = best
	return render(best)


## The hint's text with {tape} as the HUD names the cassette ("Tape A").
static func render(m: Match) -> String:
	var t := m.hint.text
	if t.contains("{tape}"):
		t = t.replace("{tape}", "Tape " + m.tape if m.tape != "" else "this tape")
	return t


## Longest current streak (for the coach `failures` view of the layer).
func max_streak() -> int:
	var n := 0
	for k: String in _streak:
		n = maxi(n, _streak[k])
	return n
