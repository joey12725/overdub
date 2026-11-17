/**
 * Sandbox: a small, complete room where every core mechanic can be poked at before the campaign
 * exists. Not a teaching level; it offers every speed and end mode at once.
 *
 *          0         1
 *          01234567890123
 *     r0   ##############
 *     r1   #..S.#.......#      S  switch "lever"           (3.5, 1.5)
 *     r2   #....#..G,...#      G  grunt "g1"               (8.5, 2.5)
 *     r3   #....D.......#      D  door "gate", opened by the lever
 *     r4   #....#...=.T.#      T  turret "t1" behind a low barrier (11.5, 4.5)
 *     r5   #~~@.#...=...#      @  start                    (3.5, 5.5)
 *     r6   #~~..#LLLLLLL#      L  laser "beam", on unless the plate is held
 *     r7   #....B....G..#      B  breakable "cracked" (needs momentum 3.0), G grunt "g2" (10.5, 7.5)
 *     r8   #P...#,,.....#      P  plate "plate"            (1, 8)
 *     r9   ##############
 *
 * Two ways east: the switch-operated door (north) or the cracked wall (south; a 1x standing heavy
 * from the baseline blade is 1.8 momentum, so it takes a faster tape, a run-up or heavier gear). The
 * laser splits the east room, so one self holding the plate lets the others cross.
 */
import type { LevelDef } from '../../core/types';

export const SANDBOX: LevelDef = {
  id: 'sandbox',
  index: 0,
  name: 'Sandbox',
  tagline: 'A scrap room to try everything.',
  theme: 'upper',
  // 3600 / 120 = 30 local ticks per beat.
  bpm: 120,
  bars: 8,
  // bars / slowest offered speed (0.5x), the documented default horizon (ARCHITECTURE "One clock").
  horizonBars: 16,
  maxTapes: 4,
  speeds: [0.5, 1, 2, 4],
  endModes: ['stop', 'repeat', 'reverse'],
  map: [
    '##############',
    '#....#.......#',
    '#....#..,,...#',
    '#............#',
    '#....#...=...#',
    '#~~..#...=...#',
    '#~~..#.......#',
    '#............#',
    '#,...#,,.....#',
    '##############',
  ],
  start: { x: 3.5, y: 5.5 },
  startFacing: 0,
  entities: [
    { kind: 'switch', id: 'lever', x: 3.5, y: 1.5 },
    { kind: 'door', id: 'gate', cells: [{ c: 5, r: 3 }], openWhen: { sig: 'lever' } },
    { kind: 'breakable', id: 'cracked', c: 5, r: 7, threshold: 3 },
    { kind: 'plate', id: 'plate', c: 1, r: 8 },
    {
      kind: 'laser',
      id: 'beam',
      from: { x: 6.5, y: 6.5 },
      to: { x: 12.5, y: 6.5 },
      onWhen: { not: { sig: 'plate' } },
    },
    { kind: 'enemy', id: 'g1', type: 'grunt', x: 8.5, y: 2.5, facing: Math.PI },
    { kind: 'enemy', id: 'g2', type: 'grunt', x: 10.5, y: 7.5, facing: Math.PI },
    { kind: 'enemy', id: 't1', type: 'turret', x: 11.5, y: 4.5, facing: Math.PI, beat: { every: 2, offset: 1 } },
    { kind: 'decor', type: 'graffiti', x: 7.5, y: 0.6, variant: 'MOX' },
    { kind: 'decor', type: 'vines', x: 12.4, y: 8.4 },
    { kind: 'decor', type: 'vines', x: 1.2, y: 1.2 },
    { kind: 'decor', type: 'crate', x: 4.4, y: 8.4 },
    { kind: 'decor', type: 'lamp', x: 1.5, y: 3.5 },
    { kind: 'decor', type: 'console', x: 12.4, y: 1.4, rot: 2 },
    { kind: 'decor', type: 'runePanel', x: 1.5, y: 5.5 },
    { kind: 'decor', type: 'pipe', x: 6.5, y: 8.6, rot: 1 },
  ],
  objective: { type: 'eliminate', text: 'Take out both grunts and the turret' },
  music: {
    root: 9,
    scale: 'Dorian',
    progression: [0, 3, 0, 4],
    chordBars: 2,
    tracks: [
      { role: 'bass', formula: 'fibonacci', params: { m: 7 } },
      { role: 'drums', formula: 'groove', genre: 'Boom bap', params: { genre: 2, voice: 0, density: 1 } },
      { role: 'melody', formula: 'lissajous', params: { p: 3, q: 2, phase: 0.25 } },
      { role: 'chord', formula: 'voicelead', params: { voices: 4 } },
    ],
  },
  // A sampler so the loadout screen has something to swap after one clear.
  loot: ['reel_lash', 'needle_rail', 'spring_soles', 'hush_hood'],
  briefing: [
    'Sandbox. Everything is unlocked here: every speed, every end mode, all four cassettes.',
    'The lever opens the door north. The cracked wall south breaks to a hard enough hit.',
    'The laser splits the far room while nobody stands on the plate.',
  ],
  hints: {
    1: 'Try 2x on the cracked wall: the same heavy swing carries twice the momentum.',
    2: 'Park a self on the plate and the laser drops for everyone else.',
  },
};
