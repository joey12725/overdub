/**
 * Enemy models: a "ruin-security machine" family — weathered temple stone shells retrofitted with
 * brass plating, dark metal joints, teal rune circuitry and a single hot-orange optic. One distinct
 * silhouette per EnemyType, all facing +Z (model forward). Geometry is cached per type and shared.
 */
import * as THREE from 'three';
import type { EnemyType } from '../../core/types';
import { PartBuilder, box, cone, cyl, extrudePoly, ico, lathe, octa, sphere, torus, tube, capsule, dodeca } from './geom';

export const ENEMY_COLORS = {
  stone: 0xa89d8b,
  stoneDark: 0x7b7163,
  stoneLight: 0xc4b8a3,
  brass: 0xd2a136,
  brassDark: 0x9c7424,
  metal: 0x3b3e46,
  metalLight: 0x5e626c,
  cable: 0x26272c,
  rune: 0x58f0dc,
  eye: 0xff6a1a,
  hazard: 0xffc21a,
  /** Telegraph / enemy projectile hue: hot orange, distinct from every cassette colour. */
  danger: 0xff6a1a,
} as const;

const E = ENEMY_COLORS;

export interface JointSpec {
  name: string;
  parent: string | null;
  pos: [number, number, number];
  geo?: THREE.BufferGeometry;
}

export interface EnemyRigSpec {
  type: EnemyType;
  joints: JointSpec[];
  /** Height above floor of the head marker (pips, target pip). */
  top: number;
  /** Footprint radius (for decals/shadow). */
  radius: number;
  /** Visual-only telegraph shape for the attack (the sim owns the real hit volume). */
  telegraph: { kind: 'cone'; reach: number; arcDeg: number } | { kind: 'line'; length: number; width: number } | { kind: 'circle'; radius: number } | { kind: 'aim'; length: number };
  /** Hovering units draw a ground shadow. */
  hover: number;
  /** Ink hull thickness. */
  hull: number;
}

/** Glow + accent: the optic, recoloured per state through the instance accent. */
const EYE = { glow: 1, accent: 1 } as const;
const RUNE = { glow: 1 } as const;

function grunt(): EnemyRigSpec {
  const body = new PartBuilder();
  // Squat sentinel: a carved stone block torso with brass collar and rune seams.
  body.add(box(0.42, 0.34, 0.32), E.stone, { pos: [0, 0.2, 0] });
  body.add(box(0.44, 0.06, 0.34), E.brass, { pos: [0, 0.36, 0] });
  body.add(box(0.3, 0.025, 0.01), E.rune, { pos: [0, 0.2, 0.162], ...RUNE });
  body.add(box(0.025, 0.2, 0.01), E.rune, { pos: [0, 0.2, 0.163], ...RUNE });
  body.add(box(0.2, 0.12, 0.08), E.metal, { pos: [0, 0.18, -0.19] });
  body.add(cyl(0.035, 0.035, 0.1, 6), E.metalLight, { pos: [0.06, 0.26, -0.24], rot: [0.4, 0, 0] });
  body.add(cyl(0.035, 0.035, 0.1, 6), E.metalLight, { pos: [-0.06, 0.26, -0.24], rot: [0.4, 0, 0] });
  const head = new PartBuilder();
  head.add(sphere(0.15, 10, 6), E.stoneDark, { pos: [0, 0.06, 0], scale: [1.1, 0.8, 1] });
  head.add(box(0.2, 0.05, 0.06), E.metal, { pos: [0, 0.06, 0.12] });
  head.add(box(0.13, 0.03, 0.02), 0xffffff, { pos: [0, 0.06, 0.155], ...EYE });
  head.add(cone(0.03, 0.1, 4), E.brass, { pos: [0.1, 0.15, -0.02], rot: [0, 0, -0.5] });
  head.add(cone(0.03, 0.1, 4), E.brass, { pos: [-0.1, 0.15, -0.02], rot: [0, 0, 0.5] });
  const armR = new PartBuilder();
  // The club: a ruin column fragment bolted to a piston forearm.
  armR.add(sphere(0.07, 8, 6), E.metal);
  armR.add(cyl(0.05, 0.05, 0.18, 8), E.metalLight, { pos: [0, -0.1, 0] });
  armR.add(cyl(0.1, 0.09, 0.24, 8), E.stoneLight, { pos: [0, -0.3, 0.02] });
  armR.add(torus(0.095, 0.018, 4, 12), E.brass, { pos: [0, -0.22, 0.02], rot: [Math.PI / 2, 0, 0] });
  armR.add(torus(0.095, 0.018, 4, 12), E.brass, { pos: [0, -0.38, 0.02], rot: [Math.PI / 2, 0, 0] });
  const armL = new PartBuilder();
  armL.add(sphere(0.06, 8, 6), E.metal);
  armL.add(cyl(0.045, 0.04, 0.22, 8), E.metalLight, { pos: [0, -0.12, 0] });
  armL.add(box(0.09, 0.08, 0.09), E.brass, { pos: [0, -0.25, 0] });
  const leg = () => {
    const l = new PartBuilder();
    l.add(cyl(0.065, 0.055, 0.16, 8), E.metal, { pos: [0, -0.08, 0] });
    l.add(box(0.13, 0.05, 0.17), E.stoneDark, { pos: [0, -0.16, 0.02] });
    return l.build();
  };
  return {
    type: 'grunt',
    joints: [
      { name: 'body', parent: null, pos: [0, 0.18, 0], geo: body.build() },
      { name: 'head', parent: 'body', pos: [0, 0.39, 0.02], geo: head.build() },
      { name: 'armR', parent: 'body', pos: [-0.27, 0.3, 0], geo: armR.build() },
      { name: 'armL', parent: 'body', pos: [0.26, 0.3, 0], geo: armL.build() },
      { name: 'legR', parent: 'body', pos: [-0.12, 0.02, 0], geo: leg() },
      { name: 'legL', parent: 'body', pos: [0.12, 0.02, 0], geo: leg() },
    ],
    top: 0.85,
    radius: 0.36,
    telegraph: { kind: 'cone', reach: 1.25, arcDeg: 100 },
    hover: 0,
    hull: 0.014,
  };
}

function stalker(): EnemyRigSpec {
  const body = new PartBuilder();
  // Lean hunter: horizontal capsule body, raised hindquarters, ridge of brass vanes.
  body.add(capsule(0.1, 0.32, 3, 8), E.metal, { rot: [Math.PI / 2 - 0.25, 0, 0], pos: [0, 0.05, 0] });
  body.add(capsule(0.085, 0.22, 3, 8), E.stone, { rot: [Math.PI / 2 - 0.25, 0, 0], pos: [0, 0.12, -0.02] });
  for (let i = 0; i < 4; i++) body.add(cone(0.03, 0.12, 4), E.brass, { pos: [0, 0.22 - i * 0.02, 0.1 - i * 0.09], rot: [-0.6, 0, 0] });
  body.add(box(0.012, 0.012, 0.3), E.rune, { pos: [0.09, 0.08, 0], ...RUNE });
  body.add(box(0.012, 0.012, 0.3), E.rune, { pos: [-0.09, 0.08, 0], ...RUNE });
  const head = new PartBuilder();
  head.add(extrudePoly([[-0.07, 0], [0.07, 0], [0.03, 0.2], [-0.03, 0.2]], 0.08), E.stoneLight, { rot: [Math.PI / 2, 0, 0], pos: [0, 0, 0] });
  head.add(box(0.11, 0.018, 0.02), 0xffffff, { pos: [0, 0.035, 0.1], ...EYE });
  head.add(cone(0.02, 0.14, 4), E.brass, { pos: [0.05, 0.06, -0.05], rot: [-1.9, 0, -0.3] });
  head.add(cone(0.02, 0.14, 4), E.brass, { pos: [-0.05, 0.06, -0.05], rot: [-1.9, 0, 0.3] });
  const blade = () => {
    const b = new PartBuilder();
    b.add(sphere(0.045, 6, 4), E.metal);
    b.add(cyl(0.025, 0.02, 0.16, 6), E.metalLight, { pos: [0, -0.08, 0] });
    b.add(extrudePoly([[0, 0], [0.035, 0.02], [0.02, 0.3], [-0.005, 0.34], [-0.01, 0.05]], 0.012), 0xdfe3ea, {
      pos: [0, -0.16, 0],
      rot: [Math.PI / 2 + 0.6, 0, 0],
    });
    return b.build();
  };
  const leg = () => {
    const l = new PartBuilder();
    // Digitigrade: thigh back, shin forward.
    l.add(cyl(0.04, 0.03, 0.2, 6), E.metal, { pos: [0, -0.08, -0.05], rot: [-0.5, 0, 0] });
    l.add(cyl(0.025, 0.02, 0.2, 6), E.metalLight, { pos: [0, -0.24, -0.03], rot: [0.5, 0, 0] });
    l.add(box(0.06, 0.03, 0.1), E.stoneDark, { pos: [0, -0.33, 0.02] });
    return l.build();
  };
  const tail = new PartBuilder();
  tail.add(tube([[0, 0, 0], [0, 0.06, -0.15], [0, 0.18, -0.28], [0, 0.3, -0.3]], 0.025, 10, 5), E.metal);
  tail.add(octa(0.04), 0xffffff, { pos: [0, 0.31, -0.3], ...EYE });
  return {
    type: 'stalker',
    joints: [
      { name: 'body', parent: null, pos: [0, 0.38, 0], geo: body.build() },
      { name: 'head', parent: 'body', pos: [0, 0.08, 0.24], geo: head.build() },
      { name: 'armR', parent: 'body', pos: [-0.11, 0.02, 0.14], geo: blade() },
      { name: 'armL', parent: 'body', pos: [0.11, 0.02, 0.14], geo: blade() },
      { name: 'legR', parent: 'body', pos: [-0.09, -0.02, -0.08], geo: leg() },
      { name: 'legL', parent: 'body', pos: [0.09, -0.02, -0.08], geo: leg() },
      { name: 'tail', parent: 'body', pos: [0, 0.06, -0.22], geo: tail.build() },
    ],
    top: 0.8,
    radius: 0.3,
    telegraph: { kind: 'line', length: 2.4, width: 0.5 },
    hover: 0,
    hull: 0.012,
  };
}

function turret(): EnemyRigSpec {
  const base = new PartBuilder();
  // A temple plinth with a rune ring, crowned by a retrofitted gun head.
  base.add(cyl(0.3, 0.36, 0.22, 8), E.stone, { pos: [0, 0.11, 0] });
  base.add(cyl(0.26, 0.3, 0.08, 8), E.stoneDark, { pos: [0, 0.26, 0] });
  base.add(torus(0.335, 0.012, 4, 24), E.rune, { pos: [0, 0.14, 0], rot: [Math.PI / 2, 0, 0], ...RUNE });
  for (let i = 0; i < 4; i++) {
    const a = (i / 4) * Math.PI * 2 + Math.PI / 4;
    base.add(box(0.08, 0.1, 0.05), E.brass, { pos: [Math.sin(a) * 0.32, 0.12, Math.cos(a) * 0.32], rot: [0, a, 0] });
  }
  const head = new PartBuilder();
  head.add(cyl(0.18, 0.2, 0.08, 10), E.metal, { pos: [0, 0.03, 0] });
  head.add(box(0.3, 0.18, 0.28), E.brass, { pos: [0, 0.15, -0.02] });
  head.add(box(0.32, 0.04, 0.3), E.brassDark, { pos: [0, 0.25, -0.02] });
  head.add(box(0.12, 0.05, 0.02), 0xffffff, { pos: [0, 0.17, 0.125], ...EYE });
  head.add(box(0.06, 0.1, 0.12), E.metal, { pos: [0, 0.16, -0.18] });
  const barrels = new PartBuilder();
  for (const s of [1, -1]) {
    barrels.add(cyl(0.035, 0.04, 0.34, 8), E.metalLight, { pos: [s * 0.075, 0, 0.17], rot: [Math.PI / 2, 0, 0] });
    barrels.add(cyl(0.045, 0.045, 0.04, 8), E.metal, { pos: [s * 0.075, 0, 0.33], rot: [Math.PI / 2, 0, 0] });
  }
  barrels.add(box(0.2, 0.03, 0.1), E.metal, { pos: [0, 0, 0.1] });
  return {
    type: 'turret',
    joints: [
      { name: 'base', parent: null, pos: [0, 0, 0], geo: base.build() },
      { name: 'head', parent: null, pos: [0, 0.3, 0], geo: head.build() },
      { name: 'barrels', parent: 'head', pos: [0, 0.12, 0.08], geo: barrels.build() },
    ],
    top: 0.82,
    radius: 0.38,
    telegraph: { kind: 'aim', length: 9 },
    hover: 0,
    hull: 0.014,
  };
}

function shielder(): EnemyRigSpec {
  const body = new PartBuilder();
  body.add(lathe([[0.0, 0], [0.2, 0], [0.24, 0.15], [0.22, 0.32], [0.14, 0.38], [0, 0.38]], 10), E.stone, {});
  body.add(torus(0.225, 0.02, 4, 16), E.brass, { pos: [0, 0.16, 0], rot: [Math.PI / 2, 0, 0] });
  body.add(box(0.012, 0.25, 0.012), E.rune, { pos: [0.0, 0.18, 0.235], ...RUNE });
  body.add(cyl(0.05, 0.05, 0.12, 6), E.metal, { pos: [0, 0.3, -0.18], rot: [0.5, 0, 0] });
  const head = new PartBuilder();
  head.add(sphere(0.12, 10, 8), E.metal, { pos: [0, 0.05, 0], scale: [1, 0.85, 1] });
  head.add(torus(0.1, 0.02, 4, 12, Math.PI), E.brass, { pos: [0, 0.07, 0], rot: [0, 0, 0] });
  head.add(sphere(0.035, 8, 6), 0xffffff, { pos: [0, 0.05, 0.105], ...EYE });
  // The tower shield: hexagonal temple door slab with a brass rim and rune emitter.
  const shield = new PartBuilder();
  const hex: [number, number][] = [];
  for (let i = 0; i < 6; i++) {
    const a = (i / 6) * Math.PI * 2 + Math.PI / 6;
    hex.push([Math.cos(a) * 0.28, Math.sin(a) * 0.34]);
  }
  shield.add(extrudePoly(hex, 0.05), E.stoneLight, { pos: [0, 0, 0] });
  shield.add(extrudePoly(hex.map(([x, y]) => [x * 0.8, y * 0.8] as [number, number]), 0.06), E.brass, { pos: [0, 0, 0.005] });
  shield.add(extrudePoly(hex.map(([x, y]) => [x * 0.62, y * 0.62] as [number, number]), 0.07), E.stone, { pos: [0, 0, 0.01] });
  shield.add(octa(0.05), 0xffffff, { pos: [0, 0, 0.05], ...EYE });
  const armR = new PartBuilder();
  armR.add(sphere(0.055, 8, 6), E.metal);
  armR.add(cyl(0.04, 0.035, 0.22, 6), E.metalLight, { pos: [0, -0.11, 0] });
  armR.add(box(0.08, 0.08, 0.08), E.brass, { pos: [0, -0.24, 0] });
  const leg = () => {
    const l = new PartBuilder();
    l.add(cyl(0.06, 0.05, 0.16, 8), E.metal, { pos: [0, -0.08, 0] });
    l.add(box(0.12, 0.05, 0.16), E.stoneDark, { pos: [0, -0.17, 0.02] });
    return l.build();
  };
  return {
    type: 'shielder',
    joints: [
      { name: 'body', parent: null, pos: [0, 0.2, 0], geo: body.build() },
      { name: 'head', parent: 'body', pos: [0, 0.4, 0], geo: head.build() },
      { name: 'shield', parent: 'body', pos: [0.05, 0.2, 0.3], geo: shield.build() },
      { name: 'armR', parent: 'body', pos: [-0.25, 0.3, 0], geo: armR.build() },
      { name: 'legR', parent: 'body', pos: [-0.1, 0.02, 0], geo: leg() },
      { name: 'legL', parent: 'body', pos: [0.1, 0.02, 0], geo: leg() },
    ],
    top: 0.9,
    radius: 0.38,
    telegraph: { kind: 'cone', reach: 1.1, arcDeg: 80 },
    hover: 0,
    hull: 0.014,
  };
}

function brute(): EnemyRigSpec {
  const body = new PartBuilder();
  // Hunched golem: massive shoulders, tiny head, brass bands strapping cracked stone.
  body.add(dodeca(0.36), E.stone, { pos: [0, 0.3, 0], scale: [1.35, 0.95, 1.0] });
  body.add(box(0.7, 0.08, 0.42), E.brass, { pos: [0, 0.36, 0], rot: [0, 0, 0] });
  body.add(box(0.36, 0.3, 0.3), E.stoneDark, { pos: [0, 0.02, -0.02] });
  body.add(box(0.02, 0.32, 0.02), E.rune, { pos: [0.08, 0.3, 0.33], rot: [0.25, 0, 0.3], ...RUNE });
  body.add(box(0.02, 0.22, 0.02), E.rune, { pos: [-0.1, 0.28, 0.33], rot: [0.25, 0, -0.5], ...RUNE });
  body.add(box(0.24, 0.16, 0.12), E.metal, { pos: [0, 0.4, -0.3] });
  for (const s of [1, -1]) body.add(cyl(0.04, 0.04, 0.18, 6), E.metalLight, { pos: [s * 0.08, 0.55, -0.32], rot: [0.3, 0, 0] });
  const head = new PartBuilder();
  head.add(box(0.2, 0.14, 0.18), E.stoneLight, { pos: [0, 0.05, 0] });
  head.add(box(0.14, 0.03, 0.02), 0xffffff, { pos: [0, 0.05, 0.095], ...EYE });
  head.add(box(0.24, 0.04, 0.2), E.brass, { pos: [0, 0.13, 0] });
  const arm = (s: number) => {
    const a = new PartBuilder();
    a.add(sphere(0.15, 8, 6), E.stoneDark, { scale: [1.1, 1, 1] });
    a.add(box(0.18, 0.12, 0.16), E.brass, { pos: [s * 0.02, 0.06, 0] });
    a.add(cyl(0.09, 0.08, 0.3, 8), E.metal, { pos: [0, -0.2, 0.02] });
    a.add(dodeca(0.17), E.stone, { pos: [0, -0.43, 0.04], scale: [1, 0.9, 1.1] });
    a.add(box(0.2, 0.05, 0.2), E.brass, { pos: [0, -0.32, 0.04] });
    return a.build();
  };
  const leg = () => {
    const l = new PartBuilder();
    l.add(cyl(0.11, 0.1, 0.22, 8), E.metal, { pos: [0, -0.1, 0] });
    l.add(box(0.22, 0.08, 0.26), E.stoneDark, { pos: [0, -0.22, 0.03] });
    return l.build();
  };
  return {
    type: 'brute',
    joints: [
      { name: 'body', parent: null, pos: [0, 0.3, 0], geo: body.build() },
      { name: 'head', parent: 'body', pos: [0, 0.6, 0.2], geo: head.build() },
      { name: 'armR', parent: 'body', pos: [-0.5, 0.42, 0.05], geo: arm(-1) },
      { name: 'armL', parent: 'body', pos: [0.5, 0.42, 0.05], geo: arm(1) },
      { name: 'legR', parent: 'body', pos: [-0.17, -0.06, 0], geo: leg() },
      { name: 'legL', parent: 'body', pos: [0.17, -0.06, 0], geo: leg() },
    ],
    top: 1.35,
    radius: 0.55,
    telegraph: { kind: 'circle', radius: 1.8 },
    hover: 0,
    hull: 0.018,
  };
}

function drone(): EnemyRigSpec {
  const body = new PartBuilder();
  // Floating ward-orb: stone shell split by a brass equator, one big lens.
  body.add(sphere(0.17, 12, 10), E.stone);
  body.add(torus(0.17, 0.025, 5, 20), E.brass, { rot: [Math.PI / 2, 0, 0] });
  body.add(cyl(0.08, 0.09, 0.06, 12), E.metal, { pos: [0, 0, 0.15], rot: [Math.PI / 2, 0, 0] });
  body.add(cyl(0.06, 0.06, 0.02, 12), 0xffffff, { pos: [0, 0, 0.185], rot: [Math.PI / 2, 0, 0], ...EYE });
  body.add(cone(0.05, 0.12, 6), E.metal, { pos: [0, -0.19, 0], rot: [Math.PI, 0, 0] });
  body.add(octa(0.025), E.rune, { pos: [0, -0.26, 0], ...RUNE });
  const rotor = () => {
    const r = new PartBuilder();
    r.add(torus(0.27, 0.014, 4, 24), E.metalLight, {});
    for (let i = 0; i < 3; i++) {
      const a = (i / 3) * Math.PI * 2;
      r.add(box(0.12, 0.012, 0.03), E.brass, { pos: [Math.cos(a) * 0.21, 0, Math.sin(a) * 0.21], rot: [0, -a, 0] });
    }
    return r.build();
  };
  return {
    type: 'drone',
    joints: [
      { name: 'body', parent: null, pos: [0, 1.0, 0], geo: body.build() },
      { name: 'rotorA', parent: 'body', pos: [0, 0.03, 0], geo: rotor() },
      { name: 'rotorB', parent: 'body', pos: [0, -0.03, 0], geo: rotor() },
    ],
    top: 1.35,
    radius: 0.3,
    telegraph: { kind: 'aim', length: 7 },
    hover: 1.0,
    hull: 0.012,
  };
}

function boss(): EnemyRigSpec {
  // The Archivist: a colossal ruin machine that keeps the dungeon's records — a stone plinth, a
  // central column with one great optic, cassette-reel wheels on its flanks and four armour
  // plates. Phases strip it down (plates open, then break away and orbit the exposed core).
  const base = new PartBuilder();
  base.add(cyl(1.05, 1.2, 0.35, 12), E.stoneDark, { pos: [0, 0.17, 0] });
  base.add(cyl(0.9, 1.0, 0.2, 12), E.stone, { pos: [0, 0.45, 0] });
  base.add(torus(1.1, 0.03, 4, 36), E.rune, { pos: [0, 0.3, 0], rot: [Math.PI / 2, 0, 0], ...RUNE });
  for (let i = 0; i < 8; i++) {
    const a = (i / 8) * Math.PI * 2;
    base.add(box(0.2, 0.3, 0.12), E.brass, { pos: [Math.sin(a) * 1.08, 0.2, Math.cos(a) * 1.08], rot: [0, a, 0] });
  }
  const core = new PartBuilder();
  core.add(cyl(0.48, 0.55, 1.1, 10), E.metal, { pos: [0, 0.55, 0] });
  core.add(cyl(0.5, 0.5, 0.08, 10), E.brass, { pos: [0, 0.2, 0] });
  core.add(cyl(0.5, 0.5, 0.08, 10), E.brass, { pos: [0, 0.95, 0] });
  for (let i = 0; i < 6; i++) {
    const a = (i / 6) * Math.PI * 2;
    core.add(box(0.03, 0.7, 0.03), E.rune, { pos: [Math.sin(a) * 0.5, 0.6, Math.cos(a) * 0.5], ...RUNE });
  }
  core.add(cone(0.42, 0.5, 10), E.stoneLight, { pos: [0, 1.35, 0] });
  core.add(octa(0.1), E.rune, { pos: [0, 1.68, 0], ...RUNE });
  const eye = new PartBuilder();
  eye.add(cyl(0.3, 0.34, 0.16, 16), E.brass, { rot: [Math.PI / 2, 0, 0] });
  eye.add(cyl(0.24, 0.24, 0.18, 16), E.metal, { rot: [Math.PI / 2, 0, 0] });
  eye.add(cyl(0.17, 0.17, 0.2, 16), 0xffffff, { rot: [Math.PI / 2, 0, 0], ...EYE });
  eye.add(box(0.36, 0.035, 0.22), E.metal, {});
  const reel = () => {
    const r = new PartBuilder();
    r.add(cyl(0.38, 0.38, 0.1, 18), E.brass, { rot: [0, 0, Math.PI / 2] });
    r.add(cyl(0.12, 0.12, 0.14, 6), E.metal, { rot: [0, 0, Math.PI / 2] });
    for (let i = 0; i < 6; i++) {
      const a = (i / 6) * Math.PI * 2;
      r.add(box(0.12, 0.05, 0.05), E.metal, { pos: [0, Math.sin(a) * 0.22, Math.cos(a) * 0.22], rot: [a, 0, 0] });
    }
    r.add(torus(0.36, 0.02, 4, 24), E.rune, { rot: [0, Math.PI / 2, 0], ...RUNE });
    return r.build();
  };
  const plate = () => {
    const p = new PartBuilder();
    p.add(box(0.55, 0.9, 0.12), E.stone, { pos: [0, 0, 0] });
    p.add(box(0.57, 0.08, 0.14), E.brass, { pos: [0, 0.32, 0] });
    p.add(box(0.57, 0.08, 0.14), E.brass, { pos: [0, -0.32, 0] });
    p.add(extrudePoly([[0, 0.12], [0.1, -0.06], [-0.1, -0.06]], 0.02), E.rune, { pos: [0, 0, 0.07], ...RUNE });
    return p.build();
  };
  const ribbon = new PartBuilder();
  // Memory ribbons: loops of magnetic tape, shown while the boss acts on a remembered recording.
  const pts: [number, number, number][] = [];
  for (let i = 0; i <= 24; i++) {
    const a = (i / 24) * Math.PI * 2;
    pts.push([Math.cos(a) * 1.25, Math.sin(a * 3) * 0.12, Math.sin(a) * 1.25]);
  }
  ribbon.add(tube(pts, 0.02, 64, 4), 0x2b1d14, {});
  ribbon.add(tube(pts.map(([x, y, z]) => [x * 0.9, y + 0.2, z * 0.9] as [number, number, number]), 0.012, 64, 3), 0xffffff, {
    glow: 1,
    accent: 1,
  });
  const joints: JointSpec[] = [
    { name: 'base', parent: null, pos: [0, 0, 0], geo: base.build() },
    { name: 'body', parent: null, pos: [0, 0.5, 0], geo: core.build() },
    { name: 'eye', parent: 'body', pos: [0, 0.7, 0.5], geo: eye.build() },
    { name: 'reelL', parent: 'body', pos: [0.62, 0.65, 0], geo: reel() },
    { name: 'reelR', parent: 'body', pos: [-0.62, 0.65, 0], geo: reel() },
    { name: 'ribbon', parent: 'body', pos: [0, 0.8, 0], geo: ribbon.build() },
  ];
  const plateGeo = plate();
  for (let i = 0; i < 4; i++) {
    joints.push({ name: `plate${i}`, parent: 'body', pos: [0, 0.6, 0], geo: i === 0 ? plateGeo : plateGeo });
  }
  return {
    type: 'boss',
    joints,
    top: 2.7,
    radius: 1.2,
    telegraph: { kind: 'circle', radius: 3.0 },
    hover: 0,
    hull: 0.022,
  };
}

const BUILDERS: Record<EnemyType, () => EnemyRigSpec> = { grunt, stalker, turret, shielder, brute, drone, boss };

export function buildEnemySpec(type: EnemyType): EnemyRigSpec {
  return BUILDERS[type]();
}

export function disposeEnemySpec(spec: EnemyRigSpec): void {
  const seen = new Set<THREE.BufferGeometry>();
  for (const j of spec.joints) if (j.geo && !seen.has(j.geo)) {
    seen.add(j.geo);
    j.geo.dispose();
  }
}

/** Shield dome for the shielder, outside the cel pipeline (energy, not matter). */
export function shieldDomeGeometry(): THREE.BufferGeometry {
  const g = ico(0.62, 1);
  return g;
}
