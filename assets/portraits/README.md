# Dialogue portraits

Twenty bust portraits, one per `characters[].portraits` entry in `data/story/story.json`.
The file for a line `{ who, expression, line }` is always

    res://assets/portraits/<who>_<expression>.png        e.g. moxie_grin.png, archivist_playback.png

| Character | id | Expressions | Faces | Name colour |
|---|---|---|---|---|
| Moxie | `moxie` | neutral, grin, smug, annoyed, surprised, thinking, determined, soft | screen right | `#f5c518` |
| Opal | `opal` | neutral, dry, amused, worried, soft | screen left | `#e9a36b` |
| Tolliver | `tolly` | neutral, earnest, flustered, impressed | screen left | `#9bb7ff` |
| The Archivist | `archivist` | idle, playback, still | straight out | `#58f0dc` |

## Format

- PNG, RGBA, **1024 x 1024**, straight (non-premultiplied) alpha, transparent background, RGB zeroed where alpha is 0.
- The bust is cut by the **bottom edge** of the canvas: anchor the texture's bottom edge to the bottom of the dialogue
  box (or just below its border) and never show the lower edge floating.
- Within a character every expression shares the same scale and position (derived from one anchor drawing and
  registered to it), so swapping textures on one `TextureRect` does not move the head. Across characters the heads are
  about the same size; headroom above the silhouette is 25-65 px.
- Opal, Tolliver and the Archivist run off the left/right edges at the shoulders by design. Moxie does not.

## Using them in Godot

- One `TextureRect` (`expand_mode = IGNORE_SIZE`, `stretch_mode = KEEP_ASPECT`), about 256 px square at 1080p, bottom
  edge on the box's bottom edge, drawn over the box so the head rises above it. Moxie on the left, everyone else on
  the right (see `docs/story/INTEGRATION.md`). Swap `texture` per line; no cross-fade needed.
- **Do not flip Moxie** (her cheek paint, strap and headphone mark are asymmetric). The others are already drawn facing
  left; do not flip them either.
- Import settings: Lossless or VRAM-uncompressed, **mipmaps on** if the portrait is ever drawn below ~400 px (bark
  toasts use a thumbnail), filter linear, `fix_alpha_border` on (default). They are 0.5-0.9 MB each on disk.
- For bark toasts, crop the head with a region: `Rect2(162, 20, 700, 700)` works for all four characters (see `art/portraits/sheets/bark_thumbs.png`).
- The Archivist's three states share every pixel of the housing; only reels, sensor, rune light and halo screens
  change, so a quick alternation between `idle` and `playback` reads as the machine winding back.

## How they were made

Source, prompts and checks live in `art/portraits/` (raw model output in `raw/`, rejected attempts in `raw/rejected/`):

| File | What it does |
|---|---|
| `gen_moxie.sh` | Moxie expression from her neutral anchor (`raw/moxie_neutral_b.png`, itself drawn from `docs/reference/R01-moxie-concept.png`) |
| `gen_new.sh` | a new character anchor in the house style, using Moxie's anchor as the style/framing reference |
| `gen_expr.sh`, `batch_cast.sh` | every Opal / Tolliver expression derived from that character's anchor (prompts inline) |
| `archivist_states.py` | paints `playback` and `still` over the Archivist's idle anchor (the image model would not change the state) |
| `cast.json` + `normalize.py` | registers each expression to its anchor, scales, mirrors where needed, cleans alpha, writes the 1024 px files here |
| `mock.py` | contact sheets, drift overlays, the cast line-up and 256 px dialogue-box mocks in `art/portraits/sheets/` |
| `verify.py` | checks every portrait `story.json` declares or uses exists, is RGBA 1024 px, has clean alpha, sits on the bottom edge and does not drift between expressions |

To redo one expression: delete its file in `art/portraits/raw/`, run the matching generator from the repo root, then

    python -I art/portraits/normalize.py <id> && python -I art/portraits/mock.py && python -I art/portraits/verify.py

and look at `art/portraits/sheets/<id>_sheet.png` and `dialogue_<id>.png` before keeping it. Image model:
gpt-image-2.6-sunburst via `tools/img`; all art is generated for this project, no third-party assets.

## Known departures from the briefs

- **Opal has no desk microphone.** It crowded the bust and fought the expressions; "worried" has a hand to her chest
  rather than gripping the stand. The radio treatment of her box carries the idea instead.
- **Tolliver's tablet and harness buckles are below the crop** at this head size; the survey flag is not drawn.
- **The Archivist** is drawn as a hooded housing with eleven halo screens (not twelve), and is more rendered (soft
  gradients on the reels and metal) than the flat two-tone human busts.
- Moxie's gestures from the prompts (hand behind head, folded arms, finger on the headphone) were left out so that only
  her face changes between expressions; "soft" does move the headphones to her neck as written.
