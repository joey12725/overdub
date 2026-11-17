/**
 * The mix: one coloured bus per cassette layer, a SFX bus, a procedural reverb and a master
 * compressor + limiter.
 *
 *   layer i:  input → hp → lp → presence → [dry | chorus] → tape saturation → wow/flutter → pan → level ┬→ music
 *                                                                                                     └→ reverb send
 *   music → tone → pre ← sfx, reverb return;  pre → shelf → glue comp → limiter → master → out
 *
 * State colour (MUSIC-08) is applied here on top of the note changes made in director.ts: a dead
 * self's layer goes hollow (band-limited, a nasal presence bump, quieter, wetter); a desynced
 * layer gets a detuned chorus and deeper wow, both easing back as the drift converges.
 */
import type { MusicRole } from './formulas';

export type MixMode = 'menu' | 'record' | 'review' | 'cinematic';

export interface LayerColour {
  present: boolean;
  dead: boolean;
  /** 0..1 desync drift. */
  drift: number;
  speed: number;
}

const TAPE_PAN = [-0.34, -0.12, 0.12, 0.34];
const ROLE_WIDTH: Record<MusicRole, number> = { bass: 0.2, drums: 0.3, melody: 1, chord: 1 };
const ROLE_LEVEL: Record<MusicRole, number> = { bass: 0.72, drums: 0.8, melody: 0.85, chord: 0.72 };
const ROLE_SEND: Record<MusicRole, number> = { bass: 0.04, drums: 0.1, melody: 0.26, chord: 0.3 };
/** Time constant (s) for colour changes: quick enough to read, slow enough to never click. */
const GLIDE = 0.12;

function saturationCurve(drive: number): Float32Array {
  const n = 2048;
  const curve = new Float32Array(n);
  const norm = Math.tanh(drive);
  for (let i = 0; i < n; i++) {
    const x = (i / (n - 1)) * 2 - 1;
    // A touch of asymmetry gives the even harmonics of tape rather than the odd ones of a clipper.
    curve[i] = Math.tanh(drive * (x + 0.04 * x * x)) / norm;
  }
  return curve;
}

/** Procedural stereo room: decaying noise that darkens as it decays. Deterministic. */
function impulse(ctx: BaseAudioContext, seconds: number): AudioBuffer {
  const len = Math.floor(ctx.sampleRate * seconds);
  const buf = ctx.createBuffer(2, len, ctx.sampleRate);
  for (let ch = 0; ch < 2; ch++) {
    const d = buf.getChannelData(ch);
    let seed = ch ? 0x2545f491 : 0x6c8e9cf5;
    let lp = 0;
    const pre = Math.floor(ctx.sampleRate * 0.012);
    for (let i = 0; i < len; i++) {
      seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
      const white = seed / 2147483648 - 1;
      const t = i / len;
      // One-pole low-pass whose cutoff falls over the tail (air absorbs highs first).
      const k = 0.55 - 0.45 * t;
      lp += k * (white - lp);
      d[i] = i < pre ? 0 : lp * Math.pow(1 - t, 2.4) * Math.exp(-3 * t);
    }
  }
  return buf;
}

class LayerBus {
  readonly input: GainNode;
  private readonly hp: BiquadFilterNode;
  private readonly lp: BiquadFilterNode;
  private readonly presence: BiquadFilterNode;
  private readonly chorusWet: GainNode;
  private readonly chorusDepth: GainNode;
  private readonly wowDepth: GainNode;
  private readonly flutterDepth: GainNode;
  private readonly pan: StereoPannerNode | null;
  private readonly level: GainNode;
  private readonly send: GainNode;
  private readonly lfos: OscillatorNode[] = [];
  private readonly nodes: AudioNode[] = [];
  private colour: LayerColour = { present: false, dead: false, drift: 0, speed: 1 };
  private width = 1;

  constructor(
    private readonly ctx: BaseAudioContext,
    private readonly index: number,
    private readonly role: MusicRole,
    music: AudioNode,
    reverb: AudioNode,
  ) {
    const g = (v: number) => {
      const n = ctx.createGain();
      n.gain.value = v;
      this.nodes.push(n);
      return n;
    };
    const f = (type: BiquadFilterType, freq: number, q: number) => {
      const n = ctx.createBiquadFilter();
      n.type = type;
      n.frequency.value = freq;
      n.Q.value = q;
      this.nodes.push(n);
      return n;
    };
    const lfo = (freq: number, depth: GainNode) => {
      const o = ctx.createOscillator();
      o.frequency.value = freq;
      o.connect(depth);
      o.start();
      this.lfos.push(o);
    };

    this.input = g(1);
    this.hp = f('highpass', role === 'bass' || role === 'drums' ? 25 : 70, 0.6);
    this.lp = f('lowpass', 12500, 0.5);
    this.presence = f('peaking', 1100, 1);
    this.presence.gain.value = 0;
    this.input.connect(this.hp);
    this.hp.connect(this.lp);
    this.lp.connect(this.presence);

    const sat = ctx.createWaveShaper();
    sat.curve = saturationCurve(role === 'bass' ? 1.5 : 1.25);
    sat.oversample = '2x';
    this.nodes.push(sat);
    const satIn = g(0.9);
    satIn.connect(sat);
    this.presence.connect(satIn);

    // Chorus: a short modulated delay mixed in under the dry signal.
    const chorus = ctx.createDelay(0.05);
    chorus.delayTime.value = 0.016;
    this.nodes.push(chorus);
    this.chorusDepth = g(0);
    this.chorusDepth.connect(chorus.delayTime);
    lfo(0.83 + index * 0.07, this.chorusDepth);
    this.chorusWet = g(0);
    this.presence.connect(chorus);
    chorus.connect(this.chorusWet);
    this.chorusWet.connect(satIn);

    // Wow (slow) and flutter (fast) on a delay line: gentle tape pitch instability.
    const wow = ctx.createDelay(0.05);
    wow.delayTime.value = 0.006;
    this.nodes.push(wow);
    this.wowDepth = g(0.00045);
    this.flutterDepth = g(0.00006);
    this.wowDepth.connect(wow.delayTime);
    this.flutterDepth.connect(wow.delayTime);
    lfo(0.47 + index * 0.05, this.wowDepth);
    lfo(6.9 + index * 0.3, this.flutterDepth);
    sat.connect(wow);

    this.level = g(0);
    if (typeof ctx.createStereoPanner === 'function') {
      this.pan = ctx.createStereoPanner();
      this.nodes.push(this.pan);
      wow.connect(this.pan);
      this.pan.connect(this.level);
    } else {
      this.pan = null;
      wow.connect(this.level);
    }
    this.level.connect(music);
    this.send = g(ROLE_SEND[role]);
    this.level.connect(this.send);
    this.send.connect(reverb);
    this.applyPan();
  }

  setWidth(width: number): void {
    this.width = width;
    this.applyPan();
  }

  private applyPan(): void {
    if (!this.pan) return;
    const p = Math.max(-0.85, Math.min(0.85, TAPE_PAN[this.index] * ROLE_WIDTH[this.role] * this.width));
    this.pan.pan.setTargetAtTime(p, this.ctx.currentTime, 0.3);
  }

  setColour(c: LayerColour, sendScale: number): void {
    this.colour = c;
    const t = this.ctx.currentTime;
    const d = Math.max(0, Math.min(1, c.drift));
    // Faster layers carry more notes per second; trim them so a 4x layer does not dominate.
    const speedTrim = c.speed > 1 ? 1 / (1 + 0.18 * Math.log2(c.speed)) : 1;
    const level = c.present ? ROLE_LEVEL[this.role] * speedTrim * (c.dead ? 0.8 : 1) : 0;
    this.level.gain.setTargetAtTime(level, t, GLIDE);
    this.lp.frequency.setTargetAtTime(c.dead ? 2600 : 12500 - 5500 * d, t, GLIDE);
    // A hollow ghost keeps some body: bass and drums are thinned, not removed.
    const deadHp = this.role === 'bass' || this.role === 'drums' ? 140 : 320;
    this.hp.frequency.setTargetAtTime(c.dead ? deadHp : this.role === 'bass' || this.role === 'drums' ? 25 : 70, t, GLIDE);
    this.presence.gain.setTargetAtTime(c.dead ? 5 : 0, t, GLIDE);
    this.chorusWet.gain.setTargetAtTime(0.5 * d, t, GLIDE);
    this.chorusDepth.gain.setTargetAtTime(0.004 * d, t, GLIDE);
    this.wowDepth.gain.setTargetAtTime(0.00045 + 0.0016 * d, t, GLIDE);
    this.flutterDepth.gain.setTargetAtTime(0.00006 + 0.00022 * d, t, GLIDE);
    this.send.gain.setTargetAtTime(ROLE_SEND[this.role] * sendScale * (c.dead ? 2.2 : 1 + 0.6 * d), t, GLIDE);
  }

  refreshSend(sendScale: number): void {
    this.setColour(this.colour, sendScale);
  }

  dispose(): void {
    for (const o of this.lfos) {
      try {
        o.stop();
      } catch {
        /* stopped */
      }
    }
    for (const n of [...this.lfos, ...this.nodes]) {
      try {
        n.disconnect();
      } catch {
        /* gone */
      }
    }
  }
}

export class Mixer {
  readonly music: GainNode;
  readonly sfx: GainNode;
  /** Count-in and UI blips: under the master volume, independent of the music fader. */
  readonly ui: GainNode;
  layers: LayerBus[];
  private readonly master: GainNode;
  private readonly tone: BiquadFilterNode;
  private readonly shelf: BiquadFilterNode;
  private readonly reverbIn: GainNode;
  private readonly reverbOut: GainNode;
  private readonly nodes: AudioNode[] = [];
  private mode: MixMode = 'menu';
  private sendScale = 1;

  constructor(
    private readonly ctx: BaseAudioContext,
    roles: readonly MusicRole[],
  ) {
    const g = (v: number) => {
      const n = ctx.createGain();
      n.gain.value = v;
      this.nodes.push(n);
      return n;
    };
    this.master = g(0.8);
    const limiter = ctx.createDynamicsCompressor();
    limiter.threshold.value = -2;
    limiter.knee.value = 0;
    limiter.ratio.value = 20;
    limiter.attack.value = 0.002;
    limiter.release.value = 0.08;
    const glue = ctx.createDynamicsCompressor();
    glue.threshold.value = -15;
    glue.knee.value = 10;
    glue.ratio.value = 3;
    glue.attack.value = 0.01;
    glue.release.value = 0.2;
    this.nodes.push(limiter, glue);
    this.shelf = ctx.createBiquadFilter();
    this.shelf.type = 'highshelf';
    this.shelf.frequency.value = 5200;
    this.shelf.gain.value = -1.5;
    this.nodes.push(this.shelf);
    const pre = g(1);
    pre.connect(this.shelf);
    this.shelf.connect(glue);
    glue.connect(limiter);
    limiter.connect(this.master);
    this.master.connect(ctx.destination);

    const convolver = ctx.createConvolver();
    convolver.buffer = impulse(ctx, 2.3);
    this.nodes.push(convolver);
    this.reverbIn = g(1);
    this.reverbOut = g(0.32);
    const reverbHp = ctx.createBiquadFilter();
    reverbHp.type = 'highpass';
    reverbHp.frequency.value = 180;
    this.nodes.push(reverbHp);
    this.reverbIn.connect(reverbHp);
    reverbHp.connect(convolver);
    convolver.connect(this.reverbOut);
    this.reverbOut.connect(pre);

    this.tone = ctx.createBiquadFilter();
    this.tone.type = 'lowpass';
    this.tone.frequency.value = 20000;
    this.tone.Q.value = 0.5;
    this.nodes.push(this.tone);
    const musicSum = g(1);
    musicSum.connect(this.tone);
    this.tone.connect(pre);
    this.music = g(0.8);
    this.music.connect(musicSum);
    this.sfx = g(0.8);
    this.sfx.connect(pre);
    const sfxSend = g(0.12);
    this.sfx.connect(sfxSend);
    sfxSend.connect(this.reverbIn);
    this.ui = g(0.8);
    this.ui.connect(pre);

    this.layers = roles.map((role, i) => new LayerBus(ctx, i, role, this.music, this.reverbIn));
  }

  setVolumes(master: number, music: number, sfx: number): void {
    const t = this.ctx.currentTime;
    this.master.gain.setTargetAtTime(master, t, 0.03);
    this.music.gain.setTargetAtTime(music, t, 0.03);
    this.sfx.gain.setTargetAtTime(sfx, t, 0.03);
    this.ui.gain.setTargetAtTime(Math.max(sfx, 0.0001) ** 0.5 * 0.9, t, 0.03);
  }

  /** Cinematic opens the mix (wider, brighter, more room); menus sit back. Notes are untouched. */
  setMode(mode: MixMode): void {
    this.mode = mode;
    const t = this.ctx.currentTime;
    const cine = mode === 'cinematic';
    this.shelf.gain.setTargetAtTime(cine ? 3 : -1.5, t, 0.4);
    this.tone.frequency.setTargetAtTime(mode === 'menu' ? 3200 : 20000, t, 0.4);
    this.reverbOut.gain.setTargetAtTime(cine ? 0.46 : 0.32, t, 0.4);
    this.sendScale = cine ? 1.35 : 1;
    for (const l of this.layers) {
      l.setWidth(cine ? 1.6 : 1);
      l.refreshSend(this.sendScale);
    }
  }

  get currentMode(): MixMode {
    return this.mode;
  }

  /** A new level may give the cassettes different roles; rebuild the four buses for them. */
  setRoles(roles: readonly MusicRole[]): void {
    for (const l of this.layers) l.dispose();
    this.layers = roles.map((role, i) => new LayerBus(this.ctx, i, role, this.music, this.reverbIn));
    for (const l of this.layers) l.setWidth(this.mode === 'cinematic' ? 1.6 : 1);
  }

  setLayerColour(i: number, c: LayerColour): void {
    this.layers[i]?.setColour(c, this.sendScale);
  }

  dispose(): void {
    for (const l of this.layers) l.dispose();
    for (const n of this.nodes) {
      try {
        n.disconnect();
      } catch {
        /* gone */
      }
    }
  }
}
