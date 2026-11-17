/**
 * Procedural faceted geometry for the environment kit: chamfered blocks (walls, crates, plinths),
 * tapered cliff columns and rocks. Built as convex hulls so every face is flat — flat faces are
 * what make the toon ramp read as graphic, hand-painted planes (ART-02).
 *
 * UVs are planar projections in local units (1 unit = 1 texture repeat), so a texture painted for
 * one tile lines up across neighbouring blocks.
 */
import * as THREE from 'three';
import { ConvexHull } from 'three/examples/jsm/math/ConvexHull.js';
import { Rng } from './rng';

export interface HullOptions {
  /** Split triangles into group 0 (sides / underside) and group 1 (upward-facing). Default true. */
  topGroup?: boolean;
  /** Per-vertex colour; enables a `color` attribute. */
  color?: (x: number, y: number, z: number) => [number, number, number];
  /** Texture repeats per unit. */
  uvScale?: number;
}

/** Flat-shaded hull of a point cloud with planar UVs and optional top / side material groups. */
export function hullGeometry(points: THREE.Vector3[], opts: HullOptions = {}): THREE.BufferGeometry {
  const hull = new ConvexHull().setFromPoints(points);
  const uvScale = opts.uvScale ?? 1;
  const tris: { p: number[]; n: THREE.Vector3; top: boolean }[] = [];
  for (const face of hull.faces) {
    const pts: number[] = [];
    let edge = face.edge;
    do {
      const p = edge.head().point;
      pts.push(p.x, p.y, p.z);
      edge = edge.next;
    } while (edge !== face.edge);
    // Faces are triangles in three's ConvexHull, but fan-triangulate defensively.
    for (let i = 1; i + 1 < pts.length / 3; i++) {
      tris.push({
        p: [pts[0], pts[1], pts[2], pts[i * 3], pts[i * 3 + 1], pts[i * 3 + 2], pts[i * 3 + 3], pts[i * 3 + 4], pts[i * 3 + 5]],
        n: face.normal.clone(),
        top: face.normal.y > 0.5,
      });
    }
  }
  const split = opts.topGroup ?? true;
  if (split) tris.sort((a, b) => Number(a.top) - Number(b.top));

  const pos: number[] = [];
  const nor: number[] = [];
  const uv: number[] = [];
  const col: number[] = [];
  let sideCount = 0;
  for (const t of tris) {
    if (!t.top) sideCount++;
    const ax = Math.abs(t.n.x);
    const ay = Math.abs(t.n.y);
    const az = Math.abs(t.n.z);
    for (let k = 0; k < 3; k++) {
      const x = t.p[k * 3];
      const y = t.p[k * 3 + 1];
      const z = t.p[k * 3 + 2];
      pos.push(x, y, z);
      nor.push(t.n.x, t.n.y, t.n.z);
      if (ay >= ax && ay >= az) uv.push(x * uvScale, -z * uvScale);
      else if (ax >= az) uv.push((t.n.x > 0 ? -z : z) * uvScale, y * uvScale);
      else uv.push((t.n.z > 0 ? x : -x) * uvScale, y * uvScale);
      if (opts.color) col.push(...opts.color(x, y, z));
    }
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('normal', new THREE.Float32BufferAttribute(nor, 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  if (opts.color) g.setAttribute('color', new THREE.Float32BufferAttribute(col, 3));
  if (split) {
    g.addGroup(0, sideCount * 3, 0);
    g.addGroup(sideCount * 3, (tris.length - sideCount) * 3, 1);
  }
  g.computeBoundingBox();
  g.computeBoundingSphere();
  return g;
}

/** Chamfered box, centred on X/Z, spanning Y in [y0, y0 + h]. */
export function chamferBox(w: number, h: number, d: number, bevel: number, y0 = 0, opts: HullOptions = {}): THREE.BufferGeometry {
  const b = Math.min(bevel, w / 2 - 1e-3, h / 2 - 1e-3, d / 2 - 1e-3);
  const hw = w / 2;
  const hd = d / 2;
  const pts: THREE.Vector3[] = [];
  for (const sx of [-1, 1]) {
    for (const sy of [0, 1]) {
      for (const sz of [-1, 1]) {
        const y = y0 + sy * h;
        const yi = sy ? y - b : y + b;
        pts.push(new THREE.Vector3(sx * hw, yi, sz * (hd - b)));
        pts.push(new THREE.Vector3(sx * (hw - b), y, sz * (hd - b)));
        pts.push(new THREE.Vector3(sx * (hw - b), yi, sz * hd));
      }
    }
  }
  return hullGeometry(pts, opts);
}

/**
 * Cliff column under an edge tile: full-width top (so neighbours meet without gaps) narrowing to
 * a chunky irregular point, so the level hangs like a floating diorama.
 */
export function cliffColumn(top: number, depth: number, seed: number, color: (y: number) => [number, number, number]): THREE.BufferGeometry {
  const rng = new Rng(seed);
  const pts: THREE.Vector3[] = [];
  const h = 0.5;
  for (const [x, z] of [
    [-h, -h],
    [h, -h],
    [h, h],
    [-h, h],
  ]) {
    pts.push(new THREE.Vector3(x, top, z));
    pts.push(new THREE.Vector3(x, top - depth * 0.35, z));
  }
  // Step in twice so the silhouette reads as stacked rock rather than a smooth cone.
  const mid = top - depth * rng.range(0.55, 0.7);
  const insetA = rng.range(0.05, 0.14);
  for (const [x, z] of [
    [-h, -h],
    [h, -h],
    [h, h],
    [-h, h],
  ]) {
    pts.push(new THREE.Vector3(x * (1 - insetA * 2) + rng.range(-0.04, 0.04), mid, z * (1 - insetA * 2) + rng.range(-0.04, 0.04)));
  }
  const bottom = top - depth;
  const bx = rng.range(-0.12, 0.12);
  const bz = rng.range(-0.12, 0.12);
  const r = rng.range(0.12, 0.22);
  for (let i = 0; i < 5; i++) {
    const a = (i / 5) * Math.PI * 2 + rng.range(-0.3, 0.3);
    pts.push(new THREE.Vector3(bx + Math.cos(a) * r, bottom + rng.range(0, 0.15), bz + Math.sin(a) * r));
  }
  return hullGeometry(pts, { topGroup: false, color: (_x, y) => color(y) });
}

/** Irregular rock / rubble chunk roughly `size` across, resting on Y = 0. */
export function rockGeometry(seed: number, size: number, flatness = 0.65): THREE.BufferGeometry {
  const rng = new Rng(seed);
  const pts: THREE.Vector3[] = [];
  const n = 11;
  for (let i = 0; i < n; i++) {
    const u = rng.next() * Math.PI * 2;
    const v = Math.acos(rng.range(-1, 1));
    const rr = size * 0.5 * rng.range(0.7, 1);
    pts.push(new THREE.Vector3(Math.sin(v) * Math.cos(u) * rr, (Math.cos(v) * 0.5 + 0.5) * rr * flatness * 2, Math.sin(v) * Math.sin(u) * rr));
  }
  // Guarantee a flat-ish base so rocks sit on the floor.
  for (let i = 0; i < 3; i++) {
    const a = (i / 3) * Math.PI * 2;
    pts.push(new THREE.Vector3(Math.cos(a) * size * 0.4, 0, Math.sin(a) * size * 0.4));
  }
  return hullGeometry(pts, { topGroup: false });
}

/** Low-poly leaf clump (flattened, jittered icosahedron). */
export function leafClump(seed: number, size: number): THREE.BufferGeometry {
  const rng = new Rng(seed);
  const pts: THREE.Vector3[] = [];
  for (let i = 0; i < 14; i++) {
    const u = rng.next() * Math.PI * 2;
    const v = Math.acos(rng.range(-0.2, 1));
    const rr = size * 0.5 * rng.range(0.75, 1.05);
    pts.push(new THREE.Vector3(Math.sin(v) * Math.cos(u) * rr, Math.cos(v) * rr * 0.9 + size * 0.1, Math.sin(v) * Math.sin(u) * rr));
  }
  pts.push(new THREE.Vector3(0, 0, 0));
  return hullGeometry(pts, { topGroup: false });
}

/** Grass tuft: a few thin blades fanned out (open geometry, render double-sided). */
export function tuftGeometry(seed: number, size: number): THREE.BufferGeometry {
  const rng = new Rng(seed);
  const pos: number[] = [];
  const nor: number[] = [];
  const blades = 6;
  for (let i = 0; i < blades; i++) {
    const a = (i / blades) * Math.PI * 2 + rng.range(-0.3, 0.3);
    const h = size * rng.range(0.6, 1);
    const lean = rng.range(0.15, 0.4) * size;
    const w = size * 0.09;
    const dx = Math.cos(a);
    const dz = Math.sin(a);
    const px = -dz * w;
    const pz = dx * w;
    pos.push(-px, 0, -pz, px, 0, pz, dx * lean, h, dz * lean);
    nor.push(dx * 0.3, 0.9, dz * 0.3, dx * 0.3, 0.9, dz * 0.3, dx * 0.3, 0.9, dz * 0.3);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('normal', new THREE.Float32BufferAttribute(nor, 3));
  g.computeBoundingSphere();
  return g;
}
