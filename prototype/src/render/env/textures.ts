/**
 * Canvas-painted textures for the environment kit. Everything is procedural (no remote assets) and
 * seeded, so a level always looks the same.
 *
 * Style (ART-02, chapter 19 "Materials and surfaces"): large flat cel colours with hand-drawn bevel
 * highlights and darker edge lines; small wear (chips, speckles, cracks) supports the big forms
 * rather than competing with them. Graffiti (ART-03) is the one loud, playful layer.
 */
import * as THREE from 'three';
import { colorTexture } from '../materials';
import { type EnvPalette, css, mixColor, scaleColor } from '../palettes';
import type { FloorKind } from './layout';
import { Rng, hashString } from './rng';

type Ctx = CanvasRenderingContext2D;

function canvas(w: number, h = w): [HTMLCanvasElement, Ctx] {
  const c = document.createElement('canvas');
  c.width = w;
  c.height = h;
  const ctx = c.getContext('2d');
  if (!ctx) throw new Error('2D canvas unavailable');
  return [c, ctx];
}

function speckle(ctx: Ctx, rng: Rng, x: number, y: number, w: number, h: number, base: number, count: number, spread = 0.12): void {
  for (let i = 0; i < count; i++) {
    const f = 1 + rng.range(-spread, spread);
    ctx.fillStyle = css(scaleColor(base, f));
    const s = rng.range(1, 2.6);
    ctx.fillRect(x + rng.next() * w, y + rng.next() * h, s, s);
  }
}

/** Slab with bevel light (top-left) and shade (bottom-right) edges. */
function bevelRect(ctx: Ctx, x: number, y: number, w: number, h: number, color: number, edge = 3, rng?: Rng): void {
  ctx.fillStyle = css(color);
  ctx.fillRect(x, y, w, h);
  ctx.fillStyle = css(scaleColor(color, 1.16));
  ctx.fillRect(x, y, w, edge);
  ctx.fillRect(x, y, edge, h);
  ctx.fillStyle = css(scaleColor(color, 0.72));
  ctx.fillRect(x, y + h - edge, w, edge);
  ctx.fillRect(x + w - edge, y, edge, h);
  if (rng) {
    // Chipped corners keep the masonry from looking machine-cut.
    for (let i = 0; i < 2; i++) {
      if (!rng.chance(0.45)) continue;
      const cx = rng.chance(0.5) ? x : x + w;
      const cy = rng.chance(0.5) ? y : y + h;
      const s = rng.range(3, 8);
      ctx.fillStyle = css(scaleColor(color, 0.6));
      ctx.beginPath();
      ctx.moveTo(cx, cy);
      ctx.lineTo(cx + (cx === x ? s : -s), cy);
      ctx.lineTo(cx, cy + (cy === y ? s : -s));
      ctx.closePath();
      ctx.fill();
    }
  }
}

function crackPath(ctx: Ctx, rng: Rng, x: number, y: number, len: number, color: string, width: number, depth = 0): void {
  let a = rng.range(0, Math.PI * 2);
  ctx.strokeStyle = color;
  ctx.lineWidth = width;
  ctx.lineCap = 'round';
  ctx.beginPath();
  ctx.moveTo(x, y);
  let px = x;
  let py = y;
  const steps = 5;
  for (let i = 0; i < steps; i++) {
    a += rng.range(-0.7, 0.7);
    px += Math.cos(a) * (len / steps);
    py += Math.sin(a) * (len / steps);
    ctx.lineTo(px, py);
    if (depth < 1 && rng.chance(0.3)) {
      ctx.stroke();
      crackPath(ctx, rng, px, py, len * 0.45, color, width * 0.7, depth + 1);
      ctx.strokeStyle = color;
      ctx.lineWidth = width;
      ctx.beginPath();
      ctx.moveTo(px, py);
    }
  }
  ctx.stroke();
}

function rivet(ctx: Ctx, x: number, y: number, r: number, base: number): void {
  ctx.fillStyle = css(scaleColor(base, 0.55));
  ctx.beginPath();
  ctx.arc(x + 0.8, y + 0.8, r, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillStyle = css(scaleColor(base, 1.35));
  ctx.beginPath();
  ctx.arc(x, y, r * 0.8, 0, Math.PI * 2);
  ctx.fill();
}

/**
 * A rune glyph. The boards use circled stars, angular strokes and stacked bars; the alphabet is not
 * decided (chapter 18), so these are abstract and integrated into plates rather than fantasy text.
 */
export function drawGlyph(ctx: Ctx, rng: Rng, cx: number, cy: number, r: number, stroke: string, width: number): void {
  ctx.save();
  ctx.strokeStyle = stroke;
  ctx.lineWidth = width;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  const kind = rng.int(0, 3);
  ctx.beginPath();
  if (kind === 0) {
    // Circled five-point star.
    ctx.arc(cx, cy, r, 0, Math.PI * 2);
    ctx.moveTo(cx + r * 0.82 * Math.cos(-Math.PI / 2), cy + r * 0.82 * Math.sin(-Math.PI / 2));
    for (let i = 1; i <= 5; i++) {
      const a = -Math.PI / 2 + ((i * 2) % 5) * ((Math.PI * 2) / 5);
      ctx.lineTo(cx + r * 0.82 * Math.cos(a), cy + r * 0.82 * Math.sin(a));
    }
  } else if (kind === 1) {
    // Angular stave with branches.
    ctx.moveTo(cx, cy - r);
    ctx.lineTo(cx, cy + r);
    const n = rng.int(2, 3);
    for (let i = 0; i < n; i++) {
      const yy = cy - r + ((i + 0.5) / n) * 2 * r;
      const dir = rng.chance(0.5) ? 1 : -1;
      ctx.moveTo(cx, yy);
      ctx.lineTo(cx + dir * r * 0.6, yy - r * 0.35);
    }
    ctx.moveTo(cx - r * 0.7, cy + r * 0.2);
    ctx.lineTo(cx + r * 0.7, cy + r * 0.2);
  } else if (kind === 2) {
    // Triangle in ring with a ticked base.
    ctx.arc(cx, cy, r, 0, Math.PI * 2);
    ctx.moveTo(cx, cy - r * 0.7);
    ctx.lineTo(cx + r * 0.62, cy + r * 0.45);
    ctx.lineTo(cx - r * 0.62, cy + r * 0.45);
    ctx.closePath();
    ctx.moveTo(cx, cy - r * 0.2);
    ctx.lineTo(cx, cy + r * 0.45);
  } else {
    // Harmonograph-like lissajous loop: music etched into the metal.
    const a = rng.int(1, 3);
    const b = a + rng.int(1, 2);
    const ph = rng.range(0, Math.PI);
    for (let i = 0; i <= 80; i++) {
      const t = (i / 80) * Math.PI * 2;
      const x = cx + Math.sin(a * t + ph) * r;
      const y = cy + Math.sin(b * t) * r;
      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    }
  }
  ctx.stroke();
  ctx.restore();
}

// ───────────────────────────── floors ─────────────────────────────

export interface FloorTextures {
  map: THREE.CanvasTexture;
  emissiveMap?: THREE.CanvasTexture;
}

const FLOOR_PX = 128;

function paintStoneSlabs(ctx: Ctx, rng: Rng, pal: EnvPalette, base: number, pattern: 'quad' | 'brick'): void {
  const S = FLOOR_PX;
  ctx.fillStyle = css(pal.grout);
  ctx.fillRect(0, 0, S, S);
  const g = 2;
  if (pattern === 'quad') {
    const merges = rng.int(0, 3);
    const rects: [number, number, number, number][] =
      merges === 0
        ? [[0, 0, S, S]]
        : merges === 1
          ? [
              [0, 0, S / 2, S],
              [S / 2, 0, S / 2, S / 2],
              [S / 2, S / 2, S / 2, S / 2],
            ]
          : [
              [0, 0, S / 2, S / 2],
              [S / 2, 0, S / 2, S / 2],
              [0, S / 2, S / 2, S / 2],
              [S / 2, S / 2, S / 2, S / 2],
            ];
    for (const [x, y, w, h] of rects) bevelRect(ctx, x + g, y + g, w - g * 2, h - g * 2, scaleColor(base, rng.range(0.93, 1.06)), 3, rng);
  } else {
    const rows = 4;
    const rh = S / rows;
    for (let r = 0; r < rows; r++) {
      const off = r % 2 ? S / 4 : 0;
      for (let x = -S / 2 + off; x < S; x += S / 2) {
        bevelRect(ctx, x + g, r * rh + g, S / 2 - g * 2, rh - g * 2, scaleColor(base, rng.range(0.9, 1.07)), 2, rng);
      }
    }
  }
  speckle(ctx, rng, 0, 0, S, S, base, 90, 0.16);
}

function paintMetalPlate(ctx: Ctx, rng: Rng, pal: EnvPalette, base: number, style: 'panel' | 'tread'): void {
  const S = FLOOR_PX;
  ctx.fillStyle = css(pal.grout);
  ctx.fillRect(0, 0, S, S);
  bevelRect(ctx, 1, 1, S - 2, S - 2, base, 3);
  if (style === 'panel') {
    ctx.strokeStyle = css(scaleColor(base, 0.62));
    ctx.lineWidth = 2;
    ctx.beginPath();
    if (rng.chance(0.5)) {
      ctx.moveTo(S / 2, 4);
      ctx.lineTo(S / 2, S - 4);
    } else {
      ctx.moveTo(4, S / 2);
      ctx.lineTo(S - 4, S / 2);
    }
    ctx.stroke();
    ctx.strokeStyle = css(scaleColor(base, 1.2));
    ctx.lineWidth = 1;
    ctx.strokeRect(10.5, 10.5, S - 21, S - 21);
  } else {
    // Diamond tread plate.
    for (let y = 8; y < S - 4; y += 12) {
      for (let x = 8 + ((y / 12) % 2) * 6; x < S - 4; x += 12) {
        ctx.fillStyle = css(scaleColor(base, 1.25));
        ctx.fillRect(x, y, 5, 2);
        ctx.fillStyle = css(scaleColor(base, 0.7));
        ctx.fillRect(x + 1, y + 2, 5, 1);
      }
    }
  }
  for (const [x, y] of [
    [7, 7],
    [S - 7, 7],
    [7, S - 7],
    [S - 7, S - 7],
  ])
    rivet(ctx, x, y, 2.6, base);
  // Scratches.
  ctx.strokeStyle = css(scaleColor(base, 1.3), 0.5);
  ctx.lineWidth = 1;
  for (let i = 0; i < 5; i++) {
    const x = rng.range(10, S - 10);
    const y = rng.range(10, S - 10);
    const a = rng.range(0, Math.PI);
    const l = rng.range(6, 20);
    ctx.beginPath();
    ctx.moveTo(x, y);
    ctx.lineTo(x + Math.cos(a) * l, y + Math.sin(a) * l);
    ctx.stroke();
  }
  speckle(ctx, rng, 4, 4, S - 8, S - 8, base, 50, 0.12);
}

function hazardBand(ctx: Ctx, pal: EnvPalette, x: number, y: number, w: number, h: number, stripe = 12, wear = 0.25, rng?: Rng): void {
  ctx.save();
  ctx.beginPath();
  ctx.rect(x, y, w, h);
  ctx.clip();
  ctx.fillStyle = css(pal.hazard);
  ctx.fillRect(x, y, w, h);
  ctx.fillStyle = css(scaleColor(pal.ink, 1.6));
  for (let i = -h; i < w + h; i += stripe * 2) {
    ctx.beginPath();
    ctx.moveTo(x + i, y + h);
    ctx.lineTo(x + i + stripe, y + h);
    ctx.lineTo(x + i + stripe + h, y);
    ctx.lineTo(x + i + h, y);
    ctx.closePath();
    ctx.fill();
  }
  if (rng) {
    // Worn paint shows the material underneath.
    for (let i = 0; i < w * h * wear * 0.02; i++) {
      ctx.fillStyle = css(scaleColor(pal.metal, rng.range(0.7, 1.1)), 0.8);
      ctx.fillRect(x + rng.next() * w, y + rng.next() * h, rng.range(1, 4), rng.range(1, 3));
    }
  }
  ctx.restore();
}

export function floorTextures(pal: EnvPalette, kind: FloorKind, seed: number): FloorTextures {
  const [c, ctx] = canvas(FLOOR_PX);
  const rng = new Rng(seed ^ hashString(kind));
  const S = FLOOR_PX;
  const metal = pal.floorFinish === 'metal' || (pal.floorFinish === 'mixed' && (kind === 'alt' || kind === 'rune'));
  let emissive: HTMLCanvasElement | undefined;

  switch (kind) {
    case 'solid':
      if (metal) paintMetalPlate(ctx, rng, pal, pal.floor, 'panel');
      else paintStoneSlabs(ctx, rng, pal, pal.floor, 'quad');
      break;
    case 'alt':
      if (metal) paintMetalPlate(ctx, rng, pal, pal.floorAlt, 'tread');
      else paintStoneSlabs(ctx, rng, pal, pal.floorAlt, 'brick');
      break;
    case 'cracked':
      if (metal) {
        paintMetalPlate(ctx, rng, pal, scaleColor(pal.floor, 0.94), 'panel');
        hazardBand(ctx, pal, 0, S * 0.68, S, S * 0.2, 10, 0.5, rng);
        for (let i = 0; i < 6; i++) {
          ctx.fillStyle = css(pal.rust, rng.range(0.4, 0.8));
          ctx.beginPath();
          ctx.ellipse(rng.range(10, S - 10), rng.range(10, S - 10), rng.range(3, 9), rng.range(2, 5), rng.range(0, 3), 0, Math.PI * 2);
          ctx.fill();
        }
      } else {
        paintStoneSlabs(ctx, rng, pal, scaleColor(pal.floor, 0.96), 'quad');
      }
      for (let i = 0; i < 2; i++) crackPath(ctx, rng, rng.range(20, S - 20), rng.range(20, S - 20), rng.range(40, 70), css(scaleColor(pal.grout, 0.8)), 2.2);
      break;
    case 'grate': {
      ctx.fillStyle = css(scaleColor(pal.grout, 0.55));
      ctx.fillRect(0, 0, S, S);
      bevelRect(ctx, 0, 0, S, S, pal.metal, 4);
      ctx.fillStyle = css(scaleColor(pal.grout, 0.45));
      ctx.fillRect(12, 12, S - 24, S - 24);
      const n = 7;
      const step = (S - 24) / n;
      for (let i = 1; i < n; i++) {
        const p = 12 + i * step;
        ctx.fillStyle = css(pal.metal);
        ctx.fillRect(p - 2, 12, 4, S - 24);
        ctx.fillRect(12, p - 2, S - 24, 4);
        ctx.fillStyle = css(scaleColor(pal.metal, 1.3));
        ctx.fillRect(p - 2, 12, 1, S - 24);
        ctx.fillRect(12, p - 2, S - 24, 1);
      }
      for (const [x, y] of [
        [6, 6],
        [S - 6, 6],
        [6, S - 6],
        [S - 6, S - 6],
      ])
        rivet(ctx, x, y, 2.4, pal.metal);
      if (pal.floorFinish !== 'stone') {
        // Lower grates glow faintly from the machinery below (R04).
        const [e, ectx] = canvas(S);
        ectx.fillStyle = '#000';
        ectx.fillRect(0, 0, S, S);
        const grd = ectx.createRadialGradient(S / 2, S / 2, 4, S / 2, S / 2, S * 0.5);
        grd.addColorStop(0, 'rgba(255,255,255,0.55)');
        grd.addColorStop(1, 'rgba(255,255,255,0)');
        ectx.fillStyle = grd;
        ectx.fillRect(12, 12, S - 24, S - 24);
        ectx.fillStyle = '#000';
        for (let i = 1; i < n; i++) {
          const p = 12 + i * step;
          ectx.fillRect(p - 2, 12, 4, S - 24);
          ectx.fillRect(12, p - 2, S - 24, 4);
        }
        emissive = e;
      }
      break;
    }
    case 'overgrown': {
      if (metal) paintMetalPlate(ctx, rng, pal, scaleColor(pal.floor, 0.92), 'panel');
      else paintStoneSlabs(ctx, rng, pal, scaleColor(pal.floor, 0.95), 'quad');
      const dark = scaleColor(pal.foliage, 0.62);
      for (let i = 0; i < 14; i++) {
        const x = rng.chance(0.6) ? (rng.chance(0.5) ? rng.range(0, 30) : rng.range(S - 30, S)) : rng.range(0, S);
        const y = rng.range(0, S);
        const r = rng.range(6, 18);
        ctx.fillStyle = css(dark);
        ctx.beginPath();
        ctx.ellipse(x + 2, y + 2, r, r * 0.7, rng.range(0, 3), 0, Math.PI * 2);
        ctx.fill();
        ctx.fillStyle = css(scaleColor(pal.foliage, rng.range(0.85, 1.1)));
        ctx.beginPath();
        ctx.ellipse(x, y, r * 0.85, r * 0.6, rng.range(0, 3), 0, Math.PI * 2);
        ctx.fill();
      }
      for (let i = 0; i < 26; i++) {
        ctx.fillStyle = css(scaleColor(pal.foliage, 1.3));
        const x = rng.range(0, S);
        const y = rng.range(0, S);
        ctx.beginPath();
        ctx.ellipse(x, y, 3, 1.4, rng.range(0, 3), 0, Math.PI * 2);
        ctx.fill();
      }
      break;
    }
    case 'rune': {
      if (metal) paintMetalPlate(ctx, rng, pal, scaleColor(pal.floor, 0.9), 'panel');
      else paintStoneSlabs(ctx, rng, pal, scaleColor(pal.floor, 0.97), 'quad');
      const glyphSeed = rng.int(0, 1 << 30);
      // Carved channel in the colour map...
      drawGlyph(ctx, new Rng(glyphSeed), S / 2, S / 2, S * 0.3, css(scaleColor(pal.grout, 0.7)), 7);
      // ...and the light living inside it in the emissive map.
      const [e, ectx] = canvas(S);
      ectx.fillStyle = '#000';
      ectx.fillRect(0, 0, S, S);
      ectx.shadowColor = '#fff';
      ectx.shadowBlur = 6;
      drawGlyph(ectx, new Rng(glyphSeed), S / 2, S / 2, S * 0.3, '#ffffff', 3.2);
      emissive = e;
      break;
    }
  }

  const map = colorTexture(c);
  const out: FloorTextures = { map };
  if (emissive) out.emissiveMap = colorTexture(emissive);
  return out;
}

// ───────────────────────────── walls ─────────────────────────────

export interface WallTextures {
  side: THREE.CanvasTexture;
  sideEmissive?: THREE.CanvasTexture;
  top: THREE.CanvasTexture;
  cutTop: THREE.CanvasTexture;
}

/**
 * Wall side / top textures. `inscribed` walls carry etched glyph channels (lit on metal finishes,
 * carved on stone); plain walls do not, so inscriptions read as deliberate rather than wallpaper.
 */
export function wallTextures(pal: EnvPalette, seed: number, inscribed: boolean): WallTextures {
  const S = 128;
  const rng = new Rng(seed ^ (inscribed ? 0x3a11 : 0x7c02));
  const [c, ctx] = canvas(S);
  let emissive: HTMLCanvasElement | undefined;
  if (pal.floorFinish === 'metal') {
    ctx.fillStyle = css(pal.grout);
    ctx.fillRect(0, 0, S, S);
    // Two tall panels per unit with a horizontal seam: heavy inscribed plating (R04).
    for (const x of [0, S / 2]) {
      for (const y of [0, S / 2]) bevelRect(ctx, x + 1, y + 1, S / 2 - 2, S / 2 - 2, scaleColor(pal.wall, rng.range(0.92, 1.08)), 3);
    }
    for (const [x, y] of [
      [6, 6],
      [S / 2 - 6, 6],
      [S / 2 + 6, S / 2 + 6],
      [S - 6, S - 6],
      [6, S - 6],
      [S - 6, 6],
    ])
      rivet(ctx, x, y, 2.2, pal.wall);
    if (inscribed) {
    const [e, ectx] = canvas(S);
    ectx.fillStyle = '#000';
    ectx.fillRect(0, 0, S, S);
    // Etched channels: carved dark in colour, faintly lit in emissive.
    const gs = rng.int(0, 1 << 30);
    drawGlyph(ctx, new Rng(gs), S * 0.25, S * 0.27, 14, css(scaleColor(pal.grout, 0.6)), 3);
    ectx.shadowColor = '#fff';
    ectx.shadowBlur = 4;
    drawGlyph(ectx, new Rng(gs), S * 0.25, S * 0.27, 14, 'rgba(255,255,255,0.9)', 1.6);
    ctx.strokeStyle = css(scaleColor(pal.grout, 0.6));
    ctx.lineWidth = 3;
    ctx.beginPath();
    ctx.moveTo(S * 0.75, S * 0.56);
    ctx.lineTo(S * 0.75, S * 0.8);
    ctx.lineTo(S * 0.88, S * 0.92);
    ctx.stroke();
    ectx.strokeStyle = 'rgba(255,255,255,0.8)';
    ectx.lineWidth = 1.4;
    ectx.beginPath();
    ectx.moveTo(S * 0.75, S * 0.56);
    ectx.lineTo(S * 0.75, S * 0.8);
    ectx.lineTo(S * 0.88, S * 0.92);
    ectx.stroke();
    emissive = e;
    } else {
      // Plain plating: a recessed vent strip and bolts instead of glyphs.
      ctx.fillStyle = css(scaleColor(pal.wall, 0.6));
      for (let i = 0; i < 4; i++) ctx.fillRect(S * 0.6, S * 0.1 + i * 7, S * 0.3, 3);
    }
    speckle(ctx, rng, 0, 0, S, S, pal.wall, 60, 0.12);
  } else {
    // Masonry courses (R03 cracked masonry), four per unit of height.
    ctx.fillStyle = css(pal.grout);
    ctx.fillRect(0, 0, S, S);
    const rows = 4;
    const rh = S / rows;
    for (let r = 0; r < rows; r++) {
      const off = r % 2 ? S / 4 : 0;
      for (let x = -S / 2 + off; x < S; x += S / 2) {
        bevelRect(ctx, x + 2, r * rh + 2, S / 2 - 4, rh - 4, scaleColor(pal.wall, rng.range(0.86, 1.08)), 3, rng);
      }
    }
    if (pal.floorFinish === 'mixed') {
      // Retrofitted metal band bolted across older stone (WORLD-01 layered history).
      bevelRect(ctx, 0, S * 0.44, S, S * 0.12, pal.metal, 2);
      for (let x = 8; x < S; x += 24) rivet(ctx, x, S * 0.5, 2, pal.metal);
    }
    crackPath(ctx, rng, rng.range(10, S - 10), rng.range(10, S - 10), 40, css(scaleColor(pal.grout, 0.75)), 1.6);
    if (inscribed) {
      // Weathered variant: deeper cracks and a moss streak running down from the cap.
      crackPath(ctx, rng, rng.range(20, S - 20), rng.range(10, 40), 60, css(scaleColor(pal.grout, 0.7)), 2.2);
      const x = rng.range(20, S - 20);
      ctx.fillStyle = css(scaleColor(pal.foliage, 0.75), 0.75);
      for (let y = 0; y < S * 0.45; y += 3) ctx.fillRect(x + Math.sin(y * 0.2) * 3 - 3, y, rng.range(4, 9) * (1 - y / (S * 0.5)), 3);
    }
    speckle(ctx, rng, 0, 0, S, S, pal.wall, 80, 0.15);
  }

  const [tc, tctx] = canvas(S);
  if (pal.floorFinish === 'metal') {
    paintMetalPlate(tctx, rng, pal, pal.wallTop, 'panel');
  } else {
    paintStoneSlabs(tctx, rng, pal, pal.wallTop, 'quad');
  }

  // Cut walls show a darker section so they read as walls sliced for view, not as floor.
  const [cc, cctx] = canvas(S);
  bevelRect(cctx, 0, 0, S, S, scaleColor(pal.wallTop, 0.82), 6);
  cctx.strokeStyle = css(scaleColor(pal.wallTop, 0.66));
  cctx.lineWidth = 3;
  for (let i = -S; i < S * 2; i += 18) {
    cctx.beginPath();
    cctx.moveTo(i, S);
    cctx.lineTo(i + S, 0);
    cctx.stroke();
  }

  const out: WallTextures = { side: colorTexture(c), top: colorTexture(tc), cutTop: colorTexture(cc) };
  if (emissive) out.sideEmissive = colorTexture(emissive);
  return out;
}

/** Rough stratified rock for the cliff skirt (lightness only; tinted by vertex colour). */
export function cliffTexture(seed: number): THREE.CanvasTexture {
  const S = 128;
  const rng = new Rng(seed ^ 0xc11f);
  const [c, ctx] = canvas(S);
  ctx.fillStyle = '#b9b9b9';
  ctx.fillRect(0, 0, S, S);
  let y = 0;
  while (y < S) {
    const h = rng.range(14, 30);
    let x = -rng.range(0, 30);
    while (x < S) {
      const w = rng.range(24, 56);
      const v = Math.round(rng.range(165, 225));
      ctx.fillStyle = `rgb(${v},${v},${v})`;
      ctx.fillRect(x + 2, y + 2, w - 4, h - 4);
      ctx.fillStyle = `rgb(${Math.min(255, v + 30)},${Math.min(255, v + 30)},${Math.min(255, v + 30)})`;
      ctx.fillRect(x + 2, y + 2, w - 4, 2);
      ctx.fillStyle = 'rgb(110,110,110)';
      ctx.fillRect(x + 2, y + h - 4, w - 4, 2);
      x += w;
    }
    y += h;
  }
  return colorTexture(c);
}

/** Yellow / black hazard stripes on a strip texture (repeat along U). */
export function hazardTexture(pal: EnvPalette, seed: number): THREE.CanvasTexture {
  const [c, ctx] = canvas(128, 32);
  hazardBand(ctx, pal, 0, 0, 128, 32, 16, 0.35, new Rng(seed ^ 0x4a2));
  return colorTexture(c);
}

// ───────────────────────────── decals & props ─────────────────────────────

const SYMBOLS = ['smiley', 'star', 'cassette', 'crown', 'heart', 'arrow', 'bolt'] as const;

/** Spray drip under a stroke. */
function drip(ctx: Ctx, rng: Rng, x: number, y: number, color: string, w: number): void {
  const len = rng.range(8, 30);
  ctx.strokeStyle = color;
  ctx.lineWidth = w;
  ctx.lineCap = 'round';
  ctx.beginPath();
  ctx.moveTo(x, y);
  ctx.lineTo(x + rng.range(-1, 1), y + len);
  ctx.stroke();
  ctx.fillStyle = color;
  ctx.beginPath();
  ctx.arc(x, y + len, w * 0.8, 0, Math.PI * 2);
  ctx.fill();
}

function overspray(ctx: Ctx, rng: Rng, color: string, cx: number, cy: number, r: number, n: number): void {
  ctx.fillStyle = color;
  for (let i = 0; i < n; i++) {
    const a = rng.range(0, Math.PI * 2);
    const d = r * Math.sqrt(rng.next());
    ctx.globalAlpha = rng.range(0.2, 0.7);
    ctx.fillRect(cx + Math.cos(a) * d, cy + Math.sin(a) * d, 1.5, 1.5);
  }
  ctx.globalAlpha = 1;
}

/**
 * Spray-paint tag or symbol (ART-03: recent, playful human intervention over older inscriptions).
 * `variant`: a symbol name (smiley, star, cassette, crown, heart, arrow, bolt), "text:WORD" or any
 * other word (sprayed as letters). Empty → a seeded symbol.
 */
export function graffitiTexture(variant: string | undefined, color: number, outline: number, seed: number): THREE.CanvasTexture {
  const S = 256;
  const [c, ctx] = canvas(S);
  const rng = new Rng(seed);
  ctx.clearRect(0, 0, S, S);
  const col = css(color);
  const dark = css(outline);
  let v = (variant ?? '').trim();
  if (v === '') v = SYMBOLS[rng.int(0, SYMBOLS.length - 1)];
  const isSymbol = (SYMBOLS as readonly string[]).includes(v.toLowerCase());
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  ctx.translate(S / 2, S / 2);
  ctx.rotate(rng.range(-0.18, 0.18));
  ctx.translate(-S / 2, -S / 2);
  overspray(ctx, rng, col, S / 2, S / 2, S * 0.42, 500);

  const strokeBoth = (w: number, path: () => void) => {
    ctx.strokeStyle = dark;
    ctx.lineWidth = w + 6;
    ctx.beginPath();
    path();
    ctx.stroke();
    ctx.strokeStyle = col;
    ctx.lineWidth = w;
    ctx.beginPath();
    path();
    ctx.stroke();
  };

  if (isSymbol) {
    const k = v.toLowerCase();
    const cx = S / 2;
    const cy = S / 2 - 8;
    if (k === 'smiley') {
      // The board's dripping X-eyed smiley.
      strokeBoth(12, () => ctx.arc(cx, cy, 78, 0, Math.PI * 2));
      strokeBoth(9, () => {
        for (const ex of [-28, 28]) {
          ctx.moveTo(cx + ex - 13, cy - 30);
          ctx.lineTo(cx + ex + 13, cy - 4);
          ctx.moveTo(cx + ex + 13, cy - 30);
          ctx.lineTo(cx + ex - 13, cy - 4);
        }
      });
      strokeBoth(9, () => {
        ctx.moveTo(cx - 40, cy + 22);
        ctx.quadraticCurveTo(cx, cy + 62, cx + 40, cy + 22);
      });
    } else if (k === 'star') {
      strokeBoth(11, () => {
        for (let i = 0; i <= 5; i++) {
          const a = -Math.PI / 2 + ((i * 2) % 5) * ((Math.PI * 2) / 5);
          const x = cx + Math.cos(a) * 80;
          const y = cy + Math.sin(a) * 80;
          if (i === 0) ctx.moveTo(x, y);
          else ctx.lineTo(x, y);
        }
      });
    } else if (k === 'cassette') {
      strokeBoth(9, () => {
        ctx.rect(cx - 82, cy - 50, 164, 100);
        ctx.rect(cx - 52, cy - 26, 104, 34);
      });
      strokeBoth(8, () => {
        ctx.moveTo(cx - 22 + 12, cy - 9);
        ctx.arc(cx - 22, cy - 9, 12, 0, Math.PI * 2);
        ctx.moveTo(cx + 22 + 12, cy - 9);
        ctx.arc(cx + 22, cy - 9, 12, 0, Math.PI * 2);
        ctx.moveTo(cx - 40, cy + 50);
        ctx.lineTo(cx - 30, cy + 28);
        ctx.lineTo(cx + 30, cy + 28);
        ctx.lineTo(cx + 40, cy + 50);
      });
    } else if (k === 'crown') {
      strokeBoth(10, () => {
        ctx.moveTo(cx - 70, cy + 40);
        ctx.lineTo(cx - 80, cy - 40);
        ctx.lineTo(cx - 35, cy);
        ctx.lineTo(cx, cy - 60);
        ctx.lineTo(cx + 35, cy);
        ctx.lineTo(cx + 80, cy - 40);
        ctx.lineTo(cx + 70, cy + 40);
        ctx.closePath();
      });
    } else if (k === 'heart') {
      strokeBoth(11, () => {
        ctx.moveTo(cx, cy + 60);
        ctx.bezierCurveTo(cx - 100, cy - 10, cx - 50, cy - 80, cx, cy - 30);
        ctx.bezierCurveTo(cx + 50, cy - 80, cx + 100, cy - 10, cx, cy + 60);
      });
    } else if (k === 'arrow') {
      strokeBoth(12, () => {
        ctx.moveTo(cx - 80, cy + 30);
        ctx.quadraticCurveTo(cx - 10, cy - 50, cx + 60, cy - 10);
        ctx.moveTo(cx + 30, cy - 40);
        ctx.lineTo(cx + 64, cy - 8);
        ctx.lineTo(cx + 24, cy + 14);
      });
    } else {
      strokeBoth(11, () => {
        ctx.moveTo(cx + 20, cy - 80);
        ctx.lineTo(cx - 35, cy + 5);
        ctx.lineTo(cx + 10, cy + 5);
        ctx.lineTo(cx - 20, cy + 80);
        ctx.lineTo(cx + 45, cy - 15);
        ctx.lineTo(cx, cy - 15);
        ctx.closePath();
      });
    }
    for (let i = 0; i < 5; i++) drip(ctx, rng, S / 2 + rng.range(-70, 70), S / 2 + rng.range(30, 70), col, rng.range(3, 6));
  } else {
    const text = (v.startsWith('text:') ? v.slice(5) : v).toUpperCase().slice(0, 10);
    const size = Math.min(110, Math.floor(380 / Math.max(3, text.length)));
    ctx.font = `italic 900 ${size}px Impact, "Arial Black", "Segoe UI", sans-serif`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.lineWidth = 10;
    ctx.strokeStyle = dark;
    ctx.save();
    ctx.translate(S / 2, S / 2);
    ctx.transform(1, 0, -0.18, 1, 0, 0);
    ctx.strokeText(text, 0, 0);
    ctx.fillStyle = col;
    ctx.fillText(text, 0, 0);
    ctx.lineWidth = 2;
    ctx.strokeStyle = 'rgba(255,255,255,0.65)';
    ctx.strokeText(text, -2, -3);
    ctx.restore();
    for (let i = 0; i < 6; i++) drip(ctx, rng, S / 2 + rng.range(-size * 1.4, size * 1.4), S / 2 + size * 0.35, col, rng.range(2.5, 5));
    // A little star flourish, as on the board's title.
    ctx.strokeStyle = col;
    ctx.lineWidth = 4;
    ctx.beginPath();
    const sx = S / 2 + Math.min(110, text.length * size * 0.32);
    const sy = S / 2 - size * 0.6;
    for (let i = 0; i <= 5; i++) {
      const a = -Math.PI / 2 + ((i * 2) % 5) * ((Math.PI * 2) / 5);
      const x = sx + Math.cos(a) * 16;
      const y = sy + Math.sin(a) * 16;
      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    }
    ctx.stroke();
  }
  const tex = colorTexture(c, false);
  tex.premultiplyAlpha = false;
  return tex;
}

/** Emissive rune panel face: glyph strokes on black. */
export function runePanelTexture(seed: number, glyphs = 3): THREE.CanvasTexture {
  const [c, ctx] = canvas(64, 192);
  const rng = new Rng(seed);
  ctx.fillStyle = '#000';
  ctx.fillRect(0, 0, 64, 192);
  ctx.shadowColor = '#fff';
  ctx.shadowBlur = 6;
  for (let i = 0; i < glyphs; i++) drawGlyph(ctx, rng, 32, 32 + i * 64, 20, '#fff', 3);
  ctx.strokeStyle = '#fff';
  ctx.lineWidth = 2;
  ctx.strokeRect(4, 4, 56, 184);
  return colorTexture(c, false);
}

/** Screen face: waveform trace on a dark grid (scrolls by texture offset). */
export function screenTexture(color: number, seed: number, kind: 'wave' | 'console'): THREE.CanvasTexture {
  const W = 256;
  const H = 128;
  const [c, ctx] = canvas(W, H);
  const rng = new Rng(seed);
  ctx.fillStyle = css(scaleColor(color, 0.12));
  ctx.fillRect(0, 0, W, H);
  ctx.strokeStyle = css(scaleColor(color, 0.35));
  ctx.lineWidth = 1;
  for (let x = 0; x <= W; x += 32) {
    ctx.beginPath();
    ctx.moveTo(x + 0.5, 0);
    ctx.lineTo(x + 0.5, H);
    ctx.stroke();
  }
  for (let y = 0; y <= H; y += 32) {
    ctx.beginPath();
    ctx.moveTo(0, y + 0.5);
    ctx.lineTo(W, y + 0.5);
    ctx.stroke();
  }
  ctx.strokeStyle = css(mixColor(color, 0xffffff, 0.35));
  ctx.lineWidth = 3;
  ctx.shadowColor = css(color);
  ctx.shadowBlur = 8;
  ctx.beginPath();
  // Periodic across the width so the scroll wraps seamlessly.
  const f1 = rng.int(2, 4);
  const f2 = rng.int(5, 9);
  for (let x = 0; x <= W; x += 2) {
    const t = (x / W) * Math.PI * 2;
    const y = H / 2 + Math.sin(t * f1) * H * 0.22 + Math.sin(t * f2 + 1) * H * 0.1 * (kind === 'wave' ? 1 : 0.5);
    if (x === 0) ctx.moveTo(x, y);
    else ctx.lineTo(x, y);
  }
  ctx.stroke();
  if (kind === 'console') {
    ctx.shadowBlur = 0;
    ctx.fillStyle = css(mixColor(color, 0xffffff, 0.2));
    for (let i = 0; i < 5; i++) ctx.fillRect(10, 10 + i * 9, rng.range(20, 70), 4);
  }
  const t = colorTexture(c);
  t.wrapT = THREE.ClampToEdgeWrapping;
  return t;
}

/** Crate side: painted metal with frame, straps and stencilled star (R03 prop library). */
export function crateTexture(pal: EnvPalette, base: number, seed: number): THREE.CanvasTexture {
  const S = 128;
  const [c, ctx] = canvas(S);
  const rng = new Rng(seed);
  bevelRect(ctx, 0, 0, S, S, base, 6);
  ctx.strokeStyle = css(scaleColor(base, 0.62));
  ctx.lineWidth = 4;
  ctx.strokeRect(12, 12, S - 24, S - 24);
  ctx.fillStyle = css(pal.trim);
  ctx.fillRect(S * 0.3, 0, 10, S);
  ctx.fillRect(S * 0.62, 0, 10, S);
  ctx.strokeStyle = css(scaleColor(base, 0.55));
  ctx.lineWidth = 5;
  ctx.beginPath();
  for (let i = 0; i <= 5; i++) {
    const a = -Math.PI / 2 + ((i * 2) % 5) * ((Math.PI * 2) / 5);
    const x = S / 2 + Math.cos(a) * 22;
    const y = S / 2 + Math.sin(a) * 22;
    if (i === 0) ctx.moveTo(x, y);
    else ctx.lineTo(x, y);
  }
  ctx.stroke();
  for (let i = 0; i < 8; i++) {
    ctx.fillStyle = css(pal.rust, rng.range(0.3, 0.7));
    ctx.fillRect(rng.range(0, S), rng.range(0, S), rng.range(3, 10), rng.range(2, 5));
  }
  for (const [x, y] of [
    [8, 8],
    [S - 8, 8],
    [8, S - 8],
    [S - 8, S - 8],
  ])
    rivet(ctx, x, y, 3, base);
  return colorTexture(c);
}

/** Dashed guide line (laser off state). */
export function dashTexture(): THREE.CanvasTexture {
  const [c, ctx] = canvas(64, 8);
  ctx.clearRect(0, 0, 64, 8);
  ctx.fillStyle = '#fff';
  ctx.fillRect(0, 2, 30, 4);
  return colorTexture(c);
}

/** Crack pattern for breakable walls: colour (dark seams) and emissive (glowing seams). */
export function crackTextures(pal: EnvPalette, seed: number): { map: THREE.CanvasTexture; emissiveMap: THREE.CanvasTexture } {
  const S = 128;
  const rng = new Rng(seed);
  const [c, ctx] = canvas(S);
  const [e, ectx] = canvas(S);
  const base = mixColor(pal.wall, pal.rust, 0.18);
  ctx.fillStyle = css(pal.grout);
  ctx.fillRect(0, 0, S, S);
  // Loose, uneven blocks: visibly different from the tidy courses of solid walls.
  for (let r = 0; r < 3; r++) {
    let x = -rng.range(0, 30);
    while (x < S) {
      const w = rng.range(30, 54);
      bevelRect(ctx, x + 3, r * (S / 3) + 3, w - 6, S / 3 - 6, scaleColor(base, rng.range(0.82, 1.05)), 3, rng);
      x += w;
    }
  }
  ectx.fillStyle = '#000';
  ectx.fillRect(0, 0, S, S);
  const seams: [number, number, number][] = [];
  for (let i = 0; i < 3; i++) seams.push([rng.range(20, S - 20), rng.range(20, S - 20), rng.range(50, 80)]);
  for (const [x, y, l] of seams) {
    const s = rng.int(0, 1 << 30);
    crackPath(ctx, new Rng(s), x, y, l, css(scaleColor(pal.grout, 0.5)), 4);
    ectx.shadowColor = '#fff';
    ectx.shadowBlur = 6;
    crackPath(ectx, new Rng(s), x, y, l, '#fff', 2);
  }
  return { map: colorTexture(c), emissiveMap: colorTexture(e) };
}

/** Vertical background gradient: lighter haze behind the diorama, dark at the edges. */
export function backgroundTexture(pal: EnvPalette): THREE.CanvasTexture {
  const [c, ctx] = canvas(256);
  const g = ctx.createRadialGradient(128, 110, 10, 128, 128, 190);
  g.addColorStop(0, css(mixColor(pal.background, pal.floorFinish === 'stone' ? pal.warm : pal.neonC, 0.18)));
  g.addColorStop(0.55, css(pal.background));
  g.addColorStop(1, css(scaleColor(pal.background, 0.55)));
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, 256, 256);
  const t = colorTexture(c, false);
  return t;
}

/** Soft round blob (glows, contact shadows, motes). */
export function blobTexture(): THREE.CanvasTexture {
  const [c, ctx] = canvas(64);
  const g = ctx.createRadialGradient(32, 32, 0, 32, 32, 32);
  g.addColorStop(0, 'rgba(255,255,255,1)');
  g.addColorStop(0.4, 'rgba(255,255,255,0.55)');
  g.addColorStop(1, 'rgba(255,255,255,0)');
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, 64, 64);
  return colorTexture(c, false);
}

/** Exit marking: chevrons and a border. */
export function exitTexture(): THREE.CanvasTexture {
  const S = 128;
  const [c, ctx] = canvas(S);
  ctx.clearRect(0, 0, S, S);
  ctx.strokeStyle = '#fff';
  ctx.lineWidth = 6;
  ctx.strokeRect(6, 6, S - 12, S - 12);
  ctx.lineWidth = 7;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  for (let i = 0; i < 3; i++) {
    const y = 34 + i * 26;
    ctx.globalAlpha = 0.45 + i * 0.25;
    ctx.beginPath();
    ctx.moveTo(36, y + 12);
    ctx.lineTo(64, y - 6);
    ctx.lineTo(92, y + 12);
    ctx.stroke();
  }
  ctx.globalAlpha = 1;
  return colorTexture(c);
}

/** Leafy vine strip with transparent background. */
export function vineTexture(pal: EnvPalette, seed: number): THREE.CanvasTexture {
  const W = 64;
  const H = 256;
  const [c, ctx] = canvas(W, H);
  const rng = new Rng(seed);
  ctx.clearRect(0, 0, W, H);
  for (let s = 0; s < 3; s++) {
    let x = rng.range(14, W - 14);
    ctx.strokeStyle = css(scaleColor(pal.foliage, 0.5));
    ctx.lineWidth = 2.5;
    ctx.beginPath();
    ctx.moveTo(x, 0);
    const len = rng.range(H * 0.5, H);
    for (let y = 0; y < len; y += 8) {
      x += rng.range(-3, 3);
      x = Math.max(6, Math.min(W - 6, x));
      ctx.lineTo(x, y);
      if (rng.chance(0.55)) {
        const side = rng.chance(0.5) ? -1 : 1;
        ctx.save();
        ctx.fillStyle = css(scaleColor(pal.foliage, rng.range(0.75, 1.2)));
        ctx.strokeStyle = css(scaleColor(pal.foliage, 0.45));
        ctx.lineWidth = 1.5;
        ctx.beginPath();
        ctx.ellipse(x + side * 7, y + 2, 7, 3.6, side * 0.6, 0, Math.PI * 2);
        ctx.fill();
        ctx.stroke();
        ctx.restore();
      }
    }
    ctx.stroke();
  }
  return colorTexture(c, false);
}
