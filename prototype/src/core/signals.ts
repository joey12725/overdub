/**
 * Signal logic: the boolean expressions that drive doors, lasers, wake conditions and objectives.
 *
 * Signals are named booleans in one table owned by the kernel (switch states, plates, breakables,
 * cores, exits…). An id missing from the table reads as false, so an expression referring to a
 * mechanism that never fired is simply off.
 */
import type { SignalExpr } from './types';

export type SignalTable = ReadonlyMap<string, boolean>;

/**
 * Evaluate an expression against the signal table at a master beat.
 *
 *  and([]) is true, or([]) is false (identity elements).
 *  beat { every, from, to } is true while (masterBeat mod every) ∈ [from, to). When from > to the
 *  window wraps around the cycle (e.g. every 4, from 3, to 1 covers beats 3..4 and 0..1).
 *  from === to is an empty window. every ≤ 0 is never true.
 */
export function evalSignal(expr: SignalExpr, signals: SignalTable, masterBeat: number): boolean {
  if ('sig' in expr) return signals.get(expr.sig) === true;
  if ('not' in expr) return !evalSignal(expr.not, signals, masterBeat);
  if ('and' in expr) {
    for (const e of expr.and) if (!evalSignal(e, signals, masterBeat)) return false;
    return true;
  }
  if ('or' in expr) {
    for (const e of expr.or) if (evalSignal(e, signals, masterBeat)) return true;
    return false;
  }
  if ('xor' in expr) return evalSignal(expr.xor[0], signals, masterBeat) !== evalSignal(expr.xor[1], signals, masterBeat);
  if ('const' in expr) return expr.const;
  if ('beat' in expr) return inBeatWindow(masterBeat, expr.beat.every, expr.beat.from, expr.beat.to);
  return assertNever(expr);
}

/** The beat-window predicate on its own (also used for HUD previews of beat-timed mechanisms). */
export function inBeatWindow(masterBeat: number, every: number, from: number, to: number): boolean {
  if (!(every > 0)) return false;
  let p = masterBeat % every;
  if (p < 0) p += every;
  // Guard the representable edge where p + every rounds back to exactly `every`.
  if (p >= every) p = 0;
  const f = mod(from, every);
  const t = mod(to, every);
  if (from === to) return false;
  // A window of a whole cycle or more is always on.
  if (Math.abs(to - from) >= every) return true;
  if (f < t) return p >= f && p < t;
  if (f > t) return p >= f || p < t;
  // Distinct from/to that coincide modulo `every` (and span < every) cannot happen; treat as empty.
  return false;
}

function mod(a: number, m: number): number {
  const r = a % m;
  return r < 0 ? r + m : r;
}

/** Every signal id an expression reads, added to `out` (insertion order follows a left-to-right walk). */
export function collectSignalIds(expr: SignalExpr, out: Set<string> = new Set()): Set<string> {
  if ('sig' in expr) out.add(expr.sig);
  else if ('not' in expr) collectSignalIds(expr.not, out);
  else if ('and' in expr) for (const e of expr.and) collectSignalIds(e, out);
  else if ('or' in expr) for (const e of expr.or) collectSignalIds(e, out);
  else if ('xor' in expr) {
    collectSignalIds(expr.xor[0], out);
    collectSignalIds(expr.xor[1], out);
  }
  return out;
}

/** True if the expression depends on the beat clock (so it can change without any signal changing). */
export function isTimedExpr(expr: SignalExpr): boolean {
  if ('beat' in expr) return true;
  if ('not' in expr) return isTimedExpr(expr.not);
  if ('and' in expr) return expr.and.some(isTimedExpr);
  if ('or' in expr) return expr.or.some(isTimedExpr);
  if ('xor' in expr) return isTimedExpr(expr.xor[0]) || isTimedExpr(expr.xor[1]);
  return false;
}

/** Compact human-readable form ("door1 & !(plateA | beat%4∈[0,2))") for debugging and validator messages. */
export function formatSignalExpr(expr: SignalExpr): string {
  if ('sig' in expr) return expr.sig;
  if ('not' in expr) return `!${wrap(expr.not)}`;
  if ('and' in expr) return expr.and.length === 0 ? 'true' : expr.and.map(wrap).join(' & ');
  if ('or' in expr) return expr.or.length === 0 ? 'false' : expr.or.map(wrap).join(' | ');
  if ('xor' in expr) return `${wrap(expr.xor[0])} ^ ${wrap(expr.xor[1])}`;
  if ('const' in expr) return String(expr.const);
  if ('beat' in expr) return `beat%${expr.beat.every}∈[${expr.beat.from},${expr.beat.to})`;
  return assertNever(expr);
}

function wrap(e: SignalExpr): string {
  const s = formatSignalExpr(e);
  return 'and' in e || 'or' in e || 'xor' in e ? `(${s})` : s;
}

function assertNever(x: never): never {
  throw new Error(`Unknown SignalExpr ${JSON.stringify(x)}`);
}
