# ui/ — integration hooks for the game layer

`res://ui/ui_root.tscn` (`ui/ui_root.gd`, extends `UiBase`) is the whole interface. Besides the
`UiBase` contract (`show_screen`, `set_*`, `update_hud`, `toast`, `navigate`, ...) it exposes the
hooks below. Everything is optional: a game that never calls them still gets the menus and HUD.
Layers, bottom to top: **Hud** (with the world widgets inside it) → **Dialogue** → **Menus**
(incl. Field Guide and the loot moment) → **Card** (chapter cards) → **Toasts**.

## Per level

| When | Call |
|---|---|
| level loaded | `ui.set_world_camera(world.ctx.camera)` (any `Camera3D`; `set_world_projector(func(sim: Vector2, h: float) -> Vector2)` for a custom mapping) |
| level loaded | `ui.load_level_widgets(level, resolved_loadout, sim_config.boss_memory)` |
| each commit / reset | `ui.set_boss_memory(new_memory)` |
| every rendered frame, next to `update_hud` | `ui.update_world(frame.snap, view, frame.events)` |
| while recording | `ui.set_aim(input.aim)` (sim radians; NAN = body facing) |
| first level of a new `LevelTheme` | `await ui.show_chapter_card(level.theme, "Depth 04 · Relay Station").finished` |

The HUD forwards these to `WidgetWorldOverlay` (threshold badges, momentum gauge near the live
self, off-screen chevrons, boss bar). The boss bar's top inset pushes the HUD banner down; read it
with `ui.hud.top_inset()` / `top_inset_changed(px)` if the camera should keep the boss out from
under it. `bottom_inset()` / `bottom_inset_changed` are unchanged.

**Resolving beat.** The HUD banner reads `GameSessionView.resolving / status_text /
resolve_progress` and shows "REWINDING TAPE…" with a progress bar (no SKIP chip). Set
`GameApp.TOAST_RESOLVING = false`.

**beatSight.** `WidgetThreatTicks` is mounted on the ruler and fed from `SessionView.threat_beats`;
nothing to wire.

## Dialogue, barks, coach marks, failure hints

`ui.dialogue` is the `DialogueLayer` (docs/DIALOGUE.md). It is already mounted and set up with the HUD
as its anchor root and `hud.world_point_to_screen` as the world mapping (which works once
`set_world_camera` was called). `ui.set_device / set_bindings` reach it. The game still drives the
story: `begin_level`, `play_intro` (await `dialogue_finished`), `update(view, events, dt, snap)` each
frame, `notify_action`, `notify_input`, `on_review_result`, `play_outro`, `on_results`,
`play_ending(UiArt.ending_card())`, `end_level`, and the save flags (`set_seen_flags`,
`seen_changed` → `get_seen_flags()`), `set_levels_cleared`.

Coach-mark anchors: the HUD implements `anchor_rect(anchor, subject)` and puts every part in its
group (`deck_<n>`, `ruler`, `objective`, `count_in`, `setup`, `decision`, `briefing`, `banner`).
While counting in / recording, a controls strip (move, aim, light, heavy, dodge, shoot, use,
ability — keycap + action glyph) sits bottom-right above the dock, so `prompt:<action>` marks point
at the real key.

## Field Guide

`ui.set_codex(codex)` (the game's `Codex`, `data/codex/codex.gd`, after `load_unlocked(save.codex)`)
adds "Field Guide" to the campaign screen (with a page count and NEW PAGE note) and the pause menu.
`ui.open_codex(entry_id)` opens it on a page (e.g. `codex.entry_for_enemy(type)` after a failed
run). It is a menu-internal screen: `ui.screen` does not change and back returns where it was
opened. `ui.set_codex_hint(entry_id)` makes the pause menu's Field Guide open on that page (the game
sets it after a failed run to the page for what killed a self, and clears it with `""`). Browsing clears NEW flags in the Codex (not persisted). Toast new pages yourself on
`codex.unlocked`.

## Replays

`ui.set_replays({level_id: {"ok": bool, "note": String}})` from `ReplayStore.quick_check` per
cleared level. Playable ones get a "▶ Watch" button beside their card; accepting it emits a
`UiIntent` with `type = MenuCampaignLogic.INTENT_WATCH_REPLAY` (`&"watchReplay"`) and `id` = level
id (not in `UiIntentType.ALL`: that contract is not the UI's).

## Loot moment

`set_results` with non-empty `loot` puts `WidgetLootReveal` over the results screen when it shows.
EQUIP NOW emits `UiIntent.equip(slot, id)` per found item, then `openLoadout`; LATER closes it.

## Settings

The settings screen (and pause → settings) adds rows that emit `UiIntent.setting(key, value)`:

| key | values | SaveSettings field it expects |
|---|---|---|
| `cassettePalette` | `"default"`, `"high_contrast"` | `cassette_palette` |
| `highContrast` | bool | `high_contrast` |
| `reduceFlashing` | bool | `reduce_flashing` |
| `shakeScale` | 1.0, 0.4 | `shake_scale` (screenShake stays the on/off) |
| `textScale` | 1.0, 1.15, 1.3, 1.5 | `text_scale` |
| `holdMode` | `"hold"`, `"press"` | `hold_mode` |
| `voices` / `barks` / `coachMarks` | bool | `voices` / `barks` / `coach_marks` |
| `textSpeed` | 0.75, 1.0, 1.5, 2.5 | `text_speed` |

Until `SaveSettings` has a field, `set_by_key` rejects the key and the UI keeps the value for the
session; once it has the field, the `set_settings` echo is authoritative. The UI applies its own part
immediately: reduce flashing (HUD lamps / glitch still), text scale (dialogue, barks, coach marks,
hints, toasts, menu body text, and the HUD's reading text through `hud.set_text_scale`), hold mode
(`hud.set_hold_mode(press)`: the reset control reads PRESS TWICE / PRESS AGAIN TO CONFIRM), barks /
coach marks / text speed (dialogue layer). `voiceVolume` is a volume row beside Character voices. Cassette colours
always come from `OD.tape_color`; the HUD follows when core switches sets.

## Generated art

`ui/theme/ui_art.gd` (`UiArt`) loads the art (imported, or straight from the PNG when the import is
missing), pre-shrinks icons for small sizes, builds nine-slices from `assets/ui/art/ui/slices.json`
and turns the cassette pattern tiles into tintable masks.
