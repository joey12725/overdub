/**
 * Standalone visual harness for the fx layer (dev only; not part of the game bundle).
 *
 * Serve with `npx vite` and open /src/render/fx/dev/harness.html. Builds its own minimal isometric
 * scene (boxes for tiles, capsules for the four selves, a boss block), fakes RenderFrames and a
 * MusicPulse, fires every SimEventType on a timer, and lets you toggle view mode and tape speed.
 * window.__fx exposes the same controls for automated screenshots.
 */
import * as THREE from 'three';
import type { ActorSnap, EnemySnap, LevelDef, ResolvedLoadout, SimEvent, SimEventType, TapeIndex } from '../../../core/types';
import { TAPE_COLORS } from '../../../core/types';
import type { MusicPulse, RenderFrame, ViewMode } from '../../../contracts';
import type { RenderCtx, ThemePalette } from '../../layer';
import { EVENT_ROUTES } from '../catalog';
import { createFxLayer } from '../index';

const PALETTES: Record<'upper' | 'lower', ThemePalette> = {
  lower: {
    theme: 'lower',
    background: 0x140f19,
    fog: 0x140f19,
    floor: 0x3b3142,
    floorAlt: 0x31293a,
    wall: 0x4b3d4f,
    wallTop: 0x6a566c,
    metal: 0x5d5163,
    trim: 0x8a7a8e,
    hazard: 0xffb21f,
    foliage: 0x6fae3a,
    neonA: 0xff3fa4,
    neonB: 0x4ff3ff,
    neonC: 0xb05cff,
    graffiti: 0xff4fa3,
    ink: 0x14110f,
    keyLight: 0xe8dcff,
    keyIntensity: 1.6,
    ambient: 0x5a4a70,
    ambientIntensity: 1.2,
    bloom: 1,
  },
  upper: {
    theme: 'upper',
    background: 0x2a2018,
    fog: 0x2a2018,
    floor: 0xc9a988,
    floorAlt: 0xb8987a,
    wall: 0xa88a6e,
    wallTop: 0xd8bc98,
    metal: 0x8a7a6e,
    trim: 0xffc83d,
    hazard: 0xffc83d,
    foliage: 0x8fbf3a,
    neonA: 0xff4fa3,
    neonB: 0x4ff3ff,
    neonC: 0xa25bff,
    graffiti: 0xff4fa3,
    ink: 0x14110f,
    keyLight: 0xfff0d8,
    keyIntensity: 2.2,
    ambient: 0x9a8070,
    ambientIntensity: 1.1,
    bloom: 0.6,
  },
};

const LEVEL: LevelDef = {
  id: 'fx-harness',
  index: 0,
  name: 'FX Harness',
  tagline: '',
  theme: 'lower',
  bpm: 120,
  bars: 4,
  horizonBars: 16,
  maxTapes: 4,
  speeds: [0.5, 1, 2, 4],
  endModes: ['stop', 'repeat', 'reverse'],
  map: [
    '##############',
    '#............#',
    '#..~~~~......#',
    '#..~~~~..::..#',
    '#........::..#',
    '#............#',
    '#....~~~.....#',
    '#............#',
    '##############',
  ],
  start: { x: 3.5, y: 4.5 },
  entities: [
    { kind: 'core', id: 'core1', x: 11.5, y: 6.5 },
    { kind: 'exit', id: 'exit', c: 11, r: 1, w: 2, h: 2 },
    { kind: 'decor', type: 'waveScreen', x: 6.5, y: 1.2 },
    { kind: 'decor', type: 'runePanel', x: 2.5, y: 1.2 },
    { kind: 'decor', type: 'runePanel', x: 9.5, y: 1.2 },
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

const LOADOUT: ResolvedLoadout = {
  loadout: { helmet: 'h', top: 't', pants: 'p', shoes: 's', melee: 'm', ranged: 'r' },
  mods: {
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
  },
  abilities: [],
  melee: {
    reach: 1.3,
    arcDeg: 120,
    light: { windup: 4, active: 4, recover: 8, impact: 10, moveMul: 0.6 },
    heavy: { windup: 10, active: 5, recover: 14, impact: 18, moveMul: 0.4 },
    damageEff: 1,
    knockbackEff: 1,
    staggerEff: 1,
    style: 'blade',
  },
  ranged: {
    archetype: 'missile',
    speed: 4,
    range: 12,
    impact: 8,
    commit: 10,
    cooldown: 30,
    pierce: 0,
    passesWalls: false,
    lobbed: false,
    count: 1,
    spreadDeg: 0,
    turnRate: 2,
    blast: 0,
  },
};

const EVENT_TYPES = Object.keys(EVENT_ROUTES) as SimEventType[];
const MODES: ViewMode[] = ['record', 'review', 'cinematic', 'idle'];

// ───────────────────────────── scene ─────────────────────────────

const renderer = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true });
renderer.setPixelRatio(Math.min(2, window.devicePixelRatio));
renderer.setSize(window.innerWidth, window.innerHeight);
document.body.appendChild(renderer.domElement);

const scene = new THREE.Scene();
let palette = PALETTES.lower;
scene.background = new THREE.Color(palette.background);

const VIEW_H = 13;
const camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0.1, 200);
const camTarget = new THREE.Vector3(7, 0, 4.5);
const focusTarget = new THREE.Vector3().copy(camTarget);
const ISO_DIR = new THREE.Vector3(1, 1.2, 1).normalize();
function layoutCamera(): void {
  const aspect = window.innerWidth / window.innerHeight;
  camera.left = (-VIEW_H * aspect) / 2;
  camera.right = (VIEW_H * aspect) / 2;
  camera.top = VIEW_H / 2;
  camera.bottom = -VIEW_H / 2;
  camera.updateProjectionMatrix();
}
layoutCamera();

const root = new THREE.Group();
scene.add(root);
const world = new THREE.Group();
scene.add(world);
const hemi = new THREE.HemisphereLight(0xffffff, 0x444466, 1.2);
scene.add(hemi);
const key = new THREE.DirectionalLight(0xffffff, 1.6);
key.position.set(-4, 10, 6);
scene.add(key);

function buildWorld(): void {
  world.clear();
  const tile = new THREE.BoxGeometry(0.98, 0.2, 0.98);
  const wall = new THREE.BoxGeometry(1, 1.4, 1);
  const floorMat = new THREE.MeshLambertMaterial({ color: palette.floor });
  const floorAlt = new THREE.MeshLambertMaterial({ color: palette.floorAlt });
  const wallMat = new THREE.MeshLambertMaterial({ color: palette.wall });
  LEVEL.map.forEach((row, r) => {
    [...row].forEach((ch, c) => {
      if (ch === ' ') return;
      if (ch === '#') {
        const m = new THREE.Mesh(wall, wallMat);
        m.position.set(c + 0.5, 0.5, r + 0.5);
        // Low front walls (iso cutaway) so the playfield stays visible.
        if (r === LEVEL.map.length - 1 || c === row.length - 1) m.scale.y = 0.25;
        m.position.y = (1.4 * m.scale.y) / 2 - 0.2;
        world.add(m);
        return;
      }
      const m = new THREE.Mesh(tile, (c + r) % 2 ? floorMat : floorAlt);
      m.position.set(c + 0.5, -0.1, r + 0.5);
      world.add(m);
    });
  });
  for (const e of LEVEL.entities) {
    if (e.kind === 'decor') {
      const m = new THREE.Mesh(new THREE.BoxGeometry(0.9, 1.0, 0.25), new THREE.MeshLambertMaterial({ color: palette.metal }));
      m.position.set(e.x, 0.5, e.y);
      world.add(m);
    } else if (e.kind === 'core') {
      const m = new THREE.Mesh(new THREE.OctahedronGeometry(0.35), new THREE.MeshLambertMaterial({ color: palette.neonA, emissive: palette.neonA, emissiveIntensity: 0.4 }));
      m.position.set(e.x, 0.7, e.y);
      world.add(m);
    }
  }
}
buildWorld();

const actorMeshes: THREE.Mesh[] = [];
for (let t = 0; t < 4; t++) {
  const m = new THREE.Mesh(new THREE.CapsuleGeometry(0.26, 0.7, 4, 12), new THREE.MeshLambertMaterial({ color: new THREE.Color(TAPE_COLORS[t]) }));
  scene.add(m);
  actorMeshes.push(m);
}
const bossMesh = new THREE.Mesh(new THREE.BoxGeometry(1.2, 1.6, 1.2), new THREE.MeshLambertMaterial({ color: 0x6a3a7a }));
scene.add(bossMesh);
const gruntMesh = new THREE.Mesh(new THREE.BoxGeometry(0.6, 0.9, 0.6), new THREE.MeshLambertMaterial({ color: 0x8a3040 }));
scene.add(gruntMesh);

// ───────────────────────────── fx layer ─────────────────────────────

let shakeAmt = 0;
const ctx: RenderCtx = {
  scene,
  camera,
  palette,
  level: LEVEL,
  loadout: LOADOUT,
  root,
  toonRamp: new THREE.DataTexture(new Uint8Array([80, 80, 80, 255, 200, 200, 200, 255, 255, 255, 255, 255]), 3, 1),
  quality: 'high',
  shake: (m) => {
    shakeAmt = Math.max(shakeAmt, m);
  },
  focus: (x, y, w) => {
    focusTarget.set(7 + (x - 7) * w * 0.5, 0, 4.5 + (y - 4.5) * w * 0.5);
  },
};
const fx = createFxLayer();
fx.loadLevel(ctx);

// ───────────────────────────── fake sim ─────────────────────────────

const state = {
  mode: 'cinematic' as ViewMode,
  worldRate: 1,
  auto: true,
  paused: false,
  t: 0,
  beat: 0,
  nextEvent: 0,
  cursor: 0,
  pending: [] as SimEvent[],
  sub: 0,
};

function actorPos(t: number, time: number): { x: number; y: number; f: number } {
  const cx = [4, 7, 9.5, 5.5][t];
  const cy = [4.5, 3.5, 5, 6.5][t];
  const r = [1.6, 1.2, 1.4, 1.0][t];
  const w = [0.9, -1.2, 0.7, 1.4][t];
  const a = time * w + t;
  return { x: cx + Math.cos(a) * r, y: cy + Math.sin(a) * r, f: a + (w > 0 ? Math.PI / 2 : -Math.PI / 2) };
}

function makeActors(time: number): ActorSnap[] {
  const out: ActorSnap[] = [];
  for (let t = 0; t < 4; t++) {
    const p = actorPos(t, time);
    const desync = t === 2 && Math.sin(time * 0.4) > 0.3;
    out.push({
      tape: t as TapeIndex,
      live: t === 0,
      x: p.x,
      y: p.y,
      facing: p.f,
      anim: 'run',
      life: t === 3 && Math.sin(time * 0.25) > 0.5 ? 'ghost' : 'alive',
      synced: !desync,
      spark: desync ? { x: p.x - 1, y: p.y } : undefined,
      iframes: false,
      phase: { tick: 0, dir: 1, traversal: 0, ended: false },
      vx: 0,
      vy: 0,
    });
  }
  return out;
}

function makeEnemies(time: number): EnemySnap[] {
  return [
    { id: 'boss', type: 'boss', x: 10.5, y: 3, facing: Math.PI, hp: 20, maxHp: 20, alive: true, state: 'idle', stateT: 0 },
    { id: 'g1', type: 'grunt', x: 6 + Math.sin(time * 1.3) * 2, y: 6.2, facing: 0, hp: 1, maxHp: 1, alive: true, state: 'move', stateT: 0 },
  ];
}

function eventFor(type: SimEventType, n: number, time: number): SimEvent {
  const tape = (n % 4) as TapeIndex;
  const p = actorPos(tape, time);
  const onBoss = type.startsWith('boss') || type === 'enemyTelegraph' || type === 'enemyAttack' || type === 'enemyShot' || type === 'enemyStagger';
  const x = onBoss ? 10.5 : type === 'core' ? 11.5 : type === 'objective' ? 7 : p.x;
  const y = onBoss ? 3 : type === 'core' ? 6.5 : type === 'objective' ? 4.5 : p.y;
  const power = [4, 10, 18, 28, 50][n % 5];
  return { sub: state.sub + n, type, x, y, tape, id: 'e', dir: p.f, power, detail: n % 2 ? 'heavy' : 'on' };
}

function fire(type: SimEventType): void {
  state.pending.push(eventFor(type, state.cursor++, state.t));
}

function fireAll(): void {
  EVENT_TYPES.forEach((t, i) => state.pending.push(eventFor(t, i, state.t)));
}

function musicPulse(beat: number): MusicPulse {
  const f = beat - Math.floor(beat);
  const step = Math.floor(beat * 2);
  const pitch = (t: number) => {
    const seq = [0, 3, 7, 5, 10, 7, 3, 2];
    return ((seq[(step * (t + 1) + t * 3) % seq.length] + t * 2) % 12) / 12;
  };
  return {
    beat,
    beatPulse: Math.pow(1 - f, 2),
    barPulse: Math.pow(1 - (beat / 4 - Math.floor(beat / 4)), 2),
    levels: [0.55 + 0.4 * Math.sin(beat * 0.7), 0.7 * (step % 2), 0.5 + 0.4 * Math.cos(beat * 0.31), 0.35],
    pitches: [pitch(0), pitch(1), pitch(2), pitch(3)],
    chord: Math.floor(beat / 8) % 4,
  };
}

let prevSnap = { sub: 0, beat: 0, actors: makeActors(0), enemies: makeEnemies(0), projectiles: [], mechs: [], objective: { complete: false, progress: 0, survivors: 4 } };

function step(dt: number): void {
  if (!state.paused) {
    state.t += dt * state.worldRate;
    state.beat += dt * (LEVEL.bpm / 60) * state.worldRate;
    state.sub += Math.round(dt * 240 * state.worldRate);
    if (state.auto && state.t >= state.nextEvent) {
      state.nextEvent = state.t + 0.45;
      fire(EVENT_TYPES[state.cursor % EVENT_TYPES.length]);
    }
  }
  const snap = { sub: state.sub, beat: state.beat, actors: makeActors(state.t), enemies: makeEnemies(state.t), projectiles: [], mechs: [], objective: { complete: false, progress: 0, survivors: 4 } };
  const frame: RenderFrame = {
    snap,
    prev: prevSnap,
    alpha: 1,
    dt,
    mode: state.mode,
    events: state.pending.splice(0),
    worldRate: state.worldRate,
    music: musicPulse(state.beat),
    active: state.mode === 'record' ? 0 : null,
  };
  prevSnap = snap;
  for (let t = 0; t < 4; t++) {
    const a = snap.actors[t];
    actorMeshes[t].position.set(a.x, 0.6, a.y);
    const mat = actorMeshes[t].material as THREE.MeshLambertMaterial;
    mat.transparent = a.life !== 'alive' || !a.synced;
    mat.opacity = a.life !== 'alive' ? 0.3 : a.synced ? 1 : 0.55;
  }
  bossMesh.position.set(snap.enemies[0].x, 0.8, snap.enemies[0].y);
  gruntMesh.position.set(snap.enemies[1].x, 0.45, snap.enemies[1].y);

  // Shell-side camera behaviour (cinematic focus + shake), as the real renderer is expected to do.
  if (state.mode === 'cinematic') camTarget.lerp(focusTarget, 1 - Math.exp(-dt * 2));
  else camTarget.lerp(new THREE.Vector3(7, 0, 4.5), 1 - Math.exp(-dt * 3));
  focusTarget.lerp(new THREE.Vector3(7, 0, 4.5), 1 - Math.exp(-dt * 0.8));
  camera.position.copy(camTarget).addScaledVector(ISO_DIR, 40);
  if (shakeAmt > 0.001) {
    camera.position.x += (Math.random() - 0.5) * shakeAmt * 0.35;
    camera.position.y += (Math.random() - 0.5) * shakeAmt * 0.35;
  }
  shakeAmt *= Math.exp(-dt * 10);
  camera.lookAt(camTarget);
  camera.updateMatrixWorld();

  fx.update(frame, ctx);
  renderer.render(scene, camera);
  status.textContent = `mode ${state.mode}  worldRate ${state.worldRate}  beat ${state.beat.toFixed(2)}  next ${EVENT_TYPES[state.cursor % EVENT_TYPES.length]}`;
}

// ───────────────────────────── UI ─────────────────────────────

const panel = document.getElementById('panel')!;
const status = document.getElementById('status')!;
function button(label: string, onClick: () => void): HTMLButtonElement {
  const b = document.createElement('button');
  b.textContent = label;
  b.onclick = onClick;
  panel.appendChild(b);
  return b;
}
const modeButtons = MODES.map((m) =>
  button(m, () => {
    state.mode = m;
    refresh();
  }),
);
const rateSel = document.createElement('select');
for (const [label, v] of [
  ['tape 4x (world 0.25)', 0.25],
  ['tape 2x (world 0.5)', 0.5],
  ['tape 1x (world 1)', 1],
  ['tape 0.5x (world 2)', 2],
] as const) {
  const o = document.createElement('option');
  o.textContent = label;
  o.value = String(v);
  rateSel.appendChild(o);
}
rateSel.value = '1';
rateSel.onchange = () => (state.worldRate = Number(rateSel.value));
panel.appendChild(rateSel);
const autoBtn = button('auto', () => {
  state.auto = !state.auto;
  refresh();
});
button('fire all', fireAll);
const evSel = document.createElement('select');
for (const t of EVENT_TYPES) {
  const o = document.createElement('option');
  o.textContent = t;
  evSel.appendChild(o);
}
panel.appendChild(evSel);
button('fire', () => fire(evSel.value as SimEventType));
button('theme', () => {
  palette = palette.theme === 'lower' ? PALETTES.upper : PALETTES.lower;
  ctx.palette = palette;
  scene.background = new THREE.Color(palette.background);
  buildWorld();
  root.clear();
  fx.loadLevel(ctx);
});
function refresh(): void {
  modeButtons.forEach((b, i) => b.classList.toggle('on', MODES[i] === state.mode));
  autoBtn.classList.toggle('on', state.auto);
}
refresh();

window.addEventListener('resize', () => {
  renderer.setSize(window.innerWidth, window.innerHeight);
  layoutCamera();
});

let last = performance.now();
function loop(now: number): void {
  const dt = Math.min(0.1, (now - last) / 1000);
  last = now;
  if (!manual) step(dt);
  requestAnimationFrame(loop);
}
let manual = false;
requestAnimationFrame(loop);

/** Automation hooks for screenshot scripts. */
(window as unknown as { __fx: unknown }).__fx = {
  setMode(m: ViewMode) {
    state.mode = m;
    refresh();
  },
  setRate(r: number) {
    state.worldRate = r;
    rateSel.value = String(r);
  },
  setAuto(a: boolean) {
    state.auto = a;
    refresh();
  },
  fire,
  fireAll,
  /** Take over the clock: advance exactly `seconds` in 1/60 s steps (deterministic captures). */
  advance(seconds: number) {
    manual = true;
    const n = Math.round(seconds * 60);
    for (let i = 0; i < n; i++) step(1 / 60);
  },
  types: EVENT_TYPES,
};
