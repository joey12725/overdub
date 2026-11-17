/**
 * Fixed-capacity particle and readout pools.
 *
 * Plain typed arrays (struct of arrays) so they are testable without a WebGL context and so the
 * steady state allocates nothing: spawning takes a slot from a free stack, and when the pool is
 * full the slot closest to the end of its life is recycled instead of growing.
 */

/** Recycle the alive slot with the highest age/life fraction (the one closest to vanishing). */
function stealSlot(alive: Uint8Array, age: Float32Array, life: Float32Array, capacity: number): number {
  let best = 0;
  let bestT = -1;
  for (let i = 0; i < capacity; i++) {
    if (!alive[i]) return i;
    const t = age[i] / (life[i] > 1e-6 ? life[i] : 1e-6);
    if (t > bestT) {
      bestT = t;
      best = i;
    }
  }
  return best;
}

export class SpritePool {
  readonly capacity: number;
  readonly pos: Float32Array;
  readonly vel: Float32Array;
  /** World direction for streaks (xyz) and streak length factor (w). */
  readonly dir: Float32Array;
  readonly color: Float32Array;
  readonly alpha: Float32Array;
  readonly size0: Float32Array;
  readonly size1: Float32Array;
  readonly life: Float32Array;
  readonly age: Float32Array;
  /** Seconds the sprite stays frozen at its first frame (the effect's own hit-stop). */
  readonly freeze: Float32Array;
  readonly gravity: Float32Array;
  /** Exponential velocity damping per second. */
  readonly drag: Float32Array;
  readonly rot: Float32Array;
  readonly rotVel: Float32Array;
  /** Shape parameter (ring thickness, arc half-width, ink seed…). */
  readonly param: Float32Array;
  readonly fadeIn: Float32Array;
  /** Exponent of the fade-out curve: <1 holds longer, >1 fades sooner. */
  readonly fadePow: Float32Array;
  /** Floor height the sprite bounces on when it has gravity (debris). NaN disables bouncing. */
  readonly floorY: Float32Array;
  readonly shape: Uint8Array;
  readonly mode: Uint8Array;
  /** Which effect spawned the sprite (index into EFFECT_IDS); used by tests and debugging. */
  readonly tag: Uint8Array;
  readonly alive: Uint8Array;
  private readonly freeStack: Int32Array;
  private freeTop: number;
  private live = 0;

  constructor(capacity: number) {
    this.capacity = capacity;
    this.pos = new Float32Array(capacity * 3);
    this.vel = new Float32Array(capacity * 3);
    this.dir = new Float32Array(capacity * 4);
    this.color = new Float32Array(capacity * 3);
    this.alpha = new Float32Array(capacity);
    this.size0 = new Float32Array(capacity);
    this.size1 = new Float32Array(capacity);
    this.life = new Float32Array(capacity);
    this.age = new Float32Array(capacity);
    this.freeze = new Float32Array(capacity);
    this.gravity = new Float32Array(capacity);
    this.drag = new Float32Array(capacity);
    this.rot = new Float32Array(capacity);
    this.rotVel = new Float32Array(capacity);
    this.param = new Float32Array(capacity);
    this.fadeIn = new Float32Array(capacity);
    this.fadePow = new Float32Array(capacity);
    this.floorY = new Float32Array(capacity);
    this.shape = new Uint8Array(capacity);
    this.mode = new Uint8Array(capacity);
    this.tag = new Uint8Array(capacity);
    this.alive = new Uint8Array(capacity);
    this.freeStack = new Int32Array(capacity);
    this.freeTop = 0;
    this.clear();
  }

  /** Number of live sprites. */
  get count(): number {
    return this.live;
  }

  clear(): void {
    this.alive.fill(0);
    this.live = 0;
    // Pop order 0, 1, 2… so slot reuse is predictable.
    for (let i = 0; i < this.capacity; i++) this.freeStack[i] = this.capacity - 1 - i;
    this.freeTop = this.capacity;
  }

  /** Take a slot (recycling the oldest when full) and reset it to defaults. */
  spawn(tag: number): number {
    let i: number;
    if (this.freeTop > 0) {
      i = this.freeStack[--this.freeTop];
      this.live++;
    } else {
      i = stealSlot(this.alive, this.age, this.life, this.capacity);
    }
    this.alive[i] = 1;
    this.tag[i] = tag;
    const i3 = i * 3;
    const i4 = i * 4;
    this.pos[i3] = this.pos[i3 + 1] = this.pos[i3 + 2] = 0;
    this.vel[i3] = this.vel[i3 + 1] = this.vel[i3 + 2] = 0;
    this.dir[i4] = 1;
    this.dir[i4 + 1] = 0;
    this.dir[i4 + 2] = 0;
    this.dir[i4 + 3] = 1;
    this.color[i3] = this.color[i3 + 1] = this.color[i3 + 2] = 1;
    this.alpha[i] = 1;
    this.size0[i] = this.size1[i] = 0.3;
    this.life[i] = 0.5;
    this.age[i] = 0;
    this.freeze[i] = 0;
    this.gravity[i] = 0;
    this.drag[i] = 0;
    this.rot[i] = 0;
    this.rotVel[i] = 0;
    this.param[i] = 0;
    this.fadeIn[i] = 0;
    this.fadePow[i] = 1;
    this.floorY[i] = NaN;
    this.shape[i] = 0;
    this.mode[i] = 0;
    return i;
  }

  kill(i: number): void {
    if (!this.alive[i]) return;
    this.alive[i] = 0;
    this.freeStack[this.freeTop++] = i;
    this.live--;
  }

  /** Advance every live sprite by dt seconds of effect time. */
  update(dt: number): void {
    if (this.live === 0) return;
    for (let i = 0; i < this.capacity; i++) {
      if (!this.alive[i]) continue;
      if (this.freeze[i] > 0) {
        this.freeze[i] -= dt;
        continue;
      }
      const age = this.age[i] + dt;
      if (age >= this.life[i]) {
        this.kill(i);
        continue;
      }
      this.age[i] = age;
      // Negative age is a spawn delay (staggered chevrons, finale rings): hold still until born.
      if (age < 0) continue;
      const i3 = i * 3;
      if (this.drag[i] > 0) {
        const k = Math.exp(-this.drag[i] * dt);
        this.vel[i3] *= k;
        this.vel[i3 + 1] *= k;
        this.vel[i3 + 2] *= k;
      }
      this.vel[i3 + 1] -= this.gravity[i] * dt;
      this.pos[i3] += this.vel[i3] * dt;
      this.pos[i3 + 1] += this.vel[i3 + 1] * dt;
      this.pos[i3 + 2] += this.vel[i3 + 2] * dt;
      const fy = this.floorY[i];
      if (fy === fy && this.pos[i3 + 1] < fy) {
        this.pos[i3 + 1] = fy;
        this.vel[i3 + 1] = -this.vel[i3 + 1] * 0.35;
        this.vel[i3] *= 0.6;
        this.vel[i3 + 2] *= 0.6;
        this.rotVel[i] *= 0.5;
      }
      this.rot[i] += this.rotVel[i] * dt;
    }
  }

  /**
   * Pack live sprites into instance arrays for the GPU. Returns the instance count.
   *   posSize: x, y, z, size        color: r, g, b, a
   *   dir:     dx, dy, dz, stretch  params: shape + 32·mode, param, rot, t (0..1 life fraction)
   */
  writeInstances(posSize: Float32Array, color: Float32Array, dir: Float32Array, params: Float32Array): number {
    let n = 0;
    for (let i = 0; i < this.capacity; i++) {
      if (!this.alive[i] || this.age[i] < 0) continue;
      const life = this.life[i] > 1e-6 ? this.life[i] : 1e-6;
      const t = Math.min(1, this.age[i] / life);
      const frozen = this.freeze[i] > 0;
      const fin = frozen || this.fadeIn[i] <= 0 ? 1 : Math.min(1, this.age[i] / this.fadeIn[i]);
      const a = this.alpha[i] * fin * Math.pow(1 - t, this.fadePow[i]);
      if (a <= 0.002) continue;
      const e = 1 - (1 - t) * (1 - t);
      const size = this.size0[i] + (this.size1[i] - this.size0[i]) * e;
      const i3 = i * 3;
      const i4 = i * 4;
      const o = n * 4;
      posSize[o] = this.pos[i3];
      posSize[o + 1] = this.pos[i3 + 1];
      posSize[o + 2] = this.pos[i3 + 2];
      posSize[o + 3] = size;
      color[o] = this.color[i3];
      color[o + 1] = this.color[i3 + 1];
      color[o + 2] = this.color[i3 + 2];
      color[o + 3] = a;
      dir[o] = this.dir[i4];
      dir[o + 1] = this.dir[i4 + 1];
      dir[o + 2] = this.dir[i4 + 2];
      dir[o + 3] = this.dir[i4 + 3];
      params[o] = this.shape[i] + 32 * this.mode[i];
      params[o + 1] = this.param[i];
      params[o + 2] = this.rot[i];
      params[o + 3] = t;
      n++;
    }
    return n;
  }
}

/** Floating world-space words (tier readouts, CLANG, DESYNC, tape letters…). */
export class TextPool {
  readonly capacity: number;
  readonly pos: Float32Array;
  readonly vel: Float32Array;
  readonly tint: Float32Array;
  /** World height of the word at rest. */
  readonly height: Float32Array;
  readonly life: Float32Array;
  readonly age: Float32Array;
  readonly freeze: Float32Array;
  readonly rot: Float32Array;
  /** Extra scale at birth that settles quickly (the "pop"). */
  readonly pop: Float32Array;
  readonly alpha: Float32Array;
  readonly word: Uint8Array;
  readonly tag: Uint8Array;
  readonly alive: Uint8Array;
  private readonly freeStack: Int32Array;
  private freeTop: number;
  private live = 0;

  constructor(capacity: number) {
    this.capacity = capacity;
    this.pos = new Float32Array(capacity * 3);
    this.vel = new Float32Array(capacity * 3);
    this.tint = new Float32Array(capacity * 3);
    this.height = new Float32Array(capacity);
    this.life = new Float32Array(capacity);
    this.age = new Float32Array(capacity);
    this.freeze = new Float32Array(capacity);
    this.rot = new Float32Array(capacity);
    this.pop = new Float32Array(capacity);
    this.alpha = new Float32Array(capacity);
    this.word = new Uint8Array(capacity);
    this.tag = new Uint8Array(capacity);
    this.alive = new Uint8Array(capacity);
    this.freeStack = new Int32Array(capacity);
    this.freeTop = 0;
    this.clear();
  }

  get count(): number {
    return this.live;
  }

  clear(): void {
    this.alive.fill(0);
    this.live = 0;
    for (let i = 0; i < this.capacity; i++) this.freeStack[i] = this.capacity - 1 - i;
    this.freeTop = this.capacity;
  }

  spawn(tag: number, word: number): number {
    let i: number;
    if (this.freeTop > 0) {
      i = this.freeStack[--this.freeTop];
      this.live++;
    } else {
      i = stealSlot(this.alive, this.age, this.life, this.capacity);
    }
    this.alive[i] = 1;
    this.tag[i] = tag;
    this.word[i] = word;
    const i3 = i * 3;
    this.pos[i3] = this.pos[i3 + 1] = this.pos[i3 + 2] = 0;
    this.vel[i3] = 0;
    this.vel[i3 + 1] = 0.55;
    this.vel[i3 + 2] = 0;
    this.tint[i3] = this.tint[i3 + 1] = this.tint[i3 + 2] = 1;
    this.height[i] = 0.5;
    this.life[i] = 0.9;
    this.age[i] = 0;
    this.freeze[i] = 0;
    this.rot[i] = 0;
    this.pop[i] = 0.6;
    this.alpha[i] = 1;
    return i;
  }

  kill(i: number): void {
    if (!this.alive[i]) return;
    this.alive[i] = 0;
    this.freeStack[this.freeTop++] = i;
    this.live--;
  }

  update(dt: number): void {
    if (this.live === 0) return;
    for (let i = 0; i < this.capacity; i++) {
      if (!this.alive[i]) continue;
      if (this.freeze[i] > 0) {
        this.freeze[i] -= dt;
        continue;
      }
      const age = this.age[i] + dt;
      if (age >= this.life[i]) {
        this.kill(i);
        continue;
      }
      this.age[i] = age;
      if (age < 0) continue;
      const i3 = i * 3;
      // Words decelerate as they rise so they settle readable instead of flying off.
      const k = Math.exp(-2.5 * dt);
      this.vel[i3] *= k;
      this.vel[i3 + 1] *= k;
      this.vel[i3 + 2] *= k;
      this.pos[i3] += this.vel[i3] * dt;
      this.pos[i3 + 1] += this.vel[i3 + 1] * dt;
      this.pos[i3 + 2] += this.vel[i3 + 2] * dt;
    }
  }

  /**
   * posSize: x, y, z, height    color: r, g, b, a    params: word, rot, 0, 0
   */
  writeInstances(posSize: Float32Array, color: Float32Array, params: Float32Array): number {
    let n = 0;
    for (let i = 0; i < this.capacity; i++) {
      if (!this.alive[i] || this.age[i] < 0) continue;
      const t = Math.min(1, this.age[i] / Math.max(1e-6, this.life[i]));
      const frozen = this.freeze[i] > 0;
      // Pop: start oversized, overshoot slightly below rest, settle (anime impact-frame feel).
      const settle = frozen ? 1 : Math.exp(-this.age[i] * 13) * Math.cos(this.age[i] * 18);
      const scale = 1 + this.pop[i] * settle;
      const fade = t < 0.7 ? 1 : 1 - (t - 0.7) / 0.3;
      const a = this.alpha[i] * fade;
      if (a <= 0.002) continue;
      const i3 = i * 3;
      const o = n * 4;
      posSize[o] = this.pos[i3];
      posSize[o + 1] = this.pos[i3 + 1];
      posSize[o + 2] = this.pos[i3 + 2];
      posSize[o + 3] = this.height[i] * scale;
      color[o] = this.tint[i3];
      color[o + 1] = this.tint[i3 + 1];
      color[o + 2] = this.tint[i3 + 2];
      color[o + 3] = a;
      params[o] = this.word[i];
      params[o + 1] = this.rot[i];
      params[o + 2] = 0;
      params[o + 3] = 0;
      n++;
    }
    return n;
  }
}
