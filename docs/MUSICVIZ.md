# MUSICVIZ — the music you can see

`musicviz/` draws the level's actual music: the four cassette layers' Harmonograph functions, the
notes they play, the chord clock and each self's state. It covers MUSIC-12 ("environmental
visualisation … runes, machinery, panels and environmental patterns can make the relationship
visible"), chapter 15's four studies (Stack, Epicycles, Shape, Constellation) and chapter 18
"Musical architecture".

**It is decoration only.** Nothing here has a collider, a physics body or a path back into the
simulation. It never shows equations to the player (chapter 15 rejected that), and it is not meant
to turn every level into a literal formula plot. Use it as the requirements describe: a panel, a
frieze, a floor inscription, a showpiece. The light per-beat pulsing of props belongs to `fx/`.
This module is the structural view of the music.

Previews: `art/previews/musicviz/` (`board_*` = every canvas flat, `world_*` = mounted in a small
3D room; `warm` = upper ruins, `dark` = lower depths; scenarios below).

---

## 1. What the player sees

| Visualiser | Study | What it shows | Where it goes |
|---|---|---|---|
| **StackStrip** (`MVStackStrip`) | Stack | All four layers' continuous contours scrolling past one shared playhead, each at its own tape speed (a 2× tape's contour is twice as compressed). Played notes are lit beads with their sustain, fresh ones flash; upcoming notes are faint rings; drum hits are stems. | `wave_screen` props (screen preset: lanes, glass) and long wall friezes (frieze preset: overlaid, transparent) |
| **EpicycleHologram** (`MVEpicycleHologram`) | Epicycles | One layer's period rebuilt from its **16 strongest Fourier harmonics** as nested rotating circles. The last tip traces the curve and flashes on each note. Rosette mode (the period wrapped round a circle) or wave mode (circles on the left writing the wave to the right). | A standing hologram: the time machine and the boss room |
| **ShapeSigil** (`MVShapeSigil`) | Shape | One period wrapped into a radial rosette, re-quantised to the chord in force (chord gravity made visible). When the chord changes it is **redrawn stylus-like from twelve o'clock over 2.5 beats** while the old figure fades. Inside is the chord star (the chord's pitch classes on a 12-gon), around it the step ticks (gate steps notched deeper), and a bright point travels the figure at the layer's read position. | Floor inscription. Four of them in a row (one per cassette) are the level's **signature** |
| **Constellation** (`MVConstellation`) | Constellation | A slowly turning pitch-class helix (one turn per octave, so octaves stack vertically). Each pitched layer's last six beats of notes are lit stars joined in playing order; the chord tones stand as faint rails; drum hits ripple round the foot. | Hologram |
| **RuneSequencer** (`MVRuneSequencer`) | MUSIC-12 runes | One row of 16 rune glyphs per cassette (= 16 consecutive local steps). Glyphs light in the layer's real note rhythm and decay; a cursor walks the row at tape speed. The carved glyphs are chosen from the contour, so the row re-carves every 16 steps. Unlit glyphs stay as faint etching. | Wall strips, rune panels |

### Self states (every visualiser, the same rules — `MVTrack`)

- **Alive**: cassette colour, full width, full glow.
- **Dead (ghost this run)**: the line thins to 40 %, greys and loses its glow over one beat, and never
  recovers this run (MUSIC-08). The notes drawn are the ghost variant the audio plays (thinner
  pattern on chord tones).
- **Desynced**: the reading slips forward (full drift = 4 steps after one bar, with a waver) and
  flickers, so the drawing visibly runs out of phase with its own notes. **On resync it snaps back
  within about half a beat with a white flash.** Sigils rotate by the slip and the strip slides.
- **Reversing**: the contour is read retrograde inside its cycle, exactly as the audio does, so the
  strip's shape runs the other way, the epicycle circles spin backwards and the rune cursor walks
  right to left.
- **Stopped**: the reading freezes (the strip draws the held value).
- **Not present (empty deck)**: a faint dashed lane, a grey empty sigil ring; nothing lit.

### Themes (`MVStyle`, `MVMount.apply_theme`)

- **Warm** (upper / mid ruins, sunlit stone): every stroke gets a soft ink under-stroke, cassette
  colours are deepened slightly, surfaces are not bloom-boosted (energy capped at 1.05), and
  holograms are drawn *over* the scene (additive 0) so they read as inked light on pale stone.
- **Dark** (lower / core, rune-inscribed metal and neon): wide halos, bright cores boosted by
  `energy` (1.6–2.2) so they bloom through the WorldEnvironment glow; holograms are purely additive.

`MusicVizHub.load_level` picks the theme from `level.theme` and re-themes every mounted material.

---

## 2. Architecture

```
musicviz/
  music_viz_hub.gd        MusicVizHub (Node): owns the model, the canvases, scheduling, mounting
  mv_music.gd             MVMusic: the level's music model (layers, tracks, notes, chord clock)
  mv_layer.gd             MVLayer: one cassette's resolved formula, params, step grid, contour cache
  mv_track.gd             MVTrack: per-layer visual state (dead / desync / reverse / stop / absent)
  mv_desync_drift.gd      MVDesyncDrift: port of sequencer.ts DesyncDrift (drift per bar)
  mv_notes.gd             MVNotes: port of director.ts note compilation (pitched + drum lanes)
  mv_note.gd, mv_variant.gd
  mv_audio_notes.gd       MVAudioNotes: routes note queries to the audio module's AudioDirector
  mv_fourier.gd           MVFourier: DFT, strongest-K epicycle chain, tables, error measures (pure)
  mv_rosette.gd           MVRosette: period -> rosette, chord snapping, chord star (pure)
  mv_helix.gd             MVHelix: pitch-class helix + projection (pure)
  mv_glyphs.gd            MVGlyphs: 24 procedural runes (pure)
  mv_style.gd             MVStyle: warm / dark look, glowing strokes, dots, batched segments
  mv_viz.gd               MVViz: base drawer (Node2D) with a retained static layer
  mv_stack_strip.gd, mv_epicycle_hologram.gd, mv_shape_sigil.gd, mv_constellation.gd,
  mv_rune_sequencer.gd    the five drawers
  mv_canvas.gd            MVCanvas: a transparent SubViewport rendering one drawer on demand
  mv_mount.gd             MVMount: quads / discs / holograms / prop screens in 3D (no physics)
  shaders/mv_surface.gdshader    screens, friezes, floor inscriptions (premultiplied, unshaded)
  shaders/mv_hologram.gdshader   billboard hologram (scanlines, sweep, flicker; add <-> over)
```

**The music is the real music.** `MVLayer` mirrors `director.ts prepareLayer` and
`formulas.ts resolveFormula`: the same formula fallbacks, engine-cleaned parameters, tape-speed
time model (`local step = master beat × speed / rate`), cycle and period. The contour is
`Harmonograph.normal(formula, step, params, cycle)` from `audio/harmonograph/`. The notes are
either compiled by `MVNotes` (a faithful port of the director's `pitchedChannel` / `drumLanes` /
`compileBar` / `strumUpward`, tested note for note against `AudioDirector`) or read straight from
the audio module's `AudioDirector` (`use_audio_director`, recommended). The chord clock is
`Harmonograph.chord_at` on the level's progression.

**Precomputed per level** (`MusicVizHub.load_level` → `MVMusic.make` and each drawer's
`music_changed`): contour tables for the whole horizon at 4× tape speed, the DFT of every shown
epicycle layer (128 points, the 16 strongest harmonics kept) and its 512-point reconstruction
table, every sigil's period rosette and its re-quantised rosette for each chord of the progression.

**Drawing cost** is kept down by:
- **reduced-rate canvases**: each visualiser renders into its own SubViewport only when due (12–20
  Hz by kind, round-robin, at most 2 per frame); the texture is reused by every mount of that kind;
- **a retained static layer per drawer** (`MVViz._static_key` / `_paint_static`): rings, ticks,
  settled sigil figures, rune etching and full epicycle curves are re-recorded only when their key
  changes (a chord change, a state change, a new rune page), so each redraw pays only for what
  moves;
- **no per-point script work for contours**: the strip's polylines are slices of the cached
  contour table mapped by one affine transform (per cycle when reversing); epicycle trails are arcs
  of the cached reconstruction table; helix points are turned by one basis multiply;
- **batched marks**: note sustains, drum stems and lit glyph strokes are single `draw_multiline`
  calls; note beads and halos are one shared soft sprite each.

Measured (`tests/musicviz/test_mv_hub.gd`, headless, on the shared and heavily loaded dev machine): a
heavy set (wave screen + 2048-px frieze + signature + epicycle hologram + constellation + rune wall),
mid-level with one desynced, one reversing and one dead layer, comes to **≈ 0.8 ms of CPU per frame
in total** (update ≈ 40 µs; screen ≈ 0.15, frieze ≈ 0.23, signature ≈ 0.08, constellation ≈ 0.1,
runes ≈ 0.08, hologram ≈ 0.11 ms). A typical level (one screen, one frieze, the signature) is about
0.45 ms. `set_quality(true)` halves rates and canvas sizes. GPU cost is a few small unshaded quads.

---

## 3. API

### MusicVizHub (one per loaded level; a plain `Node`)

```gdscript
var hub := MusicVizHub.new()
parent.add_child(hub)
hub.load_level(level)                         # LevelDef: music, bpm, horizon_bars, theme
hub.use_audio_director(audio.director())      # recommended: notes from the audio module
hub.set_tracks(tracks)                        # Array[TrackAudioState], as sent to audio.set_tracks
hub.update_from_frame(frame)                  # every rendered frame (RenderFrame)
#   or hub.update(master_beat, tracks, dt)
hub.set_intensity(MusicVizHub.intensity_for_mode(frame.mode))   # MUSIC-13, see below
hub.set_quality(low)                          # low = half rate, half resolution
hub.dispose()                                 # on level unload (frees canvases)
```

Mount helpers. Each returns the created / affected `MeshInstance3D`. All coordinates are scene
units (1 tile = 1 unit, Y up, floor top at Y = 0, `RenderCtx.to_scene`); energies are the
dark-theme values and are capped automatically on warm levels.

| Call | Result |
|---|---|
| `mount_screen(model_root, energy = 1.6)` | Puts the Stack strip (screen preset, glass backdrop) on every surface of the mesh whose name starts with **`Screen`** under `model_root`. Returns `null` (and creates nothing) if there is none. |
| `mount_frieze(parent, a, b, y0, height, facing, energy = 1.7)` | A vertical quad from floor point `a` to `b` (their Y is ignored), from height `y0` for `height`, offset 0.012 off the wall, readable left-to-right from the `facing` side. |
| `mount_runes(parent, a, b, y0, height, facing, layer = -1, energy = 1.7)` | The same quad with the rune sequencer: four rows (`layer = -1`, aspect 4 : 1) or one cassette's row (`layer` 0..3, aspect 12.8 : 1). |
| `mount_sigil(parent, centre, radius, layer, energy = 1.6)` | One cassette's Shape sigil as a floor disc (0.014 above the floor top, clear of `floor_rune` tiles). |
| `mount_signature(parent, centre, spacing, radius, axis = +X)` | The four sigils in a row centred on `centre`: the level's signature. |
| `mount_hologram(parent, base, layer, size = 1.6, lift = 0.35, energy = 2.2)` | The epicycle hologram of cassette `layer` standing on floor point `base` (Y-axis billboard). |
| `mount_constellation(parent, base, size = 1.6, lift = 0.35, energy = 2.0)` | The constellation helix hologram. |
| `texture(kind, layer = -1)` / `canvas(kind, layer)` | The live `ViewportTexture` of any kind, for custom materials (kinds: `stack_screen, frieze, epicycle, epicycle_wave, sigils, sigil, constellation, runes, rune_row`). |

Diagnostics: `frame_cost_usec(fps)`, `cost_report()`, `last_update_usec`, `canvas_count()`.

### Pure maths (node-free, headless-tested)

- `MVFourier.dft(re, im)`, `strongest(hs, 16, with_dc)`, `evaluate`, `chain` (circle centres +
  tip), `trace`, `table` / `table_at` / `arc`, `rms_error`, `max_error`, `energy` (Parseval).
- `MVRosette.wrap(sig, r_in, r_out, per_step, repeats, stepped)`, `point`, `snap_to_chord`,
  `nearest_with_pcs`, `chord_star`.
- `MVHelix.point3`, `project`, `project_all`, `screen`, `strand`, `strand3`.
- `MVGlyphs.glyph(i)` (24 distinct runes), `MVLayer.contour`, `MVTrack.read_step`,
  `value_at`, `sample_values`, `MVMusic.notes_in`, `chord_at`.

---

## 4. Integration (for the integration, world and fx engineers)

Nothing outside `musicviz/` was edited. These are the exact hooks to add.

1. **Own a hub in the world view** (`world/world_view.gd`). Create it in `_ensure_nodes()` (a child
   of the view), call `hub.load_level(level)` at the end of `load_level(level, loadout)` (after
   decor is built, so mounts can find props), `hub.update_from_frame(frame)` in `render(frame)`,
   `hub.set_quality(q == &"low")` in `set_quality(q)`, and `hub.dispose()` in `_unload()`.
   Expose it, e.g. `func musicviz() -> MusicVizHub`.

2. **Feed it the cassette states** where the game feeds the audio: in `game/app.gd`
   `_push_tracks(tracks)` (and wherever `audio.set_tracks(_silent_tracks())` is sent), add
   `world.musicviz().set_tracks(tracks)`. It is the same `Array[TrackAudioState]` (present, speed,
   life, synced, transport).

3. **Share the notes with audio**: after `audio.load_level(level)` *and* `world.load_level(...)`,
   call `world.musicviz().use_audio_director(audio.director())`. If this step is skipped,
   everything still works (the hub compiles the same notes itself) but each new bar of each layer
   costs a few milliseconds once.

4. **MUSIC-13 (readability while recording)**: each frame or on mode change,
   `hub.set_intensity(MusicVizHub.intensity_for_mode(frame.mode))`: RECORD 0.55, REVIEW 0.8, IDLE /
   CINEMATIC 1.0.

5. **Wave screens** (`world/world_decor.gd`, `DecorType.WAVE_SCREEN`): after the node is built,
   `hub.mount_screen(node)`. The kit model `wave_screen.glb` already has a `Screen` object (faces +Z,
   0–1 UVs, v top→bottom) and is found automatically. The procedural stand-in (the
   `_part(g, _box(Vector3(0.86, 0.52, 0.01)…), _screen_material(...))` line) must **name that part
   `"Screen"`** for the hub to find it; its own `_screen_material` wave is then replaced. Since the
   hub loads after decor (step 1), either collect wave-screen nodes during decor build and mount them
   in `load_level`, or walk `decor_waveScreen*` nodes.

6. **Friezes and rune walls** (world builder, during dressing): choose long, unbroken, camera-facing
   wall runs (`WorldDecor.find_wall_face` / `WorldScatter.mount_on_face` give the face and its
   normal). Recommended: **one frieze per level** on the longest visible inner wall, 0.5–0.7 tall,
   its bottom about 1.0 above the floor on full-height walls (keep clear of `wall_cut` walls), and
   **rune strips** beside rune panels and doors in the lower depths (`mount_runes(..., layer = -1)`,
   about 4 : 1). `facing` = the face normal toward the camera side. Do not put them on walls the
   camera cuts away.

7. **The signature** (floor): `hub.mount_signature(parent, centre, 1.5, 0.65)` on a clear 6 × 1.5
   floor run near the spawn or the exit pad, axis along the run. They are flat decals that never
   block anything; keep them off `floor_grate` and hazard tiles so they don't read as traps.

8. **Showpieces**: the time machine (`decor_timeMachine`, about 3 × 3 tiles):
   `hub.mount_hologram(parent, tm_pos, layer, 1.4, 0.95)` places the hologram inside the gimbal
   rings (pick the melody layer, or the boss's signature layer). The boss room: a larger
   `mount_hologram(..., size = 2.4)` behind the arena plus `mount_constellation` on the far side.
   Both are billboards: put them where the camera sees them face-on and nothing walks through them
   visually.

9. **Rune glyph sheet (optional)**: if `res://assets/textures/decals/rune_glyphs.png` exists
   (white glyphs on transparent, an 8 × 4 grid read left to right, top to bottom), the rune
   sequencer uses it automatically. Otherwise it draws its 24 procedural runes. None exists today.

**Rules for anyone mounting**: no `CollisionObject3D` / `CollisionShape3D` ever goes under a
musicviz mount (a test checks this). Mount through the hub so warm / dark theming and intensity
apply. Do not read any musicviz value from gameplay code.

---

## 5. Verification

- `bash tools/gd test musicviz`: 35 tests, three suites.
  - `test_mv_geometry.gd`: full DFT reconstruction (exact to float rounding), Parseval, residual
    error = discarded energy and non-increasing with K, 16 harmonics exact on a band-limited curve,
    largest-first chain and closure, sandbox epicycle error bounds (16-harmonic RMS 0.0–0.12 of a
    unit curve) and determinism, rosette closure / radius / interpolation, chord snapping, helix
    octave stacking and batch projection, distinct rune glyphs.
  - `test_mv_music.gd`: layer resolution like the director, speed-scaled step grid, contour cache =
    engine, deterministic in-range notes, faster tape = denser, absent layer silent, chord clock,
    retrograde reading, desync drift grows then snaps back, dead layer thins / greys / stays dead,
    stop freezes, restart resets, batch sampling = point sampling in every state, step-curve =
    table, the strip's polylines follow the reading in every transport × desync state.
  - `test_mv_hub.gd`: every kind builds and renders, mounts are plain meshes without physics, the
    static layer re-records only on change, reload re-points, the **budget**, MUSIC-13 intensity
    and theme switching, `set_tracks` + `update_from_frame`, and **AudioDirector parity** (every
    layer × six variants × two bars: onsets, pitches, velocities, durations equal).
- `bash tools/gd shot res://tools/shot_musicviz.gd <out_dir>` renders the sandbox level's music:
  `intro` (beat 2: A, B recorded; C, D empty), `states` (beat 9.4: B desynced, C reversing, D dead),
  `resync` (beat 13.12: B just resynced, mid-snap), `chord` (beat 24.7: all alive, sigils
  mid-redraw), on warm and dark, as flat boards and mounted in a 3D room (kit `wave_screen` model
  when present).

## 6. Known gaps

- Not wired into the game yet (section 4 is the integration list).
- Without `use_audio_director`, a layer's first draw of each new bar compiles its notes (measured
  2–7 ms for one layer-bar on this machine). The hub prefetches one layer-bar per frame 8 beats
  ahead to keep that out of drawing, but it is still a spike. With the director routed, the audio
  has already paid for it.
- A desynced strip slides as one piece at the current phase offset (the waver moves in time, not
  along the strip). This is deliberate and cheaper; the notes stay at their true positions, so the
  mismatch reads.
- Timings were measured headless on a heavily shared machine, so absolute numbers are noisy.
  `frame_cost_usec()` / `cost_report()` give live figures in game.
- No rune glyph sheet exists yet (procedural runes are used); no dedicated frieze / signature
  placement data in the level format: placement is left to the world builder's dressing rules.
