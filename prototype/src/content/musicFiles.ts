/**
 * The composer's files: data/music/<level id>.json (and menu.json), docs/MUSIC.md "Data format".
 *
 * Each file's `music` block is the level's `music` (copied in by art/music/merge.py and kept equal by
 * tests/content/music.test.ts); the rest is data for the audio layer, the same fields the Godot build
 * reads through ContentData.load_music_file / CampaignData.music_file (content/data.gd):
 *   stateMaps  OPEN-22 generative-parameter changes per actor state (dead, desynced, reversing, stopped)
 *   sfx        MUSIC-05 pitch policy per event class, the palette, UI pitches, OPEN-23 latency
 *   layers     per cassette: role, formula, equation, purpose
 *   bed        menu only: which cassettes play, at which speed
 */
import type { LevelMusicDef } from '../core/types';

export const MUSIC_SCHEMA = 'overdub-music/1';

export interface MusicFile {
  schema: string;
  id: string;
  /** Tempo the piece was composed at; equals the level's bpm (the level file wins if they differ). */
  bpm: number;
  title?: string;
  key?: string;
  music: LevelMusicDef;
  stateMaps?: Record<string, unknown>;
  sfx?: { palette?: string; pitchRule?: string; latency?: unknown; classes?: Record<string, unknown>; ui?: unknown };
  layers?: { cassette: number; role: string; formula: string; formulaName?: string; equation?: string; about?: string }[];
  bed?: { tracks: { present: boolean; speed: number }[] };
}

const modules = import.meta.glob('../../../data/music/*.json', { eager: true, import: 'default' }) as Record<string, unknown>;

/** Every composer file by id (file name without .json). */
export const MUSIC_FILES: Readonly<Record<string, MusicFile>> = Object.fromEntries(
  Object.entries(modules)
    .map(([path, data]) => [path.slice(Math.max(path.lastIndexOf('/'), path.lastIndexOf('\\')) + 1).replace(/\.json$/, ''), data as MusicFile] as const)
    .filter(([, f]) => f !== null && typeof f === 'object' && f.schema === MUSIC_SCHEMA),
);

/** The composer's file for a level id (or 'menu'), or undefined. */
export function musicFileFor(id: string): MusicFile | undefined {
  return MUSIC_FILES[id];
}
