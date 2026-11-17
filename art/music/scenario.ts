/**
 * Plays every piece through the game's real LayerSequencer (prototype/src/audio/sequencer.ts) on a
 * scripted attempt: cassettes join one at a time at different tape speeds, one self desyncs and
 * resyncs (drift ramps up and back down bar by bar), one dies, one tape reverses and then stops.
 * Checks that the whole timeline stays in key and how rough the downbeats get.
 *
 *   cd prototype && npx vite-node ../art/music/scenario.ts
 */
import { MusicDirector } from '../../prototype/src/audio/director';
import { LayerSequencer } from '../../prototype/src/audio/sequencer';
import { isHarsh, loadPieces } from './lib';

type TS = { present: boolean; speed: 0.5 | 1 | 2 | 4; life: 'alive' | 'ghost'; synced: boolean; transport: 1 | -1 | 0 };
const T = (present: boolean, speed: TS['speed'] = 1, o: Partial<TS> = {}): TS => ({ present, speed, life: 'alive', synced: true, transport: 1, ...o });

/** [bar, states of cassettes 1..4] */
const SCRIPT: [number, TS[]][] = [
  [0, [T(true, 1), T(false), T(false), T(false)]],
  [2, [T(true, 1), T(true, 2), T(false), T(false)]],
  [4, [T(true, 1), T(true, 2), T(true, 0.5), T(false)]],
  [6, [T(true, 1), T(true, 2), T(true, 0.5), T(true, 4)]],
  [8, [T(true, 1), T(true, 2), T(true, 0.5, { synced: false }), T(true, 4)]],
  [13, [T(true, 1), T(true, 2), T(true, 0.5), T(true, 4)]],
  [16, [T(true, 1), T(true, 2, { life: 'ghost' }), T(true, 0.5), T(true, 4)]],
  [18, [T(true, 1, { transport: -1 }), T(true, 2, { life: 'ghost' }), T(true, 0.5), T(true, 4)]],
  [20, [T(true, 1, { transport: -1 }), T(true, 2, { life: 'ghost' }), T(true, 0.5, { synced: false }), T(true, 4, { transport: 0 })]],
  [22, [T(true, 1, { transport: 0 }), T(true, 2, { life: 'ghost', transport: 0 }), T(true, 0.5, { life: 'ghost' }), T(true, 4, { transport: 0 })]],
];
const END = 24;

console.log('piece               notes  inScale%  harshDown%  harshBeat%  onsets/bar(min-max)  driftLevels(T3)');
let worst = 0, allIn = true;
for (const p of loadPieces()) {
  const d = new MusicDirector({ bpm: p.bpm, music: p.music as any });
  const seq = new LayerSequencer(d);
  const scale = new Set(d.scalePcs);
  const roles = p.music.tracks.map((t) => t.role);
  let notes = 0, inScale = 0, pairsD = 0, harshD = 0, pairsB = 0, harshB = 0, minBar = 1e9, maxBar = 0;
  const drifts: number[] = [];
  const all: { beat: number; duration: number; pitch: number; track: number }[] = [];
  for (let bar = 0; bar < END; bar++) {
    const ev = SCRIPT.filter(([b]) => b === bar)[0];
    if (ev) seq.setTracks(ev[1] as any, bar * 4);
    const ns = seq.collect(bar * 4, bar * 4 + 4);
    drifts.push(seq.drift.at(2, bar));
    minBar = Math.min(minBar, ns.length);
    maxBar = Math.max(maxBar, ns.length);
    for (const n of ns) {
      if (roles[n.track] === 'drums') continue;
      notes++;
      if (scale.has(n.pitch % 12)) inScale++;
      all.push(n);
    }
  }
  for (let b = 0; b < END * 4; b++) {
    const t = b + 0.085;
    const snd = all.filter((n) => n.beat <= t && n.beat + n.duration > t);
    for (let i = 0; i < snd.length; i++)
      for (let j = i + 1; j < snd.length; j++) {
        if (snd[i].track === snd[j].track) continue;
        const h = isHarsh(Math.abs(snd[i].pitch - snd[j].pitch)) ? 1 : 0;
        pairsB++; harshB += h;
        if (b % 4 === 0) { pairsD++; harshD += h; }
      }
  }
  const hd = (100 * harshD) / Math.max(1, pairsD);
  worst = Math.max(worst, hd);
  if (inScale !== notes) allIn = false;
  console.log(`${p.id.padEnd(19)} ${String(notes).padStart(5)}  ${((100 * inScale) / notes).toFixed(1).padStart(7)}  ${hd.toFixed(1).padStart(9)}  ${((100 * harshB) / Math.max(1, pairsB)).toFixed(1).padStart(9)}  ${`${minBar}-${maxBar}`.padStart(12)}         ${drifts.slice(7, 16).join(' ')}`);
}
console.log(`all in key: ${allIn}; worst downbeat harsh ${worst.toFixed(1)}%`);
