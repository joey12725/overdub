# OVERDUB — asset licences and credits

What ships in `assets/` (and the fonts in `ui/theme/fonts/`), where it came from, and what must be
settled before the game is distributed. Folder-level files carry the detail; this file is the index.

## Read first: three things that block or limit distribution

1. **Moxie's mesh was generated with Tencent Hunyuan3D-2 — it may not be distributed in the EU, the
   UK or South Korea.**
   `assets/models/moxie.glb` (the shipping player model, promoted from candidate E) uses geometry
   generated locally with **Hunyuan3D-2mv** under the **Tencent Hunyuan 3D 2.0 Community License**.
   Section 6(d) of that licence claims no rights in outputs, but section 5(c) forbids using or
   distributing the model's output outside its "Territory", which excludes the European Union, the
   United Kingdom and South Korea; section 5(b) forbids using outputs to improve other AI models.
   As written, a build containing this mesh cannot be sold or given away in those regions.
   The creator must choose before release: (a) regenerate the shape with a generator whose terms
   allow worldwide distribution (the pipeline in `art/moxie_e/` takes any mesh registered to the
   model sheets), or (b) restrict distribution to the licence's Territory.
   Full detail: `assets/models/candidates/e/LICENSES.md`. Her textures are baked from the creator's
   own concept art through the project's image model and are not affected.
2. **The voice files' commercial licence is unconfirmed.** Everything under
   `assets/audio/voice/elevenlabs/` was generated with ElevenLabs stock voices. ElevenLabs grants
   commercial use only on a paid plan; the plan of the account used could not be read. Check the
   plan before release (docs/VOICE-CAST.md section 7). Suggested credit: "Voices generated with
   ElevenLabs."
3. **Unused Moxie candidates carry third-party sources.** `assets/models/candidates/` (not loaded
   by the game) and the download folders under `art/moxie_a`, `art/moxie_c` and `art/moxie_d`
   include third-party avatar and animation files with their own terms. Do not ship the
   `candidates/` folder in an export; see each candidate's `LICENSES.md`.

## By folder

| Folder | What | Source | Terms |
|---|---|---|---|
| `models/moxie.glb`, `models/moxie_*.png`, `models/moxie_regions*` | The player model, her body and head textures, outfit zone masks | Mesh: Hunyuan3D-2mv output, cleaned, decimated, rigged and re-textured in Blender (`art/moxie_e/`). Textures: baked from the project's model sheets (`docs/reference/generated/`), which were made from the creator's concept art with the project image model. Zone masks: `tools/moxie_regions.py`. | **Tencent Hunyuan 3D 2.0 Community License on the mesh — see item 1 above.** Rig bone names follow Godot's SkeletonProfileHumanoid (MIT). |
| `anim/moxie_anims.res`, `anim/library/` | Moxie's animation library | Built by the scripts in `art/anim/` and `assets/anim/library/build_library.gd`. The candidate clip sets under `anim/candidates/` were retargeted from the Universal Animation Library by Quaternius. | Own work; Universal Animation Library is CC0 1.0. The origin of `anim/library/mannequin.glb` was not re-checked for this file — confirm with `art/anim/` before release. |
| `models/enemies/`, `models/kit/` | The seven robots, the environment kit, mechanisms and traps | Original models built by the Blender Python scripts in `art/enemies/`, `art/kit/` and `art/traps/` | Own work; nothing downloaded |
| `models/weapons/`, `models/projectiles/` | Melee and ranged weapons, projectiles | Original models from `art/weapons/` | Own work — `models/weapons/LICENSES.md`, `models/projectiles/LICENSES.md` |
| `models/wardrobe/` | Headgear models and wardrobe data | Built by `art/wardrobe/` | Own work |
| `models/candidates/` | Moxie candidates that were not chosen | See each folder | `candidates/c/LICENSES.md`, `candidates/e/LICENSES.md`; not for shipping (item 3) |
| `textures/` | Graffiti, decals, rune glyphs, backdrops, tape art, patterns, wardrobe textures | Generated with the project image model (gpt-image, through `tools/img`) from prompts in `art/world_art/jobs.py` and the other `art/` scripts, then processed locally | Output of the project's own image-model account, used under that provider's terms; `textures/README.md` lists every file |
| `portraits/` | Twenty dialogue portraits | Generated with the project image model from the creator's Moxie references (`art/portraits/`) | As above; `portraits/README.md` |
| `ui/`, `codex/`, `icon.svg` | Key art, logo, chapter and ending cards, icons, panels, Field Guide plates | Generated with the project image model and processed by `art/ui_art/`, `art/icons/`; the logo and nine-slices are built by script | As above |
| `audio/inst/`, `audio/drums/`, `audio/blip/`, `audio/sfx/`, `audio/ui/`, `audio/voice/count_*` | Instrument, drum, effect and UI samples; the synthesised count-in words | Synthesised by `art/audio/make_samples.py` (no recordings, no sample packs) | Own work; `audio/README.md` |
| `audio/voice/elevenlabs/` | Dialogue, barks, count-in words, deck calls, efforts | ElevenLabs stock voices, processed by `art/voice_el/` | **Unconfirmed — see item 2 above** |
| `audio/voice/count/`, `audio/voice/efforts/`, `audio/voice/voice_bank.gd` | The synthesised voice bank | `art/voice/build_voice.py` | Own work (not re-checked for this file) |
| `ui/theme/fonts/` (outside `assets/`) | Inter, DejaVu Sans Mono | Copied from the Blender 4.5 distribution | Inter: SIL Open Font License 1.1 (`OFL-1.1.txt`). DejaVu Sans Mono: Bitstream Vera and Arev licences (`Bitstream-Vera.txt`, `Arev-Fonts.txt`). The licence texts must ship with the game. |

Music is data, not audio files: the score in `data/music/` and `data/levels/` was written for this
game and is played by the synthesiser in `audio/`.

## Tools (nothing of theirs ships)

Godot 4.4.1 (MIT), Blender 4.5 (GPL; its output is unencumbered), Python, Node. The prototype under
`prototype/` has its own `package.json` dependencies and does not ship with the Godot build.

## Before release

- Decide the Hunyuan question (item 1) and record the decision here.
- Confirm the ElevenLabs plan (item 2) and add the credit line to the credits screen.
- Exclude `assets/models/candidates/` and `assets/anim/candidates/` from the export preset.
- Ship `ui/theme/fonts/OFL-1.1.txt`, `Bitstream-Vera.txt` and `Arev-Fonts.txt` with the build.
- Re-read the image-model provider's current terms for commercial use of generated images.
