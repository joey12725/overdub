/**
 * Test helper: build a valid minimal LevelDef in a few lines.
 *
 *   const level = makeLevel({ map: ['#####', '#...#', '#####'], entities: [door] });
 *
 * Defaults: bpm 120 (30 local ticks per beat), 4 bars (480 local ticks = 8 local seconds),
 * horizon = bars / slowest offered speed, all speeds and end modes, a 12×10 walled open room,
 * start at the room's centre (or the first floor tile of a custom map), default music.
 */
import type { LevelDef, LevelMusicDef, MapRows, TapeSpeed } from '../../src/core/types';

/** A 12×10 room: walls around a floor of 10×8 tiles (interior x ∈ [1, 11), y ∈ [1, 9)). */
export const OPEN_ROOM: MapRows = [
  '############',
  '#..........#',
  '#..........#',
  '#..........#',
  '#..........#',
  '#..........#',
  '#..........#',
  '#..........#',
  '#..........#',
  '############',
];

export const DEFAULT_MUSIC: LevelMusicDef = {
  root: 9,
  scale: 'Minor',
  progression: [0, 5, 2, 6],
  chordBars: 1,
  tracks: [
    { role: 'bass', formula: 'triangular' },
    { role: 'drums', formula: 'ruler' },
    { role: 'melody', formula: 'recaman' },
    { role: 'chord', formula: 'squares' },
  ],
};

const FLOOR = new Set(['.', ':', ',', '~']);

/** Centre of the first floor tile scanning rows top to bottom, or of the map's middle tile. */
function defaultStart(map: MapRows): { x: number; y: number } {
  if (map === OPEN_ROOM) return { x: 6, y: 5 };
  for (let r = 0; r < map.length; r++) {
    for (let c = 0; c < map[r].length; c++) if (FLOOR.has(map[r][c])) return { x: c + 0.5, y: r + 0.5 };
  }
  return { x: (map[0]?.length ?? 1) / 2, y: map.length / 2 };
}

export function makeLevel(partial: Partial<LevelDef> = {}): LevelDef {
  const map = partial.map ?? OPEN_ROOM;
  const speeds: TapeSpeed[] = partial.speeds ?? [0.5, 1, 2, 4];
  const bars = partial.bars ?? 4;
  const slowest = Math.min(...speeds);
  return {
    id: 'test-level',
    index: 0,
    name: 'Test Level',
    tagline: 'A level built by a test.',
    theme: 'upper',
    bpm: 120,
    maxTapes: 4,
    endModes: ['stop', 'repeat', 'reverse'],
    entities: [],
    objective: { type: 'eliminate', text: 'Test objective' },
    music: DEFAULT_MUSIC,
    loot: [],
    briefing: [],
    startFacing: 0,
    ...partial,
    bars,
    horizonBars: partial.horizonBars ?? bars / slowest,
    speeds,
    map,
    start: partial.start ?? defaultStart(map),
  };
}
