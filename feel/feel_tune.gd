class_name FeelTune
extends RefCounted
## Every number of the combat-feel layer, and the pure maps from simulation facts (momentum, tape
## speed, weapon style) to presentation amounts. No nodes, no clock: unit-tested in tests/feel/.
##
## MOMENTUM TIERS. The sim's momentum is impact x tape speed x approach (ARCHITECTURE "Combat").
## A standing 1x light is 1.0 and just kills a grunt; a running 4x sledge heavy is about 17.
##
##   tier 0  CLANG   momentum < 1, or any CLANG event: the hit did nothing. Must feel dull and wrong.
##   tier 1  LIGHT   1 <= m < 2     tier 2  SOLID   2 <= m < 4
##   tier 3  HEAVY   4 <= m < 8     tier 4  CRUSH   m >= 8

const TIER_CLANG: int = 0
const TIER_LIGHT: int = 1
const TIER_SOLID: int = 2
const TIER_HEAVY: int = 3
const TIER_CRUSH: int = 4
const TIER_COUNT: int = 5
const TIER_NAMES: Array[String] = ["clang", "light", "solid", "heavy", "crush"]
## Lower momentum bound of tiers 1..4.
const TIER_MIN: Array[float] = [1.0, 2.0, 4.0, 8.0]

const SPEEDS: Array[float] = [0.5, 1.0, 2.0, 4.0]

# ── per-tier tables (index = tier) ──────────────────────────────────────────────────────────────
## Visual hit-hold on the victim, seconds: its pose AND position freeze at the contact frame.
const HOLD_VICTIM: Array[float] = [0.050, 0.045, 0.075, 0.110, 0.150]
## Visual hit-hold on the attacker, seconds. A clang holds the attacker LONGER than a light hit:
## the weapon stops dead on the target and she has to drag it back.
const HOLD_ATTACKER: Array[float] = [0.075, 0.030, 0.055, 0.085, 0.120]
## Seconds over which a held presentation catches back up with the simulation (ease-out).
const CATCH_UP: Array[float] = [0.110, 0.060, 0.090, 0.120, 0.160]
## Screen shake magnitude requested through RenderCtx.shake (0..1).
const SHAKE: Array[float] = [0.03, 0.10, 0.22, 0.42, 0.70]
## Directional camera punch along the hit, tiles.
const PUNCH: Array[float] = [0.0, 0.035, 0.075, 0.135, 0.21]
## Frames (at 60 Hz) of full flash on the struck actor. Tier 3+ shows an INVERTED first frame.
const FLASH_FRAMES: Array[int] = [1, 1, 2, 2, 3]
## Impact burst diameter, tiles.
const BURST_SIZE: Array[float] = [0.85, 0.95, 1.4, 2.0, 2.9]
## Impact lines in the burst.
const BURST_LINES: Array[int] = [4, 7, 10, 15, 22]
## Burst lifetime, seconds.
const BURST_LIFE: Array[float] = [0.30, 0.16, 0.20, 0.26, 0.34]
## Squash-and-stretch amplitude on the victim (fraction of scale along / across the hit).
const SQUASH: Array[float] = [0.03, 0.12, 0.20, 0.30, 0.40]
## Recoil tilt of the victim away from the hit, degrees.
const TILT: Array[float] = [2.0, 9.0, 15.0, 22.0, 30.0]
## Dust puffs per tile of knockback slide.
const DUST_PER_TILE: Array[float] = [0.0, 2.0, 3.0, 4.0, 5.0]

# ── per-tape-speed tables (index = speed index: 0.5x, 1x, 2x, 4x) ───────────────────────────────
## Hold scale: a 0.5x hit hangs, a 4x flurry must not stall (its hits come four times as often).
const SPEED_HOLD: Array[float] = [1.4, 1.0, 0.7, 0.5]
## Shake scale: fast tapes hit harder for the same weapon.
const SPEED_SHAKE: Array[float] = [0.85, 1.0, 1.15, 1.3]
## Smear length scale (in clip fraction): slow tapes drag a deep, long smear.
const SPEED_SMEAR_SPAN: Array[float] = [1.7, 1.0, 0.85, 0.75]
## Smear width / opacity scale.
const SPEED_SMEAR_WEIGHT: Array[float] = [1.35, 1.0, 0.9, 0.8]
## Discrete echo blades inside the smear (multi-ghosting): none on slow tapes, a flurry on fast ones.
const SPEED_ECHOES: Array[int] = [0, 0, 3, 5]
## Whole-body afterimages spawned through a swing's active window.
const SPEED_BODY_GHOSTS: Array[int] = [0, 0, 2, 4]
## Extra pose drag (seconds the weapon-side presentation trails) that makes 0.5x read as heavy.
const SPEED_DRAG: Array[float] = [0.030, 0.0, 0.0, 0.0]

# ── per-style smear shape ────────────────────────────────────────────────────────────────────────
## Trail length behind the weapon, in clip fraction, for a light swing at 1x.
const STYLE_SMEAR_SPAN: Dictionary[String, float] = {
	"blade": 0.11, "shiv": 0.07, "blunt": 0.13, "whip": 0.15, "gauntlet": 0.08, "polearm": 0.13,
}
## Ribbon inner edge, as a fraction of the weapon's length from the grip (a blade smears its whole
## edge, a sledge only its head, a whip only its tip, a fist its knuckles).
const STYLE_SMEAR_INNER: Dictionary[String, float] = {
	"blade": 0.18, "shiv": 0.10, "blunt": 0.62, "whip": 0.55, "gauntlet": 0.0, "polearm": 0.55,
}
## Shader look per style: 0 = clean cut (blade, shiv), 1 = thick blunt mass, 2 = thin whip line,
## 3 = fist cone, 4 = wide polearm sweep.
const STYLE_SMEAR_LOOK: Dictionary[String, int] = {"blade": 0, "shiv": 0, "blunt": 1, "whip": 2, "gauntlet": 3, "polearm": 4}
const HEAVY_SMEAR_SCALE: float = 1.3
## Clip fractions between which a swing smears (never the wind-up, never the late recovery).
const SMEAR_FROM: float = 0.30
const SMEAR_TO: float = 0.70

## Dodge afterimages: one every this many seconds while the dodge lasts, each living this long.
const DODGE_GHOST_EVERY: float = 0.035
const GHOST_LIFE: float = 0.26
## Distance (tiles) within which an enemy attack during i-frames counts as a near miss.
const NEAR_MISS_RADIUS: float = 1.7
## Knockback presentation: slide speed (tiles / s) above which dust is kicked up.
const SLIDE_DUST_SPEED: float = 1.2
## A slide that stops while still this fast against something solid is a wall slam.
const SLAM_SPEED: float = 3.0


static func tier_of(momentum: float, clang: bool = false) -> int:
	if clang or not (momentum >= TIER_MIN[0]):
		return TIER_CLANG
	if momentum < TIER_MIN[1]:
		return TIER_LIGHT
	if momentum < TIER_MIN[2]:
		return TIER_SOLID
	if momentum < TIER_MIN[3]:
		return TIER_HEAVY
	return TIER_CRUSH


## Tier of a melee HIT event. A HIT with no CLANG beside it did damage (a keen weapon's damageEff
## can turn momentum below 1 into a damage point), so it is never presented below LIGHT; a CLANG is
## tier 0 however hard it was swung.
static func hit_tier(momentum: float, clang: bool) -> int:
	if clang:
		return TIER_CLANG
	return maxi(TIER_LIGHT, tier_of(momentum))


## Index 0..3 of the offered tape speed nearest to `speed` (in ratio terms).
static func speed_index(speed: float) -> int:
	if not (speed > 0.0):
		return 1
	var best := 1
	var best_d := INF
	for i: int in SPEEDS.size():
		var d := absf(log(speed / SPEEDS[i]))
		if d < best_d:
			best_d = d
			best = i
	return best


static func hold_victim(tier: int, speed: float) -> float:
	return HOLD_VICTIM[clampi(tier, 0, 4)] * SPEED_HOLD[speed_index(speed)]


static func hold_attacker(tier: int, speed: float) -> float:
	return HOLD_ATTACKER[clampi(tier, 0, 4)] * SPEED_HOLD[speed_index(speed)]


static func catch_up(tier: int, speed: float) -> float:
	return CATCH_UP[clampi(tier, 0, 4)] * SPEED_HOLD[speed_index(speed)]


static func shake(tier: int, speed: float) -> float:
	return minf(1.0, SHAKE[clampi(tier, 0, 4)] * SPEED_SHAKE[speed_index(speed)])


static func punch(tier: int, speed: float) -> float:
	return PUNCH[clampi(tier, 0, 4)] * SPEED_SHAKE[speed_index(speed)]


## Smear trail length in clip fraction.
static func smear_span(style: String, heavy: bool, speed: float) -> float:
	var s: float = STYLE_SMEAR_SPAN.get(style, 0.11)
	return s * (HEAVY_SMEAR_SCALE if heavy else 1.0) * SPEED_SMEAR_SPAN[speed_index(speed)]


## Smear strength 0..1 at clip fraction `frac`: off in the wind-up, full through the hit window,
## fading out over the first part of the recovery.
static func smear_envelope(frac: float) -> float:
	if frac <= SMEAR_FROM or frac >= SMEAR_TO:
		return 0.0
	if frac < 0.38:
		return (frac - SMEAR_FROM) / (0.38 - SMEAR_FROM)
	if frac <= 0.58:
		return 1.0
	return 1.0 - (frac - 0.58) / (SMEAR_TO - 0.58)


## [tail, head] clip fractions of the smear ribbon when the clip is at `frac`, playing in `dir`
## (+1 forward, -1 on a reversed tape: the trail then lies on the other side of the weapon).
static func smear_range(frac: float, span: float, dir: int) -> Vector2:
	if dir < 0:
		return Vector2(minf(SMEAR_TO, frac + span), frac)
	return Vector2(maxf(SMEAR_FROM, frac - span), frac)
