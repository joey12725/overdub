class_name GameSessionView
extends SessionView
## SessionView plus the game layer's optional "resolving" beat (port addition; see GameSession).
##
## After a take ends, the authoritative combined run is resolved on a worker thread. During that
## short beat the session reports phase REVIEW with `resolving = true`; the HUD can show
## `status_text` ("REWINDING TAPE…") and `resolve_progress` instead of the review prompts. Code that
## only knows SessionView keeps working: read the fields with `view.get("resolving")` or test
## `view is GameSessionView`.

## True while the authoritative result of the take just recorded is being computed.
var resolving: bool = false
## 0..1 progress of that computation (meaningful only while resolving).
var resolve_progress: float = 0.0
## Player-facing line for the resolving beat ("" when not resolving).
var status_text: String = ""

const RESOLVING_TEXT: String = "Rewinding tape…"


func copy() -> SessionView:
	var o := GameSessionView.new()
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
	o.resolving = resolving
	o.resolve_progress = resolve_progress
	o.status_text = status_text
	return o
