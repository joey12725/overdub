/**
 * Moxie, built from primitives (CHAR-01..09, R01 as the colour anchor, R02 for turnaround/pose).
 *
 * About 1.05 scene units tall with chibi proportions so she reads in the isometric view: a big head
 * with oversized YELLOW over-ear headphones (CHAR-05, the signature), messy dark-brown pigtails
 * (CHAR-07), light crop top with dark trim and a diagonal strap, dark jacket with yellow lining worn
 * off the shoulders, baggy olive low-rise cargos with a yellow zigzag graphic and a red/pink hanging
 * strap (CHAR-08), a belt with the yellow Walkman (CHAR-06) and tech pouches, wrist devices with
 * glowing screens (CHAR-09), fingerless gloves and chunky high-tops with yellow laces.
 *
 * The geometry is built once per level (the loadout is fixed for the attempt) and shared by all four
 * selves; each self owns its own meshes and materials so styles can differ per tape.
 */
import * as THREE from 'three';
import type { GearSlot, MeleeWeaponDef } from '../../core/types';
import {
  PartBuilder,
  box,
  cone,
  cyl,
  extrudePoly,
  lathe,
  sphere,
  torus,
  tube,
} from './geom';
import { parseHexColor } from './math';
import type { Pose } from './pose';

export const MOXIE_COLORS = {
  skin: 0xc98559,
  skinDark: 0xa8653f,
  hair: 0x3b2219,
  hairLight: 0x5e3826,
  phones: 0xffc414,
  phonesDark: 0xd99a00,
  phonesEmblem: 0x231d26,
  top: 0xece5d6,
  trim: 0x262125,
  jacket: 0x2c2427,
  jacketLight: 0x3e3437,
  lining: 0xf4b51b,
  pants: 0x6d6a3b,
  pantsDark: 0x575430,
  graphic: 0xf6c12b,
  strap: 0xc8285a,
  belt: 0x2a2626,
  metal: 0x9aa0a6,
  walkman: 0xffc81e,
  walkmanDark: 0x2a2328,
  pouch: 0x3d3b3e,
  vial: 0x3ee8d2,
  device: 0x26262c,
  screen: 0x4ff2ff,
  glove: 0x221f24,
  shoeUpper: 0x2f2a2c,
  shoeSole: 0xebe1d0,
  shoeCap: 0xd5c9b2,
  laces: 0xffc81e,
  eye: 0x2a140c,
  iris: 0xe39b2a,
  white: 0xfff8ee,
  mark: 0xe8406a,
  markB: 0x48d6ff,
  bandage: 0xf1dcc0,
} as const;

/** Looks per slot as provided by ResolvedLoadout.looks (APPAREL-03). */
export type LookMap = Partial<Record<GearSlot, { color?: string; variant?: string }>>;

/** Supported `look.variant` values, by slot; unknown variants fall back to the baseline shape. */
export const LOOK_VARIANTS = {
  helmet: ['none', 'visor', 'cap', 'beanie', 'goggles', 'antenna', 'mask'],
  top: ['crop', 'tank', 'armored', 'vest'],
  pants: ['cargo', 'shorts', 'armored', 'joggers'],
  shoes: ['hightop', 'boots', 'runners', 'mag'],
} as const;

/** Rig dimensions (scene units). */
export const RIG = {
  hipY: 0.46,
  spineY: 0.06,
  headY: 0.21,
  shoulderX: 0.115,
  shoulderY: 0.165,
  upperArm: 0.14,
  foreArm: 0.13,
  legX: 0.068,
  thigh: 0.19,
  shin: 0.18,
  headR: 0.135,
  /** Height of the top of the head (for markers). */
  top: 1.08,
  /** Height of the hand mount for trails. */
  handY: 0.62,
} as const;

export const HEAD_SCALE = 1.16;

export type BoneName =
  | 'hips'
  | 'spine'
  | 'jacket'
  | 'head'
  | 'phones'
  | 'pigL'
  | 'pigLTip'
  | 'pigR'
  | 'pigRTip'
  | 'armL'
  | 'elbowL'
  | 'armR'
  | 'elbowR'
  | 'weapon'
  | 'weaponBack'
  | 'legL'
  | 'kneeL'
  | 'footL'
  | 'legR'
  | 'kneeR'
  | 'footR';

export const BONE_NAMES: readonly BoneName[] = [
  'hips',
  'spine',
  'jacket',
  'head',
  'phones',
  'pigL',
  'pigLTip',
  'pigR',
  'pigRTip',
  'armL',
  'elbowL',
  'armR',
  'elbowR',
  'weapon',
  'weaponBack',
  'legL',
  'kneeL',
  'footL',
  'legR',
  'kneeR',
  'footR',
];

/** Geometry per bone, shared by every self of a level. */
export type MoxieGeometry = Partial<Record<BoneName, THREE.BufferGeometry>>;

function lookColor(looks: LookMap, slot: GearSlot, fallback: number): number {
  return parseHexColor(looks[slot]?.color, fallback);
}

function variantOf<S extends keyof typeof LOOK_VARIANTS>(looks: LookMap, slot: S): (typeof LOOK_VARIANTS)[S][number] {
  const v = looks[slot]?.variant;
  const list = LOOK_VARIANTS[slot] as readonly string[];
  if (v && list.includes(v)) return v as (typeof LOOK_VARIANTS)[S][number];
  // A helmet with a colour but no known variant still has to show up: goggles never hide the phones.
  if (slot === 'helmet' && looks.helmet?.color) return 'goggles' as (typeof LOOK_VARIANTS)[S][number];
  return list[0] as (typeof LOOK_VARIANTS)[S][number];
}

const C = MOXIE_COLORS;

function buildPelvis(looks: LookMap): THREE.BufferGeometry {
  const b = new PartBuilder();
  const pants = lookColor(looks, 'pants', C.pants);
  const pv = variantOf(looks, 'pants');
  // Low-rise seat of the cargos: wide and baggy, sits well below the navel.
  b.add(lathe([[0.0, -0.07], [0.105, -0.07], [0.118, -0.03], [0.112, 0.02], [0.104, 0.045], [0.0, 0.045]], 12), pants);
  // Belt: dark band with a metal buckle; worn slightly crooked.
  b.add(cyl(0.112, 0.114, 0.026, 14, true), C.belt, { pos: [0, 0.042, 0], rot: [0, 0, 0.05] });
  b.add(torus(0.113, 0.012, 4, 16), C.belt, { pos: [0, 0.042, 0], rot: [Math.PI / 2, 0, 0.05] });
  b.add(box(0.04, 0.03, 0.012), C.metal, { pos: [-0.02, 0.045, 0.112] });
  // Yellow Walkman on the left hip, face out (CHAR-06), with a lit cassette window.
  b.add(box(0.075, 0.058, 0.03), C.walkman, { pos: [0.075, 0.02, 0.09], rot: [0, 0.6, 0] });
  b.add(box(0.05, 0.026, 0.006), C.walkmanDark, { pos: [0.085, 0.024, 0.106], rot: [0, 0.6, 0] });
  b.add(box(0.012, 0.012, 0.004), 0xffffff, { pos: [0.077, 0.024, 0.112], rot: [0, 0.6, 0], glow: 1 });
  b.add(box(0.012, 0.012, 0.004), 0xffffff, { pos: [0.096, 0.024, 0.098], rot: [0, 0.6, 0], glow: 1 });
  b.add(box(0.06, 0.008, 0.02), C.walkmanDark, { pos: [0.075, 0.053, 0.09], rot: [0, 0.6, 0] });
  // Tech pouches and a glowing vial round the right side and back (scavenged, not uniform).
  b.add(box(0.045, 0.05, 0.035), C.pouch, { pos: [-0.1, 0.01, 0.05], rot: [0, -0.9, 0] });
  b.add(box(0.03, 0.008, 0.036), C.graphic, { pos: [-0.1, 0.035, 0.05], rot: [0, -0.9, 0] });
  b.add(box(0.04, 0.045, 0.03), C.pouch, { pos: [-0.105, 0.012, -0.045], rot: [0, -1.9, 0] });
  b.add(cyl(0.011, 0.011, 0.06, 6), C.vial, { pos: [-0.118, -0.02, 0.0], glow: 1 });
  b.add(box(0.05, 0.04, 0.03), C.pouch, { pos: [0.02, 0.015, -0.11] });
  b.add(box(0.012, 0.012, 0.004), C.screen, { pos: [0.02, 0.02, -0.126], glow: 1 });
  // Red/pink hanging strap from the front buckle down over the right thigh.
  b.add(box(0.022, 0.2, 0.006), C.strap, { pos: [-0.045, -0.06, 0.113], rot: [0.1, 0, 0.18] });
  b.add(box(0.026, 0.012, 0.01), C.metal, { pos: [-0.063, -0.15, 0.122], rot: [0.1, 0, 0.18] });
  if (pv === 'armored') {
    b.add(box(0.16, 0.05, 0.02), 0x4a4a52, { pos: [0, -0.04, 0.11], rot: [0.15, 0, 0] });
  }
  return b.build();
}

function buildSpine(looks: LookMap): THREE.BufferGeometry {
  const b = new PartBuilder();
  const top = lookColor(looks, 'top', C.top);
  const tv = variantOf(looks, 'top');
  // Bare midriff (crop top + low-rise pants is an explicit choice: CHAR-08).
  b.add(lathe([[0.0, -0.02], [0.085, -0.02], [0.08, 0.04], [0.088, 0.08], [0.0, 0.08]], 12), C.skin);
  const topBottom = tv === 'tank' ? -0.01 : 0.075;
  // Light crop top with dark trim (R01).
  b.add(
    lathe(
      [
        [0.0, topBottom],
        [0.098, topBottom],
        [0.105, 0.11],
        [0.1, 0.15],
        [0.08, 0.175],
        [0.0, 0.18],
      ],
      12,
    ),
    top,
  );
  b.add(torus(0.098, 0.008, 4, 16), C.trim, { pos: [0, topBottom, 0], rot: [Math.PI / 2, 0, 0] });
  // Chest emblem (R01 dark star/arrow on the top).
  b.add(extrudePoly([[0, 0.022], [0.018, -0.012], [0, -0.004], [-0.018, -0.012]], 0.004), C.trim, {
    pos: [0, 0.125, 0.1],
    rot: [-0.15, 0, 0],
  });
  // Shoulder straps of the top + bare collarbones/neck.
  b.add(box(0.016, 0.06, 0.012), C.trim, { pos: [0.05, 0.18, 0.04], rot: [0.2, 0, -0.2] });
  b.add(box(0.016, 0.06, 0.012), C.trim, { pos: [-0.05, 0.18, 0.04], rot: [0.2, 0, 0.2] });
  b.add(lathe([[0.0, 0.17], [0.09, 0.17], [0.06, 0.2], [0.035, 0.215], [0.0, 0.215]], 10), C.skin);
  // Diagonal dark strap across the chest, left shoulder to right hip.
  b.add(box(0.024, 0.25, 0.012), C.trim, { pos: [0.0, 0.1, 0.105], rot: [0.12, 0, 0.62] });
  b.add(box(0.03, 0.02, 0.016), C.metal, { pos: [0.02, 0.12, 0.112], rot: [0.12, 0, 0.62] });
  b.add(box(0.024, 0.25, 0.012), C.trim, { pos: [0.0, 0.1, -0.1], rot: [-0.12, 0, -0.62] });
  // Headphone cable from the Walkman up to the neck.
  b.add(tube([[0.07, -0.02, 0.09], [0.055, 0.05, 0.105], [0.03, 0.14, 0.1], [0.04, 0.2, 0.06]], 0.0045, 10, 4), C.phones);
  // Choker.
  b.add(cyl(0.04, 0.04, 0.016, 10), C.trim, { pos: [0, 0.205, 0] });
  b.add(torus(0.01, 0.003, 4, 8), C.metal, { pos: [0, 0.19, 0.04] });
  if (tv === 'armored') {
    b.add(box(0.15, 0.08, 0.025), lookColor(looks, 'top', 0x5a5e66), { pos: [0, 0.13, 0.1], rot: [-0.1, 0, 0] });
    b.add(box(0.13, 0.012, 0.028), C.graphic, { pos: [0, 0.095, 0.105], rot: [-0.1, 0, 0] });
  }
  if (tv === 'vest') {
    b.add(box(0.06, 0.13, 0.02), lookColor(looks, 'top', 0x3a3d45), { pos: [0.065, 0.11, 0.09], rot: [0, 0.3, 0] });
    b.add(box(0.06, 0.13, 0.02), lookColor(looks, 'top', 0x3a3d45), { pos: [-0.065, 0.11, 0.09], rot: [0, -0.3, 0] });
  }
  return b.build();
}

function buildJacket(): THREE.BufferGeometry {
  // Oversized jacket slipped off the shoulders: it hangs behind her from elbow height as a curved
  // drape, the yellow lining showing on its inner face and in the rolled collar (R01).
  const b = new PartBuilder();
  const cz = 0.075; // body axis in the jacket bone's frame
  const shell = new THREE.CylinderGeometry(0.158, 0.182, 0.25, 14, 1, true, Math.PI * 0.55, Math.PI * 0.9);
  shell.translate(0, -0.125, cz);
  b.add(shell, C.jacket);
  const lining = flipFaces(new THREE.CylinderGeometry(0.151, 0.175, 0.24, 14, 1, true, Math.PI * 0.55, Math.PI * 0.9));
  lining.translate(0, -0.125, cz);
  b.add(lining, C.lining);
  // Hem band.
  b.add(new THREE.TorusGeometry(0.182, 0.01, 4, 14, Math.PI * 0.9).rotateX(-Math.PI / 2).rotateY(Math.PI * 0.05).translate(0, -0.25, cz), C.jacketLight);
  // Fat collar roll draped across the back, lining side out.
  b.add(new THREE.TorusGeometry(0.162, 0.019, 5, 16, Math.PI * 0.9).rotateX(-Math.PI / 2).rotateY(Math.PI * 0.05).translate(0, 0.0, cz), C.lining);
  b.add(new THREE.TorusGeometry(0.165, 0.016, 5, 16, Math.PI * 0.9).rotateX(-Math.PI / 2).rotateY(Math.PI * 0.05).translate(0, -0.022, cz), C.jacket);
  // Back graphic: yellow chevrons (R01 sleeve chevrons, repeated where the iso camera sees them).
  const chev: [number, number][] = [[-0.05, 0], [0, -0.035], [0.05, 0], [0.05, -0.018], [0, -0.053], [-0.05, -0.018]];
  b.add(extrudePoly(chev, 0.004), C.graphic, { pos: [0, -0.085, cz - 0.172] });
  b.add(extrudePoly(chev, 0.004), C.graphic, { pos: [0, -0.145, cz - 0.178] });
  return b.build();
}

/** Reverse winding and normals so an open surface shows its inside (jacket lining). */
function flipFaces(g: THREE.BufferGeometry): THREE.BufferGeometry {
  const ng = g.index ? g.toNonIndexed() : g;
  if (ng !== g) g.dispose();
  const pos = ng.getAttribute('position') as THREE.BufferAttribute;
  const nrm = ng.getAttribute('normal') as THREE.BufferAttribute;
  for (let i = 0; i < pos.count; i += 3) {
    for (const a of [pos, nrm]) {
      const x = a.getX(i + 1);
      const y = a.getY(i + 1);
      const z = a.getZ(i + 1);
      a.setXYZ(i + 1, a.getX(i + 2), a.getY(i + 2), a.getZ(i + 2));
      a.setXYZ(i + 2, x, y, z);
    }
  }
  for (let i = 0; i < nrm.count; i++) nrm.setXYZ(i, -nrm.getX(i), -nrm.getY(i), -nrm.getZ(i));
  return ng;
}

function buildHead(looks: LookMap): THREE.BufferGeometry {
  const b = new PartBuilder();
  const R = RIG.headR;
  // Face: slightly squashed sphere with a pointed chin (anime head).
  b.add(sphere(R, 16, 12), C.skin, { pos: [0, 0.11, 0.0], scale: [0.95, 1, 0.98] });
  b.add(cone(0.075, 0.07, 8), C.skin, { pos: [0, 0.015, 0.035], rot: [Math.PI, 0, 0], scale: [1.05, 1, 0.9] });
  // Neck.
  b.add(cyl(0.035, 0.04, 0.06, 8), C.skin, { pos: [0, -0.01, -0.01] });
  // Eyes: big dark almond shapes with amber iris and a highlight, set wide (anime).
  for (const s of [1, -1]) {
    b.add(sphere(0.03, 10, 8), C.eye, { pos: [s * 0.05, 0.1, 0.112], scale: [1.05, 1.15, 0.35] });
    b.add(sphere(0.019, 8, 6), C.iris, { pos: [s * 0.05, 0.096, 0.121], scale: [1, 1.2, 0.3] });
    b.add(sphere(0.008, 6, 4), C.white, { pos: [s * 0.043, 0.112, 0.125], scale: [1, 1, 0.4], glow: 0.6 });
    // Thick upper lash line.
    b.add(box(0.064, 0.012, 0.012), C.eye, { pos: [s * 0.052, 0.132, 0.112], rot: [0, s * 0.35, s * -0.18] });
  }
  // Brows.
  b.add(box(0.045, 0.008, 0.01), C.hair, { pos: [0.052, 0.165, 0.115], rot: [0, 0.3, 0.15] });
  b.add(box(0.045, 0.008, 0.01), C.hair, { pos: [-0.052, 0.165, 0.115], rot: [0, -0.3, -0.15] });
  // Cocky smirk.
  b.add(box(0.04, 0.007, 0.008), 0x6a2a24, { pos: [0.006, 0.036, 0.112], rot: [0, 0, -0.12] });
  // Face markings: pink/cyan stripes under the left eye (R02), bandage on the right cheek (R01).
  b.add(box(0.04, 0.009, 0.006), C.mark, { pos: [0.06, 0.068, 0.113], rot: [0, 0.45, 0.25] });
  b.add(box(0.032, 0.007, 0.006), C.markB, { pos: [0.068, 0.056, 0.11], rot: [0, 0.45, 0.25] });
  b.add(box(0.036, 0.016, 0.008), C.bandage, { pos: [-0.066, 0.06, 0.108], rot: [0, -0.45, -0.5] });
  b.add(box(0.03, 0.006, 0.006), 0xc94a4a, { pos: [-0.055, 0.075, 0.114], rot: [0, -0.45, -0.3] });

  // Hair: a dark-brown cap with messy spikes; bangs fall over the forehead (CHAR-07).
  b.add(sphere(R * 1.07, 14, 10, ), C.hair, { pos: [0, 0.13, -0.012], scale: [1.0, 0.95, 1.0] });
  const spikes: [number, number, number, number, number][] = [
    // x, y, z, rotX, rotZ (cones point +Y before rotation)
    [0.0, 0.25, -0.02, -0.3, 0.0],
    [0.06, 0.24, 0.02, 0.1, -0.6],
    [-0.06, 0.24, 0.02, 0.1, 0.6],
    [0.09, 0.2, -0.06, -0.5, -0.9],
    [-0.09, 0.2, -0.06, -0.5, 0.9],
    [0.03, 0.22, -0.1, -1.2, -0.3],
    [-0.04, 0.2, -0.12, -1.4, 0.4],
    [0.12, 0.12, -0.04, -0.2, -1.6],
    [-0.12, 0.12, -0.04, -0.2, 1.6],
  ];
  for (const [x, y, z, rx, rz] of spikes) b.add(cone(0.04, 0.11, 5), C.hair, { pos: [x, y, z], rot: [rx, 0, rz] });
  const bangs: [number, number, number][] = [
    [0.0, 0.2, 0.122],
    [0.05, 0.195, 0.115],
    [-0.05, 0.195, 0.115],
    [0.09, 0.17, 0.095],
    [-0.09, 0.17, 0.095],
    [0.025, 0.185, 0.128],
  ];
  bangs.forEach(([x, y, z], i) =>
    b.add(cone(0.03, 0.075, 4), i % 2 ? C.hairLight : C.hair, {
      pos: [x, y, z],
      rot: [Math.PI - 0.35, 0, x * 3.5 + (i % 3) * 0.12 - 0.12],
    }),
  );
  // Side locks framing the face.
  b.add(cone(0.03, 0.14, 5), C.hair, { pos: [0.115, 0.07, 0.06], rot: [Math.PI + 0.15, 0, 0.12] });
  b.add(cone(0.03, 0.14, 5), C.hair, { pos: [-0.115, 0.07, 0.06], rot: [Math.PI + 0.15, 0, -0.12] });

  const hv = variantOf(looks, 'helmet');
  const hc = lookColor(looks, 'helmet', 0x3c4250);
  // Headgear never covers the ear cups (APPAREL-03 / CHAR-05): everything sits between them.
  switch (hv) {
    case 'visor':
      b.add(cyl(R * 1.02, R * 1.02, 0.035, 16, true, ), hc, { pos: [0, 0.11, 0.01], scale: [1, 1, 1.05], glow: 0.3 });
      b.add(box(0.17, 0.03, 0.01), 0x58f0ff, { pos: [0, 0.11, 0.14], glow: 1 });
      break;
    case 'cap':
      b.add(sphere(R * 1.08, 12, 6), hc, { pos: [0, 0.155, -0.005], scale: [0.92, 0.6, 1.0] });
      b.add(box(0.12, 0.012, 0.09), hc, { pos: [0, 0.16, -0.16], rot: [-0.15, 0, 0] });
      b.add(box(0.04, 0.02, 0.01), C.graphic, { pos: [0, 0.19, 0.12] });
      break;
    case 'beanie':
      b.add(sphere(R * 1.1, 12, 8), hc, { pos: [0, 0.17, -0.01], scale: [0.88, 0.75, 1.0] });
      b.add(torus(R * 0.95, 0.018, 5, 16), hc, { pos: [0, 0.14, -0.005], rot: [Math.PI / 2 - 0.15, 0, 0], scale: [0.92, 1.05, 1] });
      break;
    case 'goggles':
      b.add(torus(R * 0.98, 0.012, 4, 18), hc, { pos: [0, 0.195, 0.0], rot: [Math.PI / 2 - 0.4, 0, 0], scale: [0.9, 1, 1] });
      for (const s of [1, -1]) {
        b.add(cyl(0.03, 0.03, 0.03, 10), hc, { pos: [s * 0.04, 0.215, 0.105], rot: [Math.PI / 2 - 0.6, 0, 0] });
        b.add(cyl(0.022, 0.022, 0.004, 10), 0x7ff3ff, { pos: [s * 0.04, 0.227, 0.118], rot: [Math.PI / 2 - 0.6, 0, 0], glow: 0.8 });
      }
      break;
    case 'antenna':
      b.add(cyl(0.006, 0.006, 0.14, 5), hc, { pos: [-0.06, 0.29, -0.06], rot: [-0.3, 0, 0.3] });
      b.add(sphere(0.016, 8, 6), 0xff5577, { pos: [-0.08, 0.36, -0.08], glow: 1 });
      break;
    case 'mask':
      b.add(sphere(0.07, 10, 6), hc, { pos: [0, 0.035, 0.08], scale: [1.3, 0.75, 0.75] });
      b.add(box(0.05, 0.006, 0.01), 0x58f0ff, { pos: [0, 0.035, 0.135], glow: 1 });
      break;
    default:
      break;
  }
  return b.build();
}

function buildPhones(): THREE.BufferGeometry {
  // The signature: big yellow over-ear cups with the R01 triangle emblem, a thick band over the
  // crown and an accent ring that glows in the cassette colour (UI-02).
  const b = new PartBuilder();
  const cupX = 0.142;
  const cupY = 0.105;
  for (const s of [1, -1]) {
    const rz = (s * Math.PI) / 2;
    b.add(cyl(0.078, 0.082, 0.055, 16), C.phones, { pos: [s * cupX, cupY, -0.005], rot: [0, 0, rz] });
    b.add(cyl(0.07, 0.07, 0.03, 14), C.phonesDark, { pos: [s * (cupX - 0.035), cupY, -0.005], rot: [0, 0, rz] });
    // Accent ring (cassette colour) round the outer face.
    b.add(torus(0.068, 0.009, 5, 18), 0xffffff, {
      pos: [s * (cupX + 0.029), cupY, -0.005],
      rot: [0, Math.PI / 2, 0],
      glow: 1,
      accent: 1,
    });
    b.add(cyl(0.056, 0.056, 0.012, 14), C.phones, { pos: [s * (cupX + 0.03), cupY, -0.005], rot: [0, 0, rz] });
    // Triangle emblem.
    b.add(extrudePoly([[0, 0.032], [0.03, -0.02], [-0.03, -0.02]], 0.008), C.phonesEmblem, {
      pos: [s * (cupX + 0.037), cupY - 0.002, -0.005],
      rot: [0, (s * Math.PI) / 2, 0],
    });
    b.add(extrudePoly([[0, 0.014], [0.013, -0.009], [-0.013, -0.009]], 0.01), C.phones, {
      pos: [s * (cupX + 0.04), cupY - 0.002, -0.005],
      rot: [0, (s * Math.PI) / 2, 0],
    });
    // Yoke.
    b.add(box(0.02, 0.07, 0.03), C.phonesDark, { pos: [s * (cupX - 0.005), cupY + 0.075, -0.005] });
  }
  // Headband arching over the hair.
  b.add(torus(0.15, 0.017, 6, 20, Math.PI), C.phones, { pos: [0, cupY + 0.08, -0.005], scale: [0.98, 0.95, 1.4] });
  b.add(torus(0.15, 0.01, 4, 20, Math.PI), C.phonesEmblem, { pos: [0, cupY + 0.085, -0.005], scale: [0.98, 0.98, 1.6] });
  return b.build();
}

function buildPigtail(side: 1 | -1, tip: boolean): THREE.BufferGeometry {
  // Messy, voluminous tails: a puffed root at the hair tie, chunky tufts hanging down and out,
  // loose strands at the tips (CHAR-07, R01).
  const b = new PartBuilder();
  if (!tip) {
    b.add(sphere(0.058, 9, 7), C.hair, { pos: [0, -0.02, 0], scale: [1, 1.1, 1] });
    b.add(torus(0.032, 0.011, 4, 10), C.strap, { pos: [0, 0.02, 0], rot: [Math.PI / 2, 0, 0] });
    const tufts: [number, number, number, number, number, number][] = [
      [0, -0.07, 0, 0, 0, 0.052],
      [side * 0.03, -0.06, 0.03, 0.35, side * 0.35, 0.042],
      [-side * 0.02, -0.065, -0.03, -0.35, -side * 0.2, 0.044],
      [side * 0.045, -0.02, -0.01, 0.1, side * 0.9, 0.034],
    ];
    for (const [x, y, z, rx, rz, r] of tufts)
      b.add(cone(r, 0.15, 5), C.hair, { pos: [x, y, z], rot: [Math.PI + rx, 0, rz] });
    b.add(cone(0.022, 0.12, 4), C.hairLight, { pos: [side * 0.035, -0.06, 0.035], rot: [Math.PI + 0.3, 0, side * 0.45] });
  } else {
    const tufts: [number, number, number, number, number, number][] = [
      [0, -0.045, 0, 0, 0, 0.042],
      [side * 0.025, -0.04, 0.022, 0.35, side * 0.4, 0.03],
      [-side * 0.022, -0.04, -0.018, -0.4, -side * 0.3, 0.03],
      [side * 0.01, -0.03, -0.03, -0.8, side * 0.6, 0.022],
    ];
    for (const [x, y, z, rx, rz, r] of tufts)
      b.add(cone(r, 0.13, 4), C.hair, { pos: [x, y, z], rot: [Math.PI + rx, 0, rz] });
    // Loose strands.
    b.add(tube([[0, 0, 0], [side * 0.02, -0.06, 0.01], [side * 0.05, -0.11, -0.01], [side * 0.04, -0.15, 0.02]], 0.0045, 8, 3), C.hairLight);
    b.add(tube([[0, 0, 0], [-side * 0.01, -0.07, -0.02], [-side * 0.035, -0.12, -0.01]], 0.004, 6, 3), C.hair);
  }
  return b.build();
}

function buildUpperArm(side: 1 | -1): THREE.BufferGeometry {
  const b = new PartBuilder();
  // Bare shoulder, then the slipped-off jacket sleeve bunched from mid upper arm (R01).
  b.add(sphere(0.04, 10, 8), C.skin, { pos: [0, -0.01, 0] });
  b.add(cyl(0.03, 0.028, 0.08, 8), C.skin, { pos: [0, -0.04, 0] });
  b.add(cyl(0.056, 0.05, 0.1, 10), C.jacket, { pos: [0, -0.1, -0.004] });
  b.add(torus(0.053, 0.009, 5, 14), C.lining, { pos: [0, -0.053, -0.004], rot: [Math.PI / 2, 0, 0] });
  // Chevron on the sleeve (R01).
  b.add(extrudePoly([[-0.03, 0], [0, -0.02], [0.03, 0], [0.03, -0.012], [0, -0.032], [-0.03, -0.012]], 0.004), C.graphic, {
    pos: [side * 0.054, -0.09, 0],
    rot: [0, (side * Math.PI) / 2, 0],
  });
  return b.build();
}

function buildForearm(side: 1 | -1): THREE.BufferGeometry {
  const b = new PartBuilder();
  // Bunched oversized sleeve to mid forearm, yellow lining at the cuff.
  b.add(cyl(0.05, 0.052, 0.06, 10), C.jacket, { pos: [0, -0.025, 0] });
  b.add(torus(0.048, 0.011, 5, 14), C.lining, { pos: [0, -0.058, 0], rot: [Math.PI / 2, 0, 0] });
  b.add(cyl(0.024, 0.022, 0.06, 8), C.skin, { pos: [0, -0.08, 0] });
  // Wrist device: chunky band with a glowing screen (CHAR-09).
  b.add(cyl(0.031, 0.031, 0.036, 10), C.device, { pos: [0, -0.1, 0] });
  b.add(box(0.03, 0.022, 0.008), C.screen, { pos: [side * 0.006, -0.1, 0.03], glow: 1 });
  b.add(box(0.006, 0.012, 0.006), 0xff4d8d, { pos: [side * 0.03, -0.096, 0.0], glow: 1 });
  // Fingerless glove: dark palm, skin finger stubs.
  b.add(box(0.044, 0.048, 0.03), C.glove, { pos: [0, -0.135, 0.004] });
  b.add(box(0.04, 0.02, 0.026), C.skin, { pos: [0, -0.165, 0.006] });
  b.add(box(0.014, 0.03, 0.016), C.skin, { pos: [side * -0.026, -0.14, 0.014], rot: [0, 0, side * 0.4] });
  return b.build();
}

function buildThigh(side: 1 | -1, looks: LookMap): THREE.BufferGeometry {
  const b = new PartBuilder();
  const pants = lookColor(looks, 'pants', C.pants);
  const pv = variantOf(looks, 'pants');
  // Baggy cargo leg with a side pocket.
  b.add(cyl(0.068, 0.062, RIG.thigh + 0.02, 10), pants, { pos: [0, -RIG.thigh / 2, 0] });
  b.add(box(0.016, 0.06, 0.05), shade(pants, 0.85), { pos: [side * 0.066, -0.11, 0.0] });
  if (side === 1) {
    // Yellow zigzag graphic down the outside of the left leg (R01).
    b.add(box(0.012, 0.05, 0.018), C.graphic, { pos: [0.067, -0.06, 0.03], rot: [0, 0, 0.5] });
    b.add(box(0.012, 0.05, 0.018), C.graphic, { pos: [0.067, -0.1, 0.025], rot: [0, 0, -0.5] });
    b.add(box(0.012, 0.05, 0.018), C.graphic, { pos: [0.065, -0.14, 0.03], rot: [0, 0, 0.5] });
  }
  if (pv === 'shorts') {
    b.add(torus(0.062, 0.012, 5, 12), shade(pants, 0.85), { pos: [0, -RIG.thigh, 0], rot: [Math.PI / 2, 0, 0] });
  }
  return b.build();
}

function buildShin(side: 1 | -1, looks: LookMap): THREE.BufferGeometry {
  const b = new PartBuilder();
  const pants = lookColor(looks, 'pants', C.pants);
  const pv = variantOf(looks, 'pants');
  if (pv === 'shorts') {
    b.add(cyl(0.032, 0.028, RIG.shin, 8), C.skin, { pos: [0, -RIG.shin / 2, 0] });
  } else if (pv === 'joggers') {
    b.add(cyl(0.058, 0.04, RIG.shin, 10), pants, { pos: [0, -RIG.shin / 2, 0] });
    b.add(cyl(0.042, 0.042, 0.03, 10), shade(pants, 0.8), { pos: [0, -RIG.shin + 0.01, 0] });
  } else {
    // Baggy leg ballooning over the boot, rolled cuff (R01).
    b.add(cyl(0.06, 0.068, RIG.shin - 0.02, 10), pants, { pos: [0, -RIG.shin / 2 + 0.01, 0] });
    b.add(cyl(0.072, 0.072, 0.035, 10), shade(pants, 0.82), { pos: [0, -RIG.shin + 0.02, 0] });
    if (side === -1) {
      // Rip at the right knee showing skin.
      b.add(sphere(0.022, 8, 6), C.skin, { pos: [0, -0.02, 0.056], scale: [1.2, 0.8, 0.4] });
    } else {
      b.add(box(0.012, 0.05, 0.018), C.graphic, { pos: [0.064, -0.05, 0.03], rot: [0, 0, -0.5] });
    }
  }
  if (pv === 'armored') {
    b.add(box(0.07, 0.06, 0.025), lookColor(looks, 'pants', 0x4a4a52), { pos: [0, -0.02, 0.06] });
  }
  return b.build();
}

function buildFoot(looks: LookMap): THREE.BufferGeometry {
  const b = new PartBuilder();
  const upper = lookColor(looks, 'shoes', C.shoeUpper);
  const sv = variantOf(looks, 'shoes');
  const fy = -0.075; // sole bottom relative to ankle
  if (sv === 'runners') {
    b.add(box(0.075, 0.02, 0.16), C.shoeSole, { pos: [0, fy + 0.01, 0.025] });
    b.add(box(0.07, 0.045, 0.14), upper, { pos: [0, fy + 0.04, 0.02] });
    b.add(box(0.04, 0.01, 0.07), C.laces, { pos: [0, fy + 0.065, 0.045] });
    return b.build();
  }
  const tall = sv === 'boots' ? 0.05 : 0;
  // Chunky high-top: thick off-white sole, dark upper, pale toe cap, yellow laces and tag (R01).
  b.add(box(0.088, 0.032, 0.17), C.shoeSole, { pos: [0, fy + 0.016, 0.028] });
  b.add(box(0.082, 0.05, 0.15), upper, { pos: [0, fy + 0.055, 0.025] });
  b.add(box(0.08, 0.04, 0.05), C.shoeCap, { pos: [0, fy + 0.05, 0.085] });
  b.add(cyl(0.048, 0.05, 0.075 + tall, 10), upper, { pos: [0, fy + 0.1 + tall / 2, -0.005] });
  b.add(cyl(0.05, 0.05, 0.016, 10), C.shoeCap, { pos: [0, fy + 0.14 + tall, -0.005] });
  for (let i = 0; i < 3; i++) {
    b.add(box(0.05, 0.009, 0.012), C.laces, { pos: [0, fy + 0.07 + i * 0.022, 0.045 - i * 0.012], rot: [-0.5, 0, (i % 2 ? 1 : -1) * 0.25] });
  }
  b.add(extrudePoly([[0, 0.016], [0.015, -0.01], [-0.015, -0.01]], 0.004), C.laces, {
    pos: [0.044, fy + 0.06, 0.0],
    rot: [0, Math.PI / 2, 0],
  });
  if (sv === 'mag') {
    b.add(box(0.09, 0.008, 0.16), 0x5ff6ff, { pos: [0, fy + 0.004, 0.028], glow: 1 });
  }
  return b.build();
}

function buildWeapon(melee: MeleeWeaponDef, looks: LookMap): THREE.BufferGeometry {
  // Built along +Y from the grip at the origin. Length tracks reach so reach differences read
  // (WEAPON-04 / NEW-01) without becoming absurd at gameplay scale.
  const b = new PartBuilder();
  const color = parseHexColor(looks.melee?.color, 0);
  const len = Math.max(0.16, Math.min(0.5, melee.reach * 0.26));
  switch (melee.style) {
    case 'blade': {
      const bladeCol = color || 0xd8dde6;
      b.add(cyl(0.012, 0.012, 0.07, 6), C.trim, { pos: [0, 0.0, 0] });
      b.add(box(0.016, 0.03, 0.016), C.graphic, { pos: [0, -0.01, 0] });
      b.add(box(0.07, 0.014, 0.022), C.metal, { pos: [0, 0.04, 0] });
      b.add(
        extrudePoly([[-0.022, 0], [0.02, 0], [0.026, len * 0.7], [0.0, len], [-0.012, len * 0.82]], 0.008),
        bladeCol,
        { pos: [0, 0.045, 0] },
      );
      b.add(box(0.005, len * 0.75, 0.01), 0x9ff4ff, { pos: [0.004, 0.045 + len * 0.4, 0], glow: 1 });
      break;
    }
    case 'blunt': {
      const headCol = color || 0x8a8f99;
      b.add(cyl(0.014, 0.014, len, 6), 0x5a5e66, { pos: [0, len / 2 - 0.02, 0] });
      b.add(box(0.03, 0.05, 0.03), C.graphic, { pos: [0, -0.005, 0] });
      b.add(box(0.1, 0.065, 0.065), headCol, { pos: [0, len, 0] });
      b.add(box(0.105, 0.016, 0.07), C.graphic, { pos: [0, len, 0] });
      b.add(box(0.02, 0.03, 0.03), 0xff7a2a, { pos: [0.055, len, 0], glow: 0.8 });
      break;
    }
    case 'whip': {
      const cable = color || 0x3a3640;
      b.add(cyl(0.014, 0.012, 0.08, 6), C.trim, { pos: [0, 0.02, 0] });
      b.add(sphere(0.016, 6, 4), C.graphic, { pos: [0, 0.065, 0] });
      // Coiled cable hanging from the grip; the swing trail shows its full lash.
      b.add(
        tube(
          [
            [0, 0.07, 0],
            [0.03, 0.12, 0.02],
            [0.05, 0.08, -0.02],
            [0.02, 0.03, -0.04],
            [-0.03, 0.06, -0.01],
            [-0.02, 0.13, 0.03],
            [0.04, 0.17, 0.04],
          ],
          0.007,
          24,
          4,
        ),
        cable,
      );
      b.add(sphere(0.012, 6, 4), 0x5ff6ff, { pos: [0.04, 0.17, 0.04], glow: 1 });
      break;
    }
    case 'gauntlet': {
      const plate = color || 0xffc81e;
      // Oversized armoured fist over the right hand; points along +Y = out of the hand.
      b.add(box(0.075, 0.075, 0.07), plate, { pos: [0, 0.01, 0.0] });
      b.add(box(0.08, 0.025, 0.075), C.trim, { pos: [0, 0.055, 0.0] });
      for (let i = 0; i < 4; i++) b.add(box(0.016, 0.02, 0.02), C.metal, { pos: [-0.027 + i * 0.018, 0.075, 0.02] });
      b.add(cyl(0.045, 0.04, 0.06, 8), C.trim, { pos: [0, -0.05, 0] });
      b.add(box(0.03, 0.012, 0.006), C.screen, { pos: [0, -0.04, 0.042], glow: 1 });
      break;
    }
  }
  return b.build();
}

function shade(hex: number, f: number): number {
  const r = Math.round(((hex >> 16) & 255) * f);
  const g = Math.round(((hex >> 8) & 255) * f);
  const bl = Math.round((hex & 255) * f);
  return (r << 16) | (g << 8) | bl;
}

/** Build every bone's geometry for a loadout. Call once per level. */
export function buildMoxieGeometry(melee: MeleeWeaponDef, looks: LookMap = {}): MoxieGeometry {
  const weapon = buildWeapon(melee, looks);
  return {
    hips: buildPelvis(looks),
    spine: buildSpine(looks),
    jacket: buildJacket(),
    head: buildHead(looks),
    phones: buildPhones(),
    pigL: buildPigtail(1, false),
    pigLTip: buildPigtail(1, true),
    pigR: buildPigtail(-1, false),
    pigRTip: buildPigtail(-1, true),
    armL: buildUpperArm(1),
    elbowL: buildForearm(1),
    armR: buildUpperArm(-1),
    elbowR: buildForearm(-1),
    weapon,
    // Stowed copy across the back while not swinging (shared geometry; gauntlets stay on the fist).
    weaponBack: melee.style === 'gauntlet' ? undefined : weapon,
    legL: buildThigh(1, looks),
    kneeL: buildShin(1, looks),
    footL: buildFoot(looks),
    legR: buildThigh(-1, looks),
    kneeR: buildShin(-1, looks),
    footR: buildFoot(looks),
  };
}

export function disposeMoxieGeometry(g: MoxieGeometry): void {
  const seen = new Set<THREE.BufferGeometry>();
  for (const k of BONE_NAMES) {
    const geo = g[k];
    if (geo && !seen.has(geo)) {
      seen.add(geo);
      geo.dispose();
    }
  }
}

/** Bone hierarchy with rest offsets; meshes are attached by the caller. */
export interface MoxieBones {
  /** Positioned at the actor's feet, rotated by facing. */
  root: THREE.Group;
  /** Carries rootY / rootFwd / stretch so markers on `root` stay steady. */
  body: THREE.Group;
  bones: Record<BoneName, THREE.Group>;
}

export function createMoxieBones(): MoxieBones {
  const root = new THREE.Group();
  const body = new THREE.Group();
  root.add(body);
  const mk = (): THREE.Group => new THREE.Group();
  const bones = {} as Record<BoneName, THREE.Group>;
  for (const n of BONE_NAMES) bones[n] = mk();
  const B = bones;
  body.add(B.hips);
  B.hips.position.set(0, RIG.hipY, 0);
  B.hips.add(B.spine);
  B.spine.position.set(0, RIG.spineY, 0);
  B.spine.add(B.jacket);
  B.jacket.position.set(0, 0.11, -0.075);
  B.spine.add(B.head);
  B.head.position.set(0, RIG.headY, 0);
  // Chibi head: bigger than anatomy so face, hair and headphones read at isometric scale.
  B.head.scale.setScalar(HEAD_SCALE);
  B.head.add(B.phones);
  B.head.add(B.pigL);
  B.pigL.position.set(0.105, 0.21, -0.075);
  B.pigL.add(B.pigLTip);
  B.pigLTip.position.set(0, -0.13, 0);
  B.head.add(B.pigR);
  B.pigR.position.set(-0.105, 0.21, -0.075);
  B.pigR.add(B.pigRTip);
  B.pigRTip.position.set(0, -0.13, 0);
  B.spine.add(B.armL);
  B.armL.position.set(RIG.shoulderX, RIG.shoulderY, 0);
  B.armL.add(B.elbowL);
  B.elbowL.position.set(0, -RIG.upperArm, 0);
  B.spine.add(B.armR);
  B.armR.position.set(-RIG.shoulderX, RIG.shoulderY, 0);
  B.armR.add(B.elbowR);
  B.elbowR.position.set(0, -RIG.upperArm, 0);
  B.elbowR.add(B.weapon);
  B.weapon.position.set(0, -0.145, 0.012);
  B.weapon.rotation.set(1.9, 0, 0);
  B.spine.add(B.weaponBack);
  B.weaponBack.position.set(0.07, -0.06, -0.15);
  B.weaponBack.rotation.set(-0.15, 0, 0.55);
  B.hips.add(B.legL);
  B.legL.position.set(RIG.legX, -0.02, 0);
  B.legL.add(B.kneeL);
  B.kneeL.position.set(0, -RIG.thigh, 0);
  B.kneeL.add(B.footL);
  B.footL.position.set(0, -RIG.shin, 0);
  B.hips.add(B.legR);
  B.legR.position.set(-RIG.legX, -0.02, 0);
  B.legR.add(B.kneeR);
  B.kneeR.position.set(0, -RIG.thigh, 0);
  B.kneeR.add(B.footR);
  B.footR.position.set(0, -RIG.shin, 0);
  for (const n of ['armL', 'armR', 'legL', 'legR'] as const) bones[n].rotation.order = 'ZXY';
  return { root, body, bones };
}

/** Pose → bone transforms. Allocation-free. */
export function applyPose(b: MoxieBones, p: Pose): void {
  const B = b.bones;
  const st = p.stretch;
  b.body.position.set(0, p.rootY, p.rootFwd);
  b.body.scale.set(1 - st * 0.25, 1 - st * 0.35, 1 + st);
  B.hips.rotation.set(p.hipsPitch, p.hipsYaw, p.hipsRoll);
  B.spine.rotation.set(p.spinePitch, p.spineYaw, p.spineRoll);
  B.head.rotation.set(p.headPitch, p.headYaw, p.headRoll);
  B.phones.position.y = p.phonesBob;
  B.jacket.rotation.x = 0.12 + p.jacketFlare * 0.7;
  B.armL.rotation.set(-p.armLRaise, p.armLTwist, p.armLOut);
  B.elbowL.rotation.x = -p.elbowL;
  B.armR.rotation.set(-p.armRRaise, -p.armRTwist, -p.armROut);
  B.elbowR.rotation.x = -p.elbowR;
  B.legL.rotation.set(-p.legLRaise, 0, p.legLOut);
  B.kneeL.rotation.x = p.kneeL;
  B.footL.rotation.x = p.footL + p.legLRaise - p.kneeL;
  B.legR.rotation.set(-p.legRRaise, 0, -p.legROut);
  B.kneeR.rotation.x = p.kneeR;
  B.footR.rotation.x = p.footR + p.legRRaise - p.kneeR;
  // Pigtails sit high and flare up/out; swing trails them backward, tips droop further.
  B.pigL.rotation.set(0.45 + p.pigLSwing, 0, 0.35 + p.pigLOut * 0.7);
  B.pigLTip.rotation.set(p.pigLTip * 0.8, 0, -0.25 - p.pigLTip * 0.4);
  B.pigR.rotation.set(0.45 + p.pigRSwing, 0, -0.35 - p.pigROut * 0.7);
  B.pigRTip.rotation.set(p.pigRTip * 0.8, 0, 0.25 + p.pigRTip * 0.4);
}
