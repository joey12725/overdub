/**
 * Checks the SFX pitch policy of a piece: every tone of every event class, for every cassette and
 * every chord of the progression, must be in the level scale; chord-sourced tones are chord tones by
 * construction, scale-sourced tones are checked for rubs (minor second / tritone) against the triad.
 */
import { MusicDirector } from '../../prototype/src/audio/director';
import { HG } from '../../prototype/src/audio/hg';
import type { MusicDef } from './lib';
import type { SfxClass, Tone } from './statemaps';

export function tonePitch(d: MusicDirector, tone: Tone, tape: number, chordBeat: number): number {
  if (tone.from === 'scale') return 12 * (tone.octave + 1) + HG.degreeMidi(tone.index, { root: d.root, scale: d.scale });
  const chord = d.chordAt(chordBeat, 0);
  const pcs = chord.pcs.length ? chord.pcs : [chord.root];
  const base = 12 * (tone.octave + 1) + chord.root;
  const stack = pcs.map((pc) => base + ((((pc - chord.root) % 12) + 12) % 12)).sort((a, b) => a - b);
  const i = tone.index + (tone.perTape ? tape : 0);
  const idx = ((i % stack.length) + stack.length) % stack.length;
  return stack[idx] + 12 * Math.floor(i / stack.length);
}

export function checkSfx(piece: { bpm: number; music: MusicDef; sfx: { classes: Record<string, SfxClass>; ui?: Record<string, any> } }) {
  const d = new MusicDirector({ bpm: piece.bpm, music: piece.music as any });
  const scale = new Set(d.scalePcs);
  let tones = 0, inScale = 0, chordTones = 0, tense = 0, lo = 127, hi = 0;
  const tenseClasses = new Set<string>();
  for (const [name, cls] of Object.entries(piece.sfx.classes)) {
    for (const list of [cls.tones, cls.off, cls.heavy]) {
      if (!list) continue;
      for (let ci = 0; ci < d.progression.length; ci++) {
        const beat = ci * d.chordBeats;
        const triad = d.chordAt(beat, 0).pcs;
        for (let tape = 0; tape < 4; tape++) {
          for (const tone of list) {
            const p = tonePitch(d, tone, tape, beat);
            tones++;
            lo = Math.min(lo, p); hi = Math.max(hi, p);
            if (scale.has(p % 12)) inScale++;
            if (triad.includes(p % 12)) chordTones++;
            else if (triad.some((pc) => [1, 6, 11].includes((((p - pc) % 12) + 12) % 12))) { tense++; tenseClasses.add(name); }
          }
        }
      }
    }
  }
  let ui = 0, uiIn = 0;
  const walk = (x: any) => {
    if (Array.isArray(x)) x.forEach(walk);
    else if (x && typeof x === 'object') {
      if (x.from === 'scale') { ui++; if (scale.has(tonePitch(d, x, 0, 0) % 12)) uiIn++; }
      else Object.values(x).forEach(walk);
    }
  };
  walk(piece.sfx.ui ?? {});
  return {
    tonesChecked: tones + ui,
    inScalePct: (100 * (inScale + uiIn)) / Math.max(1, tones + ui),
    chordTonePct: (100 * chordTones) / Math.max(1, tones),
    tensePct: (100 * tense) / Math.max(1, tones),
    tenseClasses: [...tenseClasses],
    lowestMidi: lo,
    highestMidi: hi,
  };
}
