/**
 * One enemy on screen. Readability contract (AI-04, UI-03): every enemy shows where it faces/aims,
 * a telegraph that fills with stateT before it attacks, a stagger wobble, a hit flash, its current
 * target (thin line + pip in the targeted self's cassette colour), hit-point pips for multi-hit
 * types, shield state for the shielder, a death burst, and for the boss its phase and memory mode.
 */
import * as THREE from 'three';
import type { EnemyType } from '../../core/types';
import { placeStrip } from './decals';
import { ENEMY_COLORS, type EnemyRigSpec } from './enemyModels';
import type { EnemyInterp } from './interp';
import {
  createCelMaterial,
  createFlatMaterial,
  createHullMaterial,
  createStripMaterial,
  type CelMaterial,
  type FlatMaterial,
  type HullMaterial,
  type SharedUniforms,
  type StripMaterial,
} from './materials';
import { clamp01, easeInCubic, easeOutCubic, hash01, hashString, lerp, smoothstep } from './math';
import type { ParticleSystem } from './particles';

export interface EnemyShared {
  shared: SharedUniforms;
  ink: number;
  dust: ParticleSystem;
  glow: ParticleSystem;
  geo: {
    strip: THREE.BufferGeometry;
    pip: THREE.BufferGeometry;
    shadow: THREE.BufferGeometry;
    shock: THREE.BufferGeometry;
    arrow: THREE.BufferGeometry;
    dome: THREE.BufferGeometry;
    domeEdges: THREE.BufferGeometry;
    bar: THREE.BufferGeometry;
    /** Telegraph shapes per type (built from the rig spec). */
    telegraph: Partial<Record<EnemyType, THREE.BufferGeometry>>;
  };
}

export interface EnemyFrameEnv {
  dt: number;
  time: number;
  camQuat: THREE.Quaternion;
  /** Position + colour of a self by tape; null when that self is not on screen. */
  selfPos: (tape: number) => { x: number; y: number } | null;
  tapeColor: (tape: number) => THREE.Color;
  /** Hit flash requests from events this frame (enemy id → true). */
  hitThisFrame: (id: string) => boolean;
}

const MAX_PIPS = 8;
const DEATH_SECONDS = 0.6;
const FLASH_SECONDS = 0.14;

const tmpColor = new THREE.Color();
const EYE_BASE = new THREE.Color(ENEMY_COLORS.eye);
const DANGER = new THREE.Color(ENEMY_COLORS.danger);
const WHITE = new THREE.Color(1, 1, 1);
const STONE = new THREE.Color(ENEMY_COLORS.stone);

export class EnemyView {
  readonly type: EnemyType;
  readonly group = new THREE.Group();
  /** Rotated by facing. */
  private readonly root = new THREE.Group();
  /** Unrotated world-space helpers (aim line, target line). */
  readonly world = new THREE.Group();
  private readonly joints = new Map<string, THREE.Group>();
  private readonly jointList: THREE.Group[] = [];
  private readonly restList: THREE.Vector3[] = [];
  /** Boss armour plates, resolved once (no per-frame name lookups). */
  private readonly plates: THREE.Group[] = [];
  private readonly mat: CelMaterial;
  private readonly hull: HullMaterial;
  private readonly spec: EnemyRigSpec;
  private readonly S: EnemyShared;

  private readonly tele: THREE.Mesh | null;
  private readonly teleMat: StripMaterial;
  private readonly aim: THREE.Mesh;
  private readonly aimMat: StripMaterial;
  private readonly targetLine: THREE.Mesh;
  private readonly targetMat: StripMaterial;
  private readonly targetPip: THREE.Mesh;
  private readonly targetPipMat: FlatMaterial;
  private readonly arrow: THREE.Mesh;
  private readonly arrowMat: FlatMaterial;
  private readonly shadow: THREE.Mesh | null;
  private readonly shadowMat: FlatMaterial | null;
  private readonly pips: THREE.Mesh[] = [];
  private readonly pipOn: FlatMaterial;
  private readonly pipOff: FlatMaterial;
  private readonly marker = new THREE.Group();
  private readonly shock: THREE.Mesh;
  private readonly shockMat: FlatMaterial;
  private readonly dome: THREE.Group | null;
  private readonly domeMat: FlatMaterial | null;
  private readonly domeEdgeMat: THREE.LineBasicMaterial | null;
  private readonly barBg: THREE.Mesh | null;
  private readonly barFill: THREE.Mesh | null;
  private readonly barMat: FlatMaterial | null;
  private readonly barBgMat: FlatMaterial | null;

  private walk = 0;
  private moving = 0;
  private prevX = 0;
  private prevY = 0;
  private lastHp = 0;
  private flash = 0;
  private time = 0;
  private deathT = -1;
  private wasAlive = false;
  private initialized = false;
  private lastShield = false;
  private shieldBreakT = 1;
  private recallT = 0;
  private lastPhase = -1;
  private seed = 0;
  private x = 0;
  private y = 0;

  constructor(spec: EnemyRigSpec, S: EnemyShared) {
    this.spec = spec;
    this.type = spec.type;
    this.S = S;
    this.mat = createCelMaterial(S.shared, false);
    this.mat.uniforms.uAccent.value.copy(EYE_BASE);
    this.mat.uniforms.uRim.value = 0.08;
    this.hull = createHullMaterial(S.ink, spec.hull, false);
    this.group.add(this.root);
    for (const j of spec.joints) {
      const g = new THREE.Group();
      g.position.set(...j.pos);
      this.jointList.push(g);
      this.restList.push(g.position.clone());
      this.joints.set(j.name, g);
      if (j.name.startsWith('plate')) {
        g.rotation.order = 'YXZ';
        this.plates.push(g);
      }
      if (j.geo) {
        const fill = new THREE.Mesh(j.geo, this.mat);
        const hull = new THREE.Mesh(j.geo, this.hull);
        fill.frustumCulled = false;
        hull.frustumCulled = false;
        g.add(fill, hull);
      }
    }
    for (const j of spec.joints) {
      const g = this.joints.get(j.name)!;
      if (j.parent) this.joints.get(j.parent)!.add(g);
      else this.root.add(g);
    }

    // Telegraph decal (rotates with facing) — aim-type telegraphs use the world-space aim line.
    this.teleMat = createStripMaterial(ENEMY_COLORS.danger);
    // Side-edge highlight outlines a cone; on a full circle the "sides" are just the seam.
    this.teleMat.uniforms.uEdge.value = spec.telegraph.kind === 'circle' ? 0 : 1.2;
    this.teleMat.uniforms.uBack.value = 0.22;
    const tg = S.geo.telegraph[spec.type];
    if (tg && spec.telegraph.kind !== 'aim') {
      this.tele = new THREE.Mesh(tg, this.teleMat);
      this.tele.position.y = 0.022;
      this.tele.renderOrder = 4;
      this.root.add(this.tele);
    } else this.tele = null;

    this.aimMat = createStripMaterial(ENEMY_COLORS.danger);
    this.aimMat.uniforms.uEdge.value = 0.6;
    this.aim = new THREE.Mesh(S.geo.strip, this.aimMat);
    this.aim.renderOrder = 7;
    this.aim.frustumCulled = false;
    this.world.add(this.aim);

    this.targetMat = createStripMaterial(0xffffff);
    this.targetMat.uniforms.uDash.value = 0.12;
    this.targetLine = new THREE.Mesh(S.geo.strip, this.targetMat);
    this.targetLine.renderOrder = 5;
    this.targetLine.frustumCulled = false;
    this.world.add(this.targetLine);

    // Facing arrow on the floor in front of the body.
    this.arrowMat = createFlatMaterial(ENEMY_COLORS.danger);
    this.arrow = new THREE.Mesh(S.geo.arrow, this.arrowMat);
    this.arrow.position.set(0, 0.018, spec.radius + 0.12);
    this.arrow.renderOrder = 3;
    this.root.add(this.arrow);

    if (spec.hover > 0) {
      this.shadowMat = createFlatMaterial(0x000000);
      this.shadowMat.uniforms.uOpacity.value = 0.3;
      this.shadow = new THREE.Mesh(S.geo.shadow, this.shadowMat);
      this.shadow.position.y = 0.015;
      this.shadow.renderOrder = 2;
      this.group.add(this.shadow);
    } else {
      this.shadow = null;
      this.shadowMat = null;
    }

    // Billboarded marker above the head: target pip, hp pips, boss bar.
    this.group.add(this.marker);
    this.marker.position.y = spec.top + 0.12;
    this.targetPipMat = createFlatMaterial(0xffffff, { overlay: true });
    this.targetPip = new THREE.Mesh(S.geo.pip, this.targetPipMat);
    this.targetPip.scale.set(1.4, 1.4, 1);
    this.targetPip.position.y = 0.13;
    this.targetPip.rotation.z = Math.PI / 4;
    this.targetPip.renderOrder = 46;
    this.marker.add(this.targetPip);
    this.pipOn = createFlatMaterial(0xfff1d6, { overlay: true });
    this.pipOff = createFlatMaterial(0x2a2530, { overlay: true });
    this.pipOff.uniforms.uOpacity.value = 0.75;
    for (let i = 0; i < MAX_PIPS; i++) {
      const p = new THREE.Mesh(S.geo.pip, this.pipOn);
      p.renderOrder = 45;
      p.visible = false;
      this.pips.push(p);
      this.marker.add(p);
    }
    if (spec.type === 'boss') {
      this.barBgMat = createFlatMaterial(0x1b1720, { overlay: true });
      this.barBgMat.uniforms.uOpacity.value = 0.85;
      this.barMat = createFlatMaterial(ENEMY_COLORS.danger, { overlay: true });
      this.barBg = new THREE.Mesh(S.geo.bar, this.barBgMat);
      this.barFill = new THREE.Mesh(S.geo.bar, this.barMat);
      this.barBg.scale.set(1.6, 0.1, 1);
      this.barBg.renderOrder = 44;
      this.barFill.renderOrder = 45;
      this.marker.add(this.barBg, this.barFill);
    } else {
      this.barBg = this.barFill = null;
      this.barMat = this.barBgMat = null;
    }

    // Shield dome (shielder): faceted energy shell, additive.
    if (spec.type === 'shielder') {
      this.dome = new THREE.Group();
      this.domeMat = createFlatMaterial(0x58f0dc, { additive: true });
      this.domeMat.uniforms.uOpacity.value = 0.12;
      this.domeMat.side = THREE.FrontSide;
      this.domeEdgeMat = new THREE.LineBasicMaterial({ color: 0x8ffff0, transparent: true, opacity: 0.6, depthWrite: false });
      const shell = new THREE.Mesh(S.geo.dome, this.domeMat);
      const edges = new THREE.LineSegments(S.geo.domeEdges, this.domeEdgeMat);
      shell.renderOrder = 34;
      edges.renderOrder = 35;
      this.dome.add(shell, edges);
      this.dome.position.set(0, 0.45, 0.12);
      this.dome.scale.set(1, 0.95, 0.8);
      this.root.add(this.dome);
    } else {
      this.dome = null;
      this.domeMat = null;
      this.domeEdgeMat = null;
    }

    this.shockMat = createFlatMaterial(ENEMY_COLORS.danger, { additive: true });
    this.shock = new THREE.Mesh(S.geo.shock, this.shockMat);
    this.shock.position.y = 0.03;
    this.shock.visible = false;
    this.shock.renderOrder = 8;
    this.group.add(this.shock);
  }

  /** Reset per-instance state when (re)acquired from the pool for a new enemy id. */
  reset(id: string): void {
    this.initialized = false;
    this.deathT = -1;
    this.flash = 0;
    this.walk = 0;
    this.moving = 0;
    this.seed = hashString(id) * 100;
    this.lastPhase = -1;
    this.recallT = 0;
    this.group.visible = true;
    this.world.visible = true;
    this.root.visible = true;
  }

  /** True while the death burst is still playing after the enemy left the snapshot. */
  get dying(): boolean {
    return this.deathT >= 0 && this.deathT < DEATH_SECONDS;
  }

  /** Called when the enemy is absent from the snapshot: play out the death if it was alive. */
  vanish(env: EnemyFrameEnv): void {
    if (this.wasAlive && this.deathT < 0) this.startDeath();
    this.wasAlive = false;
    if (this.deathT >= 0) this.tickDeath(env.dt);
    this.world.visible = false;
    this.marker.visible = false;
    if (this.tele) this.tele.visible = false;
  }

  hide(): void {
    this.group.visible = false;
    this.world.visible = false;
  }

  update(e: EnemyInterp, env: EnemyFrameEnv): void {
    const dt = env.dt;
    this.time += dt;
    this.x = e.x;
    this.y = e.y;
    this.group.position.set(e.x, 0, e.y);
    this.root.rotation.y = Math.PI / 2 - e.facing;
    this.group.visible = true;
    this.world.visible = true;
    this.marker.visible = true;

    if (!this.initialized || e.teleported) {
      this.prevX = e.x;
      this.prevY = e.y;
      this.lastHp = e.hp;
      this.lastShield = e.shield;
      this.wasAlive = e.alive && e.state !== 'dead';
      this.initialized = true;
      if (!this.wasAlive) {
        // Seen for the first time already dead (seek into a run): no burst, just gone.
        this.deathT = DEATH_SECONDS;
      }
    }
    const dead = !e.alive || e.state === 'dead';
    if (dead) {
      if (this.wasAlive && this.deathT < 0) this.startDeath();
      this.wasAlive = false;
      this.tickDeath(dt);
      this.world.visible = false;
      this.marker.visible = false;
      if (this.tele) this.tele.visible = false;
      return;
    }
    this.wasAlive = true;
    this.deathT = -1;
    this.root.visible = true;
    this.root.scale.set(1, 1, 1);
    this.root.position.set(0, 0, 0);

    // Hit flash: hp went down, or the sim reported a hit on this id.
    if (e.hp < this.lastHp || env.hitThisFrame(e.id)) this.flash = FLASH_SECONDS;
    this.lastHp = e.hp;
    this.flash = Math.max(0, this.flash - dt);

    const dist = Math.hypot(e.x - this.prevX, e.y - this.prevY);
    this.prevX = e.x;
    this.prevY = e.y;
    const spd = dt > 0 ? dist / dt : 0;
    this.moving += (clamp01(spd / 2.5) - this.moving) * Math.min(1, dt * 10);
    this.walk += dist * 7;

    this.resetJoints();
    this.animate(e);
    this.updateEye(e);
    this.updateTelegraph(e, env);
    this.updateTarget(e, env);
    this.updateMarkers(e, env);
    if (this.dome) this.updateShield(e, dt);
    if (this.shadow) {
      const body = this.joints.get('body')!;
      const h = body.position.y;
      const s = 1 - Math.min(0.5, h * 0.25);
      this.shadow.scale.set(s, 1, s);
    }
    this.shock.visible = false;

    const m = this.mat.uniforms;
    m.uFlash.value = this.flash > 0 ? 0.85 : 0;
    m.uFlashCol.value.copy(WHITE);
    m.uDesat.value = e.state === 'asleep' ? 0.5 : 0;
  }

  private resetJoints(): void {
    for (let i = 0; i < this.jointList.length; i++) {
      const g = this.jointList[i];
      g.position.copy(this.restList[i]);
      g.rotation.set(0, 0, 0);
      g.scale.set(1, 1, 1);
      g.visible = true;
    }
  }

  private j(name: string): THREE.Group {
    return this.joints.get(name)!;
  }

  private animate(e: EnemyInterp): void {
    const t = e.stateT;
    const tm = this.time + this.seed;
    const tele = e.state === 'telegraph' ? easeOutCubic(t) : 0;
    const atk = e.state === 'attack' ? t : -1;
    const sw = Math.sin(this.walk) * this.moving;
    const asleep = e.state === 'asleep';
    const breathe = Math.sin(tm * 2.2) * 0.008;
    switch (this.type) {
      case 'grunt': {
        const body = this.j('body');
        body.position.y += Math.abs(Math.cos(this.walk)) * 0.03 * this.moving + breathe - (asleep ? 0.05 : 0);
        this.j('legL').rotation.x = sw * 0.6;
        this.j('legR').rotation.x = -sw * 0.6;
        this.j('armL').rotation.x = -sw * 0.4;
        const armR = this.j('armR');
        if (tele > 0) {
          armR.rotation.x = -2.6 * tele;
          body.rotation.x = -0.15 * tele;
        } else if (atk >= 0) {
          armR.rotation.x = lerp(-2.6, -0.8, easeOutCubic(Math.min(1, atk * 3)));
          body.rotation.x = 0.3 * easeOutCubic(Math.min(1, atk * 3));
        } else armR.rotation.x = sw * 0.4;
        if (asleep) this.j('head').rotation.x = 0.35;
        break;
      }
      case 'stalker': {
        const body = this.j('body');
        body.position.y += Math.abs(Math.cos(this.walk)) * 0.04 * this.moving + breathe;
        body.rotation.x = 0.1 * this.moving;
        this.j('legL').rotation.x = sw * 0.8;
        this.j('legR').rotation.x = -sw * 0.8;
        this.j('tail').rotation.y = Math.sin(tm * 3) * 0.4;
        this.j('tail').rotation.x = Math.sin(tm * 2.1) * 0.15;
        const aL = this.j('armL');
        const aR = this.j('armR');
        aL.rotation.x = -0.3 - sw * 0.3;
        aR.rotation.x = -0.3 + sw * 0.3;
        if (tele > 0) {
          body.position.y -= 0.1 * tele;
          body.rotation.x = -0.35 * tele;
          aL.rotation.x = -2.1 * tele;
          aR.rotation.x = -2.1 * tele;
          aL.rotation.z = 0.5 * tele;
          aR.rotation.z = -0.5 * tele;
        } else if (atk >= 0) {
          const k = easeOutCubic(Math.min(1, atk * 2.5));
          body.position.z += 0.25 * k * (1 - atk);
          body.rotation.x = 0.4 * k;
          aL.rotation.x = lerp(-2.1, -1.2, k);
          aR.rotation.x = lerp(-2.1, -1.2, k);
          aL.rotation.z = lerp(0.5, -0.6, k);
          aR.rotation.z = lerp(-0.5, 0.6, k);
        }
        if (asleep) {
          body.position.y -= 0.12;
          this.j('head').rotation.x = 0.5;
        }
        break;
      }
      case 'turret': {
        const head = this.j('head');
        const barrels = this.j('barrels');
        head.rotation.y = 0;
        if (asleep) head.rotation.x = 0.35;
        if (tele > 0) barrels.rotation.z = this.time * 12 * tele;
        if (atk >= 0) barrels.position.z -= 0.08 * (1 - easeOutCubic(atk));
        head.position.y += breathe * 0.5;
        break;
      }
      case 'shielder': {
        const body = this.j('body');
        body.position.y += Math.abs(Math.cos(this.walk)) * 0.025 * this.moving + breathe;
        this.j('legL').rotation.x = sw * 0.5;
        this.j('legR').rotation.x = -sw * 0.5;
        const sh = this.j('shield');
        const down = 1 - (e.shield ? 1 : 0);
        // Shield down: slab sags and swings aside, exposing the body.
        sh.rotation.x = 0.9 * down;
        sh.rotation.y = 0.6 * down;
        sh.position.y -= 0.12 * down;
        sh.position.x += 0.12 * down;
        if (tele > 0) sh.position.z -= 0.12 * tele;
        if (atk >= 0) sh.position.z += 0.22 * easeOutCubic(Math.min(1, atk * 3)) * (1 - atk * 0.5);
        this.j('armR').rotation.x = -sw * 0.4 - tele * 1.2;
        if (asleep) this.j('head').rotation.x = 0.4;
        break;
      }
      case 'brute': {
        const body = this.j('body');
        body.position.y += Math.abs(Math.cos(this.walk)) * 0.04 * this.moving + breathe * 2;
        body.rotation.x = 0.15;
        this.j('legL').rotation.x = sw * 0.45;
        this.j('legR').rotation.x = -sw * 0.45;
        const aL = this.j('armL');
        const aR = this.j('armR');
        aL.rotation.x = -sw * 0.35;
        aR.rotation.x = sw * 0.35;
        if (tele > 0) {
          aL.rotation.x = -2.9 * tele;
          aR.rotation.x = -2.9 * tele;
          body.rotation.x = 0.15 - 0.35 * tele;
          body.position.y += 0.08 * tele;
        } else if (atk >= 0) {
          const k = easeInCubic(Math.min(1, atk * 4));
          aL.rotation.x = lerp(-2.9, -0.5, k);
          aR.rotation.x = lerp(-2.9, -0.5, k);
          body.rotation.x = lerp(-0.2, 0.5, k);
          body.position.y -= 0.1 * k;
        }
        if (asleep) {
          body.position.y -= 0.1;
          body.rotation.x = 0.45;
        }
        break;
      }
      case 'drone': {
        const body = this.j('body');
        body.position.y += Math.sin(tm * 2.4) * 0.06 - (asleep ? 0.55 : 0);
        body.rotation.x = 0.15 * this.moving + (tele > 0 ? -0.1 * tele : 0);
        body.rotation.z = Math.sin(tm * 1.7) * 0.06;
        const spin = asleep ? 0 : 14;
        this.j('rotorA').rotation.y = tm * spin;
        this.j('rotorB').rotation.y = -tm * spin * 1.3;
        this.j('rotorA').rotation.x = 0.1;
        if (atk >= 0) body.position.z -= 0.08 * (1 - atk);
        break;
      }
      case 'boss':
        this.animateBoss(e, tele, atk);
        break;
    }

    // Stagger wobble on top of everything (MOM: stagger must read).
    if (e.state === 'stagger') {
      const amp = (1 - t) * 0.35;
      this.root.rotation.z = Math.sin(this.time * 32) * amp;
      this.root.rotation.x = Math.sin(this.time * 23 + 1) * amp * 0.6;
      this.root.position.y = Math.abs(Math.sin(this.time * 16)) * 0.04 * (1 - t);
    } else {
      this.root.rotation.z = 0;
      this.root.rotation.x = 0;
    }
  }

  private animateBoss(e: EnemyInterp, tele: number, atk: number): void {
    const phase = Math.max(0, Math.round(e.bossPhase));
    if (this.lastPhase >= 0 && phase !== this.lastPhase) {
      // Change of form: flash and shed debris so the transition itself is unmissable.
      this.flash = 0.35;
      this.startDeathBurst(0.5);
    }
    this.lastPhase = phase;
    const tm = this.time;
    const body = this.j('body');
    body.position.y += Math.sin(tm * 1.1) * 0.04;
    const recall = e.bossRecall;
    this.recallT += ((recall ? 1 : 0) - this.recallT) * 0.12;
    // Reels spin forward normally; in memory mode they spin hard in reverse (rewinding a tape).
    const reelSpin = recall ? -9 : 1.2 + phase * 1.5;
    this.j('reelL').rotation.x = tm * reelSpin;
    this.j('reelR').rotation.x = -tm * reelSpin;
    const ribbon = this.j('ribbon');
    ribbon.visible = this.recallT > 0.05;
    ribbon.rotation.y = -tm * 2.2;
    ribbon.scale.setScalar(0.6 + 0.4 * this.recallT);
    const eye = this.j('eye');
    eye.scale.setScalar(1 + phase * 0.18 + tele * 0.25);
    for (let i = 0; i < this.plates.length; i++) {
      const p = this.plates[i];
      const a = (i / 4) * Math.PI * 2 + Math.PI / 4;
      if (phase <= 0) {
        // Sealed: plates hug the column.
        p.position.set(Math.sin(a) * 0.58, 0.6, Math.cos(a) * 0.58);
        p.rotation.set(0, a, 0);
      } else if (phase === 1) {
        // Opened: plates hinge outward, exposing rune channels; the reels come up to speed.
        p.position.set(Math.sin(a) * 0.95, 0.5, Math.cos(a) * 0.95);
        p.rotation.set(-0.55, a, 0);
      } else {
        // Broken free: two plates gone, the rest orbit the exposed core.
        p.visible = i % 2 === 0;
        const o = a + tm * 0.8;
        p.position.set(Math.sin(o) * 1.55, 0.9 + Math.sin(tm * 2 + i) * 0.15, Math.cos(o) * 1.55);
        p.rotation.set(0.3, o, Math.sin(tm + i) * 0.3);
      }
    }
    if (tele > 0) {
      body.position.y += 0.15 * tele;
      body.rotation.x = -0.1 * tele;
    } else if (atk >= 0) {
      const k = easeOutCubic(Math.min(1, atk * 3));
      body.position.y += 0.15 * (1 - k) - 0.08 * k;
      body.rotation.x = 0.08 * k;
    }
    const m = this.mat.uniforms;
    // Later phases run hotter: tinted toward the danger hue so the change of form also reads in colour.
    m.uTint.value.copy(DANGER);
    m.uTintAmt.value = phase >= 2 ? 0.12 + 0.06 * Math.sin(tm * 4) : 0;
  }

  private updateEye(e: EnemyInterp): void {
    const m = this.mat.uniforms;
    const acc = m.uAccent.value;
    const t = e.stateT;
    switch (e.state) {
      case 'asleep':
        acc.copy(EYE_BASE).multiplyScalar(0.25);
        break;
      case 'telegraph':
        acc.copy(EYE_BASE).lerp(WHITE, t * 0.8).multiplyScalar(1 + t * 1.5 + Math.sin(this.time * 30) * 0.3 * t);
        break;
      case 'attack':
        acc.copy(WHITE).multiplyScalar(2.2 - t);
        break;
      case 'stagger':
        acc.copy(EYE_BASE).multiplyScalar(Math.sin(this.time * 40) > 0 ? 1.2 : 0.2);
        break;
      default:
        acc.copy(EYE_BASE).multiplyScalar(1.1);
    }
    if (this.type === 'boss' && e.bossRecall) {
      // Acting on memory: the optic takes the colour of the remembered tape (BOSS-02).
      const c = e.recallTape >= 0 ? this.envTapeColor(e.recallTape) : WHITE;
      acc.lerp(tmpColor.copy(c).multiplyScalar(1.8), 0.85);
    }
    m.uGlowMul.value = e.state === 'asleep' ? 0.6 : 1.4;
  }

  private tapeColorFn: ((t: number) => THREE.Color) | null = null;
  private envTapeColor(t: number): THREE.Color {
    return this.tapeColorFn ? this.tapeColorFn(t) : WHITE;
  }

  private updateTelegraph(e: EnemyInterp, env: EnemyFrameEnv): void {
    this.tapeColorFn = env.tapeColor;
    const tele = e.state === 'telegraph';
    const atk = e.state === 'attack';
    const tm = this.teleMat.uniforms;
    if (this.tele) {
      this.tele.visible = tele || atk;
      if (tele) {
        tm.uFill.value = clamp01(e.stateT);
        tm.uOpacity.value = 0.55 + 0.25 * smoothstep(0.7, 1, e.stateT) * (0.5 + 0.5 * Math.sin(this.time * 40));
        tm.uColor.value.copy(DANGER);
      } else if (atk) {
        tm.uFill.value = 1;
        tm.uOpacity.value = 0.9 * (1 - e.stateT);
        tm.uColor.value.copy(DANGER).lerp(WHITE, 0.5 * (1 - e.stateT));
      }
      if (this.type === 'boss') {
        const phase = Math.max(0, Math.round(e.bossPhase));
        const s = 1 + phase * 0.2;
        this.tele.scale.set(s, 1, s);
        if (e.bossRecall) tm.uColor.value.lerp(this.envTapeColor(e.recallTape >= 0 ? e.recallTape : 0), 0.5);
      }
    }
    // Aim line: always shows where turrets/drones point; fills during the telegraph.
    const aimType = this.spec.telegraph.kind === 'aim';
    const am = this.aimMat.uniforms;
    if (aimType) {
      let len = (this.spec.telegraph as { length: number }).length;
      if (e.hasTarget) {
        const p = env.selfPos(e.target);
        if (p) len = Math.min(len, Math.max(0.6, Math.hypot(p.x - e.x, p.y - e.y)));
      }
      const fx = Math.cos(e.facing);
      const fy = Math.sin(e.facing);
      const h = this.type === 'drone' ? 1.0 : 0.42;
      const start = 0.35;
      const width = tele ? 0.05 + 0.05 * e.stateT : atk ? 0.12 * (1 - e.stateT) + 0.03 : 0.025;
      placeStrip(this.aim, e.x + fx * start, e.y + fy * start, e.x + fx * (start + len), e.y + fy * (start + len), width, h);
      this.aim.visible = e.state !== 'asleep';
      am.uFill.value = tele ? clamp01(e.stateT) : 1;
      am.uBack.value = tele ? 0.25 : 1;
      am.uOpacity.value = tele ? 0.9 : atk ? 0.95 * (1 - e.stateT) + 0.1 : 0.28;
      am.uColor.value.copy(DANGER);
      if (atk) am.uColor.value.lerp(WHITE, 0.6 * (1 - e.stateT));
    } else {
      this.aim.visible = false;
    }
    this.arrow.visible = e.state !== 'asleep';
    this.arrowMat.uniforms.uOpacity.value = tele ? 0.9 : 0.55;
  }

  private updateTarget(e: EnemyInterp, env: EnemyFrameEnv): void {
    const p = e.hasTarget && e.state !== 'asleep' ? env.selfPos(e.target) : null;
    this.targetLine.visible = p !== null;
    this.targetPip.visible = p !== null;
    if (!p) return;
    const c = env.tapeColor(e.target);
    const len = placeStrip(this.targetLine, e.x, e.y, p.x, p.y, 0.022, 0.035);
    const tm = this.targetMat.uniforms;
    tm.uLength.value = len;
    tm.uTime.value = this.time;
    tm.uColor.value.copy(c);
    tm.uOpacity.value = e.state === 'telegraph' ? 0.75 : 0.35;
    this.targetPipMat.uniforms.uColor.value.copy(c);
    this.targetPipMat.uniforms.uOpacity.value = 0.95;
  }

  private updateMarkers(e: EnemyInterp, env: EnemyFrameEnv): void {
    this.marker.quaternion.copy(env.camQuat);
    const multi = e.maxHp > 1 && this.type !== 'boss';
    const n = multi ? Math.min(MAX_PIPS, Math.max(0, Math.round(e.maxHp))) : 0;
    const gap = 0.085;
    for (let i = 0; i < MAX_PIPS; i++) {
      const p = this.pips[i];
      p.visible = i < n;
      if (!p.visible) continue;
      p.position.set((i - (n - 1) / 2) * gap, 0, 0);
      p.material = i < e.hp ? this.pipOn : this.pipOff;
    }
    if (this.barFill && this.barBg && this.barMat) {
      const f = e.maxHp > 0 ? clamp01(e.hp / e.maxHp) : 0;
      this.barFill.scale.set(1.56 * f, 0.07, 1);
      this.barFill.position.x = -0.78 * (1 - f);
      this.barBg.position.y = 0;
      this.barMat.uniforms.uColor.value.copy(DANGER).lerp(WHITE, this.flash > 0 ? 0.7 : 0);
      if (e.bossRecall && e.recallTape >= 0) this.barMat.uniforms.uColor.value.lerp(this.envTapeColor(e.recallTape), 0.6);
    }
  }

  private updateShield(e: EnemyInterp, dt: number): void {
    if (!this.dome || !this.domeMat || !this.domeEdgeMat) return;
    if (this.lastShield && !e.shield) {
      this.shieldBreakT = 0;
      // Shards of the shell scatter when it drops.
      for (let i = 0; i < 16; i++) {
        const a = hash01(i + this.seed) * Math.PI * 2;
        this.S.glow.emit({
          x: e.x + Math.cos(e.facing) * 0.3,
          y: 0.5 + hash01(i * 3 + this.seed) * 0.4,
          z: e.y + Math.sin(e.facing) * 0.3,
          vx: Math.cos(a) * 1.4,
          vy: 0.8,
          vz: Math.sin(a) * 1.4,
          life: 0.45,
          size: 0.05,
          color: tmpColor.setHex(0x8ffff0),
          drag: 3,
          gravity: 3,
        });
      }
    }
    this.lastShield = e.shield;
    this.shieldBreakT = Math.min(1, this.shieldBreakT + dt * 3);
    this.dome.visible = e.shield || this.shieldBreakT < 1;
    const k = e.shield ? 1 : 1 - this.shieldBreakT;
    const shimmer = 0.5 + 0.5 * Math.sin(this.time * 5);
    this.domeMat.uniforms.uOpacity.value = (0.08 + 0.06 * shimmer) * k + (e.shield ? 0 : 0.25 * k);
    this.domeEdgeMat.opacity = (0.45 + 0.25 * shimmer) * k;
    const s = e.shield ? 1 : 1 + (1 - k) * 0.3;
    this.dome.scale.set(s, 0.95 * s, 0.8 * s);
  }

  private startDeath(): void {
    this.deathT = 0;
    this.startDeathBurst(1);
  }

  private startDeathBurst(scale: number): void {
    const S = this.S;
    const n = Math.round((this.type === 'boss' ? 60 : this.type === 'brute' ? 34 : 22) * scale);
    const r = this.spec.radius;
    for (let i = 0; i < n; i++) {
      const a = hash01(i * 1.7 + this.seed) * Math.PI * 2;
      const sp = 0.8 + hash01(i * 3.1 + this.seed) * 2.2 * (r + 0.5);
      S.dust.emit({
        x: this.x,
        y: 0.2 + hash01(i + this.seed) * this.spec.top * 0.7,
        z: this.y,
        vx: Math.cos(a) * sp,
        vy: 1 + hash01(i * 5.3) * 2,
        vz: Math.sin(a) * sp,
        life: 0.9,
        size: 0.06 + hash01(i * 2.2) * 0.06,
        grow: 0.6,
        color: i % 4 === 0 ? tmpColor.setHex(ENEMY_COLORS.brass) : STONE,
        alpha: 1,
        drag: 1.2,
        gravity: 6,
      });
      if (i % 2 === 0)
        S.glow.emit({
          x: this.x,
          y: 0.4 + hash01(i * 9 + this.seed) * this.spec.top * 0.5,
          z: this.y,
          vx: Math.cos(a + 0.5) * sp * 0.8,
          vy: 0.5 + hash01(i * 7.7) * 1.5,
          vz: Math.sin(a + 0.5) * sp * 0.8,
          life: 0.5,
          size: 0.05,
          color: DANGER,
          alpha: 1,
          drag: 2,
        });
    }
  }

  private tickDeath(dt: number): void {
    if (this.deathT < 0) return;
    this.deathT += dt;
    const k = clamp01(this.deathT / DEATH_SECONDS);
    if (k >= 1) {
      this.root.visible = false;
      this.shock.visible = false;
      if (this.shadow) this.shadow.visible = false;
      return;
    }
    // Collapse: flash, crumple downward, shrink; a shock ring expands on the floor.
    this.root.visible = true;
    const s = 1 - easeInCubic(k) * 0.9;
    this.root.scale.set(1 + k * 0.2, s, 1 + k * 0.2);
    this.root.position.y = -k * 0.15;
    this.mat.uniforms.uFlash.value = k < 0.2 ? 1 : 0.6 * (1 - k);
    this.mat.uniforms.uFlashCol.value.copy(k < 0.2 ? WHITE : DANGER);
    this.shock.visible = true;
    const rr = this.spec.radius * (1 + k * 2.5);
    this.shock.scale.set(rr, 1, rr);
    this.shockMat.uniforms.uOpacity.value = 0.8 * (1 - k);
  }

  dispose(): void {
    this.mat.dispose();
    this.hull.dispose();
    this.teleMat.dispose();
    this.aimMat.dispose();
    this.targetMat.dispose();
    this.targetPipMat.dispose();
    this.arrowMat.dispose();
    this.shadowMat?.dispose();
    this.pipOn.dispose();
    this.pipOff.dispose();
    this.shockMat.dispose();
    this.domeMat?.dispose();
    this.domeEdgeMat?.dispose();
    this.barMat?.dispose();
    this.barBgMat?.dispose();
  }
}
