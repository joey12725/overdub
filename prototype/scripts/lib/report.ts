/**
 * Readable text for the level CLI: event logs, plan timelines, level summaries and timing tables.
 * Node-free. Every number comes from the running code (src/core/time.ts and friends).
 */
import { horizonSubs, subsPerBeat, tapeTicks, ticksPerBeat } from '../../src/core/time';
import { BEATS_PER_BAR, FRAME_SUBS, LOCAL_HZ, SUB_HZ, subsPerLocalTick, TAPE_NAMES } from '../../src/core/types';
import type { LevelDef, Outcome, Resolution, SimEvent, Tape } from '../../src/core/types';
import { dirText, exprText, fmt, pos, renderStatic } from './ascii';
import type { TakeLog } from './plan';
import { loadoutBySlot, type SolutionFile, type SolutionTake } from './solution';

function who(e: SimEvent): string {
  return e.tape !== undefined ? TAPE_NAMES[e.tape] : '?';
}

function mom(e: SimEvent): string {
  return e.power !== undefined ? `momentum ${fmt(e.power)}` : '';
}

/** One event as a sentence, or null for presentation-only noise (footsteps). */
export function describeEvent(e: SimEvent, verbose = false): string | null {
  const id = e.id ?? '?';
  // Switched as a string: the event vocabulary is still growing (traps), and an event this tool does
  // not know yet must still be printed (see the default case).
  switch (e.type as string) {
    case 'step':
      return null;
    case 'swing':
      return `${who(e)} swings ${e.detail} toward ${dirText(e.dir ?? 0)} (${mom(e)})`;
    case 'hit':
      return e.tape !== undefined ? `${who(e)}'s ${e.detail} hits ${id} (${mom(e)})` : `${e.detail} hits ${id} (${mom(e)})`;
    case 'whiff':
      return `${who(e)}'s ${e.detail} hits nothing`;
    case 'kill':
      return e.tape !== undefined ? `${who(e)} KILLS ${id} (${e.detail}, ${mom(e)})` : `${id} is KILLED (${e.detail})`;
    case 'break':
      return `${who(e)} BREAKS ${id} (${e.detail}, ${mom(e)})`;
    case 'clang':
      return `${e.tape !== undefined ? `${who(e)}'s hit` : 'a hit'} on ${id} does nothing: ${e.detail === 'momentum' ? 'too little momentum for any damage' : e.detail} (${mom(e)})`;
    case 'dodge':
      return `${who(e)} dodges toward ${dirText(e.dir ?? 0)}`;
    case 'fire':
      return `${who(e)} fires ${e.detail} toward ${dirText(e.dir ?? 0)}`;
    case 'projectileHit': {
      const what = e.detail ?? 'projectile';
      if (what.endsWith(':wall')) return verbose ? `${what.slice(0, -5)} shot hits a wall` : null;
      // A shot that lands on an enemy is followed by its own 'hit' event: say it once.
      if (e.id !== undefined) return verbose ? `${what} shot lands on ${e.id}` : null;
      if (e.tape !== undefined) return `${what} shot reaches ${who(e)}`;
      return verbose ? `${what} shot ends` : null;
    }
    case 'interact':
      return `${who(e)} flips switch ${id} ${String(e.detail).toUpperCase()}`;
    case 'interactFail':
      return `${who(e)}'s interact does nothing: ${e.detail}`;
    case 'door':
      return `door ${id} ${e.detail === 'open' ? 'OPENS' : 'CLOSES'}`;
    case 'plate':
      return `plate ${id} ${e.detail === 'on' ? 'is PRESSED' : 'is released'}`;
    case 'laser':
      return `laser ${id} turns ${String(e.detail).toUpperCase()}`;
    case 'core':
      return `${who(e)} LIGHTS core ${id} (${mom(e)})`;
    case 'selfDeath':
      return `${who(e)} DIES: ${e.detail}`;
    case 'desync':
      return `${who(e)} DESYNCS: ${e.detail}`;
    case 'resync':
      return `${who(e)} resyncs${e.detail ? ` (${e.detail})` : ''}`;
    case 'tapeWrap':
      return `${who(e)}'s tape repeats from its start (pass ${(e.power ?? 0) + 1})`;
    case 'tapeTurn':
      return `${who(e)}'s tape turns around, now running ${e.detail}`;
    case 'tapeEnd':
      return `${who(e)}'s tape ends; ${who(e)} holds its last pose`;
    case 'enemyTelegraph':
      return verbose ? `${id} winds up a ${e.detail}${e.tape !== undefined ? ` at ${who(e)}` : ''}` : null;
    case 'enemyAttack':
      return `${id} attacks (${e.detail}) toward ${dirText(e.dir ?? 0)}`;
    case 'enemyShot':
      return `${id} fires a ${e.detail}${e.tape !== undefined ? ` at ${who(e)}` : ''}`;
    case 'enemyStagger':
      return verbose ? `${id} is staggered for ${fmt(e.power ?? 0)} s` : null;
    case 'bossPhase':
      return `boss ${id} enters ${e.detail}`;
    case 'bossRecall':
      return `boss ${id} acts on its memory of ${who(e)} (${e.detail})`;
    case 'objective':
      return `OBJECTIVE COMPLETE (${e.detail})`;
    case 'trap': {
      // docs/TRAPS.md "Events": detail is '<kind>:<what>'. Hazards cycling on the beat would drown
      // the log, so only signal sources and one-off machinery are shown unless --verbose.
      const [kind, what] = String(e.detail ?? '').split(':');
      const shown = kind === 'sensor' || kind === 'relay' || kind === 'bumper' || kind === 'magnet' || kind === 'crusher';
      if (!verbose && (!shown || what === 'warn')) return null;
      return `${kind} ${id}: ${what}${e.power !== undefined && kind !== 'relay' ? ` (${fmt(e.power)})` : ''}`;
    }
    default:
      // An event type added to the kernel after this tool was written: show it raw rather than hide it.
      return `${e.type}${e.tape !== undefined ? ` ${who(e)}` : ''}${e.id !== undefined ? ` ${e.id}` : ''}${e.detail ? `: ${e.detail}` : ''}`;
  }
}

function eventKey(e: SimEvent): string {
  return `${e.sub}|${e.type}|${e.tape ?? ''}|${e.id ?? ''}|${e.detail ?? ''}`;
}

/** One line per event: master beat, what happened, where. */
export function eventLines(level: LevelDef, events: readonly SimEvent[], verbose = false, mark = ' '): string[] {
  const spb = subsPerBeat(level);
  const out: string[] = [];
  for (const e of events) {
    const text = describeEvent(e, verbose);
    if (text === null) continue;
    const where = e.type === 'objective' ? '' : `   @ ${pos(e.x, e.y)}`;
    out.push(`${mark} beat ${fmt(e.sub / spb).padStart(6)}  ${text}${where}`);
  }
  return out;
}

/**
 * What a take changed: events of the run with this take that the run before it did not have ("+"),
 * and events of the earlier run that no longer happen ("-"), in beat order.
 */
export function eventDiffLines(level: LevelDef, before: readonly SimEvent[], after: readonly SimEvent[], verbose = false): string[] {
  const count = (list: readonly SimEvent[]): Map<string, number> => {
    const m = new Map<string, number>();
    for (const e of list) m.set(eventKey(e), (m.get(eventKey(e)) ?? 0) + 1);
    return m;
  };
  const had = count(before);
  const has = count(after);
  const rows: { sub: number; order: number; line: string }[] = [];
  let order = 0;
  for (const e of after) {
    const k = eventKey(e);
    const n = had.get(k) ?? 0;
    if (n > 0) had.set(k, n - 1);
    else for (const line of eventLines(level, [e], verbose, '+')) rows.push({ sub: e.sub, order: order++, line });
  }
  for (const e of before) {
    const k = eventKey(e);
    const n = has.get(k) ?? 0;
    if (n > 0) has.set(k, n - 1);
    else for (const line of eventLines(level, [e], verbose, '-')) rows.push({ sub: e.sub, order: order++, line });
  }
  rows.sort((a, b) => a.sub - b.sub || a.order - b.order);
  return rows.map((r) => r.line);
}

export function outcomeLines(o: Outcome): string[] {
  const head = o.win ? 'WIN' : `FAIL (${o.reason === 'noSurvivor' ? 'nobody survived' : 'objective not complete'})`;
  return [`Outcome: ${head}`, ...o.notes.map((n) => `  - ${n}`)];
}

export function takeTitle(n: number, take: Pick<SolutionTake, 'speed' | 'endMode' | 'note'>): string {
  return `Take ${n} = tape ${TAPE_NAMES[n - 1]}, ${take.speed}x, ${take.endMode}: ${take.note}`;
}

/** The plan as it actually played out: when each step began and finished, and where. */
export function stepLines(level: LevelDef, take: SolutionTake, log: TakeLog): string[] {
  const perBeat = ticksPerBeat(level) * take.speed;
  const beat = (t: number): string => fmt(t / perBeat);
  const out: string[] = [];
  const width = Math.min(46, Math.max(...log.steps.map((s) => s.text.length), 4));
  for (const s of log.steps) {
    const text = s.text.length > width ? s.text : s.text.padEnd(width);
    if (s.startTick === null) {
      out.push(`  ${String(s.n).padStart(2)}. ${text}  NEVER REACHED`);
      continue;
    }
    const open = s.restful && s.n === log.steps.length ? 'to the end of the take' : 'NOT FINISHED';
    const span = s.endTick === null ? `tick ${String(s.startTick).padStart(4)} ->  ...   beat ${beat(s.startTick).padStart(6)} ->    ...  ${open}` : `tick ${String(s.startTick).padStart(4)} -> ${String(s.endTick).padStart(4)}   beat ${beat(s.startTick).padStart(6)} -> ${beat(s.endTick).padStart(6)}  at ${pos(s.x, s.y)}`;
    const flags = s.flags.filter((f) => !f.startsWith('pressed'));
    out.push(`  ${String(s.n).padStart(2)}. ${text}  ${span}${flags.length ? `  [${flags.join('; ')}]` : ''}`);
  }
  out.push(`      (${log.inputs.length} local ticks recorded = master beats 0 to ${beat(log.inputs.length)})`);
  return out;
}

/** A self's position at every `every` master beats of a resolved run. */
export function traceLines(level: LevelDef, res: Resolution, tape: number, every = 1): string[] {
  const spb = subsPerBeat(level);
  const out: string[] = [];
  const beats = res.horizonSubs / spb;
  let lastRow = '';
  let held = 0;
  for (let b = 0; b <= beats + 1e-9; b += every) {
    const i = Math.min(res.frames.length - 1, Math.round((b * spb) / FRAME_SUBS));
    const a = res.frames[i].actors.find((x) => x.tape === tape);
    if (!a) continue;
    const state = a.life !== 'alive' ? 'dead' : a.synced ? 'alive' : 'DESYNCED';
    const where = a.phase.ended ? 'tape ended' : `local tick ${fmt(a.phase.tick, 1)}${a.phase.dir === -1 ? ' <-' : ''}`;
    const row = `${TAPE_NAMES[tape]} at ${pos(a.x, a.y).padEnd(14)}  tile ${`(${Math.floor(a.x)},${Math.floor(a.y)})`.padEnd(7)}  ${state.padEnd(8)} ${a.anim.padEnd(12)} ${where}`;
    // Once a self has stopped changing (tape ended, holding its pose), say so once instead of repeating it.
    if (a.phase.ended && row === lastRow) {
      held++;
      continue;
    }
    if (held > 0) out.push(`               ... unchanged for ${held} more row(s)`);
    held = 0;
    lastRow = row;
    out.push(`  beat ${fmt(b).padStart(6)}  ${row}`);
  }
  if (held > 0) out.push(`               ... unchanged to the horizon (beat ${fmt(beats)})`);
  return out;
}

/** Tempo, tape length and horizon of a level, with one row per offered speed. */
export function timingLines(level: LevelDef): string[] {
  const tpb = ticksPerBeat(level);
  const ticks = tapeTicks(level);
  const secPerBeat = 60 / level.bpm;
  const localBeats = level.bars * BEATS_PER_BAR;
  const hSubs = horizonSubs(level);
  const hBeats = level.horizonBars * BEATS_PER_BAR;
  const out: string[] = [];
  out.push(`Tempo ${level.bpm} bpm: one beat = ${fmt(secPerBeat, 3)} s = ${tpb} local ticks (${LOCAL_HZ} ticks per recorded second).`);
  out.push(`A take records ${level.bars} bars = ${localBeats} local beats = ${ticks} local ticks = ${fmt(ticks / LOCAL_HZ, 1)} s of real time, whatever its speed.`);
  out.push(`Master horizon: ${level.horizonBars} bars = ${hBeats} master beats = ${fmt(hSubs / SUB_HZ, 1)} s (${hSubs} substeps). The run is judged at beat ${hBeats}.`);
  out.push('');
  out.push('  speed   one pass covers (master time)           local ticks per master beat   passes inside the horizon');
  for (const s of [...level.speeds].sort((a, b) => a - b)) {
    const bars = level.bars / s;
    const beats = bars * BEATS_PER_BAR;
    const secs = (ticks * subsPerLocalTick(s)) / SUB_HZ;
    const passes = level.horizonBars / bars;
    const cut = passes < 1 ? `  <- cut off at beat ${hBeats}: only local ticks 0..${Math.floor(hBeats * tpb * s)} get recorded` : '';
    out.push(`  ${`${s}x`.padEnd(6)}  ${`${fmt(bars, bars % 1 ? 2 : 0)} bars = ${fmt(beats, beats % 1 ? 2 : 0)} beats = ${fmt(secs, 1)} s`.padEnd(40)}  ${String(tpb * s).padEnd(28)}  ${fmt(passes, 2)}${cut}`);
  }
  return out;
}

/** Everything `show` prints about a level. */
export function showLines(level: LevelDef, sol: SolutionFile | null): string[] {
  const out: string[] = [];
  out.push(`${level.id}  "${level.name}"  (campaign index ${level.index}, theme ${level.theme})`);
  out.push(level.tagline);
  out.push('');
  out.push(...renderStatic(level));
  out.push('');
  const o = level.objective;
  const targets = o.targets?.length ? ` targets: ${o.targets.join(', ')}` : '';
  const when = o.when ? ` when: ${exprText(o.when)}` : '';
  out.push(`Objective (${o.type}${targets}${when}): ${o.text}`);
  out.push('  A run wins when the objective is complete AND at least one self is alive at the horizon.');
  out.push(`Cassettes: ${level.maxTapes}   speeds: ${level.speeds.map((s) => `${s}x`).join(', ')}   end modes: ${level.endModes.join(', ')}`);
  out.push(`Loot: ${level.loot.length ? level.loot.join(', ') : 'none'}`);
  out.push('');
  out.push(...timingLines(level));
  out.push('');
  out.push('Briefing:');
  for (const b of level.briefing) out.push(`  - ${b}`);
  for (const [k, v] of Object.entries(level.hints ?? {})) out.push(`  hint, tape ${k}: ${v}`);
  if (sol) {
    let worn: ReturnType<typeof loadoutBySlot>;
    try {
      worn = loadoutBySlot(sol);
    } catch {
      worn = undefined;
    }
    out.push('');
    out.push(`Solution: ${sol.takes.length} take(s)${worn ? `, wearing ${Object.values(worn).join(', ')}` : ', baseline loadout'}${sol.generated ? `; compiled, expects ${sol.generated.outcome.win ? 'a WIN' : 'a FAIL'}` : '; not compiled yet (run --write)'}`);
    sol.takes.forEach((t, i) => out.push(`  ${takeTitle(i + 1, t)}`));
  }
  return out;
}

/** Tapes in a run, one line each. */
export function tapeLines(level: LevelDef, tapes: readonly Tape[]): string[] {
  const tpb = ticksPerBeat(level);
  return tapes.map((t) => `  tape ${TAPE_NAMES[t.index]}: ${t.speed}x ${t.endMode}, ${t.ticks} local ticks = master beats 0 to ${fmt(t.ticks / (tpb * t.speed))}, ${t.events.length} recorded action(s)`);
}
