/**
 * The master beat ruler (UI-01, NEW-09): one continuous master timeline with beat ticks, bar lines
 * and bar numbers, a moving playhead, and one lane per cassette showing where each tape's passes,
 * actions and life/sync changes sit in MASTER time. Visible in every phase, recording included.
 *
 * The static picture is drawn to a canvas only when something it depends on changes; the playhead
 * is a DOM element moved by transform every frame.
 */
import {
  BEATS_PER_BAR,
  TAPE_COLORS,
  TAPE_NAMES,
  type ActionKind,
  type DeckView,
  type SessionView,
} from '../../core/types';
import type { MusicPulse } from '../../contracts';
import { Bind, h } from './dom';
import { icon } from './icons';
import {
  barLabelStep,
  formatSpeed,
  formatWorldRate,
  laneLayout,
  masterPositionText,
  placeMarks,
  type LaneLayout,
} from './model';

const INK = '#14110f';
const PAPER = '#f3ead8';
const TRACK = '#0d0b0a';
const DEAD = '#9aa3b5';
const DESYNC = '#c98bff';
const GOOD = '#7dff6b';
const THREAT = '#ff4d6d';
const SPAN_TWEEN_MS = 280;

export interface RulerGeometry {
  gutter: number;
  trackX: number;
  trackW: number;
  bandH: number;
  threatH: number;
  laneY: [number, number, number, number];
  laneH: number;
}

/** Pixel layout of the ruler body. Kept separate so the playhead and the canvas agree exactly. */
export function rulerGeometry(w: number, h: number, em: number, slim: boolean): RulerGeometry {
  const gutter = slim ? Math.round(em * 1.8) : Math.round(em * 5.2);
  const padR = Math.round(em * 0.8);
  const trackX = gutter;
  const trackW = Math.max(10, w - gutter - padR);
  const bandH = slim ? Math.round(Math.max(10, h * 0.26)) : Math.round(Math.max(18, Math.min(h * 0.27, em * 1.95)));
  const threatH = slim ? 0 : Math.round(bandH * 0.36);
  const gap = slim ? 2 : Math.max(2, Math.round(em * 0.22));
  const lanesTop = bandH + gap;
  const laneH = Math.max(3, (h - lanesTop - gap * 4) / 4);
  const laneY = [0, 1, 2, 3].map((i) => lanesTop + i * (laneH + gap)) as RulerGeometry['laneY'];
  return { gutter, trackX, trackW, bandH, threatH, laneY, laneH };
}

interface SpanTween {
  from: number;
  to: number;
  t0: number;
  cur: number;
}

const LEGEND: { kind: ActionKind; label: string }[] = [
  { kind: 'light', label: 'light' },
  { kind: 'heavy', label: 'heavy' },
  { kind: 'dodge', label: 'dodge' },
  { kind: 'ranged', label: 'ranged' },
  { kind: 'interact', label: 'interact' },
  { kind: 'ability', label: 'ability' },
];

/** SVG form of the lane glyphs, so the legend matches the canvas exactly. */
function glyphSvg(kind: ActionKind): string {
  const body: Record<ActionKind, string> = {
    light: '<path d="M9 18L15 6" stroke="currentColor" stroke-width="3" stroke-linecap="round"/>',
    heavy: '<path d="M12 3l8 9-8 9-8-9z" fill="currentColor"/>',
    dodge: '<path d="M4 6l6 6-6 6M12 6l6 6-6 6" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linejoin="round"/>',
    ranged: '<path d="M4 7h7V3l9 9-9 9v-4H4z" fill="currentColor"/>',
    interact: '<rect x="5" y="5" width="14" height="14" rx="2" fill="none" stroke="currentColor" stroke-width="3"/>',
    ability: '<path d="M12 2l2.6 7.4L22 12l-7.4 2.6L12 22l-2.6-7.4L2 12l7.4-2.6z" fill="currentColor"/>',
  };
  return `<svg class="odh-glyph" viewBox="0 0 24 24" aria-hidden="true">${body[kind]}</svg>`;
}

export class RulerEl {
  readonly root: HTMLElement;
  private readonly body: HTMLElement;
  private readonly canvas: HTMLCanvasElement;
  private readonly g: CanvasRenderingContext2D | null;
  private readonly playhead: HTMLElement;
  private readonly posB: Bind;
  private readonly worldB: Bind;
  private readonly lampB: Bind;
  private readonly horizonB: Bind;

  private w = 0;
  private h = 0;
  private dpr = 1;
  private em = 14;
  private fontDisplay = 'Arial Black, Impact, sans-serif';
  private fontMono = 'Consolas, monospace';
  private slim = false;
  private geo: RulerGeometry | null = null;
  private key = '';
  private lastX = NaN;
  private readonly spans: (SpanTween | null)[] = [null, null, null, null];
  private readonly hatchCache = new Map<string, CanvasPattern | null>();
  private readonly resizeObs: ResizeObserver | null = null;

  constructor() {
    this.root = h('div', 'odh-ruler');
    const head = h('div', 'odh-ruler-head');
    head.innerHTML =
      '<span class="odh-ruler-title">MASTER BEAT RULER<small>bars here are master bars</small></span>' +
      '<span class="odh-lamp" aria-hidden="true"></span>' +
      '<span class="odh-ruler-pos"></span>' +
      '<span class="odh-ruler-horizon"></span>' +
      `<span class="odh-world">${icon('world')}<span class="odh-world-txt"></span></span>` +
      `<span class="odh-legend">${LEGEND.map((l) => `<span>${glyphSvg(l.kind)}${l.label}</span>`).join('')}` +
      `<span class="odh-legend-state">${icon('death')}died</span><span class="odh-legend-state odh-legend-desync">${icon(
        'desync',
      )}desync</span><span class="odh-legend-state odh-legend-resync">${icon('resync')}resync</span></span>`;
    this.body = h('div', 'odh-ruler-body');
    this.canvas = h('canvas', 'odh-ruler-canvas');
    this.canvas.setAttribute('aria-hidden', 'true');
    this.playhead = h('div', 'odh-playhead', '<span class="odh-playhead-head"></span>');
    this.body.append(this.canvas, this.playhead);
    this.root.append(head, this.body);
    this.g = this.canvas.getContext('2d');

    this.posB = new Bind(head.querySelector('.odh-ruler-pos') as HTMLElement);
    this.worldB = new Bind(head.querySelector('.odh-world') as HTMLElement);
    this.lampB = new Bind(head.querySelector('.odh-lamp') as HTMLElement);
    this.horizonB = new Bind(head.querySelector('.odh-ruler-horizon') as HTMLElement);

    if (typeof ResizeObserver === 'function') {
      this.resizeObs = new ResizeObserver(() => this.measure());
      this.resizeObs.observe(this.body);
    }
  }

  private measure(): void {
    const r = this.body.getBoundingClientRect();
    const cs = getComputedStyle(this.body);
    this.em = parseFloat(cs.fontSize) || 14;
    const fd = cs.getPropertyValue('--font-display').trim();
    const fm = cs.getPropertyValue('--font-mono').trim();
    if (fd) this.fontDisplay = fd;
    if (fm) this.fontMono = fm;
    this.w = Math.max(0, Math.round(r.width));
    this.h = Math.max(0, Math.round(r.height));
    this.dpr = Math.min(3, window.devicePixelRatio || 1);
    this.canvas.width = Math.max(1, Math.round(this.w * this.dpr));
    this.canvas.height = Math.max(1, Math.round(this.h * this.dpr));
    this.key = '';
    this.lastX = NaN;
  }

  setSlim(slim: boolean): void {
    this.slim = slim;
  }

  update(view: SessionView, pulse: MusicPulse, now: number, reduced: boolean): void {
    // Header readouts (master position, horizon, world rate relative to the player).
    this.posB.setText(masterPositionText(view.beat, view.horizonBeats));
    const horizonBars = view.horizonBeats / BEATS_PER_BAR;
    this.horizonB.setText(`of ${Math.round(horizonBars * 100) / 100} master bars`);
    const rate = Math.round(view.worldRate * 100) / 100;
    this.worldB.toggle('odh-world--slow', rate < 0.999 && rate > 0);
    this.worldB.toggle('odh-world--fast', rate > 1.001);
    const relative = (view.phase === 'recording' || view.phase === 'countin') && rate > 0 ? ' vs you' : '';
    this.worldB.setHtml(`${icon('world')}<span class="odh-world-txt">${formatWorldRate(rate)}${relative}</span>`);
    this.lampB.style('opacity', reduced ? '0.85' : (0.25 + 0.75 * Math.max(0, Math.min(1, pulse.beatPulse))).toFixed(2));
    this.lampB.toggle('odh-lamp--bar', pulse.barPulse > 0.6);

    if (this.w === 0 && this.resizeObs === null) this.measure();
    if (this.w === 0 || this.h === 0) return;

    const geo = rulerGeometry(this.w, this.h, this.em, this.slim);
    this.geo = geo;
    const horizon = Math.max(1e-6, view.horizonBeats);

    // Span tweens: when a tape's speed changes the lane length slides to its new span (NEW-10).
    let animating = false;
    for (let i = 0; i < 4; i++) {
      const d = view.decks[i];
      const target = d.speed !== null ? d.spanBars * BEATS_PER_BAR : 0;
      let t = this.spans[i];
      if (!t) {
        t = { from: target, to: target, t0: now, cur: target };
        this.spans[i] = t;
      } else if (t.to !== target) {
        const startFrom = t.to === 0 || target === 0 || reduced ? target : t.cur;
        t = { from: startFrom, to: target, t0: now, cur: startFrom };
        this.spans[i] = t;
      }
      const k = Math.min(1, (now - t.t0) / SPAN_TWEEN_MS);
      const e = 1 - Math.pow(1 - k, 3);
      t.cur = t.from + (t.to - t.from) * e;
      if (k < 1) animating = true;
    }

    const liveIdx = view.phase === 'recording' && view.active !== null ? view.active : -1;
    const livePx = liveIdx >= 0 ? Math.round((Math.max(0, view.beat) / horizon) * geo.trackW) : -1;
    const key = this.drawKey(view, livePx, animating ? now : 0);
    if (key !== this.key) {
      this.key = key;
      this.draw(view, geo, liveIdx);
    }

    const x = geo.trackX + Math.max(0, Math.min(1, view.beat / horizon)) * geo.trackW;
    if (Number.isNaN(this.lastX) || Math.abs(x - this.lastX) > 0.2) {
      this.lastX = x;
      this.playhead.style.transform = `translate3d(${x.toFixed(1)}px,0,0)`;
    }
  }

  private drawKey(view: SessionView, livePx: number, animStamp: number): string {
    let k = `${this.w}x${this.h}@${this.dpr}|${this.slim ? 1 : 0}|${view.horizonBeats}|${view.level.bpm}|${view.phase}|${view.active}|${livePx}|${animStamp}|${view.threatBeats.join(',')}`;
    for (let i = 0; i < 4; i++) {
      const d = view.decks[i];
      let tickSum = 0;
      for (const m of d.marks) tickSum += m.tick;
      let stateSum = 0;
      for (const s of d.stateMarks) stateSum += s.beat;
      k += `#${d.status}|${d.speed}|${d.endMode}|${d.marks.length}:${tickSum}|${d.stateMarks.length}:${stateSum.toFixed(3)}|${d.life}|${d.synced ? 1 : 0}|${(this.spans[i]?.cur ?? 0).toFixed(3)}`;
    }
    return k;
  }

  private hatch(color: string, alpha: number): CanvasPattern | null {
    const id = `${color}/${alpha}/${this.dpr}`;
    if (this.hatchCache.has(id)) return this.hatchCache.get(id) ?? null;
    const s = Math.max(4, Math.round(7 * this.dpr));
    const c = document.createElement('canvas');
    c.width = s;
    c.height = s;
    const g = c.getContext('2d');
    let pat: CanvasPattern | null = null;
    if (g && this.g) {
      g.strokeStyle = color;
      g.globalAlpha = alpha;
      g.lineWidth = Math.max(1, 1.6 * this.dpr);
      g.beginPath();
      g.moveTo(-1, s + 1);
      g.lineTo(s + 1, -1);
      g.moveTo(-1, 1);
      g.lineTo(1, -1);
      g.moveTo(s - 1, s + 1);
      g.lineTo(s + 1, s - 1);
      g.stroke();
      pat = this.g.createPattern(c, 'repeat');
    }
    this.hatchCache.set(id, pat);
    return pat;
  }

  private draw(view: SessionView, geo: RulerGeometry, liveIdx: number): void {
    const g = this.g;
    if (!g) return;
    const { trackX, trackW, bandH, threatH, laneY, laneH } = geo;
    const horizon = Math.max(1e-6, view.horizonBeats);
    const X = (beat: number) => trackX + (beat / horizon) * trackW;
    g.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
    g.clearRect(0, 0, this.w, this.h);
    const em = this.em;
    const lanesBottom = laneY[3] + laneH;

    // ── beat grid through the lanes (faint) so every lane reads against master beats.
    const totalBeats = Math.ceil(horizon - 1e-6);
    const beatPx = trackW / horizon;
    g.lineWidth = 1;
    for (let b = 0; b <= totalBeats; b++) {
      const x = Math.round(X(Math.min(b, horizon))) + 0.5;
      const isBar = b % BEATS_PER_BAR === 0;
      if (!isBar && beatPx < 5) continue;
      g.strokeStyle = isBar ? 'rgba(243,234,216,0.16)' : 'rgba(243,234,216,0.05)';
      g.beginPath();
      g.moveTo(x, bandH);
      g.lineTo(x, lanesBottom);
      g.stroke();
    }

    // ── ruler band: ticks, bar lines, bar numbers.
    const horizonBars = horizon / BEATS_PER_BAR;
    const step = barLabelStep(horizonBars, trackW, em * 2.1);
    g.fillStyle = 'rgba(243,234,216,0.06)';
    g.fillRect(trackX, threatH, trackW, bandH - threatH);
    for (let b = 0; b <= totalBeats; b++) {
      const beat = Math.min(b, horizon);
      const x = Math.round(X(beat)) + 0.5;
      const isBar = b % BEATS_PER_BAR === 0;
      if (!isBar && beatPx < 3) continue;
      const len = isBar ? (bandH - threatH) * 0.62 : (bandH - threatH) * 0.24;
      g.strokeStyle = isBar ? PAPER : 'rgba(243,234,216,0.55)';
      g.lineWidth = isBar ? 2 : 1;
      g.beginPath();
      g.moveTo(x, bandH);
      g.lineTo(x, bandH - len);
      g.stroke();
      const bar = b / BEATS_PER_BAR;
      if (isBar && bar % step === 0 && bar < horizonBars - 1e-6 && !this.slim) {
        g.fillStyle = PAPER;
        g.font = `${Math.round(em * 0.72)}px ${this.fontDisplay}`;
        g.textBaseline = 'alphabetic';
        g.fillText(String(bar + 1), x + 3, bandH - (bandH - threatH) * 0.3);
      }
    }
    // Baseline + horizon end cap.
    g.fillStyle = PAPER;
    g.fillRect(trackX, bandH - 2, trackW, 2);
    g.fillRect(trackX + trackW - 3, threatH, 3, lanesBottom - threatH);

    // ── threat beats (beatSight) as small markers above the ruler.
    if (threatH > 0 && view.threatBeats.length) {
      g.fillStyle = THREAT;
      g.strokeStyle = INK;
      g.lineWidth = 1.5;
      const s = Math.max(5, threatH * 0.62);
      for (const tb of view.threatBeats) {
        if (tb < 0 || tb > horizon) continue;
        const x = X(tb);
        g.beginPath();
        g.moveTo(x - s * 0.7, 1);
        g.lineTo(x + s * 0.7, 1);
        g.lineTo(x, 1 + s * 1.2);
        g.closePath();
        g.fill();
        g.stroke();
      }
    }

    // ── lanes
    for (let i = 0; i < 4; i++) this.drawLane(g, view, view.decks[i], i, geo, X, i === liveIdx);

    // Gutter caption: unit reminder (chapter 03 terminology).
    if (!this.slim) {
      g.fillStyle = 'rgba(243,234,216,0.6)';
      g.font = `${Math.round(em * 0.56)}px ${this.fontMono}`;
      g.textBaseline = 'middle';
      g.fillText('MASTER', 4, threatH + (bandH - threatH) * 0.32);
      g.fillText('BARS →', 4, threatH + (bandH - threatH) * 0.74);
    }
  }

  private drawLane(
    g: CanvasRenderingContext2D,
    view: SessionView,
    d: DeckView,
    i: number,
    geo: RulerGeometry,
    X: (b: number) => number,
    live: boolean,
  ): void {
    const color = TAPE_COLORS[i];
    const y = geo.laneY[i];
    const lh = geo.laneH;
    const cy = y + lh / 2;
    const { trackX, trackW } = geo;
    const em = this.em;
    const horizon = Math.max(1e-6, view.horizonBeats);
    const isActive = view.active === i;

    // Gutter label: cassette letter chip + its speed, so every lane names its tape and rate.
    const chipW = this.slim ? geo.gutter - 4 : Math.min(lh * 1.25, em * 1.6);
    g.fillStyle = d.status === 'unavailable' ? '#3a332d' : color;
    roundRect(g, 2, y, chipW, lh, Math.min(4, lh / 3));
    g.fill();
    if (isActive && !this.slim) {
      g.strokeStyle = PAPER;
      g.lineWidth = 2;
      g.stroke();
    }
    if (lh >= 8) {
      g.fillStyle = d.status === 'unavailable' ? '#7a7068' : INK;
      g.font = `${Math.round(Math.min(lh * 0.78, em * 0.95))}px ${this.fontDisplay}`;
      g.textAlign = 'center';
      g.textBaseline = 'middle';
      g.fillText(TAPE_NAMES[i], 2 + chipW / 2, cy + 1);
      g.textAlign = 'left';
    }
    if (!this.slim && lh >= 8) {
      g.fillStyle = d.status === 'unavailable' ? '#7a7068' : PAPER;
      g.font = `${Math.round(Math.min(lh * 0.7, em * 0.82))}px ${this.fontDisplay}`;
      g.textBaseline = 'middle';
      g.fillText(d.status === 'unavailable' ? '—' : formatSpeed(d.speed), chipW + 7, cy + 1);
    }

    // Track background.
    g.fillStyle = TRACK;
    g.fillRect(trackX, y, trackW, lh);

    if (d.status === 'unavailable') {
      const pat = this.hatch('#5a524b', 0.7);
      if (pat) {
        g.fillStyle = pat;
        g.fillRect(trackX, y, trackW, lh);
      }
      return;
    }

    const span = this.spans[i]?.cur ?? (d.speed !== null ? d.spanBars * BEATS_PER_BAR : 0);
    const showLayout = d.speed !== null && d.endMode !== null && span > 0 && d.status !== 'empty';

    if (!showLayout) {
      // Future, unrecorded cassette: an empty lane, never a predicted performer (REC-03).
      g.save();
      g.setLineDash([5, 4]);
      g.strokeStyle = hexA(color, 0.55);
      g.lineWidth = 1.5;
      g.strokeRect(trackX + 1, y + 1, trackW - 2, lh - 2);
      g.restore();
      if (lh >= 9 && !this.slim) {
        g.fillStyle = hexA(color, 0.7);
        g.font = `${Math.round(Math.min(lh * 0.62, em * 0.66))}px ${this.fontMono}`;
        g.textBaseline = 'middle';
        g.fillText('NOT RECORDED', trackX + 8, cy + 1);
      }
      return;
    }

    const layout: LaneLayout = laneLayout(span, d.endMode!, horizon);
    const recorded = d.status === 'pending' || d.status === 'committed';
    const inset = Math.max(1, Math.round(lh * 0.1));

    for (const seg of layout.segments) {
      const x0 = X(seg.start);
      const x1 = X(seg.end);
      const w = Math.max(1, x1 - x0);
      const first = seg.traversal === 0;
      if (recorded) {
        g.fillStyle = hexA(color, first ? (d.status === 'committed' ? 1 : 0.78) : 0.36);
        g.fillRect(x0, y + inset, w, lh - inset * 2);
        if (d.status === 'pending' && first) {
          // Uncommitted take: striped so "not locked yet" reads without colour.
          const pat = this.hatch(INK, 0.35);
          if (pat) {
            g.fillStyle = pat;
            g.fillRect(x0, y + inset, w, lh - inset * 2);
          }
        }
      } else {
        // Armed preview / recording: the tape's time layout as outlines; the recorded part fills live.
        g.fillStyle = hexA(color, first ? 0.2 : 0.08);
        g.fillRect(x0, y + inset, w, lh - inset * 2);
        g.save();
        if (!first || d.status === 'armed') g.setLineDash([4, 3]);
        g.strokeStyle = hexA(color, first ? 0.95 : 0.55);
        g.lineWidth = first ? 2 : 1.25;
        g.strokeRect(x0 + 1, y + inset + 0.5, w - 2, lh - inset * 2 - 1);
        g.restore();
      }
      // Boundary between passes: a hard ink cut for repeat, a turn notch for reverse.
      if (!first) {
        g.fillStyle = INK;
        g.fillRect(x0 - 1.5, y, 3, lh);
        if (d.endMode === 'reverse') {
          g.fillStyle = PAPER;
          g.beginPath();
          g.moveTo(x0 - 1, y);
          g.lineTo(x0 + Math.min(6, lh * 0.4), y);
          g.lineTo(x0 - 1, y + Math.min(6, lh * 0.4));
          g.closePath();
          g.fill();
        }
      }
      // Direction arrows on the repeat / reverse passes.
      if (!first && w > lh * 1.4 && lh >= 6) {
        const n = Math.max(1, Math.min(4, Math.floor(w / (lh * 5))));
        g.strokeStyle = recorded ? hexA(INK, 0.75) : hexA(color, 0.7);
        g.lineWidth = Math.max(1.2, lh * 0.12);
        g.lineJoin = 'round';
        const ah = lh * 0.26;
        for (let a = 0; a < n; a++) {
          const ax = x0 + (w * (a + 0.5)) / n;
          const dir = seg.dir;
          g.beginPath();
          g.moveTo(ax - dir * ah * 0.6, cy - ah);
          g.lineTo(ax + dir * ah * 0.6, cy);
          g.lineTo(ax - dir * ah * 0.6, cy + ah);
          g.stroke();
        }
      }
    }

    // 'stop' tapes: a hold line to the horizon — the self stays where it ended (still solid).
    if (layout.holdFrom !== null) {
      const hx = X(layout.holdFrom);
      g.save();
      g.setLineDash([2, 3]);
      g.strokeStyle = hexA(color, recorded ? 0.85 : 0.5);
      g.lineWidth = Math.max(1.5, lh * 0.16);
      g.beginPath();
      g.moveTo(hx + 2, cy);
      g.lineTo(X(horizon) - 2, cy);
      g.stroke();
      g.restore();
      const s = Math.max(3, lh * 0.34);
      g.fillStyle = recorded ? color : hexA(color, 0.6);
      g.strokeStyle = INK;
      g.lineWidth = 1.5;
      g.fillRect(hx + 3, cy - s / 2, s, s);
      g.strokeRect(hx + 3, cy - s / 2, s, s);
      if (lh >= 10 && !this.slim && X(horizon) - hx > em * 4) {
        g.font = `${Math.round(Math.min(lh * 0.6, em * 0.62))}px ${this.fontMono}`;
        g.textBaseline = 'middle';
        const tx = hx + s + 9;
        const tw = g.measureText('HOLDS POSE').width;
        g.fillStyle = TRACK;
        g.fillRect(tx - 3, y + 1, tw + 6, lh - 2);
        g.fillStyle = hexA(color, 0.9);
        g.fillText('HOLDS POSE', tx, cy + 1);
      }
    }

    // Live fill: the lane being recorded fills in as the master playhead advances.
    if (live) {
      const fx1 = Math.min(X(Math.max(0, view.beat)), X(Math.min(span, horizon)));
      if (fx1 > trackX) {
        g.fillStyle = color;
        g.fillRect(trackX, y + inset, fx1 - trackX, lh - inset * 2);
        g.fillStyle = PAPER;
        g.fillRect(fx1 - 2, y, 2, lh);
      }
    }

    // Action marks, mapped from local ticks through the tape's speed onto master beats.
    if (d.marks.length && d.speed !== null && lh >= 5) {
      const placed = placeMarks(d.marks, d.speed, view.level.bpm, layout);
      const gs = Math.min(lh * 0.74, em * 1.0);
      for (const p of placed) {
        if (live && p.traversal === 0) {
          drawGlyph(g, p.kind, X(p.beat), cy, gs, INK, 1);
        } else {
          drawGlyph(g, p.kind, X(p.beat), cy, gs, recorded ? INK : hexA(color, 0.9), p.traversal === 0 ? 1 : 0.6);
        }
      }
    }

    // State marks from the latest resolved run: dead / desynced stretches, then the event glyphs.
    const marks = [...d.stateMarks].sort((a, b) => a.beat - b.beat);
    let desyncFrom: number | null = null;
    for (const m of marks) {
      if (m.kind === 'desync') desyncFrom = m.beat;
      else if (m.kind === 'resync' && desyncFrom !== null) {
        this.shade(g, X(desyncFrom), X(m.beat), y, lh, DESYNC, 0.75);
        desyncFrom = null;
      } else if (m.kind === 'death') {
        if (desyncFrom !== null) {
          this.shade(g, X(desyncFrom), X(m.beat), y, lh, DESYNC, 0.75);
          desyncFrom = null;
        }
        this.shade(g, X(m.beat), X(horizon), y, lh, '#14110f', 0.55);
        this.shade(g, X(m.beat), X(horizon), y, lh, DEAD, 0.55);
      }
    }
    if (desyncFrom !== null) this.shade(g, X(desyncFrom), X(horizon), y, lh, DESYNC, 0.75);
    for (const m of marks) {
      const x = X(Math.max(0, Math.min(horizon, m.beat)));
      drawStateGlyph(g, m.kind, x, cy, Math.min(lh * 0.95, em * 1.1));
    }

    if (isActive && !this.slim) {
      g.strokeStyle = PAPER;
      g.lineWidth = 1.5;
      g.strokeRect(trackX - 0.5, y - 0.5, trackW + 1, lh + 1);
    }
  }

  private shade(g: CanvasRenderingContext2D, x0: number, x1: number, y: number, lh: number, color: string, alpha: number): void {
    if (x1 <= x0) return;
    const pat = this.hatch(color, alpha);
    if (!pat) return;
    g.fillStyle = pat;
    g.fillRect(x0, y, x1 - x0, lh);
  }

  dispose(): void {
    this.resizeObs?.disconnect();
  }
}

function roundRect(g: CanvasRenderingContext2D, x: number, y: number, w: number, hgt: number, r: number): void {
  g.beginPath();
  g.moveTo(x + r, y);
  g.arcTo(x + w, y, x + w, y + hgt, r);
  g.arcTo(x + w, y + hgt, x, y + hgt, r);
  g.arcTo(x, y + hgt, x, y, r);
  g.arcTo(x, y, x + w, y, r);
  g.closePath();
}

function hexA(hex: string, a: number): string {
  const n = parseInt(hex.slice(1), 16);
  return `rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},${a})`;
}

/** Lane glyphs: distinct silhouettes so kinds read without colour (matches glyphSvg). */
function drawGlyph(
  g: CanvasRenderingContext2D,
  kind: ActionKind,
  x: number,
  cy: number,
  size: number,
  color: string,
  alpha: number,
): void {
  const s = size / 2;
  g.save();
  g.globalAlpha = alpha;
  g.fillStyle = color;
  g.strokeStyle = color;
  g.lineJoin = 'round';
  g.lineCap = 'round';
  g.beginPath();
  switch (kind) {
    case 'light':
      g.lineWidth = Math.max(1.4, s * 0.38);
      g.moveTo(x - s * 0.45, cy + s);
      g.lineTo(x + s * 0.45, cy - s);
      g.stroke();
      break;
    case 'heavy':
      g.moveTo(x, cy - s * 1.15);
      g.lineTo(x + s * 0.85, cy);
      g.lineTo(x, cy + s * 1.15);
      g.lineTo(x - s * 0.85, cy);
      g.closePath();
      g.fill();
      break;
    case 'dodge':
      g.lineWidth = Math.max(1.2, s * 0.3);
      g.moveTo(x - s * 0.9, cy - s * 0.7);
      g.lineTo(x - s * 0.2, cy);
      g.lineTo(x - s * 0.9, cy + s * 0.7);
      g.moveTo(x + s * 0.1, cy - s * 0.7);
      g.lineTo(x + s * 0.8, cy);
      g.lineTo(x + s * 0.1, cy + s * 0.7);
      g.stroke();
      break;
    case 'ranged':
      g.moveTo(x - s, cy - s * 0.35);
      g.lineTo(x, cy - s * 0.35);
      g.lineTo(x, cy - s * 0.9);
      g.lineTo(x + s, cy);
      g.lineTo(x, cy + s * 0.9);
      g.lineTo(x, cy + s * 0.35);
      g.lineTo(x - s, cy + s * 0.35);
      g.closePath();
      g.fill();
      break;
    case 'interact':
      g.lineWidth = Math.max(1.2, s * 0.32);
      g.rect(x - s * 0.7, cy - s * 0.7, s * 1.4, s * 1.4);
      g.stroke();
      break;
    case 'ability': {
      const r1 = s * 1.05;
      const r2 = s * 0.32;
      for (let k = 0; k < 8; k++) {
        const r = k % 2 === 0 ? r1 : r2;
        const a = (k * Math.PI) / 4 - Math.PI / 2;
        if (k === 0) g.moveTo(x + Math.cos(a) * r, cy + Math.sin(a) * r);
        else g.lineTo(x + Math.cos(a) * r, cy + Math.sin(a) * r);
      }
      g.closePath();
      g.fill();
      break;
    }
  }
  g.restore();
}

function drawStateGlyph(g: CanvasRenderingContext2D, kind: 'death' | 'desync' | 'resync', x: number, cy: number, size: number): void {
  const s = size / 2;
  g.save();
  g.lineCap = 'round';
  g.lineJoin = 'round';
  if (kind === 'death') {
    for (const [w, c] of [
      [Math.max(3, s * 0.6), INK],
      [Math.max(1.6, s * 0.3), PAPER],
    ] as [number, string][]) {
      g.lineWidth = w;
      g.strokeStyle = c;
      g.beginPath();
      g.moveTo(x - s * 0.7, cy - s * 0.7);
      g.lineTo(x + s * 0.7, cy + s * 0.7);
      g.moveTo(x + s * 0.7, cy - s * 0.7);
      g.lineTo(x - s * 0.7, cy + s * 0.7);
      g.stroke();
    }
  } else if (kind === 'desync') {
    for (const [w, c] of [
      [Math.max(3, s * 0.5), INK],
      [Math.max(1.5, s * 0.24), DESYNC],
    ] as [number, string][]) {
      g.lineWidth = w;
      g.strokeStyle = c;
      g.beginPath();
      g.moveTo(x - s * 0.8, cy + s * 0.2);
      g.lineTo(x - s * 0.35, cy - s * 0.6);
      g.lineTo(x + s * 0.05, cy + s * 0.6);
      g.lineTo(x + s * 0.45, cy - s * 0.6);
      g.lineTo(x + s * 0.8, cy);
      g.stroke();
    }
  } else {
    g.lineWidth = Math.max(3, s * 0.5);
    g.strokeStyle = INK;
    g.beginPath();
    g.arc(x, cy, s * 0.65, 0, Math.PI * 2);
    g.stroke();
    g.lineWidth = Math.max(1.5, s * 0.24);
    g.strokeStyle = GOOD;
    g.stroke();
  }
  g.restore();
}
