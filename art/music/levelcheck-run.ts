/**
 * Prints, for every piece, what a player can hear in the level as it stands (see levelcheck.ts).
 *
 *   cd prototype && npx vite-node ../art/music/levelcheck-run.ts
 */
import { runLevelCheck } from './levelcheck';

if (runLevelCheck()) process.exit(1);
