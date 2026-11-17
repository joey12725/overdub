/**
 * OPEN-22 state maps, OPEN-23 latency policy and the MUSIC-05 SFX pitch policy, as data.
 * compose.ts copies these into every data/music/*.json (with per-piece palettes from pieces.ts).
 *
 * The DEFAULT state maps reproduce the prototype's director.ts note-for-note
 * (verify-statemaps.ts proves it), so the Godot audio port can either keep a hard-coded port of
 * director.ts or read these tables: the notes are the same.
 */
export const STATE_MAPS = {
  about:
    'Generative-parameter changes per actor state (MUSIC-08/09, OPEN-22). Ops are applied to the baseline channel parameters of the layer, in the order given by "order"; "only" restricts an op to roles (pitched layers) or to drum lane classes (kick, backbeat, hat, perc). drift:true scales by the drift level d in 0..1: set -> value*d, add -> value*d, mul -> 1+(value-1)*d.',
  order: ['dead', 'desynced', 'reversing', 'stopped'],
  backgroundVoice:
    'Every PRESENT cassette (recorded, or being recorded now) always has its generated layer sounding, independent of action sounds. A cassette that has not been recorded yet is silent. Action sounds are added on top and never replace the layer.',
  alive: { meaning: 'Baseline: the music block exactly as written.' },
  dead: {
    meaning:
      'The self is a ghost for the rest of this run. The layer thins to its skeleton, softens and falls onto chord tones. It does not recover until a new run keeps that self alive.',
    timing: {
      onset: 'immediate: the first step at or after the death beat (notes already scheduled inside the look-ahead are re-planned)',
      ramp: 'none',
      release: 'only at the next run (restart at beat 0)',
    },
    pitched: [
      { param: 'steps', op: 'max', value: 2 },
      { param: 'pulses', op: 'mul', value: 0.5, round: true, min: 1 },
      { param: 'gravity', op: 'set', value: 1 },
      { param: 'palette', op: 'set', value: 0 },
      { param: 'contour', op: 'max', value: 0.35 },
      { param: 'cycle', op: 'mul', value: 0.25, round: true, min: 4 },
      { param: 'phrase', op: 'set', value: 8 },
      { param: 'accent', op: 'mul', value: 0.65, round: true },
      { param: 'ghost', op: 'mul', value: 0.65, round: true },
      { param: 'extension', op: 'set', value: 0 },
    ],
    drums: {
      lanes: ['kick', 'backbeat', 'hat'],
      backbeatAs: 'rim',
      ops: [
        { param: 'density', op: 'mul', value: 0.5 },
        { param: 'threshold', op: 'max', value: 0.8 },
        { param: 'velocity', op: 'mul', value: 0.65 },
      ],
    },
  },
  desynced: {
    meaning:
      'The self is alive but off its recording. The contour slips ahead of the rhythm and smooths toward the phrase arch; the gate (which steps sound) is untouched, so the layer stays in time and in key. It converges back to the exact baseline after resync.',
    timing: {
      driftRisePerBar: 0.25,
      driftFallPerBar: 0.5,
      driftQuantum: 0.25,
      onset: 'the drift level is evaluated per master bar: 0.25 in the bar of the desync, full (1.0) in the fourth bar',
      release: 'falls 0.5 per bar after resync: exactly on the baseline within two bars',
      deadWins: 'a dead self never drifts (drift = 0)',
    },
    pitched: [
      { param: 'phase', op: 'set', value: 4, drift: true, round: true },
      { param: 'contour', op: 'add', value: 0.45, drift: true, max: 0.8 },
      { param: 'accent', op: 'mul', value: 0.85, drift: true, round: true },
      { param: 'microSteps', op: 'set', value: 0.18, drift: true },
    ],
    drums: {
      ops: [
        { param: 'rotation', op: 'set', value: 2, drift: true, round: true, only: ['perc'] },
        { param: 'phase', op: 'set', value: 4, drift: true, round: true, only: ['hat', 'perc'] },
        { param: 'microSteps', op: 'set', value: 0.18, drift: true, only: ['hat', 'perc'] },
      ],
    },
  },
  reversing: {
    meaning: 'The tape is on a reverse pass. The contour is read backwards across its cycle (retrograde); gate, chord clock and tempo are unchanged.',
    timing: { onset: 'immediate at the next step', ramp: 'none', release: 'immediate at the next step' },
    pitched: [{ param: 'retrograde', op: 'set', value: true }],
    drums: { ops: [{ param: 'retrograde', op: 'set', value: true, only: ['hat', 'perc'] }] },
  },
  stopped: {
    meaning:
      'The tape has stopped. The layer becomes a hold figure: one sustained chord tone (bass: the chord root) re-voiced as the chords move, and the kit a single soft kick heartbeat. Tape speed no longer matters.',
    timing: { onset: 'immediate at the next step', ramp: 'none', release: 'immediate at the next step' },
    pitched: [
      { param: 'rate', op: 'set', value: 2, only: ['melody'] },
      { param: 'rate', op: 'set', value: 4, only: ['bass', 'chord'] },
      { param: 'ignoreSpeed', op: 'set', value: true },
      { param: 'pulses', op: 'set', value: 1 },
      { param: 'steps', op: 'set', value: 1 },
      { param: 'gateLength', op: 'set', value: 1 },
      { param: 'contour', op: 'set', value: 1 },
      { param: 'shape', op: 'set', value: 'flat' },
      { param: 'palette', op: 'set', value: 0 },
      { param: 'gravity', op: 'set', value: 1 },
      { param: 'cadence', op: 'set', value: false },
      { param: 'accent', op: 'mul', value: 0.7, round: true },
      { param: 'ghost', op: 'mul', value: 0.7, round: true },
      { param: 'retrograde', op: 'set', value: false },
      { param: 'phase', op: 'set', value: 0 },
      { param: 'microSteps', op: 'set', value: 0 },
      { param: 'rootAnchor', op: 'set', value: true, only: ['bass'] },
      { param: 'strum', op: 'set', value: 0, only: ['chord'] },
    ],
    drums: {
      lanes: ['kick'],
      ops: [
        { param: 'density', op: 'set', value: 0.34 },
        { param: 'velocity', op: 'mul', value: 0.6 },
        { param: 'rate', op: 'set', value: 0.25 },
        { param: 'ignoreSpeed', op: 'set', value: true },
      ],
    },
  },
  paramGlossary: {
    rate: 'beats per step at 1x (engine channel.rate = rate / tapeSpeed, unless ignoreSpeed)',
    ignoreSpeed: 'when true, channel.rate = rate regardless of tape speed',
    pulses: 'Euclidean gate k (channel.gateParams.k)',
    steps: 'Euclidean gate n (channel.gateParams.n)',
    gateLength: 'channel.gateLength (note length as a fraction of a step)',
    gravity: 'channel.gravity: pull of strong steps onto chord tones',
    palette: 'channel.palette: 0 = chord tones only, 2 = whole scale',
    contour: 'channel.contour: blend of the phrase shape over the formula',
    shape: 'channel.shape: arch | flat',
    cycle: 'channel.cycle: formula period P in steps',
    phrase: 'channel.phrase: phrase length in steps',
    cadence: 'channel.cadence: last step of each phrase lands on the chord root',
    accent: 'channel.accent velocity',
    ghost: 'channel.ghost velocity (never above accent)',
    extension: 'chord layer: 0 = triad, 1 = seventh',
    phase: 'channel.phase: contour index offset in steps',
    microSteps: 'lateness as a fraction of one step (channel.micro in ms = microSteps * stepBeats * 60000 / bpm)',
    retrograde: 'channel.retrograde',
    rootAnchor: 'bass: channel.rootAnchor',
    strum: 'chord: channel.strum in ms',
    density: 'drums: groove density of the kick / backbeat / perc lanes',
    threshold: 'drums: hit threshold of the formula (hat) lane',
    velocity: 'drums: multiplier on every lane accent and ghost',
    rotation: 'drums: groove rotation of the perc lane',
  },
};

/**
 * MUSIC-05 pitch policy. Each class lists the tones it plays, in order.
 *   from "chord": index into the triad of the chord in force at the cue's grid line, stacked upward
 *                 from the chord root in `octave` (0 root, 1 third, 2 fifth, 3 root an octave up ...).
 *   from "scale": 0-based degree of the level scale in `octave` (degree 0 = the key root).
 *   perTape: add the acting cassette index (0..3) to `index`, so four selves spell the chord.
 * The default table is the prototype's sfx.ts RECIPES; per-arc palettes override classes.
 */
export type Tone = { from: 'chord' | 'scale'; index: number; octave: number; perTape?: boolean };
export interface SfxClass {
  tones: Tone[];
  off?: Tone[];
  heavy?: Tone[];
  impact: boolean;
  group: string;
}
const c = (index: number, octave: number, perTape = false): Tone => (perTape ? { from: 'chord', index, octave, perTape } : { from: 'chord', index, octave });
const s = (index: number, octave: number): Tone => ({ from: 'scale', index, octave });

export const SFX_DEFAULT: Record<string, SfxClass> = {
  step: { tones: [c(0, 3, true)], impact: false, group: 'movement' },
  dodge: { tones: [c(1, 5, true)], impact: false, group: 'movement' },
  swingLight: { tones: [c(2, 4, true)], impact: false, group: 'attack' },
  swingHeavy: { tones: [c(0, 3, true)], impact: false, group: 'attack' },
  fire: { tones: [c(0, 4, true), c(2, 5, true)], impact: false, group: 'attack' },
  hit: { tones: [c(0, 4, true), c(2, 5, true)], heavy: [c(2, 4, true), c(4, 5, true)], impact: true, group: 'impact' },
  projectileHit: { tones: [c(1, 5, true)], impact: true, group: 'impact' },
  clang: { tones: [c(1, 5, true)], impact: true, group: 'impact' },
  kill: { tones: [c(0, 5), c(1, 5), c(2, 5)], impact: true, group: 'impact' },
  break: { tones: [c(0, 2), c(0, 3)], impact: true, group: 'impact' },
  interact: { tones: [c(1, 5), c(2, 5)], off: [c(2, 5), c(1, 5)], impact: false, group: 'mechanism' },
  interactFail: { tones: [c(0, 3)], impact: false, group: 'mechanism' },
  door: { tones: [c(0, 2), c(2, 2)], off: [c(2, 2), c(0, 2)], impact: false, group: 'mechanism' },
  plate: { tones: [c(2, 4)], off: [c(0, 4)], impact: false, group: 'mechanism' },
  laser: { tones: [c(0, 3)], impact: false, group: 'mechanism' },
  core: { tones: [c(0, 5), c(1, 5), c(2, 5), c(3, 5)], impact: true, group: 'mechanism' },
  objective: { tones: [c(0, 5), c(1, 5), c(2, 5), c(0, 6)], impact: false, group: 'mechanism' },
  selfDeath: { tones: [c(2, 4), c(1, 4), c(0, 4)], impact: true, group: 'tape' },
  desync: { tones: [c(0, 4, true)], impact: false, group: 'tape' },
  resync: { tones: [c(0, 4, true), c(3, 4, true)], impact: false, group: 'tape' },
  tapeWrap: { tones: [c(0, 5)], impact: false, group: 'tape' },
  tapeTurn: { tones: [c(2, 4)], impact: false, group: 'tape' },
  tapeEnd: { tones: [c(0, 3)], impact: false, group: 'tape' },
  enemyTelegraph: { tones: [c(0, 3), c(1, 3)], impact: false, group: 'enemy' },
  enemyAttack: { tones: [c(0, 2)], impact: true, group: 'enemy' },
  enemyShot: { tones: [c(2, 4)], impact: false, group: 'enemy' },
  enemyStagger: { tones: [c(1, 3)], impact: false, group: 'enemy' },
  bossPhase: { tones: [c(0, 1), c(0, 2), c(2, 2)], impact: true, group: 'enemy' },
  bossRecall: { tones: [c(0, 4), c(2, 4), c(3, 4)], impact: false, group: 'enemy' },
};

/** Per-arc palettes: the same actions change colour as Moxie descends. */
export const SFX_PALETTES: Record<string, { about: string; classes: Record<string, SfxClass> }> = {
  warm: {
    about: 'Upper ruins. Thirds and full triads: every action is a small chime inside the chord (the default table).',
    classes: {},
  },
  hollow: {
    about:
      'The middle. Thirds drop out of the impacts: hits, shots and kills are root-and-fifth, so the mode stays ambiguous and cold. Mechanisms keep their thirds so puzzles still read as friendly.',
    classes: {
      hit: { tones: [c(0, 4, true), c(2, 4, true)], heavy: [c(0, 3, true), c(2, 4, true)], impact: true, group: 'impact' },
      kill: { tones: [c(2, 4), c(0, 5), c(2, 5)], impact: true, group: 'impact' },
      fire: { tones: [c(0, 4, true), c(2, 4, true)], impact: false, group: 'attack' },
      selfDeath: { tones: [c(2, 4), c(0, 4), c(2, 3)], impact: true, group: 'tape' },
    },
  },
  neon: {
    about:
      'Lower levels. Power dyads an octave down and octave stabs: impacts land as weight on root and fifth, while the high blips (dodge, clang) stay above the lead as neon glints.',
    classes: {
      hit: { tones: [c(0, 3, true), c(2, 3, true)], heavy: [c(0, 2, true), c(0, 3, true)], impact: true, group: 'impact' },
      kill: { tones: [c(0, 4), c(2, 4), c(3, 4)], impact: true, group: 'impact' },
      fire: { tones: [c(0, 4, true), c(3, 4, true)], impact: false, group: 'attack' },
      swingLight: { tones: [c(0, 4, true)], impact: false, group: 'attack' },
      enemyAttack: { tones: [c(0, 2), c(2, 2)], impact: true, group: 'enemy' },
    },
  },
  boss: {
    about:
      'The Archivist. Player sounds are the neon table. The enemy telegraphs on the raised seventh of the harmonic minor key (scale degree 6, the leading tone) and attacks on the key root, so every enemy attack is a tiny cadence the player can hear coming.',
    classes: {
      hit: { tones: [c(0, 3, true), c(2, 3, true)], heavy: [c(0, 2, true), c(0, 3, true)], impact: true, group: 'impact' },
      kill: { tones: [c(0, 4), c(2, 4), c(3, 4)], impact: true, group: 'impact' },
      fire: { tones: [c(0, 4, true), c(3, 4, true)], impact: false, group: 'attack' },
      enemyTelegraph: { tones: [s(6, 3)], impact: false, group: 'enemy' },
      enemyAttack: { tones: [s(0, 2), s(0, 3)], impact: true, group: 'enemy' },
      bossRecall: { tones: [s(6, 4), s(0, 5)], impact: false, group: 'enemy' },
      bossPhase: { tones: [s(0, 1), s(0, 2), s(4, 2)], impact: true, group: 'enemy' },
    },
  },
  resolved: {
    about: "The time machine. The warm table again, with kills and the objective opened up by an octave: the first level's chimes, grown.",
    classes: {
      kill: { tones: [c(0, 5), c(1, 5), c(2, 5), c(3, 5)], impact: true, group: 'impact' },
      objective: { tones: [c(0, 4), c(1, 4), c(2, 4), c(0, 5), c(1, 5), c(2, 5), c(0, 6)], impact: false, group: 'mechanism' },
    },
  },
};

export const UI_PITCH = {
  about:
    'UI blips (AudioBase.UI_*) and the count-in use 0-based scale degrees of the key in force: the menu bed key on menus, the level key in a level. Tones are played in order, one grid step apart.',
  move: [s(0, 5)],
  select: [s(0, 5), s(2, 5)],
  back: [s(2, 5), s(0, 5)],
  commit: [s(0, 4), s(2, 4), s(4, 4)],
  retry: [s(4, 4), s(0, 4)],
  reset: [s(4, 4), s(2, 4), s(0, 4)],
  win: [s(0, 4), s(2, 4), s(4, 4), s(0, 5)],
  fail: [s(2, 4), s(0, 4)],
  loot: [s(4, 5), s(0, 6)],
  speed: [s(0, 5), s(4, 5)],
  countIn: { '5': [s(0, 4)], '6': [s(0, 4)], '7': [s(0, 4)], '8': [s(4, 4)] },
};

/** OPEN-23. */
export function latencyPolicy(bpm: number) {
  const sixteenthMs = 15000 / bpm;
  const impactGrid = sixteenthMs > 130 ? 'thirtysecond' : 'sixteenth';
  return {
    about:
      'OPEN-23 / MUSIC-05..07. Only the audible accent is placed, never the simulation event, and only LATE: on the next grid line at or after the event. Impact classes also fire an immediate soft transient (30% gain, first pitch) at the event itself whenever the accent is more than 12 ms away, so feedback is never mushy. Player inputs are not quantised.',
    grid: 'sixteenth of the tempo as heard (the master sixteenth, subdivided by the power of two the world is slowed by while recording at tape speed s)',
    maxLateness: 'one grid step',
    sixteenthMs: Math.round(sixteenthMs * 10) / 10,
    impactGrid,
    impactGridMs: Math.round((impactGrid === 'sixteenth' ? sixteenthMs : sixteenthMs / 2) * 10) / 10,
    impactGridNote:
      'Proposal beyond the prototype: impact classes use the 32nd grid when a sixteenth is longer than 130 ms (bpm below 116), which keeps the worst-case delay of a hit under about 100 ms. All other cues stay on the sixteenth. Both grids nest inside the music.',
    immediateTransientMinDelayMs: 12,
    mergeRule: 'same class and same grid line -> one cue (gain x1.08 per extra event, capped at 1); at most 8 cues per grid line, by priority',
  };
}
