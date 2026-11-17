# replay/ — kept winning performances

CINE-01 ("once the level is beaten, the player should be able to watch the combined result"),
LEVEL-09 (revisiting), and requirements chapter 20 "Replay integrity" (a replay must reproduce the
actual resolved outcome; never a fresh adaptive run). Node-free GDScript; depends only on `core/`.

| File | class_name | Role |
|---|---|---|
| `replay_record.gd` | `ReplayRecord` | One kept win: level id + level hash, loadout ids + the resolved numbers, the run's tapes (`ODTape.to_dict`), the boss memory input, and the expectation (outcome, horizon, event count, events checksum). JSON with `format: "overdub-replay"`, `version: 1`. |
| `replay_verifier.gd` | `ReplayVerifier` | Hashes, the events checksum, `quick_check` (no resolve), `verify` (re-resolve + compare), `check_resolution` (compare a resolve done elsewhere, e.g. on a thread). Verdicts `STATUS_OK / STATUS_STALE / STATUS_INVALID / STATUS_MISSING` with a `REASON_*` and a message. |
| `replay_store.gd` | `ReplayStore` | `user://replays/<level>.json`: `record_win`, `save` (atomic), `load_record`, `has_replay`, `list_level_ids`, `remove`, `quick_check(level)`, `play(level) -> Check`. |
| `replay_playback.gd` | `ReplayPlayback` | Plays a verified Resolution as the locked cinematic: `advance(dt)`, `current_frame()`, `drain_events()`, `skip()`, `done`, `view() -> SessionView` (phase CINEMATIC, decks COMMITTED, only SKIP offered). |

## What is stored, and why it cannot show a wrong result

- **Inputs, not frames.** The tapes, the resolved loadout and the boss memory the winning run was
  given. A file is a few KB; the frames are re-made by `ODResolve.resolve_encounter` on play.
- **Exactness.** GDScript's JSON parser is not correctly rounded for every double, so every number
  inside `tapes`, `bossMemory` and `resolvedLoadout` is also stored as float64 bits (`inputBits`)
  and restored bit for bit on load. The re-resolve therefore runs on exactly the winning tapes.
- **No new learning step.** The stored boss memory is passed verbatim; it is never rebuilt. There is
  no live take; the kernel has no randomness.
- **Stale instead of wrong.** `levelHash` (SHA-256 of the level's canonical JSON) catches level edits;
  an optional current loadout catches gear-catalogue changes; and the re-resolve must reproduce the
  horizon, the outcome (win, objective, survivors, reason) and the events checksum (SHA-256 over every
  event's `sub|type|tape|id|detail`). Any mismatch → `STATUS_STALE` with `REASON_LEVEL_CHANGED`,
  `REASON_GEAR_CHANGED` or `REASON_RULES_CHANGED`, and no Resolution to show. Outcome notes and float
  payloads are left out of the checksum, so rewording a note does not stale a replay.
- **Policy.** A new win on a level replaces its replay (the latest performance is the one kept). A
  newer `version` is refused; corrupt or foreign files are reported `STATUS_INVALID`.

## Integration (for the game layer — not wired yet)

1. **On a win** (GameSession enters `CINEMATIC`; the `resolved` cue with `outcome.win`):
   ```gdscript
   var tapes: Array = session.committed_tapes.duplicate()
   tapes.append(session.pending_tape)
   ReplayStore.new().record_win(session.level, session.loadout, tapes, session.boss_memory,
       session.resolution, int(Time.get_unix_time_from_system()))
   ```
   `session.boss_memory` is the memory the winning run was resolved with (it is rebuilt only on
   commit/reset, and a winning take is never committed through `commit`).
2. **Campaign screen:** for each cleared level, `store.quick_check(level, current_loadout)` (cheap)
   decides the badge: `ok()` → offer "Watch replay"; `is_stale()` → show "replay out of date"
   (`check.message`); missing → nothing. `current_loadout` = `LoadoutRules.resolve_loadout(
   check.record.loadout_ids, catalogue)` if the screen wants gear changes detected; pass null to
   trust the stored numbers. Suggested contract additions (owner: game/contracts):
   `CampaignLevelEntry.has_replay: bool`, `replay_stale: bool`, `replay_note: String`, and a
   `UiIntentType.WATCH_REPLAY` intent carrying the level id.
3. **Watch:** `var check := store.play(level, current_loadout)` (resolves on the calling thread;
   ~0.3–3 s). For the "rewinding tape" beat, resolve on a worker instead:
   `ODResolve.resolve_encounter(check_q.record.config(level).deep_copy(), progress, token)` on a
   Thread, then `ReplayVerifier.check_resolution(record, level, res)` on the main thread. If
   `check.ok()`, drive `ReplayPlayback.new(check.resolution, level, check.record)` exactly like the
   session's cinematic phase (render `current_frame()`, feed `drain_events()` to audio/fx, HUD from
   `view()`, RenderFrame mode `ViewMode.CINEMATIC`); return to the campaign screen when `done` or on
   skip.

Tests: `tests/replay/test_replay.gd` (`bash tools/gd test tests/replay`).
