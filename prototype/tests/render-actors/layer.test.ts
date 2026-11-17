import * as THREE from 'three';
import { describe, expect, it } from 'vitest';
import type { MusicPulse, RenderFrame } from '../../src/contracts';
import type { ActorSnap, EnemySnap, FrameSnapshot, LevelDef, ProjectileSnap, ResolvedLoadout } from '../../src/core/types';
import { createActorLayer } from '../../src/render/actors';
import type { RenderCtx, ThemePalette } from '../../src/render/layer';

const PALETTE: ThemePalette = {
  theme: 'upper',
  background: 0,
  fog: 0,
  floor: 0,
  floorAlt: 0,
  wall: 0,
  wallTop: 0,
  metal: 0,
  trim: 0,
  hazard: 0xffc21a,
  foliage: 0,
  neonA: 0,
  neonB: 0,
  neonC: 0,
  graffiti: 0,
  ink: 0x111111,
  keyLight: 0xffffff,
  keyIntensity: 1.5,
  ambient: 0xffffff,
  ambientIntensity: 0.8,
  bloom: 0.5,
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
    arcDeg: 100,
    light: { windup: 6, active: 4, recover: 8, impact: 1, moveMul: 0.5 },
    heavy: { windup: 16, active: 6, recover: 16, impact: 2, moveMul: 0.3 },
    damageEff: 1,
    knockbackEff: 1,
    staggerEff: 1,
    style: 'blunt',
  },
  ranged: {
    archetype: 'missile',
    speed: 2,
    range: 10,
    impact: 1,
    commit: 12,
    cooldown: 30,
    pierce: 0,
    passesWalls: false,
    lobbed: false,
    count: 1,
    spreadDeg: 0,
    turnRate: 2,
    blast: 0,
  },
  looks: { helmet: { variant: 'visor', color: '#334455' }, pants: { variant: 'shorts' } },
};

const LEVEL = {
  id: 't',
  entities: [
    { kind: 'enemy', id: 'g1', type: 'grunt', x: 1, y: 1 },
    { kind: 'enemy', id: 'b1', type: 'boss', x: 5, y: 5 },
  ],
} as unknown as LevelDef;

const PULSE: MusicPulse = { beat: 0, beatPulse: 0.5, barPulse: 0, levels: [0, 0, 0, 0], pitches: [0, 0, 0, 0], chord: 0 };

function makeCtx(): RenderCtx {
  const camera = new THREE.OrthographicCamera(-5, 5, 5, -5, 0.1, 100);
  camera.position.set(10, 8, 10);
  camera.lookAt(0, 0, 0);
  const ramp = new THREE.DataTexture(new Uint8Array([0, 0, 0, 255, 255, 255, 255, 255]), 2, 1);
  return {
    scene: new THREE.Scene(),
    camera,
    palette: PALETTE,
    level: LEVEL,
    loadout: LOADOUT,
    root: new THREE.Group(),
    toonRamp: ramp,
    quality: 'high',
    shake: () => {},
    focus: () => {},
  };
}

function actor(tape: 0 | 1 | 2 | 3, over: Partial<ActorSnap> = {}): ActorSnap {
  return {
    tape,
    live: tape === 0,
    x: tape,
    y: 0,
    facing: 0,
    anim: 'idle',
    life: 'alive',
    synced: true,
    iframes: false,
    phase: { tick: 0, dir: 1, traversal: 0, ended: false },
    vx: 0,
    vy: 0,
    ...over,
  };
}

function snap(sub: number, actors: ActorSnap[], enemies: EnemySnap[], projectiles: ProjectileSnap[]): FrameSnapshot {
  return { sub, beat: sub / 120, actors, enemies, projectiles, mechs: [], objective: { complete: false, progress: 0, survivors: 1 } };
}

function frame(s: FrameSnapshot, prev: FrameSnapshot): RenderFrame {
  return { snap: s, prev, alpha: 0.5, dt: 1 / 60, mode: 'review', events: [], worldRate: 1, music: PULSE, active: 0 };
}

function countObjects(o: THREE.Object3D): number {
  let n = 0;
  o.traverse(() => n++);
  return n;
}

const ANIMS = ['idle', 'run', 'lightWindup', 'lightActive', 'lightRecover', 'heavyWindup', 'heavyActive', 'heavyRecover', 'dodge', 'ranged', 'interact', 'stopped'] as const;

describe('actor layer (headless)', () => {
  it('builds, draws every state, handles appear/disappear and does not grow the scene graph', () => {
    const ctx = makeCtx();
    const layer = createActorLayer();
    layer.loadLevel(ctx);
    expect(ctx.root.children.length).toBe(1);

    let prev: FrameSnapshot | null = null;
    let steady = -1;
    const lives = ['alive', 'recGhost', 'ghost'] as const;
    for (let f = 0; f < 240; f++) {
      const anim = ANIMS[Math.floor(f / 10) % ANIMS.length];
      const life = lives[Math.floor(f / 40) % 3];
      const actors = [
        actor(0, { anim, x: f * 0.02, phase: { tick: f, dir: 1, traversal: 0, ended: false }, iframes: anim === 'dodge' }),
        actor(1, { life, synced: f % 60 < 30, spark: f % 60 < 30 ? { x: 1, y: 2 } : undefined, phase: { tick: f, dir: -1, traversal: 0, ended: false } }),
      ];
      // Tape 2 appears and disappears.
      if (f % 50 < 25) actors.push(actor(2, { anim: 'run', vx: 3 }));
      const enemies: EnemySnap[] = [
        { id: 'g1', type: 'grunt', x: 1, y: 1, facing: f * 0.1, hp: 1, maxHp: 1, alive: f < 200, state: f < 200 ? 'telegraph' : 'dead', stateT: (f % 30) / 30, target: 0 },
        { id: 'b1', type: 'boss', x: 5, y: 5, facing: 0, hp: 20, maxHp: 30, alive: true, state: 'attack', stateT: 0.5, bossPhase: Math.floor(f / 80), bossRecall: f % 40 < 20, bossRecallTape: 1, target: 1 },
      ];
      // Shielder comes and goes (pooled view reuse).
      if (f % 90 < 45) enemies.push({ id: `s${Math.floor(f / 90)}`, type: 'shielder', x: 3, y: 3, facing: 0, hp: 2, maxHp: 2, alive: true, state: 'idle', stateT: 0, shield: f % 20 < 10 });
      const projectiles: ProjectileSnap[] = [];
      if (f % 30 < 20) projectiles.push({ id: 1000 + Math.floor(f / 30), owner: { tape: 0 }, archetype: 'missile', x: f * 0.05, y: 0, z: 0, dir: 0, targetId: 'b1' });
      projectiles.push({ id: 5, owner: { enemy: 'g1' }, archetype: 'arc', x: f * 0.03, y: 1, z: Math.sin(f * 0.05) + 1, dir: 0.3 });
      const s = snap(f * 4, actors, enemies, projectiles);
      layer.update(frame(s, prev ?? s), ctx);
      prev = s;
      if (f === 120) steady = countObjects(ctx.root);
    }
    // After warm-up every view exists; later frames recycle them rather than adding objects.
    expect(countObjects(ctx.root)).toBeLessThanOrEqual(steady + 40);
    expect(Number.isFinite(countObjects(ctx.root))).toBe(true);

    // Every visible mesh has finite world transforms (no NaN poses leaked into the rig).
    ctx.root.updateMatrixWorld(true);
    ctx.root.traverse((o) => {
      for (const v of o.matrixWorld.elements) expect(Number.isFinite(v)).toBe(true);
    });

    // A second level load replaces, not accumulates.
    layer.loadLevel(ctx);
    expect(ctx.root.children.length).toBe(1);
    layer.dispose();
    expect(ctx.root.children.length).toBe(0);
  });

  it('copes with an empty snapshot and a missing previous one', () => {
    const ctx = makeCtx();
    const layer = createActorLayer();
    layer.loadLevel(ctx);
    const s = snap(0, [], [], []);
    expect(() => layer.update({ ...frame(s, s), prev: s, alpha: 0 }, ctx)).not.toThrow();
    layer.dispose();
  });
});
