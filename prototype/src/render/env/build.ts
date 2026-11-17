/**
 * Builds a level's environment from LevelDef.map: instanced floor tiles per variant, bevelled wall
 * blocks (cut low on the camera side; chapter 16), barriers, the floating-diorama cliff skirt, edge
 * trim and hazard bands, decor entities and seeded ambient dressing.
 *
 * Draw-call budget: every repeated element is an InstancedMesh (one per variant), so a level costs a
 * few dozen draw calls regardless of size. Nothing here allocates per frame after construction.
 */
import * as THREE from 'three';
import type { DecorDef, LevelDef } from '../../core/types';
import type { MusicReactive } from '../layer';
import type { MaterialKit } from '../materials';
import { type EnvPalette, mixColor, scaleColor } from '../palettes';
import { type DecorCtx, type Practical, buildDecor, mountOnFace } from './decor';
import { chamferBox, cliffColumn, leafClump, rockGeometry, tuftGeometry } from './geom';
import {
  BARRIER_HEIGHT,
  type FloorKind,
  type LevelLayout,
  TILE_THICK,
  computeLayout,
} from './layout';
import { reactiveGlow, reactiveToon, registerReactive } from './reactive';
import { Rng, tileNoise } from './rng';
import { planScatter } from './scatter';
import {
  blobTexture,
  cliffTexture,
  floorTextures,
  hazardTexture,
  vineTexture,
  wallTextures,
} from './textures';

export interface EnvBuild {
  group: THREE.Group;
  layout: LevelLayout;
  reactive: MusicReactive[];
  practicals: Practical[];
  /** Per-frame ambient animation (wall-clock seconds). */
  update(time: number, dt: number): void;
  /** Top surface height at a sim position. */
  surfaceHeight(x: number, y: number): number;
  /** Counts of instanced elements, for diagnostics and tests. */
  stats: Record<string, number>;
}

/** Collects instance transforms for one geometry + material, then emits a single InstancedMesh. */
class Batch {
  private matrices: THREE.Matrix4[] = [];
  private colors: number[] = [];

  constructor(
    readonly name: string,
    readonly geo: THREE.BufferGeometry,
    readonly mat: THREE.Material | THREE.Material[],
    readonly cast = true,
    readonly receive = true,
  ) {}

  add(m: THREE.Matrix4, color = 0xffffff): void {
    this.matrices.push(m.clone());
    this.colors.push(color);
  }

  get count(): number {
    return this.matrices.length;
  }

  build(): THREE.InstancedMesh | null {
    if (this.matrices.length === 0) return null;
    const mesh = new THREE.InstancedMesh(this.geo, this.mat, this.matrices.length);
    const c = new THREE.Color();
    for (let i = 0; i < this.matrices.length; i++) {
      mesh.setMatrixAt(i, this.matrices[i]);
      mesh.setColorAt(i, c.setHex(this.colors[i]));
    }
    mesh.instanceMatrix.needsUpdate = true;
    if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;
    mesh.castShadow = this.cast;
    mesh.receiveShadow = this.receive;
    mesh.name = this.name;
    mesh.computeBoundingSphere();
    return mesh;
  }
}

const dummy = new THREE.Object3D();
function xform(x: number, y: number, z: number, ry = 0, sx = 1, sy = 1, sz = 1, rx = 0, rz = 0): THREE.Matrix4 {
  dummy.position.set(x, y, z);
  dummy.rotation.set(rx, ry, rz);
  dummy.scale.set(sx, sy, sz);
  dummy.updateMatrix();
  return dummy.matrix;
}

/** Grey multiplier for instance colours: shade variation and contact darkening. */
function grey(f: number): number {
  return scaleColor(0xffffff, f);
}

export function buildEnvironment(level: LevelDef, pal: EnvPalette, kit: MaterialKit): EnvBuild {
  const layout = computeLayout(level);
  const seed = layout.seed;
  const group = new THREE.Group();
  group.name = 'env';
  const reactive: MusicReactive[] = [];
  const practicals: Practical[] = [];
  const animators: ((t: number, dt: number) => void)[] = [];
  const batches: Batch[] = [];
  const batch = (b: Batch): Batch => {
    batches.push(b);
    return b;
  };

  // ───────────── floor tiles ─────────────
  const floorGeo = kit.geo('floorTile', () => chamferBox(0.985, TILE_THICK, 0.985, 0.035, -TILE_THICK));
  const floorSide = kit.toon(scaleColor(pal.floorFinish === 'stone' ? pal.stone : pal.metal, 0.8));
  const floorBatches = new Map<string, Batch>();
  const variants = (k: FloorKind) => (k === 'solid' || k === 'alt' || k === 'cracked' ? 3 : k === 'rune' ? 2 : 1);
  const floorBatch = (kind: FloorKind, variant: number): Batch => {
    const key = `${kind}:${variant}`;
    let b = floorBatches.get(key);
    if (b) return b;
    const tex = floorTextures(pal, kind, seed + variant * 7919);
    kit.texture(tex.map);
    let top: THREE.MeshToonMaterial;
    if (tex.emissiveMap) {
      kit.texture(tex.emissiveMap);
      const glowColor = kind === 'rune' ? pal.rune : pal.neonC;
      top = kit.toon(0xffffff, { map: tex.map, emissiveMap: tex.emissiveMap, emissive: glowColor, emissiveIntensity: kind === 'rune' ? 1.7 : 0.9 });
      registerReactive(reactive, reactiveToon(kind === 'rune' ? 'rune' : 'neon', top));
    } else {
      top = kit.toon(0xffffff, { map: tex.map });
    }
    b = batch(new Batch(`floor:${key}`, floorGeo, [floorSide, top], false, true));
    floorBatches.set(key, b);
    return b;
  };
  for (const f of layout.floors) {
    const variant = Math.floor(f.shade * variants(f.kind)) % variants(f.kind);
    const shade = (0.95 + 0.08 * tileNoise(seed ^ 0x77, f.c, f.r)) * (1 - 0.3 * f.ao);
    floorBatch(f.kind, variant).add(xform(f.c + 0.5, 0, f.r + 0.5, (f.rot * Math.PI) / 2), grey(shade));
  }

  // ───────────── walls ─────────────
  // Two finishes: plain and inscribed / weathered, so etching reads as deliberate (WORLD-02).
  const wallSides: THREE.MeshToonMaterial[] = [];
  let wallTop: THREE.MeshToonMaterial | null = null;
  let wallCutTop: THREE.MeshToonMaterial | null = null;
  for (const inscribed of [false, true]) {
    const wt = wallTextures(pal, seed, inscribed);
    kit.texture(wt.side);
    kit.texture(wt.top);
    kit.texture(wt.cutTop);
    if (wt.sideEmissive) {
      kit.texture(wt.sideEmissive);
      const m = kit.toon(0xffffff, { map: wt.side, emissiveMap: wt.sideEmissive, emissive: pal.rune, emissiveIntensity: 1.1 });
      registerReactive(reactive, reactiveToon('rune', m));
      wallSides.push(m);
    } else {
      wallSides.push(kit.toon(0xffffff, { map: wt.side }));
    }
    wallTop ??= kit.toon(0xffffff, { map: wt.top });
    wallCutTop ??= kit.toon(0xffffff, { map: wt.cutTop });
  }
  const inscribedShare = pal.floorFinish === 'stone' ? 0.3 : 0.28;
  const wallBatches = new Map<string, Batch>();
  for (const w of layout.walls) {
    const inscribed = tileNoise(seed ^ 0x1d5, w.c, w.r) < inscribedShare ? 1 : 0;
    const key = `${w.height.toFixed(2)}:${w.cut ? 1 : 0}:${inscribed}`;
    let b = wallBatches.get(key);
    if (!b) {
      const gkey = `${w.height.toFixed(2)}:${w.cut ? 1 : 0}`;
      const geo = kit.geo(`wall:${gkey}`, () => chamferBox(1, w.height + TILE_THICK, 1, w.cut ? 0.05 : 0.06, -TILE_THICK));
      b = batch(new Batch(`wall:${key}`, geo, [wallSides[inscribed], w.cut ? wallCutTop! : wallTop!], true, true));
      wallBatches.set(key, b);
    }
    // Quarter-turn variety on the masonry; the hull is symmetric so the footprint is unchanged.
    const rot = (Math.floor(w.shade * 4) * Math.PI) / 2;
    b.add(xform(w.c + 0.5, 0, w.r + 0.5, rot), grey(0.9 + 0.14 * w.shade));
  }

  // ───────────── cliff skirt ─────────────
  const cliffTex = kit.texture(cliffTexture(seed));
  cliffTex.repeat.set(1, 1);
  const cliffMat = kit.toon(0xffffff, { map: cliffTex, vertexColors: true });
  const top = new THREE.Color(pal.cliff);
  const deep = new THREE.Color(pal.cliffDeep);
  const tmp = new THREE.Color();
  const cliffBatches = new Map<string, Batch>();
  for (const cl of layout.cliffs) {
    const shape = Math.floor(cl.shade * 3) % 3;
    const key = `${cl.depth.toFixed(2)}:${shape}`;
    let b = cliffBatches.get(key);
    if (!b) {
      const depth = cl.depth;
      const geo = kit.geo(`cliff:${key}`, () =>
        cliffColumn(-TILE_THICK, depth, seed + shape * 131 + Math.round(depth * 100), (y) => {
          // Fade into the background with depth so the diorama floats (no fog needed).
          const t = Math.min(1, Math.max(0, (-TILE_THICK - y) / depth));
          tmp.copy(top).lerp(deep, Math.pow(t, 1.15));
          return [tmp.r, tmp.g, tmp.b];
        }),
      );
      b = batch(new Batch(`cliff:${key}`, geo, cliffMat, false, true));
      cliffBatches.set(key, b);
    }
    b.add(xform(cl.c + 0.5, 0, cl.r + 0.5, (Math.floor(tileNoise(seed ^ 0xc1, cl.c, cl.r) * 4) * Math.PI) / 2), grey(0.92 + 0.12 * cl.shade));
  }

  // ───────────── edge trim and hazard bands ─────────────
  const lipColor = pal.floorFinish === 'stone' ? scaleColor(pal.wallTop, 0.92) : pal.metal;
  const lip = batch(new Batch('edge:lip', kit.geo('lip', () => new THREE.BoxGeometry(1, 0.08, 0.08)), kit.toon(lipColor), false, true));
  const hazTex = kit.texture(hazardTexture(pal, seed));
  hazTex.repeat.set(2, 1);
  const hazard = batch(new Batch('edge:hazard', kit.geo('hazPlane', () => new THREE.PlaneGeometry(1, 0.3)), kit.toon(0xffffff, { map: hazTex }), false, true));
  const hazardShare = pal.floorFinish === 'stone' ? 0.4 : 0.6;
  for (const e of layout.edges) {
    const { c, r, side } = e;
    if (e.wall) {
      // Walls rise straight from the skirt; no floor lip.
    } else if (side === 'e') lip.add(xform(c + 1, 0, r + 0.5, Math.PI / 2));
    else if (side === 'w') lip.add(xform(c, 0, r + 0.5, Math.PI / 2));
    else if (side === 's') lip.add(xform(c + 0.5, 0, r + 1));
    else lip.add(xform(c + 0.5, 0, r));
    // Hazard paint comes in runs of three tiles so it reads as deliberate striping, not noise.
    const run = side === 'e' ? Math.floor(r / 3) * 31 + c : Math.floor(c / 3) * 17 + r * 3;
    if ((side === 'e' || side === 's') && tileNoise(seed ^ 0x4a7, run, side === 'e' ? 1 : 2) < hazardShare) {
      if (side === 'e') hazard.add(xform(c + 1.006, -0.5, r + 0.5, Math.PI / 2));
      else hazard.add(xform(c + 0.5, -0.5, r + 1.006));
    }
  }

  // ───────────── barriers ─────────────
  if (layout.barriers.length > 0) {
    const bTex = kit.texture(hazardTexture(pal, seed ^ 0x99));
    bTex.repeat.set(1, 3);
    const bSide = kit.toon(0xffffff, { map: bTex });
    const bTop = kit.toon(pal.floorFinish === 'stone' ? pal.wallTop : pal.metal);
    const baseH = 0.34;
    const base = batch(new Batch('barrier:base', kit.geo('barrierBase', () => chamferBox(0.8, baseH, 0.8, 0.05)), [bSide, bTop]));
    const link = batch(new Batch('barrier:link', kit.geo('barrierLink', () => chamferBox(0.3, baseH * 0.9, 0.56, 0.03)), [bSide, bTop]));
    const railMat = kit.toon(pal.floorFinish === 'metal' ? scaleColor(pal.hazard, 0.9) : pal.hazard);
    const post = batch(new Batch('barrier:post', kit.geo('barrierPost', () => new THREE.CylinderGeometry(0.045, 0.045, BARRIER_HEIGHT - baseH + 0.04, 8)), railMat));
    const rail = batch(new Batch('barrier:rail', kit.geo('barrierRail', () => new THREE.CylinderGeometry(0.035, 0.035, 0.5, 8).rotateZ(Math.PI / 2)), railMat));
    const railY = BARRIER_HEIGHT;
    const postY = baseH + (BARRIER_HEIGHT - baseH) / 2;
    for (const b of layout.barriers) {
      const x = b.c + 0.5;
      const z = b.r + 0.5;
      base.add(xform(x, 0, z));
      post.add(xform(x, postY, z));
      const any = b.n || b.e || b.s || b.w;
      if (b.e || !any) rail.add(xform(x + 0.25, railY, z));
      if (b.w || !any) rail.add(xform(x - 0.25, railY, z));
      if (b.s) rail.add(xform(x, railY, z + 0.25, Math.PI / 2));
      if (b.n) rail.add(xform(x, railY, z - 0.25, Math.PI / 2));
      if (b.e && layout.at(b.c + 1, b.r) === '=') link.add(xform(x + 0.5, 0, z, Math.PI / 2));
      if (b.s && layout.at(b.c, b.r + 1) === '=') link.add(xform(x, 0, z + 0.5));
    }
  }

  // ───────────── contact shadows ─────────────
  const blobTex = kit.texture(blobTexture());
  const blobMat = kit.glow(pal.ink, { intensity: 1, opacity: 0.42, map: blobTex, depthWrite: false });
  blobMat.blending = THREE.NormalBlending;
  blobMat.transparent = true;
  blobMat.polygonOffset = true;
  blobMat.polygonOffsetFactor = -1;
  blobMat.polygonOffsetUnits = -1;
  const blobs = batch(new Batch('blob', kit.geo('blobPlane', () => new THREE.PlaneGeometry(1, 1).rotateX(-Math.PI / 2)), blobMat, false, false));
  const blob = (x: number, y: number, radius: number, strength = 1): void => {
    const s = radius * 2 * (0.8 + 0.2 * strength);
    blobs.add(xform(x, 0.006, y, 0, s, 1, s));
  };

  // ───────────── decor entities ─────────────
  const decorCtx: DecorCtx = { kit, pal, layout, seed, reactive, animate: animators, practicals, blob };
  for (const e of level.entities) {
    if (e.kind !== 'decor') continue;
    const obj = buildDecor(e as DecorDef, decorCtx);
    if (obj) group.add(obj);
  }

  // ───────────── ambient scatter ─────────────
  const scatter = planScatter(level, layout);
  const rng = new Rng(seed ^ 0xab5);
  const tuftMat = kit.toon(pal.foliage, { side: THREE.DoubleSide });
  const tufts = [0, 1, 2].map((i) => batch(new Batch(`tuft${i}`, kit.geo(`tuft${i}:0.32`, () => tuftGeometry(i, 0.32)), tuftMat, false, true)));
  const pebbleMat = kit.toon(pal.floorFinish === 'stone' ? pal.stone : pal.metal);
  const pebbles = [0, 1].map((i) => batch(new Batch(`pebble${i}`, kit.geo(`pebble${i}`, () => rockGeometry(i * 53 + 1, 0.12)), pebbleMat, false, true)));
  const stainMat = kit.glow(pal.floorFinish === 'stone' ? pal.grout : pal.rust, { intensity: 1, opacity: 0.22, map: blobTex, depthWrite: false });
  stainMat.polygonOffset = true;
  stainMat.polygonOffsetFactor = -1;
  stainMat.polygonOffsetUnits = -1;
  const stains = batch(new Batch('stain', kit.geo('blobPlane', () => new THREE.PlaneGeometry(1, 1).rotateX(-Math.PI / 2)), stainMat, false, false));
  const paintTex = kit.texture(hazardTexture(pal, seed ^ 0x9a1));
  const paintMat = kit.toon(0xffffff, { map: paintTex, decal: true, transparent: true, opacity: 0.85 });
  const paints = batch(new Batch('floorPaint', kit.geo('paintPlane', () => new THREE.PlaneGeometry(0.96, 0.24).rotateX(-Math.PI / 2)), paintMat, false, true));
  const vineTex = kit.texture(vineTexture(pal, seed));
  const vineMat = kit.toon(0xffffff, { map: vineTex, transparent: true, alphaTest: 0.35, side: THREE.DoubleSide, depthWrite: true });
  const vinesB = batch(new Batch('vine', kit.geo('vplane', () => new THREE.PlaneGeometry(1, 1)), vineMat, false, false));
  const pipeColor = pal.floorFinish === 'stone' ? pal.hazard : pal.floorFinish === 'mixed' ? pal.rust : pal.metal;
  const pipesB = batch(new Batch('wallPipe', kit.geo('wallPipe', () => new THREE.CylinderGeometry(0.06, 0.06, 1, 8).rotateZ(Math.PI / 2)), kit.toon(pipeColor), true, true));
  const bracketB = batch(new Batch('wallBracket', kit.geo('wallBracket', () => new THREE.BoxGeometry(0.08, 0.16, 0.12)), kit.toon(pal.trim), false, true));
  const neonColors = [pal.neonA, pal.neonB, pal.neonC];
  const neonB = neonColors.map((col, i) => {
    const mat = kit.glow(col, { intensity: 2.8 });
    registerReactive(reactive, reactiveGlow('neon', mat));
    return batch(new Batch(`wallNeon${i}`, kit.geo('wallNeon', () => new THREE.BoxGeometry(0.07, 0.62, 0.05)), mat, false, false));
  });
  const neonCap = batch(new Batch('wallNeonCap', kit.geo('wallNeonCap', () => new THREE.BoxGeometry(0.12, 0.07, 0.08)), kit.toon(pal.metal), false, true));
  const ventBody = batch(new Batch('wallVent', kit.geo('wallVent', () => chamferBox(0.46, 0.32, 0.06, 0.015, -0.16)), kit.toon(scaleColor(pal.metal, 0.95)), false, true));
  const ventSlat = batch(new Batch('wallVentSlat', kit.geo('wallVentSlat', () => new THREE.BoxGeometry(0.38, 0.03, 0.02)), kit.toon(scaleColor(pal.grout, 0.7)), false, false));
  const sagCurve = new THREE.QuadraticBezierCurve3(new THREE.Vector3(-0.5, 0, 0), new THREE.Vector3(0, -0.5, 0), new THREE.Vector3(0.5, 0, 0));
  const cableB = batch(new Batch('wallCable', kit.geo('wallCable', () => new THREE.TubeGeometry(sagCurve, 12, 0.025, 5, false)), kit.toon(pal.floorFinish === 'stone' ? 0x2e2a28 : 0x18141e), false, false));
  const leafMat = kit.toon(pal.foliage);
  const leafB = [0, 1].map((i) => batch(new Batch(`topLeaf${i}`, kit.geo(`leaf${i + 3}`, () => leafClump(i + 3, 0.5)), leafMat, true, true)));
  const rubbleMat = kit.toon(pal.floorFinish === 'stone' ? scaleColor(pal.wallTop, 0.95) : pal.metal);
  const rubbleB = [0, 1, 2].map((i) => batch(new Batch(`topRubble${i}`, kit.geo(`rock${i}`, () => rockGeometry(i * 977 + 3, 0.34)), rubbleMat, true, true)));
  const cliffRockMat = kit.toon(mixColor(pal.cliff, pal.stone, 0.4));

  for (const it of scatter) {
    const c = Math.floor(it.x);
    const r = Math.floor(it.y);
    const h = layout.wallHeight(c, r);
    switch (it.kind) {
      case 'tuft':
        tufts[Math.floor(it.v * 3) % 3].add(xform(it.x, 0, it.y, it.v * 6, it.s, it.s, it.s), grey(0.85 + it.v * 0.3));
        break;
      case 'pebbles':
        for (let i = 0; i < 3; i++) {
          const a = it.v * 10 + i * 2.1;
          pebbles[i & 1].add(xform(it.x + Math.cos(a) * 0.12, 0, it.y + Math.sin(a) * 0.12, a, it.s, it.s, it.s), grey(0.85 + 0.1 * i));
        }
        break;
      case 'stain':
        stains.add(xform(it.x, 0.004, it.y, it.v * 3, 0.5 + it.s * 0.5, 1, 0.4 + it.s * 0.4));
        break;
      case 'floorPaint': {
        const off = (it.v - 0.5) * 0.5;
        const alongX = it.v < 0.5;
        paints.add(xform(it.x + (alongX ? 0 : off), 0.003, it.y + (alongX ? off : 0), alongX ? 0 : Math.PI / 2, 1, 1, it.s));
        break;
      }
      case 'wallVine': {
        const len = Math.max(0.5, h * (0.45 + 0.5 * it.s));
        mountOnFace(dummy, c, r, it.face!, h - len / 2, (it.v - 0.5) * 0.5, 0.018);
        dummy.scale.set(0.45, len, 1);
        dummy.updateMatrix();
        vinesB.add(dummy.matrix);
        mountOnFace(dummy, c, r, it.face!, h - 0.05, (it.v - 0.5) * 0.5, -0.1);
        dummy.scale.setScalar(0.7);
        dummy.updateMatrix();
        leafB[0].add(dummy.matrix);
        break;
      }
      case 'wallPipe': {
        const y = 0.25 + it.v * Math.max(0.1, h - 0.6);
        mountOnFace(dummy, c, r, it.face!, y, 0, 0.07);
        dummy.scale.set(1, 1, 1);
        dummy.updateMatrix();
        pipesB.add(dummy.matrix);
        mountOnFace(dummy, c, r, it.face!, y, 0, 0.04);
        dummy.updateMatrix();
        bracketB.add(dummy.matrix);
        break;
      }
      case 'wallNeon': {
        const y = Math.min(h - 0.4, 0.5 + it.s * 0.3);
        mountOnFace(dummy, c, r, it.face!, y, (it.v - 0.5) * 0.4, 0.04);
        dummy.scale.set(1, 1, 1);
        dummy.updateMatrix();
        neonB[Math.floor(it.v * 3) % 3].add(dummy.matrix);
        for (const dy of [-0.33, 0.33]) {
          mountOnFace(dummy, c, r, it.face!, y + dy, (it.v - 0.5) * 0.4, 0.04);
          dummy.updateMatrix();
          neonCap.add(dummy.matrix);
        }
        break;
      }
      case 'wallVent': {
        const y = Math.min(h - 0.3, 0.55 + it.v * 0.3);
        mountOnFace(dummy, c, r, it.face!, y, (it.v - 0.5) * 0.3, 0.01);
        dummy.scale.set(it.s, it.s, 1);
        dummy.updateMatrix();
        ventBody.add(dummy.matrix);
        for (let i = 0; i < 4; i++) {
          mountOnFace(dummy, c, r, it.face!, y - 0.1 + i * 0.065, (it.v - 0.5) * 0.3, 0.075);
          dummy.scale.set(it.s, 1, 1);
          dummy.updateMatrix();
          ventSlat.add(dummy.matrix);
        }
        break;
      }
      case 'wallCable': {
        const y = Math.max(0.5, h - 0.25);
        mountOnFace(dummy, c, r, it.face!, y, 0, 0.04);
        dummy.scale.set(1, 0.4 + it.s * 0.6, 1);
        dummy.updateMatrix();
        cableB.add(dummy.matrix);
        break;
      }
      case 'topGrass':
        leafB[Math.floor(it.v * 2) % 2].add(xform(it.x + (it.v - 0.5) * 0.4, h, it.y + (it.s - 0.8) * 0.4, it.v * 6, it.s, it.s * 0.7, it.s));
        break;
      case 'topRubble':
        rubbleB[Math.floor(it.v * 3) % 3].add(xform(it.x + (it.v - 0.5) * 0.4, h, it.y - (it.v - 0.5) * 0.3, it.v * 6, it.s * 1.2, it.s, it.s * 1.2), grey(0.9 + 0.15 * it.s));
        break;
      case 'cliffRoot': {
        const len = 0.5 + it.s * 0.9;
        mountOnFace(dummy, c, r, it.face!, -TILE_THICK - len / 2 + 0.05, (it.v - 0.5) * 0.6, 0.02);
        dummy.scale.set(0.4, len, 1);
        dummy.updateMatrix();
        vinesB.add(dummy.matrix);
        break;
      }
      case 'cliffRock': {
        const s = rng.int(0, 2);
        const rock = new THREE.Mesh(kit.geo(`rock${s}`, () => rockGeometry(s * 977 + 3, 0.34)), cliffRockMat);
        mountOnFace(rock, c, r, it.face!, -0.55 - it.v * 0.5, (it.v - 0.5) * 0.6, -0.05);
        rock.scale.setScalar(0.8 + it.s * 0.6);
        rock.rotation.y += it.v * 5;
        group.add(rock);
        break;
      }
    }
  }

  // ───────────── emit instanced meshes ─────────────
  const stats: Record<string, number> = {};
  for (const b of batches) {
    const mesh = b.build();
    if (!mesh) continue;
    group.add(mesh);
    const k = b.name.split(':')[0];
    stats[k] = (stats[k] ?? 0) + b.count;
  }

  // ───────────── ambient motes ─────────────
  const b = layout.bounds;
  const area = (b.maxX - b.minX) * (b.maxZ - b.minZ);
  const moteCount = Math.min(260, Math.round(area * 0.45 * pal.moteDensity));
  if (moteCount > 0) {
    const pos = new Float32Array(moteCount * 3);
    const speed = new Float32Array(moteCount);
    const mrng = new Rng(seed ^ 0x307e);
    for (let i = 0; i < moteCount; i++) {
      pos[i * 3] = mrng.range(b.minX, b.maxX);
      pos[i * 3 + 1] = mrng.range(0.1, 3);
      pos[i * 3 + 2] = mrng.range(b.minZ, b.maxZ);
      speed[i] = mrng.range(0.05, 0.22);
    }
    const geo = kit.bag.track(new THREE.BufferGeometry());
    const attr = new THREE.BufferAttribute(pos, 3);
    attr.setUsage(THREE.DynamicDrawUsage);
    geo.setAttribute('position', attr);
    geo.boundingSphere = new THREE.Sphere(new THREE.Vector3((b.minX + b.maxX) / 2, 1.5, (b.minZ + b.maxZ) / 2), Math.hypot(b.maxX - b.minX, b.maxZ - b.minZ));
    const mat = kit.bag.track(
      new THREE.PointsMaterial({
        color: new THREE.Color(pal.mote).multiplyScalar(1.4),
        size: 4,
        sizeAttenuation: false,
        map: blobTex,
        transparent: true,
        opacity: 0.55,
        blending: THREE.AdditiveBlending,
        depthWrite: false,
      }),
    );
    const points = new THREE.Points(geo, mat);
    points.name = 'motes';
    points.frustumCulled = false;
    group.add(points);
    animators.push((t, dt) => {
      for (let i = 0; i < moteCount; i++) {
        let y = pos[i * 3 + 1] + speed[i] * dt;
        if (y > 3.2) y = 0.1;
        pos[i * 3 + 1] = y;
        pos[i * 3] += Math.sin(t * 0.6 + i) * 0.002;
      }
      attr.needsUpdate = true;
    });
  }

  const surfaceHeight = (x: number, y: number): number => {
    const c = Math.floor(x);
    const r = Math.floor(y);
    const ch = layout.at(c, r);
    if (ch === '#') return layout.wallHeight(c, r);
    if (ch === '=') return BARRIER_HEIGHT;
    return 0;
  };

  return {
    group,
    layout,
    reactive,
    practicals,
    stats,
    surfaceHeight,
    update(time: number, dt: number) {
      for (const a of animators) a(time, dt);
    },
  };
}
