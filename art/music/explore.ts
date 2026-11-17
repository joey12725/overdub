/**
 * Explore: Rewind (09) is meant to be palindromic, so a reversing tape still plays the tune.
 * Searches lead and bass variants for the smallest share of steps changed by reversal, and prints
 * the analysis score beside it so the trade-off is visible.
 *   cd prototype && npx vite-node ../art/music/explore.ts
 */
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { MusicDirector } from '../../prototype/src/audio/director';
import { analyse, HERE, mapNotes, variant, type MusicDef, type StateMaps } from './lib';
import { STATE_MAPS } from './statemaps';

const maps = STATE_MAPS as unknown as StateMaps;
const base: MusicDef = JSON.parse(readFileSync(join(HERE, 'tuned.json'), 'utf8'))['09-rewind'].music;
const bpm = 120;
function revChange(m: MusicDef, track: number): number {
  const d = new MusicDirector({ bpm, music: m as any });
  let ch = 0, n = 0;
  for (const s of [0.5, 1, 2] as const) {
    const sig = (ns: any[]) => { const mm = new Map<number, string>(); for (const x of ns) mm.set(x.step, (mm.get(x.step) ?? '') + x.pitch + ','); return mm; };
    const a = sig(mapNotes(d, maps, track, variant(s), 16)), b = sig(mapNotes(d, maps, track, variant(s, { transport: -1 }), 16));
    const keys = new Set([...a.keys(), ...b.keys()]);
    for (const k of keys) { n++; if (a.get(k) !== b.get(k)) ch++; }
  }
  return (100 * ch) / Math.max(1, n);
}
const rows: { track: number; desc: string; rev: number; score: number }[] = [];
const tryTrack = (track: number, formula: string, params: Record<string, number>) => {
  const m: MusicDef = JSON.parse(JSON.stringify(base));
  m.tracks[track] = { ...m.tracks[track], formula, params };
  rows.push({ track, desc: `${formula} ${JSON.stringify(params)}`, rev: revChange(m, track), score: analyse({ id: '09', bpm, music: m, stateMaps: maps }).score });
};
for (const cycle of [8, 16])
  for (const cycles of [1, 2])
    for (const off of [0.25, 0.75])
      for (const contour of [0, 0.15, 0.3])
        for (const pulses of [5, 4]) {
          // Phase that puts the mirror axis of the triangle between the two middle samples of the cycle.
          const phase = (((off - (cycles * (cycle - 1)) / (2 * cycle)) % 1) + 1) % 1;
          tryTrack(0, 'triangle', { cycles, phase, contour, cycle, register: 0, pulses, steps: 8 });
        }
for (const cycle of [8, 16])
  for (const contour of [0, 0.1, 0.25])
    for (const [f, fp] of [['ruler', {}], ['thue', {}], ['triangle', { cycles: 1, phase: (((0.25 - (cycle - 1) / (2 * cycle)) % 1) + 1) % 1 }], ['sine', { cycles: 1, phase: (((0.25 - (cycle - 1) / (2 * cycle)) % 1) + 1) % 1 }]] as [string, Record<string, number>][])
      for (const [pulses, steps] of [[3, 8], [4, 8], [2, 4]])
        tryTrack(1, f, { ...fp, contour, cycle, register: -1, pulses, steps });
for (const t of [0, 1]) {
  console.log(`track ${t + 1}: best by reversal change`);
  for (const r of rows.filter((x) => x.track === t).sort((a, b) => a.rev - b.rev || b.score - a.score).slice(0, 8)) console.log(`  rev ${r.rev.toFixed(0).padStart(3)}%  score ${r.score}  ${r.desc}`);
}
