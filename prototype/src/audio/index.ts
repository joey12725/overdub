/**
 * OVERDUB audio module (MUSIC-01..13, UI-04). The game layer uses `createAudio()`; content authors
 * can call `listMusicFormulas()` / read `LAYER_PARAMS` to see what a level's music may use.
 */
export { createAudio, AudioEngine } from './engine';
export {
  listMusicFormulas,
  isMusicFormulaAllowed,
  resolveFormula,
  LAYER_PARAMS,
  ROLE_DEFAULTS,
  MUSIC_ROLES,
  type MusicFormulaInfo,
  type MusicParamInfo,
  type LayerParamInfo,
  type MusicRole,
} from './formulas';
export { MusicDirector, baselineVariant, resolveGenre, resolveScale, type LayerNote, type LayerVariant, type ChordInfo, type DrumKind } from './director';
