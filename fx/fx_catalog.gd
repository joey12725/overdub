class_name FxCatalog
extends RefCounted
## Effect catalogue: which effects exist, which view modes may show them, and which effects every
## simulation event triggers (port of prototype/src/render/fx/catalog.ts).
##
## Readability policy (MUSIC-13, CINE-03, chapter 16 "readability"):
##   core       - tells the player something about the world (a hit landed, a tape desynced, the boss
##                remembers). Shown in record, review and cinematic, restrained while recording.
##   review     - secondary texture (footstep dust, impact dust). Review and cinematic only.
##   cinematic  - the musical flourishes of the winning performance. Cinematic only, never while the
##                player is in control.
## 'idle' shows no event effects at all - only the ambient music visuals.

const TIER_CORE := 0
const TIER_REVIEW := 1
const TIER_CINEMATIC := 2

# Effect ids, in catalogue order (the index is the sprite tag).
const HIT_BURST: StringName = &"hitBurst"
const HIT_STREAKS: StringName = &"hitStreaks"
const TIER_WORD: StringName = &"tierWord"
const KILL_BURST: StringName = &"killBurst"
const KILL_WORD: StringName = &"killWord"
const DEBRIS: StringName = &"debris"
const BREAK_WORD: StringName = &"breakWord"
const CLANG_SPARK: StringName = &"clangSpark"
const CLANG_TELL: StringName = &"clangTell"
const SWING_ARC: StringName = &"swingArc"
const WHIFF_PUFF: StringName = &"whiffPuff"
const DODGE_AFTERIMAGE: StringName = &"dodgeAfterimage"
const MUZZLE_FLASH: StringName = &"muzzleFlash"
const PROJECTILE_IMPACT: StringName = &"projectileImpact"
const INTERACT_PING: StringName = &"interactPing"
const INTERACT_FAIL: StringName = &"interactFail"
const DOOR_PULSE: StringName = &"doorPulse"
const PLATE_PULSE: StringName = &"platePulse"
const LASER_PULSE: StringName = &"laserPulse"
const CORE_IGNITE: StringName = &"coreIgnite"
const DEATH_SHATTER: StringName = &"deathShatter"
const TAPE_LETTER: StringName = &"tapeLetter"
const DESYNC_TEAR: StringName = &"desyncTear"
const RESYNC_CONVERGE: StringName = &"resyncConverge"
const WRAP_BLINK: StringName = &"wrapBlink"
const TURN_CHEVRONS: StringName = &"turnChevrons"
const END_STOP: StringName = &"endStop"
const TELEGRAPH_RING: StringName = &"telegraphRing"
const ENEMY_SLASH: StringName = &"enemySlash"
const ENEMY_MUZZLE: StringName = &"enemyMuzzle"
const STAGGER_STARS: StringName = &"staggerStars"
const BOSS_SHOCK: StringName = &"bossShock"
const BOSS_RECALL_TELL: StringName = &"bossRecallTell"
const OBJECTIVE_PULSE: StringName = &"objectivePulse"
const STEP_DUST: StringName = &"stepDust"
const IMPACT_DUST: StringName = &"impactDust"
const INK_SPLASH: StringName = &"inkSplash"
const SPEED_LINE_BURST: StringName = &"speedLineBurst"
const CINE_ECHO: StringName = &"cineEcho"
const CINE_FOCUS: StringName = &"cineFocus"
const FINALE_BURST: StringName = &"finaleBurst"
## Trap state changes (docs/TRAPS.md "Events for audio and fx"): one effect, dispatched on the
## event's `<kind>:<what>` detail.
const TRAP_FX: StringName = &"trapFx"

const EFFECT_IDS: Array[StringName] = [
	# core
	HIT_BURST, HIT_STREAKS, TIER_WORD, KILL_BURST, KILL_WORD, DEBRIS, BREAK_WORD, CLANG_SPARK,
	CLANG_TELL, SWING_ARC, WHIFF_PUFF, DODGE_AFTERIMAGE, MUZZLE_FLASH, PROJECTILE_IMPACT,
	INTERACT_PING, INTERACT_FAIL, DOOR_PULSE, PLATE_PULSE, LASER_PULSE, CORE_IGNITE, DEATH_SHATTER,
	TAPE_LETTER, DESYNC_TEAR, RESYNC_CONVERGE, WRAP_BLINK, TURN_CHEVRONS, END_STOP, TELEGRAPH_RING,
	ENEMY_SLASH, ENEMY_MUZZLE, STAGGER_STARS, BOSS_SHOCK, BOSS_RECALL_TELL, OBJECTIVE_PULSE,
	TRAP_FX,
	# review
	STEP_DUST, IMPACT_DUST,
	# cinematic
	INK_SPLASH, SPEED_LINE_BURST, CINE_ECHO, CINE_FOCUS, FINALE_BURST,
]

## Effect id -> TIER_*.
const EFFECT_TIER: Dictionary[StringName, int] = {
	HIT_BURST: TIER_CORE,
	HIT_STREAKS: TIER_CORE,
	TIER_WORD: TIER_CORE,
	KILL_BURST: TIER_CORE,
	KILL_WORD: TIER_CORE,
	DEBRIS: TIER_CORE,
	BREAK_WORD: TIER_CORE,
	CLANG_SPARK: TIER_CORE,
	CLANG_TELL: TIER_CORE,
	SWING_ARC: TIER_CORE,
	WHIFF_PUFF: TIER_CORE,
	DODGE_AFTERIMAGE: TIER_CORE,
	MUZZLE_FLASH: TIER_CORE,
	PROJECTILE_IMPACT: TIER_CORE,
	INTERACT_PING: TIER_CORE,
	INTERACT_FAIL: TIER_CORE,
	DOOR_PULSE: TIER_CORE,
	PLATE_PULSE: TIER_CORE,
	LASER_PULSE: TIER_CORE,
	CORE_IGNITE: TIER_CORE,
	DEATH_SHATTER: TIER_CORE,
	TAPE_LETTER: TIER_CORE,
	DESYNC_TEAR: TIER_CORE,
	RESYNC_CONVERGE: TIER_CORE,
	WRAP_BLINK: TIER_CORE,
	TURN_CHEVRONS: TIER_CORE,
	END_STOP: TIER_CORE,
	TELEGRAPH_RING: TIER_CORE,
	ENEMY_SLASH: TIER_CORE,
	ENEMY_MUZZLE: TIER_CORE,
	STAGGER_STARS: TIER_CORE,
	BOSS_SHOCK: TIER_CORE,
	BOSS_RECALL_TELL: TIER_CORE,
	OBJECTIVE_PULSE: TIER_CORE,
	TRAP_FX: TIER_CORE,
	STEP_DUST: TIER_REVIEW,
	IMPACT_DUST: TIER_REVIEW,
	INK_SPLASH: TIER_CINEMATIC,
	SPEED_LINE_BURST: TIER_CINEMATIC,
	CINE_ECHO: TIER_CINEMATIC,
	CINE_FOCUS: TIER_CINEMATIC,
	FINALE_BURST: TIER_CINEMATIC,
}

## SimEventType -> effects. tests/fx/test_fx_routing.gd fails when a SimEventType.ALL member has no
## route here, or a route names an event type that no longer exists.
const EVENT_ROUTES: Dictionary[StringName, Array] = {
	SimEventType.STEP: [STEP_DUST],
	SimEventType.SWING: [SWING_ARC],
	SimEventType.HIT: [HIT_BURST, HIT_STREAKS, TIER_WORD, IMPACT_DUST, INK_SPLASH, SPEED_LINE_BURST],
	SimEventType.WHIFF: [WHIFF_PUFF],
	SimEventType.KILL: [KILL_BURST, KILL_WORD, IMPACT_DUST, INK_SPLASH, SPEED_LINE_BURST, CINE_FOCUS],
	SimEventType.BREAK: [DEBRIS, BREAK_WORD, IMPACT_DUST, INK_SPLASH, SPEED_LINE_BURST, CINE_FOCUS],
	SimEventType.CLANG: [CLANG_SPARK, CLANG_TELL],
	SimEventType.DODGE: [DODGE_AFTERIMAGE],
	SimEventType.FIRE: [MUZZLE_FLASH],
	SimEventType.PROJECTILE_HIT: [PROJECTILE_IMPACT, TIER_WORD, INK_SPLASH],
	SimEventType.INTERACT: [INTERACT_PING],
	SimEventType.INTERACT_FAIL: [INTERACT_FAIL],
	SimEventType.DOOR: [DOOR_PULSE],
	SimEventType.PLATE: [PLATE_PULSE],
	SimEventType.LASER: [LASER_PULSE],
	SimEventType.CORE: [CORE_IGNITE, SPEED_LINE_BURST, CINE_FOCUS],
	SimEventType.SELF_DEATH: [DEATH_SHATTER, TAPE_LETTER, INK_SPLASH, CINE_FOCUS],
	SimEventType.DESYNC: [DESYNC_TEAR, CINE_ECHO],
	SimEventType.RESYNC: [RESYNC_CONVERGE, CINE_ECHO, CINE_FOCUS],
	SimEventType.TAPE_WRAP: [WRAP_BLINK, TAPE_LETTER],
	SimEventType.TAPE_TURN: [TURN_CHEVRONS, TAPE_LETTER],
	SimEventType.TAPE_END: [END_STOP, TAPE_LETTER],
	SimEventType.ENEMY_TELEGRAPH: [TELEGRAPH_RING],
	SimEventType.ENEMY_ATTACK: [ENEMY_SLASH],
	SimEventType.ENEMY_SHOT: [ENEMY_MUZZLE],
	SimEventType.ENEMY_STAGGER: [STAGGER_STARS],
	SimEventType.BOSS_PHASE: [BOSS_SHOCK, INK_SPLASH, SPEED_LINE_BURST, CINE_FOCUS],
	SimEventType.BOSS_RECALL: [BOSS_RECALL_TELL, CINE_FOCUS],
	SimEventType.OBJECTIVE: [OBJECTIVE_PULSE, FINALE_BURST, CINE_FOCUS],
	# Not in SimEventType.ALL yet (core keeps it out until every consumer routes it), but it is a real
	# event the trap simulation emits, so it is routed here.
	SimEventType.TRAP: [TRAP_FX],
}


## How a view mode dresses effects.
class ModeProfile:
	extends RefCounted
	## Event-driven effects run at all.
	var events: bool
	## Highest TIER_* allowed.
	var max_tier: int
	## Scales particle counts, sizes and alphas.
	var intensity: float
	## Scales camera-shake requests.
	var shake: float
	## Minimum momentum tier whose word readout is shown (0 shows every hit).
	var min_word_tier: int
	## Scale of floating readouts.
	var text_scale: float
	## Brightness of the ambient music visuals (runes, sigils, contour strips, epicycles).
	var ambient: float
	## Strength of the world-speed treatment (world_rate != 1).
	var world_speed: float
	## Letterbox bar height as a fraction of the screen height, per side.
	var letterbox: float

	func _init(p_events: bool, p_max_tier: int, p_intensity: float, p_shake: float, p_min_word_tier: int, p_text_scale: float, p_ambient: float, p_world_speed: float, p_letterbox: float) -> void:
		events = p_events
		max_tier = p_max_tier
		intensity = p_intensity
		shake = p_shake
		min_word_tier = p_min_word_tier
		text_scale = p_text_scale
		ambient = p_ambient
		world_speed = p_world_speed
		letterbox = p_letterbox


static var _profiles: Dictionary[StringName, ModeProfile] = {}
static var _index: Dictionary[StringName, int] = {}


## The profile of a ViewMode (idle for anything unknown).
static func profile(mode: StringName) -> ModeProfile:
	if _profiles.is_empty():
		_profiles[ViewMode.IDLE] = ModeProfile.new(false, TIER_CORE, 0.0, 0.0, 99, 0.0, 1.0, 0.0, 0.0)
		_profiles[ViewMode.RECORD] = ModeProfile.new(true, TIER_CORE, 0.7, 0.55, 2, 0.8, 0.55, 1.0, 0.0)
		_profiles[ViewMode.REVIEW] = ModeProfile.new(true, TIER_REVIEW, 0.9, 0.8, 1, 0.9, 0.8, 0.6, 0.0)
		_profiles[ViewMode.CINEMATIC] = ModeProfile.new(true, TIER_CINEMATIC, 1.2, 1.0, 0, 1.1, 1.0, 0.4, 0.085)
	var p: ModeProfile = _profiles.get(mode)
	return p if p != null else _profiles[ViewMode.IDLE]


## Index of an effect id in EFFECT_IDS (its sprite tag), -1 if unknown.
static func effect_index(id: StringName) -> int:
	if _index.is_empty():
		for i: int in EFFECT_IDS.size():
			_index[EFFECT_IDS[i]] = i
	return _index.get(id, -1)


## True when an effect of `tier` may spawn in `mode`.
static func tier_allowed(tier: int, mode: StringName) -> bool:
	var p := profile(mode)
	return p.events and tier <= p.max_tier


static func effect_allowed(id: StringName, mode: StringName) -> bool:
	return tier_allowed(EFFECT_TIER.get(id, TIER_CINEMATIC), mode)


## Effects routed from an event type (empty for an unknown type).
static func routes_for(type: StringName) -> Array:
	return EVENT_ROUTES.get(type, [])
