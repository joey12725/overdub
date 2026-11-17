/**
 * Mechanism accent colours. A door and the switch / plate that opens it share an accent so the
 * wiring reads at a glance (chapter 19: functional doors must be distinguishable; chapter 11 puzzle
 * vocabulary depends on the player seeing cause and effect).
 *
 * The accent set deliberately avoids the four cassette identity hues (red, yellow, blue, green;
 * UI-02) so a mechanism is never mistaken for a self.
 */
import type { EntityDef, LevelDef, SignalExpr } from '../../core/types';
import { hashString } from '../env/rng';

export const MECH_ACCENTS: readonly number[] = [
  0xff8a1f, // orange
  0x1fe8c0, // teal
  0xf04dff, // magenta
  0x9a6bff, // violet
  0xf3ead2, // ivory
  0xff9ec4, // coral pink
];

/** Accent for mechanisms driven only by the beat grid or constants (no switch to match). */
export const BEAT_ACCENT = 0xfff3c4;
/** Exit zones read the same in every level. */
export const EXIT_ACCENT = 0xc8fff4;
/** Laser beams are always hazard red-magenta so danger is never colour-coded away. */
export const LASER_BEAM = 0xff2b5e;

/** Pure-hash accent for a signal id (used when no level-wide assignment is available). */
export function signalAccent(id: string): number {
  return MECH_ACCENTS[hashString(id) % MECH_ACCENTS.length];
}

/** Signal ids referenced by an expression, depth-first, in source order, without duplicates. */
export function exprSignals(expr: SignalExpr, out: string[] = []): string[] {
  if ('sig' in expr) {
    if (!out.includes(expr.sig)) out.push(expr.sig);
  } else if ('not' in expr) {
    exprSignals(expr.not, out);
  } else if ('and' in expr) {
    for (const e of expr.and) exprSignals(e, out);
  } else if ('or' in expr) {
    for (const e of expr.or) exprSignals(e, out);
  } else if ('xor' in expr) {
    exprSignals(expr.xor[0], out);
    exprSignals(expr.xor[1], out);
  }
  return out;
}

/** Signals a mechanism consumes (doors, lasers) or produces (switch, plate, breakable, core, exit). */
function entitySignals(e: EntityDef): string[] {
  switch (e.kind) {
    case 'door':
      return exprSignals(e.openWhen);
    case 'laser':
      return exprSignals(e.onWhen);
    case 'switch':
    case 'plate':
    case 'breakable':
    case 'core':
    case 'exit':
      return [e.id];
    case 'enemy':
      return e.wakeWhen ? exprSignals(e.wakeWhen) : [];
    default:
      return [];
  }
}

/**
 * Level-wide signal → accent table. Ids are visited in sorted order; each takes its hash-preferred
 * slot, probing forward to the next unused accent so signals in one level stay distinct while the
 * palette lasts. Deterministic for a given level.
 */
export function buildAccentMap(level: Pick<LevelDef, 'entities'>): Map<string, number> {
  const ids = new Set<string>();
  for (const e of level.entities) for (const s of entitySignals(e)) ids.add(s);
  const sorted = [...ids].sort();
  const used = new Set<number>();
  const map = new Map<string, number>();
  for (const id of sorted) {
    const start = hashString(id) % MECH_ACCENTS.length;
    let slot = start;
    if (used.size < MECH_ACCENTS.length) {
      for (let k = 0; k < MECH_ACCENTS.length; k++) {
        const s = (start + k) % MECH_ACCENTS.length;
        if (!used.has(s)) {
          slot = s;
          break;
        }
      }
    }
    used.add(slot);
    map.set(id, MECH_ACCENTS[slot]);
  }
  return map;
}

/** Accent for an expression: the colour of its first referenced signal, or the beat accent. */
export function exprAccent(expr: SignalExpr, map?: Map<string, number>): number {
  const sigs = exprSignals(expr);
  if (sigs.length === 0) return BEAT_ACCENT;
  return map?.get(sigs[0]) ?? signalAccent(sigs[0]);
}
