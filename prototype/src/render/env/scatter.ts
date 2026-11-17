/**
 * Ambient dressing so a level never looks bare (chapter 19: cracked masonry, cables, vents,
 * vegetation growing through seams). Seeded by the level id, never Math.random, so every view of
 * a level (record, review, cinematic) is identical.
 *
 * Readability rule: ambient dressing never stands on the walkable floor as something that could be
 * mistaken for an obstacle. Floor items are flat (tufts, pebbles, stains); anything bulky goes on
 * wall faces, wall tops or the cliff skirt.
 */
import type { LevelDef } from '../../core/types';
import { paletteFor } from '../palettes';
import { type LevelLayout, isFloorChar } from './layout';
import { Rng } from './rng';

export type ScatterKind =
  | 'tuft'
  | 'pebbles'
  | 'stain'
  | 'floorPaint'
  | 'wallVine'
  | 'wallPipe'
  | 'wallNeon'
  | 'wallVent'
  | 'wallCable'
  | 'topGrass'
  | 'topRubble'
  | 'cliffRoot'
  | 'cliffRock';

export interface ScatterItem {
  kind: ScatterKind;
  /** Floor items: exact position. Wall / cliff items: centre of the owning tile. */
  x: number;
  y: number;
  /** Wall / cliff face the item hangs on ('e' = +X face, 's' = +Z face; the camera-facing sides). */
  face?: 'e' | 's';
  /** 0..1 variant / scale parameters. */
  v: number;
  s: number;
}

/** Tiles that entities occupy or stand on; ambient dressing keeps off them. */
export function occupiedTiles(level: Pick<LevelDef, 'entities' | 'start'>): Set<string> {
  const out = new Set<string>();
  const add = (c: number, r: number) => out.add(`${Math.floor(c)},${Math.floor(r)}`);
  add(level.start.x, level.start.y);
  for (const e of level.entities) {
    switch (e.kind) {
      case 'enemy':
      case 'switch':
      case 'core':
      case 'decor':
        add(e.x, e.y);
        break;
      case 'door':
        for (const cell of e.cells) add(cell.c, cell.r);
        break;
      case 'plate':
      case 'breakable':
        add(e.c, e.r);
        break;
      case 'exit':
        for (let dr = 0; dr < e.h; dr++) for (let dc = 0; dc < e.w; dc++) add(e.c + dc, e.r + dr);
        break;
      case 'laser': {
        // Keep the beam corridor clean so the hazard reads.
        const steps = Math.ceil(Math.hypot(e.to.x - e.from.x, e.to.y - e.from.y) * 2) + 1;
        for (let i = 0; i <= steps; i++) {
          const t = i / steps;
          add(e.from.x + (e.to.x - e.from.x) * t, e.from.y + (e.to.y - e.from.y) * t);
        }
        break;
      }
    }
  }
  return out;
}

export function planScatter(level: Pick<LevelDef, 'id' | 'theme' | 'entities' | 'start'>, layout: LevelLayout): ScatterItem[] {
  const pal = paletteFor(level.theme);
  const rng = new Rng(layout.seed ^ 0x5ca77e5);
  const busy = occupiedTiles(level);
  const out: ScatterItem[] = [];
  const green = pal.overgrowth;
  const tech = pal.floorFinish === 'stone' ? 0.25 : pal.floorFinish === 'mixed' ? 0.6 : 1;

  for (const f of layout.floors) {
    const key = `${f.c},${f.r}`;
    const ch = layout.at(f.c, f.r);
    if (busy.has(key) || ch === '=') continue;
    const nearWall = layout.at(f.c - 1, f.r) === '#' || layout.at(f.c, f.r - 1) === '#';
    const overgrown = ch === ',';
    const tuftChance = overgrown ? 0.85 : (nearWall ? 0.35 : 0.08) * green * 3;
    if (rng.chance(Math.min(0.9, tuftChance))) {
      const n = overgrown ? rng.int(2, 4) : 1;
      for (let i = 0; i < n; i++) {
        // Hug the back edges of the tile so the playable centre stays clear.
        const x = f.c + (nearWall && layout.at(f.c - 1, f.r) === '#' ? rng.range(0.08, 0.3) : rng.range(0.1, 0.9));
        const y = f.r + (nearWall && layout.at(f.c, f.r - 1) === '#' ? rng.range(0.08, 0.3) : rng.range(0.1, 0.9));
        out.push({ kind: 'tuft', x, y, v: rng.next(), s: rng.range(0.6, 1.1) });
      }
    }
    if (rng.chance(nearWall ? 0.22 : 0.05)) {
      out.push({ kind: 'pebbles', x: f.c + rng.range(0.15, 0.85), y: f.r + rng.range(0.15, 0.85), v: rng.next(), s: rng.range(0.6, 1) });
    }
    // Worn hazard paint across a tile (both reference tile sets carry painted markings).
    if (ch !== ',' && rng.chance(0.045)) {
      out.push({ kind: 'floorPaint', x: f.c + 0.5, y: f.r + 0.5, v: rng.next(), s: rng.range(0.7, 1) });
    }
    if (rng.chance(0.06 * (0.5 + tech))) {
      out.push({ kind: 'stain', x: f.c + rng.range(0.3, 0.7), y: f.r + rng.range(0.3, 0.7), v: rng.next(), s: rng.range(0.5, 1) });
    }
  }

  for (const w of layout.walls) {
    if (w.cut) continue;
    const faces: ('e' | 's')[] = [];
    if (isFloorChar(layout.at(w.c + 1, w.r)) || layout.at(w.c + 1, w.r) === '=') faces.push('e');
    if (isFloorChar(layout.at(w.c, w.r + 1)) || layout.at(w.c, w.r + 1) === '=') faces.push('s');
    for (const face of faces) {
      const roll = rng.next();
      if (roll < 0.28 * green * 3) out.push({ kind: 'wallVine', x: w.c + 0.5, y: w.r + 0.5, face, v: rng.next(), s: rng.range(0.5, 1) });
      else if (roll < 0.28 * green * 3 + 0.16 * tech) out.push({ kind: 'wallNeon', x: w.c + 0.5, y: w.r + 0.5, face, v: rng.next(), s: rng.range(0.6, 1) });
      else if (roll < 0.28 * green * 3 + 0.16 * tech + 0.12) out.push({ kind: 'wallPipe', x: w.c + 0.5, y: w.r + 0.5, face, v: rng.next(), s: rng.range(0.4, 0.8) });
      else if (roll < 0.28 * green * 3 + 0.16 * tech + 0.2) out.push({ kind: 'wallVent', x: w.c + 0.5, y: w.r + 0.5, face, v: rng.next(), s: rng.range(0.7, 1) });
      else if (roll < 0.28 * green * 3 + 0.16 * tech + 0.27) out.push({ kind: 'wallCable', x: w.c + 0.5, y: w.r + 0.5, face, v: rng.next(), s: rng.range(0.5, 1) });
    }
    if (rng.chance(0.35 * (green * 3 + 0.2))) out.push({ kind: 'topGrass', x: w.c + 0.5, y: w.r + 0.5, v: rng.next(), s: rng.range(0.6, 1.1) });
    else if (rng.chance(pal.floorFinish === 'stone' ? 0.25 : 0.1)) out.push({ kind: 'topRubble', x: w.c + 0.5, y: w.r + 0.5, v: rng.next(), s: rng.range(0.6, 1) });
  }

  for (const cl of layout.cliffs) {
    const faces: ('e' | 's')[] = [];
    if (layout.at(cl.c + 1, cl.r) === ' ') faces.push('e');
    if (layout.at(cl.c, cl.r + 1) === ' ') faces.push('s');
    for (const face of faces) {
      if (rng.chance(0.3 * (green * 2 + 0.25))) out.push({ kind: 'cliffRoot', x: cl.c + 0.5, y: cl.r + 0.5, face, v: rng.next(), s: rng.range(0.5, 1) });
      if (rng.chance(0.3)) out.push({ kind: 'cliffRock', x: cl.c + 0.5, y: cl.r + 0.5, face, v: rng.next(), s: rng.range(0.5, 1) });
    }
  }
  return out;
}
