/**
 * Tile grid: static map solidity plus a dynamic overlay, and the geometric queries the kernel,
 * player controller, path-finder and projectiles share.
 *
 * Tile (c, r) covers world x ∈ [c, c+1), y ∈ [r, r+1) (see MapRows in types.ts). Out-of-bounds
 * tiles behave as walls for everything.
 *
 * Two kinds of solidity:
 *   movement   — walls, void, low barriers ('='), dynamic solids. Bodies collide with these.
 *   projectile — walls and dynamic solids only. Projectiles and line of sight pass over void and
 *                low barriers.
 * The dynamic overlay (closed doors, unbroken breakables) blocks both and is set by the kernel.
 */
import { COLLISION_SKIN } from './tuning';
import type { LevelDef, MapRows, Vec2 } from './types';

// ───────────────────────────── tiles ─────────────────────────────

export const TILE_WALL = 0;
export const TILE_FLOOR = 1;
export const TILE_VOID = 2;
export const TILE_LOW = 3;
export const TILE_GRATE = 4;
export const TILE_OVERGROWN = 5;
export const TILE_RUNE = 6;
export type TileKind = 0 | 1 | 2 | 3 | 4 | 5 | 6;

const CHAR_TO_TILE: Record<string, TileKind> = {
  '#': TILE_WALL,
  '.': TILE_FLOOR,
  ' ': TILE_VOID,
  '=': TILE_LOW,
  ':': TILE_GRATE,
  ',': TILE_OVERGROWN,
  '~': TILE_RUNE,
};

/** Map character for each TileKind (index = kind). */
export const TILE_CHARS: readonly string[] = ['#', '.', ' ', '=', ':', ',', '~'];

/** True for the tile kinds a body may stand on. */
export function isFloorKind(kind: TileKind): boolean {
  return kind === TILE_FLOOR || kind === TILE_GRATE || kind === TILE_OVERGROWN || kind === TILE_RUNE;
}

export interface MoveOpts {
  /** Low barriers do not block (the 'phaseDodge' ability during a dodge). */
  ignoreLow?: boolean;
}

export interface MoveResult {
  x: number;
  y: number;
  /** True if any collision changed the requested motion. */
  blocked: boolean;
}

export interface RayHit {
  /** True if a blocking tile was hit within the distance limit. */
  hit: boolean;
  /** Distance along the ray to the hit (or to the limit when nothing was hit). */
  dist: number;
  /** World point of the hit (or of the limit). */
  x: number;
  y: number;
  /** Tile that was hit (-1, -1 when nothing was hit). */
  c: number;
  r: number;
  /** Surface normal of the face that was entered (0, 0 when starting inside a solid or no hit). */
  nx: number;
  ny: number;
}

/** Error thrown for malformed maps so the level validator can report the level and cell. */
export class MapParseError extends Error {
  constructor(
    message: string,
    readonly c: number,
    readonly r: number,
  ) {
    super(message);
    this.name = 'MapParseError';
  }
}

/** Static block flags. */
const Block = {
  None: 0,
  Move: 1,
  Shot: 2,
  /** Blocks movement only because it is a low barrier (ignorable with MoveOpts.ignoreLow). */
  Low: 4,
} as const;

// ───────────────────────────── grid ─────────────────────────────

export class Grid {
  readonly cols: number;
  readonly rows: number;
  /** TileKind per tile, row-major (index = r * cols + c). */
  readonly tiles: Uint8Array;
  /** Static Block flags per tile. */
  private readonly staticBlock: Uint8Array;
  /** 1 where the kernel has made the tile solid this substep. */
  private readonly dynamic: Uint8Array;
  private _revision = 0;

  constructor(cols: number, rows: number, tiles: Uint8Array) {
    if (!(cols > 0 && rows > 0) || tiles.length !== cols * rows) {
      throw new Error(`Grid: bad dimensions ${cols}x${rows} for ${tiles.length} tiles`);
    }
    this.cols = cols;
    this.rows = rows;
    this.tiles = tiles;
    this.staticBlock = new Uint8Array(tiles.length);
    this.dynamic = new Uint8Array(tiles.length);
    for (let i = 0; i < tiles.length; i++) {
      const t = tiles[i] as TileKind;
      let b: number = Block.None;
      if (t === TILE_WALL) b = Block.Move | Block.Shot;
      else if (t === TILE_VOID) b = Block.Move;
      else if (t === TILE_LOW) b = Block.Move | Block.Low;
      this.staticBlock[i] = b;
    }
  }

  /** Parse MapRows. Short rows are padded with void. Throws MapParseError on unknown characters. */
  static parse(map: MapRows): Grid {
    const rows = map.length;
    let cols = 0;
    for (const row of map) cols = Math.max(cols, row.length);
    if (rows === 0 || cols === 0) throw new MapParseError('Map is empty', 0, 0);
    const tiles = new Uint8Array(cols * rows).fill(TILE_VOID);
    for (let r = 0; r < rows; r++) {
      const row = map[r];
      for (let c = 0; c < row.length; c++) {
        const ch = row[c];
        const kind = CHAR_TO_TILE[ch];
        if (kind === undefined) {
          throw new MapParseError(`Unknown map character ${JSON.stringify(ch)} at column ${c}, row ${r}`, c, r);
        }
        tiles[r * cols + c] = kind;
      }
    }
    return new Grid(cols, rows, tiles);
  }

  static fromLevel(level: Pick<LevelDef, 'map'>): Grid {
    return Grid.parse(level.map);
  }

  /**
   * Incremented whenever the dynamic overlay actually changes. Path caches and spark re-planning
   * key off it (DESYNC-04: a reopened route must be noticed).
   */
  get revision(): number {
    return this._revision;
  }

  inBounds(c: number, r: number): boolean {
    return c >= 0 && r >= 0 && c < this.cols && r < this.rows;
  }

  index(c: number, r: number): number {
    return r * this.cols + c;
  }

  /** Tile kind; out of bounds reads as wall. */
  tileAt(c: number, r: number): TileKind {
    return this.inBounds(c, r) ? (this.tiles[r * this.cols + c] as TileKind) : TILE_WALL;
  }

  /** Tile kind under a world point. */
  tileAtPoint(x: number, y: number): TileKind {
    return this.tileAt(Math.floor(x), Math.floor(y));
  }

  // ── dynamic overlay ──

  setDynamicSolid(c: number, r: number, solid: boolean): void {
    if (!this.inBounds(c, r)) return;
    const i = r * this.cols + c;
    const v = solid ? 1 : 0;
    if (this.dynamic[i] !== v) {
      this.dynamic[i] = v;
      this._revision++;
    }
  }

  isDynamicSolid(c: number, r: number): boolean {
    return this.inBounds(c, r) && this.dynamic[r * this.cols + c] === 1;
  }

  clearDynamic(): void {
    let changed = false;
    for (let i = 0; i < this.dynamic.length; i++) {
      if (this.dynamic[i] !== 0) {
        this.dynamic[i] = 0;
        changed = true;
      }
    }
    if (changed) this._revision++;
  }

  // ── per-tile solidity ──

  /** Does tile (c, r) block bodies? */
  blocksMove(c: number, r: number, ignoreLow = false): boolean {
    if (!this.inBounds(c, r)) return true;
    const i = r * this.cols + c;
    if (this.dynamic[i] === 1) return true;
    const b = this.staticBlock[i];
    if (b & Block.Move) return !(ignoreLow && b & Block.Low);
    return false;
  }

  /** Does tile (c, r) block projectiles and line of sight? */
  blocksShot(c: number, r: number): boolean {
    if (!this.inBounds(c, r)) return true;
    const i = r * this.cols + c;
    return this.dynamic[i] === 1 || (this.staticBlock[i] & Block.Shot) !== 0;
  }

  /** Can a body stand on tile (c, r) right now? (floor and not dynamically solid) */
  isWalkable(c: number, r: number): boolean {
    return !this.blocksMove(c, r, false);
  }

  /** Is the tile statically walkable, ignoring the dynamic overlay? (door cells are) */
  isStaticWalkable(c: number, r: number): boolean {
    return this.inBounds(c, r) && (this.staticBlock[r * this.cols + c] & Block.Move) === 0;
  }

  // ── circle queries ──

  /**
   * Does a circle overlap any movement-blocking tile? Touching exactly is not overlapping.
   * A radius ≤ 0 tests the point's tile.
   */
  isSolidAt(x: number, y: number, radius: number, opts?: MoveOpts): boolean {
    const ignoreLow = opts?.ignoreLow === true;
    if (!(radius > 0)) return this.blocksMove(Math.floor(x), Math.floor(y), ignoreLow);
    const r2 = radius * radius;
    const c0 = Math.floor(x - radius);
    const c1 = Math.floor(x + radius);
    const r0 = Math.floor(y - radius);
    const r1 = Math.floor(y + radius);
    for (let r = r0; r <= r1; r++) {
      for (let c = c0; c <= c1; c++) {
        if (!this.blocksMove(c, r, ignoreLow)) continue;
        const qx = x < c ? c : x > c + 1 ? c + 1 : x;
        const qy = y < r ? r : y > r + 1 ? r + 1 : y;
        const dx = x - qx;
        const dy = y - qy;
        if (dx * dx + dy * dy < r2) return true;
      }
    }
    return false;
  }

  /**
   * Move a circle by (dx, dy) with wall sliding. The motion is cut into steps of at most
   * MOVE_STEP tiles and penetration is resolved after each, so a fast body cannot tunnel through a
   * 1-tile wall (a step never carries the centre past a tile's middle). Resolved circles rest
   * COLLISION_SKIN outside walls. When nothing blocks, the result is exactly (x + dx, y + dy).
   */
  moveCircle(x: number, y: number, dx: number, dy: number, radius: number, opts?: MoveOpts, out?: MoveResult): MoveResult {
    const res = out ?? { x: 0, y: 0, blocked: false };
    const ignoreLow = opts?.ignoreLow === true;
    const r = radius > 0 ? radius : 1e-4;
    const dist = Math.hypot(dx, dy);
    const n = dist > 0 ? Math.ceil(dist / MOVE_STEP) : 0;
    let px = x;
    let py = y;
    let blocked = false;
    if (this.resolveCircle(px, py, r, ignoreLow, scratch)) {
      px = scratch.x;
      py = scratch.y;
      blocked = true;
    }
    const sx = n > 0 ? dx / n : 0;
    const sy = n > 0 ? dy / n : 0;
    for (let i = 0; i < n; i++) {
      px += sx;
      py += sy;
      if (this.resolveCircle(px, py, r, ignoreLow, scratch)) {
        px = scratch.x;
        py = scratch.y;
        blocked = true;
      }
    }
    if (blocked) {
      res.x = px;
      res.y = py;
    } else {
      res.x = x + dx;
      res.y = y + dy;
    }
    res.blocked = blocked;
    return res;
  }

  /**
   * Push a circle out of blocking tiles, deepest penetration first so internal seams between
   * adjacent wall tiles never produce sideways bumps. Returns true if it moved; result in `out`.
   */
  private resolveCircle(x: number, y: number, radius: number, ignoreLow: boolean, out: Vec2): boolean {
    let moved = false;
    const r2 = radius * radius;
    for (let iter = 0; iter < 8; iter++) {
      let best = -1;
      let bestPen = 0;
      let bestPx = 0;
      let bestPy = 0;
      const c0 = Math.floor(x - radius);
      const c1 = Math.floor(x + radius);
      const r0 = Math.floor(y - radius);
      const r1 = Math.floor(y + radius);
      for (let r = r0; r <= r1; r++) {
        for (let c = c0; c <= c1; c++) {
          if (!this.blocksMove(c, r, ignoreLow)) continue;
          const qx = x < c ? c : x > c + 1 ? c + 1 : x;
          const qy = y < r ? r : y > r + 1 ? r + 1 : y;
          const ddx = x - qx;
          const ddy = y - qy;
          const d2 = ddx * ddx + ddy * ddy;
          if (d2 >= r2) continue;
          let pen: number;
          let pxv: number;
          let pyv: number;
          if (d2 > 1e-18) {
            const d = Math.sqrt(d2);
            pen = radius - d;
            const k = (radius + COLLISION_SKIN - d) / d;
            pxv = ddx * k;
            pyv = ddy * k;
          } else {
            // Centre inside (or on the edge of) the tile: leave through the nearest face whose
            // neighbour is open, so a body is never shoved deeper into a wall mass.
            const left = x - c;
            const right = c + 1 - x;
            const top = y - r;
            const bottom = r + 1 - y;
            let face = -1;
            let faceDist = Infinity;
            const consider = (f: number, d: number, nc: number, nr: number, requireOpen: boolean): void => {
              if (requireOpen && this.blocksMove(nc, nr, ignoreLow)) return;
              if (d < faceDist) {
                faceDist = d;
                face = f;
              }
            };
            consider(0, left, c - 1, r, true);
            consider(1, right, c + 1, r, true);
            consider(2, top, c, r - 1, true);
            consider(3, bottom, c, r + 1, true);
            if (face < 0) {
              consider(0, left, 0, 0, false);
              consider(1, right, 0, 0, false);
              consider(2, top, 0, 0, false);
              consider(3, bottom, 0, 0, false);
            }
            pen = radius + faceDist;
            const push = faceDist + radius + COLLISION_SKIN;
            pxv = face === 0 ? -push : face === 1 ? push : 0;
            pyv = face === 2 ? -push : face === 3 ? push : 0;
          }
          if (pen > bestPen) {
            bestPen = pen;
            best = r * this.cols + c;
            bestPx = pxv;
            bestPy = pyv;
          }
        }
      }
      if (best < 0) break;
      x += bestPx;
      y += bestPy;
      moved = true;
    }
    out.x = x;
    out.y = y;
    return moved;
  }

  /**
   * Would a circle swept from (x0, y0) to (x1, y1) overlap any movement-blocking tile?
   * Exact (segment-to-box distance), not sampled. Used for the desync "straight step is blocked"
   * test and for path string-pulling. A radius ≤ 0 falls back to the tile walk of segmentBlocked.
   */
  sweepCircleBlocked(x0: number, y0: number, x1: number, y1: number, radius: number, opts?: MoveOpts): boolean {
    const ignoreLow = opts?.ignoreLow === true;
    if (!(radius > 0)) return this.traverse(x0, y0, x1 - x0, y1 - y0, 1, false, ignoreLow, null);
    const len = Math.hypot(x1 - x0, y1 - y0);
    // Chunk long sweeps so each chunk's candidate box stays small.
    const chunks = Math.max(1, Math.ceil(len / 2));
    const r2 = radius * radius;
    for (let k = 0; k < chunks; k++) {
      const ax = x0 + ((x1 - x0) * k) / chunks;
      const ay = y0 + ((y1 - y0) * k) / chunks;
      const bx = k === chunks - 1 ? x1 : x0 + ((x1 - x0) * (k + 1)) / chunks;
      const by = k === chunks - 1 ? y1 : y0 + ((y1 - y0) * (k + 1)) / chunks;
      const c0 = Math.floor(Math.min(ax, bx) - radius);
      const c1 = Math.floor(Math.max(ax, bx) + radius);
      const r0 = Math.floor(Math.min(ay, by) - radius);
      const r1 = Math.floor(Math.max(ay, by) + radius);
      for (let r = r0; r <= r1; r++) {
        for (let c = c0; c <= c1; c++) {
          if (!this.blocksMove(c, r, ignoreLow)) continue;
          if (segmentBoxDist2(ax, ay, bx, by, c, r, c + 1, r + 1) < r2) return true;
        }
      }
    }
    return false;
  }

  // ── rays ──

  /**
   * Does the segment pass through a blocking tile? `forProjectile` selects projectile/sight
   * solidity (walls, dynamic) instead of movement solidity (also void and low barriers).
   * Includes the start and end tiles. Passing exactly through a corner between two tiles is blocked
   * only if both of them block (a sealed diagonal), not by grazing one.
   */
  segmentBlocked(x0: number, y0: number, x1: number, y1: number, forProjectile: boolean): boolean {
    return this.traverse(x0, y0, x1 - x0, y1 - y0, 1, forProjectile, false, null);
  }

  /** Clear line of sight between two points (projectile solidity). */
  lineOfSight(a: Vec2, b: Vec2): boolean {
    return !this.traverse(a.x, a.y, b.x - a.x, b.y - a.y, 1, true, false, null);
  }

  /**
   * Cast a ray from (x0, y0) along (dirX, dirY) (need not be normalised) up to maxDist tiles.
   * Returns the first blocking tile and the distance to its entry face.
   */
  raycast(x0: number, y0: number, dirX: number, dirY: number, maxDist: number, forProjectile: boolean, out?: RayHit): RayHit {
    const res = out ?? { hit: false, dist: 0, x: 0, y: 0, c: -1, r: -1, nx: 0, ny: 0 };
    const len = Math.hypot(dirX, dirY);
    if (!(len > 0)) {
      const c = Math.floor(x0);
      const r = Math.floor(y0);
      const hit = forProjectile ? this.blocksShot(c, r) : this.blocksMove(c, r);
      res.hit = hit;
      res.dist = 0;
      res.x = x0;
      res.y = y0;
      res.c = hit ? c : -1;
      res.r = hit ? r : -1;
      res.nx = 0;
      res.ny = 0;
      return res;
    }
    const ux = dirX / len;
    const uy = dirY / len;
    res.hit = this.traverse(x0, y0, ux, uy, maxDist, forProjectile, false, res);
    if (!res.hit) {
      res.dist = maxDist;
      res.c = -1;
      res.r = -1;
      res.nx = 0;
      res.ny = 0;
    }
    res.x = x0 + ux * res.dist;
    res.y = y0 + uy * res.dist;
    return res;
  }

  /**
   * Amanatides–Woo grid walk along p(t) = (x0, y0) + t·(dx, dy), t ∈ [0, tMax]. Returns true on
   * the first blocking tile; if `hit` is given, fills dist (= t), tile and entry normal.
   */
  private traverse(
    x0: number,
    y0: number,
    dx: number,
    dy: number,
    tMax: number,
    forProjectile: boolean,
    ignoreLow: boolean,
    hit: RayHit | null,
  ): boolean {
    const blocks = (c: number, r: number): boolean =>
      forProjectile ? this.blocksShot(c, r) : this.blocksMove(c, r, ignoreLow);
    let c = Math.floor(x0);
    let r = Math.floor(y0);
    if (blocks(c, r)) {
      if (hit) setHit(hit, 0, c, r, 0, 0);
      return true;
    }
    const stepX = dx > 0 ? 1 : dx < 0 ? -1 : 0;
    const stepY = dy > 0 ? 1 : dy < 0 ? -1 : 0;
    const tDeltaX = stepX !== 0 ? 1 / Math.abs(dx) : Infinity;
    const tDeltaY = stepY !== 0 ? 1 / Math.abs(dy) : Infinity;
    let tMaxX = stepX > 0 ? (c + 1 - x0) / dx : stepX < 0 ? (x0 - c) / -dx : Infinity;
    let tMaxY = stepY > 0 ? (r + 1 - y0) / dy : stepY < 0 ? (y0 - r) / -dy : Infinity;
    // Bounded by the number of tile boundaries the segment can cross.
    const limit = 4 + Math.ceil(Math.abs(dx) * tMax) + Math.ceil(Math.abs(dy) * tMax) + 2;
    for (let n = 0; n < limit; n++) {
      const diff = tMaxX - tMaxY;
      const tie = Math.abs(diff) <= 1e-12 * Math.max(1, Math.abs(tMaxX)) && tMaxX !== Infinity;
      if (tie) {
        const t = tMaxX;
        if (t > tMax) return false;
        const aBlocks = blocks(c + stepX, r);
        const bBlocks = blocks(c, r + stepY);
        if (aBlocks && bBlocks) {
          if (hit) setHit(hit, t, c + stepX, r, -stepX, 0);
          return true;
        }
        c += stepX;
        r += stepY;
        tMaxX += tDeltaX;
        tMaxY += tDeltaY;
        if (blocks(c, r)) {
          if (hit) setHit(hit, t, c, r, -stepX, -stepY);
          return true;
        }
      } else if (diff < 0) {
        const t = tMaxX;
        if (t > tMax) return false;
        c += stepX;
        tMaxX += tDeltaX;
        if (blocks(c, r)) {
          if (hit) setHit(hit, t, c, r, -stepX, 0);
          return true;
        }
      } else {
        const t = tMaxY;
        if (t > tMax) return false;
        r += stepY;
        tMaxY += tDeltaY;
        if (blocks(c, r)) {
          if (hit) setHit(hit, t, c, r, 0, -stepY);
          return true;
        }
      }
    }
    return false;
  }

  /**
   * Nearest walkable tile to (c, r) by Chebyshev rings, scanning each ring in a fixed order
   * (deterministic). Returns the tile index or -1 if none within maxRing.
   */
  nearestWalkable(c: number, r: number, maxRing = 8): number {
    if (this.isWalkable(c, r)) return this.index(c, r);
    let best = -1;
    let bestD = Infinity;
    for (let ring = 1; ring <= maxRing; ring++) {
      for (let rr = r - ring; rr <= r + ring; rr++) {
        for (let cc = c - ring; cc <= c + ring; cc++) {
          if (Math.max(Math.abs(cc - c), Math.abs(rr - r)) !== ring) continue;
          if (!this.isWalkable(cc, rr)) continue;
          const d = (cc - c) * (cc - c) + (rr - r) * (rr - r);
          if (d < bestD) {
            bestD = d;
            best = this.index(cc, rr);
          }
        }
      }
      if (best >= 0) return best;
    }
    return -1;
  }

  /** ASCII dump (static tiles; dynamic solids shown as 'D'). For debugging and test failure messages. */
  toString(): string {
    const lines: string[] = [];
    for (let r = 0; r < this.rows; r++) {
      let s = '';
      for (let c = 0; c < this.cols; c++) {
        const i = r * this.cols + c;
        s += this.dynamic[i] ? 'D' : TILE_CHARS[this.tiles[i]];
      }
      lines.push(s);
    }
    return lines.join('\n');
  }
}

/** Largest sub-move moveCircle takes before resolving; < 0.5 so no tile can be skipped. */
const MOVE_STEP = 0.2;

const scratch: Vec2 = { x: 0, y: 0 };

function setHit(h: RayHit, t: number, c: number, r: number, nx: number, ny: number): void {
  h.dist = t;
  h.c = c;
  h.r = r;
  h.nx = nx;
  h.ny = ny;
}

/** Parse a level's map. */
export function parseGrid(map: MapRows): Grid {
  return Grid.parse(map);
}

// ───────────────────────────── geometry helpers ─────────────────────────────

function pointBoxDist2(px: number, py: number, bx0: number, by0: number, bx1: number, by1: number): number {
  const qx = px < bx0 ? bx0 : px > bx1 ? bx1 : px;
  const qy = py < by0 ? by0 : py > by1 ? by1 : py;
  const dx = px - qx;
  const dy = py - qy;
  return dx * dx + dy * dy;
}

function pointSegDist2(px: number, py: number, ax: number, ay: number, bx: number, by: number): number {
  const vx = bx - ax;
  const vy = by - ay;
  const l2 = vx * vx + vy * vy;
  let t = l2 > 0 ? ((px - ax) * vx + (py - ay) * vy) / l2 : 0;
  t = t < 0 ? 0 : t > 1 ? 1 : t;
  const dx = ax + vx * t - px;
  const dy = ay + vy * t - py;
  return dx * dx + dy * dy;
}

/** Liang–Barsky: does segment a→b intersect the closed box? */
function segmentHitsBox(ax: number, ay: number, bx: number, by: number, x0: number, y0: number, x1: number, y1: number): boolean {
  const dx = bx - ax;
  const dy = by - ay;
  let t0 = 0;
  let t1 = 1;
  // Each slab clips [t0, t1]; p·t <= q must hold for the point to be inside that half-plane.
  const clip = (p: number, q: number): boolean => {
    if (p === 0) return q >= 0;
    const t = q / p;
    if (p < 0) {
      if (t > t1) return false;
      if (t > t0) t0 = t;
    } else {
      if (t < t0) return false;
      if (t < t1) t1 = t;
    }
    return true;
  };
  return clip(-dx, ax - x0) && clip(dx, x1 - ax) && clip(-dy, ay - y0) && clip(dy, y1 - ay);
}

/**
 * Squared distance between segment a→b and an axis-aligned box. For disjoint convex shapes the
 * minimum is attained at a segment endpoint or a box corner, so those cases cover it exactly.
 */
export function segmentBoxDist2(ax: number, ay: number, bx: number, by: number, x0: number, y0: number, x1: number, y1: number): number {
  if (segmentHitsBox(ax, ay, bx, by, x0, y0, x1, y1)) return 0;
  let d = pointBoxDist2(ax, ay, x0, y0, x1, y1);
  d = Math.min(d, pointBoxDist2(bx, by, x0, y0, x1, y1));
  d = Math.min(d, pointSegDist2(x0, y0, ax, ay, bx, by));
  d = Math.min(d, pointSegDist2(x1, y0, ax, ay, bx, by));
  d = Math.min(d, pointSegDist2(x0, y1, ax, ay, bx, by));
  d = Math.min(d, pointSegDist2(x1, y1, ax, ay, bx, by));
  return d;
}
