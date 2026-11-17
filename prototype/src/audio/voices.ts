/**
 * Synthesised voices: the four cassette instruments, a drum kit, gameplay cues, count-in ticks and
 * UI blips. Everything is built from oscillators, one shared noise buffer and filters; no samples,
 * no network (the lo-fi cassette colour comes from the per-layer buses in mixer.ts).
 */
import type { DrumKind, LayerNote } from './director';
import type { MusicRole } from './formulas';
import type { SfxCue } from './sfx';

export interface Voice {
  readonly start: number;
  readonly end: number;
  /** Fades out from `at` (a choke, ~20 ms). Safe to call more than once. */
  release(at: number): void;
  /** Drops a voice that has not started yet so it never sounds. */
  cancel(): void;
}

const mtof = (p: number) => 440 * 2 ** ((p - 69) / 12);
const EPS = 0.0001;

const noiseBuffers = new WeakMap<BaseAudioContext, AudioBuffer>();
/** Two seconds of white noise from a fixed LCG: identical on every run, no Math.random. */
function noiseBuffer(ctx: BaseAudioContext): AudioBuffer {
  let b = noiseBuffers.get(ctx);
  if (!b) {
    b = ctx.createBuffer(1, ctx.sampleRate * 2, ctx.sampleRate);
    const d = b.getChannelData(0);
    let seed = 0x9e3779b9;
    for (let i = 0; i < d.length; i++) {
      seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
      d[i] = seed / 2147483648 - 1;
    }
    noiseBuffers.set(ctx, b);
  }
  return b;
}

/** One sounding event: owns its nodes and cleans them up when it ends. */
class Patch {
  private readonly sources: AudioScheduledSourceNode[] = [];
  private readonly nodes: AudioNode[] = [];
  private readonly envs: GainNode[] = [];
  private released = false;
  end: number;

  constructor(
    readonly ctx: BaseAudioContext,
    readonly t: number,
    readonly out: AudioNode,
  ) {
    this.end = t;
  }

  gain(value: number, dest: AudioNode = this.out): GainNode {
    const g = this.ctx.createGain();
    g.gain.value = value;
    g.connect(dest);
    this.nodes.push(g);
    return g;
  }

  /** A modulation amount feeding an AudioParam (FM depth, vibrato depth in cents …). */
  mod(depth: number, param: AudioParam): GainNode {
    const g = this.ctx.createGain();
    g.gain.value = depth;
    g.connect(param);
    this.nodes.push(g);
    return g;
  }

  /** A gain whose level is an envelope; tracked so a choke can silence it. */
  env(dest: AudioNode = this.out): GainNode {
    const g = this.gain(0, dest);
    g.gain.setValueAtTime(EPS, this.t);
    this.envs.push(g);
    return g;
  }

  osc(type: OscillatorType, freq: number, dest: AudioNode, detune = 0, at = this.t): OscillatorNode {
    const o = this.ctx.createOscillator();
    o.type = type;
    o.frequency.setValueAtTime(freq, at);
    o.detune.value = detune;
    o.connect(dest);
    this.sources.push(o);
    this.startAt(o, at);
    return o;
  }

  noise(dest: AudioNode, at = this.t, playbackRate = 1): AudioBufferSourceNode {
    const n = this.ctx.createBufferSource();
    n.buffer = noiseBuffer(this.ctx);
    n.loop = true;
    // Different offsets per hit avoid an audibly identical noise burst every time.
    const offset = (at * 7.31) % 1.8;
    n.playbackRate.value = playbackRate;
    n.connect(dest);
    this.sources.push(n);
    try {
      n.start(Math.max(at, 0), offset);
    } catch {
      /* already started */
    }
    return n;
  }

  filter(type: BiquadFilterType, freq: number, q: number, dest: AudioNode): BiquadFilterNode {
    const f = this.ctx.createBiquadFilter();
    f.type = type;
    f.frequency.setValueAtTime(freq, this.t);
    f.Q.value = q;
    f.connect(dest);
    this.nodes.push(f);
    return f;
  }

  panner(pan: number): StereoPannerNode | GainNode {
    if (typeof this.ctx.createStereoPanner !== 'function') return this.gain(1);
    const p = this.ctx.createStereoPanner();
    p.pan.value = Math.max(-1, Math.min(1, pan));
    p.connect(this.out);
    this.nodes.push(p);
    return p;
  }

  private startAt(s: AudioScheduledSourceNode, at: number): void {
    try {
      s.start(Math.max(at, 0));
    } catch {
      /* already started */
    }
  }

  /** Schedules stops and cleanup; `tail` is how long after `end` the sound may still ring. */
  finish(end: number, tail: number): Voice {
    this.end = end + tail;
    const stopAt = this.end + 0.05;
    for (const s of this.sources) {
      try {
        s.stop(stopAt);
      } catch {
        /* stopped */
      }
    }
    let remaining = this.sources.length;
    const cleanup = () => {
      for (const n of [...this.sources, ...this.nodes]) {
        try {
          n.disconnect();
        } catch {
          /* gone */
        }
      }
    };
    for (const s of this.sources) {
      s.onended = () => {
        if (--remaining <= 0) cleanup();
      };
    }
    const self = this;
    return {
      start: this.t,
      get end() {
        return self.end;
      },
      release(at: number) {
        if (self.released) return;
        self.released = true;
        const t = Math.max(at, self.ctx.currentTime);
        for (const g of self.envs) {
          const p = g.gain as AudioParam & { cancelAndHoldAtTime?: (t: number) => AudioParam };
          if (typeof p.cancelAndHoldAtTime === 'function') p.cancelAndHoldAtTime(t);
          else p.cancelScheduledValues(t);
          p.setTargetAtTime(0, t, 0.012);
        }
        self.end = Math.min(self.end, t + 0.12);
        for (const s of self.sources) {
          try {
            s.stop(t + 0.12);
          } catch {
            /* stopped */
          }
        }
      },
      cancel() {
        self.released = true;
        const now = self.ctx.currentTime;
        self.end = now;
        for (const s of self.sources) {
          try {
            s.stop(now);
          } catch {
            /* stopped */
          }
        }
      },
    };
  }
}

/** Attack / decay / sustain / release on a gain param, fitted inside `dur`. */
function adsr(g: GainNode, t: number, dur: number, peak: number, attack: number, decay: number, sustain: number, release: number): number {
  const a = Math.min(attack, dur * 0.4);
  const d = Math.min(decay, Math.max(0.001, dur - a));
  const p = g.gain;
  p.setValueAtTime(EPS, t);
  p.exponentialRampToValueAtTime(Math.max(EPS * 2, peak), t + a);
  p.exponentialRampToValueAtTime(Math.max(EPS, peak * sustain), t + a + d);
  const end = t + Math.max(dur, a + d);
  p.setTargetAtTime(EPS, end, release / 4);
  return end;
}

/** Percussive one-shot: fast attack, exponential decay. */
function hitEnv(g: GainNode, t: number, peak: number, decay: number, attack = 0.001): number {
  const p = g.gain;
  p.setValueAtTime(EPS, t);
  p.exponentialRampToValueAtTime(Math.max(EPS * 2, peak), t + attack);
  p.exponentialRampToValueAtTime(EPS, t + attack + decay);
  return t + attack + decay;
}

// ───────────────────────────── cassette instruments ─────────────────────────────

/** Plays one layer note into a cassette bus. Instrument follows the layer role. */
export function playLayerNote(ctx: BaseAudioContext, out: AudioNode, role: MusicRole, note: LayerNote, time: number, dur: number): Voice {
  if (note.drum) return playDrum(ctx, out, note.drum, note.velocity / 127, time);
  const v = Math.max(0.05, note.velocity / 127);
  const f = mtof(note.pitch);
  const P = new Patch(ctx, time, out);
  if (role === 'bass') {
    // Subtractive bass: saw + square sub through a resonant low-pass with a plucked cutoff.
    const env = P.env();
    const tame = P.filter('lowpass', 2400, 0.7, env);
    const lp = P.filter('lowpass', 180 + 1700 * v, 5, tame);
    lp.frequency.setValueAtTime(220 + 1900 * v, time);
    lp.frequency.exponentialRampToValueAtTime(170 + 260 * v, time + 0.22);
    P.osc('sawtooth', f, P.gain(0.55, lp));
    P.osc('square', f / 2, P.gain(0.32, lp));
    P.osc('sine', f, P.gain(0.45, env));
    const end = adsr(env, time, dur, 0.3 * v, 0.004, 0.18, 0.68, 0.08);
    return P.finish(end, 0.1);
  }
  if (role === 'chord') {
    // Warm keys: sine + soft octave + a pair of detuned saws under a gentle low-pass; long notes
    // swell like a pad.
    const env = P.env();
    const lp = P.filter('lowpass', 1500 + 900 * v, 0.6, env);
    P.osc('sine', f, P.gain(0.5, env));
    P.osc('triangle', f * 2, P.gain(0.12, env));
    P.osc('sawtooth', f, P.gain(0.12, lp), -7);
    P.osc('sawtooth', f, P.gain(0.12, lp), 7);
    const padLike = dur > 0.9;
    const end = adsr(env, time, dur, 0.13 * v, padLike ? 0.09 : 0.012, padLike ? 0.6 : 0.45, padLike ? 0.75 : 0.42, padLike ? 0.7 : 0.4);
    return P.finish(end, padLike ? 0.75 : 0.45);
  }
  // Plucky lead: detuned saw + triangle into a resonant low-pass that snaps shut.
  const env = P.env();
  const lp = P.filter('lowpass', 900 + 3600 * v, 3, env);
  lp.frequency.setValueAtTime(900 + 3600 * v, time);
  lp.frequency.exponentialRampToValueAtTime(650, time + 0.18);
  P.osc('sawtooth', f, P.gain(0.42, lp), -6);
  P.osc('triangle', f, P.gain(0.5, lp), 5);
  P.osc('sine', f * 2, P.gain(0.05, env));
  const end = adsr(env, time, dur, 0.26 * v, 0.003, 0.22, 0.2, 0.16);
  return P.finish(end, 0.18);
}

export function playDrum(ctx: BaseAudioContext, out: AudioNode, kind: DrumKind, vel: number, time: number): Voice {
  const v = Math.max(0.05, Math.min(1, vel));
  const P = new Patch(ctx, time, out);
  const t = time;
  switch (kind) {
    case 'kick': {
      const body = P.env();
      const o = P.osc('sine', 160, body);
      o.frequency.exponentialRampToValueAtTime(46, t + 0.11);
      const end = hitEnv(body, t, 0.9 * v, 0.38);
      const click = P.env();
      P.noise(P.filter('highpass', 3000, 0.7, click), t);
      hitEnv(click, t, 0.18 * v, 0.006);
      return P.finish(end, 0.02);
    }
    case 'snare': {
      const n = P.env();
      P.noise(P.filter('bandpass', 1900, 0.8, n), t);
      const end = hitEnv(n, t, 0.42 * v, 0.17);
      const tone = P.env();
      const o = P.osc('triangle', 205, tone);
      o.frequency.exponentialRampToValueAtTime(165, t + 0.08);
      hitEnv(tone, t, 0.28 * v, 0.09);
      return P.finish(end, 0.02);
    }
    case 'clap': {
      const n = P.env();
      P.noise(P.filter('bandpass', 1250, 1.2, n), t);
      const g = n.gain;
      g.setValueAtTime(EPS, t);
      for (const off of [0, 0.011, 0.022]) {
        g.exponentialRampToValueAtTime(0.45 * v, t + off + 0.001);
        g.exponentialRampToValueAtTime(0.06 * v, t + off + 0.009);
      }
      g.exponentialRampToValueAtTime(0.38 * v, t + 0.034);
      g.exponentialRampToValueAtTime(EPS, t + 0.2);
      return P.finish(t + 0.2, 0.02);
    }
    case 'hatClosed':
    case 'hatOpen': {
      const n = P.env();
      const bp = P.filter('bandpass', 10000, 0.7, n);
      P.noise(P.filter('highpass', 7000, 0.7, bp), t);
      const end = hitEnv(n, t, (kind === 'hatOpen' ? 0.2 : 0.24) * v, kind === 'hatOpen' ? 0.32 : 0.045);
      return P.finish(end, 0.02);
    }
    case 'tom': {
      const body = P.env();
      const o = P.osc('sine', 175, body);
      o.frequency.exponentialRampToValueAtTime(104, t + 0.2);
      const end = hitEnv(body, t, 0.5 * v, 0.3);
      return P.finish(end, 0.02);
    }
    case 'rim': {
      const g = P.env();
      P.osc('triangle', 1750, g);
      P.noise(P.filter('bandpass', 2600, 2, g), t);
      const end = hitEnv(g, t, 0.3 * v, 0.03);
      return P.finish(end, 0.02);
    }
    case 'perc': {
      // Small FM blip: a woody, pitched percussion voice.
      const g = P.env();
      const car = P.osc('sine', 620, g);
      const depth = P.mod(420, car.frequency);
      depth.gain.setValueAtTime(420, t);
      depth.gain.exponentialRampToValueAtTime(20, t + 0.08);
      P.osc('sine', 930, depth);
      const end = hitEnv(g, t, 0.28 * v, 0.09);
      return P.finish(end, 0.02);
    }
  }
}

// ───────────────────────────── gameplay cues ─────────────────────────────

/** Bright tonal blip used by many cues. */
function blip(P: Patch, dest: AudioNode, type: OscillatorType, pitch: number, at: number, peak: number, decay: number, glideTo?: number): number {
  const g = P.env(dest);
  const o = P.osc(type, mtof(pitch), g, 0, at);
  if (glideTo !== undefined) o.frequency.exponentialRampToValueAtTime(mtof(glideTo), at + decay);
  return hitEnv(g, at, peak, decay, 0.002);
}

/** Filtered noise sweep (whooshes, rumbles, rewinds). */
function sweep(P: Patch, dest: AudioNode, type: BiquadFilterType, from: number, to: number, q: number, at: number, peak: number, dur: number, attack = 0.02): number {
  const g = P.env(dest);
  const f = P.filter(type, from, q, g);
  f.frequency.setValueAtTime(from, at);
  f.frequency.exponentialRampToValueAtTime(Math.max(20, to), at + dur);
  P.noise(f, at);
  g.gain.setValueAtTime(EPS, at);
  g.gain.exponentialRampToValueAtTime(Math.max(EPS * 2, peak), at + attack);
  g.gain.exponentialRampToValueAtTime(EPS, at + dur);
  return at + dur;
}

export function playCue(ctx: BaseAudioContext, out: AudioNode, cue: SfxCue): Voice {
  const P = new Patch(ctx, cue.time, out);
  const d = P.panner(cue.pan);
  const t = cue.time;
  const g = Math.max(0.01, Math.min(1, cue.gain));
  const [p0, p1 = p0, p2 = p1, p3 = p2] = cue.pitches;
  const s16 = Math.min(0.12, Math.max(0.03, cue.sixteenth));
  let end = t + 0.1;
  switch (cue.kind) {
    case 'transient': {
      end = sweep(P, d, 'highpass', 2500, 1800, 0.7, t, 0.5 * g, 0.012, 0.001);
      break;
    }
    case 'step': {
      end = sweep(P, d, 'bandpass', 1800, 900, 1.5, t, 0.5 * g, 0.03, 0.002);
      blip(P, d, 'sine', p0 + 12, t, 0.12 * g, 0.03);
      break;
    }
    case 'swingLight':
    case 'swingHeavy': {
      const heavy = cue.kind === 'swingHeavy';
      end = sweep(P, d, 'bandpass', heavy ? 500 : 1400, heavy ? 1800 : 4200, 1.1, t, 0.5 * g, heavy ? 0.16 : 0.09, 0.03);
      blip(P, d, 'triangle', p0, t + 0.01, 0.22 * g, heavy ? 0.14 : 0.07);
      break;
    }
    case 'hit': {
      end = blip(P, d, 'triangle', p0, t, 0.55 * g, 0.16);
      blip(P, d, 'square', p1, t, 0.12 * g, 0.08);
      sweep(P, d, 'highpass', 3000, 1200, 0.8, t, 0.5 * g, 0.05, 0.001);
      break;
    }
    case 'kill': {
      cue.pitches.forEach((p, i) => {
        end = blip(P, d, 'triangle', p, t + i * s16 * 0.5, 0.36 * g, 0.18);
      });
      sweep(P, d, 'bandpass', 2400, 600, 1, t, 0.4 * g, 0.18, 0.002);
      break;
    }
    case 'break': {
      end = sweep(P, d, 'lowpass', 2600, 160, 0.8, t, 0.9 * g, 0.45, 0.002);
      blip(P, d, 'sine', p0, t, 0.6 * g, 0.32, p0 - 12);
      blip(P, d, 'triangle', p1, t, 0.25 * g, 0.2);
      break;
    }
    case 'clang': {
      // Inharmonic but rooted on a chord tone: metal that is still in key.
      const gg = P.env(d);
      const f = mtof(p0);
      for (const [ratio, lvl] of [
        [1, 0.5],
        [2.76, 0.25],
        [5.4, 0.12],
      ] as const)
        P.osc('sine', f * ratio, P.gain(lvl, gg));
      end = hitEnv(gg, t, 0.55 * g, 0.28);
      break;
    }
    case 'dodge': {
      end = sweep(P, d, 'bandpass', 800, 3600, 2, t, 0.45 * g, 0.14, 0.04);
      blip(P, d, 'sine', p0, t + 0.02, 0.12 * g, 0.1, p0 + 5);
      break;
    }
    case 'fire': {
      const a = cue.detail;
      if (a === 'missile') {
        end = blip(P, d, 'sawtooth', p0 - 12, t, 0.22 * g, 0.3, p0);
        sweep(P, d, 'lowpass', 400, 1600, 1, t, 0.25 * g, 0.3, 0.02);
      } else if (a === 'pierce') {
        end = blip(P, d, 'square', p1 + 12, t, 0.18 * g, 0.09, p1);
      } else if (a === 'phase') {
        end = blip(P, d, 'sine', p0 + 12, t, 0.25 * g, 0.25);
        blip(P, d, 'sine', p0 + 12.12, t, 0.2 * g, 0.25);
      } else if (a === 'arc') {
        end = blip(P, d, 'triangle', p0, t, 0.3 * g, 0.18, p1);
      } else if (a === 'burst') {
        for (let i = 0; i < 3; i++) end = blip(P, d, 'square', p0 + 12, t + i * s16 * 0.35, 0.12 * g, 0.04);
      } else {
        end = blip(P, d, 'triangle', p1, t, 0.25 * g, 0.12, p0);
      }
      break;
    }
    case 'projectileHit': {
      end = blip(P, d, 'triangle', p0, t, 0.4 * g, 0.1);
      sweep(P, d, 'bandpass', 2000, 900, 1.2, t, 0.35 * g, 0.05, 0.001);
      break;
    }
    case 'interact': {
      sweep(P, d, 'highpass', 4000, 3000, 0.7, t, 0.3 * g, 0.015, 0.001);
      blip(P, d, 'square', p0, t, 0.14 * g, 0.08);
      end = blip(P, d, 'triangle', p1, t + s16 * 0.5, 0.3 * g, 0.14);
      break;
    }
    case 'interactFail': {
      end = blip(P, d, 'sine', p0, t, 0.35 * g, 0.08, p0 - 2);
      break;
    }
    case 'door': {
      const opening = cue.detail !== 'off' && cue.detail !== 'close' && cue.detail !== 'closed';
      end = sweep(P, d, 'lowpass', opening ? 180 : 700, opening ? 700 : 160, 1.5, t, 0.5 * g, 0.5, 0.05);
      blip(P, d, 'sine', p0, t, 0.4 * g, 0.4);
      blip(P, d, 'sine', p1, t + 0.18, 0.3 * g, 0.4);
      break;
    }
    case 'plate': {
      end = blip(P, d, 'sine', p0 - 12, t, 0.5 * g, 0.12, p0 - 24);
      blip(P, d, 'triangle', p0, t, 0.18 * g, 0.12);
      break;
    }
    case 'laser': {
      const on = cue.detail !== 'off';
      const gg = P.env(d);
      const lp = P.filter('lowpass', on ? 2200 : 900, 4, gg);
      const o = P.osc('sawtooth', mtof(p0), lp);
      if (!on) o.frequency.exponentialRampToValueAtTime(mtof(p0 - 12), t + 0.2);
      P.osc('sawtooth', mtof(p0 + 7), P.gain(0.5, lp), 9);
      end = hitEnv(gg, t, 0.22 * g, 0.22, 0.01);
      break;
    }
    case 'core': {
      cue.pitches.forEach((p, i) => {
        const gg = P.env(d);
        P.osc('sine', mtof(p), gg, 0, t + i * 0.012);
        P.osc('sine', mtof(p) * 3.01, P.gain(0.12, gg), 0, t + i * 0.012);
        end = Math.max(end, hitEnv(gg, t + i * 0.012, 0.22 * g, 1.1, 0.003));
      });
      break;
    }
    case 'selfDeath': {
      // A tape-stop fall through the chord: the self's voice winding down.
      cue.pitches.forEach((p, i) => {
        end = blip(P, d, 'triangle', p, t + i * s16, 0.32 * g, 0.3, p - 5);
      });
      sweep(P, d, 'lowpass', 1800, 120, 1.2, t, 0.4 * g, 0.6, 0.004);
      break;
    }
    case 'desync': {
      // Two detuned voices with a wobbling pitch: the self slipping out of step, still in key.
      const gg = P.env(d);
      const a = P.osc('triangle', mtof(p0), gg, -18);
      const b = P.osc('triangle', mtof(p0), gg, 22);
      P.osc('sine', 6.5, P.mod(28, a.detune));
      P.osc('sine', 5.1, P.mod(28, b.detune));
      end = hitEnv(gg, t, 0.2 * g, 0.42, 0.02);
      break;
    }
    case 'resync': {
      blip(P, d, 'triangle', p0, t, 0.3 * g, 0.1);
      end = blip(P, d, 'sine', p1, t + s16 * 0.5, 0.35 * g, 0.22);
      break;
    }
    case 'tapeWrap': {
      end = sweep(P, d, 'bandpass', 900, 5200, 3, t, 0.35 * g, 0.12, 0.01);
      blip(P, d, 'sine', p0, t + 0.1, 0.15 * g, 0.05);
      break;
    }
    case 'tapeTurn': {
      // Reverse swell: rises instead of decaying.
      const gg = P.env(d);
      P.osc('triangle', mtof(p0), gg);
      gg.gain.setValueAtTime(EPS, t);
      gg.gain.exponentialRampToValueAtTime(0.25 * g, t + 0.22);
      gg.gain.exponentialRampToValueAtTime(EPS, t + 0.26);
      end = t + 0.26;
      break;
    }
    case 'tapeEnd': {
      end = blip(P, d, 'triangle', p0, t, 0.3 * g, 0.4, p0 - 12);
      sweep(P, d, 'highpass', 3000, 2000, 0.7, t + 0.38, 0.3 * g, 0.02, 0.001);
      break;
    }
    case 'enemyTelegraph': {
      const gg = P.env(d);
      const lp = P.filter('lowpass', 300, 6, gg);
      lp.frequency.exponentialRampToValueAtTime(2200, t + 0.18);
      P.osc('square', mtof(p0), lp);
      P.osc('square', mtof(p1), P.gain(0.5, lp));
      gg.gain.setValueAtTime(EPS, t);
      gg.gain.exponentialRampToValueAtTime(0.2 * g, t + 0.16);
      gg.gain.exponentialRampToValueAtTime(EPS, t + 0.22);
      end = t + 0.22;
      break;
    }
    case 'enemyAttack': {
      end = blip(P, d, 'sine', p0, t, 0.6 * g, 0.2, p0 - 12);
      sweep(P, d, 'lowpass', 1600, 200, 1, t, 0.45 * g, 0.15, 0.002);
      break;
    }
    case 'enemyShot': {
      end = blip(P, d, 'square', p0, t, 0.14 * g, 0.12, p0 - 7);
      break;
    }
    case 'enemyStagger': {
      const gg = P.env(d);
      const o = P.osc('triangle', mtof(p0), gg);
      P.osc('sine', 11, P.mod(45, o.detune));
      end = hitEnv(gg, t, 0.25 * g, 0.3, 0.004);
      break;
    }
    case 'bossPhase': {
      cue.pitches.forEach((p) => {
        end = blip(P, d, 'sawtooth', p, t, 0.18 * g, 1.2);
      });
      sweep(P, d, 'lowpass', 120, 3000, 1.2, t, 0.45 * g, 0.9, 0.3);
      break;
    }
    case 'bossRecall': {
      // A remembered phrase played backwards: swells that cut off.
      cue.pitches.forEach((p, i) => {
        const gg = P.env(d);
        const at = t + i * s16;
        P.osc('sine', mtof(p), gg, 0, at);
        P.osc('triangle', mtof(p), P.gain(0.3, gg), 6, at);
        gg.gain.setValueAtTime(EPS, at);
        gg.gain.exponentialRampToValueAtTime(0.2 * g, at + 0.3);
        gg.gain.exponentialRampToValueAtTime(EPS, at + 0.34);
        end = at + 0.34;
      });
      break;
    }
    case 'objective': {
      cue.pitches.forEach((p, i) => {
        end = blip(P, d, 'triangle', p, t + i * s16 * 0.5, 0.3 * g, 0.5);
        blip(P, d, 'sine', p + 12, t + i * s16 * 0.5, 0.08 * g, 0.4);
      });
      break;
    }
  }
  return P.finish(end, 0.05);
}

// ───────────────────────────── count-in and UI ─────────────────────────────

/** A clave-like tick on `pitch`; `accent` for the last count before the downbeat. */
export function playTick(ctx: BaseAudioContext, out: AudioNode, pitch: number, time: number, accent: boolean): Voice {
  const P = new Patch(ctx, time, out);
  const g = accent ? 0.5 : 0.36;
  blip(P, out, 'sine', pitch, time, g, accent ? 0.22 : 0.14);
  blip(P, out, 'triangle', pitch + 12, time, g * 0.35, 0.05);
  const end = sweep(P, out, 'bandpass', 2600, 2400, 3, time, g * 0.5, 0.015, 0.001);
  return P.finish(Math.max(end, time + 0.22), 0.05);
}

export type UiKind = 'move' | 'select' | 'back' | 'commit' | 'retry' | 'reset' | 'win' | 'fail' | 'loot' | 'speed';

/** UI blips; `scale(degree)` returns MIDI notes in the current key so menus match the level. */
export function playUi(ctx: BaseAudioContext, out: AudioNode, kind: UiKind, scale: (degree: number) => number, time: number): Voice {
  const P = new Patch(ctx, time, out);
  const t = time;
  let end = t + 0.1;
  const seq = (degrees: number[], step: number, type: OscillatorType, peak: number, decay: number) => {
    degrees.forEach((dg, i) => {
      end = Math.max(end, blip(P, out, type, scale(dg), t + i * step, peak, decay));
    });
  };
  switch (kind) {
    case 'move':
      seq([4], 0, 'sine', 0.12, 0.04);
      break;
    case 'select':
      seq([2, 4], 0.05, 'triangle', 0.2, 0.09);
      break;
    case 'back':
      seq([4, 2], 0.05, 'triangle', 0.18, 0.09);
      break;
    case 'commit':
      sweep(P, out, 'highpass', 3000, 2000, 0.7, t, 0.25, 0.02, 0.001);
      seq([0, 2, 4, 7], 0.06, 'triangle', 0.24, 0.2);
      break;
    case 'retry':
      end = sweep(P, out, 'bandpass', 4200, 900, 3, t, 0.3, 0.22, 0.01);
      seq([4, 2], 0.08, 'sine', 0.16, 0.1);
      break;
    case 'reset':
      end = sweep(P, out, 'bandpass', 5200, 500, 3, t, 0.35, 0.45, 0.01);
      seq([7, 4, 2, 0], 0.07, 'sine', 0.14, 0.12);
      break;
    case 'win':
      seq([0, 2, 4, 7, 9, 11, 14], 0.07, 'triangle', 0.26, 0.4);
      break;
    case 'fail':
      seq([4, 3, 1, 0], 0.12, 'triangle', 0.22, 0.3);
      break;
    case 'loot':
      seq([7, 9, 11, 14], 0.045, 'sine', 0.22, 0.3);
      seq([14], 0.2, 'triangle', 0.1, 0.5);
      break;
    case 'speed': {
      const gg = P.env(out);
      const o = P.osc('triangle', mtof(scale(0)), gg);
      o.frequency.exponentialRampToValueAtTime(mtof(scale(4)), t + 0.12);
      end = hitEnv(gg, t, 0.16, 0.14, 0.01);
      break;
    }
  }
  return P.finish(end, 0.05);
}
