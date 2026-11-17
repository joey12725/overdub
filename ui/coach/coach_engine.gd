class_name CoachEngine
extends RefCounted
## The coach-mark director (docs/ONBOARDING.md "Lifecycle"). Node-free: it reads
## data/onboarding/coachmarks.json, is fed once per frame, and exposes at most one visible mark
## (`current`, with its bound `subject`). CoachLayer draws it.
##
## Each frame, with the layer enabled and no dialogue box open:
##   1. skip: every unseen mark of this level whose skipIf holds is retired silently
##   2. visible mark: dismissOn holds -> done (by the player); left its phases or outlived `linger`
##      -> fades, done if it was up >= minShownSecondsToCount, else back to unseen
##   3. choose (nothing visible, minGapSeconds since the last fade, phase budget left, no bark on
##      screen): the first unseen mark, urgent ones first, then file order, whose level and phase
##      match and whose trigger holds
##   4. an urgent mark that becomes eligible pre-empts a visible ordinary one at once
## Marks with once = true are stored in the seen store (coach.<id>); once = false marks retire per
## level visit. While a dialogue box opens, a visible mark fades as if its phase ended.
##
##   var e := CoachEngine.load_file()
##   e.seen = store; e.begin_level("01-soft-open", level_def)
##   e.update(dt, view, events, snapshot)        # every frame
##   e.note_input(&"move"); e.note_action(&"record"); e.ctx.levels_cleared = save.cleared.size()

signal shown(mark: CoachMarkDef)
## reason: "player" | "time" | "phase" | "preempt" | "dialogue" | "disabled" | "level";
## done: the mark was retired (it will not show again this save / visit).
signal hidden(mark: CoachMarkDef, reason: String, done: bool)

const DEFAULT_PATH := "res://data/onboarding/coachmarks.json"
const DEFAULT_LIMITS: Dictionary = {
	"maxVisible": 1,
	"minGapSeconds": 1.5,
	"maxPerPhaseVisit": 2,
	"maxUrgentPerPhaseVisit": 2,
	"defaultLingerSeconds": 10.0,
	"minShownSecondsToCount": 1.5,
}

var marks: Array[CoachMarkDef] = []
var raw_marks: Array[Dictionary] = []
var limits: Dictionary = DEFAULT_LIMITS.duplicate()
var ctx: CoachContext = CoachContext.new()
var seen: DlgSeenStore = DlgSeenStore.new():
	set(v):
		seen = v if v != null else DlgSeenStore.new()
		ctx.seen = seen
var enabled: bool = true:
	set(v):
		enabled = v
		if not v:
			_fade("disabled", false)
## A story dialogue box is open (marks wait; a visible one fades).
var dialogue_open: bool = false
## A bark is on screen (delays the next mark).
var bark_on_screen: bool = false
var errors: Array[String] = []

var current: CoachMarkDef = null
var subject: CoachConditions.Binding = CoachConditions.Binding.new()
var shown_at: float = 0.0
## Mark ids that have been visible since the latest count-in (bark suppression).
var shown_this_take: Array[String] = []

var _last_fade: float = -INF
var _phase_ordinary: int = 0
var _phase_urgent: int = 0


func _init() -> void:
	ctx.seen = seen


static func load_file(p_path: String = DEFAULT_PATH) -> CoachEngine:
	var e := CoachEngine.new()
	if not FileAccess.file_exists(p_path):
		e.errors.append("coach marks missing: %s" % p_path)
		return e
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(p_path))
	if not (parsed is Dictionary):
		e.errors.append("coach marks are not a JSON object: %s" % p_path)
		return e
	e.load_data(parsed)
	return e


func load_data(d: Dictionary) -> void:
	marks.clear()
	raw_marks.clear()
	limits = DEFAULT_LIMITS.duplicate()
	var lim: Variant = d.get("limits", {})
	if lim is Dictionary:
		for k: Variant in lim:
			limits[str(k)] = lim[k]
	var arr: Variant = d.get("marks", [])
	if not (arr is Array):
		errors.append("coach marks: no 'marks' array")
		return
	var ids: Dictionary[String, bool] = {}
	for i in (arr as Array).size():
		var e: Variant = (arr as Array)[i]
		if not (e is Dictionary):
			errors.append("coach mark %d is not an object" % i)
			continue
		var m := CoachMarkDef.from_dict(e, i)
		if ids.has(m.id):
			errors.append("coach mark id '%s' is used twice" % m.id)
		ids[m.id] = true
		marks.append(m)
		raw_marks.append(e)


func validate() -> Array[String]:
	var out: Array[String] = errors.duplicate()
	for i in marks.size():
		out.append_array(marks[i].validate(raw_marks[i]))
	return out


func get_mark(id: String) -> CoachMarkDef:
	for m: CoachMarkDef in marks:
		if m.id == id:
			return m
	return null


func limit(key: String) -> float:
	return float(limits.get(key, DEFAULT_LIMITS.get(key, 0.0)))


func begin_level(level_id: String, level: LevelDef = null) -> void:
	_fade("level", false)
	ctx.begin_level(level_id, level)
	ctx.visit_done.clear()
	_last_fade = -INF
	_phase_ordinary = 0
	_phase_urgent = 0
	shown_this_take.clear()


func note_action(a: StringName) -> void:
	ctx.add_action(a)


func note_input(input: StringName) -> void:
	ctx.add_input(input)


func set_device(device: StringName) -> void:
	ctx.device = device


func is_done(m: CoachMarkDef) -> bool:
	return seen.has(m.seen_key()) or ctx.visit_done.has(m.id)


func shown_for() -> float:
	return ctx.clock - shown_at if current != null else 0.0


func update(dt: float, view: SessionView, events: Array[SimEvent] = [], snap: FrameSnapshot = null) -> void:
	if ctx.advance(dt, view, snap):
		_phase_ordinary = 0
		_phase_urgent = 0
		if ctx.phase == SessionPhase.COUNTIN:
			shown_this_take.clear()
	ctx.add_events(events)
	if not enabled:
		return
	if dialogue_open:
		_fade("dialogue", false)
		return
	# 1. skip
	for m: CoachMarkDef in marks:
		if m != current and m.skip_if != null and not is_done(m) and m.applies_to(ctx.level_id):
			if CoachConditions.eval(m.skip_if, ctx, 0.0):
				_retire(m)
	# 2. the visible mark
	if current != null:
		if current.dismiss_on != null and CoachConditions.eval(current.dismiss_on, ctx, shown_at):
			_fade("player", true)
		elif not current.in_phase(ctx.phase):
			_fade("phase", false)
		elif shown_for() >= _linger(current):
			_fade("time", false)
	# 4. urgent pre-emption of an ordinary mark
	if current != null and not current.urgent and _phase_urgent < int(limit("maxUrgentPerPhaseVisit")):
		var b := CoachConditions.Binding.new()
		var u := _choose(true, b)
		if u != null:
			_fade("preempt", false)
			_show(u, b)
			return
	# 3. choose
	if current == null and not bark_on_screen and ctx.clock - _last_fade >= limit("minGapSeconds"):
		var b := CoachConditions.Binding.new()
		var m := _choose(false, b)
		if m != null:
			_show(m, b)


func _linger(m: CoachMarkDef) -> float:
	return m.linger if m.linger >= 0.0 else limit("defaultLingerSeconds")


func _eligible(m: CoachMarkDef, b: CoachConditions.Binding) -> bool:
	if m == current or is_done(m) or not m.applies_to(ctx.level_id) or not m.in_phase(ctx.phase):
		return false
	return CoachConditions.eval(m.trigger, ctx, ctx.clock, b)


func _choose(urgent_only: bool, b: CoachConditions.Binding) -> CoachMarkDef:
	var urgent_ok := _phase_urgent < int(limit("maxUrgentPerPhaseVisit"))
	var ordinary_ok := _phase_ordinary < int(limit("maxPerPhaseVisit"))
	if urgent_ok:
		for m: CoachMarkDef in marks:
			if m.urgent:
				var tb := CoachConditions.Binding.new()
				if _eligible(m, tb):
					_copy_binding(tb, b)
					return m
	if urgent_only or not ordinary_ok:
		return null
	for m: CoachMarkDef in marks:
		if not m.urgent:
			var tb := CoachConditions.Binding.new()
			if _eligible(m, tb):
				_copy_binding(tb, b)
				return m
	return null


static func _copy_binding(from: CoachConditions.Binding, to: CoachConditions.Binding) -> void:
	to.has = from.has
	to.kind = from.kind
	to.tape = from.tape
	to.id = from.id
	to.pos = from.pos
	to.has_pos = from.has_pos


func _show(m: CoachMarkDef, b: CoachConditions.Binding) -> void:
	current = m
	subject = b
	shown_at = ctx.clock
	if m.urgent:
		_phase_urgent += 1
	else:
		_phase_ordinary += 1
	if not shown_this_take.has(m.id):
		shown_this_take.append(m.id)
	shown.emit(m)


func _fade(reason: String, by_player: bool) -> void:
	if current == null:
		return
	var m := current
	var done := by_player or shown_for() >= limit("minShownSecondsToCount")
	current = null
	_last_fade = ctx.clock
	if done:
		_retire(m)
	hidden.emit(m, reason, done)


func _retire(m: CoachMarkDef) -> void:
	if m.once:
		seen.mark(m.seen_key())
	else:
		ctx.visit_done[m.id] = true
