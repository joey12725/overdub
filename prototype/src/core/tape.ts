/**
 * Tapes: recording, sampling, velocity estimation, cloning and serialisation (PLAY-01..06).
 *
 * A Tape is a fixed trajectory (pose sample per local tick, sample 0 = start pose) plus action
 * events. Playback samples it by fractional local tick; it never re-runs physics.
 */
import { tapePhaseInto } from './time';
import {
  ANIM_STATES,
  LOCAL_HZ,
  type ActionKind,
  type AnimState,
  type EndMode,
  type Tape,
  type TapeEvent,
  type TapeIndex,
  type TapePhase,
  type TapeSpeed,
} from './types';

/** One interpolated pose. */
export interface PoseSample {
  x: number;
  y: number;
  facing: number;
  anim: AnimState;
}

const ANIM_INDEX: Record<AnimState, number> = Object.fromEntries(ANIM_STATES.map((a, i) => [a, i])) as Record<
  AnimState,
  number
>;

/** AnimState → index stored in Tape.anim. */
export function animIndex(anim: AnimState): number {
  return ANIM_INDEX[anim];
}

/** Index stored in Tape.anim → AnimState (unknown indices read as idle). */
export function animFromIndex(i: number): AnimState {
  return ANIM_STATES[i] ?? 'idle';
}

const TWO_PI = Math.PI * 2;

/** Wrap an angle into (-π, π]. */
export function wrapAngle(a: number): number {
  let r = a % TWO_PI;
  if (r <= -Math.PI) r += TWO_PI;
  else if (r > Math.PI) r -= TWO_PI;
  return r;
}

/** Signed shortest angular difference b − a, in (-π, π]. */
export function angleDelta(a: number, b: number): number {
  return wrapAngle(b - a);
}

/** Interpolate angles along the shortest arc. */
export function lerpAngle(a: number, b: number, t: number): number {
  return wrapAngle(a + angleDelta(a, b) * t);
}

// ───────────────────────────── recorder ─────────────────────────────

export interface TapeRecorderInit {
  index: TapeIndex;
  speed: TapeSpeed;
  endMode: EndMode;
  /** Local ticks the take will last (level allowance). */
  ticks: number;
  /** Start pose = sample 0 (REC-02: every tape starts at the level start at beat zero). */
  start: { x: number; y: number; facing: number; anim?: AnimState };
}

/**
 * Accumulates one take. Typed arrays are allocated up front for `ticks + 1` samples.
 * Call `push` once per local tick (after the controller step) and `addEvent` for each event that
 * tick produced. Positions are stored as float32: callers wanting live == playback exactness should
 * feed already float32-rounded values (the PlayerController does).
 */
export class TapeRecorder {
  readonly index: TapeIndex;
  readonly speed: TapeSpeed;
  readonly endMode: EndMode;
  readonly ticks: number;
  private readonly pos: Float32Array;
  private readonly facing: Float32Array;
  private readonly anim: Uint8Array;
  private readonly events: TapeEvent[] = [];
  /** Samples written so far (≥ 1: the start pose). */
  private samples = 1;

  constructor(init: TapeRecorderInit) {
    if (!(Number.isInteger(init.ticks) && init.ticks >= 0)) throw new Error(`TapeRecorder: bad tick count ${init.ticks}`);
    this.index = init.index;
    this.speed = init.speed;
    this.endMode = init.endMode;
    this.ticks = init.ticks;
    this.pos = new Float32Array((init.ticks + 1) * 2);
    this.facing = new Float32Array(init.ticks + 1);
    this.anim = new Uint8Array(init.ticks + 1);
    this.pos[0] = init.start.x;
    this.pos[1] = init.start.y;
    this.facing[0] = init.start.facing;
    this.anim[0] = animIndex(init.start.anim ?? 'idle');
  }

  /** Local ticks recorded so far (samples − 1). */
  get recordedTicks(): number {
    return this.samples - 1;
  }

  get complete(): boolean {
    return this.samples === this.ticks + 1;
  }

  /** Append the pose at the end of the next local tick. Throws once the allowance is used up. */
  push(x: number, y: number, facing: number, anim: AnimState): void {
    if (this.samples > this.ticks) throw new Error('TapeRecorder: tape is full');
    const i = this.samples++;
    this.pos[i * 2] = x;
    this.pos[i * 2 + 1] = y;
    this.facing[i] = facing;
    this.anim[i] = animIndex(anim);
  }

  /**
   * Record an event. Its tick must be a recorded or the currently-recording tick
   * (≤ recordedTicks, since the event of tick i is added alongside sample i + 1) and events must
   * arrive in non-decreasing tick order.
   */
  addEvent(ev: TapeEvent): void {
    if (!(ev.tick >= 0 && ev.tick <= this.ticks && ev.tick <= this.recordedTicks)) {
      throw new Error(`TapeRecorder: event tick ${ev.tick} out of range`);
    }
    const last = this.events[this.events.length - 1];
    if (last && ev.tick < last.tick) throw new Error('TapeRecorder: events must be added in tick order');
    this.events.push({ ...ev });
  }

  /**
   * The take so far as a Tape whose `ticks` is the number recorded (a prefix of the final tape).
   * Arrays are copies; the recorder can keep recording.
   */
  snapshot(): Tape {
    const n = this.samples;
    return {
      index: this.index,
      speed: this.speed,
      endMode: this.endMode,
      ticks: n - 1,
      pos: this.pos.slice(0, n * 2),
      facing: this.facing.slice(0, n),
      anim: this.anim.slice(0, n),
      events: this.events.map((e) => ({ ...e })),
    };
  }

  /**
   * The finished Tape with the full allowance. If fewer ticks were recorded (an aborted take), the
   * remaining samples hold the last recorded pose so the tape stays well-formed.
   */
  finish(): Tape {
    const last = this.samples - 1;
    for (let i = this.samples; i <= this.ticks; i++) {
      this.pos[i * 2] = this.pos[last * 2];
      this.pos[i * 2 + 1] = this.pos[last * 2 + 1];
      this.facing[i] = this.facing[last];
      this.anim[i] = this.anim[last];
    }
    return {
      index: this.index,
      speed: this.speed,
      endMode: this.endMode,
      ticks: this.ticks,
      pos: this.pos.slice(),
      facing: this.facing.slice(),
      anim: this.anim.slice(),
      events: this.events.map((e) => ({ ...e })),
    };
  }
}

// ───────────────────────────── sampling ─────────────────────────────

/**
 * Pose at a fractional local tick (clamped to [0, ticks]). Position is linearly interpolated,
 * facing along the shortest arc, and anim is the sample at floor(tick) (state of the tick in progress).
 */
export function samplePose(tape: Tape, tick: number): PoseSample {
  return samplePoseInto(tape, tick, { x: 0, y: 0, facing: 0, anim: 'idle' });
}

/** Allocation-free samplePose. */
export function samplePoseInto(tape: Tape, tick: number, out: PoseSample): PoseSample {
  const T = tape.ticks;
  const t = tick > 0 ? (tick < T ? tick : T) : 0;
  const i = Math.floor(t);
  const f = t - i;
  const p = tape.pos;
  if (f === 0 || i >= T) {
    out.x = p[i * 2];
    out.y = p[i * 2 + 1];
    out.facing = tape.facing[i];
  } else {
    const x0 = p[i * 2];
    const y0 = p[i * 2 + 1];
    out.x = x0 + (p[i * 2 + 2] - x0) * f;
    out.y = y0 + (p[i * 2 + 3] - y0) * f;
    out.facing = lerpAngle(tape.facing[i], tape.facing[i + 1], f);
  }
  out.anim = animFromIndex(tape.anim[i]);
  return out;
}

/**
 * Pose of a tape at a master substep: the playhead from tapePhaseAt (end behaviour applied), then
 * samplePose. `phaseOut`, if given, receives the phase. Allocation-free when `out` is passed.
 */
export function samplePoseAtSub(
  tape: Tape,
  sub: number,
  out: PoseSample = { x: 0, y: 0, facing: 0, anim: 'idle' },
  phaseOut: TapePhase = { tick: 0, dir: 1, traversal: 0, ended: false },
): PoseSample {
  tapePhaseInto(tape, sub, phaseOut);
  return samplePoseInto(tape, phaseOut.tick, out);
}

/** Position only, allocation-free (hot path for collision and desync checks). */
export function samplePosInto(tape: Tape, tick: number, out: { x: number; y: number }): { x: number; y: number } {
  const T = tape.ticks;
  const t = tick > 0 ? (tick < T ? tick : T) : 0;
  const i = Math.floor(t);
  const f = t - i;
  const p = tape.pos;
  if (f === 0 || i >= T) {
    out.x = p[i * 2];
    out.y = p[i * 2 + 1];
  } else {
    out.x = p[i * 2] + (p[i * 2 + 2] - p[i * 2]) * f;
    out.y = p[i * 2 + 1] + (p[i * 2 + 3] - p[i * 2 + 1]) * f;
  }
  return out;
}

/**
 * Local-space velocity (tiles per local second) of the recorded motion at a fractional tick:
 * the slope of the segment containing it (the last segment at t = ticks). Zero for empty tapes.
 */
export function localVelocityAt(tape: Tape, tick: number, out: { x: number; y: number } = { x: 0, y: 0 }): { x: number; y: number } {
  const T = tape.ticks;
  if (T <= 0) {
    out.x = 0;
    out.y = 0;
    return out;
  }
  const t = tick > 0 ? (tick < T ? tick : T) : 0;
  const i = Math.min(Math.floor(t), T - 1);
  const p = tape.pos;
  out.x = (p[i * 2 + 2] - p[i * 2]) * LOCAL_HZ;
  out.y = (p[i * 2 + 3] - p[i * 2 + 1]) * LOCAL_HZ;
  return out;
}

/**
 * Master-space velocity (tiles per master second) of the visible motion: local velocity × speed ×
 * playhead direction. A reversing tape moves backward along its path; a stopped one is still.
 */
export function masterVelocityAt(
  tape: Tape,
  tick: number,
  dir: 1 | -1 | 0,
  out: { x: number; y: number } = { x: 0, y: 0 },
): { x: number; y: number } {
  localVelocityAt(tape, tick, out);
  const k = tape.speed * dir;
  out.x *= k;
  out.y *= k;
  // Normalise -0 so snapshots compare cleanly.
  if (out.x === 0) out.x = 0;
  if (out.y === 0) out.y = 0;
  return out;
}

/** Deep copy. */
export function cloneTape(tape: Tape): Tape {
  return {
    index: tape.index,
    speed: tape.speed,
    endMode: tape.endMode,
    ticks: tape.ticks,
    pos: tape.pos.slice(),
    facing: tape.facing.slice(),
    anim: tape.anim.slice(),
    events: tape.events.map((e) => ({ ...e })),
  };
}

/** Same trajectory and events with a different end mode (setup can change end behaviour; the recording is untouched). */
export function withEndMode(tape: Tape, endMode: EndMode): Tape {
  return { ...cloneTape(tape), endMode };
}

/** Bit-exact equality of two tapes (determinism tests, replay verification). */
export function tapesEqual(a: Tape, b: Tape): boolean {
  if (a.index !== b.index || a.speed !== b.speed || a.endMode !== b.endMode || a.ticks !== b.ticks) return false;
  if (!typedEqual(a.pos, b.pos) || !typedEqual(a.facing, b.facing) || !typedEqual(a.anim, b.anim)) return false;
  if (a.events.length !== b.events.length) return false;
  for (let i = 0; i < a.events.length; i++) {
    const x = a.events[i];
    const y = b.events[i];
    if (x.tick !== y.tick || x.kind !== y.kind || !same(x.dir, y.dir) || !same(x.x, y.x) || !same(x.y, y.y) || !same(x.vx, y.vx) || !same(x.vy, y.vy)) {
      return false;
    }
  }
  return true;
}

function same(a: number, b: number): boolean {
  return Object.is(a, b) || a === b;
}

function typedEqual(a: Float32Array | Uint8Array, b: Float32Array | Uint8Array): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (!(a[i] === b[i] || (a[i] !== a[i] && b[i] !== b[i]))) return false;
  return true;
}

// ───────────────────────────── serialisation ─────────────────────────────

const ACTION_KINDS: readonly ActionKind[] = ['light', 'heavy', 'dodge', 'ranged', 'interact', 'ability'];

/**
 * JSON-safe tape. Pose arrays are little-endian bytes in base64 (lossless and ~4× smaller than
 * number arrays). Events are tuples [tick, kindIndex, dir, x, y, vx, vy]; doubles round-trip
 * exactly through JSON.
 */
export interface SerializedTape {
  v: 1;
  index: TapeIndex;
  speed: TapeSpeed;
  endMode: EndMode;
  ticks: number;
  pos: string;
  facing: string;
  anim: string;
  events: [number, number, number, number, number, number, number][];
}

export function serializeTape(tape: Tape): SerializedTape {
  return {
    v: 1,
    index: tape.index,
    speed: tape.speed,
    endMode: tape.endMode,
    ticks: tape.ticks,
    pos: base64FromBytes(float32ToBytes(tape.pos)),
    facing: base64FromBytes(float32ToBytes(tape.facing)),
    anim: base64FromBytes(tape.anim),
    events: tape.events.map((e) => [e.tick, ACTION_KINDS.indexOf(e.kind), e.dir, e.x, e.y, e.vx, e.vy]),
  };
}

/** Inverse of serializeTape. Throws on malformed input (wrong version, lengths or kinds). */
export function deserializeTape(s: SerializedTape): Tape {
  if (!s || s.v !== 1) throw new Error('deserializeTape: unsupported version');
  const ticks = s.ticks;
  if (!(Number.isInteger(ticks) && ticks >= 0)) throw new Error('deserializeTape: bad ticks');
  const pos = bytesToFloat32(bytesFromBase64(s.pos));
  const facing = bytesToFloat32(bytesFromBase64(s.facing));
  const anim = bytesFromBase64(s.anim);
  if (pos.length !== (ticks + 1) * 2 || facing.length !== ticks + 1 || anim.length !== ticks + 1) {
    throw new Error('deserializeTape: array lengths do not match ticks');
  }
  const events: TapeEvent[] = s.events.map((t) => {
    const kind = ACTION_KINDS[t[1]];
    if (!kind) throw new Error(`deserializeTape: bad action kind ${t[1]}`);
    return { tick: t[0], kind, dir: t[2], x: t[3], y: t[4], vx: t[5], vy: t[6] };
  });
  return { index: s.index, speed: s.speed, endMode: s.endMode, ticks, pos, facing, anim, events };
}

function float32ToBytes(a: Float32Array): Uint8Array {
  const out = new Uint8Array(a.length * 4);
  const dv = new DataView(out.buffer);
  for (let i = 0; i < a.length; i++) dv.setFloat32(i * 4, a[i], true);
  return out;
}

function bytesToFloat32(b: Uint8Array): Float32Array {
  if (b.length % 4 !== 0) throw new Error('deserializeTape: float array byte length not a multiple of 4');
  const out = new Float32Array(b.length / 4);
  const dv = new DataView(b.buffer, b.byteOffset, b.byteLength);
  for (let i = 0; i < out.length; i++) out[i] = dv.getFloat32(i * 4, true);
  return out;
}

const B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
const B64_INV = (() => {
  const t = new Int16Array(128).fill(-1);
  for (let i = 0; i < B64.length; i++) t[B64.charCodeAt(i)] = i;
  return t;
})();

/** Standard padded base64 (pure, so core stays free of DOM/Node globals). */
export function base64FromBytes(b: Uint8Array): string {
  let s = '';
  let i = 0;
  for (; i + 2 < b.length; i += 3) {
    const n = (b[i] << 16) | (b[i + 1] << 8) | b[i + 2];
    s += B64[n >> 18] + B64[(n >> 12) & 63] + B64[(n >> 6) & 63] + B64[n & 63];
  }
  const rem = b.length - i;
  if (rem === 1) {
    const n = b[i] << 16;
    s += B64[n >> 18] + B64[(n >> 12) & 63] + '==';
  } else if (rem === 2) {
    const n = (b[i] << 16) | (b[i + 1] << 8);
    s += B64[n >> 18] + B64[(n >> 12) & 63] + B64[(n >> 6) & 63] + '=';
  }
  return s;
}

export function bytesFromBase64(s: string): Uint8Array {
  if (s.length % 4 !== 0) throw new Error('base64: length not a multiple of 4');
  let pad = 0;
  if (s.endsWith('==')) pad = 2;
  else if (s.endsWith('=')) pad = 1;
  const out = new Uint8Array((s.length / 4) * 3 - pad);
  let o = 0;
  for (let i = 0; i < s.length; i += 4) {
    const a = dec(s, i);
    const b = dec(s, i + 1);
    const c = s[i + 2] === '=' ? 0 : dec(s, i + 2);
    const d = s[i + 3] === '=' ? 0 : dec(s, i + 3);
    const n = (a << 18) | (b << 12) | (c << 6) | d;
    if (o < out.length) out[o++] = (n >> 16) & 255;
    if (o < out.length) out[o++] = (n >> 8) & 255;
    if (o < out.length) out[o++] = n & 255;
  }
  return out;
}

function dec(s: string, i: number): number {
  const code = s.charCodeAt(i);
  const v = code < 128 ? B64_INV[code] : -1;
  if (v < 0) throw new Error(`base64: bad character at ${i}`);
  return v;
}
