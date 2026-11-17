/**
 * Batched thick polylines (ribbons, contour strips, sigils, epicycles, rune strokes) in one draw.
 *
 * WebGL lines are 1px, which reads as noise on an isometric screen, so every polyline is expanded
 * on the CPU into a triangle strip with a soft glowing cross-section. Lines are declared at level
 * load (buffers sized once); per frame only points/colours are rewritten in place.
 */
import * as THREE from 'three';

/** Strip lies flat on the floor (side vector in the XZ plane). */
export const FACING_FLOOR = 0;
/** Strip turns its face to the camera. */
export const FACING_CAMERA = 1;
/** Strip lies in a plane with a given normal (holographic panels). */
export const FACING_PLANE = 2;

const VERT = /* glsl */ `
attribute vec4 aColor;
attribute float aEdge;
varying vec4 vColor;
varying float vEdge;
void main() {
  vColor = aColor;
  vEdge = aEdge;
  gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
}
`;

const FRAG = /* glsl */ `
varying vec4 vColor;
varying float vEdge;
void main() {
  float e = abs(vEdge);
  float a = vColor.a * pow(max(0.0, 1.0 - e * e), 1.5);
  if (a < 0.003) discard;
  vec3 col = mix(vColor.rgb, vec3(1.0), (1.0 - smoothstep(0.0, 0.45, e)) * 0.35);
  gl_FragColor = vec4(col, a);
}
`;

export class PolylineBatch {
  readonly capacity: number;
  mesh: THREE.Mesh | null = null;
  private used = 0;
  // Per line.
  private starts: number[] = [];
  private counts: number[] = [];
  private closed: boolean[] = [];
  private facing: number[] = [];
  private normals: number[] = [];
  private lineAlpha: number[] = [];
  private geomDirty: boolean[] = [];
  // Per point.
  private readonly pts: Float32Array;
  private readonly wid: Float32Array;
  private readonly col: Float32Array;
  // GPU.
  private geo: THREE.BufferGeometry | null = null;
  private mat: THREE.ShaderMaterial | null = null;
  private posAttr: THREE.BufferAttribute | null = null;
  private colAttr: THREE.BufferAttribute | null = null;
  private readonly lastView = new THREE.Vector3(NaN, NaN, NaN);

  constructor(capacity: number) {
    this.capacity = capacity;
    this.pts = new Float32Array(capacity * 3);
    this.wid = new Float32Array(capacity).fill(0.05);
    this.col = new Float32Array(capacity * 4).fill(1);
  }

  get lineCount(): number {
    return this.starts.length;
  }

  /**
   * Declare a polyline of `points` points. Closed lines get one extra hidden point that mirrors the
   * first. Returns a handle, or -1 if the batch is full. Only valid before finalize().
   */
  addLine(points: number, facing: number, closed = false, nx = 0, ny = 1, nz = 0): number {
    if (this.mesh) throw new Error('PolylineBatch: addLine after finalize');
    const total = points + (closed ? 1 : 0);
    if (points < 2 || this.used + total > this.capacity) return -1;
    this.starts.push(this.used);
    this.counts.push(total);
    this.closed.push(closed);
    this.facing.push(facing);
    const l = Math.hypot(nx, ny, nz) || 1;
    this.normals.push(nx / l, ny / l, nz / l);
    this.lineAlpha.push(1);
    this.geomDirty.push(true);
    this.used += total;
    return this.starts.length - 1;
  }

  /** Points the caller writes (excludes the hidden closing point). */
  pointsOf(line: number): number {
    return this.counts[line] - (this.closed[line] ? 1 : 0);
  }

  setNormal(line: number, nx: number, ny: number, nz: number): void {
    const l = Math.hypot(nx, ny, nz) || 1;
    this.normals[line * 3] = nx / l;
    this.normals[line * 3 + 1] = ny / l;
    this.normals[line * 3 + 2] = nz / l;
    this.geomDirty[line] = true;
  }

  setPoint(line: number, i: number, x: number, y: number, z: number): void {
    const o = (this.starts[line] + i) * 3;
    this.pts[o] = x;
    this.pts[o + 1] = y;
    this.pts[o + 2] = z;
    this.geomDirty[line] = true;
  }

  setWidth(line: number, i: number, w: number): void {
    this.wid[this.starts[line] + i] = w;
    this.geomDirty[line] = true;
  }

  setLineWidth(line: number, w: number): void {
    const s = this.starts[line];
    const n = this.counts[line];
    for (let i = 0; i < n; i++) this.wid[s + i] = w;
    this.geomDirty[line] = true;
  }

  setColor(line: number, i: number, r: number, g: number, b: number, a: number): void {
    const o = (this.starts[line] + i) * 4;
    this.col[o] = r;
    this.col[o + 1] = g;
    this.col[o + 2] = b;
    this.col[o + 3] = a;
  }

  setLineColor(line: number, r: number, g: number, b: number, a: number): void {
    const s = this.starts[line];
    const n = this.counts[line];
    for (let i = 0; i < n; i++) {
      const o = (s + i) * 4;
      this.col[o] = r;
      this.col[o + 1] = g;
      this.col[o + 2] = b;
      this.col[o + 3] = a;
    }
  }

  /** Multiplies every point's alpha (0 hides the line without touching its points). */
  setLineAlpha(line: number, a: number): void {
    this.lineAlpha[line] = a;
  }

  finalize(renderOrder: number): THREE.Mesh {
    const verts = Math.max(2, this.used * 2);
    const geo = new THREE.BufferGeometry();
    this.posAttr = new THREE.BufferAttribute(new Float32Array(verts * 3), 3);
    this.posAttr.setUsage(THREE.DynamicDrawUsage);
    this.colAttr = new THREE.BufferAttribute(new Float32Array(verts * 4), 4);
    this.colAttr.setUsage(THREE.DynamicDrawUsage);
    const edge = new Float32Array(verts);
    for (let v = 0; v < verts; v++) edge[v] = v % 2 === 0 ? -1 : 1;
    geo.setAttribute('position', this.posAttr);
    geo.setAttribute('aColor', this.colAttr);
    geo.setAttribute('aEdge', new THREE.BufferAttribute(edge, 1));
    let segs = 0;
    for (let l = 0; l < this.counts.length; l++) segs += this.counts[l] - 1;
    const idx = verts > 65535 ? new Uint32Array(segs * 6) : new Uint16Array(segs * 6);
    let k = 0;
    for (let l = 0; l < this.counts.length; l++) {
      const base = this.starts[l] * 2;
      for (let s = 0; s < this.counts[l] - 1; s++) {
        const a = base + s * 2;
        idx[k++] = a;
        idx[k++] = a + 1;
        idx[k++] = a + 2;
        idx[k++] = a + 1;
        idx[k++] = a + 3;
        idx[k++] = a + 2;
      }
    }
    geo.setIndex(new THREE.BufferAttribute(idx, 1));
    this.geo = geo;
    this.mat = new THREE.ShaderMaterial({
      vertexShader: VERT,
      fragmentShader: FRAG,
      transparent: true,
      depthWrite: false,
      depthTest: true,
      blending: THREE.AdditiveBlending,
      side: THREE.DoubleSide,
      polygonOffset: true,
      polygonOffsetFactor: -1,
      polygonOffsetUnits: -2,
    });
    const mesh = new THREE.Mesh(geo, this.mat);
    mesh.frustumCulled = false;
    mesh.renderOrder = renderOrder;
    mesh.name = 'fx-lines';
    mesh.userData.fx = true;
    mesh.userData.noOutline = true;
    this.mesh = mesh;
    return mesh;
  }

  /** Rebuild strip vertices for changed lines and upload. `view` is the camera's forward vector. */
  commit(view: THREE.Vector3): void {
    if (!this.posAttr || !this.colAttr) return;
    const viewChanged = Math.abs(view.x - this.lastView.x) + Math.abs(view.y - this.lastView.y) + Math.abs(view.z - this.lastView.z) > 1e-5 || this.lastView.x !== this.lastView.x;
    if (viewChanged) this.lastView.copy(view);
    const P = this.posAttr.array as Float32Array;
    const C = this.colAttr.array as Float32Array;
    let geomChanged = false;
    for (let l = 0; l < this.counts.length; l++) {
      const s = this.starts[l];
      const n = this.counts[l];
      const closed = this.closed[l];
      if (closed) {
        // Mirror point 0 into the hidden closing point.
        const a = s * 3;
        const b = (s + n - 1) * 3;
        this.pts[b] = this.pts[a];
        this.pts[b + 1] = this.pts[a + 1];
        this.pts[b + 2] = this.pts[a + 2];
        this.wid[s + n - 1] = this.wid[s];
        const ca = s * 4;
        const cb = (s + n - 1) * 4;
        this.col[cb] = this.col[ca];
        this.col[cb + 1] = this.col[ca + 1];
        this.col[cb + 2] = this.col[ca + 2];
        this.col[cb + 3] = this.col[ca + 3];
      }
      const la = this.lineAlpha[l];
      for (let i = 0; i < n; i++) {
        const c = (s + i) * 4;
        const v = (s + i) * 8;
        const a = this.col[c + 3] * la;
        C[v] = C[v + 4] = this.col[c];
        C[v + 1] = C[v + 5] = this.col[c + 1];
        C[v + 2] = C[v + 6] = this.col[c + 2];
        C[v + 3] = C[v + 7] = a;
      }
      const facing = this.facing[l];
      if (!this.geomDirty[l] && !(viewChanged && facing === FACING_CAMERA)) continue;
      this.geomDirty[l] = false;
      geomChanged = true;
      let nx = this.normals[l * 3];
      let ny = this.normals[l * 3 + 1];
      let nz = this.normals[l * 3 + 2];
      if (facing === FACING_FLOOR) {
        nx = 0;
        ny = 1;
        nz = 0;
      } else if (facing === FACING_CAMERA) {
        nx = view.x;
        ny = view.y;
        nz = view.z;
      }
      let sx = 1;
      let sy = 0;
      let sz = 0;
      for (let i = 0; i < n; i++) {
        let i0 = i - 1;
        let i1 = i + 1;
        if (closed) {
          // The closing point duplicates point 0, so wrap over the n-1 distinct points.
          const m = n - 1;
          i0 = (((i - 1) % m) + m) % m;
          i1 = (i + 1) % m;
        } else {
          if (i0 < 0) i0 = 0;
          if (i1 > n - 1) i1 = n - 1;
        }
        const a = (s + i0) * 3;
        const b = (s + i1) * 3;
        const tx = this.pts[b] - this.pts[a];
        const ty = this.pts[b + 1] - this.pts[a + 1];
        const tz = this.pts[b + 2] - this.pts[a + 2];
        // side = t × n
        const cx = ty * nz - tz * ny;
        const cy = tz * nx - tx * nz;
        const cz = tx * ny - ty * nx;
        const cl = Math.hypot(cx, cy, cz);
        if (cl > 1e-7) {
          sx = cx / cl;
          sy = cy / cl;
          sz = cz / cl;
        }
        const p = (s + i) * 3;
        const hw = this.wid[s + i] * 0.5;
        const v = (s + i) * 6;
        P[v] = this.pts[p] - sx * hw;
        P[v + 1] = this.pts[p + 1] - sy * hw;
        P[v + 2] = this.pts[p + 2] - sz * hw;
        P[v + 3] = this.pts[p] + sx * hw;
        P[v + 4] = this.pts[p + 1] + sy * hw;
        P[v + 5] = this.pts[p + 2] + sz * hw;
      }
    }
    if (geomChanged) this.posAttr.needsUpdate = true;
    this.colAttr.needsUpdate = true;
  }

  dispose(): void {
    this.geo?.dispose();
    this.mat?.dispose();
    this.geo = null;
    this.mat = null;
    this.mesh = null;
  }
}
