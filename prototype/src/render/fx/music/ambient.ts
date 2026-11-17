/**
 * Music-linked environment (MUSIC-12, chapter 18 "Musical architecture").
 *
 * Harmonograph-inspired visuals that live in the architecture and react to RenderFrame.music:
 *   - rune strokes on inscribed floor tiles ('~') and glyph columns on rune panels, pulsing on the
 *     beat/bar and with each cassette's layer level;
 *   - a "Stack" contour strip (four layers' recent pitches against a shared playhead) on every
 *     wave-screen prop and along the far edge of the level;
 *   - Lissajous / rose floor sigils that morph with the chord index;
 *   - an "Epicycles" hologram (sixteen strongest Fourier harmonics of the combined contour as nested
 *     rotating circles) beyond the far corner.
 * Visual only: nothing here is a collider or feeds back into gameplay.
 */
import * as THREE from 'three';
import type { LevelDef } from '../../../core/types';
import type { MusicPulse } from '../../../contracts';
import type { ThemePalette } from '../../layer';
import { TAPE_HEX, hexToRgb } from '../colors';
import { dft, hash4, runeGlyph, sigilParamsForChord, sigilPoints, strongestHarmonics, type SigilParams } from '../curves';
import { FACING_FLOOR, FACING_PLANE, PolylineBatch } from '../gpu/polyline';

/** Pitch-history samples per beat and length (16 beats = four bars of contour). */
export const SAMPLES_PER_BEAT = 8;
export const HISTORY = 128;
const DFT_N = 64;
const EPI_COUNT = 16;
const EPI_CIRCLE_PTS = 28;
const TRACE_PTS = 72;
const SIGIL_PTS = 160;
const SCREEN_PTS = 48;
const MAX_RUNE_TILES = 160;
const MAX_PANELS = 12;
const MAX_SIGILS = 6;
/** Edge hologram layout (tiles along the edge / scene height). Kept low enough to stay in frame. */
const STRIP_Y = 1.75;
const STRIP_H = 0.95;
const EPI_R = 1.05;
/** Edge length reserved for the epicycles + their trace at the strip's right end. */
const EPI_SPAN = 4.2;

interface Sigil {
  x: number;
  z: number;
  radius: number;
  line: number;
  variant: number;
  from: Float32Array;
  to: Float32Array;
  cur: Float32Array;
  morph: number;
  rgb: Float32Array;
}

interface RuneStroke {
  line: number;
  tape: number;
  phase: number;
}

interface PanelGlyph {
  line: number;
  /** Local stroke points (u, v) in panel space. */
  local: number[];
  tape: number;
  glyph: number;
}

interface WaveScreen {
  x: number;
  z: number;
  lines: number[];
  frame: number;
  playhead: number;
}

interface PanelHost {
  x: number;
  z: number;
  glyphs: PanelGlyph[];
}

export class MusicAmbient {
  readonly batch: PolylineBatch;
  private readonly level: LevelDef;
  private readonly palette: ThemePalette;
  private readonly W: number;
  private readonly H: number;

  // Pitch / level history per tape (ring buffers).
  private readonly hPitch = new Float32Array(4 * HISTORY);
  private readonly hLevel = new Float32Array(4 * HISTORY);
  private hHead = 0;
  private hCount = 0;
  private lastSample = NaN;

  private readonly sigils: Sigil[] = [];
  private readonly runes: RuneStroke[] = [];
  private readonly panels: PanelHost[] = [];
  private readonly screens: WaveScreen[] = [];
  private readonly sigilParams: SigilParams = { kind: 'lissajous', a: 1, b: 2, delta: 0, p: 3, q: 1 };
  private lastChord = NaN;

  // Edge strip + epicycles.
  private stripLines: number[] = [];
  private stripPlayhead = -1;
  private stripBase = -1;
  private stripTicks: number[] = [];
  private epiCircles: number[] = [];
  private epiChain = -1;
  private epiTrace = -1;
  private edgeChosen = false;
  private ox = 0;
  private oz = 0;
  /** Along-edge unit vector (screen-rightward) and outward normal. */
  private ex = 1;
  private ez = 0;
  private nx = 0;
  private nz = -1;
  private edgeLen = 1;

  // Epicycle state.
  private readonly signal = new Float32Array(DFT_N);
  private readonly re = new Float32Array(DFT_N);
  private readonly im = new Float32Array(DFT_N);
  private readonly smRe = new Float32Array(DFT_N);
  private readonly smIm = new Float32Array(DFT_N);
  private readonly hf = new Float32Array(EPI_COUNT);
  private readonly ha = new Float32Array(EPI_COUNT);
  private readonly hp = new Float32Array(EPI_COUNT);
  private readonly traceY = new Float32Array(TRACE_PTS);
  private traceTimer = 0;

  // Camera-yaw basis for the billboarded panel holograms.
  private bRx = 1;
  private bRz = 0;
  private bNx = 0;
  private bNz = 1;
  private basisSet = false;

  private readonly rgb = new Float32Array(3);
  private readonly tapeRgb = new Float32Array(12);
  private readonly runeRgb = new Float32Array(3);
  private readonly camRight = new THREE.Vector3();
  private readonly camFwd = new THREE.Vector3();

  constructor(level: LevelDef, palette: ThemePalette, quality: 'low' | 'high') {
    this.level = level;
    this.palette = palette;
    this.H = level.map.length;
    let w = 0;
    for (let r = 0; r < level.map.length; r++) w = Math.max(w, level.map[r].length);
    this.W = w;
    for (let t = 0; t < 4; t++) hexToRgb(TAPE_HEX[t], this.tapeRgb, t * 3);
    hexToRgb(palette.neonC, this.runeRgb);
    this.batch = new PolylineBatch(quality === 'low' ? 7000 : 10000);
    this.build(quality);
    this.hPitch.fill(0.5);
  }

  private build(quality: 'low' | 'high'): void {
    const level = this.level;
    const b = this.batch;

    // Floor sigils: under the shared start position, every core and the exit.
    const spots: { x: number; z: number; r: number; hex: number }[] = [{ x: level.start.x, z: level.start.y, r: 1.15, hex: this.palette.neonA }];
    for (const e of level.entities) {
      if (spots.length >= MAX_SIGILS) break;
      if (e.kind === 'core') spots.push({ x: e.x, z: e.y, r: 0.95, hex: this.palette.neonC });
      else if (e.kind === 'exit') spots.push({ x: e.c + e.w / 2, z: e.r + e.h / 2, r: Math.max(0.8, Math.min(e.w, e.h) * 0.45), hex: this.palette.hazard });
    }
    for (let s = 0; s < spots.length; s++) {
      const line = b.addLine(SIGIL_PTS, FACING_FLOOR, true);
      if (line < 0) break;
      b.setLineWidth(line, 0.045);
      const rgb = new Float32Array(3);
      hexToRgb(spots[s].hex, rgb);
      this.sigils.push({
        x: spots[s].x,
        z: spots[s].z,
        radius: spots[s].r,
        line,
        variant: s,
        from: new Float32Array(SIGIL_PTS * 2),
        to: new Float32Array(SIGIL_PTS * 2),
        cur: new Float32Array(SIGIL_PTS * 2),
        morph: 1,
        rgb,
      });
    }

    // Rune strokes on inscribed floor tiles.
    let tiles = 0;
    const tileCap = quality === 'low' ? MAX_RUNE_TILES >> 1 : MAX_RUNE_TILES;
    for (let r = 0; r < level.map.length && tiles < tileCap; r++) {
      const row = level.map[r];
      for (let c = 0; c < row.length && tiles < tileCap; c++) {
        if (row[c] !== '~') continue;
        tiles++;
        const seed = hash4(c, r, level.index, 7);
        const strokes = runeGlyph(seed);
        const tape = (c * 7 + r * 3) % 4;
        const rot = ((seed >>> 8) % 4) * (Math.PI / 2);
        const cr = Math.cos(rot);
        const sr = Math.sin(rot);
        for (const st of strokes) {
          const n = st.length / 2;
          const line = b.addLine(n, FACING_FLOOR, false);
          if (line < 0) break;
          b.setLineWidth(line, 0.05);
          for (let i = 0; i < n; i++) {
            const u = st[i * 2] * 0.3;
            const v = st[i * 2 + 1] * 0.3;
            b.setPoint(line, i, c + 0.5 + u * cr - v * sr, 0.014, r + 0.5 + u * sr + v * cr);
          }
          this.runes.push({ line, tape, phase: (c + r) * 0.6 });
        }
      }
    }

    // Prop overlays: glyph columns on rune panels, contour strips on wave screens.
    let panelIdx = 0;
    for (const e of level.entities) {
      if (e.kind !== 'decor' || panelIdx >= MAX_PANELS) continue;
      if (e.type === 'runePanel') {
        const host: PanelHost = { x: e.x, z: e.y, glyphs: [] };
        for (let gi = 0; gi < 3; gi++) {
          const strokes = runeGlyph(hash4(Math.round(e.x * 10), Math.round(e.y * 10), gi, 11));
          for (const st of strokes) {
            const n = st.length / 2;
            const line = b.addLine(n, FACING_PLANE, false);
            if (line < 0) break;
            b.setLineWidth(line, 0.04);
            const local: number[] = [];
            for (let i = 0; i < n; i++) local.push(st[i * 2] * 0.16, 0.55 + gi * 0.42 + st[i * 2 + 1] * 0.16);
            host.glyphs.push({ line, local, tape: panelIdx % 4, glyph: gi });
          }
        }
        this.panels.push(host);
        panelIdx++;
      } else if (e.type === 'waveScreen') {
        const scr: WaveScreen = { x: e.x, z: e.y, lines: [], frame: -1, playhead: -1 };
        for (let t = 0; t < 4; t++) {
          const line = b.addLine(SCREEN_PTS, FACING_PLANE, false);
          if (line < 0) break;
          b.setLineWidth(line, 0.035);
          scr.lines.push(line);
        }
        scr.frame = b.addLine(4, FACING_PLANE, true);
        if (scr.frame >= 0) b.setLineWidth(scr.frame, 0.025);
        scr.playhead = b.addLine(2, FACING_PLANE, false);
        if (scr.playhead >= 0) b.setLineWidth(scr.playhead, 0.03);
        this.screens.push(scr);
        panelIdx++;
      }
    }

    // Edge strip: four layer contours, a baseline, a playhead and beat ticks.
    for (let t = 0; t < 4; t++) {
      const line = b.addLine(HISTORY, FACING_PLANE, false);
      if (line < 0) break;
      b.setLineWidth(line, 0.06);
      this.stripLines.push(line);
    }
    this.stripBase = b.addLine(2, FACING_PLANE, false);
    if (this.stripBase >= 0) b.setLineWidth(this.stripBase, 0.03);
    this.stripPlayhead = b.addLine(2, FACING_PLANE, false);
    if (this.stripPlayhead >= 0) b.setLineWidth(this.stripPlayhead, 0.05);
    for (let k = 0; k < 4; k++) {
      const line = b.addLine(2, FACING_PLANE, false);
      if (line < 0) break;
      b.setLineWidth(line, 0.03);
      this.stripTicks.push(line);
    }

    // Epicycles.
    for (let i = 0; i < EPI_COUNT; i++) {
      const line = b.addLine(EPI_CIRCLE_PTS, FACING_PLANE, true);
      if (line < 0) break;
      b.setLineWidth(line, 0.025);
      this.epiCircles.push(line);
    }
    this.epiChain = b.addLine(EPI_COUNT + 1, FACING_PLANE, false);
    if (this.epiChain >= 0) b.setLineWidth(this.epiChain, 0.03);
    this.epiTrace = b.addLine(TRACE_PTS, FACING_PLANE, false);
    if (this.epiTrace >= 0) b.setLineWidth(this.epiTrace, 0.05);
  }

  /** Build the GPU mesh (after construction). */
  createMesh(): THREE.Mesh {
    return this.batch.finalize(2);
  }

  update(music: MusicPulse, brightness: number, dt: number, camera: THREE.Camera): void {
    camera.updateMatrixWorld();
    this.camRight.setFromMatrixColumn(camera.matrixWorld, 0);
    camera.getWorldDirection(this.camFwd);
    this.updateBasis();
    if (!this.edgeChosen) this.chooseEdge();

    this.sampleHistory(music);
    this.updateSigils(music, brightness, dt);
    this.updateRunes(music, brightness);
    this.updatePanels(music, brightness);
    this.updateScreens(music, brightness);
    this.updateStrip(music, brightness);
    this.updateEpicycles(music, brightness, dt);
    this.batch.commit(this.camFwd);
  }

  // ───────────────────────────── history ─────────────────────────────

  private sampleHistory(m: MusicPulse): void {
    const idx = Math.floor(m.beat * SAMPLES_PER_BEAT);
    const last = this.lastSample;
    if (last !== last || idx < last || idx - last > HISTORY) {
      // First frame or the transport jumped (new run / seek): restart the contour.
      this.hHead = 0;
      this.hCount = 0;
      this.lastSample = idx;
      this.pushSample(m);
      return;
    }
    for (let s = last; s < idx; s++) this.pushSample(m);
    this.lastSample = idx;
  }

  private pushSample(m: MusicPulse): void {
    const h = this.hHead;
    for (let t = 0; t < 4; t++) {
      const p = m.pitches[t];
      const l = m.levels[t];
      this.hPitch[t * HISTORY + h] = Number.isFinite(p) ? Math.max(0, Math.min(1, p)) : 0.5;
      this.hLevel[t * HISTORY + h] = Number.isFinite(l) ? Math.max(0, Math.min(1, l)) : 0;
    }
    this.hHead = (h + 1) % HISTORY;
    if (this.hCount < HISTORY) this.hCount++;
    this.refreshSpectrum();
  }

  /** Index into the ring for the k-th sample counting back from newest (k = 0 newest). */
  private back(k: number): number {
    return (this.hHead - 1 - k + HISTORY * 2) % HISTORY;
  }

  private refreshSpectrum(): void {
    // Combined contour of the last DFT_N samples, weighted by how loud each layer is.
    for (let s = 0; s < DFT_N; s++) {
      const h = this.back(DFT_N - 1 - s);
      let num = 0;
      let den = 0;
      for (let t = 0; t < 4; t++) {
        const l = this.hLevel[t * HISTORY + h];
        num += l * this.hPitch[t * HISTORY + h];
        den += l;
      }
      this.signal[s] = den > 0.02 ? (num / den) * 2 - 1 : 0;
    }
    dft(this.signal, DFT_N, this.re, this.im);
  }

  // ───────────────────────────── basis / placement ─────────────────────────────

  private updateBasis(): void {
    let rx = this.camRight.x;
    let rz = this.camRight.z;
    const rl = Math.hypot(rx, rz);
    if (rl < 1e-5) return;
    rx /= rl;
    rz /= rl;
    if (this.basisSet && Math.abs(rx - this.bRx) + Math.abs(rz - this.bRz) < 1e-4) return;
    this.bRx = rx;
    this.bRz = rz;
    // Normal faces the camera (opposite the view direction, flattened).
    let nx = -this.camFwd.x;
    let nz = -this.camFwd.z;
    const nl = Math.hypot(nx, nz) || 1;
    nx /= nl;
    nz /= nl;
    this.bNx = nx;
    this.bNz = nz;
    this.basisSet = true;
    const b = this.batch;
    for (const p of this.panels) {
      for (const g of p.glyphs) {
        b.setNormal(g.line, nx, 0, nz);
        const n = g.local.length / 2;
        for (let i = 0; i < n; i++) {
          const u = g.local[i * 2];
          const v = g.local[i * 2 + 1];
          b.setPoint(g.line, i, p.x + rx * u + nx * 0.35, v, p.z + rz * u + nz * 0.35);
        }
      }
    }
    for (const s of this.screens) {
      for (const l of s.lines) b.setNormal(l, nx, 0, nz);
      if (s.frame >= 0) {
        b.setNormal(s.frame, nx, 0, nz);
        const hw = 0.62;
        const y0 = 1.18;
        const y1 = 1.82;
        const cx = s.x + nx * 0.3;
        const cz = s.z + nz * 0.3;
        b.setPoint(s.frame, 0, cx - rx * hw, y0, cz - rz * hw);
        b.setPoint(s.frame, 1, cx + rx * hw, y0, cz + rz * hw);
        b.setPoint(s.frame, 2, cx + rx * hw, y1, cz + rz * hw);
        b.setPoint(s.frame, 3, cx - rx * hw, y1, cz - rz * hw);
      }
      if (s.playhead >= 0) b.setNormal(s.playhead, nx, 0, nz);
    }
  }

  private chooseEdge(): void {
    const fx = this.camFwd.x;
    const fz = this.camFwd.z;
    const W = this.W;
    const H = this.H;
    // Outward normals of the four map edges; the far edges point along the view direction.
    const cands = [
      { nx: 0, nz: -1, len: W },
      { nx: 0, nz: 1, len: W },
      { nx: -1, nz: 0, len: H },
      { nx: 1, nz: 0, len: H },
    ];
    let best = cands[0];
    let bestScore = -Infinity;
    for (const c of cands) {
      const score = c.nx * fx + c.nz * fz + c.len * 1e-3;
      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }
    this.nx = best.nx;
    this.nz = best.nz;
    // Along-edge direction that reads left → right on screen.
    let ex = -best.nz;
    let ez = best.nx;
    if (ex * this.camRight.x + ez * this.camRight.z < 0) {
      ex = -ex;
      ez = -ez;
    }
    this.ex = ex;
    this.ez = ez;
    this.edgeLen = Math.max(EPI_SPAN + 4, best.len - 1);
    // Origin: the edge's left end (screen-left), pushed outward beyond the map.
    const midX = best.nx === 0 ? W / 2 : best.nx < 0 ? 0 : W;
    const midZ = best.nz === 0 ? H / 2 : best.nz < 0 ? 0 : H;
    this.ox = midX - ex * (this.edgeLen / 2) + best.nx * 0.9;
    this.oz = midZ - ez * (this.edgeLen / 2) + best.nz * 0.9;
    const b = this.batch;
    for (const l of this.stripLines) b.setNormal(l, best.nx, 0, best.nz);
    for (const l of this.stripTicks) b.setNormal(l, best.nx, 0, best.nz);
    for (const l of this.epiCircles) b.setNormal(l, best.nx, 0, best.nz);
    if (this.stripBase >= 0) b.setNormal(this.stripBase, best.nx, 0, best.nz);
    if (this.stripPlayhead >= 0) b.setNormal(this.stripPlayhead, best.nx, 0, best.nz);
    if (this.epiChain >= 0) b.setNormal(this.epiChain, best.nx, 0, best.nz);
    if (this.epiTrace >= 0) b.setNormal(this.epiTrace, best.nx, 0, best.nz);
    this.edgeChosen = true;
  }

  // ───────────────────────────── sigils ─────────────────────────────

  private updateSigils(m: MusicPulse, br: number, dt: number): void {
    const chord = Number.isFinite(m.chord) ? m.chord : 0;
    const changed = chord !== this.lastChord;
    const first = this.lastChord !== this.lastChord;
    this.lastChord = chord;
    let avg = 0;
    for (let t = 0; t < 4; t++) avg += m.levels[t] ?? 0;
    avg *= 0.25;
    const a = (0.16 + 0.24 * m.barPulse + 0.1 * m.beatPulse + 0.2 * avg) * br;
    const ang = (m.beat * Math.PI) / 32;
    const ca = Math.cos(ang);
    const sa = Math.sin(ang);
    const b = this.batch;
    for (let s = 0; s < this.sigils.length; s++) {
      const g = this.sigils[s];
      if (changed) {
        sigilPoints(g.to, SIGIL_PTS, sigilParamsForChord(chord, g.variant, this.sigilParams));
        if (first) g.from.set(g.to);
        else g.from.set(g.cur);
        g.morph = first ? 1 : 0;
      }
      if (g.morph < 1 || changed) {
        g.morph = Math.min(1, g.morph + dt / 1.2);
        const e = g.morph * g.morph * (3 - 2 * g.morph);
        for (let i = 0; i < SIGIL_PTS * 2; i++) g.cur[i] = g.from[i] + (g.to[i] - g.from[i]) * e;
      }
      // Alternate sigils counter-rotate so a room never turns as one block.
      const dir = s % 2 === 0 ? 1 : -1;
      for (let i = 0; i < SIGIL_PTS; i++) {
        const u = g.cur[i * 2];
        const v = g.cur[i * 2 + 1];
        const ru = u * ca - v * sa * dir;
        const rv = u * sa * dir + v * ca;
        b.setPoint(g.line, i, g.x + ru * g.radius, 0.016, g.z + rv * g.radius);
      }
      b.setLineColor(g.line, g.rgb[0], g.rgb[1], g.rgb[2], a);
    }
  }

  // ───────────────────────────── runes ─────────────────────────────

  private updateRunes(m: MusicPulse, br: number): void {
    const b = this.batch;
    const beatPhase = (m.beat * Math.PI) / 2;
    for (let i = 0; i < this.runes.length; i++) {
      const r = this.runes[i];
      const lvl = m.levels[r.tape] ?? 0;
      const wave = Math.max(0, Math.cos(r.phase - beatPhase));
      const a = (0.1 + 0.5 * lvl + 0.12 * m.beatPulse + 0.16 * wave * wave * wave) * br;
      const k = 0.35 * Math.min(1, lvl * 1.5);
      const o = r.tape * 3;
      b.setLineColor(
        r.line,
        this.runeRgb[0] + (this.tapeRgb[o] - this.runeRgb[0]) * k,
        this.runeRgb[1] + (this.tapeRgb[o + 1] - this.runeRgb[1]) * k,
        this.runeRgb[2] + (this.tapeRgb[o + 2] - this.runeRgb[2]) * k,
        a,
      );
    }
  }

  private updatePanels(m: MusicPulse, br: number): void {
    const b = this.batch;
    const beatInBar = ((Math.floor(m.beat) % 4) + 4) % 4;
    for (let pi = 0; pi < this.panels.length; pi++) {
      const glyphs = this.panels[pi].glyphs;
      for (let gi = 0; gi < glyphs.length; gi++) {
        const g = glyphs[gi];
        const lvl = m.levels[g.tape] ?? 0;
        const lit = beatInBar === g.glyph ? m.beatPulse * 0.35 : 0;
        const a = (0.16 + 0.55 * lvl + 0.25 * m.barPulse + lit) * br;
        const o = g.tape * 3;
        b.setLineColor(g.line, this.tapeRgb[o] * 0.5 + this.runeRgb[0] * 0.5, this.tapeRgb[o + 1] * 0.5 + this.runeRgb[1] * 0.5, this.tapeRgb[o + 2] * 0.5 + this.runeRgb[2] * 0.5, a);
      }
    }
  }

  // ───────────────────────────── contour strips ─────────────────────────────

  private updateScreens(m: MusicPulse, br: number): void {
    const b = this.batch;
    const rx = this.bRx;
    const rz = this.bRz;
    const nx = this.bNx;
    const nz = this.bNz;
    hexToRgb(this.palette.neonB, this.rgb);
    for (let si = 0; si < this.screens.length; si++) {
      const s = this.screens[si];
      const cx = s.x + nx * 0.3;
      const cz = s.z + nz * 0.3;
      const hw = 0.56;
      for (let t = 0; t < s.lines.length; t++) {
        const line = s.lines[t];
        const o = t * 3;
        for (let i = 0; i < SCREEN_PTS; i++) {
          const k = SCREEN_PTS - 1 - i;
          const h = this.back(k);
          const valid = k < this.hCount;
          const p = valid ? this.hPitch[t * HISTORY + h] : 0.5;
          const l = valid ? this.hLevel[t * HISTORY + h] : 0;
          const u = -hw + (2 * hw * i) / (SCREEN_PTS - 1);
          const v = 1.5 + (p - 0.5) * 0.5 + (t - 1.5) * 0.025;
          b.setPoint(line, i, cx + rx * u, v, cz + rz * u);
          b.setColor(line, i, this.tapeRgb[o], this.tapeRgb[o + 1], this.tapeRgb[o + 2], (0.08 + 0.8 * l) * br);
        }
      }
      if (s.frame >= 0) b.setLineColor(s.frame, this.rgb[0], this.rgb[1], this.rgb[2], (0.18 + 0.12 * m.barPulse) * br);
      if (s.playhead >= 0) {
        b.setPoint(s.playhead, 0, cx + rx * hw, 1.2, cz + rz * hw);
        b.setPoint(s.playhead, 1, cx + rx * hw, 1.8, cz + rz * hw);
        b.setLineColor(s.playhead, 1, 1, 1, (0.25 + 0.5 * m.beatPulse) * br);
      }
    }
  }

  private stripPoint(line: number, i: number, u: number, v: number): void {
    this.batch.setPoint(line, i, this.ox + this.ex * u, v, this.oz + this.ez * u);
  }

  private updateStrip(m: MusicPulse, br: number): void {
    const b = this.batch;
    const L = this.edgeLen;
    // The strip runs from the screen-left end; the epicycle hologram takes the last EPI_SPAN units
    // (the side corner, which an isometric framing keeps in view more often than the far corner).
    const s0 = 0.4;
    const play = s0 + (L - EPI_SPAN - s0) * 0.8;
    const y0 = STRIP_Y;
    const hgt = STRIP_H;
    const frac = m.beat * SAMPLES_PER_BEAT - Math.floor(m.beat * SAMPLES_PER_BEAT);
    for (let t = 0; t < this.stripLines.length; t++) {
      const line = this.stripLines[t];
      const o = t * 3;
      for (let i = 0; i < HISTORY; i++) {
        const k = HISTORY - 1 - i;
        const h = this.back(k);
        const valid = k < this.hCount;
        const p = valid ? this.hPitch[t * HISTORY + h] : 0.5;
        const l = valid ? this.hLevel[t * HISTORY + h] : 0;
        // Smooth scroll: shift by the fraction of the current sample so the strip glides.
        const u = s0 + ((play - s0) * (i + 1 - frac)) / HISTORY;
        // Older samples fade toward the left like ink drying.
        const age = i / (HISTORY - 1);
        this.stripPoint(line, i, Math.max(s0, u), y0 + p * hgt + t * 0.03);
        b.setColor(line, i, this.tapeRgb[o], this.tapeRgb[o + 1], this.tapeRgb[o + 2], (0.06 + 0.75 * l) * (0.25 + 0.75 * age) * br);
      }
    }
    hexToRgb(this.palette.neonB, this.rgb);
    if (this.stripBase >= 0) {
      this.stripPoint(this.stripBase, 0, s0, y0 - 0.08);
      this.stripPoint(this.stripBase, 1, L, y0 - 0.08);
      b.setLineColor(this.stripBase, this.rgb[0], this.rgb[1], this.rgb[2], (0.2 + 0.2 * m.barPulse) * br);
    }
    if (this.stripPlayhead >= 0) {
      this.stripPoint(this.stripPlayhead, 0, play, y0 - 0.15);
      this.stripPoint(this.stripPlayhead, 1, play, y0 + hgt + 0.2);
      b.setLineColor(this.stripPlayhead, 1, 1, 1, (0.35 + 0.5 * m.beatPulse) * br);
    }
    // Upcoming beat ticks to the right of the playhead; the bar line stands taller.
    const unit = (play - s0) / (HISTORY / SAMPLES_PER_BEAT);
    const nextBeat = Math.ceil(m.beat);
    for (let k = 0; k < this.stripTicks.length; k++) {
      const bt = nextBeat + k;
      const u = play + (bt - m.beat) * unit;
      const bar = ((bt % 4) + 4) % 4 === 0;
      const line = this.stripTicks[k];
      this.stripPoint(line, 0, u, y0 - 0.12);
      this.stripPoint(line, 1, u, y0 + (bar ? 0.5 : 0.18));
      b.setLineColor(line, this.rgb[0], this.rgb[1], this.rgb[2], (bar ? 0.5 : 0.28) * br);
    }
  }

  // ───────────────────────────── epicycles ─────────────────────────────

  private updateEpicycles(m: MusicPulse, br: number, dt: number): void {
    if (this.epiChain < 0) return;
    const b = this.batch;
    // Smooth the spectrum so harmonics swell rather than pop when the contour changes.
    const k = 1 - Math.exp(-dt * 3);
    for (let i = 0; i < DFT_N; i++) {
      this.smRe[i] += (this.re[i] - this.smRe[i]) * k;
      this.smIm[i] += (this.im[i] - this.smIm[i]) * k;
    }
    const count = strongestHarmonics(this.smRe, this.smIm, DFT_N, EPI_COUNT, this.hf, this.ha, this.hp);
    const R = EPI_R;
    let sum = 0;
    for (let i = 0; i < count; i++) sum += this.ha[i];
    // Normalise so the hologram keeps its size; a nearly flat contour is magnified at most ~8×.
    const scale = sum > 1e-6 ? R / Math.max(sum, 0.12) : 0;
    // One revolution per DFT window (DFT_N samples), locked to the master beat.
    const windowBeats = DFT_N / SAMPLES_PER_BEAT;
    const theta = ((m.beat / windowBeats) % 1) * Math.PI * 2;
    const cu = this.edgeLen - EPI_R - 0.3;
    const cv = STRIP_Y + STRIP_H * 0.5;
    let x = 0;
    let y = 0;
    this.stripPoint(this.epiChain, 0, cu, cv);
    for (let i = 0; i < EPI_COUNT; i++) {
      const line = this.epiCircles[i];
      if (line === undefined) break;
      if (i >= count) {
        b.setLineAlpha(line, 0);
        this.stripPoint(this.epiChain, i + 1, cu + x, cv + y);
        continue;
      }
      const r = this.ha[i] * scale;
      // Circle centred on the running tip.
      for (let p = 0; p < EPI_CIRCLE_PTS; p++) {
        const a = (p / EPI_CIRCLE_PTS) * Math.PI * 2;
        this.stripPoint(line, p, cu + x + Math.cos(a) * r, cv + y + Math.sin(a) * r);
      }
      b.setLineAlpha(line, 1);
      b.setLineColor(line, this.runeRgb[0], this.runeRgb[1], this.runeRgb[2], (0.12 + 0.18 * (1 - i / EPI_COUNT)) * br);
      // x = Σ a·sin, y = Σ a·cos: the vertical coordinate of the tip is the reconstructed contour.
      const ang = this.hf[i] * theta + this.hp[i];
      x += r * Math.sin(ang);
      y += r * Math.cos(ang);
      this.stripPoint(this.epiChain, i + 1, cu + x, cv + y);
    }
    b.setLineColor(this.epiChain, 1, 1, 1, (0.3 + 0.3 * m.beatPulse) * br);

    // Trace: the tip's height over recent time, drawn rightward toward the strip.
    this.traceTimer += dt;
    if (this.traceTimer >= 1 / 30) {
      this.traceTimer = 0;
      this.traceY.copyWithin(1, 0, TRACE_PTS - 1);
      this.traceY[0] = y;
    }
    hexToRgb(this.palette.neonA, this.rgb);
    // Newest sample sits beside the circles and flows left, toward the strip's future-beat ticks.
    const t0 = cu - EPI_R - 0.25;
    const span = 1.4;
    for (let i = 0; i < TRACE_PTS; i++) {
      const u = t0 - (span * i) / (TRACE_PTS - 1);
      this.stripPoint(this.epiTrace, i, u, cv + this.traceY[i]);
      b.setColor(this.epiTrace, i, this.rgb[0], this.rgb[1], this.rgb[2], (0.55 * (1 - i / TRACE_PTS)) * br);
    }
  }

  dispose(): void {
    this.batch.dispose();
  }
}
