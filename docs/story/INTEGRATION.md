# OVERDUB — story integration (one page, for engineers)

All text is data in `data/story/story.json`; all art prompts are in `data/story/portraits.json`.
Nothing in the story needs a new mechanic, and the whole layer can be switched off without
changing a level. Level keys are `"<NN>-<slug>"` and are expected to match the level ids in
`data/levels/`; if an id differs, rename the key, not the level.

## Data shape

Every spoken line, everywhere, is `{ who, expression, line }`. `who` is a `characters[].id`,
`expression` is one of that character's `portraits`, and the portrait asset id is
`"<who>.<expression>"` (20 in total, each with a prompt in `portraits.json`). Lines are plain ASCII
and at most 76 characters, so a two-line box at about 45 characters per line always fits.
`characters[].color` tints the speaker name and the box edge.

## Where each piece appears

| Data | When | Required? |
|---|---|---|
| `title.tagline` | Title screen, under the logo, over `keyArt` | optional |
| `chapters[]` | Full-screen card (`card` id in `portraits.json`) before the level named in `before`, first visit only | optional |
| `levels[id].intro` | After the level loads, before `briefing`. First visit only; replayable from level select | **core** |
| `levels[id].outro` | After the win cinematic, before `results`. First clear only | **core** |
| `levels[id].firstDeath` / `firstDesync` | The first time that event happens **in that level**; shown at the next `decision` or `review`, never during a take | optional |
| `once.*` | The first time the event happens **in the save**, on any level. If the level has its own `firstDeath` / `firstDesync`, the level's version plays instead and still marks the `once` flag | optional |
| `levels[id].idle` | One line as a small toast after about 40 s of no input in `setup`; at most once per visit | optional |
| `barks.*` | One-line toasts, see below | optional |
| `ending` | After the `12-master-tape` outro, in place of `results` | **core** |
| `stinger` | After the credits | optional |

If only the **core** rows ship, the story is complete.

## Dialogue box (intro, outro, firsts, ending)

- Bottom of the screen, world dimmed but visible. Portrait on the left for Moxie, on the right for
  everyone else; speaker name above the text in the character colour.
- Text types on quickly. Confirm completes the line if it is still typing, otherwise advances.
  Holding cancel (or pressing start) skips the whole sequence. No choices, no branching, no auto-advance.
- Only the current speaker's portrait is shown; swap with a short pop, no cross-fade.
- A line ending in `--` or starting with `--` is a radio cut: clip it with static, no extra handling.
- Opal and the Archivist are voices in Moxie's headphones. If cheap, give their boxes a radio
  treatment (scanline or waveform edge); the Archivist uses the same channel Opal lost in level 05.
- Never open a box during `countin`, `recording`, `review` or `cinematic`.
- Arrays can hold a single entry (`barks.lastTape`, most `idle`), and `firstDeath` / `firstDesync`
  are absent on most levels (only 01 and 11 have a `firstDeath`; no level has a `firstDesync`).
- In `ending`, lines 1 to 6 play in the machine room and lines 7 to 14 on the surface. Fade to
  the title key art (or black) between line 6 and line 7; that index is the only hard-coded cut.

## Barks

A bark is a small non-blocking toast near Moxie's deck (portrait thumbnail plus text, about two
seconds), chosen at random from the array without repeating the previous pick. Suggested rule: at
most one bark per session state, and roughly a one in three chance on repeatable events so they
stay a treat. They must never cover the beat ruler.

| Key | Trigger |
|---|---|
| `countIn` | start of `countin` |
| `takeCommitted` / `retry` / `resetAll` | the matching choice in `decision` |
| `lastTape` | `setup` for the final cassette |
| `death` | the live self dies during a take |
| `ghostTake` | a few seconds into recording as `recGhost` |
| `desync` / `resync` | a playback self desyncs or resyncs during a take or review |
| `rescue` | review shows a self alive at the horizon that died in the previous combined run |
| `fail` | a combined run fails in `review` |
| `win` | entering `cinematic` |
| `loot` | gear awarded in `results` |
| `bossRecall` (Moxie) and `archivistRecall` | level 11 only, when the boss telegraphs an action taken from `BossMemory`; show the Archivist's line, then Moxie's |
| `archivistSurprised` | level 11 only, optional: a committed take the boss has no memory answer for |

## Notes and assumptions

- The Archivist's quoted lines ("Easy money", "Back by dinner") are fixed strings from level 01's
  intro. They are not generated from what the player did.
- The fiction says discarded takes never reach the Archivist. That matches `BossMemory` being
  built from committed tapes only; if that rule changes, change `archivistSurprised[2]` and the
  "All kept" in level 08's intro.
- Take names in dialogue are "Take One" to "Take Four" (recording order). The HUD's cassette
  letters A to D can stay as they are; nothing in the text depends on them.
- Save flags needed: per level `introSeen`, `outroSeen`, and one flag per `once` key.
- Portrait files: `assets/story/portraits/<who>.<expression>.png`, square, transparent. Chapter
  cards and key art are 16:9 and opaque. Paths are a suggestion; nothing in the data hard-codes them.
- `portraits.json` is safe to hand-edit. `negativePrompt` applies to every image;
  `bustNegativePrompt` is added for the 20 busts only (the wide images have scenery and echoes).
  Each bust has a `facing`: Moxie faces right, Opal and Tolliver face left, the Archivist is frontal.
  Do not mirror Moxie's portrait in the UI; her face paint and strap are asymmetric.
