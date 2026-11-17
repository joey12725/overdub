/**
 * Shared fixtures for the trap tests (docs/TRAPS.md).
 *
 * Every level here is the 12×10 open room at 120 bpm: 120 master substeps per beat, 30 local ticks
 * per beat, and 4 substeps per local tick at 1×. A beat window `from: n` turns true in substep
 * `n·120 − 1` (the substep that produces the instant `n·120`).
 */
import type { EnemyDef, EnemyType, EntityDef, LevelDef, MechSnap, Resolution, SignalExpr, Tape, TapeIndex } from '../../../src/core/types';
import { TRAP_EVENT } from '../../../src/core/traps';
import { makeLevel } from '../../helpers/levels';
import { pathTape } from '../../helpers/script';

export const SPB = 120;

/** True on master beats [from, to) of every `every`. */
export const beats = (every: number, from: number, to: number): SignalExpr => ({ beat: { every, from, to } });

export const NEVER: SignalExpr = { const: false };
export const ALWAYS: SignalExpr = { const: true };

/** An open room with the given entities; 1× only, `bars` bars long (default 2 = 8 beats = 960 substeps). */
export function room(entities: EntityDef[], extra: Partial<LevelDef> = {}): LevelDef {
  return makeLevel({ speeds: [1], bars: 2, start: { x: 1.5, y: 1.5 }, entities, ...extra });
}

/** An enemy that never wakes: a body for the machines to act on, with no behaviour of its own. */
export function sleeper(id: string, type: EnemyType, x: number, y: number, extra: Partial<EnemyDef> = {}): EnemyDef {
  return { kind: 'enemy', id, type, x, y, wakeWhen: NEVER, ...extra };
}

/** A tape that stands at (x, y) for the whole take. */
export function stand(index: TapeIndex, x: number, y: number, ticks = 240): Tape {
  return pathTape({ index, speed: 1, ticks, path: [{ tick: 0, x, y }] });
}

/** The snapshot of one mechanism / trap in the frame at (or just after) a master substep. */
export function mechAt(res: Resolution, sub: number, id: string): MechSnap {
  const frame = res.frames.find((f) => f.sub >= sub) ?? res.frames[res.frames.length - 1];
  const m = frame.mechs.find((x) => x.id === id);
  if (!m) throw new Error(`no mech ${id}`);
  return m;
}

/** Trap events of one trap as [sub, detail] pairs. */
export function trapEvents(res: { events: Resolution['events'] }, id: string): [number, string][] {
  return res.events.filter((e) => e.type === TRAP_EVENT && e.id === id).map((e) => [e.sub, e.detail ?? '']);
}

export function enemyAt(res: Resolution, sub: number, id: string) {
  const frame = res.frames.find((f) => f.sub >= sub) ?? res.frames[res.frames.length - 1];
  const e = frame.enemies.find((x) => x.id === id);
  if (!e) throw new Error(`no enemy ${id}`);
  return e;
}

export function lastFrame(res: Resolution) {
  return res.frames[res.frames.length - 1];
}
