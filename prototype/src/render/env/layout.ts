/**
 * Pure level → placement layout. No Three.js objects here, so the counts and the cutaway rule can
 * be unit-tested in node; env/build.ts turns a layout into instanced meshes.
 *
 * Scene convention (layer.ts): tile (c, r) covers scene X in [c, c+1), Z in [r, r+1); floor top
 * at Y = 0. The camera sits on the +X / +Z side, so a tile's "front" neighbours are (c+1, r) and
 * (c, r+1) and its "behind" neighbours are (c-1, r), (c, r-1).
 */
import type { LevelDef, Theme } from '../../core/types';
import { hashString, tileNoise } from './rng';

export const TILE_THICK = 0.24;
/** Height of a wall cut away because it would hide the playfield behind it (chapter 16 cutaways). */
export const WALL_CUT_HEIGHT = 0.42;
export const BARRIER_HEIGHT = 0.55;

export type FloorKind = 'solid' | 'alt' | 'cracked' | 'grate' | 'overgrown' | 'rune';
export const FLOOR_KINDS: readonly FloorKind[] = ['solid', 'alt', 'cracked', 'grate', 'overgrown', 'rune'];

export type Side = 'n' | 'e' | 's' | 'w';

export interface FloorPlacement {
  c: number;
  r: number;
  kind: FloorKind;
  /** Quarter turns of the tile top, for variety. */
  rot: 0 | 1 | 2 | 3;
  /** 0..1 deterministic tone variation. */
  shade: number;
  /** 0..1 contact darkening from walls standing behind this tile. */
  ao: number;
}

export interface WallPlacement {
  c: number;
  r: number;
  height: number;
  /** True when the wall was cut low so it does not hide floor behind it. */
  cut: boolean;
  shade: number;
}

export interface BarrierPlacement {
  c: number;
  r: number;
  /** Which neighbours are barriers or walls (rails connect toward them). */
  n: boolean;
  e: boolean;
  s: boolean;
  w: boolean;
}

export interface CliffPlacement {
  c: number;
  r: number;
  /** Depth of the skirt below the tile underside. */
  depth: number;
  shade: number;
}

export interface EdgePlacement {
  c: number;
  r: number;
  side: Side;
  /** The tile is a wall block (gets skirt paint but no floor lip). */
  wall: boolean;
}

export interface LevelBounds {
  minX: number;
  minZ: number;
  maxX: number;
  maxZ: number;
  /** Tallest wall top. */
  maxY: number;
  /** Deepest cliff bottom (negative). */
  minY: number;
}

export interface LevelLayout {
  cols: number;
  rows: number;
  floors: FloorPlacement[];
  walls: WallPlacement[];
  barriers: BarrierPlacement[];
  cliffs: CliffPlacement[];
  edges: EdgePlacement[];
  bounds: LevelBounds;
  seed: number;
  /** Map character at (c, r); ' ' outside the map. */
  at(c: number, r: number): string;
  /** Wall height at (c, r), 0 when not a wall. */
  wallHeight(c: number, r: number): number;
}

const FLOOR_CHARS = new Set(['.', ':', ',', '~']);

export function isFloorChar(ch: string): boolean {
  return FLOOR_CHARS.has(ch);
}

/** Any tile that has ground under it (floor, wall or barrier). */
export function isSolidGround(ch: string): boolean {
  return ch !== ' ' && ch !== '';
}

/** Full-height wall profile per theme: ruins vary a lot up top, plated walls are regular below. */
function wallHeightFor(theme: Theme, n: number, edge: boolean): number {
  const steps: Record<Theme, number[]> = {
    upper: [1.25, 1.5, 1.5, 1.8, 2.15],
    mid: [1.5, 1.7, 1.7, 1.95],
    lower: [1.8, 1.8, 2.0, 2.0, 2.3],
    core: [2.0, 2.0, 2.3, 2.6],
  };
  const list = steps[theme] ?? steps.upper;
  const h = list[Math.floor(n * list.length) % list.length];
  // The outer rim reads as the room's back wall; give it a touch more presence.
  return edge ? h + 0.25 : h;
}

export function computeLayout(level: Pick<LevelDef, 'id' | 'map' | 'theme'>): LevelLayout {
  const rows = level.map.length;
  const cols = rows > 0 ? Math.max(...level.map.map((row) => row.length)) : 0;
  const seed = hashString(level.id);
  const at = (c: number, r: number): string => {
    if (r < 0 || r >= rows || c < 0) return ' ';
    const row = level.map[r];
    return c < row.length ? row[c] : ' ';
  };
  const isWall = (c: number, r: number): boolean => at(c, r) === '#';
  const ground = (c: number, r: number): boolean => isSolidGround(at(c, r));
  const open = (c: number, r: number): boolean => {
    const ch = at(c, r);
    return isFloorChar(ch) || ch === '=';
  };

  const floors: FloorPlacement[] = [];
  const walls: WallPlacement[] = [];
  const barriers: BarrierPlacement[] = [];
  const cliffs: CliffPlacement[] = [];
  const edges: EdgePlacement[] = [];
  const heights = new Float32Array(rows * cols);

  let minX = Infinity;
  let minZ = Infinity;
  let maxX = -Infinity;
  let maxZ = -Infinity;
  let maxY = 0;
  let minY = -TILE_THICK;

  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      const ch = at(c, r);
      if (!isSolidGround(ch)) continue;
      minX = Math.min(minX, c);
      minZ = Math.min(minZ, r);
      maxX = Math.max(maxX, c + 1);
      maxZ = Math.max(maxZ, r + 1);
      const n = tileNoise(seed, c, r);
      const n2 = tileNoise(seed ^ 0x9e3779b9, c, r);

      if (ch === '#') {
        // Cutaway (chapter 16): a wall that has open floor behind it, from the camera's point of
        // view, is cut low so it can never hide a self, an enemy tell or a spark.
        const hidesFloor = open(c - 1, r) || open(c, r - 1) || open(c - 1, r - 1);
        const rim = !ground(c - 1, r) || !ground(c, r - 1);
        const height = hidesFloor ? WALL_CUT_HEIGHT : wallHeightFor(level.theme, n, rim);
        walls.push({ c, r, height, cut: hidesFloor, shade: n2 });
        heights[r * cols + c] = height;
        maxY = Math.max(maxY, height);
      } else {
        let kind: FloorKind;
        if (ch === ':') kind = 'grate';
        else if (ch === ',') kind = 'overgrown';
        else if (ch === '~') kind = 'rune';
        else kind = n < 0.58 ? 'solid' : n < 0.86 ? 'alt' : 'cracked';
        const wBehind = isWall(c - 1, r);
        const nBehind = isWall(c, r - 1);
        const cornerBehind = isWall(c - 1, r - 1) && !wBehind && !nBehind;
        const ao = Math.min(1, (wBehind ? 0.55 : 0) + (nBehind ? 0.55 : 0) + (cornerBehind ? 0.3 : 0));
        floors.push({ c, r, kind, rot: (Math.floor(n2 * 4) & 3) as 0 | 1 | 2 | 3, shade: n2, ao });
        if (ch === '=') {
          const link = (cc: number, rr: number): boolean => at(cc, rr) === '=' || at(cc, rr) === '#';
          barriers.push({ c, r, n: link(c, r - 1), e: link(c + 1, r), s: link(c, r + 1), w: link(c - 1, r) });
          maxY = Math.max(maxY, BARRIER_HEIGHT);
        }
      }

      const sides: [Side, number, number][] = [
        ['n', c, r - 1],
        ['e', c + 1, r],
        ['s', c, r + 1],
        ['w', c - 1, r],
      ];
      for (const [side, cc, rr] of sides) if (!ground(cc, rr)) edges.push({ c, r, side, wall: ch === '#' });

      const exposed = !ground(c + 1, r) || !ground(c, r + 1) || !ground(c - 1, r) || !ground(c, r - 1);
      if (exposed) {
        // Chunky, irregular skirt so the level reads as a floating diorama (R03/R04 boards).
        const depth = 1.1 + Math.floor(tileNoise(seed ^ 0x51ed27, c, r) * 4) * 0.35;
        cliffs.push({ c, r, depth, shade: n });
        minY = Math.min(minY, -TILE_THICK - depth);
      }
    }
  }

  if (!Number.isFinite(minX)) {
    minX = 0;
    minZ = 0;
    maxX = Math.max(1, cols);
    maxZ = Math.max(1, rows);
  }

  return {
    cols,
    rows,
    floors,
    walls,
    barriers,
    cliffs,
    edges,
    bounds: { minX, minZ, maxX, maxZ, maxY, minY },
    seed,
    at,
    wallHeight: (c, r) => (c >= 0 && r >= 0 && c < cols && r < rows ? heights[r * cols + c] : 0),
  };
}

/** Floor placements grouped by kind (one instanced mesh per kind). */
export function countFloorKinds(layout: LevelLayout): Record<FloorKind, number> {
  const out = { solid: 0, alt: 0, cracked: 0, grate: 0, overgrown: 0, rune: 0 } as Record<FloorKind, number>;
  for (const f of layout.floors) out[f.kind]++;
  return out;
}
