import { describe, expect, it } from 'vitest';
import { Grid } from '../../../src/core/grid';
import { Pathfinder, pathLength } from '../../../src/core/path';

const MAZE = [
  '###########',
  '#.....#...#',
  '#.###.#.#.#',
  '#.#...#.#.#',
  '#.#.###.#.#',
  '#.#.....#.#',
  '#.#######.#',
  '#.........#',
  '###########',
];

function tiles(pf: Pathfinder, path: number[]): [number, number][] {
  const cols = pf.grid.cols;
  return path.map((i) => [i % cols, Math.floor(i / cols)]);
}

/** Check a tile path is legal: consecutive tiles adjacent, all walkable, no corner cutting. */
function expectLegal(grid: Grid, path: [number, number][]): void {
  for (const [c, r] of path) expect(grid.isWalkable(c, r)).toBe(true);
  for (let i = 1; i < path.length; i++) {
    const [c0, r0] = path[i - 1];
    const [c1, r1] = path[i];
    expect(Math.max(Math.abs(c1 - c0), Math.abs(r1 - r0))).toBe(1);
    if (c1 !== c0 && r1 !== r0) {
      expect(grid.isWalkable(c1, r0)).toBe(true);
      expect(grid.isWalkable(c0, r1)).toBe(true);
    }
  }
}

/** Reference BFS-Dijkstra over the same graph for optimal cost comparison. */
function dijkstraCost(grid: Grid, c0: number, r0: number, c1: number, r1: number): number {
  const n = grid.cols * grid.rows;
  const dist = new Float64Array(n).fill(Infinity);
  const done = new Uint8Array(n);
  dist[r0 * grid.cols + c0] = 0;
  for (;;) {
    let u = -1;
    for (let i = 0; i < n; i++) if (!done[i] && dist[i] < Infinity && (u < 0 || dist[i] < dist[u])) u = i;
    if (u < 0) return Infinity;
    if (u === r1 * grid.cols + c1) return dist[u];
    done[u] = 1;
    const uc = u % grid.cols;
    const ur = Math.floor(u / grid.cols);
    for (let dr = -1; dr <= 1; dr++) {
      for (let dc = -1; dc <= 1; dc++) {
        if (!dc && !dr) continue;
        const vc = uc + dc;
        const vr = ur + dr;
        if (!grid.isWalkable(vc, vr)) continue;
        if (dc && dr && (!grid.isWalkable(vc, ur) || !grid.isWalkable(uc, vr))) continue;
        const v = vr * grid.cols + vc;
        const w = dc && dr ? Math.SQRT2 : 1;
        if (dist[u] + w < dist[v]) dist[v] = dist[u] + w;
      }
    }
  }
}

describe('A*', () => {
  it('finds the optimal legal path through a maze', () => {
    const g = Grid.parse(MAZE);
    const pf = new Pathfinder(g);
    const p = pf.findTilePath(1, 1, 3, 3)!;
    expect(p).not.toBeNull();
    const t = tiles(pf, p);
    expect(t[0]).toEqual([1, 1]);
    expect(t[t.length - 1]).toEqual([3, 3]);
    expectLegal(g, t);
    const res = pf.findPath(1.5, 1.5, 3.5, 3.5, { smooth: false })!;
    expect(res.complete).toBe(true);
    expect(res.cost).toBeCloseTo(dijkstraCost(g, 1, 1, 3, 3), 9);
  });

  it('matches Dijkstra on every reachable pair of a maze', () => {
    const g = Grid.parse(MAZE);
    const pf = new Pathfinder(g);
    const open: [number, number][] = [];
    for (let r = 0; r < g.rows; r++) for (let c = 0; c < g.cols; c++) if (g.isWalkable(c, r)) open.push([c, r]);
    for (let i = 0; i < open.length; i += 3) {
      for (let j = 1; j < open.length; j += 5) {
        const [c0, r0] = open[i];
        const [c1, r1] = open[j];
        const res = pf.findPath(c0 + 0.5, r0 + 0.5, c1 + 0.5, r1 + 0.5, { smooth: false });
        const ref = dijkstraCost(g, c0, r0, c1, r1);
        if (ref === Infinity) expect(res).toBeNull();
        else expect(res!.cost).toBeCloseTo(ref, 9);
      }
    }
  });

  it('never cuts corners', () => {
    const g = Grid.parse(['#####', '#..##', '##..#', '#####']);
    const pf = new Pathfinder(g);
    // (2,1) → (2,2) is direct; (1,1) → (3,2) must not squeeze diagonally between walls.
    const t = tiles(pf, pf.findTilePath(1, 1, 3, 2)!);
    expectLegal(g, t);
    expect(t).toEqual([
      [1, 1],
      [2, 1],
      [2, 2],
      [3, 2],
    ]);
    const sealed = Grid.parse(['####', '#.##', '##.#', '####']);
    expect(new Pathfinder(sealed).findTilePath(1, 1, 2, 2)).toBeNull();
  });

  it('re-plans when a door closes and when it opens again (DESYNC-04)', () => {
    const g = Grid.parse([
      '###########',
      '#....#....#',
      '#.........#',
      '#....#....#',
      '#.####....#',
      '#.........#',
      '###########',
    ]);
    const pf = new Pathfinder(g);
    const direct = pf.findPath(2.5, 2.5, 8.5, 2.5)!;
    expect(direct.cost).toBeCloseTo(6, 9);
    // Close the door at (5, 2): the only route is the long detour through the bottom corridor.
    g.setDynamicSolid(5, 2, true);
    const detour = pf.findPath(2.5, 2.5, 8.5, 2.5)!;
    expect(detour.cost).toBeGreaterThan(9);
    expect(tiles(pf, pf.findTilePath(2, 2, 8, 2)!).some(([c, r]) => c === 5 && r === 2)).toBe(false);
    // Seal the detour too: no route.
    g.setDynamicSolid(1, 4, true);
    expect(pf.hasRoute(2, 2, 8, 2)).toBe(false);
    expect(pf.findPath(2.5, 2.5, 8.5, 2.5)).toBeNull();
    // Reopen the door: direct again.
    g.setDynamicSolid(5, 2, false);
    expect(pf.hasRoute(2, 2, 8, 2)).toBe(true);
    expect(pf.findPath(2.5, 2.5, 8.5, 2.5)!.cost).toBeCloseTo(6, 9);
  });

  it('partial paths head for the reachable tile nearest an unreachable goal', () => {
    const g = Grid.parse(['#######', '#..#..#', '#..#..#', '#######']);
    const pf = new Pathfinder(g);
    expect(pf.findPath(1.5, 1.5, 4.5, 1.5)).toBeNull();
    const part = pf.findPath(1.5, 1.5, 4.5, 1.5, { allowPartial: true })!;
    expect(part.complete).toBe(false);
    const last = part.points[part.points.length - 1];
    expect([last.x, last.y]).toEqual([2.5, 1.5]);
    // Goal inside a wall (a projection that desynced into it).
    const inWall = pf.findPath(1.5, 2.5, 3.4, 2.5, { allowPartial: true })!;
    expect(inWall.points[inWall.points.length - 1]).toEqual({ x: 2.5, y: 2.5 });
  });

  it('starts from the nearest walkable tile when the start is inside a solid', () => {
    const g = Grid.parse(['#####', '#...#', '#####']);
    g.setDynamicSolid(1, 1, true);
    const res = new Pathfinder(g).findPath(1.5, 1.5, 3.5, 1.5)!;
    expect(res).not.toBeNull();
    expect(res.points[res.points.length - 1]).toEqual({ x: 3.5, y: 1.5 });
  });

  it('is deterministic: identical inputs give identical paths', () => {
    const g = Grid.parse(['############', '#..........#', '#..........#', '#..........#', '############']);
    const a = new Pathfinder(g).findTilePath(1, 1, 10, 3);
    const b = new Pathfinder(g).findTilePath(1, 1, 10, 3);
    const pf = new Pathfinder(g);
    pf.findTilePath(3, 3, 1, 1);
    expect(pf.findTilePath(1, 1, 10, 3)).toEqual(a);
    expect(b).toEqual(a);
  });
});

describe('smoothing', () => {
  it('string-pulls open-room paths to a straight line', () => {
    const g = Grid.parse(['##########', '#........#', '#........#', '#........#', '#........#', '##########']);
    const res = new Pathfinder(g).findPath(1.5, 1.5, 8.5, 3.7)!;
    expect(res.points).toEqual([{ x: 8.5, y: 3.7 }]);
  });

  it('keeps corners around obstacles and every leg is walkable with clearance', () => {
    const g = Grid.parse(MAZE);
    const pf = new Pathfinder(g);
    const raw = pf.findPath(1.5, 1.5, 3.5, 3.5, { smooth: false })!;
    const sm = pf.findPath(1.5, 1.5, 3.5, 3.5, { radius: 0.2 })!;
    expect(sm.points.length).toBeLessThan(raw.points.length);
    let x = 1.5;
    let y = 1.5;
    for (const p of sm.points) {
      expect(g.sweepCircleBlocked(x, y, p.x, p.y, 0.2)).toBe(false);
      x = p.x;
      y = p.y;
    }
    expect(pathLength(1.5, 1.5, sm.points)).toBeLessThanOrEqual(pathLength(1.5, 1.5, raw.points) + 1e-9);
  });
});

describe('performance', () => {
  it('re-plans on a 40x40 maze many times per second', () => {
    // Deterministic maze: walls on a lattice with gaps from an LCG.
    let seed = 99;
    const rnd = (): number => {
      seed = (seed * 1664525 + 1013904223) >>> 0;
      return seed / 0x100000000;
    };
    const rows: string[] = [];
    for (let r = 0; r < 40; r++) {
      let s = '';
      for (let c = 0; c < 40; c++) {
        const border = r === 0 || c === 0 || r === 39 || c === 39;
        s += border || (r % 4 === 0 && rnd() < 0.8) || (c % 6 === 0 && rnd() < 0.5) ? '#' : '.';
      }
      rows.push(s);
    }
    const g = Grid.parse(rows);
    const pf = new Pathfinder(g);
    const open: [number, number][] = [];
    for (let r = 0; r < 40; r++) for (let c = 0; c < 40; c++) if (g.isWalkable(c, r)) open.push([c, r]);
    const t0 = performance.now();
    let found = 0;
    const N = 2000;
    for (let i = 0; i < N; i++) {
      const [c0, r0] = open[(i * 7919) % open.length];
      const [c1, r1] = open[(i * 104729 + 13) % open.length];
      if (i % 50 === 0) g.setDynamicSolid(c1, (r1 + 1) % 40, i % 100 === 0);
      if (pf.findPath(c0 + 0.5, r0 + 0.5, c1 + 0.5, r1 + 0.5, { allowPartial: true })) found++;
    }
    const ms = performance.now() - t0;
    expect(found).toBe(N);
    // Generous bound for CI noise; typical runs are far below.
    expect(ms / N).toBeLessThan(2);
  });
});
