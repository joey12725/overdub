class_name BruteBehaviour
extends MeleeChaser
## Brute (HEALTH-02, MOM-01..05, AI-04, AI-07): three hit points, heavy, and slow to hit back. Port
## of prototype/src/core/enemies/brute.ts.
##
##   - Hit points 3 (ENEMY_STATS): three standing 1x lights, or one 1x running heavy
##     (floor(2 x 1.5) = 3), which is the momentum lesson.
##   - Poise. A hit below BRUTE_POISE_MOMENTUM still does its damage but neither shoves nor staggers
##     it: chip damage cannot interrupt the slam. A hit at or above it is applied in full through the
##     shared formulas, where the brute's mass and poise still shrink the result: a high-momentum hit
##     really moves it (MOM-05) and can break its telegraph.
##   - Its slam is wide (BRUTE_ARC) and slow to arrive: the long telegraph (ENEMY_STATS
##     telegraphBeats) is the window to roll out or to knock it out of the windup.
##   - It walks at the NEAREST targetable self, re-choosing on every beat, like the grunt.
##   - Its body is heavy enough to hold 'heavy' pressure plates.

## Total slam arc, radians (240 deg: it is hard to stand anywhere near it except squarely behind).
const BRUTE_ARC: float = (4.0 * PI) / 3.0
## Recovery after a slam, master beats (the punish window).
const BRUTE_RECOVER_BEATS: float = 1.0
## Momentum a single hit needs to shove or stagger a brute. 3 = a 1x running heavy or anything
## stronger; a 1x light (1.2) or a 2x standing light (2.4) just chips it.
const BRUTE_POISE_MOMENTUM: float = 3.0


func _init() -> void:
	type = EnemyType.BRUTE
	heavy_body = true
	var p := StalkerBehaviour.MeleeProfile.new()
	p.type = EnemyType.BRUTE
	p.arc = BRUTE_ARC
	p.recover_beats = BRUTE_RECOVER_BEATS
	p.stop_fraction = 0.6
	p.strike_name = "slam"
	p.pick = func(w: ODSim, e: EnemyState) -> SelfActor: return EnemyCommon.nearest_target(w, e.x, e.y)
	p.retarget_on_beat = func(_w: ODSim, _e: EnemyState, _beat: int) -> bool: return true
	p.retarget_after_strike = false
	profile = p


func on_hit(_w: ODSim, _e: EnemyState, strike: EnemyStrike) -> HitResponse:
	if strike.momentum >= BRUTE_POISE_MOMENTUM:
		return HitResponse.apply()
	var st: EnemyStrike = strike.copy()
	st.knockback = 0.0
	st.has_knockback = true
	st.stagger = 0.0
	st.has_stagger = true
	return HitResponse.replace(st)
