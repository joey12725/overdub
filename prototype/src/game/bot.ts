/**
 * Headless bot: plays a Session from a list of scripted takes and reports the Outcome. Level
 * designers use it to prove a level is solvable (APP-TEST-03) without a browser.
 *
 * It drives the real Session exactly as a player would: choose speed / end mode in setup, record
 * (count-in included), one input per local tick, then commit and move to the next cassette. The
 * last take's resolved run is the verdict; earlier takes are committed regardless of whether their
 * own combined runs win (a plan's intermediate runs usually do not).
 */
import type { ActorSnap, EndMode, FrameSnapshot, LevelDef, Outcome, PlayerInput, ResolvedLoadout, TapeIndex, TapeSpeed } from '../core/types';
import { BASE_LOADOUT, resolveLoadout } from '../content/index';
import { createSession, type Session } from './session';

/** What a closed-loop bot controller can see on each local tick. */
export interface BotContext {
  /** Local tick about to be recorded (0-based). */
  tick: number;
  /** Cassette being recorded. */
  index: TapeIndex;
  /** World as of the end of the previous local tick (beat-zero state on tick 0). */
  snap: FrameSnapshot;
  /** The live self in `snap`. */
  self: ActorSnap;
}

export interface BotTake {
  speed: TapeSpeed;
  endMode: EndMode;
  /**
   * Input for each local tick. Open-loop scripts can ignore `ctx`; closed-loop controllers may
   * read it (the session is deterministic, so the take is still reproducible).
   */
  inputs: (tick: number, ctx: BotContext) => PlayerInput;
}

export interface BotOptions {
  /** Gear for every take (shared by all cassettes). Default: the baseline loadout (APP-TEST-03). */
  loadout?: ResolvedLoadout;
  /** Stop as soon as a take wins instead of failing on leftover takes. Default true. */
  stopOnWin?: boolean;
}

export interface BotRun {
  outcome: Outcome;
  /** Takes actually recorded (a win can come before the plan runs out). */
  takesRecorded: number;
  session: Session;
}

const WALL_STEP = 1 / 60;

function settle(session: Session, maxSeconds: number): void {
  // Count-in / playback clocks; a generous bound guards against a stuck phase.
  let t = 0;
  const start = session.phase;
  while (session.phase === start && t < maxSeconds) {
    session.advance(WALL_STEP);
    t += WALL_STEP;
  }
  if (session.phase === start) throw new Error(`bot: session stuck in '${start}'`);
}

function configure(session: Session, take: BotTake, n: number): void {
  const level = session.level;
  if (!level.speeds.includes(take.speed)) throw new Error(`bot: take ${n + 1} wants speed ${take.speed}x; level offers ${level.speeds.join(', ')}`);
  if (!level.endModes.includes(take.endMode)) throw new Error(`bot: take ${n + 1} wants end mode '${take.endMode}'; level offers ${level.endModes.join(', ')}`);
  for (let guard = 0; session.speed !== take.speed && guard < 8; guard++) session.act(session.speed < take.speed ? 'speedUp' : 'speedDown');
  for (let guard = 0; session.endMode !== take.endMode && guard < 4; guard++) session.act('cycleEndMode');
  if (session.speed !== take.speed || session.endMode !== take.endMode) throw new Error(`bot: could not configure take ${n + 1}`);
}

/** Run the plan and return the full result. Throws on a plan the level cannot accept. */
export function runBotDetailed(level: LevelDef, takes: readonly BotTake[], options: BotOptions = {}): BotRun {
  if (takes.length === 0) throw new Error('bot: the plan has no takes');
  if (takes.length > level.maxTapes) throw new Error(`bot: ${takes.length} takes but the level offers ${level.maxTapes} cassettes`);
  const session = createSession({ level, loadout: options.loadout ?? resolveLoadout(BASE_LOADOUT) });
  session.act('start');
  const stopOnWin = options.stopOnWin ?? true;
  const horizonSeconds = session.horizonSubs / 240 + 5;
  for (let n = 0; n < takes.length; n++) {
    const take = takes[n];
    configure(session, take, n);
    session.act('record');
    settle(session, 10);
    if (session.phase !== 'recording') throw new Error(`bot: take ${n + 1} did not start recording`);
    const index = session.activeIndex!;
    let tick = 0;
    while (session.phase === 'recording') {
      const snap = session.currentFrame().snap;
      const self = snap.actors.find((a) => a.live)!;
      session.tickLocal(take.inputs(tick, { tick, index, snap, self }));
      tick++;
    }
    if (session.phase === 'cinematic') {
      settle(session, horizonSeconds);
      return { outcome: session.outcome!, takesRecorded: n + 1, session };
    }
    session.act('skip');
    const outcome = session.outcome!;
    if (n === takes.length - 1 || (outcome.win && stopOnWin)) return { outcome, takesRecorded: n + 1, session };
    if (!session.act('commit')) throw new Error(`bot: could not commit take ${n + 1}`);
  }
  throw new Error('bot: unreachable');
}

/** Run a scripted plan through a real Session and return the authoritative Outcome. */
export function runBot(level: LevelDef, takes: readonly BotTake[], options: BotOptions = {}): Outcome {
  return runBotDetailed(level, takes, options).outcome;
}

// ───────────────────────────── controller helpers ─────────────────────────────

/** A neutral input (no movement, given aim, no buttons). */
export function idleInput(aim = 0): PlayerInput {
  return { moveX: 0, moveY: 0, aim, light: false, heavy: false, dodge: false, ranged: false, interact: false, ability: false };
}

/** Input steering toward (x, y); stops inside `tolerance`. */
export function steerTo(self: { x: number; y: number }, x: number, y: number, tolerance = 0.08): PlayerInput {
  const dx = x - self.x;
  const dy = y - self.y;
  const d = Math.hypot(dx, dy);
  const inp = idleInput(Math.atan2(dy, dx));
  if (d > tolerance) {
    // Ease off near the target so the controller does not overshoot.
    const k = Math.min(1, d / 0.6) / d;
    inp.moveX = dx * k;
    inp.moveY = dy * k;
  }
  return inp;
}
