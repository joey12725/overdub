/**
 * Procedural mesh assembly. A "part" is many primitives (boxes, lathes, extrusions) baked into one
 * BufferGeometry with per-vertex colour, glow and accent flags, so a whole rig segment is a single
 * draw call for the fill and one for the ink hull. Built once per level; never in the frame loop.
 */
import * as THREE from 'three';

export interface PrimOpts {
  pos?: [number, number, number];
  /** Euler XYZ in radians. */
  rot?: [number, number, number];
  scale?: [number, number, number];
  /** 1 = emissive/unlit. */
  glow?: number;
  /** 1 = recoloured by the instance accent colour. */
  accent?: number;
}

const tmpColor = new THREE.Color();
const tmpMat = new THREE.Matrix4();
const tmpQuat = new THREE.Quaternion();
const tmpEuler = new THREE.Euler();
const tmpPos = new THREE.Vector3();
const tmpScale = new THREE.Vector3();

export class PartBuilder {
  private readonly pieces: THREE.BufferGeometry[] = [];

  add(geo: THREE.BufferGeometry, color: number, o: PrimOpts = {}): this {
    let g = geo.index ? geo.toNonIndexed() : geo.clone();
    geo.dispose();
    g.deleteAttribute('uv');
    if (!g.getAttribute('normal')) g.computeVertexNormals();
    tmpPos.set(...(o.pos ?? [0, 0, 0]));
    tmpEuler.set(...(o.rot ?? [0, 0, 0]));
    tmpQuat.setFromEuler(tmpEuler);
    tmpScale.set(...(o.scale ?? [1, 1, 1]));
    tmpMat.compose(tmpPos, tmpQuat, tmpScale);
    g.applyMatrix4(tmpMat);
    const n = g.getAttribute('position').count;
    tmpColor.setHex(color);
    const col = new Float32Array(n * 3);
    const glow = new Float32Array(n);
    const acc = new Float32Array(n);
    for (let i = 0; i < n; i++) {
      col[i * 3] = tmpColor.r;
      col[i * 3 + 1] = tmpColor.g;
      col[i * 3 + 2] = tmpColor.b;
      glow[i] = o.glow ?? 0;
      acc[i] = o.accent ?? 0;
    }
    g.setAttribute('color', new THREE.BufferAttribute(col, 3));
    g.setAttribute('glow', new THREE.BufferAttribute(glow, 1));
    g.setAttribute('accent', new THREE.BufferAttribute(acc, 1));
    for (const name of Object.keys(g.attributes)) {
      if (!['position', 'normal', 'color', 'glow', 'accent'].includes(name)) g.deleteAttribute(name);
    }
    g = g.index ? g.toNonIndexed() : g;
    this.pieces.push(g);
    return this;
  }

  get empty(): boolean {
    return this.pieces.length === 0;
  }

  /** Merge everything into one geometry with a smoothed `oNormal` for crack-free outlines. */
  build(): THREE.BufferGeometry {
    const names = ['position', 'normal', 'color', 'glow', 'accent'] as const;
    const sizes = { position: 3, normal: 3, color: 3, glow: 1, accent: 1 };
    let total = 0;
    for (const p of this.pieces) total += p.getAttribute('position').count;
    const out = new THREE.BufferGeometry();
    const arrays: Record<string, Float32Array> = {};
    for (const nm of names) arrays[nm] = new Float32Array(total * sizes[nm]);
    let off = 0;
    for (const p of this.pieces) {
      const cnt = p.getAttribute('position').count;
      for (const nm of names) {
        const src = p.getAttribute(nm).array as Float32Array;
        arrays[nm].set(src.subarray(0, cnt * sizes[nm]), off * sizes[nm]);
      }
      off += cnt;
      p.dispose();
    }
    this.pieces.length = 0;
    for (const nm of names) out.setAttribute(nm, new THREE.BufferAttribute(arrays[nm], sizes[nm]));
    out.setAttribute('oNormal', new THREE.BufferAttribute(smoothNormals(arrays.position, arrays.normal), 3));
    out.computeBoundingSphere();
    out.computeBoundingBox();
    return out;
  }
}

/** Average normals of coincident vertices so the extruded hull stays closed at hard edges. */
export function smoothNormals(pos: Float32Array, nrm: Float32Array): Float32Array {
  const n = pos.length / 3;
  const acc = new Map<string, [number, number, number]>();
  const keys: string[] = new Array(n);
  const q = (v: number) => Math.round(v * 2000);
  for (let i = 0; i < n; i++) {
    const k = `${q(pos[i * 3])},${q(pos[i * 3 + 1])},${q(pos[i * 3 + 2])}`;
    keys[i] = k;
    let a = acc.get(k);
    if (!a) {
      a = [0, 0, 0];
      acc.set(k, a);
    }
    a[0] += nrm[i * 3];
    a[1] += nrm[i * 3 + 1];
    a[2] += nrm[i * 3 + 2];
  }
  const out = new Float32Array(n * 3);
  for (let i = 0; i < n; i++) {
    const a = acc.get(keys[i])!;
    const l = Math.hypot(a[0], a[1], a[2]) || 1;
    out[i * 3] = a[0] / l;
    out[i * 3 + 1] = a[1] / l;
    out[i * 3 + 2] = a[2] / l;
  }
  return out;
}

// ───────────── primitive shorthands (all centred at the origin unless noted) ─────────────

export const box = (w: number, h: number, d: number) => new THREE.BoxGeometry(w, h, d);
export const sphere = (r: number, ws = 12, hs = 8) => new THREE.SphereGeometry(r, ws, hs);
export const cyl = (rt: number, rb: number, h: number, seg = 10, open = false) =>
  new THREE.CylinderGeometry(rt, rb, h, seg, 1, open);
export const cone = (r: number, h: number, seg = 6) => new THREE.ConeGeometry(r, h, seg);
export const torus = (R: number, r: number, rs = 6, ts = 16, arc = Math.PI * 2) =>
  new THREE.TorusGeometry(R, r, rs, ts, arc);
export const capsule = (r: number, len: number, cap = 4, rad = 8) => new THREE.CapsuleGeometry(r, len, cap, rad);
export const ico = (r: number, detail = 0) => new THREE.IcosahedronGeometry(r, detail);
export const octa = (r: number) => new THREE.OctahedronGeometry(r, 0);
export const dodeca = (r: number) => new THREE.DodecahedronGeometry(r, 0);

/** Lathe from (radius, y) pairs, bottom to top. */
export function lathe(profile: [number, number][], seg = 12): THREE.BufferGeometry {
  return new THREE.LatheGeometry(
    profile.map(([r, y]) => new THREE.Vector2(r, y)),
    seg,
  );
}

/** Extrude a 2D polygon (x, y) by `depth` along +Z, centred on z = 0. */
export function extrudePoly(points: [number, number][], depth: number, bevel = 0): THREE.BufferGeometry {
  const shape = new THREE.Shape(points.map(([x, y]) => new THREE.Vector2(x, y)));
  const g = new THREE.ExtrudeGeometry(shape, {
    depth,
    bevelEnabled: bevel > 0,
    bevelThickness: bevel,
    bevelSize: bevel,
    bevelSegments: 1,
    steps: 1,
  });
  g.translate(0, 0, -depth / 2);
  return g;
}

/** A tube through 3D points (cables, straps, hair strands). */
export function tube(points: [number, number, number][], r: number, seg = 12, radial = 5): THREE.BufferGeometry {
  const curve = new THREE.CatmullRomCurve3(points.map(([x, y, z]) => new THREE.Vector3(x, y, z)));
  return new THREE.TubeGeometry(curve, seg, r, radial, false);
}

/** Flat ring sector in the XZ plane (y up), angles measured from +Z toward +X. */
export function ringSector(inner: number, outer: number, start: number, length: number, seg = 24): THREE.BufferGeometry {
  const g = new THREE.RingGeometry(inner, outer, seg, 1, start, length);
  g.rotateX(-Math.PI / 2);
  return g;
}
