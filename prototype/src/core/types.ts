/**
 * OVERDUB — shared contracts.
 *
 * This file is the seam between every module (core sim, content, audio, render, ui, game).
 * Rules for editing it:
 *   - You MAY add new optional fields, new union members and new exported types.
 *   - You MUST NOT rename, remove or change the meaning of anything that exists.
 *   - No runtime code besides trivial constants. No imports from other project files.
 *
 * Vocabulary (see docs/ARCHITECTURE.md):
 *   wall time    — real seconds experienced by the person holding the controller.
 *   local time   — progress along one cassette's recording. While recording, local == wall.
 *   master time  — the single shared world timeline. master = local / tapeSpeed.
 *   substep      — the atomic master simulation step: 1/SUB_HZ master seconds.
 *   local tick   — one recorded sample: 1/LOCAL_HZ local seconds.
 */

// ───────────────────────────── time ─────────────────────────────

/** Master substeps per master second. Every tape speed divides this evenly. */
export const SUB_HZ = 240;
/** Recorded samples (local ticks) per local second. */
export const LOCAL_HZ = 60;
export const BEATS_PER_BAR = 4;

/** Tape speed relative to the middle option. Powers of two only. */
export type TapeSpeed = 0.5 | 1 | 2 | 4;
export const ALL_SPEEDS: readonly TapeSpeed[] = [0.5, 1, 2, 4];

/** Master substeps the world advances per local tick of a tape at `speed` (8, 4, 2, 1). */
export function subsPerLocalTick(speed: TapeSpeed): number {
  return SUB_HZ / LOCAL_HZ / speed;
}

/** What a cassette does when its recording runs out before the master horizon does. */
export type EndMode = 'stop' | 'repeat' | 'reverse';

export type TapeIndex = 0 | 1 | 2 | 3;
export const TAPE_COUNT = 4;

export interface Vec2 {
  x: number;
  y: number;
}

// ───────────────────────────── input & tape ─────────────────────────────

/** One local tick of player intent. Movement is already camera-corrected into world axes. */
export interface PlayerInput {
  /** Desired move direction, each component in [-1, 1]; length is clamped to 1 by the controller. */
  moveX: number;
  moveY: number;
  /** Aim direction in radians (world space, atan2(y, x)). */
  aim: number;
  /** Edge-triggered buttons: true only on the tick the button went down. */
  light: boolean;
  heavy: boolean;
  dodge: boolean;
  ranged: boolean;
  interact: boolean;
  /** Gear ability button (e.g. manual desync), edge-triggered. */
  ability: boolean;
}

export type ActionKind = 'light' | 'heavy' | 'dodge' | 'ranged' | 'interact' | 'ability';

/** A recorded attempt. Tapes preserve attempts, never results (PLAY-02). */
export interface TapeEvent {
  /** Local tick on which the action started. */
  tick: number;
  kind: ActionKind;
  /** Facing/aim in radians when the action started. Playback never re-aims (PLAY-01). */
  dir: number;
  /** Actor position when the action started. */
  x: number;
  y: number;
  /** Local-space velocity (tiles per local second) when the action started; feeds momentum. */
  vx: number;
  vy: number;
}

export type AnimState =
  | 'idle'
  | 'run'
  | 'lightWindup'
  | 'lightActive'
  | 'lightRecover'
  | 'heavyWindup'
  | 'heavyActive'
  | 'heavyRecover'
  | 'dodge'
  | 'ranged'
  | 'interact'
  | 'stopped';

/**
 * One cassette's performance: a fixed trajectory plus action events (PLAY-01).
 * `ticks` local ticks were recorded, so pose arrays hold `ticks + 1` samples (sample 0 = start pose).
 */
export interface Tape {
  index: TapeIndex;
  speed: TapeSpeed;
  endMode: EndMode;
  /** Number of local ticks recorded (level.bars worth). */
  ticks: number;
  /** Interleaved x, y per sample. Length (ticks + 1) * 2. */
  pos: Float32Array;
  /** Facing in radians per sample. Length ticks + 1. */
  facing: Float32Array;
  /** AnimState index (see ANIM_STATES) per sample. Length ticks + 1. */
  anim: Uint8Array;
  events: TapeEvent[];
}

export const ANIM_STATES: readonly AnimState[] = [
  'idle',
  'run',
  'lightWindup',
  'lightActive',
  'lightRecover',
  'heavyWindup',
  'heavyActive',
  'heavyRecover',
  'dodge',
  'ranged',
  'interact',
  'stopped',
];

/** Where a tape's playhead is on its recording at a given master substep. */
export interface TapePhase {
  /** Fractional local tick in [0, ticks]. */
  tick: number;
  /** +1 forward, -1 during a reverse pass, 0 once a 'stop' tape has ended. */
  dir: 1 | -1 | 0;
  /** How many end-of-tape boundaries have been crossed so far (0 on the first traversal). */
  traversal: number;
  /** True once a 'stop' tape has reached its end. */
  ended: boolean;
}

// ───────────────────────────── equipment ─────────────────────────────

export type GearSlot = 'helmet' | 'top' | 'pants' | 'shoes' | 'melee' | 'ranged';
export const GEAR_SLOTS: readonly GearSlot[] = ['helmet', 'top', 'pants', 'shoes', 'melee', 'ranged'];

/**
 * Numeric stat modifiers. Every key is a MULTIPLIER applied on top of the base value (1 = unchanged)
 * unless its name ends in `Add`, in which case it is added. Modifiers from all equipped items combine
 * (multipliers multiply, adds add).
 */
export interface StatMods {
  /** Run speed (tiles per local second). */
  moveSpeed?: number;
  /** How quickly velocity approaches the input direction. */
  accel?: number;
  /** How much velocity survives a direction change / action (momentum retention). */
  momentumRetention?: number;
  dodgeDistance?: number;
  /** Length of the dodge invulnerability window. */
  dodgeIframes?: number;
  /** Recovery before another dodge is allowed. */
  dodgeCooldown?: number;
  /** Momentum generated by melee swings. */
  meleeImpact?: number;
  /** Damage dealt per unit momentum. */
  damage?: number;
  /** Knockback distance per unit momentum. */
  knockback?: number;
  /** Maximum knockback distance. */
  knockbackCap?: number;
  /** Stagger duration per unit momentum. */
  stagger?: number;
  /** Extra momentum from moving into a strike. */
  approachBonus?: number;
  /** Recovery spark travel speed (DESYNC-02). */
  sparkSpeed?: number;
  /** Reach for switches and other interactions, in tiles (added). */
  interactRadiusAdd?: number;
  /** Ranged weapon projectile speed. */
  projectileSpeed?: number;
  /** Ranged weapon cooldown. */
  rangedCooldown?: number;
}

/** Discrete abilities granted by gear. The sim, HUD or renderer keys behaviour off these ids. */
export type AbilityId =
  /** Ability button toggles this self into desync on demand (candidate gear idea from GEAR chapter). */
  | 'manualDesync'
  /** Enemy targeting rules treat this loadout's selves as farther away than they are. */
  | 'lowProfile'
  /** Enemy targeting rules treat this loadout's selves as nearer than they are. */
  | 'loudmouth'
  /** HUD draws upcoming enemy attack beats on the master ruler. */
  | 'beatSight'
  /** Laser hazards do not kill. */
  | 'laserProof'
  /** Standing still on a pressure plate counts double / holds heavy plates. */
  | 'heavyStep'
  /** Dodge passes through enemies and low barriers. */
  | 'phaseDodge'
  /** Ending a dodge into a strike adds momentum. */
  | 'slideStrike'
  /** Heavy attacks reflect projectiles that are inside the swing arc. */
  | 'parry'
  /** A melee kill refunds the dodge cooldown. */
  | 'killRefresh';

export interface MeleeSwingDef {
  /** Local ticks before the hit frame. */
  windup: number;
  /** Local ticks the hit volume stays live. */
  active: number;
  /** Local ticks of recovery after the active window. */
  recover: number;
  /** Base momentum of the swing at 1x tape speed, standing still. */
  impact: number;
  /** Move-speed multiplier while the swing is in progress. */
  moveMul: number;
}

export interface MeleeWeaponDef {
  /** Reach of the hit volume in tiles, measured from the actor centre. */
  reach: number;
  /** Total arc of the hit volume in degrees, centred on the swing direction. */
  arcDeg: number;
  light: MeleeSwingDef;
  heavy: MeleeSwingDef;
  /** Multiplier from momentum to damage. */
  damageEff: number;
  /** Multiplier from momentum to knockback distance. */
  knockbackEff: number;
  /** Multiplier from momentum to stagger duration. */
  staggerEff: number;
  /** 'blade' | 'blunt' etc. — presentation + flavour only. */
  style: 'blade' | 'blunt' | 'whip' | 'gauntlet';
}

export type RangedArchetype = 'missile' | 'pierce' | 'phase' | 'arc' | 'burst';

export interface RangedWeaponDef {
  archetype: RangedArchetype;
  /** Projectile speed in tiles per MASTER second. Missiles are deliberately very slow (WEAPON-02). */
  speed: number;
  /** Maximum travel distance in tiles (missile: lifetime distance). */
  range: number;
  /** Momentum delivered on hit (feeds the same damage/knockback/stagger model as melee). */
  impact: number;
  /** Local ticks the firing actor is committed (cannot act). */
  commit: number;
  /** Local ticks before another shot may be fired. */
  cooldown: number;
  /** How many enemies one projectile can pass through (pierce). 0 = stops at first hit. */
  pierce: number;
  /** Projectile ignores walls/closed doors (phase). */
  passesWalls: boolean;
  /** Lobbed: ignores low cover and enemies in flight, damages a small radius on landing (arc). */
  lobbed: boolean;
  /** Projectiles per shot (burst) and the total spread in degrees. */
  count: number;
  spreadDeg: number;
  /** Homing turn rate in radians per master second (missile). 0 = flies straight. */
  turnRate: number;
  /** Blast radius in tiles on impact (0 = single target). */
  blast: number;
  /**
   * Optional: collision radius of each projectile in tiles. Absent = the sim's default. Lets a
   * weapon be "thin" (pierce shot must be lined up precisely) or "fat" independently of blast.
   */
  radius?: number;
  /**
   * Optional, lobbed weapons: the shell never lands closer than this many tiles from the launcher
   * (the arc shot's minimum-range feel). Absent = no minimum.
   */
  minRange?: number;
}

export interface GearItem {
  id: string;
  slot: GearSlot;
  name: string;
  /** One-line player-readable statement of the mechanical effect (APPAREL-03). */
  effect: string;
  /** Flavour text. */
  lore: string;
  mods?: StatMods;
  abilities?: AbilityId[];
  melee?: MeleeWeaponDef;
  ranged?: RangedWeaponDef;
  /** Presentation hints for the character model (colour / silhouette variant). */
  look?: { color?: string; variant?: string };
  /**
   * Optional: the item's trade-off in plain words, shown by the loadout screen next to the effect
   * (WEAPON-02 "stated downside"). Absent = the UI states the archetype's inherent trade-off.
   */
  downside?: string;
}

/** Item ids per slot. Every slot always holds an item (baseline gear cannot be unequipped to empty). */
export type Loadout = Record<GearSlot, string>;

/** A loadout resolved into the numbers and flags the sim consumes. */
export interface ResolvedLoadout {
  loadout: Loadout;
  mods: Required<StatMods>;
  abilities: AbilityId[];
  melee: MeleeWeaponDef;
  ranged: RangedWeaponDef;
  /**
   * Presentation hints of the equipped items, by slot (copied from GearItem.look), so the renderer
   * can show equipped clothing (APPAREL-03) without importing the gear catalogue. Optional: a slot
   * without an entry draws Moxie's baseline look.
   */
  looks?: Partial<Record<GearSlot, { color?: string; variant?: string }>>;
}

// ───────────────────────────── level data ─────────────────────────────

export type Theme = 'upper' | 'mid' | 'lower' | 'core';

/**
 * Map rows use one character per tile:
 *   '#' solid wall          '.' floor              ' ' void (no floor, impassable)
 *   '=' low barrier (blocks movement, not projectiles/line of sight)
 *   ':' metal grate floor   ',' overgrown floor    '~' inscribed/rune floor
 * Anything dynamic (doors, switches, enemies…) is an entity placed on top of floor.
 * Tile (c, r) covers world x in [c, c+1) and y in [r, r+1). Row 0 is the top of the array.
 */
export type MapRows = string[];

/** Boolean logic over named signals; drives doors, lasers and objectives. */
export type SignalExpr =
  | { sig: string }
  | { not: SignalExpr }
  | { and: SignalExpr[] }
  | { or: SignalExpr[] }
  | { xor: [SignalExpr, SignalExpr] }
  | { const: boolean }
  /** True while masterBeat mod `every` is within [from, to). Beat-timed mechanisms. */
  | { beat: { every: number; from: number; to: number } };

export type EnemyType =
  /** Walks at the NEAREST living self and strikes on the beat. 1 hit. */
  | 'grunt'
  /** Hunts the FARTHEST living self. 1 hit, fast. */
  | 'stalker'
  /** Stationary; fires at the nearest self in line of sight on its beat grid. Destroyed by melee. */
  | 'turret'
  /** Shield recharges instantly: needs a second hit inside a short window. */
  | 'shielder'
  /** Heavy: 3 hits, strong knockback resistance, slow telegraphed slam. */
  | 'brute'
  /** Hovering ranged unit that keeps distance and fires on off-beats. 2 hits. */
  | 'drone'
  /** Outside-the-loop boss with a health bar and cross-recording memory. */
  | 'boss';

export interface EnemyDef {
  kind: 'enemy';
  id: string;
  type: EnemyType;
  x: number;
  y: number;
  /** Initial facing in radians. */
  facing?: number;
  /** Override hit points (boss health, tougher variants). */
  hp?: number;
  /** Attack grid override: fires/strikes every `every` beats, offset by `offset` beats. */
  beat?: { every: number; offset: number };
  /** Turret only: restrict aim to an arc (radians) around `facing`. Omit for 360°. */
  arc?: number;
  /** Stays asleep until this signal is true. */
  wakeWhen?: SignalExpr;
}

export interface DoorDef {
  kind: 'door';
  id: string;
  /** Tiles the door occupies when closed. */
  cells: { c: number; r: number }[];
  /** Door is open while this evaluates true. */
  openWhen: SignalExpr;
}

export interface SwitchDef {
  kind: 'switch';
  /** Signal id; true when the switch is on. An 'interact' attempt in range toggles it. */
  id: string;
  x: number;
  y: number;
  initial?: boolean;
}

export interface PlateDef {
  kind: 'plate';
  /** Signal id; true while an effective body (alive + synced self, or an enemy) stands on it. */
  id: string;
  c: number;
  r: number;
  /** Requires the 'heavyStep' ability or a brute/boss body. */
  heavy?: boolean;
}

export interface BreakableDef {
  kind: 'breakable';
  /** Signal id; true once broken. */
  id: string;
  c: number;
  r: number;
  /** A single melee hit needs at least this much momentum to break it (Scenario K). */
  threshold: number;
}

export interface LaserDef {
  kind: 'laser';
  id: string;
  /** Beam runs between these tile centres; kills living, synced selves that touch it while on. */
  from: Vec2;
  to: Vec2;
  /** Laser is on while this evaluates true. */
  onWhen: SignalExpr;
}

/** A core is an objective target that must be struck (momentum >= threshold) to activate. */
export interface CoreDef {
  kind: 'core';
  /** Signal id; true once activated. */
  id: string;
  x: number;
  y: number;
  threshold?: number;
}

export interface ExitDef {
  kind: 'exit';
  /** Signal id `exit` is true while an alive + synced self stands inside. */
  id: string;
  c: number;
  r: number;
  w: number;
  h: number;
}

/** Non-colliding set dressing. Purely visual. */
export interface DecorDef {
  kind: 'decor';
  type:
    | 'graffiti'
    | 'vines'
    | 'bush'
    | 'crate'
    | 'barrel'
    | 'pipe'
    | 'console'
    | 'generator'
    | 'vent'
    | 'arch'
    | 'rubble'
    | 'chest'
    | 'neon'
    | 'runePanel'
    | 'waveScreen'
    | 'cable'
    | 'lamp'
    | 'timeMachine';
  x: number;
  y: number;
  /** Rotation in quarter turns. */
  rot?: 0 | 1 | 2 | 3;
  /** Free-form variant (graffiti text, neon colour…). */
  variant?: string;
}

// ── traps and automated machinery (docs/TRAPS.md; simulated by src/core/traps) ──

/**
 * Cardinal direction on the tile grid: 'n' points toward row 0 of the map array (−y), 'e' toward
 * higher columns (+x), 's' toward higher rows (+y), 'w' toward lower columns (−x).
 */
export type Dir4 = 'n' | 'e' | 's' | 'w';

/** A tile reference, same coordinates as door cells and plates. */
export interface TileRef {
  c: number;
  r: number;
}

/** Floor tiles that are lethal to vulnerable selves and damaging to grounded enemies while raised. */
export interface SpikesDef {
  kind: 'spikes';
  /** Signal id; true while raised. */
  id: string;
  cells: TileRef[];
  /** Raised while this evaluates true. */
  upWhen: SignalExpr;
  /** Damage per hit to enemies (default 1). */
  damage?: number;
}

/** A piston: lethal on the stroke, solid (like a closed door) while extended. */
export interface CrusherDef {
  kind: 'crusher';
  /** Signal id; true while solid (from the stroke until the retract completes). */
  id: string;
  /** Floor tiles occupied when extended, ordered from the housing outward. */
  cells: TileRef[];
  /** Extended while this evaluates true. */
  extendWhen: SignalExpr;
  /** Presentation only: travel direction of the piston (default: inferred from the first two cells). */
  dir?: Dir4;
  /** Stroke damage to enemies (default 3). */
  damage?: number;
}

/** A belt that carries grounded enemies, floor-height projectiles and the LIVE self. */
export interface ConveyorDef {
  kind: 'conveyor';
  /** Signal id; true while running. `<id>.rev` is true while reversed. */
  id: string;
  cells: TileRef[];
  /** Travel direction when not reversed. */
  dir: Dir4;
  /** Tiles per master second (default 2). */
  speed?: number;
  /** Runs while true (default: always). */
  runWhen?: SignalExpr;
  /** Runs the opposite way while true. */
  reverseWhen?: SignalExpr;
}

/** A directional flame from a nozzle tile, stopped by anything that blocks shots. */
export interface FlameDef {
  kind: 'flame';
  /** Signal id; true while burning. */
  id: string;
  /** The nozzle tile (normally a wall tile). The jet starts on the next tile along `dir`. */
  c: number;
  r: number;
  dir: Dir4;
  /** Whole tiles covered when nothing blocks the jet. */
  range: number;
  /** Burning while this evaluates true. */
  onWhen: SignalExpr;
  /** Damage per hit to enemies (default 1). */
  damage?: number;
}

/** An indestructible automated shooter firing straight darts on a beat grid, never targeting. */
export interface DartDef {
  kind: 'dart';
  /** Signal id; true while enabled. */
  id: string;
  /** The launcher tile (normally a wall tile). */
  c: number;
  r: number;
  dir: Dir4;
  /** Fires on master beats `offset + k·every` (defaults 2 and 0). */
  every?: number;
  offset?: number;
  /** Fires only while true (default: always). */
  enabledWhen?: SignalExpr;
  /** Dart speed, tiles per master second (default 8). */
  speed?: number;
}

/** A spring plate that launches what stands on it (enemies, the live self; never a recorded self). */
export interface BumperDef {
  kind: 'bumper';
  /** Signal id; true for a short pulse after each firing. */
  id: string;
  c: number;
  r: number;
  dir: Dir4;
  /** Launch distance in tiles for a body of mass 1 (default 3). */
  power?: number;
  /** Fires once each time this BECOMES true. */
  fireWhen: SignalExpr;
}

/** A tripwire that is a signal source: true while a detected body breaks the beam. Harmless. */
export interface SensorDef {
  kind: 'sensor';
  /** Signal id; true while tripped (or forever once tripped, with `latch`). */
  id: string;
  from: Vec2;
  to: Vec2;
  /** Which bodies trip it (default 'any'). */
  detects?: 'any' | 'selves' | 'enemies';
  latch?: boolean;
}

/** Signal logic with memory: turns a trigger into a beat-quantised pulse, latch or toggle. */
export interface RelayDef {
  kind: 'relay';
  /** Signal id; the relay's output. `<id>.armed` is true from the trigger until it fires. */
  id: string;
  /** The relay arms each time this BECOMES true. */
  trigger: SignalExpr;
  /** 'pulse' (default): true for `hold` beats. 'latch': true forever. 'toggle': flips. */
  mode?: 'pulse' | 'latch' | 'toggle';
  /** Fire on the first master beat multiple of this at or after the trigger (default 1; 0 = at once). */
  quantize?: number;
  /** Extra beats after the quantised boundary (default 0). */
  delay?: number;
  /** Pulse length in beats (default 1). */
  hold?: number;
  /** Where to draw its indicator lamp (optional; it has no body). */
  x?: number;
  y?: number;
}

/** Pulls living enemies within a radius toward a point while on. */
export interface MagnetDef {
  kind: 'magnet';
  /** Signal id; true while pulling. */
  id: string;
  x: number;
  y: number;
  radius: number;
  /** Tiles per master second for a body of mass 1 (default 1.5). */
  pull?: number;
  /** Pulling while this evaluates true. */
  onWhen: SignalExpr;
}

export type TrapDef =
  | SpikesDef
  | CrusherDef
  | ConveyorDef
  | FlameDef
  | DartDef
  | BumperDef
  | SensorDef
  | RelayDef
  | MagnetDef;

export type EntityDef =
  | EnemyDef
  | DoorDef
  | SwitchDef
  | PlateDef
  | BreakableDef
  | LaserDef
  | CoreDef
  | ExitDef
  | DecorDef
  | SpikesDef
  | CrusherDef
  | ConveyorDef
  | FlameDef
  | DartDef
  | BumperDef
  | SensorDef
  | RelayDef
  | MagnetDef;

export interface ObjectiveDef {
  /**
   *  'eliminate' — every enemy (or those listed in `targets`) is dead.
   *  'reach'     — an alive + synced self is inside the exit when the horizon ends.
   *  'activate'  — every core (or those in `targets`) is activated.
   *  'boss'      — the boss is dead.
   *  'signal'    — custom: `when` latches true at any point of the run.
   */
  type: 'eliminate' | 'reach' | 'activate' | 'boss' | 'signal';
  targets?: string[];
  when?: SignalExpr;
  /** Short imperative shown in the HUD ("Break the wall", "Kill both turrets"). */
  text: string;
}

/** One cassette's musical layer for a level (MUSIC-02). Interpreted by src/audio. */
export interface TrackMusicDef {
  role: 'bass' | 'drums' | 'melody' | 'chord';
  /** Harmonograph formula id (see src/vendor/harmonograph.js `catalogue`). */
  formula: string;
  params?: Record<string, number>;
  /** Drum genre starting point when role is 'drums'. */
  genre?: string;
}

export interface LevelMusicDef {
  /** Root pitch class 0–11 and Harmonograph scale name. */
  root: number;
  scale: string;
  /** Roman-numeral style progression as scale degrees (0-based), one chord per `chordBars` bars. */
  progression: number[];
  chordBars?: number;
  /** Exactly four entries: the layer owned by cassette 1..4. */
  tracks: [TrackMusicDef, TrackMusicDef, TrackMusicDef, TrackMusicDef];
}

export interface LevelDef {
  id: string;
  /** Position on the fixed campaign path, 0-based (LEVEL-08). */
  index: number;
  name: string;
  /** One-line teaser shown on the campaign path. */
  tagline: string;
  theme: Theme;
  /** Master tempo. 3600 / bpm must be an integer so a beat is a whole number of local ticks. */
  bpm: number;
  /** Local recording allowance in bars — identical for every tape speed (TIME-02, TIME-04). */
  bars: number;
  /** Length of the whole encounter on the master timeline, in master bars (authored; OPEN-02). */
  horizonBars: number;
  /** How many cassettes the level offers (LEVEL-02). */
  maxTapes: 1 | 2 | 3 | 4;
  /** Speeds / end behaviours the level exposes (unlocked progressively; PLAY-05). */
  speeds: TapeSpeed[];
  endModes: EndMode[];
  map: MapRows;
  /** Every tape starts here at beat zero (REC-02). */
  start: Vec2;
  startFacing?: number;
  entities: EntityDef[];
  objective: ObjectiveDef;
  music: LevelMusicDef;
  /** Gear ids awarded the first time the level is cleared. */
  loot: string[];
  /** Briefing lines shown before the first take; teach one idea at a time. */
  briefing: string[];
  /** Optional contextual hints keyed by tape number (1-based) shown during setup. */
  hints?: Record<number, string>;
}

// ───────────────────────────── simulation output ─────────────────────────────

/** Life state of a self within the current run. Recalculated every run (GHOST-06). */
export type LifeState =
  /** Physically effective. */
  | 'alive'
  /** The live take after death: still constrained by walls, still interactive, takes no damage (GHOST-02..04). */
  | 'recGhost'
  /** A played-back tape after death: follows its path, intangible, harmless (GHOST-05). */
  | 'ghost';

export interface ActorSnap {
  tape: TapeIndex;
  /** True for the self currently under live control. */
  live: boolean;
  /** Projection position: always the recorded/intended pose. */
  x: number;
  y: number;
  facing: number;
  anim: AnimState;
  life: LifeState;
  /** False while desynchronised (DESYNC-07): harmless, invulnerable, cannot operate mechanisms. */
  synced: boolean;
  /** Recovery spark position while desynced (DESYNC-02). */
  spark?: Vec2;
  /** True while dodge invulnerability is active. */
  iframes: boolean;
  /** Playhead on this actor's tape. */
  phase: TapePhase;
  /** Master-space velocity in tiles per master second (for animation lean / motion trails). */
  vx: number;
  vy: number;
}

export interface EnemySnap {
  id: string;
  type: EnemyType;
  x: number;
  y: number;
  facing: number;
  hp: number;
  maxHp: number;
  alive: boolean;
  state: 'asleep' | 'idle' | 'move' | 'telegraph' | 'attack' | 'stagger' | 'dead';
  /** 0..1 progress through the current state (telegraph fill, stagger recovery…). */
  stateT: number;
  /** Tape index of the self it is currently targeting, if any. */
  target?: TapeIndex;
  /** Shielder: shield currently up. */
  shield?: boolean;
  /** Boss only: current phase and whether it is replaying remembered pressure. */
  bossPhase?: number;
  /**
   * Boss only: true while the current telegraph/attack is driven by BossMemory (acting on a
   * remembered recording) rather than ordinary reactivity, so the renderer can show it (BOSS-02).
   */
  bossRecall?: boolean;
  /** Boss only: the committed tape whose memory is being acted on, when `bossRecall` is true. */
  bossRecallTape?: TapeIndex;
  /**
   * Boss only: the remembered place a memory strike will land on, while `bossRecall` is true, so the
   * renderer can mark the floor there (the recall telegraph is drawn away from the boss's body).
   */
  bossRecallAt?: Vec2;
}

export interface ProjectileSnap {
  id: number;
  /** 'self' projectiles carry the firing tape's index; enemy projectiles carry the enemy id. */
  owner: { tape: TapeIndex } | { enemy: string };
  /** 'dart' is fired by a dart launcher trap; its owner is `{ enemy: <launcher id> }` (docs/TRAPS.md). */
  archetype: RangedArchetype | 'bolt' | 'shock' | 'dart';
  x: number;
  y: number;
  /** Visual height above the floor (arc shots). */
  z: number;
  dir: number;
  /** Missile only: id of the locked target. */
  targetId?: string;
}

export interface MechSnap {
  id: string;
  kind:
    | 'door'
    | 'switch'
    | 'plate'
    | 'breakable'
    | 'laser'
    | 'core'
    | 'exit'
    // traps (docs/TRAPS.md "Snapshot fields"); listed after the classic mechanisms in `mechs`
    | 'spikes'
    | 'crusher'
    | 'conveyor'
    | 'flame'
    | 'dart'
    | 'bumper'
    | 'sensor'
    | 'relay'
    | 'magnet';
  /**
   * Door: open. Switch/plate/core/exit: on. Breakable: broken. Laser: firing.
   * Spikes: raised. Crusher: solid. Conveyor: running. Flame: burning. Dart: enabled. Bumper: just
   * fired. Sensor: tripped. Relay: output. Magnet: pulling.
   */
  on: boolean;
  /**
   * 0..1 open/close animation progress for doors. Traps: spikes 1 raised / 0 down; crusher
   * extension; dart progress toward the next shot; bumper spring return 1→0; relay armed→fire.
   */
  t?: number;
  /** Traps: 0..1 telegraph ramp over the beat before a hazard activates (relay: 1 while armed). */
  warn?: number;
  /** Traps: current direction in radians (conveyor travel, flame, dart lane, bumper launch, crusher). */
  dir?: number;
  /** Traps: flame — current jet length in tiles; sensor — live beam length in tiles. */
  reach?: number;
  /** Traps: dart launcher / bumper — true for a short flash after firing. */
  firing?: boolean;
}

export interface ObjectiveSnap {
  /** Latched: the objective has been satisfied in this run. */
  complete: boolean;
  /** 0..1 progress (enemies killed / total, cores lit / total, boss damage). */
  progress: number;
  /** Count of selves that are currently alive (not ghost). */
  survivors: number;
}

/** Everything a renderer / HUD / audio layer needs for one instant of the encounter. */
export interface FrameSnapshot {
  /** Master substep index. */
  sub: number;
  /** Master beat position (float). */
  beat: number;
  actors: ActorSnap[];
  enemies: EnemySnap[];
  projectiles: ProjectileSnap[];
  mechs: MechSnap[];
  objective: ObjectiveSnap;
}

export type SimEventType =
  | 'step' // footstep of a self
  | 'swing' // melee swing became active
  | 'hit' // a self's attack connected with an enemy / object
  | 'whiff' // a swing's active window ended without connecting
  | 'kill' // enemy died
  | 'break' // breakable wall destroyed
  | 'clang' // hit lacked the momentum to matter (e.g. below a breakable's threshold, shield up)
  | 'dodge'
  | 'fire' // a self launched a ranged projectile
  | 'projectileHit'
  | 'interact' // a self toggled a switch
  | 'interactFail' // interact attempt with nothing in range / while ineffective
  | 'door' // door changed state
  | 'plate' // plate changed state
  | 'laser' // laser changed state
  | 'core' // core activated
  | 'selfDeath' // a self died (becomes ghost / recGhost)
  | 'desync'
  | 'resync'
  | 'tapeWrap' // a 'repeat' tape cut back to its start
  | 'tapeTurn' // a 'reverse' tape turned around
  | 'tapeEnd' // a 'stop' tape ran out
  | 'enemyTelegraph'
  | 'enemyAttack'
  | 'enemyShot'
  | 'enemyStagger'
  | 'bossPhase'
  | 'bossRecall' // the outside-the-loop boss acts on a remembered recording
  | 'objective'; // objective latched complete

export interface SimEvent {
  sub: number;
  type: SimEventType;
  x: number;
  y: number;
  /** Self involved, if any. */
  tape?: TapeIndex;
  /** Enemy / mechanism involved, if any. */
  id?: string;
  /** Direction in radians, where meaningful. */
  dir?: number;
  /** Momentum / intensity, where meaningful. */
  power?: number;
  /** Extra discriminator: 'light' | 'heavy' | archetype | 'on' | 'off' … */
  detail?: string;
}

export type FailReason = 'objective' | 'noSurvivor';

export interface Outcome {
  /** REC-07: objective complete AND at least one self alive at the end of the horizon. */
  win: boolean;
  objectiveComplete: boolean;
  survivors: TapeIndex[];
  reason?: FailReason;
  /** Human explanations in the game's own terms ("Tape 1 died at beat 9", "Spark never caught up"). */
  notes: string[];
}

/**
 * Cross-recording memory for the outside-the-loop boss (BOSS-01/02).
 * Built ONLY from committed tapes; discarded takes and the cinematic replay never update it.
 */
export interface BossMemory {
  /** Per committed tape: sampled positions in master beats the boss will pre-empt. */
  observed: {
    tape: TapeIndex;
    speed: TapeSpeed;
    samples: { beat: number; x: number; y: number }[];
    /**
     * Optional: every attack attempt (light, heavy, ranged) the tape makes within the horizon, end
     * behaviour applied, in master beats. Absent = the boss remembers positions only.
     */
    actions?: BossMemoryAction[];
  }[];
}

/** One remembered attack attempt of a committed tape (see BossMemory.observed[].actions). */
export interface BossMemoryAction {
  /** Master beat (fractional) at which the attempt fired. */
  beat: number;
  /** Recorded position of the self at that instant. */
  x: number;
  y: number;
  kind: ActionKind;
}

export interface SimConfig {
  level: LevelDef;
  loadout: ResolvedLoadout;
  /** Tapes to play back (already recorded). */
  tapes: Tape[];
  /**
   * Present when a new take is being recorded: the live self is driven by `stepLocalTick`.
   * Absent for authoritative playback, where every tape (including a just-recorded one) is fixed.
   */
  live?: { index: TapeIndex; speed: TapeSpeed; endMode: EndMode };
  bossMemory?: BossMemory;
}

/** The deterministic encounter simulation. Same config + same inputs ⇒ same result, bit for bit. */
export interface ISim {
  readonly config: SimConfig;
  /** Current master substep. */
  readonly sub: number;
  /** Total substeps in the encounter horizon. */
  readonly horizonSubs: number;
  /** Local ticks in one recording (level.bars). */
  readonly tapeTicks: number;
  /** Record mode: local ticks recorded so far. */
  readonly localTick: number;
  /** Record mode: true once the take's local allowance is used up. Playback: true at the horizon. */
  readonly done: boolean;
  /** Record mode only: advance the live self one local tick and the world the matching substeps. */
  stepLocalTick(input: PlayerInput): void;
  /** Playback mode only: advance exactly one master substep. */
  stepSub(): void;
  snapshot(): FrameSnapshot;
  /** Events emitted since the last drain, in order. */
  drainEvents(): SimEvent[];
  /** Record mode: the take recorded so far as a Tape (complete once `done`). */
  liveTape(): Tape;
  /** Outcome as of now; authoritative only for playback mode at the horizon. */
  outcome(): Outcome;
  /**
   * Optional: 'beatSight' data for the HUD (SessionView.threatBeats). Master beats of upcoming enemy
   * attacks from now to `lookAheadBeats` master beats ahead (default 8), sorted ascending; a
   * forecast from the current state. Empty when the loadout lacks 'beatSight'.
   */
  threatBeats?(lookAheadBeats?: number): number[];
}

/** Result of resolving the whole combined encounter under playback rules (REC-06, OPEN-07). */
export interface Resolution {
  outcome: Outcome;
  /** One snapshot every FRAME_SUBS substeps, starting at substep 0; replayed verbatim by the cinematic. */
  frames: FrameSnapshot[];
  events: SimEvent[];
  horizonSubs: number;
}

/** Substeps between stored snapshots in a Resolution (60 snapshots per master second). */
export const FRAME_SUBS = 4;

// ───────────────────────────── session (one level attempt) ─────────────────────────────

export type SessionPhase =
  /** Level briefing / first look. */
  | 'briefing'
  /** Choosing tape speed and end behaviour for the next take. */
  | 'setup'
  /** "five, six, seven, eight". */
  | 'countin'
  /** Live take in progress. */
  | 'recording'
  /** Watching the combined result of the takes so far at true master speed (skippable). */
  | 'review'
  /** Retry take / commit and advance / reset the whole attempt. */
  | 'decision'
  /** Locked, non-interactive true-speed performance of a winning attempt (CINE-01..05). */
  | 'cinematic'
  /** Level cleared; loot and next-level prompt. */
  | 'results';

export type DeckStatus =
  /** Level does not offer this cassette. */
  | 'unavailable'
  /** Not recorded yet. */
  | 'empty'
  /** Being configured for the next take. */
  | 'armed'
  | 'recording'
  /** Recorded but not yet committed (awaiting decision). */
  | 'pending'
  | 'committed';

/** Everything the cassette-deck HUD needs for one cassette (UI-06, UI-07, NEW-07..11). */
export interface DeckView {
  index: TapeIndex;
  status: DeckStatus;
  speed: TapeSpeed | null;
  endMode: EndMode | null;
  /** 0..1 progress along the local tape right now. */
  localProgress: number;
  /** Playhead direction: 1 forward, -1 reversing, 0 stopped/idle. */
  transport: 1 | -1 | 0;
  /** Reel spin rate relative to the viewer's clock (so 2x visibly spins twice as fast as 1x). */
  reelRate: number;
  life: LifeState | null;
  synced: boolean;
  /** Master-bar span of one traversal: level.bars / speed. */
  spanBars: number;
  /** Event markers on this tape, in LOCAL ticks, for the timeline lane. */
  marks: { tick: number; kind: ActionKind }[];
  /** Master beats at which this self died / desynced / resynced in the latest resolved run. */
  stateMarks: { beat: number; kind: 'death' | 'desync' | 'resync' }[];
}

export interface SessionView {
  phase: SessionPhase;
  level: LevelDef;
  decks: [DeckView, DeckView, DeckView, DeckView];
  /** Index of the cassette being set up / recorded, or null. */
  active: TapeIndex | null;
  /** Master beat position of the playhead. */
  beat: number;
  /** Total master beats in the horizon. */
  horizonBeats: number;
  /** How fast master time is passing relative to wall time right now (1/speed while recording). */
  worldRate: number;
  /** Count-in: 0 when not counting, else 5, 6, 7, 8. */
  count: 0 | 5 | 6 | 7 | 8;
  /** Speeds and end modes selectable for the active cassette. */
  speeds: TapeSpeed[];
  endModes: EndMode[];
  objective: ObjectiveSnap & { text: string };
  /** Latest resolved outcome (set once a take has been reviewed). */
  outcome: Outcome | null;
  /** Which decision actions are currently offered. */
  actions: SessionAction[];
  /** Upcoming enemy attack beats for the 'beatSight' ability (empty otherwise). */
  threatBeats: number[];
  /** Contextual hint line, if any. */
  hint: string | null;
}

export type SessionAction =
  | 'start' // leave briefing
  | 'speedUp'
  | 'speedDown'
  | 'cycleEndMode'
  | 'record' // begin count-in
  | 'skip' // skip review playback
  | 'endAttempt' // end a failing playback early (REC-08)
  | 'retryTake' // discard the current take, keep committed tapes (REC-04)
  | 'commit' // commit the take and move to the next cassette
  | 'resetAll' // wipe every cassette (REC-05)
  | 'continue' // results → campaign
  | 'quit';

// ───────────────────────────── campaign / save ─────────────────────────────

export interface SaveData {
  version: 1;
  /** Ids of cleared levels. */
  cleared: string[];
  /** Owned gear ids (generous inventory: never discarded; GEAR-04). */
  inventory: string[];
  loadout: Loadout;
  settings: {
    master: number;
    music: number;
    sfx: number;
    /** Extra audio→visual delay in ms (e.g. Bluetooth). */
    avOffsetMs: number;
    screenShake: boolean;
    /** Colour-blind friendly cassette patterns. */
    patterns: boolean;
  };
}

/** Cassette identity colours, shared by the HUD, the world and the music UI (UI-02). */
export const TAPE_COLORS: readonly string[] = ['#ff4d6d', '#ffd23f', '#3ec5ff', '#7dff6b'];
export const TAPE_NAMES: readonly string[] = ['A', 'B', 'C', 'D'];
