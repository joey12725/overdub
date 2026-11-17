class_name EnemyState
extends RefCounted
## Mutable per-run state of one enemy (prototype core/enemies/types.ts EnemyState; AI-01..07).
## Created fresh for every run (REC-02) by EnemyCommon.create_enemy_state.
##
## Optional TypeScript fields: `target` is a TapeIndex or -1 (none). `plan_sub` starts at -INF like
## the prototype's -Infinity so the first navigation plan is always stale.

var id: String = ""
## EnemyType.*
var type: StringName = &""
var def: EnemyDef = null
## The registered behaviour for `type`, looked up once when the run starts (port addition: the
## prototype re-read the registry on every call; the result is the same, the lookup is not repeated).
var beh: EnemyBehaviour = null
var stats: Tuning.EnemyStats = null
## Attack grid in master beats (EnemyDef.beat overrides the type default).
var every: float = 0.0
var offset: float = 0.0

var x: float = 0.0
var y: float = 0.0
var facing: float = 0.0
var hp: int = 0
var max_hp: int = 0
var alive: bool = true
var awake: bool = true

## EnemyStateName.*
var state: StringName = EnemyStateName.IDLE
## Substeps bounding the current state (for EnemySnap.state_t).
var state_start: int = 0
var state_end: int = 0
## Self currently targeted (lowest tape index on ties); -1 = none.
var target: int = -1
## Substep on which the telegraphed attack lands, or -1.
var attack_sub: int = -1

## Stagger lasts until this substep (exclusive).
var stagger_until: int = 0
## Remaining knockback slide: per-substep displacement and substeps left (MOM-05).
var knock_dx: float = 0.0
var knock_dy: float = 0.0
var knock_subs: int = 0

## Navigation route (framework-managed by EnemyCommon.walk_toward).
var path: Array[Vector2] = []
var path_idx: int = 0
var plan_sub: float = -INF
var plan_rev: int = -1
var plan_tx: float = 0.0
var plan_ty: float = 0.0

var death_sub: int = -1
var killed_by: String = ""

## Behaviour-private extras (shield timers, boss phase...). Plain data only (int, float, bool, String).
var mem: Dictionary[String, Variant] = {}
