import { describe, expect, it } from 'vitest';
import { Grid, MapParseError, TILE_FLOOR, TILE_GRATE, TILE_LOW, TILE_VOID, TILE_WALL } from '../../../src/core/grid';
import { COLLISION_SKIN } from '../../../src/core/tuning';

const R = 0.3;

describe('parsing', () => {
  it('reads every documented tile character and pads short rows with void', () => {
    const g = Grid.parse(['#.= :,~', '#.']);
    expect(g.cols).toBe(7);
    expect(g.rows).toBe(2);
    expect(g.tileAt(0, 0)).toBe(TILE_WALL);
    expect(g.tileAt(1, 0)).toBe(TILE_FLOOR);
    expect(g.tileAt(2, 0)).toBe(TILE_LOW);
    expect(g.tileAt(3, 0)).toBe(TILE_VOID);
    expect(g.tileAt(4, 0)).toBe(TILE_GRATE);
    expect(g.tileAt(5, 1)).toBe(TILE_VOID);
    expect(g.tileAt(-1, 0)).toBe(TILE_WALL);
    expect(g.toString()).toBe('#.= :,~\n#.     ');
  });

  it('rejects unknown characters with their position', () => {
    try {
      Grid.parse(['##', '#D']);
      throw new Error('expected a throw');
    } catch (e) {
      expect(e).toBeInstanceOf(MapParseError);
      expect((e as MapParseError).c).toBe(1);
      expect((e as MapParseError).r).toBe(1);
    }
    expect(() => Grid.parse([])).toThrow(MapParseError);
  });
});

describe('solidity', () => {
  const g = Grid.parse(['#####', '#.= #', '#####']);

  it('separates movement solidity from projectile solidity', () => {
    expect(g.isWalkable(1, 1)).toBe(true);
    expect(g.isWalkable(2, 1)).toBe(false); // low barrier blocks movement
    expect(g.blocksShot(2, 1)).toBe(false); // …not projectiles
    expect(g.isWalkable(3, 1)).toBe(false); // void is impassable…
    expect(g.blocksShot(3, 1)).toBe(false); // …but does not block shots
    expect(g.blocksShot(0, 0)).toBe(true);
    expect(g.blocksMove(2, 1, true)).toBe(false); // phaseDodge ignores low barriers
    expect(g.blocksMove(3, 1, true)).toBe(true); // but never void
    expect(g.blocksMove(99, 99)).toBe(true);
    expect(g.blocksShot(-1, 1)).toBe(true);
  });

  it('dynamic overlay blocks both and bumps the revision only on change', () => {
    const d = Grid.parse(['.....']);
    const r0 = d.revision;
    d.setDynamicSolid(2, 0, true);
    expect(d.revision).toBe(r0 + 1);
    d.setDynamicSolid(2, 0, true);
    expect(d.revision).toBe(r0 + 1);
    expect(d.isWalkable(2, 0)).toBe(false);
    expect(d.blocksShot(2, 0)).toBe(true);
    expect(d.isStaticWalkable(2, 0)).toBe(true);
    expect(d.lineOfSight({ x: 0.5, y: 0.5 }, { x: 4.5, y: 0.5 })).toBe(false);
    d.setDynamicSolid(2, 0, false);
    expect(d.lineOfSight({ x: 0.5, y: 0.5 }, { x: 4.5, y: 0.5 })).toBe(true);
    d.setDynamicSolid(9, 9, true); // out of bounds: ignored
    expect(d.revision).toBe(r0 + 2);
    d.setDynamicSolid(1, 0, true);
    d.clearDynamic();
    expect(d.isWalkable(1, 0)).toBe(true);
  });

  it('isSolidAt tests circle overlap, touching is not overlap', () => {
    expect(g.isSolidAt(1.5, 1.5, R)).toBe(false);
    expect(g.isSolidAt(1.25, 1.5, R)).toBe(true); // into the wall at x = 1
    expect(g.isSolidAt(1.3, 1.5, R)).toBe(false); // exactly touching
    expect(g.isSolidAt(1.5, 1.5, 0.6)).toBe(true);
    expect(g.isSolidAt(1.5, 1.5, 0)).toBe(false);
    expect(g.isSolidAt(1.75, 1.5, R)).toBe(true); // low barrier at x = 2
    expect(g.isSolidAt(1.75, 1.5, R, { ignoreLow: true })).toBe(false);
  });
});

describe('moveCircle', () => {
  const room = Grid.parse(['##########', '#........#', '#........#', '#........#', '#........#', '##########']);

  it('is exact when nothing blocks', () => {
    const r = room.moveCircle(3, 3, 0.37, -0.11, R);
    expect(r).toEqual({ x: 3.37, y: 2.89, blocked: false });
  });

  it('stops at a wall with the collision skin', () => {
    const r = room.moveCircle(8, 3, 2, 0, R);
    expect(r.blocked).toBe(true);
    expect(r.x).toBeCloseTo(9 - R - COLLISION_SKIN, 9);
    expect(r.y).toBe(3);
  });

  it('slides along a wall made of several tiles without seam bumps', () => {
    // Hug the top wall (y = 1) and push diagonally into it across many tile seams.
    let x = 1.5;
    let y = 1 + R + COLLISION_SKIN;
    for (let i = 0; i < 60; i++) {
      const r = room.moveCircle(x, y, 0.1, -0.05, R);
      expect(r.y).toBeCloseTo(1 + R + COLLISION_SKIN, 9);
      expect(r.x).toBeCloseTo(x + 0.1, 9);
      x = r.x;
      y = r.y;
      if (x > 8) break;
    }
  });

  it('slides out of an inside corner without sticking or penetrating', () => {
    let x = 7;
    let y = 3;
    for (let i = 0; i < 40; i++) {
      const r = room.moveCircle(x, y, 0.2, -0.2, R);
      x = r.x;
      y = r.y;
      expect(room.isSolidAt(x, y, R)).toBe(false);
    }
    expect(x).toBeCloseTo(9 - R - COLLISION_SKIN, 6);
    expect(y).toBeCloseTo(1 + R + COLLISION_SKIN, 6);
  });

  it('cannot tunnel through a 1-tile wall at any speed', () => {
    const g = Grid.parse(['#######', '#..#..#', '#..#..#', '#######']);
    for (const dist of [1.25, 2, 3.5, 10, 100]) {
      const r = g.moveCircle(1.5, 1.5, dist, 0, R);
      expect(r.x).toBeLessThan(3);
      expect(r.x).toBeCloseTo(3 - R - COLLISION_SKIN, 9);
      const back = g.moveCircle(5.5, 2.5, -dist, 0.3, R);
      expect(back.x).toBeGreaterThan(4);
    }
  });

  it('never leaves the walkable region under random fast motion (deterministic LCG)', () => {
    const g = Grid.parse([
      '############',
      '#....#.....#',
      '#.##.#.##..#',
      '#.#..=..#..#',
      '#.#.###.#..#',
      '#...# ..#..#',
      '############',
    ]);
    let seed = 7;
    const rnd = (): number => {
      seed = (seed * 1664525 + 1013904223) >>> 0;
      return seed / 0x100000000;
    };
    let x = 1.5;
    let y = 1.5;
    for (let i = 0; i < 4000; i++) {
      const a = rnd() * Math.PI * 2;
      const d = rnd() * 1.5;
      const r = g.moveCircle(x, y, Math.cos(a) * d, Math.sin(a) * d, R);
      // Never overlapping a solid and never on a non-walkable tile.
      expect(g.isSolidAt(r.x, r.y, R)).toBe(false);
      expect(g.isWalkable(Math.floor(r.x), Math.floor(r.y))).toBe(true);
      // Moves never cross a solid tile (no tunnelling): the straight segment stays clear for a point.
      expect(g.segmentBlocked(x, y, r.x, r.y, false) && Math.hypot(r.x - x, r.y - y) > 1.2).toBe(false);
      x = r.x;
      y = r.y;
    }
  });

  it('pushes a circle that starts overlapping (door closed on it) back into open space', () => {
    const g = Grid.parse(['#####', '#...#', '#####']);
    g.setDynamicSolid(2, 1, true);
    const r = g.moveCircle(2.4, 1.5, 0, 0, R);
    expect(r.blocked).toBe(true);
    expect(g.isSolidAt(r.x, r.y, R)).toBe(false);
  });

  it('phaseDodge crosses low barriers only', () => {
    const g = Grid.parse(['#####', '#.=.#', '#####']);
    expect(g.moveCircle(1.5, 1.5, 2, 0, R).x).toBeLessThan(2);
    expect(g.moveCircle(1.5, 1.5, 2, 0, R, { ignoreLow: true }).x).toBeCloseTo(3.5, 9);
  });
});

describe('sweeps and rays', () => {
  const g = Grid.parse(['#######', '#.....#', '#..#..#', '#.....#', '#######']);

  it('sweepCircleBlocked is exact against tile boxes', () => {
    expect(g.sweepCircleBlocked(1.5, 1.5, 5.5, 1.5, R)).toBe(false);
    expect(g.sweepCircleBlocked(1.5, 2.5, 5.5, 2.5, R)).toBe(true);
    // Passing the pillar corner with clearance just above/below the radius.
    expect(g.sweepCircleBlocked(1.5, 1.69, 5.5, 1.69, R)).toBe(false);
    expect(g.sweepCircleBlocked(1.5, 1.71, 5.5, 1.71, R)).toBe(true);
    expect(g.sweepCircleBlocked(1.5, 1.5, 5.5, 3.5, 0)).toBe(true);
  });

  it('segmentBlocked walks every tile on the segment', () => {
    expect(g.segmentBlocked(1.5, 1.5, 5.5, 1.5, true)).toBe(false);
    expect(g.segmentBlocked(1.5, 2.5, 5.5, 2.5, true)).toBe(true);
    expect(g.segmentBlocked(2.9, 1.5, 4.1, 3.5, true)).toBe(true);
    expect(g.segmentBlocked(3.5, 2.5, 3.5, 2.5, true)).toBe(true); // starts inside
  });

  it('exact diagonal corner crossings block only when both side tiles block', () => {
    const d = Grid.parse(['....', '.#..', '..#.', '....']);
    // Through the shared corner (2, 2) of the two diagonal walls: sealed.
    expect(d.segmentBlocked(1.5, 2.5, 2.5, 1.5, true)).toBe(true);
    const e = Grid.parse(['....', '.#..', '....', '....']);
    // Grazing the corner of a single wall tile: open.
    expect(e.segmentBlocked(1.5, 2.5, 2.5, 1.5, true)).toBe(false);
  });

  it('void and low barriers do not block sight; walls do', () => {
    const v = Grid.parse(['#####', '#. .#', '#.=.#', '#####']);
    expect(v.lineOfSight({ x: 1.5, y: 1.5 }, { x: 3.5, y: 1.5 })).toBe(true);
    expect(v.lineOfSight({ x: 1.5, y: 2.5 }, { x: 3.5, y: 2.5 })).toBe(true);
    expect(v.segmentBlocked(1.5, 1.5, 3.5, 1.5, false)).toBe(true); // but not walkable
    expect(v.lineOfSight({ x: 1.5, y: 1.5 }, { x: 5.5, y: 1.5 })).toBe(false); // out of bounds past the wall
  });

  it('raycast reports distance, tile and normal', () => {
    const hit = g.raycast(1.5, 2.5, 1, 0, 10, true);
    expect(hit.hit).toBe(true);
    expect(hit.c).toBe(3);
    expect(hit.r).toBe(2);
    expect(hit.dist).toBeCloseTo(1.5, 12);
    expect(hit.x).toBeCloseTo(3, 12);
    expect([hit.nx, hit.ny]).toEqual([-1, 0]);
    const up = g.raycast(4.5, 3.5, 0, -2, 10, true);
    expect(up.dist).toBeCloseTo(2.5, 12);
    expect([up.c, up.r, up.nx, up.ny]).toEqual([4, 0, 0, 1]);
    const miss = g.raycast(1.5, 1.5, 1, 0, 2, true);
    expect(miss.hit).toBe(false);
    expect(miss.dist).toBe(2);
    expect(miss.x).toBeCloseTo(3.5, 12);
    const diag = g.raycast(1.5, 1.5, 1, 1, 10, true);
    expect(diag.hit).toBe(true);
    expect(diag.dist).toBeCloseTo(Math.SQRT2 * 2.5, 9);
  });

  it('nearestWalkable finds the closest open tile deterministically', () => {
    const n = g.nearestWalkable(3, 2);
    expect([n % g.cols, Math.floor(n / g.cols)]).toEqual([3, 1]);
    expect(g.nearestWalkable(2, 2)).toBe(g.index(2, 2));
    const solid = Grid.parse(['###', '###', '###']);
    expect(solid.nearestWalkable(1, 1, 3)).toBe(-1);
  });
});
