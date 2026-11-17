/**
 * The JSON campaign is real: every data/levels/<NN>-<slug>.json validates, has a compiled solution,
 * and that solution wins — replayed input by input through the real Session with the baseline
 * loadout (APP-TEST-03), replayed from its stored tapes, and nudged a tick either way.
 *
 * The same checks run on the sandbox's worked example (data/levels/solutions/sandbox.json), which
 * is the file designers copy.
 *
 * When this fails for your level, the message says what to run. The usual fix is
 *   cd prototype && npx vite-node scripts/level.ts run <level> --write
 */
import { describe, expect, it } from 'vitest';
import { GEAR, LEVELS, SANDBOX } from '../../src/content/index';
import { CAMPAIGN_FILES, CAMPAIGN_LEVELS, FIRST_CAMPAIGN_INDEX, campaignOrderProblems, levelFileProblems } from '../../src/content/levelFiles';
import { isProblem, validateLevel } from '../../src/content/validate';
import { serializeTape } from '../../src/core/tape';
import type { LevelDef } from '../../src/core/types';
import { mutationVariants, replayStoredInputs, replayStoredTapes, runSolution, runVariants, sameOutcome, timelineOf } from '../../scripts/lib/run';
import { baselineLoadout, checkSolution, staleReasons, usesBaseline, type SolutionFile } from '../../scripts/lib/solution';

// Raw text, parsed per level, so one malformed file fails its own test instead of the whole suite.
const levelTexts = import.meta.glob('../../../data/levels/*.json', { eager: true, query: '?raw', import: 'default' }) as Record<string, string>;
const solutionTexts = import.meta.glob('../../../data/levels/solutions/*.json', { eager: true, query: '?raw', import: 'default' }) as Record<string, string>;

function fileName(path: string): string {
  return path.slice(path.lastIndexOf('/') + 1);
}

const levelFiles = Object.keys(levelTexts)
  .map(fileName)
  .filter((f) => f !== 'index.json')
  .sort();
const campaignFiles = levelFiles.filter((f) => f !== 'sandbox.json');

function textOf(table: Record<string, string>, file: string): string | undefined {
  const key = Object.keys(table).find((k) => fileName(k) === file);
  return key === undefined ? undefined : table[key];
}

function parse<T>(what: string, text: string): T {
  try {
    return JSON.parse(text.replace(/^﻿/, '')) as T;
  } catch (err) {
    throw new Error(`${what} is not valid JSON: ${(err as Error).message}`);
  }
}

function loadLevel(file: string): LevelDef {
  return parse<LevelDef>(`data/levels/${file}`, textOf(levelTexts, file)!);
}

function loadSolution(file: string): SolutionFile {
  const text = textOf(solutionTexts, file);
  if (text === undefined) throw new Error(`data/levels/solutions/${file} does not exist: every level needs its designer's solution`);
  return parse<SolutionFile>(`data/levels/solutions/${file}`, text);
}

/** The checks every authored level has to pass. */
function levelSuite(file: string): void {
  const stem = file.replace(/\.json$/, '');
  const fix = `cd prototype && npx vite-node scripts/level.ts run ${stem} --write`;

  it('is a valid level, named after its id and campaign index', () => {
    const level = loadLevel(file);
    expect(validateLevel(level).filter(isProblem), `level.ts validate ${stem}`).toEqual([]);
    expect(levelFileProblems(file, level)).toEqual([]);
    for (const id of level.loot) expect(GEAR[id], `loot "${id}" is not a gear id`).toBeDefined();
  });

  it('has a well-formed solution, compiled against the current level and plan', () => {
    const level = loadLevel(file);
    const sol = loadSolution(file);
    expect(checkSolution(sol, level)).toEqual([]);
    expect(staleReasons(sol, level), `re-compile it: ${fix}`).toEqual([]);
    expect(usesBaseline(sol), 'the stored solution must wear the baseline loadout (APP-TEST-03)').toBe(true);
    expect(sol.generated!.outcome.win, 'the stored expected outcome must be a win').toBe(true);
  });

  it('wins when its stored inputs are replayed through the bot with the baseline loadout (APP-TEST-03)', () => {
    const level = loadLevel(file);
    const sol = loadSolution(file);
    const replay = replayStoredInputs(level, sol, baselineLoadout());
    expect(replay.outcome.notes, fix).toEqual(sol.generated!.outcome.notes);
    expect(replay.outcome.win).toBe(true);
    // The recorded performance is reproduced bit for bit, so the stored tapes are the truth.
    expect(replay.tapes.map(serializeTape)).toEqual(sol.generated!.tapes);
  });

  it('gives the same outcome when its stored tapes are resolved under playback rules', () => {
    const level = loadLevel(file);
    const sol = loadSolution(file);
    const res = replayStoredTapes(level, sol, baselineLoadout());
    expect(sameOutcome(res.outcome, sol.generated!.outcome), res.outcome.notes.join(' ')).toBe(true);
    expect(res.outcome.win).toBe(true);
    expect(timelineOf(level, res.events)).toEqual(sol.generated!.timeline);
  });

  it('still wins with every take one local tick late or early', () => {
    const level = loadLevel(file);
    const sol = loadSolution(file);
    // The plan as written must itself reproduce the stored result.
    expect(runSolution(level, sol, { loadout: baselineLoadout() }).outcome.win, fix).toBe(true);
    const results = runVariants(level, sol, mutationVariants(sol.takes.length, 'quick'), baselineLoadout());
    const failed = results.filter((r) => !r.win).map((r) => `${r.label}: ${r.notes.join(' ')}`);
    expect(failed, `knife-edge solution; see \`npx vite-node scripts/level.ts mutate ${stem}\``).toEqual([]);
  });
}

describe('campaign levels (data/levels/<NN>-<slug>.json)', () => {
  it('finds the level files', () => {
    expect(levelFiles).toContain('sandbox.json');
    for (const f of campaignFiles) expect(f, 'campaign files are <NN>-<slug>.json; only sandbox.json may go without a number').toMatch(/^\d\d-[a-z0-9]+(-[a-z0-9]+)*\.json$/);
  });

  it('numbers the campaign 1, 2, 3 … (like the file names) without gaps or duplicates', () => {
    const files = campaignFiles.map((file) => ({ file, level: loadLevel(file) }));
    expect(campaignOrderProblems(files)).toEqual([]);
  });

  it('is what the content module loads, in index order, with the sandbox kept off the path', () => {
    expect(CAMPAIGN_FILES.map((f) => f.file).sort()).toEqual(campaignFiles);
    expect(CAMPAIGN_LEVELS.map((l) => l.index)).toEqual(CAMPAIGN_LEVELS.map((_, i) => i + FIRST_CAMPAIGN_INDEX));
    for (const f of CAMPAIGN_FILES) expect(f.level).toEqual(loadLevel(f.file));
    if (campaignFiles.length > 0) {
      expect(LEVELS.map((l) => l.id)).toEqual(CAMPAIGN_LEVELS.map((l) => l.id));
      expect(LEVELS.some((l) => l.id === SANDBOX.id)).toBe(false);
    } else {
      // No campaign file yet: the game still has something to play.
      expect(LEVELS).toEqual([SANDBOX]);
    }
    expect(SANDBOX.id).toBe('sandbox');
  });

  for (const file of campaignFiles) describe(file, () => levelSuite(file));
});

describe('worked example: the sandbox and its solution', () => {
  it('data/levels/sandbox.json is the sandbox the game ships', () => {
    expect(loadLevel('sandbox.json')).toEqual(JSON.parse(JSON.stringify(SANDBOX)));
  });

  levelSuite('sandbox.json');
});
