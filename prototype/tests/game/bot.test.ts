/**
 * The headless bot proves levels solvable through the real Session (APP-TEST-03).
 */
import { describe, expect, it } from 'vitest';
import { BASE_LOADOUT, resolveLoadout, SANDBOX } from '../../src/content/index';
import { idleInput, runBot, runBotDetailed, type BotTake } from '../../src/game/bot';
import { planTake } from './plans';

/** One self does everything: lever, door, both grunts, then the turret from above (dodging its bolt). */
const soloSweep = (): BotTake =>
  planTake(
    1,
    'stop',
    [
      { kind: 'goto', x: 3.5, y: 2.3 },
      { kind: 'interact' },
      { kind: 'goto', x: 4.5, y: 3.5 },
      { kind: 'goto', x: 7.0, y: 3.5 },
      { kind: 'goto', x: 11.5, y: 3.4 },
      { kind: 'hold', x: 11.5, y: 3.4 },
    ],
    { dodgeRange: 1.2 },
  );

describe('bot', () => {
  it('solves the sandbox with the baseline loadout in one take', () => {
    const run = runBotDetailed(SANDBOX, [soloSweep()], { loadout: resolveLoadout(BASE_LOADOUT) });
    expect(run.outcome.win).toBe(true);
    expect(run.takesRecorded).toBe(1);
    expect(run.session.phase).toBe('results');
    expect(run.outcome.survivors).toEqual([0]);
  });

  it('solves the sandbox with a two-cassette plan: A opens the door and holds the plate, B (2x) fights', () => {
    const a = planTake(
      1,
      'stop',
      [
        { kind: 'goto', x: 3.5, y: 2.3 },
        { kind: 'interact' },
        { kind: 'goto', x: 2.5, y: 6.5 },
        { kind: 'goto', x: 1.5, y: 8.5 },
        { kind: 'hold', x: 1.5, y: 8.5 },
      ],
      { strikeRange: 0 },
    );
    const b = planTake(
      2,
      'stop',
      [
        { kind: 'goto', x: 4.5, y: 3.5 },
        { kind: 'goto', x: 7.0, y: 3.5 },
        { kind: 'goto', x: 11.5, y: 3.4 },
        { kind: 'hold', x: 11.5, y: 3.4 },
      ],
      { dodgeRange: 1.2 },
    );
    const run = runBotDetailed(SANDBOX, [a, b]);
    expect(run.outcome.win).toBe(true);
    expect(run.takesRecorded).toBe(2);
    expect(run.session.committedTapes).toHaveLength(1);
    expect(run.session.pendingTape!.speed).toBe(2);
    expect(run.session.resolution!.events.some((e) => e.type === 'plate' && e.detail === 'on')).toBe(true);
  });

  it('reports a failing plan as the final resolved outcome', () => {
    const idle: BotTake = { speed: 1, endMode: 'stop', inputs: () => idleInput() };
    const out = runBot(SANDBOX, [idle, idle]);
    expect(out.win).toBe(false);
    expect(out.reason).toBe('objective');
  });

  it('rejects plans the level cannot accept', () => {
    const idle = (speed: 0.5 | 1 | 2 | 4): BotTake => ({ speed, endMode: 'stop', inputs: () => idleInput() });
    expect(() => runBot(SANDBOX, [])).toThrow(/no takes/);
    expect(() => runBot(SANDBOX, [idle(1), idle(1), idle(1), idle(1), idle(1)])).toThrow(/offers 4/);
    expect(() => runBot({ ...SANDBOX, speeds: [1, 2] }, [idle(4)])).toThrow(/speed 4x/);
  });
});
