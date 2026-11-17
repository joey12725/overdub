'use strict';
// Prints the Harmonograph formula reference as Markdown, generated from the
// vendored engine so the document can never drift from the catalogue.
// Usage: node scripts/list-formulas.cjs > docs/HARMONOGRAPH-FORMULAS.md

const path = require('node:path');

// The UMD bundle assigns globalThis.HG as a side effect of loading (see the
// header of src/vendor/harmonograph.js). Read the API from there rather than
// from require()'s return value, which is not the engine API under CommonJS here.
const modulePath = path.resolve(__dirname, '..', 'src', 'vendor', 'harmonograph.js');
const returned = require(modulePath);
const HG = [globalThis.HG, returned].find(api => api && Array.isArray(api.catalogue));
if (!HG) throw new Error('harmonograph.js did not expose a catalogue');

const esc = value => String(value).replace(/\|/g, '\|').replace(/\r?\n/g, ' ');
const num = value => (Number.isFinite(value) ? String(value) : esc(value));

const out = [];
const line = (text = '') => out.push(text);

line('# Harmonograph formula reference');
line();
line('LevelDef.music.tracks[].formula must be one of the formula ids listed below, and each key in that track\'s params object must come from the parameter list of the chosen formula (keys not listed there are dropped by the engine). ' +
  'Every value is generated from `src/vendor/harmonograph.js` by `scripts/list-formulas.cjs`, so regenerate this file rather than editing it by hand.');
line();

// Formulas
line(`## Formulas (${HG.catalogue.length})`);
line();
line('`id` is the value for `formula`. `Integer` marks formulas that yield discrete integer values per step; `Period` is `yes` when the formula defines a period function, `no` otherwise.');
line();
line('| Formula id | Display name | Group | Math | Integer | Period | Param key | Label | Default | Min | Max | Step | Detents |');
line('| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |');
for (const f of HG.catalogue) {
  const common = [
    `\`${esc(f.id)}\``, esc(f.name), esc(f.category), esc(f.formula),
    f.integer ? 'yes' : 'no', f.period ? 'yes' : 'no'
  ];
  if (f.params.length === 0) {
    line(`| ${[...common, '—', '—', '—', '—', '—', '—', '—'].join(' | ')} |`);
    continue;
  }
  f.params.forEach((p, i) => {
    const idCells = i === 0 ? common : ['', '', '', '', '', ''];
    line(`| ${[...idCells,
      `\`${esc(p.key)}\``, esc(p.label), num(p.value), num(p.min), num(p.max), num(p.step),
      Array.isArray(p.detents) && p.detents.length ? p.detents.map(String).join(', ') : '—'
    ].join(' | ')} |`);
  });
}
line();

// Scales
const scaleNames = Object.keys(HG.SCALES);
line(`## Scales (${scaleNames.length})`);
line();
line('Scale names are the values accepted for the scale control. Intervals are semitone offsets from the root.');
line();
line('| Scale name | Semitone intervals |');
line('| --- | --- |');
for (const name of scaleNames) line(`| ${esc(name)} | ${HG.SCALES[name].join(', ')} |`);
line();

// Drum genres
const genreNames = Object.keys(HG.GENRES);
const lanes = HG.channel(0).lanes.slice(0, 4);
line(`## Drum genres (${genreNames.length})`);
line();
line('A genre sets the first four drum lanes, in this order: ' +
  lanes.map((l, i) => `${i + 1}. ${esc(l.name)}`).join(', ') + '. ' +
  'Each lane pattern is a Euclidean gate `[k, n, rotation]`: k hits spread across n steps, rotated by the rotation value.');
line();
line('| Genre | Lane | Hits (k) | Steps (n) | Rotation |');
line('| --- | --- | --- | --- | --- |');
for (const genre of genreNames) {
  HG.GENRES[genre].forEach(([k, n, rot], i) => {
    line(`| ${esc(genre)} | ${esc(lanes[i] ? lanes[i].name : `Lane ${i + 1}`)} | ${k} | ${n} | ${rot} |`);
  });
}
line();

// Top-level API functions
const apiFunctions = Object.keys(HG).filter(key => typeof HG[key] === 'function').sort();
line(`## Top-level API functions (${apiFunctions.length})`);
line();
line(apiFunctions.map(name => `\`${name}\``).join(', '));
line();

process.stdout.write(out.join('\n'));
