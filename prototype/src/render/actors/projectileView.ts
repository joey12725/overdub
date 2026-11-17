/**
 * Projectiles, one look per archetype (WEAPON-01..03), coloured by owner: a self's shots carry its
 * cassette colour, enemy shots the hot danger orange.
 *   missile — slow, chunky, smoke trail, dashed lock line + reticle on its one locked target (WEAPON-02)
 *   pierce  — fast bright lance with a long streak
 *   phase   — ghostly orb drawn over walls (it passes through them, so it must stay visible)
 *   arc     — lobbed shell at height z, ground shadow and a landing marker
 *   burst   — small pellets with short streaks
 *   bolt    — enemy energy bolt
 *   shock   — enemy crackling orb
 */
import * as THREE from 'three';
import type { ProjectileSnap } from '../../core/types';
import { placeStrip } from './decals';
import { createFlatMaterial, createStripMaterial, type FlatMaterial, type StripMaterial } from './materials';
import { hash01 } from './math';
import type { ProjectileInterp } from './interp';
import type { ParticleSystem } from './particles';

export type ProjectileKind = ProjectileSnap['archetype'];

export interface ProjectileShared {
  dust: ParticleSystem;
  glow: ParticleSystem;
  geo: {
    strip: THREE.BufferGeometry;
    orb: THREE.BufferGeometry;
    lance: THREE.BufferGeometry;
    missileBody: THREE.BufferGeometry;
    missileFins: THREE.BufferGeometry;
    ring: THREE.BufferGeometry;
    disc: THREE.BufferGeometry;
    pellet: THREE.BufferGeometry;
  };
}

export interface ProjectileFrameEnv {
  dt: number;
  time: number;
  camQuat: THREE.Quaternion;
  enemyPos: (id: string) => { x: number; y: number } | null;
}

const SMOKE = new THREE.Color(0xb9b4ad);
const WHITE = new THREE.Color(1, 1, 1);
const tmp = new THREE.Color();
const CRACKLE_SEGS = 10;

export class ProjectileView {
  readonly kind: ProjectileKind;
  readonly group = new THREE.Group();
  /** Rotated to the travel direction, raised to z. */
  private readonly body = new THREE.Group();
  readonly world = new THREE.Group();
  private readonly color = new THREE.Color();
  private readonly S: ProjectileShared;
  private readonly mats: FlatMaterial[] = [];
  private readonly core: FlatMaterial;
  private readonly halo: FlatMaterial;
  private readonly streak: THREE.Mesh | null = null;
  private readonly streakMat: StripMaterial | null = null;
  private readonly lockLine: THREE.Mesh | null = null;
  private readonly lockMat: StripMaterial | null = null;
  private readonly reticle: THREE.Mesh | null = null;
  private readonly reticleMat: FlatMaterial | null = null;
  private readonly shadow: THREE.Mesh | null = null;
  private readonly landing: THREE.Mesh | null = null;
  private readonly landingMat: FlatMaterial | null = null;
  private readonly crackle: THREE.LineSegments | null = null;
  private readonly cracklePos: Float32Array | null = null;
  private readonly crackleMat: THREE.LineBasicMaterial | null = null;
  private emitAcc = 0;
  private time = 0;
  private lastX = 0;
  private lastY = 0;
  private lastZ = 0;
  private vx = 0;
  private vy = 0;
  private vz = 0;
  private g = 0;
  private samples = 0;
  private seed = 0;

  constructor(kind: ProjectileKind, S: ProjectileShared) {
    this.kind = kind;
    this.S = S;
    this.group.add(this.body);
    const overlay = kind === 'phase';
    this.core = this.mat(0xffffff, { additive: false, overlay });
    this.halo = this.mat(0xffffff, { additive: true, overlay });
    const G = S.geo;
    const add = (geo: THREE.BufferGeometry, m: THREE.Material, s: [number, number, number], ro = 20, parent: THREE.Object3D = this.body) => {
      const mesh = new THREE.Mesh(geo, m);
      mesh.scale.set(...s);
      mesh.renderOrder = ro;
      mesh.frustumCulled = false;
      parent.add(mesh);
      return mesh;
    };
    const strip = (overlayStrip: boolean): [THREE.Mesh, StripMaterial] => {
      const m = createStripMaterial(0xffffff, { additive: true, overlay: overlayStrip });
      const mesh = new THREE.Mesh(G.strip, m);
      mesh.renderOrder = 19;
      mesh.frustumCulled = false;
      this.world.add(mesh);
      return [mesh, m];
    };
    switch (kind) {
      case 'missile': {
        add(G.missileBody, this.mat(0x2d2a30), [1, 1, 1]);
        add(G.missileFins, this.core, [1, 1, 1]);
        const ex = add(G.orb, this.halo, [0.09, 0.09, 0.14], 21);
        ex.position.z = -0.17;
        [this.lockLine, this.lockMat] = strip(false);
        this.lockMat.uniforms.uDash.value = 0.14;
        this.reticleMat = createFlatMaterial(0xffffff, { overlay: true, additive: true });
        this.mats.push(this.reticleMat);
        this.reticle = new THREE.Mesh(G.ring, this.reticleMat);
        this.reticle.renderOrder = 42;
        this.world.add(this.reticle);
        break;
      }
      case 'pierce': {
        add(G.lance, this.core, [0.05, 0.05, 0.55]);
        add(G.lance, this.halo, [0.11, 0.11, 0.8], 21);
        [this.streak, this.streakMat] = strip(false);
        break;
      }
      case 'phase': {
        add(G.orb, this.core, [0.09, 0.09, 0.09], 50);
        add(G.orb, this.halo, [0.2, 0.2, 0.2], 51);
        const r = add(G.ring, this.halo, [0.22, 0.22, 0.22], 51);
        r.rotation.x = Math.PI / 2;
        break;
      }
      case 'arc': {
        add(G.orb, this.core, [0.1, 0.1, 0.1]);
        add(G.orb, this.halo, [0.17, 0.17, 0.17], 21);
        const sm = createFlatMaterial(0x000000);
        sm.uniforms.uOpacity.value = 0.35;
        this.mats.push(sm);
        this.shadow = new THREE.Mesh(G.disc, sm);
        this.shadow.renderOrder = 3;
        this.world.add(this.shadow);
        this.landingMat = createFlatMaterial(0xffffff, { additive: true });
        this.mats.push(this.landingMat);
        this.landing = new THREE.Mesh(G.ring, this.landingMat);
        this.landing.renderOrder = 4;
        this.world.add(this.landing);
        break;
      }
      case 'burst': {
        add(G.pellet, this.core, [0.045, 0.045, 0.045]);
        add(G.orb, this.halo, [0.08, 0.08, 0.08], 21);
        [this.streak, this.streakMat] = strip(false);
        break;
      }
      case 'bolt': {
        add(G.lance, this.core, [0.06, 0.06, 0.3]);
        add(G.orb, this.halo, [0.13, 0.13, 0.22], 21);
        [this.streak, this.streakMat] = strip(false);
        break;
      }
      case 'shock': {
        add(G.orb, this.core, [0.08, 0.08, 0.08]);
        add(G.orb, this.halo, [0.18, 0.18, 0.18], 21);
        this.cracklePos = new Float32Array(CRACKLE_SEGS * 2 * 3);
        const cg = new THREE.BufferGeometry();
        cg.setAttribute('position', new THREE.BufferAttribute(this.cracklePos, 3).setUsage(THREE.DynamicDrawUsage));
        this.crackleMat = new THREE.LineBasicMaterial({ color: 0xffffff, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending });
        this.crackle = new THREE.LineSegments(cg, this.crackleMat);
        this.crackle.frustumCulled = false;
        this.crackle.renderOrder = 22;
        this.body.add(this.crackle);
        break;
      }
    }
  }

  private mat(color: number, opts: { additive?: boolean; overlay?: boolean } = {}): FlatMaterial {
    const m = createFlatMaterial(color, opts);
    this.mats.push(m);
    return m;
  }

  reset(id: number, color: THREE.Color): void {
    this.seed = hash01(id * 0.37 + 1) * 100;
    this.samples = 0;
    this.time = 0;
    this.emitAcc = 0;
    this.color.copy(color);
    // Enemy shots keep more of their orange so they never read as a self's pale shot.
    const pale = this.kind === 'missile' ? 0 : this.kind === 'bolt' || this.kind === 'shock' ? 0.2 : 0.55;
    this.core.uniforms.uColor.value.copy(color).lerp(WHITE, pale);
    this.halo.uniforms.uColor.value.copy(color);
    this.halo.uniforms.uOpacity.value = 0.55;
    this.streakMat?.uniforms.uColor.value.copy(color);
    this.lockMat?.uniforms.uColor.value.copy(color);
    this.reticleMat?.uniforms.uColor.value.copy(color);
    this.landingMat?.uniforms.uColor.value.copy(color);
    this.crackleMat?.color.copy(color).lerp(WHITE, 0.4);
    this.group.visible = true;
    this.world.visible = true;
  }

  update(p: ProjectileInterp, targetId: string | undefined, env: ProjectileFrameEnv): void {
    const dt = env.dt;
    this.time += dt;
    const h = this.kind === 'arc' ? 0.15 + p.z : this.kind === 'missile' ? 0.45 + p.z : 0.5 + p.z;
    this.group.position.set(p.x, h, p.y);
    this.body.rotation.set(0, Math.PI / 2 - p.dir, 0);

    // Velocity estimate (for landing prediction, trails).
    if (this.samples > 0 && dt > 1e-5) {
      const k = Math.min(1, dt * 12);
      const nvx = (p.x - this.lastX) / dt;
      const nvy = (p.y - this.lastY) / dt;
      const nvz = (p.z - this.lastZ) / dt;
      if (this.samples > 1) {
        const ng = -(nvz - this.vz) / dt;
        if (Number.isFinite(ng)) this.g += (ng - this.g) * Math.min(1, dt * 4);
      }
      this.vx += (nvx - this.vx) * k;
      this.vy += (nvy - this.vy) * k;
      this.vz += (nvz - this.vz) * k;
    }
    const moved = Math.hypot(p.x - this.lastX, p.y - this.lastY);
    this.lastX = p.x;
    this.lastY = p.y;
    this.lastZ = p.z;
    this.samples++;
    if (p.fresh) this.muzzle(p);

    const fx = Math.cos(p.dir);
    const fy = Math.sin(p.dir);
    switch (this.kind) {
      case 'missile': {
        // Slow and smoky: the long flight is the weapon's drawback (WEAPON-02), so make it visible.
        this.emitAcc += moved * 22 + dt * 8;
        let k = 0;
        while (this.emitAcc >= 1) {
          this.emitAcc -= 1;
          k++;
          const r = hash01(this.time * 50 + this.seed + k * 4.1) - 0.5;
          this.S.dust.emitRaw(p.x - fx * 0.2 + r * 0.04, h + r * 0.04, p.y - fy * 0.2, 0, 0.15, 0, 1.2, 0.07, 3, SMOKE, 0.55, 2, 0);
        }
        const tp = targetId ? env.enemyPos(targetId) : null;
        if (this.lockLine && this.lockMat && this.reticle && this.reticleMat) {
          this.lockLine.visible = tp !== null;
          this.reticle.visible = tp !== null;
          if (tp) {
            const len = placeStrip(this.lockLine, p.x, p.y, tp.x, tp.y, 0.03, 0.06);
            this.lockMat.uniforms.uLength.value = len;
            this.lockMat.uniforms.uTime.value = this.time;
            this.lockMat.uniforms.uOpacity.value = 0.55;
            this.reticle.position.set(tp.x, 0.06, tp.y);
            this.reticle.rotation.set(-Math.PI / 2, 0, this.time * 3);
            const s = 0.42 + Math.sin(this.time * 8) * 0.04;
            this.reticle.scale.set(s, s, s);
            this.reticleMat.uniforms.uOpacity.value = 0.85;
          }
        }
        break;
      }
      case 'pierce':
      case 'burst':
      case 'bolt': {
        if (this.streak && this.streakMat) {
          const L = this.kind === 'pierce' ? 1.1 : this.kind === 'bolt' ? 0.5 : 0.28;
          const w = this.kind === 'pierce' ? 0.07 : this.kind === 'bolt' ? 0.08 : 0.04;
          placeStrip(this.streak, p.x - fx * L, p.y - fy * L, p.x, p.y, w, h);
          const u = this.streakMat.uniforms;
          // The strip runs tail (uv.x = 0) to head (uv.x = 1): fade it out toward the tail.
          u.uFill.value = 1;
          u.uBack.value = 1;
          u.uFade.value = 1;
          u.uOpacity.value = 0.8;
          u.uEdge.value = -0.8;
        }
        break;
      }
      case 'phase': {
        const s = 1 + Math.sin(this.time * 9 + this.seed) * 0.15;
        this.body.scale.set(s, s, s);
        this.halo.uniforms.uOpacity.value = 0.35 + 0.15 * Math.sin(this.time * 13);
        this.emitAcc += dt * 18;
        while (this.emitAcc >= 1) {
          this.emitAcc -= 1;
          this.S.glow.emitRaw(p.x, h, p.y, 0, 0.1, 0, 0.35, 0.06, 0.3, this.color, 0.6, 0, 0);
        }
        break;
      }
      case 'arc': {
        if (this.shadow) {
          this.shadow.position.set(p.x, 0.016, p.y);
          const s = Math.max(0.05, 0.14 - p.z * 0.03);
          this.shadow.scale.set(s / 0.14, 1, s / 0.14);
        }
        if (this.landing && this.landingMat) {
          // Predict touchdown from the observed parabola (falls back to a straight-down drop).
          const g = this.g > 0.5 ? this.g : 9.8;
          const disc = this.vz * this.vz + 2 * g * Math.max(0, p.z);
          const tl = Math.max(0, (this.vz + Math.sqrt(disc)) / g);
          const lx = p.x + this.vx * tl;
          const ly = p.y + this.vy * tl;
          this.landing.position.set(lx, 0.02, ly);
          this.landing.rotation.set(-Math.PI / 2, 0, this.time * 2);
          const s = 0.35 + 0.08 * Math.sin(this.time * 10);
          this.landing.scale.set(s, s, s);
          this.landingMat.uniforms.uOpacity.value = this.samples > 2 ? 0.8 : 0;
        }
        break;
      }
      case 'shock': {
        if (this.crackle && this.cracklePos) {
          const P = this.cracklePos;
          const step = Math.floor(this.time * 24);
          for (let i = 0; i < CRACKLE_SEGS; i++) {
            const a = hash01(step * 13 + i * 7 + this.seed) * Math.PI * 2;
            const b = hash01(step * 17 + i * 3 + this.seed) * Math.PI - Math.PI / 2;
            const r0 = 0.05;
            const r1 = 0.14 + hash01(step + i) * 0.12;
            const cx = Math.cos(a) * Math.cos(b);
            const cy = Math.sin(b);
            const cz = Math.sin(a) * Math.cos(b);
            const j = (hash01(step * 5 + i) - 0.5) * 0.08;
            P[i * 6] = cx * r0;
            P[i * 6 + 1] = cy * r0;
            P[i * 6 + 2] = cz * r0;
            P[i * 6 + 3] = cx * r1 + j;
            P[i * 6 + 4] = cy * r1 - j;
            P[i * 6 + 5] = cz * r1 + j;
          }
          (this.crackle.geometry.getAttribute('position') as THREE.BufferAttribute).needsUpdate = true;
        }
        this.halo.uniforms.uOpacity.value = 0.4 + 0.3 * hash01(Math.floor(this.time * 30) + this.seed);
        break;
      }
    }
  }

  private muzzle(p: ProjectileInterp): void {
    for (let i = 0; i < 8; i++) {
      const a = p.dir + (hash01(i + this.seed) - 0.5) * 1.6;
      const sp = 0.8 + hash01(i * 3 + this.seed) * 1.4;
      this.S.glow.emit({
        x: p.x,
        y: 0.5 + p.z,
        z: p.y,
        vx: Math.cos(a) * sp,
        vy: 0.2,
        vz: Math.sin(a) * sp,
        life: 0.22,
        size: 0.05,
        color: tmp.copy(this.color).lerp(WHITE, 0.3),
        alpha: 1,
        drag: 6,
      });
    }
  }

  /** Projectile ended between snapshots: small pop at its last position. */
  pop(): void {
    for (let i = 0; i < 10; i++) {
      const a = (i / 10) * Math.PI * 2;
      this.S.glow.emit({
        x: this.lastX,
        y: 0.5 + this.lastZ,
        z: this.lastY,
        vx: Math.cos(a) * 1.2,
        vy: 0.4,
        vz: Math.sin(a) * 1.2,
        life: 0.25,
        size: 0.05,
        color: this.color,
        alpha: 0.9,
        drag: 5,
      });
    }
  }

  hide(): void {
    this.group.visible = false;
    this.world.visible = false;
  }

  dispose(): void {
    for (const m of this.mats) m.dispose();
    this.streakMat?.dispose();
    this.lockMat?.dispose();
    this.crackleMat?.dispose();
    this.crackle?.geometry.dispose();
  }
}
