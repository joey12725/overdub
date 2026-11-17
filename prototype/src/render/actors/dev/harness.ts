/**
 * Standalone visual harness for the actor layer: its own scene, camera, lights and fake snapshots,
 * independent of the renderer shell. Open /src/render/actors/dev/harness.html under `npx vite`.
 * Query params: ?scene=<name>  &zoom=<n>  &still=1 (freeze presentation time for screenshots).
 */
import * as THREE from 'three';
import type { MusicPulse, RenderFrame } from '../../../contracts';
import type {
  ActorSnap,
  AnimState,
  EnemySnap,
  EnemyType,
  FrameSnapshot,
  LevelDef,
  LifeState,
  MeleeWeaponDef,
  ProjectileSnap,
  RangedWeaponDef,
  ResolvedLoadout,
  StatMods,
  TapeIndex,
} from '../../../core/types';
import type { RenderCtx, RenderLayer, ThemePalette } from '../../layer';
import { createActorLayer } from '../index';

// ───────────── fixtures ─────────────

const PALETTE: ThemePalette = {
  theme: 'upper',
  background: 0x2a2433,
  fog: 0x2a2433,
  floor: 0xcdb99a,
  floorAlt: 0xbba684,
  wall: 0xa8977d,
  wallTop: 0xd8c7a6,
  metal: 0x4a4d55,
  trim: 0x2b2a2e,
  hazard: 0xffc21a,
  foliage: 0x5d8c3a,
  neonA: 0x3ee8ff,
  neonB: 0xff3ea8,
  neonC: 0x9a5cff,
  graffiti: 0xe84fb0,
  ink: 0x17121c,
  keyLight: 0xfff1d8,
  keyIntensity: 1.6,
  ambient: 0xb9b1d6,
  ambientIntensity: 0.9,
  bloom: 0.6,
};

function melee(style: MeleeWeaponDef['style'], reach: number, arcDeg: number): MeleeWeaponDef {
  return {
    reach,
    arcDeg,
    light: { windup: 8, active: 6, recover: 12, impact: 1, moveMul: 0.6 },
    heavy: { windup: 22, active: 8, recover: 22, impact: 2.2, moveMul: 0.3 },
    damageEff: 1,
    knockbackEff: 1,
    staggerEff: 1,
    style,
  };
}

const RANGED: RangedWeaponDef = {
  archetype: 'pierce',
  speed: 14,
  range: 8,
  impact: 1,
  commit: 18,
  cooldown: 30,
  pierce: 2,
  passesWalls: false,
  lobbed: false,
  count: 1,
  spreadDeg: 0,
  turnRate: 0,
  blast: 0,
};

const MODS: Required<StatMods> = {
  moveSpeed: 1,
  accel: 1,
  momentumRetention: 1,
  dodgeDistance: 1,
  dodgeIframes: 1,
  dodgeCooldown: 1,
  meleeImpact: 1,
  damage: 1,
  knockback: 1,
  knockbackCap: 1,
  stagger: 1,
  approachBonus: 1,
  sparkSpeed: 1,
  interactRadiusAdd: 0,
  projectileSpeed: 1,
  rangedCooldown: 1,
};

function loadout(m: MeleeWeaponDef, looks: ResolvedLoadout['looks'] = {}): ResolvedLoadout {
  return {
    loadout: { helmet: 'h', top: 't', pants: 'p', shoes: 's', melee: 'm', ranged: 'r' },
    mods: MODS,
    abilities: [],
    melee: m,
    ranged: RANGED,
    looks,
  };
}

const LEVEL: LevelDef = {
  id: 'harness',
  index: 0,
  name: 'Harness',
  tagline: '',
  theme: 'upper',
  bpm: 120,
  bars: 8,
  horizonBars: 16,
  maxTapes: 4,
  speeds: [1],
  endModes: ['stop'],
  map: ['.'],
  start: { x: 0, y: 0 },
  entities: [
    { kind: 'enemy', id: 'g', type: 'grunt', x: 0, y: 0 },
    { kind: 'enemy', id: 'b', type: 'boss', x: 0, y: 0 },
  ],
  objective: { type: 'eliminate', text: '' },
  music: {
    root: 0,
    scale: 'minor',
    progression: [0],
    tracks: [
      { role: 'bass', formula: 'a' },
      { role: 'drums', formula: 'a' },
      { role: 'melody', formula: 'a' },
      { role: 'chord', formula: 'a' },
    ],
  },
  loot: [],
  briefing: [],
};

// ───────────── snapshot builders ─────────────

interface ActorOpts {
  tape: TapeIndex;
  x: number;
  y: number;
  facing?: number;
  anim?: AnimState;
  tick?: number;
  life?: LifeState;
  synced?: boolean;
  live?: boolean;
  iframes?: boolean;
  spark?: { x: number; y: number };
  vx?: number;
  vy?: number;
  ended?: boolean;
  traversal?: number;
}

function actor(o: ActorOpts): ActorSnap {
  return {
    tape: o.tape,
    live: o.live ?? false,
    x: o.x,
    y: o.y,
    facing: o.facing ?? Math.PI / 2,
    anim: o.anim ?? 'idle',
    life: o.life ?? 'alive',
    synced: o.synced ?? true,
    spark: o.spark,
    iframes: o.iframes ?? false,
    phase: { tick: o.tick ?? 0, dir: o.ended ? 0 : 1, traversal: o.traversal ?? 0, ended: o.ended ?? false },
    vx: o.vx ?? 0,
    vy: o.vy ?? 0,
  };
}

/** Cycle through a sequence of [anim, ticks] repeatedly; returns the anim and a tick counter. */
function sequence(t: number, seq: [AnimState, number][]): { anim: AnimState; tick: number } {
  const total = seq.reduce((s, [, n]) => s + n, 0);
  const tick = t * 60;
  let k = tick % total;
  for (const [a, n] of seq) {
    if (k < n) return { anim: a, tick };
    k -= n;
  }
  return { anim: seq[0][0], tick };
}

function enemy(id: string, type: EnemyType, x: number, y: number, extra: Partial<EnemySnap> = {}): EnemySnap {
  return {
    id,
    type,
    x,
    y,
    facing: -Math.PI / 2,
    hp: 1,
    maxHp: 1,
    alive: true,
    state: 'idle',
    stateT: 0,
    ...extra,
  };
}

/** A readable 5-second enemy loop: idle → move → telegraph → attack → stagger. */
function enemyCycle(t: number, offset: number): Pick<EnemySnap, 'state' | 'stateT'> & { dx: number; hpLoss: number } {
  const P = 5;
  const k = (t + offset) % P;
  if (k < 0.8) return { state: 'idle', stateT: k / 0.8, dx: 0, hpLoss: 0 };
  if (k < 1.8) return { state: 'move', stateT: (k - 0.8) / 1, dx: Math.sin((k - 0.8) * Math.PI) * 0.4, hpLoss: 0 };
  if (k < 3.0) return { state: 'telegraph', stateT: (k - 1.8) / 1.2, dx: 0, hpLoss: 0 };
  if (k < 3.5) return { state: 'attack', stateT: (k - 3.0) / 0.5, dx: 0, hpLoss: 0 };
  if (k < 4.3) return { state: 'stagger', stateT: (k - 3.5) / 0.8, dx: 0, hpLoss: 1 };
  return { state: 'idle', stateT: 0, dx: 0, hpLoss: 1 };
}

// ───────────── scenes ─────────────

interface LayerScript {
  loadout: ResolvedLoadout;
  frame: (t: number) => Omit<FrameSnapshot, 'sub' | 'beat' | 'mechs' | 'objective'>;
  active?: TapeIndex | null;
}

interface SceneDef {
  title: string;
  center: [number, number];
  height: number;
  layers: LayerScript[];
  labels: { x: number; y: number; text: string }[];
  walls?: { x: number; y: number; w: number; d: number; h: number }[];
}

const BLADE = melee('blade', 1.4, 110);

function animsScene(): SceneDef {
  // Twelve AnimStates across three layers (each layer draws four selves).
  const cells: { label: string; f: (t: number, x: number, y: number, tape: TapeIndex) => ActorSnap }[] = [
    { label: 'idle', f: (t, x, y, tape) => actor({ tape, x, y, anim: 'idle', tick: t * 60 }) },
    {
      label: 'run',
      f: (t, x, y, tape) => {
        const a = t * 1.6;
        const r = 0.45;
        return actor({ tape, x: x + Math.cos(a) * r, y: y + Math.sin(a) * r, facing: a + Math.PI / 2, anim: 'run', tick: t * 60, vx: -Math.sin(a) * 0.72, vy: Math.cos(a) * 0.72 });
      },
    },
    { label: 'light (windup/active/recover)', f: (t, x, y, tape) => actor({ tape, x, y, ...sequence(t, [['lightWindup', 8], ['lightActive', 6], ['lightRecover', 12], ['idle', 24]]) }) },
    { label: 'heavy (windup/active/recover)', f: (t, x, y, tape) => actor({ tape, x, y, ...sequence(t, [['heavyWindup', 22], ['heavyActive', 8], ['heavyRecover', 22], ['idle', 24]]) }) },
    {
      label: 'dodge (i-frames)',
      f: (t, x, y, tape) => {
        const s = sequence(t, [['dodge', 18], ['idle', 30]]);
        const k = (t * 60) % 48;
        const d = s.anim === 'dodge' ? (k / 18) * 1.0 : 1.0 - ((k - 18) / 30) * 1.0;
        return actor({ tape, x: x - 0.5 + d, y, facing: 0, ...s, iframes: s.anim === 'dodge' && k > 2 && k < 15, vx: s.anim === 'dodge' ? 3.3 : 0 });
      },
    },
    { label: 'ranged (wrist device)', f: (t, x, y, tape) => actor({ tape, x, y, ...sequence(t, [['ranged', 18], ['idle', 30]]) }) },
    { label: 'interact (reach)', f: (t, x, y, tape) => actor({ tape, x, y, ...sequence(t, [['interact', 16], ['idle', 30]]) }) },
    { label: 'stopped (held, desaturated)', f: (_t, x, y, tape) => actor({ tape, x, y, anim: 'stopped', tick: 0, ended: true }) },
    {
      label: 'death transition (loops)',
      f: (t, x, y, tape) => {
        const k = t % 3;
        return actor({ tape, x, y, anim: 'idle', tick: t * 60, life: k < 1 ? 'alive' : 'ghost', traversal: Math.floor(t / 3) });
      },
    },
    { label: 'light, facing camera', f: (t, x, y, tape) => actor({ tape, x, y, facing: Math.PI / 4, ...sequence(t, [['lightWindup', 8], ['lightActive', 6], ['lightRecover', 12], ['idle', 24]]) }) },
    { label: 'heavy, facing camera', f: (t, x, y, tape) => actor({ tape, x, y, facing: Math.PI / 4, ...sequence(t, [['heavyWindup', 22], ['heavyActive', 8], ['heavyRecover', 22], ['idle', 24]]) }) },
    { label: 'run in place (side)', f: (t, x, y, tape) => actor({ tape, x, y, facing: 0, anim: 'run', tick: t * 60, vx: 4 }) },
  ];
  const layers: LayerScript[] = [];
  const labels: SceneDef['labels'] = [];
  for (let L = 0; L < 3; L++) {
    const group = cells.slice(L * 4, L * 4 + 4);
    const pos = group.map((_, i) => [i * 2.6 - 3.9, L * 2.6 - 2.6] as [number, number]);
    group.forEach((c, i) => labels.push({ x: pos[i][0], y: pos[i][1] + 0.75, text: c.label }));
    layers.push({
      loadout: loadout(BLADE),
      active: null,
      frame: (t) => ({
        actors: group.map((c, i) => {
          const a = c.f(t, pos[i][0], pos[i][1], i as TapeIndex);
          // The run cell needs real displacement for stride; others stand.
          return a;
        }),
        enemies: [],
        projectiles: [],
      }),
    });
  }
  return { title: 'Animations', center: [0, 0], height: 9, layers, labels };
}

function statesScene(): SceneDef {
  const labels: SceneDef['labels'] = [];
  const P = (x: number, y: number, text: string) => {
    labels.push({ x, y: y + 0.75, text });
    return [x, y] as const;
  };
  const a1 = P(-4.2, -1.6, 'A live, alive');
  const b1 = P(-1.4, -1.6, 'B playback, alive');
  const c1 = P(1.4, -1.6, 'C recGhost (dead, performing)');
  const d1 = P(4.2, -1.6, 'D playback ghost (inert)');
  const a2 = P(-3.2, 1.6, 'A desynced projection + spark');
  const b2 = P(1.2, 1.6, 'B stopped');
  const c2 = P(4.2, 1.6, 'C resync merge (loops)');
  const run = (t: number, cx: number, cy: number, r: number, sp = 1.2) => {
    const a = t * sp;
    return { x: cx + Math.cos(a) * r, y: cy + Math.sin(a) * r, facing: a + Math.PI / 2, anim: 'run' as AnimState, vx: -Math.sin(a) * r * sp, vy: Math.cos(a) * r * sp };
  };
  return {
    title: 'States',
    center: [0, 0],
    height: 8,
    walls: [{ x: -1.75, y: 1.6, w: 0.5, d: 2.2, h: 1.2 }],
    labels,
    layers: [
      {
        loadout: loadout(BLADE),
        active: 0,
        frame: (t) => ({
          actors: [
            actor({ tape: 0, live: true, ...run(t, a1[0], a1[1], 0.35), tick: t * 60 }),
            actor({ tape: 1, ...run(t + 1, b1[0], b1[1], 0.35), tick: t * 60 }),
            actor({ tape: 2, life: 'recGhost', live: false, ...run(t + 2, c1[0], c1[1], 0.35), tick: t * 60 }),
            actor({ tape: 3, life: 'ghost', ...run(t + 3, d1[0], d1[1], 0.35), tick: t * 60 }),
          ],
          enemies: [],
          projectiles: [],
        }),
      },
      {
        loadout: loadout(BLADE),
        active: null,
        frame: (t) => {
          // Desynced projection walks through the wall; its spark detours around the end.
          const k = (t * 0.25) % 1;
          const px = a2[0] + k * 3.2;
          const py = a2[1];
          const sk = Math.max(0, Math.min(1, (k - 0.1) / 0.9));
          const route = [
            [a2[0], a2[1]],
            [-2.2, 2.9],
            [-1.3, 2.9],
            [px, py],
          ];
          const seg = sk * 3;
          const si = Math.min(2, Math.floor(seg));
          const f = seg - si;
          const sx = route[si][0] + (route[si + 1][0] - route[si][0]) * f;
          const sy = route[si][1] + (route[si + 1][1] - route[si][1]) * f;
          const mk = t % 3;
          return {
            actors: [
              actor({ tape: 0, x: px, y: py, facing: 0, anim: 'run', tick: t * 60, vx: 0.8, synced: false, spark: { x: sx, y: sy } }),
              actor({ tape: 1, x: b2[0], y: b2[1], anim: 'stopped', ended: true }),
              actor({ tape: 2, x: c2[0], y: c2[1], anim: 'idle', tick: t * 60, synced: mk > 1.5, spark: mk > 1.5 ? undefined : { x: c2[0] - 1.2 + mk * 0.8, y: c2[1] + 0.6 - mk * 0.4 } }),
            ],
            enemies: [],
            projectiles: [],
          };
        },
      },
    ],
  };
}

function cassettesScene(): SceneDef {
  const labels: SceneDef['labels'] = [];
  const xs = [-3.3, -1.1, 1.1, 3.3];
  ['A', 'B', 'C', 'D'].forEach((n, i) => labels.push({ x: xs[i], y: 0.75, text: `Tape ${n}${i === 0 ? ' (live)' : ''}` }));
  return {
    title: 'Four selves, one Moxie',
    center: [0, 0],
    height: 4.2,
    labels,
    layers: [
      {
        loadout: loadout(BLADE),
        active: 0,
        frame: (t) => ({
          actors: xs.map((x, i) => actor({ tape: i as TapeIndex, live: i === 0, x, y: 0, facing: Math.PI / 4 + 0.35, anim: 'idle', tick: t * 60 + i * 20 })),
          enemies: [],
          projectiles: [],
        }),
      },
    ],
  };
}

function weaponsScene(): SceneDef {
  const styles: [MeleeWeaponDef['style'], number, number][] = [
    ['blade', 1.4, 110],
    ['blunt', 1.2, 70],
    ['whip', 2.4, 50],
    ['gauntlet', 0.9, 60],
  ];
  const labels: SceneDef['labels'] = [];
  const layers: LayerScript[] = styles.map(([s, reach, arc], i) => {
    const x = i * 2.9 - 4.35;
    labels.push({ x, y: -1.2 + 0.75, text: `${s} light (reach ${reach}, ${arc}°)` });
    labels.push({ x, y: 1.5 + 0.75, text: `${s} heavy` });
    return {
      loadout: loadout(melee(s, reach, arc)),
      active: null,
      frame: (t: number) => ({
        actors: [
          actor({ tape: i as TapeIndex, x, y: -1.2, facing: Math.PI / 4 + 0.4, ...sequence(t, [['lightWindup', 8], ['lightActive', 6], ['lightRecover', 12], ['idle', 30]]) }),
          actor({ tape: ((i + 1) % 4) as TapeIndex, x, y: 1.5, facing: Math.PI / 4 + 0.4, ...sequence(t, [['heavyWindup', 22], ['heavyActive', 8], ['heavyRecover', 22], ['idle', 30]]) }),
        ],
        enemies: [],
        projectiles: [],
      }),
    };
  });
  return { title: 'Weapons', center: [0, 0.2], height: 7, layers, labels };
}

function gearScene(): SceneDef {
  const sets: { label: string; looks: ResolvedLoadout['looks'] }[] = [
    { label: 'baseline', looks: {} },
    { label: 'visor + armored top', looks: { helmet: { variant: 'visor', color: '#2d3a55' }, top: { variant: 'armored' } } },
    { label: 'cap + shorts + runners', looks: { helmet: { variant: 'cap', color: '#d23c6a' }, pants: { variant: 'shorts', color: '#3d5a78' }, shoes: { variant: 'runners', color: '#e0e4ea' } } },
    { label: 'beanie + vest + boots', looks: { helmet: { variant: 'beanie', color: '#5b8c3a' }, top: { variant: 'vest', color: '#6a4c8c' }, shoes: { variant: 'boots' } } },
    { label: 'goggles + tank + mag', looks: { helmet: { variant: 'goggles', color: '#8a5a2a' }, top: { variant: 'tank', color: '#2a2a2a' }, shoes: { variant: 'mag' } } },
    { label: 'mask + joggers', looks: { helmet: { variant: 'mask', color: '#1e1e24' }, pants: { variant: 'joggers', color: '#3a3a40' } } },
    { label: 'antenna + armored pants', looks: { helmet: { variant: 'antenna', color: '#9aa0a6' }, pants: { variant: 'armored' } } },
  ];
  const labels: SceneDef['labels'] = [];
  const layers = sets.map((s, i) => {
    const x = (i % 4) * 2.2 - 3.3;
    const y = Math.floor(i / 4) * 2.4 - 1.2;
    labels.push({ x, y: y + 0.75, text: s.label });
    return {
      loadout: loadout(BLADE, s.looks),
      active: null,
      frame: (t: number) => ({
        actors: [actor({ tape: (i % 4) as TapeIndex, x, y, facing: Math.PI / 4 + 0.3, anim: 'idle' as AnimState, tick: t * 60 })],
        enemies: [],
        projectiles: [],
      }),
    };
  });
  return { title: 'Gear looks', center: [0, 0], height: 6.4, layers, labels };
}

function enemiesScene(): SceneDef {
  const types: EnemyType[] = ['grunt', 'stalker', 'turret', 'shielder', 'brute', 'drone'];
  const labels: SceneDef['labels'] = [];
  const pos = types.map((_, i) => [(i % 3) * 3.6 - 3.6, i < 3 ? -2.6 : 3.0] as [number, number]);
  types.forEach((ty, i) => labels.push({ x: pos[i][0], y: pos[i][1] + 0.9, text: ty }));
  const selves: [number, number][] = [
    [-4.4, 0.3],
    [-1.5, 0.3],
    [1.5, 0.3],
    [4.4, 0.3],
  ];
  return {
    title: 'Enemies',
    center: [0, 0.2],
    height: 10,
    labels,
    layers: [
      {
        loadout: loadout(BLADE),
        active: 0,
        frame: (t) => {
          const enemies: EnemySnap[] = types.map((ty, i) => {
            const c = enemyCycle(t, i * 0.7);
            const multi = ty === 'brute' ? 3 : ty === 'drone' || ty === 'shielder' ? 2 : 1;
            const target = (i % 4) as TapeIndex;
            const [sx, sy] = selves[target];
            const [ex, ey] = pos[i];
            const facing = Math.atan2(sy - ey, sx - ex);
            const loop = Math.floor((t + i * 0.7) / 5);
            // Grunt and stalker die at the end of every other loop to show the death burst.
            const dies = (ty === 'grunt' || ty === 'stalker') && loop % 2 === 1 && (t + i * 0.7) % 5 > 4.3;
            return enemy(`${ty}${loop}`, ty, ex + c.dx, ey, {
              facing,
              state: dies ? 'dead' : c.state,
              stateT: c.stateT,
              alive: !dies,
              maxHp: multi,
              hp: Math.max(1, multi - c.hpLoss),
              target,
              shield: ty === 'shielder' ? c.state !== 'stagger' : undefined,
            });
          });
          return {
            actors: selves.map(([x, y], i) => actor({ tape: i as TapeIndex, live: i === 0, x, y, facing: Math.PI / 4, anim: 'idle', tick: t * 60 })),
            enemies,
            projectiles: [],
          };
        },
      },
    ],
  };
}

function bossScene(): SceneDef {
  const labels: SceneDef['labels'] = [
    { x: -4.2, y: -0.4, text: 'phase 0 (sealed)' },
    { x: 0, y: -0.4, text: 'phase 1 (opened)' },
    { x: 4.2, y: -0.4, text: 'phase 2 (broken, orbiting)' },
    { x: 0, y: 4.2, text: 'acting on memory of tape C' },
  ];
  return {
    title: 'Boss',
    center: [0, 1.4],
    height: 10.5,
    labels,
    layers: [
      {
        loadout: loadout(BLADE),
        active: null,
        frame: (t) => {
          const c = enemyCycle(t, 0);
          const boss = (id: string, x: number, y: number, phase: number, recall: boolean): EnemySnap =>
            enemy(id, 'boss', x, y, {
              facing: Math.PI / 4,
              hp: 30 - phase * 10 - (Math.floor(t / 2) % 4),
              maxHp: 30,
              bossPhase: phase,
              bossRecall: recall,
              bossRecallTape: recall ? 2 : undefined,
              state: recall ? 'telegraph' : c.state,
              stateT: recall ? (t % 2) / 2 : c.stateT,
              target: recall ? 2 : 1,
            });
          return {
            actors: [actor({ tape: 1, x: 1.4, y: 6.0, facing: -Math.PI / 2, anim: 'idle', tick: t * 60 }), actor({ tape: 2, x: -2.4, y: 5.4, facing: 0, anim: 'idle', tick: t * 60 })],
            enemies: [boss('b0', -4.2, -2, 0, false), boss('b1', 0, -2, 1, false), boss('b2', 4.2, -2, 2, false), boss('bm', 0, 2.6, 2, true)],
            projectiles: [],
          };
        },
      },
    ],
  };
}

function projectilesScene(): SceneDef {
  const kinds: ProjectileSnap['archetype'][] = ['missile', 'pierce', 'phase', 'arc', 'burst', 'bolt', 'shock'];
  const labels: SceneDef['labels'] = [];
  const rows = kinds.map((k, i) => {
    const y = i * 1.0 - 3.0;
    labels.push({ x: -4.6, y: y + 0.1, text: k });
    return y;
  });
  return {
    title: 'Projectiles',
    center: [0, 0],
    height: 8.5,
    labels,
    walls: [{ x: 0.5, y: rows[2], w: 0.4, d: 0.8, h: 1.2 }],
    layers: [
      {
        loadout: loadout(BLADE),
        active: null,
        frame: (t) => {
          const projectiles: ProjectileSnap[] = [];
          kinds.forEach((k, i) => {
            const speed = k === 'missile' ? 1.2 : k === 'arc' ? 2.4 : k === 'pierce' ? 5 : 3;
            const span = 7;
            const life = span / speed;
            const loop = Math.floor(t / life);
            const f = (t % life) / life;
            const x = -3.5 + f * span;
            const enemyOwned = k === 'bolt' || k === 'shock';
            const owner = enemyOwned ? { enemy: 'g' } : { tape: (i % 4) as TapeIndex };
            if (k === 'burst') {
              for (let j = 0; j < 3; j++) {
                const sp = (j - 1) * 0.12;
                projectiles.push({ id: 1000 + loop * 10 + j, owner, archetype: k, x: -3.5 + f * 3, y: rows[i] + Math.sin(sp) * f * 3, z: 0, dir: sp });
              }
              return;
            }
            const z = k === 'arc' ? 4 * 1.4 * f * (1 - f) : 0;
            projectiles.push({ id: i * 100 + loop, owner, archetype: k, x, y: rows[i], z, dir: 0, targetId: k === 'missile' ? 'tgt' : undefined });
          });
          return {
            actors: [],
            enemies: [enemy('tgt', 'grunt', 4.4, rows[0], { facing: Math.PI })],
            projectiles,
          };
        },
      },
    ],
  };
}

function closeupScene(): SceneDef {
  return {
    title: 'Close-up',
    center: [0, 0],
    height: 1.6,
    labels: [],
    layers: [
      {
        loadout: loadout(BLADE),
        active: 0,
        frame: (t) => ({
          actors: [actor({ tape: 1, live: false, x: 0, y: 0, facing: Math.PI / 4 + Math.sin(t * 0.4) * 1.2 + Number(params.get("f") ?? "0"), anim: 'idle', tick: t * 60 })],
          enemies: [],
          projectiles: [],
        }),
      },
    ],
  };
}

const SCENES: Record<string, () => SceneDef> = {
  anims: animsScene,
  states: statesScene,
  cassettes: cassettesScene,
  weapons: weaponsScene,
  gear: gearScene,
  enemies: enemiesScene,
  boss: bossScene,
  projectiles: projectilesScene,
  closeup: closeupScene,
};

// ───────────── runtime ─────────────

const params = new URLSearchParams(location.search);
if (params.get('dark') === '1') {
  // Lower-level look: dark rune-inscribed metal under magenta/cyan neon.
  Object.assign(PALETTE, {
    theme: 'lower',
    background: 0x0d0b14,
    floor: 0x2a2734,
    floorAlt: 0x24212d,
    wall: 0x3a3646,
    keyLight: 0xc9b8ff,
    keyIntensity: 1.1,
    ambient: 0x5a4a8a,
    ambientIntensity: 0.6,
  });
}
const renderer = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true });
renderer.setPixelRatio(Math.min(2, window.devicePixelRatio));
renderer.setSize(window.innerWidth, window.innerHeight);
renderer.outputColorSpace = THREE.SRGBColorSpace;
document.body.appendChild(renderer.domElement);

const scene = new THREE.Scene();
scene.background = new THREE.Color(PALETTE.background);
const camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0.1, 200);
scene.add(new THREE.HemisphereLight(0xfff4e0, 0x6a5a80, 1.6));
const sun = new THREE.DirectionalLight(0xfff1d8, 1.8);
sun.position.set(-5, 10, 6);
scene.add(sun);

function makeRamp(): THREE.DataTexture {
  const v = [0, 0, 150, 255, 255];
  const data = new Uint8Array(v.length * 4);
  v.forEach((x, i) => data.set([x, x, x, 255], i * 4));
  const t = new THREE.DataTexture(data, v.length, 1, THREE.RGBAFormat);
  t.magFilter = THREE.NearestFilter;
  t.minFilter = THREE.NearestFilter;
  t.needsUpdate = true;
  return t;
}
const ramp = makeRamp();

const world = new THREE.Group();
scene.add(world);
let layers: { layer: RenderLayer; ctx: RenderCtx; script: LayerScript; prev: FrameSnapshot | null }[] = [];
let current: SceneDef | null = null;
const labelsEl = document.getElementById('labels')!;
const barEl = document.getElementById('bar')!;

function buildFloor(def: SceneDef): void {
  const floor = new THREE.Group();
  const span = Math.ceil(def.height * 1.6);
  const geo = new THREE.BoxGeometry(1, 0.2, 1);
  const m1 = new THREE.MeshLambertMaterial({ color: PALETTE.floor });
  const m2 = new THREE.MeshLambertMaterial({ color: PALETTE.floorAlt });
  for (let x = -span; x <= span; x++)
    for (let z = -span; z <= span; z++) {
      const tile = new THREE.Mesh(geo, (x + z) & 1 ? m1 : m2);
      tile.position.set(x + 0.5 + Math.floor(def.center[0]), -0.1, z + 0.5 + Math.floor(def.center[1]));
      floor.add(tile);
    }
  for (const w of def.walls ?? []) {
    const wall = new THREE.Mesh(new THREE.BoxGeometry(w.w, w.h, w.d), new THREE.MeshLambertMaterial({ color: PALETTE.wall }));
    wall.position.set(w.x, w.h / 2, w.y);
    floor.add(wall);
  }
  world.add(floor);
}

function load(name: string): void {
  for (const l of layers) l.layer.dispose();
  world.clear();
  labelsEl.innerHTML = '';
  const def = (SCENES[name] ?? SCENES.anims)();
  current = def;
  buildFloor(def);
  layers = def.layers.map((script) => {
    const root = new THREE.Group();
    world.add(root);
    const ctx: RenderCtx = {
      scene,
      camera,
      palette: PALETTE,
      level: LEVEL,
      loadout: script.loadout,
      root,
      toonRamp: ramp,
      quality: 'high',
      shake: () => {},
      focus: () => {},
    };
    const layer = createActorLayer();
    layer.loadLevel(ctx);
    return { layer, ctx, script, prev: null };
  });
  for (const l of def.labels) {
    const el = document.createElement('div');
    el.className = 'lbl';
    el.textContent = l.text;
    (el as HTMLElement & { _w?: [number, number] })._w = [l.x, l.y];
    labelsEl.appendChild(el);
  }
  for (const b of barEl.querySelectorAll('button')) b.classList.toggle('on', b.textContent === name);
  resize();
}

function resize(): void {
  const w = window.innerWidth;
  const h = window.innerHeight;
  renderer.setSize(w, h);
  const def = current;
  if (!def) return;
  const zoom = Number(params.get('zoom') ?? '1') || 1;
  const vh = def.height / zoom;
  const vw = vh * (w / h);
  camera.left = -vw / 2;
  camera.right = vw / 2;
  camera.top = vh / 2;
  camera.bottom = -vh / 2;
  // Classic isometric: 45° yaw, ~35° pitch.
  const [cx, cz] = def.center;
  camera.position.set(cx + 20, 20 * 0.82, cz + 20);
  camera.lookAt(cx, 0.4, cz);
  camera.updateProjectionMatrix();
}

for (const name of Object.keys(SCENES)) {
  const b = document.createElement('button');
  b.textContent = name;
  b.onclick = () => {
    params.set('scene', name);
    history.replaceState(null, '', `?${params.toString()}`);
    load(name);
  };
  barEl.appendChild(b);
}
window.addEventListener('resize', resize);

const pulse: MusicPulse = { beat: 0, beatPulse: 0, barPulse: 0, levels: [0, 0, 0, 0], pitches: [0, 0, 0, 0], chord: 0 };
let last = performance.now();
let t = Number(params.get('t') ?? '0') || 0;
const still = params.get('still') === '1';
const tmpV = new THREE.Vector3();

function tick(now: number): void {
  const dt = Math.min(0.05, (now - last) / 1000);
  last = now;
  if (!still) t += dt;
  const beat = t * 2;
  pulse.beat = beat;
  pulse.beatPulse = Math.pow(1 - (beat % 1), 3);
  pulse.barPulse = Math.pow(1 - ((beat / 4) % 1), 3);
  for (const l of layers) {
    const partial = l.script.frame(t);
    const snap: FrameSnapshot = {
      sub: Math.floor(t * 240),
      beat,
      mechs: [],
      objective: { complete: false, progress: 0, survivors: 4 },
      ...partial,
    };
    const frame: RenderFrame = {
      snap,
      prev: l.prev ?? snap,
      alpha: 1,
      dt: still ? 1 / 60 : dt,
      mode: 'review',
      events: [],
      worldRate: 1,
      music: pulse,
      active: l.script.active ?? null,
    };
    l.layer.update(frame, l.ctx);
    l.prev = snap;
  }
  renderer.render(scene, camera);
  const w = window.innerWidth;
  const h = window.innerHeight;
  for (const el of labelsEl.children) {
    const p = (el as HTMLElement & { _w?: [number, number] })._w;
    if (!p) continue;
    // Screen-down on an isometric floor is +x+z: anchor labels just below each subject.
    tmpV.set(p[0] - 0.75 + 0.55, 0, p[1] - 0.75 + 0.55).project(camera);
    (el as HTMLElement).style.left = `${(tmpV.x * 0.5 + 0.5) * w}px`;
    (el as HTMLElement).style.top = `${(-tmpV.y * 0.5 + 0.5) * h}px`;
  }
  (window as unknown as { __frames: number }).__frames = ((window as unknown as { __frames: number }).__frames ?? 0) + 1;
  requestAnimationFrame(tick);
}

load(params.get('scene') ?? 'anims');
requestAnimationFrame(tick);
