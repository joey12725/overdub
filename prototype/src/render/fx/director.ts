/**
 * FxDirector — the CPU half of the effects layer.
 *
 * Turns RenderFrame events into pooled sprites and readouts, runs the continuous world-speed and
 * cinematic treatments, and computes the overlay state and the shake/focus requests. It owns no
 * GPU objects, so it runs (and is tested) without a WebGL context; src/render/fx/index.ts uploads
 * its pools every frame.
 *
 * Never touches simulation state and never delays anything but its own sprites: the "hit-stop" here
 * freezes the burst's particles for a few frames while the game keeps running (CINE-04, MUSIC-07).
 */
import type { ActorSnap, LevelDef, SimEvent } from '../../core/types';
import type { RenderFrame, ViewMode } from '../../contracts';
import type { ThemePalette } from '../layer';
import { EFFECT_IDS, EVENT_ROUTES, MODE_PROFILES, effectAllowed, type EffectId, type ModeProfile } from './catalog';
import { FX_HEX, TAPE_HEX, hexToRgb } from './colors';
import { Rng, hash4 } from './curves';
import { SpritePool, TextPool } from './pool';
import {
  MODE_BILLBOARD,
  MODE_FLOOR,
  MODE_STREAK,
  SHAPE_ARC,
  SHAPE_CHEVRON,
  SHAPE_CROSS,
  SHAPE_DASHRING,
  SHAPE_DEBRIS,
  SHAPE_DOT,
  SHAPE_GLITCH,
  SHAPE_GLOW,
  SHAPE_INK,
  SHAPE_RING,
  SHAPE_SHARD,
  SHAPE_SPARK,
  SHAPE_STAR,
  SHAPE_STOP,
  SHAPE_STREAK,
} from './shapes';
import {
  W_BREAK,
  W_CLANG,
  W_CLEAR,
  W_DESYNC,
  W_KO,
  W_PHASE,
  W_REMEMBERS,
  W_RESYNC,
  W_TAPE_A,
  momentumTier,
  tierWord,
} from './words';

/** Level-scoped inputs the director needs (no GPU, no scene). */
export interface FxEnv {
  palette: ThemePalette;
  level: LevelDef;
  /** Momentum of a 1× standing light attack with the current loadout (tier reference). */
  refMomentum: number;
  /** Melee reach in tiles and arc in degrees, so swing arcs match the real hit volume. */
  meleeReach: number;
  meleeArcDeg: number;
  quality: 'low' | 'high';
}

export const GLOW_CAPACITY = 1536;
export const INK_CAPACITY = 384;
export const TEXT_CAPACITY = 48;
export const RIBBON_POINTS = 40;
/** Max new readouts per frame: a skipped review can flush hundreds of events at once. */
const WORDS_PER_FRAME = 6;

/** Height of impact effects above the floor (roughly Moxie's chest). */
const H_IMPACT = 0.8;
const H_FLOOR = 0.035;
const H_WORD = 1.55;

/** Sprite tags for continuous (non-event) treatments, outside the EFFECT_IDS index range. */
export const TAG_WORLD_SPEED = 250;
/** Continuous cinematic flourishes (beat ripples); only ever spawned in cinematic mode. */
export const TAG_CINE_CONTINUOUS = 251;

const EFFECT_INDEX: Record<EffectId, number> = (() => {
  const m = {} as Record<EffectId, number>;
  for (let i = 0; i < EFFECT_IDS.length; i++) m[EFFECT_IDS[i]] = i;
  return m;
})();

/** Camera-space overlay state (letterbox, flashes, world-speed tint, speed lines, sweep, glitch). */
export class ScreenFx {
  letterbox = 0;
  flash = new Float32Array(3);
  flashA = 0;
  tint = new Float32Array(3);
  tintA = 0;
  /** World-speed speed lines 0..1 and sign (+1 world sped up, -1 world slowed). */
  speed = 0;
  speedSign = 0;
  /** Bar-synced light sweep: position 0..1 across the screen and strength. */
  sweepPos = 0;
  sweepA = 0;
  /** Radial speed-line burst around a world point (cinematic impacts). */
  burst = new Float32Array(3);
  burstAmt = 0;
  /** Glitch tear strength and colour (desync, boss recall). */
  glitch = 0;
  glitchColor = new Float32Array(3);
  time = 0;
}

/** Per-tape colour ribbons for the cinematic (four performances read as four voices). */
export class RibbonTrails {
  readonly pts = new Float32Array(4 * RIBBON_POINTS * 3);
  readonly head = new Int32Array(4);
  readonly count = new Int32Array(4);
  /** Current visibility 0..1 (eases in and out). */
  readonly alpha = new Float32Array(4);
  /** 1 when the self is a ghost (fainter), 2 when desynced (flickers), 0 alive. */
  readonly state = new Uint8Array(4);
  readonly present = new Uint8Array(4);
  readonly lastX = new Float32Array(4);
  readonly lastZ = new Float32Array(4);
  sampleTimer = 0;

  reset(t: number): void {
    this.count[t] = 0;
    this.head[t] = 0;
  }

  push(t: number, x: number, y: number, z: number): void {
    const h = this.head[t];
    const o = (t * RIBBON_POINTS + h) * 3;
    this.pts[o] = x;
    this.pts[o + 1] = y;
    this.pts[o + 2] = z;
    this.head[t] = (h + 1) % RIBBON_POINTS;
    if (this.count[t] < RIBBON_POINTS) this.count[t]++;
  }

  /** k-th point from oldest (0) to newest (count-1). */
  pointIndex(t: number, k: number): number {
    const start = (this.head[t] - this.count[t] + RIBBON_POINTS) % RIBBON_POINTS;
    return (t * RIBBON_POINTS + ((start + k) % RIBBON_POINTS)) * 3;
  }
}

export class FxDirector {
  readonly glow: SpritePool;
  readonly ink: SpritePool;
  readonly text: TextPool;
  readonly screen = new ScreenFx();
  readonly ribbons = new RibbonTrails();
  /** How many times each effect (index into EFFECT_IDS) was triggered since load. */
  readonly spawnCounts = new Int32Array(EFFECT_IDS.length);

  /** Shake requested this frame (0..1, already scaled by mode). */
  shakeOut = 0;
  /** Cinematic focus request: world point (sim axes) and weight; weight 0 means none. */
  focusX = 0;
  focusY = 0;
  focusW = 0;

  /** Smoothed signed world-speed amount (-1 slowed … +1 sped up). */
  worldSpeed = 0;
  mode: ViewMode = 'idle';

  private env: FxEnv;
  private readonly rng = new Rng(1);
  private readonly c = new Float32Array(3);
  private readonly tmp = new Float32Array(3);
  private tag = 0;
  private alphaK = 1;
  private countK = 1;
  private wordsThisFrame = 0;
  private prof: ModeProfile = MODE_PROFILES.idle;
  private lastMasterBeat = NaN;
  private lastMusicBeat = NaN;
  private lastChord = NaN;
  private smearTimer = 0;

  constructor(env: FxEnv) {
    this.env = env;
    const low = env.quality === 'low';
    this.glow = new SpritePool(low ? GLOW_CAPACITY >> 1 : GLOW_CAPACITY);
    this.ink = new SpritePool(low ? INK_CAPACITY >> 1 : INK_CAPACITY);
    this.text = new TextPool(TEXT_CAPACITY);
  }

  setQuality(q: 'low' | 'high'): void {
    this.env.quality = q;
  }

  update(frame: RenderFrame): void {
    const dt = Math.min(0.1, Math.max(0, frame.dt));
    const prof = MODE_PROFILES[frame.mode] ?? MODE_PROFILES.idle;
    this.mode = frame.mode;
    this.prof = prof;
    this.screen.time += dt;
    this.shakeOut = 0;
    this.wordsThisFrame = 0;
    this.alphaK = Math.min(1.1, 0.55 + 0.45 * prof.intensity);
    this.countK = prof.intensity * (this.env.quality === 'low' ? 0.6 : 1);

    if (prof.events) {
      const evs = frame.events;
      for (let i = 0; i < evs.length; i++) this.dispatch(evs[i], frame.mode);
    }

    const wr = frame.worldRate > 0 && Number.isFinite(frame.worldRate) ? frame.worldRate : 1;
    // World-attached effects run a little slower in a slowed world and faster in a sped one, so the
    // sparks themselves carry the tape speed; the square root keeps them readable at 0.25×/4×.
    const fxRate = Math.min(2, Math.max(0.5, Math.sqrt(wr)));

    this.updateWorldSpeed(frame, prof, wr, fxRate, dt);
    this.updateMusicFlourishes(frame, dt, fxRate);
    this.updateRibbons(frame, dt);
    this.updateFocus(frame, dt);
    this.decayScreen(dt);

    this.glow.update(dt * fxRate);
    this.ink.update(dt * fxRate);
    // Readouts live on wall time: they are text to be read, not part of the world.
    this.text.update(dt);
  }

  /** Remove every transient effect (used on level load / mode resets). */
  clear(): void {
    this.glow.clear();
    this.ink.clear();
    this.text.clear();
    for (let t = 0; t < 4; t++) this.ribbons.reset(t);
    this.screen.flashA = 0;
    this.screen.burstAmt = 0;
    this.screen.glitch = 0;
    this.focusW = 0;
  }

  // ───────────────────────────── routing ─────────────────────────────

  private dispatch(ev: SimEvent, mode: ViewMode): void {
    const routes = EVENT_ROUTES[ev.type];
    // An event type from a newer sim build without a route is ignored rather than crashing a frame.
    if (!routes) return;
    for (let r = 0; r < routes.length; r++) {
      const id = routes[r];
      if (!effectAllowed(id, mode)) continue;
      this.tag = EFFECT_INDEX[id];
      this.spawnCounts[this.tag]++;
      this.rng.seed(hash4(ev.sub, this.tag, Math.round(ev.x * 16), Math.round(ev.y * 16)));
      this.run(id, ev);
    }
  }

  private run(id: EffectId, ev: SimEvent): void {
    switch (id) {
      case 'hitBurst':
        return this.hitBurst(ev, 1);
      case 'hitStreaks':
        return this.hitStreaks(ev);
      case 'tierWord':
        return this.tierWordFx(ev);
      case 'killBurst':
        return this.killBurst(ev);
      case 'killWord':
        this.colorTape(ev.tape, this.env.palette.hazard);
        this.whiten(0.15);
        this.word(W_KO, ev.x, H_WORD + 0.15, ev.y, 0.55, 1.0, 0.09, 0.9);
        return;
      case 'debris':
        return this.debris(ev);
      case 'breakWord':
        this.colorHex(this.env.palette.hazard);
        this.word(W_BREAK, ev.x, H_WORD + 0.1, ev.y, 0.5, 1.0, 0.08, 0.9);
        return;
      case 'clangSpark':
        return this.clangSpark(ev);
      case 'clangTell':
        return this.clangTell(ev);
      case 'swingArc':
        return this.swingArc(ev);
      case 'whiffPuff':
        return this.whiffPuff(ev);
      case 'dodgeAfterimage':
        return this.dodgeAfterimage(ev);
      case 'muzzleFlash':
        return this.muzzle(ev, ev.tape !== undefined ? TAPE_HEX[ev.tape] : FX_HEX.white, 0.5);
      case 'projectileImpact':
        return this.hitBurst(ev, 0.75);
      case 'interactPing':
        return this.interactPing(ev);
      case 'interactFail':
        return this.interactFail(ev);
      case 'doorPulse':
        return this.doorPulse(ev);
      case 'platePulse':
        return this.platePulse(ev);
      case 'laserPulse':
        return this.laserPulse(ev);
      case 'coreIgnite':
        return this.coreIgnite(ev);
      case 'deathShatter':
        return this.deathShatter(ev);
      case 'tapeLetter':
        return this.tapeLetter(ev);
      case 'desyncTear':
        return this.desyncTear(ev);
      case 'resyncConverge':
        return this.resyncConverge(ev);
      case 'wrapBlink':
        return this.wrapBlink(ev);
      case 'turnChevrons':
        return this.turnChevrons(ev);
      case 'endStop':
        return this.endStop(ev);
      case 'telegraphRing':
        return this.telegraphRing(ev);
      case 'enemySlash':
        return this.enemySlash(ev);
      case 'enemyMuzzle':
        return this.muzzle(ev, this.env.palette.neonB, 0.42);
      case 'staggerStars':
        return this.staggerStars(ev);
      case 'bossShock':
        return this.bossShock(ev);
      case 'bossRecallTell':
        return this.bossRecallTell(ev);
      case 'objectivePulse':
        return this.objectivePulse(ev);
      case 'stepDust':
        return this.stepDust(ev);
      case 'impactDust':
        return this.impactDust(ev);
      case 'inkSplash':
        return this.inkSplash(ev);
      case 'speedLineBurst':
        return this.speedLineBurst(ev);
      case 'cineEcho':
        return this.cineEcho(ev);
      case 'cineFocus':
        return this.cineFocus(ev);
      case 'finaleBurst':
        return this.finaleBurst(ev);
    }
  }

  // ───────────────────────────── helpers ─────────────────────────────

  private colorHex(hex: number): void {
    hexToRgb(hex, this.c);
  }

  private colorTape(tape: number | undefined, fallback: number): void {
    hexToRgb(tape !== undefined && tape >= 0 && tape < 4 ? TAPE_HEX[tape] : fallback, this.c);
  }

  private whiten(k: number): void {
    const c = this.c;
    c[0] += (1 - c[0]) * k;
    c[1] += (1 - c[1]) * k;
    c[2] += (1 - c[2]) * k;
  }

  private darken(k: number): void {
    const c = this.c;
    c[0] *= 1 - k;
    c[1] *= 1 - k;
    c[2] *= 1 - k;
  }

  private n(count: number): number {
    return Math.max(1, Math.round(count * this.countK));
  }

  /** Momentum relative to a 1× standing light blow. */
  private ratio(ev: SimEvent): number {
    const p = ev.power;
    if (p === undefined || !Number.isFinite(p)) return 1;
    return Math.max(0, p) / (this.env.refMomentum > 1e-6 ? this.env.refMomentum : 1);
  }

  private requestShake(m: number): void {
    const s = Math.min(1, m * this.prof.shake);
    if (s > this.shakeOut) this.shakeOut = s;
  }

  private emit(
    pool: SpritePool,
    shape: number,
    mode: number,
    x: number,
    y: number,
    z: number,
    s0: number,
    s1: number,
    life: number,
    alpha: number,
  ): number {
    const i = pool.spawn(this.tag);
    const i3 = i * 3;
    pool.pos[i3] = x;
    pool.pos[i3 + 1] = y;
    pool.pos[i3 + 2] = z;
    pool.color[i3] = this.c[0];
    pool.color[i3 + 1] = this.c[1];
    pool.color[i3 + 2] = this.c[2];
    pool.alpha[i] = alpha * this.alphaK;
    pool.size0[i] = s0;
    pool.size1[i] = s1;
    pool.life[i] = life;
    pool.shape[i] = shape;
    pool.mode[i] = mode;
    return i;
  }

  private setVel(pool: SpritePool, i: number, vx: number, vy: number, vz: number): void {
    const i3 = i * 3;
    pool.vel[i3] = vx;
    pool.vel[i3 + 1] = vy;
    pool.vel[i3 + 2] = vz;
  }

  private setDir(pool: SpritePool, i: number, dx: number, dy: number, dz: number, stretch: number): void {
    const i4 = i * 4;
    pool.dir[i4] = dx;
    pool.dir[i4 + 1] = dy;
    pool.dir[i4 + 2] = dz;
    pool.dir[i4 + 3] = stretch;
  }

  /** Spawn a readout in the current colour. Returns -1 when the frame's word budget is spent. */
  private word(w: number, x: number, y: number, z: number, height: number, life: number, freeze: number, pop: number): number {
    if (this.wordsThisFrame >= WORDS_PER_FRAME || this.prof.textScale <= 0) return -1;
    this.wordsThisFrame++;
    const t = this.text;
    const i = t.spawn(this.tag, w);
    const i3 = i * 3;
    t.pos[i3] = x + this.rng.sym(0.12);
    t.pos[i3 + 1] = y;
    t.pos[i3 + 2] = z + this.rng.sym(0.12);
    t.tint[i3] = this.c[0];
    t.tint[i3 + 1] = this.c[1];
    t.tint[i3 + 2] = this.c[2];
    t.height[i] = height * this.prof.textScale;
    t.life[i] = life;
    t.freeze[i] = freeze;
    t.pop[i] = pop;
    // A slight hand-set tilt reads as inked lettering rather than UI text.
    t.rot[i] = this.rng.sym(0.14);
    return i;
  }

  private dirOf(ev: SimEvent): number {
    return ev.dir !== undefined && Number.isFinite(ev.dir) ? ev.dir : this.rng.next() * Math.PI * 2;
  }

  /** Sparks flying from (x, y, z) in a cone around angle `a` (sim/XZ plane). */
  private sparks(count: number, x: number, y: number, z: number, a: number, spread: number, speed: number, size: number, life: number, freeze: number, gravity: number): void {
    const pool = this.glow;
    for (let k = 0; k < count; k++) {
      const ang = a + this.rng.sym(spread);
      const sp = speed * this.rng.range(0.55, 1.1);
      const vy = sp * this.rng.range(-0.15, 0.45);
      const vx = Math.cos(ang) * sp;
      const vz = Math.sin(ang) * sp;
      const i = this.emit(pool, SHAPE_STREAK, MODE_STREAK, x, y, z, size, size * 0.5, life * this.rng.range(0.7, 1.2), 1);
      this.setVel(pool, i, vx, vy, vz);
      const inv = 1 / Math.max(1e-4, Math.hypot(vx, vy, vz));
      this.setDir(pool, i, vx * inv, vy * inv, vz * inv, this.rng.range(3, 5.5));
      pool.drag[i] = 5;
      pool.gravity[i] = gravity;
      pool.freeze[i] = freeze;
    }
  }

  // ───────────────────────────── effects ─────────────────────────────

  private hitBurst(ev: SimEvent, scale: number): void {
    const r = this.ratio(ev);
    const tier = momentumTier(ev.power ?? this.env.refMomentum, this.env.refMomentum);
    const s = (0.6 + 0.4 * Math.sqrt(Math.min(6, r))) * scale;
    const freeze = 0.035 + 0.022 * tier;
    const x = ev.x;
    const z = ev.y;
    this.colorTape(ev.tape, FX_HEX.white);
    this.whiten(0.55);
    let i = this.emit(this.glow, SHAPE_GLOW, MODE_BILLBOARD, x, H_IMPACT, z, 0.55 * s, 1.0 * s, 0.2, 0.95);
    this.glow.freeze[i] = freeze;
    this.colorTape(ev.tape, FX_HEX.white);
    i = this.emit(this.glow, SHAPE_RING, MODE_BILLBOARD, x, H_IMPACT, z, 0.3 * s, 1.5 * s, 0.28, 0.85);
    this.glow.param[i] = 0.14;
    this.glow.freeze[i] = freeze;
    i = this.emit(this.glow, SHAPE_SPARK, MODE_BILLBOARD, x, H_IMPACT, z, 0.9 * s, 0.4 * s, 0.14, 1);
    this.glow.rot[i] = this.rng.next() * Math.PI;
    this.glow.freeze[i] = freeze;
    this.whiten(0.3);
    const a = this.dirOf(ev);
    this.sparks(this.n(5 + 3 * tier), x, H_IMPACT, z, a, 0.9, 5 + 1.6 * tier, 0.07 * s, 0.3, freeze, 4);
    if (tier >= 1) this.requestShake(0.06 + 0.06 * Math.min(6, r));
  }

  private hitStreaks(ev: SimEvent): void {
    const tier = momentumTier(ev.power ?? this.env.refMomentum, this.env.refMomentum);
    const a = this.dirOf(ev);
    const dx = Math.cos(a);
    const dz = Math.sin(a);
    this.colorTape(ev.tape, FX_HEX.white);
    this.whiten(0.4);
    const count = this.n(2 + tier);
    for (let k = 0; k < count; k++) {
      const off = this.rng.sym(0.35);
      const px = ev.x - dz * off + dx * this.rng.range(0.1, 0.5);
      const pz = ev.y + dx * off + dz * this.rng.range(0.1, 0.5);
      const sp = 10 + 3 * tier;
      const i = this.emit(this.glow, SHAPE_STREAK, MODE_STREAK, px, H_IMPACT + this.rng.sym(0.25), pz, 0.05, 0.03, 0.16, 0.9);
      this.setVel(this.glow, i, dx * sp, 0, dz * sp);
      this.setDir(this.glow, i, dx, 0, dz, 10 + 2 * tier);
      this.glow.drag[i] = 8;
      this.glow.freeze[i] = 0.03 + 0.02 * tier;
    }
  }

  private tierWordFx(ev: SimEvent): void {
    const tier = momentumTier(ev.power ?? this.env.refMomentum, this.env.refMomentum);
    if (tier < this.prof.minWordTier) return;
    if (tier === 0) {
      this.colorHex(0xd8d8d8);
    } else {
      this.colorTape(ev.tape, FX_HEX.white);
      this.whiten(0.1);
    }
    this.word(tierWord(tier), ev.x, H_WORD, ev.y, 0.34 + 0.08 * tier, 0.75 + 0.1 * tier, 0.035 + 0.022 * tier, 0.55 + 0.15 * tier);
  }

  private killBurst(ev: SimEvent): void {
    this.hitBurst(ev, 1.35);
    const x = ev.x;
    const z = ev.y;
    const a = this.dirOf(ev);
    // Ink shards: the anime "shatter" read of a defeat, in the theme's ink so they read on any floor.
    this.colorHex(this.env.palette.ink);
    const count = this.n(7);
    for (let k = 0; k < count; k++) {
      const ang = a + this.rng.sym(1.4);
      const sp = this.rng.range(2.5, 5.5);
      const i = this.emit(this.ink, SHAPE_SHARD, MODE_BILLBOARD, x, H_IMPACT, z, this.rng.range(0.1, 0.2), 0.08, this.rng.range(0.5, 0.8), 0.9);
      this.setVel(this.ink, i, Math.cos(ang) * sp, this.rng.range(1.5, 4), Math.sin(ang) * sp);
      this.ink.gravity[i] = 12;
      this.ink.floorY[i] = 0.05;
      this.ink.rot[i] = this.rng.next() * 6.283;
      this.ink.rotVel[i] = this.rng.sym(14);
      this.ink.fadePow[i] = 2;
    }
    this.colorTape(ev.tape, this.env.palette.hazard);
    const i = this.emit(this.glow, SHAPE_RING, MODE_FLOOR, x, H_FLOOR, z, 0.4, 2.2, 0.45, 0.7);
    this.glow.param[i] = 0.08;
    this.requestShake(0.32);
  }

  private debris(ev: SimEvent): void {
    const pal = this.env.palette;
    const a = this.dirOf(ev);
    const count = this.n(14);
    for (let k = 0; k < count; k++) {
      this.colorHex(k % 3 === 0 ? pal.wallTop : pal.wall);
      const ang = a + this.rng.sym(1.2);
      const sp = this.rng.range(2, 6);
      const i = this.emit(this.ink, SHAPE_DEBRIS, MODE_BILLBOARD, ev.x + this.rng.sym(0.4), this.rng.range(0.3, 1.2), ev.y + this.rng.sym(0.4), this.rng.range(0.12, 0.26), 0.1, this.rng.range(1.1, 1.6), 1);
      this.setVel(this.ink, i, Math.cos(ang) * sp, this.rng.range(2, 5.5), Math.sin(ang) * sp);
      this.ink.gravity[i] = 14;
      this.ink.floorY[i] = 0.08;
      this.ink.rot[i] = this.rng.next() * 6.283;
      this.ink.rotVel[i] = this.rng.sym(10);
      this.ink.fadePow[i] = 4;
      this.ink.freeze[i] = 0.06;
    }
    this.colorHex(FX_HEX.dust);
    for (let k = 0; k < this.n(6); k++) {
      const i = this.emit(this.ink, SHAPE_GLOW, MODE_BILLBOARD, ev.x + this.rng.sym(0.6), this.rng.range(0.2, 0.9), ev.y + this.rng.sym(0.6), 0.4, 1.3, this.rng.range(0.7, 1.0), 0.2);
      this.setVel(this.ink, i, this.rng.sym(0.8), 0.4, this.rng.sym(0.8));
      this.ink.drag[i] = 2;
    }
    this.colorHex(pal.hazard);
    this.whiten(0.4);
    const i = this.emit(this.glow, SHAPE_GLOW, MODE_BILLBOARD, ev.x, H_IMPACT, ev.y, 1.0, 1.8, 0.22, 0.8);
    this.glow.freeze[i] = 0.06;
    this.requestShake(0.45);
  }

  private clangSpark(ev: SimEvent): void {
    // Deliberately dull: few, slow, grey sparks that drop, with no flash ring and no freeze, so a
    // blow without enough momentum (Scenario K) never reads as a real hit.
    this.colorHex(FX_HEX.clang);
    const a = this.dirOf(ev) + Math.PI;
    this.sparks(this.n(6), ev.x, H_IMPACT, ev.y, a, 1.3, 2.6, 0.05, 0.3, 0, 10);
    const i = this.emit(this.glow, SHAPE_GLOW, MODE_BILLBOARD, ev.x, H_IMPACT, ev.y, 0.3, 0.35, 0.12, 0.35);
    this.glow.fadePow[i] = 2;
  }

  private clangTell(ev: SimEvent): void {
    this.colorHex(FX_HEX.clang);
    // An inward-collapsing dashed ring: the force bounced off instead of radiating out.
    let i = this.emit(this.glow, SHAPE_DASHRING, MODE_BILLBOARD, ev.x, H_IMPACT, ev.y, 1.1, 0.35, 0.38, 0.75);
    this.glow.param[i] = 0.12;
    // A sagging down-chevron: "not enough".
    i = this.emit(this.glow, SHAPE_CHEVRON, MODE_BILLBOARD, ev.x, H_IMPACT + 0.55, ev.y, 0.22, 0.2, 0.5, 0.8);
    this.glow.rot[i] = -Math.PI / 2;
    this.setVel(this.glow, i, 0, -0.6, 0);
    this.colorHex(0xb9c0c8);
    this.word(W_CLANG, ev.x, H_WORD - 0.1, ev.y, 0.34, 0.8, 0, 0.25);
  }

  private swingArc(ev: SimEvent): void {
    const heavy = ev.detail === 'heavy';
    const reach = this.env.meleeReach > 0 ? this.env.meleeReach : 1.2;
    const half = ((this.env.meleeArcDeg > 0 ? this.env.meleeArcDeg : 120) * Math.PI) / 360;
    this.colorTape(ev.tape, FX_HEX.white);
    this.whiten(0.2);
    const s = reach / 0.78;
    const i = this.emit(this.glow, SHAPE_ARC, MODE_FLOOR, ev.x, H_FLOOR + 0.01, ev.y, s * 0.85, s, heavy ? 0.22 : 0.15, heavy ? 0.6 : 0.45);
    this.glow.param[i] = half;
    this.glow.rot[i] = this.dirOf(ev);
  }

  private whiffPuff(ev: SimEvent): void {
    const a = this.dirOf(ev);
    this.colorHex(FX_HEX.dust);
    for (let k = 0; k < this.n(3); k++) {
      const d = this.rng.range(0.5, 1.0);
      const i = this.emit(this.ink, SHAPE_GLOW, MODE_BILLBOARD, ev.x + Math.cos(a) * d, this.rng.range(0.4, 0.9), ev.y + Math.sin(a) * d, 0.18, 0.45, 0.32, 0.25);
      this.setVel(this.ink, i, Math.cos(a) * 0.6, 0.3, Math.sin(a) * 0.6);
    }
  }

  private dodgeAfterimage(ev: SimEvent): void {
    const a = this.dirOf(ev);
    const dx = Math.cos(a);
    const dz = Math.sin(a);
    this.colorTape(ev.tape, FX_HEX.white);
    for (let k = 0; k < 3; k++) {
      const back = 0.2 + k * 0.25;
      const i = this.emit(this.glow, SHAPE_STREAK, MODE_STREAK, ev.x - dx * back, 0.35 + k * 0.3, ev.y - dz * back, 0.12, 0.05, 0.25, 0.45);
      this.setDir(this.glow, i, dx, 0, dz, 6);
      this.setVel(this.glow, i, -dx * 1.5, 0, -dz * 1.5);
    }
    const i = this.emit(this.glow, SHAPE_GLOW, MODE_FLOOR, ev.x, H_FLOOR, ev.y, 0.5, 0.9, 0.3, 0.3);
    this.glow.rot[i] = a;
  }

  private muzzle(ev: SimEvent, hex: number, size: number): void {
    const a = this.dirOf(ev);
    const dx = Math.cos(a);
    const dz = Math.sin(a);
    const x = ev.x + dx * 0.5;
    const z = ev.y + dz * 0.5;
    this.colorHex(hex);
    this.whiten(0.35);
    const i = this.emit(this.glow, SHAPE_STAR, MODE_BILLBOARD, x, H_IMPACT, z, size, size * 0.6, 0.11, 1);
    this.glow.rot[i] = this.rng.next() * 6.283;
    for (let k = 0; k < this.n(3); k++) {
      const j = this.emit(this.glow, SHAPE_STREAK, MODE_STREAK, x, H_IMPACT, z, 0.05, 0.03, 0.12, 0.8);
      const ang = a + this.rng.sym(0.3);
      this.setVel(this.glow, j, Math.cos(ang) * 7, 0, Math.sin(ang) * 7);
      this.setDir(this.glow, j, Math.cos(ang), 0, Math.sin(ang), 5);
      this.glow.drag[j] = 10;
    }
  }

  private interactPing(ev: SimEvent): void {
    this.colorTape(ev.tape, FX_HEX.white);
    const i = this.emit(this.glow, SHAPE_RING, MODE_FLOOR, ev.x, H_FLOOR, ev.y, 0.2, 1.0, 0.42, 0.75);
    this.glow.param[i] = 0.12;
    const j = this.emit(this.glow, SHAPE_DOT, MODE_BILLBOARD, ev.x, 0.9, ev.y, 0.16, 0.08, 0.45, 0.9);
    this.setVel(this.glow, j, 0, 1.6, 0);
  }

  private interactFail(ev: SimEvent): void {
    this.colorHex(FX_HEX.clang);
    const i = this.emit(this.glow, SHAPE_CROSS, MODE_BILLBOARD, ev.x, 1.25, ev.y, 0.32, 0.26, 0.45, 0.8);
    this.glow.fadePow[i] = 0.6;
  }

  private doorPulse(ev: SimEvent): void {
    const open = ev.detail === 'on' || ev.detail === 'open';
    this.colorHex(open ? this.env.palette.hazard : this.env.palette.neonB);
    const i = this.emit(this.glow, SHAPE_RING, MODE_FLOOR, ev.x, H_FLOOR, ev.y, 0.4, 1.6, 0.5, 0.55);
    this.glow.param[i] = 0.1;
    this.colorHex(FX_HEX.dust);
    for (let k = 0; k < this.n(4); k++) {
      const j = this.emit(this.ink, SHAPE_GLOW, MODE_BILLBOARD, ev.x + this.rng.sym(0.5), 0.15, ev.y + this.rng.sym(0.5), 0.25, 0.7, 0.6, 0.22);
      this.setVel(this.ink, j, this.rng.sym(0.6), 0.5, this.rng.sym(0.6));
    }
  }

  private platePulse(ev: SimEvent): void {
    const on = ev.detail !== 'off';
    this.colorHex(on ? this.env.palette.hazard : FX_HEX.clang);
    const i = this.emit(this.glow, SHAPE_RING, MODE_FLOOR, ev.x, H_FLOOR, ev.y, on ? 0.3 : 0.9, on ? 1.1 : 0.4, 0.4, on ? 0.7 : 0.4);
    this.glow.param[i] = 0.12;
  }

  private laserPulse(ev: SimEvent): void {
    const on = ev.detail !== 'off';
    this.colorHex(this.env.palette.neonB);
    const i = this.emit(this.glow, SHAPE_GLOW, MODE_BILLBOARD, ev.x, 0.6, ev.y, on ? 0.5 : 0.4, on ? 0.9 : 0.1, on ? 0.25 : 0.3, on ? 0.8 : 0.4);
    this.glow.fadePow[i] = 1.5;
    if (on) {
      const j = this.emit(this.glow, SHAPE_RING, MODE_BILLBOARD, ev.x, 0.6, ev.y, 0.2, 0.8, 0.22, 0.6);
      this.glow.param[j] = 0.15;
    }
  }

  private coreIgnite(ev: SimEvent): void {
    const pal = this.env.palette;
    this.colorHex(pal.neonA);
    this.whiten(0.3);
    let i = this.emit(this.glow, SHAPE_STREAK, MODE_STREAK, ev.x, 1.4, ev.y, 0.35, 0.2, 0.7, 0.9);
    this.setDir(this.glow, i, 0, 1, 0, 9);
    this.glow.fadePow[i] = 0.7;
    i = this.emit(this.glow, SHAPE_RING, MODE_FLOOR, ev.x, H_FLOOR, ev.y, 0.4, 2.8, 0.7, 0.8);
    this.glow.param[i] = 0.06;
    this.emit(this.glow, SHAPE_GLOW, MODE_BILLBOARD, ev.x, 0.9, ev.y, 0.8, 1.8, 0.35, 0.9);
    this.sparks(this.n(14), ev.x, 0.9, ev.y, 0, Math.PI, 6, 0.06, 0.45, 0.05, 3);
    this.requestShake(0.3);
  }

  private deathShatter(ev: SimEvent): void {
    this.colorTape(ev.tape, FX_HEX.white);
    const count = this.n(10);
    for (let k = 0; k < count; k++) {
      const ang = this.rng.next() * 6.283;
      const sp = this.rng.range(1.5, 4);
      const i = this.emit(this.glow, SHAPE_SHARD, MODE_BILLBOARD, ev.x, this.rng.range(0.4, 1.2), ev.y, this.rng.range(0.1, 0.18), 0.05, this.rng.range(0.6, 0.9), 0.9);
      this.setVel(this.glow, i, Math.cos(ang) * sp, this.rng.range(1, 3.5), Math.sin(ang) * sp);
      this.glow.gravity[i] = 7;
      this.glow.rot[i] = ang;
      this.glow.rotVel[i] = this.rng.sym(9);
      this.glow.freeze[i] = 0.08;
    }
    // The self leaves a rising wisp in its colour: it becomes a ghost, it does not vanish (GHOST-05).
    let i = this.emit(this.glow, SHAPE_GLOW, MODE_BILLBOARD, ev.x, 1.0, ev.y, 0.5, 0.25, 0.9, 0.7);
    this.setVel(this.glow, i, 0, 1.3, 0);
    this.glow.fadeIn[i] = 0.1;
    i = this.emit(this.glow, SHAPE_DASHRING, MODE_FLOOR, ev.x, H_FLOOR, ev.y, 0.3, 1.6, 0.6, 0.6);
    this.glow.param[i] = 0.08;
    this.requestShake(0.35);
  }

  private tapeLetter(ev: SimEvent): void {
    if (ev.tape === undefined) return;
    let x = ev.x;
    let z = ev.y;
    if (ev.type === 'tapeWrap') {
      // The self reappears at the start position, so its letter does too.
      x = this.env.level.start.x;
      z = this.env.level.start.y;
    }
    this.colorTape(ev.tape, FX_HEX.white);
    this.word(W_TAPE_A + ev.tape, x, H_WORD + 0.2, z, 0.62, 0.8, 0, 0.5);
  }

  private desyncTear(ev: SimEvent): void {
    this.colorTape(ev.tape, FX_HEX.recall);
    for (let k = 0; k < 3; k++) {
      // Translucent so the desynced projection underneath stays readable (UI-03).
      const i = this.emit(this.glow, SHAPE_GLITCH, MODE_BILLBOARD, ev.x + this.rng.sym(0.2), 0.6 + k * 0.35, ev.y + this.rng.sym(0.2), this.rng.range(0.55, 0.85), 0.8, 0.45, 0.42);
      this.glow.param[i] = this.rng.next() * 100;
    }
    this.screenGlitch(0.55);
    this.word(W_DESYNC, ev.x, H_WORD, ev.y, 0.36, 0.95, 0, 0.45);
  }

  private resyncConverge(ev: SimEvent): void {
    this.colorTape(ev.tape, FX_HEX.white);
    const count = this.n(12);
    const life = 0.32;
    for (let k = 0; k < count; k++) {
      const ang = (k / count) * 6.283 + this.rng.sym(0.2);
      const r = 1.4;
      const i = this.emit(this.glow, SHAPE_DOT, MODE_BILLBOARD, ev.x + Math.cos(ang) * r, H_IMPACT + this.rng.sym(0.3), ev.y + Math.sin(ang) * r, 0.12, 0.08, life, 0.95);
      this.setVel(this.glow, i, (-Math.cos(ang) * r) / life, 0, (-Math.sin(ang) * r) / life);
    }
    let i = this.emit(this.glow, SHAPE_RING, MODE_BILLBOARD, ev.x, H_IMPACT, ev.y, 1.6, 0.2, life, 0.7);
    this.glow.param[i] = 0.1;
    // The convergence flash blooms as the motes arrive.
    this.whiten(0.5);
    i = this.emit(this.glow, SHAPE_GLOW, MODE_BILLBOARD, ev.x, H_IMPACT, ev.y, 0.3, 1.5, 0.55, 0.9);
    this.glow.age[i] = -life * 0.85;
    this.glow.fadeIn[i] = 0.05;
    this.colorTape(ev.tape, FX_HEX.white);
    const w = this.word(W_RESYNC, ev.x, H_WORD, ev.y, 0.36, 0.95, 0, 0.6);
    if (w >= 0) this.text.age[w] = -life * 0.8;
  }

  private wrapBlink(ev: SimEvent): void {
    this.colorTape(ev.tape, FX_HEX.white);
    // Blink out where the tape ran out…
    let i = this.emit(this.glow, SHAPE_DASHRING, MODE_BILLBOARD, ev.x, H_IMPACT, ev.y, 0.9, 0.2, 0.25, 0.7);
    this.glow.param[i] = 0.12;
    this.emit(this.glow, SHAPE_GLOW, MODE_BILLBOARD, ev.x, H_IMPACT, ev.y, 0.6, 0.1, 0.2, 0.5);
    // …and cut back in at the start position (PLAY 'repeat': a hard cut, never a slide).
    const sx = this.env.level.start.x;
    const sz = this.env.level.start.y;
    this.whiten(0.3);
    i = this.emit(this.glow, SHAPE_GLOW, MODE_BILLBOARD, sx, H_IMPACT, sz, 1.0, 0.5, 0.22, 0.9);
    this.glow.fadeIn[i] = 0.03;
    i = this.emit(this.glow, SHAPE_RING, MODE_FLOOR, sx, H_FLOOR, sz, 0.2, 1.3, 0.4, 0.7);
    this.glow.param[i] = 0.1;
  }

  private turnChevrons(ev: SimEvent): void {
    // Reverse: chevrons pointing back along the path the tape will now retrace.
    const back = this.dirOf(ev) + Math.PI;
    const dx = Math.cos(back);
    const dz = Math.sin(back);
    this.colorTape(ev.tape, FX_HEX.white);
    for (let k = 0; k < 3; k++) {
      const d = 0.35 + k * 0.38;
      const i = this.emit(this.glow, SHAPE_CHEVRON, MODE_FLOOR, ev.x + dx * d, H_FLOOR + 0.01, ev.y + dz * d, 0.32, 0.3, 0.45, 0.85);
      this.glow.rot[i] = back;
      this.glow.age[i] = -0.07 * k;
      this.setVel(this.glow, i, dx * 0.8, 0, dz * 0.8);
    }
  }

  private endStop(ev: SimEvent): void {
    this.colorTape(ev.tape, FX_HEX.white);
    const i = this.emit(this.glow, SHAPE_STOP, MODE_BILLBOARD, ev.x, 1.35, ev.y, 0.4, 0.34, 0.9, 0.85);
    this.glow.fadePow[i] = 0.5;
    const j = this.emit(this.glow, SHAPE_RING, MODE_FLOOR, ev.x, H_FLOOR, ev.y, 0.9, 0.5, 0.35, 0.5);
    this.glow.param[j] = 0.1;
  }

  private telegraphRing(ev: SimEvent): void {
    // Complements the actor layer's telegraph, never replaces it: a charging ring that tightens
    // onto the enemy plus a faint wedge toward the attack direction.
    this.colorHex(this.env.palette.hazard);
    let i = this.emit(this.glow, SHAPE_RING, MODE_FLOOR, ev.x, H_FLOOR, ev.y, 1.5, 0.6, 0.35, 0.5);
    this.glow.param[i] = 0.08;
    this.glow.fadeIn[i] = 0.08;
    if (ev.dir !== undefined) {
      i = this.emit(this.glow, SHAPE_ARC, MODE_FLOOR, ev.x, H_FLOOR, ev.y, 1.0, 1.1, 0.35, 0.3);
      this.glow.param[i] = 0.6;
      this.glow.rot[i] = ev.dir;
    }
  }

  private enemySlash(ev: SimEvent): void {
    this.colorHex(FX_HEX.enemy);
    const a = this.dirOf(ev);
    const i = this.emit(this.glow, SHAPE_ARC, MODE_FLOOR, ev.x, H_FLOOR + 0.02, ev.y, 1.0, 1.25, 0.18, 0.65);
    this.glow.param[i] = 0.9;
    this.glow.rot[i] = a;
    this.whiten(0.3);
    this.sparks(this.n(3), ev.x + Math.cos(a) * 0.6, H_IMPACT, ev.y + Math.sin(a) * 0.6, a, 0.5, 6, 0.05, 0.15, 0, 0);
  }

  private staggerStars(ev: SimEvent): void {
    this.colorHex(this.env.palette.hazard);
    for (let k = 0; k < 3; k++) {
      const ang = (k / 3) * 6.283;
      const i = this.emit(this.glow, SHAPE_STAR, MODE_BILLBOARD, ev.x + Math.cos(ang) * 0.35, 1.45, ev.y + Math.sin(ang) * 0.35, 0.18, 0.12, 0.6, 0.85);
      this.setVel(this.glow, i, -Math.sin(ang) * 1.4, 0.2, Math.cos(ang) * 1.4);
      this.glow.drag[i] = 1.5;
      this.glow.rotVel[i] = 6;
    }
  }

  private bossShock(ev: SimEvent): void {
    const pal = this.env.palette;
    this.colorHex(pal.neonC);
    let i = this.emit(this.glow, SHAPE_RING, MODE_FLOOR, ev.x, H_FLOOR, ev.y, 1.0, 5.5, 0.75, 0.85);
    this.glow.param[i] = 0.05;
    i = this.emit(this.glow, SHAPE_RING, MODE_FLOOR, ev.x, H_FLOOR, ev.y, 0.6, 3.5, 0.6, 0.6);
    this.glow.param[i] = 0.1;
    this.glow.age[i] = -0.1;
    this.whiten(0.4);
    this.emit(this.glow, SHAPE_GLOW, MODE_BILLBOARD, ev.x, 1.2, ev.y, 1.4, 2.6, 0.4, 0.8);
    this.flash(pal.neonC, 0.12);
    this.colorHex(pal.neonC);
    this.whiten(0.2);
    this.word(W_PHASE, ev.x, H_WORD + 0.9, ev.y, 0.5, 1.2, 0.1, 0.8);
    this.requestShake(0.75);
  }

  private bossRecallTell(ev: SimEvent): void {
    // "It remembers": unmistakable and different from every other tell — rewind chevrons collapse
    // onto the boss, an eye opens above it, the screen tears in the remembered tape's colour.
    const hex = ev.tape !== undefined ? TAPE_HEX[ev.tape] : FX_HEX.recall;
    this.colorHex(hex);
    let i = this.emit(this.glow, SHAPE_RING, MODE_FLOOR, ev.x, H_FLOOR, ev.y, 3.2, 0.9, 0.55, 0.75);
    this.glow.param[i] = 0.07;
    const n = 6;
    for (let k = 0; k < n; k++) {
      const ang = (k / n) * 6.283;
      const r = 2.6;
      i = this.emit(this.glow, SHAPE_CHEVRON, MODE_FLOOR, ev.x + Math.cos(ang) * r, H_FLOOR + 0.01, ev.y + Math.sin(ang) * r, 0.34, 0.26, 0.5, 0.85);
      this.glow.rot[i] = ang + Math.PI;
      this.setVel(this.glow, i, -Math.cos(ang) * 3.4, 0, -Math.sin(ang) * 3.4);
      this.glow.age[i] = -0.03 * k;
    }
    i = this.emit(this.glow, SHAPE_RING, MODE_BILLBOARD, ev.x, 2.2, ev.y, 0.2, 0.6, 0.85, 0.95);
    this.glow.param[i] = 0.22;
    this.glow.fadePow[i] = 0.5;
    this.whiten(0.5);
    i = this.emit(this.glow, SHAPE_DOT, MODE_BILLBOARD, ev.x, 2.2, ev.y, 0.18, 0.22, 0.85, 1);
    this.glow.fadePow[i] = 0.5;
    this.colorHex(hex);
    for (let k = 0; k < 2; k++) {
      i = this.emit(this.glow, SHAPE_GLITCH, MODE_BILLBOARD, ev.x, 1.7 + k * 0.5, ev.y, 1.0, 1.1, 0.5, 0.38);
      this.glow.param[i] = this.rng.next() * 100;
    }
    hexToRgb(hex, this.tmp);
    this.screenGlitchColor(this.tmp, 0.7);
    this.flash(hex, 0.08);
    this.colorHex(hex);
    this.whiten(0.15);
    this.word(W_REMEMBERS, ev.x, 2.75, ev.y, 0.38, 1.3, 0.06, 0.5);
    if (ev.tape !== undefined) this.word(W_TAPE_A + ev.tape, ev.x + 0.9, 2.25, ev.y, 0.4, 1.3, 0.06, 0.5);
    this.requestShake(0.25);
  }

  private objectivePulse(ev: SimEvent): void {
    const pal = this.env.palette;
    this.colorHex(pal.hazard);
    this.whiten(0.3);
    let i = this.emit(this.glow, SHAPE_RING, MODE_FLOOR, ev.x, H_FLOOR, ev.y, 0.5, 3.2, 0.8, 0.8);
    this.glow.param[i] = 0.06;
    i = this.emit(this.glow, SHAPE_GLOW, MODE_BILLBOARD, ev.x, 1.0, ev.y, 0.8, 1.6, 0.4, 0.8);
    this.colorHex(pal.hazard);
    this.word(W_CLEAR, ev.x, H_WORD + 0.5, ev.y, this.mode === 'cinematic' ? 0.7 : 0.5, 1.6, 0.12, 0.9);
  }

  private stepDust(ev: SimEvent): void {
    this.colorHex(FX_HEX.dust);
    const i = this.emit(this.ink, SHAPE_GLOW, MODE_BILLBOARD, ev.x, 0.06, ev.y, 0.12, 0.32, 0.35, 0.18);
    this.setVel(this.ink, i, this.rng.sym(0.3), 0.25, this.rng.sym(0.3));
  }

  private impactDust(ev: SimEvent): void {
    this.colorHex(FX_HEX.dust);
    const i = this.emit(this.ink, SHAPE_RING, MODE_FLOOR, ev.x, H_FLOOR, ev.y, 0.3, 1.3, 0.45, 0.3);
    this.ink.param[i] = 0.2;
  }

  private inkSplash(ev: SimEvent): void {
    // Impact freeze-frame: an ink splash painted on the floor UNDER the impact (never over the
    // actors), held still for a beat-fraction, then fading.
    const r = this.ratio(ev);
    const s = 0.55 + 0.25 * Math.sqrt(Math.min(6, r));
    this.colorHex(this.env.palette.ink);
    let i = this.emit(this.ink, SHAPE_INK, MODE_FLOOR, ev.x, H_FLOOR - 0.005, ev.y, s * 0.6, s, 1.3, 0.6);
    this.ink.param[i] = this.rng.next() * 50;
    this.ink.rot[i] = this.rng.next() * 6.283;
    this.ink.freeze[i] = 0.09;
    this.ink.fadePow[i] = 3;
    const a = this.dirOf(ev);
    for (let k = 0; k < this.n(4); k++) {
      const ang = a + this.rng.sym(0.7);
      const d = s * this.rng.range(0.9, 1.6);
      i = this.emit(this.ink, SHAPE_INK, MODE_FLOOR, ev.x + Math.cos(ang) * d, H_FLOOR - 0.004, ev.y + Math.sin(ang) * d, 0.08, 0.14, 1.2, 0.6);
      this.ink.param[i] = this.rng.next() * 50;
      this.ink.freeze[i] = 0.09;
      this.ink.fadePow[i] = 3;
    }
    this.colorTape(ev.tape, this.env.palette.hazard);
    i = this.emit(this.glow, SHAPE_RING, MODE_FLOOR, ev.x, H_FLOOR + 0.004, ev.y, s * 0.8, s * 1.3, 0.5, 0.5);
    this.glow.param[i] = 0.05;
    this.glow.freeze[i] = 0.09;
  }

  private speedLineBurst(ev: SimEvent): void {
    const tier = momentumTier(ev.power ?? this.env.refMomentum, this.env.refMomentum);
    const amt = ev.type === 'hit' ? 0.25 + 0.15 * tier : 0.85;
    // Small hits don't get a radial burst; it would make every tap look like a finisher.
    if (amt < 0.5) return;
    const sc = this.screen;
    if (amt >= sc.burstAmt * 0.8) {
      sc.burst[0] = ev.x;
      sc.burst[1] = H_IMPACT;
      sc.burst[2] = ev.y;
      sc.burstAmt = Math.max(sc.burstAmt, Math.min(1, amt));
    }
  }

  private cineEcho(ev: SimEvent): void {
    this.colorTape(ev.tape, FX_HEX.white);
    const i = this.emit(this.glow, SHAPE_DASHRING, MODE_FLOOR, ev.x, H_FLOOR, ev.y, 0.5, 2.4, 0.6, 0.6);
    this.glow.param[i] = 0.06;
    this.glow.rotVel[i] = ev.type === 'desync' ? -2 : 2;
  }

  private cineFocus(ev: SimEvent): void {
    let w = 0.5;
    switch (ev.type) {
      case 'objective':
        w = 1;
        break;
      case 'bossPhase':
        w = 0.8;
        break;
      case 'bossRecall':
        w = 0.7;
        break;
      case 'kill':
        w = 0.55;
        break;
      case 'resync':
      case 'core':
      case 'break':
        w = 0.5;
        break;
      case 'selfDeath':
        w = 0.45;
        break;
      default:
        w = 0.4;
    }
    if (w >= this.focusW * 0.8) {
      this.focusX = ev.x;
      this.focusY = ev.y;
      this.focusW = Math.max(w, this.focusW * 0.8);
    }
  }

  private finaleBurst(ev: SimEvent): void {
    // Four rings in the four cassette colours: the voices resolving together.
    for (let t = 0; t < 4; t++) {
      this.colorHex(TAPE_HEX[t]);
      const i = this.emit(this.glow, SHAPE_RING, MODE_FLOOR, ev.x, H_FLOOR + 0.004 * t, ev.y, 0.5, 4 + t * 0.9, 1.0, 0.8);
      this.glow.param[i] = 0.05;
      this.glow.age[i] = -0.09 * t;
      this.whiten(0.25);
      this.sparks(this.n(10), ev.x, 1.0, ev.y, (t / 4) * 6.283, 1.2, 8, 0.07, 0.7, 0.06, 5);
    }
    this.colorHex(this.env.palette.ink);
    for (let k = 0; k < this.n(14); k++) {
      const ang = this.rng.next() * 6.283;
      const sp = this.rng.range(3, 7);
      const i = this.emit(this.ink, SHAPE_SHARD, MODE_BILLBOARD, ev.x, 1.0, ev.y, this.rng.range(0.12, 0.24), 0.08, this.rng.range(0.8, 1.2), 0.85);
      this.setVel(this.ink, i, Math.cos(ang) * sp, this.rng.range(2, 6), Math.sin(ang) * sp);
      this.ink.gravity[i] = 10;
      this.ink.floorY[i] = 0.05;
      this.ink.rotVel[i] = this.rng.sym(12);
    }
    this.flash(0xffffff, 0.22);
    this.screen.burst[0] = ev.x;
    this.screen.burst[1] = 1;
    this.screen.burst[2] = ev.y;
    this.screen.burstAmt = 1;
    this.requestShake(0.6);
  }

  // ───────────────────────────── screen helpers ─────────────────────────────

  private flash(hex: number, a: number): void {
    const sc = this.screen;
    const aa = a * this.alphaK;
    if (aa >= sc.flashA) {
      hexToRgb(hex, sc.flash);
      sc.flashA = aa;
    }
  }

  private screenGlitch(a: number): void {
    this.screenGlitchColor(this.c, a);
  }

  private screenGlitchColor(rgb: Float32Array, a: number): void {
    const sc = this.screen;
    const aa = a * this.alphaK;
    if (aa >= sc.glitch) {
      sc.glitchColor[0] = rgb[0];
      sc.glitchColor[1] = rgb[1];
      sc.glitchColor[2] = rgb[2];
      sc.glitch = aa;
    }
  }

  private decayScreen(dt: number): void {
    const sc = this.screen;
    sc.flashA *= Math.exp(-dt * 3.5);
    sc.burstAmt *= Math.exp(-dt * 3.2);
    sc.glitch *= Math.exp(-dt * 4.5);
    if (sc.flashA < 0.002) sc.flashA = 0;
    if (sc.burstAmt < 0.01) sc.burstAmt = 0;
    if (sc.glitch < 0.01) sc.glitch = 0;
    const target = this.prof.letterbox;
    // Letterbox eases in over ~a second (and back out when the cinematic ends).
    sc.letterbox += (target - sc.letterbox) * (1 - Math.exp(-dt * 2.5));
    if (Math.abs(sc.letterbox - target) < 1e-4) sc.letterbox = target;
  }

  // ───────────────────────────── continuous treatments ─────────────────────────────

  private findActive(frame: RenderFrame): ActorSnap | null {
    const actors = frame.snap.actors;
    if (frame.active !== null) {
      for (let i = 0; i < actors.length; i++) if (actors[i].tape === frame.active) return actors[i];
    }
    for (let i = 0; i < actors.length; i++) if (actors[i].live) return actors[i];
    return null;
  }

  private updateWorldSpeed(frame: RenderFrame, prof: ModeProfile, wr: number, fxRate: number, dt: number): void {
    const target = prof.worldSpeed * Math.max(-1, Math.min(1, Math.log2(wr) / 2));
    this.worldSpeed += (target - this.worldSpeed) * (1 - Math.exp(-dt * 4));
    if (Math.abs(this.worldSpeed) < 1e-4) this.worldSpeed = 0;
    const ws = this.worldSpeed;
    const amt = Math.abs(ws);
    const sc = this.screen;
    hexToRgb(ws < 0 ? FX_HEX.slowWorld : FX_HEX.fastWorld, sc.tint);
    sc.tintA = amt * 0.07;
    sc.speed = amt;
    sc.speedSign = ws < 0 ? -1 : ws > 0 ? 1 : 0;

    const beat = frame.snap.beat;
    const mb = Math.floor(beat);
    const prevMb = this.lastMasterBeat;
    this.lastMasterBeat = mb;
    if (amt < 0.08 || !prof.events || prevMb !== prevMb || mb <= prevMb || mb - prevMb > 4) return;

    // Time-ripple: one floor ring per MASTER beat from the active self, expanding over one master
    // beat of wall time — slow, lazy rings in a slowed world, quick ones in a sped-up world.
    const actor = this.findActive(frame);
    if (actor) {
      this.tag = TAG_WORLD_SPEED;
      hexToRgb(ws < 0 ? FX_HEX.slowWorld : FX_HEX.fastWorld, this.c);
      const beatWall = 60 / Math.max(1, this.env.level.bpm) / wr;
      const i = this.emit(this.glow, SHAPE_RING, MODE_FLOOR, actor.x, H_FLOOR - 0.01, actor.y, 0.5, 3.2, beatWall * fxRate, 0.12 + 0.18 * amt);
      this.glow.param[i] = 0.04;
      this.glow.fadePow[i] = 1.5;
    }

    // Motion smear: when the world runs fast around a slow tape, moving enemies leave faint streaks.
    if (ws > 0.15) {
      this.smearTimer += dt;
      if (this.smearTimer >= 0.05) {
        this.smearTimer = 0;
        this.smear(frame, ws);
      }
    }
  }

  private smear(frame: RenderFrame, ws: number): void {
    const en = frame.snap.enemies;
    const pe = frame.prev.enemies;
    hexToRgb(FX_HEX.fastWorld, this.c);
    this.tag = TAG_WORLD_SPEED;
    const lim = Math.min(16, en.length);
    for (let i = 0; i < lim; i++) {
      const e = en[i];
      if (!e.alive) continue;
      const p = i < pe.length && pe[i].id === e.id ? pe[i] : null;
      if (!p) continue;
      const dx = e.x - p.x;
      const dz = e.y - p.y;
      const d = Math.hypot(dx, dz);
      if (d < 0.002 || d > 2) continue;
      const k = this.emit(this.glow, SHAPE_STREAK, MODE_STREAK, e.x - (dx / d) * 0.35, 0.6, e.y - (dz / d) * 0.35, 0.18, 0.1, 0.2, 0.22 * ws);
      this.setDir(this.glow, k, dx / d, 0, dz / d, 4);
    }
  }

  private updateMusicFlourishes(frame: RenderFrame, dt: number, fxRate: number): void {
    const m = frame.music;
    const sc = this.screen;
    const cine = frame.mode === 'cinematic';
    const chord = m.chord;
    const prevChord = this.lastChord;
    this.lastChord = chord;
    const beat = Math.floor(m.beat);
    const prevBeat = this.lastMusicBeat;
    this.lastMusicBeat = beat;

    if (cine) {
      // Bar-synced light sweep across the frame.
      const barPos = m.beat / 4 - Math.floor(m.beat / 4);
      sc.sweepPos = barPos;
      sc.sweepA = 0.03 + 0.05 * m.barPulse;
    } else {
      sc.sweepA *= Math.exp(-dt * 6);
    }

    if (!cine) return;

    // Chord-change palette flash, drawn from the level theme's own neon/accent colours.
    if (prevChord === prevChord && chord !== prevChord) {
      const pal = this.env.palette;
      const idx = ((Math.round(chord) % 4) + 4) % 4;
      const hex = idx === 0 ? pal.neonA : idx === 1 ? pal.neonB : idx === 2 ? pal.neonC : pal.hazard;
      this.flash(hex, 0.1);
    }

    // Beat-synced floor ripples under every living, synced self, in its tape colour.
    if (prevBeat === prevBeat && beat > prevBeat && beat - prevBeat <= 2) {
      const bar = beat % 4 === 0;
      const actors = frame.snap.actors;
      this.tag = TAG_CINE_CONTINUOUS;
      for (let i = 0; i < actors.length; i++) {
        const a = actors[i];
        if (a.life !== 'alive') continue;
        hexToRgb(TAPE_HEX[a.tape], this.c);
        const lv = m.levels[a.tape] ?? 0;
        const k = this.emit(this.glow, SHAPE_RING, MODE_FLOOR, a.x, H_FLOOR - 0.008, a.y, 0.3, bar ? 1.9 : 1.1, 0.5 * fxRate, 0.22 + 0.2 * lv + (bar ? 0.15 : 0));
        this.glow.param[k] = 0.06;
      }
    }
  }

  private updateRibbons(frame: RenderFrame, dt: number): void {
    const rb = this.ribbons;
    const cine = frame.mode === 'cinematic';
    const actors = frame.snap.actors;
    const prev = frame.prev.actors;
    rb.present.fill(0);
    rb.sampleTimer += dt;
    const sample = rb.sampleTimer >= 1 / 30;
    if (sample) rb.sampleTimer = 0;
    for (let i = 0; i < actors.length; i++) {
      const a = actors[i];
      const t = a.tape;
      if (t < 0 || t > 3) continue;
      rb.present[t] = 1;
      let x = a.x;
      let z = a.y;
      for (let j = 0; j < prev.length; j++) {
        const p = prev[j];
        if (p.tape !== t) continue;
        if (Math.abs(p.x - a.x) + Math.abs(p.y - a.y) < 3) {
          x = p.x + (a.x - p.x) * frame.alpha;
          z = p.y + (a.y - p.y) * frame.alpha;
        }
        break;
      }
      rb.state[t] = a.life !== 'alive' ? 1 : a.synced ? 0 : 2;
      const target = cine ? (a.life === 'alive' ? 1 : 0.35) : 0;
      rb.alpha[t] += (target - rb.alpha[t]) * (1 - Math.exp(-dt * 3));
      if (!cine) {
        if (rb.alpha[t] < 0.01) rb.reset(t);
        continue;
      }
      // A 'repeat' cut teleports the self: break the ribbon instead of drawing a line across the room.
      if (rb.count[t] > 0 && Math.abs(x - rb.lastX[t]) + Math.abs(z - rb.lastZ[t]) > 2.5) rb.reset(t);
      if (sample || rb.count[t] === 0) rb.push(t, x, 0.045, z);
      else {
        // Keep the newest point glued to the self between samples.
        const o = rb.pointIndex(t, rb.count[t] - 1);
        rb.pts[o] = x;
        rb.pts[o + 2] = z;
      }
      rb.lastX[t] = x;
      rb.lastZ[t] = z;
    }
    for (let t = 0; t < 4; t++) {
      if (!rb.present[t]) {
        rb.alpha[t] *= Math.exp(-dt * 4);
        if (rb.alpha[t] < 0.01) rb.reset(t);
      }
    }
  }

  private updateFocus(frame: RenderFrame, dt: number): void {
    if (frame.mode !== 'cinematic') {
      this.focusW = 0;
      return;
    }
    this.focusW *= Math.exp(-dt * 0.9);
    // The boss is always worth a glance when nothing louder is happening.
    const en = frame.snap.enemies;
    for (let i = 0; i < en.length; i++) {
      const e = en[i];
      if (e.type === 'boss' && e.alive && this.focusW < 0.25) {
        this.focusX = e.x;
        this.focusY = e.y;
        this.focusW = 0.25;
        break;
      }
    }
    if (this.focusW < 0.02) this.focusW = 0;
  }
}
