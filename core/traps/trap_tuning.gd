class_name TrapTuning
extends RefCounted
## Trap constants (prototype core/traps/tuning.ts; docs/TRAPS.md). Times are master time; distances
## are tiles. Never instantiated.
##
## The prototype's TRAP_EVENT is SimEventType.TRAP here (see its comment for why it is not in
## SimEventType.ALL yet).

## Telegraph look-ahead: a hazard's `warn` ramps 0 -> 1 over this many master beats before it activates.
const TRAP_WARN_BEATS: float = 1.0
## The telegraph scan looks for the next activation on this grid (fractions of a beat: sixteenths).
const TRAP_WARN_GRID_PER_BEAT: float = 4.0
## The telegraph forecast is refreshed this many times per beat (and whenever it runs out).
const TRAP_WARN_REFRESH_PER_BEAT: float = 8.0

## Continuous hazards (spikes, flame) hit an enemy on contact and again after each full beat of contact.
const HAZARD_RETICK_BEATS: float = 1.0
## Stagger a hazard or dart inflicts on an enemy it damages, master seconds.
const HAZARD_STAGGER: float = 0.25

const SPIKES_DAMAGE: float = 1.0

## Crusher stroke damage to enemies: kills everything but a boss.
const CRUSHER_DAMAGE: float = 3.0
## Substeps a crusher takes to withdraw; it stays solid (and harmless) until they have elapsed.
const CRUSHER_RETRACT_SUBS: int = 60

## Default belt speed, tiles per master second.
const CONVEYOR_SPEED: float = 2.0

const FLAME_DAMAGE: float = 1.0

## Dart launcher defaults: beat grid, dart speed (tiles per master second), size and maximum flight.
const DART_EVERY: float = 2.0
const DART_OFFSET: float = 0.0
const DART_SPEED: float = 8.0
const DART_RADIUS: float = 0.12
const DART_RANGE: float = 64.0
const DART_DAMAGE: float = 1.0
## Substeps the launcher's `firing` flag stays up after a shot (0.1 s).
const DART_FLASH_SUBS: int = 24

## Default bumper launch distance for a body of mass 1, tiles.
const BUMPER_POWER: float = 3.0
## Substeps the bumper's signal / `on` flag stays up after firing (0.25 s).
const BUMPER_PULSE_SUBS: int = 60
## Substeps over which the LIVE self's launch is spread: the same slide time as enemy knockback,
## max(1, round(KNOCKBACK_SECONDS * SUB_HZ)) = 43.
const BUMPER_FLIGHT_SUBS: int = 43

## Default magnet pull for a body of mass 1, tiles per master second.
const MAGNET_PULL: float = 1.5
## A magnet stops pulling a body inside this distance of its centre, tiles.
const MAGNET_HOLD_RADIUS: float = 0.6

## Relay defaults, master beats.
const RELAY_QUANTIZE: float = 1.0
const RELAY_DELAY: float = 0.0
const RELAY_HOLD: float = 1.0
