class_name CinemaTypes
extends RefCounted
## Small data classes of the cinematic director (docs/CINEMATIC.md "Data"). Plain RefCounted
## records with to_dict() for printing, goldens and determinism checks.


## Highlight one self or entity in its cassette colour during a shot (captions-free callout).
class Callout:
	extends RefCounted
	## Self to highlight; -1 when the callout is an entity.
	var tape: int = -1
	## Enemy / mechanism id to highlight; "" when the callout is a self.
	var id: String = ""
	## CinemaGrammar.ROLE_*
	var role: StringName = CinemaGrammar.ROLE_SUBJECT
	## Cassette colour (an entity takes the colour of the self acting on it).
	var color: Color = Color.WHITE
	## Runtime only: 0..1 highlight strength for this frame (CinemaDirector fills it).
	var strength: float = 1.0

	static func of_tape(p_tape: int, p_role: StringName) -> Callout:
		var c := Callout.new()
		c.tape = p_tape
		c.role = p_role
		c.color = OD.tape_color(p_tape)
		return c

	static func of_id(p_id: String, p_role: StringName, by_tape: int) -> Callout:
		var c := Callout.new()
		c.id = p_id
		c.role = p_role
		c.color = OD.tape_color(by_tape) if by_tape >= 0 else Color(1, 1, 1)
		c.tape = -1
		return c

	func key() -> String:
		return ("t%d" % tape) if tape >= 0 else ("e:" + id)

	func copy() -> Callout:
		var c := Callout.new()
		c.tape = tape
		c.id = id
		c.role = role
		c.color = color
		c.strength = strength
		return c

	func to_dict() -> Dictionary:
		var d := {"role": String(role), "color": color.to_html(false)}
		if tape >= 0:
			d["tape"] = tape
		else:
			d["id"] = id
		return d


## One split-screen pane: which self it follows, where, in its cassette colour.
class Pane:
	extends RefCounted
	## Self this pane follows (its border is the cassette colour); -1 = a place, not a self.
	var tape: int = -1
	var color: Color = Color.WHITE
	## Normalised screen rect (0..1).
	var rect: Rect2 = Rect2(0, 0, 1, 1)
	## Planned floor point (sim axes); the runtime tracks the self when a snapshot is given.
	var focus: Vector2 = Vector2.ZERO
	## Visible floor diameter in tiles.
	var span: float = CinemaGrammar.SPAN_ROOM_MIN
	var reason: String = ""

	func copy() -> Pane:
		var p := Pane.new()
		p.tape = tape
		p.color = color
		p.rect = rect
		p.focus = focus
		p.span = span
		p.reason = reason
		return p

	func to_dict() -> Dictionary:
		return {
			"tape": tape,
			"rect": [snappedf(rect.position.x, 0.001), snappedf(rect.position.y, 0.001), snappedf(rect.size.x, 0.001), snappedf(rect.size.y, 0.001)],
			"focus": [snappedf(focus.x, 0.01), snappedf(focus.y, 0.01)],
			"span": snappedf(span, 0.01),
		}


## A music-linked flourish (MUSIC-13). Cues never cut; the fx layer plays them.
class Cue:
	extends RefCounted
	## Master beat (bar sweeps and chord flashes on bar lines; impacts on the event's exact beat).
	var beat: float = 0.0
	## CinemaGrammar.CUE_*
	var kind: StringName = CinemaGrammar.CUE_BAR_SWEEP
	## 0..1
	var strength: float = 1.0
	## Self the cue belongs to (impact cues), -1 = everyone.
	var tape: int = -1
	## Chord index into LevelMusicDef.progression for chord flashes; -1 otherwise.
	var chord: int = -1
	var point: Vector2 = Vector2.ZERO

	func to_dict() -> Dictionary:
		var d := {"beat": snappedf(beat, 0.001), "kind": String(kind), "strength": snappedf(strength, 0.001)}
		if tape >= 0:
			d["tape"] = tape
		if chord >= 0:
			d["chord"] = chord
		return d


## A self's or an enemy's action, from wind-up to impact: the editor never cuts away inside one.
class Action:
	extends RefCounted
	var start_beat: float = 0.0
	var impact_beat: float = 0.0
	var tapes: Array[int] = []
	var ids: Array[String] = []
	var point: Vector2 = Vector2.ZERO
	## "swing" | "shot" | "telegraph" | "recall"
	var what: String = ""

	func to_dict() -> Dictionary:
		return {"start": snappedf(start_beat, 0.001), "impact": snappedf(impact_beat, 0.001), "what": what, "tapes": tapes.duplicate(), "ids": ids.duplicate()}


## Optional knowledge from outside the winning Resolution.
class Context:
	extends RefCounted
	## Events of EARLIER runs of this attempt (the review resolutions and the live recordings that
	## came before the win). Only `selfDeath` events are read: a self that died there and lives now
	## was rescued (GHOST-06).
	var prior_events: Array[SimEvent] = []
