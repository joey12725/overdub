/**
 * Campaign level registry. LEVELS is the fixed campaign path (LEVEL-08), ordered by `index`.
 * Level designers add a module per level here and list it in ALL_LEVELS; order in that list does
 * not matter, sorting by `index` defines the path.
 */
import type { LevelDef } from '../../core/types';
import { CAMPAIGN_LEVELS } from '../levelFiles';
import { SANDBOX } from './sandbox';

// The campaign is data/levels/<NN>-<slug>.json (levelFiles.ts); the sandbox stands in until the first level file exists.
const ALL_LEVELS: LevelDef[] = CAMPAIGN_LEVELS.length > 0 ? CAMPAIGN_LEVELS : [SANDBOX];

export const LEVELS: LevelDef[] = [...ALL_LEVELS].sort((a, b) => a.index - b.index);

export { SANDBOX };
