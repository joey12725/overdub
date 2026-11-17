/**
 * One self (one cassette's Moxie) on screen: rig + pose, state styling, cassette identity markers,
 * dodge afterimages, swing trail, death transition and the desync spark/tether.
 *
 * Four selves, one Moxie (UI-02): identity is the cassette colour on the ink outline, the floor
 * ring with the tape letter and the headphone glow — never a recoloured outfit.
 */
import * as THREE from 'three';
import { LOCAL_HZ, type MeleeWeaponDef, type RangedWeaponDef, type TapeIndex } from '../../core/types';
import type { ActorInterp } from './interp';
import { createFlatMaterial, createPointsMaterial, createStripMaterial, pixelsPerUnit, type FlatMaterial, type PointsMaterial, type StripMaterial } from './materials';
import { bump, clamp01, dampFactor, hash01, smoothstep } from './math';
import { applyPose, RIG, type MoxieGeometry } from './moxie';
import { EchoRig, MoxieMesh } from './moxieMesh';
import type { ParticleSystem } from './particles';
import {
  animDurationTicks,
  animProgress,
  blendPose,
  computePose,
  copyPose,
  createPose,
  createPoseParams,
  DEATH_SECONDS,
  isMeleeState,
  type Pose,
} from './pose';
import {
  actorStyleParams,
  flickerValue,
  IFRAME_OPACITY_HIGH,
  IFRAME_OPACITY_LOW,
  selectActorStyle,
  STOPPED_DESAT,
  type ActorStyleId,
} from './style';
import { SwingTrail } from './swing';
import { placeStrip } from './decals';

/** Reference run speed in tiles per LOCAL second, for normalising stride amplitude and lean. */
const RUN_REF = 4.2;
/** Tiles per full stride cycle. */
const STRIDE_LEN = 0.95;
/** Seconds to cross-fade between anim states. */
const BLEND_SECONDS = 0.09;
const HISTORY = 12;
const AFTERIMAGES = 3;
const SPARK_TRAIL = 14;
const MERGE_SECONDS = 0.55;

export interface SelfShared {
  geometry: MoxieGeometry;
  shared: import('./materials').SharedUniforms;
  melee: MeleeWeaponDef;
  ranged: RangedWeaponDef;
  ink: number;
  dust: ParticleSystem;
  glow: ParticleSystem;
  geo: {
    ring: THREE.BufferGeometry;
    ringOuter: THREE.BufferGeometry;
    disc: THREE.BufferGeometry;
    badge: THREE.BufferGeometry;
    letter: THREE.BufferGeometry;
    chevron: THREE.BufferGeometry;
    halo: THREE.BufferGeometry;
    bar: THREE.BufferGeometry;
    strip: THREE.BufferGeometry;
    mergeRing: THREE.BufferGeometry;
    flash: THREE.BufferGeometry;
  };
  letterTex: (THREE.Texture | null)[];
}

/** Per-frame inputs shared by all selves. */
export interface SelfFrameEnv {
  dt: number;
  time: number;
  beatPulse: number;
  camRight: THREE.Vector3;
  camQuat: THREE.Quaternion;
  /** Horizontal unit vector pointing from the camera into the scene (screen up on the floor). */
  camFwdX: number;
  camFwdZ: number;
  /** Is this the self under live control (from RenderFrame.active or ActorSnap.live). */
  isLive: boolean;
  /** Global intensity for flourishes (cinematic mode turns it up). */
  flourish: number;
}

const tmpColor = new THREE.Color();
const tmpColor2 = new THREE.Color();
// Blue-grey: reads as 'drained' on both the warm upper floors and the dark lower ones.
const GHOST_GREY = new THREE.Color(0x7d8394);
const DUST_GREY = new THREE.Color(0x8d8f99);
const WHITE = new THREE.Color(1, 1, 1);

export class SelfView {
  readonly tape: TapeIndex;
  /** World-space container at the actor's feet (unrotated): markers live here. */
  readonly group = new THREE.Group();
  /** Spark, trail and tether live in world space, outside `group`. */
  readonly world = new THREE.Group();
  readonly color: THREE.Color;
  private readonly moxie: MoxieMesh;
  private readonly echoes: EchoRig[] = [];
  private readonly swing: SwingTrail;
  private readonly S: SelfShared;

  // markers
  private readonly ring: THREE.Mesh;
  private readonly ringMat: FlatMaterial;
  private readonly ringInk: THREE.Mesh;
  private readonly ringInkMat: FlatMaterial;
  private readonly disc: THREE.Mesh;
  private readonly discMat: FlatMaterial;
  private readonly liveRing: THREE.Mesh;
  private readonly liveRingMat: FlatMaterial;
  private readonly badge: THREE.Mesh;
  private readonly badgeMat: FlatMaterial;
  private readonly letter: THREE.Mesh | null;
  private readonly letterMat: THREE.MeshBasicMaterial | null;
  private readonly chevron: THREE.Group;
  private readonly chevronMat: FlatMaterial;
  private readonly chevronInkMat: FlatMaterial;
  private readonly halo: THREE.Mesh;
  private readonly haloMat: FlatMaterial;
  private readonly pause: THREE.Group;
  private readonly pauseMat: FlatMaterial;
  private readonly muzzle: THREE.Mesh;
  private readonly muzzleMat: FlatMaterial;

  // spark
  private readonly spark: THREE.Points;
  private readonly sparkGeo: THREE.BufferGeometry;
  private readonly sparkMat: PointsMaterial;
  private readonly sparkPos: Float32Array;
  private readonly sparkRgba: Float32Array;
  private readonly sparkSize: Float32Array;
  private readonly trailX = new Float32Array(SPARK_TRAIL);
  private readonly trailZ = new Float32Array(SPARK_TRAIL);
  private trailCount = 0;
  private readonly tether: THREE.Mesh;
  private readonly tetherMat: StripMaterial;
  private readonly merge: THREE.Mesh;
  private readonly mergeMat: FlatMaterial;

  // animation state
  private readonly pose = createPose();
  private readonly target = createPose();
  private readonly from = createPose();
  private readonly params = createPoseParams();
  private readonly history: Pose[] = [];
  private readonly histX = new Float32Array(HISTORY);
  private readonly histY = new Float32Array(HISTORY);
  private readonly histF = new Float32Array(HISTORY);
  private histHead = 0;
  private histFill = 0;
  private lastAnim: ActorInterp['anim'] = 'idle';
  private entryTick = 0;
  private lastTraversal = 0;
  private blendT = 1;
  private prevX = 0;
  private prevY = 0;
  private prevTick = 0;
  private speed = 0;
  private initialized = false;
  private lastLife: ActorInterp['life'] = 'alive';
  private lastSynced = true;
  private deathT = -1;
  private mergeT = -1;
  private mergeX = 0;
  private mergeY = 0;
  private afterT = 0;
  private dustAcc = 0;
  private bitsAcc = 0;
  private visible = false;
  /** False until a pose has been computed since the self (re)appeared. */
  private posed = false;
  private readonly seed: number;

  constructor(tape: TapeIndex, color: THREE.Color, S: SelfShared) {
    this.tape = tape;
    this.S = S;
    this.color = color.clone();
    this.seed = hash01(tape + 1) * 10;
    this.moxie = new MoxieMesh(S.geometry, S.shared, color.getHex(), S.ink);
    this.moxie.solidMat.uniforms.uAccent.value.copy(color);
    this.moxie.fxMat.uniforms.uAccent.value.copy(color);
    this.moxie.fxMat.uniforms.uHoloCol.value.copy(color);
    this.group.add(this.moxie.bones.root);
    for (let i = 0; i < AFTERIMAGES; i++) {
      const e = new EchoRig(S.geometry, color);
      this.echoes.push(e);
      this.world.add(e.bones.root);
    }
    for (let i = 0; i < HISTORY; i++) this.history.push(createPose());
    this.swing = new SwingTrail(S.melee, color);
    this.moxie.bones.root.add(this.swing.group);

    // Floor identity: tinted disc, ink-backed ring, letter badge on the camera side (UI-02).
    this.discMat = createFlatMaterial(color.getHex());
    this.disc = new THREE.Mesh(S.geo.disc, this.discMat);
    this.disc.position.y = 0.008;
    this.ringInkMat = createFlatMaterial(S.ink);
    this.ringInk = new THREE.Mesh(S.geo.ringOuter, this.ringInkMat);
    this.ringInk.position.y = 0.01;
    this.ringMat = createFlatMaterial(color.getHex());
    this.ring = new THREE.Mesh(S.geo.ring, this.ringMat);
    this.ring.position.y = 0.012;
    this.liveRingMat = createFlatMaterial(color.getHex(), { additive: true });
    this.liveRing = new THREE.Mesh(S.geo.ring, this.liveRingMat);
    this.liveRing.position.y = 0.014;
    this.badgeMat = createFlatMaterial(S.ink);
    this.badge = new THREE.Mesh(S.geo.badge, this.badgeMat);
    const tex = S.letterTex[tape] ?? null;
    if (tex) {
      this.letterMat = new THREE.MeshBasicMaterial({ map: tex, transparent: true, depthWrite: false });
      this.letter = new THREE.Mesh(S.geo.letter, this.letterMat);
    } else {
      this.letterMat = null;
      this.letter = null;
    }
    for (const m of [this.disc, this.ringInk, this.ring, this.liveRing, this.badge]) {
      m.renderOrder = 2;
      this.group.add(m);
    }
    if (this.letter) {
      this.letter.renderOrder = 3;
      this.group.add(this.letter);
    }

    // Live marker: bouncing chevron, drawn over walls so the controlled self is never lost.
    this.chevronMat = createFlatMaterial(color.getHex(), { overlay: true });
    this.chevronInkMat = createFlatMaterial(S.ink, { overlay: true });
    this.chevron = new THREE.Group();
    const chevInk = new THREE.Mesh(S.geo.chevron, this.chevronInkMat);
    chevInk.scale.set(1.35, 1.35, 1);
    chevInk.position.z = -0.01;
    chevInk.renderOrder = 40;
    const chev = new THREE.Mesh(S.geo.chevron, this.chevronMat);
    chev.renderOrder = 41;
    this.chevron.add(chevInk, chev);
    this.group.add(this.chevron);

    // Broken halo: "dead but still performing" (GHOST-01).
    this.haloMat = createFlatMaterial(color.getHex(), { additive: true });
    this.halo = new THREE.Mesh(S.geo.halo, this.haloMat);
    this.halo.renderOrder = 35;
    this.group.add(this.halo);

    // Pause glyph for a 'stop' tape holding its final pose.
    this.pauseMat = createFlatMaterial(color.getHex(), { overlay: false });
    this.pause = new THREE.Group();
    const b1 = new THREE.Mesh(S.geo.bar, this.pauseMat);
    const b2 = new THREE.Mesh(S.geo.bar, this.pauseMat);
    b1.position.x = -0.035;
    b2.position.x = 0.035;
    this.pause.add(b1, b2);
    this.group.add(this.pause);

    // Wrist-device muzzle flash on the left hand (ranged pose thrusts the left wrist).
    this.muzzleMat = createFlatMaterial(color.getHex(), { additive: true });
    this.muzzle = new THREE.Mesh(S.geo.flash, this.muzzleMat);
    this.muzzle.position.set(0, -0.12, 0.05);
    this.muzzle.renderOrder = 36;
    this.moxie.bones.bones.elbowL.add(this.muzzle);

    // Spark: soft glow + hot core + comet trail, drawn above walls (DESYNC-06).
    const n = SPARK_TRAIL + 2;
    this.sparkPos = new Float32Array(n * 3);
    this.sparkRgba = new Float32Array(n * 4);
    this.sparkSize = new Float32Array(n);
    this.sparkGeo = new THREE.BufferGeometry();
    this.sparkGeo.setAttribute('position', new THREE.BufferAttribute(this.sparkPos, 3).setUsage(THREE.DynamicDrawUsage));
    this.sparkGeo.setAttribute('rgba', new THREE.BufferAttribute(this.sparkRgba, 4).setUsage(THREE.DynamicDrawUsage));
    this.sparkGeo.setAttribute('size', new THREE.BufferAttribute(this.sparkSize, 1).setUsage(THREE.DynamicDrawUsage));
    this.sparkMat = createPointsMaterial({ additive: true, overlay: true, soft: 1 });
    this.spark = new THREE.Points(this.sparkGeo, this.sparkMat);
    this.spark.frustumCulled = false;
    this.spark.renderOrder = 60;
    const sm = this.sparkMat;
    this.spark.onBeforeRender = (renderer, _s, camera) => {
      sm.uniforms.uPxPerUnit.value = pixelsPerUnit(renderer, camera);
    };
    this.world.add(this.spark);
    this.tetherMat = createStripMaterial(color.getHex(), { overlay: true });
    this.tetherMat.uniforms.uDash.value = 0.16;
    this.tether = new THREE.Mesh(S.geo.strip, this.tetherMat);
    this.tether.renderOrder = 55;
    this.tether.frustumCulled = false;
    this.world.add(this.tether);
    this.mergeMat = createFlatMaterial(color.getHex(), { additive: true, overlay: true });
    this.merge = new THREE.Mesh(S.geo.mergeRing, this.mergeMat);
    this.merge.renderOrder = 56;
    this.world.add(this.merge);

    this.setVisible(false);
  }

  setVisible(v: boolean): void {
    this.visible = v;
    this.group.visible = v;
    if (!v) {
      this.spark.visible = false;
      this.tether.visible = false;
      this.merge.visible = false;
      for (const e of this.echoes) e.bones.root.visible = false;
      this.initialized = false;
      this.posed = false;
      this.trailCount = 0;
      this.deathT = -1;
      this.mergeT = -1;
    }
  }

  get isVisible(): boolean {
    return this.visible;
  }

  /** Current interpolated world position of the projection (for enemy target lines). */
  readonly pos = { x: 0, y: 0 };

  update(a: ActorInterp, env: SelfFrameEnv): void {
    if (!this.visible) this.setVisible(true);
    const dt = env.dt;
    const S = this.S;
    this.pos.x = a.x;
    this.pos.y = a.y;

    // ── transitions ──
    const fresh = !this.initialized || a.teleported;
    if (fresh) {
      this.prevX = a.x;
      this.prevY = a.y;
      this.prevTick = a.tick;
      this.lastLife = a.life;
      this.lastSynced = a.synced;
      this.lastAnim = a.anim;
      this.entryTick = a.tick;
      this.lastTraversal = a.traversal;
      this.blendT = 1;
      this.trailCount = 0;
      this.histFill = 0;
      if (!this.initialized) this.deathT = -1;
    }
    if (!fresh) {
      if (this.lastLife === 'alive' && a.life !== 'alive') this.startDeath(a);
      if (!this.lastSynced && a.synced) this.startMerge(a);
    }
    if (a.life === 'alive' && this.lastLife !== 'alive') this.deathT = -1;
    this.lastLife = a.life;
    this.lastSynced = a.synced;
    this.initialized = true;

    // ── locomotion measures (speed-invariant: distance per LOCAL tick) ──
    const dx = a.x - this.prevX;
    const dy = a.y - this.prevY;
    const dist = Math.hypot(dx, dy);
    const dTick = Math.abs(a.tick - this.prevTick);
    if (dTick > 1e-4) {
      const localSpeed = (dist / dTick) * LOCAL_HZ;
      this.speed += (localSpeed - this.speed) * dampFactor(14, dt);
    } else if (a.dir === 0 || a.ended) {
      this.speed += (0 - this.speed) * dampFactor(10, dt);
    }
    this.prevX = a.x;
    this.prevY = a.y;
    this.prevTick = a.tick;
    const p = this.params;
    p.time += dt;
    p.stride += (dist / STRIDE_LEN) * Math.PI * 2;
    if (p.stride > 1e4) p.stride -= Math.PI * 2 * 1000;
    p.speed = clamp01(this.speed / RUN_REF);
    p.beat = env.beatPulse;
    p.style = S.melee.style;
    const vmag = Math.hypot(a.vx, a.vy);
    if (vmag > 1e-4) {
      const cf = Math.cos(a.facing);
      const sf = Math.sin(a.facing);
      p.leanF = ((a.vx * cf + a.vy * sf) / vmag) * p.speed;
      p.leanS = ((a.vx * sf - a.vy * cf) / vmag) * p.speed;
    } else {
      p.leanF = 0;
      p.leanS = 0;
    }

    // ── pose ──
    if (a.anim !== this.lastAnim || a.traversal !== this.lastTraversal) {
      copyPose(this.pose, this.from);
      this.blendT = 0;
      this.entryTick = a.tick;
      this.lastAnim = a.anim;
      this.lastTraversal = a.traversal;
    }
    const dur = animDurationTicks(a.anim, S.melee, S.ranged);
    const t = animProgress(this.entryTick, a.tick, a.dir, dur);
    const dying = this.deathT >= 0 && this.deathT < DEATH_SECONDS;
    if (dying) {
      this.deathT += dt;
      computePose('death', this.deathT / DEATH_SECONDS, p, this.target);
      copyPose(this.target, this.pose);
    } else if (a.anim === 'stopped') {
      // Hold whatever pose the tape ended on: the self reads as paused, not idling (stop mode).
      // Seen first already stopped (e.g. a seek): there is no prior pose to hold, use the rest stance.
      if (!this.posed) computePose('stopped', 0, p, this.pose);
      this.blendT = 1;
    } else {
      computePose(a.anim, t, p, this.target);
      this.blendT = Math.min(1, this.blendT + dt / BLEND_SECONDS);
      if (this.blendT < 1) blendPose(this.from, this.target, smoothstep(0, 1, this.blendT), this.pose);
      else copyPose(this.target, this.pose);
    }
    this.posed = true;
    applyPose(this.moxie.bones, this.pose);
    // Weapon in hand only while swinging; otherwise stowed across the back (gauntlets stay worn).
    const drawn = !dying && (isMeleeState(a.anim) || S.melee.style === 'gauntlet');
    this.moxie.bones.bones.weapon.visible = drawn;
    this.moxie.bones.bones.weaponBack.visible = !drawn;
    const root = this.moxie.bones.root;
    root.rotation.y = Math.PI / 2 - a.facing;
    this.group.position.set(a.x, 0, a.y);

    // ── style ──
    const styleId: ActorStyleId = dying ? 'alive' : selectActorStyle(a.life, a.synced);
    const st = actorStyleParams(styleId);
    const flick = st.flicker > 0 ? 1 - st.flicker * (1 - flickerValue(env.time, this.seed)) : 1;
    let mode: 'solid' | 'fx' | 'hollow' = st.body === 'solid' ? 'solid' : st.body === 'hollow' ? 'hollow' : 'fx';
    let opacity = st.opacity * flick;
    if (a.iframes && st.body === 'solid') {
      // Dodge i-frames: hard flicker between two translucencies (never fully solid).
      mode = 'fx';
      opacity = flickerValue(env.time * 1.6, this.seed + 3) > 0.5 ? IFRAME_OPACITY_HIGH : IFRAME_OPACITY_LOW;
    }
    const echoes = st.chroma > 0;
    this.moxie.setMode(mode, echoes);
    const m = this.moxie.bodyMat.uniforms;
    const stopped = a.anim === 'stopped' && !dying;
    m.uOpacity.value = opacity;
    m.uDesat.value = Math.min(1, st.desat + (stopped ? STOPPED_DESAT : 0));
    m.uHolo.value = st.body === 'holo' ? 1 : 0;
    m.uPhase.value = st.body === 'phased' ? 1 : 0;
    m.uGlowMul.value = 1.5 * st.glow * (1 + env.beatPulse * 0.6) + (env.isLive ? 0.4 : 0);
    m.uRim.value = st.body === 'phased' ? 0.4 : 0.14;
    m.uRimCol.value.copy(this.color);
    // Death flash: white pop, then cassette colour, as the self "breaks".
    let flash = 0;
    if (dying) {
      const dtn = this.deathT / DEATH_SECONDS;
      flash = dtn < 0.12 ? 1 : Math.max(0, 1 - (dtn - 0.12) / 0.5) * 0.7;
      m.uFlashCol.value.copy(dtn < 0.12 ? WHITE : this.color);
    } else if (this.mergeT >= 0) {
      flash = Math.max(0, 1 - this.mergeT / 0.3) * 0.8;
      m.uFlashCol.value.copy(this.color);
    }
    m.uFlash.value = flash;
    // Hull.
    const hullCol = st.hullTapeColor ? this.color : GHOST_GREY;
    const hm = mode === 'solid' ? this.moxie.hullMat.uniforms : this.moxie.hullFxMat.uniforms;
    hm.uColor.value.copy(hullCol);
    if (stopped) hm.uColor.value.lerp(tmpColor.setRGB(0.5, 0.5, 0.5), 0.35);
    hm.uOpacity.value = st.hullOpacity * (st.body === 'solid' && !a.iframes ? 1 : flick);
    hm.uThick.value = 0.011 * st.hullScale * (env.isLive ? 1.15 : 1);
    if (echoes) {
      const j = (flickerValue(env.time * 0.7, this.seed + 7) - 0.5) * 0.02;
      const s = 0.03 * st.chroma + j;
      this.moxie.echoMatA.uniforms.uShift.value.copy(env.camRight).multiplyScalar(s);
      this.moxie.echoMatB.uniforms.uShift.value.copy(env.camRight).multiplyScalar(-s);
      this.moxie.echoMatA.uniforms.uOpacity.value = 0.32 * st.chroma * flick;
      this.moxie.echoMatB.uniforms.uOpacity.value = 0.32 * st.chroma * flick;
    }

    // ── markers ──
    const live = env.isLive;
    const ringK = st.ring * (live ? 1 : 0.75);
    this.ringMat.uniforms.uOpacity.value = 0.95 * ringK;
    this.ringInkMat.uniforms.uOpacity.value = 0.55 * ringK;
    this.discMat.uniforms.uOpacity.value = (live ? 0.24 : 0.14) * ringK;
    this.liveRing.visible = live;
    if (live) {
      const pulse = 1.15 + env.beatPulse * 0.25;
      this.liveRing.scale.set(pulse, 1, pulse);
      this.liveRingMat.uniforms.uOpacity.value = 0.25 + 0.5 * env.beatPulse;
    }
    const badgeK = Math.max(0.35, ringK);
    this.badge.position.set(-env.camFwdX * 0.42, 0.016, -env.camFwdZ * 0.42);
    this.badgeMat.uniforms.uOpacity.value = 0.85 * badgeK;
    if (this.letter && this.letterMat) {
      this.letter.position.set(-env.camFwdX * 0.42, 0.02, -env.camFwdZ * 0.42);
      this.letter.rotation.set(0, Math.atan2(-env.camFwdX, -env.camFwdZ), 0);
      this.letterMat.opacity = badgeK;
    }
    this.chevron.visible = live;
    if (live) {
      this.chevron.position.set(0, RIG.top + 0.2 + env.beatPulse * 0.06 + Math.abs(Math.sin(env.time * 3.2)) * 0.05, 0);
      this.chevron.quaternion.copy(env.camQuat);
    }
    this.halo.visible = st.marker === 'brokenHalo';
    if (this.halo.visible) {
      this.halo.position.set(0, RIG.top + 0.06 + this.pose.rootY + Math.sin(env.time * 2.3) * 0.015, 0);
      this.halo.rotation.set(0.25 + Math.sin(env.time * 1.3) * 0.08, env.time * 0.9, 0.12);
      this.haloMat.uniforms.uOpacity.value = 0.85 * flick;
    }
    this.pause.visible = stopped;
    if (stopped) {
      this.pause.position.set(0, RIG.top + 0.14, 0);
      this.pause.quaternion.copy(env.camQuat);
      this.pauseMat.uniforms.uOpacity.value = 0.6 + 0.3 * Math.sin(env.time * 2);
    }
    // Muzzle flash on the wrist device.
    const wrist = this.pose.wrist;
    this.muzzle.visible = wrist > 0.05 && !dying;
    if (this.muzzle.visible) {
      const s = 0.4 + wrist * 1.1;
      this.muzzle.scale.set(s, s, s);
      this.muzzleMat.uniforms.uOpacity.value = wrist * 0.9;
    }

    // ── swing trail ──
    const swingK = st.body === 'solid' ? 1 : st.body === 'holo' ? 0.8 : 0.35;
    this.swing.update(dying ? 'idle' : a.anim, t, dt, env.time, swingK * (0.85 + env.flourish * 0.3));

    // ── afterimages ──
    this.pushHistory(a);
    if (a.anim === 'dodge' && !dying) this.afterT = 1;
    else this.afterT = Math.max(0, this.afterT - dt * 5);
    for (let i = 0; i < AFTERIMAGES; i++) {
      const e = this.echoes[i];
      const back = (i + 1) * 3;
      const show = this.afterT > 0.01 && this.histFill > back && st.body !== 'hollow';
      e.bones.root.visible = show;
      if (!show) continue;
      const idx = (this.histHead - 1 - back + HISTORY * 4) % HISTORY;
      applyPose(e.bones, this.history[idx]);
      e.bones.bones.weapon.visible = false;
      e.bones.root.position.set(this.histX[idx], 0, this.histY[idx]);
      e.bones.root.rotation.y = Math.PI / 2 - this.histF[idx];
      e.mat.uniforms.uOpacity.value = 0.3 * this.afterT * (1 - i / AFTERIMAGES);
    }

    // ── particles: ghost dust, hologram bits ──
    if (st.trail === 'dust') {
      this.dustAcc += dist * 6 + dt * 1.5;
      let k = 0;
      while (this.dustAcc >= 1) {
        this.dustAcc -= 1;
        k++;
        const r = hash01(env.time * 91 + this.seed + k * 7.1) - 0.5;
        const r2 = hash01(env.time * 57 + this.seed * 3 + k * 3.3) - 0.5;
        S.dust.emitRaw(a.x + r * 0.25, 0.05 + Math.abs(r2) * 0.2, a.y + r2 * 0.25, -dx * 2 + r * 0.1, 0.12, -dy * 2 + r2 * 0.1, 1.1, 0.07, 2.2, DUST_GREY, 0.45, 1.5, 0);
      }
    } else this.dustAcc = 0;
    if (st.trail === 'holoBits') {
      this.bitsAcc += dt * 9 + dist * 5;
      let k = 0;
      while (this.bitsAcc >= 1) {
        this.bitsAcc -= 1;
        k++;
        const r = hash01(env.time * 71 + this.seed + k * 5.7) - 0.5;
        const r2 = hash01(env.time * 33 + this.seed * 5 + k * 2.9) - 0.5;
        const ry = hash01(env.time * 13 + this.seed + k * 1.3);
        S.glow.emitRaw(a.x + r * 0.35, 0.1 + ry * 0.8, a.y + r2 * 0.35, 0, 0.35, 0, 0.8, 0.035, 0.4, this.color, 0.8, 0, 0);
      }
    } else this.bitsAcc = 0;

    // ── death / merge timers ──
    if (this.deathT >= DEATH_SECONDS) this.deathT = -1;
    this.updateSpark(a, st.tether, env);
  }

  private startDeath(a: ActorInterp): void {
    this.deathT = 0;
    const S = this.S;
    for (let i = 0; i < 26; i++) {
      const ang = (i / 26) * Math.PI * 2 + hash01(i + this.seed) * 0.4;
      const sp = 0.9 + hash01(i * 7 + this.seed) * 1.6;
      S.glow.emit({
        x: a.x,
        y: 0.45 + hash01(i * 3 + this.seed) * 0.4,
        z: a.y,
        vx: Math.cos(ang) * sp,
        vy: 0.6 + hash01(i * 11) * 1.4,
        vz: Math.sin(ang) * sp,
        life: 0.7,
        size: 0.06,
        grow: 0.3,
        color: i % 3 === 0 ? WHITE : this.color,
        alpha: 1,
        drag: 2.5,
        gravity: 2.5,
      });
    }
  }

  private startMerge(a: ActorInterp): void {
    this.mergeT = 0;
    this.mergeX = a.x;
    this.mergeY = a.y;
    const S = this.S;
    for (let i = 0; i < 20; i++) {
      const ang = (i / 20) * Math.PI * 2;
      S.glow.emit({
        x: a.x + Math.cos(ang) * 0.1,
        y: 0.5,
        z: a.y + Math.sin(ang) * 0.1,
        vx: Math.cos(ang) * 1.8,
        vy: 0.4,
        vz: Math.sin(ang) * 1.8,
        life: 0.5,
        size: 0.05,
        grow: 0.4,
        color: i % 2 ? WHITE : this.color,
        alpha: 1,
        drag: 4,
      });
    }
  }

  private pushHistory(a: ActorInterp): void {
    const i = this.histHead;
    copyPose(this.pose, this.history[i]);
    this.histX[i] = a.x;
    this.histY[i] = a.y;
    this.histF[i] = a.facing;
    this.histHead = (i + 1) % HISTORY;
    this.histFill = Math.min(HISTORY, this.histFill + 1);
  }

  private updateSpark(a: ActorInterp, wantTether: boolean, env: SelfFrameEnv): void {
    const show = wantTether && a.hasSpark;
    this.spark.visible = show;
    this.tether.visible = show;
    if (show) {
      // Comet trail: positions sampled as the spark moves.
      const lx = this.trailCount > 0 ? this.trailX[0] : a.sparkX + 1e3;
      const lz = this.trailCount > 0 ? this.trailZ[0] : a.sparkY + 1e3;
      if (Math.hypot(a.sparkX - lx, a.sparkY - lz) > 0.04) {
        for (let i = SPARK_TRAIL - 1; i > 0; i--) {
          this.trailX[i] = this.trailX[i - 1];
          this.trailZ[i] = this.trailZ[i - 1];
        }
        this.trailX[0] = a.sparkX;
        this.trailZ[0] = a.sparkY;
        this.trailCount = Math.min(SPARK_TRAIL, this.trailCount + 1);
      }
      const h = 0.32 + Math.sin(env.time * 6) * 0.02;
      const P = this.sparkPos;
      const C = this.sparkRgba;
      const Z = this.sparkSize;
      const pulse = 0.85 + 0.15 * Math.sin(env.time * 14);
      // 0: soft glow halo; 1: hot white core.
      P[0] = a.sparkX;
      P[1] = h;
      P[2] = a.sparkY;
      C[0] = this.color.r;
      C[1] = this.color.g;
      C[2] = this.color.b;
      C[3] = 0.55;
      Z[0] = 0.42 * pulse;
      P[3] = a.sparkX;
      P[4] = h;
      P[5] = a.sparkY;
      tmpColor2.copy(this.color).lerp(WHITE, 0.65);
      C[4] = tmpColor2.r;
      C[5] = tmpColor2.g;
      C[6] = tmpColor2.b;
      C[7] = 1;
      Z[1] = 0.13;
      for (let i = 0; i < SPARK_TRAIL; i++) {
        const k = 2 + i;
        const on = i < this.trailCount;
        const f = 1 - i / SPARK_TRAIL;
        P[k * 3] = on ? this.trailX[i] : a.sparkX;
        P[k * 3 + 1] = h - (1 - f) * 0.05;
        P[k * 3 + 2] = on ? this.trailZ[i] : a.sparkY;
        C[k * 4] = this.color.r;
        C[k * 4 + 1] = this.color.g;
        C[k * 4 + 2] = this.color.b;
        C[k * 4 + 3] = on ? 0.7 * f * f : 0;
        Z[k] = 0.11 * f + 0.02;
      }
      (this.sparkGeo.getAttribute('position') as THREE.BufferAttribute).needsUpdate = true;
      (this.sparkGeo.getAttribute('rgba') as THREE.BufferAttribute).needsUpdate = true;
      (this.sparkGeo.getAttribute('size') as THREE.BufferAttribute).needsUpdate = true;
      const len = placeStrip(this.tether, a.sparkX, a.sparkY, a.x, a.y, 0.05, 0.03);
      this.tetherMat.uniforms.uLength.value = len;
      this.tetherMat.uniforms.uTime.value = env.time;
      this.tetherMat.uniforms.uOpacity.value = 0.9;
    } else {
      this.trailCount = 0;
    }
    if (this.mergeT >= 0) {
      this.mergeT += env.dt;
      const k = this.mergeT / MERGE_SECONDS;
      if (k >= 1) {
        this.mergeT = -1;
        this.merge.visible = false;
      } else {
        this.merge.visible = true;
        this.merge.position.set(this.mergeX, 0.05, this.mergeY);
        const s = 0.25 + 0.9 * Math.sqrt(k);
        this.merge.scale.set(s, 1, s);
        this.mergeMat.uniforms.uOpacity.value = (1 - k) * (0.6 + 0.4 * bump(k * 2));
      }
    }
  }

  dispose(): void {
    this.moxie.dispose();
    for (const e of this.echoes) e.dispose();
    this.swing.dispose();
    for (const mat of [
      this.ringMat,
      this.ringInkMat,
      this.discMat,
      this.liveRingMat,
      this.badgeMat,
      this.chevronMat,
      this.chevronInkMat,
      this.haloMat,
      this.pauseMat,
      this.muzzleMat,
      this.tetherMat,
      this.mergeMat,
    ])
      mat.dispose();
    this.letterMat?.dispose();
    this.sparkGeo.dispose();
    this.sparkMat.dispose();
  }
}

/** Whether a self's anim currently uses a melee swing (exported for tests/harness). */
export const selfUsesSwing = isMeleeState;
