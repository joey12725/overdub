#!/usr/bin/env node
/**
 * Writes the Harmonograph fidelity goldens for the GDScript port (audio/harmonograph/**):
 *
 *   tests/audio/goldens/hg_formulas.json  catalogue metadata; for every formula at its defaults,
 *                                          at two varied parameter sets (and with {} for normal's
 *                                          raw-params quirk): the first 64 values and normals, a
 *                                          spread of probe steps (negative, fractional, large) and
 *                                          the period.
 *   tests/audio/goldens/hg_harmony.json   chordAt over many harmonic configurations, degreeMidi,
 *                                          scaleNotes, fold, euclid, groovePattern, sumPeriod.
 *   tests/audio/goldens/hg_compile.json   the engine's initial state, and a spread of full states
 *                                          (roots / scales / progressions / chord sources /
 *                                          tempos; melody, bass, chord and drum channels at speeds
 *                                          0.5 / 1 / 2 / 4, retrograde on and off, Sums, every drum
 *                                          genre, lane logic, builds) with compileChannel output for
 *                                          8 bars (plus mid-phrase seeks) and compileTimeline cases.
 *
 * Plain Node, no build step:  node prototype/scripts/export-hg-goldens.cjs
 *
 * Godot's JSON parser does not round-trip every double exactly (about 15% of arbitrary 17-digit
 * values come back one ulp off), which would derail chaotic maps fed from golden inputs. So every
 * non-integer number in an INPUT (parameters, states) is written as the string "<decimal>@<hex>"
 * where hex is the little-endian IEEE-754 bit pattern; the GDScript test decodes the bits.
 * Expected outputs are plain numbers compared within 1e-9 (integers exactly).
 */
'use strict';
const fs = require('fs');
const path = require('path');

const ENGINE = path.resolve(__dirname, '../src/vendor/harmonograph.js');
const exported = require(ENGINE);
const HG = exported && typeof exported.compileChannel === 'function' ? exported : globalThis.HG;
if (!HG || typeof HG.compileChannel !== 'function') throw new Error('Harmonograph engine failed to load');

const OUT_DIR = path.resolve(__dirname, '../../tests/audio/goldens');

// ───────────────────────────── helpers ─────────────────────────────

const buf = Buffer.alloc(8);
function bits(v) {
  buf.writeDoubleLE(v);
  return buf.toString('hex');
}
/** Deep copy with every non-integer finite number replaced by "<decimal>@<hex bits>". */
function enc(x) {
  if (typeof x === 'number') {
    if (!Number.isFinite(x)) throw new Error('non-finite input ' + x);
    if (Number.isInteger(x) && !Object.is(x, -0)) return x;
    return String(x) + '@' + bits(x);
  }
  if (Array.isArray(x)) return x.map(enc);
  if (x && typeof x === 'object') {
    const o = {};
    for (const k of Object.keys(x)) o[k] = enc(x[k]);
    return o;
  }
  return x;
}
/** Output number: must be finite (JSON would turn NaN/Infinity into null). -0 is written as 0. */
function num(v, what) {
  if (typeof v !== 'number' || !Number.isFinite(v)) throw new Error('non-finite output for ' + what + ': ' + v);
  return Object.is(v, -0) ? 0 : v;
}

/** Deterministic PRNG (mulberry32). */
function rng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const pick = (r, list) => list[Math.floor(r() * list.length)];
const randInt = (r, lo, hi) => lo + Math.floor(r() * (hi - lo + 1));

/** A parameter value at fraction f of its range, snapped to the step grid. */
function paramAt(p, f) {
  let v = p.min + (p.max - p.min) * f;
  if (p.step === 1) v = Math.round(v);
  else if (p.step > 0) v = Math.round(v / p.step) * p.step;
  return Math.min(p.max, Math.max(p.min, v));
}
function paramsAt(id, f) {
  return Object.fromEntries(HG.byId[id].params.map((p) => [p.key, paramAt(p, f)]));
}
function randomParams(r, id) {
  return Object.fromEntries(HG.byId[id].params.map((p) => [p.key, paramAt(p, r())]));
}

function write(name, data) {
  fs.mkdirSync(OUT_DIR, { recursive: true });
  const file = path.join(OUT_DIR, name);
  fs.writeFileSync(file, JSON.stringify(data) + '\n');
  console.log('wrote', path.relative(process.cwd(), file), (fs.statSync(file).size / 1024).toFixed(0) + ' KiB');
}

// ───────────────────────────── formulas ─────────────────────────────

const N = 64;
const PROBES = [-7, -1, 0.5, 2.25, 7.75, 15.5, 31, 63.5, 100, 257.5, 1000];

function formulaSet(f, label, params, P) {
  const values = [];
  const normals = [];
  for (let n = 0; n < N; n++) {
    values.push(num(HG.value(f.id, n, params, P), f.id + ' value ' + n));
    normals.push(num(HG.normal(f.id, n, params, P), f.id + ' normal ' + n));
  }
  const probes = PROBES.map((n) => [n, num(HG.value(f.id, n, params, P), f.id + ' probe'), num(HG.normal(f.id, n, params, P), f.id + ' probe n')]);
  const period = HG.period(f.id, params, P);
  return { label, P, params: enc(params), values, normals, probes, period: period === null ? null : num(period, f.id + ' period') };
}

function exportFormulas() {
  const formulas = HG.catalogue.map((f) => ({
    id: f.id,
    name: f.name,
    category: f.category,
    formula: f.formula,
    integer: f.integer,
    hasPeriod: !!f.period,
    params: f.params.map((p) => enc({ key: p.key, label: p.label, value: p.value, min: p.min, max: p.max, step: p.step, detents: p.detents })),
    sets: [
      formulaSet(f, 'default', HG.defaults(f.id), 16),
      formulaSet(f, 'varied-a', paramsAt(f.id, 0.27), 12),
      formulaSet(f, 'varied-b', paramsAt(f.id, 0.83), 24),
      // normal() reads the RAW params for its modulus (p.m || p.N || p.p || ...): {} differs.
      formulaSet(f, 'empty', {}, 16),
    ],
  }));
  write('hg_formulas.json', { version: 1, generator: 'prototype/scripts/export-hg-goldens.cjs', n: N, probes: PROBES, formulas, chaos: chaosTraces() });
  return formulas.length;
}

/**
 * Bit-level traces of the two maps whose recurrence goes through Math.sin (sinemap, circle), at
 * every parameter set of the formula goldens: per iterate the sin argument, Math.sin's result and
 * the new x, as IEEE bit patterns. They let the GDScript test locate the first iterate where its
 * platform sin differs from V8's (by an ulp) and show that the rest of the arithmetic is exact,
 * i.e. that any divergence of these chaotic maps comes from the sin implementation alone.
 * The recurrences below are copied from the engine's stream() verbatim.
 */
function chaosTraces() {
  const out = [];
  const TAU = Math.PI * 2;
  const mod = (x, m) => ((x % m) + m) % m;
  const ITER = 1300;
  for (const id of ['sinemap', 'circle']) {
    const sets = [['default', HG.defaults(id)], ['varied-a', HG.cleanParams(id, paramsAt(id, 0.27))], ['varied-b', HG.cleanParams(id, paramsAt(id, 0.83))]];
    for (const [label, p] of sets) {
      let x = 0.217;
      const trace = [];
      for (let i = 0; i < ITER; i++) {
        const arg = id === 'sinemap' ? Math.PI * x : TAU * x;
        const s = Math.sin(arg);
        x = id === 'sinemap' ? p.r * s : mod(x + p.omega - p.K / TAU * s, 1);
        trace.push([bits(arg), bits(s), bits(x)]);
      }
      // The trace must be the engine's own stream.
      const seq = Array.from({ length: ITER }, (_, n) => HG.value(id, n, p));
      seq.forEach((v, n) => { if (bits(v) !== trace[n][2]) throw new Error('chaos trace is not the engine stream: ' + id + ' ' + n); });
      out.push({ id, label, params: enc(p), trace });
    }
  }
  return out;
}

// ───────────────────────────── harmony ─────────────────────────────

function harmonyState(cfg) {
  const s = HG.initialState();
  s.sections = [];
  s.channels = [];
  Object.assign(s, cfg);
  return s;
}

function exportHarmony() {
  const r = rng(1405);
  const scales = Object.keys(HG.SCALES);
  const configs = [];
  // Every scale, a few roots, progression source.
  scales.forEach((scale, i) => {
    for (const root of [0, (i * 5 + 2) % 12, (i * 7 + 9) % 12]) {
      configs.push({ root, scale, chordSource: 'progression', progression: [0, 5, 2, 6], chordRate: 4, extension: i % 5 });
    }
  });
  // Progression shapes and rates.
  for (const [progression, chordRate] of [[[0, 3, 4, 0], 2], [[1, 4, 0], 8], [[6, 5, 4, 3, 2, 1, 0], 1], [[-1, 7, 9, -8], 4], [[0], 4], [[2, 2, 5], 0.5]]) {
    configs.push({ root: randInt(r, 0, 11), scale: pick(r, scales), chordSource: 'progression', progression, chordRate, extension: randInt(r, 0, 4) });
  }
  // Formula-chosen chords (every Harmony formula and a few others), with allowed sets.
  for (const chordFormula of ['circlechord', 'extension', 'voicelead', 'spread', 'plr', 'fibonacci', 'sine', 'logistic', 'euclid', 'thue']) {
    for (let k = 0; k < 2; k++) {
      configs.push({
        root: randInt(r, 0, 11), scale: pick(r, scales), chordSource: 'formula', chordFormula,
        chordParams: k ? randomParams(r, chordFormula) : {}, chordRate: pick(r, [1, 2, 4]),
        allowed: k ? [0, 3, 4, 5] : [0, 1, 2, 3, 4, 5, 6], extension: randInt(r, 0, 4),
        degree: randInt(r, 0, 6), quality: k ? pick(r, ['diatonic', 'major', 'minor']) : 'diatonic',
      });
    }
  }
  // Pads, qualities, borrowed chords, escape and shift.
  const borrowed = ['', '♭II', '♭III', '♭VI', '♭VII', 'iv', 'V/V', 'V/vi', 'TT', 'sus', 'bogus'];
  const qualities = ['diatonic', 'major', 'minor', 'dominant', 'diminished', 'weird'];
  for (let k = 0; k < 40; k++) {
    configs.push({
      root: randInt(r, 0, 11), scale: pick(r, scales), chordSource: pick(r, ['pads', 'pads', 'progression']),
      progression: [randInt(r, 0, 6), randInt(r, 0, 6), randInt(r, 0, 6)], chordRate: 4,
      degree: randInt(r, 0, 6), extension: randInt(r, 0, 4), quality: pick(r, qualities),
      borrowed: pick(r, borrowed), escape: r() < 0.6, shift: r() < 0.3,
      chordRoot: r() < 0.5 ? randInt(r, 0, 11) : null,
    });
  }
  const beats = [];
  for (let b = 0; b < 64; b += 1.5) beats.push(b);
  beats.push(-3, -0.5, 127.25);
  const chords = configs.map((cfg) => {
    const s = harmonyState(cfg);
    return { config: enc(cfg), chords: beats.map((beat) => { const c = HG.chordAt(s, beat); return [beat, c.degree, c.root, c.pcs, c.name]; }) };
  });

  const degreeMidi = [];
  for (const scale of scales) for (const root of [0, 4, 11]) {
    const row = [];
    for (let d = -10; d <= 20; d++) row.push(HG.degreeMidi(d, { root, scale }));
    degreeMidi.push({ scale, root, from: -10, values: row });
  }

  const scaleNotes = [];
  for (let k = 0; k < 30; k++) {
    const low = randInt(r, 0, 100);
    const c = { low, high: low + randInt(r, 1, 40), octave: pick(r, [0, 0, 1, -1, 2]) };
    const s = { root: randInt(r, 0, 11), scale: pick(r, scales) };
    scaleNotes.push({ channel: c, state: s, notes: HG.scaleNotes(c, s) });
  }
  // Edges: empty and clamped ranges.
  for (const c of [{ low: 120, high: 140, octave: 1 }, { low: -5, high: 3, octave: 0 }, { low: 61, high: 61, octave: 0 }]) {
    const s = { root: 1, scale: 'Major Pentatonic' };
    scaleNotes.push({ channel: c, state: s, notes: HG.scaleNotes(c, s) });
  }

  const fold = [];
  for (const mode of ['reflect', 'wrap', 'nearest', 'drift']) for (const len of [0, 1, 2, 5, 7, 12, 15]) for (const oct of [5, 7]) {
    const row = [];
    for (let d = -20; d <= 30; d++) for (const prev of [0, 3, 9]) row.push(num(HG.fold(d, len, mode, prev, oct), 'fold'));
    fold.push({ mode, len, octave: oct, values: row });
  }

  const euclid = [];
  for (const n of [1, 3, 5, 8, 12, 16, 7.6]) for (const k of [0, 1, 2, 3, 5, 8, 16, 2.5, -1]) for (const rot of [0, 1, 3]) {
    const row = [];
    for (let step = -4; step < 36; step++) row.push(HG.euclid(step, k, n, rot));
    euclid.push({ k: enc(k), n: enc(n), rot, values: row });
  }

  const groove = [];
  HG.GENRES; // order of Object.values(GENRES) is the genre index
  for (let genre = 0; genre <= 11; genre++) for (let voice = 0; voice <= 7; voice++) for (const density of [0.5, 1, 1.55, 2]) for (const rotation of [0, 3]) {
    const p = HG.cleanParams('groove', { genre, voice, density, rotation });
    const g = HG.groovePattern(p);
    groove.push({ params: enc(p), k: g.k, n: g.n, rotation: g.rotation });
  }

  write('hg_harmony.json', { version: 1, genres: Object.keys(HG.GENRES), scales, chords, degreeMidi, scaleNotes, fold, euclid, groove });
  return chords.length;
}

// ───────────────────────────── states ─────────────────────────────

const ALL_IDS = HG.catalogue.map((f) => f.id);
const GATE_IDS = HG.catalogue.filter((f) => f.category === 'Rhythm & gates').map((f) => f.id);
const VEL_IDS = ['accent', 'crescendo', 'sine', 'saw', 'triangle', 'euclid', 'groove', 'spread', 'logistic', 'fibonacci'];
const GENRE_NAMES = Object.keys(HG.GENRES);
const SPEEDS = [0.5, 1, 2, 4];
const TYPES = ['Melody', 'Bass', 'Chord', 'Drums'];
const BASE_INDEX = { Melody: 0, Bass: 2, Chord: 3, Drums: 4 };

function baseState(r) {
  const s = HG.initialState();
  s.sections = [];
  s.channels = [];
  s.queuedSection = null;
  if (r) {
    s.root = randInt(r, 0, 11);
    s.scale = pick(r, Object.keys(HG.SCALES));
    s.tempo = pick(r, [72, 90, 100, 120, 132, 140, 174]);
    s.chordRate = pick(r, [2, 4, 8, 16]);
    s.progression = Array.from({ length: randInt(r, 1, 6) }, () => randInt(r, 0, 6));
    s.inversion = r() < 0.2 ? randInt(r, 0, 2) : 0;
    s.chordOctave = r() < 0.15 ? pick(r, [-1, 1]) : 0;
    if (r() < 0.2) { s.chordSource = 'formula'; s.chordFormula = pick(r, ['circlechord', 'plr', 'fibonacci', 'voicelead']); s.chordParams = randomParams(r, s.chordFormula); }
    if (r() < 0.1) { s.quality = pick(r, ['major', 'minor', 'dominant', 'diminished']); }
    if (r() < 0.15) { s.escape = true; s.borrowed = pick(r, ['', '♭VI', 'iv', 'sus']); }
    if (r() < 0.1) s.shift = true;
  }
  return s;
}

/** A preset channel of the given type with its id set to its position. */
function makeChannel(type, id) {
  const c = HG.channel(BASE_INDEX[type]);
  c.id = id;
  c.active = true;
  return c;
}

/** Randomised but valid channel configuration (deterministic from r). */
function randomChannel(r, type, id, formula) {
  const c = makeChannel(type, id);
  c.formula = formula;
  c.params = randomParams(r, formula);
  c.rate = type === 'Drums' ? pick(r, [0.25, 0.25, 0.5]) : pick(r, [0.25, 0.5, 1, 2]);
  c.speed = pick(r, SPEEDS);
  c.retrograde = r() < 0.4;
  c.cycle = pick(r, [8, 12, 16, 24, 32]);
  c.phrase = pick(r, [8, 12, 16, 32]);
  c.phase = r() < 0.3 ? randInt(r, 1, 5) : 0;
  c.gate = pick(r, GATE_IDS);
  c.gateParams = randomParams(r, c.gate);
  if (c.gate === 'euclid') c.gateParams = { k: randInt(r, 1, 8), n: pick(r, [8, 12, 16]), rot: randInt(r, 0, 3) };
  c.gateLength = pick(r, [0.5, 0.72, 0.9, 1.2]);
  c.velocity = pick(r, VEL_IDS);
  c.velocityParams = r() < 0.5 ? randomParams(r, c.velocity) : {};
  c.accent = randInt(r, 70, 127);
  c.ghost = randInt(r, 20, 69);
  c.repeated = pick(r, ['retrigger', 'retrigger', 'tie', 'suppress']);
  if (type !== 'Drums') {
    c.low = type === 'Bass' ? randInt(r, 28, 40) : randInt(r, 48, 64);
    c.high = c.low + randInt(r, 7, 26);
  }
  c.gravity = pick(r, [0, 0.4, 0.8, 1]);
  c.palette = pick(r, [0, 1, 2, 2, 3]);
  c.mode = r() < 0.3 ? 'step' : 'absolute';
  c.fold = pick(r, ['reflect', 'wrap', 'nearest', 'drift']);
  c.leap = randInt(r, 1, 4);
  c.recovery = r() < 0.7;
  c.contour = pick(r, [0, 0, 0.2, 0.5]);
  c.shape = pick(r, ['arch', 'ramp', 'flat']);
  c.cadence = r() < 0.7;
  c.swing = pick(r, [0.5, 0.5, 0.58, 0.66]);
  c.micro = pick(r, [0, 0, 12.5, -8]);
  c.invert = r() < 0.15;
  c.octave = pick(r, [0, 0, 0, 1, -1]);
  if (r() < 0.25) {
    const keys = Object.keys(c.params);
    if (keys.length) { c.variation = pick(r, [1, 2, 0.5]); c.variationParam = pick(r, keys); }
  }
  if (type === 'Bass') { c.rootAnchor = r() < 0.5; c.octavePattern = pick(r, [0, 0, 3, 5]); }
  if (type === 'Chord') {
    c.voicingFormula = r() < 0.5;
    c.extension = randInt(r, 0, 4);
    c.inversion = randInt(r, 0, 2);
    c.followContour = r() < 0.4;
    c.minimal = r() < 0.7;
    c.spread = pick(r, [0, 0, 1]);
    c.strum = pick(r, [0, 10, 25]);
    c.strumDirection = pick(r, [1, -1]);
  }
  if (type === 'Drums') randomLanes(r, c);
  return c;
}

function randomLanes(r, c) {
  // The engine's `genre` command on lanes 0..3.
  const g = HG.GENRES[pick(r, GENRE_NAMES)];
  c.lanes.slice(0, 4).forEach((l, i) => { l.gate = 'euclid'; l.params = { k: g[i][0], n: g[i][1], rot: g[i][2] }; l.mute = false; });
  c.lanes.forEach((l, j) => {
    if (j > 3) l.mute = r() < 0.6;
    if (r() < 0.2) { l.gate = pick(r, GATE_IDS); l.params = randomParams(r, l.gate); }
    if (r() < 0.25) { l.logic = pick(r, ['AND', 'OR', 'XOR', 'NOT']); l.other = randInt(r, 0, 7); }
    l.approach = r() < 0.1;
    l.anticipation = r() < 0.1;
    if (r() < 0.2) { l.velocity = pick(r, VEL_IDS); l.velocityParams = randomParams(r, l.velocity); }
    l.micro = r() < 0.15 ? 7.5 : 0;
    l.accent = randInt(r, 80, 127);
    l.ghost = randInt(r, 20, 60);
  });
}

/** Director-style drum channel: one lane, formula-driven (MusicDirector.drumChannel). */
function directorDrum(id, genre, voice, lane, formula, params, opts = {}) {
  const c = makeChannel('Drums', id);
  const useFormula = formula !== 'groove';
  const p = useFormula ? params : HG.cleanParams('groove', { genre: GENRE_NAMES.indexOf(genre), voice, density: opts.density ?? 1, rotation: opts.rotation ?? 0 });
  c.formula = useFormula ? formula : 'groove';
  c.params = p;
  c.drumLane = lane;
  c.drumFormula = true;
  c.drumVelocity = opts.drumVelocity ?? 'formula';
  c.drumThreshold = useFormula ? (opts.threshold ?? 0.5) : 0.5;
  c.rate = opts.rate ?? 0.25;
  c.cycle = 16;
  c.phrase = 16;
  c.gateLength = 0.5;
  c.swing = opts.swing ?? 0.5;
  c.phase = opts.phase ?? 0;
  c.retrograde = !!opts.retrograde;
  c.speed = opts.speed ?? 1;
  c.lanes = c.lanes.map((l, j) => ({ ...l, mute: j !== lane, gate: c.formula, params: { ...p }, accent: opts.accent ?? 100, ghost: opts.ghost ?? 50, micro: 0 }));
  return c;
}

/** Director-style pitched channel (MusicDirector.pitchedChannel at a baseline variant). */
function directorPitched(id, type, formula, params, o) {
  const c = makeChannel(type, id);
  c.formula = formula;
  c.params = HG.cleanParams(formula, params);
  c.low = o.low;
  c.high = o.high;
  c.mode = 'absolute';
  c.fold = 'reflect';
  c.rate = o.rate;
  c.gate = 'euclid';
  c.gateParams = { k: o.pulses, n: o.steps, rot: 0 };
  c.gateLength = o.gateLength;
  c.gravity = o.gravity;
  c.contour = o.contour;
  c.shape = o.shape ?? 'arch';
  c.palette = o.palette;
  c.cycle = 16;
  c.phrase = o.phrase ?? 16;
  c.cadence = o.cadence ?? true;
  c.leap = 2;
  c.recovery = true;
  c.velocity = 'accent';
  c.velocityParams = {};
  c.accent = o.accent;
  c.ghost = o.ghost;
  c.speed = 1;
  c.phase = o.phase ?? 0;
  c.micro = o.micro ?? 0;
  c.retrograde = !!o.retrograde;
  if (type === 'Bass') { c.rootAnchor = !!o.rootAnchor; c.octavePattern = 0; }
  if (type === 'Chord') {
    c.extension = o.extension ?? 1;
    c.voicingFormula = false;
    c.followContour = true;
    c.minimal = true;
    c.inversion = 0;
    c.spread = 0;
    c.strum = o.strum ?? 10;
    c.strumDirection = 1;
  }
  return c;
}

function compileAll(s, windows) {
  const out = [];
  for (let i = 0; i < s.channels.length; i++) {
    for (const [start, bars] of windows) {
      const notes = HG.compileChannel(s, i, start, bars).map((e) => [
        e.pitch, e.velocity, num(e.beat, 'beat'), num(e.duration, 'duration'), e.step,
        e.lane === undefined ? -1 : e.lane, e.formulaValue === undefined ? null : num(e.formulaValue, 'fv'), e.roll ? 1 : 0,
      ]);
      out.push({ channel: i, start, bars, notes });
    }
  }
  return out;
}

const WINDOWS = [[0, 8]];
const SEEK_WINDOWS = [[0, 8], [12, 2], [30, 1.5]];

function exportCompile() {
  const states = [];
  const add = (name, s, windows = WINDOWS) => {
    // The JSON round trip is the engine's own copy(); it also drops `undefined` fields.
    const plain = HG.copy(s);
    delete plain.sections;
    states.push({ name, state: enc(plain), compiles: compileAll(s, windows) });
  };

  // 1. The engine's initial state, all eight presets audible (lorenz pad, rose arp, ...).
  {
    const s = HG.initialState();
    s.sections = [];
    s.channels.forEach((c) => (c.active = true));
    add('initial-all-active', s, SEEK_WINDOWS);
  }
  // 2. Every type at every speed, retrograde off and on (8 channels per state).
  TYPES.forEach((type, ti) => {
    const r = rng(100 + ti);
    const s = baseState(r);
    const formula = ['lorenz', 'fibonacci', 'sine', 'groove'][ti];
    SPEEDS.forEach((speed) => [false, true].forEach((retro) => {
      const c = type === 'Drums' && formula === 'groove'
        ? directorDrum(s.channels.length, GENRE_NAMES[ti * 2], 2, 2, 'groove', null, { speed, retrograde: retro })
        : makeChannel(type, s.channels.length);
      if (type !== 'Drums') { c.formula = formula; c.params = HG.defaults(formula); }
      c.speed = speed;
      c.retrograde = retro;
      s.channels.push(c);
    }));
    add('speeds-' + type.toLowerCase(), s, SEEK_WINDOWS);
  });
  // 2b. The same matrix through the rate (how the director applies tape speed: rate / speed).
  TYPES.forEach((type, ti) => {
    const r = rng(200 + ti);
    const s = baseState(r);
    SPEEDS.forEach((speed) => [false, true].forEach((retro) => {
      const c = randomChannel(r, type, s.channels.length, pick(r, ALL_IDS));
      c.rate = (type === 'Drums' ? 0.25 : type === 'Chord' ? 2 : 0.5) / speed;
      c.speed = 1;
      c.retrograde = retro;
      s.channels.push(c);
    }));
    add('rates-' + type.toLowerCase(), s);
  });
  // 3. Every formula as a melody contour (and as a bass / chord / drum-formula contour), random
  //    keys, scales, progressions and tempos.
  {
    const r = rng(300);
    for (let i = 0; i < ALL_IDS.length; i += 4) {
      const s = baseState(r);
      for (let j = 0; j < 4 && i + j < ALL_IDS.length; j++) {
        const id = ALL_IDS[i + j];
        const type = TYPES[(i / 4 + j) % 4];
        if (type === 'Drums') {
          s.channels.push(directorDrum(s.channels.length, pick(r, GENRE_NAMES), 2, 2, id, randomParams(r, id), {
            threshold: pick(r, [0.3, 0.5, 0.7]), drumVelocity: pick(r, ['formula', 'fixed', 'legacy']),
            speed: pick(r, SPEEDS), retrograde: r() < 0.5, swing: pick(r, [0.5, 0.56]),
          }));
        } else {
          s.channels.push(randomChannel(r, type, s.channels.length, id));
        }
      }
      add('formulas-' + i, s);
    }
  }
  // 4. Every scale with a director-style band (melody / bass / chord / groove kit).
  {
    const r = rng(400);
    Object.keys(HG.SCALES).forEach((scale, i) => {
      const s = baseState(null);
      s.root = (i * 7) % 12;
      s.scale = scale;
      s.tempo = [96, 110, 120, 128, 140][i % 5];
      s.progression = [[0, 5, 3, 4], [0, 3, 4, 0], [5, 3, 0, 4], [1, 4, 0, 0]][i % 4];
      s.chordRate = [4, 8][i % 2];
      const low = (floor, span) => { const l = floor + (((s.root - floor) % 12) + 12) % 12; return { low: l, high: l + span }; };
      const m = pick(r, ALL_IDS.filter((id) => !['Harmony', 'Expression', 'Rhythm & gates'].includes(HG.byId[id].category)));
      s.channels.push(directorPitched(0, 'Melody', m, randomParams(r, m), { ...low(55, 19), rate: 0.5, pulses: 5, steps: 8, gateLength: 0.8, gravity: 0.5, contour: 0.15, palette: 2, accent: 96, ghost: 50 }));
      s.channels.push(directorPitched(1, 'Bass', 'fibonacci', { m: 7 }, { ...low(31, 17), rate: 0.5 / pick(r, SPEEDS), pulses: 3, steps: 8, gateLength: 0.85, gravity: 0.8, contour: 0.1, palette: 0, accent: 104, ghost: 64 }));
      s.channels.push(directorPitched(2, 'Chord', 'sine', {}, { ...low(50, 19), rate: 2, pulses: 1, steps: 1, gateLength: 0.92, gravity: 0.5, contour: 0.2, palette: 2, accent: 82, ghost: 58, retrograde: i % 3 === 0 }));
      const genre = GENRE_NAMES[i % GENRE_NAMES.length];
      s.channels.push(directorDrum(3, genre, 0, 0, 'groove', null, { accent: 112, ghost: 76 }));
      s.channels.push(directorDrum(4, genre, 1, 1, 'groove', null, { accent: 100, ghost: 62, swing: 0.56 }));
      s.channels.push(directorDrum(5, genre, 2, 2, pick(r, ['lorenz', 'sine', 'thue', 'euclid']), {}, { accent: 84, ghost: 30, threshold: 0.5 }));
      s.channels.push(directorDrum(6, genre, 5, 5, 'groove', null, { accent: 78, ghost: 40, rotation: 1, phase: 2, retrograde: true }));
      add('scale-' + scale.toLowerCase().replace(/[^a-z]/g, '-'), s);
    });
  }
  // 5. Every genre: a full kit from the genre command (Euclidean lanes 0..3 plus extras, lane
  //    logic, approach / anticipation), and the groove formula on every voice.
  GENRE_NAMES.forEach((genre, gi) => {
    const r = rng(500 + gi);
    const s = baseState(r);
    const kit = makeChannel('Drums', 0);
    s.channels.push(kit);
    HG.command(s, { type: 'genre', channel: 0, name: genre });
    kit.lanes.forEach((l, j) => {
      if (j > 3) l.mute = j % 2 === 0;
      l.velocity = pick(r, VEL_IDS);
      l.velocityParams = randomParams(r, l.velocity);
    });
    kit.lanes[5].logic = ['AND', 'OR', 'XOR', 'NOT'][gi % 4];
    kit.lanes[5].other = 0;
    kit.lanes[7].approach = true;
    kit.lanes[6].anticipation = true;
    kit.swing = gi % 3 === 0 ? 0.6 : 0.5;
    const logicKit = randomChannel(r, 'Drums', 1, 'euclid');
    s.channels.push(logicKit);
    for (let voice = 0; voice <= 7; voice++) {
      s.channels.push(directorDrum(s.channels.length, genre, voice, voice, 'groove', null, { density: pick(r, [0.5, 1, 1.5]), rotation: voice % 3, drumVelocity: pick(r, ['formula', 'fixed', 'legacy']) }));
    }
    add('genre-' + gi, s);
  });
  // 6. Sums: every operator, both modes, term sources (including a cycle), sum gate / velocity.
  {
    const ops = ['+', '×', '∘', 'mod', 'interleave', 'mask', 'max', 'min', 'AND', 'OR', 'XOR'];
    const r = rng(600);
    for (const mode of ['contour', 'integer']) {
      for (let k = 0; k < ops.length; k += 3) {
        const s = baseState(r);
        for (let j = 0; j < 4; j++) {
          const type = TYPES[j];
          const c = randomChannel(r, type, j, pick(r, ALL_IDS));
          c.sumEnabled = true;
          c.sumMode = mode;
          c.sumMod = pick(r, [5, 7, 12]);
          c.sumGate = r() < 0.4;
          c.sumVelocity = r() < 0.4;
          c.sumThreshold = pick(r, [0.3, 0.5, 0.7]);
          c.terms.forEach((t, ti) => {
            t.amplitude = ti < 4 ? pick(r, [1, 0.5, -0.75, 0.3]) : 0;
            t.formula = pick(r, ALL_IDS);
            t.params = randomParams(r, t.formula);
            t.ratio = pick(r, [1, 2, 3, 0.5, 1.5]);
            t.phase = pick(r, [0, 0.25, 0.5]);
            t.operator = ops[(k + ti) % ops.length];
            t.source = ti === 2 && r() < 0.6 ? randInt(r, 0, 3) : -1;
          });
          s.channels.push(c);
        }
        add('sum-' + mode + '-' + k, s);
      }
    }
  }
  // 7. Pitch-mapping matrix: step mode with every fold and recovery, palettes, shapes, cadence,
  //    variation, invert, repeats; chord voicing options.
  {
    const r = rng(700);
    for (let k = 0; k < 6; k++) {
      const s = baseState(r);
      s.escape = k % 2 === 1;
      ['reflect', 'wrap', 'nearest', 'drift'].forEach((fold, j) => {
        const c = randomChannel(r, 'Melody', s.channels.length, pick(r, ['collatz', 'lorenz', 'logistic', 'sine', 'recaman', 'harmonograph']));
        c.mode = k < 3 ? 'step' : 'absolute';
        c.fold = fold;
        c.recovery = (j + k) % 2 === 0;
        c.leap = 2 + (j % 3);
        c.palette = (j + k) % 4;
        c.gate = 'euclid';
        c.gateParams = { k: 5 + j, n: 8 + j, rot: j };
        s.channels.push(c);
      });
      const chord = randomChannel(r, 'Chord', s.channels.length, pick(r, ['sine', 'triangle', 'rose']));
      chord.gate = 'modgate';
      chord.gateParams = { d: pick(r, [2, 4, 8]), rot: 0 };
      s.channels.push(chord);
      add('mapping-' + k, s);
    }
  }
  // 8. Builds: held (kick / bass muted, hat densified, Zeno roll) and released with an end.
  {
    const r = rng(800);
    for (const [held, released, start, end] of [[true, false, 4, null], [false, true, 0, 22], [true, false, 10, null]]) {
      const s = baseState(r);
      Object.assign(s.build, { held, released, start, end, q: pick(r, [0.8, 0.7]), gap: 1, hits: 24, bars: 4 });
      s.channels.push(makeChannel('Drums', 0));
      s.channels.push(randomChannel(r, 'Bass', 1, 'fibonacci'));
      s.channels.push(directorDrum(2, 'House', 1, 1, 'groove', null, {}));
      const lane2 = makeChannel('Drums', 3);
      lane2.drumLane = 2;
      s.channels.push(lane2);
      add('build-' + (held ? 'held' : 'released') + '-' + start, s);
    }
  }
  // 9. Solo, inactive channels and degenerate ranges.
  {
    const r = rng(900);
    const s = baseState(r);
    for (let j = 0; j < 4; j++) s.channels.push(randomChannel(r, TYPES[j], j, pick(r, ALL_IDS)));
    s.channels[1].solo = true;
    s.channels[3].solo = true;
    s.channels.push(randomChannel(r, 'Melody', 4, 'sine'));
    s.channels[4].active = false;
    const empty = randomChannel(r, 'Melody', 5, 'sine');
    empty.low = 61; empty.high = 61; // C♯ only: empty in most keys
    s.channels.push(empty);
    add('solo-and-edges', s);
  }

  // Timelines: queued channel toggles and a released build inside the window.
  const timelines = [];
  {
    const r = rng(1000);
    for (let k = 0; k < 3; k++) {
      const s = baseState(r);
      for (let j = 0; j < 4; j++) s.channels.push(randomChannel(r, TYPES[j], j, pick(r, ALL_IDS)));
      s.channels[0].queued = { active: false, beat: 8 };
      s.channels[1].active = false;
      s.channels[1].queued = { active: true, beat: 4 + k * 2 };
      s.channels[3].queued = { active: k % 2 === 0, beat: 14 };
      if (k > 0) Object.assign(s.build, { held: false, released: true, start: 2, end: 10 + k, q: 0.8, gap: 1, hits: 16, bars: 2 });
      const plain = HG.copy(s);
      delete plain.sections;
      const results = [];
      for (let i = 0; i < s.channels.length; i++) {
        results.push({
          channel: i, start: 0, bars: 4,
          notes: HG.compileTimeline(s, i, 0, 4).map((e) => [e.pitch, e.velocity, num(e.beat, 'b'), num(e.duration, 'd'), e.step, e.lane === undefined ? -1 : e.lane, e.formulaValue === undefined ? null : num(e.formulaValue, 'fv'), e.roll ? 1 : 0]),
        });
      }
      timelines.push({ name: 'timeline-' + k, state: enc(plain), compiles: results });
    }
  }

  // Sum periods and ratio choices for the Sum states.
  const sumPeriods = [];
  for (const st of states.filter((x) => x.name.startsWith('sum-') || x.name.startsWith('formulas-'))) {
    // Rebuild the live state from the encoded copy is unnecessary: recompute from a fresh decode.
    const s = JSON.parse(JSON.stringify(st.state), (k, v) => (typeof v === 'string' && /@[0-9a-f]{16}$/.test(v) ? Buffer.from(v.split('@')[1], 'hex').readDoubleLE(0) : v));
    s.channels.forEach((c, i) => {
      const p = HG.sumPeriod(c, s);
      sumPeriods.push({ state: st.name, channel: i, period: p === null ? null : p, ratios: c.terms.map((t) => HG.ratioChoices(c, t, s)) });
    });
  }

  const initial = HG.initialState();
  delete initial.sections;
  write('hg_compile.json', { version: 1, initialState: enc(initial), states, timelines, sumPeriods });
  return { states: states.length, timelines: timelines.length };
}

const nf = exportFormulas();
const nh = exportHarmony();
const nc = exportCompile();
console.log(`formulas: ${nf}; harmony configs: ${nh}; states: ${nc.states}; timelines: ${nc.timelines}`);
