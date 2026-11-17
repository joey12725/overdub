/**
 * Proves the state-map DATA is a faithful description of the game's behaviour: for every piece,
 * layer, tape speed and actor state, the notes built from data/music/*.json "stateMaps"
 * (lib.mapNotes) are compared note-for-note with the prototype's MusicDirector (lib.protoNotes).
 *
 *   cd prototype && npx vite-node ../art/music/verify-statemaps.ts [-- --drafts]
 */
import { MusicDirector } from '../../prototype/src/audio/director';
import { loadPieces, mapNotes, protoNotes, SPEEDS4, variant, type StateMaps } from './lib';
import { DRAFTS } from './pieces';
import { STATE_MAPS } from './statemaps';

const drafts = process.argv.includes('--drafts');
const pieces = drafts ? Object.entries(DRAFTS).map(([id, p]) => ({ id, bpm: p.bpm, music: p.music, stateMaps: STATE_MAPS as unknown as StateMaps })) : loadPieces();
let compared = 0, notes = 0, bad = 0;
for (const p of pieces) {
  const d = new MusicDirector({ bpm: p.bpm, music: p.music as any });
  for (let t = 0; t < 4; t++)
    for (const s of SPEEDS4)
      for (const dead of [false, true])
        for (const transport of [1, -1, 0] as const)
          for (const drift of dead ? [0] : [0, 0.25, 0.5, 0.75, 1]) {
            const v = variant(s, { dead, transport, drift });
            const a = protoNotes(d, t, v, 8);
            const b = mapNotes(d, p.stateMaps, t, v, 8);
            compared++;
            notes += a.length;
            const ja = JSON.stringify(a), jb = JSON.stringify(b);
            if (ja !== jb) {
              bad++;
              if (bad <= 5) console.log(`MISMATCH ${p.id} T${t + 1} ${JSON.stringify(v)}: proto ${a.length} notes, map ${b.length} notes`);
            }
          }
}
console.log(`${pieces.length} pieces, ${compared} layer variants, ${notes} notes compared: ${bad} mismatching variants`);
if (bad) process.exit(1);
