class_name StalkerBehaviour
extends MeleeChaser
## Stalker (AI-01, AI-02, AI-07): fast, one hit, and it hunts the FARTHEST effective self. Port of
## prototype/src/core/enemies/stalker.ts (the shared chaser it hosted lives in melee_chaser.gd).
##
## The rule is the grunt's mirror image, so the two read as a pair: the grunt punishes whoever is
## closest, the stalker goes for the straggler. Adding a self on the far side of the room drags the
## stalker across it (AI-02: more selves change circumstances, not the rule).
##
## Targeting cadence. "Farthest from me" measured continuously would make a stalker between two
## selves turn back the moment it passes the midpoint and dither there forever. So it CHOOSES on a
## legible schedule and then commits:
##   - on every bar line (master beat divisible by BEATS_PER_BAR), unless its quarry is already
##     within STALKER_COMMIT_RANGE (it never abandons prey it is about to lunge at),
##   - right after each of its own strikes,
##   - immediately when its quarry stops being targetable (dies, desyncs),
## it picks the farthest targetable self (perceived distance; ties -> lowest tape index), and hunts
## that self until the next choice. Strikes land on its beat grid like every melee enemy (AI-07).
##
## Port note: the commit-range check is a targeting decision, so it measures perceived distance
## (EnemyCommon.perceived_distance, the single effective-distance helper); the prototype measured
## raw distance there. Physical reach stays raw (MeleeChaser).

## Stalker strike arc (a quick lunge: narrower than the grunt's swing).
const STALKER_ARC: float = PI / 2.0
## Recovery after a lunge, master beats.
const STALKER_RECOVER_BEATS: float = 0.25
## Within this many tiles of its quarry it stops reconsidering on bar lines, tiles (perceived).
const STALKER_COMMIT_RANGE: float = 2.5


## Shape and rhythm of a beat-grid melee enemy (stalker.ts MeleeProfile).
class MeleeProfile:
	extends RefCounted
	## EnemyType.*
	var type: StringName = &""
	## Total strike arc in radians, centred on the facing locked at telegraph start.
	var arc: float = 0.0
	## Time the enemy stays committed after a strike, master beats.
	var recover_beats: float = 0.0
	## Stops walking at this fraction of its reach from the target's centre.
	var stop_fraction: float = 0.6
	## SimEvent.detail of its telegraph and attack (lets audio / render tell strikes apart).
	var strike_name: String = ""
	## Choose a quarry: func(w: ODSim, e: EnemyState) -> SelfActor (null = none). Called by
	## `retarget_on_beat` moments and on target loss.
	var pick: Callable
	## Re-pick on this master beat boundary? func(w: ODSim, e: EnemyState, beat: int) -> bool.
	var retarget_on_beat: Callable
	## Re-pick right after each strike?
	var retarget_after_strike: bool = false


func _init() -> void:
	type = EnemyType.STALKER
	var p := MeleeProfile.new()
	p.type = EnemyType.STALKER
	p.arc = STALKER_ARC
	p.recover_beats = STALKER_RECOVER_BEATS
	p.stop_fraction = 0.6
	p.strike_name = "lunge"
	p.pick = func(w: ODSim, e: EnemyState) -> SelfActor: return farthest_target(w, e.x, e.y)
	p.retarget_on_beat = func(w: ODSim, e: EnemyState, beat: int) -> bool: return _stalker_retarget_on_beat(w, e, beat)
	p.retarget_after_strike = true
	profile = p


static func _stalker_retarget_on_beat(w: ODSim, e: EnemyState, beat: int) -> bool:
	# beat >= 0, so % matches JS for the bar-line test.
	if beat % OD.BEATS_PER_BAR != 0:
		return false
	var q: SelfActor = EnemyCommon.self_by_index(w, e.target)
	if q == null or not EnemyCommon.targetable(q):
		return true
	var dx: float = q.pose.x - e.x
	var dy: float = q.pose.y - e.y
	return EnemyCommon.perceived_distance(w, ODGrid.hypot(dx, dy)) > STALKER_COMMIT_RANGE


## Hit every vulnerable self inside reach + body radius and the strike arc, with line of sight, at
## this instant. One hit is lethal (HEALTH-01); i-frames are judged by the combat queue.
static func melee_strike(w: ODSim, e: EnemyState, reach: float, arc: float, detail: String) -> void:
	var ar: float = Tuning.BASE.actor_radius
	var r: float = reach + ar
	for s: SelfActor in w.selves:
		if not EnemyCommon.targetable(s):
			continue
		var dx: float = s.pose.x - e.x
		var dy: float = s.pose.y - e.y
		var d: float = ODGrid.hypot(dx, dy)
		if d > r:
			continue
		if d > ar and arc < PI * 2.0:
			var slack: float = asin(minf(1.0, ar / d))
			if absf(TapeLib.angle_delta(e.facing, atan2(dy, dx))) > arc / 2.0 + slack:
				continue
		if w.grid.segment_blocked(e.x, e.y, s.pose.x, s.pose.y, true):
			continue
		w.combat.hit_self(SelfHit.make(s, "struck by %s %s" % [e.type, e.id], e.x, e.y, e.facing))
	w.emit(SimEvent.make(0, SimEventType.ENEMY_ATTACK, e.x, e.y).with_id(e.id).with_dir(e.facing).with_detail(detail))


## Farthest targetable self from (x, y) by perceived distance. Ties go to the lowest tape index
## (selves are sorted by index; strict comparison keeps the first).
static func farthest_target(w: ODSim, x: float, y: float) -> SelfActor:
	var best: SelfActor = null
	var best_d: float = -INF
	for s: SelfActor in w.selves:
		if not EnemyCommon.targetable(s):
			continue
		var dx: float = s.pose.x - x
		var dy: float = s.pose.y - y
		var d: float = EnemyCommon.perceived_distance(w, ODGrid.hypot(dx, dy))
		if d > best_d:
			best_d = d
			best = s
	return best
