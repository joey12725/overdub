import { describe, expect, it } from 'vitest';
import { isProblem, validateCampaign, validateLevel } from '../../src/content/validate';
import type { EntityDef, LevelDef, LevelMusicDef, ObjectiveDef } from '../../src/core/types';

/**
 * A small level that satisfies every rule. Individual tests mutate one aspect and assert that the
 * matching message is reported. Mutations that break one rule may cascade into related messages;
 * tests only require the expected message to be present.
 */
const MAP: string[] = [
  '#########',
  '#.......#',
  '#.:.=.,.#',
  '#...~...#',
  '#.#...###',
  '#.....#.#',
  '#########',
];

const MUSIC: LevelMusicDef = {
  root: 0,
  scale: 'major',
  progression: [0, 3, 4, 0],
  tracks: [
    { role: 'bass', formula: 'pulse' },
    { role: 'drums', formula: 'pulse', genre: 'house' },
    { role: 'melody', formula: 'pulse', params: { density: 0.5 } },
    { role: 'chord', formula: 'pulse' },
  ],
};

function baseEntities(): EntityDef[] {
  return [
    { kind: 'switch', id: 'sw1', x: 1.5, y: 3.5 },
    { kind: 'plate', id: 'p1', c: 3, r: 5 },
    { kind: 'breakable', id: 'b1', c: 4, r: 3, threshold: 2 },
    { kind: 'door', id: 'd1', cells: [{ c: 7, r: 3 }], openWhen: { sig: 'sw1' } },
    { kind: 'laser', id: 'l1', from: { x: 2.5, y: 1.5 }, to: { x: 6.5, y: 1.5 }, onWhen: { not: { sig: 'sw1' } } },
    { kind: 'core', id: 'c1', x: 3.5, y: 1.5, threshold: 1 },
    { kind: 'exit', id: 'x1', c: 7, r: 1, w: 1, h: 1 },
    { kind: 'enemy', id: 'g1', type: 'grunt', x: 4.5, y: 5.5 },
    { kind: 'enemy', id: 't1', type: 'turret', x: 5.5, y: 5.5, wakeWhen: { sig: 'dead:g1' } },
    { kind: 'decor', type: 'crate', x: 1.5, y: 5.5 },
  ];
}

function makeLevel(overrides: Partial<LevelDef> = {}): LevelDef {
  return {
    id: 'lvl-a',
    index: 0,
    name: 'Test Room',
    tagline: 'A room for tests.',
    theme: 'upper',
    bpm: 120,
    bars: 8,
    horizonBars: 16,
    maxTapes: 2,
    speeds: [0.5, 1, 2, 4],
    endModes: ['stop', 'repeat', 'reverse'],
    map: MAP.slice(),
    start: { x: 1.5, y: 1.5 },
    entities: baseEntities(),
    objective: { type: 'eliminate', text: 'Clear the room' },
    music: MUSIC,
    loot: ['gear-a'],
    briefing: ['Record a take.'],
    hints: { 1: 'Stand on the plate.' },
    ...overrides,
  };
}

/** Replaces the entity with the given id, merging `changes` over it. */
function withEntity(id: string, changes: Record<string, unknown>): LevelDef {
  const entities = baseEntities().map((e) =>
    'id' in e && e.id === id ? ({ ...e, ...changes } as EntityDef) : e,
  );
  return makeLevel({ entities });
}

/** Removes every entity of the given kind. */
function withoutKind(kind: EntityDef['kind']): LevelDef {
  return makeLevel({ entities: baseEntities().filter((e) => e.kind !== kind) });
}

function problemsOf(level: LevelDef): string[] {
  return validateLevel(level).filter(isProblem);
}

function expectProblem(level: LevelDef, pattern: RegExp): void {
  const problems = problemsOf(level);
  expect(
    problems.some((p) => pattern.test(p)),
    `expected a problem matching ${pattern}; got:\n${problems.join('\n') || '(none)'}`,
  ).toBe(true);
}

function objective(value: unknown): ObjectiveDef {
  return value as ObjectiveDef;
}

describe('validateLevel: valid fixture', () => {
  it('reports nothing for a level that satisfies every rule', () => {
    expect(validateLevel(makeLevel())).toEqual([]);
  });

  it('reports a note, not a problem, when the horizon is shorter than one pass of the slowest speed', () => {
    const level = makeLevel({ speeds: [1, 2], horizonBars: 6 });
    const messages = validateLevel(level);
    expect(messages.some((m) => m.startsWith('note: ') && /slowest offered speed/.test(m))).toBe(true);
    expect(problemsOf(level)).toEqual([]);
  });
});

describe('time and tempo', () => {
  it('rejects a bpm where 3600 / bpm is not an integer', () => {
    expectProblem(makeLevel({ bpm: 7 }), /3600 \/ bpm must be an integer/);
  });

  it('rejects non-positive bars', () => {
    expectProblem(makeLevel({ bars: 0 }), /bars must be a positive integer/);
  });

  it('rejects a fractional horizonBars', () => {
    expectProblem(makeLevel({ horizonBars: 10.5 }), /horizonBars must be a positive integer/);
  });

  it('rejects a horizon shorter than one pass of the fastest offered speed', () => {
    expectProblem(makeLevel({ horizonBars: 1 }), /shorter than one pass of the fastest speed/);
  });
});

describe('tapes, speeds and end modes', () => {
  it('rejects maxTapes outside 1..4', () => {
    expectProblem(makeLevel({ maxTapes: 5 as LevelDef['maxTapes'] }), /maxTapes must be an integer 1\.\.4/);
  });

  it('rejects a speed that is not in ALL_SPEEDS', () => {
    expectProblem(makeLevel({ speeds: [1, 3] as LevelDef['speeds'] }), /must be a power of two from ALL_SPEEDS/);
  });

  it('rejects duplicate speeds', () => {
    expectProblem(makeLevel({ speeds: [1, 1] }), /speeds lists 1 more than once/);
  });

  it('rejects an empty speeds list', () => {
    expectProblem(makeLevel({ speeds: [] }), /speeds must not be empty/);
  });

  it('rejects duplicate end modes', () => {
    expectProblem(makeLevel({ endModes: ['stop', 'stop'] }), /endModes lists "stop" more than once/);
  });

  it('rejects an unknown end mode', () => {
    expectProblem(makeLevel({ endModes: ['spin'] as unknown as LevelDef['endModes'] }), /must be one of stop, repeat, reverse/);
  });

  it('rejects an empty end mode list', () => {
    expectProblem(makeLevel({ endModes: [] }), /endModes must not be empty/);
  });
});

describe('map', () => {
  it('rejects an empty map', () => {
    expectProblem(makeLevel({ map: [] }), /map must be a non-empty array/);
  });

  it('rejects a non-rectangular map', () => {
    const map = MAP.slice();
    map[3] = '#...~...';
    expectProblem(makeLevel({ map }), /map row 3 has length 8, expected 9/);
  });

  it('rejects characters outside the documented set', () => {
    const map = MAP.slice();
    map[1] = '#.......X';
    expectProblem(makeLevel({ map }), /undocumented characters "X"/);
  });

  it('rejects a walkable border that the start can reach', () => {
    const map = MAP.slice();
    map[0] = '###.#####';
    expectProblem(makeLevel({ map }), /walkable area leaks past the map edge at \(3,0\)/);
  });

  it('accepts a walkable border tile that the start cannot reach', () => {
    // The corner floor tile touches only walls, so it is sealed off by void and walls.
    const map = MAP.slice();
    map[0] = '.########';
    expect(problemsOf(makeLevel({ map }))).toEqual([]);
  });
});

describe('start and positions', () => {
  it('rejects a start on a wall tile', () => {
    expectProblem(makeLevel({ start: { x: 2.5, y: 4.5 } }), /start tile \(2,4\) is not a walkable floor tile/);
  });

  it('rejects a start outside the map', () => {
    expectProblem(makeLevel({ start: { x: 99, y: 1 } }), /start \(99, 1\) is outside the map/);
  });

  it('rejects an entity position outside the map', () => {
    expectProblem(withEntity('g1', { x: 20 }), /enemy "g1": position \(20, 5\.5\) is outside the map/);
  });

  it('rejects an enemy standing on a wall tile', () => {
    expectProblem(withEntity('g1', { x: 2.5, y: 4.5 }), /enemy "g1": tile \(2,4\) is '#', not a floor tile/);
  });

  it('rejects a switch on a low barrier', () => {
    expectProblem(withEntity('sw1', { x: 4.5, y: 2.5 }), /switch "sw1": tile \(4,2\) is '=', not a floor tile/);
  });

  it('rejects a breakable placed on a wall', () => {
    expectProblem(
      makeLevel({ entities: baseEntities().map((e) => (e.kind === 'breakable' ? { ...e, c: 2, r: 4 } : e)) }),
      /breakable "b1": cell \(2,4\) is '#', not a floor tile/,
    );
  });

  it('rejects a door cell placed on a wall', () => {
    expectProblem(withEntity('d1', { cells: [{ c: 0, r: 0 }] }), /door "d1": cell \(0,0\) is '#', not a floor tile/);
  });

  it('rejects a laser endpoint outside the map', () => {
    expectProblem(withEntity('l1', { to: { x: 12, y: 1.5 } }), /laser "l1"\.to: position \(12, 1\.5\) is outside the map/);
  });

  it('rejects an exit rectangle that extends past the map', () => {
    expectProblem(withEntity('x1', { w: 3 }), /exit "x1": cell \(9,1\) is outside the map/);
  });
});

describe('solid occupancy', () => {
  it('rejects two solid entities on one tile', () => {
    const level = makeLevel({
      entities: [...baseEntities(), { kind: 'breakable', id: 'b2', c: 1, r: 3, threshold: 1 }],
    });
    expectProblem(level, /breakable "b2" and switch "sw1" share tile \(1,3\)/);
  });

  it('allows a body to stand on a plate', () => {
    const level = makeLevel({
      entities: [...baseEntities(), { kind: 'enemy', id: 'g2', type: 'grunt', x: 3.5, y: 5.5 }],
    });
    expect(problemsOf(level)).toEqual([]);
  });
});

describe('ids and signals', () => {
  it('rejects duplicate ids across entity kinds', () => {
    expectProblem(withEntity('c1', { id: 'sw1' }), /duplicate id "sw1" \(switch and core\)/);
  });

  it('rejects a signal that no entity produces', () => {
    expectProblem(withEntity('d1', { openWhen: { sig: 'nope' } }), /signal "nope" is not produced/);
  });

  it('rejects a dead: reference to an enemy that does not exist', () => {
    expectProblem(withEntity('t1', { wakeWhen: { sig: 'dead:ghost' } }), /refers to enemy "ghost", which does not exist/);
  });

  it('accepts a dead: reference to an existing enemy', () => {
    expect(problemsOf(makeLevel())).toEqual([]);
  });

  it('rejects an expression node with two operators', () => {
    expectProblem(withEntity('d1', { openWhen: { sig: 'sw1', const: true } }), /exactly one operator \(has sig, const\)/);
  });

  it('rejects an unknown operator', () => {
    expectProblem(withEntity('d1', { openWhen: { nand: [] } }), /unknown signal operator "nand"/);
  });

  it('rejects an xor that does not have two operands', () => {
    expectProblem(withEntity('d1', { openWhen: { xor: [{ sig: 'sw1' }] } }), /xor needs exactly two expressions/);
  });

  it('rejects an empty and', () => {
    expectProblem(withEntity('d1', { openWhen: { and: [] } }), /and needs a non-empty array/);
  });

  it('rejects a non-boolean const', () => {
    expectProblem(withEntity('d1', { openWhen: { const: 'yes' } }), /const must be true or false/);
  });

  it('rejects a beat window with every <= 0', () => {
    expectProblem(withEntity('l1', { onWhen: { beat: { every: 0, from: 0, to: 0 } } }), /every > 0/);
  });

  it('rejects a beat window whose from is not below to', () => {
    expectProblem(withEntity('l1', { onWhen: { beat: { every: 4, from: 3, to: 2 } } }), /0 <= from < to <= every/);
  });

  it('rejects a beat window that ends after every', () => {
    expectProblem(withEntity('l1', { onWhen: { beat: { every: 4, from: 0, to: 5 } } }), /0 <= from < to <= every/);
  });

  it('accepts a well-formed beat window', () => {
    expect(problemsOf(withEntity('l1', { onWhen: { beat: { every: 4, from: 0, to: 2 } } }))).toEqual([]);
  });

  it('requires a door to have openWhen', () => {
    expectProblem(withEntity('d1', { openWhen: undefined }), /door "d1": openWhen is required/);
  });
});

describe('objective', () => {
  it('rejects eliminate with no enemies and no targets', () => {
    expectProblem(withoutKind('enemy'), /eliminate objective needs at least one enemy/);
  });

  it('rejects eliminate targets that are not enemies', () => {
    expectProblem(makeLevel({ objective: objective({ type: 'eliminate', text: 'Go', targets: ['ghost'] }) }), /objective target "ghost" is not a enemy/);
  });

  it('rejects reach without an exit', () => {
    expectProblem(makeLevel({ entities: baseEntities().filter((e) => e.kind !== 'exit'), objective: objective({ type: 'reach', text: 'Get out' }) }), /reach objective needs at least one exit/);
  });

  it('rejects activate without cores', () => {
    expectProblem(makeLevel({ entities: baseEntities().filter((e) => e.kind !== 'core'), objective: objective({ type: 'activate', text: 'Light up' }) }), /activate objective needs at least one core/);
  });

  it('rejects boss without exactly one boss enemy', () => {
    expectProblem(makeLevel({ objective: objective({ type: 'boss', text: 'Defeat it' }) }), /boss objective needs exactly one boss enemy \(found 0\)/);
  });

  it('rejects signal without a when expression', () => {
    expectProblem(makeLevel({ objective: objective({ type: 'signal', text: 'Wait' }) }), /signal objective needs a "when" expression/);
  });

  it('rejects an objective when expression with an unproduced signal', () => {
    expectProblem(makeLevel({ objective: objective({ type: 'signal', text: 'Wait', when: { sig: 'ghost' } }) }), /signal "ghost" is not produced/);
  });

  it('accepts a signal objective whose when is a produced signal', () => {
    expect(problemsOf(makeLevel({ objective: objective({ type: 'signal', text: 'Wait', when: { sig: 'dead:g1' } }) }))).toEqual([]);
  });
});

describe('reachability', () => {
  it('reports an enemy sealed off from the start', () => {
    expectProblem(withEntity('g1', { x: 7.5, y: 5.5 }), /enemy "g1" is unreachable from the start/);
  });

  it('treats a closed door as passable when checking reachability', () => {
    // The only route into the pocket at (7,5) runs through the door cell at (7,4). DOORS are
    // passable for reachability (ARCHITECTURE: "treating doors and breakables as passable"), so the
    // grunt behind it must still count as reachable.
    const map = MAP.slice();
    map[4] = '#.#...#.#';
    const entities = baseEntities().map((e): EntityDef => {
      if (e.kind === 'door') return { ...e, cells: [{ c: 7, r: 4 }] };
      if (e.kind === 'enemy' && e.id === 'g1') return { ...e, x: 7.5, y: 5.5 };
      return e;
    });
    expect(problemsOf(makeLevel({ map, entities }))).toEqual([]);
  });
});

describe('music', () => {
  it('rejects a track list that does not have four entries', () => {
    const music = { ...MUSIC, tracks: MUSIC.tracks.slice(0, 3) } as unknown as LevelMusicDef;
    expectProblem(makeLevel({ music }), /tracks must have exactly four entries \(found 3\)/);
  });

  it('rejects an unknown track role', () => {
    const tracks = [...MUSIC.tracks] as LevelMusicDef['tracks'];
    tracks[0] = { role: 'lead' as 'bass', formula: 'pulse' };
    expectProblem(makeLevel({ music: { ...MUSIC, tracks } }), /role "lead" is not one of/);
  });

  it('rejects a root outside 0..11', () => {
    expectProblem(makeLevel({ music: { ...MUSIC, root: 12 } }), /music\.root must be an integer 0\.\.11/);
  });

  it('rejects an empty progression', () => {
    expectProblem(makeLevel({ music: { ...MUSIC, progression: [] } }), /progression must be a non-empty array/);
  });

  it('rejects a progression degree outside 0..6', () => {
    expectProblem(makeLevel({ music: { ...MUSIC, progression: [0, 7] } }), /progression degree 7 must be an integer 0\.\.6/);
  });
});

describe('briefing, loot and hints', () => {
  it('rejects an empty briefing', () => {
    expectProblem(makeLevel({ briefing: [] }), /briefing needs at least one line/);
  });

  it('rejects an empty loot id', () => {
    expectProblem(makeLevel({ loot: [''] }), /every loot id must be a non-empty string/);
  });

  it('rejects a hint keyed by something other than a tape number', () => {
    expectProblem(makeLevel({ hints: { 7: 'Too many' } }), /hint key "7" must be a tape number 1\.\.4/);
  });
});

describe('validateCampaign', () => {
  it('accepts an ordered campaign of valid levels', () => {
    const levels = [makeLevel({ id: 'lvl-a', index: 1 }), makeLevel({ id: 'lvl-b', index: 2 })];
    expect(validateCampaign(levels)).toEqual([]);
  });

  it('reports duplicate level ids', () => {
    const levels = [makeLevel({ id: 'dup', index: 1 }), makeLevel({ id: 'dup', index: 2 })];
    expect(validateCampaign(levels)).toEqual(expect.arrayContaining([expect.stringMatching(/duplicate level id "dup"/)]));
  });

  it('reports index values that are not 1..n in order (levels are numbered like their files)', () => {
    const levels = [makeLevel({ id: 'lvl-a', index: 1 }), makeLevel({ id: 'lvl-b', index: 3 })];
    expect(validateCampaign(levels)).toEqual(['lvl-b: index is 3, expected 2 (campaign order is index 1..2)']);
  });

  it('prefixes every level problem with the level id', () => {
    const levels = [makeLevel({ id: 'lvl-a', index: 1 }), makeLevel({ id: 'lvl-b', index: 2, bpm: 7 })];
    const messages = validateCampaign(levels);
    expect(messages.some((m) => m.startsWith('lvl-b: 3600 / bpm must be an integer'))).toBe(true);
  });

  it('reports an empty campaign', () => {
    expect(validateCampaign([])).toEqual(['campaign has no levels']);
  });
});
