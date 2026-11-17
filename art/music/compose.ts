/**
 * Writes data/music/<piece>.json from pieces.ts (the idea), tuned.json (the tuned music blocks),
 * and statemaps.ts (state maps, SFX pitch policy, latency policy).
 *
 *   cd prototype && npx vite-node ../art/music/compose.ts
 */
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { HG } from '../../prototype/src/audio/hg';
import { analyse, HERE, MUSIC_DIR, NOTE_NAMES, type MusicDef, type StateMaps } from './lib';
import { PIECES } from './pieces';
import { inLevel, levelInfo } from './levelcheck';
import { latencyPolicy, SFX_DEFAULT, SFX_PALETTES, STATE_MAPS, UI_PITCH } from './statemaps';

const tuned: Record<string, { music: MusicDef; score: number }> = JSON.parse(readFileSync(join(HERE, 'tuned.json'), 'utf8'));
mkdirSync(MUSIC_DIR, { recursive: true });
const r1 = (x: number) => Math.round(x * 10) / 10;

for (const p of PIECES) {
  const music = tuned[p.file]?.music;
  if (!music) throw new Error(`${p.file} has not been tuned (run tune.ts)`);
  const rep = analyse({ id: p.file, bpm: p.bpm, music, stateMaps: STATE_MAPS as unknown as StateMaps });
  const info = p.level === 'menu' ? null : levelInfo(p.file);
  if (info && info.bpm !== p.bpm) throw new Error(`${p.file}: composed at ${p.bpm} bpm but ${info.file} says ${info.bpm} (the level designer owns bpm: change pieces.ts and retune)`);
  const heard = inLevel({ bpm: p.bpm, music, stateMaps: STATE_MAPS as unknown as StateMaps }, info ?? { maxTapes: 4, speeds: [0.5, 1, 2, 4], horizonBars: 8 });
  const palette = SFX_PALETTES[p.sfxPalette];
  const doc = {
    schema: 'overdub-music/1',
    id: p.file,
    level: p.level,
    index: p.index,
    title: p.title,
    description: p.description,
    arc: p.arc,
    key: `${NOTE_NAMES[music.root]} ${music.scale}`,
    bpm: p.bpm,
    bpmNote: 'Tempo the piece was composed and measured at. bpm and bars belong to the level designer: if the level file says otherwise, the level wins (3600 / bpm must be an integer).',
    music,
    layers: music.tracks.map((tr, i) => ({
      cassette: i + 1,
      role: tr.role,
      formula: tr.formula,
      formulaName: HG.byId[tr.formula]?.name ?? tr.formula,
      equation: HG.byId[tr.formula]?.formula ?? '',
      ...(tr.genre ? { genre: tr.genre } : {}),
      about: p.layers[i],
    })),
    ...(p.bed ? { bed: { about: 'TrackAudioState per cassette for the menu bed (life alive, synced, transport 1).', tracks: p.bed } } : {}),
    inLevel: {
      about: info
        ? `What a player can hear in ${info.file} as it stands: cassettes 1..${heard.audibleCassettes} (maxTapes) at tape speeds ${info.speeds.join(', ')}; every subset and speed combination of those, ${heard.bars} bars each. The other layers are composed and verified for the day the level gains cassettes.`
        : 'No level file yet: measured for all four cassettes at 0.5, 1, 2 and 4x, every subset and speed combination.',
      levelFile: info ? info.file : null,
      ...(info ? { levelBars: info.bars, levelHorizonBars: info.horizonBars } : {}),
      ...heard,
    },
    stateMaps: STATE_MAPS,
    sfx: {
      palette: p.sfxPalette,
      about: palette.about,
      pitchRule:
        'tones are played in order. from "chord": index into the triad of the chord in force at the cue\'s grid line, stacked upward from the chord root in MIDI octave `octave` (C4 = 60; 0 root, 1 third, 2 fifth, 3 root an octave up ...). from "scale": 0-based degree of the level scale in `octave`. perTape: add the acting cassette index (0..3) to index, so four selves acting together spell the chord. "off" replaces "tones" for off / close events, "heavy" for power >= 6.',
      latency: latencyPolicy(p.bpm),
      classes: { ...SFX_DEFAULT, ...palette.classes },
      ui: UI_PITCH,
    },
    analysis: {
      about: 'Measured by art/music/analyze.ts over 16 master bars per stream; see docs/MUSIC.md for definitions.',
      score: rep.score,
      inScalePct: rep.inScalePct,
      notesChecked: rep.notesChecked,
      harshDownbeatPctMean81: r1(rep.harshDownMean81),
      harshDownbeatPctWorst81: r1(rep.harshDownWorst81),
      harshDownbeatPctMeanWith4x: r1(rep.harshDownMean4x),
      chordToneDownbeatPct: r1(rep.chordToneDownPct),
      onsetsOn16thGridPct: r1(rep.grid16Pct),
      onsetsOn32ndGridPct: r1(rep.grid32Pct),
      onsetsPerBarByLayerAndSpeed: rep.layers.map((l, i) => ({ role: rep.roles[i], ...Object.fromEntries(Object.entries(l).map(([s, st]) => [s + 'x', r1(st.onsetsPerBar)])) })),
      densityFlags: rep.densityFlags,
      mudBelow150HzPct: r1(rep.mudPct),
      leadAboveChordPct: r1(rep.leadAboveChordPct),
      deadDensityRatio: Math.round(rep.states.deadDensityRatio * 100) / 100,
      desyncChangedStepsPct: r1(rep.states.driftChangedPct),
    },
  };
  writeFileSync(join(MUSIC_DIR, p.file + '.json'), JSON.stringify(doc, null, 2) + '\n');
  console.log(`wrote data/music/${p.file}.json  score ${rep.score}`);
}
