/**
 * Iterates each piece until its metrics are good across the whole matrix.
 *
 * The composer fixes the idea (pieces.ts: key, tempo, roles, rhythm, and a short list of fitting
 * formulas per layer). This script searches inside that space by coordinate descent on the score of
 * lib.analyse(): progression first, then for each layer the formula and its parameters, then the
 * layer-shaping parameters, for two passes. Deterministic: same pieces.ts -> same tuned.json.
 *
 *   cd prototype && npx vite-node ../art/music/tune.ts [-- <id substring> ...]
 */
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { analyse, HERE, type MusicDef, type StateMaps, type TrackDef } from './lib';
import { PIECES, type LayerSpec, type Piece } from './pieces';
import { STATE_MAPS } from './statemaps';

const OUT = join(HERE, 'tuned.json');
const tuned: Record<string, { music: MusicDef; score: number; log: string[] }> = existsSync(OUT) ? JSON.parse(readFileSync(OUT, 'utf8')) : {};
const wanted = process.argv.slice(2).filter((a) => a !== '--');

const DEFAULT_GRID: Record<string, Record<string, number[]>> = {
  melody: { contour: [0.15, 0.3, 0.45, 0.6, 0.7], gravity: [0.5, 0.67, 0.85], cycle: [8, 16, 32] },
  bass: { contour: [0.1, 0.25, 0.4], cycle: [8, 16] },
  chord: { contour: [0.2, 0.4, 0.6], cycle: [8, 16, 32] },
  drums: { threshold: [0.4, 0.5, 0.6, 0.7, 0.8], density: [0.5, 0.75, 1] },
};
/** Small preference for the composer's first-choice formula, so equal scores keep the intended character. */
const RANK_COST = 1.5;
const MAX_COMBOS = 40;

function cartesian(grid: Record<string, number[]>): Record<string, number>[] {
  let out: Record<string, number>[] = [{}];
  for (const [k, vals] of Object.entries(grid)) out = out.flatMap((o) => vals.map((v) => ({ ...o, [k]: v })));
  return out;
}
/** Cartesian product, thinned evenly (always keeping the first = the composer's preferred values). */
function combos(grid: Record<string, number[]>): Record<string, number>[] {
  const all = cartesian(grid);
  if (all.length <= MAX_COMBOS) return all;
  const stride = all.length / MAX_COMBOS;
  return Array.from({ length: MAX_COMBOS }, (_, i) => all[Math.floor(i * stride)]);
}

function tunePiece(p: Piece): void {
  const maps = STATE_MAPS as unknown as StateMaps;
  const log: string[] = [];
  const evalMusic = (m: MusicDef) => analyse({ id: p.file, bpm: p.bpm, music: m, stateMaps: maps }).score;
  // Split a track's params into formula params and layer-shaping params (searched) + fixed.
  type State = { formula: string; fparams: Record<string, number>; lparams: Record<string, number> };
  const st: State[] = p.tracks.map((spec) => {
    if (spec.reprise) {
      const src = tuned[spec.reprise.piece]?.music.tracks[spec.reprise.track];
      if (!src) throw new Error(`${p.file}: reprise source ${spec.reprise.piece} not tuned yet`);
      const fparams: Record<string, number> = {};
      const grid = { ...DEFAULT_GRID[spec.role], ...(spec.grid ?? {}) };
      for (const [k, v] of Object.entries(src.params ?? {})) if (!(k in grid) && !(k in spec.fixed) && !['rate', 'register', 'pulses', 'steps', 'phrase', 'gravity', 'contour', 'cycle', 'threshold', 'density'].includes(k)) fparams[k] = v;
      return { formula: src.formula, fparams, lparams: {} };
    }
    const [id, g] = spec.formulas[0];
    return { formula: id, fparams: Object.fromEntries(Object.entries(g).map(([k, v]) => [k, v[0]])), lparams: {} };
  });
  const track = (spec: LayerSpec, s: State): TrackDef => {
    const params = { ...s.fparams, ...s.lparams, ...spec.fixed };
    return spec.genre ? { role: spec.role, formula: s.formula, genre: spec.genre, params } : { role: spec.role, formula: s.formula, params };
  };
  let prog = p.progressions[0];
  const music = (): MusicDef => ({ root: p.root, scale: p.scale, progression: prog, chordBars: p.chordBars, tracks: p.tracks.map((spec, i) => track(spec, st[i])) });
  let best = evalMusic(music());
  log.push(`start ${best}`);

  const pickProg = () => {
    for (const cand of p.progressions) {
      const keep = prog;
      prog = cand;
      const sc = evalMusic(music());
      if (sc > best + 1e-9) { best = sc; log.push(`progression ${JSON.stringify(cand)} -> ${sc}`); }
      else prog = keep;
    }
  };

  for (let pass = 0; pass < 2; pass++) {
    pickProg();
    p.tracks.forEach((spec, i) => {
      // Stage A: formula and its parameters.
      if (!spec.reprise) {
        let bestAdj = -Infinity, bestState: State | null = null, bestRaw = best;
        spec.formulas.forEach(([id, g], rank) => {
          for (const fp of combos(g)) {
            const keep = st[i];
            st[i] = { formula: id, fparams: fp, lparams: keep.lparams };
            const sc = evalMusic(music());
            const adj = sc - rank * RANK_COST;
            if (adj > bestAdj + 1e-9) { bestAdj = adj; bestState = st[i]; bestRaw = sc; }
            st[i] = keep;
          }
        });
        if (bestState && (bestState.formula !== st[i].formula || JSON.stringify(bestState.fparams) !== JSON.stringify(st[i].fparams)) && bestRaw >= best - RANK_COST * spec.formulas.length) {
          const cur = evalMusic(music());
          const curRank = spec.formulas.findIndex(([id]) => id === st[i].formula);
          if (bestAdj > cur - curRank * RANK_COST + 1e-9) { st[i] = bestState; best = bestRaw; log.push(`T${i + 1} ${st[i].formula} ${JSON.stringify(st[i].fparams)} -> ${bestRaw}`); }
        }
      }
      // Stage B: layer-shaping parameters.
      const grid = { ...DEFAULT_GRID[spec.role], ...(spec.grid ?? {}) };
      for (const k of Object.keys(spec.fixed)) delete grid[k];
      for (const lp of cartesian(grid)) {
        const keep = st[i];
        st[i] = { ...keep, lparams: lp };
        const sc = evalMusic(music());
        if (sc > best + 1e-9) { best = sc; log.push(`T${i + 1} layer ${JSON.stringify(lp)} -> ${sc}`); }
        else st[i] = keep;
      }
    });
  }
  best = evalMusic(music());
  tuned[p.file] = { music: music(), score: best, log };
  console.log(`${p.file.padEnd(20)} ${log[0]} -> final ${best}  prog ${JSON.stringify(prog)}  ` + music().tracks.map((t) => `${t.role}:${t.formula}${JSON.stringify(t.params)}`).join(' '));
  writeFileSync(OUT, JSON.stringify(tuned, null, 1));
}

for (const p of PIECES) if (!wanted.length || wanted.some((w) => p.file.includes(w))) tunePiece(p);
