/**
 * Authoring-time validation of level data.
 *
 * Every rule here is a documented rule in src/core/types.ts (the doc comments on LevelDef and its
 * family) or a consequence of one. The checks run on plain data, never on a running simulation, so
 * a broken level is reported by the content tests before the game ever loads it.
 *
 * Return convention: validateLevel / validateCampaign return human-readable strings. Entries that
 * start with `note:` are advisories and do not make a level invalid; every other entry is a
 * problem. Use `isProblem` to tell them apart.
 *
 * This file imports nothing from src/core except the shared types module (ARCHITECTURE.md rule for
 * src/content), so the signal-expression walk is implemented here rather than shared with the sim.
 */
import { ALL_SPEEDS, TAPE_COUNT } from '../core/types';
import type {
  EndMode,
  EntityDef,
  LevelDef,
  LevelMusicDef,
  ObjectiveDef,
  TapeSpeed,
  Theme,
} from '../core/types';

/** Characters the map grammar defines (types.ts MapRows). */
const MAP_CHARS: ReadonlySet<string> = new Set(['#', '.', ' ', '=', ':', ',', '~']);
/**
 * Tiles a self can stand on. '=' is a low barrier that blocks movement, so it is not walkable; '#'
 * and ' ' are never walkable. Doors and breakables are placed on these floor tiles, so treating
 * them as passable for reachability (types.ts EntityDef doc) falls out of the same test.
 */
const FLOOR_CHARS: ReadonlySet<string> = new Set(['.', ':', ',', '~']);

const THEMES: readonly Theme[] = ['upper', 'mid', 'lower', 'core'];
const END_MODES: readonly EndMode[] = ['stop', 'repeat', 'reverse'];
const ENEMY_TYPES: readonly string[] = ['grunt', 'stalker', 'turret', 'shielder', 'brute', 'drone', 'boss'];
const OBJECTIVE_TYPES: readonly string[] = ['eliminate', 'reach', 'activate', 'boss', 'signal'];
const MUSIC_ROLES: readonly string[] = ['bass', 'drums', 'melody', 'chord'];
/** Traps and automated machinery (docs/TRAPS.md; types.ts SpikesDef..MagnetDef). */
const TRAP_KINDS: readonly string[] = ['spikes', 'crusher', 'conveyor', 'flame', 'dart', 'bumper', 'sensor', 'relay', 'magnet'];
const ENTITY_KINDS: readonly string[] = ['enemy', 'door', 'switch', 'plate', 'breakable', 'laser', 'core', 'exit', 'decor', ...TRAP_KINDS];
const DIRS: readonly string[] = ['n', 'e', 's', 'w'];
const DIR_STEP: Readonly<Record<string, readonly [number, number]>> = { n: [0, -1], e: [1, 0], s: [0, 1], w: [-1, 0] };
const DECOR_TYPES: readonly string[] = [
  'graffiti', 'vines', 'bush', 'crate', 'barrel', 'pipe', 'console', 'generator', 'vent', 'arch',
  'rubble', 'chest', 'neon', 'runePanel', 'waveScreen', 'cable', 'lamp', 'timeMachine',
];
/** Entity kinds that carry an id (and therefore share the one id namespace). */
const ID_KINDS: ReadonlySet<string> = new Set(['enemy', 'door', 'switch', 'plate', 'breakable', 'laser', 'core', 'exit', ...TRAP_KINDS]);
/** Kinds whose id is a signal the rest of the level can read (types.ts SwitchDef..ExitDef). */
const SIGNAL_KINDS: ReadonlySet<string> = new Set(['switch', 'plate', 'breakable', 'core', 'exit', ...TRAP_KINDS]);
/**
 * Entities that occupy their tile exclusively. Plates, exits, lasers and decor are standable or
 * non-colliding, so they may share a tile with a body. An enemy on a plate is the documented way a
 * plate is pressed (types.ts PlateDef), which is why plates are not in this set.
 */
const SOLID_KINDS: ReadonlySet<string> = new Set(['enemy', 'door', 'switch', 'breakable', 'core']);

const DEAD_PREFIX = 'dead:';

/** True for an entry that makes a level invalid; false for `note:` advisories. */
export function isProblem(message: string): boolean {
  return !message.startsWith('note:');
}

export function validateLevel(level: LevelDef): string[] {
  const out: string[] = [];
  const problem = (message: string): void => {
    out.push(message);
  };

  // ── identity ──
  if (!isNonEmptyString(level.id)) problem('id must be a non-empty string');
  if (!isNonEmptyString(level.name)) problem('name must be a non-empty string');
  if (!isNonEmptyString(level.tagline)) problem('tagline must be a non-empty string');
  if (!THEMES.includes(level.theme)) problem(`theme "${String(level.theme)}" is not one of ${THEMES.join(', ')}`);
  if (!isInt(level.index) || level.index < 0) problem(`index must be a non-negative integer (got ${String(level.index)})`);

  // ── time (ARCHITECTURE "One clock", types.ts LevelDef.bpm / bars / horizonBars) ──
  if (!isNum(level.bpm) || level.bpm <= 0) {
    problem(`bpm must be a positive number (got ${String(level.bpm)})`);
  } else if (!Number.isInteger(3600 / level.bpm)) {
    problem(`3600 / bpm must be an integer so a beat is a whole number of local ticks (bpm ${level.bpm} gives ${3600 / level.bpm})`);
  }
  const barsOk = isInt(level.bars) && level.bars > 0;
  if (!barsOk) problem(`bars must be a positive integer (got ${String(level.bars)})`);
  const horizonOk = isInt(level.horizonBars) && level.horizonBars > 0;
  if (!horizonOk) problem(`horizonBars must be a positive integer (got ${String(level.horizonBars)})`);

  // ── cassettes and speeds (PLAY-05, TIME-04, types.ts TapeSpeed) ──
  if (!isInt(level.maxTapes) || level.maxTapes < 1 || level.maxTapes > TAPE_COUNT) {
    problem(`maxTapes must be an integer 1..${TAPE_COUNT} (got ${String(level.maxTapes)})`);
  }
  const speeds = checkUniqueList<TapeSpeed>(level.speeds, 'speeds', (s) => ALL_SPEEDS.includes(s), 'a power of two from ALL_SPEEDS', problem);
  const endModes = checkUniqueList<EndMode>(level.endModes, 'endModes', (m) => END_MODES.includes(m), 'one of stop, repeat, reverse', problem);
  if (endModes !== null && endModes.length === 0) problem('endModes must not be empty');
  if (speeds !== null && speeds.length === 0) problem('speeds must not be empty');

  const validSpeeds = (speeds ?? []).filter((s) => ALL_SPEEDS.includes(s));
  if (barsOk && horizonOk && validSpeeds.length > 0) {
    const fastest = Math.max(...validSpeeds);
    const slowest = Math.min(...validSpeeds);
    // A fastest-speed pass occupies bars / speed master bars; a horizon shorter than that cannot
    // contain even one full pass of a tape the player can select.
    if (level.horizonBars < level.bars / fastest) {
      problem(`horizonBars ${level.horizonBars} is shorter than one pass of the fastest speed (${level.bars} / ${fastest} = ${level.bars / fastest} bars)`);
    }
    if (level.horizonBars < level.bars / slowest) {
      out.push(`note: horizonBars ${level.horizonBars} is shorter than one pass of the slowest offered speed (${level.bars} / ${slowest} = ${level.bars / slowest} bars); the horizon will cut that tape off`);
    }
  }

  // ── map (types.ts MapRows) ──
  const mapOk = checkMapShape(level.map, problem);
  const geo = mapOk ? { rows: level.map.length, cols: level.map[0]!.length, grid: level.map } : null;

  // ── start (REC-02) ──
  let startTile: [number, number] | null = null;
  if (!isFiniteVec(level.start)) {
    problem('start must be a Vec2 of finite numbers');
  } else if (geo !== null) {
    if (!inMap(geo, level.start.x, level.start.y)) {
      problem(`start (${level.start.x}, ${level.start.y}) is outside the map`);
    } else {
      const c = Math.floor(level.start.x);
      const r = Math.floor(level.start.y);
      if (!isWalkable(geo, c, r)) {
        problem(`start tile (${c},${r}) is not a walkable floor tile (found '${geo.grid[r]![c]}')`);
      } else {
        startTile = [c, r];
      }
    }
  }
  if (level.startFacing !== undefined && !isNum(level.startFacing)) problem('startFacing must be a finite number when present');

  // ── walkable area enclosure (types.ts MapRows: the playfield is bounded) ──
  if (geo !== null && startTile !== null) {
    const reached = floodFill(geo, startTile);
    let leaks = 0;
    let firstLeak: [number, number] | null = null;
    for (let r = 0; r < geo.rows; r++) {
      for (let c = 0; c < geo.cols; c++) {
        if (!reached[r * geo.cols + c]) continue;
        if (c === 0 || r === 0 || c === geo.cols - 1 || r === geo.rows - 1) {
          leaks++;
          firstLeak ??= [c, r];
        }
      }
    }
    // Walkable border tiles that the start cannot reach are sealed off by walls or void, which is
    // what "bounded by void" permits; only the reachable playfield must stay inside the map.
    if (firstLeak !== null) {
      problem(`walkable area leaks past the map edge at (${firstLeak[0]},${firstLeak[1]}); ${leaks} reachable border tile(s) must be walls or void`);
    }
  }

  // ── entities ──
  const entities: EntityDef[] = Array.isArray(level.entities) ? level.entities : [];
  if (!Array.isArray(level.entities)) problem('entities must be an array');

  const idKinds = new Map<string, string>();
  const enemyIds = new Set<string>();
  const signalIds = new Set<string>();
  let bossCount = 0;
  let enemyCount = 0;
  let coreCount = 0;
  let exitCount = 0;

  // Pass 1: ids, duplicate detection and the producer tables every later check reads.
  entities.forEach((e, i) => {
    if (typeof e !== 'object' || e === null || !ENTITY_KINDS.includes(e.kind)) {
      problem(`entity #${i} has unknown kind ${JSON.stringify((e as { kind?: unknown } | null)?.kind)}`);
      return;
    }
    if (e.kind === 'enemy') {
      enemyCount++;
      if (e.type === 'boss') bossCount++;
    }
    if (e.kind === 'core') coreCount++;
    if (e.kind === 'exit') exitCount++;
    if (!ID_KINDS.has(e.kind)) return;
    const id = (e as { id?: unknown }).id;
    const label = describeEntity(e, i);
    if (!isNonEmptyString(id)) {
      problem(`${label}: id must be a non-empty string`);
      return;
    }
    const previous = idKinds.get(id);
    if (previous !== undefined) {
      problem(`duplicate id "${id}" (${previous} and ${e.kind}); ids must be unique across signals, enemies, doors and lasers`);
      return;
    }
    idKinds.set(id, e.kind);
    if (e.kind === 'enemy') enemyIds.add(id);
    if (SIGNAL_KINDS.has(e.kind)) signalIds.add(id);
    // Secondary trap signals (docs/TRAPS.md): a belt's reversed flag, a relay's armed flag.
    if (e.kind === 'conveyor') signalIds.add(`${id}.rev`);
    if (e.kind === 'relay') signalIds.add(`${id}.armed`);
  });

  // Pass 2: per-entity geometry, field rules, and the work lists the later passes consume.
  const occupied = new Map<string, string>();
  const reachTargets: { label: string; cells: [number, number][] }[] = [];
  const expressions: { where: string; expr: unknown }[] = [];
  const exitIds = new Set<string>();
  const coreIds = new Set<string>();

  const occupy = (label: string, c: number, r: number): void => {
    const key = `${c},${r}`;
    const other = occupied.get(key);
    if (other !== undefined) {
      problem(`${label} and ${other} share tile (${c},${r}); solid entities need their own tile`);
    } else {
      occupied.set(key, label);
    }
  };

  /** Point entity (enemy, switch, core): position must be in the map and on a floor tile. */
  const pointTile = (label: string, x: unknown, y: unknown): [number, number] | null => {
    if (!isNum(x) || !isNum(y)) {
      problem(`${label}: position must be finite numbers`);
      return null;
    }
    if (geo === null) return null;
    if (!inMap(geo, x, y)) {
      problem(`${label}: position (${x}, ${y}) is outside the map`);
      return null;
    }
    const c = Math.floor(x);
    const r = Math.floor(y);
    if (!isWalkable(geo, c, r)) {
      problem(`${label}: tile (${c},${r}) is '${geo.grid[r]![c]}', not a floor tile`);
      return null;
    }
    return [c, r];
  };

  /** Cell entity (plate, breakable, door cell, exit cell): integer tile on a floor tile. */
  const cellTile = (label: string, c: unknown, r: unknown): [number, number] | null => {
    if (!isInt(c) || !isInt(r)) {
      problem(`${label}: cell coordinates must be integers (got ${String(c)}, ${String(r)})`);
      return null;
    }
    if (geo === null) return null;
    if (c < 0 || r < 0 || c >= geo.cols || r >= geo.rows) {
      problem(`${label}: cell (${c},${r}) is outside the map`);
      return null;
    }
    if (!isWalkable(geo, c, r)) {
      problem(`${label}: cell (${c},${r}) is '${geo.grid[r]![c]}', not a floor tile`);
      return null;
    }
    return [c, r];
  };

  const insideOnly = (label: string, x: unknown, y: unknown): void => {
    if (!isNum(x) || !isNum(y)) {
      problem(`${label}: position must be finite numbers`);
      return;
    }
    if (geo !== null && !inMap(geo, x, y)) problem(`${label}: position (${x}, ${y}) is outside the map`);
  };

  // ── trap helpers (docs/TRAPS.md) ──
  const crusherCells: { label: string; c: number; r: number }[] = [];
  const beltCells = new Map<string, string>();
  /** Local ticks per master beat; trap beat grids must land on whole local ticks. */
  const ticksPerBeat = isNum(level.bpm) && level.bpm > 0 ? 3600 / level.bpm : NaN;
  const onTickGrid = (beats: number): boolean => !Number.isInteger(ticksPerBeat) || Number.isInteger(Math.round(beats * ticksPerBeat * 1e6) / 1e6);

  /** A non-empty list of distinct floor cells. Returns the valid ones in order. */
  const cellList = (label: string, cells: unknown): [number, number][] => {
    const out: [number, number][] = [];
    if (!Array.isArray(cells) || cells.length === 0) {
      problem(`${label}: needs at least one cell`);
      return out;
    }
    const seen = new Set<string>();
    for (const cell of cells) {
      const tile = cellTile(label, cell?.c, cell?.r);
      if (tile === null) continue;
      const key = `${tile[0]},${tile[1]}`;
      if (seen.has(key)) {
        problem(`${label}: cell (${tile[0]},${tile[1]}) is listed twice`);
        continue;
      }
      seen.add(key);
      out.push(tile);
    }
    return out;
  };
  const requireExpr = (label: string, field: string, expr: unknown): void => {
    if (expr === undefined) problem(`${label}: ${field} is required`);
    else expressions.push({ where: `${label}.${field}`, expr });
  };
  const optionalExpr = (label: string, field: string, expr: unknown): void => {
    if (expr !== undefined) expressions.push({ where: `${label}.${field}`, expr });
  };
  const requireDir = (label: string, dir: unknown): dir is string => {
    if (typeof dir === 'string' && DIRS.includes(dir)) return true;
    problem(`${label}: dir must be one of n, e, s, w (got ${JSON.stringify(dir)})`);
    return false;
  };
  const optionalPositive = (label: string, field: string, v: unknown, integer = false): void => {
    if (v === undefined) return;
    if (!isNum(v) || v <= 0 || (integer && !isInt(v))) problem(`${label}: ${field} must be a positive ${integer ? 'integer' : 'number'} when present`);
  };
  /** Emitter tile (flame nozzle, dart launcher): any tile in the map whose front tile is not a wall. */
  const emitterTile = (label: string, c: unknown, r: unknown, dir: unknown): void => {
    const dirOk = requireDir(label, dir);
    if (!isInt(c) || !isInt(r)) {
      problem(`${label}: c and r must be integers (got ${String(c)}, ${String(r)})`);
      return;
    }
    if (geo === null) return;
    if (c < 0 || r < 0 || c >= geo.cols || r >= geo.rows) {
      problem(`${label}: tile (${c},${r}) is outside the map`);
      return;
    }
    if (!dirOk) return;
    const [dc, dr] = DIR_STEP[dir as string]!;
    const fc = c + dc;
    const fr = r + dr;
    if (fc < 0 || fr < 0 || fc >= geo.cols || fr >= geo.rows || geo.grid[fr]![fc] === '#') {
      problem(`${label}: the tile in front of it (${fc},${fr}) is a wall or outside the map, so it can never reach anything`);
    }
  };

  entities.forEach((e, i) => {
    if (typeof e !== 'object' || e === null || !ENTITY_KINDS.includes(e.kind)) return;
    const label = describeEntity(e, i);
    switch (e.kind) {
      case 'spikes': {
        cellList(label, e.cells);
        requireExpr(label, 'upWhen', e.upWhen);
        optionalPositive(label, 'damage', e.damage, true);
        break;
      }
      case 'crusher': {
        const cells = cellList(label, e.cells);
        if (Array.isArray(e.cells) && cells.length === e.cells.length && cells.length > 1) {
          const dc = cells[1]![0] - cells[0]![0];
          const dr = cells[1]![1] - cells[0]![1];
          const unit = Math.abs(dc) + Math.abs(dr) === 1;
          const straight = unit && cells.every(([c, r], k) => c === cells[0]![0] + dc * k && r === cells[0]![1] + dr * k);
          if (!straight) problem(`${label}: cells must form one straight, contiguous line ordered from the housing outward`);
        }
        for (const [c, r] of cells) crusherCells.push({ label, c, r });
        requireExpr(label, 'extendWhen', e.extendWhen);
        if (e.dir !== undefined) requireDir(label, e.dir);
        optionalPositive(label, 'damage', e.damage, true);
        break;
      }
      case 'conveyor': {
        const cells = cellList(label, e.cells);
        for (const [c, r] of cells) {
          const key = `${c},${r}`;
          const other = beltCells.get(key);
          if (other !== undefined) problem(`${label} and ${other} share tile (${c},${r}); a tile belongs to one belt`);
          else beltCells.set(key, label);
        }
        requireDir(label, e.dir);
        optionalPositive(label, 'speed', e.speed);
        optionalExpr(label, 'runWhen', e.runWhen);
        optionalExpr(label, 'reverseWhen', e.reverseWhen);
        break;
      }
      case 'flame': {
        emitterTile(label, e.c, e.r, e.dir);
        if (!isInt(e.range) || e.range <= 0) problem(`${label}: range must be a positive integer number of tiles`);
        requireExpr(label, 'onWhen', e.onWhen);
        optionalPositive(label, 'damage', e.damage, true);
        break;
      }
      case 'dart': {
        emitterTile(label, e.c, e.r, e.dir);
        if (e.every !== undefined && !(isNum(e.every) && e.every > 0)) problem(`${label}: every must be a positive number of beats`);
        else if (e.every !== undefined && !onTickGrid(e.every)) problem(`${label}: every ${e.every} beats is not a whole number of local ticks at ${level.bpm} bpm`);
        if (e.offset !== undefined && !(isNum(e.offset) && e.offset >= 0)) problem(`${label}: offset must be a non-negative number of beats`);
        else if (e.offset !== undefined && !onTickGrid(e.offset)) problem(`${label}: offset ${e.offset} beats is not a whole number of local ticks at ${level.bpm} bpm`);
        optionalExpr(label, 'enabledWhen', e.enabledWhen);
        optionalPositive(label, 'speed', e.speed);
        break;
      }
      case 'bumper': {
        cellTile(label, e.c, e.r);
        requireDir(label, e.dir);
        optionalPositive(label, 'power', e.power);
        requireExpr(label, 'fireWhen', e.fireWhen);
        break;
      }
      case 'sensor': {
        if (!isFiniteVec(e.from) || !isFiniteVec(e.to)) {
          problem(`${label}: from and to must be Vec2 of finite numbers`);
        } else {
          if (e.from.x === e.to.x && e.from.y === e.to.y) problem(`${label}: from and to must differ`);
          for (const [name, p] of [['from', e.from], ['to', e.to]] as const) {
            insideOnly(`${label}.${name}`, p.x, p.y);
            if (geo !== null && inMap(geo, p.x, p.y) && geo.grid[Math.floor(p.y)]![Math.floor(p.x)] === '#') {
              problem(`${label}.${name}: (${p.x}, ${p.y}) is inside a wall tile; put both ends of the beam over open tiles`);
            }
          }
        }
        if (e.detects !== undefined && !['any', 'selves', 'enemies'].includes(e.detects)) problem(`${label}: detects must be any, selves or enemies`);
        if (e.latch !== undefined && typeof e.latch !== 'boolean') problem(`${label}: latch must be a boolean`);
        break;
      }
      case 'relay': {
        requireExpr(label, 'trigger', e.trigger);
        if (e.mode !== undefined && !['pulse', 'latch', 'toggle'].includes(e.mode)) problem(`${label}: mode must be pulse, latch or toggle`);
        for (const [field, v] of [['quantize', e.quantize], ['delay', e.delay], ['hold', e.hold]] as const) {
          if (v === undefined) continue;
          if (!isNum(v) || v < 0 || (field === 'hold' && v <= 0)) problem(`${label}: ${field} must be a ${field === 'hold' ? 'positive' : 'non-negative'} number of beats`);
          else if (!onTickGrid(v)) problem(`${label}: ${field} ${v} beats is not a whole number of local ticks at ${level.bpm} bpm`);
        }
        if ((e.x === undefined) !== (e.y === undefined)) problem(`${label}: give both x and y, or neither`);
        else if (e.x !== undefined) insideOnly(label, e.x, e.y);
        break;
      }
      case 'magnet': {
        insideOnly(label, e.x, e.y);
        if (!isNum(e.radius) || e.radius <= 0) problem(`${label}: radius must be a positive number`);
        optionalPositive(label, 'pull', e.pull);
        requireExpr(label, 'onWhen', e.onWhen);
        break;
      }
      case 'enemy': {
        if (!ENEMY_TYPES.includes(e.type)) problem(`${label}: unknown enemy type "${String(e.type)}"`);
        if (e.facing !== undefined && !isNum(e.facing)) problem(`${label}: facing must be a finite number`);
        if (e.hp !== undefined && !(isInt(e.hp) && e.hp > 0)) problem(`${label}: hp must be a positive integer`);
        if (e.beat !== undefined) {
          if (!isObject(e.beat) || !isInt(e.beat.every) || e.beat.every <= 0 || !isNum(e.beat.offset)) {
            problem(`${label}: beat must be { every: positive integer, offset: number }`);
          }
        }
        if (e.arc !== undefined && !isNum(e.arc)) problem(`${label}: arc must be a finite number`);
        const tile = pointTile(label, e.x, e.y);
        if (tile !== null) {
          occupy(label, tile[0], tile[1]);
          reachTargets.push({ label, cells: [tile] });
        }
        if (e.wakeWhen !== undefined) expressions.push({ where: `${label}.wakeWhen`, expr: e.wakeWhen });
        break;
      }
      case 'door': {
        if (!Array.isArray(e.cells) || e.cells.length === 0) {
          problem(`${label}: a door needs at least one cell`);
        } else {
          const seen = new Set<string>();
          for (const cell of e.cells) {
            const tile = cellTile(label, cell?.c, cell?.r);
            if (tile === null) continue;
            const key = `${tile[0]},${tile[1]}`;
            if (seen.has(key)) {
              problem(`${label}: cell (${tile[0]},${tile[1]}) is listed twice`);
              continue;
            }
            seen.add(key);
            occupy(label, tile[0], tile[1]);
          }
        }
        if (e.openWhen === undefined) problem(`${label}: openWhen is required`);
        else expressions.push({ where: `${label}.openWhen`, expr: e.openWhen });
        break;
      }
      case 'switch': {
        if (e.initial !== undefined && typeof e.initial !== 'boolean') problem(`${label}: initial must be a boolean`);
        const tile = pointTile(label, e.x, e.y);
        if (tile !== null) {
          occupy(label, tile[0], tile[1]);
          reachTargets.push({ label, cells: [tile] });
        }
        break;
      }
      case 'plate': {
        if (e.heavy !== undefined && typeof e.heavy !== 'boolean') problem(`${label}: heavy must be a boolean`);
        const tile = cellTile(label, e.c, e.r);
        if (tile !== null) reachTargets.push({ label, cells: [tile] });
        break;
      }
      case 'breakable': {
        if (!isNum(e.threshold) || e.threshold <= 0) problem(`${label}: threshold must be a positive number`);
        const tile = cellTile(label, e.c, e.r);
        if (tile !== null) occupy(label, tile[0], tile[1]);
        break;
      }
      case 'laser': {
        if (!isFiniteVec(e.from) || !isFiniteVec(e.to)) {
          problem(`${label}: from and to must be Vec2 of finite numbers`);
        } else {
          insideOnly(`${label}.from`, e.from.x, e.from.y);
          insideOnly(`${label}.to`, e.to.x, e.to.y);
        }
        if (e.onWhen === undefined) problem(`${label}: onWhen is required`);
        else expressions.push({ where: `${label}.onWhen`, expr: e.onWhen });
        break;
      }
      case 'core': {
        if (e.threshold !== undefined && !(isNum(e.threshold) && e.threshold > 0)) {
          problem(`${label}: threshold must be a positive number when present`);
        }
        const tile = pointTile(label, e.x, e.y);
        if (tile !== null) {
          occupy(label, tile[0], tile[1]);
          coreIds.add(String(e.id));
          reachTargets.push({ label, cells: [tile] });
        }
        break;
      }
      case 'exit': {
        if (!isInt(e.w) || e.w <= 0 || !isInt(e.h) || e.h <= 0) {
          problem(`${label}: w and h must be positive integers`);
          break;
        }
        const cells: [number, number][] = [];
        for (let dr = 0; dr < e.h; dr++) {
          for (let dc = 0; dc < e.w; dc++) {
            const tile = cellTile(label, e.c + dc, e.r + dr);
            if (tile !== null) cells.push(tile);
          }
        }
        exitIds.add(String(e.id));
        if (cells.length > 0) reachTargets.push({ label, cells });
        break;
      }
      case 'decor': {
        if (!DECOR_TYPES.includes(e.type)) problem(`${label}: unknown decor type "${String(e.type)}"`);
        if (e.rot !== undefined && ![0, 1, 2, 3].includes(e.rot)) problem(`${label}: rot must be 0..3`);
        insideOnly(label, e.x, e.y);
        break;
      }
    }
  });

  // A crusher turns its tiles solid, so no door, switch, breakable or core may share them (an enemy
  // may stand on one: that is how a crusher is used).
  const crusherSeen = new Map<string, string>();
  for (const cell of crusherCells) {
    const key = `${cell.c},${cell.r}`;
    const other = occupied.get(key);
    if (other !== undefined && !other.startsWith('enemy ')) {
      problem(`${cell.label} and ${other} share tile (${cell.c},${cell.r}); solid entities need their own tile`);
    }
    const twin = crusherSeen.get(key);
    if (twin !== undefined && twin !== cell.label) problem(`${cell.label} and ${twin} share tile (${cell.c},${cell.r}); a tile belongs to one crusher`);
    else crusherSeen.set(key, cell.label);
  }

  // ── signal producers, references and expression shape (types.ts SignalExpr) ──
  for (const ref of expressions) {
    checkExpression(ref.expr, ref.where, signalIds, enemyIds, problem);
  }

  // ── objective (types.ts ObjectiveDef) ──
  const objective: ObjectiveDef | undefined = level.objective;
  if (!isObject(objective)) {
    problem('objective is required');
  } else {
    if (!OBJECTIVE_TYPES.includes(objective.type)) problem(`objective type "${String(objective.type)}" is not recognised`);
    if (!isNonEmptyString(objective.text)) problem('objective text must be a non-empty string');
    if (objective.targets !== undefined && !Array.isArray(objective.targets)) {
      problem('objective targets must be an array of ids');
    }
    const targets: string[] = Array.isArray(objective.targets) ? objective.targets : [];
    const requireTargetsIn = (known: { has(key: string): boolean }, kind: string): void => {
      for (const t of targets) {
        if (!known.has(t)) problem(`objective target "${String(t)}" is not a ${kind}`);
      }
    };
    switch (objective.type) {
      case 'eliminate':
        if (targets.length > 0) requireTargetsIn(enemyIds, 'enemy');
        else if (enemyCount === 0) problem('eliminate objective needs at least one enemy or explicit targets');
        break;
      case 'reach':
        if (exitCount === 0) problem('reach objective needs at least one exit');
        if (targets.length > 0) requireTargetsIn(exitIds, 'exit');
        break;
      case 'activate':
        if (targets.length > 0) requireTargetsIn(coreIds, 'core');
        else if (coreCount === 0) problem('activate objective needs at least one core');
        break;
      case 'boss':
        if (bossCount !== 1) problem(`boss objective needs exactly one boss enemy (found ${bossCount})`);
        if (targets.length > 0) requireTargetsIn(enemyIds, 'enemy');
        break;
      case 'signal':
        if (objective.when === undefined) problem('signal objective needs a "when" expression');
        if (targets.length > 0) requireTargetsIn(idKinds, 'known id');
        break;
    }
    if (objective.when !== undefined) {
      checkExpression(objective.when, 'objective.when', signalIds, enemyIds, problem);
    }
  }

  // ── reachability (ARCHITECTURE "everything reachable"; doors/breakables are floor, so passable) ──
  if (geo !== null && startTile !== null) {
    const reached = floodFill(geo, startTile);
    for (const target of reachTargets) {
      const ok = target.cells.some(([c, r]) => reached[r * geo.cols + c] === 1);
      if (!ok) problem(`${target.label} is unreachable from the start`);
    }
  }

  // ── music (types.ts LevelMusicDef) ──
  const music: LevelMusicDef | undefined = level.music;
  if (!isObject(music)) {
    problem('music is required');
  } else {
    if (!isInt(music.root) || music.root < 0 || music.root > 11) problem(`music.root must be an integer 0..11 (got ${String(music.root)})`);
    if (!isNonEmptyString(music.scale)) problem('music.scale must be a non-empty string');
    if (!Array.isArray(music.progression) || music.progression.length === 0) {
      problem('music.progression must be a non-empty array of scale degrees');
    } else {
      for (const degree of music.progression) {
        if (!isInt(degree) || degree < 0 || degree > 6) problem(`music.progression degree ${String(degree)} must be an integer 0..6`);
      }
    }
    if (music.chordBars !== undefined && !(isInt(music.chordBars) && music.chordBars > 0)) {
      problem('music.chordBars must be a positive integer when present');
    }
    if (!Array.isArray(music.tracks) || music.tracks.length !== 4) {
      problem(`music.tracks must have exactly four entries (found ${Array.isArray(music.tracks) ? music.tracks.length : 'none'})`);
    } else {
      music.tracks.forEach((track, t) => {
        const where = `music.tracks[${t}]`;
        if (!isObject(track)) {
          problem(`${where} must be an object`);
          return;
        }
        if (!MUSIC_ROLES.includes(track.role)) problem(`${where}.role "${String(track.role)}" is not one of ${MUSIC_ROLES.join(', ')}`);
        if (!isNonEmptyString(track.formula)) problem(`${where}.formula must be a non-empty string`);
        if (track.params !== undefined && (!isObject(track.params) || !Object.values(track.params).every(isNum))) {
          problem(`${where}.params must map names to finite numbers`);
        }
        if (track.genre !== undefined && typeof track.genre !== 'string') problem(`${where}.genre must be a string`);
      });
    }
  }

  // ── briefing, loot, hints ──
  if (!Array.isArray(level.briefing) || level.briefing.length === 0) {
    problem('briefing needs at least one line');
  } else if (!level.briefing.every(isNonEmptyString)) {
    problem('every briefing line must be a non-empty string');
  }
  if (!Array.isArray(level.loot)) {
    problem('loot must be an array of gear ids');
  } else if (!level.loot.every(isNonEmptyString)) {
    problem('every loot id must be a non-empty string');
  }
  if (level.hints !== undefined) {
    if (!isObject(level.hints)) {
      problem('hints must be an object keyed by tape number');
    } else {
      for (const [key, text] of Object.entries(level.hints)) {
        const tape = Number(key);
        if (!isInt(tape) || tape < 1 || tape > TAPE_COUNT) problem(`hint key "${key}" must be a tape number 1..${TAPE_COUNT}`);
        if (!isNonEmptyString(text)) problem(`hint for tape ${key} must be a non-empty string`);
      }
    }
  }

  return out;
}

/** Index of the first campaign level (data/levels/01-*.json); the sandbox is index 0, off the path. */
export const FIRST_CAMPAIGN_INDEX = 1;

/** An ordered campaign: unique ids, index = position + 1 (levels are numbered 1..N like their files). */
export function validateCampaign(levels: LevelDef[]): string[] {
  if (!Array.isArray(levels) || levels.length === 0) return ['campaign has no levels'];
  const out: string[] = [];
  const seenIds = new Map<string, number>();
  levels.forEach((level, position) => {
    const label = isNonEmptyString(level.id) ? level.id : `level #${position}`;
    if (isNonEmptyString(level.id)) {
      const first = seenIds.get(level.id);
      if (first !== undefined) {
        out.push(`duplicate level id "${level.id}" at campaign positions ${first} and ${position}`);
      } else {
        seenIds.set(level.id, position);
      }
    }
    if (level.index !== position + FIRST_CAMPAIGN_INDEX) {
      out.push(`${label}: index is ${String(level.index)}, expected ${position + FIRST_CAMPAIGN_INDEX} (campaign order is index ${FIRST_CAMPAIGN_INDEX}..${levels.length - 1 + FIRST_CAMPAIGN_INDEX})`);
    }
    for (const message of validateLevel(level)) {
      out.push(message.startsWith('note:')
        ? `note: ${label}: ${message.slice('note:'.length).trimStart()}`
        : `${label}: ${message}`);
    }
  });
  return out;
}

// ───────────────────────────── helpers ─────────────────────────────

interface Geo {
  rows: number;
  cols: number;
  grid: string[];
}

function isNum(v: unknown): v is number {
  return typeof v === 'number' && Number.isFinite(v);
}

function isInt(v: unknown): v is number {
  return typeof v === 'number' && Number.isInteger(v);
}

function isNonEmptyString(v: unknown): v is string {
  return typeof v === 'string' && v.trim() !== '';
}

function isObject(v: unknown): v is Record<string, any> {
  return typeof v === 'object' && v !== null && !Array.isArray(v);
}

function isFiniteVec(v: unknown): v is { x: number; y: number } {
  return isObject(v) && isNum(v.x) && isNum(v.y);
}

function describeEntity(e: { kind: string; id?: unknown }, index: number): string {
  return typeof e.id === 'string' && e.id !== '' ? `${e.kind} "${e.id}"` : `${e.kind} #${index}`;
}

/** Checks a list that must hold distinct members drawn from a fixed set. Returns the list or null when it is not an array. */
function checkUniqueList<T>(
  value: unknown,
  name: string,
  allowed: (v: T) => boolean,
  expected: string,
  problem: (m: string) => void,
): T[] | null {
  if (!Array.isArray(value)) {
    problem(`${name} must be an array`);
    return null;
  }
  const seen = new Set<unknown>();
  for (const member of value as T[]) {
    if (!allowed(member)) problem(`${name} entry ${JSON.stringify(member)} must be ${expected}`);
    if (seen.has(member)) problem(`${name} lists ${JSON.stringify(member)} more than once`);
    seen.add(member);
  }
  return value as T[];
}

/** Validates the shape of the map and returns true only when it is non-empty, rectangular and uses documented characters. */
function checkMapShape(map: unknown, problem: (m: string) => void): map is string[] {
  if (!Array.isArray(map) || map.length === 0) {
    problem('map must be a non-empty array of rows');
    return false;
  }
  if (!map.every((row) => typeof row === 'string')) {
    problem('every map row must be a string');
    return false;
  }
  const rows = map as string[];
  const width = rows[0]!.length;
  if (width === 0) {
    problem('map rows must not be empty');
    return false;
  }
  let rectangular = true;
  rows.forEach((row, r) => {
    if (row.length !== width) {
      problem(`map row ${r} has length ${row.length}, expected ${width} (map must be rectangular)`);
      rectangular = false;
    }
  });
  const badChars = new Set<string>();
  for (const row of rows) {
    for (const ch of row) {
      if (!MAP_CHARS.has(ch)) badChars.add(ch);
    }
  }
  if (badChars.size > 0) {
    problem(`map uses undocumented characters ${[...badChars].map((c) => JSON.stringify(c)).join(', ')}; allowed: ${[...MAP_CHARS].map((c) => JSON.stringify(c)).join(' ')}`);
  }
  return rectangular && badChars.size === 0;
}

function inMap(geo: Geo, x: number, y: number): boolean {
  return x >= 0 && y >= 0 && x < geo.cols && y < geo.rows;
}

function isWalkable(geo: Geo, c: number, r: number): boolean {
  if (c < 0 || r < 0 || c >= geo.cols || r >= geo.rows) return false;
  return FLOOR_CHARS.has(geo.grid[r]![c]!);
}

/** 4-connected flood over walkable tiles from `start`. Returns 1 for each reached tile, indexed r * cols + c. */
function floodFill(geo: Geo, start: [number, number]): Uint8Array {
  const reached = new Uint8Array(geo.cols * geo.rows);
  const stack: [number, number][] = [start];
  reached[start[1] * geo.cols + start[0]] = 1;
  while (stack.length > 0) {
    const [c, r] = stack.pop()!;
    const neighbours: [number, number][] = [[c + 1, r], [c - 1, r], [c, r + 1], [c, r - 1]];
    for (const [nc, nr] of neighbours) {
      if (!isWalkable(geo, nc, nr)) continue;
      const idx = nr * geo.cols + nc;
      if (reached[idx]) continue;
      reached[idx] = 1;
      stack.push([nc, nr]);
    }
  }
  return reached;
}

/**
 * Walks a SignalExpr (types.ts). Each node must have exactly one operator key. Every `sig` must be
 * produced by a signal-producing entity, or be `dead:<enemyId>` for an existing enemy.
 */
function checkExpression(
  expr: unknown,
  where: string,
  signalIds: ReadonlySet<string>,
  enemyIds: ReadonlySet<string>,
  problem: (m: string) => void,
): void {
  if (!isObject(expr)) {
    problem(`${where}: signal expression must be an object`);
    return;
  }
  const keys = Object.keys(expr);
  if (keys.length !== 1) {
    problem(`${where}: signal expression must have exactly one operator (has ${keys.length === 0 ? 'none' : keys.join(', ')})`);
    return;
  }
  const op = keys[0]!;
  const arg = expr[op];
  switch (op) {
    case 'sig': {
      if (!isNonEmptyString(arg)) {
        problem(`${where}: sig must be a non-empty signal id`);
        return;
      }
      if (arg.startsWith(DEAD_PREFIX)) {
        const enemy = arg.slice(DEAD_PREFIX.length);
        if (enemy === '') problem(`${where}: "${arg}" names no enemy`);
        else if (!enemyIds.has(enemy)) problem(`${where}: "${arg}" refers to enemy "${enemy}", which does not exist`);
      } else if (!signalIds.has(arg)) {
        problem(`${where}: signal "${arg}" is not produced by any switch, plate, breakable, core or exit`);
      }
      return;
    }
    case 'not':
      checkExpression(arg, `${where}.not`, signalIds, enemyIds, problem);
      return;
    case 'and':
    case 'or':
      if (!Array.isArray(arg) || arg.length === 0) {
        problem(`${where}: ${op} needs a non-empty array of expressions`);
        return;
      }
      arg.forEach((child, i) => checkExpression(child, `${where}.${op}[${i}]`, signalIds, enemyIds, problem));
      return;
    case 'xor':
      if (!Array.isArray(arg) || arg.length !== 2) {
        problem(`${where}: xor needs exactly two expressions`);
        return;
      }
      checkExpression(arg[0], `${where}.xor[0]`, signalIds, enemyIds, problem);
      checkExpression(arg[1], `${where}.xor[1]`, signalIds, enemyIds, problem);
      return;
    case 'const':
      if (typeof arg !== 'boolean') problem(`${where}: const must be true or false`);
      return;
    case 'beat': {
      if (!isObject(arg) || !isNum(arg.every) || arg.every <= 0 || !isNum(arg.from) || !isNum(arg.to)) {
        problem(`${where}: beat must be { every > 0, from, to } with finite numbers`);
        return;
      }
      const { every, from, to } = arg;
      if (!(from >= 0 && from < to && to <= every)) {
        problem(`${where}: beat window [${from}, ${to}) must satisfy 0 <= from < to <= every (every = ${every})`);
      }
      return;
    }
    default:
      problem(`${where}: unknown signal operator "${op}"`);
  }
}
