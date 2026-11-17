/**
 * Trap constants (docs/TRAPS.md). Times are master time; distances are tiles.
 */
import { KNOCKBACK_SECONDS } from '../tuning';
import { SUB_HZ, type SimEventType } from '../types';

/**
 * The SimEvent.type of every trap state change ('trap'; id = trap id, detail = '<kind>:<what>';
 * docs/TRAPS.md "Events for audio and fx").
 *
 * It is deliberately NOT yet a member of the SimEventType union in types.ts: the fx suite
 * (tests/render-fx/routing.test.ts) requires every declared type to have a route in
 * src/render/fx/catalog.ts, which belongs to the fx engineer. Consumers that do not know the type
 * ignore it (the fx director and the sfx table both skip unrouted types). To finish the wiring, add
 * `| 'trap'` to SimEventType and a `trap` entry to EVENT_ROUTES in one change, then drop this cast.
 */
export const TRAP_EVENT = 'trap' as SimEventType;

/** Telegraph look-ahead: a hazard's `warn` ramps 0→1 over this many master beats before it activates. */
export const TRAP_WARN_BEATS = 1;
/** The telegraph scan looks for the next activation on this grid (fractions of a beat: sixteenths). */
export const TRAP_WARN_GRID_PER_BEAT = 4;
/** The telegraph forecast is refreshed this many times per beat (and whenever it runs out). */
export const TRAP_WARN_REFRESH_PER_BEAT = 8;

/** Continuous hazards (spikes, flame) hit an enemy on contact and again after each full beat of contact. */
export const HAZARD_RETICK_BEATS = 1;
/** Stagger a hazard or dart inflicts on an enemy it damages, master seconds. */
export const HAZARD_STAGGER = 0.25;

export const SPIKES_DAMAGE = 1;

/** Crusher stroke damage to enemies: kills everything but a boss. */
export const CRUSHER_DAMAGE = 3;
/** Substeps a crusher takes to withdraw; it stays solid (and harmless) until they have elapsed. */
export const CRUSHER_RETRACT_SUBS = 60;

/** Default belt speed, tiles per master second. */
export const CONVEYOR_SPEED = 2;

export const FLAME_DAMAGE = 1;

/** Dart launcher defaults: beat grid, dart speed (tiles per master second), size and maximum flight. */
export const DART_EVERY = 2;
export const DART_OFFSET = 0;
export const DART_SPEED = 8;
export const DART_RADIUS = 0.12;
export const DART_RANGE = 64;
export const DART_DAMAGE = 1;
/** Substeps the launcher's `firing` flag stays up after a shot (0.1 s). */
export const DART_FLASH_SUBS = 24;

/** Default bumper launch distance for a body of mass 1, tiles. */
export const BUMPER_POWER = 3;
/** Substeps the bumper's signal / `on` flag stays up after firing (0.25 s). */
export const BUMPER_PULSE_SUBS = 60;
/** Substeps over which the LIVE self's launch is spread: the same slide time as enemy knockback. */
export const BUMPER_FLIGHT_SUBS = Math.max(1, Math.round(KNOCKBACK_SECONDS * SUB_HZ));

/** Default magnet pull for a body of mass 1, tiles per master second. */
export const MAGNET_PULL = 1.5;
/** A magnet stops pulling a body inside this distance of its centre, tiles. */
export const MAGNET_HOLD_RADIUS = 0.6;

/** Relay defaults, master beats. */
export const RELAY_QUANTIZE = 1;
export const RELAY_DELAY = 0;
export const RELAY_HOLD = 1;
