/**
 * Standalone visual harness for the renderer shell: a hard-coded demo level and fake snapshots
 * (mechanisms cycling, selves walking loops) so the environment can be eyeballed without the game.
 *
 * Serve with `npx vite` and open /src/render/dev/harness.html.
 * Query params: theme=upper|mid|lower|core, mode=record|review|cinematic|idle, quality=low|high,
 * t=<seconds> (freeze the fake clock at a time; useful for screenshots), pulse=1 (pulse the
 * music-reactive materials from the fake beat, standing in for the fx layer).
 * Keys: 1-4 theme, M cycle mode, Q toggle quality, S shake, P pause.
 */
import type { ActorSnap, EnemySnap, FrameSnapshot, LevelDef, MechSnap, ResolvedLoadout, SimEvent, TapeIndex, Theme } from '../../core/types';
import type { MusicPulse, RenderFrame, ViewMode } from '../../contracts';
import { createRenderer } from '../index';

const MAP = [
  '##########        ',
  '#....,,,.#        ',
  '#.~~..,,.#########',
  '#.~~.....,.......#',
  '#....=====...::..#',
  '#........#...::..#',
  '####.#####.......#',
  '   #.#   #...~~..#',
  '   #.#   #.......#',
  '   #.#####.#######',
  '   #..........#   ',
  '   ############   ',
];

function demoLevel(theme: Theme): LevelDef {
  return {
    id: `harness-${theme}`,
    index: 0,
    name: 'Harness',
    tagline: 'render harness',
    theme,
    bpm: 120,
    bars: 8,
    horizonBars: 16,
    maxTapes: 4,
    speeds: [1],
    endModes: ['stop'],
    map: MAP,
    start: { x: 5.5, y: 3.5 },
    entities: [
      { kind: 'switch', id: 'lever', x: 2.5, y: 4.5 },
      { kind: 'door', id: 'gate', cells: [{ c: 9, r: 3 }], openWhen: { sig: 'lever' } },
      { kind: 'plate', id: 'pad', c: 16, r: 4 },
      { kind: 'door', id: 'gate2', cells: [{ c: 4, r: 6 }], openWhen: { sig: 'pad' } },
      { kind: 'plate', id: 'heavyPad', c: 12, r: 8, heavy: true },
      { kind: 'breakable', id: 'wall', c: 10, r: 9, threshold: 3 },
      { kind: 'laser', id: 'zap', from: { x: 10.5, y: 5.5 }, to: { x: 16.5, y: 5.5 }, onWhen: { beat: { every: 4, from: 0, to: 2 } } },
      { kind: 'core', id: 'core1', x: 11.5, y: 7.5 },
      { kind: 'exit', id: 'exit', c: 5, r: 10, w: 3, h: 1 },
      { kind: 'enemy', id: 'g1', type: 'grunt', x: 13.5, y: 3.5 },
      { kind: 'enemy', id: 't1', type: 'turret', x: 16.5, y: 7.5 },
      { kind: 'decor', type: 'graffiti', x: 3.5, y: 1.2, variant: 'smiley' },
      { kind: 'decor', type: 'graffiti', x: 12.5, y: 3.2, variant: 'MOXIE' },
      { kind: 'decor', type: 'graffiti', x: 1.2, y: 6.5, variant: 'star' },
      { kind: 'decor', type: 'vines', x: 6.5, y: 1.2 },
      { kind: 'decor', type: 'bush', x: 7.5, y: 2.6 },
      { kind: 'decor', type: 'crate', x: 16.4, y: 3.4, variant: 'stack' },
      { kind: 'decor', type: 'barrel', x: 15.6, y: 3.4 },
      { kind: 'decor', type: 'neon', x: 8.5, y: 1.4, variant: 'pink' },
      { kind: 'decor', type: 'lamp', x: 1.5, y: 3.5 },
      { kind: 'decor', type: 'runePanel', x: 1.4, y: 5.4 },
      { kind: 'decor', type: 'waveScreen', x: 8.5, y: 10.3 },
      { kind: 'decor', type: 'generator', x: 12.6, y: 10.5 },
      { kind: 'decor', type: 'console', x: 11.0, y: 2.4 },
      { kind: 'decor', type: 'vent', x: 15.4, y: 2.45 },
      { kind: 'decor', type: 'arch', x: 4.5, y: 7.6 },
      { kind: 'decor', type: 'pipe', x: 6.5, y: 5.4 },
      { kind: 'decor', type: 'rubble', x: 7.5, y: 4.4 },
      { kind: 'decor', type: 'chest', x: 5.5, y: 1.4, variant: 'open' },
      { kind: 'decor', type: 'cable', x: 3.6, y: 10.4 },
      { kind: 'decor', type: 'timeMachine', x: 14.5, y: 7.5 },
    ],
    objective: { type: 'reach', text: 'Reach the exit' },
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
    briefing: ['Harness'],
  };
}

const LOADOUT = {
  loadout: { helmet: 'h', top: 't', pants: 'p', shoes: 's', melee: 'm', ranged: 'r' },
  mods: {
    moveSpeed: 1, accel: 1, momentumRetention: 1, dodgeDistance: 1, dodgeIframes: 1, dodgeCooldown: 1, meleeImpact: 1, damage: 1,
    knockback: 1, knockbackCap: 1, stagger: 1, approachBonus: 1, sparkSpeed: 1, interactRadiusAdd: 0, projectileSpeed: 1, rangedCooldown: 1,
  },
  abilities: [],
  melee: {
    reach: 1.2, arcDeg: 120, damageEff: 1, knockbackEff: 1, staggerEff: 1, style: 'blade',
    light: { windup: 4, active: 4, recover: 8, impact: 1, moveMul: 0.5 },
    heavy: { windup: 10, active: 5, recover: 14, impact: 2, moveMul: 0.3 },
  },
  ranged: { archetype: 'missile', speed: 2, range: 12, impact: 1, commit: 6, cooldown: 60, pierce: 0, passesWalls: false, lobbed: false, count: 1, spreadDeg: 0, turnRate: 1, blast: 0 },
} as unknown as ResolvedLoadout;

const params = new URLSearchParams(location.search);
const THEMES: Theme[] = ['upper', 'mid', 'lower', 'core'];
const MODES: ViewMode[] = ['record', 'review', 'cinematic', 'idle'];
let theme = (THEMES.includes(params.get('theme') as Theme) ? params.get('theme') : 'upper') as Theme;
let mode = (MODES.includes(params.get('mode') as ViewMode) ? params.get('mode') : 'record') as ViewMode;
let quality: 'low' | 'high' = params.get('quality') === 'low' ? 'low' : 'high';
const frozen = params.has('t') ? Number(params.get('t')) : null;
const pulse = params.get('pulse') === '1';
let paused = false;

const stage = document.getElementById('stage')!;
const hud = document.getElementById('hud')!;
// layers=0 shows the shell alone (environment + mechanisms) without the actor / fx layers.
const renderer = createRenderer(params.get('layers') === '0' ? { layers: [] } : undefined);
stage.appendChild(renderer.canvas);
renderer.setQuality(quality);

function fit(): void {
  renderer.resize(stage.clientWidth, stage.clientHeight, window.devicePixelRatio || 1);
}
window.addEventListener('resize', fit);
fit();

let level = demoLevel(theme);
function load(): void {
  level = demoLevel(theme);
  renderer.loadLevel(level, LOADOUT);
}
load();

/** Closed loop the fake live self walks (tile centres). */
const LOOP: [number, number][] = [
  [5.5, 3.5],
  [7.5, 3.5],
  [8.5, 3.5],
  [10.5, 3.5],
  [12.5, 5.5],
  [12.5, 7.5],
  [10.5, 8.5],
  [10.5, 10.4],
  [6.5, 10.4],
  [4.5, 10.4],
  [4.5, 7.5],
  [4.5, 5.5],
  [3.5, 3.5],
];

function along(path: [number, number][], t: number): { x: number; y: number; facing: number } {
  const lens: number[] = [];
  let total = 0;
  for (let i = 0; i < path.length; i++) {
    const a = path[i];
    const b = path[(i + 1) % path.length];
    const l = Math.hypot(b[0] - a[0], b[1] - a[1]);
    lens.push(l);
    total += l;
  }
  let d = ((t % total) + total) % total;
  for (let i = 0; i < path.length; i++) {
    if (d <= lens[i]) {
      const a = path[i];
      const b = path[(i + 1) % path.length];
      const k = d / lens[i];
      return { x: a[0] + (b[0] - a[0]) * k, y: a[1] + (b[1] - a[1]) * k, facing: Math.atan2(b[1] - a[1], b[0] - a[0]) };
    }
    d -= lens[i];
  }
  return { x: path[0][0], y: path[0][1], facing: 0 };
}

function actor(tape: TapeIndex, live: boolean, t: number, speed: number, offset: number, life: ActorSnap['life'], synced = true): ActorSnap {
  const p = along(LOOP, t * speed + offset);
  return {
    tape,
    live,
    x: p.x,
    y: p.y,
    facing: p.facing,
    anim: 'run',
    life,
    synced,
    spark: synced ? undefined : { x: p.x - 1, y: p.y + 0.5 },
    iframes: false,
    phase: { tick: t * 60, dir: 1, traversal: 0, ended: false },
    vx: Math.cos(p.facing) * speed,
    vy: Math.sin(p.facing) * speed,
  };
}

function snapshot(t: number): FrameSnapshot {
  const beat = t * (level.bpm / 60);
  const lever = Math.floor(t / 4) % 2 === 1;
  const pad = Math.floor(t / 3) % 2 === 1;
  const doorT = (on: boolean, period: number) => {
    const phase = (t % period) / period;
    const k = Math.min(1, (phase * period) / 0.6);
    return on ? k : 1 - k;
  };
  const mechs: MechSnap[] = [
    { id: 'lever', kind: 'switch', on: lever },
    { id: 'gate', kind: 'door', on: lever, t: doorT(lever, 4) },
    { id: 'pad', kind: 'plate', on: pad },
    { id: 'heavyPad', kind: 'plate', on: Math.floor(t / 5) % 2 === 0 },
    { id: 'gate2', kind: 'door', on: pad, t: doorT(pad, 3) },
    { id: 'wall', kind: 'breakable', on: t % 16 > 6 },
    { id: 'zap', kind: 'laser', on: beat % 4 < 2 },
    { id: 'core1', kind: 'core', on: t % 20 > 10 },
    { id: 'exit', kind: 'exit', on: t % 10 > 7 },
  ];
  const enemies: EnemySnap[] = [
    { id: 'g1', type: 'grunt', x: 13.5 + Math.sin(t) * 0.8, y: 3.5, facing: Math.PI, hp: 1, maxHp: 1, alive: true, state: 'move', stateT: (t % 1) },
    { id: 't1', type: 'turret', x: 16.5, y: 7.5, facing: t, hp: 1, maxHp: 1, alive: true, state: 'idle', stateT: 0 },
  ];
  return {
    sub: Math.floor(t * 240),
    beat,
    actors: [actor(0, true, t, 2.2, 0, 'alive'), actor(1, false, t, 1.6, 9, 'alive'), actor(2, false, t, 1.2, 20, 'ghost'), actor(3, false, t, 1.8, 30, 'alive', false)],
    enemies,
    projectiles: [],
    mechs,
    objective: { complete: false, progress: 0.3, survivors: 3 },
  };
}

let clock = frozen ?? 0;
let prevSnap = snapshot(clock);
let last = performance.now();
let prevBroken = false;
const events: SimEvent[] = [];
const music: MusicPulse = { beat: 0, beatPulse: 0, barPulse: 0, levels: [0.6, 0.4, 0.8, 0.5], pitches: [0.3, 0.5, 0.7, 0.2], chord: 0 };

function frame(now: number): void {
  const dt = Math.min(0.1, (now - last) / 1000);
  last = now;
  if (!paused && frozen === null) clock += dt;
  const snap = snapshot(clock);
  events.length = 0;
  const broken = clock % 16 > 6;
  if (broken && !prevBroken) {
    events.push({ sub: snap.sub, type: 'break', x: 10.5, y: 9.5, id: 'wall', dir: Math.PI / 2, power: 4 });
    renderer.iso.addTrauma(0.6);
  }
  prevBroken = broken;
  music.beat = snap.beat;
  music.beatPulse = 1 - (snap.beat % 1);
  music.barPulse = 1 - ((snap.beat / 4) % 1);
  music.chord = Math.floor(snap.beat / 8) % 4;
  if (pulse) {
    // Stand-in for the fx layer: breathe the music-linked architecture on the beat.
    for (const r of renderer.context?.musicReactive ?? []) r.setLevel(0.7 + 0.6 * music.beatPulse * music.beatPulse);
  }
  const rf: RenderFrame = { snap, prev: prevSnap, alpha: 1, dt: frozen !== null ? 1 / 60 : dt, mode, events, worldRate: 1, music, active: 0 };
  renderer.render(rf);
  prevSnap = snap;
  const s = renderer.stats();
  hud.textContent =
    `theme ${theme}  mode ${mode}  quality ${quality}\n` +
    `draw calls ${s.calls}  tris ${s.triangles}  geos ${s.geometries}  tex ${s.textures}\n` +
    `t ${clock.toFixed(1)}s  beat ${snap.beat.toFixed(1)}\n` +
    `[1-4] theme  [M] mode  [Q] quality  [S] shake  [P] pause`;
  requestAnimationFrame(frame);
}

window.addEventListener('keydown', (e) => {
  const n = Number(e.key);
  if (n >= 1 && n <= 4) {
    theme = THEMES[n - 1];
    load();
  } else if (e.key === 'm' || e.key === 'M') {
    mode = MODES[(MODES.indexOf(mode) + 1) % MODES.length];
  } else if (e.key === 'q' || e.key === 'Q') {
    quality = quality === 'high' ? 'low' : 'high';
    renderer.setQuality(quality);
  } else if (e.key === 's' || e.key === 'S') {
    renderer.iso.addTrauma(0.8);
  } else if (e.key === 'p' || e.key === 'P') {
    paused = !paused;
  }
});

// Clicking reports the floor point under the cursor (checks screenToWorld by eye).
renderer.canvas.addEventListener('click', (e) => {
  const r = renderer.canvas.getBoundingClientRect();
  const w = renderer.screenToWorld(e.clientX - r.left, e.clientY - r.top);
  console.info(`floor (${w.x.toFixed(2)}, ${w.y.toFixed(2)}) tile ${Math.floor(w.x)},${Math.floor(w.y)} '${MAP[Math.floor(w.y)]?.[Math.floor(w.x)] ?? ' '}'`);
});

(window as unknown as { __harness: unknown }).__harness = { renderer, ready: true };
requestAnimationFrame(frame);
