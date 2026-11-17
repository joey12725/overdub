class_name HudModel
extends RefCounted
## HUD view-model (port of prototype/src/ui/hud/model.ts plus the Godot layout maths): every rule
## that turns SessionView data into what the decks and the master beat ruler show. Pure and
## node-free so it is unit-tested headless (tests/ui_hud); the widgets only draw the results.
##
## Terminology (requirements chapter 03): the ruler is always in MASTER bars/beats, a deck's
## recording allowance is in LOCAL tape bars. Every string built here names which one it means.

const EPS := 1e-9
## Hard ceiling so a degenerate span can never spin the layout loop forever.
const MAX_SEGMENTS := 512
## Reel revolutions per viewer second at reel_rate 1. 0.5x still visibly turns, 4x is not a blur.
const BASE_REEL_RPS := 0.55

# ───────────────────────────── icon / tone ids ─────────────────────────────

const ICON_LOCK: StringName = &"lock"
const ICON_REC: StringName = &"rec"
const ICON_ARM: StringName = &"arm"
const ICON_EMPTY: StringName = &"empty"
const ICON_NONE: StringName = &"none"
const ICON_TAKE: StringName = &"take"
const ICON_ALIVE: StringName = &"alive"
const ICON_GHOST: StringName = &"ghost"
const ICON_REC_GHOST: StringName = &"recGhost"
const ICON_DESYNC: StringName = &"desync"
const ICON_RESYNC: StringName = &"resync"
const ICON_STOP: StringName = &"stop"
const ICON_REPEAT: StringName = &"repeat"
const ICON_REVERSE: StringName = &"reverse"
const ICON_PLAY: StringName = &"play"
const ICON_REWIND: StringName = &"rewind"
const ICON_HOLD: StringName = &"hold"
const ICON_CUE: StringName = &"cue"
const ICON_DEATH: StringName = &"death"
const ICON_SURVIVOR: StringName = &"survivor"
const ICON_WORLD: StringName = &"world"

const TONE_MUTED: StringName = &"muted"
const TONE_IDLE: StringName = &"idle"
const TONE_ARMED: StringName = &"armed"
const TONE_REC: StringName = &"rec"
const TONE_PENDING: StringName = &"pending"
const TONE_LOCKED: StringName = &"locked"
const TONE_GOOD: StringName = &"good"
const TONE_DEAD: StringName = &"dead"
const TONE_DESYNC: StringName = &"desync"
const TONE_WARN: StringName = &"warn"

const DEVICE_KEYBOARD: StringName = &"keyboard"
const DEVICE_GAMEPAD: StringName = &"gamepad"


## A word + icon + tone. `short` is the compact-deck wording (same meaning, fewer letters).
class Badge:
	extends RefCounted
	var label: String = ""
	var short: String = ""
	var icon: StringName = &""
	var tone: StringName = &""
	## End-mode badges only: what happens when the tape runs out before the horizon.
	var copy: String = ""

	static func make(p_label: String, p_icon: StringName, p_tone: StringName, p_short: String = "") -> Badge:
		var b := Badge.new()
		b.label = p_label
		b.icon = p_icon
		b.tone = p_tone
		b.short = p_short if p_short != "" else p_label
		return b

	func key() -> String:
		return "%s|%s|%s" % [label, icon, tone]


## How one traversal sits on the master timeline.
class LaneSegment:
	extends RefCounted
	## Master beats.
	var start: float = 0.0
	var end: float = 0.0
	## 0 = the recorded pass itself, 1+ = repeats / reversals.
	var traversal: int = 0
	## Playback direction across this segment: 1 or -1.
	var dir: int = 1
	## True when the horizon cuts this traversal short.
	var partial: bool = false


class LaneLayout:
	extends RefCounted
	var span_beats: float = 0.0
	var segments: Array[LaneSegment] = []
	## 'stop' tapes that end before the horizon: master beat from which the self holds its pose;
	## -1 = no hold.
	var hold_from: float = -1.0

	func has_hold() -> bool:
		return hold_from >= 0.0


class PlacedMark:
	extends RefCounted
	var beat: float = 0.0
	var kind: StringName = &""
	var traversal: int = 0
	var dir: int = 1


class TimeLeft:
	extends RefCounted
	## 0..1 of the take still to record.
	var fraction: float = 0.0
	## Remaining LOCAL bars (the player's own bars; TIME-02).
	var local_bars: float = 0.0
	var text: String = ""


class Prompt:
	extends RefCounted
	var action: StringName = &""
	var binding: ButtonPrompt = null
	var label: String = ""
	## Plain-text form for tests and logs: "[Space] RECORD".
	var text: String = ""


class DecisionOption:
	extends RefCounted
	var action: StringName = &""
	var title: String = ""
	## What it keeps / destroys, so retry and reset can never be confused.
	var detail: String = ""
	## &"retry" | &"commit" | &"reset"
	var tone: StringName = &""
	var enabled: bool = false
	## Reset needs a hold-to-confirm (REC-05).
	var hold: bool = false


class Verdict:
	extends RefCounted
	var title: String = ""
	## &"neutral" | &"win" | &"fail"
	var tone: StringName = &""
	var sub: String = ""


## Pixel layout of the ruler body. Kept separate so the playhead and the lanes agree exactly.
class RulerGeometry:
	extends RefCounted
	var gutter: float = 0.0
	var track_x: float = 0.0
	var track_w: float = 0.0
	var band_h: float = 0.0
	var threat_h: float = 0.0
	var lane_y: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var lane_h: float = 0.0


## Where the HUD's dock pieces go on screen.
class DockLayout:
	extends RefCounted
	var unit: float = 14.0
	var slim: bool = false
	var visible: bool = true
	var decks: Array[Rect2] = [Rect2(), Rect2(), Rect2(), Rect2()]
	## Room above the active deck for its "REC / ARMED" tab (part of the inset).
	var tab_h: float = 0.0
	var ruler: Rect2 = Rect2()
	## Setup control surface: anchored with its bottom edge at setup_bottom, centred over the active
	## deck and clamped to the screen; height is the panel's own.
	var setup_x: float = 0.0
	var setup_w: float = 0.0
	var setup_bottom: float = 0.0
	## Pixels at the bottom of the screen covered by the dock (decks + ruler + active tab).
	var bottom_inset: float = 0.0


## Sub-rectangles of one deck, in the deck's local coordinates.
class DeckGeometry:
	extends RefCounted
	var body: Rect2 = Rect2()
	## The illustrated cassette (shell, label strip, window, reels). Deck flashes go here.
	var cassette: Rect2 = Rect2()
	## The speed readout column: nothing is ever drawn over it.
	var speed: Rect2 = Rect2()
	## Inside `speed`: the big number, and the span bar under it.
	var speed_text: Rect2 = Rect2()
	var span_bar: Rect2 = Rect2()
	var span_caption: Rect2 = Rect2()
	## Badge rows (status, life, end/transport...).
	var badges: Array[Rect2] = []
	var speed_font: float = 0.0
	var badge_font: float = 0.0
	## Where deck_event() flashes draw (always inside `cassette`, never over `speed`).
	var flash: Rect2 = Rect2()


# ───────────────────────────── formatting helpers ─────────────────────────────

## Numbers as the prototype prints them after rounding to 2 decimals: 0.5 -> "0.5", 4 -> "4".
static func format_bars(n: float) -> String:
	var r := roundf(n * 100.0) / 100.0
	if absf(r - roundf(r)) < 1e-9:
		return str(int(roundf(r)))
	var s := "%.2f" % r
	while s.ends_with("0"):
		s = s.substr(0, s.length() - 1)
	return s


static func _plural(n: float, word: String) -> String:
	return word if absf(n - 1.0) < EPS else word + "s"


# ───────────────────────────── time mapping (TIME-03) ─────────────────────────────

## Master beats one LOCAL tick of a tape at `speed` covers: master = local / speed.
static func master_beats_per_local_tick(speed: float, bpm: float) -> float:
	return bpm / 60.0 / float(OD.LOCAL_HZ) / speed


## Master beat (from the start of a traversal) at which a local tick falls on its first pass.
static func local_tick_to_master_beat(tick: float, speed: float, bpm: float) -> float:
	return tick * master_beats_per_local_tick(speed, bpm)


## Master beats one traversal occupies: level.bars local bars become bars / speed master bars.
static func traversal_beats(local_bars: float, speed: float) -> float:
	return local_bars * OD.BEATS_PER_BAR / speed


## Local ticks in a full recording of `local_bars` bars at `bpm` (identical for every speed; TIME-02).
static func recording_ticks(local_bars: float, bpm: float) -> int:
	return roundi(local_bars * OD.BEATS_PER_BAR * 60.0 * OD.LOCAL_HZ / bpm)


## How one tape's traversals tile the master timeline up to the horizon (architecture: end
## behaviour). stop: one pass then a hold; repeat: passes back to back, all forward; reverse:
## ping-pong. end_mode is OD.EndMode.
static func lane_layout(span_beats: float, end_mode: int, horizon_beats: float) -> LaneLayout:
	var out := LaneLayout.new()
	out.span_beats = span_beats
	if not (span_beats > 0.0) or not (horizon_beats > 0.0):
		return out
	var start := 0.0
	var k := 0
	while start < horizon_beats - EPS and k < MAX_SEGMENTS:
		var seg := LaneSegment.new()
		seg.start = start
		seg.end = minf(start + span_beats, horizon_beats)
		seg.traversal = k
		seg.dir = -1 if end_mode == OD.EndMode.REVERSE and k % 2 == 1 else 1
		seg.partial = seg.end - seg.start < span_beats - EPS
		out.segments.append(seg)
		if end_mode == OD.EndMode.STOP:
			break
		start += span_beats
		k += 1
	if end_mode == OD.EndMode.STOP and span_beats < horizon_beats - EPS:
		out.hold_from = span_beats
	return out


## Every master beat at which a recorded action fires, across all traversals up to the horizon.
## Repeats re-fire forward; reverse passes cross each action's tick from the far end (PLAY-06).
static func place_marks(marks: Array[DeckMark], speed: float, bpm: float, layout: LaneLayout) -> Array[PlacedMark]:
	var out: Array[PlacedMark] = []
	if not (speed > 0.0):
		return out
	var span := layout.span_beats
	var per := master_beats_per_local_tick(speed, bpm)
	for seg: LaneSegment in layout.segments:
		for m: DeckMark in marks:
			var local := float(m.tick) * per
			if local < -EPS or local > span + EPS:
				continue
			var beat := seg.start + local if seg.dir == 1 else seg.start + (span - local)
			if beat < seg.start - EPS or beat > seg.end + EPS:
				continue
			var p := PlacedMark.new()
			p.beat = beat
			p.kind = m.kind
			p.traversal = seg.traversal
			p.dir = seg.dir
			out.append(p)
	# Stable sort by beat (insertion sort: Godot's sort is not stable, and the prototype's is).
	for i in range(1, out.size()):
		var cur := out[i]
		var j := i - 1
		while j >= 0 and out[j].beat > cur.beat:
			out[j + 1] = out[j]
			j -= 1
		out[j + 1] = cur
	return out


## Which traversal is playing at master beat `beat` (0-based).
static func traversal_at(beat: float, span_beats: float) -> int:
	if not (span_beats > 0.0) or beat <= 0.0:
		return 0
	return floori(beat / span_beats + EPS)


## Label every n-th master bar so labels stay at least `min_px` apart. n is a power of two.
static func bar_label_step(horizon_bars: float, track_px: float, min_px: float = 30.0) -> int:
	if not (horizon_bars > 0.0) or not (track_px > 0.0):
		return 1
	var bar_px := track_px / horizon_bars
	var step := 1
	while step * bar_px < min_px and step < 1024:
		step *= 2
	return step


# ───────────────────────────── speed (UI-05, UI-07, NEW-10) ─────────────────────────────

## "0.5×", "1×", "2×", "4×"; "--" for no speed (0).
static func format_speed(speed: float) -> String:
	if not (speed > 0.0):
		return "--"
	return format_bars(speed) + "×"


## One-line consequence of a speed choice, in the game's own terms (momentum × tapeSpeed; world 1/s).
static func speed_consequence(speed: float) -> String:
	if is_equal_approx(speed, 0.5):
		return "0.5× — this take plays back over twice the time and hits half as hard; the world runs at double speed while you record"
	if is_equal_approx(speed, 1.0):
		return "1× — this take plays back in the time it took to record, at normal force; the world runs at normal speed while you record"
	if is_equal_approx(speed, 2.0):
		return "2× — this take plays back in half the time and hits twice as hard; the world runs at half speed while you record"
	if is_equal_approx(speed, 4.0):
		return "4× — this take plays back in a quarter of the time and hits four times as hard; the world runs at quarter speed while you record"
	if speed > 0.0:
		return "%s — this take plays back in %s the time it took to record; the world runs at ×%s while you record" % [
			format_speed(speed), format_bars(1.0 / speed), format_bars(1.0 / speed)]
	return ""


## "8 local bars → 4 master bars": the TIME-03 conversion stated explicitly (chapter 03 warning).
static func span_copy(local_bars: float, speed: float) -> String:
	var master := local_bars / speed
	return "%s local %s → %s master %s" % [format_bars(local_bars), _plural(local_bars, "bar"),
		format_bars(master), _plural(master, "bar")]


## World speed relative to the person playing, as shown on the ruler ("world ×0.5").
static func format_world_rate(rate: float) -> String:
	if not (rate > 0.0):
		return "world paused"
	return "world ×" + format_bars(roundf(rate * 100.0) / 100.0)


## Fraction (0..1) of the deck's span scale that one pass fills: the slowest offered speed fills
## the whole scale, so a 2× tape visibly fills half of what a 1× tape does (UI-07).
static func span_scale_fill(speed: float, offered: Array[float]) -> float:
	if not (speed > 0.0):
		return 0.0
	var slowest := speed
	for s: float in offered:
		if s > 0.0:
			slowest = minf(slowest, s)
	return clampf(slowest / speed, 0.0, 1.0)


## Master bars the span scale represents (one pass at the slowest offered speed).
static func span_scale_bars(local_bars: float, offered: Array[float], speed: float) -> float:
	var slowest := speed if speed > 0.0 else 1.0
	for s: float in offered:
		if s > 0.0:
			slowest = minf(slowest, s)
	return local_bars / slowest


# ───────────────────────────── end behaviour ─────────────────────────────

static func end_mode_info(mode: int) -> Badge:
	var b: Badge
	match mode:
		OD.EndMode.STOP:
			b = Badge.make("STOP", ICON_STOP, TONE_IDLE)
			b.copy = "at the end this self holds its last pose: still solid, still a target"
		OD.EndMode.REPEAT:
			b = Badge.make("REPEAT", ICON_REPEAT, TONE_IDLE)
			b.copy = "at the end it cuts back to the start and plays again, every action re-fires"
		OD.EndMode.REVERSE:
			b = Badge.make("REVERSE", ICON_REVERSE, TONE_IDLE)
			b.copy = "at the end it plays backward, then forward again; every action re-fires on the way"
		_:
			b = Badge.make("--", ICON_NONE, TONE_MUTED)
	return b


# ───────────────────────────── status / state tables (NEW-08, NEW-11, UI-03) ─────────────────────────────

## Cassette status. Never colour-only: each has its own word and icon.
static func status_badge(status: StringName) -> Badge:
	match status:
		DeckStatus.UNAVAILABLE:
			return Badge.make("NOT IN THIS LEVEL", ICON_NONE, TONE_MUTED, "NOT IN LEVEL")
		DeckStatus.EMPTY:
			return Badge.make("NOT RECORDED", ICON_EMPTY, TONE_IDLE, "NOT RECORDED")
		DeckStatus.ARMED:
			return Badge.make("ARMED", ICON_ARM, TONE_ARMED)
		DeckStatus.RECORDING:
			return Badge.make("RECORDING", ICON_REC, TONE_REC)
		DeckStatus.PENDING:
			return Badge.make("TAKE — NOT COMMITTED", ICON_TAKE, TONE_PENDING, "UNCOMMITTED")
		DeckStatus.COMMITTED:
			return Badge.make("COMMITTED", ICON_LOCK, TONE_LOCKED)
	return Badge.make(String(status).to_upper(), ICON_NONE, TONE_MUTED)


## The self's state in the current run (GHOST-01..06, DESYNC-07). Null when the cassette has no
## self in the run (life -1). `synced` is reported even for ghosts: the HUD shows what the sim says.
static func life_badge(life: int, synced: bool) -> Badge:
	match life:
		OD.LifeState.ALIVE:
			if synced:
				return Badge.make("ALIVE", ICON_ALIVE, TONE_GOOD)
			return Badge.make("DESYNCED — SPARK CHASING", ICON_DESYNC, TONE_DESYNC, "DESYNCED")
		OD.LifeState.REC_GHOST:
			if synced:
				return Badge.make("DIED — RECORDING AS GHOST", ICON_REC_GHOST, TONE_DEAD, "REC GHOST")
			return Badge.make("GHOST TAKE — DESYNCED", ICON_DESYNC, TONE_DESYNC, "GHOST TAKE·DESYNC")
		OD.LifeState.GHOST:
			if synced:
				return Badge.make("DEAD — GHOST", ICON_GHOST, TONE_DEAD, "DEAD·GHOST")
			return Badge.make("DEAD — GHOST, OUT OF SYNC", ICON_GHOST, TONE_DESYNC, "GHOST·NO SYNC")
	return null


## Stable identity of a status × life × synced presentation; two inputs look different iff their
## keys differ.
static func presentation_key(status: StringName, life: int, synced: bool) -> String:
	var s := status_badge(status)
	var st := life_badge(life, synced)
	return "%s#%s" % [s.key(), st.key() if st != null else "-"]


## What the transport is doing right now (NEW-11: stopped / looping / reversing). Only meaningful for
## tapes that have a recording to play; null otherwise.
static func transport_badge(deck: DeckView, beat: float) -> Badge:
	if deck.status != DeckStatus.PENDING and deck.status != DeckStatus.COMMITTED and deck.status != DeckStatus.RECORDING:
		return null
	var span := deck.span_bars * OD.BEATS_PER_BAR
	var pass_n := traversal_at(beat, span) + 1
	if deck.transport == -1:
		return Badge.make("REVERSING · PASS %d" % pass_n, ICON_REWIND, TONE_IDLE, "◀ PASS %d" % pass_n)
	if deck.transport == 1:
		if deck.end_mode == OD.EndMode.REPEAT and pass_n > 1:
			return Badge.make("LOOPING · PASS %d" % pass_n, ICON_REPEAT, TONE_IDLE, "LOOP %d" % pass_n)
		if deck.end_mode == OD.EndMode.REVERSE and pass_n > 1:
			return Badge.make("FORWARD · PASS %d" % pass_n, ICON_PLAY, TONE_IDLE, "▶ PASS %d" % pass_n)
		return Badge.make("PLAYING", ICON_PLAY, TONE_IDLE)
	if deck.status != DeckStatus.RECORDING and (deck.local_progress >= 1.0 - 1e-6 or (deck.end_mode == OD.EndMode.STOP and beat >= span - 1e-6)):
		return Badge.make("STOPPED — HOLDING POSE", ICON_HOLD, TONE_IDLE, "HOLDING")
	if beat <= 1e-6:
		return Badge.make("CUED AT BEAT 0", ICON_CUE, TONE_IDLE, "CUED")
	return Badge.make("PAUSED", ICON_HOLD, TONE_IDLE)


## The badge rows a deck shows, most important first: status, the self's run state, end mode,
## transport. Compact decks (`max_rows` < 4) fold the transport into the end-mode row when the
## transport says something the end mode alone does not (looping / reversing / holding), so a
## compact deck still distinguishes stopped / looping / reversing (NEW-11).
static func deck_badges(deck: DeckView, beat: float, phase: StringName, max_rows: int) -> Array[Badge]:
	var rows: Array[Badge] = [status_badge(deck.status)]
	if deck.status == DeckStatus.UNAVAILABLE:
		return rows
	var life := life_badge(deck.life, deck.synced)
	if life != null:
		rows.append(life)
	var end_b: Badge = end_mode_info(deck.end_mode) if deck.end_mode >= 0 else null
	var tr: Badge = transport_badge(deck, beat) if phase != SessionPhase.SETUP else null
	if max_rows >= rows.size() + 2 or tr == null or end_b == null:
		if end_b != null:
			rows.append(end_b)
		if tr != null:
			rows.append(tr)
	else:
		var says_more := tr.icon == ICON_REWIND or tr.icon == ICON_REPEAT or tr.icon == ICON_HOLD or tr.label.begins_with("FORWARD")
		if says_more:
			var merged := Badge.make("%s · %s" % [end_b.label, tr.short], tr.icon, TONE_IDLE)
			merged.copy = end_b.copy
			rows.append(merged)
		else:
			rows.append(end_b)
	while rows.size() > max_rows:
		rows.pop_back()
	return rows


# ───────────────────────────── reels ─────────────────────────────

## Signed reel spin in revolutions per second: magnitude from reel_rate, sign from the transport.
static func reel_spin(reel_rate: float, transport: int) -> float:
	if transport == 0:
		return 0.0
	return absf(reel_rate) * float(signi(transport)) * BASE_REEL_RPS


## Radii of the supply (left) and take-up (right) tape packs as tape transfers with progress.
## Area, not radius, is conserved as tape moves between reels.
static func tape_pack_radii(progress: float, hub: float, full: float) -> Vector2:
	var p := clampf(progress, 0.0, 1.0)
	var hub2 := hub * hub
	var cap := full * full - hub2
	return Vector2(sqrt(hub2 + cap * (1.0 - p)), sqrt(hub2 + cap * p))


## The reel spin and transport direction a deck shows. In setup the armed reels preview the chosen
## speed so the reel behaviour changes with the readout (NEW-10); otherwise they follow the deck.
static func deck_reel_spin(deck: DeckView, setting_up: bool) -> float:
	if setting_up and deck.speed > 0.0:
		return reel_spin(deck.speed, 1)
	return reel_spin(deck.reel_rate, deck.transport)


# ───────────────────────────── prompts ─────────────────────────────

static var _defaults: Dictionary = {}


## Default button prompts per device. These mirror the bindings the input layer is expected to use;
## set_bindings() overrides them with the live map.
static func default_bindings(device: StringName) -> Dictionary:
	if _defaults.is_empty():
		var k := ButtonPrompt.STYLE_KEY
		_defaults[DEVICE_KEYBOARD] = {
			SessionAction.START: ButtonPrompt.make("Enter", k),
			SessionAction.SPEED_DOWN: ButtonPrompt.make("Q", k),
			SessionAction.SPEED_UP: ButtonPrompt.make("E", k),
			SessionAction.CYCLE_END_MODE: ButtonPrompt.make("Tab", k),
			SessionAction.RECORD: ButtonPrompt.make("Space", k),
			SessionAction.SKIP: ButtonPrompt.make("Enter", k),
			SessionAction.END_ATTEMPT: ButtonPrompt.make("Backspace", k),
			SessionAction.RETRY_TAKE: ButtonPrompt.make("R", k),
			SessionAction.COMMIT: ButtonPrompt.make("Enter", k),
			SessionAction.RESET_ALL: ButtonPrompt.make("Delete", k),
			SessionAction.CONTINUE: ButtonPrompt.make("Enter", k),
			SessionAction.QUIT: ButtonPrompt.make("Esc", k),
		}
		_defaults[DEVICE_GAMEPAD] = {
			SessionAction.START: ButtonPrompt.make("A", ButtonPrompt.STYLE_FACE_A),
			SessionAction.SPEED_DOWN: ButtonPrompt.make("LB", ButtonPrompt.STYLE_SHOULDER),
			SessionAction.SPEED_UP: ButtonPrompt.make("RB", ButtonPrompt.STYLE_SHOULDER),
			SessionAction.CYCLE_END_MODE: ButtonPrompt.make("Y", ButtonPrompt.STYLE_FACE_Y),
			SessionAction.RECORD: ButtonPrompt.make("A", ButtonPrompt.STYLE_FACE_A),
			SessionAction.SKIP: ButtonPrompt.make("A", ButtonPrompt.STYLE_FACE_A),
			SessionAction.END_ATTEMPT: ButtonPrompt.make("B", ButtonPrompt.STYLE_FACE_B),
			SessionAction.RETRY_TAKE: ButtonPrompt.make("X", ButtonPrompt.STYLE_FACE_X),
			SessionAction.COMMIT: ButtonPrompt.make("A", ButtonPrompt.STYLE_FACE_A),
			SessionAction.RESET_ALL: ButtonPrompt.make("Y", ButtonPrompt.STYLE_FACE_Y),
			SessionAction.CONTINUE: ButtonPrompt.make("A", ButtonPrompt.STYLE_FACE_A),
			SessionAction.QUIT: ButtonPrompt.make("Start", ButtonPrompt.STYLE_MENU),
		}
	return _defaults.get(device, _defaults[DEVICE_KEYBOARD])


static func action_label(action: StringName) -> String:
	match action:
		SessionAction.START:
			return "START"
		SessionAction.SPEED_UP:
			return "FASTER"
		SessionAction.SPEED_DOWN:
			return "SLOWER"
		SessionAction.CYCLE_END_MODE:
			return "END MODE"
		SessionAction.RECORD:
			return "RECORD"
		SessionAction.SKIP:
			return "SKIP"
		SessionAction.END_ATTEMPT:
			return "END ATTEMPT"
		SessionAction.RETRY_TAKE:
			return "RETRY TAKE"
		SessionAction.COMMIT:
			return "COMMIT TAPE"
		SessionAction.RESET_ALL:
			return "RESET ALL TAPES"
		SessionAction.CONTINUE:
			return "CONTINUE"
		SessionAction.QUIT:
			return "QUIT"
	return String(action).to_upper()


## The prompt for `action`: the live binding from set_bindings() when there is one, else the
## device default.
static func prompt_for(action: StringName, device: StringName, bindings: Dictionary = {}) -> Prompt:
	var p := Prompt.new()
	p.action = action
	var b: ButtonPrompt = bindings.get(action) as ButtonPrompt if bindings.has(action) else null
	if b == null:
		b = default_bindings(device).get(action) as ButtonPrompt
	if b == null:
		b = ButtonPrompt.make("?")
	p.binding = b
	p.label = action_label(action)
	p.text = "[%s] %s" % [b.key, p.label]
	return p


# ───────────────────────────── decision (REC-04, REC-05) ─────────────────────────────

static func decision_options(actions: Array[StringName], active_tape: int) -> Array[DecisionOption]:
	var tape_name := "this tape" if active_tape < 0 or active_tape >= OD.TAPE_COUNT else "tape " + OD.TAPE_NAMES[active_tape]
	var out: Array[DecisionOption] = []
	var retry := DecisionOption.new()
	retry.action = SessionAction.RETRY_TAKE
	retry.title = "RETRY TAKE"
	retry.detail = "re-record %s — keeps every earlier tape" % tape_name
	retry.tone = &"retry"
	retry.enabled = actions.has(SessionAction.RETRY_TAKE)
	out.append(retry)
	var commit := DecisionOption.new()
	commit.action = SessionAction.COMMIT
	commit.title = "COMMIT TAPE & CONTINUE"
	commit.detail = "lock %s in and arm the next cassette" % tape_name
	commit.tone = &"commit"
	commit.enabled = actions.has(SessionAction.COMMIT)
	out.append(commit)
	var reset := DecisionOption.new()
	reset.action = SessionAction.RESET_ALL
	reset.title = "RESET ALL TAPES"
	reset.detail = "wipes every cassette — start the attempt from tape A"
	reset.tone = &"reset"
	reset.enabled = actions.has(SessionAction.RESET_ALL)
	reset.hold = true
	out.append(reset)
	return out


## What the hold-to-confirm control says (docs/ACCESSIBILITY.md "Hold actions"). Hold mode: "HOLD TO
## CONFIRM", then "KEEP HOLDING…" while `progress` fills. Press-twice mode: "PRESS TWICE TO CONFIRM",
## then "PRESS AGAIN TO CONFIRM" once the first press armed it (`progress` 1).
static func confirm_copy(press_twice: bool, progress: float) -> String:
	if press_twice:
		return "PRESS AGAIN TO CONFIRM" if progress >= 1.0 else "PRESS TWICE TO CONFIRM"
	return "HOLD TO CONFIRM" if progress <= 0.0 else "KEEP HOLDING…"


## Headline for the decision panel, from the latest resolved outcome (REC-07).
static func verdict(outcome: Outcome) -> Verdict:
	var v := Verdict.new()
	if outcome == null:
		v.title = "TAKE RECORDED"
		v.tone = &"neutral"
		v.sub = "decide what happens to this take"
	elif outcome.win:
		v.title = "THE COMBINED RUN WORKS"
		v.tone = &"win"
		v.sub = "objective complete with a survivor at the end"
	elif outcome.reason == FailReason.NO_SURVIVOR:
		v.title = "NO SURVIVOR AT THE END"
		v.tone = &"fail"
		v.sub = "at least one self must be alive when the horizon ends"
	else:
		v.title = "OBJECTIVE NOT COMPLETE"
		v.tone = &"fail"
		v.sub = "the combined run never finished the job"
	return v


# ───────────────────────────── recording ─────────────────────────────

static func recording_time_left(local_progress: float, local_bars: float) -> TimeLeft:
	var t := TimeLeft.new()
	t.fraction = clampf(1.0 - local_progress, 0.0, 1.0)
	t.local_bars = local_bars * t.fraction
	var left := t.local_bars
	var shown := ceilf(left - 1e-6) if left >= 1.0 else roundf(left * 10.0) / 10.0
	t.text = "%s local %s left" % [format_bars(shown), _plural(shown, "bar")]
	return t


## "bar 3 · beat 2" for a master beat position (both 1-based, as a musician counts).
static func master_position_text(beat: float, horizon_beats: float = INF) -> String:
	if beat >= horizon_beats - 1e-6:
		return "end · %s bars" % format_bars(horizon_beats / OD.BEATS_PER_BAR)
	var b := maxf(0.0, beat)
	var bar := floori(b / OD.BEATS_PER_BAR) + 1
	var in_bar := floori(fmod(b, float(OD.BEATS_PER_BAR))) + 1
	return "bar %d · beat %d" % [bar, in_bar]


## Count-in caption: "TAPE B · 2× · world ×0.5 while you record".
static func count_in_caption(view: SessionView) -> String:
	var a := view.active
	var speed := view.decks[a].speed if a >= 0 and a < view.decks.size() else 0.0
	var rate := 1.0 / speed if speed > 0.0 else 1.0
	return "TAPE %s · %s · %s while you record" % [OD.TAPE_NAMES[a] if a >= 0 and a < OD.TAPE_COUNT else "",
		format_speed(speed), format_world_rate(rate)]


## Decks the level offers (status not unavailable).
static func offered_count(view: SessionView) -> int:
	var n := 0
	for d: DeckView in view.decks:
		if d.status != DeckStatus.UNAVAILABLE:
			n += 1
	return n


## Text shown in the deck flash for deck_event() kinds.
static func flash_text(kind: StringName) -> String:
	match kind:
		ActionKind.LIGHT:
			return "LIGHT"
		ActionKind.HEAVY:
			return "HEAVY!"
		ActionKind.DODGE:
			return "DODGE"
		ActionKind.RANGED:
			return "FIRE"
		ActionKind.INTERACT:
			return "SWITCH"
		ActionKind.ABILITY:
			return "ABILITY"
		StateMarkKind.DEATH:
			return "✕ DOWN"
		StateMarkKind.DESYNC:
			return "DESYNC"
		StateMarkKind.RESYNC:
			return "RESYNC"
	return String(kind).to_upper()


static func flash_is_big(kind: StringName) -> bool:
	return kind == StateMarkKind.DEATH or kind == StateMarkKind.DESYNC or kind == StateMarkKind.RESYNC or kind == ActionKind.HEAVY


# ───────────────────────────── layout ─────────────────────────────

## Pixel layout of the ruler body (w × h, the area under the ruler header).
static func ruler_geometry(w: float, h: float, u: float, slim: bool) -> RulerGeometry:
	var g := RulerGeometry.new()
	g.gutter = roundf(u * 1.9) if slim else roundf(u * 5.4)
	var pad_r := roundf(u * 0.6)
	g.track_x = g.gutter
	g.track_w = maxf(10.0, w - g.gutter - pad_r)
	g.band_h = roundf(maxf(6.0, h * 0.2)) if slim else roundf(maxf(16.0, minf(h * 0.26, u * 1.6)))
	g.threat_h = 0.0 if slim else roundf(g.band_h * 0.34)
	var gap := 2.0 if slim else maxf(2.0, roundf(u * 0.16))
	var lanes_top := g.band_h + gap
	g.lane_h = maxf(3.0, (h - lanes_top - gap * 4.0) / 4.0)
	for i in 4:
		g.lane_y[i] = lanes_top + i * (g.lane_h + gap)
	return g


## Height of the ruler header row (title, position, world rate, legend) in units.
const RULER_HEAD_U := 1.35
## Dock sizes in units of UiPalette.unit_for(screen).
const MARGIN_U := 0.9
const RULER_U := 8.4
const RULER_SLIM_U := 3.6
const DECK_GAP_U := 0.7
const ROW_GAP_U := 0.55
const TAB_U := 1.2


## Deck heights (active, inactive) in units for a phase.
static func deck_heights_u(phase: StringName) -> Vector2:
	match phase:
		SessionPhase.CINEMATIC:
			return Vector2(3.2, 3.2)
		SessionPhase.RECORDING, SessionPhase.COUNTIN:
			return Vector2(6.3, 4.9)
		SessionPhase.SETUP:
			return Vector2(8.6, 6.2)
	return Vector2(7.6, 6.2)


## Relative width of the active deck in its row.
static func active_weight(phase: StringName) -> float:
	match phase:
		SessionPhase.SETUP:
			return 1.75
		SessionPhase.CINEMATIC:
			return 1.0
		SessionPhase.RECORDING, SessionPhase.COUNTIN:
			return 1.5
	return 1.3


## Where the dock goes for a screen of `size` (the HUD's own size) in `phase` with `active` deck.
## While recording the inactive decks are compact so the playfield keeps >= ~70% of the height.
static func dock_layout(size: Vector2, phase: StringName, active: int) -> DockLayout:
	var L := DockLayout.new()
	var u := UiPalette.unit_for(size)
	L.unit = u
	L.slim = phase == SessionPhase.CINEMATIC
	L.visible = phase != SessionPhase.RESULTS
	if not L.visible:
		for i in 4:
			L.decks[i] = Rect2()
		L.bottom_inset = 0.0
		return L
	var m := roundf(u * MARGIN_U)
	var ruler_h := roundf(u * (RULER_SLIM_U if L.slim else RULER_U))
	L.ruler = Rect2(m, size.y - m - ruler_h, size.x - 2.0 * m, ruler_h)
	var row_bottom := L.ruler.position.y - roundf(u * ROW_GAP_U)
	var hu := deck_heights_u(phase)
	var has_active := active >= 0 and active < OD.TAPE_COUNT
	var weight := active_weight(phase) if has_active else 1.0
	var gap := roundf(u * DECK_GAP_U)
	var avail := size.x - 2.0 * m - gap * 3.0
	var total_w := 3.0 + weight if has_active else 4.0
	var x := m
	if L.slim:
		# The cinematic steps back: four small decks centred, not full-width strips.
		var cap := u * 17.0 * 4.0
		if avail > cap:
			x = m + (avail - cap) * 0.5
			avail = cap
	var top := row_bottom
	for i in 4:
		var is_active := has_active and i == active
		var w := floorf(avail * (weight if is_active else 1.0) / total_w)
		var h := roundf(u * (hu.x if is_active or not has_active else hu.y))
		if not has_active:
			h = roundf(u * hu.y)
		L.decks[i] = Rect2(x, row_bottom - h, w, h)
		top = minf(top, row_bottom - h)
		x += w + gap
	L.tab_h = 0.0 if L.slim or not has_active else roundf(u * TAB_U)
	L.bottom_inset = size.y - (top - L.tab_h)
	if has_active:
		var ad := L.decks[active]
		L.setup_w = minf(size.x - 2.0 * m, maxf(ad.size.x, u * 34.0))
		L.setup_x = clampf(ad.position.x + (ad.size.x - L.setup_w) * 0.5, m, size.x - m - L.setup_w)
		L.setup_bottom = ad.position.y - L.tab_h - roundf(u * 0.5)
	return L


## Inside one deck of `size`: the cassette, the speed column and the badge rows. `u` is the HUD
## unit; `slim` is the cinematic strip.
static func deck_geometry(size: Vector2, u: float, slim: bool) -> DeckGeometry:
	var g := DeckGeometry.new()
	var pad := roundf(u * (0.3 if slim else 0.42))
	g.body = Rect2(pad, pad, maxf(1.0, size.x - 2.0 * pad), maxf(1.0, size.y - 2.0 * pad))
	var bh := g.body.size.y
	var col_gap := roundf(u * 0.45)
	var badge_h := clampf(u * 1.18, 12.0, bh)
	var row_gap := roundf(u * 0.2)
	var rows := clampi(floori((bh + row_gap) / (badge_h + row_gap)), 1, 4)
	if slim:
		rows = 1
		badge_h = minf(bh, u * 1.15)
	g.badge_font = maxf(9.0, badge_h * 0.56)
	# Speed column width: fits "0.5×" at the speed font; the font shrinks before anything overlaps.
	g.speed_font = clampf(bh * (0.62 if slim else 0.5), u * 1.6, u * 4.2)
	var speed_w := roundf(g.speed_font * 2.35)
	var cass_w := roundf(clampf(bh * 1.5, bh * 1.12, g.body.size.x * 0.42))
	var badge_min := u * (6.0 if slim else 7.5)
	var need := cass_w + speed_w + badge_min + col_gap * 2.0
	if need > g.body.size.x:
		# Shrink the cassette to its minimum aspect first, then the speed font.
		var over := need - g.body.size.x
		var cut := minf(over, cass_w - bh * 1.12)
		cass_w -= maxf(0.0, cut)
		over -= maxf(0.0, cut)
		if over > 0.0:
			var new_w := maxf(u * 3.4, speed_w - over)
			g.speed_font *= new_w / speed_w
			speed_w = new_w
	g.cassette = Rect2(g.body.position, Vector2(cass_w, bh))
	g.speed = Rect2(g.cassette.end.x + col_gap, g.body.position.y, speed_w, bh)
	if slim:
		g.speed_text = g.speed
		g.span_bar = Rect2()
		g.span_caption = Rect2()
	else:
		var cap_h := roundf(u * 0.8)
		var bar_h := roundf(maxf(5.0, u * 0.5))
		g.span_caption = Rect2(g.speed.position.x, g.speed.end.y - cap_h, speed_w, cap_h)
		g.span_bar = Rect2(g.speed.position.x + 2.0, g.span_caption.position.y - bar_h - roundf(u * 0.12), speed_w - 4.0, bar_h)
		g.speed_text = Rect2(g.speed.position, Vector2(speed_w, g.span_bar.position.y - g.speed.position.y - roundf(u * 0.1)))
	var bx := g.speed.end.x + col_gap
	var bw := maxf(1.0, g.body.end.x - bx)
	var total_h := rows * badge_h + (rows - 1) * row_gap
	var by := g.body.position.y + (bh - total_h) * 0.5
	for r in rows:
		g.badges.append(Rect2(bx, by + r * (badge_h + row_gap), bw, badge_h))
	# Flash over the cassette window (lower part of the cassette), never the speed column.
	g.flash = g.cassette.grow(-roundf(u * 0.1))
	return g


## Number of badge rows the deck geometry offers.
static func badge_rows(g: DeckGeometry) -> int:
	return g.badges.size()
