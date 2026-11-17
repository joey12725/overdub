class_name CinemaShot
extends RefCounted
## One entry of the edit decision list. Start and end are whole master beats; a shot owns
## [start_beat, end_beat).

var start_beat: int = 0
var end_beat: int = 0
## CinemaGrammar.KIND_* (what the shot is about).
var kind: StringName = CinemaGrammar.KIND_COVERAGE
## Floor point (sim axes) the shot frames; for a pan, where it starts.
var focus_point: Vector2 = Vector2.ZERO
## Pan destination (MOVE_PAN only); otherwise equal to focus_point.
var focus_to: Vector2 = Vector2.ZERO
## Self to track (-1 = none): the runtime follows its live position when given snapshots.
var focus_tape: int = -1
## Enemy / mechanism the shot is about ("" = none).
var focus_id: String = ""
## CinemaGrammar.FRAMING_*
var framing: StringName = CinemaGrammar.FRAMING_WIDE
## Visible floor diameter in tiles (for WIDE: the level's diameter; the camera may simply fit).
var span: float = 12.0
## CinemaGrammar.MOVE_*
var move: StringName = CinemaGrammar.MOVE_HOLD
## +1 / -1: orbit direction (alternates so consecutive orbits do not feel mechanical).
var move_sign: float = 1.0
## CinemaGrammar.EMPHASIS_* (exactly one per shot, possibly none).
var emphasis: StringName = CinemaGrammar.EMPHASIS_NONE
## Letterbox depth for this shot (fraction of screen height per bar).
var letterbox: float = CinemaGrammar.LETTERBOX_BASE
## Peak time-ripple strength (EMPHASIS_TIME_RIPPLE only), centred on key_beat.
var ripple: float = 0.0
## Split-screen panes (EMPHASIS_SPLIT only; 2..4). The shot's own focus/span still frames all of
## them together, as the fallback for a renderer without split-screen.
var panes: Array[CinemaTypes.Pane] = []
var callouts: Array[CinemaTypes.Callout] = []
## Why the editor chose this shot (debug / demo / docs; never shown on screen).
var reason: String = ""
## The story beat's cause and effect beats (fractional master beats).
var cause_beat: float = 0.0
var key_beat: float = 0.0
## Beats that must stay inside the shot (the whole cause->effect action) when boundaries move.
var core_start: int = 0
var core_end: int = 0
var score: float = 0.0
## CinemaGrammar.TRANSITION_*: how this shot begins.
var transition: StringName = CinemaGrammar.TRANSITION_CUT
## Every self / id the shot is about (used for the cut rule and callouts).
var tapes: Array[int] = []
var ids: Array[String] = []
## Kinds of every moment this shot shows (its own kind first).
var shows: Array[StringName] = []
## Indices into Resolution.events of the events this shot explains.
var source_events: Array[int] = []


func length() -> int:
	return end_beat - start_beat


func contains_beat(beat: float) -> bool:
	return beat >= float(start_beat) and beat < float(end_beat)


## One callout per self / entity; a survivor role wins over the others (the finale's highlight).
func add_callout(c: CinemaTypes.Callout) -> void:
	for o: CinemaTypes.Callout in callouts:
		if o.key() == c.key():
			if c.role == CinemaGrammar.ROLE_SURVIVOR:
				o.role = c.role
			return
	callouts.append(c)


func add_tape(t: int) -> void:
	if t >= 0 and not tapes.has(t):
		tapes.append(t)


func add_id(i: String) -> void:
	if not i.is_empty() and not ids.has(i):
		ids.append(i)


## True when the floor point is inside what this shot shows (any pane, for a split).
func frames_point(p: Vector2) -> bool:
	if framing == CinemaGrammar.FRAMING_WIDE:
		return true
	if p.distance_to(focus_point) <= span * 0.5:
		return true
	if move == CinemaGrammar.MOVE_PAN and p.distance_to(focus_to) <= span * 0.5:
		return true
	for pane: CinemaTypes.Pane in panes:
		if p.distance_to(pane.focus) <= pane.span * 0.5:
			return true
	return false


func to_dict() -> Dictionary:
	var d := {
		"start": start_beat,
		"end": end_beat,
		"kind": String(kind),
		"framing": String(framing),
		"move": String(move),
		"emphasis": String(emphasis),
		"focus": [snappedf(focus_point.x, 0.01), snappedf(focus_point.y, 0.01)],
		"span": snappedf(span, 0.01),
		"transition": String(transition),
		"reason": reason,
	}
	if move == CinemaGrammar.MOVE_PAN:
		d["focusTo"] = [snappedf(focus_to.x, 0.01), snappedf(focus_to.y, 0.01)]
	if focus_tape >= 0:
		d["focusTape"] = focus_tape
	if not focus_id.is_empty():
		d["focusId"] = focus_id
	if not panes.is_empty():
		var p: Array = []
		for x: CinemaTypes.Pane in panes:
			p.append(x.to_dict())
		d["panes"] = p
	var c: Array = []
	for x: CinemaTypes.Callout in callouts:
		c.append(x.to_dict())
	d["callouts"] = c
	var s: Array = []
	for k: StringName in shows:
		s.append(String(k))
	d["shows"] = s
	return d
