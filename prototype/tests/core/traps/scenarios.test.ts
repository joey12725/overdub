/**
 * Traps as puzzle pieces: machines turned against enemies, chained machines, determinism, and the
 * guarantee that a level without traps is untouched (docs/TRAPS.md).
 */
import { describe, expect, it } from 'vitest';
import { createSim } from '../../../src/core/index';
import { TRAP_EVENT } from '../../../src/core/traps';
import type { EntityDef, LevelDef, Tape } from '../../../src/core/types';
import { baseLoadout } from '../../helpers/loadout';
import { eventsOf, pathTape, recordTake, resolve, script } from '../../helpers/script';
import { ALWAYS, beats, enemyAt, lastFrame, room, sleeper, stand, trapEvents } from './util';

const belt: EntityDef = { kind: 'conveyor', id: 'belt', cells: [3, 4, 5, 6].map((c) => ({ c, r: 5 })), dir: 'e', speed: 2 };

describe('machines turned against enemies', () => {
  it('a conveyor delivers a sleeping grunt into a recorded swing', () => {
    // The belt drops the grunt at x = 7 on substep 420. Tape A stands at x = 8 and swings west on
    // local tick 110: hit volume live for ticks [116, 120) = substeps [464, 480).
    const swing: Tape = pathTape({ index: 0, speed: 1, ticks: 240, path: [{ tick: 0, x: 8, y: 5.5 }], events: [{ tick: 110, kind: 'light', dir: Math.PI }] });
    const withBelt = resolve(room([belt, sleeper('g', 'grunt', 3.5, 5.5)]), [swing]);
    const kill = eventsOf(withBelt.events, 'kill');
    expect(kill.map((e) => [e.id, e.tape, e.detail])).toEqual([['g', 0, 'light']]);
    expect(kill[0].sub).toBe(464);
    expect(kill[0].x).toBeGreaterThanOrEqual(7);
    expect(withBelt.outcome.win).toBe(true);
    // Without the machine the same recording swings at nothing.
    const without = resolve(room([sleeper('g', 'grunt', 3.5, 5.5)]), [swing]);
    expect(eventsOf(without.events, 'kill')).toHaveLength(0);
    expect(eventsOf(without.events, 'whiff', { tape: 0 })).toHaveLength(1);
    expect(without.outcome.win).toBe(false);
  });

  it('a dart launcher kills an enemy that a later tape knocked into its lane', () => {
    // The grunt sleeps just north of the lane along row 5. Tape B, at 0.5×, cannot kill it (momentum
    // 0.6: no damage) but shoves it 0.6 tiles south, into the lane; the next dart does the rest.
    const level = room([{ kind: 'dart', id: 'dl', c: 0, r: 5, dir: 'e', every: 2 }, sleeper('g', 'grunt', 6.5, 4.75)], { speeds: [0.5, 1] });
    const a = stand(0, 2.5, 2.5);
    const b: Tape = pathTape({ index: 1, speed: 0.5, ticks: 240, path: [{ tick: 0, x: 6.5, y: 3.9 }], events: [{ tick: 20, kind: 'light', dir: Math.PI / 2 }] });
    const alone = resolve(level, [a]);
    expect(eventsOf(alone.events, 'kill')).toHaveLength(0);
    expect(alone.outcome.win).toBe(false);
    const both = resolve(level, [a, b]);
    const clang = eventsOf(both.events, 'clang', { id: 'g' });
    expect(clang).toHaveLength(1);
    const landed = enemyAt(both, clang[0].sub + 60, 'g');
    expect(landed.y).toBeCloseTo(5.35, 4);
    const kill = eventsOf(both.events, 'kill');
    expect(kill.map((e) => [e.id, e.detail, e.tape])).toEqual([['g', 'dart', undefined]]);
    expect(kill[0].sub).toBeGreaterThan(clang[0].sub);
    expect(both.outcome.win).toBe(true);
    expect(both.outcome.survivors).toEqual([0, 1]);
  });

  it('an awake grunt hunting a self walks onto raised spikes: the trap does not care who it is', () => {
    const level = room([{ kind: 'spikes', id: 'sp', cells: [{ c: 5, r: 5 }, { c: 6, r: 5 }], upWhen: ALWAYS }, { kind: 'enemy', id: 'g', type: 'grunt', x: 2.5, y: 5.5 }]);
    const res = resolve(level, [stand(0, 9.5, 5.5)]);
    const kill = eventsOf(res.events, 'kill');
    expect(kill.map((e) => [e.id, e.detail])).toEqual([['g', 'spikes']]);
    // 2.5 tiles at 2.2 tiles per second.
    expect(kill[0].sub).toBeGreaterThan(260);
    expect(kill[0].sub).toBeLessThan(290);
    expect(res.outcome.win).toBe(true);
    expect(res.outcome.survivors).toEqual([0]);
  });
});

describe('chained machines', () => {
  /** belt → enemies-only tripwire → (door) and → relay (next beat + 1) → crusher. */
  const chain = (): LevelDef =>
    room([
      belt,
      sleeper('g', 'grunt', 3.5, 5.5),
      { kind: 'sensor', id: 'trip', from: { x: 4.5, y: 5 }, to: { x: 4.5, y: 6 }, detects: 'enemies' },
      { kind: 'door', id: 'gate', cells: [{ c: 9, r: 8 }], openWhen: { sig: 'trip' } },
      { kind: 'relay', id: 'slam', trigger: { sig: 'trip' }, quantize: 1, delay: 1, hold: 1 },
      { kind: 'crusher', id: 'cr', cells: [{ c: 5, r: 5 }], extendWhen: { sig: 'slam' } },
    ]);

  it('an enemy riding a belt through a sensor opens a door and fires a crusher onto itself a beat later', () => {
    const res = resolve(chain(), [stand(0, 2.5, 2.5)]);
    // The grunt (radius 0.32) breaks the beam at x = 4.5 once its centre passes 4.18: substep 82.
    const trip = trapEvents(res, 'trip');
    expect(trip[0]).toEqual([82, 'sensor:on']);
    // Same substep: the door starts opening (half open 17 substeps later) and the relay arms.
    expect(eventsOf(res.events, 'door', { id: 'gate' })[0]).toMatchObject({ sub: 82 + 17, detail: 'open' });
    expect(trapEvents(res, 'slam')).toEqual([
      [82, 'relay:armed'],
      [239, 'relay:on'],
      [359, 'relay:off'],
    ]);
    // Quantised to beat 1, plus one beat: the stroke lands on beat 2 with the grunt at x = 5.5.
    expect(trapEvents(res, 'cr').filter(([, d]) => d === 'crusher:slam')).toEqual([[239, 'crusher:slam']]);
    const kill = eventsOf(res.events, 'kill');
    expect(kill.map((e) => [e.id, e.sub, e.detail])).toEqual([['g', 239, 'crusher']]);
    expect(kill[0].x).toBeCloseTo(5.5, 5);
    expect(res.outcome.win).toBe(true);
  });

  it('no self can start that chain: the tripwire only sees enemies', () => {
    const level = chain();
    level.entities = level.entities.filter((e) => e.kind !== 'enemy' && e.kind !== 'conveyor');
    const crosser = pathTape({ index: 0, speed: 1, ticks: 240, path: [{ tick: 0, x: 3.5, y: 5.5 }, { tick: 60, x: 7.5, y: 5.5 }] });
    const res = resolve(level, [crosser]);
    expect(res.events.filter((e) => e.type === TRAP_EVENT)).toEqual([]);
    expect(eventsOf(res.events, 'door')).toHaveLength(0);
  });
});

// ───────────────────────────── determinism ─────────────────────────────

/** One of everything, with awake enemies, so every system interacts. */
function gauntlet(): LevelDef {
  return room(
    [
      { kind: 'switch', id: 'sw', x: 2.5, y: 2.5 },
      { kind: 'door', id: 'd', cells: [{ c: 9, r: 8 }], openWhen: { or: [{ sig: 'trip' }, { sig: 'bm' }] } },
      { kind: 'spikes', id: 'sp', cells: [{ c: 5, r: 2 }, { c: 6, r: 2 }], upWhen: beats(2, 1, 2) },
      { kind: 'crusher', id: 'cr', cells: [{ c: 8, r: 3 }, { c: 8, r: 4 }], extendWhen: { sig: 'rl' } },
      { kind: 'conveyor', id: 'belt', cells: [3, 4, 5, 6].map((c) => ({ c, r: 5 })), dir: 'e', reverseWhen: { sig: 'sw' } },
      { kind: 'flame', id: 'fl', c: 0, r: 7, dir: 'e', range: 6, onWhen: beats(4, 2, 3) },
      { kind: 'dart', id: 'dl', c: 11, r: 3, dir: 'w', every: 2, offset: 1 },
      { kind: 'bumper', id: 'bm', c: 7, r: 5, dir: 'n', fireWhen: beats(4, 3, 3.5) },
      { kind: 'sensor', id: 'trip', from: { x: 4.5, y: 4 }, to: { x: 4.5, y: 7 } },
      { kind: 'relay', id: 'rl', trigger: { sig: 'trip' }, delay: 1 },
      { kind: 'magnet', id: 'mag', x: 9.5, y: 6.5, radius: 3, onWhen: beats(8, 4, 8) },
      { kind: 'enemy', id: 'g1', type: 'grunt', x: 3.5, y: 5.5 },
      { kind: 'enemy', id: 'g2', type: 'stalker', x: 9.5, y: 2.5 },
      { kind: 'enemy', id: 't1', type: 'turret', x: 10.5, y: 8.5 },
      { kind: 'enemy', id: 'b1', type: 'brute', x: 6.5, y: 7.5 },
      { kind: 'enemy', id: 'dr', type: 'drone', x: 8.5, y: 6.5 },
    ],
    { start: { x: 1.5, y: 5.5 }, speeds: [1, 2], bars: 4 },
  );
}

describe('determinism', () => {
  const wander = (): ReturnType<typeof script> =>
    script().run(0, 60, 1, 0).run(60, 110, 0, -1).run(110, 200, 1, 0.4).run(200, 300, -1, 0.2).run(300, 480, 0.3, 1).press(40, 'light').press(130, 'dodge').press(210, 'heavy').press(330, 'ranged').press(400, 'interact');

  it('the same tapes in a level with every trap resolve to the same frames and events, bit for bit', () => {
    const level = gauntlet();
    const a = recordTake({ level, index: 0, speed: 1, script: wander() });
    const b = recordTake({ level, tapes: [a.tape], index: 1, speed: 2, script: script().run(0, 200, 0.5, -1).press(90, 'heavy') });
    const r1 = resolve(level, [a.tape, b.tape]);
    const r2 = resolve(gauntlet(), [a.tape, b.tape]);
    expect(r1.events.some((e) => e.type === TRAP_EVENT)).toBe(true);
    expect(r1.frames.length).toBeGreaterThan(400);
    expect(JSON.stringify(r2.frames)).toBe(JSON.stringify(r1.frames));
    expect(JSON.stringify(r2.events)).toBe(JSON.stringify(r1.events));
    expect(r2.outcome).toEqual(r1.outcome);
  });

  it('recording the same inputs twice gives the same tape, belts and bumpers included', () => {
    const level = gauntlet();
    const a = recordTake({ level, index: 0, speed: 1, script: wander() });
    const b = recordTake({ level: gauntlet(), index: 0, speed: 1, script: wander() });
    expect(Array.from(b.tape.pos)).toEqual(Array.from(a.tape.pos));
    expect(b.tape.events).toEqual(a.tape.events);
    expect(JSON.stringify(b.events)).toBe(JSON.stringify(a.events));
  });

  it('a take that rode a belt and a bumper plays back as the same motion against the same world', () => {
    // No enemies and no hazards on the route: playback must reproduce what the player saw.
    const level = room(
      [belt, { kind: 'bumper', id: 'bm', c: 7, r: 5, dir: 's', power: 2, fireWhen: beats(8, 6, 6.5) }],
      { start: { x: 2.5, y: 5.5 } },
    );
    const take = recordTake({ level, index: 0, speed: 1, script: script().run(0, 12, 1, 0).run(200, 230, -1, 0) });
    // Walks onto the belt, rides it to x = 7 (the bumper tile), is thrown south on beat 6, walks west.
    expect(take.events.find((e) => e.type === TRAP_EVENT && e.detail === 'bumper:fire')!.power).toBe(1);
    const res = resolve(level, [take.tape]);
    for (let i = 0; i < take.frames.length; i++) {
      const live = take.frames[i].actors[0];
      const played = res.frames[i + 1].actors[0];
      expect(res.frames[i + 1].sub).toBe(take.frames[i].sub);
      expect([played.x, played.y]).toEqual([live.x, live.y]);
      expect(played.synced).toBe(true);
    }
    expect(eventsOf(res.events, 'desync')).toHaveLength(0);
  });
});

describe('strictly additive', () => {
  it('a level with no traps has an inert trap system and the classic mechanism snapshot', () => {
    const level = room([
      { kind: 'switch', id: 'sw', x: 2.5, y: 2.5 },
      { kind: 'door', id: 'd', cells: [{ c: 6, r: 5 }], openWhen: { sig: 'sw' } },
      { kind: 'laser', id: 'lz', from: { x: 1, y: 7.5 }, to: { x: 11, y: 7.5 }, onWhen: beats(4, 0, 1) },
      sleeper('g', 'grunt', 8.5, 5.5),
    ]);
    const sim = createSim({ level, loadout: baseLoadout(), tapes: [stand(0, 2.5, 3.2)] });
    for (let i = 0; i < 300; i++) sim.stepSub();
    expect(sim.snapshot().mechs.map((m) => m.kind)).toEqual(['switch', 'door', 'laser']);
    expect(Object.keys(sim.snapshot().mechs[1]).sort()).toEqual(['id', 'kind', 'on', 't']);
    expect(sim.drainEvents().some((e) => e.type === TRAP_EVENT)).toBe(false);
    expect((sim as unknown as { traps: { count: number } }).traps.count).toBe(0);
  });

  it('trap snapshots come after the classic mechanisms, in entity order', () => {
    const level = room([
      { kind: 'spikes', id: 'sp', cells: [{ c: 5, r: 2 }], upWhen: ALWAYS },
      { kind: 'switch', id: 'sw', x: 2.5, y: 2.5 },
      { kind: 'relay', id: 'rl', trigger: { sig: 'sw' } },
      { kind: 'door', id: 'd', cells: [{ c: 6, r: 5 }], openWhen: { sig: 'rl' } },
      { kind: 'magnet', id: 'mag', x: 5.5, y: 5.5, radius: 2, onWhen: ALWAYS },
    ]);
    const sim = createSim({ level, loadout: baseLoadout(), tapes: [stand(0, 2.5, 3.2)] });
    expect(sim.snapshot().mechs.map((m) => m.id)).toEqual(['sw', 'd', 'sp', 'rl', 'mag']);
  });

  it('survivors and notes: a self killed by a machine is reported in the game’s own terms', () => {
    const res = resolve(room([{ kind: 'flame', id: 'fl', c: 0, r: 5, dir: 'e', range: 8, onWhen: beats(4, 1, 2) }, sleeper('g', 'grunt', 9.5, 2.5)]), [stand(0, 3.5, 5.5)]);
    expect(res.outcome).toMatchObject({ win: false, survivors: [] });
    expect(res.outcome.notes.join(' ')).toMatch(/burned by flame jet fl/);
    expect(lastFrame(res).objective.survivors).toBe(0);
  });
});
