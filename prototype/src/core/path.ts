/**
 * Path-finding over walkable tiles: drives the recovery spark (DESYNC-02..04) and enemy navigation.
 *
 * A* on the 8-connected tile graph without corner cutting (a diagonal step needs both orthogonal
 * neighbours walkable), honouring the grid's dynamic overlay so closed doors block and reopened ones
 * are used on the next plan. Costs 1 / √2 with the octile heuristic (admissible and consistent, so
 * results are optimal). Ties are broken by (f, h, tile index) so the chosen path never depends on
 * heap internals.
 *
 * Buffers are allocated once per Pathfinder and reused; visited state is reset by bumping a
 * generation stamp, so a plan on a 40×40 map costs microseconds and allocates only its result.
 */
import { Grid } from './grid';
import { BASE } from './tuning';
import type { Vec2 } from './types';

const SQRT2 = Math.SQRT2;

// Neighbour order is fixed (E, W, S, N, SE, SW, NE, NW) for determinism.
const NDC = [1, -1, 0, 0, 1, -1, 1, -1];
const NDR = [0, 0, 1, -1, 1, 1, -1, -1];

export interface PathOpts {
  /**
   * When the goal is unwalkable or unreachable, return a path to the reachable tile closest to it
   * (Euclidean, ties by lower cost) instead of null. The spark uses this to wait as close as it can
   * to a projection that is inside a wall or sealed off (DESYNC-03: no teleport).
   */
  allowPartial?: boolean;
  /** String-pull the tile path into straight runs (default true). */
  smooth?: boolean;
  /** Clearance radius used while smoothing, tiles (default BASE.sparkRadius). */
  radius?: number;
}

export interface PathResult {
  /** Waypoints to visit in order, excluding the start point. Ends at the goal point when it was reached. */
  points: Vec2[];
  /** True if the goal tile itself was reached (false for a partial path). */
  complete: boolean;
  /** Path cost in tiles along the tile graph (before smoothing). */
  cost: number;
}

export class Pathfinder {
  readonly grid: Grid;
  private readonly n: number;
  private readonly g: Float64Array;
  private readonly parent: Int32Array;
  private readonly openGen: Uint32Array;
  private readonly closedGen: Uint32Array;
  private gen = 0;
  // Binary min-heap with lazy deletion.
  private heapNode: Int32Array;
  private heapF: Float64Array;
  private heapH: Float64Array;
  private heapSize = 0;
  // Connected components of walkable tiles (4-connectivity equals 8-connectivity without corner
  // cutting, since any legal diagonal step can be replaced by two orthogonal ones).
  private readonly comp: Int32Array;
  private compRevision = -1;
  private readonly floodStack: Int32Array;
  /** Nodes expanded by the most recent search (diagnostics, performance tests). */
  lastExpanded = 0;

  constructor(grid: Grid) {
    this.grid = grid;
    const n = grid.cols * grid.rows;
    this.n = n;
    this.g = new Float64Array(n);
    this.parent = new Int32Array(n);
    this.openGen = new Uint32Array(n);
    this.closedGen = new Uint32Array(n);
    const cap = Math.max(16, n * 2);
    this.heapNode = new Int32Array(cap);
    this.heapF = new Float64Array(cap);
    this.heapH = new Float64Array(cap);
    this.comp = new Int32Array(n);
    this.floodStack = new Int32Array(n);
  }

  // ───────────────────────────── reachability ─────────────────────────────

  /** Component id of a tile (-1 if unwalkable). Recomputed lazily when the grid revision changes. */
  componentOf(c: number, r: number): number {
    if (!this.grid.inBounds(c, r)) return -1;
    this.ensureComponents();
    return this.comp[r * this.grid.cols + c];
  }

  /** Is there any route between two tiles right now? O(1) after a per-revision flood fill. */
  hasRoute(c0: number, r0: number, c1: number, r1: number): boolean {
    const a = this.componentOf(c0, r0);
    return a >= 0 && a === this.componentOf(c1, r1);
  }

  /** hasRoute between the tiles under two world points. */
  hasRouteBetween(a: Vec2, b: Vec2): boolean {
    return this.hasRoute(Math.floor(a.x), Math.floor(a.y), Math.floor(b.x), Math.floor(b.y));
  }

  private ensureComponents(): void {
    const grid = this.grid;
    if (this.compRevision === grid.revision && this.compRevision >= 0) return;
    const cols = grid.cols;
    const comp = this.comp;
    comp.fill(-1);
    let next = 0;
    const stack = this.floodStack;
    for (let i = 0; i < this.n; i++) {
      if (comp[i] !== -1) continue;
      const c = i % cols;
      const r = (i - c) / cols;
      if (!grid.isWalkable(c, r)) continue;
      let sp = 0;
      stack[sp++] = i;
      comp[i] = next;
      while (sp > 0) {
        const j = stack[--sp];
        const jc = j % cols;
        const jr = (j - jc) / cols;
        for (let d = 0; d < 4; d++) {
          const nc = jc + NDC[d];
          const nr = jr + NDR[d];
          if (!grid.isWalkable(nc, nr)) continue;
          const k = nr * cols + nc;
          if (comp[k] !== -1) continue;
          comp[k] = next;
          stack[sp++] = k;
        }
      }
      next++;
    }
    this.compRevision = grid.revision;
  }

  // ───────────────────────────── A* ─────────────────────────────

  /**
   * Tile path from (c0, r0) to (c1, r1) as tile indices, start and goal inclusive, or null.
   * With allowPartial the path ends at the reachable tile nearest the goal.
   */
  findTilePath(c0: number, r0: number, c1: number, r1: number, allowPartial = false): number[] | null {
    const res = this.search(c0, r0, c1, r1, allowPartial);
    return res ? res.tiles : null;
  }

  private search(
    c0: number,
    r0: number,
    c1: number,
    r1: number,
    allowPartial: boolean,
  ): { tiles: number[]; complete: boolean; cost: number } | null {
    const grid = this.grid;
    const cols = grid.cols;
    this.lastExpanded = 0;
    if (!grid.isWalkable(c0, r0)) return null;
    const start = r0 * cols + c0;
    const goalWalkable = grid.isWalkable(c1, r1);
    if (!allowPartial) {
      if (!goalWalkable || !this.hasRoute(c0, r0, c1, r1)) return null;
    }
    const goal = goalWalkable ? r1 * cols + c1 : -1;
    if (start === goal) return { tiles: [start], complete: true, cost: 0 };

    const gen = this.nextGen();
    const g = this.g;
    const parent = this.parent;
    const openGen = this.openGen;
    const closedGen = this.closedGen;
    this.heapSize = 0;

    g[start] = 0;
    parent[start] = -1;
    openGen[start] = gen;
    const h0 = octile(c0, r0, c1, r1);
    this.push(start, h0, h0);

    let best = start;
    let bestD = euclid2(c0, r0, c1, r1);
    let bestG = 0;
    let found = false;

    while (this.heapSize > 0) {
      const node = this.pop();
      if (closedGen[node] === gen) continue;
      closedGen[node] = gen;
      this.lastExpanded++;
      if (node === goal) {
        found = true;
        break;
      }
      const nc0 = node % cols;
      const nr0 = (node - nc0) / cols;
      const gn = g[node];
      if (allowPartial) {
        const d = euclid2(nc0, nr0, c1, r1);
        if (d < bestD || (d === bestD && gn < bestG)) {
          bestD = d;
          bestG = gn;
          best = node;
        }
      }
      for (let k = 0; k < 8; k++) {
        const nc = nc0 + NDC[k];
        const nr = nr0 + NDR[k];
        if (!grid.isWalkable(nc, nr)) continue;
        let step = 1;
        if (k >= 4) {
          // No corner cutting: both orthogonal neighbours of a diagonal step must be open.
          if (!grid.isWalkable(nc, nr0) || !grid.isWalkable(nc0, nr)) continue;
          step = SQRT2;
        }
        const ni = nr * cols + nc;
        if (closedGen[ni] === gen) continue;
        const ng = gn + step;
        if (openGen[ni] === gen && ng >= g[ni]) continue;
        openGen[ni] = gen;
        g[ni] = ng;
        parent[ni] = node;
        const h = octile(nc, nr, c1, r1);
        this.push(ni, ng + h, h);
      }
    }

    const end = found ? goal : allowPartial ? best : -1;
    if (end < 0) return null;
    const tiles: number[] = [];
    for (let i = end; i !== -1; i = parent[i]) tiles.push(i);
    tiles.reverse();
    return { tiles, complete: found, cost: g[end] };
  }

  /**
   * World-space path from (sx, sy) to (tx, ty). A start inside an unwalkable tile begins from the
   * nearest walkable tile. Returns null when no route exists (unless allowPartial).
   */
  findPath(sx: number, sy: number, tx: number, ty: number, opts?: PathOpts): PathResult | null {
    const grid = this.grid;
    const cols = grid.cols;
    let c0 = Math.floor(sx);
    let r0 = Math.floor(sy);
    if (!grid.isWalkable(c0, r0)) {
      const near = grid.nearestWalkable(c0, r0);
      if (near < 0) return null;
      c0 = near % cols;
      r0 = (near - c0) / cols;
    }
    const c1 = Math.floor(tx);
    const r1 = Math.floor(ty);
    const res = this.search(c0, r0, c1, r1, opts?.allowPartial === true);
    if (!res) return null;
    const pts: Vec2[] = [];
    for (let i = 1; i < res.tiles.length; i++) {
      const t = res.tiles[i];
      const c = t % cols;
      pts.push({ x: c + 0.5, y: (t - c) / cols + 0.5 });
    }
    if (res.complete) {
      // Finish on the exact goal point, replacing the goal tile's centre.
      if (pts.length > 0) pts[pts.length - 1] = { x: tx, y: ty };
      else pts.push({ x: tx, y: ty });
    } else if (pts.length === 0 && (c0 + 0.5 !== sx || r0 + 0.5 !== sy)) {
      // Partial path that never left the start tile: still head for its centre (stable waiting spot).
      pts.push({ x: c0 + 0.5, y: r0 + 0.5 });
    }
    const points = opts?.smooth === false ? pts : this.smooth(sx, sy, pts, opts?.radius ?? BASE.sparkRadius);
    return { points, complete: res.complete, cost: res.cost };
  }

  /**
   * String pulling by line of walk: from each kept point, skip ahead to the last consecutive
   * waypoint a circle of `radius` can sweep to without touching movement-blocking tiles.
   * The next waypoint is always kept even if the sweep to it is tight, so progress is guaranteed.
   */
  smooth(sx: number, sy: number, points: readonly Vec2[], radius: number): Vec2[] {
    if (points.length <= 1) return points.slice();
    const out: Vec2[] = [];
    let ax = sx;
    let ay = sy;
    let i = 0;
    while (i < points.length) {
      let j = i;
      while (j + 1 < points.length && !this.grid.sweepCircleBlocked(ax, ay, points[j + 1].x, points[j + 1].y, radius)) j++;
      out.push(points[j]);
      ax = points[j].x;
      ay = points[j].y;
      i = j + 1;
    }
    return out;
  }

  // ───────────────────────────── heap ─────────────────────────────

  private nextGen(): number {
    this.gen++;
    if (this.gen >= 0xffffffff) {
      this.gen = 1;
      this.openGen.fill(0);
      this.closedGen.fill(0);
    }
    return this.gen;
  }

  private less(a: number, b: number): boolean {
    const fa = this.heapF[a];
    const fb = this.heapF[b];
    if (fa !== fb) return fa < fb;
    const ha = this.heapH[a];
    const hb = this.heapH[b];
    if (ha !== hb) return ha < hb;
    return this.heapNode[a] < this.heapNode[b];
  }

  private swap(a: number, b: number): void {
    const n = this.heapNode[a];
    this.heapNode[a] = this.heapNode[b];
    this.heapNode[b] = n;
    const f = this.heapF[a];
    this.heapF[a] = this.heapF[b];
    this.heapF[b] = f;
    const h = this.heapH[a];
    this.heapH[a] = this.heapH[b];
    this.heapH[b] = h;
  }

  private push(node: number, f: number, h: number): void {
    if (this.heapSize === this.heapNode.length) this.grow();
    let i = this.heapSize++;
    this.heapNode[i] = node;
    this.heapF[i] = f;
    this.heapH[i] = h;
    while (i > 0) {
      const p = (i - 1) >> 1;
      if (!this.less(i, p)) break;
      this.swap(i, p);
      i = p;
    }
  }

  private pop(): number {
    const top = this.heapNode[0];
    const last = --this.heapSize;
    if (last > 0) {
      this.heapNode[0] = this.heapNode[last];
      this.heapF[0] = this.heapF[last];
      this.heapH[0] = this.heapH[last];
      let i = 0;
      for (;;) {
        const l = 2 * i + 1;
        if (l >= last) break;
        const r = l + 1;
        const m = r < last && this.less(r, l) ? r : l;
        if (!this.less(m, i)) break;
        this.swap(i, m);
        i = m;
      }
    }
    return top;
  }

  private grow(): void {
    const cap = this.heapNode.length * 2;
    const nn = new Int32Array(cap);
    nn.set(this.heapNode);
    const nf = new Float64Array(cap);
    nf.set(this.heapF);
    const nh = new Float64Array(cap);
    nh.set(this.heapH);
    this.heapNode = nn;
    this.heapF = nf;
    this.heapH = nh;
  }
}

function octile(c0: number, r0: number, c1: number, r1: number): number {
  const dx = Math.abs(c1 - c0);
  const dy = Math.abs(r1 - r0);
  return dx > dy ? dx - dy + SQRT2 * dy : dy - dx + SQRT2 * dx;
}

function euclid2(c0: number, r0: number, c1: number, r1: number): number {
  const dx = c1 - c0;
  const dy = r1 - r0;
  return dx * dx + dy * dy;
}

/** Total length of a polyline starting at (sx, sy). */
export function pathLength(sx: number, sy: number, points: readonly Vec2[]): number {
  let len = 0;
  let x = sx;
  let y = sy;
  for (const p of points) {
    len += Math.hypot(p.x - x, p.y - y);
    x = p.x;
    y = p.y;
  }
  return len;
}
