class_name CoachMarkDef
extends RefCounted
## One coach mark from data/onboarding/coachmarks.json (docs/ONBOARDING.md "Coach mark format").
## Node-free.

var id: String = ""
## A level id, or "any".
var level: String = "any"
## SessionPhase names the mark may be visible in.
var phases: Array[String] = []
var trigger: Variant = false
var anchor: String = ""
var text: String = ""
var dismiss_on: Variant = null
## true: done for the whole save once retired; false: retired per level visit.
var once: bool = true
var skip_if: Variant = null
var urgent: bool = false
## Seconds it may stay up before fading by itself; < 0 = the file's defaultLingerSeconds.
var linger: float = -1.0
var teaches: String = ""
## File order (priority).
var order: int = 0

const FIELDS: Array[String] = ["id", "level", "phase", "trigger", "anchor", "text", "dismissOn", "once", "skipIf", "urgent", "linger", "teaches"]


static func from_dict(d: Dictionary, p_order: int = 0) -> CoachMarkDef:
	var m := CoachMarkDef.new()
	m.order = p_order
	m.id = str(d.get("id", "mark-%d" % p_order))
	m.level = str(d.get("level", "any"))
	var ph: Variant = d.get("phase", [])
	if ph is Array:
		for p: Variant in ph:
			m.phases.append(str(p))
	elif ph != null and str(ph) != "":
		m.phases.append(str(ph))
	m.trigger = d.get("trigger", false)
	m.anchor = str(d.get("anchor", ""))
	m.text = str(d.get("text", ""))
	m.dismiss_on = d.get("dismissOn", null)
	m.once = d.get("once", true) != false
	m.skip_if = d.get("skipIf", null)
	m.urgent = d.get("urgent", false) == true
	var lg: Variant = d.get("linger", null)
	if lg is int or lg is float:
		m.linger = float(lg)
	m.teaches = str(d.get("teaches", ""))
	return m


func applies_to(level_id: String) -> bool:
	return level == "any" or level == "" or level == level_id


func in_phase(phase: StringName) -> bool:
	return phases.is_empty() or phases.has(String(phase))


func seen_key() -> String:
	return "coach." + id


## Problems in this definition ([] when fine).
func validate(raw: Dictionary = {}) -> Array[String]:
	var out: Array[String] = []
	if text.strip_edges() == "":
		out.append("%s: no text" % id)
	for k: Variant in raw:
		if not FIELDS.has(str(k)):
			out.append("%s: unknown field '%s'" % [id, k])
	for p: String in phases:
		if not SessionPhase.has(StringName(p)):
			out.append("%s: unknown phase '%s'" % [id, p])
	out.append_array(CoachConditions.validate(trigger, id + ".trigger"))
	if dismiss_on != null:
		out.append_array(CoachConditions.validate(dismiss_on, id + ".dismissOn"))
	if skip_if != null:
		out.append_array(CoachConditions.validate(skip_if, id + ".skipIf"))
	return out
