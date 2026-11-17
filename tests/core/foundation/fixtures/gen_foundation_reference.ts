// Generates tests/core/foundation/fixtures/foundation_reference.json from the prototype.
// Run from the repo root: cd prototype && npx vite-node ../tests/core/foundation/fixtures/gen_foundation_reference.ts
// Doubles are stored as base64 little-endian Float64 bytes so Godot's float parser cannot round them.
import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { Grid } from '../../../../prototype/src/core/grid';
import { Pathfinder } from '../../../../prototype/src/core/path';
import { PlayerController } from '../../../../prototype/src/core/player';
import { TapeRecorder, serializeTape } from '../../../../prototype/src/core/tape';
import { baseLoadout } from '../../../../prototype/tests/helpers/loadout';
import type { ResolvedLoadout } from '../../../../prototype/src/core/types';

const DIR = fileURLToPath(new URL('.', import.meta.url));
const OUT = DIR + 'foundation_reference.json';

function f64(values: number[]): string {
  const b = new Uint8Array(new Float64Array(values).buffer);
  return Buffer.from(b).toString('base64');
}

// ── path: the performance-test maze, first 500 plans ──
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
const plans: { found: boolean; complete: boolean; expanded: number; cost: string; points: string }[] = [];
for (let i = 0; i < 500; i++) {
  const [c0, r0] = open[(i * 7919) % open.length];
  const [c1, r1] = open[(i * 104729 + 13) % open.length];
  if (i % 50 === 0) g.setDynamicSolid(c1, (r1 + 1) % 40, i % 100 === 0);
  // Alternate smoothing on/off and use a non-centre goal every third plan.
  const tx = c1 + (i % 3 === 0 ? 0.25 : 0.5);
  const ty = r1 + (i % 3 === 0 ? 0.8 : 0.5);
  const res = pf.findPath(c0 + 0.5, r0 + 0.5, tx, ty, { allowPartial: true, smooth: i % 2 === 0 });
  plans.push({
    found: !!res,
    complete: res ? res.complete : false,
    expanded: pf.lastExpanded,
    cost: f64([res ? res.cost : 0]),
    points: f64(res ? res.points.flatMap((p) => [p.x, p.y]) : []),
  });
}

// ── grid: the random fast-motion walk, every position ──
const walkGrid = Grid.parse([
  '############',
  '#....#.....#',
  '#.##.#.##..#',
  '#.#..=..#..#',
  '#.#.###.#..#',
  '#...# ..#..#',
  '############',
]);
let s2 = 7;
const rnd2 = (): number => {
  s2 = (s2 * 1664525 + 1013904223) >>> 0;
  return s2 / 0x100000000;
};
let x = 1.5;
let y = 1.5;
const walk: number[] = [];
const walkInputs: number[] = [];
for (let i = 0; i < 4000; i++) {
  const a = rnd2() * Math.PI * 2;
  const d = rnd2() * 1.5;
  const dx = Math.cos(a) * d;
  const dy = Math.sin(a) * d;
  walkInputs.push(a, d, dx, dy);
  const r = walkGrid.moveCircle(x, y, dx, dy, 0.3);
  x = r.x;
  y = r.y;
  walk.push(x, y);
}

// ── player: the determinism recording ──
function record(seedIn: number, loadout: ResolvedLoadout = baseLoadout()) {
  let s = seedIn;
  const rnd3 = (): number => {
    s = (s * 1664525 + 1013904223) >>> 0;
    return s / 0x100000000;
  };
  const grid = Grid.parse([
    '################',
    '#......#.......#',
    '#..==..#..##...#',
    '#......=.......#',
    '#..#.......#...#',
    '#..#..###..#...#',
    '#..............#',
    '################',
  ]);
  const ctl = new PlayerController({ x: 2, y: 2, facing: 0 });
  const ticks = 600;
  const rec = new TapeRecorder({ index: 0, speed: 2, endMode: 'stop', ticks, start: { x: ctl.pose.x, y: ctl.pose.y, facing: ctl.pose.facing } });
  let mx = 0;
  let my = 0;
  const vel: number[] = [];
  for (let i = 0; i < ticks; i++) {
    if (i % 9 === 0) {
      mx = rnd3() * 2 - 1;
      my = rnd3() * 2 - 1;
    }
    const r = rnd3();
    const res = ctl.step(
      {
        moveX: mx,
        moveY: my,
        aim: rnd3() * 6.28 - 3.14,
        light: r < 0.03,
        heavy: r >= 0.03 && r < 0.045,
        dodge: r >= 0.045 && r < 0.07,
        ranged: r >= 0.07 && r < 0.08,
        interact: r >= 0.08 && r < 0.09,
        ability: r >= 0.09 && r < 0.095,
      },
      grid,
      loadout,
      i < 300 ? 'alive' : 'recGhost',
    );
    for (const e of res.events) rec.addEvent(e);
    rec.push(res.x, res.y, res.facing, res.anim);
    vel.push(res.vx, res.vy);
  }
  return { tape: serializeTape(rec.finish()), velocities: f64(vel) };
}

writeFileSync(
  OUT,
  JSON.stringify({
    generator: 'prototype core (grid.ts, path.ts, player.ts, tape.ts); doubles are base64 Float64 LE',
    node: process.version,
    path: plans,
    walk: f64(walk),
    walkInputs: f64(walkInputs),
    player42: record(42),
    player5fast: record(5, baseLoadout({ mods: { moveSpeed: 1.2 } })),
  }),
);
console.log('wrote', OUT);
