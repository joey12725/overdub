/**
 * Level validation of trap entities (src/content/validate.ts; docs/TRAPS.md JSON shapes).
 */
import { describe, expect, it } from 'vitest';
import { isProblem, validateLevel } from '../../../src/content/validate';
import type { EntityDef, LevelDef } from '../../../src/core/types';
import { makeLevel } from '../../helpers/levels';

/** A valid level using every trap kind, written the way a level file would be (plain JSON). */
const TRAPS: EntityDef[] = JSON.parse(`[
  { "kind": "enemy", "id": "g1", "type": "grunt", "x": 9.5, "y": 2.5 },
  { "kind": "switch", "id": "lever", "x": 2.5, "y": 2.5 },
  { "kind": "spikes", "id": "sp1", "cells": [ { "c": 4, "r": 3 }, { "c": 5, "r": 3 } ],
    "upWhen": { "beat": { "every": 4, "from": 2, "to": 3 } } },
  { "kind": "crusher", "id": "cr1", "cells": [ { "c": 6, "r": 1 }, { "c": 6, "r": 2 }, { "c": 6, "r": 3 } ], "dir": "s",
    "extendWhen": { "sig": "slam" } },
  { "kind": "conveyor", "id": "belt1", "cells": [ { "c": 2, "r": 5 }, { "c": 3, "r": 5 }, { "c": 4, "r": 5 } ],
    "dir": "e", "speed": 2, "reverseWhen": { "sig": "lever" } },
  { "kind": "flame", "id": "fl1", "c": 0, "r": 7, "dir": "e", "range": 5,
    "onWhen": { "and": [ { "beat": { "every": 2, "from": 1, "to": 2 } }, { "not": { "sig": "belt1.rev" } } ] } },
  { "kind": "dart", "id": "d1", "c": 11, "r": 4, "dir": "w", "every": 2, "offset": 0.5 },
  { "kind": "bumper", "id": "bm1", "c": 7, "r": 6, "dir": "n", "power": 3,
    "fireWhen": { "beat": { "every": 4, "from": 3, "to": 3.5 } } },
  { "kind": "sensor", "id": "trip1", "from": { "x": 3.5, "y": 4.0 }, "to": { "x": 3.5, "y": 7.0 }, "detects": "enemies" },
  { "kind": "relay", "id": "slam", "trigger": { "sig": "trip1" }, "mode": "pulse", "quantize": 1, "delay": 1, "hold": 1 },
  { "kind": "door", "id": "gate", "cells": [ { "c": 9, "r": 8 } ], "openWhen": { "or": [ { "sig": "slam.armed" }, { "sig": "bm1" } ] } },
  { "kind": "magnet", "id": "mag1", "x": 8.5, "y": 4.5, "radius": 4, "pull": 1.5, "onWhen": { "sig": "lever" } }
]`);

function level(entities: EntityDef[] = TRAPS): LevelDef {
  return makeLevel({ start: { x: 1.5, y: 1.5 }, entities, briefing: ['Mind the machines.'], horizonBars: 8 });
}

function problems(entities: EntityDef[]): string[] {
  return validateLevel(level(entities)).filter(isProblem);
}

/** The valid level with one entity replaced by `patch` merged over it. */
function withPatch(id: string, patch: Record<string, unknown>): EntityDef[] {
  return TRAPS.map((e) => ('id' in e && e.id === id ? ({ ...e, ...patch } as EntityDef) : e));
}

function expectProblem(entities: EntityDef[], pattern: RegExp): void {
  const list = problems(entities);
  expect(list.some((p) => pattern.test(p)), `expected a problem matching ${pattern}; got:\n${list.join('\n') || '(none)'}`).toBe(true);
}

describe('validateLevel: traps', () => {
  it('accepts a level that uses every trap kind and their secondary signals', () => {
    expect(validateLevel(level()).filter(isProblem)).toEqual([]);
  });

  it('puts trap ids in the one id namespace and makes them signals', () => {
    expectProblem(withPatch('sp1', { id: 'lever' }), /duplicate id "lever"/);
    expectProblem(withPatch('cr1', { extendWhen: { sig: 'nope' } }), /signal "nope" is not produced/);
    expectProblem(withPatch('gate', { openWhen: { sig: 'lever.rev' } }), /signal "lever\.rev" is not produced/);
  });

  it('requires each trap’s driving expression', () => {
    expectProblem(withPatch('sp1', { upWhen: undefined }), /spikes "sp1": upWhen is required/);
    expectProblem(withPatch('cr1', { extendWhen: undefined }), /crusher "cr1": extendWhen is required/);
    expectProblem(withPatch('fl1', { onWhen: undefined }), /flame "fl1": onWhen is required/);
    expectProblem(withPatch('bm1', { fireWhen: undefined }), /bumper "bm1": fireWhen is required/);
    expectProblem(withPatch('slam', { trigger: undefined }), /relay "slam": trigger is required/);
    expectProblem(withPatch('mag1', { onWhen: undefined }), /magnet "mag1": onWhen is required/);
    expectProblem(withPatch('sp1', { upWhen: { beat: { every: 4, from: 3, to: 2 } } }), /beat window/);
  });

  it('checks cells: on the floor, in the map, not repeated, and crushers in one straight line', () => {
    expectProblem(withPatch('sp1', { cells: [] }), /spikes "sp1": needs at least one cell/);
    expectProblem(withPatch('sp1', { cells: [{ c: 0, r: 3 }] }), /not a floor tile/);
    expectProblem(withPatch('belt1', { cells: [{ c: 2, r: 5 }, { c: 2, r: 5 }] }), /listed twice/);
    expectProblem(withPatch('cr1', { cells: [{ c: 6, r: 1 }, { c: 6, r: 3 }] }), /straight, contiguous line/);
    expectProblem(withPatch('cr1', { cells: [{ c: 6, r: 1 }, { c: 7, r: 2 }] }), /straight, contiguous line/);
    expectProblem(withPatch('cr1', { cells: [{ c: 9, r: 8 }] }), /crusher "cr1" and door "gate" share tile/);
    expectProblem(
      [...TRAPS, { kind: 'conveyor', id: 'belt2', cells: [{ c: 4, r: 5 }], dir: 'n' }],
      /share tile \(4,5\); a tile belongs to one belt/,
    );
  });

  it('lets an enemy start on a crusher cell (that is what crushers are for)', () => {
    expect(problems([...TRAPS, { kind: 'enemy', id: 'g2', type: 'grunt', x: 6.5, y: 2.5 }])).toEqual([]);
  });

  it('checks directions, numbers and beat grids', () => {
    expectProblem(withPatch('belt1', { dir: 'north' }), /dir must be one of n, e, s, w/);
    expectProblem(withPatch('belt1', { speed: 0 }), /speed must be a positive number/);
    expectProblem(withPatch('fl1', { range: 2.5 }), /range must be a positive integer/);
    expectProblem(withPatch('fl1', { dir: 'w' }), /tile in front of it \(-1,7\) is a wall or outside the map/);
    expectProblem(withPatch('d1', { c: 12 }), /outside the map/);
    expectProblem(withPatch('d1', { every: 0 }), /every must be a positive number/);
    expectProblem(withPatch('d1', { offset: 0.01 }), /not a whole number of local ticks/);
    expectProblem(withPatch('bm1', { power: -1 }), /power must be a positive number/);
    expectProblem(withPatch('bm1', { c: 0 }), /not a floor tile/);
    expectProblem(withPatch('slam', { mode: 'blink' }), /mode must be pulse, latch or toggle/);
    expectProblem(withPatch('slam', { hold: 0 }), /hold must be a positive number of beats/);
    expectProblem(withPatch('slam', { delay: -1 }), /delay must be a non-negative number of beats/);
    expectProblem(withPatch('slam', { x: 3 }), /give both x and y/);
    expectProblem(withPatch('mag1', { radius: 0 }), /radius must be a positive number/);
    expectProblem(withPatch('sp1', { damage: 0.5 }), /damage must be a positive integer/);
  });

  it('checks sensor geometry and options', () => {
    expectProblem(withPatch('trip1', { to: { x: 3.5, y: 4.0 } }), /from and to must differ/);
    expectProblem(withPatch('trip1', { from: { x: 0.5, y: 4.5 } }), /inside a wall tile/);
    expectProblem(withPatch('trip1', { detects: 'ghosts' }), /detects must be any, selves or enemies/);
    expectProblem(withPatch('trip1', { latch: 'yes' }), /latch must be a boolean/);
  });
});
