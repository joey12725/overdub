/**
 * What the PLAYER can actually hear in a level: a level with maxTapes N only ever sounds cassettes
 * 1..N, at the tape speeds the level allows. This measures exactly that sub-matrix: every non-empty
 * subset of the audible cassettes, at every allowed speed combination.
 *
 * Used by compose.ts (written into data/music/*.json "inLevel") and runnable on its own:
 *   cd prototype && npx vite-node ../art/music/levelcheck.ts
 */
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { MusicDirector, type LayerNote } from '../../prototype/src/audio/director';
import { isHarsh, loadPieces, mapNotes, onsets, REPO, variant, type MusicDef, type Speed, type StateMaps } from './lib';

export interface LevelInfo {
  file: string;
  bpm: number;
  bars: number;
  horizonBars: number;
  maxTapes: number;
  speeds: Speed[];
}
export function levelInfo(id: string): LevelInfo | null {
  const file = join(REPO, 'data', 'levels', id + '.json');
  if (!existsSync(file)) return null;
  const d = JSON.parse(readFileSync(file, 'utf8'));
  return { file: `data/levels/${id}.json`, bpm: d.bpm, bars: d.bars, horizonBars: d.horizonBars ?? d.bars, maxTapes: d.maxTapes ?? 4, speeds: (d.speeds ?? [0.5, 1, 2]) as Speed[] };
}

export interface InLevelReport {
  audibleCassettes: number;
  speeds: number[];
  bars: number;
  combinationsChecked: number;
  inScalePct: number;
  /** Cross-layer harsh intervals (m2/m9/close tritone) on downbeats, over every subset x speed combination. */
  harshDownbeatPctMean: number;
  harshDownbeatPctWorst: number;
  worstCombo: string;
  /** Fewest / most onsets in any bar of any subset x speed combination (single cassettes included). */
  onsetsPerBarMin: number;
  onsetsPerBarMax: number;
  /** Turns of the chord progression inside the level horizon (a whole number loops cleanly). */
  progressionTurnsInHorizon: number;
}

export function inLevel(piece: { bpm: number; music: MusicDef; stateMaps: StateMaps }, info: { maxTapes: number; speeds: Speed[]; horizonBars: number }): InLevelReport {
  const d = new MusicDirector({ bpm: piece.bpm, music: piece.music as any });
  const bars = Math.max(8, info.horizonBars);
  const n = Math.min(4, info.maxTapes);
  const roles = piece.music.tracks.map((t) => t.role);
  const scale = new Set(d.scalePcs);
  const streams: LayerNote[][][] = [];
  let notes = 0, ok = 0;
  for (let t = 0; t < n; t++) {
    streams.push(info.speeds.map((s) => mapNotes(d, piece.stateMaps, t, variant(s), bars)));
    if (roles[t] !== 'drums') for (const ns of streams[t]) for (const x of ns) { notes++; if (scale.has(x.pitch % 12)) ok++; }
  }
  const at = (ns: LayerNote[], b: number) => ns.filter((x) => x.beat <= b + 0.085 && x.beat + x.duration > b + 0.085).map((x) => x.pitch);
  const down: number[][][][] = streams.map((byS, t) => byS.map((ns) => (roles[t] === 'drums' ? [] : Array.from({ length: bars }, (_, b) => at(ns, b * 4)))));
  const perBar: number[][][] = streams.map((byS, t) =>
    byS.map((ns) => {
      const c = new Array(bars).fill(0);
      for (const b of onsets(ns, roles[t] === 'chord')) c[Math.min(bars - 1, Math.floor(b / 4 + 1e-9))]++;
      return c;
    }),
  );
  const S = info.speeds.length;
  let sum = 0, cnt = 0, worst = 0, worstCombo = '-', lo = Infinity, hi = 0, checked = 0;
  // Each cassette is absent (-1) or at one of the allowed speeds.
  const idx = new Array(n).fill(-1);
  const total = (S + 1) ** n;
  for (let c = 1; c < total; c++) {
    let x = c;
    for (let t = 0; t < n; t++) { idx[t] = (x % (S + 1)) - 1; x = Math.floor(x / (S + 1)); }
    checked++;
    let pairs = 0, harsh = 0;
    for (let i = 0; i < n; i++)
      for (let j = i + 1; j < n; j++) {
        if (idx[i] < 0 || idx[j] < 0 || roles[i] === 'drums' || roles[j] === 'drums') continue;
        for (let b = 0; b < bars; b++) for (const p of down[i][idx[i]][b]) for (const q of down[j][idx[j]][b]) { pairs++; if (isHarsh(Math.abs(p - q))) harsh++; }
      }
    if (pairs) {
      const h = (100 * harsh) / pairs;
      sum += h; cnt++;
      if (h > worst) { worst = h; worstCombo = idx.map((k, t) => (k < 0 ? null : `${roles[t]}@${info.speeds[k]}x`)).filter(Boolean).join(' + '); }
    }
    for (let b = 0; b < bars; b++) {
      let tot = 0;
      for (let t = 0; t < n; t++) if (idx[t] >= 0) tot += perBar[t][idx[t]][b];
      lo = Math.min(lo, tot); hi = Math.max(hi, tot);
    }
  }
  const r1 = (v: number) => Math.round(v * 10) / 10;
  return {
    audibleCassettes: n,
    speeds: info.speeds,
    bars,
    combinationsChecked: checked,
    inScalePct: notes ? r1((100 * ok) / notes) : 100,
    harshDownbeatPctMean: r1(cnt ? sum / cnt : 0),
    harshDownbeatPctWorst: r1(worst),
    worstCombo,
    onsetsPerBarMin: lo,
    onsetsPerBarMax: hi,
    progressionTurnsInHorizon: Math.round((info.horizonBars / (piece.music.progression.length * (piece.music.chordBars ?? 1))) * 100) / 100,
  };
}

/** Prints the table; called by levelcheck-run.ts. */
export function runLevelCheck(): number {
  console.log('piece               level  bpm piece/level  tapes speeds      combos scale%  hDn hDnW onsets/bar turns  worst combo');
  let bad = 0;
  for (const p of loadPieces()) {
    const info = p.id === 'menu' ? null : levelInfo(p.id);
    const r = inLevel(p, info ?? { maxTapes: 4, speeds: [0.5, 1, 2, 4] as Speed[], horizonBars: 8 });
    if (info && info.bpm !== p.bpm) bad++;
    console.log(
      [
        p.id.padEnd(19),
        (info ? 'yes' : 'no').padEnd(6),
        `${p.bpm}/${info ? info.bpm : '-'}`.padEnd(15),
        String(r.audibleCassettes).padEnd(5),
        r.speeds.join(',').padEnd(11),
        String(r.combinationsChecked).padStart(6),
        String(r.inScalePct).padStart(6),
        r.harshDownbeatPctMean.toFixed(1).padStart(4),
        r.harshDownbeatPctWorst.toFixed(1).padStart(4),
        `${r.onsetsPerBarMin}-${r.onsetsPerBarMax}`.padStart(10),
        String(r.progressionTurnsInHorizon).padStart(5),
        ' ' + r.worstCombo,
      ].join(' '),
    );
  }
  console.log(bad ? `${bad} piece(s) disagree with the level file's bpm` : 'every piece matches the bpm of its level file (where a level file exists)');
  return bad;
}
