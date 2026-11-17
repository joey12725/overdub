/**
 * Fixed-capacity CPU particle system drawn as one THREE.Points. Used for ghost dust, hologram bits,
 * missile smoke, death bursts and merge flashes. Ring-buffer allocation: when full, the oldest
 * particle is overwritten, so emission never allocates and never fails.
 */
import * as THREE from 'three';
import { createPointsMaterial, pixelsPerUnit, type PointsMaterial } from './materials';

export interface EmitOpts {
  x: number;
  y: number;
  z: number;
  vx?: number;
  vy?: number;
  vz?: number;
  life: number;
  size: number;
  /** Size multiplier reached at end of life. */
  grow?: number;
  color: THREE.Color;
  alpha?: number;
  /** Velocity damping per second. */
  drag?: number;
  /** Downward acceleration (scene Y). */
  gravity?: number;
}

export class ParticleSystem {
  readonly points: THREE.Points;
  private readonly cap: number;
  private readonly pos: Float32Array;
  private readonly vel: Float32Array;
  private readonly rgba: Float32Array;
  private readonly size: Float32Array;
  private readonly age: Float32Array;
  private readonly life: Float32Array;
  private readonly base: Float32Array;
  private readonly grow: Float32Array;
  private readonly alpha0: Float32Array;
  private readonly drag: Float32Array;
  private readonly grav: Float32Array;
  private next = 0;
  private alive = 0;
  private readonly geo: THREE.BufferGeometry;
  private readonly mat: PointsMaterial;

  constructor(capacity: number, opts: { additive: boolean; overlay: boolean; soft: number; renderOrder?: number }) {
    this.cap = capacity;
    this.pos = new Float32Array(capacity * 3);
    this.vel = new Float32Array(capacity * 3);
    this.rgba = new Float32Array(capacity * 4);
    this.size = new Float32Array(capacity);
    this.age = new Float32Array(capacity);
    this.life = new Float32Array(capacity);
    this.base = new Float32Array(capacity);
    this.grow = new Float32Array(capacity);
    this.alpha0 = new Float32Array(capacity);
    this.drag = new Float32Array(capacity);
    this.grav = new Float32Array(capacity);
    this.geo = new THREE.BufferGeometry();
    this.geo.setAttribute('position', new THREE.BufferAttribute(this.pos, 3).setUsage(THREE.DynamicDrawUsage));
    this.geo.setAttribute('rgba', new THREE.BufferAttribute(this.rgba, 4).setUsage(THREE.DynamicDrawUsage));
    this.geo.setAttribute('size', new THREE.BufferAttribute(this.size, 1).setUsage(THREE.DynamicDrawUsage));
    this.geo.boundingSphere = new THREE.Sphere(new THREE.Vector3(), 1e6);
    this.mat = createPointsMaterial(opts);
    this.points = new THREE.Points(this.geo, this.mat);
    this.points.frustumCulled = false;
    this.points.renderOrder = opts.renderOrder ?? 5;
    const mat = this.mat;
    this.points.onBeforeRender = (renderer, _scene, camera) => {
      mat.uniforms.uPxPerUnit.value = pixelsPerUnit(renderer, camera);
    };
  }

  /** Convenience form for one-off bursts (event-driven, not per frame). */
  emit(o: EmitOpts): void {
    this.emitRaw(o.x, o.y, o.z, o.vx ?? 0, o.vy ?? 0, o.vz ?? 0, o.life, o.size, o.grow ?? 1, o.color, o.alpha ?? 1, o.drag ?? 0, o.gravity ?? 0);
  }

  /** Positional form for continuous emitters that run every frame: no options object to allocate. */
  emitRaw(
    x: number,
    y: number,
    z: number,
    vx: number,
    vy: number,
    vz: number,
    life: number,
    size: number,
    grow: number,
    color: THREE.Color,
    alpha: number,
    drag: number,
    gravity: number,
  ): void {
    const i = this.next;
    this.next = (this.next + 1) % this.cap;
    this.pos[i * 3] = x;
    this.pos[i * 3 + 1] = y;
    this.pos[i * 3 + 2] = z;
    this.vel[i * 3] = vx;
    this.vel[i * 3 + 1] = vy;
    this.vel[i * 3 + 2] = vz;
    this.rgba[i * 4] = color.r;
    this.rgba[i * 4 + 1] = color.g;
    this.rgba[i * 4 + 2] = color.b;
    this.alpha0[i] = alpha;
    this.rgba[i * 4 + 3] = alpha;
    this.base[i] = size;
    this.size[i] = size;
    this.grow[i] = grow;
    this.age[i] = 0;
    this.life[i] = Math.max(0.01, life);
    this.drag[i] = drag;
    this.grav[i] = gravity;
    this.alive = Math.min(this.cap, this.alive + 1);
  }

  update(dt: number): void {
    if (this.alive === 0) return;
    let any = 0;
    for (let i = 0; i < this.cap; i++) {
      if (this.life[i] <= 0) continue;
      const a = (this.age[i] += dt);
      if (a >= this.life[i]) {
        this.life[i] = 0;
        this.rgba[i * 4 + 3] = 0;
        this.size[i] = 0;
        continue;
      }
      any++;
      const k = Math.max(0, 1 - this.drag[i] * dt);
      this.vel[i * 3] *= k;
      this.vel[i * 3 + 1] = this.vel[i * 3 + 1] * k - this.grav[i] * dt;
      this.vel[i * 3 + 2] *= k;
      this.pos[i * 3] += this.vel[i * 3] * dt;
      this.pos[i * 3 + 1] += this.vel[i * 3 + 1] * dt;
      this.pos[i * 3 + 2] += this.vel[i * 3 + 2] * dt;
      const t = a / this.life[i];
      this.size[i] = this.base[i] * (1 + (this.grow[i] - 1) * t);
      this.rgba[i * 4 + 3] = this.alpha0[i] * (1 - t) * (1 - t * 0.3);
    }
    this.alive = any;
    (this.geo.getAttribute('position') as THREE.BufferAttribute).needsUpdate = true;
    (this.geo.getAttribute('rgba') as THREE.BufferAttribute).needsUpdate = true;
    (this.geo.getAttribute('size') as THREE.BufferAttribute).needsUpdate = true;
  }

  clear(): void {
    this.life.fill(0);
    this.rgba.fill(0);
    this.size.fill(0);
    this.alive = 0;
  }

  dispose(): void {
    this.geo.dispose();
    this.mat.dispose();
  }
}

/** Shared scratch colour for emitters; fill it, emit, done (emit copies the components). */
export const emitColor = new THREE.Color();
