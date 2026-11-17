/**
 * Export golden fixtures that prove the Godot port preserves the prototype's rules
 * (docs/GODOT-PORT.md "Tests", tests/goldens/README.md).
 *
 *   cd prototype && npx vite-node scripts/export-goldens.ts            # export + stability check
 *   cd prototype && npx vite-node scripts/export-goldens.ts -- --fast  # export only (no stability check)
 *   cd prototype && npx vite-node scripts/export-goldens.ts -- --jitter 1e-6      # check at another scale
 *   cd prototype && npx vite-node scripts/export-goldens.ts -- --diagnose <name>   # where a jittered run departs
 *
 * Every scenario runs through the prototype's real simulation (src/core) and is written to
 * tests/goldens/<name>.json with everything needed to replay it without this script: the full
 * LevelDef, the resolved loadout (plus catalogue gear ids where the loadout came from
 * data/gear.json), the takes in order (per-local-tick PlayerInput lists for recorded takes, or a
 * serialised tape for trajectory takes), the boss memory each stage used, and the expected results
 * (outcome, the full ordered event list and snapshots sampled every 60 substeps plus the final one).
 * tests/goldens/index.json lists the scenarios. The format is documented field by field in
 * tests/goldens/README.md.
 *
 * Scenarios are taken from the prototype's own suites (tests/core/**, tests/game/**) and kept short
 * so floating-point differences between JavaScript and GDScript cannot accumulate. The stability
 * check re-runs every scenario with all level coordinates and tape samples shifted by ±JITTER tiles
 * (the same recorded inputs are replayed) and fails the export if any event's (sub, type, tape, id,
 * detail) or the outcome changes, or if any sampled position moves by more than the port's
 * tolerance: a scenario that passes is not balanced on a knife-edge at that scale.
 *
 * Output is deterministic: two runs produce byte-identical files.
 */
import { mkdirSync, readdirSync, unlinkSync, writeFileSync } from 'node:fs';
import { dirname, resolve as resolvePath } from 'node:path';
import { fileURLToPath } from 'node:url';
import { BASE_LOADOUT, resolveLoadout, SANDBOX } from '../src/content/index';
import { buildBossMemory, createSim, resolveEncounter } from '../src/core/index';
import { serializeTape } from '../src/core/tape';
import { TUTORIAL_WALL_THRESHOLD } from '../src/core/tuning';
import { TRAP_EVENT } from '../src/core/traps';
import type {
  ActorSnap,
  BossMemory,
  EndMode,
  EnemyDef,
  EnemySnap,
  EntityDef,
  FrameSnapshot,
  LevelDef,
  Loadout,
  MapRows,
  Outcome,
  PlayerInput,
  RangedWeaponDef,
  ResolvedLoadout,
  SimEvent,
  Tape,
  TapeIndex,
  TapeSpeed,
} from '../src/core/types';
import { makeLevel, OPEN_ROOM } from '../tests/helpers/levels';
import { baseLoadout, type LoadoutPatch } from '../tests/helpers/loadout';
import { pathTape, recordTake, resolve, script, type InputScript } from '../tests/helpers/script';
import { planTake, type PlanStep, type ReflexOptions } from '../tests/game/plans';

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolvePath(here, '..', '..');
const outDir = resolvePath(repoRoot, 'tests', 'goldens');

/** Golden file format version (tests/goldens/README.md). */
const FORMAT = 1;
/** Snapshots are sampled at every substep that is a multiple of this, plus the final one. */
const SAMPLE_SUBS = 60;
/** Values that come out of float maths are rounded to this many decimals in the files. */
const DECIMALS = 4;
/** Coordinate shift used by the stability check (tiles; `--jitter <v>` overrides). Above float32 rounding at map scale. */
const JITTER = (() => {
  const i = process.argv.indexOf('--jitter');
  const v = i >= 0 ? Number(process.argv[i + 1]) : 1e-5;
  if (!(v > 0)) throw new Error('--jitter needs a positive number');
  return v;
})();
/** Largest position drift the stability check accepts (the port's comparison tolerance). */
const POS_TOLERANCE = 1e-3;

// ───────────────────────────── scenario model ─────────────────────────────

type InputSource = { script: InputScript } | { controller: (tick: number, snap: FrameSnapshot, self: ActorSnap) => PlayerInput };

type TakeSpec =
  | { source: 'tape'; tape: Tape }
  | ({ source: 'inputs'; index: TapeIndex; speed: TapeSpeed; endMode: EndMode; ticks?: number } & InputSource);

interface Spec {
  name: string;
  description: string;
  /** Requirement ids, scenario letters and prototype test names this golden reproduces. */
  covers: string[];
  level: LevelDef;
  loadout: ResolvedLoadout;
  /** Set when the loadout was resolved from catalogue gear ids (data/gear.json). */
  gear?: Loadout;
  takes: TakeSpec[];
  /** Cassettes whose tapes build the boss memory (committed tapes), when the scenario uses one. */
  bossMemoryFrom?: TapeIndex[];
  /**
   * What the scenario must show (the prototype test's own assertions, restated). Several scenarios
   * are detuned from their test (odd speeds, off-centre positions) to stay off knife-edges; the
   * check proves each still demonstrates its rule. The export fails if a check fails.
   */
  check?: (c: Checker) => void;
}

/** Assertions over a base run, used by Spec.check. */
class Checker {
  readonly failures: string[] = [];
  constructor(readonly run: RunResult) {}
  get events(): SimEvent[] {
    return this.run.events;
  }
  get outcome(): Outcome {
    return this.run.outcome;
  }
  /** Resolution events of a type, optionally filtered by tape / id / detail. */
  ev(type: SimEvent['type'], f: { tape?: number; id?: string; detail?: string } = {}, list: SimEvent[] = this.run.events): SimEvent[] {
    return list.filter((e) => e.type === type && (f.tape === undefined || e.tape === f.tape) && (f.id === undefined || e.id === f.id) && (f.detail === undefined || e.detail === f.detail));
  }
  /** Events of the recording of the k-th recorded take. */
  recEvents(k = 0): SimEvent[] {
    return this.run.recordings[k].events;
  }
  last(): FrameSnapshot {
    return this.run.snapshots[this.run.snapshots.length - 1];
  }
  need(cond: boolean, msg: string): void {
    if (!cond) this.failures.push(msg);
  }
  count(type: SimEvent['type'], n: number, f: { tape?: number; id?: string; detail?: string } = {}, list?: SimEvent[]): void {
    const got = this.ev(type, f, list).length;
    this.need(got === n, `expected ${n} '${type}' ${JSON.stringify(f)}, got ${got}`);
  }
  win(w: boolean): void {
    this.need(this.run.outcome.win === w, `expected win ${w}, got ${this.run.outcome.win}`);
  }
}

// ───────────────────────────── small helpers ─────────────────────────────

const SLEEP = { const: false } as const;
const SPB = 120; // substeps per beat at bpm 120

function grunt(id: string, x: number, y: number, hp?: number): EntityDef {
  const g: EntityDef = { kind: 'enemy', id, type: 'grunt', x, y, wakeWhen: SLEEP };
  if (hp !== undefined) g.hp = hp;
  return g;
}

function turretAt(x: number, y: number, extra: Partial<EntityDef> = {}): EntityDef {
  return { kind: 'enemy', id: 't1', type: 'turret', x, y, facing: Math.PI, ...extra } as EntityDef;
}

function still(index: TapeIndex, x: number, y: number, ticks: number, speed: TapeSpeed = 1, events: { tick: number; kind: 'light' | 'heavy' | 'dodge' | 'ranged' | 'interact' | 'ability'; dir?: number }[] = []): Tape {
  return pathTape({ index, speed, ticks, path: [{ tick: 0, x, y }], events });
}

const T = (tape: Tape): TakeSpec => ({ source: 'tape', tape });

const rec = (index: TapeIndex, speed: TapeSpeed, endMode: EndMode, s: InputScript, ticks?: number): TakeSpec => ({
  source: 'inputs',
  index,
  speed,
  endMode,
  script: s,
  ticks,
});

/** A closed-loop bot take (tests/game/plans.ts). Its inputs are recorded and written open-loop. */
function botTake(index: TapeIndex, speed: TapeSpeed, endMode: EndMode, steps: PlanStep[], reflex: ReflexOptions = {}): TakeSpec {
  const plan = planTake(speed, endMode, steps, reflex);
  return {
    source: 'inputs',
    index,
    speed,
    endMode,
    controller: (tick, snap, self) => plan.inputs(tick, { tick, index, snap, self }),
  };
}

function catalogue(patch: Partial<Loadout>): { loadout: ResolvedLoadout; gear: Loadout } {
  const loadout = resolveLoadout({ ...BASE_LOADOUT, ...patch });
  return { loadout, gear: { ...loadout.loadout } };
}

const withMap = (rowFn: (row: string, r: number) => string): MapRows => OPEN_ROOM.map(rowFn);
const inner = (r: number) => r !== 0 && r !== OPEN_ROOM.length - 1;
/** OPEN_ROOM with a wall column at x = 5 and a doorway at (5, 5). */
const DOORWAY_MAP: MapRows = withMap((row, r) => (inner(r) ? row.slice(0, 5) + (r === 5 ? '.' : '#') + row.slice(6) : row));

// ───────────────────────────── scenarios ─────────────────────────────

const SCENARIOS: (() => Spec | Spec[])[] = [];
const add = (f: () => Spec | Spec[]) => SCENARIOS.push(f);

// ── clock: every tape speed records the same local allowance (TEST-01, TIME-02/03) ──
for (const speed of [0.5, 1, 2, 4] as TapeSpeed[]) {
  add(() => ({
    name: `clock-record-${String(speed).replace('.', '_')}x`,
    description: `A ${speed}x take runs east for its whole 1-bar allowance (120 local ticks) and is then resolved; the world advances ${4 / speed} substeps per local tick.`,
    covers: ['TEST-01', 'TIME-02', 'TIME-03', 'kernel clock'],
    level: makeLevel({ speeds: [0.5, 1, 2, 4], bars: 1 }),
    loadout: baseLoadout(),
    takes: [rec(0, speed, 'stop', script().run(0, 1000, 1, 0))],
    check: (c) => {
      const r = c.run.recordings[0];
      c.need(r.tape.ticks === 120, `allowance ${r.tape.ticks}`);
      c.need(r.snapshots[r.snapshots.length - 1].sub === 120 * (4 / speed), 'world advanced 4/s substeps per tick');
    },
  }));
}

add(() => ({
  name: 'clock-plate-2x-record-replay',
  description: 'A 2x take lands on a plate; the plate event happens at the same master substep in recording and in replay.',
  covers: ['TEST-02'],
  level: makeLevel({
    speeds: [1, 2],
    bars: 1,
    start: { x: 2.5, y: 5.5 },
    entities: [{ kind: 'plate', id: 'p1', c: 7, r: 5 }],
    objective: { type: 'signal', when: { sig: 'p1' }, text: 'Stand on the plate' },
  }),
  loadout: baseLoadout(),
  takes: [rec(0, 2, 'stop', script().run(0, 1000, 1, 0))],
  check: (c) => {
    const key = (l: SimEvent[]) => JSON.stringify(c.ev('plate', {}, l).map((e) => [e.sub, e.detail]));
    c.need(c.ev('plate').length > 0 && key(c.events) === key(c.recEvents()), 'plate at the same substep in recording and replay');
    c.need(c.outcome.objectiveComplete, 'objective complete');
  },
}));

const busyLevel = (): LevelDef =>
  makeLevel({
    speeds: [0.5, 1, 2],
    bars: 2,
    start: { x: 2.5, y: 5.5 },
    entities: [
      { kind: 'enemy', id: 'g1', type: 'grunt', x: 9.5, y: 2.5 },
      { kind: 'enemy', id: 't1', type: 'turret', x: 10.5, y: 8.5, facing: Math.PI },
      { kind: 'switch', id: 'sw', x: 4.5, y: 2.5 },
      { kind: 'door', id: 'd1', cells: [{ c: 7, r: 5 }], openWhen: { sig: 'sw' } },
      { kind: 'plate', id: 'p1', c: 5, r: 7 },
    ],
  });

const busyScript = () =>
  script()
    .run(0, 25, 0.6, -1)
    .press(26, 'interact')
    .run(30, 70, 1, 0.3)
    .press(72, 'light', 0)
    .run(80, 110, -0.4, 1)
    .press(112, 'dodge')
    .run(120, 160, 1, 0)
    .press(165, 'heavy', -0.5)
    .run(200, 240, 0, -1);

add(() => ({
  name: 'record-busy-death',
  description: 'Record-then-resolve fidelity: a busy 1x take (switch, door, plate, grunt, turret) dies part-way; the replay reproduces positions, kills and the death.',
  covers: ['kernel determinism', 'record → resolve reproduction', 'GHOST-01'],
  level: busyLevel(),
  loadout: baseLoadout(),
  takes: [rec(0, 1, 'stop', busyScript())],
  check: (c) => {
    c.count('selfDeath', 1, {}, c.recEvents());
    const death = c.ev('selfDeath', {}, c.recEvents())[0]?.sub ?? -1;
    const key = (l: SimEvent[]) => JSON.stringify(l.filter((e) => e.sub <= death && e.type !== 'step').map((e) => [e.sub, e.type, e.id, e.tape]));
    c.need(key(c.events) === key(c.recEvents()), 'replay reproduces every event up to the death');
  },
}));

add(() => ({
  name: 'record-two-takes-busy',
  description: 'Take A (2x, busy script) is recorded, then take B (1x, reverse) is recorded live against A; the combined run is resolved.',
  covers: ['TEST-03', 'TEST-04', 'kernel determinism'],
  level: busyLevel(),
  loadout: baseLoadout(),
  takes: [rec(0, 2, 'stop', busyScript()), rec(1, 1, 'reverse', busyScript())],
  check: (c) => {
    // TEST-04: while B records, A plays back exactly as its own recording placed it.
    const a = c.run.recordings[0].snapshots;
    const b = c.run.recordings[1].snapshots;
    const bySub = new Map(a.map((f) => [f.sub, f.actors[0]]));
    const shared = b.filter((f) => bySub.has(f.sub) && f.sub <= 480);
    c.need(shared.length > 5 && shared.every((f) => f.actors[0].x === bySub.get(f.sub)!.x && f.actors[0].y === bySub.get(f.sub)!.y), 'A replays its recorded path during B’s take');
    c.need(b[0].actors.map((x) => `${x.tape}${x.live}`).join() === '0false,1true', 'A playing back, B live');
  },
}));

add(() => {
  const level = makeLevel({
    speeds: [1],
    bars: 2,
    start: { x: 2.5, y: 5.5 },
    entities: [
      { kind: 'enemy', id: 'g1', type: 'grunt', x: 6.5, y: 5.5 },
      { kind: 'switch', id: 'sw', x: 3.5, y: 4.5 },
      { kind: 'door', id: 'd1', cells: [{ c: 9, r: 5 }], openWhen: { sig: 'sw' } },
    ],
  });
  return {
    name: 'record-calm-kill-win',
    description: 'A surviving take waits for an awake grunt and kills it with a standing 1x light; recording and replay agree exactly and the run wins.',
    covers: ['kernel determinism', 'AI-01', 'win with one survivor'],
    level,
    loadout: baseLoadout(),
    takes: [rec(0, 1, 'stop', script().press(2, 'interact').aim(0, 400, 0).press(80, 'light', 0).run(120, 160, 1, 0))],
    check: (c) => {
      c.count('kill', 1, {}, c.recEvents());
      c.count('kill', 1);
      c.count('selfDeath', 0);
      c.win(true);
    },
  };
});

add(() => {
  // dead:<enemy id> (data/levels/README.md "Signal expressions"): a door opens on a grunt's death.
  const level = makeLevel({
    speeds: [1],
    bars: 1,
    start: { x: 5.0, y: 5.5 },
    entities: [grunt('g1', 6.0, 5.5, 1), { kind: 'door', id: 'gate', cells: [{ c: 9, r: 2 }], openWhen: { sig: 'dead:g1' } }],
  });
  return {
    name: 'mech-dead-signal-opens-door',
    description: 'A standing 1x light kills a sleeping one-hit grunt; the door wired to dead:g1 starts opening on the next mechanisms update.',
    covers: ['dead:<enemy> signal', 'LEVEL signal expressions'],
    level,
    loadout: baseLoadout(),
    takes: [rec(0, 1, 'stop', script().aim(0, 240, 0).press(20, 'light', 0))],
    check: (c) => {
      c.count('kill', 1, { id: 'g1' });
      c.count('door', 1, { id: 'gate', detail: 'open' });
    },
  };
});

add(() => ({
  name: 'clock-empty-run',
  description: 'No tapes at all (after a reset): the encounter runs to the horizon with no selves and fails with no survivor.',
  covers: ['TEST-06'],
  level: busyLevel(),
  loadout: baseLoadout(),
  takes: [],
  check: (c) => {
    c.need(c.run.snapshots.every((f) => f.actors.length === 0), 'no selves at all');
    c.need(c.outcome.survivors.length === 0 && !c.outcome.win, 'no survivor, no win');
  },
}));

// ── end behaviour (TEST-25, TEST-26, PLAY-05/06, Scenario G) ──
const modesLevel = (): LevelDef =>
  makeLevel({
    speeds: [0.5, 1, 2],
    bars: 1,
    start: { x: 2.5, y: 5.5 },
    entities: [
      { kind: 'switch', id: 'sw', x: 5.5, y: 1.5 },
      { kind: 'enemy', id: 't1', type: 'turret', x: 6.8, y: 2.5, hp: 4, beat: { every: 1000, offset: 999 } },
    ],
  });

function shortTape(endMode: EndMode): Tape {
  return pathTape({
    index: 0,
    speed: 2,
    endMode,
    ticks: 120,
    path: [
      { tick: 0, x: 2.5, y: 5.5 },
      { tick: 60, x: 5.5, y: 2.5 },
    ],
    events: [
      { tick: 70, kind: 'interact' },
      { tick: 80, kind: 'light', dir: 0 },
    ],
  });
}

for (const mode of ['stop', 'repeat', 'reverse'] as EndMode[]) {
  add(() => ({
    name: `tapemode-${mode}`,
    description: `A 2x '${mode}' tape (1 bar, horizon 2 bars) walks to a switch and a turret, toggles and swings; end behaviour applies against a world that keeps going.`,
    covers: mode === 'stop' ? ['PLAY-05', 'OPEN-05'] : mode === 'repeat' ? ['TEST-25', 'Scenario G'] : ['TEST-26', 'PLAY-06'],
    level: modesLevel(),
    loadout: baseLoadout(),
    takes: [T(shortTape(mode))],
    check: (c) => {
      const toggles = c.ev('interact', { id: 'sw' }).map((e) => e.detail).join(',');
      if (mode === 'stop') {
        c.count('tapeEnd', 1, { tape: 0 });
        c.need(toggles === 'on', toggles);
      } else {
        c.count(mode === 'repeat' ? 'tapeWrap' : 'tapeTurn', 3, { tape: 0 });
        c.need(toggles === 'on,off,on,off', toggles);
        c.count('hit', 2, { id: 't1' });
        c.count('kill', 1, { id: 't1' });
      }
    },
  }));
}

add(() => {
  const level = makeLevel({
    speeds: [0.5, 1, 2, 4],
    bars: 1,
    start: { x: 2.5, y: 5.5 },
    entities: [
      { kind: 'enemy', id: 't1', type: 'turret', x: 8.5, y: 5.5, hp: 12, beat: { every: 1000, offset: 999 } },
      { kind: 'switch', id: 'sw', x: 4.5, y: 8.5 },
      { kind: 'door', id: 'd1', cells: [{ c: 10, r: 2 }], openWhen: { sig: 'sw' } },
    ],
  });
  const mk = (index: TapeIndex, speed: TapeSpeed, endMode: EndMode, y: number, events: { tick: number; kind: 'light' | 'interact'; dir?: number }[]) =>
    pathTape({ index, speed, endMode, ticks: 120, path: [{ tick: 0, x: 2.5, y: 5.5 }, { tick: 40, x: 7.4, y }], events });
  return {
    name: 'tapemode-mixed-four',
    description: 'Four tapes at once, one per speed (0.5x stop, 1x repeat, 2x reverse, 4x repeat), striking one tough turret and toggling a switch; traversals, wraps and turns interleave.',
    covers: ['TIME-03', 'PLAY-05', 'PLAY-06', 'every speed and end mode'],
    level,
    loadout: baseLoadout(),
    takes: [
      mk(0, 0.5, 'stop', 5.5, [{ tick: 60, kind: 'light', dir: 0 }]),
      mk(1, 1, 'repeat', 4.9, [{ tick: 50, kind: 'light', dir: 0.4 }]),
      pathTape({ index: 2, speed: 2, endMode: 'reverse', ticks: 120, path: [{ tick: 0, x: 2.5, y: 5.5 }, { tick: 30, x: 4.5, y: 7.8 }], events: [{ tick: 40, kind: 'interact' }] }),
      mk(3, 4, 'repeat', 6.1, [{ tick: 70, kind: 'light', dir: -0.4 }]),
    ].map(T),
    check: (c) => {
      c.count('tapeWrap', 7, { tape: 3 });
      c.count('tapeWrap', 1, { tape: 1 });
      c.count('tapeTurn', 3, { tape: 2 });
      c.need(c.ev('interact', { id: 'sw' }).map((e) => e.detail).join() === 'on,off,on,off', 'reverse pass toggles the switch back');
      c.count('kill', 1, { id: 't1' });
    },
  };
});

add(() => {
  const level = makeLevel({
    speeds: [0.5, 1, 2, 4],
    bars: 1,
    start: { x: 2.5, y: 5.5 },
    entities: [{ kind: 'switch', id: 'sw', x: 4.5, y: 5.5 }, { kind: 'laser', id: 'beam', from: { x: 8.5, y: 1.5 }, to: { x: 8.5, y: 8.5 }, onWhen: { sig: 'sw' } }],
    objective: { type: 'signal', when: { sig: 'sw' }, text: 'Flip it' },
  });
  return {
    name: 'tapemode-record-4x-reverse',
    description: 'A 4x reverse take is recorded from inputs (one world substep per local tick), toggling a switch; the resolution ping-pongs it eight times over the horizon.',
    covers: ['TIME-03', 'PLAY-06', 'record at 4x'],
    level,
    loadout: baseLoadout(),
    takes: [rec(0, 4, 'reverse', script().run(0, 18, 1, 0).press(30, 'interact').run(50, 80, 0, 1).run(80, 100, 1, -1))],
    check: (c) => {
      const r = c.run.recordings[0];
      c.need(r.snapshots[r.snapshots.length - 1].sub === 120, 'a 4x take advances one substep per local tick');
      c.count('tapeTurn', 7, { tape: 0 });
      c.count('interact', 8, { id: 'sw' });
    },
  };
});

// ── ghosts and survival (TEST-07..12, TEST-23/24, Scenarios C and D) ──
const rescueRoom = (): LevelDef =>
  makeLevel({
    speeds: [1, 2],
    bars: 4,
    map: ['############', '#.....#....#', '#.....#....#', '#..........#', '#.....#....#', '############'],
    start: { x: 3.0, y: 3.5 },
    entities: [
      { kind: 'enemy', id: 't1', type: 'turret', x: 1.5, y: 4.5 },
      { kind: 'enemy', id: 'g1', type: 'grunt', x: 3.0, y: 2.55, wakeWhen: { const: false } },
      { kind: 'switch', id: 'lever', x: 2.5, y: 1.5 },
      { kind: 'door', id: 'gate', cells: [{ c: 6, r: 3 }], openWhen: { sig: 'lever' } },
    ],
    objective: { type: 'eliminate', targets: ['g1'], text: 'Destroy the grunt' },
  });

const tapeAScript = () =>
  script()
    .aim(0, 480, -Math.PI / 2)
    .press(100, 'light', -Math.PI / 2)
    .run(130, 150, -0.3, -1)
    .press(160, 'interact')
    .run(175, 200, 0.55, 1)
    .run(200, 300, 1, 0);

add(() => ({
  name: 'ghost-scenario-c',
  description: 'Scenario C: the take is shot early, keeps going as a recording ghost (strikes the grunt, flips the lever, walks through the door); replayed, it dies again and none of that happens.',
  covers: ['Scenario C', 'TEST-07', 'TEST-09', 'TEST-10', 'GHOST-01..05'],
  level: rescueRoom(),
  loadout: baseLoadout(),
  takes: [rec(0, 1, 'stop', tapeAScript())],
  check: (c) => {
    c.count('selfDeath', 1, {}, c.recEvents());
    c.count('kill', 1, { id: 'g1' }, c.recEvents());
    c.count('selfDeath', 1);
    c.count('kill', 0);
    c.count('interact', 0);
    c.win(false);
  },
}));

add(() => {
  const level = rescueRoom();
  level.entities = level.entities.map((e) => (e.kind === 'door' ? { ...e, openWhen: { const: false } } : e));
  return {
    name: 'ghost-recghost-blocked-by-door',
    description: 'The recording ghost is still blocked by a closed door (the door here never opens).',
    covers: ['TEST-08', 'GHOST-02'],
    level,
    loadout: baseLoadout(),
    takes: [rec(0, 1, 'stop', tapeAScript())],
    check: (c) => {
      const r = c.run.recordings[0];
      c.count('selfDeath', 1, {}, r.events);
      c.need(r.snapshots.every((f) => f.actors[0].x < 6 - 0.29), 'never passes the closed door');
      c.need(r.snapshots[r.snapshots.length - 1].actors[0].life === 'recGhost', 'ends as a recording ghost');
    },
  };
});

add(() => ({
  name: 'ghost-rescue',
  description: 'Rescue: take B (2x) destroys the turret before its first shot, so take A survives and its later strike and lever become effective; both survive and win.',
  covers: ['TEST-11', 'rescue', 'Scenario C'],
  level: rescueRoom(),
  loadout: baseLoadout(),
  takes: [rec(0, 1, 'stop', tapeAScript()), rec(1, 2, 'stop', script().run(0, 9, -1.5, 1).press(9, 'light', Math.atan2(1, -1.5)).run(30, 60, 1, -1))],
  check: (c) => {
    c.count('kill', 1, { id: 't1' });
    c.count('selfDeath', 0);
    c.count('kill', 1, { id: 'g1', tape: 0 });
    c.win(true);
    c.need(JSON.stringify(c.outcome.survivors) === '[0,1]', 'both survive');
  },
}));

const scenarioD = (): LevelDef =>
  makeLevel({
    speeds: [1],
    bars: 4,
    map: ['##############', '#............#', '#............#', '#.......######', '#............#', '#.......######', '#............#', '##############'],
    start: { x: 2.5, y: 4.5 },
    entities: [
      { kind: 'switch', id: 'gate', x: 2.5, y: 2.5 },
      { kind: 'switch', id: 'lamp', x: 6.5, y: 1.5 },
      { kind: 'door', id: 'door', cells: [{ c: 8, r: 4 }], openWhen: { sig: 'gate' } },
      { kind: 'enemy', id: 't1', type: 'turret', x: 12.5, y: 4.5, facing: Math.PI },
    ],
    objective: { type: 'signal', when: { sig: 'gate' }, text: 'Open the gate' },
  });

add(() => {
  const tapeA = pathTape({
    index: 0,
    speed: 1,
    ticks: 480,
    path: [
      { tick: 0, x: 2.5, y: 4.5 },
      { tick: 60, x: 6.0, y: 4.5 },
      { tick: 440, x: 6.0, y: 4.5 },
      { tick: 460, x: 6.3, y: 2.3 },
    ],
    events: [{ tick: 470, kind: 'interact' }],
  });
  const tapeB = pathTape({ index: 1, speed: 1, ticks: 480, path: [{ tick: 0, x: 2.5, y: 4.5 }, { tick: 30, x: 2.5, y: 3.0 }], events: [{ tick: 300, kind: 'interact' }] });
  return [
    {
      name: 'ghost-scenario-d-alone',
      description: 'Scenario D control: tape A alone survives the corridor and lights the lamp.',
      covers: ['Scenario D'],
      level: scenarioD(),
      loadout: baseLoadout(),
      takes: [T(tapeA)],
      check: (c) => {
        c.count('selfDeath', 0);
        c.need(c.ev('interact', { id: 'lamp' }).map((e) => e.detail).join() === 'on', 'lamp lit');
      },
    },
    {
      name: 'ghost-scenario-d',
      description: 'Scenario D: tape B opens the door late, exposing A to the turret; A dies at a new time, keeps moving as a ghost, its lamp switch does not count, and B wins alone.',
      covers: ['Scenario D', 'TEST-12', 'GHOST-05', 'win with one survivor'],
      level: scenarioD(),
      loadout: baseLoadout(),
      takes: [T(tapeA), T(tapeB)],
      check: (c) => {
        const d = c.ev('selfDeath', { tape: 0 });
        c.need(d.length === 1 && d[0].sub > 300 * 4 && d[0].sub < 440 * 4, 'A dies once, after B opens the door, while waiting');
        c.count('interact', 0, { id: 'lamp' });
        c.count('interact', 1, { id: 'gate', tape: 1 });
        c.need(JSON.stringify(c.outcome.survivors) === '[1]', 'B survives alone');
        c.win(true);
      },
    },
  ];
});

const survivalRoom = (): LevelDef =>
  makeLevel({
    speeds: [1],
    bars: 2,
    start: { x: 2.5, y: 5.5 },
    entities: [
      { kind: 'laser', id: 'beam', from: { x: 1.5, y: 2.5 }, to: { x: 10.5, y: 2.5 }, onWhen: { const: true } },
      { kind: 'enemy', id: 'g1', type: 'grunt', x: 8.0, y: 7.5, wakeWhen: { const: false } },
    ],
    objective: { type: 'eliminate', text: 'Destroy the grunt' },
  });

// Detuned from the test (ticks 41 / 93, 61 / 163, x + 0.03, y 2.47): round waypoints put the
// accumulated footstep stride exactly on its 0.85-tile threshold, a knife-edge.
function walkIntoLaser(index: TapeIndex, x: number): Tape {
  return pathTape({ index, speed: 1, ticks: 240, path: [{ tick: 0, x: 2.5, y: 5.5 }, { tick: 41, x: x + 0.03, y: 5.5 }, { tick: 93, x: x + 0.03, y: 2.47 }] });
}

function killGrunt(index: TapeIndex, thenDie: boolean): Tape {
  const path = [
    { tick: 0, x: 2.5, y: 5.5 },
    { tick: 61, x: 7.0, y: 7.5 },
  ];
  if (thenDie) path.push({ tick: 100, x: 7.0, y: 7.5 }, { tick: 163, x: 7.0, y: 2.5 });
  return pathTape({ index, speed: 1, ticks: 240, path, events: [{ tick: 70, kind: 'light', dir: 0 }] });
}

add(() => ({
  name: 'survivors-one-wins',
  description: 'Three selves burn in a laser; the fourth kills the grunt and survives: the attempt is won with one survivor.',
  covers: ['TEST-23', 'REC-07', 'win with one survivor'],
  level: survivalRoom(),
  loadout: baseLoadout(),
  takes: [T(walkIntoLaser(0, 3.5)), T(walkIntoLaser(1, 5.5)), T(walkIntoLaser(2, 9.5)), T(killGrunt(3, false))],
  check: (c) => {
    c.need(JSON.stringify(c.ev('selfDeath').map((e) => e.tape)) === '[0,1,2]', 'three laser deaths');
    c.need(JSON.stringify(c.outcome.survivors) === '[3]', 'one survivor');
    c.win(true);
  },
}));

add(() => ({
  name: 'survivors-none-fails',
  description: 'The objective completes but every self dies afterwards: not a win (reason noSurvivor).',
  covers: ['TEST-24', 'REC-07', 'fail with none'],
  level: survivalRoom(),
  loadout: baseLoadout(),
  takes: [T(walkIntoLaser(0, 3.5)), T(killGrunt(1, true))],
  check: (c) => {
    c.need(c.outcome.objectiveComplete && !c.outcome.win && c.outcome.reason === 'noSurvivor', 'objective done, no survivor');
  },
}));

add(() => {
  const level = makeLevel({
    id: 'laser-hall',
    speeds: [1],
    endModes: ['stop'],
    bars: 2,
    maxTapes: 2,
    start: { x: 2.5, y: 5.5 },
    entities: [
      { kind: 'laser', id: 'beam', from: { x: 5.5, y: 1.5 }, to: { x: 5.5, y: 8.5 }, onWhen: { const: true } },
      { kind: 'enemy', id: 'g1', type: 'grunt', x: 8.5, y: 5.5, wakeWhen: { const: false } },
    ],
    objective: { type: 'eliminate', targets: ['g1'], text: 'Destroy the grunt' },
  });
  return {
    name: 'ghost-final-tape-edge',
    description: 'Final-tape edge case: take B dies in a laser, then as a recording ghost kills the grunt (the provisional run latches the objective); the authoritative resolve does not.',
    covers: ['OPEN-07', 'REC-06', 'GHOST-03'],
    level,
    loadout: baseLoadout(),
    takes: [
      rec(0, 1, 'stop', script()),
      botTake(1, 1, 'stop', [
        { kind: 'goto', x: 7.6, y: 5.5 },
        { kind: 'hold', x: 7.6, y: 5.5 },
      ]),
    ],
    check: (c) => {
      const live = c.recEvents(1);
      c.count('selfDeath', 1, { tape: 1 }, live);
      c.count('kill', 1, { id: 'g1' }, live);
      c.count('objective', 1, {}, live);
      c.count('kill', 0);
      c.need(!c.outcome.win && !c.outcome.objectiveComplete && JSON.stringify(c.outcome.survivors) === '[0]', 'authoritative run fails');
    },
  };
});

// ── desync and the recovery spark (TEST-13..17, Scenarios I and J) ──
function corridor(detour: boolean): LevelDef {
  return makeLevel({
    speeds: [1],
    bars: 4,
    map: ['##############', detour ? '#............#' : '##############', detour ? '#.##########.#' : '#.############', '#............#', '##############'],
    start: { x: 1.5, y: 3.5 },
    entities: [
      { kind: 'switch', id: 'sw', x: 1.5, y: 2.5 },
      { kind: 'door', id: 'd1', cells: [{ c: 7, r: 3 }], openWhen: { not: { sig: 'sw' } } },
      { kind: 'exit', id: 'exit', c: 12, r: 3, w: 1, h: 1 },
    ],
    objective: { type: 'reach', text: 'Reach the end' },
  });
}

// Detuned from the test (arrives on tick 223, not 220): 3 tiles/s is 1/80 tile per substep, which
// divides the footstep stride exactly and lines the spark up on exact ties.
const runner = (speed: TapeSpeed = 1, endMode: EndMode = 'stop'): Tape =>
  pathTape({ index: 0, speed, endMode, ticks: 480, path: [{ tick: 0, x: 1.5, y: 3.5 }, { tick: 223, x: 12.5, y: 3.5 }] });

function switcher(closeAt: number, reopenAt?: number): Tape {
  const events: { tick: number; kind: 'interact' }[] = [{ tick: closeAt, kind: 'interact' }];
  if (reopenAt !== undefined) events.push({ tick: reopenAt, kind: 'interact' });
  return pathTape({ index: 1, speed: 1, ticks: 480, path: [{ tick: 0, x: 1.5, y: 3.5 }], events });
}

add(() => [
  {
    name: 'desync-scenario-i-detour',
    description: 'Scenario I: a door closes across the runner, which desyncs; its spark takes the open detour at finite speed and resyncs on catch-up; the runner then holds the exit.',
    covers: ['Scenario I', 'TEST-13', 'TEST-14', 'DESYNC-01..05', 'detour recovery'],
    level: corridor(true),
    loadout: baseLoadout(),
    takes: [T(runner()), T(switcher(5))],
    check: (c) => {
      const d = c.ev('desync', { tape: 0 });
      const r = c.ev('resync', { tape: 0 });
      c.need(d.length === 1 && d[0].detail === 'blocked by door d1', 'desync at the door');
      c.need(r.length === 1 && (r[0].sub - d[0].sub) / 240 > 18 / 7.5, 'resync only after the ~20-tile detour');
      c.need(c.run.snapshots.some((f) => f.actors[0].spark !== undefined && f.actors[0].spark.y < 2), 'spark took the detour row');
      c.win(true);
    },
  },
  {
    name: 'desync-scenario-i-reopened',
    description: 'Scenario I: the switcher reopens the direct route at tick 150, so the spark catches up sooner than by the detour.',
    covers: ['Scenario I', 'reopened route', 'DESYNC-04'],
    level: corridor(true),
    loadout: baseLoadout(),
    takes: [T(runner()), T(switcher(5, 150))],
    check: (c) => {
      const detour = resolve(corridor(true), [runner(), switcher(5)]).events.find((e) => e.type === 'resync')!.sub;
      const r = c.ev('resync', { tape: 0 });
      c.need(r.length === 1 && r[0].sub < detour, 'reopened route resyncs sooner than the detour');
    },
  },
  {
    name: 'desync-no-route',
    description: 'With no route the spark never catches up; nothing teleports or kills it; the alive-but-desynced self is a survivor that cannot hold the exit.',
    covers: ['DESYNC-03', 'TEST-15'],
    level: corridor(false),
    loadout: baseLoadout(),
    takes: [T(runner()), T(switcher(5))],
    check: (c) => {
      c.count('desync', 1, { tape: 0 });
      c.count('resync', 0, { tape: 0 });
      const a = c.last().actors[0];
      c.need(!a.synced && a.life === 'alive' && a.spark!.x < 7, 'spark waits on its side of the door');
      c.need(c.outcome.survivors.includes(0) && !c.outcome.objectiveComplete, 'desynced survivor cannot hold the exit');
    },
  },
  {
    name: 'desync-route-reopened-by-other',
    description: 'Another tape reopens the blocked route at tick 300; the spark recovers and the run wins.',
    covers: ['TEST-15', 'Scenario J', 'reopened route'],
    level: corridor(false),
    loadout: baseLoadout(),
    takes: [T(runner()), T(switcher(5, 300))],
    check: (c) => {
      const open = c.ev('door', { id: 'd1', detail: 'open' });
      const r = c.ev('resync', { tape: 0 });
      c.need(open.length === 1 && r.length === 1 && r[0].sub > open[0].sub, 'resync after the reopen');
      c.win(true);
    },
  },
  {
    name: 'desync-repeat-cut-spark',
    description: 'A 2x repeat runner desyncs at the closed door; at the cut the projection teleports back to the start but the spark has to travel, then resyncs with the new traversal.',
    covers: ['DESYNC', 'What a tape is', 'repeat'],
    level: corridor(false),
    loadout: baseLoadout(),
    takes: [T(runner(2, 'repeat')), T(switcher(2))],
    check: (c) => {
      const cut = 480 * 2;
      c.need(c.ev('tapeWrap', { tape: 0 }).some((e) => e.sub + 1 === cut), 'wraps at the cut');
      const r = c.ev('resync', { tape: 0 });
      c.need(r.length > 0 && r[0].sub > cut, 'resyncs after the cut');
    },
  },
]);

add(() => {
  const level = makeLevel({
    speeds: [1],
    bars: 2,
    map: ['############', '#..........#', '#..........#', '#..........#', '#..........#', '#.....=....#', '#..........#', '#..........#', '#..........#', '############'],
    start: { x: 2.5, y: 5.5 },
    entities: [
      { kind: 'enemy', id: 't1', type: 'turret', x: 10.5, y: 5.5, facing: Math.PI },
      { kind: 'enemy', id: 'g1', type: 'grunt', x: 7.4, y: 6.3, wakeWhen: { const: false } },
    ],
    objective: { type: 'eliminate', targets: ['g1'], text: 'Destroy the grunt' },
  });
  const tapeA = pathTape({ index: 0, speed: 1, ticks: 240, path: [{ tick: 0, x: 2.5, y: 5.5 }, { tick: 40, x: 6.5, y: 5.5 }], events: [{ tick: 120, kind: 'light', dir: Math.atan2(0.8, 0.9) }] });
  const tapeC = still(2, 2.5, 5.5, 240);
  return {
    name: 'desync-harmless-invulnerable',
    description: 'A self desynced on a low barrier swings at a grunt for no damage; the turret ignores it and shoots the self standing behind it, straight through the projection.',
    covers: ['TEST-16', 'DESYNC-07', 'AI-07 targeting policy'],
    level,
    loadout: baseLoadout(),
    takes: [T(tapeA), T(tapeC)],
    check: (c) => {
      c.count('desync', 1, { tape: 0 });
      c.count('hit', 0);
      const shots = c.ev('enemyShot', { id: 't1' });
      c.need(shots.length > 0 && shots.every((s) => s.tape === 2), 'turret shoots only C');
      c.need(JSON.stringify(c.ev('selfDeath').map((e) => e.tape)) === '[2]', 'only C dies');
    },
  };
});

function turretLevel(detour: boolean): LevelDef {
  return makeLevel({
    speeds: [1],
    bars: 4,
    map: ['################', '#..............#', '#..............#', detour ? '#####.######...#' : '#####.##########', '#..............#', '#..............#', '################'],
    start: { x: 2.5, y: 1.5 },
    entities: [
      { kind: 'switch', id: 'sw', x: 1.5, y: 1.5 },
      { kind: 'door', id: 'd1', cells: [{ c: 5, r: 3 }], openWhen: { not: { sig: 'sw' } } },
      { kind: 'enemy', id: 't1', type: 'turret', x: 8.5, y: 5.0, facing: Math.PI, arc: Math.PI },
    ],
    objective: { type: 'eliminate', targets: ['t1'], text: 'Destroy the turret' },
  });
}

function crosser(strikeAt: number): Tape {
  return pathTape({
    index: 0,
    speed: 1,
    ticks: 480,
    // Detuned from the test (ticks 61 / 123 / 133 for 60 / 120 / 130, x 6.53 for 6.5) to keep the spark off exact ties.
    path: [
      { tick: 0, x: 2.5, y: 1.5 },
      { tick: 61, x: 5.5, y: 1.5 },
      { tick: 123, x: 5.5, y: 4.5 },
      { tick: 133, x: 6.53, y: 4.5 },
      { tick: 200, x: 6.53, y: 4.5 },
      { tick: 260, x: 9.6, y: 4.4 },
      { tick: 270, x: 9.6, y: 5.0 },
    ],
    events: [{ tick: strikeAt, kind: 'light', dir: Math.PI }],
  });
}

const doorman = (): Tape => still(1, 2.5, 1.5, 480, 1, [{ tick: 5, kind: 'interact' }]);

add(() => [
  {
    name: 'desync-scenario-j-control',
    description: 'Scenario J control: without desync the turret kills the crossing tape in its lane.',
    covers: ['Scenario J', 'TEST-17'],
    level: turretLevel(true),
    loadout: baseLoadout(),
    takes: [T(crosser(400))],
    check: (c) => {
      c.need(c.ev('selfDeath', { tape: 0 }).map((e) => e.detail).join() === 'shot by turret t1', 'shot in the lane');
      c.count('kill', 0);
    },
  },
  {
    name: 'desync-scenario-j',
    description: 'Scenario J: desync protects the crossing, the spark detours, the tape resyncs behind the turret and breaks it.',
    covers: ['Scenario J', 'DESYNC-02..07', 'detour recovery'],
    level: turretLevel(true),
    loadout: baseLoadout(),
    takes: [T(crosser(400)), T(doorman())],
    check: (c) => {
      const d = c.ev('desync', { tape: 0 });
      const r = c.ev('resync', { tape: 0 });
      const k = c.ev('kill', { id: 't1' });
      c.need(d.length === 1 && r.length === 1 && k.length === 1 && k[0].tape === 0 && r[0].sub < k[0].sub, 'desync, resync, then the kill');
      c.count('selfDeath', 0);
      c.need(c.ev('enemyShot').filter((e) => e.tape === 0 && e.sub > d[0]?.sub && e.sub < r[0]?.sub).length === 0, 'no shot at the projection');
      c.win(true);
    },
  },
  {
    name: 'desync-scenario-j-no-detour',
    description: 'TEST-17: the spark never catches up, so the desynced strike cannot hurt the turret.',
    covers: ['TEST-17', 'Scenario J'],
    level: turretLevel(false),
    loadout: baseLoadout(),
    takes: [T(crosser(400)), T(doorman())],
    check: (c) => {
      c.count('desync', 1, { tape: 0 });
      c.count('resync', 0, { tape: 0 });
      c.count('kill', 0);
      c.count('selfDeath', 0);
      c.need(!c.outcome.objectiveComplete, 'objective not complete');
    },
  },
]);

// ── combat: targeting, knockback, momentum, dodge (TEST-18..21, Scenario K) ──
add(() => {
  const level = makeLevel({ speeds: [1], bars: 3, start: { x: 2.5, y: 5.5 }, entities: [{ kind: 'enemy', id: 'g1', type: 'grunt', x: 9.5, y: 5.5 }] });
  const tapeA = still(0, 2.5, 5.5, 360);
  const tapeB = pathTape({ index: 1, speed: 1, ticks: 360, path: [{ tick: 0, x: 2.5, y: 5.5 }, { tick: 40, x: 8.5, y: 2.0 }] });
  return [
    {
      name: 'enemy-grunt-strike',
      description: 'A grunt walks at the only self and strikes on its beat grid after a telegraph; one strike kills; the ghost is never targeted again.',
      covers: ['AI-01', 'AI-07', 'HEALTH-01'],
      level,
      loadout: baseLoadout(),
      takes: [T(tapeA)],
      check: (c) => {
        const at = c.ev('enemyAttack', { id: 'g1' });
        c.need(at.length > 0 && at.every((a) => a.sub % 240 === 0), 'strikes on its beat grid');
        c.need(c.ev('enemyTelegraph', { id: 'g1' })[0]?.sub === at[0]?.sub - 60, 'telegraph half a beat ahead');
        c.need(c.ev('selfDeath').map((e) => e.detail).join() === 'struck by grunt g1', 'one strike kills');
      },
    },
    {
      name: 'enemy-grunt-target-switch',
      description: 'A closer self (B) changes the grunt’s target on a beat boundary while A’s path is unchanged.',
      covers: ['TEST-18', 'AI-02..04'],
      level,
      loadout: baseLoadout(),
      takes: [T(tapeA), T(tapeB)],
      check: (c) => c.need(c.run.snapshots.some((f) => f.enemies[0].target === 1), 'switches to B'),
    },
  ];
});

add(() => {
  const level = makeLevel({ speeds: [1], bars: 1, start: { x: 1.5, y: 5.5 }, entities: [{ kind: 'enemy', id: 'g1', type: 'grunt', x: 6.0, y: 5.5, hp: 2, wakeWhen: { const: false } }] });
  const tapeA = pathTape({
    index: 0,
    speed: 1,
    ticks: 120,
    // Detuned from the test (tick 21 for 20, y 3.47 for 3.5) to keep footsteps off the stride knife-edge.
    path: [
      { tick: 0, x: 1.5, y: 5.5 },
      { tick: 21, x: 1.5, y: 3.47 },
      { tick: 50, x: 8.2, y: 3.47 },
      { tick: 60, x: 8.2, y: 5.5 },
    ],
    events: [{ tick: 90, kind: 'light', dir: Math.PI }],
  });
  const tapeB = pathTape({ index: 1, speed: 1, ticks: 120, path: [{ tick: 0, x: 1.5, y: 5.5 }, { tick: 30, x: 5.0, y: 5.5 }], events: [{ tick: 40, kind: 'light', dir: 0 }] });
  return [
    {
      name: 'combat-knockback-alone-whiff',
      description: 'Knockback control: alone, A’s swing at an empty spot whiffs.',
      covers: ['TEST-19'],
      level,
      loadout: baseLoadout(),
      takes: [T(tapeA)],
      check: (c) => {
        c.count('whiff', 1, { tape: 0 });
        c.count('kill', 0);
      },
    },
    {
      name: 'combat-knockback-changes-later-hit',
      description: 'B knocks the grunt east into the spot where A swings later; the same recorded swing now kills.',
      covers: ['TEST-19', 'MOM-05', 'knockback changing later hits'],
      level,
      loadout: baseLoadout(),
      takes: [T(tapeA), T(tapeB)],
      check: (c) => {
        c.count('hit', 1, { tape: 1 });
        c.need(c.ev('kill', { id: 'g1' }).map((e) => e.tape).join() === '0', 'A kills');
        c.count('whiff', 0, { tape: 0 });
      },
    },
  ];
});

for (const [speed, motion] of [
  [0.5, 'stand'],
  [1, 'stand'],
  [2, 'stand'],
  [1, 'into'],
  [1, 'away'],
] as [TapeSpeed, 'stand' | 'into' | 'away'][]) {
  add(() => {
    const level = makeLevel({ speeds: [0.5, 1, 2], bars: 1, start: { x: 5.0, y: 5.5 }, entities: [{ kind: 'enemy', id: 'g1', type: 'grunt', x: 6.0, y: 5.5, hp: 10, wakeWhen: { const: false } }] });
    const v = 4.5 / 60;
    const path =
      motion === 'stand'
        ? [{ tick: 0, x: 5.0, y: 5.5 }]
        : motion === 'into'
          ? [
              { tick: 0, x: 5.0 - 26 * v, y: 5.5 },
              { tick: 26, x: 5.0, y: 5.5 },
            ]
          : [
              { tick: 0, x: 5.0 + 6 * v, y: 5.5 },
              { tick: 20, x: 5.0 + 6 * v, y: 5.5 },
              { tick: 26, x: 5.0, y: 5.5 },
            ];
    return {
      name: `momentum-${String(speed).replace('.', '_')}x-${motion}`,
      description: `One light swing at a tough sleeping grunt from a ${speed}x tape, ${motion === 'stand' ? 'standing' : motion === 'into' ? 'moving into the strike' : 'moving away from the strike'}: momentum sets damage, knockback and stagger.`,
      covers: ['TEST-20', 'MOM-01..04'],
      level,
      loadout: baseLoadout(),
      takes: [T(pathTape({ index: 0, speed, ticks: 120, path, events: [{ tick: 20, kind: 'light', dir: 0 }] }))],
      check: (c) => {
        const hit = c.ev('hit')[0];
        const expect = { stand: 1.2 * speed, into: 1.2, away: 1.2 }[motion];
        c.need(!!hit, 'the swing connects');
        if (motion === 'stand') c.need(Math.abs(hit.power! - expect) < 1e-6, `momentum ${hit?.power} = ${expect}`);
        if (motion === 'into') c.need(hit.power! > expect, 'running into the strike adds momentum');
        if (motion === 'away') c.need(hit.power! < expect, 'moving away removes momentum');
        if (speed === 0.5) c.count('clang', 1);
      },
    };
  });
}

add(() => {
  const level = makeLevel({ speeds: [1], bars: 2, start: { x: 5.0, y: 5.5 }, entities: [{ kind: 'enemy', id: 't1', type: 'turret', x: 10.5, y: 5.5, facing: Math.PI, beat: { every: 64, offset: 2 } }] });
  const stand = (dodgeAt?: number): Tape => still(0, 5.0, 5.5, 240, 1, dodgeAt === undefined ? [] : [{ tick: dodgeAt, kind: 'dodge' }]);
  const none = resolve(level, [stand()]);
  const death = none.events.find((e) => e.type === 'selfDeath');
  if (!death) throw new Error('dodge scenario: the standing self should die');
  const hitTick = Math.floor(death.sub / 4);
  return [
    {
      name: 'dodge-iframes-pass-through',
      description: 'A bolt arriving inside the dodge’s i-frames passes through and breaks on the wall behind.',
      covers: ['TEST-21', 'COMBAT-04'],
      level,
      loadout: baseLoadout(),
      takes: [T(stand(hitTick - 4))],
      check: (c) => {
        c.count('selfDeath', 0);
        c.count('dodge', 1);
        c.need(c.ev('projectileHit', { detail: 'bolt:wall' }).length > 0, 'bolt broke on the wall behind');
      },
    },
    {
      name: 'dodge-too-early-dies',
      description: 'The same dodge started far too early: its i-frames are over when the bolt arrives, which kills.',
      covers: ['TEST-21', 'COMBAT-04', 'fail with none'],
      level,
      loadout: baseLoadout(),
      takes: [T(stand(hitTick - 30))],
      check: (c) => c.count('selfDeath', 1),
    },
    {
      name: 'dodge-record-live-iframes',
      description: 'A recorded dodge gives the live self the same i-frames (10 local ticks) during recording.',
      covers: ['TEST-21', 'COMBAT-04', 'record'],
      level,
      loadout: baseLoadout(),
      takes: [rec(0, 1, 'stop', script().press(101, 'dodge'))],
      check: (c) => {
        const take = recordTake({ level, index: 0, speed: 1, script: script().press(101, 'dodge') });
        c.need(take.frames.filter((f) => f.actors[0].iframes).length === 10, 'ten live i-frame ticks');
        c.need(c.run.recordings[0].tape.events.some((e) => e.kind === 'dodge' && e.tick === 101), 'dodge recorded on tick 101');
      },
    },
  ];
});

// Scenario K: the breakable wall and momentum thresholds.
const wallLevel = (): LevelDef =>
  makeLevel({
    speeds: [0.5, 1, 2],
    bars: 2,
    start: { x: 1.5, y: 5.5 },
    entities: [{ kind: 'breakable', id: 'w1', c: 8, r: 5, threshold: TUTORIAL_WALL_THRESHOLD }],
    objective: { type: 'signal', when: { sig: 'w1' }, text: 'Break the wall' },
  });

function wallScript(speed: TapeSpeed, button: 'light' | 'heavy', running: boolean): InputScript {
  const level = wallLevel();
  const probe = createSim({ level, loadout: baseLoadout(), tapes: [], live: { index: 0, speed, endMode: 'stop' } });
  const run = script().run(0, 1000, 1, 0);
  let pressAt = -1;
  for (let t = 0; t < probe.tapeTicks; t++) {
    probe.stepLocalTick(run.input(t));
    const x = probe.snapshot().actors[0].x;
    if (running && x >= 6.6) {
      pressAt = t + 1;
      break;
    }
    if (!running && x >= 7.69) {
      pressAt = t + 20;
      break;
    }
  }
  if (pressAt < 0) throw new Error('wall scenario: never reached the wall');
  return running ? script().run(0, 1000, 1, 0).press(pressAt, button, 0) : script().run(0, pressAt - 15, 1, 0).press(pressAt, button, 0);
}

for (const [speed, button, running, note] of [
  [1, 'light', false, 'a 1x standing light clangs (momentum 1.2 of 5)'],
  [1, 'heavy', true, 'a 1x running heavy is still too weak (momentum 3)'],
  [2, 'heavy', false, 'a 2x standing heavy is still too weak (momentum 4)'],
  [2, 'heavy', true, 'a 2x running heavy breaks it (momentum 6) and the self walks through the gap'],
] as [TapeSpeed, 'light' | 'heavy', boolean, string][]) {
  add(() => ({
    name: `momentum-wall-${String(speed).replace('.', '_')}x-${running ? 'run' : 'stand'}-${button}`,
    description: `Scenario K: ${note}.`,
    covers: ['Scenario K', 'MOM-01..04', 'momentum thresholds'],
    level: wallLevel(),
    loadout: baseLoadout(),
    takes: [rec(0, speed, 'stop', wallScript(speed, button, running))],
    check: (c) => {
      const breaks = speed === 2 && running;
      c.count('break', breaks ? 1 : 0, { id: 'w1' });
      if (!breaks) c.count('clang', 1, { id: 'w1' });
      c.win(breaks);
    },
  }));
}

// ── mechanisms and objectives ──
const doorRoom = (extra: EntityDef[] = []): LevelDef =>
  makeLevel({
    speeds: [1],
    bars: 2,
    start: { x: 2.5, y: 5.5 },
    entities: [{ kind: 'switch', id: 'sw', x: 2.5, y: 4.5 }, { kind: 'door', id: 'd1', cells: [{ c: 6, r: 5 }], openWhen: { not: { sig: 'sw' } } }, ...extra],
  });

const closer = (at: number): Tape => still(1, 2.5, 5.5, 240, 1, [{ tick: at, kind: 'interact' }]);

add(() => [
  {
    name: 'mech-door-closes-on-playback',
    description: 'A door closing on a playback self desyncs it (doors never delete a body); the spark starts beside the door.',
    covers: ['DESYNC-01', 'doors never delete a body'],
    level: doorRoom(),
    loadout: baseLoadout(),
    // Detuned from the test (x 6.43 on tick 41, not 6.5 on tick 40): dead centre in the door cell
    // the spark's nearest free side is a tie.
    takes: [T(pathTape({ index: 0, speed: 1, ticks: 240, path: [{ tick: 0, x: 2.5, y: 5.5 }, { tick: 41, x: 6.43, y: 5.5 }] })), T(closer(60))],
    check: (c) => {
      const closed = c.ev('door', { id: 'd1', detail: 'closed' });
      const d = c.ev('desync', { tape: 0 });
      c.need(closed.length === 1 && d.length === 1 && d[0].sub === closed[0].sub + 1 && d[0].detail === 'blocked by door d1', 'door closing desyncs the body');
      const a = c.last().actors[0];
      c.need(a.life === 'alive' && !!a.spark && (a.spark.x < 6 - 0.2 || a.spark.x > 7 + 0.2), 'spark beside the door');
    },
  },
  {
    name: 'mech-door-closes-on-live',
    description: 'A door closing on the live self pushes it out to the nearest free side; it stays alive and synced.',
    covers: ['doors never delete a body', 'record'],
    level: doorRoom(),
    loadout: baseLoadout(),
    takes: [T(closer(60)), rec(0, 1, 'stop', script().run(0, 52, 1, 0))],
    check: (c) => {
      c.count('desync', 0, {}, c.recEvents());
      c.need(c.run.recordings[0].snapshots.every((f) => f.actors.every((a) => a.synced && a.life === 'alive')), 'live self stays synced and alive');
    },
  },
  {
    name: 'mech-door-pushes-enemy',
    description: 'A door closing on a sleeping grunt pushes it out of the doorway.',
    covers: ['doors never delete a body'],
    level: doorRoom([{ kind: 'enemy', id: 'g1', type: 'grunt', x: 6.5, y: 5.3, wakeWhen: { const: false } }]),
    loadout: baseLoadout(),
    takes: [T(closer(10))],
    check: (c) => {
      const g = c.last().enemies[0];
      c.need(g.alive && !(g.x > 6 - 0.32 && g.x < 7 + 0.32 && g.y > 5 - 0.32 && g.y < 6 + 0.32), 'grunt pushed out of the doorway');
    },
  },
  {
    name: 'mech-interact-nothing',
    description: 'An interact with nothing in reach emits interactFail "nothing in reach".',
    covers: ['interactFail'],
    level: doorRoom(),
    loadout: baseLoadout(),
    takes: [T(still(0, 8.5, 8.5, 120, 1, [{ tick: 10, kind: 'interact' }]))],
    check: (c) => c.count('interactFail', 1, { detail: 'nothing in reach' }),
  },
]);

add(() => {
  const plateLevel = (heavy: boolean): LevelDef =>
    makeLevel({
      speeds: [1],
      bars: 1,
      start: { x: 2.5, y: 5.5 },
      entities: [
        { kind: 'plate', id: 'p1', c: 5, r: 5, heavy },
        { kind: 'laser', id: 'beam', from: { x: 8.5, y: 1.5 }, to: { x: 8.5, y: 8.5 }, onWhen: { not: { sig: 'p1' } } },
      ],
    });
  // Detuned from the test (ticks 31, 61 / 101 for 30, 60 / 100; 7.47 / 10.47 for 7.5 / 10.5): the test's speeds put the plate
  // entry and the footsteps on exact substep ties.
  const onPlate = (): Tape => pathTape({ index: 0, speed: 1, ticks: 120, path: [{ tick: 0, x: 2.5, y: 5.5 }, { tick: 31, x: 5.5, y: 5.5 }] });
  const crosser2 = (): Tape => pathTape({ index: 2, speed: 1, ticks: 120, path: [{ tick: 0, x: 2.5, y: 5.5 }, { tick: 61, x: 2.5, y: 7.47 }, { tick: 101, x: 10.47, y: 7.47 }] });
  return [
    {
      name: 'mech-plate-holds-laser-off',
      description: 'An effective body holds a plate, which switches a laser off for another self crossing it.',
      covers: ['plates', 'lasers', 'signals'],
      level: plateLevel(false),
      loadout: baseLoadout(),
      takes: [T(onPlate()), T(crosser2())],
      check: (c) => {
        c.need(c.ev('plate', { id: 'p1' }).map((e) => e.detail).join() === 'on', 'plate on');
        c.need(c.ev('laser', { id: 'beam' }).map((e) => e.detail).join() === 'off', 'laser off');
        c.count('selfDeath', 0);
      },
    },
    {
      name: 'mech-laser-kills',
      description: 'Without the plate held the laser kills the crossing self (fail with no survivor).',
      covers: ['lasers', 'fail with none'],
      level: plateLevel(false),
      loadout: baseLoadout(),
      takes: [T(crosser2())],
      check: (c) => {
        c.need(c.ev('selfDeath').map((e) => e.detail).join() === 'burned by laser beam', 'burned');
        c.need(c.outcome.reason === 'noSurvivor', 'no survivor');
      },
    },
    {
      name: 'ability-laser-proof',
      description: "laserProof: the same crossing survives the live laser.",
      covers: ['laserProof', 'every ability'],
      level: plateLevel(false),
      loadout: baseLoadout({ abilities: ['laserProof'] }),
      takes: [T(crosser2())],
      check: (c) => c.count('selfDeath', 0),
    },
    {
      name: 'mech-heavy-plate-needs-heavystep',
      description: 'A heavy plate ignores an ordinary self.',
      covers: ['plates', 'heavyStep'],
      level: plateLevel(true),
      loadout: baseLoadout(),
      takes: [T(onPlate())],
      check: (c) => c.count('plate', 0),
    },
    {
      name: 'ability-heavy-step',
      description: 'heavyStep: the same self holds the heavy plate and turns the laser off.',
      covers: ['heavyStep', 'every ability'],
      level: plateLevel(true),
      loadout: baseLoadout({ abilities: ['heavyStep'] }),
      takes: [T(onPlate())],
      check: (c) => c.need(c.ev('plate').map((e) => e.detail).join() === 'on', 'plate on'),
    },
  ];
});

add(() => {
  const level = makeLevel({
    speeds: [1],
    bars: 1,
    start: { x: 2.5, y: 5.5 },
    entities: [
      { kind: 'laser', id: 'beam', from: { x: 1.5, y: 3.5 }, to: { x: 10.5, y: 3.5 }, onWhen: { const: true } },
      { kind: 'plate', id: 'p1', c: 5, r: 1 },
    ],
  });
  return {
    name: 'mech-dead-ghost-no-plate',
    description: 'A self dies to a laser on the way; its ghost then stands on the plate, which stays off.',
    covers: ['GHOST-05', 'plates'],
    level,
    loadout: baseLoadout(),
    takes: [T(pathTape({ index: 0, speed: 1, ticks: 120, path: [{ tick: 0, x: 2.5, y: 5.5 }, { tick: 40, x: 5.5, y: 1.5 }] }))],
    check: (c) => {
      c.count('selfDeath', 1);
      c.count('plate', 0);
    },
  };
});

add(() => {
  const level = makeLevel({ speeds: [1], bars: 1, start: { x: 2.5, y: 5.5 }, entities: [{ kind: 'exit', id: 'exit', c: 9, r: 4, w: 2, h: 2 }], objective: { type: 'reach', text: 'Get out' } });
  return [
    {
      name: 'objective-reach-win',
      description: 'reach: an alive, synced self is in the exit when the horizon ends (the objective latches on the last substep).',
      covers: ['reach objective', 'exit'],
      level,
      loadout: baseLoadout(),
      takes: [T(pathTape({ index: 0, speed: 1, ticks: 120, path: [{ tick: 0, x: 2.5, y: 5.5 }, { tick: 60, x: 9.5, y: 5.0 }] }))],
      check: (c) => {
        c.win(true);
        c.need(c.ev('objective').length === 1 && c.ev('objective')[0].sub === c.run.horizonSubs - 1, 'latched on the last substep');
      },
    },
    {
      name: 'objective-reach-pass-by-fails',
      description: 'reach: passing through the exit and leaving again does not count.',
      covers: ['reach objective', 'exit'],
      level,
      loadout: baseLoadout(),
      takes: [T(pathTape({ index: 0, speed: 1, ticks: 120, path: [{ tick: 0, x: 2.5, y: 5.5 }, { tick: 50, x: 9.5, y: 5.0 }, { tick: 80, x: 5.5, y: 5.0 }] }))],
      check: (c) => c.need(!c.outcome.objectiveComplete, 'passing by does not count'),
    },
  ];
});

add(() => {
  const level = makeLevel({
    speeds: [0.5, 1],
    bars: 1,
    start: { x: 5.0, y: 5.5 },
    entities: [{ kind: 'core', id: 'c1', x: 6.0, y: 5.5, threshold: 1 }],
    objective: { type: 'activate', text: 'Light the core' },
  });
  const swing = (speed: 0.5 | 1): Tape => still(0, 5.0, 5.5, 120, speed, [{ tick: 10, kind: 'light', dir: 0 }]);
  return [
    {
      name: 'objective-core-weak-clang',
      description: 'activate: a 0.5x light (momentum 0.6) clangs off a threshold-1 core.',
      covers: ['activate objective', 'cores'],
      level,
      loadout: baseLoadout(),
      takes: [T(swing(0.5))],
      check: (c) => {
        c.count('clang', 1, { id: 'c1' });
        c.need(!c.outcome.objectiveComplete, 'not lit');
      },
    },
    {
      name: 'objective-core-activated',
      description: 'activate: a 1x light (momentum 1.2) lights the core and wins.',
      covers: ['activate objective', 'cores'],
      level,
      loadout: baseLoadout(),
      takes: [T(swing(1))],
      check: (c) => {
        c.count('core', 1, { id: 'c1' });
        c.win(true);
      },
    },
  ];
});

// ── enemies ──
add(() => {
  const stalker: EntityDef = { kind: 'enemy', id: 's1', type: 'stalker', x: 6, y: 5, wakeWhen: { beat: { every: 1000, from: 1, to: 1000 } } };
  const level = makeLevel({ speeds: [1], bars: 4, start: { x: 2, y: 5 }, entities: [stalker] });
  const tapeA = still(0, 2, 5, 480);
  const tapeB = pathTape({ index: 1, speed: 1, ticks: 480, path: [{ tick: 0, x: 2, y: 5 }, { tick: 20, x: 10, y: 8 }] });
  return [
    {
      name: 'enemy-stalker-alone',
      description: 'A stalker wakes on beat 1 and hunts the only self.',
      covers: ['AI-01', 'AI-02', 'stalker'],
      level,
      loadout: baseLoadout(),
      takes: [T(tapeA)],
      check: (c) => {
        c.need(c.run.snapshots.some((f) => f.enemies[0].target === 0), 'targets A');
        c.need(c.ev('selfDeath').map((d) => d.detail).join() === 'struck by stalker s1', 'strikes A');
      },
    },
    {
      name: 'enemy-stalker-farthest',
      description: 'A stalker hunts the FARTHEST self past a nearer one, kills it on its beat grid, then re-picks the survivor.',
      covers: ['AI-01', 'AI-02', 'AI-07', 'stalker'],
      level,
      loadout: baseLoadout(),
      takes: [T(tapeA), T(tapeB)],
      check: (c) => {
        c.need(c.ev('selfDeath').map((d) => d.tape).join() === '1,0', 'kills B (farthest) first, then A');
        c.need(c.ev('enemyAttack', { id: 's1' }).every((a) => a.sub % 240 === 120), 'strikes on beats 1, 3, 5 …');
      },
    },
  ];
});

add(() => {
  const shielder: EntityDef = { kind: 'enemy', id: 'sh', type: 'shielder', x: 6, y: 5, wakeWhen: { const: false } };
  const level = makeLevel({ speeds: [0.5, 1, 2], bars: 2, start: { x: 4.9, y: 5 }, entities: [shielder] });
  const striker = (index: TapeIndex, ticks: number[], kind: 'light' | 'heavy' = 'light', speed: TapeSpeed = 1) => {
    const west = index % 2 === 0;
    return pathTape({ index, speed, ticks: 240, path: [{ tick: 0, x: west ? 4.9 : 7.1, y: 5 }], events: ticks.map((tick) => ({ tick, kind, dir: west ? 0 : Math.PI })) });
  };
  const c = pathTape({ index: 2, speed: 1, ticks: 240, path: [{ tick: 0, x: 3.9, y: 5 }], events: [{ tick: 63, kind: 'light', dir: 0 }] });
  return [
    {
      name: 'enemy-shielder-alone-clangs',
      description: 'One self alone can never hurt a shielder: eight lights all clang off the shield.',
      covers: ['Scenario A', 'AI-05', 'shielder'],
      level,
      loadout: baseLoadout(),
      takes: [T(striker(0, [10, 14, 18, 22, 40, 60, 80, 100]))],
      check: (k) => {
        k.count('hit', 0, { id: 'sh' });
        k.count('clang', 8, { id: 'sh', detail: 'shield' });
      },
    },
    {
      name: 'enemy-shielder-pair-hit',
      description: 'A pops the shield, B follows inside the window and lands; the shield is back at once, so A’s next swing only pops it again.',
      covers: ['Scenario A', 'AI-05', 'shielder'],
      level,
      loadout: baseLoadout(),
      takes: [T(striker(0, [30, 36])), T(striker(1, [33]))],
      check: (k) => {
        k.need(JSON.stringify(k.ev('hit', { id: 'sh' }).map((h) => [h.sub, h.tape])) === JSON.stringify([[(33 + 6) * 4, 1]]), 'B lands inside the window');
        k.count('clang', 2, { id: 'sh', tape: 0 });
      },
    },
    {
      name: 'enemy-shielder-two-pairs-kill',
      description: 'Two coordinated pairs kill it: B’s landed hit shoves it toward C, who supplies the second follow-up after A pops it again.',
      covers: ['Scenario A', 'shielder two-self kill', 'MOM-05'],
      level,
      loadout: baseLoadout(),
      takes: [T(striker(0, [30, 60])), T(striker(1, [33])), T(c)],
      check: (k) => {
        k.need(k.ev('hit', { id: 'sh' }).map((h) => h.tape).join() === '1,2', 'B then C land');
        k.need(k.ev('kill', { id: 'sh' }).map((h) => h.tape).join() === '2', 'C kills');
        k.win(true);
      },
    },
    {
      name: 'enemy-shielder-same-substep-kill',
      description: 'Two selves strike on the same substep with 1x heavies: the first pops, the second kills (the classic two-self kill).',
      covers: ['Scenario A', 'shielder two-self kill'],
      level,
      loadout: baseLoadout(),
      takes: [T(striker(0, [30], 'heavy')), T(striker(1, [30], 'heavy'))],
      check: (k) => {
        k.need(k.ev('clang', { id: 'sh' }).map((h) => h.tape).join() === '0', 'A pops');
        k.need(JSON.stringify(k.ev('kill', { id: 'sh' }).map((h) => [h.sub, h.tape])) === JSON.stringify([[(30 + 16) * 4, 1]]), 'B kills on the same substep');
      },
    },
  ];
});

add(() => {
  const shielder: EntityDef = { kind: 'enemy', id: 'sh', type: 'shielder', x: 6, y: 5, wakeWhen: { const: false } };
  const level = makeLevel({ speeds: [1], bars: 2, start: { x: 2, y: 2 }, entities: [shielder, { kind: 'enemy', id: 't1', type: 'turret', x: 10, y: 5, facing: Math.PI }] });
  return {
    name: 'enemy-shielder-blocks-bolts',
    description: 'A self hides behind a shielder from a turret: the bolts clang off the shield without popping it.',
    covers: ['shielder', 'turret'],
    level,
    loadout: baseLoadout(),
    takes: [T(still(0, 2, 5, 240))],
    check: (c) => {
      c.need(c.ev('clang', { id: 'sh' }).length > 0, 'bolts clang');
      c.count('hit', 0, { id: 'sh' });
      c.need(c.run.snapshots.every((f) => f.enemies[0].shield === true), 'shield never drops');
    },
  };
});

add(() => {
  const sleeper = (type: 'brute' | 'grunt', hp?: number): EnemyDef => ({ kind: 'enemy', id: 'b1', type, x: 6, y: 5, wakeWhen: { const: false }, ...(hp !== undefined ? { hp } : {}) });
  const lvl = (type: 'brute' | 'grunt', hp?: number) => makeLevel({ speeds: [1, 2], bars: 2, start: { x: 4.9, y: 5 }, entities: [sleeper(type, hp)] });
  const swings = (ticks: number[], kind: 'light' | 'heavy' = 'light', speed: 1 | 2 = 1) => still(0, 4.9, 5, 240, speed, ticks.map((tick) => ({ tick, kind, dir: 0 })));
  const runLevel = makeLevel({ speeds: [1], bars: 2, start: { x: 1.5, y: 5 }, entities: [{ ...sleeper('brute'), x: 5.9 }] });
  const runIn = pathTape({ index: 0, speed: 1, ticks: 240, path: [{ tick: 0, x: 1.5, y: 5 }, { tick: 40, x: 4.8, y: 5 }], events: [{ tick: 39, kind: 'heavy', dir: 0 }] });
  return [
    {
      name: 'enemy-brute-three-lights',
      description: 'Three standing 1x lights kill a brute; the first two neither move nor stagger it (poise).',
      covers: ['HEALTH-02', 'MOM-05', 'brute'],
      level: lvl('brute'),
      loadout: baseLoadout(),
      takes: [T(swings([20, 60, 100]))],
      check: (c) => {
        c.count('hit', 3, { id: 'b1' });
        c.count('kill', 1, { id: 'b1' });
        c.count('enemyStagger', 0);
      },
    },
    {
      name: 'enemy-brute-poise-broken',
      description: 'A 2x standing heavy (momentum 4) is above the brute’s poise: it really moves and staggers it.',
      covers: ['MOM-05', 'brute'],
      level: lvl('brute', 10),
      loadout: baseLoadout(),
      takes: [T(swings([20], 'heavy', 2))],
      check: (c) => {
        c.count('enemyStagger', 1, { id: 'b1' });
        c.need(c.last().enemies[0].x > 6.5 && c.last().enemies[0].hp === 6, 'moved and damaged');
      },
    },
    {
      name: 'enemy-grunt-shoved',
      description: 'The same light that a brute shrugs off shoves a grunt back.',
      covers: ['MOM-05', 'knockback'],
      level: lvl('grunt', 3),
      loadout: baseLoadout(),
      takes: [T(swings([20]))],
      check: (c) => c.need(c.last().enemies[0].x > 7, 'grunt shoved more than a tile'),
    },
    {
      name: 'enemy-brute-running-heavy',
      description: 'One 1x running heavy (approach clamps to 1: momentum 3) kills a brute outright.',
      covers: ['MOM-01..04', 'brute'],
      level: runLevel,
      loadout: baseLoadout(),
      takes: [T(runIn)],
      check: (c) => {
        c.need(Math.abs((c.ev('hit', { id: 'b1' })[0]?.power ?? 0) - 3) < 1e-4, 'momentum 3');
        c.count('kill', 1, { id: 'b1' });
      },
    },
  ];
});

add(() => {
  const lvl = makeLevel({ speeds: [1], bars: 2, start: { x: 4.9, y: 5 }, entities: [{ kind: 'enemy', id: 'b1', type: 'brute', x: 6, y: 5 }] });
  return {
    name: 'enemy-brute-slam-wide',
    description: 'An awake brute telegraphs its slam and lands it on its grid beat; the slam is wide enough to kill a self at its side as well.',
    covers: ['AI-04', 'AI-07', 'brute', 'fail with none'],
    level: lvl,
    loadout: baseLoadout(),
    takes: [T(still(0, 4.9, 5, 240)), T(still(1, 6, 3.6, 240))],
    check: (c) => {
      const a = c.ev('enemyAttack', { id: 'b1' })[0];
      c.need(!!a && (a.sub - 240) % 480 === 0 && c.ev('enemyTelegraph', { id: 'b1' })[0]?.detail === 'slam', 'telegraphed slam on its grid beat');
      c.need(JSON.stringify(c.ev('selfDeath').map((d) => [d.tape, d.sub])) === JSON.stringify([[0, a?.sub], [1, a?.sub]]), 'both selves die to one slam');
    },
  };
});

add(() => {
  const plate = makeLevel({
    speeds: [1],
    bars: 1,
    start: { x: 2, y: 2 },
    entities: [{ kind: 'enemy', id: 'b1', type: 'brute', x: 6.5, y: 5.5, wakeWhen: { const: false } }, { kind: 'plate', id: 'p1', c: 6, r: 5, heavy: true }],
  });
  return {
    name: 'enemy-brute-holds-heavy-plate',
    description: 'A sleeping brute’s body holds a heavy plate.',
    covers: ['brute', 'plates'],
    level: plate,
    loadout: baseLoadout(),
    takes: [T(still(0, 2, 2, 120))],
    check: (c) => c.need(c.run.snapshots[1].mechs.find((m) => m.id === 'p1')!.on, 'brute holds the plate'),
  };
});

add(() => {
  const HOLD_FIRE = { every: 1000, offset: 999 };
  const droneAt = (x: number, y: number, extra: Partial<EntityDef> = {}): EntityDef => ({ kind: 'enemy', id: 'd1', type: 'drone', x, y, ...extra }) as EntityDef;
  const voidMap = ['##############', '#...=.   ....#', '#...=.   ....#', '#...=.   ....#', '#...=.   ....#', '#...=.   ....#', '#...=.   ....#', '##############'];
  const keep = (e: { x: number; y: number }, x: number, y: number) => Math.abs(Math.hypot(e.x - x, e.y - y) - 5) <= 0.5;
  // Detuned from the tests (drones at 4.013 / 12.513, B at y 8.2): whole-tile distances put the
  // drone's stop on its keep band exactly, and the test's A/B pair is equidistant from the drone.
  return [
    {
      name: 'enemy-drone-backs-off',
      description: 'A drone backs off from a self that is too close until it is at its keep distance.',
      covers: ['AI-01', 'drone'],
      level: makeLevel({ speeds: [1], bars: 4, start: { x: 2, y: 5 }, entities: [droneAt(4.013, 5, { beat: HOLD_FIRE })] }),
      loadout: baseLoadout(),
      takes: [T(still(0, 2, 5, 480))],
      check: (c) => c.need(keep(c.last().enemies[0], 2, 5), 'at its keep distance'),
    },
    {
      name: 'enemy-drone-hovers-over-void',
      description: 'A drone closes in over a void trench and a low barrier that would stop a walker.',
      covers: ['AI-01', 'drone', 'void'],
      level: makeLevel({ map: voidMap, speeds: [1], bars: 4, start: { x: 1.5, y: 3.5 }, entities: [droneAt(12.513, 3.5, { beat: HOLD_FIRE })] }),
      loadout: baseLoadout(),
      takes: [T(still(0, 1.5, 3.5, 480))],
      check: (c) => {
        const d = c.last().enemies[0];
        c.need(d.x < 9 && voidMap[Math.floor(d.y)][Math.floor(d.x)] === ' ' && keep(d, 1.5, 3.5), 'hovers over the trench at keep distance');
      },
    },
    {
      name: 'enemy-drone-fire',
      description: 'A drone fires telegraphed bolts on the off-beat along its locked aim at three spread-out selves.',
      covers: ['AI-06', 'AI-07', 'drone'],
      level: makeLevel({ speeds: [1], bars: 4, start: { x: 1.5, y: 5 }, entities: [droneAt(6.5, 5)] }),
      loadout: baseLoadout(),
      takes: [T(still(0, 1.5, 2, 480)), T(still(1, 1.5, 8.2, 480)), T(still(2, 10.5, 8, 480))],
      check: (c) => {
        const shots = c.ev('enemyShot', { id: 'd1' });
        c.need(shots.length >= 2 && shots.every((s) => s.sub % SPB === SPB / 2), 'bolts on the off-beat');
        c.need(c.ev('selfDeath').some((d) => d.detail === 'shot by drone d1'), 'a bolt kills');
      },
    },
    {
      name: 'enemy-drone-two-hits',
      description: 'A drone takes two hit points: a 2x light (2 damage) kills it.',
      covers: ['HEALTH-02', 'drone'],
      level: makeLevel({ speeds: [1, 2], bars: 1, start: { x: 5.5, y: 5 }, entities: [droneAt(6.5, 5, { wakeWhen: { const: false } })] }),
      loadout: baseLoadout(),
      takes: [T(still(0, 5.5, 5, 120, 2, [{ tick: 10, kind: 'light', dir: 0 }]))],
      check: (c) => c.count('kill', 1, { id: 'd1' }),
    },
  ];
});

// ── the boss (BOSS-01..03, HEALTH-03) ──
add(() => {
  const boss: EntityDef = { kind: 'enemy', id: 'b1', type: 'boss', x: 6, y: 5, facing: Math.PI, hp: 16 };
  const level = makeLevel({ speeds: [1, 2], bars: 2, start: { x: 4.7, y: 5 }, entities: [boss], objective: { type: 'boss', text: 'Defeat the boss' } });
  const holder = still(0, 4.7, 5, 240);
  const striker = (index: TapeIndex) => still(index, 7.9, 5, 240, 2, [40, 80, 120, 160].map((tick) => ({ tick, kind: 'heavy' as const, dir: Math.PI })));
  const boss12: EntityDef = { ...boss, hp: 12 };
  // boss-phases is detuned from its test (the selves at y 5.03, not 5): level with the boss, its
  // facing is exactly ±π and the sweep ring's orientation would hang on the sign of a zero.
  const level12 = makeLevel({ speeds: [1, 2], bars: 4, start: { x: 4.7, y: 5.03 }, entities: [boss12], objective: { type: 'boss', text: 'Defeat the boss' } });
  return [
    {
      name: 'boss-coordinated-win',
      description: 'One self holds the boss’s eye in front, another lands 2x heavies on its back: phases 2 and 3, then the kill; both survive.',
      covers: ['BOSS-03', 'HEALTH-03', 'boss fight without memory'],
      level,
      loadout: baseLoadout(),
      takes: [T(holder), T(striker(1))],
      check: (c) => {
        c.need(c.ev('hit', { id: 'b1' }).map((h) => h.tape).join() === '1,1,1,1', 'four back hits by B');
        c.need(c.ev('bossPhase', { id: 'b1' }).map((p) => p.power).join() === '2,3', 'phases 2 and 3');
        c.win(true);
      },
    },
    {
      name: 'boss-alone-armour',
      description: 'One self alone can never hurt the boss (armour clangs) and is cleaved on the bar grid.',
      covers: ['BOSS-03', 'AI-07'],
      level,
      loadout: baseLoadout(),
      takes: [T(striker(0))],
      check: (c) => {
        c.count('hit', 0, { id: 'b1' });
        c.need(c.ev('clang', { id: 'b1' }).length > 0 && c.ev('clang', { id: 'b1' }).every((x) => x.detail === 'armour'), 'armour');
        c.need(c.ev('selfDeath')[0]?.detail === 'struck by boss b1' && c.ev('selfDeath')[0].sub % (4 * SPB) === 0, 'cleaved on the bar');
      },
    },
    {
      name: 'boss-phases',
      description: 'Two back hits move the boss to phase 2 (adds the sweep ring of shock shots) and phase 3 (attacks every two beats).',
      covers: ['HEALTH-03', 'AI-07', 'shock projectiles'],
      level: level12,
      loadout: baseLoadout(),
      takes: [T(still(0, 4.7, 5.03, 480)), T(still(1, 7.9, 5.03, 480, 2, [40, 80].map((tick) => ({ tick, kind: 'heavy' as const, dir: Math.PI }))))],
      check: (c) => {
        c.need(c.ev('bossPhase', { id: 'b1' }).map((p) => p.detail).join() === 'phase 2,phase 3', 'two phase changes');
        c.need(c.ev('enemyAttack', { id: 'b1' }).some((a) => a.detail === 'sweep'), 'the sweep appears');
        c.need(c.ev('enemyAttack', { id: 'b1' }).every((a) => a.sub % SPB === 0), 'every landing on a whole beat');
      },
    },
  ];
});

add(() => {
  const map = ['################', '#..............#', '#..............#', '#..............#', '#..............#', '#.........#....#', '#.........#....#', '#.........#....#', '#..............#', '#..............#', '#..............#', '################'];
  const boss: EntityDef = { kind: 'enemy', id: 'b1', type: 'boss', x: 7, y: 6.5, facing: 0, hp: 20 };
  const level = () => makeLevel({ map, speeds: [1, 2], bars: 2, start: { x: 3.5, y: 2.5 }, entities: [boss], objective: { type: 'boss', text: 'Defeat the boss' } });
  // Detuned from the test (first leg ends on tick 31, not 30) to keep footsteps off the stride knife-edge.
  const tapeA = pathTape({ index: 0, speed: 1, ticks: 240, path: [{ tick: 0, x: 3.5, y: 2.5 }, { tick: 31, x: 13.5, y: 2.5 }, { tick: 60, x: 13.5, y: 6.5 }] });
  const tapeB = pathTape({ index: 1, speed: 1, ticks: 240, path: [{ tick: 0, x: 3.5, y: 2.5 }, { tick: 25, x: 5.2, y: 6.5 }], events: [{ tick: 60, kind: 'heavy', dir: 0 }] });
  const guard = pathTape({ index: 1, speed: 2, ticks: 240, path: [{ tick: 0, x: 3.5, y: 2.5 }, { tick: 50, x: 5.2, y: 6.5 }], events: [{ tick: 100, kind: 'heavy', dir: 0 }] });
  const swinger = pathTape({ index: 2, speed: 1, ticks: 240, path: [{ tick: 0, x: 3.5, y: 2.5 }, { tick: 240, x: 3.5, y: 9.5 }], events: [{ tick: 72, kind: 'light', dir: 0 }] });
  return [
    {
      name: 'boss-memory-none',
      description: 'First take, no memory: only the base pattern; the pillar shelters tape A.',
      covers: ['BOSS-01', 'boss fight without memory'],
      level: level(),
      loadout: baseLoadout(),
      takes: [T(tapeA)],
      check: (c) => {
        c.count('bossRecall', 0);
        c.count('selfDeath', 0);
      },
    },
    {
      name: 'boss-memory-dwell',
      description: 'With memory of committed tape A the boss pre-empts A’s remembered dwell: telegraphed at the remembered place, then struck.',
      covers: ['BOSS-01', 'BOSS-02', 'boss fight with memory'],
      level: level(),
      loadout: baseLoadout(),
      takes: [T(tapeA)],
      bossMemoryFrom: [0],
      check: (c) => {
        const r = c.ev('bossRecall', { id: 'b1' });
        c.need(r.length === 1 && r[0].tape === 0 && r[0].detail === 'dwell', 'one dwell recall of A');
        const d = c.ev('selfDeath', { tape: 0 });
        c.need(d.length === 1 && d[0].sub === 3 * SPB && d[0].detail === 'struck by boss b1 (remembering Tape A)', 'A struck at the remembered dwell');
      },
    },
    {
      name: 'boss-memory-blind-armour',
      description: 'Without memory, B is the nearest self, holds the boss’s attention and clangs off its armour.',
      covers: ['BOSS-03', 'boss fight without memory'],
      level: level(),
      loadout: baseLoadout(),
      takes: [T(tapeA), T(tapeB)],
      check: (c) => {
        c.need(JSON.stringify(c.ev('clang', { id: 'b1', tape: 1 }).map((x) => [x.sub, x.detail])) === JSON.stringify([[(60 + 16) * 4, 'armour']]), 'B clangs');
        c.count('hit', 0, { id: 'b1' });
      },
    },
    {
      name: 'boss-memory-exploited',
      description: 'With memory, the boss commits to punishing A’s old spot and B’s back hit lands.',
      covers: ['BOSS-02', 'BOSS-03', 'boss fight with memory'],
      level: level(),
      loadout: baseLoadout(),
      takes: [T(tapeA), T(tapeB)],
      bossMemoryFrom: [0],
      check: (c) => c.need(c.ev('hit', { id: 'b1', tape: 1 }).map((h) => h.sub).join() === String((60 + 16) * 4), 'B lands'),
    },
    {
      name: 'boss-memory-guard-cancels',
      description: 'A strong back hit during the recall telegraph staggers the boss and cancels the memory strike, protecting the remembered tape.',
      covers: ['BOSS-02', 'boss fight with memory'],
      level: level(),
      loadout: baseLoadout(),
      takes: [T(tapeA), T(guard)],
      bossMemoryFrom: [0],
      check: (c) => {
        c.count('bossRecall', 1);
        c.count('enemyStagger', 1, { id: 'b1' });
        c.count('enemyAttack', 0, { id: 'b1', detail: 'recall' });
        c.count('selfDeath', 0, { tape: 0 });
      },
    },
    {
      name: 'boss-memory-attack-recall',
      description: 'A remembered attack (a light swung while passing) is pre-empted on the nearest whole beat.',
      covers: ['BOSS-02', 'boss fight with memory'],
      level: level(),
      loadout: baseLoadout(),
      takes: [T(swinger)],
      bossMemoryFrom: [2],
      check: (c) => c.need(JSON.stringify(c.ev('bossRecall', { id: 'b1' }).map((r) => [r.tape, r.detail, r.power])) === JSON.stringify([[2, 'attack', 2]]), 'attack recall on beat 2'),
    },
    {
      name: 'boss-memory-record',
      description: 'Recording take B (idle) with memory of committed tape A sees the same memory strike as its authoritative resolve.',
      covers: ['BOSS-01', 'BOSS-02', 'record', 'boss fight with memory'],
      level: level(),
      loadout: baseLoadout(),
      takes: [T(tapeA), rec(1, 1, 'stop', script())],
      bossMemoryFrom: [0],
      check: (c) => {
        const live = c.ev('bossRecall', {}, c.recEvents()).map((e) => e.sub).join();
        c.need(live !== '' && live === c.ev('bossRecall').map((e) => e.sub).join(), 'same memory strike live and resolved');
      },
    },
  ];
});

// ── ranged archetypes (WEAPON-01..03, NEW-02..05, Scenario F) ──
// As in tests/core/weapons/archetypes.test.ts, except pierce flies at 23.7 tiles/s (not 24): at 0.1
// tile per substep its wall contact fell exactly on a substep boundary.
const WEAPONS: Record<RangedWeaponDef['archetype'], Partial<RangedWeaponDef>> = {
  missile: { archetype: 'missile', speed: 2.5, range: 14, turnRate: 2.5, pierce: 0 },
  pierce: { archetype: 'pierce', speed: 23.7, range: 12, pierce: 3, radius: 0.12, turnRate: 0 },
  phase: { archetype: 'phase', speed: 6, range: 9, passesWalls: true, pierce: 0, turnRate: 0 },
  arc: { archetype: 'arc', speed: 7, range: 6, lobbed: true, blast: 1.2, pierce: 0, turnRate: 0 },
  burst: { archetype: 'burst', speed: 16, range: 8, count: 5, spreadDeg: 40, pierce: 0, turnRate: 0, radius: 0.2 },
};

const rangeLevel = (entities: EntityDef[], map: MapRows = OPEN_ROOM): LevelDef => makeLevel({ speeds: [1], bars: 4, map, start: { x: 2.5, y: 5.5 }, entities });
const shooter = (dir = 0): Tape => still(0, 2.5, 5.5, 480, 1, [{ tick: 10, kind: 'ranged', dir }]);
const loadoutWith = (ranged: Partial<RangedWeaponDef>, more: LoadoutPatch = {}) => baseLoadout({ ...more, ranged });
const WALLED: MapRows = withMap((row, r) => (inner(r) ? row.slice(0, 5) + '#' + row.slice(6) : row));

add(() => [
  {
    name: 'ranged-pierce-line',
    description: 'A piercing shot strikes three enemies in its line, each exactly once, then ends at the far wall.',
    covers: ['NEW-04', 'WEAPON-01', 'pierce'],
    level: rangeLevel([grunt('g1', 5.5, 5.5, 5), grunt('g2', 7.5, 5.5, 5), grunt('g3', 9.5, 5.5, 5)]),
    loadout: loadoutWith(WEAPONS.pierce),
    takes: [T(shooter())],
    check: (c) => {
      for (const id of ['g1', 'g2', 'g3']) c.count('hit', 1, { id, detail: 'pierce' });
      c.count('projectileHit', 1, { detail: 'pierce:wall' });
    },
  },
  {
    name: 'ranged-pierce-1-stops',
    description: 'pierce 1 passes through one enemy and stops at the next.',
    covers: ['NEW-04', 'pierce'],
    level: rangeLevel([grunt('g1', 5.5, 5.5, 5), grunt('g2', 7.5, 5.5, 5), grunt('g3', 9.5, 5.5, 5)]),
    loadout: loadoutWith({ ...WEAPONS.pierce, pierce: 1 }),
    takes: [T(shooter())],
    check: (c) => {
      c.count('hit', 1, { id: 'g2' });
      c.count('hit', 0, { id: 'g3' });
    },
  },
  {
    name: 'ranged-phase-through-wall',
    description: 'A phase shot passes a full wall and kills the enemy behind it.',
    covers: ['NEW-05', 'phase'],
    level: rangeLevel([grunt('g1', 8.5, 5.5)], WALLED),
    loadout: loadoutWith(WEAPONS.phase),
    takes: [T(shooter())],
    check: (c) => c.count('kill', 1, { id: 'g1' }),
  },
  {
    name: 'ranged-phase-map-edge',
    description: 'A long-range phase shot stops at the map edge.',
    covers: ['NEW-05', 'phase'],
    level: rangeLevel([]),
    loadout: loadoutWith({ ...WEAPONS.phase, range: 40 }),
    takes: [T(shooter())],
    check: (c) => c.count('projectileHit', 1, { detail: 'phase:edge' }),
  },
  {
    name: 'ranged-burst-wall',
    description: 'A burst is stopped by a full wall: every pellet breaks on it.',
    covers: ['NEW-05', 'burst'],
    level: rangeLevel([grunt('g1', 8.5, 5.5)], WALLED),
    loadout: loadoutWith(WEAPONS.burst),
    takes: [T(shooter())],
    check: (c) => {
      c.count('hit', 0, { id: 'g1' });
      c.need(c.ev('projectileHit', { detail: 'burst:wall' }).length > 0, 'pellets break on the wall');
    },
  },
  {
    name: 'ranged-arc-over-wall',
    description: 'An arc shot is lobbed over a full wall and lands on the enemy behind it.',
    covers: ['NEW-05', 'arc'],
    level: rangeLevel([grunt('g1', 8.5, 5.5)], WALLED),
    loadout: loadoutWith(WEAPONS.arc),
    takes: [T(shooter())],
    check: (c) => {
      c.count('hit', 1, { id: 'g1' });
      c.count('projectileHit', 1, { detail: 'arc:land' });
    },
  },
  {
    name: 'ranged-arc-blast',
    description: 'An arc shot flies over a near enemy, lands at its range and its blast strikes every enemy it overlaps, pushing each away from the centre.',
    covers: ['arc', 'blast'],
    level: rangeLevel([grunt('near', 4.5, 5.5), grunt('centre', 8.5, 5.5), grunt('side', 8.5, 6.5, 5), grunt('out', 8.5, 7.9)]),
    loadout: loadoutWith(WEAPONS.arc),
    takes: [T(shooter())],
    check: (c) => {
      c.count('hit', 0, { id: 'near' });
      c.count('kill', 1, { id: 'centre' });
      c.count('hit', 1, { id: 'side' });
      c.count('hit', 0, { id: 'out' });
      c.need(c.last().enemies.find((e) => e.id === 'side')!.y > 7, 'side pushed away');
    },
  },
  {
    name: 'ranged-arc-min-range',
    description: 'A short arc shot never lands closer than its minRange.',
    covers: ['arc', 'minRange'],
    level: rangeLevel([]),
    loadout: loadoutWith({ ...WEAPONS.arc, range: 2, minRange: 4 }),
    takes: [T(shooter())],
    check: (c) => c.need(Math.abs(c.ev('projectileHit', { detail: 'arc:land' })[0]?.x - 6.5) < 1e-4, 'lands at 4 tiles'),
  },
  {
    name: 'ranged-burst-fan',
    description: 'A burst fans five pellets across 40°; pellets reach enemies on the fan’s edges but fizzle before a far one.',
    covers: ['burst', 'WEAPON-01'],
    level: rangeLevel([
      grunt('up', 2.5 + 2.5 * Math.cos((20 * Math.PI) / 180), 5.5 - 2.5 * Math.sin((20 * Math.PI) / 180), 9),
      grunt('down', 2.5 + 2.5 * Math.cos((20 * Math.PI) / 180), 5.5 + 2.5 * Math.sin((20 * Math.PI) / 180), 9),
      grunt('far', 9.5, 5.5, 9),
    ]),
    loadout: loadoutWith({ ...WEAPONS.burst, range: 3.5 }),
    takes: [T(shooter())],
    check: (c) => {
      c.need(c.ev('hit', { id: 'up' }).length > 0 && c.ev('hit', { id: 'down' }).length > 0, 'edge pellets connect');
      c.count('hit', 0, { id: 'far' });
    },
  },
  {
    name: 'ranged-momentum-model',
    description: 'A ranged hit delivers def.impact through the melee damage / knockback / stagger arithmetic (efficiencies 1, the damage mod applies).',
    covers: ['WEAPON-03', 'momentum model'],
    level: rangeLevel([grunt('g1', 6.5, 5.5, 5)]),
    loadout: loadoutWith({ ...WEAPONS.pierce, pierce: 0, impact: 2.4 }, { mods: { damage: 1.5 }, melee: { damageEff: 3, knockbackEff: 3 } }),
    takes: [T(shooter())],
    check: (c) => {
      c.need(c.ev('hit', { id: 'g1' })[0]?.power === 2.4, 'impact 2.4');
      c.need(c.last().enemies[0].hp === 2, 'floor(2.4 × 1.5) = 3 damage');
      c.count('enemyStagger', 1, { id: 'g1' });
    },
  },
  {
    name: 'ranged-door-blocks-straight-shot',
    description: 'A closed door stops a straight shot.',
    covers: ['NEW-05', 'doors'],
    level: rangeLevel([{ kind: 'door', id: 'd1', cells: [{ c: 5, r: 5 }], openWhen: { const: false } }, grunt('g1', 8.5, 5.5)], DOORWAY_MAP),
    loadout: loadoutWith(WEAPONS.pierce),
    takes: [T(shooter())],
    check: (c) => c.count('hit', 0, { id: 'g1' }),
  },
  {
    name: 'ranged-reverse-pass-fires-again',
    description: 'A reverse tape fires again on every pass with the recorded direction, and each shot that arrives hurts again.',
    covers: ['PLAY-06', 'reverse'],
    level: rangeLevel([grunt('g1', 9.5, 5.5, 9)]),
    loadout: loadoutWith({ archetype: 'pierce', speed: 20, range: 12, pierce: 0, turnRate: 0 }),
    takes: [T(pathTape({ index: 0, speed: 1, endMode: 'reverse', ticks: 120, path: [{ tick: 0, x: 2.5, y: 5.5 }], events: [{ tick: 20, kind: 'ranged', dir: 0 }] }))],
    check: (c) => {
      const fires = c.ev('fire');
      const arrived = fires.filter((e) => e.sub + 120 < c.run.horizonSubs);
      c.need(fires.length >= 2 && fires.every((e) => e.dir === 0), 'fires again with the recorded direction');
      c.need(c.ev('hit', { id: 'g1' }).length === arrived.length && arrived.length >= 2, 'each arriving shot hurts again');
    },
  },
]);

add(() => {
  const missileLevel = (entities: EntityDef[], start = { x: 2.5, y: 5.5 }) => makeLevel({ speeds: [1], bars: 4, start, entities });
  const g = (id: string, x: number, y: number, hp = 5) => grunt(id, x, y, hp);
  const A = still(0, 2.5, 5.5, 480, 1, [{ tick: 60, kind: 'ranged', dir: 0 }]);
  const pusher = (index: 1 | 2, x: number, y: number, tick: number, dir: number) => still(index, x, y, 480, 1, [{ tick, kind: 'heavy', dir }]);
  const base = () => missileLevel([g('g1', 6.5, 3.5), g('g2', 7.5, 5.5)]);
  const locks = (c: Checker) => [...new Set(c.run.snapshots.flatMap((f) => f.projectiles.filter((p) => p.archetype === 'missile').map((p) => p.targetId)))].join();
  return [
    {
      name: 'missile-scenario-f-alone',
      description: 'Scenario F: alone, the missile locks the nearest enemy (g1) at launch and strikes it.',
      covers: ['Scenario F', 'TEST-22', 'NEW-03', 'missile'],
      level: base(),
      loadout: baseLoadout(),
      takes: [T(A)],
      check: (c) => {
        c.need(locks(c) === 'g1', `locks g1 (${locks(c)})`);
        c.count('hit', 1, { id: 'g1', tape: 0, detail: 'missile' });
      },
    },
    {
      name: 'missile-scenario-f-target-change',
      description: 'Scenario F: tape B knocks g2 closer before A’s launch; the same recorded launch locks g2 instead.',
      covers: ['Scenario F', 'TEST-22', 'missile target change'],
      level: base(),
      loadout: baseLoadout(),
      takes: [T(A), T(pusher(1, 8.6, 5.5, 10, Math.PI))],
      check: (c) => {
        c.need(locks(c) === 'g2', `locks g2 (${locks(c)})`);
        c.count('hit', 1, { id: 'g2', tape: 0, detail: 'missile' });
        c.count('hit', 0, { id: 'g1' });
      },
    },
    {
      name: 'missile-no-retarget',
      description: 'After launch the missile never retargets, even when another enemy is shoved nearer to it.',
      covers: ['MISSILE-03', 'NEW-03'],
      level: base(),
      loadout: baseLoadout(),
      takes: [T(A), T(pusher(2, 8.6, 5.5, 62, Math.PI))],
      check: (c) => {
        c.need(locks(c) === 'g1', `locks g1 (${locks(c)})`);
        c.count('hit', 1, { id: 'g1', tape: 0 });
        c.count('hit', 0, { id: 'g2', tape: 0 });
      },
    },
    {
      name: 'missile-target-dies-first',
      description: 'When its target dies first the missile flies straight on and still never switches.',
      covers: ['MISSILE-03', 'NEW-03'],
      level: missileLevel([g('g1', 6.5, 3.5, 1), g('g2', 9.5, 8.5)]),
      loadout: baseLoadout(),
      takes: [T(A), T(still(1, 7.4, 3.5, 480, 1, [{ tick: 70, kind: 'light', dir: Math.PI }]))],
      check: (c) => {
        c.need(c.ev('kill', { id: 'g1' })[0]?.tape === 1, 'B kills the target');
        c.need(locks(c) === 'g1', 'never switches');
        c.count('hit', 0, { id: 'g2', tape: 0 });
      },
    },
    {
      name: 'missile-turn-rate',
      description: 'A missile fired away from the only enemy turns round no faster than its turn rate and strikes it.',
      covers: ['MISSILE-02', 'missile'],
      // Detuned from the test (the grunt at y 5.62, not 5.5): dead behind the launcher, which way
      // the missile turns would be a tie.
      level: missileLevel([g('g1', 2.5, 5.62)], { x: 5.5, y: 5.5 }),
      loadout: baseLoadout(),
      takes: [T(still(0, 5.5, 5.5, 480, 1, [{ tick: 10, kind: 'ranged', dir: 0 }]))],
      check: (c) => c.count('hit', 1, { id: 'g1' }),
    },
    {
      name: 'missile-no-enemy-straight',
      description: 'With no enemy the missile flies straight along the recorded direction until it breaks on the wall.',
      covers: ['MISSILE-04', 'missile'],
      level: missileLevel([]),
      // Detuned from the test (2.45 tiles/s, not 2.5): the wall contact fell on a substep boundary.
      loadout: loadoutWith({ speed: 2.45 }),
      takes: [T(A)],
      check: (c) => c.need(c.run.snapshots.every((f) => f.projectiles.every((p) => p.targetId === undefined && p.dir === 0)), 'flies straight, no lock'),
    },
  ];
});

add(() => {
  const lv = makeLevel({ speeds: [1], bars: 4, start: { x: 2.5, y: 5.5 }, entities: [{ kind: 'enemy', id: 't1', type: 'turret', x: 9.5, y: 5.5, facing: Math.PI }] });
  const tape = pathTape({ index: 0, speed: 1, ticks: 480, path: [{ tick: 0, x: 2.5, y: 5.5 }, { tick: 40, x: 7.5, y: 5.5 }], events: [{ tick: 60, kind: 'ranged', dir: 0 }] });
  const doorLevel = (open: boolean) =>
    makeLevel({ speeds: [1], bars: 4, map: DOORWAY_MAP, start: { x: 2.5, y: 5.5 }, entities: [{ kind: 'door', id: 'd1', cells: [{ c: 5, r: 5 }], openWhen: { const: open } }, grunt('g1', 9.5, 5.5, 5)] });
  return [
    {
      name: 'ranged-ghost-launch-gating',
      description: 'The recording ghost’s missile flies and kills the turret in its own take; under playback the self dies at the same moment and its ghost fires nothing.',
      covers: ['GHOST-03', 'GHOST-05', 'launch gating'],
      level: lv,
      loadout: baseLoadout(),
      takes: [rec(0, 1, 'stop', script().aim(0, 480, 0).press(150, 'ranged', 0))],
      check: (c) => {
        const live = c.recEvents();
        c.need(c.ev('selfDeath', { tape: 0 }, live)[0]?.sub < 150 * 4, 'dies before the shot');
        c.count('fire', 1, { tape: 0 }, live);
        c.count('kill', 1, { id: 't1', tape: 0 }, live);
        c.count('fire', 0);
        c.count('kill', 0);
      },
    },
    {
      name: 'ranged-desynced-launches-nothing',
      description: 'A self desynced at a shut door launches nothing.',
      covers: ['DESYNC-07', 'launch gating'],
      level: doorLevel(false),
      loadout: baseLoadout(),
      takes: [T(tape)],
      check: (c) => {
        c.count('desync', 1, { tape: 0 });
        c.count('fire', 0);
      },
    },
    {
      name: 'ranged-synced-launches',
      description: 'Control: with the door open the same tape launches its missile.',
      covers: ['launch gating', 'missile'],
      level: doorLevel(true),
      loadout: baseLoadout(),
      takes: [T(tape)],
      check: (c) => c.count('fire', 1, { tape: 0 }),
    },
  ];
});

// ── abilities (every AbilityId) ──
add(() => {
  const lv = makeLevel({ speeds: [1], bars: 4, start: { x: 2.5, y: 5.5 } });
  const loadout = baseLoadout({ abilities: ['manualDesync'] });
  const tlv = makeLevel({ speeds: [1], bars: 4, start: { x: 2.5, y: 5.5 }, entities: [turretAt(8.5, 5.5)] });
  const map: MapRows = withMap((row, r) => (inner(r) ? row.slice(0, 5) + (r === 5 ? '.' : '#') + row.slice(6) : row));
  const dlv = makeLevel({ speeds: [1], bars: 4, map, start: { x: 2.5, y: 5.5 }, entities: [{ kind: 'door', id: 'd1', cells: [{ c: 5, r: 5 }], openWhen: { beat: { every: 16, from: 6, to: 16 } } }] });
  const paired = pathTape({ index: 0, speed: 1, ticks: 480, path: [{ tick: 0, x: 2.5, y: 5.5 }, { tick: 40, x: 7.5, y: 5.5 }], events: [{ tick: 60, kind: 'ability' }, { tick: 300, kind: 'ability' }] });
  return [
    {
      name: 'ability-manual-desync-record',
      description: 'manualDesync live: the first press desyncs in place and holds the spark; the second re-syncs the body where it is. Replayed, the released spark must catch up by ordinary spark rules.',
      covers: ['manualDesync', 'every ability', 'OPEN-11', 'record'],
      level: lv,
      loadout,
      takes: [rec(0, 1, 'stop', script().run(0, 120, 1, 0).press(20, 'ability').press(80, 'ability'), 160)],
      check: (c) => {
        const live = c.recEvents();
        c.need(JSON.stringify(c.ev('desync', { tape: 0 }, live).map((e) => [e.sub, e.detail])) === JSON.stringify([[80, 'manual desync']]), 'live desync on the first press');
        c.need(JSON.stringify(c.ev('resync', { tape: 0 }, live).map((e) => [e.sub, e.detail])) === JSON.stringify([[320, 'manual desync']]), 'live resync on the second press');
        const r = c.ev('resync', { tape: 0 });
        c.need(r.length === 1 && r[0].sub > 320 + 60, 'replayed spark has to catch up');
      },
    },
    {
      name: 'ability-manual-desync-turret',
      description: 'While voluntarily desynced the self is harmless and invulnerable: a turret never shoots at it.',
      covers: ['manualDesync', 'DESYNC-07'],
      level: tlv,
      loadout,
      takes: [T(still(0, 2.5, 5.5, 480, 1, [{ tick: 0, kind: 'ability' }, { tick: 30, kind: 'light', dir: 0 }]))],
      check: (c) => {
        c.count('enemyShot', 0);
        c.count('selfDeath', 0);
        c.count('swing', 0);
      },
    },
    {
      name: 'ability-manual-desync-paired',
      description: 'An involuntary desync (a beat-timed door) is held by the next press, so recorded on/off presses stay paired.',
      covers: ['manualDesync', 'beat signals'],
      level: dlv,
      loadout,
      takes: [T(paired)],
      check: (c) => {
        c.need(c.ev('desync', { tape: 0 }).map((e) => e.detail).join() === 'blocked by door d1', 'involuntary desync');
        const r = c.ev('resync', { tape: 0 });
        c.need(r.length === 1 && r[0].sub > 300 * 4, 'held until the second press');
      },
    },
    {
      name: 'desync-beat-door',
      description: 'Control: without the gear the same tape resyncs as soon as the beat-timed door opens.',
      covers: ['DESYNC-04', 'beat signals'],
      level: dlv,
      loadout: baseLoadout(),
      takes: [T(paired)],
      check: (c) => c.need(c.ev('resync', { tape: 0 })[0]?.sub < 300 * 4, 'resyncs when the door opens'),
    },
  ];
});

add(() => {
  const HALL: MapRows = ['#'.repeat(22), '#' + '.'.repeat(20) + '#', '#' + '.'.repeat(20) + '#', '#' + '.'.repeat(20) + '#', '#'.repeat(22)];
  const hall = (selfX: number) => makeLevel({ speeds: [1], bars: 2, map: HALL, start: { x: selfX, y: 2.5 }, entities: [turretAt(2.5, 2.5, { facing: 0 })] });
  return [
    {
      name: 'ability-low-profile',
      description: 'lowProfile: a self 9 tiles from a turret (reach 12) is read as 13.5 tiles away and never shot.',
      covers: ['lowProfile', 'every ability'],
      level: hall(11.5),
      loadout: baseLoadout({ abilities: ['lowProfile'] }),
      takes: [T(still(0, 11.5, 2.5, 240))],
      check: (c) => c.count('enemyShot', 0),
    },
    {
      name: 'ability-low-profile-control',
      description: 'Control: without lowProfile the same self is shot.',
      covers: ['lowProfile', 'turret'],
      level: hall(11.5),
      loadout: baseLoadout(),
      takes: [T(still(0, 11.5, 2.5, 240))],
      check: (c) => c.need(c.ev('enemyShot').length > 0, 'shot'),
    },
    {
      name: 'ability-loudmouth',
      description: 'loudmouth: a self 14 tiles from a turret is read as 10.5 tiles away and shot.',
      covers: ['loudmouth', 'every ability'],
      level: hall(16.5),
      loadout: baseLoadout({ abilities: ['loudmouth'] }),
      takes: [T(still(0, 16.5, 2.5, 240))],
      check: (c) => {
        c.need(c.ev('enemyShot').length > 0, 'shot');
        c.need(resolve(hall(16.5), [still(0, 16.5, 2.5, 240)]).events.every((e) => e.type !== 'enemyShot'), 'control: out of range without the gear');
      },
    },
  ];
});

add(() => ({
  name: 'ability-beat-sight',
  description: 'beatSight: upcoming enemy attack beats (8-beat look-ahead) are listed in every sampled snapshot (threatBeats) and match the beats the turret’s shots land on.',
  covers: ['beatSight', 'every ability'],
  level: makeLevel({ speeds: [1], bars: 4, start: { x: 2.5, y: 5.5 }, entities: [turretAt(8.5, 5.5, { beat: { every: 2, offset: 0 } } as Partial<EntityDef>)] }),
  loadout: baseLoadout({ abilities: ['beatSight'] }),
  takes: [T(still(0, 2.5, 5.5, 480))],
  check: (c) => {
    const s0 = c.run.snapshots[0].threatBeats ?? [];
    c.need(s0.length > 0 && s0[0] === 2, `forecast at beat 0 starts with beat 2 (${s0.join()})`);
    c.need(c.ev('enemyShot')[0]?.sub === 2 * SPB, 'the first shot lands on beat 2');
  },
}));

add(() => {
  const map: MapRows = withMap((row, r) => (inner(r) ? row.slice(0, 6) + '=' + row.slice(7) : row));
  const lv = makeLevel({ speeds: [1], bars: 2, map, start: { x: 5, y: 5.5 }, startFacing: 0 });
  const dodge = () => script().aim(0, 240, 0).press(0, 'dodge');
  const loadout = baseLoadout({ abilities: ['phaseDodge'] });
  const phased = recordTake({ level: lv, loadout, index: 0, speed: 1, script: dodge(), ticks: 40 }).tape;
  return [
    {
      name: 'ability-phase-dodge-record',
      description: 'phaseDodge: a dodge passes through a column of low barriers live and replays without desync.',
      covers: ['phaseDodge', 'every ability', 'record'],
      level: lv,
      loadout,
      takes: [rec(0, 1, 'stop', dodge(), 40)],
      check: (c) => {
        const r = c.run.recordings[0];
        c.need(r.snapshots[r.snapshots.length - 1].actors[0].x > 7.3, 'crossed the barrier live');
        c.count('desync', 0);
      },
    },
    {
      name: 'ability-phase-dodge-blocked',
      description: 'Without phaseDodge the same dodge is stopped by the barrier while recording.',
      covers: ['phaseDodge', 'dodge'],
      level: lv,
      loadout: baseLoadout(),
      takes: [rec(0, 1, 'stop', dodge(), 40)],
      check: (c) => {
        const r = c.run.recordings[0];
        c.need(r.snapshots[r.snapshots.length - 1].actors[0].x < 6, 'stopped at the barrier');
      },
    },
    {
      name: 'ability-phase-dodge-replayed-without-gear',
      description: 'The phased tape replayed without the gear cannot cross the barrier: it desyncs there.',
      covers: ['phaseDodge', 'DESYNC-01'],
      level: lv,
      loadout: baseLoadout(),
      takes: [T(phased)],
      check: (c) => c.count('desync', 1, { tape: 0 }),
    },
  ];
});

add(() => {
  const lv = makeLevel({ speeds: [1], bars: 2, start: { x: 2.5, y: 5.5 }, entities: [{ kind: 'enemy', id: 'g1', type: 'grunt', x: 3.3, y: 5.5, hp: 20, wakeWhen: SLEEP }] });
  const tape = pathTape({
    index: 0,
    speed: 1,
    ticks: 100,
    endMode: 'reverse',
    path: [{ tick: 0, x: 2.5, y: 5.5 }],
    events: [{ tick: 10, kind: 'dodge', dir: 0 }, { tick: 24, kind: 'light', dir: 0 }, { tick: 60, kind: 'light', dir: 0 }],
  });
  return {
    name: 'ability-slide-strike',
    description: 'slideStrike: a strike started straight out of a dodge carries extra momentum, only on a forward pass of a reverse tape.',
    covers: ['slideStrike', 'every ability', 'reverse'],
    level: lv,
    loadout: baseLoadout({ abilities: ['slideStrike'] }),
    takes: [T(tape)],
    check: (c) => {
      const p = c.ev('swing').map((e) => +e.power!.toFixed(6));
      const slide = +(1.2 * 1.5).toFixed(6);
      c.need(JSON.stringify(p.slice(0, 5)) === JSON.stringify([slide, 1.2, 1.2, 1.2, slide]), `forward-pass slide strikes only (${p.join()})`);
    },
  };
});

add(() => {
  const lv = makeLevel({ speeds: [1], bars: 4, start: { x: 2.5, y: 5.5 }, entities: [turretAt(6.5, 5.5, { beat: { every: 8, offset: 0 } } as Partial<EntityDef>)] });
  const deathEv = resolve(lv, [still(0, 2.5, 5.5, 480)]).events.find((e) => e.type === 'selfDeath' && e.tape === 0);
  if (!deathEv) throw new Error('parry scenario: the standing self should be shot');
  const heavyTick = Math.round((deathEv.sub - 24) / 4) - 16;
  const swinger = still(0, 2.5, 5.5, 480, 1, [{ tick: heavyTick, kind: 'heavy', dir: 0 }]);
  return [
    {
      name: 'ability-parry',
      description: 'parry: a heavy swing turns an enemy shot inside its arc back at the shooter; the reflected bolt destroys the turret.',
      covers: ['parry', 'every ability'],
      level: lv,
      loadout: baseLoadout({ abilities: ['parry'] }),
      takes: [T(swinger)],
      check: (c) => {
        c.count('selfDeath', 0);
        c.need(JSON.stringify(c.ev('projectileHit', { detail: 'parry' }).map((e) => [e.tape, e.id])) === JSON.stringify([[0, 't1']]), 'parried');
        c.need(JSON.stringify(c.ev('kill', { id: 't1' }).map((e) => [e.tape, e.detail])) === JSON.stringify([[0, 'bolt']]), 'reflected bolt kills the turret');
        c.win(true);
      },
    },
    {
      name: 'ability-parry-control',
      description: 'Control: without the gear the same swing does nothing to the shot, which kills.',
      covers: ['parry', 'turret'],
      level: lv,
      loadout: baseLoadout(),
      takes: [T(swinger)],
      check: (c) => c.need(c.ev('selfDeath', { tape: 0 }).map((e) => e.sub).join() === String(deathEv.sub), 'dies as without the swing'),
    },
  ];
});

add(() => {
  const lv0 = makeLevel({ speeds: [1], bars: 2, start: { x: 8.5, y: 5.5 }, startFacing: Math.PI });
  const probe = recordTake({ level: lv0, index: 0, speed: 1, script: script().aim(0, 240, Math.PI).press(0, 'dodge').press(14, 'light', Math.PI), ticks: 30 });
  const at = probe.frames[20].actors[0];
  const lv = makeLevel({ ...lv0, entities: [{ kind: 'enemy', id: 'g1', type: 'grunt', x: at.x - 0.8, y: at.y, wakeWhen: SLEEP }] });
  const s = () => script().aim(0, 240, Math.PI).press(0, 'dodge').press(14, 'light', Math.PI).press(26, 'dodge');
  return [
    {
      name: 'ability-kill-refresh',
      description: 'killRefresh: a melee kill by the live self refunds its dodge cooldown, so the second dodge press (tick 26) is accepted.',
      covers: ['killRefresh', 'every ability', 'record'],
      level: lv,
      loadout: baseLoadout({ abilities: ['killRefresh'] }),
      takes: [rec(0, 1, 'stop', s(), 60)],
      check: (c) => {
        c.count('kill', 1, { id: 'g1' }, c.recEvents());
        c.need(c.run.recordings[0].tape.events.filter((e) => e.kind === 'dodge').map((e) => e.tick).join() === '0,26', 'second dodge accepted');
      },
    },
    {
      name: 'ability-kill-refresh-control',
      description: 'Control: without the gear the second dodge press falls inside the cooldown and is dropped.',
      covers: ['killRefresh', 'dodge cooldown'],
      level: lv,
      loadout: baseLoadout(),
      takes: [rec(0, 1, 'stop', s(), 60)],
      check: (c) => c.need(c.run.recordings[0].tape.events.filter((e) => e.kind === 'dodge').map((e) => e.tick).join() === '0', 'second dodge dropped'),
    },
  ];
});

// ── catalogue gear (data/gear.json ids; exercises loadout resolution) ──
for (const id of ['mixtape_rocket', 'needle_rail', 'bleed_emitter', 'bass_drop', 'static_spray']) {
  add(() => {
    const { loadout, gear } = catalogue({ ranged: id });
    return {
      name: `gear-ranged-${id.replace(/_/g, '-')}`,
      description: `Catalogue ranged weapon ${id} (${loadout.ranged.archetype}): the live self steps forward and fires twice down a room of sleeping grunts; recorded from inputs, then resolved.`,
      covers: ['WEAPON-01..03', `every ranged archetype (${loadout.ranged.archetype})`, 'catalogue gear'],
      level: rangeLevel([grunt('g1', 6.5, 5.5, 3), grunt('g2', 10.0, 5.2, 3), grunt('g3', 9.6, 7.6, 3)]),
      loadout,
      gear,
      takes: [rec(0, 1, 'stop', script().run(0, 12, 1, 0).aim(12, 480, 0).press(20, 'ranged', 0).press(200, 'ranged', 0.35))],
      check: (c) => {
        c.need(c.ev('fire').length === 2 && c.ev('fire').every((e) => e.detail === loadout.ranged.archetype), 'two launches of the archetype');
        c.need(c.ev('hit').length > 0, 'something is hit');
      },
    };
  });
}

for (const id of ['splice_blade', 'stylus_shiv', 'amp_sledge', 'reel_lash', 'speaker_knuckles', 'vinyl_glaive']) {
  add(() => {
    const { loadout, gear } = catalogue({ melee: id });
    return {
      name: `gear-melee-${id.replace(/_/g, '-')}`,
      description: `Catalogue melee weapon ${id}: the live self walks up to a tough sleeping grunt and swings light and heavy, standing and running; recorded from inputs, then resolved.`,
      covers: ['WEAPON-04', 'COMBAT-01..03', 'catalogue gear'],
      level: makeLevel({ speeds: [1], bars: 3, start: { x: 2.5, y: 5.5 }, entities: [grunt('g1', 6.2, 5.5, 20)] }),
      loadout,
      gear,
      takes: [
        rec(
          0,
          1,
          'stop',
          script().run(0, 40, 1, 0).aim(40, 360, 0).press(50, 'light', 0).press(90, 'heavy', 0).run(140, 150, -1, 0).run(170, 205, 1, 0).press(196, 'heavy', 0).press(260, 'light', 0),
        ),
      ],
      check: (c) => {
        c.need(c.ev('swing').length === 4, `four swings (${c.ev('swing').length})`);
        c.need(c.ev('hit', { id: 'g1' }).length > 0, 'the grunt is hit');
      },
    };
  });
}

add(() => {
  const { loadout, gear } = catalogue({ helmet: 'rabbit_ears', top: 'ballast_puffer', pants: 'flywheel_cargos', shoes: 'grip_sprinters', ranged: 'needle_rail' });
  return {
    name: 'gear-apparel-mods',
    description: 'Apparel stat mods combined (moveSpeed, accel, momentumRetention, approachBonus, meleeImpact, dodgeIframes, sparkSpeed): the live self runs, turns, dodges and lands a running heavy on a grunt.',
    covers: ['GEAR-01..03', 'APPAREL-01..03', 'catalogue gear', 'combineMods'],
    level: makeLevel({ speeds: [1, 2], bars: 2, start: { x: 2.5, y: 5.5 }, entities: [grunt('g1', 5.9, 2.0, 6)] }),
    loadout,
    gear,
    takes: [rec(0, 2, 'stop', script().run(0, 20, 1, 0).run(20, 30, 0, -1).press(32, 'dodge', 0).run(34, 70, 1, -0.2).press(52, 'heavy', 0).run(90, 120, -1, 1))],
    check: (c) => {
      const hit = c.ev('hit', { id: 'g1', tape: 0 })[0];
      c.need(!!hit && hit.power! > 1.8 * 1.25 * 2, 'running 2x heavy lands with the gear momentum');
      c.count('dodge', 1);
    },
  };
});

add(() => {
  const { loadout, gear } = catalogue({ top: 'dropout_jacket', shoes: 'slick_sliders', helmet: 'click_visor' });
  const lv = makeLevel({ speeds: [1], bars: 2, start: { x: 2.5, y: 5.5 }, entities: [grunt('g1', 6.0, 5.5, 9), turretAt(10.5, 2.5, { beat: { every: 4, offset: 3 } } as Partial<EntityDef>)] });
  return {
    name: 'gear-abilities-catalogue',
    description: 'Catalogue ability gear (dropout_jacket manualDesync, slick_sliders slideStrike, click_visor beatSight): the live self dodges into a slide strike, then desyncs and re-syncs on demand while a turret looks for it.',
    covers: ['manualDesync', 'slideStrike', 'beatSight', 'catalogue gear'],
    level: lv,
    loadout,
    gear,
    takes: [rec(0, 1, 'stop', script().run(0, 10, 1, 0).aim(10, 240, 0).press(12, 'dodge', 0).press(24, 'light', 0).press(70, 'ability').run(80, 110, 0, 1).press(140, 'ability'))],
    check: (c) => {
      const live = c.recEvents();
      c.need(c.ev('swing', {}, live)[0]?.power! > 1.0 + 1e-6, 'slide strike adds momentum');
      c.count('desync', 1, { detail: 'manual desync' }, live);
      c.count('resync', 1, { detail: 'manual desync' }, live);
      c.need(c.run.snapshots.every((f) => Array.isArray(f.threatBeats)), 'beatSight forecasts in every snapshot');
    },
  };
});

// ── traps and automated machinery (docs/TRAPS.md; prototype/tests/core/traps/*.test.ts) ──
// Every scenario is a prototype trap test restated (some combine several tests in one room). The
// room is the 12x10 open room at 120 bpm: 120 substeps per beat, a window `from: n` turns true in
// substep n*120 - 1.

const trapRoom = (entities: EntityDef[], extra: Partial<LevelDef> = {}): LevelDef =>
  makeLevel({ speeds: [1], bars: 2, start: { x: 1.5, y: 1.5 }, entities, ...extra });
const beatW = (every: number, from: number, to: number) => ({ beat: { every, from, to } });
const ALWAYS = { const: true } as const;
const NEVER = { const: false } as const;
const cellsOf = (...pairs: [number, number][]) => pairs.map(([c, r]) => ({ c, r }));
const sleeper = (id: string, type: EnemyDef['type'], x: number, y: number, extra: Partial<EnemyDef> = {}): EntityDef =>
  ({ kind: 'enemy', id, type, x, y, wakeWhen: SLEEP, ...extra }) as EntityDef;
const standAt = (index: TapeIndex, x: number, y: number, ticks = 240): Tape => still(index, x, y, ticks);
const trapEv = (c: Checker, id: string, list?: SimEvent[]): [number, string][] =>
  c.ev(TRAP_EVENT, { id }, list).map((e) => [e.sub, e.detail ?? '']);
const sameList = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b);
const toggles = (index: TapeIndex, x: number, y: number, ...ticks: number[]): Tape =>
  still(index, x, y, 240, 1, ticks.map((tick) => ({ tick, kind: 'interact' as const })));
const wallCrusherCells = (c: number) => [1, 2, 3, 4, 5, 6, 7, 8].map((r) => ({ c, r }));

add(() => [
  {
    name: 'trap-spikes',
    description: 'Spikes on a beat window kill a playback self standing on a raised cell (and only there), publish their id to a door and telegraph a beat ahead; always-raised spikes kill a grunt on contact, hit a brute once per beat and clang off a shielder.',
    covers: ['TRAPS spikes', 'trap signals', 'trap telegraph', 'HAZARD_RETICK_BEATS', 'shielder immune to traps'],
    level: trapRoom([
      { kind: 'spikes', id: 'sp', cells: cellsOf([5, 5], [6, 5]), upWhen: beatW(4, 1, 2) },
      { kind: 'door', id: 'd', cells: cellsOf([9, 8]), openWhen: { sig: 'sp' } },
      { kind: 'spikes', id: 'sp2', cells: cellsOf([3, 7], [4, 7], [6, 7]), upWhen: ALWAYS },
      sleeper('g', 'grunt', 3.5, 7.5),
      sleeper('b', 'brute', 4.5, 7.5),
      sleeper('s', 'shielder', 6.5, 7.5),
    ] as EntityDef[]),
    loadout: baseLoadout(),
    takes: [T(standAt(0, 5.5, 5.5)), T(standAt(1, 7.2, 5.5))],
    check: (c) => {
      c.need(sameList(c.ev('selfDeath').map((e) => [e.tape, e.sub, e.detail]), [[0, 119, 'skewered by spikes sp']]), 'tape 0 skewered at 119');
      c.need(sameList(trapEv(c, 'sp').slice(0, 3), [[0, 'spikes:warn'], [119, 'spikes:up'], [239, 'spikes:down']]), 'spikes timeline');
      c.need(sameList(c.ev('kill').map((e) => [e.id, e.sub, e.detail]), [['g', 0, 'spikes'], ['b', 240, 'spikes']]), 'grunt and brute killed by the spikes');
      c.need(c.ev('clang', { id: 's' }).length > 0, 'shielder clangs');
      c.need(c.ev('door', { id: 'd', detail: 'open' })[0]?.sub === 137, 'door driven by the spikes signal');
    },
  },
  {
    name: 'trap-spikes-dodge',
    description: 'A recorded dodge carries a playback self across a quarter-beat spike window; the same path one row down without the dodge dies inside the window.',
    covers: ['TRAPS spikes', 'dodge i-frames vs traps'],
    level: trapRoom([{ kind: 'spikes', id: 'sp', cells: cellsOf([5, 5], [6, 5], [5, 6], [6, 6]), upWhen: beatW(8, 1, 1.25) }] as EntityDef[]),
    loadout: baseLoadout(),
    takes: [
      T(pathTape({ index: 0, speed: 1, ticks: 240, path: [{ tick: 0, x: 4.4, y: 5.5 }, { tick: 28, x: 4.4, y: 5.5 }, { tick: 42, x: 7.4, y: 5.5 }], events: [{ tick: 28, kind: 'dodge' }] })),
      T(pathTape({ index: 1, speed: 1, ticks: 240, path: [{ tick: 0, x: 4.4, y: 6.5 }, { tick: 28, x: 4.4, y: 6.5 }, { tick: 42, x: 7.4, y: 6.5 }] })),
    ],
    check: (c) => {
      const d = c.ev('selfDeath');
      c.need(d.length === 1 && d[0].tape === 1 && d[0].sub >= 119 && d[0].sub < 149, 'only the walker dies, inside the window');
    },
  },
  {
    name: 'trap-spikes-live',
    description: 'Raised spikes kill the live self once; the recording ghost then walks on over them freely.',
    covers: ['TRAPS spikes', 'record', 'recGhost'],
    level: trapRoom([{ kind: 'spikes', id: 'sp', cells: cellsOf([5, 5], [6, 5]), upWhen: ALWAYS }] as EntityDef[], { start: { x: 3.5, y: 5.5 } }),
    loadout: baseLoadout(),
    takes: [rec(0, 1, 'stop', script().run(0, 200, 1, 0))],
    check: (c) => {
      c.need(sameList(c.ev('selfDeath', {}, c.recEvents()).map((e) => e.detail), ['skewered by spikes sp']), 'one death while recording');
      const a = c.run.recordings[0].snapshots[c.run.recordings[0].snapshots.length - 1].actors[0];
      c.need(a.life === 'recGhost' && a.x > 8, 'the recording ghost walks on');
    },
  },
  {
    name: 'trap-crusher-stroke',
    description: 'A piston across the room strokes on its beat window: it crushes the self and the enemies on its cells (drone included), pushes a 5 hp survivor out, only walls off a self beside it, and desyncs a self that dodged the stroke on a cell.',
    covers: ['TRAPS crusher', 'crusher push-out', 'dodge i-frames vs traps', 'desync blocked by crusher'],
    level: trapRoom([
      { kind: 'crusher', id: 'cr', cells: wallCrusherCells(5), extendWhen: beatW(8, 1, 2) },
      sleeper('g', 'grunt', 5.5, 2.5),
      sleeper('dr', 'drone', 5.5, 6.5),
      sleeper('tough', 'grunt', 5.4, 7.5, { hp: 5 }),
    ] as EntityDef[]),
    loadout: baseLoadout(),
    takes: [
      T(standAt(0, 5.5, 4.5)),
      T(standAt(1, 4.5, 4.5)),
      // Detuned off the cell's centre (x 5.42) so the spark's nearest free side is not a tie.
      T(pathTape({ index: 2, speed: 1, ticks: 240, path: [{ tick: 0, x: 5.42, y: 5.5 }], events: [{ tick: 28, kind: 'dodge' }] })),
    ],
    check: (c) => {
      c.need(sameList(c.ev('selfDeath').map((e) => [e.tape, e.sub, e.detail]), [[0, 119, 'crushed by crusher cr']]), 'tape 0 crushed');
      c.need(sameList(c.ev('desync').map((e) => [e.tape, e.sub, e.detail]), [[2, 120, 'blocked by crusher cr']]), 'the dodger desyncs on the solid piston');
      c.need(sameList(c.ev('kill').map((e) => [e.id, e.sub, e.detail]), [['g', 119, 'crusher'], ['dr', 119, 'crusher']]), 'grunt and drone crushed');
      const tough = c.last().enemies.find((e) => e.id === 'tough')!;
      c.need(tough.alive && tough.hp === 2 && tough.x <= 5 - 0.32 + 1e-6, 'tough grunt pushed out');
      // Struck: tape 0, the dodger (vulnerable; its i-frames are judged when the hit applies), g, dr, tough.
      c.need(c.ev(TRAP_EVENT, { detail: 'crusher:slam' })[0]?.power === 5, 'slam power counts the bodies struck');
    },
  },
  {
    name: 'trap-crusher-desync-recover',
    description: 'A playback self walking into an extended piston desyncs ("blocked by crusher cr"); its spark waits at the face and resyncs once the retract completes.',
    covers: ['TRAPS crusher', 'desync blocked by crusher', 'DESYNC-02..05'],
    level: trapRoom([{ kind: 'crusher', id: 'cr', cells: wallCrusherCells(5), extendWhen: beatW(8, 0.5, 3) }] as EntityDef[]),
    loadout: baseLoadout(),
    // Detuned from the test (ends at 8.43 on tick 118): the test's route puts a footstep stride exactly
    // on a substep boundary.
    takes: [T(pathTape({ index: 0, speed: 1, ticks: 240, path: [{ tick: 0, x: 2.5, y: 5.5 }, { tick: 118, x: 8.43, y: 5.5 }] }))],
    check: (c) => {
      const d = c.ev('desync', { tape: 0 });
      const open = c.ev(TRAP_EVENT, { id: 'cr', detail: 'crusher:open' })[0];
      const rs = c.ev('resync', { tape: 0 });
      c.need(d.length === 1 && d[0].detail === 'blocked by crusher cr', 'desync names the crusher');
      c.need(!!open && open.sub === 419 && rs.length === 1 && rs[0].sub > open.sub, 'resyncs after the piston opens');
    },
  },
  {
    name: 'trap-crusher-live-hold',
    description: 'The live self standing in a piston lane is crushed on the stroke and its body is pushed out; the signal returns mid-retract, so the piston re-extends without a second stroke.',
    covers: ['TRAPS crusher', 'crusher:hold', 'record'],
    // Detuned off the cell's centre (x 5.4): dead centre, the push-out side is a tie.
    level: trapRoom([{ kind: 'crusher', id: 'cr', cells: wallCrusherCells(5), extendWhen: { or: [beatW(8, 1, 2), beatW(8, 2.125, 3)] } }] as EntityDef[], { start: { x: 5.4, y: 4.5 } }),
    loadout: baseLoadout(),
    takes: [rec(0, 1, 'stop', script())],
    check: (c) => {
      const live = c.recEvents();
      c.need(sameList(c.ev('selfDeath', {}, live).map((e) => e.detail), ['crushed by crusher cr']), 'crushed');
      c.need(sameList(trapEv(c, 'cr', live).filter(([, d]) => d !== 'crusher:warn'), [[119, 'crusher:slam'], [239, 'crusher:retract'], [254, 'crusher:hold'], [359, 'crusher:retract'], [419, 'crusher:open']]), 'stroke, hold, retract');
      const a = c.run.recordings[0].snapshots[c.run.recordings[0].snapshots.length - 1].actors[0];
      c.need(a.life === 'recGhost' && a.x <= 5 - 0.3 + 1e-6, 'the body was pushed out');
    },
  },
  {
    name: 'trap-flame',
    description: 'A flame jet is cut short by a closed door and burns the self behind it the moment another tape opens the door; a second jet stops at an extended crusher and passes a low barrier; a third burns a turret, a drone and a brute once per beat.',
    covers: ['TRAPS flame', 'doors are shields', 'flame reach', 'HAZARD_RETICK_BEATS'],
    level: trapRoom(
      [
        { kind: 'flame', id: 'fl', c: 0, r: 5, dir: 'e', range: 8, onWhen: ALWAYS },
        { kind: 'switch', id: 'sw', x: 2.5, y: 2.5 },
        { kind: 'door', id: 'door', cells: cellsOf([5, 5]), openWhen: { sig: 'sw' } },
        { kind: 'flame', id: 'fl2', c: 0, r: 1, dir: 'e', range: 8, onWhen: ALWAYS },
        { kind: 'crusher', id: 'cr', cells: cellsOf([7, 1]), extendWhen: beatW(8, 2, 4) },
        { kind: 'flame', id: 'fl3', c: 0, r: 7, dir: 'e', range: 8, onWhen: ALWAYS },
        sleeper('dr', 'drone', 2.5, 7.5),
        sleeper('b', 'brute', 4.5, 7.5),
        sleeper('t', 'turret', 6.5, 7.5),
      ] as EntityDef[],
      { map: OPEN_ROOM.map((row, r) => (r === 1 ? row.slice(0, 3) + '=' + row.slice(4) : row)) },
    ),
    loadout: baseLoadout(),
    takes: [T(standAt(0, 7.5, 5.5)), T(pathTape({ index: 1, speed: 1, ticks: 240, path: [{ tick: 0, x: 2.5, y: 3.2 }], events: [{ tick: 150, kind: 'interact' }] }))],
    check: (c) => {
      const open = c.ev('door', { id: 'door', detail: 'open' })[0];
      const death = c.ev('selfDeath', { tape: 0 });
      c.need(!!open && death.length === 1 && death[0].sub === open.sub, 'burned the substep the door opens');
      c.need(sameList(c.ev('kill').map((e) => [e.id, e.sub, e.detail]), [['t', 0, 'flame'], ['dr', 120, 'flame'], ['b', 240, 'flame']]), 'turret, drone, brute burned');
      c.need(c.run.snapshots.find((f) => f.sub === 300)!.mechs.find((m) => m.id === 'fl2')!.reach === 6, 'the crusher cuts the second jet');
    },
  },
  {
    name: 'trap-conveyor',
    description: 'Belts carry a sleeping grunt in master time and reverse on a switch (publishing <id>.rev to a door); turrets, drones and playback selves are never carried; a body is stopped by a wall, not pushed through it; a belt with runWhen stops and starts.',
    covers: ['TRAPS conveyor', '<id>.rev', 'trap signals'],
    level: trapRoom([
      { kind: 'conveyor', id: 'belt', cells: cellsOf([3, 5], [4, 5], [5, 5], [6, 5]), dir: 'e', speed: 2, reverseWhen: { sig: 'sw' } },
      { kind: 'switch', id: 'sw', x: 2.5, y: 2.5 },
      { kind: 'door', id: 'd', cells: cellsOf([9, 8]), openWhen: { sig: 'belt.rev' } },
      // Detuned off x.5 (3.53, 7.53): from x.5 the belt lands a body exactly on its last cell's edge.
      sleeper('g', 'grunt', 3.53, 5.5),
      { kind: 'conveyor', id: 'belt2', cells: cellsOf([3, 7], [4, 7], [5, 7], [6, 7]), dir: 'w', speed: 2 },
      sleeper('t', 'turret', 4.5, 7.5),
      sleeper('dr', 'drone', 5.5, 7.5),
      { kind: 'conveyor', id: 'belt3', cells: cellsOf([8, 3], [9, 3], [10, 3]), dir: 'e', speed: 2 },
      sleeper('g2', 'grunt', 8.5, 3.5),
      { kind: 'conveyor', id: 'belt4', cells: cellsOf([7, 1], [8, 1], [9, 1]), dir: 'e', speed: 2, runWhen: beatW(4, 0, 1) },
      sleeper('g3', 'grunt', 7.53, 1.5),
    ] as EntityDef[]),
    loadout: baseLoadout(),
    takes: [T(standAt(0, 6.5, 7.5)), T(toggles(1, 2.5, 3.2, 30))],
    check: (c) => {
      c.need(sameList(trapEv(c, 'belt'), [[120, 'conveyor:reverse']]), 'reverses at 120');
      const at240 = c.run.snapshots.find((f) => f.sub === 240)!;
      c.need(Math.abs(at240.enemies.find((e) => e.id === 'g')!.x - 3.53) < 1e-5, 'carried east then back west');
      const end = c.last();
      c.need(end.enemies.find((e) => e.id === 't')!.x === 4.5 && end.enemies.find((e) => e.id === 'dr')!.x === 5.5, 'turret and drone not carried');
      c.need(end.actors[0].x === 6.5 && end.actors[0].synced, 'playback self not carried');
      const g2 = end.enemies.find((e) => e.id === 'g2')!;
      c.need(g2.x <= 11 - 0.32 + 1e-6 && g2.x > 10.6, 'stopped by the wall');
      c.need(c.ev('door', { id: 'd', detail: 'open' }).length === 1, 'door reads belt.rev');
    },
  },
  {
    name: 'trap-conveyor-dart-drift',
    description: 'A dart crossing a belt that runs across its lane drifts sideways with the belt without turning.',
    covers: ['TRAPS conveyor', 'TRAPS dart', 'floor-height projectiles drift'],
    level: trapRoom([
      { kind: 'conveyor', id: 'belt', cells: cellsOf([4, 5], [5, 5], [6, 5], [7, 5]), dir: 's', speed: 2 },
      { kind: 'dart', id: 'dl', c: 0, r: 5, dir: 'e', every: 8, speed: 4 },
    ] as EntityDef[]),
    loadout: baseLoadout(),
    takes: [T(standAt(0, 2.5, 2.5))],
    check: (c) => {
      const p = c.run.snapshots.find((f) => f.sub === 300)!.projectiles[0];
      c.need(!!p && p.y > 5.8 && p.dir === 0, 'drifted south, heading unchanged');
    },
  },
  {
    name: 'trap-conveyor-live-ride',
    description: 'The live self is carried by a belt by what the world moves per local tick (1x take, then a 2x take after a later tape reversed the belt); the rides are baked into the tapes and replay unchanged.',
    covers: ['TRAPS conveyor', 'liveCarry', 'PlayerController.displace', 'record', 'TIME-02'],
    level: trapRoom(
      [
        { kind: 'conveyor', id: 'belt', cells: cellsOf([3, 5], [4, 5], [5, 5], [6, 5]), dir: 'e', speed: 2, reverseWhen: { sig: 'sw' } },
        { kind: 'switch', id: 'sw', x: 2.5, y: 2.5 },
      ] as EntityDef[],
      // Detuned off x.5 (3.51): from x.5 the ride lands exactly on the belt's last edge.
      { start: { x: 3.51, y: 5.5 }, speeds: [1, 2] },
    ),
    loadout: baseLoadout(),
    takes: [rec(0, 1, 'stop', script()), T(toggles(1, 2.5, 3.2, 10)), rec(2, 2, 'stop', script().run(100, 140, 0, -1))],
    check: (c) => {
      const t0 = c.run.recordings[0].tape;
      c.need(Math.abs(t0.pos[30 * 2] - 4.51) < 1e-4 && t0.pos[240 * 2] >= 7, 'the 1x ride');
      const t2 = c.run.recordings[1].tape;
      // East until the switch flips (substep 40 = 2x tick 20), then west at 1/60 tile per 2x tick until
      // its centre leaves the belt's first cell (x < 3).
      c.need(Math.abs(t2.pos[20 * 2] - (3.51 + 40 / 120)) < 1e-4, 'the 2x take rides east at half speed');
      c.need(t2.pos[100 * 2] < 3 && t2.pos[100 * 2] > 3 - 1 / 60 - 1e-6, 'then west off the reversed belt');
      c.count('desync', 0);
    },
  },
  {
    name: 'trap-bumper',
    description: 'Bumpers fire once per rising edge: a grunt is thrown the full power with real knockback, a brute by power / mass, a turret and a recorded self not at all, and a grunt thrown into a wall staggers.',
    covers: ['TRAPS bumper', 'MOM-05', 'MOM-06', 'wall slam stagger'],
    level: trapRoom(
      [
        { kind: 'bumper', id: 'bm', c: 4, r: 5, dir: 'e', power: 3, fireWhen: beatW(8, 1, 2) },
        sleeper('g', 'grunt', 4.5, 5.5),
        { kind: 'bumper', id: 'bm2', c: 4, r: 3, dir: 'e', fireWhen: beatW(8, 1, 2) },
        sleeper('b', 'brute', 4.5, 3.5),
        { kind: 'bumper', id: 'bm3', c: 4, r: 7, dir: 'e', fireWhen: beatW(8, 1, 2) },
        sleeper('t', 'turret', 4.5, 7.5),
        { kind: 'bumper', id: 'bm4', c: 2, r: 8, dir: 'e', fireWhen: beatW(8, 1, 2) },
        { kind: 'bumper', id: 'bm5', c: 9, r: 1, dir: 'e', power: 3, fireWhen: beatW(8, 1, 2) },
        sleeper('g2', 'grunt', 9.5, 1.5),
      ] as EntityDef[],
      { bars: 4 },
    ),
    loadout: baseLoadout(),
    takes: [T(standAt(0, 2.5, 8.5, 480))],
    check: (c) => {
      const f = c.run.snapshots.find((s) => s.sub === 240)!;
      c.need(Math.abs(f.enemies.find((e) => e.id === 'g')!.x - 7.5) < 1e-5, 'grunt thrown 3 tiles');
      c.need(Math.abs(f.enemies.find((e) => e.id === 'b')!.x - 5.5) < 1e-5, 'brute thrown 1 tile');
      c.need(f.enemies.find((e) => e.id === 't')!.x === 4.5, 'turret stays');
      c.need(c.last().actors[0].x === 2.5, 'recorded self stays');
      c.need(c.ev('enemyStagger', { id: 'g2' }).length > 0, 'wall slam staggers');
      c.need(c.ev(TRAP_EVENT, { id: 'bm', detail: 'bumper:fire' }).map((e) => e.sub).join() === '119,1079', 'fires on each rising edge');
    },
  },
  {
    name: 'trap-bumper-live',
    description: 'A bumper throws the live self (1x take, then a 2x take standing on the same plate); the flights are recorded as ordinary movement and replay without the plate.',
    covers: ['TRAPS bumper', 'liveCarry', 'BUMPER_FLIGHT_SUBS', 'record', 'TIME-02'],
    level: trapRoom([{ kind: 'bumper', id: 'bm', c: 4, r: 5, dir: 'e', power: 3, fireWhen: beatW(8, 1, 2) }] as EntityDef[], { start: { x: 4.5, y: 5.5 }, speeds: [1, 2] }),
    loadout: baseLoadout(),
    takes: [rec(0, 1, 'stop', script()), rec(1, 2, 'stop', script().run(100, 130, 0, 1))],
    check: (c) => {
      const t0 = c.run.recordings[0].tape;
      c.need(Math.abs(t0.pos[45 * 2] - 7.5) < 1e-4, 'thrown 3 tiles over 11 local ticks');
      c.need(c.ev(TRAP_EVENT, { detail: 'bumper:fire' }, c.recEvents(1))[0]?.power === 1, 'the 2x live self is launched');
      c.need(c.ev(TRAP_EVENT, { detail: 'bumper:fire' })[0]?.power === 0, 'playback fires under nobody');
      c.count('desync', 0);
    },
  },
  {
    name: 'trap-magnet',
    description: 'A magnet drags enemies in range toward its centre at pull / mass and holds them short of it (turret never, a far grunt never, selves never); a beat-driven magnet pulls a drone only while on.',
    covers: ['TRAPS magnet'],
    level: trapRoom([
      { kind: 'magnet', id: 'mag', x: 8.5, y: 5.5, radius: 4, pull: 1.5, onWhen: ALWAYS },
      sleeper('g', 'grunt', 5.5, 5.5),
      sleeper('b', 'brute', 8.5, 2.5),
      sleeper('far', 'grunt', 2.5, 5.5),
      sleeper('t', 'turret', 8.5, 7.5),
      { kind: 'magnet', id: 'mag2', x: 4.5, y: 1.5, radius: 3, onWhen: beatW(8, 1, 2) },
      sleeper('dr', 'drone', 2.2, 1.5),
    ] as EntityDef[]),
    loadout: baseLoadout(),
    takes: [T(standAt(0, 7.5, 5.5))],
    check: (c) => {
      const f = c.run.snapshots.find((s) => s.sub === 240)!;
      c.need(Math.abs(f.enemies.find((e) => e.id === 'g')!.x - 7.0) < 1e-5, 'grunt pulled at 1.5 t/s');
      c.need(Math.abs(f.enemies.find((e) => e.id === 'b')!.y - 3.0) < 1e-5, 'brute pulled at 0.5 t/s');
      const end = c.last();
      c.need(Math.abs(end.enemies.find((e) => e.id === 'g')!.x - 7.9) < 1e-5, 'held 0.6 short of the centre');
      c.need(end.enemies.find((e) => e.id === 'far')!.x === 2.5 && end.enemies.find((e) => e.id === 't')!.x === 8.5, 'far grunt and turret untouched');
      c.need(Math.abs(end.enemies.find((e) => e.id === 'dr')!.x - (2.2 + (1.5 / 0.7) * 0.5)) < 1e-4, 'drone pulled for one beat');
    },
  },
  {
    name: 'trap-dart',
    description: 'Dart launchers fire on their beat grids, never aim: the first vulnerable self in a lane is shot and the next dart flies through its ghost to the self behind; darts strike a grunt and then a brute behind it (1 damage each, credited to the launcher); offset and enabledWhen gate a third launcher.',
    covers: ['TRAPS dart', 'dart archetype', 'trap kills count for eliminate'],
    level: trapRoom([
      { kind: 'dart', id: 'dl', c: 0, r: 5, dir: 'e', every: 2, offset: 0 },
      { kind: 'dart', id: 'dl2', c: 0, r: 3, dir: 'e', every: 2 },
      sleeper('g', 'grunt', 6.5, 3.5),
      sleeper('b', 'brute', 9.5, 3.5),
      { kind: 'dart', id: 'dl3', c: 11, r: 7, dir: 'w', every: 4, offset: 1, enabledWhen: { not: beatW(8, 4, 8) } },
    ] as EntityDef[]),
    loadout: baseLoadout(),
    takes: [T(standAt(0, 5.5, 5.5)), T(standAt(1, 8.5, 5.5)), T(standAt(2, 5.5, 4.5))],
    check: (c) => {
      c.need(sameList(c.ev('selfDeath').map((e) => [e.tape, e.detail]), [[0, 'shot by dart launcher dl'], [1, 'shot by dart launcher dl']]), 'two selves shot');
      c.need(sameList(c.ev('kill').map((e) => [e.id, e.detail]), [['g', 'dart'], ['b', 'dart']]), 'grunt then brute killed by darts');
      c.need(sameList(trapEv(c, 'dl3').filter(([, d]) => d === 'dart:fire'), [[120, 'dart:fire']]), 'offset and enabledWhen');
      c.need(c.outcome.objectiveComplete, 'eliminate completes');
    },
  },
  {
    name: 'trap-dart-crusher',
    description: 'An extended crusher stops darts at its face and a crusher plugging the muzzle stops the launcher firing at all.',
    covers: ['TRAPS dart', 'TRAPS crusher', 'muzzle blocked'],
    level: trapRoom([
      { kind: 'dart', id: 'dl', c: 0, r: 5, dir: 'e', every: 1 },
      { kind: 'crusher', id: 'cr', cells: cellsOf([6, 5]), extendWhen: beatW(8, 1.5, 4) },
      { kind: 'crusher', id: 'plug', cells: cellsOf([1, 5]), extendWhen: beatW(8, 5.5, 6.5) },
    ] as EntityDef[]),
    loadout: baseLoadout(),
    takes: [T(standAt(0, 9.5, 2.5))],
    check: (c) => {
      c.need(c.ev('projectileHit', { detail: 'dart:wall' }).map((e) => Math.round(e.x)).join() === '6,11,6,6,11,11', 'darts stop at the piston');
      c.need(trapEv(c, 'dl').map(([s]) => s).join() === '0,120,240,360,480,600,840', 'plugged muzzle fires nothing');
    },
  },
  {
    name: 'trap-dart-dodge-parry',
    description: 'A dart passes through a self inside recorded dodge i-frames; with parry, a heavy swing turns another launcher\'s dart like any enemy shot.',
    covers: ['TRAPS dart', 'dodge i-frames vs traps', 'parry'],
    level: trapRoom([
      { kind: 'dart', id: 'dl', c: 0, r: 5, dir: 'e', every: 8 },
      { kind: 'dart', id: 'dl2', c: 0, r: 7, dir: 'e', every: 8 },
    ] as EntityDef[]),
    loadout: baseLoadout({ abilities: ['parry'] }),
    takes: [
      T(pathTape({ index: 0, speed: 1, ticks: 240, path: [{ tick: 0, x: 5.5, y: 5.5 }, { tick: 28, x: 5.5, y: 5.5 }, { tick: 42, x: 5.5, y: 3.5 }], events: [{ tick: 28, kind: 'dodge' }] })),
      T(still(1, 5.5, 7.5, 240, 1, [{ tick: 12, kind: 'heavy', dir: Math.PI }])),
    ],
    check: (c) => {
      c.count('selfDeath', 0);
      c.need(c.ev('projectileHit', { detail: 'parry', id: 'dl2' }).length === 1, 'the dart is parried');
    },
  },
  {
    name: 'trap-sensor',
    description: 'Beam sensors: a self crossing a beam trips it (and a door on it starts opening that substep); a latched beam stays on; an enemies-only beam ignores the self; a beam cut by a closed door sees the grunt before the door, not the one beyond.',
    covers: ['TRAPS sensor', 'trap signals', 'latch', 'detects'],
    // Beam ends 0.05 inside the room (the test's y = 1 and 9 sit exactly on the wall faces, where a
    // shift of the emitter into the wall blinds the beam).
    level: trapRoom([
      { kind: 'sensor', id: 'trip', from: { x: 5.5, y: 1.05 }, to: { x: 5.5, y: 8.95 } },
      { kind: 'door', id: 'd', cells: cellsOf([9, 8]), openWhen: { sig: 'trip' } },
      { kind: 'sensor', id: 'latch', from: { x: 6.5, y: 1.05 }, to: { x: 6.5, y: 8.95 }, latch: true },
      { kind: 'sensor', id: 'foes', from: { x: 4.5, y: 1.05 }, to: { x: 4.5, y: 8.95 }, detects: 'enemies' },
      { kind: 'sensor', id: 'cut', from: { x: 9.5, y: 1.05 }, to: { x: 9.5, y: 7.5 } },
      { kind: 'door', id: 'shut', cells: cellsOf([9, 4]), openWhen: NEVER },
      sleeper('h', 'grunt', 9.5, 2.5),
      sleeper('g', 'grunt', 9.5, 6.5),
    ] as EntityDef[]),
    loadout: baseLoadout(),
    // Detuned off x.5 (3.53): from 3.5 the body's edge touches the beam exactly at a substep.
    takes: [T(pathTape({ index: 0, speed: 1, ticks: 240, path: [{ tick: 0, x: 3.53, y: 5.5 }, { tick: 60, x: 7.53, y: 5.5 }] }))],
    check: (c) => {
      const t = trapEv(c, 'trip');
      c.need(t.length === 2 && t[0][1] === 'sensor:on' && t[0][0] >= 100 && t[0][0] <= 104, 'trips on crossing');
      c.need(c.ev('door', { id: 'd', detail: 'open' })[0]?.sub === t[0][0] + 17, 'the door reads it the same substep');
      c.need(sameList(trapEv(c, 'latch').map(([, d]) => d), ['sensor:on']), 'latched');
      c.need(trapEv(c, 'foes').length === 0, 'enemies-only beam ignores the self');
      const cut = c.run.snapshots[0].mechs.find((m) => m.id === 'cut')!;
      c.need(cut.on && Math.abs(cut.reach! - 2.95) < 1e-9, 'cut at the door face, tripped by the near grunt');
    },
  },
  {
    name: 'trap-sensor-relay-chain',
    description: 'A belt carries a grunt through an enemies-only tripwire: the door on the wire starts opening that substep and a relay (quantize 1, delay 1) fires a crusher onto the grunt exactly one beat after the next beat.',
    covers: ['TRAPS sensor', 'TRAPS relay', 'TRAPS crusher', 'TRAPS conveyor', 'chained machines'],
    level: trapRoom([
      { kind: 'conveyor', id: 'belt', cells: cellsOf([3, 5], [4, 5], [5, 5], [6, 5]), dir: 'e', speed: 2 },
      sleeper('g', 'grunt', 3.5, 5.5),
      { kind: 'sensor', id: 'trip', from: { x: 4.5, y: 5 }, to: { x: 4.5, y: 6 }, detects: 'enemies' },
      { kind: 'door', id: 'gate', cells: cellsOf([9, 8]), openWhen: { sig: 'trip' } },
      { kind: 'relay', id: 'slam', trigger: { sig: 'trip' }, quantize: 1, delay: 1, hold: 1 },
      { kind: 'crusher', id: 'cr', cells: cellsOf([5, 5]), extendWhen: { sig: 'slam' } },
    ] as EntityDef[]),
    loadout: baseLoadout(),
    takes: [T(standAt(0, 2.5, 2.5))],
    check: (c) => {
      c.need(sameList(trapEv(c, 'slam'), [[82, 'relay:armed'], [239, 'relay:on'], [359, 'relay:off']]), 'relay timeline');
      c.need(sameList(c.ev('kill').map((e) => [e.id, e.sub, e.detail]), [['g', 239, 'crusher']]), 'crushed on beat 2');
      c.win(true);
    },
  },
  {
    name: 'trap-relay-modes',
    description: 'Relays turn a switch into a pulse (next beat, one beat), a quantize-2 / delay-1 / half-beat pulse, an immediate quarter-beat pulse, a latch and a toggle; a hold-2 relay ignores triggers while armed or pulsing and publishes <id>.armed; a delay-1 relay gives the crusher it drives a full one-beat telegraph.',
    covers: ['TRAPS relay', '<id>.armed', 'relay forecast telegraph'],
    level: trapRoom([
      { kind: 'switch', id: 'sw', x: 2.5, y: 2.5 },
      { kind: 'relay', id: 'rl', trigger: { sig: 'sw' } },
      { kind: 'relay', id: 'q', trigger: { sig: 'sw' }, quantize: 2, delay: 1, hold: 0.5 },
      { kind: 'relay', id: 'now', trigger: { sig: 'sw' }, quantize: 0, hold: 0.25 },
      { kind: 'relay', id: 'lt', trigger: { sig: 'sw' }, mode: 'latch' },
      { kind: 'relay', id: 'tg', trigger: { sig: 'sw' }, mode: 'toggle' },
      { kind: 'relay', id: 'rd', trigger: { sig: 'sw' }, delay: 1 },
      { kind: 'crusher', id: 'cr', cells: cellsOf([6, 5]), extendWhen: { sig: 'rd' } },
      { kind: 'switch', id: 'sw2', x: 8.5, y: 2.5 },
      { kind: 'relay', id: 'ra', trigger: { sig: 'sw2' }, hold: 2 },
      { kind: 'door', id: 'd', cells: cellsOf([9, 8]), openWhen: { sig: 'ra.armed' } },
    ] as EntityDef[]),
    loadout: baseLoadout(),
    takes: [T(standAt(0, 9.5, 6.5)), T(toggles(1, 2.5, 3.2, 10, 80, 150)), T(toggles(2, 8.5, 3.2, 10, 21, 32, 43, 54))],
    check: (c) => {
      c.need(sameList(trapEv(c, 'rl').slice(0, 3), [[40, 'relay:armed'], [119, 'relay:on'], [239, 'relay:off']]), 'pulse');
      c.need(sameList(trapEv(c, 'now').filter(([, d]) => d !== 'relay:armed').slice(0, 2), [[40, 'relay:on'], [70, 'relay:off']]), 'quantize 0');
      c.need(sameList(trapEv(c, 'tg').filter(([, d]) => d !== 'relay:armed'), [[119, 'relay:on'], [719, 'relay:off']]), 'toggle');
      c.need(sameList(trapEv(c, 'ra'), [[40, 'relay:armed'], [119, 'relay:on'], [359, 'relay:off']]), 'ignores triggers while busy');
      c.need(c.ev(TRAP_EVENT, { id: 'cr', detail: 'crusher:slam' })[0]?.sub === 239, 'relay-driven stroke on beat 2');
    },
  },
  {
    name: 'trap-machines-vs-enemies',
    description: 'Machines turned against enemies: a belt delivers a sleeping grunt into a recorded swing, and a 0.5x swing too weak to hurt shoves a grunt into a dart lane where the next dart kills it.',
    covers: ['TRAPS puzzle uses', 'MOM-05', 'trap kills count for eliminate'],
    level: trapRoom(
      [
        { kind: 'conveyor', id: 'belt', cells: cellsOf([3, 5], [4, 5], [5, 5], [6, 5]), dir: 'e', speed: 2 },
        // Detuned off x.5 (3.53): from x.5 the belt drops the grunt exactly on x = 7.
        sleeper('g', 'grunt', 3.53, 5.5),
        { kind: 'dart', id: 'dl', c: 0, r: 7, dir: 'e', every: 2 },
        sleeper('k', 'grunt', 9.5, 6.75),
      ] as EntityDef[],
      { speeds: [0.5, 1] },
    ),
    loadout: baseLoadout(),
    takes: [
      T(still(0, 8, 5.5, 240, 1, [{ tick: 110, kind: 'light', dir: Math.PI }])),
      T(still(1, 9.5, 5.9, 240, 0.5, [{ tick: 20, kind: 'light', dir: Math.PI / 2 }])),
    ],
    check: (c) => {
      c.need(c.ev('kill', { id: 'g' })[0]?.detail === 'light' && c.ev('kill', { id: 'g' })[0]?.tape === 0, 'delivered into the swing');
      c.need(c.ev('clang', { id: 'k' }).length === 1 && c.ev('kill', { id: 'k' })[0]?.detail === 'dart', 'shoved into the dart lane');
    },
  },
  {
    name: 'trap-spikes-hunter',
    description: 'An awake grunt hunting a self walks onto raised spikes and dies: the trap does not care who it is.',
    covers: ['TRAPS spikes', 'TRAPS puzzle uses'],
    level: trapRoom([{ kind: 'spikes', id: 'sp', cells: cellsOf([5, 5], [6, 5]), upWhen: ALWAYS }, { kind: 'enemy', id: 'g', type: 'grunt', x: 2.5, y: 5.5 }] as EntityDef[]),
    loadout: baseLoadout(),
    takes: [T(standAt(0, 9.5, 5.5))],
    check: (c) => {
      const k = c.ev('kill');
      c.need(k.length === 1 && k[0].detail === 'spikes' && k[0].sub > 260 && k[0].sub < 290, 'walks onto the spikes');
      c.win(true);
    },
  },
  {
    name: 'trap-gauntlet',
    description: 'One of every machine with awake enemies in one room; two live takes (1x wandering with every action, then 2x) recorded through the player controller and resolved: everything interacts.',
    covers: ['TRAPS all nine kinds', 'trap determinism', 'record', 'liveCarry'],
    level: makeLevel({
      speeds: [1, 2],
      bars: 4,
      start: { x: 1.5, y: 5.5 },
      entities: [
        { kind: 'switch', id: 'sw', x: 2.5, y: 2.5 },
        { kind: 'door', id: 'd', cells: cellsOf([9, 8]), openWhen: { or: [{ sig: 'trip' }, { sig: 'bm' }] } },
        { kind: 'spikes', id: 'sp', cells: cellsOf([5, 2], [6, 2]), upWhen: beatW(2, 1, 2) },
        { kind: 'crusher', id: 'cr', cells: cellsOf([8, 3], [8, 4]), extendWhen: { sig: 'rl' } },
        { kind: 'conveyor', id: 'belt', cells: cellsOf([3, 5], [4, 5], [5, 5], [6, 5]), dir: 'e', reverseWhen: { sig: 'sw' } },
        { kind: 'flame', id: 'fl', c: 0, r: 7, dir: 'e', range: 6, onWhen: beatW(4, 2, 3) },
        { kind: 'dart', id: 'dl', c: 11, r: 3, dir: 'w', every: 2, offset: 1 },
        { kind: 'bumper', id: 'bm', c: 7, r: 5, dir: 'n', fireWhen: beatW(4, 3, 3.5) },
        { kind: 'sensor', id: 'trip', from: { x: 4.5, y: 4 }, to: { x: 4.5, y: 7 } },
        { kind: 'relay', id: 'rl', trigger: { sig: 'trip' }, delay: 1 },
        { kind: 'magnet', id: 'mag', x: 9.5, y: 6.5, radius: 3, onWhen: beatW(8, 4, 8) },
        { kind: 'enemy', id: 'g1', type: 'grunt', x: 3.5, y: 5.5 },
        { kind: 'enemy', id: 'g2', type: 'stalker', x: 9.5, y: 2.5 },
        { kind: 'enemy', id: 't1', type: 'turret', x: 10.5, y: 8.5 },
        { kind: 'enemy', id: 'b1', type: 'brute', x: 6.5, y: 7.5 },
        { kind: 'enemy', id: 'dr', type: 'drone', x: 8.5, y: 6.5 },
      ] as EntityDef[],
    }),
    loadout: baseLoadout(),
    takes: [
      rec(0, 1, 'stop', script().run(0, 60, 1, 0).run(60, 110, 0, -1).run(110, 200, 1, 0.4).run(200, 300, -1, 0.2).run(300, 480, 0.3, 1).press(40, 'light').press(130, 'dodge').press(210, 'heavy').press(330, 'ranged').press(400, 'interact')),
      rec(1, 2, 'stop', script().run(0, 200, 0.5, -1).press(90, 'heavy')),
    ],
    check: (c) => {
      c.need(c.ev(TRAP_EVENT).length > 10, 'the machines ran');
      c.need(c.run.snapshots.length > 30, 'resolved the whole horizon');
    },
  },
]);

// ── the shipped sandbox level, baseline catalogue gear, closed-loop bot plans (APP-TEST-03) ──
add(() => {
  const { loadout, gear } = catalogue({});
  return [
    {
      name: 'sandbox-bot-solo',
      description: 'The shipped sandbox level with the baseline loadout: one 1x take opens the gate, clears both grunts and the turret while dodging its bolt (bot inputs, recorded open-loop).',
      covers: ['APP-TEST-03', 'sandbox', 'catalogue gear', 'every enemy type (grunt, turret)'],
      level: SANDBOX,
      loadout,
      gear,
      takes: [
        botTake(
          0,
          1,
          'stop',
          [
            { kind: 'goto', x: 3.5, y: 2.3 },
            { kind: 'interact' },
            { kind: 'goto', x: 4.5, y: 3.5 },
            { kind: 'goto', x: 7.0, y: 3.5 },
            { kind: 'goto', x: 11.5, y: 3.4 },
            { kind: 'hold', x: 11.5, y: 3.4 },
          ],
          { dodgeRange: 1.2 },
        ),
      ],
      check: (c) => {
        c.win(true);
        c.need(JSON.stringify(c.outcome.survivors) === '[0]', 'A survives');
      },
    },
    {
      name: 'sandbox-bot-two-cassettes',
      description: 'The sandbox with two cassettes: A (1x) opens the door and holds the plate, B (2x) fights.',
      covers: ['APP-TEST-03', 'sandbox', 'plates', 'lasers', 'record against playback'],
      level: SANDBOX,
      loadout,
      gear,
      takes: [
        botTake(
          0,
          1,
          'stop',
          [
            { kind: 'goto', x: 3.5, y: 2.3 },
            { kind: 'interact' },
            { kind: 'goto', x: 2.5, y: 6.5 },
            { kind: 'goto', x: 1.5, y: 8.5 },
            { kind: 'hold', x: 1.5, y: 8.5 },
          ],
          { strikeRange: 0 },
        ),
        botTake(
          1,
          2,
          'stop',
          [
            { kind: 'goto', x: 4.5, y: 3.5 },
            { kind: 'goto', x: 7.0, y: 3.5 },
            { kind: 'goto', x: 11.5, y: 3.4 },
            { kind: 'hold', x: 11.5, y: 3.4 },
          ],
          { dodgeRange: 1.2 },
        ),
      ],
      check: (c) => {
        c.win(true);
        c.need(c.ev('plate', { detail: 'on' }).length > 0, 'A holds the plate');
      },
    },
  ];
});

// ───────────────────────────── running a scenario ─────────────────────────────

interface Recording {
  take: number;
  inputs: PlayerInput[];
  bossMemory: BossMemory | undefined;
  tape: Tape;
  outcome: Outcome;
  events: SimEvent[];
  snapshots: FrameSnapshot[];
}

interface RunResult {
  recordings: Recording[];
  tapes: Tape[];
  bossMemory: BossMemory | undefined;
  horizonSubs: number;
  outcome: Outcome;
  events: SimEvent[];
  snapshots: (FrameSnapshot & { threatBeats?: number[] })[];
}

function copyInput(i: PlayerInput): PlayerInput {
  return { moveX: i.moveX, moveY: i.moveY, aim: i.aim, light: i.light, heavy: i.heavy, dodge: i.dodge, ranged: i.ranged, interact: i.interact, ability: i.ability };
}

const shift = (v: number, d: number) => v + d;

/** The level with every continuous coordinate moved by (d, d). Tile geometry is unchanged. */
function jitterLevel(level: LevelDef, d: number): LevelDef {
  if (d === 0) return level;
  const out: LevelDef = JSON.parse(JSON.stringify(level));
  out.start = { x: shift(out.start.x, d), y: shift(out.start.y, d) };
  out.entities = out.entities.map((e) => {
    switch (e.kind) {
      case 'enemy':
      case 'switch':
      case 'core':
        return { ...e, x: shift(e.x, d), y: shift(e.y, d) };
      case 'laser':
      case 'sensor':
        return { ...e, from: { x: shift(e.from.x, d), y: shift(e.from.y, d) }, to: { x: shift(e.to.x, d), y: shift(e.to.y, d) } };
      case 'magnet':
        return { ...e, x: shift(e.x, d), y: shift(e.y, d) };
      default:
        return e;
    }
  });
  return out;
}

function jitterTape(t: Tape, d: number): Tape {
  if (d === 0) return t;
  const pos = new Float32Array(t.pos.length);
  for (let i = 0; i < pos.length; i++) pos[i] = t.pos[i] + d;
  return { ...t, pos, facing: t.facing.slice(), anim: t.anim.slice(), events: t.events.map((e) => ({ ...e, x: e.x + d, y: e.y + d })) };
}

function memoryFor(spec: Spec, level: LevelDef, tapes: Tape[]): BossMemory | undefined {
  if (!spec.bossMemoryFrom) return undefined;
  const committed = tapes.filter((t) => spec.bossMemoryFrom!.includes(t.index));
  return committed.length ? buildBossMemory(level, committed) : undefined;
}

const isSample = (sub: number) => sub % SAMPLE_SUBS === 0;

/**
 * Run a scenario. `fixedInputs` (per take) replays recorded inputs instead of the take's script or
 * controller; the stability check uses it so that a jittered world sees exactly the same inputs.
 */
function runScenario(spec: Spec, d: number, fixedInputs?: (PlayerInput[] | undefined)[]): RunResult {
  const level = jitterLevel(spec.level, d);
  const tapes: Tape[] = [];
  const recordings: Recording[] = [];
  spec.takes.forEach((take, k) => {
    if (take.source === 'tape') {
      tapes.push(jitterTape(take.tape, d));
      return;
    }
    const bossMemory = memoryFor(spec, level, tapes);
    const sim = createSim({ level, loadout: spec.loadout, tapes: [...tapes], live: { index: take.index, speed: take.speed, endMode: take.endMode }, bossMemory });
    const fixed = fixedInputs?.[k];
    const limit = fixed ? fixed.length : (take.ticks ?? sim.tapeTicks);
    const inputs: PlayerInput[] = [];
    const events: SimEvent[] = [];
    const snapshots: FrameSnapshot[] = [sim.snapshot()];
    for (let t = 0; t < limit && !sim.done; t++) {
      let inp: PlayerInput;
      if (fixed) inp = fixed[t];
      else if ('script' in take) inp = take.script.input(t);
      else {
        const snap = sim.snapshot();
        const self = snap.actors.find((a) => a.live);
        if (!self) throw new Error(`${spec.name}: no live self`);
        inp = take.controller(t, snap, self);
      }
      inputs.push(copyInput(inp));
      sim.stepLocalTick(inp);
      for (const e of sim.drainEvents()) events.push(e);
      if (isSample(sim.sub)) snapshots.push(sim.snapshot());
    }
    if (snapshots[snapshots.length - 1].sub !== sim.sub) snapshots.push(sim.snapshot());
    const tape = sim.liveTape();
    recordings.push({ take: k, inputs, bossMemory, tape, outcome: sim.outcome(), events, snapshots });
    tapes.push(tape);
  });

  const bossMemory = memoryFor(spec, level, tapes);
  const sim = createSim({ level, loadout: spec.loadout, tapes, bossMemory });
  const threat = spec.loadout.abilities.includes('beatSight');
  const H = sim.horizonSubs;
  const events: SimEvent[] = [];
  const snap0 = sim.snapshot() as FrameSnapshot & { threatBeats?: number[] };
  if (threat) snap0.threatBeats = sim.threatBeats!();
  const snapshots: (FrameSnapshot & { threatBeats?: number[] })[] = [snap0];
  while (sim.sub < H) {
    sim.stepSub();
    for (const e of sim.drainEvents()) events.push(e);
    if (isSample(sim.sub) || sim.sub === H) {
      const s = sim.snapshot() as FrameSnapshot & { threatBeats?: number[] };
      if (threat) s.threatBeats = sim.threatBeats!();
      snapshots.push(s);
    }
  }
  const outcome = sim.outcome();

  if (d === 0) {
    // The loop above must be resolveEncounter exactly (resolve.ts); prove it on the base run.
    const ref = resolveEncounter({ level, loadout: spec.loadout, tapes, bossMemory });
    if (JSON.stringify(ref.events) !== JSON.stringify(events) || JSON.stringify(ref.outcome) !== JSON.stringify(outcome) || ref.horizonSubs !== H) {
      throw new Error(`${spec.name}: the export loop disagrees with resolveEncounter`);
    }
    const bySub = new Map(ref.frames.map((f) => [f.sub, f]));
    for (const s of snapshots) {
      const { threatBeats: _t, ...plain } = s;
      if (JSON.stringify(bySub.get(s.sub)) !== JSON.stringify(plain)) throw new Error(`${spec.name}: snapshot ${s.sub} disagrees with resolveEncounter`);
    }
  }
  return { recordings, tapes, bossMemory, horizonSubs: H, outcome, events, snapshots };
}

// ───────────────────────────── JSON output ─────────────────────────────

const SCALE = 10 ** DECIMALS;
function r(v: number): number {
  if (!Number.isFinite(v)) throw new Error(`non-finite value ${v}`);
  const x = Math.round(v * SCALE) / SCALE;
  return x === 0 ? 0 : x; // no -0
}

function outEvent(e: SimEvent): Record<string, unknown> {
  const o: Record<string, unknown> = { sub: e.sub, type: e.type, x: r(e.x), y: r(e.y) };
  if (e.tape !== undefined) o.tape = e.tape;
  if (e.id !== undefined) o.id = e.id;
  if (e.dir !== undefined) o.dir = r(e.dir);
  if (e.power !== undefined) o.power = r(e.power);
  if (e.detail !== undefined) o.detail = e.detail;
  return o;
}

function outActor(a: ActorSnap): Record<string, unknown> {
  const o: Record<string, unknown> = {
    tape: a.tape,
    live: a.live,
    x: r(a.x),
    y: r(a.y),
    facing: r(a.facing),
    anim: a.anim,
    life: a.life,
    synced: a.synced,
    iframes: a.iframes,
    phase: { tick: r(a.phase.tick), dir: a.phase.dir, traversal: a.phase.traversal, ended: a.phase.ended },
  };
  if (a.spark) o.spark = { x: r(a.spark.x), y: r(a.spark.y) };
  return o;
}

function outEnemy(e: EnemySnap): Record<string, unknown> {
  const o: Record<string, unknown> = { id: e.id, type: e.type, x: r(e.x), y: r(e.y), hp: e.hp, maxHp: e.maxHp, alive: e.alive, state: e.state };
  if (e.target !== undefined) o.target = e.target;
  if (e.shield !== undefined) o.shield = e.shield;
  if (e.bossPhase !== undefined) o.bossPhase = e.bossPhase;
  if (e.bossRecall !== undefined) o.bossRecall = e.bossRecall;
  if (e.bossRecallTape !== undefined) o.bossRecallTape = e.bossRecallTape;
  if (e.bossRecallAt !== undefined) o.bossRecallAt = { x: r(e.bossRecallAt.x), y: r(e.bossRecallAt.y) };
  return o;
}

function outSnapshot(f: FrameSnapshot & { threatBeats?: number[] }): Record<string, unknown> {
  const o: Record<string, unknown> = {
    sub: f.sub,
    beat: r(f.beat),
    actors: f.actors.map(outActor),
    enemies: f.enemies.map(outEnemy),
    projectiles: f.projectiles.map((p) => {
      const q: Record<string, unknown> = { id: p.id, owner: 'tape' in p.owner ? { tape: p.owner.tape } : { enemy: p.owner.enemy }, archetype: p.archetype, x: r(p.x), y: r(p.y), z: r(p.z), dir: r(p.dir) };
      if (p.targetId !== undefined) q.targetId = p.targetId;
      return q;
    }),
    mechs: f.mechs.map((m) => {
      const q: Record<string, unknown> = { id: m.id, kind: m.kind, on: m.on };
      if (m.t !== undefined) q.t = r(m.t);
      // Trap snapshot fields (docs/TRAPS.md "Snapshot fields"); classic mechanisms never have them.
      if (m.warn !== undefined) q.warn = r(m.warn);
      if (m.dir !== undefined) q.dir = r(m.dir);
      if (m.reach !== undefined) q.reach = r(m.reach);
      if (m.firing !== undefined) q.firing = m.firing;
      return q;
    }),
    objective: { complete: f.objective.complete, progress: r(f.objective.progress), survivors: f.objective.survivors },
  };
  if (f.threatBeats) o.threatBeats = f.threatBeats.map(r);
  return o;
}

function outOutcome(o: Outcome): Record<string, unknown> {
  const out: Record<string, unknown> = { win: o.win, objectiveComplete: o.objectiveComplete, survivors: [...o.survivors] };
  if (o.reason !== undefined) out.reason = o.reason;
  out.notes = [...o.notes];
  return out;
}

const BUTTONS = ['light', 'heavy', 'dodge', 'ranged', 'interact', 'ability'] as const;
function outInput(i: PlayerInput): [number, number, number, string[]] {
  return [i.moveX, i.moveY, i.aim, BUTTONS.filter((b) => i[b])];
}

function goldenJson(spec: Spec, res: RunResult): Record<string, unknown> {
  let rec = 0;
  const takes = spec.takes.map((take) => {
    if (take.source === 'tape') return { source: 'tape', tape: serializeTape(take.tape) };
    const recording = res.recordings[rec++];
    return { source: 'inputs', index: take.index, speed: take.speed, endMode: take.endMode, inputs: recording.inputs.map(outInput) };
  });
  return {
    format: FORMAT,
    name: spec.name,
    description: spec.description,
    covers: spec.covers,
    level: spec.level,
    loadout: { gear: spec.gear ?? null, resolved: spec.loadout },
    bossMemoryFrom: spec.bossMemoryFrom ?? null,
    takes,
    expected: {
      recordings: res.recordings.map((rr) => ({
        take: rr.take,
        bossMemory: rr.bossMemory ?? null,
        tape: serializeTape(rr.tape),
        outcome: outOutcome(rr.outcome),
        events: rr.events.map(outEvent),
        snapshots: rr.snapshots.map(outSnapshot),
      })),
      resolution: {
        bossMemory: res.bossMemory ?? null,
        horizonSubs: res.horizonSubs,
        outcome: outOutcome(res.outcome),
        events: res.events.map(outEvent),
        snapshots: res.snapshots.map(outSnapshot),
      },
    },
  };
}

/**
 * JSON with one-space indentation in which every value whose one-line form fits in INLINE_WIDTH
 * characters stays on one line (an event, an input tuple, an actor). Plain JSON; deterministic.
 */
const INLINE_WIDTH = 220;
function compactJson(v: unknown, indent = ''): string {
  const flat = JSON.stringify(v);
  if (flat === undefined) throw new Error('compactJson: unserialisable value');
  if (v === null || typeof v !== 'object' || flat.length + indent.length <= INLINE_WIDTH) return flat;
  const inner = indent + ' ';
  if (Array.isArray(v)) {
    if (v.length === 0) return '[]';
    return '[\n' + v.map((x) => inner + compactJson(x, inner)).join(',\n') + '\n' + indent + ']';
  }
  const entries = Object.entries(v as Record<string, unknown>).filter(([, x]) => x !== undefined);
  if (entries.length === 0) return '{}';
  return '{\n' + entries.map(([k, x]) => inner + JSON.stringify(k) + ': ' + compactJson(x, inner)).join(',\n') + '\n' + indent + '}';
}

// ───────────────────────────── stability check ─────────────────────────────

const sig = (e: SimEvent) => `${e.sub}|${e.type}|${e.tape ?? ''}|${e.id ?? ''}|${e.detail ?? ''}`;
const outcomeSig = (o: Outcome) => JSON.stringify([o.win, o.objectiveComplete, o.survivors, o.reason ?? null]);

function firstEventDiff(a: SimEvent[], b: SimEvent[]): string | null {
  const n = Math.max(a.length, b.length);
  for (let i = 0; i < n; i++) {
    const x = a[i] ? sig(a[i]) : '(none)';
    const y = b[i] ? sig(b[i]) : '(none)';
    if (x !== y) return `event #${i}: ${x} vs ${y}`;
  }
  return null;
}

/** Largest position difference between two runs' sampled snapshots (the jitter itself removed). */
function maxDrift(a: FrameSnapshot[], b: FrameSnapshot[], d: number): number {
  let m = 0;
  const upd = (x0: number, y0: number, x1: number, y1: number) => {
    m = Math.max(m, Math.abs(x1 - d - x0), Math.abs(y1 - d - y0));
  };
  for (let i = 0; i < Math.min(a.length, b.length); i++) {
    const fa = a[i];
    const fb = b[i];
    fa.actors.forEach((x, j) => {
      const y = fb.actors[j];
      if (!y) return;
      upd(x.x, x.y, y.x, y.y);
      if (x.spark && y.spark) upd(x.spark.x, x.spark.y, y.spark.x, y.spark.y);
    });
    fa.enemies.forEach((x, j) => {
      const y = fb.enemies[j];
      if (y) upd(x.x, x.y, y.x, y.y);
    });
    fa.projectiles.forEach((x, j) => {
      const y = fb.projectiles[j];
      if (y && y.id === x.id) upd(x.x, x.y, y.x, y.y);
    });
  }
  return m;
}

function stability(spec: Spec, base: RunResult): string[] {
  const problems: string[] = [];
  const fixed = spec.takes.map((t) => (t.source === 'inputs' ? base.recordings.find((r) => spec.takes[r.take] === t)!.inputs : undefined));
  for (const d of [JITTER, -JITTER]) {
    const j = runScenario(spec, d, fixed);
    const stages: [string, SimEvent[], SimEvent[], Outcome, Outcome, FrameSnapshot[], FrameSnapshot[]][] = base.recordings.map((rr, i) => [
      `recording of take ${rr.take}`,
      rr.events,
      j.recordings[i].events,
      rr.outcome,
      j.recordings[i].outcome,
      rr.snapshots,
      j.recordings[i].snapshots,
    ]);
    stages.push(['resolution', base.events, j.events, base.outcome, j.outcome, base.snapshots, j.snapshots]);
    for (const [stage, ea, eb, oa, ob, sa, sb] of stages) {
      const diff = firstEventDiff(ea, eb);
      if (diff) problems.push(`jitter ${d}: ${stage}: ${diff}`);
      if (outcomeSig(oa) !== outcomeSig(ob)) problems.push(`jitter ${d}: ${stage}: outcome ${outcomeSig(oa)} vs ${outcomeSig(ob)}`);
      const drift = maxDrift(sa, sb, d);
      if (drift > POS_TOLERANCE) problems.push(`jitter ${d}: ${stage}: positions drift by ${drift.toExponential(2)}`);
    }
  }
  return problems;
}

// ───────────────────────────── main ─────────────────────────────

/** `--diagnose <name>`: print where a jittered run first departs from the base run. Writes nothing. */
function diagnose(spec: Spec): void {
  const base = runScenario(spec, 0);
  const fixed = spec.takes.map((t) => (t.source === 'inputs' ? base.recordings.find((r) => spec.takes[r.take] === t)!.inputs : undefined));
  for (const d of [JITTER, -JITTER]) {
    const j = runScenario(spec, d, fixed);
    console.log(`jitter ${d}: ${firstEventDiff(base.events, j.events) ?? 'events identical'}`);
    for (let i = 0; i < base.snapshots.length; i++) {
      const drift = maxDrift([base.snapshots[i]], [j.snapshots[i]], d);
      if (drift > 1e-4) {
        console.log(`  first drift > 1e-4 at sub ${base.snapshots[i].sub}: ${drift.toExponential(2)}`);
        console.log('  base   ' + JSON.stringify(outSnapshot(base.snapshots[i])));
        console.log('  jitter ' + JSON.stringify(outSnapshot(j.snapshots[i])));
        break;
      }
    }
    const ea = base.events.map(sig);
    const eb = j.events.map(sig);
    const onlyA = ea.filter((x) => !eb.includes(x));
    const onlyB = eb.filter((x) => !ea.includes(x));
    if (onlyA.length || onlyB.length) console.log(`  only in base: ${onlyA.join(', ')}\n  only in jitter: ${onlyB.join(', ')}`);
  }
}

function main(): void {
  const fast = process.argv.includes('--fast');
  const specs: Spec[] = [];
  for (const f of SCENARIOS) {
    const s = f();
    for (const one of Array.isArray(s) ? s : [s]) specs.push(one);
  }
  const di = process.argv.indexOf('--diagnose');
  if (di >= 0) {
    const want = process.argv[di + 1];
    const spec = specs.find((s) => s.name === want);
    if (!spec) throw new Error(`no scenario named ${want}`);
    diagnose(spec);
    return;
  }
  const names = new Set<string>();
  for (const s of specs) {
    if (!/^[a-z0-9][a-z0-9_-]*$/.test(s.name)) throw new Error(`bad scenario name ${s.name}`);
    if (names.has(s.name)) throw new Error(`duplicate scenario name ${s.name}`);
    names.add(s.name);
  }

  mkdirSync(outDir, { recursive: true });
  for (const f of readdirSync(outDir)) if (f.endsWith('.json')) unlinkSync(resolvePath(outDir, f));

  const index: Record<string, unknown>[] = [];
  const unstable: string[] = [];
  const failed: string[] = [];
  for (const spec of specs) {
    const res = runScenario(spec, 0);
    if (spec.check) {
      const checker = new Checker(res);
      spec.check(checker);
      if (checker.failures.length) {
        failed.push(spec.name);
        console.error(`CHECK FAILED ${spec.name}:\n      ${checker.failures.join('\n      ')}`);
      }
    }
    const json = goldenJson(spec, res);
    const text = compactJson(json) + '\n';
    if (JSON.stringify(JSON.parse(text)) !== JSON.stringify(json)) throw new Error(`${spec.name}: compact JSON does not round-trip`);
    writeFileSync(resolvePath(outDir, `${spec.name}.json`), text, 'utf8');
    const o = res.outcome;
    const line = `${spec.name.padEnd(46)} ${o.win ? 'WIN ' : 'fail'} ev ${String(res.events.length).padStart(4)} snaps ${String(res.snapshots.length).padStart(3)} ${(text.length / 1024).toFixed(0).padStart(4)} KB`;
    let status = '';
    if (!fast) {
      const problems = stability(spec, res);
      if (problems.length) {
        unstable.push(spec.name);
        status = `  UNSTABLE\n      ${problems.slice(0, 4).join('\n      ')}`;
      } else status = '  stable';
    }
    console.log(line + status);
    index.push({
      name: spec.name,
      file: `${spec.name}.json`,
      description: spec.description,
      covers: spec.covers,
      takes: spec.takes.map((t) => t.source),
      win: o.win,
      events: res.events.length,
    });
  }
  writeFileSync(resolvePath(outDir, 'index.json'), compactJson({ format: FORMAT, sampleSubs: SAMPLE_SUBS, decimals: DECIMALS, scenarios: index }) + '\n', 'utf8');
  console.log(`\n${specs.length} scenarios written to ${outDir}`);
  const checked = specs.filter((s) => s.check).length;
  if (failed.length) {
    console.error(`checks FAILED: ${failed.join(', ')}`);
    process.exitCode = 1;
  } else console.log(`checks: all ${checked} scenario checks pass`);
  const unchecked = specs.filter((s) => !s.check).map((s) => s.name);
  if (unchecked.length) console.log(`scenarios without a check: ${unchecked.join(', ')}`);
  if (!fast) {
    if (unstable.length) {
      console.error(`UNSTABLE under ±${JITTER} jitter: ${unstable.join(', ')}`);
      process.exitCode = 1;
    } else console.log(`stability: all ${specs.length} scenarios unchanged under ±${JITTER} tile jitter`);
  }
}

main();
