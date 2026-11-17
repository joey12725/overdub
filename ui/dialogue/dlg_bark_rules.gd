class_name DlgBarkRules
extends RefCounted
## Which bark (if any) plays for an event: per-event cooldowns and chances, a global rate limit, at
## most one bark per session phase, and never the same line twice running. Node-free; the clock is
## advanced by tick(dt) and the RNG is seedable, so the rules are testable.
##
## INTEGRATION.md "Barks": chosen at random without repeating the previous pick; at most one per
## session state; about a one in three chance on repeatable events so they stay a treat.

## Per-key [chance 0..1, cooldown seconds]. Keys not listed use DEFAULT_RULE.
const RULES: Dictionary = {
	"countIn": [0.34, 25.0],
	"takeCommitted": [0.5, 12.0],
	"retry": [0.4, 12.0],
	"resetAll": [1.0, 20.0],
	"lastTape": [1.0, 30.0],
	"death": [0.5, 10.0],
	"ghostTake": [1.0, 20.0],
	"desync": [0.5, 12.0],
	"resync": [0.5, 12.0],
	"rescue": [1.0, 8.0],
	"fail": [0.4, 15.0],
	"win": [1.0, 0.0],
	"loot": [1.0, 0.0],
	"bossRecall": [1.0, 6.0],
	"archivistRecall": [1.0, 6.0],
	"archivistSurprised": [1.0, 10.0],
	"idle": [1.0, 0.0],
}
const DEFAULT_RULE: Array = [0.5, 10.0]

## Global limits: at least GAP seconds between barks, at most WINDOW_MAX barks per WINDOW seconds.
var gap: float = 4.0
var window: float = 60.0
var window_max: int = 5
## At most one bark per session phase (reset by new_phase()).
var one_per_phase: bool = true
var enabled: bool = true

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var now: float = 0.0
var _last_at: Dictionary[String, float] = {}
var _last_pick: Dictionary[String, int] = {}
var _last_text: String = ""
var _history: Array[float] = []
var _phase_used: bool = false
## Why the last request() returned null ("disabled", "cooldown", "gap", "rate", "phase", "chance",
## "empty"); "" after a success. For tests and debugging.
var last_reject: String = ""


func _init(seed_value: int = 0) -> void:
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()


func tick(dt: float) -> void:
	now += dt


func new_phase() -> void:
	_phase_used = false


static func rule(key: String) -> Array:
	return RULES.get(key, DEFAULT_RULE)


## Pick a line for `key` from `lines`, or null when the rules say no. `force` skips the chance roll
## and the global limits (used for the second half of a paired bark and for scripted ones), but never
## `enabled` or the no-repeat rule.
func request(key: String, lines: Array[DlgLine], force: bool = false) -> DlgLine:
	last_reject = ""
	if not enabled:
		last_reject = "disabled"
		return null
	if lines.is_empty():
		last_reject = "empty"
		return null
	var r := rule(key)
	var chance: float = r[0]
	var cooldown: float = r[1]
	if not force:
		if _last_at.has(key) and now - _last_at[key] < cooldown:
			last_reject = "cooldown"
			return null
		if not _history.is_empty() and now - _history[_history.size() - 1] < gap:
			last_reject = "gap"
			return null
		_prune()
		if _history.size() >= window_max:
			last_reject = "rate"
			return null
		if one_per_phase and _phase_used:
			last_reject = "phase"
			return null
		if chance < 1.0 and rng.randf() >= chance:
			# A failed roll still starts the cooldown, so a burst of the same event does not re-roll
			# until one lands.
			_last_at[key] = now
			last_reject = "chance"
			return null
	var pick := _pick(key, lines)
	_last_pick[key] = pick
	_last_at[key] = now
	_history.append(now)
	_phase_used = true
	_last_text = lines[pick].line
	return lines[pick]


func _pick(key: String, lines: Array[DlgLine]) -> int:
	var n := lines.size()
	if n == 1:
		return 0
	var avoid: int = _last_pick.get(key, -1)
	var choices: Array[int] = []
	for i in n:
		if i != avoid and lines[i].line != _last_text:
			choices.append(i)
	if choices.is_empty():
		for i in n:
			if i != avoid:
				choices.append(i)
	return choices[rng.randi_range(0, choices.size() - 1)]


func _prune() -> void:
	while not _history.is_empty() and now - _history[0] > window:
		_history.pop_front()
