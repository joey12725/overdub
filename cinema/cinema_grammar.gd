class_name CinemaGrammar
extends RefCounted
## The editorial vocabulary of the cinematic director (docs/CINEMATIC.md; CINE-01..05, MUSIC-13,
## PILLAR-06). Constants only, never instantiated.
##
## The planner (CinemaPlanner) turns a resolved encounter into an edit decision list of CinemaShot,
## the runtime (CinemaDirector) turns that list plus the master beat into camera parameters. Every
## value the editor reasons with lives here so the scoring table in docs/CINEMATIC.md and the code
## cannot drift apart.

# ───────────────────────────── shot kinds (what a shot is about) ─────────────────────────────

## Beat zero, wide, every self at the start.
const KIND_OPENING: StringName = &"opening"
## Filler between story beats: keeps the selves in view, no claim of importance.
const KIND_COVERAGE: StringName = &"coverage"
## The objective completes.
const KIND_CLIMAX: StringName = &"climax"
## The last shot: the survivors when the tape runs out.
const KIND_FINALE: StringName = &"finale"
## Two or more selves strike the same enemy together (the shielder pincer).
const KIND_MULTI_KILL: StringName = &"multiKill"
## One self's knockback delivers an enemy into another self's swing (or a hazard).
const KIND_KNOCKBACK: StringName = &"knockback"
## A trap / laser / door kills an enemy.
const KIND_TRAP_KILL: StringName = &"trapKill"
## A ranged shot fired earlier lands a kill later.
const KIND_SHOT_KILL: StringName = &"shotKill"
const KIND_KILL: StringName = &"kill"
## A self that died in an earlier take's run survives this one.
const KIND_RESCUE: StringName = &"rescue"
## An enemy winding up on one self is cut down by another before it lands.
const KIND_SAVE: StringName = &"save"
## A self desyncs (and, when it happens, its spark catches up again).
const KIND_DESYNC: StringName = &"desync"
## One self operates a mechanism that lets another self through.
const KIND_OPENED_FOR: StringName = &"openedFor"
## One self holds a plate while another crosses what it controls.
const KIND_PLATE_HOLD: StringName = &"plateHold"
## A mechanism changes state and nobody is shown using it.
const KIND_MECHANISM: StringName = &"mechanism"
## A wall breaks.
const KIND_BREAK: StringName = &"break"
const KIND_BOSS_PHASE: StringName = &"bossPhase"
## The boss acts on a memory of a committed tape, and the self is no longer there.
const KIND_BOSS_FOOLED: StringName = &"bossFooled"
## The boss acts on a memory and it works.
const KIND_BOSS_RECALL: StringName = &"bossRecall"
## A self dies in the winning run (a sacrifice: someone else carries the objective).
const KIND_DEATH: StringName = &"death"

# ───────────────────────────── framing ─────────────────────────────

## Whole level (camera fits the level).
const FRAMING_WIDE: StringName = &"wide"
## One room (flood-filled area between walls and doors).
const FRAMING_ROOM: StringName = &"room"
## Two subjects (cause and effect) both in frame.
const FRAMING_TWO_SHOT: StringName = &"twoShot"
## One subject, tight.
const FRAMING_CLOSE: StringName = &"close"

## Visible floor diameter, in tiles, for the tight framings. ROOM and WIDE come from the level.
const SPAN_CLOSE: float = 6.0
const SPAN_TWO_SHOT_MIN: float = 7.0
## Two-shot span = subject distance + this margin.
const SPAN_TWO_SHOT_MARGIN: float = 5.0
const SPAN_ROOM_MIN: float = 7.0
## Subjects closer than this are a close-up; farther than TWO_SHOT_MAX_DIST need a pan / split / cut.
const CLOSE_MAX_DIST: float = 3.0
const TWO_SHOT_MAX_DIST: float = 12.0

# ───────────────────────────── camera moves ─────────────────────────────

const MOVE_HOLD: StringName = &"hold"
const MOVE_PUSH_IN: StringName = &"pushIn"
const MOVE_PULL_OUT: StringName = &"pullOut"
## Target travels from focus_point (cause) to focus_to (effect) between cause_beat and key_beat.
const MOVE_PAN: StringName = &"pan"
## A few degrees of yaw around the focus.
const MOVE_ORBIT: StringName = &"orbit"

## Push-in / pull-out range as span multipliers (start -> end).
const PUSH_FROM: float = 1.25
const PUSH_TO: float = 0.85
const PULL_FROM: float = 0.85
const PULL_TO: float = 1.35
## Orbit amplitude, degrees of yaw.
const ORBIT_DEGREES: float = 4.0

# ───────────────────────────── emphasis (at most one per shot) ─────────────────────────────

const EMPHASIS_NONE: StringName = &"none"
## Deeper letterbox bars for the shot.
const EMPHASIS_LETTERBOX: StringName = &"letterbox"
## A time-ripple distortion that peaks on the shot's key beat (time-themed links: rescue, desync,
## a fooled memory).
const EMPHASIS_TIME_RIPPLE: StringName = &"timeRipple"
## Split-screen request: two to four panes in cassette colours.
const EMPHASIS_SPLIT: StringName = &"split"

## The cinematic's resting letterbox (mirrors FxCatalog's CINEMATIC profile) and the emphasised one,
## as a fraction of the screen height per bar.
const LETTERBOX_BASE: float = 0.085
const LETTERBOX_DEEP: float = 0.15
const RIPPLE_STRENGTH: float = 1.0

# ───────────────────────────── transitions ─────────────────────────────

## Hard cut on the beat.
const TRANSITION_CUT: StringName = &"cut"
## The new shot eases in from the previous framing over BLEND_BEATS (same subject, new size).
const TRANSITION_BLEND: StringName = &"blend"
const BLEND_BEATS: float = 1.0
## Letterbox / split panes ease over this many beats.
const EASE_BEATS: float = 0.5

# ───────────────────────────── callout roles ─────────────────────────────

const ROLE_CAUSE: StringName = &"cause"
const ROLE_EFFECT: StringName = &"effect"
const ROLE_TARGET: StringName = &"target"
const ROLE_SURVIVOR: StringName = &"survivor"
const ROLE_SUBJECT: StringName = &"subject"

# ───────────────────────────── flourish cues (never cuts) ─────────────────────────────

## Every bar line: a sweep along the beat ruler / floor runes.
const CUE_BAR_SWEEP: StringName = &"barSweep"
## The chord changes (LevelMusicDef.progression, chord_bars per chord): a palette flash.
const CUE_CHORD_FLASH: StringName = &"chordFlash"
## An important impact (kill, phase break, objective): an accent on the exact event beat.
const CUE_IMPACT: StringName = &"impact"

# ───────────────────────────── editorial rules ─────────────────────────────

const MIN_SHOT_BEATS: int = 2
## Coverage shots are at most this long (a long gap becomes several, cut on bar lines).
const MAX_COVERAGE_BEATS: int = 8
## The opening holds at least this long.
const OPENING_MIN_BEATS: int = 2
## The opening grows to this when nothing important needs the time.
const OPENING_PREFERRED_BEATS: int = 4
## Lead-in before a cause and tail after an effect.
const PRE_BEATS: float = 1.0
const POST_BEATS: float = 1.5
## An action is on screen until this long after its impact (follow-through).
const FOLLOW_THROUGH_BEATS: float = 0.25
## A boundary may move this far to land on a bar line.
const BAR_SNAP_BEATS: int = 1
## Cause and effect closer in time than this are "simultaneous" (split-screen candidates).
const SIMULTANEOUS_BEATS: float = 2.0
## Cause and effect farther apart in time than this get two shots.
const SEQUENTIAL_SPLIT_BEATS: float = 4.0
## Shots per beat of encounter: the cap is ceil(beats / BEATS_PER_SHOT) + 1, at least 2.
const BEATS_PER_SHOT: float = 3.0
const MAX_PANES: int = 4

# ───────────────────────────── importance (scoring table) ─────────────────────────────
## objective-critical > kills > rescues / desync > mechanisms > movement. Ties resolve by key beat,
## then kind, then the first event index. A rescue that the analyzer can pin on a saving kill absorbs
## that kill and keeps the higher of the two scores, so a rescue-by-kill ranks as the kill does.

const SCORE: Dictionary[StringName, float] = {
	KIND_CLIMAX: 100.0,
	KIND_BOSS_FOOLED: 78.0,
	KIND_BOSS_PHASE: 72.0,
	KIND_MULTI_KILL: 66.0,
	KIND_KNOCKBACK: 62.0,
	KIND_TRAP_KILL: 58.0,
	KIND_SHOT_KILL: 52.0,
	KIND_SAVE: 50.0,
	KIND_KILL: 44.0,
	KIND_BOSS_RECALL: 46.0,
	KIND_RESCUE: 42.0,
	KIND_DESYNC: 38.0,
	KIND_DEATH: 34.0,
	KIND_PLATE_HOLD: 36.0,
	KIND_OPENED_FOR: 32.0,
	KIND_BREAK: 28.0,
	KIND_MECHANISM: 18.0,
	KIND_COVERAGE: 5.0,
	KIND_OPENING: 90.0,
	KIND_FINALE: 95.0,
}
## Added when a moment involves two or more selves (coordination is the point of the game).
const SCORE_MULTI_TAPE_BONUS: float = 8.0
## Added when the killed enemy is a named objective target.
const SCORE_TARGET_BONUS: float = 10.0
## Added to a kill that also saved another self (it was winding up on them).
const SCORE_SAVE_BONUS: float = 12.0

## Default emphasis per kind (the planner may drop it to keep one effect at a time).
const EMPHASIS_FOR: Dictionary[StringName, StringName] = {
	KIND_CLIMAX: EMPHASIS_LETTERBOX,
	KIND_BOSS_PHASE: EMPHASIS_LETTERBOX,
	KIND_BOSS_FOOLED: EMPHASIS_TIME_RIPPLE,
	KIND_RESCUE: EMPHASIS_TIME_RIPPLE,
	KIND_DESYNC: EMPHASIS_TIME_RIPPLE,
}

## Kind order for deterministic tie-breaks.
const KIND_ORDER: Array[StringName] = [
	KIND_CLIMAX, KIND_FINALE, KIND_OPENING, KIND_BOSS_FOOLED, KIND_BOSS_PHASE, KIND_MULTI_KILL,
	KIND_KNOCKBACK, KIND_TRAP_KILL, KIND_SHOT_KILL, KIND_SAVE, KIND_BOSS_RECALL,
	KIND_KILL, KIND_RESCUE, KIND_DESYNC, KIND_PLATE_HOLD, KIND_DEATH, KIND_OPENED_FOR, KIND_BREAK,
	KIND_MECHANISM, KIND_COVERAGE,
]


static func score_of(kind: StringName) -> float:
	return SCORE.get(kind, 1.0)


static func kind_rank(kind: StringName) -> int:
	var i := KIND_ORDER.find(kind)
	return i if i >= 0 else KIND_ORDER.size()


## Normalised pane rectangles (0..1 of the screen) for a split of `n` panes (2..4): two side by
## side, three as one tall left pane and two stacked right, four as a quad.
static func pane_rects(n: int) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if n <= 1:
		out.append(Rect2(0, 0, 1, 1))
	elif n == 2:
		out.append(Rect2(0, 0, 0.5, 1))
		out.append(Rect2(0.5, 0, 0.5, 1))
	elif n == 3:
		out.append(Rect2(0, 0, 0.5, 1))
		out.append(Rect2(0.5, 0, 0.5, 0.5))
		out.append(Rect2(0.5, 0.5, 0.5, 0.5))
	else:
		out.append(Rect2(0, 0, 0.5, 0.5))
		out.append(Rect2(0.5, 0, 0.5, 0.5))
		out.append(Rect2(0, 0.5, 0.5, 0.5))
		out.append(Rect2(0.5, 0.5, 0.5, 0.5))
	return out
