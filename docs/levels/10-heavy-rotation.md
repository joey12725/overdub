# 10 — Heavy Rotation

Lower levels, 150 bpm, B-flat Phrygian (0 6 3 0, two bars a chord), the composer's block from
`data/music/10-heavy-rotation.json` (rotating-vertices drums, spirograph bass, rose lead, star-polygon
chords). Four cassettes, all speeds, stop / repeat / reverse. Takes of
8 bars; horizon 8 bars (32 beats; a 0.5x tape is cut off at half its length).
LEVEL-03: a finite set of selves allocated across two fronts.
Files: `data/levels/10-heavy-rotation.json`, `data/levels/solutions/10-heavy-rotation.json`.

## The idea

```
###########.....#~~~~#o#   east amp (o) behind vaultE (+)
###########......~~~~~+#   roost entrance; eyeE (latching beam) wakes the wasps
#.......m.~.....#......#
#p....R.m.~..@..#......#   armW plate (p), Anvil (R, brute, hp 150), press (m) + eyeW beam, bait line (~)
#.......m.~.....f::::::#   roaster nozzle (f), fire lane (:) with eyeLane beam
#+#########.....#......#   vaultW
#o#########...p.#.N.N..#   west amp, armE plate, two wasps (drones, hp 40)
```

Both enemies are plated: nothing in the baseline loadout can kill them inside a take. Two machines
can, and each needs two bodies in two places at once.

- **Press (west).** `eyeW` (enemies only) AND `armW` held → relay → crusher on the next beat. The
  plate is at the far end of the Anvil's den and also wakes it. The Anvil goes for the nearest self.
  Alone on the plate, that is you. With a second self standing at the corridor mouth (4 tiles from
  it, against your 5) it walks east through the beam and is pressed. The slam latches `doneW`, which
  opens the vault of the west amp.
- **Roaster (east).** The flame lane across the roost burns while `armE` is held. Wasps keep five
  tiles from the nearest self, so a lure standing in the north rows makes them cross the lane to
  close the distance. A wasp entering the burning lane latches `doneE`, which opens the east vault.

Both amps need momentum 3.2, so whoever strikes must be at 2x or faster, and must still have tape
left when their machine has finished (beat 7 west, beat 5 east).

## Intended solution (2 + 2, wins at beat 8.02; `mutate`: all 28 win)

| Beat | A, 1x stop (bait) | B, 2x stop | C, 1x stop | D, 2x stop |
|---|---|---|---|---|
| 0–2.6 | stands at (10.5, 6.5) from beat 2 | past the sleeping Anvil | onto `armE` at 2.6, roaster on | into the roost, back row, at 2.5 |
| 3.7 | | on `armW`: Anvil wakes, heads for A | | wasps closing in |
| 4.6–5.1 | | | | both wasps burn; vaultE opens 4.73 |
| 6.8–7.0 | | Anvil pressed at 6.99; vaultW opens 7.17 | | 2x heavy on the east amp at 6.79 |
| 8.0 | | 2x heavy on the west amp | | |

## Naive plans, run with the tools

| Plan | Result |
|---|---|
| One 4x tape does everything | FAIL — it can do the whole east front (amp at 6.58) and the tape ends on the way west. |
| No bait (B, C, D) | FAIL — "Tape A died at beat 14: struck by brute anvil"; west amp never unlocks. |
| No one on the roaster plate (A, B, D) | FAIL — lure "shot by drone wasp1" at beat 7; the wasps then leave the roost and shoot the bait at 17.9. |
| Lure stands too deep (row 4) | FAIL — the wasps park five tiles off, south of the lane, and shoot her at 5.69. |
| Right selves, strikers at 1x | FAIL — both amps: "needs 3.2 (momentum 1.80)". |
| Right selves, wrong order (strikers recorded before their supports) | FAIL — in her own take B is alone with the Anvil and D with live wasps, so neither records a route into a vault; both amps stay dark. |

## Alternatives that win (both use three tapes)

- **East solo at 4x:** trip `eyeE`, sprint to `armE`; the wasps have to cross the burning lane to
  reach her; sprint back for the amp (6.58). With A and B as above: wins at 8.02.
- **One body, two jobs:** the bait at 2x leaves at beat 7.5 and becomes the weight on `armE`; the
  lure waits for the roaster before going in. Wins at 14.25.

So the plain reading costs 2 + 2 and spends everything; a player who wastes a self on one front has
to find one of these to pay for it. Not found, and not proven impossible: a one-self west front
(kiting the Anvil out and back through the armed press was not run; rough arithmetic says a 2x tape
ends just before the amp).

## Teaches for later

Machines as kill conditions, "nearest self" as a steering wheel, sensors and relays as visible
cause and effect, and budgeting tapes across simultaneous problems (11, 12).

## Numbers relied on (`level.ts probe 10`)

150 bpm: 24 ticks per beat; 2x runs 3.4 tiles per beat, 4x 7.0. Brute walks 0.7 tiles per beat and
stops 0.84 short of its target; with `quantize 1, delay 0` it is 0–0.7 tiles past the beam edge at
the slam, inside the press column. Drones hold exactly 5.0 tiles, fly 1.25 per beat. Press damage
150, roaster damage 40 (kills on contact). Amps 3.2: 2x heavy 3.6, 1x best 2.7.
Godot replay: `bash tools/gd script res://tools/bot.gd -- 10-heavy-rotation` wins identically.

## Presentation must-haves

- The Anvil and the wasps must look armoured, and a hit on them must read as "no effect", or the
  premise is invisible. Their health is in the snapshot (`hp` / `maxHp`).
- `armW`, the `slam` lamp, the press and vaultW share one accent; `armE`, the roaster, the `doneE`
  lamp and vaultE another. The relay lamps sit at (8.5, 4.6), (1.5, 7.6) and (22.5, 3.4).
- `eyeE` and `eyeW` are thin pale beams, not lasers. The inscribed strips mark the bait line and
  the roost's back rows; the grate marks the fire lane.
- The Anvil's wake-up when `armW` goes down needs a clear cue (it is the cost of arming the press).
