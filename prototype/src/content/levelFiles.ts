/**
 * The JSON campaign: every `data/levels/<NN>-<slug>.json` at the repo root, loaded at build time
 * and ordered by `index` (LEVEL-08). The same files are read by the Godot build (content/data.gd),
 * so a level is authored once, as plain data. Format and naming rules: data/levels/README.md.
 *
 * Only files whose name starts with a two-digit campaign index are on the path; `sandbox.json` (and
 * anything else without the prefix) is deliberately left out, so the sandbox stays available for
 * development without becoming a campaign level.
 *
 * This module only loads and orders. It never throws on a badly named or invalid file: the level
 * tools (`prototype/scripts/level.ts validate`) and tests/levels/campaign.test.ts report those.
 */
import type { LevelDef } from '../core/types';

export interface CampaignFile {
  /** File name without directory, e.g. `03-crossfire.json`. */
  file: string;
  /** File name without extension, e.g. `03-crossfire`. Must equal the level's `id`. */
  stem: string;
  level: LevelDef;
}

const modules = import.meta.glob('../../../data/levels/[0-9][0-9]-*.json', { eager: true, import: 'default' }) as Record<string, unknown>;

function fileOf(path: string): string {
  const cut = Math.max(path.lastIndexOf('/'), path.lastIndexOf('\\'));
  return path.slice(cut + 1);
}

/** Campaign level files in path order: by `index`, ties (an authoring error) broken by file name. */
export const CAMPAIGN_FILES: readonly CampaignFile[] = Object.entries(modules)
  .map(([path, level]): CampaignFile => {
    const file = fileOf(path);
    return { file, stem: file.replace(/\.json$/, ''), level: level as LevelDef };
  })
  .sort((a, b) => {
    const ia = Number.isFinite(a.level?.index) ? a.level.index : Number.MAX_SAFE_INTEGER;
    const ib = Number.isFinite(b.level?.index) ? b.level.index : Number.MAX_SAFE_INTEGER;
    return ia - ib || (a.file < b.file ? -1 : a.file > b.file ? 1 : 0);
  });

/** The campaign path: LevelDefs in index order. Empty until the first campaign file exists. */
export const CAMPAIGN_LEVELS: LevelDef[] = CAMPAIGN_FILES.map((f) => f.level);

/**
 * Naming problems of one level file (empty = fine). Rules (data/levels/README.md):
 *   - campaign files are `<NN>-<slug>.json`: two digits, a dash, a lower-case slug;
 *   - `index` inside equals NN;
 *   - `id` inside equals the file name without `.json` (the Godot loader opens `<id>.json`).
 * A file without the numeric prefix (the sandbox) only has to satisfy the id rule.
 */
export function levelFileProblems(file: string, level: Pick<LevelDef, 'id' | 'index'>): string[] {
  const out: string[] = [];
  const stem = fileOf(file).replace(/\.json$/, '');
  if (level.id !== stem) out.push(`id "${String(level.id)}" must equal the file name without .json ("${stem}")`);
  const m = /^(\d+)-(.*)$/.exec(stem);
  if (m) {
    if (m[1].length !== 2) out.push(`campaign prefix "${m[1]}" must be exactly two digits`);
    if (!/^[a-z0-9]+(-[a-z0-9]+)*$/.test(m[2])) out.push(`slug "${m[2]}" must be lower-case words joined by dashes (a-z, 0-9)`);
    if (level.index !== Number(m[1])) out.push(`index is ${String(level.index)} but the file name says ${Number(m[1])}`);
  }
  return out;
}

/** Index of the first campaign level: files are 01-…, 02-…; 0 is the off-path sandbox. */
export const FIRST_CAMPAIGN_INDEX = 1;

/** Problems with the campaign as a whole: indices must run 1, 2, 3 … with no gap or duplicate. */
export function campaignOrderProblems(files: readonly Pick<CampaignFile, 'file' | 'level'>[]): string[] {
  const out: string[] = [];
  const sorted = [...files].sort((a, b) => a.level.index - b.level.index || (a.file < b.file ? -1 : 1));
  sorted.forEach((f, position) => {
    const want = position + FIRST_CAMPAIGN_INDEX;
    if (f.level.index !== want) {
      const clash = sorted.find((o) => o !== f && o.level.index === f.level.index);
      out.push(
        clash
          ? `${f.file}: index ${f.level.index} is also used by ${clash.file}`
          : `${f.file}: index ${f.level.index} leaves a gap (expected ${want}; campaign indices run ${FIRST_CAMPAIGN_INDEX}..${sorted.length - 1 + FIRST_CAMPAIGN_INDEX})`,
      );
    }
  });
  return out;
}
