# OVERDUB icons

One sticker family for the loadout screen and the HUD. Everything here is RGBA PNG with a transparent
background. File name = id, so no lookup table is needed in code:

| What | Path | Id source | Size |
|---|---|---|---|
| Gear item | `gear/<item id>.png` | `id` in `data/gear.json` (37 items) | 512x512 |
| Empty slot glyph | `slots/<slot>.png` | `GearSlot`: helmet, top, pants, shoes, melee, ranged | 512x512 |
| Ability emblem | `abilities/<AbilityId>.png` | `AbilityId` in `prototype/src/core/types.ts` (10) | 512x512 |
| Action glyph | `actions/<ActionKind>.png` | `ActionKind`: light, heavy, dodge, ranged, interact, ability | 256x256 |
| Tape glyph | `tape/<name>.png` | `EndMode` (stop, repeat, reverse) + tape/self states (alive, dead, desync, resync, locked, rec) | 256x256 |

```gdscript
var tex := load("res://assets/ui/icons/gear/%s.png" % item.id)
var ability_tex := load("res://assets/ui/icons/abilities/%s.png" % ability_id)   # camelCase, exactly as AbilityId
```

## Gear (`gear/`)

Colour stickers: black ink outline, uniform 8 px white sticker border, flat cel colour with one shadow tone.
Each sticker is trimmed, scaled so its longest side is 464 px and centred on the 512 canvas (24 px padding),
so icons line up in a grid without per-icon offsets. Designed to read at 64 px; fine down to about 40 px.

| Slot | Ids |
|---|---|
| helmet | scrap_cap, hush_hood, feedback_crown, click_visor, prism_goggles, rabbit_ears |
| top | lined_bomber, ballast_puffer, razor_mesh, sub_vest, patchcord_hoodie, dropout_jacket, mirrorball_vest, encore_tee |
| pants | olive_cargos, snap_trackies, flywheel_cargos, kneepad_joggers, parachute_pants, bandolier_cargos |
| shoes | beater_hightops, slick_sliders, anvil_platforms, static_runners, spring_soles, grip_sprinters |
| melee | splice_blade, stylus_shiv, amp_sledge, reel_lash, speaker_knuckles, vinyl_glaive |
| ranged | mixtape_rocket, needle_rail, bleed_emitter, bass_drop, static_spray |

## Slots (`slots/`)

White silhouette + black ink outline, no colour. Meant for an EMPTY or placeholder slot: draw at 35-50 %
opacity, or tint with `modulate` (white x tint = tint, the ink stays black).

## Abilities (`abilities/`)

Colour emblems in the gear sticker style, one per `AbilityId`:

| Id | Picture | Granted by |
|---|---|---|
| manualDesync | cassette snapped out of alignment | dropout_jacket |
| lowProfile | muted speaker | hush_hood |
| loudmouth | megaphone | feedback_crown |
| beatSight | eye with a metronome pupil | click_visor |
| laserProof | prism bending a beam | prism_goggles |
| heavyStep | boot on a pressure plate | anvil_platforms |
| phaseDodge | half-dissolved sneaker | static_runners |
| slideStrike | slide arrow into a slash | slick_sliders |
| parry | mirror shield bouncing a shot | mirrorball_vest |
| killRefresh | refresh loop around a skull pick | encore_tee |

## HUD glyphs (`actions/`, `tape/`)

Drawn procedurally (`art/icons/glyphs.py`), not generated, so they stay crisp: solid WHITE shape, bold BLACK
outline, transparent canvas. They read at 24 px on light and dark panels. Tint with `modulate` to the tape's
channel colour; the outline stays black. `tape/rec` is the one pre-coloured glyph (record red) - do not tint it.

| File | Shape | Meaning |
|---|---|---|
| actions/light | slim crescent slash | light attack |
| actions/heavy | impact burst | heavy attack |
| actions/dodge | double chevron | dodge |
| actions/ranged | crosshair | ranged weapon |
| actions/interact | lever switch | interact |
| actions/ability | lightning bolt | ability button |
| tape/stop | square | EndMode `stop` |
| tape/repeat | loop arrow | EndMode `repeat` |
| tape/reverse | rewind (double triangle, left) | EndMode `reverse` |
| tape/alive | heart | self is alive |
| tape/dead | skull | self is dead |
| tape/desync | disc snapped in two, halves slipped | self is desynced |
| tape/resync | spark with comet tail | recovery spark travelling home |
| tape/locked | padlock | tape / option locked |
| tape/rec | red dot | recording |

## Import notes (Godot)

- Enable **Mipmaps > Generate** on these textures (or use `TextureRect` with `expand` and a filtered, mipmapped
  texture filter): the masters are 256-512 px and will shimmer if point- or bilinear-sampled down to 24-64 px.
- Alpha is straight (not premultiplied); transparent pixels carry white (gear) or black (glyph) RGB, so turn on
  **Process > Fix Alpha Border** if you see fringes.

## Rebuilding

Sources live in `art/icons/`: `prompts.py` (every prompt), `generate.py` (calls `tools/img`), `process.py`
(cut-out clean-up, sticker border, trim/pad to 512), `glyphs.py` (HUD glyphs), `sheet.py` (contact sheets
`art/icons/sheet_*.png` on light and dark). Raw generations are kept in `art/icons/raw/`.
