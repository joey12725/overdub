/**
 * File access for the level CLI (Node only; the tests load the same files through Vite instead).
 *
 *   data/levels/<NN>-<slug>.json             a campaign level
 *   data/levels/sandbox.json                 the development sandbox (not on the campaign path)
 *   data/levels/solutions/<same name>.json   the designer's solution for that level
 */
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { basename, dirname, isAbsolute, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { LevelDef } from '../../src/core/types';
import { formatSolution, type SolutionFile } from './solution';

const here = dirname(fileURLToPath(import.meta.url));
export const REPO_ROOT = resolve(here, '..', '..', '..');
export const LEVEL_DIR = resolve(REPO_ROOT, 'data', 'levels');
export const SOLUTION_DIR = resolve(LEVEL_DIR, 'solutions');
export const INDEX_PATH = resolve(LEVEL_DIR, 'index.json');

export interface LevelFile {
  /** Absolute path. */
  path: string;
  /** File name, e.g. `03-crossfire.json`. */
  file: string;
  /** Name without `.json`. */
  stem: string;
  level: LevelDef;
}

function readJson(path: string): unknown {
  const text = readFileSync(path, 'utf8').replace(/^﻿/, '');
  try {
    return JSON.parse(text);
  } catch (err) {
    throw new Error(`${path}: not valid JSON (${(err as Error).message})`);
  }
}

/** Names of every level file in data/levels (index.json excluded), sorted. */
export function listLevelFiles(): string[] {
  return readdirSync(LEVEL_DIR)
    .filter((f) => f.endsWith('.json') && f !== 'index.json')
    .sort();
}

export function isCampaignFile(file: string): boolean {
  return /^\d+-/.test(basename(file));
}

/**
 * Find a level file from what was typed: a path, a file name in data/levels, a name without
 * `.json`, or just the campaign number ("03").
 */
export function findLevelPath(arg: string): string {
  const direct = isAbsolute(arg) ? arg : resolve(process.cwd(), arg);
  if (existsSync(direct) && direct.endsWith('.json')) return direct;
  for (const name of [arg, `${arg}.json`]) {
    const p = resolve(LEVEL_DIR, name);
    if (existsSync(p) && p.endsWith('.json')) return p;
  }
  const hits = listLevelFiles().filter((f) => f.startsWith(`${arg}-`) || f.startsWith(`${arg.padStart(2, '0')}-`));
  if (hits.length === 1) return resolve(LEVEL_DIR, hits[0]);
  if (hits.length > 1) throw new Error(`"${arg}" matches several level files: ${hits.join(', ')}`);
  throw new Error(`no level file for "${arg}" (looked for a path, ${LEVEL_DIR}/${arg}.json and ${arg}-*.json). Levels: ${listLevelFiles().join(', ')}`);
}

export function loadLevelFile(path: string): LevelFile {
  const level = readJson(path) as LevelDef;
  if (typeof level !== 'object' || level === null || Array.isArray(level)) throw new Error(`${path}: a level file must hold one JSON object`);
  const file = basename(path);
  return { path, file, stem: file.replace(/\.json$/, ''), level };
}

/** The solution that belongs to a level file: `solutions/<same file name>` next to it. */
export function solutionPathFor(levelPath: string): string {
  return resolve(dirname(levelPath), 'solutions', basename(levelPath));
}

export function loadSolution(path: string): SolutionFile | null {
  if (!existsSync(path)) return null;
  return readJson(path) as SolutionFile;
}

export function saveSolution(path: string, sol: SolutionFile): void {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, formatSolution(sol), 'utf8');
}

export interface LevelIndex {
  version: number;
  levels: string[];
  extra: string[];
}

/** data/levels/index.json as the Godot loader reads it, or null when missing. */
export function loadIndex(): LevelIndex | null {
  if (!existsSync(INDEX_PATH)) return null;
  const raw = readJson(INDEX_PATH) as Partial<LevelIndex>;
  return { version: raw.version ?? 1, levels: raw.levels ?? [], extra: raw.extra ?? [] };
}

export function saveIndex(index: LevelIndex): void {
  writeFileSync(INDEX_PATH, JSON.stringify(index, null, 2) + '\n', 'utf8');
}
