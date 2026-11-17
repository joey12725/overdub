import type { LevelDef, TrackMusicDef } from '../../src/core/types';

/** The parts of a LevelDef the audio module reads, with the rest filled with inert values. */
export function musicLevel(
  tracks: [TrackMusicDef, TrackMusicDef, TrackMusicDef, TrackMusicDef],
  opts: { root?: number; scale?: string; progression?: number[]; chordBars?: number; bpm?: number } = {},
): LevelDef {
  return {
    id: 'audio-test',
    index: 0,
    name: 'Audio test',
    tagline: '',
    theme: 'upper',
    bpm: opts.bpm ?? 120,
    bars: 4,
    horizonBars: 8,
    maxTapes: 4,
    speeds: [0.5, 1, 2, 4],
    endModes: ['stop', 'repeat', 'reverse'],
    map: ['...'],
    start: { x: 1, y: 0 },
    entities: [],
    objective: { type: 'reach', text: 'Reach the exit' },
    music: {
      root: opts.root ?? 9,
      scale: opts.scale ?? 'Minor',
      progression: opts.progression ?? [0, 5, 2, 6],
      chordBars: opts.chordBars ?? 1,
      tracks,
    },
    loot: [],
    briefing: ['test'],
  };
}

export const STANDARD_TRACKS: [TrackMusicDef, TrackMusicDef, TrackMusicDef, TrackMusicDef] = [
  { role: 'melody', formula: 'fibonacci', params: { m: 7 } },
  { role: 'bass', formula: 'sine' },
  { role: 'drums', formula: 'thue', genre: 'Lo-fi 80' },
  { role: 'chord', formula: 'rose', params: { k: 3 } },
];

export const standardLevel = (opts?: Parameters<typeof musicLevel>[1]) => musicLevel(STANDARD_TRACKS, opts);
