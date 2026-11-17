# Wardrobe — equipped gear shows on Moxie

Requirements: Revision 2 APPAREL-01..03 and chapter 17. Helmets, tops, pants and shoes are four
gameplay slots; what is equipped is visible on the character, and she stays Moxie in every
combination: yellow headphones, belt Walkman, scrappy pigtails, crop top, low-rise silhouette.

Two mechanisms, chosen so the wardrobe works on whichever Moxie model wins the rebuild:

| Slot | How it shows | Why |
|---|---|---|
| helmet | a separate rigid model on the `Head` bone that sits *with* the headphones | independent of the body mesh; never hides the headphones |
| top, pants, shoes | a **look** of the base outfit: colours per outfit material, an optional tiling pattern, optional decals | no new meshes, so the silhouette (crop top, low rise) cannot change |

Nothing in the wardrobe ever touches a material outside `top*`, `jacket*`, `pants*`, `shoes*`, so
headphones, Walkman, hair, skin, face paint, belt and tools are constant by construction.

## Files

| Path | What |
|---|---|
| `data/wardrobe.json` | the data: item id -> `{ slot, attach \| look, palette, concept }`, plus fit and naming tables. **Generated** — edit `art/wardrobe/spec.py`, run `build_data.py` |
| `assets/models/wardrobe/<id>.glb` | the six headgear models |
| `assets/models/wardrobe/wardrobe.gd` | `class_name Wardrobe` — the static runtime API (no dependency on the actor layer) |
| `assets/models/wardrobe/wardrobe_look.gdshader` | reference shader for a look (flat colour + pattern); the block marked `WARDROBE PATTERN` is what the actor shader needs |
| `assets/textures/wardrobe/pattern_<id>.png` | ten 512 px seamless greyscale pattern masks (white = paint the look's pattern colour) |
| `assets/textures/wardrobe/decal_<id>.png` | five 512 px RGBA decals (white graphic, alpha = coverage; tinted in game) |
| `assets/textures/wardrobe/concepts/<id>.png` | half-size copies of the concept sheets, loadable by the loadout screen |
| `docs/reference/generated/wardrobe/<id>.png` | full-size concept sheet per item (26) and `mix_*.png` full-outfit mixes (6) |
| `art/wardrobe/spec.py` | single source of truth: items, colours, prompts, patterns, decals, mixes, the measured head |
| `art/wardrobe/build_headgear.py`, `hlib.py` | Blender: builds the six glbs and fit renders |
| `art/wardrobe/concepts.py` | image model: concept sheets, pattern and decal sources, mixes |
| `art/wardrobe/textures.py` | makes the pattern sources exactly seamless, cuts the decals, writes 3x3 tiling previews |
| `art/wardrobe/build_data.py` | writes `data/wardrobe.json`, copies concept sheets into `assets/` |
| `art/wardrobe/measure_head.py` | measures a Moxie glb's head (outside Blender) for the fit |
| `art/wardrobe/check_wardrobe.gd` | headless Godot verification (exits non-zero on failure) |
| `art/wardrobe/shot_wardrobe.gd` | windowed Godot preview at the game's isometric angle |
| `art/wardrobe/sheets.py` | contact sheets for review |
| `art/previews/wardrobe/` | every preview (git-ignored) |

## Headgear

Each is one mesh object `Headgear`, bevelled hard-surface or cloth forms, flat base-colour
materials (no textures, no UVs needed), `helmet_glow` emissive. Material names: `helmet` (the
item's main colour), `helmet_trim`, `helmet_dark`, `helmet_metal`, `helmet_steel`,
`helmet_accent` (Moxie yellow), `helmet_accent2` (magenta), `helmet_paper`, `helmet_copper`,
`helmet_lens`, `helmet_glow`.

**Authoring space.** Godot axes, +Y up, +Z Moxie's front, +X her left, **origin at the Head
bone's joint** (top of the neck), 1 unit = 1 tile. `attach.offset` is `[0, 0, 0]` and
`attach.scale` 1.0 for every item: the fit is already in the vertices.

| id | name | anchor | tris | bounds from the Head joint | how it sits with the headphones |
|---|---|---|---|---|---|
| `scrap_cap` | Scrap Cap | brow | 1796 | y 0.116..0.243, x ±0.119, z -0.017..0.207 | five-panel cap whose whole back is cut away; front crown and brim end in front of the band, side tabs tuck under the cups |
| `hush_hood` | Hush Hood | neck | 2388 | y -0.231..0.165, x ±0.166, z -0.190..0.093 | hood pushed back: a quilted foam roll round the neck and a cowl lip behind the head below the pigtails; head and headphones uncovered |
| `feedback_crown` | Feedback Crown | brow | 2460 | y 0.168..0.297, x ±0.113, z 0.022..0.134 | tiara of five blown tweeters across the brow, in front of the band |
| `click_visor` | Click-Track Visor | brow | 1564 | y 0.115..0.270, x ±0.134, z 0.021..0.221 | sun-visor on the brow under the band, metronome arm, four beat lights |
| `prism_goggles` | Prism Goggles | brow | 2220 | y 0.118..0.246, x ±0.114, z -0.027..0.150 | goggles pushed up on the forehead; strap runs back under the cups |
| `rabbit_ears` | Rabbit-Ear Aerials | cups | 1442 | y 0.057..0.474, x ±0.304, z -0.139..0.028 | two telescoping aerials zip-tied to the outside of the ear cups |

### Head fit

The gear is modelled against the Moxie currently in the game, `assets/models/moxie.glb` (the
interim humanoid). Its head, measured by `measure_head.py` relative to the Head joint
(`spec.HEAD`, copied into `data/wardrobe.json` `head_fit`):

| | value |
|---|---|
| Head joint in model space | (0, 1.395, -0.006) |
| skull centre / radii | (0, 0.110, 0.004) / (0.090, 0.097, 0.100) |
| hair over the skull | 0.018 at the brow, 0.022 at the crown; fringe reaches z 0.120 |
| headphones box | (-0.129, 0.035, -0.052) .. (0.129, 0.227, 0.043); band top y 0.227 |
| ear cup | centre (±0.111, 0.083, -0.005), radius 0.047 |

At run time `Wardrobe.head_fit(skeleton, meshes, model_path)` returns `{ offset, scale,
brow_push, source }` for the model actually loaded, in this order:

1. `head_fit.models["res://…/moxie.glb"] = { "offset": [x,y,z], "scale": s, "brow_push": z }` in
   the data — an explicit, hand-nudged fit (set it in `build_data.py`, which writes the file).
2. **headphones** — the model's materials named `headphones*`, `phones*` or `hp_*` are measured;
   cup-to-cup width gives the scale, band top and centre give the offset. Gear follows the
   headphones wherever the modeller put them.
3. **skin** — no named headphones: the width and top of the head's `skin*` vertices.
4. the reference fit unchanged.

`brow_push` moves the four brow items forward when the model's fringe stands further out than
the reference fringe would. Measured fits today:

| model | source | scale | offset |
|---|---|---|---|
| `assets/models/moxie.glb` | headphones | 1.003 | ~0 |
| `candidates/a` | headphones | 1.128 | (0, 0.003, -0.017), brow push 0.020 |
| `candidates/b` | headphones | 1.161 | (0, 0.005, -0.015), brow push 0.049 |
| `candidates/c` (textured, no headphone materials) | skin | 0.751 | (0, 0.005, 0) |
| `candidates/e` (two materials `body`, `head`) | reference | 1.0 | 0 — needs an explicit `models` entry if it wins |

When the final model lands: run `measure_head.py`, put the numbers in `spec.HEAD`, rebuild
(`build_headgear.py`, `build_data.py`), look at `_sheet_a/_b.png` and the Godot `fit_*` pages.
If it is only slightly different nothing needs rebuilding — the run-time fit absorbs it.

## Looks (tops, pants, shoes)

A look is `{ colors, pattern?, decals? }`.

**Colours** are keyed by outfit material name: `top`, `top_trim`, `jacket`, `jacket_lining`,
`jacket_trim`, `pants`, `pants_graphic`, `pants_trim`, `shoes`, `shoes_sole`, `shoes_lace`,
`shoes_trim`. A model's material is matched to a key by `Wardrobe.match_key`:
exact name -> alias (`aliases` in the data, e.g. `lace` -> `shoes_lace`, `pants_olive` -> `pants`,
`jacket_dark` -> `jacket`) -> the role of its last word (`suffix_roles`, e.g. `jacket_rib` ->
`jacket_trim`, `pants_cuff` -> `pants_trim`) -> longest `_` prefix. A material that matches
nothing keeps the model's own colour. Checked against the current model and candidates a, b, c:
every `top*/jacket*/pants*/shoes*` material resolves, nothing else is touched.

**Pattern**: `{ texture, region, color, strength, scale }`. The texture is a seamless grey mask;
`final = mix(base, color, mask * strength)` on the material that resolves to `region` (and its
unnamed sub-parts, never another keyed material such as the lining). The base models have no
UVs to rely on, so the reference shader projects the mask as a **screen tone** pinned to the
character's origin (`scale` = repeats per metre; it travels with her, it does not swim).

**Decals**: `{ texture, place, color, opacity }`; the only place is `jacket_back`. They are
alpha-scissor cards on a `BoneAttachment3D` of `UpperChest` (then `Chest`), placed on the
measured rearmost surface of the `jacket*` materials.

| id | slot | colours | pattern | decal |
|---|---|---|---|---|
| `lined_bomber` | top | top `#eadfcc`, trim `#2e292b`, jacket `#3a3033`, lining `#e9a81c` | – | `bomber_star` `#e9a81c` |
| `ballast_puffer` | top | top `#2e292b`, trim `#c9c2a8`, jacket `#5d6b3a`, lining `#f08a24` | `quilt` on jacket `#3f4a26` | – |
| `razor_mesh` | top | top `#1a1a1f`, trim `#c9cdd6`, jacket `#26232b`, lining `#b3204c` | `mesh` on top `#c9cdd6` | – |
| `sub_vest` | top | top `#44444f`, trim `#ff4fa3`, jacket `#2f2f38`, lining `#ffd23f` | `grille` on jacket `#15151b` | `sub_cone` `#ffd23f` |
| `patchcord_hoodie` | top | top `#f2efe6`, trim `#ff7a2f`, jacket `#3ec5ff`, lining `#1f3f66` | – | `patch_jacks` `#f2efe6` |
| `dropout_jacket` | top | top `#1f1b2b`, trim `#7fe7ff`, jacket `#8a5cff`, lining `#6b4630` | `dropout` on jacket `#3a2380` | `skip_glyph` `#7fe7ff` |
| `mirrorball_vest` | top | top `#2b2f3a`, trim `#7fe7ff`, jacket `#d8dbe6`, lining `#ff4fa3` | `mirror` on jacket `#7d86a8` | – |
| `encore_tee` | top | top `#ff4d6d`, trim `#f2efe6`, jacket `#4a2530`, lining `#ffd23f` | – | `tour_print` `#f2c9b8` (60%) |
| `olive_cargos` | pants | pants `#5f5b3e`, graphic `#f0b21c` | – | – |
| `snap_trackies` | pants | pants `#2b2f6b`, graphic `#f2efe6` | `snaps` `#f2efe6` | – |
| `flywheel_cargos` | pants | pants `#6e5a3a`, graphic `#d98a4a` | `canvas` `#4d3d25` | – |
| `kneepad_joggers` | pants | pants `#3a3a40`, graphic `#ff4d6d` | – | – |
| `parachute_pants` | pants | pants `#b14cff`, graphic `#7dff6b` | `ripstop` `#7a2fc0` | – |
| `bandolier_cargos` | pants | pants `#4d4a2e`, graphic `#ff7a2f` | `camo` `#2f2e1c` | – |
| `beater_hightops` | shoes | shoes `#cdbca4`, sole `#eae0ce`, lace `#f5b819` | – | – |
| `slick_sliders` | shoes | shoes `#ffd23f`, sole `#1c1a21`, lace `#f2efe6` | – | – |
| `anvil_platforms` | shoes | shoes `#3d3d46`, sole `#8b90a0`, lace `#ff4fa3` | – | – |
| `static_runners` | shoes | shoes `#3ec5ff`, sole `#f2efe6`, lace `#1c1a21` | `static` `#eaffff` | – |
| `spring_soles` | shoes | shoes `#7dff6b`, sole `#c9cdd6`, lace `#25212b` | – | – |
| `grip_sprinters` | shoes | shoes `#ff7a2f`, sole `#25212b`, lace `#ffd23f` | – | – |

`*_trim` colours are derived (a darker or lighter shade of the main colour) and are in the data.
Every item also carries `palette: { base, trim, accent }` — three swatches for UI.

The three baseline items (`lined_bomber`, `olive_cargos`, `beater_hightops`) are her signature
outfit; equipping them reproduces the reference colours.

What a look cannot show, by design (no new meshes): knee pads, coil springs, platform soles,
puffer volume, bandoliers. Those live in the concept sheets as targets; if the modellers add
optional sub-meshes later (e.g. a `shoes_platform` object), a look can grow a `show` list.

### Looks on a textured body (the shipping model)

The shipping `assets/models/moxie.glb` has two materials, `body` and `head`, each one painted
texture, so there are no `top` / `jacket` / `pants` / `shoes` materials to recolour. Looks are
applied with **region masks** instead:

- `tools/moxie_regions.py` (run with `python -I tools/moxie_regions.py [preview_dir]` whenever the
  model or its albedo changes) rasterises every body triangle in UV space, so each texel knows
  where it sits on the rest-pose body, and classifies it by position and colour into six zones:
  `top` (the white crop top), `jacket` (the dark shell), `jacket_lining` (its yellow lining and
  trim), `pants` (the khaki cloth, not the belt gear or the skin showing through the tears),
  `pants_graphic` (the yellow zigzags) and `shoes`. It writes `assets/models/moxie_regions_a.png`
  (R top, G jacket, B lining), `moxie_regions_b.png` (R pants, G graphic, B shoes) and
  `moxie_regions.json` (mean linear colour and luminance of each zone's paint).
- `MoxieModel.outfit_zones(item_ids)` asks `Wardrobe.tints_for` for those six names and hands the
  colours to the body shader (`actors/shaders/actor_body.gdshaderinc`, `od_zones`), which redraws
  a zone as `tint * (texel luminance / zone luminance)`: folds, seams, pocket lines and the painted
  cel shading survive the recolour.
- Items of the catalogue's **base loadout** recolour nothing: the painted model is that outfit.
- Not carried on this model: `top_trim`, `pants_trim`, `shoes_sole` / `shoes_lace` (the zone takes
  the item's main colour), **patterns** and **decals**. Shape changes were never possible.
- Headgear needs no masks. Brow gear (cap, crown, visor, goggles) is tipped back and lifted a
  little on this head by `MoxieModel.seat_headgear`, because a level brim covers her whole face
  from the gameplay camera. Her headphones are part of the head texture and stay visible beside
  every piece; the cassette-coloured glow rings sit on the ear cups.

## Concept sheets

`docs/reference/generated/wardrobe/<id>.png` — one per item, image-model output guided by the
approved Moxie art:

- headgear: the item alone from three angles + Moxie wearing it with her headphones;
- tops / pants / shoes: Moxie front and back wearing the variant, the rest of the outfit baseline;
- `mix_baseline, mix_loud, mix_stealth, mix_signal, mix_clash, mix_tempo`: six full loadouts
  (one item per slot, every headgear once) to check she is recognisable in any combination.
  She is: in all six the headphones, Walkman, pigtails, face paint, bare midriff and low-rise
  baggy silhouette read first; the same six are rendered on the 3D model in
  `art/previews/wardrobe/godot_*_mixes.png`.

`Wardrobe.concept_path(id)` gives the in-game copy (`res://assets/textures/wardrobe/concepts/`).

Prompting notes (kept in `concepts.py`): pass R01 + R02 for headgear; for looks pass only the
clean front/back model sheets and put the garment first in a short prompt — with the R02 line-up
as an input, or a long identity-first prompt, the model redraws the reference and ignores the
garment. `encore_tee` contains lettering ("ENCORE") on the sheet; the in-game decal has none.

## Runtime API (`Wardrobe`, all static)

```gdscript
Wardrobe.has_item(id) -> bool            Wardrobe.slot_of(id) -> String
Wardrobe.palette(id) -> { base, trim, accent: Color }
Wardrobe.concept_path(id) -> String
Wardrobe.material_names(meshes) -> Array[StringName]
Wardrobe.tints_for(item_ids, material_names) -> Dictionary[StringName, Color]
Wardrobe.pattern_for(item_ids, material_name) -> { texture, color, strength, scale, id } or {}
Wardrobe.decals_for(item_ids) -> Array[Dictionary]
Wardrobe.attach_decals(skeleton, item_ids, make_material := Callable(), meshes := []) -> Array[Node3D]
Wardrobe.clear_decals(skeleton)
Wardrobe.head_fit(skeleton, meshes, model_path := "") -> { offset, scale, brow_push, source }
Wardrobe.attach_headgear(skeleton, item_id, fit := {}) -> BoneAttachment3D   # child "Headgear"
Wardrobe.clear_headgear(skeleton)
Wardrobe.measure_place("jacket_back", skeleton, meshes) -> Vector3 or null
```

`art/wardrobe/shot_wardrobe.gd` (`_figure`, `_paint`) is a complete worked example of dressing a
model with these calls.

## Integration steps (actor engineer)

Already wired in `actors/self_view.gd` (seen while resuming): `Wardrobe.tints_for` feeds
`ActorRig.apply_materials`, and `Wardrobe.attach_headgear(sk, helmet_id, Wardrobe.head_fit(...))`
puts the headgear on the head and adopts it into the rig. Still to do:

1. **Patterns.** Copy the block between the `WARDROBE PATTERN` rules of
   `assets/models/wardrobe/wardrobe_look.gdshader` into `actors/shaders/actor_body_fx.gdshader`
   (five uniforms, one varying, `pattern_anchor_of`, `pattern_mix`), set
   `pattern_anchor = pattern_anchor_of(PROJECTION_MATRIX, VIEW_MATRIX, NODE_POSITION_WORLD)` in
   `vertex()` and wrap the base colour with `pattern_mix(base, UV, SCREEN_UV, VIEWPORT_SIZE)` in
   `fragment()`. Then in `ActorRig.apply_materials`, per surface:
   ```gdscript
   var pat := Wardrobe.pattern_for(item_ids, mat_name)
   if not pat.is_empty():
       m.set_shader_parameter(&"pattern_tex", pat.texture)
       m.set_shader_parameter(&"pattern_col", pat.color)
       m.set_shader_parameter(&"pattern_amt", pat.strength)
       m.set_shader_parameter(&"pattern_scale", pat.scale)
   ```
   and keep `pattern_px_per_m` = viewport height in pixels / orthographic camera size up to date
   (once per frame or on resize). `pattern_amt` defaults to 0, so unpatterned materials cost
   nothing. Echo selves can use the same pattern; drop it for x-ray/ghost passes if it is noisy.
2. **Decals.** After `apply_materials`, call
   `Wardrobe.attach_decals(sk, item_ids, make_mat, body_meshes)` and `rig.adopt()` each returned
   node. `make_mat` is `func(tex, color, opacity) -> Material`; return the actor toon material
   with alpha scissor so the print takes the toon ramp and the self's outline rules (the default
   is a plain unshaded card).
3. **Loadout change.** On re-equip: `Wardrobe.clear_headgear(sk)`, `Wardrobe.clear_decals(sk)`,
   then repeat the calls above.
4. **Loadout screen.** `Wardrobe.concept_path(id)` for the item picture, `Wardrobe.palette(id)`
   for swatches; `data/wardrobe.json` `mixes` lists six showcase loadouts.
5. **Textured outfit materials.** `apply_materials` replaces the colour outright and drops the
   texture when a tint exists, which is right for flat models. If the winning model paints its
   clothes into textures (candidates b, c), either keep those textures greyscale-neutral and
   multiply, or leave the tint off for textured surfaces; candidate e (one `body` texture) can
   show headgear and decals only unless its outfit is split into `top/jacket/pants/shoes`
   materials — that split is the one requirement the wardrobe places on the modellers.
6. **Headphone material names.** The fit recognises `headphones*`, `phones*`, `hp_*`
   (`head_fit.headphone_prefixes`). A model using other names needs either a prefix added in
   `build_data.py` or an explicit `head_fit.models` entry.

## Rebuilding

```bash
bash tools/mem                                                   # one heavy process at a time
python -I art/wardrobe/measure_head.py [model.glb ...]           # head numbers for spec.HEAD
python -I art/wardrobe/concepts.py [items|patterns|decals|mixes] [id ...]   # FORCE=1 to redo
python -I art/wardrobe/textures.py                               # seamless masks + 3x3 previews
"…/blender.exe" --background --threads 6 --python art/wardrobe/build_headgear.py [-- id ... --no-preview]
python -I art/wardrobe/build_data.py                             # data/wardrobe.json
python -I art/wardrobe/sheets.py                                 # contact sheets
bash tools/gd script res://art/wardrobe/check_wardrobe.gd        # verification
bash tools/gd shot res://art/wardrobe/shot_wardrobe.gd [model=res://…] [tag=name] [page ...]
```

## Verification done

- `check_wardrobe.gd`: 0 failures — 26 wardrobe entries match the 26 helmet/top/pants/shoes
  items of `data/gear.json`; every glb loads through the import pipeline and raw through
  `GLTFDocument`, 1442–2460 triangles, flat materials, emissive `helmet_glow`; 15 textures load
  at 512 px; looks touch only outfit materials on the current model and candidates a, b, c, e;
  headgear attaches to `Head` on each.
- glbs parsed from outside Blender (`build_data.py` reads triangle counts, bounds and material
  colours straight from the files).
- Patterns: each tiled 3x3 and looked at (`art/previews/wardrobe/tile_*.png`, `_patterns.png`).
- Headgear on the head: Blender fit renders (`_sheet_a.png`, `_sheet_b.png`: iso, iso-back,
  front, side) and Godot at the game's isometric angle (`godot_ref_headgear*.png`,
  `godot_ref_fit_*.png`), plus candidates a, b, c (`godot_cand_*`).
- Looks and mixes in Godot: `godot_ref_tops.png`, `_tops_back.png` (decals), `_pants.png`,
  `_shoes.png`, `_mixes.png`.

## Known gaps

- Patterns and decals are implemented and previewed but not yet wired into the actor shader
  (steps 1–2 above).
- The headgear is fitted to the interim Moxie; the final model needs a re-measure (minutes).
- The Hush Hood sits behind the neck, so from the front three-quarter camera only its shoulder
  rolls and cowl rim show; it reads best from behind.
- Rigid headgear does not react to the pigtails' secondary motion; the cowl of the hood and the
  aerials can intersect swinging hair.
- The screen-tone pattern does not rotate with the character; on fast spins it stays upright
  like printed manga tone (intended, but a matter of taste).
- Look-only variants cannot change shape (see "What a look cannot show").
