/**
 * The level tools themselves (prototype/scripts/lib): the plan language compiles to the timing it
 * promises, the solution format round-trips, and the reports say what happened.
 */
import { describe, expect, it } from 'vitest';
import { campaignOrderProblems, levelFileProblems } from '../../src/content/levelFiles';
import { actionTiming } from '../../src/core/player';
import { TUTORIAL_WALL_THRESHOLD } from '../../src/core/tuning';
import type { LevelDef, PlayerInput } from '../../src/core/types';
import { frameAtBeat, renderFrame, renderStatic } from '../../scripts/lib/ascii';
import { probeLines, runDistanceInBeats, swingNumbers } from '../../scripts/lib/probe';
import { describeEvent, eventDiffLines, showLines, stepLines } from '../../scripts/lib/report';
import { compiledSolution, mutationVariants, replayStoredInputs, replayStoredTapes, runSolution, sameOutcome, verifyGenerated } from '../../scripts/lib/run';
import {
  baselineLoadout,
  checkSolution,
  decodeInputs,
  encodeInputs,
  formatSolution,
  parseTime,
  solutionLoadoutIds,
  staleReasons,
  usesBaseline,
  type PlanStep,
  type SolutionFile,
} from '../../scripts/lib/solution';
import { makeLevel } from '../helpers/levels';

/** A 12x10 open room at 120 bpm (30 local ticks per beat), 4 bars; start in the middle at (6, 5). */
function room(partial: Partial<LevelDef> = {}): LevelDef {
  return makeLevel({ id: 'tools', briefing: ['test'], ...partial });
}

function solo(level: LevelDef, plan: PlanStep[], speed: 0.5 | 1 | 2 | 4 = 1): SolutionFile {
  return { level: level.id, takes: [{ speed, endMode: 'stop', note: 'test take', plan }] };
}

describe('plan language', () => {
  it('reads time values: master beats, local ticks, local beats', () => {
    expect(parseTime(6)).toEqual({ unit: 'beat', n: 6 });
    expect(parseTime('90t')).toEqual({ unit: 'tick', n: 90 });
    expect(parseTime('3lb')).toEqual({ unit: 'localBeat', n: 3 });
    expect(parseTime('soon')).toBeNull();
    expect(parseTime(-1)).toBeNull();
  });

  it('presses on exactly the tick a master beat falls on, at every speed', () => {
    for (const speed of [0.5, 1, 2, 4] as const) {
      const level = room();
      const run = runSolution(level, solo(level, [{ at: 3, press: 'light', aim: 'E' }], speed));
      // 30 ticks per beat at 120 bpm; a tape at speed s lives s local beats per master beat.
      expect(run.tapes[0].events.map((e) => [e.kind, e.tick])).toEqual([['light', 3 * 30 * speed]]);
      expect(run.tapes[0].events[0].dir).toBeCloseTo(0, 3);
      expect(run.warnings).toEqual([]);
    }
  });

  it('landAt presses early enough for the hit frame to open on the beat', () => {
    const level = room();
    const run = runSolution(level, solo(level, [{ landAt: 4, press: 'heavy', aim: 'S' }], 2));
    const windup = actionTiming('heavy', baselineLoadout()).effect;
    expect(run.tapes[0].events[0].tick).toBe(4 * 60 - windup);
    const swing = run.resolution.events.find((e) => e.type === 'swing')!;
    expect(swing.sub / 120).toBeCloseTo(4, 6);
    expect(swing.dir).toBeCloseTo(Math.PI / 2, 3);
  });

  it('understands ticks and local beats as well as master beats', () => {
    const level = room();
    const run = runSolution(level, solo(level, [{ at: '45t', press: 'light' }, { at: '4lb', press: 'light' }, { waitUntilTick: 200 }, { press: 'interact' }], 2));
    expect(run.tapes[0].events.map((e) => e.tick)).toEqual([45, 120, 200]);
  });

  it('goto stops on the spot and a press after it is a true standing press', () => {
    const level = room();
    const run = runSolution(level, solo(level, [{ goto: [9.5, 5] }, { press: 'heavy', aim: 'E' }]));
    const ev = run.tapes[0].events[0];
    expect(Math.hypot(ev.x - 9.5, ev.y - 5)).toBeLessThan(0.12);
    expect(ev.vx).toBe(0);
    expect(ev.vy).toBe(0);
  });

  it('via keeps running, so a press on arrival carries the run-up', () => {
    const level = room({ start: { x: 2, y: 5 } });
    const run = runSolution(level, solo(level, [{ via: [8, 5], press: 'heavy' }]));
    const ev = run.tapes[0].events[0];
    expect(ev.vx).toBeGreaterThan(4);
    expect(ev.dir).toBeCloseTo(0, 2);
    const swing = run.resolution.events.find((e) => e.type === 'swing')!;
    const standing = swingNumbers(baselineLoadout(), [1]).find((w) => w.kind === 'heavy' && !w.running)!;
    expect(swing.power!).toBeGreaterThan(standing.momentum * 1.4);
  });

  it('goto finds its way around walls', () => {
    const level = room({
      map: ['#########', '#...#...#', '#...#...#', '#...#...#', '#.......#', '#########'],
      start: { x: 1.5, y: 1.5 },
    });
    const run = runSolution(level, solo(level, [{ goto: [6.5, 1.5] }]));
    const step = run.logs[0].steps[0];
    expect(step.endTick).not.toBeNull();
    expect(Math.hypot(step.x - 6.5, step.y - 1.5)).toBeLessThan(0.12);
    expect(run.warnings).toEqual([]);
  });

  it('a goto through a closed door waits there and is reported, not silently skipped', () => {
    const level = room({
      map: ['#########', '#...#...#', '#.......#', '#...#...#', '#########'],
      start: { x: 1.5, y: 2.5 },
      entities: [
        { kind: 'switch', id: 'sw', x: 1.5, y: 1.5 },
        { kind: 'door', id: 'door', cells: [{ c: 4, r: 2 }], openWhen: { sig: 'sw' } },
        { kind: 'enemy', id: 'g', type: 'turret', x: 7.5, y: 1.5, wakeWhen: { const: false } },
      ],
    });
    const stuck = runSolution(level, solo(level, [{ goto: [6.5, 2.5] }, { press: 'light' }]));
    expect(stuck.logs[0].steps[0].endTick).toBeNull();
    expect(stuck.warnings.join('\n')).toMatch(/step 1 .*still in progress.*way was blocked/);
    expect(stuck.warnings.join('\n')).toMatch(/step 2 .*never reached/);
    // With the switch flipped first, the same goto walks through.
    const open = runSolution(level, solo(level, [{ goto: [2.2, 2.2], press: 'interact' }, { goto: [6.5, 2.5] }]));
    expect(open.logs[0].steps[1].endTick).not.toBeNull();
    expect(open.resolution.events.some((e) => e.type === 'door' && e.detail === 'open')).toBe(true);
  });

  it('waitFor reacts to the world: a grunt in reach, a door opening', () => {
    const level = room({ entities: [{ kind: 'enemy', id: 'g1', type: 'grunt', x: 10, y: 5 }] });
    const run = runSolution(level, solo(level, [{ waitFor: { near: 'g1', dist: 1.5 } }, { press: 'light', aim: 'g1' }]));
    expect(run.outcome.win).toBe(true);
    expect(run.resolution.events.some((e) => e.type === 'kill' && e.id === 'g1' && e.tape === 0)).toBe(true);
  });

  it('warns when a timed step is reached late and when a press is dropped', () => {
    const level = room();
    const late = runSolution(level, solo(level, [{ wait: 2 }, { at: 1, press: 'light' }]));
    expect(late.warnings.join('\n')).toMatch(/step 2 .*LATE: wanted tick 30, was free at tick 60/);
    const dropped = runSolution(level, solo(level, [{ press: 'ability' }]));
    expect(dropped.warnings.join('\n')).toMatch(/ability press on tick 0 was dropped/);
  });

  it('waits out a cooldown instead of losing the second dodge', () => {
    const level = room();
    const run = runSolution(level, solo(level, [{ press: 'dodge', aim: 'E' }, { press: 'dodge', aim: 'W' }]));
    const ticks = run.tapes[0].events.filter((e) => e.kind === 'dodge').map((e) => e.tick);
    expect(ticks).toEqual([0, actionTiming('dodge', baselineLoadout()).cooldown]);
    expect(run.warnings).toEqual([]);
  });

  it('reports a win that arrives before the last take', () => {
    const level = room({ entities: [{ kind: 'enemy', id: 'g1', type: 'grunt', x: 10, y: 5 }] });
    const sol = solo(level, [{ waitFor: { near: 'g1', dist: 1.5 } }, { press: 'light', aim: 'g1' }]);
    sol.takes.push({ speed: 1, endMode: 'stop', note: 'never needed', plan: [] });
    const run = runSolution(level, sol);
    expect(run.takesRecorded).toBe(1);
    expect(run.warnings.join('\n')).toMatch(/already wins after take 1/);
  });
});

describe('solution files', () => {
  const level = room({ entities: [{ kind: 'enemy', id: 'g1', type: 'grunt', x: 10, y: 5 }] });
  const sol = solo(level, [{ waitFor: { near: 'g1', dist: 1.5 } }, { press: 'light', aim: 'g1' }]);

  it('run-length encodes the input stream losslessly', () => {
    const inputs: PlayerInput[] = [];
    const mk = (moveX: number, aim: number, heavy = false): PlayerInput => ({ moveX, moveY: -0.25, aim, light: false, heavy, dodge: false, ranged: false, interact: heavy, ability: false });
    for (let i = 0; i < 40; i++) inputs.push(mk(0.5, 1.25));
    inputs.push(mk(0.5, 1.25, true));
    for (let i = 0; i < 3; i++) inputs.push(mk(-0.1234, -3.1));
    const enc = encodeInputs(inputs);
    // Presses first, then one span per run of ticks with the same stick and aim (game/bot.gd "inputs").
    expect(enc).toEqual([
      { tick: 40, press: 'heavy', aim: 1.25 },
      { tick: 40, press: 'interact', aim: 1.25 },
      { from: 0, to: 41, move: [0.5, -0.25], aim: 1.25 },
      { from: 41, to: 44, move: [-0.1234, -0.25], aim: -3.1 },
    ]);
    expect(decodeInputs(JSON.parse(JSON.stringify(enc)), 44)).toEqual(inputs);
  });

  it('reads an input stream the way the Godot bot does (game/bot.gd TickScript)', () => {
    const got = decodeInputs(
      [
        { from: 0, to: 4, move: [1, 0] },
        { from: 2, to: 4, move: [0, -1] },
        { from: 3, to: 6, aim: 0.5 },
        { tick: 1, press: 'light' },
        { tick: 5, press: 'dodge', aim: 2 },
        { tick: 99, press: 'heavy' },
      ],
      6,
    );
    // A later span overrides an earlier one; with no aim span the aim follows the stick.
    expect(got.map((i) => [i.moveX, i.moveY])).toEqual([[1, 0], [1, 0], [0, -1], [0, -1], [0, 0], [0, 0]]);
    expect(got.map((i) => i.aim)).toEqual([0, 0, -Math.PI / 2, 0.5, 0.5, 2]);
    expect(got.map((i) => i.light)).toEqual([false, true, false, false, false, false]);
    expect(got[5].dodge).toBe(true);
    expect(got.some((i) => i.heavy)).toBe(false);
  });

  it('stores a performance that replays identically from inputs and from tapes', () => {
    const run = runSolution(level, sol);
    const stored = compiledSolution(level, sol, run);
    expect(verifyGenerated(level, stored)).toEqual([]);
    // What the Godot bot reads (game/bot.gd load_plan): version, level, expect, and per take inputs.
    expect(stored.version).toBe(1);
    expect(stored.expect).toEqual({ win: true, takes: 1 });
    expect(stored.takes[0].inputs!.some((e) => 'press' in e && e.press === 'light')).toBe(true);
    expect(stored.generated!.ticks).toEqual([run.logs[0].inputs.length]);
    // Through the text on disk and back.
    const text = formatSolution(stored);
    const back = JSON.parse(text) as SolutionFile;
    expect(back).toEqual(JSON.parse(JSON.stringify(stored)));
    expect(staleReasons(back, level)).toEqual([]);
    expect(sameOutcome(replayStoredInputs(level, back).outcome, run.outcome)).toBe(true);
    expect(sameOutcome(replayStoredTapes(level, back).outcome, run.outcome)).toBe(true);
    // One plan step, one input entry and one tape per line.
    expect(text).toContain('        { "waitFor": { "near": "g1", "dist": 1.5 } },\n');
    expect(text).toMatch(/\n        \{ "tick": \d+, "press": "light", "aim": [-0-9.]+ \},?\n/);
    expect(text.split('\n').filter((l) => l.includes('"pos":')).length).toBe(1);
    // Compiling again from the stored file changes nothing.
    expect(formatSolution(compiledSolution(level, back, runSolution(level, back)))).toBe(text);
  });

  it('refuses to store a plan with takes that are never recorded', () => {
    const padded: SolutionFile = { ...sol, takes: [...sol.takes, { speed: 1, endMode: 'stop', note: 'never needed', plan: [] }] };
    expect(() => compiledSolution(level, padded, runSolution(level, padded))).toThrow(/used 1 of 2 takes/);
  });

  it('notices a level or plan edited after compiling', () => {
    const run = runSolution(level, sol);
    const stored = compiledSolution(level, sol, run);
    expect(staleReasons(stored, { ...level, bars: 8 })).toEqual(['the level file changed since the solution was compiled']);
    const edited: SolutionFile = { ...stored, takes: [{ ...stored.takes[0], note: 'changed' }] };
    expect(staleReasons(edited, level)).toEqual(['the plan changed since the solution was compiled']);
    expect(staleReasons(sol, level)).toEqual(['the solution has no generated section yet']);
  });

  it('checks the structure before anything runs', () => {
    const bad = {
      level: 'other',
      loadout: ['no_such_item'],
      takes: [
        { speed: 3, endMode: 'loop', note: '', plan: [{ goto: [1, 2], wait: 1 }, { press: 'jump' }, { aim: 'nobody', press: 'light' }, { fly: true }, { waitFor: { near: 'g1' } }, { tol: 1 }] },
      ],
    } as unknown as SolutionFile;
    const problems = checkSolution(bad, level).join('\n');
    expect(problems).toMatch(/"level" is "other"/);
    expect(problems).toMatch(/unknown gear id "no_such_item"/);
    expect(problems).toMatch(/speed 3 is not one of/);
    expect(problems).toMatch(/endMode "loop"/);
    expect(problems).toMatch(/"note" must say/);
    expect(problems).toMatch(/step 1: one verb per step/);
    expect(problems).toMatch(/step 2: press must be one of/);
    expect(problems).toMatch(/step 3 aim: "nobody" is neither a compass direction/);
    expect(problems).toMatch(/step 4: unknown key "fly"/);
    expect(problems).toMatch(/step 5: waitFor.near needs "dist"/);
    expect(problems).toMatch(/step 6: has no verb/);
    expect(checkSolution(sol, level)).toEqual([]);
    expect(checkSolution({ ...sol, takes: [...sol.takes, ...sol.takes, ...sol.takes, ...sol.takes, ...sol.takes] }, level).join('\n')).toMatch(/5 takes but the level offers 4/);
  });

  it('swaps named gear into the baseline loadout, written by slot or as a list', () => {
    const ids = solutionLoadoutIds({ loadout: ['reel_lash'] });
    expect(ids.melee).toBe('reel_lash');
    expect(ids.shoes).toBe(baselineLoadout().loadout.shoes);
    expect(solutionLoadoutIds({ loadout: { melee: 'reel_lash' } })).toEqual(ids);
    expect(() => solutionLoadoutIds({ loadout: ['nope'] })).toThrow(/unknown gear id/);
    expect(checkSolution({ ...sol, loadout: { melee: 'spring_soles' } }, level).join('\n')).toMatch(/"spring_soles" is a shoes item, not melee/);
    expect(checkSolution({ ...sol, loadout: { hat: 'reel_lash' } } as unknown as SolutionFile, level).join('\n')).toMatch(/"hat" is not a gear slot/);
    // The file always stores the by-slot shape (the one the Godot bot reads), and nothing for the baseline.
    expect(formatSolution({ ...sol, loadout: ['reel_lash'] })).toContain('  "loadout": { "melee": "reel_lash" },\n');
    expect(formatSolution({ ...sol, loadout: [baselineLoadout().loadout.melee] })).not.toContain('"loadout"');
    expect(usesBaseline(sol)).toBe(true);
    expect(usesBaseline({ loadout: { melee: 'reel_lash' } })).toBe(false);
  });

  it('points at a take written in the Godot bot\'s own step format', () => {
    const godot = { version: 1, level: level.id, takes: [{ speed: 1, endMode: 'stop', steps: [{ goto: [3, 3] }], reflex: {} }] } as unknown as SolutionFile;
    const problems = checkSolution(godot, level).join('\n');
    expect(problems).toMatch(/"steps" belongs to the Godot bot's own step list/);
    expect(problems).toMatch(/"plan" must be an array of steps/);
  });
});

describe('robustness variants', () => {
  it('shifts every timed step by the requested ticks', () => {
    const level = room();
    const sol = solo(level, [{ at: 2, press: 'light' }]);
    const tickOf = (shift: number): number => runSolution(level, sol, { mutations: [{ shift, dx: 0, dy: 0 }] }).tapes[0].events[0].tick;
    expect([-2, -1, 0, 1, 2].map(tickOf)).toEqual([58, 59, 60, 61, 62]);
  });

  it('nudges every goto target', () => {
    const level = room();
    const sol = solo(level, [{ goto: [8, 5] }]);
    const run = runSolution(level, sol, { mutations: [{ shift: 0, dx: 0.5, dy: -0.5 }] });
    expect(Math.hypot(run.logs[0].steps[0].x - 8.5, run.logs[0].steps[0].y - 4.5)).toBeLessThan(0.12);
  });

  it('lists the variants: together, one take at a time, and nudged', () => {
    expect(mutationVariants(1, 'quick').map((v) => v.label)).toEqual(['all takes +1 tick', 'all takes -1 tick']);
    expect(mutationVariants(3, 'quick')).toHaveLength(2 + 3 * 2);
    expect(mutationVariants(3, 'full')).toHaveLength(4 + 3 * 4 + 4 + 4);
    const one = mutationVariants(3, 'quick').find((v) => v.label === 'take 2 (B) -1 tick')!;
    expect(one.mutations.map((m) => m.shift)).toEqual([0, -1, 0]);
  });

  it('catches a solution that only works on one exact tick', () => {
    const level = room({
      map: ['#########', '#.......#', '#########'],
      start: { x: 3.5, y: 1.5 },
      bars: 2,
      entities: [
        { kind: 'switch', id: 'sw', x: 1.5, y: 1.5 },
        { kind: 'door', id: 'door', cells: [{ c: 4, r: 1 }], openWhen: { sig: 'sw' } },
        { kind: 'core', id: 'core', x: 5.5, y: 1.5 },
      ],
      objective: { type: 'activate', text: 'Light the core' },
    });
    // The blade reaches 1.3 tiles and the core is 0.4 wide: from x = 3.83 the swing only just touches
    // the core at 5.5, so the same plan nudged 0.08 tiles west swings at thin air.
    const sol = solo(level, [{ goto: [2.4, 1.5], press: 'interact' }, { goto: [3.83, 1.5], tol: 0.02 }, { press: 'light', aim: 'E' }]);
    const base = runSolution(level, sol);
    expect(base.outcome.win).toBe(true);
    const west = runSolution(level, sol, { mutations: [{ shift: 0, dx: -0.08, dy: 0 }] });
    expect(west.outcome.win).toBe(false);
  });
});

describe('reports', () => {
  const level = room({
    entities: [
      { kind: 'enemy', id: 'g1', type: 'grunt', x: 10, y: 5 },
      { kind: 'plate', id: 'pad', c: 2, r: 2 },
      { kind: 'door', id: 'door', cells: [{ c: 9, r: 8 }], openWhen: { sig: 'pad' } },
      { kind: 'breakable', id: 'wall', c: 3, r: 7, threshold: TUTORIAL_WALL_THRESHOLD },
    ],
  });
  const sol = solo(level, [{ waitFor: { near: 'g1', dist: 1.5 } }, { press: 'light', aim: 'g1' }, { goto: [2.5, 2.5] }]);
  const run = runSolution(level, sol);

  it('draws the level with every entity and a table', () => {
    const lines = renderStatic(level);
    expect(lines.some((l) => l.includes('#.....@...G#'))).toBe(true);
    expect(lines.some((l) => l.includes('#.p'))).toBe(true);
    expect(lines.some((l) => l.includes('@'))).toBe(true);
    expect(lines.join('\n')).toContain('door "door" on tile (9,8): open while pad');
    expect(lines.join('\n')).toContain('breakable "wall" on tile (3,7): one hit of momentum 5 or more');
    const show = showLines(level, sol).join('\n');
    expect(show).toContain('Objective (eliminate)');
    expect(show).toContain('A take records 4 bars = 16 local beats = 480 local ticks = 8.0 s');
    expect(show).toContain('Take 1 = tape A, 1x, stop: test take');
  });

  it('draws one instant of the run: selves, enemies, mechanisms and their states', () => {
    const start = renderFrame(level, frameAtBeat(level, run.resolution, 0), run.tapes).join('\n');
    expect(start).toContain('#.....A...G#');
    expect(start).toContain('+  door "door" closed');
    const end = renderFrame(level, frameAtBeat(level, run.resolution, 16), run.tapes).join('\n');
    expect(end).toContain('#.A');
    expect(end).toContain('P  plate "pad" PRESSED');
    expect(end).toContain(':  door "door" OPEN');
    expect(end).toContain('x  grunt "g1"');
    expect(end).toContain('objective COMPLETE');
    // Dead selves are lower case, desynced ones a question mark with their spark shown.
    const snap = JSON.parse(JSON.stringify(frameAtBeat(level, run.resolution, 0)));
    snap.actors[0].life = 'ghost';
    expect(renderFrame(level, snap).join('\n')).toContain('#.....a...G#');
    snap.actors[0].life = 'alive';
    snap.actors[0].synced = false;
    snap.actors[0].spark = { x: 3.5, y: 5.5 };
    expect(renderFrame(level, snap).join('\n')).toContain('#..!..?...G#');
  });

  it('tells the story of a run in sentences and shows what a take changed', () => {
    const kill = run.resolution.events.find((e) => e.type === 'kill')!;
    expect(describeEvent(kill)).toMatch(/^A KILLS g1 \(light, momentum 1\.00\)$/);
    expect(describeEvent({ sub: 0, type: 'step', x: 0, y: 0 })).toBeNull();
    const diff = eventDiffLines(level, [], run.resolution.events);
    expect(diff.every((l) => l.startsWith('+'))).toBe(true);
    expect(eventDiffLines(level, run.resolution.events, run.resolution.events)).toEqual([]);
    expect(eventDiffLines(level, run.resolution.events, []).every((l) => l.startsWith('-'))).toBe(true);
    const steps = stepLines(level, sol.takes[0], run.logs[0]).join('\n');
    expect(steps).toMatch(/1\. waitFor .*tick +0 ->/);
    expect(steps).toMatch(/3\. goto \[2\.5,2\.5\]/);
  });

  it('probes real numbers: the tuning targets hold', () => {
    const baseline = baselineLoadout();
    const swings = swingNumbers(baseline, [0.5, 1, 2]);
    const get = (kind: string, running: boolean, speed: number) => swings.find((w) => w.kind === kind && w.running === running && w.speed === speed)!;
    expect(get('light', false, 1).damage).toBe(1);
    expect(get('light', false, 0.5).damage).toBe(0);
    expect(get('heavy', true, 2).momentum).toBeGreaterThanOrEqual(TUTORIAL_WALL_THRESHOLD);
    expect(get('heavy', false, 2).momentum).toBeLessThan(TUTORIAL_WALL_THRESHOLD);
    const slow = runDistanceInBeats(level, baseline, 2, 1);
    const fast = runDistanceInBeats(level, baseline, 2, 2);
    expect(slow.ticks).toBe(60);
    expect(fast.ticks).toBe(120);
    expect(fast.tiles).toBeGreaterThan(slow.tiles * 1.9);
    const text = probeLines(level, baseline, { beats: 2, speed: 2 }).join('\n');
    expect(text).toContain(`=> in 2 master beat(s) a 2x self runs ${fast.tiles.toFixed(2)} tiles (120 local ticks)`);
    expect(text).toContain('breakable "wall" needs momentum 5: 4x light running');
    expect(text).toMatch(/grunt +1 /);
  });
});

describe('traps (docs/TRAPS.md) in the tools', () => {
  const level = room({
    start: { x: 2.5, y: 5 },
    entities: [
      { kind: 'enemy', id: 't', type: 'turret', x: 10.5, y: 8.5, wakeWhen: { const: false } },
      { kind: 'spikes', id: 'sp', cells: [{ c: 5, r: 4 }, { c: 5, r: 5 }], upWhen: { beat: { every: 4, from: 0, to: 2 } } },
      { kind: 'crusher', id: 'cr', cells: [{ c: 8, r: 1 }], extendWhen: { const: false } },
      { kind: 'conveyor', id: 'belt', cells: [{ c: 2, r: 8 }, { c: 3, r: 8 }], dir: 'w' },
      { kind: 'sensor', id: 'wire', from: { x: 7.5, y: 1.2 }, to: { x: 7.5, y: 8.8 }, detects: 'selves' },
    ],
  } as Partial<LevelDef>);

  it('draws them as authored and names what drives them', () => {
    const text = renderStatic(level).join('\n');
    expect(text).toContain('#....W.;...#');
    expect(text).toContain('#.<<...;..T#');
    expect(text).toContain('spikes "sp" on tiles (5,4) (5,5): raised while beats [0, 2) of every 4');
    expect(text).toContain('m  crusher "cr" over tile (8,1): extends while never');
    expect(text).toContain('conveyor "belt" on tiles (2,8) (3,8) toward west');
  });

  it('lets a plan wait for a trap and aim at one, and shows their live state', () => {
    const sol = solo(level, [{ waitFor: { off: 'sp' } }, { goto: [9.5, 5] }, { face: 'wire' }]);
    expect(checkSolution(sol, level)).toEqual([]);
    const run = runSolution(level, sol);
    // The spikes are up for beats 0-2: the self must not have set off before they dropped.
    expect(run.logs[0].steps[0].endTick).toBeGreaterThanOrEqual(59);
    expect(run.resolution.events.some((e) => e.type === 'selfDeath')).toBe(false);
    const early = renderFrame(level, frameAtBeat(level, run.resolution, 1), run.tapes).join('\n');
    expect(early).toContain('W  spikes "sp" RAISED (lethal)');
    const late = renderFrame(level, frameAtBeat(level, run.resolution, 7), run.tapes).join('\n');
    expect(late).toContain('w  spikes "sp" down');
    expect(late).toContain(';  sensor "wire" clear');
    const walked = runSolution(level, solo(level, [{ goto: [9.5, 5], straight: true }]));
    expect(walked.outcome.notes.join(' ')).toMatch(/Tape A died at beat .*spikes sp/);
  });

  it('reports trap events without letting beat-timed hazards drown the log', () => {
    const ev = (detail: string): Parameters<typeof describeEvent>[0] => ({ sub: 0, type: 'trap', x: 0, y: 0, id: 'x1', detail }) as unknown as Parameters<typeof describeEvent>[0];
    expect(describeEvent(ev('sensor:on'))).toBe('sensor x1: on');
    expect(describeEvent(ev('spikes:up'))).toBeNull();
    expect(describeEvent(ev('spikes:up'), true)).toBe('spikes x1: up');
    expect(describeEvent(ev('crusher:warn'))).toBeNull();
    expect(describeEvent({ sub: 0, type: 'somethingNew', x: 0, y: 0, id: 'q', detail: 'd' } as unknown as Parameters<typeof describeEvent>[0])).toBe('somethingNew q: d');
  });
});

describe('level file naming', () => {
  it('ties the file name to the id and the campaign index', () => {
    expect(levelFileProblems('03-crossfire.json', { id: '03-crossfire', index: 3 })).toEqual([]);
    expect(levelFileProblems('sandbox.json', { id: 'sandbox', index: 0 })).toEqual([]);
    expect(levelFileProblems('data/levels/03-crossfire.json', { id: 'crossfire', index: 3 }).join('\n')).toMatch(/id "crossfire" must equal the file name without \.json \("03-crossfire"\)/);
    expect(levelFileProblems('03-crossfire.json', { id: '03-crossfire', index: 4 }).join('\n')).toMatch(/index is 4 but the file name says 3/);
    expect(levelFileProblems('3-crossfire.json', { id: '3-crossfire', index: 3 }).join('\n')).toMatch(/exactly two digits/);
    expect(levelFileProblems('03-Cross_Fire.json', { id: '03-Cross_Fire', index: 3 }).join('\n')).toMatch(/lower-case words joined by dashes/);
  });

  it('wants campaign indices 1, 2, 3 … (the file prefixes) without gaps or duplicates', () => {
    const f = (file: string, index: number) => ({ file, level: { index } as LevelDef });
    expect(campaignOrderProblems([f('02-b.json', 2), f('01-a.json', 1)])).toEqual([]);
    expect(campaignOrderProblems([f('01-a.json', 1), f('03-c.json', 3)]).join('\n')).toMatch(/03-c\.json: index 3 leaves a gap \(expected 2/);
    expect(campaignOrderProblems([f('00-a.json', 0), f('01-b.json', 1)]).join('\n')).toMatch(/00-a\.json: index 0 leaves a gap \(expected 1/);
    expect(campaignOrderProblems([f('01-a.json', 1), f('01-b.json', 1)]).join('\n')).toMatch(/01-b\.json: index 1 is also used by 01-a\.json/);
  });
});
