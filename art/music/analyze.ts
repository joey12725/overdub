/**
 * Measures every piece across the whole speed / subset / state matrix.
 *
 *   cd prototype && npx vite-node ../art/music/analyze.ts            # data/music/*.json  -> art/music/out/metrics.json
 *   cd prototype && npx vite-node ../art/music/analyze.ts -- --drafts # first-pass drafts -> art/music/out/metrics-drafts.json
 *   ... -- --only 07 --verbose
 *
 * See docs/MUSIC.md "Analysis method" for what each number means.
 */
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { analyse, HERE, loadPieces, type LevelReport, type StateMaps } from './lib';
import { DRAFTS } from './pieces';
import { STATE_MAPS } from './statemaps';
import { checkSfx } from './sfxcheck';

const args = process.argv.slice(2);
const drafts = args.includes('--drafts');
const verbose = args.includes('--verbose');
const only = args.includes('--only') ? args[args.indexOf('--only') + 1] : null;

const pieces = drafts
  ? Object.entries(DRAFTS).map(([id, p]) => ({ id, bpm: p.bpm, music: p.music, stateMaps: STATE_MAPS as unknown as StateMaps }))
  : loadPieces();

const f = (x: number, d = 1) => x.toFixed(d);
const reports: LevelReport[] = [];
console.log(`${drafts ? 'DRAFTS (before)' : 'data/music (after)'} — 16 master bars per stream`);
console.log(
  ['piece'.padEnd(19), 'key'.padEnd(20), 'score', 'scale%', 'hDn', 'hDnW', 'hBt', 'h4x', 'pairW', 'ctDn%', 'g16%', 'g32%', 'mix/bar', 'mud%', 'clus%', 'lead%', 'st+rp', 'leap', 'rng', 'bars', 'dead', 'drift%', 'flags'].join(' '),
);
for (const p of pieces) {
  if (only && !p.id.includes(only)) continue;
  const r = analyse(p);
  reports.push(r);
  const m = r.melody['1'];
  console.log(
    [
      r.id.padEnd(19),
      r.key.padEnd(20),
      f(r.score).padStart(5),
      f(r.inScalePct, 0).padStart(6),
      f(r.harshDownMean81).padStart(4),
      f(r.harshDownWorst81).padStart(4),
      f(r.harshBeatMean81).padStart(4),
      f(r.harshDownMean4x).padStart(4),
      f(r.harshDownWorstPair, 0).padStart(5),
      f(r.chordToneDownPct, 0).padStart(5),
      f(r.grid16Pct, 0).padStart(4),
      f(r.grid32Pct4x, 0).padStart(4),
      `${r.mixMinPerBar}-${r.mixMaxPerBar}`.padStart(7),
      f(r.mudPct).padStart(4),
      f(r.chordClusterPct, 0).padStart(5),
      f(r.leadAboveChordPct, 0).padStart(5),
      m ? f(m.stepPct + m.repeatPct, 0).padStart(5) : '    -',
      m ? f(m.leapPct, 0).padStart(4) : '   -',
      m ? String(m.range).padStart(3) : '  -',
      m ? String(m.distinctBars).padStart(4) : '   -',
      f(r.states.deadDensityRatio, 2).padStart(4),
      f(r.states.driftChangedPct, 0).padStart(6),
      r.densityFlags.length ? r.densityFlags.join('; ') : '-',
    ].join(' '),
  );
  if (verbose) {
    console.log('   penalties', JSON.stringify(r.penalties));
    console.log('   worst pair', r.worstPairLabel, '| ic hist down %', r.icHistogramDownPct.map((x) => f(x, 0)).join(' '));
    r.roles.forEach((role, i) => console.log(`   T${i + 1} ${role.padEnd(6)} ${r.formulas[i].padEnd(12)} onsets/bar ` + Object.entries(r.layers[i]).map(([s, st]) => `${s}x:${f(st.onsetsPerBar)}(max ${st.maxPerBar}, gap ${f(st.longestGapBeats)})`).join('  ')));
    console.log('   register', r.register.map((x) => `${x.role} ${f(x.lowHz, 0)}-${f(x.highHz, 0)}Hz (med ${f(x.medianHz, 0)})`).join(' | '));
    for (const [s, c] of Object.entries(r.melody)) console.log(`   melody@${s}x notes ${c.notes} step ${f(c.stepPct, 0)} skip ${f(c.skipPct, 0)} leap ${f(c.leapPct, 0)} rep ${f(c.repeatPct, 0)} maxLeap ${c.maxLeap} range ${c.range} pitches ${c.distinctPitches} distinctBars ${c.distinctBars}/8`);
    console.log('   states', JSON.stringify(r.states));
  }
  if (!drafts) {
    const sfx = checkSfx(p as any);
    (r as any).sfx = sfx;
    if (verbose) console.log('   sfx', JSON.stringify(sfx));
  }
}
const avg = (k: (r: LevelReport) => number) => reports.reduce((a, r) => a + k(r), 0) / Math.max(1, reports.length);
console.log(`MEAN score ${f(avg((r) => r.score))}  harshDown ${f(avg((r) => r.harshDownMean81))}  worst81 ${f(Math.max(...reports.map((r) => r.harshDownWorst81)))}  inScale min ${f(Math.min(...reports.map((r) => r.inScalePct)), 2)}  notes checked ${reports.reduce((a, r) => a + r.notesChecked, 0)}`);
if (!only) {
  mkdirSync(join(HERE, 'out'), { recursive: true });
  const out = join(HERE, 'out', drafts ? 'metrics-drafts.json' : 'metrics.json');
  writeFileSync(out, JSON.stringify(reports, null, 1));
  console.log('wrote', out);
}
