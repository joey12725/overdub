/**
 * IAudio implementation: wires the pure music logic (director, sequencer, scheduler, SFX planner,
 * pulse meter) to Web Audio (mixer, voices) and the Web Speech count-in.
 *
 * Safe everywhere: constructing it touches no Web Audio API; until `unlock()` succeeds (or forever,
 * in node) the scheduler still runs on a virtual clock so `pulse()` keeps describing the music,
 * but nothing is played.
 */
import type { IAudio, MusicPulse, TrackAudioState } from '../contracts';
import type { LevelDef, SimEvent, TapeIndex } from '../core/types';
import { BEATS_PER_BAR, TAPE_COUNT } from '../core/types';
import { MusicDirector } from './director';
import type { MusicRole } from './formulas';
import { Mixer, type MixMode } from './mixer';
import { PulseMeter, silentPulse } from './pulse';
import { TransportScheduler, type SchedulerUpdate } from './scheduler';
import { LayerSequencer } from './sequencer';
import { SfxPlanner } from './sfx';
import { cancelSpeech, primeSpeech, speakCount } from './speech';
import { playCue, playLayerNote, playTick, playUi, type UiKind, type Voice } from './voices';

/** After this long without setTransport the frame loop has stalled (hidden tab): stop the music. */
const STALE_TRANSPORT = 0.25;
const TICK_MS = 25;
const MAX_MUSIC_VOICES = 160;
const MAX_SFX_VOICES = 40;
const COUNT_DEGREES: Record<5 | 6 | 7 | 8, number> = { 5: 0, 6: 2, 7: 4, 8: 7 };

/** Harmony for UI / count-in sounds before any level is loaded: A minor, calm tempo. */
const FALLBACK_LEVEL: Pick<LevelDef, 'bpm' | 'music'> = {
  bpm: 100,
  music: {
    root: 9,
    scale: 'Minor',
    progression: [0],
    tracks: [
      { role: 'melody', formula: 'sine' },
      { role: 'bass', formula: 'triangle' },
      { role: 'drums', formula: 'euclid' },
      { role: 'chord', formula: 'sine' },
    ],
  },
};

const SILENT_TRACK: TrackAudioState = { present: false, speed: 1, life: 'alive', synced: true, transport: 1 };

type AudioCtor = new (opts?: AudioContextOptions) => AudioContext;

function audioContextCtor(): AudioCtor | null {
  const g = globalThis as { AudioContext?: AudioCtor; webkitAudioContext?: AudioCtor };
  return g.AudioContext ?? g.webkitAudioContext ?? null;
}

function wallSeconds(): number {
  return (typeof performance !== 'undefined' ? performance.now() : Date.now()) / 1000;
}

/** Volumes arrive as 0..1; a 0..100 slider value is accepted too. */
function unitVolume(v: number): number {
  if (!Number.isFinite(v)) return 0;
  const x = v > 1 ? v / 100 : v;
  return Math.min(1, Math.max(0, x));
}

export class AudioEngine implements IAudio {
  private ctx: AudioContext | null = null;
  private mixer: Mixer | null = null;
  private timer: ReturnType<typeof setInterval> | null = null;
  private director: MusicDirector = new MusicDirector(FALLBACK_LEVEL);
  private loaded = false;
  private seq: LayerSequencer = new LayerSequencer(this.director);
  private sched: TransportScheduler = this.makeScheduler();
  private readonly planner = new SfxPlanner();
  private readonly meter = new PulseMeter();
  private readonly music = new Map<number, Voice>();
  private sfxVoices: Voice[] = [];
  private tracks: TrackAudioState[] = [SILENT_TRACK, SILENT_TRACK, SILENT_TRACK, SILENT_TRACK];
  private transport = { beat: 0, rate: 0, playing: false, at: 0 };
  private clockIsAudio = false;
  private volumes = { master: 0.8, music: 0.8, sfx: 0.8 };
  private mode: MixMode = 'record';
  private colourKey = '';
  private disposed = false;

  // ───────────────────────────── IAudio ─────────────────────────────

  async unlock(): Promise<void> {
    if (this.disposed) return;
    primeSpeech();
    const Ctor = audioContextCtor();
    if (!Ctor) return;
    try {
      if (!this.ctx) {
        this.ctx = new Ctor({ latencyHint: 'interactive' });
        this.mixer = new Mixer(this.ctx, this.roles());
        this.mixer.setVolumes(this.volumes.master, this.volumes.music, this.volumes.sfx);
        this.mixer.setMode(this.mode);
        this.colourKey = '';
        this.timer = setInterval(() => this.tick(), TICK_MS);
      }
      if (this.ctx.state !== 'running') await this.ctx.resume();
    } catch {
      // Autoplay refused or the device is gone: stay silent, keep the virtual clock.
    }
    this.tick();
  }

  loadLevel(level: LevelDef): void {
    this.stopAllMusic();
    this.director = new MusicDirector(level);
    this.loaded = true;
    this.seq = new LayerSequencer(this.director);
    this.sched = this.makeScheduler();
    this.meter.clear();
    this.planner.reset();
    this.seq.setTracks(this.tracks, this.currentBeat(this.now()));
    this.mixer?.setRoles(this.roles());
    this.colourKey = '';
    this.tick();
  }

  setTransport(masterBeat: number, rate: number, playing: boolean): void {
    const now = this.now();
    const beat = Number.isFinite(masterBeat) ? Math.max(0, masterBeat) : 0;
    // Every take (and every review) restarts at beat 0 with fresh selves.
    if (beat + 0.5 < this.transport.beat || (beat < 1e-6 && this.transport.beat > 1e-6)) this.seq.restart();
    this.transport = { beat, rate: Number.isFinite(rate) ? Math.max(0, rate) : 0, playing, at: now };
    this.tick(now);
  }

  setTracks(tracks: [TrackAudioState, TrackAudioState, TrackAudioState, TrackAudioState]): void {
    this.tracks = tracks.map((t) => ({ ...(t ?? SILENT_TRACK) }));
    const now = this.now();
    if (this.seq.setTracks(this.tracks, this.currentBeat(now))) {
      this.applyCancel(this.sched.invalidate(now));
      this.tick(now);
    }
  }

  onEvents(events: SimEvent[]): void {
    if (!events.length || !this.loaded) return;
    const ctx = this.audible();
    if (!ctx || !this.mixer) return;
    const now = ctx.currentTime;
    const cues = this.planner.plan(
      events,
      { now, beat: this.currentBeat(now), rate: this.transport.rate, playing: this.isRunning(now), bpm: this.director.bpm },
      this.director,
    );
    for (const cue of cues) this.addSfx(playCue(ctx, this.mixer.sfx, cue));
  }

  countIn(n: 5 | 6 | 7 | 8): void {
    const degree = COUNT_DEGREES[n];
    if (degree === undefined) return;
    const ctx = this.audible();
    if (ctx && this.mixer) {
      // Rising scale degrees 1-3-5-8 lead into the downbeat; "eight" is accented.
      this.addSfx(playTick(ctx, this.mixer.ui, this.director.scaleMidi(degree, 5), ctx.currentTime, n === 8));
    }
    speakCount(n, this.volumes.master * this.volumes.sfx, this.director.bpm);
  }

  ui(kind: UiKind): void {
    const ctx = this.audible();
    if (!ctx || !this.mixer) return;
    this.addSfx(playUi(ctx, this.mixer.ui, kind, (d) => this.director.scaleMidi(d, 5), ctx.currentTime));
  }

  setMode(mode: MixMode): void {
    this.mode = mode;
    this.mixer?.setMode(mode);
  }

  setVolumes(master: number, music: number, sfx: number): void {
    this.volumes = { master: unitVolume(master), music: unitVolume(music), sfx: unitVolume(sfx) };
    this.mixer?.setVolumes(this.volumes.master, this.volumes.music, this.volumes.sfx);
  }

  pulse(): MusicPulse {
    const now = this.now();
    const beat = this.currentBeat(now);
    const chord = this.loaded ? this.director.chordAt(beat).index : 0;
    if (!this.loaded) return silentPulse(beat, chord);
    // Levels follow what is heard, so compensate for the output latency of the device.
    const ctx = this.clockIsAudio ? this.ctx : null;
    const latency = ctx ? (ctx.outputLatency || 0) + (ctx.baseLatency || 0) : 0;
    return this.meter.sample(now - latency, beat, chord);
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    if (this.timer !== null) clearInterval(this.timer);
    this.timer = null;
    this.stopAllMusic();
    for (const v of this.sfxVoices) v.release(this.ctx?.currentTime ?? 0);
    this.sfxVoices = [];
    cancelSpeech();
    this.mixer?.dispose();
    this.mixer = null;
    const ctx = this.ctx;
    this.ctx = null;
    if (ctx) void ctx.close().catch(() => undefined);
  }

  // ───────────────────────────── internals ─────────────────────────────

  private makeScheduler(): TransportScheduler {
    return new TransportScheduler((from, to) => this.seq.collect(from, to), { bpm: this.director.bpm });
  }

  private roles(): MusicRole[] {
    return [0, 1, 2, 3].map((i) => this.director.layer(i as TapeIndex).role);
  }

  /** The AudioContext when it can actually make sound. */
  private audible(): AudioContext | null {
    return this.ctx && this.ctx.state === 'running' && !this.disposed ? this.ctx : null;
  }

  private now(): number {
    const ctx = this.audible();
    return ctx ? ctx.currentTime : wallSeconds();
  }

  private isRunning(now: number): boolean {
    const t = this.transport;
    return t.playing && t.rate > 0 && now - t.at <= STALE_TRANSPORT;
  }

  private currentBeat(now: number): number {
    const t = this.transport;
    if (!t.playing || !(t.rate > 0)) return t.beat;
    const dt = Math.min(Math.max(0, now - t.at), STALE_TRANSPORT);
    return t.beat + dt * t.rate * (this.director.bpm / 60);
  }

  private tick(nowArg?: number): void {
    if (this.disposed) return;
    const audioClock = this.audible() !== null;
    if (audioClock !== this.clockIsAudio) {
      // The note clock changed (unlock, or the context was suspended): plans on the old clock are void.
      this.clockIsAudio = audioClock;
      this.applyCancel(this.sched.reset());
      this.stopAllMusic();
      this.meter.clear();
      this.transport.at = this.now();
      nowArg = undefined;
    }
    const now = nowArg ?? this.now();
    const running = this.isRunning(now);
    const beat = this.currentBeat(now);
    this.applyUpdate(this.sched.update(now, beat, this.transport.rate, running), now);
    this.updateColours(beat);
    this.pruneVoices(now);
  }

  private applyUpdate(u: SchedulerUpdate, now: number): void {
    this.applyCancel(u.cancel);
    if (u.choke) for (const v of this.music.values()) if (v.start <= now) v.release(now);
    const ctx = this.audible();
    for (const p of u.start) {
      this.meter.add(p);
      if (!ctx || !this.mixer || this.music.size >= MAX_MUSIC_VOICES) continue;
      const bus = this.mixer.layers[p.note.track];
      if (!bus) continue;
      this.music.set(p.id, playLayerNote(ctx, bus.input, this.director.layer(p.note.track).role, p.note, p.time, p.dur));
    }
  }

  private applyCancel(cancelled: readonly { id: number }[]): void {
    if (!cancelled.length) return;
    for (const p of cancelled) {
      this.music.get(p.id)?.cancel();
      this.music.delete(p.id);
    }
    this.meter.cancel(cancelled.map((p) => p.id));
  }

  private stopAllMusic(): void {
    const at = this.ctx?.currentTime ?? 0;
    for (const v of this.music.values()) {
      if (v.start > at) v.cancel();
      else v.release(at);
    }
    this.music.clear();
  }

  private addSfx(v: Voice): void {
    this.sfxVoices.push(v);
    if (this.sfxVoices.length > MAX_SFX_VOICES) {
      const now = this.ctx?.currentTime ?? 0;
      this.sfxVoices.sort((a, b) => a.end - b.end);
      const drop = this.sfxVoices.splice(0, this.sfxVoices.length - MAX_SFX_VOICES);
      for (const d of drop) d.release(now);
    }
  }

  private pruneVoices(now: number): void {
    for (const [id, v] of this.music) if (v.end < now) this.music.delete(id);
    if (this.sfxVoices.length) this.sfxVoices = this.sfxVoices.filter((v) => v.end >= now);
  }

  /** Bus colour follows the same variant the notes were composed with (MUSIC-08). */
  private updateColours(beat: number): void {
    if (!this.mixer) return;
    const bar = Math.max(0, Math.floor(beat / BEATS_PER_BAR));
    const colours = [];
    for (let i = 0; i < TAPE_COUNT; i++) {
      const v = this.seq.variantAt(i as TapeIndex, bar);
      colours.push(v ? { present: true, dead: v.dead, drift: v.drift, speed: v.speed } : { present: false, dead: false, drift: 0, speed: 1 });
    }
    const key = JSON.stringify(colours);
    if (key === this.colourKey) return;
    this.colourKey = key;
    colours.forEach((c, i) => this.mixer?.setLayerColour(i, c));
  }
}

export function createAudio(): IAudio {
  return new AudioEngine();
}
