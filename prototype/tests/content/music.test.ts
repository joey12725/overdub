/**
 * The composer's music reaches the levels: every campaign level's `music` block is the one in
 * data/music/<id>.json (merged by art/music/merge.py), at the level's own tempo, and the extras the
 * audio layer reads (state maps, sfx pitch sets) are present. The Godot build checks the same thing
 * through ContentData.load_music_file (tests/content/test_music_files.gd).
 */
import { describe, expect, it } from 'vitest';
import { LEVELS } from '../../src/content/index';
import { MUSIC_FILES, MUSIC_SCHEMA, musicFileFor } from '../../src/content/musicFiles';

describe('composer music files (data/music)', () => {
  it('has a file for every campaign level and the menu', () => {
    for (const l of LEVELS) expect(musicFileFor(l.id), `data/music/${l.id}.json`).toBeDefined();
    expect(musicFileFor('menu')?.bed?.tracks).toHaveLength(4);
  });

  for (const l of LEVELS) {
    it(`${l.id}: the level plays the composer's music at the level's tempo`, () => {
      const f = musicFileFor(l.id)!;
      expect(f.schema).toBe(MUSIC_SCHEMA);
      expect(f.id).toBe(l.id);
      expect(f.bpm, 'bpm belongs to the level; retune the piece (docs/MUSIC.md)').toBe(l.bpm);
      expect(l.music, 'run python -I art/music/merge.py --write').toEqual(f.music);
      expect(Object.keys(f.stateMaps ?? {})).toEqual(expect.arrayContaining(['order', 'dead', 'desynced', 'reversing', 'stopped']));
      expect(Object.keys(f.sfx?.classes ?? {}).length).toBeGreaterThan(0);
      expect(f.layers?.map((x) => x.role)).toEqual(l.music.tracks.map((t) => t.role));
    });
  }

  it('only lists files of the music schema', () => {
    for (const [id, f] of Object.entries(MUSIC_FILES)) expect(f.id, id).toBe(id);
  });
});
