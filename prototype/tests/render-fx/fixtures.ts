import type { ActorSnap, EnemySnap, FrameSnapshot, LevelDef, SimEvent, SimEventType, TapeIndex } from '../../src/core/types';
import type { MusicPulse, RenderFrame, ViewMode } from '../../src/contracts';
import type { ThemePalette } from '../../src/render/layer';
import { FxDirector, type FxEnv } from '../../src/render/fx/director';
// Raw source of the contracts, so the routing test sees the union exactly as declared.
import typesSource from '../../src/core/types.ts?raw';

export const PALETTE: ThemePalette = {
  theme: 'lower',
  background: 0x120e16,
  fog: 0x120e16,
  floor: 0x3a3040,
  floorAlt: 0x2e2634,
  wall: 0x4a3c4c,
  wallTop: 0x5c4a5e,
  metal: 0x6a5a6e,
  trim: 0x8a7a8e,
  hazard: 0xffb21f,
  foliage: 0x6fae3a,
  neonA: 0xff3fa4,
  neonB: 0x4ff3ff,
  neonC: 0xb05cff,
  graffiti: 0xff4fa3,
  ink: 0x14110f,
  keyLight: 0xffffff,
  keyIntensity: 1,
  ambient: 0x404060,
  ambientIntensity: 0.6,
  bloom: 1,
};

export const LEVEL: LevelDef = {
  id: 'fx-test',
  index: 0,
  name: 'FX Test',
  tagline: '',
  theme: 'lower',
  bpm: 120,
  bars: 4,
  horizonBars: 8,
  maxTapes: 4,
  speeds: [0.5, 1, 2, 4],
  endModes: ['stop', 'repeat', 'reverse'],
  map: ['##########', '#........#', '#..~~~...#', '#........#', '##########'],
  start: { x: 2.5, y: 2.5 },
  entities: [
    { kind: 'core', id: 'core1', x: 7.5, y: 2.5 },
    { kind: 'decor', type: 'waveScreen', x: 5, y: 1 },
    { kind: 'decor', type: 'runePanel', x: 3, y: 1 },
  ],
  objective: { type: 'activate', text: 'Light the core' },
  music: {
    root: 0,
    scale: 'minor',
    progression: [0, 5, 3, 4],
    tracks: [
      { role: 'bass', formula: 'a' },
      { role: 'drums', formula: 'b' },
      { role: 'melody', formula: 'c' },
      { role: 'chord', formula: 'd' },
    ],
  },
  loot: [],
  briefing: [],
};

export function makeEnv(): FxEnv {
  return { palette: PALETTE, level: LEVEL, refMomentum: 10, meleeReach: 1.2, meleeArcDeg: 120, quality: 'high' };
}

export function makeDirector(): FxDirector {
  return new FxDirector(makeEnv());
}

export function actor(tape: TapeIndex, x: number, y: number, over: Partial<ActorSnap> = {}): ActorSnap {
  return {
    tape,
    live: tape === 0,
    x,
    y,
    facing: 0,
    anim: 'run',
    life: 'alive',
    synced: true,
    iframes: false,
    phase: { tick: 0, dir: 1, traversal: 0, ended: false },
    vx: 0,
    vy: 0,
    ...over,
  };
}

export function boss(x: number, y: number): EnemySnap {
  return { id: 'boss', type: 'boss', x, y, facing: 0, hp: 10, maxHp: 10, alive: true, state: 'idle', stateT: 0 };
}

export function snapshot(beat: number, actors: ActorSnap[] = [], enemies: EnemySnap[] = []): FrameSnapshot {
  return {
    sub: Math.round(beat * 120),
    beat,
    actors,
    enemies,
    projectiles: [],
    mechs: [],
    objective: { complete: false, progress: 0, survivors: actors.length },
  };
}

export function music(beat: number, chord = 0): MusicPulse {
  const f = beat - Math.floor(beat);
  return {
    beat,
    beatPulse: 1 - f,
    barPulse: 1 - (beat / 4 - Math.floor(beat / 4)),
    levels: [0.8, 0.5, 0.6, 0.3],
    pitches: [0.2 + 0.1 * Math.sin(beat), 0.5, 0.7 + 0.1 * Math.cos(beat * 2), 0.4],
    chord,
  };
}

export function frame(mode: ViewMode, beat: number, events: SimEvent[] = [], opts: Partial<RenderFrame> = {}): RenderFrame {
  const actors = [actor(0, 2.5, 2.5), actor(1, 4, 2.5), actor(2, 6, 3, { synced: false, spark: { x: 5, y: 3 } }), actor(3, 7, 2, { life: 'ghost' })];
  const snap = snapshot(beat, actors, [boss(8, 3)]);
  return {
    snap,
    prev: snap,
    alpha: 1,
    dt: 1 / 60,
    mode,
    events,
    worldRate: 1,
    music: music(beat, Math.floor(beat / 4) % 4),
    active: mode === 'record' ? 0 : null,
    ...opts,
  };
}

/** Every SimEventType declared in src/core/types.ts, parsed from the source so new members are caught. */
export async function declaredEventTypes(): Promise<SimEventType[]> {
  const src = typesSource;
  const m = /export type SimEventType\s*=([\s\S]*?);/.exec(src);
  if (!m) throw new Error('SimEventType union not found in src/core/types.ts');
  // Comments in the union mention other quoted words ("a 'repeat' tape"), so strip them first.
  const body = m[1].replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/.*$/gm, '');
  const names = [...body.matchAll(/\|\s*'([A-Za-z0-9_]+)'/g)].map((x) => x[1]);
  return names as SimEventType[];
}

/** One event of each type with plausible fields. */
export function eventOf(type: SimEventType, power = 20, tape: TapeIndex = 1): SimEvent {
  return { sub: 1000, type, x: 4, y: 2.5, tape, id: 'e1', dir: 0.7, power, detail: type === 'swing' ? 'heavy' : 'on' };
}
