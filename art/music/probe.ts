/**
 * Probe: how much of each layer changes when its tape reverses (share of steps whose pitch set differs).
 *   cd prototype && npx vite-node ../art/music/probe.ts
 */
import { MusicDirector } from '../../prototype/src/audio/director';
import { loadPieces, mapNotes, variant } from './lib';

for (const p of loadPieces()) {
  const d = new MusicDirector({ bpm: p.bpm, music: p.music as any });
  const row = p.music.tracks.map((t, i) => {
    const sig = (ns: any[]) => { const m = new Map<number, string>(); for (const n of ns) m.set(n.step, (m.get(n.step) ?? '') + (n.drum ?? n.pitch) + ','); return m; };
    const a = sig(mapNotes(d, p.stateMaps, i, variant(1), 16)), b = sig(mapNotes(d, p.stateMaps, i, variant(1, { transport: -1 }), 16));
    const keys = new Set([...a.keys(), ...b.keys()]);
    let ch = 0;
    for (const k of keys) if (a.get(k) !== b.get(k)) ch++;
    return `${t.role}:${t.formula} ${Math.round((100 * ch) / Math.max(1, keys.size))}%`;
  });
  console.log(p.id.padEnd(19), row.join('  '));
}
