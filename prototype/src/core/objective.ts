/**
 * Objectives, the run log and the Outcome (REC-06, REC-07, HEALTH-04, TEST-23/24).
 *
 * The objective latches the first substep it is satisfied ('reach' is judged at the horizon). The
 * Outcome is: win = objective latched AND at least one self 'alive' (a desynced-but-alive self
 * counts as a survivor; it cannot hold an exit).
 *
 * Notes explain the run in the game's own terms (TEST chapter: "failures can be explained"): who
 * died at which beat and to what, which self desynced, where, and whether its spark caught up,
 * which swing lacked the momentum for what, and what part of the objective is missing.
 */
import { evalSignal } from './signals';
import type { EnemyState } from './enemies/types';
import { TAPE_NAMES, type LevelDef, type ObjectiveSnap, type Outcome, type TapeIndex } from './types';
import type { World } from './sim';

export interface DeathRecord {
  tape: TapeIndex;
  sub: number;
  cause: string;
}
export interface DesyncRecord {
  tape: TapeIndex;
  sub: number;
  cause: string;
}
export interface ResyncRecord {
  tape: TapeIndex;
  sub: number;
}
export interface WeakHitRecord {
  tape: TapeIndex;
  sub: number;
  kind: string;
  target: string;
  momentum: number;
  /** Threshold that was needed, when there is one. */
  need: number | null;
  reason: string;
}
export interface KillRecord {
  id: string;
  sub: number;
  by: string;
}

/** Everything noteworthy that happened in a run, in order. Plain data. */
export class RunLog {
  readonly deaths: DeathRecord[] = [];
  readonly desyncs: DesyncRecord[] = [];
  readonly resyncs: ResyncRecord[] = [];
  readonly weakHits: WeakHitRecord[] = [];
  readonly kills: KillRecord[] = [];

  death(tape: TapeIndex, sub: number, cause: string): void {
    this.deaths.push({ tape, sub, cause });
  }
  desync(tape: TapeIndex, sub: number, cause: string): void {
    this.desyncs.push({ tape, sub, cause });
  }
  resync(tape: TapeIndex, sub: number): void {
    this.resyncs.push({ tape, sub });
  }
  weak(tape: TapeIndex, sub: number, kind: string, target: string, momentum: number, need: number | null, reason: string): void {
    this.weakHits.push({ tape, sub, kind, target, momentum, need, reason });
  }
  kill(id: string, sub: number, by: string): void {
    this.kills.push({ id, sub, by });
  }
}

export class ObjectiveTracker {
  complete = false;
  completeSub = -1;

  constructor(private readonly level: LevelDef) {}

  /** Objective-latch phase of a substep. */
  update(w: World): void {
    if (this.complete) return;
    if (this.satisfiedNow(w)) {
      this.complete = true;
      this.completeSub = w.s;
      w.emit({ type: 'objective', x: 0, y: 0, detail: this.level.objective.type });
    }
  }

  private satisfiedNow(w: World): boolean {
    const obj = this.level.objective;
    switch (obj.type) {
      case 'eliminate': {
        const list = targetEnemies(w, obj.targets);
        return list.every((e) => !e.alive);
      }
      case 'activate': {
        const cores = targetCores(w, obj.targets);
        return cores.every((c) => c.on);
      }
      case 'boss': {
        const bosses = bossEnemies(w, obj.targets);
        return bosses.length > 0 && bosses.every((e) => !e.alive);
      }
      case 'reach':
        return w.now >= w.horizonSubs && exitHeld(w, obj.targets);
      case 'signal':
        return obj.when ? evalSignal(obj.when, w.signals, w.beat) : false;
    }
  }

  progress(w: World): number {
    const obj = this.level.objective;
    if (this.complete) return 1;
    switch (obj.type) {
      case 'eliminate': {
        const list = targetEnemies(w, obj.targets);
        return list.length === 0 ? 1 : list.filter((e) => !e.alive).length / list.length;
      }
      case 'activate': {
        const cores = targetCores(w, obj.targets);
        return cores.length === 0 ? 1 : cores.filter((c) => c.on).length / cores.length;
      }
      case 'boss': {
        const bosses = bossEnemies(w, obj.targets);
        let hp = 0;
        let max = 0;
        for (const b of bosses) {
          hp += b.hp;
          max += b.maxHp;
        }
        return max > 0 ? 1 - hp / max : 0;
      }
      case 'reach':
        return exitHeld(w, obj.targets) ? 1 : 0;
      case 'signal':
        return 0;
    }
  }

  snapshot(w: World): ObjectiveSnap {
    let survivors = 0;
    for (const s of w.selves) if (s.life === 'alive') survivors++;
    return { complete: this.complete, progress: this.progress(w), survivors };
  }
}

function targetEnemies(w: World, targets: string[] | undefined): readonly EnemyState[] {
  if (!targets || targets.length === 0) return w.enemies;
  return w.enemies.filter((e) => targets.includes(e.id));
}

function bossEnemies(w: World, targets: string[] | undefined): readonly EnemyState[] {
  if (targets && targets.length > 0) return w.enemies.filter((e) => targets.includes(e.id));
  return w.enemies.filter((e) => e.type === 'boss');
}

function targetCores(w: World, targets: string[] | undefined) {
  const cores = w.mechs.cores;
  if (!targets || targets.length === 0) return cores.map((c) => c);
  return cores.filter((c) => targets.includes(c.def.id));
}

/** Any listed exit (all exits when none are listed) currently held by an alive, synced self. */
function exitHeld(w: World, targets: string[] | undefined): boolean {
  for (const x of w.mechs.exits) {
    if (targets && targets.length > 0 && !targets.includes(x.def.id)) continue;
    if (x.on) return true;
  }
  return false;
}

// ───────────────────────────── outcome ─────────────────────────────

export function tapeName(t: TapeIndex): string {
  return `Tape ${TAPE_NAMES[t]}`;
}

/** Master beat of a substep event, formatted for notes (beats count from 0 like the ruler). */
export function formatBeat(w: World, sub: number): string {
  const b = Math.round((sub / w.spb) * 100) / 100;
  return `beat ${b}`;
}

function fmtNum(n: number): string {
  return String(Math.round(n * 100) / 100);
}

/** The outcome as of now (authoritative for playback at the horizon). */
export function buildOutcome(w: World, tracker: ObjectiveTracker, level: LevelDef): Outcome {
  const survivors: TapeIndex[] = [];
  for (const s of w.selves) if (s.life === 'alive') survivors.push(s.index);
  const objectiveComplete = tracker.complete;
  const win = objectiveComplete && survivors.length > 0;
  const notes: string[] = [];
  const log = w.log;

  if (objectiveComplete) notes.push(`Objective complete at ${formatBeat(w, tracker.completeSub)}: ${level.objective.text}.`);
  else notes.push(`Objective not complete: ${level.objective.text}. ${missingObjective(w, level)}`);

  for (const d of log.deaths) notes.push(`${tapeName(d.tape)} died at ${formatBeat(w, d.sub)}: ${d.cause}.`);

  for (const s of w.selves) {
    const ds = log.desyncs.filter((d) => d.tape === s.index);
    const rs = log.resyncs.filter((r) => r.tape === s.index);
    for (let i = 0; i < ds.length; i++) {
      const d = ds[i];
      const r = rs[i];
      const head = `${tapeName(d.tape)} desynced at ${formatBeat(w, d.sub)} (${d.cause})`;
      if (r) notes.push(`${head}; its spark caught up at ${formatBeat(w, r.sub)}.`);
      else notes.push(`${head}; its spark never caught up.`);
    }
    if (!s.synced && s.life === 'alive') {
      notes.push(`${tapeName(s.index)} ended the run desynced: it survives, but it could not act or hold an exit.`);
    }
  }

  const seen = new Set<string>();
  for (const h of log.weakHits) {
    const key = `${h.tape}|${h.kind}|${h.target}`;
    if (seen.has(key)) continue;
    seen.add(key);
    if (h.need !== null) {
      notes.push(
        `${tapeName(h.tape)}'s ${h.kind} at ${formatBeat(w, h.sub)} hit ${h.target} with momentum ${fmtNum(h.momentum)}; it needs ${fmtNum(h.need)}.`,
      );
    } else {
      notes.push(`${tapeName(h.tape)}'s ${h.kind} at ${formatBeat(w, h.sub)} hit ${h.target} but did no damage (${h.reason}, momentum ${fmtNum(h.momentum)}).`);
    }
  }

  let reason: Outcome['reason'];
  if (!objectiveComplete) reason = 'objective';
  else if (survivors.length === 0) {
    reason = 'noSurvivor';
    notes.push('No self survived to the end: the objective needs at least one survivor.');
  }
  if (survivors.length > 0) notes.push(`Survivors: ${survivors.map(tapeName).join(', ')}.`);

  const out: Outcome = { win, objectiveComplete, survivors, notes };
  if (reason) out.reason = reason;
  return out;
}

function missingObjective(w: World, level: LevelDef): string {
  const obj = level.objective;
  switch (obj.type) {
    case 'eliminate': {
      const left = targetEnemies(w, obj.targets).filter((e) => e.alive);
      return left.length ? `Still standing: ${left.map((e) => `${e.type} ${e.id}`).join(', ')}.` : '';
    }
    case 'activate': {
      const left = targetCores(w, obj.targets).filter((c) => !c.on);
      return left.length ? `Not activated: ${left.map((c) => `core ${c.def.id}`).join(', ')}.` : '';
    }
    case 'boss': {
      const bosses = bossEnemies(w, obj.targets);
      if (bosses.length === 0) return 'There is no boss in this level.';
      const alive = bosses.filter((b) => b.alive);
      return alive.map((b) => `${b.id} survived with ${b.hp} of ${b.maxHp} hp.`).join(' ');
    }
    case 'reach':
      return w.now >= w.horizonSubs ? 'No alive, synced self was in the exit when the encounter ended.' : 'The encounter has not ended yet.';
    case 'signal':
      return 'The required condition never happened.';
  }
}
