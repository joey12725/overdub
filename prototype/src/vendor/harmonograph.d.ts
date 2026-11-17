// The vendored Harmonograph engine (harmonograph.js) is a UMD bundle with no ES exports: when
// evaluated it assigns its API to `globalThis.HG` (and to `module.exports` under CommonJS).
// Import it only for that side effect:
//
//     import '../vendor/harmonograph.js';
//
// and read the API through the typed wrapper in src/audio/hg.ts, which describes the subset of the
// engine OVERDUB relies on. Declaring a default export here would type-check but fail at runtime,
// because the file never exports one.
export {};
