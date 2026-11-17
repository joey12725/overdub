/**
 * The authoritative result (REC-06, REC-07, OPEN-07) and the outside-the-loop boss memory.
 *
 * resolveEncounter runs every tape — including the one just recorded — under playback rules for the
 * whole horizon. Only that run decides victory, so a recording ghost's provisional effects can never
 * count (Scenario C). Its frames are replayed verbatim by the cinematic (CINE-04).
 */
import { Sim } from './sim';
import { FRAME_SUBS, type FrameSnapshot, type Resolution, type SimConfig, type SimEvent } from './types';

/**
 * Play the combined encounter to the horizon. Stores a snapshot at substep 0, every FRAME_SUBS
 * substeps, and at the final substep (also when the horizon is not a multiple of FRAME_SUBS), plus
 * every event in order.
 */
export function resolveEncounter(config: Omit<SimConfig, 'live'>): Resolution {
  const sim = new Sim({ level: config.level, loadout: config.loadout, tapes: config.tapes, bossMemory: config.bossMemory });
  const H = sim.horizonSubs;
  const frames: FrameSnapshot[] = [sim.snapshot()];
  const events: SimEvent[] = [];
  while (sim.sub < H) {
    sim.stepSub();
    const ev = sim.drainEvents();
    for (const e of ev) events.push(e);
    if (sim.sub % FRAME_SUBS === 0 || sim.sub === H) frames.push(sim.snapshot());
  }
  return { outcome: sim.outcome(), frames, events, horizonSubs: H };
}

/**
 * Cross-recording memory for the boss (BOSS-01/02), built ONLY from committed tapes. Lives in
 * bossMemory.ts next to the reading the boss makes of it; re-exported here for older importers.
 */
export { buildBossMemory } from './bossMemory';
