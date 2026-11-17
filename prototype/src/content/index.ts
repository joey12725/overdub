/**
 * Content facade (src/contracts.ts "content"): levels, the gear catalogue and loadout resolution.
 * Pure data and pure functions; imports only src/core/types.
 */
export { LEVELS, SANDBOX } from './levels';
export { GEAR, BASE_LOADOUT, BASE_INVENTORY } from './gear';
export {
  resolveLoadout,
  describeLoadout,
  itemsForSlot,
  sanitiseLoadout,
  isBaseline,
  combineMods,
  identityMods,
  isAdditiveStat,
  SLOT_LABEL,
  STAT_LABEL,
  ABILITY_TEXT,
} from './loadout';
