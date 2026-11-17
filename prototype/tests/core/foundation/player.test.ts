import { describe, expect, it } from 'vitest';
import { Grid } from '../../../src/core/grid';
import {
  actionTiming,
  dodgeIframeWindow,
  effectTick,
  idleInput,
  meleeHitWindow,
  PlayerController,
  rangedLaunchTick,
  type PlayerStepResult,
} from '../../../src/core/player';
import { TapeRecorder, tapesEqual } from '../../../src/core/tape';
import { BASE } from '../../../src/core/tuning';
import type { PlayerInput, ResolvedLoadout, Tape, TapeEvent } from '../../../src/core/types';
import { OPEN_ROOM } from '../../helpers/levels';
import { baseLoadout } from '../../helpers/loadout';

const BIG_ROOM = Grid.parse([
  '##############################',
  ...Array.from({ length: 12 }, () => '#............................#'),
  '##############################',
]);

function input(p: Partial<PlayerInput> = {}): PlayerInput {
  return { ...idleInput(), ...p };
}

function run(
  ctl: PlayerController,
  inputs: (t: number) => Partial<PlayerInput>,
  n: number,
  grid: Grid = BIG_ROOM,
  loadout: ResolvedLoadout = baseLoadout(),
): PlayerStepResult[] {
  const out: PlayerStepResult[] = [];
  for (let i = 0; i < n; i++) out.push(ctl.step(input(inputs(ctl.tick)), grid, loadout, 'alive'));
  return out;
}

function allEvents(steps: PlayerStepResult[]): TapeEvent[] {
  return steps.flatMap((s) => s.events);
}

describe('locomotion', () => {
  it('accelerates to run speed quickly and holds it', () => {
    const ctl = new PlayerController({ x: 3, y: 6 });
    const steps = run(ctl, () => ({ moveX: 1 }), 60);
    const reachTick = steps.findIndex((s) => s.vx >= BASE.runSpeed - 1e-9);
    expect(reachTick).toBeGreaterThan(0);
    expect(reachTick).toBeLessThanOrEqual(8); // ~0.13 s
    expect(steps[59].vx).toBeCloseTo(BASE.runSpeed, 9);
    expect(steps[59].x - steps[58].x).toBeCloseTo(BASE.runSpeed / 60, 5);
    expect(steps[59].anim).toBe('run');
    // One local second of running covers close to runSpeed tiles.
    expect(steps[59].x - 3).toBeGreaterThan(BASE.runSpeed - 0.5);
  });

  it('brakes to a full stop with no input', () => {
    const ctl = new PlayerController({ x: 3, y: 6 });
    run(ctl, () => ({ moveX: 1 }), 30);
    const steps = run(ctl, () => ({}), 30);
    const stopTick = steps.findIndex((s) => s.vx === 0 && s.vy === 0);
    expect(stopTick).toBeGreaterThanOrEqual(0);
    expect(stopTick).toBeLessThanOrEqual(10);
    expect(steps[29].anim).toBe('idle');
  });

  it('clamps diagonal input to unit length', () => {
    const ctl = new PlayerController({ x: 3, y: 3 });
    const s = run(ctl, () => ({ moveX: 1, moveY: 1 }), 60)[59];
    expect(Math.hypot(s.vx, s.vy)).toBeCloseTo(BASE.runSpeed, 6);
  });

  it('momentum retention gear carries more sideways velocity through a turn', () => {
    const turn = (ret: number): number => {
      const ctl = new PlayerController({ x: 3, y: 3 });
      const lo = baseLoadout({ mods: { momentumRetention: ret } });
      run(ctl, () => ({ moveX: 1 }), 30, BIG_ROOM, lo);
      return run(ctl, () => ({ moveY: 1 }), 4, BIG_ROOM, lo)[3].vx;
    };
    expect(turn(2)).toBeGreaterThan(turn(1));
    expect(turn(1)).toBeGreaterThan(0);
  });

  it('moveSpeed gear raises top speed', () => {
    const ctl = new PlayerController({ x: 3, y: 6 });
    const s = run(ctl, () => ({ moveX: 1 }), 60, BIG_ROOM, baseLoadout({ mods: { moveSpeed: 1.5 } }))[59];
    expect(s.vx).toBeCloseTo(BASE.runSpeed * 1.5, 9);
  });

  it('turns to face the movement direction', () => {
    const ctl = new PlayerController({ x: 3, y: 6, facing: 0 });
    const s = run(ctl, () => ({ moveY: -1 }), 10);
    expect(s[9].facing).toBeCloseTo(-Math.PI / 2, 6);
    expect(Math.abs(s[0].facing)).toBeLessThan(Math.PI / 2); // turned, not snapped
  });

  it('stores float32-exact positions so live state equals the tape', () => {
    const ctl = new PlayerController({ x: 3.1, y: 6.3 });
    for (const s of run(ctl, (t) => ({ moveX: Math.sin(t / 7), moveY: Math.cos(t / 5) }), 120)) {
      expect(Math.fround(s.x)).toBe(s.x);
      expect(Math.fround(s.y)).toBe(s.y);
      expect(Math.fround(s.facing)).toBe(s.facing);
    }
  });
});

describe('collision', () => {
  it('stops at walls and slides along them', () => {
    const g = Grid.parse(OPEN_ROOM);
    const ctl = new PlayerController({ x: 6, y: 5 });
    const s = run(ctl, () => ({ moveX: 1, moveY: -0.3 }), 120, g);
    const last = s[s.length - 1];
    expect(last.x).toBeCloseTo(11 - BASE.actorRadius, 2);
    expect(last.x).toBeLessThan(11 - BASE.actorRadius);
    expect(last.y).toBeLessThan(5);
    // Pushing into the wall kills the normal velocity only.
    expect(last.vx).toBeCloseTo(0, 6);
    expect(g.isSolidAt(last.x, last.y, BASE.actorRadius)).toBe(false);
  });

  it('runs down a 1-tile corridor without snagging', () => {
    const g = Grid.parse(['##########', '#........#', '####.#####', '####.#####', '####.#####', '####.#####', '#........#', '##########']);
    const ctl = new PlayerController({ x: 4.5, y: 1.5 });
    const s = run(ctl, () => ({ moveY: 1 }), 80, g);
    expect(s[s.length - 1].y).toBeGreaterThan(6.4);
    for (const p of s) expect(g.isSolidAt(p.x, p.y, BASE.actorRadius)).toBe(false);
  });

  it('enters a corridor from an angle by sliding off the corner', () => {
    const g = Grid.parse(['##########', '#........#', '####.#####', '####.#####', '#........#', '##########']);
    const ctl = new PlayerController({ x: 4.3, y: 1.5 });
    const s = run(ctl, () => ({ moveY: 1 }), 80, g);
    expect(s[s.length - 1].y).toBeGreaterThan(4.4);
  });

  it('recording ghosts are still blocked by walls (GHOST-02, TEST-08)', () => {
    const g = Grid.parse(['#####', '#...#', '#####']);
    g.setDynamicSolid(2, 1, true); // closed door
    const ctl = new PlayerController({ x: 1.5, y: 1.5 });
    let s: PlayerStepResult | null = null;
    for (let i = 0; i < 60; i++) s = ctl.step(input({ moveX: 1 }), g, baseLoadout(), 'recGhost');
    expect(s!.x).toBeLessThan(2 - BASE.actorRadius + 1e-6);
  });
});

describe('actions', () => {
  it('light attack: event, phases, facing lock and slowdown follow actionTiming', () => {
    const lo = baseLoadout();
    const tm = actionTiming('light', lo);
    expect([tm.activeStart, tm.activeEnd, tm.commit]).toEqual([6, 10, 20]);
    const ctl = new PlayerController({ x: 5, y: 6 });
    run(ctl, () => ({ moveX: 1 }), 30);
    const t0 = ctl.tick;
    const steps = run(ctl, (t) => ({ moveY: 1, light: t === t0, aim: 0.7 }), 30, BIG_ROOM, lo);
    const evs = allEvents(steps);
    expect(evs).toHaveLength(1);
    expect(evs[0]).toMatchObject({ tick: t0, kind: 'light' });
    expect(evs[0].dir).toBeCloseTo(0.7, 12);
    expect(evs[0].vx).toBeCloseTo(BASE.runSpeed, 9); // velocity when the swing started (momentum input)
    const anims = steps.map((s) => s.anim);
    expect(anims.slice(0, 6).every((a) => a === 'lightWindup')).toBe(true);
    expect(anims.slice(6, 10).every((a) => a === 'lightActive')).toBe(true);
    expect(anims.slice(10, 20).every((a) => a === 'lightRecover')).toBe(true);
    expect(anims[20]).toBe('run');
    for (let i = 0; i < 10; i++) expect(steps[i].facing).toBeCloseTo(0.7, 6);
    expect(meleeHitWindow(evs[0], lo)).toEqual({ start: t0 + 6, end: t0 + 10 });
    expect(effectTick(evs[0], lo)).toBe(t0 + 6);
    // Speed is pulled toward moveMul × run speed while committed.
    expect(Math.hypot(steps[19].vx, steps[19].vy)).toBeLessThan(BASE.runSpeed * 0.5 + 0.05);
  });

  it('heavy attack uses the heavy swing timing', () => {
    const lo = baseLoadout();
    const ctl = new PlayerController({ x: 5, y: 6 });
    const steps = run(ctl, (t) => ({ heavy: t === 0 }), 45, BIG_ROOM, lo);
    expect(steps.filter((s) => s.anim === 'heavyWindup')).toHaveLength(16);
    expect(steps.filter((s) => s.anim === 'heavyActive')).toHaveLength(5);
    expect(steps.filter((s) => s.anim === 'heavyRecover')).toHaveLength(18);
    expect(meleeHitWindow(allEvents(steps)[0], lo)).toEqual({ start: 16, end: 21 });
  });

  it('buffers a press during recovery for a few ticks, but not forever', () => {
    const lo = baseLoadout();
    const ctl = new PlayerController({ x: 5, y: 6 });
    // Light at 0 (free again at 20); heavy pressed at 14 is buffered and starts at 20.
    const s1 = run(ctl, (t) => ({ light: t === 0, heavy: t === 14 }), 40, BIG_ROOM, lo);
    expect(allEvents(s1).map((e) => [e.kind, e.tick])).toEqual([
      ['light', 0],
      ['heavy', 20],
    ]);
    // Pressed at 11: 9 ticks before free, longer than the buffer: dropped.
    const ctl2 = new PlayerController({ x: 5, y: 6 });
    const s2 = run(ctl2, (t) => ({ light: t === 0 || t === 11 }), 40, BIG_ROOM, lo);
    expect(allEvents(s2).map((e) => e.tick)).toEqual([0]);
  });

  it('dodge: dash distance, i-frames and cooldown', () => {
    const lo = baseLoadout();
    const tm = actionTiming('dodge', lo);
    const ctl = new PlayerController({ x: 5, y: 6 });
    const steps = run(ctl, (t) => ({ moveX: t < 14 ? 1 : 0, dodge: t === 0 || t === 20 || t === 30 }), 80, BIG_ROOM, lo);
    const evs = allEvents(steps);
    // The press at 20 expires in the buffer before the cooldown ends; the one at 30 waits for it.
    expect(evs.map((e) => e.tick)).toEqual([0, tm.cooldown]);
    expect(tm.cooldown).toBe(BASE.dodgeTicks + BASE.dodgeCooldown);
    // The dash covers the dodge distance.
    expect(steps[BASE.dodgeTicks - 1].x - 5).toBeCloseTo(BASE.dodgeDistance, 4);
    const win = dodgeIframeWindow(evs[0], lo)!;
    expect(win).toEqual({ start: 1, end: 1 + BASE.dodgeIframes });
    steps.slice(0, 20).forEach((s, i) => expect(s.iframes).toBe(i >= win.start && i < win.end));
    expect(steps.slice(0, BASE.dodgeTicks).every((s) => s.anim === 'dodge')).toBe(true);
  });

  it('dodge goes along facing when idle and scales with gear', () => {
    const lo = baseLoadout({ mods: { dodgeDistance: 1.5, dodgeIframes: 2, dodgeCooldown: 0.5 } });
    const ctl = new PlayerController({ x: 10, y: 6, facing: Math.PI });
    const steps = run(ctl, (t) => ({ dodge: t === 0 }), 20, BIG_ROOM, lo);
    expect(10 - steps[BASE.dodgeTicks - 1].x).toBeCloseTo(BASE.dodgeDistance * 1.5, 5);
    expect(allEvents(steps)[0].dir).toBeCloseTo(Math.PI, 6);
    const tm = actionTiming('dodge', lo);
    expect(tm.iframeEnd - tm.iframeStart).toBe(BASE.dodgeIframes * 2);
    expect(tm.cooldown).toBe(BASE.dodgeTicks + Math.round(BASE.dodgeCooldown * 0.5));
  });

  it('a buffered dodge cancels melee recovery but not windup', () => {
    const ctl = new PlayerController({ x: 5, y: 6 });
    const steps = run(ctl, (t) => ({ light: t === 0, dodge: t === 3 || t === 12 }), 30);
    // Dodge at 3 is buffered (windup) until 10, when recovery begins and it may cancel.
    expect(allEvents(steps).map((e) => [e.kind, e.tick])).toEqual([
      ['light', 0],
      ['dodge', 10],
    ]);
  });

  it('phaseDodge crosses low barriers; a normal dodge does not', () => {
    const g = Grid.parse(['#######', '#..=..#', '#######']);
    const plain = new PlayerController({ x: 1.5, y: 1.5 });
    const a = run(plain, (t) => ({ moveX: 1, dodge: t === 0 }), 20, g);
    expect(a[19].x).toBeLessThan(3);
    const phase = new PlayerController({ x: 1.5, y: 1.5 });
    const b = run(phase, (t) => ({ moveX: 1, dodge: t === 0 }), 20, g, baseLoadout({ abilities: ['phaseDodge'] }));
    expect(b[19].x).toBeGreaterThan(4);
  });

  it('ranged: launch tick, commit and cooldown', () => {
    const lo = baseLoadout();
    const tm = actionTiming('ranged', lo);
    expect(tm.effect).toBe(BASE.rangedLaunchDelay);
    expect(tm.cooldown).toBe(45);
    const ctl = new PlayerController({ x: 5, y: 6 });
    const steps = run(ctl, (t) => ({ ranged: t === 0 || t === 40, aim: -1 }), 60, BIG_ROOM, lo);
    const evs = allEvents(steps);
    expect(evs.map((e) => e.tick)).toEqual([0, 45]);
    expect(rangedLaunchTick(evs[0], lo)).toBe(BASE.rangedLaunchDelay);
    expect(steps.slice(0, 12).every((s) => s.anim === 'ranged')).toBe(true);
    expect(steps[0].facing).toBeCloseTo(-1, 6);
    expect(meleeHitWindow(evs[0], lo)).toBeNull();
    expect(dodgeIframeWindow(evs[0], lo)).toBeNull();
    expect(actionTiming('ranged', baseLoadout({ mods: { rangedCooldown: 0.5 } })).cooldown).toBe(23);
  });

  it('interact and ability', () => {
    const ctl = new PlayerController({ x: 5, y: 6 });
    const steps = run(ctl, (t) => ({ interact: t === 2, ability: t === 3 }), 20);
    expect(allEvents(steps).map((e) => e.kind)).toEqual(['interact']); // no active ability equipped
    expect(steps[2].anim).toBe('interact');
    const ctl2 = new PlayerController({ x: 5, y: 6 });
    const s2 = run(ctl2, (t) => ({ ability: t === 3, light: t === 3 }), 20, BIG_ROOM, baseLoadout({ abilities: ['manualDesync'] }));
    expect(allEvents(s2).map((e) => [e.kind, e.tick])).toEqual([
      ['ability', 3],
      ['light', 3],
    ]);
  });

  it('records the pre-step position and velocity on events', () => {
    const ctl = new PlayerController({ x: 5, y: 6 });
    run(ctl, () => ({ moveX: 1 }), 20);
    const before = ctl.pose;
    const s = ctl.step(input({ moveX: 1, light: true }), BIG_ROOM, baseLoadout(), 'alive');
    expect(s.events[0]).toMatchObject({ tick: 20, x: before.x, y: before.y, vx: before.vx, vy: before.vy });
  });

  it('killRefresh: refreshDodge clears the cooldown', () => {
    const ctl = new PlayerController({ x: 5, y: 6 });
    run(ctl, (t) => ({ dodge: t === 0 }), 16);
    expect(ctl.dodgeCooldown).toBeGreaterThan(0);
    ctl.refreshDodge();
    expect(ctl.dodgeCooldown).toBe(0);
    const s = ctl.step(input({ dodge: true }), BIG_ROOM, baseLoadout(), 'alive');
    expect(s.events[0].kind).toBe('dodge');
  });
});

describe('determinism', () => {
  function record(seed: number, loadout = baseLoadout()): Tape {
    let s = seed;
    const rnd = (): number => {
      s = (s * 1664525 + 1013904223) >>> 0;
      return s / 0x100000000;
    };
    const g = Grid.parse([
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
    for (let i = 0; i < ticks; i++) {
      if (i % 9 === 0) {
        mx = rnd() * 2 - 1;
        my = rnd() * 2 - 1;
      }
      const r = rnd();
      const res = ctl.step(
        {
          moveX: mx,
          moveY: my,
          aim: rnd() * 6.28 - 3.14,
          light: r < 0.03,
          heavy: r >= 0.03 && r < 0.045,
          dodge: r >= 0.045 && r < 0.07,
          ranged: r >= 0.07 && r < 0.08,
          interact: r >= 0.08 && r < 0.09,
          ability: r >= 0.09 && r < 0.095,
        },
        g,
        loadout,
        i < 300 ? 'alive' : 'recGhost',
      );
      for (const e of res.events) rec.addEvent(e);
      rec.push(res.x, res.y, res.facing, res.anim);
      expect(g.isSolidAt(res.x, res.y, BASE.actorRadius)).toBe(false);
    }
    return rec.finish();
  }

  it('same inputs produce bit-identical tapes', () => {
    const a = record(42);
    const b = record(42);
    expect(tapesEqual(a, b)).toBe(true);
    expect(a.events.length).toBeGreaterThan(10);
    expect(tapesEqual(a, record(43))).toBe(false);
  });

  it('gear changes the tape (loadout is an input)', () => {
    expect(tapesEqual(record(5), record(5, baseLoadout({ mods: { moveSpeed: 1.2 } })))).toBe(false);
  });
});
