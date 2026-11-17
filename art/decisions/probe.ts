/**
 * Throwaway evidence probe for docs/DECISIONS.md. Run from prototype/:
 *   npx vite-node ../art/decisions/probe.ts
 * Reads the reference implementation only; changes nothing.
 */
import { makeLevel } from '../../prototype/tests/helpers/levels';
import { eventsOf, pathTape, resolve } from '../../prototype/tests/helpers/script';
import { baseLoadout } from '../../prototype/tests/helpers/loadout';
import { actionTiming } from '../../prototype/src/core/player';
import { swingMomentum, strikeDamage, BASE, NEUTRAL_MODS } from '../../prototype/src/core/tuning';
import { createSession } from '../../prototype/src/game/session';

const out: Record<string, unknown> = {};
const lo = baseLoadout();

// ── A/B: reverse pass — where is the body when a re-fired dodge / swing takes effect? ──
{
  const level = makeLevel({
    speeds: [1], bars: 1, horizonBars: 2, start: { x: 2.5, y: 5.5 },
    entities: [{ kind: 'enemy', id: 't1', type: 'turret', x: 9.5, y: 1.5, hp: 9, beat: { every: 1000, offset: 999 } }],
  });
  const tape = pathTape({
    index: 0, speed: 1, endMode: 'reverse', ticks: 120,
    path: [{ tick: 0, x: 2.5, y: 5.5 }, { tick: 120, x: 8.5, y: 5.5 }],
    events: [{ tick: 40, kind: 'dodge' }, { tick: 80, kind: 'heavy', dir: 0 }],
  });
  const res = resolve(level, [tape], lo);
  const ifr = res.frames.filter((f) => f.actors[0].iframes).map((f) => ({ sub: f.sub, tick: f.actors[0].phase.tick, dir: f.actors[0].phase.dir }));
  const fwd = ifr.filter((f) => f.dir === 1);
  const bwd = ifr.filter((f) => f.dir === -1);
  const td = actionTiming('dodge', lo);
  const th = actionTiming('heavy', lo);
  out.reverseDodge = {
    recordedDodgeTicks: [40, 40 + td.commit],
    iframeTicksForwardPass: fwd.length ? [fwd[0].tick, fwd[fwd.length - 1].tick] : null,
    iframeTicksBackwardPass: bwd.length ? [bwd[0].tick, bwd[bwd.length - 1].tick] : null,
  };
  const swings = eventsOf(res.events, 'swing', { tape: 0 });
  out.reverseSwing = {
    recordedEventTick: 80, windupTicks: th.activeStart,
    swings: swings.map((e) => ({ sub: e.sub, x: +e.x.toFixed(3), power: e.power, dir: e.dir })),
  };
}

// ── C: a stopped tape keeps holding a plate; D: a tape killed on pass 1 stays dead on pass 2 ──
{
  const level = makeLevel({
    speeds: [2], bars: 1, horizonBars: 2, start: { x: 2.5, y: 5.5 },
    entities: [{ kind: 'plate', id: 'p1', c: 5, r: 5 }],
    objective: { type: 'signal', text: 'hold', when: { sig: 'p1' } } as never,
  });
  const tape = pathTape({ index: 0, speed: 2, endMode: 'stop', ticks: 120, path: [{ tick: 0, x: 2.5, y: 5.5 }, { tick: 60, x: 5.5, y: 5.5 }] });
  const res = resolve(level, [tape], lo);
  const last = res.frames[res.frames.length - 1];
  out.stopHoldsPlate = { plateOnAtHorizon: last.mechs.find((m) => m.id === 'p1')?.on, tapeEnded: last.actors[0].phase.ended, survivors: res.outcome.survivors };
}
{
  const level = makeLevel({
    speeds: [2], bars: 1, horizonBars: 2, start: { x: 2.5, y: 5.5 },
    entities: [{ kind: 'enemy', id: 't1', type: 'turret', x: 8.5, y: 5.5, facing: Math.PI, beat: { every: 1, offset: 0 } }],
  });
  const tape = pathTape({ index: 0, speed: 2, endMode: 'repeat', ticks: 120, path: [{ tick: 0, x: 2.5, y: 5.5 }, { tick: 120, x: 4.5, y: 5.5 }] });
  const res = resolve(level, [tape], lo);
  const deaths = eventsOf(res.events, 'selfDeath', { tape: 0 });
  const last = res.frames[res.frames.length - 1].actors[0];
  out.repeatDeath = { deaths: deaths.length, deathSub: deaths[0]?.sub, traversalAtEnd: last.phase.traversal, lifeAtEnd: last.life, outcome: res.outcome.win };
}

// ── E: momentum table for the baseline blade (test loadout) ──
{
  const m = lo.melee;
  const run = BASE.runSpeed;
  const rows: Record<string, number> = {};
  for (const s of [0.5, 1, 2, 4]) {
    for (const [k, sw] of [['light', m.light], ['heavy', m.heavy]] as const) {
      rows[`${s}x standing ${k}`] = +swingMomentum(sw, NEUTRAL_MODS, s, 0, 0, 0).toFixed(3);
      rows[`${s}x running-in ${k}`] = +swingMomentum(sw, NEUTRAL_MODS, s, run, 0, 0).toFixed(3);
      rows[`${s}x running-away ${k}`] = +swingMomentum(sw, NEUTRAL_MODS, s, -run, 0, 0).toFixed(3);
    }
  }
  out.momentum = { lightImpact: m.light.impact, heavyImpact: m.heavy.impact, rows, dmgOf: (x: number) => strikeDamage(x, m.damageEff, 1) };
  out.timings = { light: actionTiming('light', lo), heavy: actionTiming('heavy', lo), dodge: actionTiming('dodge', lo), ranged: actionTiming('ranged', lo), interact: actionTiming('interact', lo) };
}

// ── F: session: a winning first take on a 4-cassette level ends the level with no decision ──
{
  const level = makeLevel({ speeds: [1], bars: 1, horizonBars: 1, maxTapes: 4, start: { x: 2.5, y: 5.5 }, entities: [], objective: { type: 'eliminate', text: 'nothing to kill' } });
  const s = createSession({ level, loadout: lo, skipBriefing: true });
  s.act('record');
  s.advance(10);
  const idle = { moveX: 0, moveY: 0, aim: 0, light: false, heavy: false, dodge: false, ranged: false, interact: false, ability: false } as never;
  let n = 0;
  while (s.phase === 'recording' && n++ < 5000) s.tickLocal(idle);
  out.earlyWin = { phaseAfterFirstTake: s.phase, actions: s.actions(), tapesUsed: s.tapesUsed, maxTapes: level.maxTapes };
}

console.log(JSON.stringify(out, null, 1));
