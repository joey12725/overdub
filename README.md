<img src="assets/icon.svg" width="64" height="64" alt="">

# OVERDUB

An isometric action-puzzle game. You record Moxie's run on up to four cassettes, one take at a
time; every earlier take plays back beside you, at the tape speed and end mode you chose for it,
on one shared timeline set to the level's music. A level is solved when the copies of Moxie,
together, do what one of her could not.

The game is a **Godot 4.4.1** project (GDScript, Forward+) at the repo root. `prototype/` is the
earlier TypeScript build: it does not ship, but it is the executable reference for the rules, and
the simulation in `core/` is a port of it that must agree with it tick for tick.

## Run

Open the folder in Godot 4.4.1 and press Play, or:

```
godot --path .                      # the game (main scene res://game/main.tscn)
# tools/gd finds godot_console.exe / godot4 / godot on PATH; otherwise set GODOT=/path/to/godot
bash tools/gd import                # refresh the import cache after adding or changing assets
```

On the development machine Godot lives at `C:\Users\joeya\.t3\tools\godot\`, and every headless run
goes through `tools/gd`, which serialises access to the shared `.godot/` cache:

```
bash tools/gd test [filter]         # import, then run the suites whose path contains <filter>
bash tools/gd script res://x.gd     # run a SceneTree script headless
bash tools/gd shot res://x.gd       # run it windowed (needs a GPU) - for screenshots
bash tools/mem                      # memory use in percent; check before anything heavy
```

`tools/mem` also warns when exited processes are still being held in memory. When it does, waiting
does not help and polling makes it worse: reboot first.

## Controls

| Action | Keyboard and mouse | Gamepad |
|---|---|---|
| Move | W A S D or arrows | Left stick |
| Aim | Mouse | Right stick |
| Light attack | Left click | X or RT |
| Heavy attack | Right click | Y or LT |
| Dodge | Space | A |
| Use / interact | E | B |
| Ranged weapon | Q or F | RB |
| Ability | Shift | LB |
| Pause | Esc or P | Start |
| Setup: tape speed down / up | Q / E | LB / RB |
| Setup: cycle end mode | Tab | Y |
| After a take: retry | R | X |
| After a take: commit | C | — |
| End the attempt | Backspace or Delete | B |
| Reset all tapes (hold) | Backspace or Delete | Back + Y |
| Skip the cinematic (hold) | Enter, Space or Esc | A, B or Start |
| Menus | Arrows or W A S D, Enter or Space, Esc | D-pad, A, B |

The source of truth is `game/input.gd`. Settings include an option to press twice instead of
holding for "reset all".

## Tests

```
bash tools/gd test                  # every Godot suite under tests/
bash tools/gd test acceptance       # the requirement-by-requirement suite (docs/ACCEPTANCE.md)
bash tools/gd test levels           # all twelve levels replayed from their stored solutions
cd prototype && npx vitest run      # the prototype's suite (the rules reference)
```

The runner fails a test on any script error logged while it ran. `tests/goldens/` holds scenarios
exported from the prototype that the Godot simulation must reproduce exactly.

Playing the real game through automation and saving screenshots (windowed, a fresh save in the
output folder, never the player's):

```
bash tools/gd shot res://tools/smoke.gd -- <output dir>
bash tools/gd shot res://tools/shot_world.gd -- <output dir> levels    # every level's solution
bash tools/gd shot res://tools/shot_hud.gd -- <output dir>
bash tools/gd shot res://tools/shot_menus.gd -- <output dir>
bash tools/gd shot res://tools/shot_actors.gd -- <output dir>
```

## Layout

```
core/            deterministic simulation: no nodes, no clock, no randomness
content/         loaders for data/, loadout resolution, level validation
data/            levels and their solutions, gear, story, music, codex, accessibility data
game/            session state machine, input, save, campaign, and app.gd, which wires everything
game/contracts/  the small base classes each module implements
world/           level construction from the kit, camera, lighting, decals, music displays
actors/          Moxie, the robots, projectiles, cassette identity
feel/  fx/       hit feel; particles and music-linked effects
cinema/          the director that plans the winning replay's shots
musicviz/        music displays mounted in the world
audio/           the synthesiser, the music director, quantised effects, voice
replay/          kept winning performances
ui/              HUD, menus, dialogue, coach marks, widgets, theme
assets/          what the game loads: models, textures, audio, portraits, UI art
art/             sources and build scripts for everything in assets/ (Godot ignores this folder)
tests/  tools/   suites and goldens; dev scripts
docs/            design and module documents
prototype/       the TypeScript reference build
```

Start with `docs/GODOT-PORT.md` (layout, conventions, module facades, asset contract) and
`docs/ARCHITECTURE.md` (the design and its rules). `docs/requirements.txt` is the creator's list;
`docs/ACCEPTANCE.md` maps each requirement to its test; `docs/DECISIONS.md` records open questions.
Module documents: `docs/TRAPS.md`, `COMBAT-FEEL.md`, `CINEMATIC.md`, `DIALOGUE.md`, `WIDGETS.md`,
`MUSICVIZ.md`, `MUSIC.md`, `ONBOARDING.md`, `CODEX.md`, `WARDROBE.md`, `ACCESSIBILITY.md`,
`VOICE-CAST.md`, and `ui/README.md` for the hooks the UI exposes to the game.

## Rebuilding assets

Everything in `assets/` is produced by a script under `art/`; edit the source and rebuild, never the
output. Blender is 4.5: `blender --background --python art/<script>.py -- <args>`.

| Output | Rebuild with |
|---|---|
| Robots, kit, traps, weapons, headgear (`assets/models/`) | the Blender scripts in `art/enemies/`, `art/kit/`, `art/traps/`, `art/weapons/`, `art/wardrobe/` |
| Moxie (`assets/models/moxie.glb`) | the numbered steps in `art/moxie_e/` (see its README); outfit masks with `python tools/moxie_regions.py` |
| Animation library (`assets/anim/`) | `art/anim/build.py`, then `assets/anim/library/build_library.gd` |
| Samples (`assets/audio/`) | `python -I art/audio/make_samples.py [family ...]`, check with `art/audio/analyze.py` |
| Voice (`assets/audio/voice/elevenlabs/`) | `art/voice_el/` — paid and not repeatable; do not regenerate casually |
| Textures, portraits, UI art, icons | the `process.py` / `build_*.py` scripts in `art/world_art/`, `art/portraits/`, `art/ui_art/`, `art/icons/`, reading the generator output kept in each `raw/` folder |
| Level music | `python art/music/merge.py` merges `data/music/` into `data/levels/` |
| Level index, solutions, goldens | `cd prototype && npx vite-node scripts/level.ts index --write`, `level.ts run NN --write`, `scripts/export-goldens.ts` |
| Bus layout | `bash tools/gd script res://audio/tools/make_bus_layout.gd` |

After any rebuild run `bash tools/gd import`. The `raw/` folders and `art/voice_el/takes/` are kept
in the repo because they cannot be regenerated identically; `work/`, download and preview folders
are ignored (`.gitignore`).

## Credits and licences

`assets/LICENSES.md` is the index of every asset's source and terms. Read its first section before
distributing a build: **Moxie's mesh was generated with Tencent Hunyuan3D-2, whose licence forbids
distribution in the EU, the UK and South Korea**, and the commercial licence of the ElevenLabs voice
files is unconfirmed. Fonts: Inter (SIL OFL 1.1) and DejaVu Sans Mono (Bitstream Vera licence), in
`ui/theme/fonts/`.

Created in [T3 Code](https://t3.codes).
