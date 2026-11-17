# 12 — Master Tape

Core, 120 bpm, A Lydian. 4 cassettes, 4-bar takes, 8-bar (32-beat) horizon, speeds 0.5 / 1 / 2 / 4,
stop / repeat / reverse. Objective: `reach` the deck tile in front of the time machine. Files:
`data/levels/12-master-tape.json`, `data/levels/solutions/12-master-tape.json`.

## The idea

One machine, one sentence: **each pad holds the next gate open, and each pad's teeth stay down only
while the next pad along is held; the deck's teeth stay down for pad one.** Four chambers in a row on
one lane, three reel pads and the deck, wired in a ring. Every second bar the teeth count in: pad one
on beat 4, pad two on 5, pad three on 6, the deck on 7 (then 12 to 15, 20 to 23, 28 to 31).

So nobody is safe until the one after them arrives, and the last one is safe only because the first
is still standing. Every take ends with the player watching the self they just recorded die, and
the next take is what undoes it. Break any link and the ring unwinds in order, one count-in at a
time. It is the story's line ("every take was holding a door for the next one") as a mechanism.

Each leg is an earlier lesson: hold the door (03), a fast tape with a run-up (02), a hit that only
counts with a second self's (04), a take that dies and is saved later (05), and the allocation of
speeds against finite tape (10).

## Intended solution (stored; wins in the prototype and replayed in Godot)

| Take | Speed, mode | What it does | When | Deadline |
|---|---|---|---|---|
| A | 2x stop | Onto pad one. Opens gate one. | 0.42 | — |
| B | 4x stop | Through gate one, run up the chamber, running heavy through the splice (momentum 10.8 of 8), onto pad two. | break 1.62, pad 2.12 | beat 4 (A's teeth; also the end of a 4x tape) |
| C | 2x stop | Through gate two, one cut at the warden (it only drops the shield), onto pad three. | cut 2.93, pad 4.12 | beat 5 (B's teeth) |
| D | 2x stop | Through gate two, second cut inside the one-beat window (kills the warden), gate three, rides the transport belt onto the deck. | kill 3.30, deck 5.20 | beat 6 (C's teeth); warden's bash is beat 4 |

Recorded alone, A dies on beat 4, B on beat 5, C on beat 6. In the final mix nobody does: all four
are alive at beat 32.

## Naive plans (each run through the real session)

| Plan | Result | Why, in the game's words |
|---|---|---|
| One tape: pad, then the gate | FAIL | Gate one shuts the moment it steps off. |
| Right selves, all 1x | FAIL | "heavy … hit breakable wall splice with momentum 2.7; it needs 8"; A skewered on beat 4. |
| B at 2x / B at 4x swinging from a standstill | FAIL | Momentum 5.4 / 7.2 of 8. |
| A at 0.5x | FAIL | B gets through too late for its four-beat tape; B dies beat 5, C 6, A 12, D 15. |
| Nobody cuts the warden | FAIL | C bashed on beat 8, then B (teeth, 13), A (20), D on the deck (23). |
| Only D cuts the warden | FAIL | One self only ever pops its shield. Same unwinding from beat 12. |
| D at 1x | FAIL | Late to the deck: C skewered on beat 6, and the rest follow. |
| D at 4x (others as intended) | FAIL | Its tape is over at beat 4, before gate three opens. |
| Runner recorded first | FAIL | Wrong order: nothing is open yet. |
| "Cut the first take": A steps off pad one once everyone is through | FAIL | "Tape D died at beat 6.99: skewered by spikes head", then C and B. |

## Alternatives that win (tested)

- A at 1x; or A, C and D all at 4x.
- A looks after herself: a 0.5x A steps off pad one for each bite (beats 4, 12, 20, 28) and back on.
  B and C are then only needed until D is through, and the run wins with A and D alive. Harder to
  play, and it is the one place a slow tape earns its length.

## What it teaches

Nothing new: it is the exam. Trust a take that dies, record a swing for a partner who does not exist
yet, pick the speed by what the leg needs and how long the tape lasts.

## Numbers relied on (`level.ts probe 12`, 120 bpm = 30 ticks per beat)

- Splice threshold 8: 4x running heavy 10.8 breaks it; 4x standing heavy 7.2 and 2x running heavy 5.4
  do not.
- A 4x tape lasts 4 beats, which is exactly A's deadline.
- Shielder: 2 hp, shield stays down 1 beat after a pop and only for a different self; attacks on
  beats 0, 4, 8 … with a 0.75-beat wind-up; walks 0.9 tiles a beat. 2x light = 2 damage.
- Teeth are spikes (up for half a beat). Spikes were chosen over a crusher on purpose: a crusher
  shoves the dying take off the pad and that shove is recorded, so the saved self would walk off
  her pad anyway. Spikes leave the recording standing where it was.
- Slack in the stored run: pad two 1.9 beats, pad three 0.9, deck 0.8, the kill 0.7 before the bash,
  second cut 0.37 after the first (window 1.0). `mutate`: all 28 variants win.

## What the Godot presentation must get right

- Wiring: each pad and the teeth it silences must share an accent colour (reel2 with teeth1, reel3
  with teeth2, deck with teeth3, reel1 with head), and reel1 with the deck is the one that has to
  be unmissable.
- The teeth's one-beat warning must read on all four tiles in sequence: the count-in is the level.
  Teeth that are held down should show it (dim, locked), so a safe pad looks safe.
- The pads are numbered on the north wall (ONE, TWO, THREE). The lane (row 5, inscribed floor) runs
  from the start chamber straight to the deck and the time machine on its low plinth.
- The splice is struck from its south side, in view; pads are on row 1, clear of walls to their
  south-east.
- A long quiet tail (beats 6 to 32) is correct for a win: four selves standing still while the
  teeth count in and nothing bites.

## Known gaps

- The level reprises 02, 03, 04, 05 and 10 directly. Desync (07), knockback (06) and the repeat and
  reverse end modes (08, 09) are available but not required by the intended line.
- The transport belt (two tiles before the deck) is a kindness, not a puzzle.
