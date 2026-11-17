class_name SessionView
extends RefCounted
## Everything the in-level HUD needs (types.ts SessionView). Built by the game's session every frame,
## read by UiBase.update_hud. Not serialised.

## SessionPhase.*
var phase: StringName = SessionPhase.BRIEFING
var level: LevelDef = null
## Exactly OD.TAPE_COUNT decks, index = tape.
var decks: Array[DeckView] = []
## Index of the cassette being set up / recorded, or -1 = none (prototype null).
var active: int = -1
## Master beat position of the playhead.
var beat: float = 0.0
## Total master beats in the horizon.
var horizon_beats: float = 0.0
## How fast master time is passing relative to wall time right now (1/speed while recording).
var world_rate: float = 1.0
## Count-in: 0 when not counting, else 5, 6, 7, 8.
var count: int = 0
## Speeds (TapeSpeed) and end modes (OD.EndMode) selectable for the active cassette.
var speeds: Array[float] = []
var end_modes: Array[int] = []
var objective: ObjectiveView = ObjectiveView.new()
## Latest resolved outcome (set once a take has been reviewed); null = none.
var outcome: Outcome = null
## SessionAction.* currently offered.
var actions: Array[StringName] = []
## Upcoming enemy attack beats for the 'beatSight' ability (empty otherwise).
var threat_beats: Array[float] = []
## Contextual hint line; "" = none (prototype null).
var hint: String = ""


func _init() -> void:
	for i in OD.TAPE_COUNT:
		var d := DeckView.new()
		d.index = i
		decks.append(d)


## Deep copy except `level`, which is shared (levels are immutable during a session).
func copy() -> SessionView:
	var o := SessionView.new()
	o.phase = phase
	o.level = level
	o.decks.clear()
	for d: DeckView in decks:
		o.decks.append(d.copy())
	o.active = active
	o.beat = beat
	o.horizon_beats = horizon_beats
	o.world_rate = world_rate
	o.count = count
	o.speeds = speeds.duplicate()
	o.end_modes = end_modes.duplicate()
	o.objective = objective.copy() as ObjectiveView
	o.outcome = outcome.copy() if outcome != null else null
	o.actions = actions.duplicate()
	o.threat_beats = threat_beats.duplicate()
	o.hint = hint
	return o
