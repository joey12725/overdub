/**
 * Export the prototype's content as plain JSON for the Godot build (docs/GODOT-PORT.md "Data").
 *
 *   cd prototype && npx vite-node scripts/export-data.ts
 *
 * Writes (relative to the repo root):
 *   data/gear.json            { "version": 1, "items": GearItem[] (catalogue order), "baseLoadout": Loadout }
 *   data/levels/<id>.json     one LevelDef per file, exactly the TypeScript shape
 *   data/levels/index.json    { "version": 1, "levels": ["<id>", ...] } in campaign order (LEVELS),
 *                             plus "sandbox" listed separately under "extra" when it is not on the path
 *
 * The JSON is the TypeScript objects verbatim (JSON.stringify drops undefined optionals), so the
 * Godot loaders (content/data.gd) and the prototype agree field for field. Catalogue order matters
 * (UIs list items in insertion order), so gear is an array, not an object keyed by id.
 */
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { BASE_LOADOUT, GEAR, LEVELS, SANDBOX } from '../src/content/index';
import type { LevelDef } from '../src/core/types';

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, '..', '..');
const dataDir = resolve(repoRoot, 'data');
const levelDir = resolve(dataDir, 'levels');

function write(path: string, value: unknown): void {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, JSON.stringify(value, null, 2) + '\n', 'utf8');
  console.log(`wrote ${path}`);
}

function checkFinite(where: string, value: unknown): void {
  // JSON.stringify silently turns NaN / Infinity into null; refuse to export such data.
  if (typeof value === 'number' && !Number.isFinite(value)) throw new Error(`${where}: non-finite number`);
  if (Array.isArray(value)) value.forEach((v, i) => checkFinite(`${where}[${i}]`, v));
  else if (value && typeof value === 'object') {
    for (const [k, v] of Object.entries(value)) checkFinite(`${where}.${k}`, v);
  }
}

const items = Object.values(GEAR);
for (const [key, it] of Object.entries(GEAR)) {
  if (key !== it.id) throw new Error(`gear key ${key} does not match item id ${it.id}`);
}
const gear = { version: 1, items, baseLoadout: BASE_LOADOUT };
checkFinite('gear', gear);
write(resolve(dataDir, 'gear.json'), gear);

const all: LevelDef[] = [...LEVELS];
if (!all.some((l) => l.id === SANDBOX.id)) all.push(SANDBOX);
for (const level of all) {
  checkFinite(`level ${level.id}`, level);
  write(resolve(levelDir, `${level.id}.json`), level);
}
const onPath = LEVELS.map((l) => l.id);
const extra = all.map((l) => l.id).filter((id) => !onPath.includes(id));
write(resolve(levelDir, 'index.json'), { version: 1, levels: onPath, extra });
