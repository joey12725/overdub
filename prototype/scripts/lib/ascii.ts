/**
 * ASCII views of a room: the static level (`show`) and one instant of a run (`ascii-at`).
 * Designers cannot see the game while they work; this is their eyes. Node-free.
 *
 * Symbols (one character per tile; the tables under the map give exact positions and states):
 *   #  wall        .  floor        (space) void        =  low barrier
 *   @  start (static view only)
 *   A B C D  a living, synced self      a b c d  that self dead (a ghost)
 *   ?  a desynced self's projection     !  its recovery spark     2 3 4  several selves on one tile
 *   G grunt   K stalker   T turret   H shielder   R brute   N drone   X boss      x  a dead enemy
 *   +  door closed     :  door open          s / S  switch off / on     p / P  plate up / pressed
 *   %  breakable       ,  broken (rubble)    o / O  core idle / lit     e / E  exit / exit held
 *   ~  laser beam firing (not drawn while off)                          *  a projectile in flight
 *   traps (docs/TRAPS.md):
 *   w / W  spikes down / raised         m / M  crusher retracted / extended (solid)
 *   > < v ^  conveyor running that way  - |  conveyor stopped
 *   f / F  flame nozzle off / burning   &  the flame jet        j / J  dart launcher off / enabled
 *   u / U  bumper idle / just fired     ;  sensor beam          q / Q  magnet off / pulling
 *   (a relay has no body: it is listed in the table only)
 */
import { subsPerBeat } from '../../src/core/time';
import { FRAME_SUBS, TAPE_NAMES } from '../../src/core/types';
import type { Dir4, EnemyType, EntityDef, FrameSnapshot, LevelDef, MechSnap, Resolution, SignalExpr, Tape, TrapDef } from '../../src/core/types';

export const ENEMY_LETTER: Readonly<Record<EnemyType, string>> = { grunt: 'G', stalker: 'K', turret: 'T', shielder: 'H', brute: 'R', drone: 'N', boss: 'X' };

export const LEGEND: readonly string[] = [
  '#  wall      .  floor     (space) void    =  low barrier (blocks walking, not shots)',
  'A-D self     a-d dead self (ghost)        ?  desynced self    !  its spark    2-4 selves sharing a tile',
  'G grunt  K stalker  T turret  H shielder  R brute  N drone  X boss  x dead enemy   * projectile',
  '+ door closed  : door open   s/S switch off/on   p/P plate up/pressed   % breakable  , broken',
  'o/O core idle/lit   e/E exit / exit held   ~ laser firing (not drawn while off)',
  'traps: w/W spikes down/raised   m/M crusher retracted/extended   > < v ^ conveyor running   - | conveyor stopped',
  '       f/F flame nozzle off/burning   & flame jet   j/J dart launcher off/on   u/U bumper   ; sensor beam   q/Q magnet',
];

const FLOOR_CHARS: ReadonlySet<string> = new Set(['.', ':', ',', '~']);

export function fmt(n: number, digits = 2): string {
  return (Math.round(n * 10 ** digits) / 10 ** digits).toFixed(digits);
}

export function pos(x: number, y: number): string {
  return `(${fmt(x)}, ${fmt(y)})`;
}

const COMPASS_NAMES = ['E', 'SE', 'S', 'SW', 'W', 'NW', 'N', 'NE'];

/** A direction in radians as degrees plus the nearest compass name, e.g. "90° S". */
export function dirText(rad: number): string {
  let deg = Math.round((rad * 180) / Math.PI);
  deg = ((deg % 360) + 360) % 360;
  return `${deg}° ${COMPASS_NAMES[Math.round(deg / 45) % 8]}`;
}

export function exprText(e: SignalExpr): string {
  if ('sig' in e) return e.sig;
  if ('not' in e) return `not ${exprText(e.not)}`;
  if ('and' in e) return `(${e.and.map(exprText).join(' and ')})`;
  if ('or' in e) return `(${e.or.map(exprText).join(' or ')})`;
  if ('xor' in e) return `(${exprText(e.xor[0])} xor ${exprText(e.xor[1])})`;
  if ('const' in e) return e.const ? 'always' : 'never';
  return `beats [${e.beat.from}, ${e.beat.to}) of every ${e.beat.every}`;
}

/** A character grid with priorities, so a self is never hidden by the plate it stands on. */
class Canvas {
  readonly rows: number;
  readonly cols: number;
  private readonly chars: string[][];
  private readonly rank: number[][];

  constructor(level: LevelDef) {
    this.rows = level.map.length;
    this.cols = level.map[0]?.length ?? 0;
    this.chars = level.map.map((row) => [...row].map((ch) => (FLOOR_CHARS.has(ch) ? '.' : ch)));
    this.rank = level.map.map((row) => [...row].map(() => 0));
  }

  put(c: number, r: number, ch: string, rank: number): void {
    if (r < 0 || c < 0 || r >= this.rows || c >= this.cols) return;
    if (rank < this.rank[r][c]) return;
    this.chars[r][c] = ch;
    this.rank[r][c] = rank;
  }

  at(c: number, r: number): string {
    return this.chars[r]?.[c] ?? ' ';
  }

  /** The grid with a column ruler on top and row numbers on both sides. */
  lines(): string[] {
    const out: string[] = [];
    const pad = String(this.rows - 1).length;
    const gutter = ' '.repeat(pad + 2);
    if (this.cols > 10) out.push(gutter + Array.from({ length: this.cols }, (_, c) => (c >= 10 && c % 10 === 0 ? String(Math.floor(c / 10) % 10) : ' ')).join(''));
    out.push(gutter + Array.from({ length: this.cols }, (_, c) => String(c % 10)).join(''));
    for (let r = 0; r < this.rows; r++) out.push(`${String(r).padStart(pad)}  ${this.chars[r].join('')}  ${r}`);
    return out;
  }
}

function tile(v: number): number {
  return Math.floor(v);
}

function drawBeam(cv: Canvas, from: { x: number; y: number }, to: { x: number; y: number }, ch: string, rank: number): void {
  const n = Math.max(1, Math.ceil(Math.hypot(to.x - from.x, to.y - from.y) * 4));
  for (let k = 0; k <= n; k++) cv.put(tile(from.x + ((to.x - from.x) * k) / n), tile(from.y + ((to.y - from.y) * k) / n), ch, rank);
}

function drawLaser(cv: Canvas, from: { x: number; y: number }, to: { x: number; y: number }): void {
  drawBeam(cv, from, to, '~', 3);
}

// ───────────────────────────── traps (docs/TRAPS.md) ─────────────────────────────

const TRAP_KINDS: ReadonlySet<string> = new Set(['spikes', 'crusher', 'conveyor', 'flame', 'dart', 'bumper', 'sensor', 'relay', 'magnet']);
const DIR_VEC: Readonly<Record<Dir4, { x: number; y: number }>> = { n: { x: 0, y: -1 }, e: { x: 1, y: 0 }, s: { x: 0, y: 1 }, w: { x: -1, y: 0 } };
const DIR_NAME: Readonly<Record<Dir4, string>> = { n: 'north', e: 'east', s: 'south', w: 'west' };

export function isTrap(e: EntityDef): e is TrapDef {
  return TRAP_KINDS.has(e.kind);
}

function arrowOf(x: number, y: number): string {
  return Math.abs(x) >= Math.abs(y) ? (x >= 0 ? '>' : '<') : y >= 0 ? 'v' : '^';
}

function cellList(cells: readonly { c: number; r: number }[]): string {
  return `tile${cells.length > 1 ? 's' : ''} ${cells.map((c) => `(${c.c},${c.r})`).join(' ')}`;
}

/**
 * Draw one trap and return its table row. `m` is its live state; null draws the level as authored
 * (everything idle) and the row then says what drives it.
 */
function drawTrap(cv: Canvas, e: TrapDef, m: MechSnap | null, atBeatZero = false): string {
  const on = m?.on ?? atBeatZero;
  const live = m !== null;
  switch (e.kind) {
    case 'spikes': {
      for (const c of e.cells) cv.put(c.c, c.r, on ? 'W' : 'w', 2);
      return `${on ? 'W' : 'w'}  spikes "${e.id}" ${live ? (on ? 'RAISED (lethal)' : 'down') : `on ${cellList(e.cells)}: raised while ${exprText(e.upWhen)}`}`;
    }
    case 'crusher': {
      for (const c of e.cells) cv.put(c.c, c.r, on ? 'M' : 'm', on ? 4 : 2);
      return `${on ? 'M' : 'm'}  crusher "${e.id}" ${live ? (on ? 'EXTENDED (solid)' : 'retracted') : `over ${cellList(e.cells)}: extends while ${exprText(e.extendWhen)}`}`;
    }
    case 'conveyor': {
      const v = DIR_VEC[e.dir];
      const running = live ? on : atBeatZero;
      const ch = running ? (m?.dir !== undefined ? arrowOf(Math.cos(m.dir), Math.sin(m.dir)) : arrowOf(v.x, v.y)) : v.x !== 0 ? '-' : '|';
      for (const c of e.cells) cv.put(c.c, c.r, ch, 2);
      const drive = `${e.runWhen ? `runs while ${exprText(e.runWhen)}` : 'always running'}${e.reverseWhen ? `, reversed while ${exprText(e.reverseWhen)}` : ''}`;
      return `${ch}  conveyor "${e.id}" ${live ? (on ? `RUNNING ${m?.dir !== undefined ? dirText(m.dir) : DIR_NAME[e.dir]}` : 'stopped') : `on ${cellList(e.cells)} toward ${DIR_NAME[e.dir]}, ${e.speed ?? 2} tiles per master second: ${drive}`}`;
    }
    case 'flame': {
      cv.put(e.c, e.r, on ? 'F' : 'f', 4);
      const v = DIR_VEC[e.dir];
      const reach = live && on ? Math.ceil(m?.reach ?? e.range) : 0;
      for (let k = 1; k <= reach; k++) cv.put(e.c + v.x * k, e.r + v.y * k, '&', 3);
      return `${on ? 'F' : 'f'}  flame "${e.id}" ${live ? (on ? `BURNING ${fmt(m?.reach ?? e.range, 1)} tiles ${DIR_NAME[e.dir]}` : 'off') : `nozzle on tile (${e.c},${e.r}) firing ${DIR_NAME[e.dir]} up to ${e.range} tiles: burning while ${exprText(e.onWhen)}`}`;
    }
    case 'dart': {
      const enabled = live ? on : atBeatZero;
      cv.put(e.c, e.r, enabled ? 'J' : 'j', 4);
      return `${enabled ? 'J' : 'j'}  dart launcher "${e.id}" ${live ? (on ? 'enabled' : 'DISABLED') : `on tile (${e.c},${e.r}) firing ${DIR_NAME[e.dir]} on beats ${e.offset ?? 0} + k x ${e.every ?? 2}${e.enabledWhen ? `, only while ${exprText(e.enabledWhen)}` : ''}`}`;
    }
    case 'bumper': {
      cv.put(e.c, e.r, on ? 'U' : 'u', 2);
      return `${on ? 'U' : 'u'}  bumper "${e.id}" ${live ? (on ? 'JUST FIRED' : 'idle') : `on tile (${e.c},${e.r}) launching ${DIR_NAME[e.dir]} ${e.power ?? 3} tiles: fires when ${exprText(e.fireWhen)} becomes true`}`;
    }
    case 'sensor': {
      drawBeam(cv, e.from, e.to, ';', 1);
      return `;  sensor "${e.id}" ${live ? (on ? 'TRIPPED' : 'clear') : `beam from ${pos(e.from.x, e.from.y)} to ${pos(e.to.x, e.to.y)}, detects ${e.detects ?? 'any'}${e.latch ? ', latches' : ''}`}`;
    }
    case 'relay':
      return `   relay "${e.id}" ${live ? (on ? 'ON' : 'off') : `(${e.mode ?? 'pulse'}): triggered when ${exprText(e.trigger)} becomes true`}`;
    case 'magnet': {
      cv.put(tile(e.x), tile(e.y), on ? 'Q' : 'q', 4);
      return `${on ? 'Q' : 'q'}  magnet "${e.id}" ${live ? (on ? 'PULLING' : 'off') : `at ${pos(e.x, e.y)}, radius ${e.radius}: pulling while ${exprText(e.onWhen)}`}`;
    }
  }
}

/** Truth of a signal expression at beat zero with nothing pressed (static view: which doors start open). */
function initialTruth(level: LevelDef, e: SignalExpr): boolean {
  if ('sig' in e) {
    const sw = level.entities.find((x) => x.kind === 'switch' && x.id === e.sig);
    return sw !== undefined && sw.kind === 'switch' && sw.initial === true;
  }
  if ('not' in e) return !initialTruth(level, e.not);
  if ('and' in e) return e.and.every((x) => initialTruth(level, x));
  if ('or' in e) return e.or.some((x) => initialTruth(level, x));
  if ('xor' in e) return initialTruth(level, e.xor[0]) !== initialTruth(level, e.xor[1]);
  if ('const' in e) return e.const;
  return e.beat.from <= 0 && e.beat.to > 0;
}

/** Whether a trap is active at beat zero with nothing pressed, tripped or broken (static view). */
function trapOnAtBeatZero(level: LevelDef, e: TrapDef): boolean {
  switch (e.kind) {
    case 'spikes':
      return initialTruth(level, e.upWhen);
    case 'crusher':
      return initialTruth(level, e.extendWhen);
    case 'conveyor':
      return e.runWhen ? initialTruth(level, e.runWhen) : true;
    case 'flame':
    case 'magnet':
      return initialTruth(level, e.onWhen);
    case 'dart':
      return e.enabledWhen ? initialTruth(level, e.enabledWhen) : true;
    default:
      return false;
  }
}

/** The level as authored: map, entities at beat zero, and a table of every entity. */
export function renderStatic(level: LevelDef): string[] {
  const cv = new Canvas(level);
  const table: string[] = [];
  for (const e of level.entities) {
    if (isTrap(e)) {
      table.push(drawTrap(cv, e, null, trapOnAtBeatZero(level, e)));
      continue;
    }
    switch (e.kind) {
      case 'enemy': {
        cv.put(tile(e.x), tile(e.y), ENEMY_LETTER[e.type] ?? 'M', 6);
        const extra = [e.hp !== undefined ? `hp ${e.hp}` : '', e.beat ? `attacks every ${e.beat.every} beats, offset ${e.beat.offset}` : '', e.wakeWhen ? `asleep until ${exprText(e.wakeWhen)}` : '']
          .filter(Boolean)
          .join('; ');
        table.push(`${ENEMY_LETTER[e.type] ?? 'M'}  ${e.type} "${e.id}" at ${pos(e.x, e.y)}${extra ? `: ${extra}` : ''}`);
        break;
      }
      case 'door': {
        const open = initialTruth(level, e.openWhen);
        for (const c of e.cells) cv.put(c.c, c.r, open ? ':' : '+', 4);
        table.push(`${open ? ':' : '+'}  door "${e.id}" on tile${e.cells.length > 1 ? 's' : ''} ${e.cells.map((c) => `(${c.c},${c.r})`).join(' ')}: open while ${exprText(e.openWhen)}`);
        break;
      }
      case 'switch':
        cv.put(tile(e.x), tile(e.y), e.initial ? 'S' : 's', 4);
        table.push(`${e.initial ? 'S' : 's'}  switch "${e.id}" at ${pos(e.x, e.y)}, starts ${e.initial ? 'on' : 'off'}`);
        break;
      case 'plate':
        cv.put(e.c, e.r, 'p', 2);
        table.push(`p  plate "${e.id}" on tile (${e.c},${e.r})${e.heavy ? ', heavy (needs a brute / boss body or heavyStep gear)' : ''}`);
        break;
      case 'breakable':
        cv.put(e.c, e.r, '%', 4);
        table.push(`%  breakable "${e.id}" on tile (${e.c},${e.r}): one hit of momentum ${e.threshold} or more`);
        break;
      case 'laser': {
        const on = initialTruth(level, e.onWhen);
        if (on) drawLaser(cv, e.from, e.to);
        table.push(`~  laser "${e.id}" from ${pos(e.from.x, e.from.y)} to ${pos(e.to.x, e.to.y)}: firing while ${exprText(e.onWhen)}${on ? '' : ' (off at beat 0, not drawn)'}`);
        break;
      }
      case 'core':
        cv.put(tile(e.x), tile(e.y), 'o', 4);
        table.push(`o  core "${e.id}" at ${pos(e.x, e.y)}${e.threshold !== undefined ? `: needs momentum ${e.threshold}` : ''}`);
        break;
      case 'exit':
        for (let dr = 0; dr < e.h; dr++) for (let dc = 0; dc < e.w; dc++) cv.put(e.c + dc, e.r + dr, 'e', 2);
        table.push(`e  exit "${e.id}" tiles (${e.c},${e.r}) to (${e.c + e.w - 1},${e.r + e.h - 1})`);
        break;
      case 'decor':
        break;
    }
  }
  cv.put(tile(level.start.x), tile(level.start.y), '@', 9);
  table.unshift(`@  start at ${pos(level.start.x, level.start.y)}, facing ${dirText(level.startFacing ?? 0)} (every tape starts here at beat 0)`);
  return [...cv.lines(), '', ...table];
}

/** The frame of a resolution nearest a master beat. */
export function frameAtBeat(level: LevelDef, res: Resolution, beat: number): FrameSnapshot {
  const sub = Math.max(0, Math.min(res.horizonSubs, Math.round(beat * subsPerBeat(level))));
  const i = Math.min(res.frames.length - 1, Math.round(sub / FRAME_SUBS));
  return res.frames[i];
}

function selfChar(a: FrameSnapshot['actors'][number]): string {
  if (a.life !== 'alive') return TAPE_NAMES[a.tape].toLowerCase();
  return a.synced ? TAPE_NAMES[a.tape] : '?';
}

/** One instant of a run: the room with everything where it is, plus tables of exact states. */
export function renderFrame(level: LevelDef, snap: FrameSnapshot, tapes: readonly Tape[] = []): string[] {
  const cv = new Canvas(level);
  const mech = new Map(snap.mechs.map((m) => [m.id, m]));
  const mechRows: string[] = [];
  for (const e of level.entities) {
    if (e.kind === 'decor' || e.kind === 'enemy') continue;
    if (isTrap(e)) {
      mechRows.push(drawTrap(cv, e, mech.get(e.id) ?? { id: e.id, kind: e.kind, on: false }));
      continue;
    }
    const on = mech.get(e.id)?.on ?? false;
    switch (e.kind) {
      case 'door':
        for (const c of e.cells) cv.put(c.c, c.r, on ? ':' : '+', 4);
        mechRows.push(`${on ? ':' : '+'}  door "${e.id}" ${on ? 'OPEN' : 'closed'}`);
        break;
      case 'switch':
        cv.put(tile(e.x), tile(e.y), on ? 'S' : 's', 4);
        mechRows.push(`${on ? 'S' : 's'}  switch "${e.id}" ${on ? 'ON' : 'off'}`);
        break;
      case 'plate':
        cv.put(e.c, e.r, on ? 'P' : 'p', 2);
        mechRows.push(`${on ? 'P' : 'p'}  plate "${e.id}" ${on ? 'PRESSED' : 'up'}`);
        break;
      case 'breakable':
        cv.put(e.c, e.r, on ? ',' : '%', on ? 1 : 4);
        mechRows.push(`${on ? ',' : '%'}  breakable "${e.id}" ${on ? 'BROKEN' : 'intact'}`);
        break;
      case 'laser':
        if (on) drawLaser(cv, e.from, e.to);
        mechRows.push(`${on ? '~' : ' '}  laser "${e.id}" ${on ? 'FIRING' : 'off'}`);
        break;
      case 'core':
        cv.put(tile(e.x), tile(e.y), on ? 'O' : 'o', 4);
        mechRows.push(`${on ? 'O' : 'o'}  core "${e.id}" ${on ? 'LIT' : 'idle'}`);
        break;
      case 'exit':
        for (let dr = 0; dr < e.h; dr++) for (let dc = 0; dc < e.w; dc++) cv.put(e.c + dc, e.r + dr, on ? 'E' : 'e', 2);
        mechRows.push(`${on ? 'E' : 'e'}  exit "${e.id}" ${on ? 'HELD' : 'empty'}`);
        break;
    }
  }

  const enemyRows: string[] = [];
  for (const e of snap.enemies) {
    const ch = e.alive ? ENEMY_LETTER[e.type] ?? 'M' : 'x';
    cv.put(tile(e.x), tile(e.y), ch, e.alive ? 6 : 1);
    const state = e.alive ? `${e.state}${e.target !== undefined ? ` -> ${TAPE_NAMES[e.target]}` : ''}${e.shield ? ', shield up' : ''}` : 'DEAD';
    enemyRows.push(`${ch}  ${e.type} "${e.id}" at ${pos(e.x, e.y)} hp ${e.hp}/${e.maxHp} facing ${dirText(e.facing)}: ${state}`);
  }

  for (const p of snap.projectiles) cv.put(tile(p.x), tile(p.y), '*', 5);
  const shotRows = snap.projectiles.map((p) => `*  ${p.archetype} from ${'tape' in p.owner ? `tape ${TAPE_NAMES[p.owner.tape]}` : p.owner.enemy} at ${pos(p.x, p.y)} heading ${dirText(p.dir)}`);

  const selfRows: string[] = [];
  const crowd = new Map<string, number>();
  for (const a of snap.actors) {
    const key = `${tile(a.x)},${tile(a.y)}`;
    crowd.set(key, (crowd.get(key) ?? 0) + 1);
  }
  for (const a of snap.actors) {
    const key = `${tile(a.x)},${tile(a.y)}`;
    const many = crowd.get(key)!;
    cv.put(tile(a.x), tile(a.y), many > 1 ? String(many) : selfChar(a), many > 1 ? 9 : a.life === 'alive' ? 8 : 7);
    if (a.spark) cv.put(tile(a.spark.x), tile(a.spark.y), '!', 7);
    const tape = tapes.find((t) => t.index === a.tape);
    const life = a.life === 'alive' ? (a.synced ? 'alive' : 'alive but DESYNCED') : 'DEAD (ghost)';
    const head = tape ? `${tape.speed}x ${tape.endMode}` : 'live';
    const where = a.phase.ended ? 'tape ended, holding' : `local tick ${fmt(a.phase.tick, 1)}${a.phase.dir === -1 ? ' (reversing)' : ''}${a.phase.traversal > 0 ? `, pass ${a.phase.traversal + 1}` : ''}`;
    selfRows.push(
      `${selfChar(a)}  tape ${TAPE_NAMES[a.tape]} (${head}) at ${pos(a.x, a.y)} facing ${dirText(a.facing)}: ${life}, ${a.anim}${a.iframes ? ', i-frames' : ''}; ${where}${a.spark ? `; spark at ${pos(a.spark.x, a.spark.y)}` : ''}`,
    );
  }

  const obj = snap.objective;
  const head = `beat ${fmt(snap.beat)} (substep ${snap.sub})   objective ${obj.complete ? 'COMPLETE' : `${Math.round(obj.progress * 100)}%`}   selves alive ${obj.survivors}`;
  return [head, '', ...cv.lines(), '', ...selfRows, ...enemyRows, ...shotRows, ...mechRows];
}
