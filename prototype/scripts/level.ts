/**
 * The level-authoring CLI. Formats: data/levels/README.md and data/levels/solutions/README.md.
 *
 *   cd prototype && npx vite-node scripts/level.ts <command> <level> [options]
 *
 * Everything here goes through the real game code: the validator (src/content/validate.ts), the
 * Session via the headless bot (src/game/bot.ts) and the kernel's own formulas. `help` prints USAGE.
 */
import { existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { GEAR } from '../src/content/index';
import { campaignOrderProblems, levelFileProblems } from '../src/content/levelFiles';
import { isProblem, validateLevel } from '../src/content/validate';
import { deserializeTape } from '../src/core/tape';
import { BEATS_PER_BAR, TAPE_NAMES } from '../src/core/types';
import type { LevelDef, Resolution, ResolvedLoadout, TapeSpeed } from '../src/core/types';
import { frameAtBeat, LEGEND, renderFrame } from './lib/ascii';
import {
  findLevelPath,
  INDEX_PATH,
  isCampaignFile,
  LEVEL_DIR,
  listLevelFiles,
  loadIndex,
  loadLevelFile,
  loadSolution,
  saveIndex,
  saveSolution,
  solutionPathFor,
  type LevelFile,
} from './lib/files';
import { probeLines } from './lib/probe';
import { eventDiffLines, eventLines, outcomeLines, showLines, stepLines, takeTitle, tapeLines, traceLines } from './lib/report';
import { compiledSolution, mutationVariants, replayStoredTapes, resolvePrefix, runSolution, runVariants, verifyGenerated } from './lib/run';
import { baselineLoadout, checkSolution, solutionLoadout, staleReasons, usesBaseline, type SolutionFile } from './lib/solution';

export const USAGE = `OVERDUB level tools

  cd prototype && npx vite-node scripts/level.ts <command> <level> [options]

<level> is a path (../data/levels/03-crossfire.json), a file name in data/levels with or
without .json (03-crossfire), or just the campaign number (03). "sandbox" is the practice room.
The solution of a level is data/levels/solutions/<same file name>.

Commands
  validate <level|all>   Check the level file, its naming and its solution's structure.
                         Exit code 1 when there are problems ("note:" lines are advisories).
  show <level>           The map as ASCII with every entity, a legend, the objective, the
                         cassettes / speeds / end modes and the timing (tape length, master
                         span of one pass at each speed, horizon).
      --raw                also print the map rows exactly as authored
  run <level>            Compile the solution's plans, play them through the real game session
                         with the headless bot, and report: per take the plan as it played out
                         (tick and beat of every step) and a beat-by-beat event log, then the
                         final outcome with the game's own notes. Exit code 1 unless it wins.
      --write              store the inputs, tapes and expected outcome in the solution file
                           (only when the run wins; the file is rewritten in canonical layout)
      --upto N             record only the first N takes and report that intermediate state
      --trace A|B|C|D      also print that self's position on every master beat
      --every K            beat step for --trace (default 1; 0.5 = every half beat)
      --full               print every take's whole event log (default: take 1 in full, later
                           takes as "+ new / - no longer happens" against the run before them)
      --verbose            include enemy wind-ups, staggers and shots that hit walls
      --loadout a,b        wear these gear ids instead of the solution's (not with --write)
  ascii-at <level> --beat N
                         Draw the room at master beat N of the combined run: selves A-D (lower
                         case when dead, ? when desynced), enemies by letter, doors open/closed,
                         plus a table of exact positions and states.
      --to M --every K     draw several frames: beats N, N+K, ... up to M (default K = 1)
      --upto N             use only the first N takes
      --stored             use the tapes stored in the solution file instead of recompiling
  probe [level]          The numbers you keep needing, measured from the running code: tiles
                         run in N beats at each speed, momentum / damage / knockback of light
                         and heavy swings standing and running at each speed, how long each
                         action commits, enemy stats. With a level: its tempo, its speeds, and
                         which swings break its breakables / light its cores.
      --beats N            answer "how far does a self run in N master beats"
      --speed S            ... at tape speed S only (0.5, 1, 2 or 4)
      --loadout a,b        wear these gear ids instead of the baseline
  mutate <level>         Robustness check: re-run the solution with every take 1 and 2 local
                         ticks late / early (together and one take at a time) and with every
                         goto / via target nudged 0.08 tiles in each direction. Exit code 1 if
                         any variant loses: such a solution will not survive the Godot port.
      --quick              only the 1-tick variants (what the test suite runs)
  index                  List the campaign in order with each level's solution state.
      --write              rewrite data/levels/index.json (the list the Godot build loads)
  help                   This text.

Test suite for every campaign level (validates, replays stored inputs and tapes, mutates):
  cd prototype && npx vitest run tests/levels
`;

// ───────────────────────────── arguments ─────────────────────────────

const VALUE_FLAGS: ReadonlySet<string> = new Set(['upto', 'trace', 'every', 'beat', 'to', 'loadout', 'beats', 'speed']);
const BOOL_FLAGS: ReadonlySet<string> = new Set(['write', 'full', 'verbose', 'raw', 'stored', 'quick']);

interface Args {
  positional: string[];
  flags: Map<string, string>;
}

class UsageError extends Error {}

function parseArgs(argv: string[]): Args {
  const positional: string[] = [];
  const flags = new Map<string, string>();
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith('--')) {
      positional.push(a);
      continue;
    }
    const eq = a.indexOf('=');
    const name = eq < 0 ? a.slice(2) : a.slice(2, eq);
    if (BOOL_FLAGS.has(name)) flags.set(name, 'true');
    else if (VALUE_FLAGS.has(name)) {
      const value = eq < 0 ? argv[++i] : a.slice(eq + 1);
      if (value === undefined) throw new UsageError(`--${name} needs a value`);
      flags.set(name, value);
    } else throw new UsageError(`unknown option --${name}`);
  }
  return { positional, flags };
}

function numberFlag(args: Args, name: string): number | undefined {
  const v = args.flags.get(name);
  if (v === undefined) return undefined;
  const n = Number(v);
  if (!Number.isFinite(n)) throw new UsageError(`--${name} must be a number (got "${v}")`);
  return n;
}

function print(lines: readonly string[] | string): void {
  console.log(typeof lines === 'string' ? lines : lines.join('\n'));
}

function need(args: Args, what: string): string {
  const a = args.positional[1];
  if (!a) throw new UsageError(`${args.positional[0]} needs ${what}`);
  return a;
}

function loadoutFor(args: Args, sol: SolutionFile | null): ResolvedLoadout {
  const override = args.flags.get('loadout');
  if (override !== undefined) return solutionLoadout({ loadout: override.split(',').map((s) => s.trim()).filter(Boolean) });
  return sol ? solutionLoadout(sol) : baselineLoadout();
}

function loadoutText(loadout: ResolvedLoadout): string {
  const base = baselineLoadout().loadout;
  const swapped = Object.values(loadout.loadout).filter((id) => !Object.values(base).includes(id));
  return swapped.length ? `baseline with ${swapped.join(', ')}` : 'baseline';
}

function requireSolution(lf: LevelFile): SolutionFile {
  const path = solutionPathFor(lf.path);
  const sol = loadSolution(path);
  if (!sol) throw new Error(`no solution file: ${path}\n  Write one (see data/levels/solutions/README.md); data/levels/solutions/sandbox.json is a worked example.`);
  const problems = checkSolution(sol, lf.level);
  if (problems.length) throw new Error(`${path} has problems:\n${problems.map((p) => `  - ${p}`).join('\n')}`);
  return sol;
}

/** Refuse to simulate a level the validator rejects: the kernel's errors would be far less clear. */
function requireValid(lf: LevelFile): void {
  const problems = validateLevel(lf.level).filter(isProblem);
  if (problems.length) throw new Error(`${lf.file} is not a valid level:\n${problems.map((p) => `  - ${p}`).join('\n')}`);
}

// ───────────────────────────── validate ─────────────────────────────

function validateOne(lf: LevelFile, campaign: LevelFile[]): { problems: string[]; notes: string[] } {
  const problems: string[] = [];
  const notes: string[] = [];
  for (const m of validateLevel(lf.level)) (isProblem(m) ? problems : notes).push(m);
  problems.push(...levelFileProblems(lf.file, lf.level));
  for (const id of Array.isArray(lf.level.loot) ? lf.level.loot : []) if (!GEAR[id]) problems.push(`loot "${id}" is not a gear id (data/gear.json)`);
  if (isCampaignFile(lf.file)) {
    for (const p of campaignOrderProblems(campaign)) if (p.startsWith(`${lf.file}:`)) problems.push(p.slice(lf.file.length + 2));
    const index = loadIndex();
    if (index && !index.levels.includes(lf.stem)) notes.push(`note: data/levels/index.json does not list "${lf.stem}" yet; the Godot build loads levels from that list (level.ts index --write)`);
  }
  const solPath = solutionPathFor(lf.path);
  const sol = loadSolution(solPath);
  if (!sol) notes.push(`note: no solution yet (${solPath})`);
  else {
    const sp = checkSolution(sol, lf.level);
    problems.push(...sp.map((p) => `solution: ${p}`));
    if (sp.length === 0) {
      for (const r of staleReasons(sol, lf.level)) notes.push(`note: solution: ${r}; run \`level.ts run ${lf.stem} --write\``);
      if (!usesBaseline(sol)) notes.push('note: the solution wears non-baseline gear; every mandatory level must also be solvable with the baseline (APP-TEST-03)');
    }
  }
  return { problems, notes };
}

function cmdValidate(args: Args): number {
  const target = need(args, 'a level (or "all")');
  const all = listLevelFiles().map((f) => loadLevelFile(resolve(LEVEL_DIR, f)));
  const campaign = all.filter((l) => isCampaignFile(l.file));
  const targets = target === 'all' ? all : [loadLevelFile(findLevelPath(target))];
  let bad = 0;
  for (const lf of targets) {
    const { problems, notes } = validateOne(lf, campaign);
    if (problems.length) bad++;
    print(`${lf.file}: ${problems.length ? `${problems.length} PROBLEM(S)` : 'OK'}`);
    for (const p of problems) print(`  - ${p}`);
    for (const n of notes) print(`  ${n}`);
  }
  if (target === 'all') print(`\n${targets.length} level file(s), ${bad} with problems.`);
  return bad ? 1 : 0;
}

// ───────────────────────────── show ─────────────────────────────

function cmdShow(args: Args): number {
  const lf = loadLevelFile(findLevelPath(need(args, 'a level')));
  const sol = loadSolution(solutionPathFor(lf.path));
  print(showLines(lf.level, sol));
  if (args.flags.has('raw')) {
    print('\nMap rows as authored:');
    print(lf.level.map.map((row) => `  ${JSON.stringify(row)}`));
  }
  print('\nLegend:');
  print(LEGEND.map((l) => `  ${l}`));
  const problems = validateLevel(lf.level).filter(isProblem);
  if (problems.length) print(`\n${problems.length} validation problem(s); run \`level.ts validate ${lf.stem}\`.`);
  return 0;
}

// ───────────────────────────── run ─────────────────────────────

function tapeIndexOf(letter: string): number {
  const i = TAPE_NAMES.indexOf(letter.toUpperCase());
  if (i < 0) throw new UsageError(`--trace wants a tape letter A, B, C or D (got "${letter}")`);
  return i;
}

function cmdRun(args: Args): number {
  const lf = loadLevelFile(findLevelPath(need(args, 'a level')));
  requireValid(lf);
  const level = lf.level;
  const solPath = solutionPathFor(lf.path);
  const sol = requireSolution(lf);
  const write = args.flags.has('write');
  const upto = numberFlag(args, 'upto');
  const verbose = args.flags.has('verbose');
  const full = args.flags.has('full');
  if (write && (upto !== undefined || args.flags.has('loadout'))) throw new UsageError('--write stores the whole solution as written: drop --upto / --loadout');
  if (upto !== undefined && !(Number.isInteger(upto) && upto >= 1)) throw new UsageError('--upto wants a whole number of takes, 1 or more');
  const loadout = loadoutFor(args, sol);

  const run = runSolution(level, sol, { upto, loadout });
  print(`${level.id} "${level.name}": ${level.objective.text}`);
  print(`Loadout: ${loadoutText(loadout)}.   Horizon: master beat ${level.horizonBars * BEATS_PER_BAR}.   Beats below are master beats, counted from 0.`);

  let before: Resolution | null = null;
  for (let k = 0; k < run.takesRecorded; k++) {
    const take = sol.takes[k];
    const names = run.tapes.slice(0, k + 1).map((t) => TAPE_NAMES[t.index]).join(' + ');
    print('');
    print(takeTitle(k + 1, take));
    print(' Plan as played:');
    print(stepLines(level, take, run.logs[k]));
    const res = k === run.takesRecorded - 1 ? run.resolution : resolvePrefix(level, loadout, run.tapes, k + 1);
    if (k === 0 || full) {
      print(` Combined run of tape${k ? 's' : ''} ${names}:`);
      const lines = eventLines(level, res.events, verbose);
      print(lines.length ? lines : ['   (nothing happened)']);
    } else {
      print(` What this take changed in the combined run (${names}):   + new   - no longer happens`);
      const lines = eventDiffLines(level, before?.events ?? [], res.events, verbose);
      print(lines.length ? lines : ['   (nothing changed)']);
    }
    print(` After take ${k + 1}: ${res.outcome.win ? 'WIN' : 'not won yet'}. ${res.outcome.notes[0] ?? ''}`);
    before = res;
  }

  print('');
  const used = run.tapes.map((t) => TAPE_NAMES[t.index]).join(' + ');
  if (run.takesRecorded > 1 && !full) {
    print(`FINAL combined run (${used}), every event:`);
    print(eventLines(level, run.resolution.events, verbose));
    print('');
  }
  print(`Tapes in the final run:`);
  print(tapeLines(level, run.tapes));

  const trace = args.flags.get('trace');
  if (trace !== undefined) {
    const t = tapeIndexOf(trace);
    if (!run.tapes.some((x) => x.index === t)) throw new UsageError(`--trace ${trace.toUpperCase()}: that tape was not recorded in this run`);
    print('');
    print(`Trace of tape ${TAPE_NAMES[t]} in the final combined run:`);
    print(traceLines(level, run.resolution, t, numberFlag(args, 'every') ?? 1));
  }

  print('');
  print(outcomeLines(run.outcome));
  if (run.warnings.length) {
    print('');
    print('Warnings:');
    print(run.warnings.map((w) => `  ! ${w}`));
  }

  if (upto !== undefined && upto < sol.takes.length) print(`\n(Stopped after ${run.takesRecorded} of ${sol.takes.length} takes because of --upto.)`);
  if (write) {
    print('');
    if (!run.outcome.win) {
      print('NOT WRITTEN: the solution does not win. Fix the plan first.');
      return 1;
    }
    if (run.takesRecorded < sol.takes.length) {
      print(`NOT WRITTEN: the run wins after take ${run.takesRecorded}, so the later takes are never recorded. Delete them (or make them matter) first.`);
      return 1;
    }
    const next = compiledSolution(level, sol, run);
    const bad = verifyGenerated(level, next);
    if (bad.length) {
      print('NOT WRITTEN: the recorded performance does not replay identically:');
      print(bad.map((b) => `  - ${b}`));
      return 1;
    }
    saveSolution(solPath, next);
    const ticks = next.generated!.ticks.join(' + ');
    print(`Wrote ${solPath}`);
    print(`  inputs for ${next.takes.length} take(s) (${ticks} local ticks), ${next.generated!.tapes.length} tape(s), the expected outcome and ${next.generated!.timeline.length} timeline events.`);
    print('  Verified: the stored inputs replay to the same tapes and outcome, and the stored tapes resolve to the same outcome.');
  } else if (run.outcome.win && upto === undefined && !args.flags.has('loadout')) {
    const stale = staleReasons(sol, level);
    if (stale.length) print(`\nNot stored yet (${stale.join('; ')}). Run again with --write to store it.`);
  }
  return run.outcome.win ? 0 : 1;
}

// ───────────────────────────── ascii-at ─────────────────────────────

function cmdAsciiAt(args: Args): number {
  const lf = loadLevelFile(findLevelPath(need(args, 'a level')));
  requireValid(lf);
  const level = lf.level;
  const beat = numberFlag(args, 'beat');
  if (beat === undefined) throw new UsageError('ascii-at needs --beat N (a master beat)');
  const to = numberFlag(args, 'to') ?? beat;
  const every = numberFlag(args, 'every') ?? 1;
  if (!(every > 0)) throw new UsageError('--every must be more than 0');
  const upto = numberFlag(args, 'upto');
  const sol = requireSolution(lf);
  const loadout = loadoutFor(args, sol);
  let tapes;
  let resolution;
  if (args.flags.has('stored')) {
    if (!sol.generated) throw new Error('the solution has no stored tapes yet; run `level.ts run <level> --write` first');
    tapes = sol.generated.tapes.map(deserializeTape).slice(0, upto ?? undefined);
    resolution = upto === undefined ? replayStoredTapes(level, sol, loadout) : resolvePrefix(level, loadout, tapes, tapes.length);
  } else {
    const run = runSolution(level, sol, { upto, loadout });
    tapes = run.tapes;
    resolution = run.resolution;
  }
  const horizon = level.horizonBars * BEATS_PER_BAR;
  print(`${level.id}: combined run of tape${tapes.length > 1 ? 's' : ''} ${tapes.map((t) => TAPE_NAMES[t.index]).join(' + ')}${args.flags.has('stored') ? ' (stored tapes)' : ''}; horizon is beat ${horizon}; result ${resolution.outcome.win ? 'WIN' : 'FAIL'}`);
  for (let b = beat; b <= to + 1e-9; b += every) {
    if (b < 0 || b > horizon + 1e-9) {
      print(`\n(beat ${b} is outside the run: 0..${horizon})`);
      continue;
    }
    print('');
    print(renderFrame(level, frameAtBeat(level, resolution, b), tapes));
  }
  print('');
  print(LEGEND.map((l) => `  ${l}`));
  return 0;
}

// ───────────────────────────── probe ─────────────────────────────

function cmdProbe(args: Args): number {
  const target = args.positional[1];
  const level: LevelDef | null = target ? loadLevelFile(findLevelPath(target)).level : null;
  const speed = numberFlag(args, 'speed');
  if (speed !== undefined && ![0.5, 1, 2, 4].includes(speed)) throw new UsageError('--speed must be 0.5, 1, 2 or 4');
  print(probeLines(level, loadoutFor(args, null), { beats: numberFlag(args, 'beats'), speed: speed as TapeSpeed | undefined }));
  return 0;
}

// ───────────────────────────── mutate ─────────────────────────────

function cmdMutate(args: Args): number {
  const lf = loadLevelFile(findLevelPath(need(args, 'a level')));
  requireValid(lf);
  const sol = requireSolution(lf);
  const loadout = loadoutFor(args, sol);
  const base = runSolution(lf.level, sol, { loadout });
  print(`${lf.level.id}: as written the solution ${base.outcome.win ? 'WINS' : 'FAILS'} (${base.takesRecorded} take(s), loadout ${loadoutText(loadout)}).`);
  if (!base.outcome.win) {
    print(outcomeLines(base.outcome));
    print('Fix the solution before testing how robust it is.');
    return 1;
  }
  const variants = mutationVariants(sol.takes.length, args.flags.has('quick') ? 'quick' : 'full');
  const results = runVariants(lf.level, sol, variants, loadout);
  const width = Math.max(...results.map((r) => r.label.length));
  let failed = 0;
  for (const r of results) {
    if (!r.win) failed++;
    print(`  ${r.label.padEnd(width)}  ${r.win ? 'wins' : 'FAILS'}`);
    if (!r.win) for (const n of r.notes) print(`  ${' '.repeat(width)}    - ${n}`);
  }
  print('');
  if (failed) {
    print(`${failed} of ${results.length} variants FAIL: the solution sits on a knife-edge and will not survive the Godot port.`);
    print('Give the failing moment slack: wait for a condition instead of a tick, strike a beat later, stand further inside reach.');
  } else {
    print(`All ${results.length} variants win: the solution has slack in both timing and position.`);
  }
  return failed ? 1 : 0;
}

// ───────────────────────────── index ─────────────────────────────

function cmdIndex(args: Args): number {
  const all = listLevelFiles().map((f) => loadLevelFile(resolve(LEVEL_DIR, f)));
  const campaign = all.filter((l) => isCampaignFile(l.file)).sort((a, b) => a.level.index - b.level.index || (a.file < b.file ? -1 : 1));
  const extra = all.filter((l) => !isCampaignFile(l.file));
  const state = (lf: LevelFile): string => {
    const sol = loadSolution(solutionPathFor(lf.path));
    if (!sol) return 'no solution';
    if (checkSolution(sol, lf.level).length) return 'solution has problems';
    if (!sol.generated) return 'solution not compiled';
    if (staleReasons(sol, lf.level).length) return 'solution STALE (re-run with --write)';
    return sol.generated.outcome.win ? `solved, ${sol.generated.takesRecorded} take(s)` : 'stored solution FAILS';
  };
  print(`Campaign (${campaign.length} level${campaign.length === 1 ? '' : 's'}):`);
  if (campaign.length === 0) print('  (none yet: the game falls back to the sandbox)');
  for (const lf of campaign) print(`  ${String(lf.level.index).padStart(2, '0')}  ${lf.stem.padEnd(28)} "${lf.level.name}"  ${lf.level.maxTapes} tape(s), ${lf.level.speeds.join('/')}x  [${state(lf)}]`);
  print('Off the path:');
  for (const lf of extra) print(`      ${lf.stem.padEnd(28)} "${lf.level.name}"  [${state(lf)}]`);
  const problems = campaignOrderProblems(campaign);
  for (const lf of all) for (const p of levelFileProblems(lf.file, lf.level)) problems.push(`${lf.file}: ${p}`);
  if (problems.length) {
    print('\nProblems:');
    print(problems.map((p) => `  - ${p}`));
  }
  const want = { version: 1, levels: campaign.map((l) => l.stem), extra: extra.map((l) => l.stem) };
  const have = loadIndex();
  const current = have !== null && JSON.stringify(have.levels) === JSON.stringify(want.levels) && JSON.stringify(have.extra) === JSON.stringify(want.extra);
  if (args.flags.has('write')) {
    if (problems.length) {
      print(`\nNOT WRITTEN: fix the problems above first.`);
      return 1;
    }
    // Until the first campaign file exists the game runs on the sandbox; keep the index it shipped with.
    if (campaign.length === 0) {
      print(`\nNOT WRITTEN: there are no campaign files yet, ${INDEX_PATH} stays as it is.`);
      return 0;
    }
    saveIndex(want);
    print(`\nWrote ${INDEX_PATH}`);
  } else if (!current && campaign.length > 0) {
    print(`\ndata/levels/index.json is out of date (it lists: ${have ? have.levels.join(', ') || 'nothing' : 'missing'}). Run \`level.ts index --write\`.`);
  } else if (existsSync(INDEX_PATH)) {
    print('\ndata/levels/index.json is up to date.');
  }
  return problems.length ? 1 : 0;
}

// ───────────────────────────── main ─────────────────────────────

function main(argv: string[]): number {
  if (argv.includes('--help') || argv.includes('-h')) {
    print(USAGE);
    return 0;
  }
  const args = parseArgs(argv);
  const command = args.positional[0];
  switch (command) {
    case undefined:
    case 'help':
      print(USAGE);
      return command === undefined ? 1 : 0;
    case 'validate':
      return cmdValidate(args);
    case 'show':
      return cmdShow(args);
    case 'run':
      return cmdRun(args);
    case 'ascii-at':
      return cmdAsciiAt(args);
    case 'probe':
      return cmdProbe(args);
    case 'mutate':
      return cmdMutate(args);
    case 'index':
      return cmdIndex(args);
    default:
      throw new UsageError(`unknown command "${command}"`);
  }
}

try {
  process.exitCode = main(process.argv.slice(2));
} catch (err) {
  if (err instanceof UsageError) {
    console.error(`${err.message}\n\nRun \`npx vite-node scripts/level.ts help\` for the commands.`);
    process.exitCode = 2;
  } else {
    console.error(`error: ${(err as Error).message}`);
    process.exitCode = 1;
  }
}
