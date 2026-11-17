/**
 * Helpers for driving a Session headlessly.
 */
import type { LevelDef, PlayerInput, ResolvedLoadout } from '../../src/core/types';
import { createSession, type Session } from '../../src/game/session';
import { baseLoadout } from '../helpers/loadout';
import { makeLevel } from '../helpers/levels';
import type { InputScript } from '../helpers/script';

export const STEP = 1 / 60;

export function newSession(level: LevelDef, loadout: ResolvedLoadout = baseLoadout(), skipBriefing = true): Session {
  return createSession({ level, loadout, skipBriefing });
}

/** Advance wall time in 1/60 s frames until the phase changes (bounded). */
export function advanceUntilPhaseChanges(s: Session, maxSeconds = 120): void {
  const start = s.phase;
  for (let t = 0; t < maxSeconds && s.phase === start; t += STEP) s.advance(STEP);
  if (s.phase === start) throw new Error(`still in ${start}`);
}

/** record → count-in → feed the script tick by tick until the take ends. */
export function recordWith(s: Session, input: InputScript | ((tick: number) => PlayerInput)): void {
  if (!s.act('record')) throw new Error(`record not offered in ${s.phase}`);
  advanceUntilPhaseChanges(s, 10);
  if (s.phase !== 'recording') throw new Error(`expected recording, got ${s.phase}`);
  const fn = typeof input === 'function' ? input : (t: number) => input.input(t);
  let tick = 0;
  while (s.phase === 'recording') s.tickLocal(fn(tick++));
}

export function setSpeed(s: Session, speed: number): void {
  for (let i = 0; i < 8 && s.speed !== speed; i++) s.act(s.speed < speed ? 'speedUp' : 'speedDown');
  if (s.speed !== speed) throw new Error(`could not set speed ${speed}`);
}

export const NO_INPUT = (): PlayerInput => ({
  moveX: 0,
  moveY: 0,
  aim: 0,
  light: false,
  heavy: false,
  dodge: false,
  ranged: false,
  interact: false,
  ability: false,
});

export const ALL_BUTTONS = (): PlayerInput => ({
  moveX: 1,
  moveY: 1,
  aim: 1,
  light: true,
  heavy: true,
  dodge: true,
  ranged: true,
  interact: true,
  ability: true,
});

/**
 * The rescue room from the kernel ghost tests (Scenario C): a turret shoots anyone at the start;
 * a sleeping grunt is the objective; a lever opens a door.
 */
export function rescueRoom(maxTapes: 1 | 2 | 3 | 4 = 4): LevelDef {
  return makeLevel({
    id: 'rescue',
    speeds: [1, 2],
    bars: 4,
    maxTapes,
    map: ['############', '#.....#....#', '#.....#....#', '#..........#', '#.....#....#', '############'],
    start: { x: 3.0, y: 3.5 },
    entities: [
      { kind: 'enemy', id: 't1', type: 'turret', x: 1.5, y: 4.5 },
      { kind: 'enemy', id: 'g1', type: 'grunt', x: 3.0, y: 2.55, wakeWhen: { const: false } },
      { kind: 'switch', id: 'lever', x: 2.5, y: 1.5 },
      { kind: 'door', id: 'gate', cells: [{ c: 6, r: 3 }], openWhen: { sig: 'lever' } },
    ],
    objective: { type: 'eliminate', targets: ['g1'], text: 'Destroy the grunt' },
  });
}

/**
 * Laser hall for the final-tape edge case: a permanent laser across the room between the start and
 * a sleeping grunt. Walking through it kills; only a recording ghost can then reach the grunt.
 */
export function laserHall(maxTapes: 1 | 2 | 3 | 4 = 2): LevelDef {
  return makeLevel({
    id: 'laser-hall',
    speeds: [1],
    endModes: ['stop'],
    bars: 2,
    maxTapes,
    start: { x: 2.5, y: 5.5 },
    entities: [
      { kind: 'laser', id: 'beam', from: { x: 5.5, y: 1.5 }, to: { x: 5.5, y: 8.5 }, onWhen: { const: true } },
      { kind: 'enemy', id: 'g1', type: 'grunt', x: 8.5, y: 5.5, wakeWhen: { const: false } },
    ],
    objective: { type: 'eliminate', targets: ['g1'], text: 'Destroy the grunt' },
  });
}
