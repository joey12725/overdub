/**
 * Flat ground/overlay shapes: strips (lines with UVs along their length) and sectors (cones/discs).
 * Geometries are unit-sized and positioned by transform so they can be reused from pools.
 */
import * as THREE from 'three';

/** A 1×1 strip in the XZ plane, running from x = 0 to x = 1, centred on z = 0. uv.x runs along it. */
export function unitStripGeometry(): THREE.BufferGeometry {
  const g = new THREE.PlaneGeometry(1, 1, 1, 1);
  g.rotateX(-Math.PI / 2);
  g.translate(0.5, 0, 0);
  return g;
}

/**
 * Place a unit strip between two sim points (x, y) at scene height `h`, with the given width.
 * Uses rotation.y so the strip stays flat on the floor.
 */
export function placeStrip(mesh: THREE.Object3D, x0: number, y0: number, x1: number, y1: number, width: number, h: number): number {
  const dx = x1 - x0;
  const dz = y1 - y0;
  const len = Math.max(1e-4, Math.hypot(dx, dz));
  mesh.position.set(x0, h, y0);
  mesh.rotation.set(0, -Math.atan2(dz, dx), 0);
  mesh.scale.set(len, 1, width);
  return len;
}

/**
 * Sector in the XZ plane centred on +Z (model forward), angles measured from +Z toward +X.
 * `radialUv`: uv.x = radius fraction (0 inner → 1 outer), uv.y = angle fraction. Otherwise swapped
 * (uv.x = angle fraction, uv.y = radius fraction) — used by sweeps.
 */
export function sectorGeometry(inner: number, outer: number, arc: number, segs: number, radialUv: boolean): THREE.BufferGeometry {
  const n = Math.max(2, segs);
  const pos: number[] = [];
  const uv: number[] = [];
  const idx: number[] = [];
  for (let i = 0; i <= n; i++) {
    const f = i / n;
    const a = -arc / 2 + arc * f;
    const s = Math.sin(a);
    const c = Math.cos(a);
    pos.push(s * inner, 0, c * inner, s * outer, 0, c * outer);
    if (radialUv) uv.push(0, f, 1, f);
    else uv.push(f, 0, f, 1);
  }
  for (let i = 0; i < n; i++) {
    const a = i * 2;
    idx.push(a, a + 1, a + 2, a + 1, a + 3, a + 2);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  g.setAttribute('normal', new THREE.Float32BufferAttribute(new Array((pos.length / 3) * 3).fill(0).map((_, i) => (i % 3 === 1 ? 1 : 0)), 3));
  g.setIndex(idx);
  g.computeBoundingSphere();
  return g;
}

/** Flat ring (annulus) in the XZ plane. */
export function flatRing(inner: number, outer: number, segs = 40): THREE.BufferGeometry {
  const g = new THREE.RingGeometry(inner, outer, segs, 1);
  g.rotateX(-Math.PI / 2);
  return g;
}

export function flatDisc(r: number, segs = 32): THREE.BufferGeometry {
  const g = new THREE.CircleGeometry(r, segs);
  g.rotateX(-Math.PI / 2);
  return g;
}

/** Chevron pointing down (-Y) in the XY plane, extruded slightly. */
export function chevronGeometry(w: number, h: number, t: number): THREE.BufferGeometry {
  const s = new THREE.Shape();
  s.moveTo(-w / 2, h / 2);
  s.lineTo(0, -h / 2 + t);
  s.lineTo(w / 2, h / 2);
  s.lineTo(w / 2, h / 2 - t);
  s.lineTo(0, -h / 2);
  s.lineTo(-w / 2, h / 2 - t);
  s.closePath();
  const g = new THREE.ExtrudeGeometry(s, { depth: t * 0.6, bevelEnabled: false });
  g.translate(0, 0, -t * 0.3);
  return g;
}

/** Arc segments of a ring with gaps (the recording ghost's broken halo). XZ plane. */
export function brokenRingGeometry(radius: number, tube: number, gaps: number): THREE.BufferGeometry {
  const parts: THREE.BufferGeometry[] = [];
  const seg = (Math.PI * 2) / gaps;
  for (let i = 0; i < gaps; i++) {
    // Uneven pieces so it reads as cracked, not as a dashed decoration.
    const len = seg * (i === 0 ? 0.45 : 0.72 - (i % 2) * 0.12);
    const t = new THREE.TorusGeometry(radius, tube, 4, 10, len);
    t.rotateZ(i * seg + (i === 1 ? 0.25 : 0));
    t.rotateX(Math.PI / 2);
    if (i === 0) t.translate(0, 0.03, 0);
    parts.push(t.toNonIndexed());
    t.dispose();
  }
  let total = 0;
  for (const p of parts) total += p.getAttribute('position').count;
  const pos = new Float32Array(total * 3);
  const nrm = new Float32Array(total * 3);
  let off = 0;
  for (const p of parts) {
    const n = p.getAttribute('position').count;
    pos.set(p.getAttribute('position').array as Float32Array, off * 3);
    nrm.set(p.getAttribute('normal').array as Float32Array, off * 3);
    off += n;
    p.dispose();
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  g.setAttribute('normal', new THREE.BufferAttribute(nrm, 3));
  g.setAttribute('uv', new THREE.BufferAttribute(new Float32Array(total * 2), 2));
  g.computeBoundingSphere();
  return g;
}

/**
 * Letter texture for the floor disc (TAPE_NAMES). Browser only; returns null without a DOM so the
 * layer still works (without letters) in headless contexts.
 */
export function letterTexture(letter: string, color: string): THREE.Texture | null {
  if (typeof document === 'undefined') return null;
  const c = document.createElement('canvas');
  c.width = 128;
  c.height = 128;
  const g = c.getContext('2d');
  if (!g) return null;
  g.clearRect(0, 0, 128, 128);
  g.font = '900 92px system-ui, "Segoe UI", Arial, sans-serif';
  g.textAlign = 'center';
  g.textBaseline = 'middle';
  g.lineWidth = 14;
  g.strokeStyle = 'rgba(10,8,14,0.95)';
  g.strokeText(letter, 64, 70);
  g.fillStyle = color;
  g.fillText(letter, 64, 70);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 4;
  return t;
}
