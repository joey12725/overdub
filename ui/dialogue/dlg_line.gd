class_name DlgLine
extends RefCounted
## One spoken line (data/story/story.json `{ who, expression, line }`; docs/story/INTEGRATION.md).
## Node-free. `cut_before` marks a scene cut before this line (the ending's fade between the machine
## room and the surface); the player fades out and back in before typing it.

var who: String = ""
var expression: String = "neutral"
var line: String = ""
## Fade to black / key art before this line is shown (DialoguePlayer handles the fade).
var cut_before: bool = false


static func make(p_who: String, p_expression: String, p_line: String) -> DlgLine:
	var l := DlgLine.new()
	l.who = p_who
	l.expression = p_expression if p_expression != "" else "neutral"
	l.line = p_line
	return l


## From a story.json entry. Missing fields fall back to "" / "neutral"; a non-dictionary gives null.
static func from_dict(d: Variant) -> DlgLine:
	if not (d is Dictionary):
		return null
	var dd: Dictionary = d
	var l := make(str(dd.get("who", "")), str(dd.get("expression", "neutral")), str(dd.get("line", "")))
	l.cut_before = dd.get("cut", false) == true
	return l


## A typed array of lines from a JSON array; skips malformed entries.
static func list_from(v: Variant) -> Array[DlgLine]:
	var out: Array[DlgLine] = []
	if v is Array:
		for e: Variant in v:
			var l := from_dict(e)
			if l != null:
				out.append(l)
	return out


## True when the line is a radio cut ("... d--" or "--oxie?"): INTEGRATION.md.
func is_radio_cut() -> bool:
	var s := line.strip_edges()
	return s.ends_with("--") or s.begins_with("--")


func copy() -> DlgLine:
	var l := make(who, expression, line)
	l.cut_before = cut_before
	return l


func to_dict() -> Dictionary:
	var d := {"who": who, "expression": expression, "line": line}
	if cut_before:
		d["cut"] = true
	return d
