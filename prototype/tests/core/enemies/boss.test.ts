/**
 * The outside-the-loop boss (BOSS-01..03, HEALTH-03, AI-07).
 *
 * bpm 120 → 120 substeps per beat. A 1× tape advances 4 substeps per local tick, a 2× tape 2.
 * Baseline heavy: windup 16 ticks, so a heavy pressed on tick t connects on substep (t + 16) · m.
 */
import { describe, expect, it } from 'vitest';
import { buildBossMemory, createSim, resolveEncounter } from '../../../src/core/index';
import { BOSS_RECALL_RADIUS, BOSS_RECALL_TELEGRAPH_BEATS, bossPhaseFor } from '../../../src/core/enemies/boss';
import type { BossMemory, EnemyDef, LevelDef, Tape } from '../../../src/core/types';
import { makeLevel } from '../../helpers/levels';
import { baseLoadout } from '../../helpers/loadout';
import { eventsOf, frameAt, pathTape, resolve } from '../../helpers/script';

const SPB = 120;

function deepFreeze<T>(o: T): T {
  if (o && typeof o === 'object' && !Object.isFrozen(o)) {
    Object.freeze(o);
    for (const v of Object.values(o as Record<string, unknown>)) deepFreeze(v);
  }
  return o;
}

function fight(level: LevelDef, tapes: Tape[], bossMemory?: BossMemory) {
  return resolveEncounter({ level, loadout: baseLoadout(), tapes, bossMemory });
}

// ───────────────────────────── coordination (BOSS-03) ─────────────────────────────

describe('armour and attention (BOSS-03)', () => {
  const boss: EnemyDef = { kind: 'enemy', id: 'b1', type: 'boss', x: 6, y: 5, facing: Math.PI, hp: 16 };
  const level = makeLevel({ speeds: [1, 2], bars: 2, start: { x: 4.7, y: 5 }, entities: [boss], objective: { type: 'boss', text: 'Defeat the boss' } });
  // A holds its attention: the nearest self, right in front of it (west).
  const holder = pathTape({ index: 0, speed: 1, ticks: 240, path: [{ tick: 0, x: 4.7, y: 5 }] });
  // B stands behind it (east) and lands 2× heavies on its back (momentum 4 = 4 damage each).
  const striker = (index: 0 | 1 = 1) =>
    pathTape({ index, speed: 2, ticks: 240, path: [{ tick: 0, x: 7.9, y: 5 }], events: [40, 80, 120, 160].map((tick) => ({ tick, kind: 'heavy' as const, dir: Math.PI })) });

  it('a coordinated plan beats it: one self holds its eye, another strikes its back', () => {
    const res = resolve(level, [holder, striker()]);
    const hits = eventsOf(res.events, 'hit', { id: 'b1' });
    expect(hits.map((h) => h.tape)).toEqual([1, 1, 1, 1]);
    expect(eventsOf(res.events, 'kill', { id: 'b1' }).map((k) => k.tape)).toEqual([1]);
    expect(eventsOf(res.events, 'bossPhase', { id: 'b1' }).map((p) => p.power)).toEqual([2, 3]);
    expect(res.outcome.win).toBe(true);
    expect(res.outcome.survivors).toEqual([0, 1]);
    // The health bar reads as a fraction (objective progress), phase by phase.
    expect(frameAt(res, hits[1].sub + 2).enemies[0]).toMatchObject({ hp: 8, bossPhase: 2 });
    expect(frameAt(res, hits[2].sub + 2).enemies[0]).toMatchObject({ hp: 4, bossPhase: 3 });
  });

  it('one self alone can never hurt it: whoever is alone holds its attention', () => {
    const res = resolve(level, [striker(0)]);
    expect(eventsOf(res.events, 'hit', { id: 'b1' })).toHaveLength(0);
    const clangs = eventsOf(res.events, 'clang', { id: 'b1' });
    expect(clangs.length).toBeGreaterThan(0);
    expect(clangs.every((c) => c.detail === 'armour')).toBe(true);
    expect(res.frames.at(-1)!.enemies[0].hp).toBe(16);
    expect(res.outcome.win).toBe(false);
    // And it fights back: the lone self is cleaved on the bar grid.
    const death = eventsOf(res.events, 'selfDeath')[0];
    expect(death.detail).toBe('struck by boss b1');
    expect(death.sub % (4 * SPB)).toBe(0);
  });

  it('the self holding its attention is blocked even with a partner present; so is a frontal hit', () => {
    // A (nearest) also swings; only B's back hits land.
    const swingingHolder = pathTape({ index: 0, speed: 1, ticks: 240, path: [{ tick: 0, x: 4.7, y: 5 }], events: [{ tick: 20, kind: 'heavy', dir: 0 }] });
    const res = resolve(level, [swingingHolder, striker()]);
    expect(eventsOf(res.events, 'clang', { id: 'b1', tape: 0 }).map((c) => c.detail)).toEqual(['armour']);
    expect(eventsOf(res.events, 'hit', { id: 'b1', tape: 0 })).toHaveLength(0);
    // B striking from the FRONT (same side as A, but farther) is armour too.
    const front = pathTape({ index: 1, speed: 2, ticks: 240, path: [{ tick: 0, x: 4.3, y: 5.6 }], events: [{ tick: 40, kind: 'heavy', dir: Math.atan2(5 - 5.6, 6 - 4.3) }] });
    const res2 = resolve(level, [holder, front]);
    expect(eventsOf(res2.events, 'hit', { id: 'b1' })).toHaveLength(0);
    expect(eventsOf(res2.events, 'clang', { id: 'b1' }).map((c) => c.detail)).toEqual(['armour']);
  });

  it('its phases follow the health bar', () => {
    expect([16, 11, 10, 6, 5, 1].map((hp) => bossPhaseFor(hp, 16))).toEqual([1, 1, 2, 2, 3, 3]);
  });
});

// ───────────────────────────── phases and base pattern (HEALTH-03, AI-07) ─────────────────────────────

describe('phases change the base pattern', () => {
  const boss: EnemyDef = { kind: 'enemy', id: 'b1', type: 'boss', x: 6, y: 5, facing: Math.PI, hp: 12 };
  const level = makeLevel({ speeds: [1, 2], bars: 4, start: { x: 4.7, y: 5 }, entities: [boss], objective: { type: 'boss', text: 'Defeat the boss' } });
  const holder = pathTape({ index: 0, speed: 1, ticks: 480, path: [{ tick: 0, x: 4.7, y: 5 }] });
  // Two back hits (4 each): 12 → 8 (phase 2) → 4 (phase 3).
  const striker = pathTape({ index: 1, speed: 2, ticks: 480, path: [{ tick: 0, x: 7.9, y: 5 }], events: [40, 80].map((tick) => ({ tick, kind: 'heavy' as const, dir: Math.PI })) });

  const baseTelegraphs = (r: ReturnType<typeof resolve>) => eventsOf(r.events, 'enemyTelegraph', { id: 'b1' }).filter((t) => t.detail !== 'recall');

  it('phase 1 attacks once a bar with a cleave, telegraphed two beats ahead, landing on the bar line', () => {
    const res = resolve(level, [holder]);
    const tels = baseTelegraphs(res);
    expect(tels.length).toBeGreaterThan(0);
    expect(tels[0]).toMatchObject({ sub: 2 * SPB, detail: 'cleave' });
    const attacks = eventsOf(res.events, 'enemyAttack', { id: 'b1' });
    expect(attacks[0]).toMatchObject({ sub: 4 * SPB, detail: 'cleave' });
    expect(eventsOf(res.events, 'bossPhase')).toHaveLength(0);
    for (const t of tels) expect(t.detail).not.toBe('sweep');
  });

  it("phase 2 adds the sweep; phase 3 attacks every two beats; each change emits 'bossPhase'", () => {
    const res = resolve(level, [holder, striker]);
    const phases = eventsOf(res.events, 'bossPhase', { id: 'b1' });
    expect(phases.map((p) => [p.power, p.detail])).toEqual([
      [2, 'phase 2'],
      [3, 'phase 3'],
    ]);
    const hits = eventsOf(res.events, 'hit', { id: 'b1' });
    expect(phases.map((p) => p.sub)).toEqual(hits.map((h) => h.sub));
    const tels = baseTelegraphs(res).filter((t) => t.sub > phases[1].sub);
    expect(tels.length).toBeGreaterThanOrEqual(3);
    // Phase 3: one attack every 2 beats, alternating strike and sweep.
    for (let i = 1; i < tels.length; i++) expect(tels[i].sub - tels[i - 1].sub).toBe(2 * SPB);
    expect(tels.some((t) => t.detail === 'sweep')).toBe(true);
    expect(tels.some((t) => t.detail === 'cleave' || t.detail === 'volley')).toBe(true);
    // Every landing is on a whole beat (AI-07).
    for (const a of eventsOf(res.events, 'enemyAttack', { id: 'b1' })) expect(a.sub % SPB).toBe(0);
    // The sweep is a ring of shockwave shots.
    const sweep = eventsOf(res.events, 'enemyAttack', { id: 'b1' }).find((a) => a.detail === 'sweep')!;
    expect(frameAt(res, sweep.sub + 4).projectiles.filter((p) => p.archetype === 'shock').length).toBeGreaterThan(8);
  });
});

// ───────────────────────────── memory (BOSS-01, BOSS-02) ─────────────────────────────

describe('memory: the boss acts on committed tapes', () => {
  // A pillar (column 10, rows 5..7) between the boss and A's waiting spot.
  const map = [
    '################',
    '#..............#',
    '#..............#',
    '#..............#',
    '#..............#',
    '#.........#....#',
    '#.........#....#',
    '#.........#....#',
    '#..............#',
    '#..............#',
    '#..............#',
    '################',
  ];
  const boss: EnemyDef = { kind: 'enemy', id: 'b1', type: 'boss', x: 7, y: 6.5, facing: 0, hp: 20 };
  const level = makeLevel({ map, speeds: [1, 2], bars: 2, start: { x: 3.5, y: 2.5 }, entities: [boss], objective: { type: 'boss', text: 'Defeat the boss' } });
  const spot = { x: 13.5, y: 6.5 };
  // Tape A (committed) runs round the pillar and waits behind it from beat 2 on.
  const tapeA = pathTape({
    index: 0,
    speed: 1,
    ticks: 240,
    path: [
      { tick: 0, x: 3.5, y: 2.5 },
      { tick: 30, x: 13.5, y: 2.5 },
      { tick: 60, x: spot.x, y: spot.y },
    ],
  });
  const memory = buildBossMemory(level, [tapeA]);
  // Tape B stands behind the boss (west, while it looks east at A's spot) and strikes east.
  const tapeB = pathTape({ index: 1, speed: 1, ticks: 240, path: [{ tick: 0, x: 3.5, y: 2.5 }, { tick: 25, x: 5.2, y: 6.5 }], events: [{ tick: 60, kind: 'heavy', dir: 0 }] });
  const landSub = 3 * SPB; // A's dwell starts on beat 2; the strike lands on its second beat
  const startSub = landSub - BOSS_RECALL_TELEGRAPH_BEATS * SPB;

  it('first take (no memory): only the base pattern; the pillar shelters A', () => {
    const res = fight(level, [tapeA]);
    expect(eventsOf(res.events, 'bossRecall')).toHaveLength(0);
    expect(res.frames.every((f) => f.enemies[0].bossRecall === false)).toBe(true);
    expect(eventsOf(res.events, 'selfDeath')).toHaveLength(0);
  });

  it('with memory it pre-empts the remembered dwell: telegraphed at the remembered place, then struck', () => {
    const res = fight(level, [tapeA], memory);
    const recalls = eventsOf(res.events, 'bossRecall', { id: 'b1' });
    expect(recalls.map((r) => [r.sub, r.tape, r.power, r.detail, r.x, r.y])).toEqual([[startSub, 0, 3, 'dwell', spot.x, spot.y]]);
    const tel = eventsOf(res.events, 'enemyTelegraph', { id: 'b1' }).find((t) => t.detail === 'recall')!;
    expect(tel.sub).toBe(startSub);
    // The telegraph starts while A is still on its way (beat 1): it is pre-emption, not reaction.
    const early = frameAt(res, startSub).actors[0];
    expect(Math.hypot(early.x - spot.x, early.y - spot.y)).toBeGreaterThan(BOSS_RECALL_RADIUS + 1);
    // The snapshot marks the whole commitment so the renderer can draw it as memory.
    const during = frameAt(res, startSub + 8).enemies[0];
    expect(during).toMatchObject({ state: 'telegraph', bossRecall: true, bossRecallTape: 0, bossRecallAt: spot });
    expect(frameAt(res, startSub - 8).enemies[0].bossRecall).toBe(false);
    const death = eventsOf(res.events, 'selfDeath', { tape: 0 });
    expect(death).toHaveLength(1);
    expect(death[0].sub).toBe(landSub);
    expect(death[0].detail).toBe('struck by boss b1 (remembering Tape A)');
    expect(eventsOf(res.events, 'enemyAttack', { id: 'b1' }).find((a) => a.detail === 'recall')).toMatchObject({ sub: landSub, x: spot.x, y: spot.y, tape: 0 });
  });

  it('later tapes exploit its commitment: while it punishes A’s old spot, B hits its back', () => {
    const blind = fight(level, [tapeA, tapeB]);
    const aware = fight(level, [tapeA, tapeB], memory);
    const hitSub = (60 + 16) * 4;
    // Without memory B is the nearest self, so B holds its attention: armour.
    expect(eventsOf(blind.events, 'clang', { id: 'b1', tape: 1 }).map((c) => [c.sub, c.detail])).toEqual([[hitSub, 'armour']]);
    expect(eventsOf(blind.events, 'hit', { id: 'b1' })).toHaveLength(0);
    // With memory its attention is on A's remembered spot: B's hit lands.
    expect(eventsOf(aware.events, 'hit', { id: 'b1', tape: 1 }).map((h) => h.sub)).toEqual([hitSub]);
    expect(frameAt(aware, hitSub + 4).enemies[0].hp).toBe(18);
  });

  it('a strong enough back hit during the telegraph cancels the memory strike (protecting the remembered tape)', () => {
    // 2× heavy: momentum 4 ≥ BOSS_STAGGER_MOMENTUM, connects on substep (100 + 16) · 2 = 232.
    const guard = pathTape({ index: 1, speed: 2, ticks: 240, path: [{ tick: 0, x: 3.5, y: 2.5 }, { tick: 50, x: 5.2, y: 6.5 }], events: [{ tick: 100, kind: 'heavy', dir: 0 }] });
    const res = fight(level, [tapeA, guard], memory);
    expect(eventsOf(res.events, 'bossRecall')).toHaveLength(1);
    expect(eventsOf(res.events, 'hit', { id: 'b1', tape: 1 })[0].sub).toBe(232);
    expect(eventsOf(res.events, 'enemyStagger', { id: 'b1' })).toHaveLength(1);
    expect(eventsOf(res.events, 'enemyAttack', { id: 'b1' }).filter((a) => a.detail === 'recall')).toHaveLength(0);
    expect(eventsOf(res.events, 'selfDeath', { tape: 0 })).toHaveLength(0);
    expect(frameAt(res, 240).enemies[0].bossRecall).toBe(false);
  });

  it('remembered attacks are pre-empted too, on the nearest whole beat', () => {
    // A committed tape that swings at beat ≈ 2.4 while passing through (it never stands still).
    const swinger = pathTape({
      index: 2,
      speed: 1,
      ticks: 240,
      path: [
        { tick: 0, x: 3.5, y: 2.5 },
        { tick: 240, x: 3.5, y: 9.5 },
      ],
      events: [{ tick: 72, kind: 'light', dir: 0 }],
    });
    const mem = buildBossMemory(level, [swinger]);
    const res = fight(level, [swinger], mem);
    const recalls = eventsOf(res.events, 'bossRecall', { id: 'b1' });
    expect(recalls.map((r) => [r.tape, r.detail, r.power])).toEqual([[2, 'attack', 2]]);
    expect(recalls[0].y).toBeCloseTo(2.5 + (7 * 72) / 240, 4);
  });

  it('identical memory gives an identical fight', () => {
    const one = fight(level, [tapeA, tapeB], buildBossMemory(level, [tapeA]));
    const two = fight(level, [tapeA, tapeB], structuredClone(memory));
    expect(two).toEqual(one);
  });

  it('a resolve, a replay and a recording never change the memory', () => {
    const frozen = deepFreeze(structuredClone(memory));
    const before = JSON.stringify(frozen);
    // Frozen: any write would throw in strict-mode module code.
    const a = fight(level, [tapeA, tapeB], frozen);
    const b = fight(level, [tapeA, tapeB], frozen);
    expect(b).toEqual(a);
    const sim = createSim({ level, loadout: baseLoadout(), tapes: [tapeA], live: { index: 1, speed: 1, endMode: 'stop' }, bossMemory: frozen });
    const idle = { moveX: 0, moveY: 0, aim: 0, light: false, heavy: false, dodge: false, ranged: false, interact: false, ability: false };
    while (!sim.done) sim.stepLocalTick(idle);
    expect(eventsOf(sim.drainEvents(), 'bossRecall')).toHaveLength(1);
    expect(JSON.stringify(frozen)).toBe(before);
  });

  it('the recording sees the same memory strikes as its authoritative resolve', () => {
    const sim = createSim({ level, loadout: baseLoadout(), tapes: [tapeA], live: { index: 1, speed: 1, endMode: 'stop' }, bossMemory: memory });
    const idle = { moveX: 0, moveY: 0, aim: 0, light: false, heavy: false, dodge: false, ranged: false, interact: false, ability: false };
    const live: number[] = [];
    while (!sim.done) {
      sim.stepLocalTick(idle);
      for (const e of sim.drainEvents()) if (e.type === 'bossRecall') live.push(e.sub);
    }
    const res = fight(level, [tapeA, sim.liveTape()], memory);
    expect(eventsOf(res.events, 'bossRecall').map((e) => e.sub)).toEqual(live);
    expect(live).toEqual([startSub]);
  });

  it('it handles one memory at a time: a second dwell overlapping the first telegraph is skipped', () => {
    const twin = { ...tapeA, index: 3 as const };
    const mem = buildBossMemory(level, [tapeA, twin]);
    const res = fight(level, [tapeA, twin], mem);
    expect(eventsOf(res.events, 'bossRecall').map((r) => r.tape)).toEqual([0]);
  });
});
