# Harmonograph formula reference

LevelDef.music.tracks[].formula must be one of the formula ids listed below, and each key in that track's params object must come from the parameter list of the chosen formula (keys not listed there are dropped by the engine). Every value is generated from `src/vendor/harmonograph.js` by `scripts/list-formulas.cjs`, so regenerate this file rather than editing it by hand.

## Formulas (66)

`id` is the value for `formula`. `Integer` marks formulas that yield discrete integer values per step; `Period` is `yes` when the formula defines a period function, `no` otherwise.

| Formula id | Display name | Group | Math | Integer | Period | Param key | Label | Default | Min | Max | Step | Detents |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `fibonacci` | Fibonacci mod m | Number sequences | Fₙ = (Fₙ₋₁ + Fₙ₋₂) mod m | yes | no | `m` | m | 7 | 2 | 32 | 1 | 5, 7, 8, 12, 16 |
| `lucas` | Lucas mod m | Number sequences | Fₙ = (Fₙ₋₁ + Fₙ₋₂) mod m | yes | no | `m` | m | 7 | 2 | 32 | 1 | 5, 7, 8, 12, 16 |
| `tribonacci` | Tribonacci mod m | Number sequences | Tₙ = (Tₙ₋₁ + Tₙ₋₂ + Tₙ₋₃) mod m | yes | no | `m` | m | 7 | 2 | 32 | 1 | 5, 7, 8, 12, 16 |
| `squares` | Squares mod m | Number sequences | n² mod m | yes | yes | `m` | m | 7 | 2 | 32 | 1 | 5, 7, 8, 12, 16 |
| `triangular` | Triangular numbers | Number sequences | n(n + 1) / 2 mod m | yes | yes | `m` | m | 7 | 2 | 32 | 1 | 5, 7, 8, 12, 16 |
| `cubes` | Cubes mod m | Number sequences | n³ mod m | yes | yes | `m` | m | 7 | 2 | 32 | 1 | 5, 7, 8, 12, 16 |
| `linear` | Modular walk | Number sequences | (a·n + c) mod m | yes | yes | `a` | a | 2 | 1 | 16 | 1 | — |
|  |  |  |  |  |  | `c` | c | 0 | 0 | 31 | 1 | — |
|  |  |  |  |  |  | `m` | m | 7 | 2 | 32 | 1 | 5, 7, 8, 12, 16 |
| `powers` | Powers mod p | Number sequences | aⁿ mod p | yes | no | `a` | a | 3 | 1 | 16 | 1 | — |
|  |  |  |  |  |  | `m` | m | 7 | 2 | 32 | 1 | 5, 7, 8, 12, 16 |
| `collatz` | Collatz from s | Number sequences | c ↦ c/2 (even), 3c + 1 (odd) | yes | no | `s` | start s | 22 | 1 | 9999 | 1 | — |
|  |  |  |  |  |  | `after` | after 1 | 1 | 0 | 2 | 1 | — |
| `recaman` | Recamán | Number sequences | aₙ = aₙ₋₁ − n if new ≥ 0; else +n | yes | no | — | — | — | — | — | — | — |
| `norgard` | Nørgård infinity series | Number sequences | a₂ₙ = −aₙ ; a₂ₙ₊₁ = aₙ + 1 | yes | no | — | — | — | — | — | — | — |
| `popcount` | Binary digit sum | Number sequences | Σ bits(n) | yes | yes | `bits` | bits | 8 | 1 | 20 | 1 | — |
| `digitsum` | Base-b digit sum | Number sequences | Σ digitsᵦ(n) | yes | no | `base` | b | 3 | 2 | 16 | 1 | — |
| `thue` | Thue–Morse | Number sequences | popcount(n) mod 2 | yes | no | — | — | — | — | — | — | — |
| `ruler` | Ruler sequence | Number sequences | ν₂(n + 1) | yes | no | — | — | — | — | — | — | — |
| `stern` | Stern’s diatomic | Number sequences | s₂ₙ = sₙ ; s₂ₙ₊₁ = sₙ + sₙ₊₁ | yes | no | — | — | — | — | — | — | — |
| `kolakoski` | Kolakoski | Number sequences | 1, 2, 2, 1, 1, 2, … | yes | no | — | — | — | — | — | — | — |
| `beatty` | Beatty / Fibonacci word | Number sequences | ⌊(n+1)α⌋ − ⌊nα⌋ | yes | no | `alpha` | α | 1.61803398875 | 1 | 3 | 0.001 | 1.5, 1.61803398875, 2.41421356 |
| `digits` | Irrational digit stream | Number sequences | digitsᵦ(π, e, √2, φ) · 96-digit cycle | yes | yes | `constant` | constant | 0 | 0 | 3 | 1 | — |
|  |  |  |  |  |  | `base` | b | 7 | 2 | 16 | 1 | — |
| `primes` | Primes mod m | Number sequences | pₙ mod m | yes | no | `m` | m | 7 | 2 | 32 | 1 | 5, 7, 8, 12, 16 |
| `primegaps` | Prime gaps | Number sequences | pₙ₊₁ − pₙ | yes | no | — | — | — | — | — | — | — |
| `divisors` | Divisor count | Number sequences | d(n + 1) | yes | no | — | — | — | — | — | — | — |
| `totient` | Euler totient | Number sequences | φ(n + 1) | yes | no | — | — | — | — | — | — | — |
| `vdc` | Van der Corput | Number sequences | radical inverseᵦ(n) | no | no | `base` | b | 2 | 2 | 12 | 1 | — |
| `gray` | Gray-code bit | Number sequences | bitₖ(n ⊕ (n ≫ 1)) | yes | yes | `bit` | k | 2 | 0 | 12 | 1 | — |
| `bytebeat` | Bytebeat | Number sequences | (n·(n≫a | n≫b)) & mask | yes | no | `a` | a | 3 | 0 | 12 | 1 | — |
|  |  |  |  |  |  | `b` | b | 5 | 0 | 12 | 1 | — |
|  |  |  |  |  |  | `mask` | mask | 31 | 1 | 255 | 1 | — |
| `logistic` | Logistic map | Dynamical systems | x ↦ r·x(1 − x) | no | no | `r` | r | 3.83 | 2.5 | 3.99 | 0.001 | 2.9, 3.2, 3.5, 3.55, 3.83, 3.95 |
| `circle` | Circle map | Dynamical systems | θ ↦ θ + Ω − K sin(2πθ) / 2π | no | no | `omega` | Ω | 0.333333333 | 0 | 1 | 0.001 | 0.25, 0.3333333333333333, 0.4, 0.5, 0.6666667 |
|  |  |  |  |  |  | `K` | K | 0.8 | 0 | 2 | 0.01 | — |
| `tent` | Tent map | Dynamical systems | x ↦ r·min(x, 1 − x) | no | no | `r` | r | 1.9 | 1 | 1.999 | 0.001 | — |
| `sinemap` | Sine map | Dynamical systems | x ↦ r sin(πx) | no | no | `r` | r | 0.9 | 0.5 | 1 | 0.001 | — |
| `henon` | Hénon map | Dynamical systems | x ↦ 1 − ax² + y ; y ↦ bx | no | no | `a` | a | 1.4 | 0.8 | 1.4 | 0.001 | — |
|  |  |  |  |  |  | `b` | b | 0.3 | 0.1 | 0.3 | 0.001 | — |
| `lorenz` | Lorenz attractor | Dynamical systems | ẋ = σ(y−x), ẏ = x(ρ−z)−y, ż = xy−βz | no | no | `sigma` | σ | 10 | 5 | 15 | 0.1 | — |
|  |  |  |  |  |  | `rho` | ρ | 28 | 15 | 35 | 0.1 | — |
|  |  |  |  |  |  | `beta` | β | 2.6666666666666665 | 2 | 4 | 0.01 | — |
| `rossler` | Rössler attractor | Dynamical systems | ẋ = −y−z, ẏ = x+ay, ż = b+z(x−c) | no | no | `a` | a | 0.2 | 0.1 | 0.3 | 0.01 | — |
|  |  |  |  |  |  | `b` | b | 0.2 | 0.1 | 0.3 | 0.01 | — |
|  |  |  |  |  |  | `c` | c | 5.7 | 4 | 7 | 0.1 | — |
| `ca` | Cellular automaton | Dynamical systems | cellᵢ(rule, n) | yes | no | `rule` | rule | 90 | 0 | 255 | 1 | 30, 90, 110 |
|  |  |  |  |  |  | `cell` | cell | 31 | 0 | 63 | 1 | — |
| `lsystem` | L-system | Dynamical systems | A → AB, B → A | yes | yes | `depth` | depth | 10 | 2 | 16 | 1 | — |
| `sine` | Sine contour | Geometry & waves | a sin(2πkn/P + φ) + c | no | yes | `cycles` | k | 1 | 0.25 | 16 | 0.25 | 1, 2, 3, 4, 8 |
|  |  |  |  |  |  | `phase` | φ | 0 | 0 | 1 | 0.01 | 0, 0.25, 0.5, 0.75 |
|  |  |  |  |  |  | `depth` | a | 1 | 0 | 2 | 0.01 | — |
|  |  |  |  |  |  | `offset` | c | 0 | -1 | 1 | 0.01 | — |
| `triangle` | Triangle contour | Geometry & waves | a tri(kn/P + φ) + c | no | yes | `cycles` | k | 1 | 0.25 | 16 | 0.25 | 1, 2, 3, 4, 8 |
|  |  |  |  |  |  | `phase` | φ | 0 | 0 | 1 | 0.01 | 0, 0.25, 0.5, 0.75 |
|  |  |  |  |  |  | `depth` | a | 1 | 0 | 2 | 0.01 | — |
|  |  |  |  |  |  | `offset` | c | 0 | -1 | 1 | 0.01 | — |
| `saw` | Saw contour | Geometry & waves | a saw(kn/P + φ) + c | no | yes | `cycles` | k | 1 | 0.25 | 16 | 0.25 | 1, 2, 3, 4, 8 |
|  |  |  |  |  |  | `phase` | φ | 0 | 0 | 1 | 0.01 | 0, 0.25, 0.5, 0.75 |
|  |  |  |  |  |  | `depth` | a | 1 | 0 | 2 | 0.01 | — |
|  |  |  |  |  |  | `offset` | c | 0 | -1 | 1 | 0.01 | — |
| `square` | Square contour | Geometry & waves | a sign(sin(2πkn/P + φ)) + c | no | yes | `cycles` | k | 1 | 0.25 | 16 | 0.25 | 1, 2, 3, 4, 8 |
|  |  |  |  |  |  | `phase` | φ | 0 | 0 | 1 | 0.01 | 0, 0.25, 0.5, 0.75 |
|  |  |  |  |  |  | `depth` | a | 1 | 0 | 2 | 0.01 | — |
|  |  |  |  |  |  | `offset` | c | 0 | -1 | 1 | 0.01 | — |
| `lissajous` | Lissajous p:q | Geometry & waves | x = sin(pθ), y = sin(qθ + φ) | no | yes | `p` | p | 3 | 1 | 12 | 1 | — |
|  |  |  |  |  |  | `q` | q | 2 | 1 | 12 | 1 | — |
|  |  |  |  |  |  | `phase` | φ | 0.25 | 0 | 1 | 0.01 | — |
| `rose` | Rose curve | Geometry & waves | r = |cos(kθ)| | no | yes | `k` | k | 5 | 1 | 16 | 1 | — |
| `superformula` | Superformula | Geometry & waves | r = (|cos(mφ/4)|ⁿ² + |sin(mφ/4)|ⁿ³)⁻¹/ⁿ¹ | no | yes | `m` | m | 5 | 2 | 16 | 0.1 | — |
|  |  |  |  |  |  | `n1` | n₁ | 0.4 | 0.2 | 8 | 0.05 | — |
|  |  |  |  |  |  | `n2` | n₂ | 1.7 | 0.2 | 8 | 0.05 | — |
|  |  |  |  |  |  | `n3` | n₃ | 1.7 | 0.2 | 8 | 0.05 | — |
| `spirograph` | Spirograph | Geometry & waves | (R−r)eⁱᶿ + de⁻ⁱ⁽ᴿ⁻ʳ⁾ᶿ/ʳ | no | yes | `R` | R | 5 | 2 | 16 | 1 | — |
|  |  |  |  |  |  | `r` | r | 3 | 1 | 15 | 1 | — |
|  |  |  |  |  |  | `d` | d | 2 | 0 | 10 | 0.1 | — |
| `polygon` | Star polygon | Geometry & waves | vertex(nq mod p) · {p/q} | yes | yes | `p` | p | 7 | 3 | 16 | 1 | — |
|  |  |  |  |  |  | `q` | q | 2 | 1 | 15 | 1 | — |
| `vertices` | Rotating vertices | Geometry & waves | cos(2πn·speed / sides) | no | yes | `sides` | sides | 5 | 3 | 16 | 1 | — |
|  |  |  |  |  |  | `speed` | speed | 1 | 1 | 8 | 1 | — |
| `polynomial` | Polynomial | Geometry & waves | ax³ + bx² + cx | no | yes | `a` | a | 1 | -3 | 3 | 0.01 | — |
|  |  |  |  |  |  | `b` | b | 0 | -3 | 3 | 0.01 | — |
|  |  |  |  |  |  | `c` | c | -1 | -3 | 3 | 0.01 | — |
| `times` | Times-table circle | Geometry & waves | m·n mod N | yes | yes | `m` | m | 2 | 1 | 24 | 1 | — |
|  |  |  |  |  |  | `N` | N | 12 | 2 | 64 | 1 | — |
| `cardioid` | Cardioid | Geometry & waves | r = 1 − cos θ | no | yes | — | — | — | — | — | — | — |
| `astroid` | Astroid | Geometry & waves | x = cos³θ, y = sin³θ | no | yes | — | — | — | — | — | — | — |
| `spiral` | Archimedean spiral | Geometry & waves | r = θ / 2π | no | yes | — | — | — | — | — | — | — |
| `butterfly` | Butterfly | Geometry & waves | r = eᶜᵒˢᶿ − 2cos(4θ) + sin⁵(θ/12) | no | yes | — | — | — | — | — | — | — |
| `harmonograph` | Harmonograph | Geometry & waves | sin(pθ)e⁻ᵈᶿ + sin(qθ+φ)e⁻ᵈᶿ | no | yes | `p` | p | 2 | 1 | 8 | 1 | — |
|  |  |  |  |  |  | `q` | q | 3 | 1 | 8 | 1 | — |
|  |  |  |  |  |  | `decay` | d | 0.02 | 0 | 0.2 | 0.005 | — |
|  |  |  |  |  |  | `phase` | φ | 0.25 | 0 | 1 | 0.01 | — |
| `groove` | Genre groove | Rhythm & gates | g(n; genre, voice, density, rotation) | no | yes | `genre` | Genre | 0 | 0 | 10 | 1 | — |
|  |  |  |  |  |  | `voice` | Drum | 0 | 0 | 7 | 1 | — |
|  |  |  |  |  |  | `density` | Density | 1 | 0 | 2 | 0.05 | — |
|  |  |  |  |  |  | `rotation` | Rotation | 0 | 0 | 31 | 1 | — |
| `euclid` | Euclidean E(k,n,r) | Rhythm & gates | E(k, n, rotation) | yes | yes | `k` | k | 5 | 0 | 32 | 1 | — |
|  |  |  |  |  |  | `n` | n | 16 | 1 | 32 | 1 | 8, 12, 16, 24, 32 |
|  |  |  |  |  |  | `rot` | rot | 0 | 0 | 31 | 1 | — |
| `modgate` | Modulo gate | Rhythm & gates | n mod d = 0 | yes | yes | `d` | d | 2 | 1 | 32 | 1 | — |
|  |  |  |  |  |  | `rot` | rot | 0 | 0 | 31 | 1 | — |
| `staircase` | Floor staircase | Rhythm & gates | ⌊(q+1)k/n⌋ − ⌊qk/n⌋ | yes | yes | `k` | k | 5 | 0 | 32 | 1 | — |
|  |  |  |  |  |  | `n` | n | 8 | 1 | 32 | 1 | — |
| `bit` | Binary-count bit | Rhythm & gates | (n ≫ k) & 1 | yes | yes | `bit` | k | 2 | 0 | 12 | 1 | — |
| `polymeter` | Polymeter | Rhythm & gates | (n mod a = 0) ∨ (n mod b = 0) | yes | yes | `a` | a | 3 | 1 | 16 | 1 | — |
|  |  |  |  |  |  | `b` | b | 4 | 1 | 16 | 1 | — |
| `zeno` | Zeno roll | Rhythm & gates | tₖ = L(1 − qᵏ) | yes | yes | `q` | q | 0.8 | 0.4 | 0.95 | 0.01 | 0.5, 0.8 |
|  |  |  |  |  |  | `L` | L | 16 | 4 | 64 | 1 | — |
| `circlechord` | Diatonic circle | Harmony | degree = 3n mod 7 | yes | yes | — | — | — | — | — | — | — |
| `extension` | Extension ladder | Harmony | stack = 3 + n mod 5 | yes | yes | — | — | — | — | — | — | — |
| `voicelead` | Voice-leading walk | Harmony | inversion = n mod voices | yes | yes | `voices` | voices | 3 | 3 | 7 | 1 | — |
| `spread` | Spread / strum | Harmony | spread = ½ + ½ sin(2πn/P) | no | yes | — | — | — | — | — | — | — |
| `plr` | Neo-Riemannian P/L/R | Harmony | P: parallel · L: leading-tone · R: relative | yes | yes | `move` | move | 0 | 0 | 2 | 1 | — |
| `accent` | Metric accent mask | Expression | 1 on beat, ½ on eighth, ¼ elsewhere | no | yes | — | — | — | — | — | — | — |
| `crescendo` | Crescendo ramp | Expression | v = (n mod L) / (L − 1) | no | yes | `length` | L | 32 | 2 | 128 | 1 | — |

## Scales (13)

Scale names are the values accepted for the scale control. Intervals are semitone offsets from the root.

| Scale name | Semitone intervals |
| --- | --- |
| Major | 0, 2, 4, 5, 7, 9, 11 |
| Minor | 0, 2, 3, 5, 7, 8, 10 |
| Dorian | 0, 2, 3, 5, 7, 9, 10 |
| Mixolydian | 0, 2, 4, 5, 7, 9, 10 |
| Lydian | 0, 2, 4, 6, 7, 9, 11 |
| Phrygian | 0, 1, 3, 5, 7, 8, 10 |
| Locrian | 0, 1, 3, 5, 6, 8, 10 |
| Harmonic Minor | 0, 2, 3, 5, 7, 8, 11 |
| Melodic Minor | 0, 2, 3, 5, 7, 9, 11 |
| Minor Pentatonic | 0, 3, 5, 7, 10 |
| Major Pentatonic | 0, 2, 4, 7, 9 |
| Whole Tone | 0, 2, 4, 6, 8, 10 |
| Chromatic | 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 |

## Drum genres (11)

A genre sets the first four drum lanes, in this order: 1. Kick, 2. Snare, 3. Closed hat, 4. Open hat. Each lane pattern is a Euclidean gate `[k, n, rotation]`: k hits spread across n steps, rotated by the rotation value.

| Genre | Lane | Hits (k) | Steps (n) | Rotation |
| --- | --- | --- | --- | --- |
| House | Kick | 4 | 16 | 0 |
| House | Snare | 2 | 16 | 4 |
| House | Closed hat | 8 | 16 | 2 |
| House | Open hat | 4 | 16 | 2 |
| Lo-fi 80 | Kick | 3 | 16 | 0 |
| Lo-fi 80 | Snare | 2 | 16 | 4 |
| Lo-fi 80 | Closed hat | 7 | 16 | 0 |
| Lo-fi 80 | Open hat | 3 | 16 | 2 |
| Boom bap | Kick | 3 | 16 | 0 |
| Boom bap | Snare | 2 | 16 | 4 |
| Boom bap | Closed hat | 8 | 16 | 0 |
| Boom bap | Open hat | 2 | 16 | 7 |
| Trap | Kick | 3 | 16 | 0 |
| Trap | Snare | 1 | 16 | 8 |
| Trap | Closed hat | 12 | 16 | 0 |
| Trap | Open hat | 3 | 16 | 3 |
| Drill | Kick | 5 | 32 | 0 |
| Drill | Snare | 2 | 32 | 8 |
| Drill | Closed hat | 11 | 32 | 0 |
| Drill | Open hat | 3 | 16 | 5 |
| Jersey club | Kick | 5 | 16 | 0 |
| Jersey club | Snare | 4 | 16 | 2 |
| Jersey club | Closed hat | 8 | 16 | 0 |
| Jersey club | Open hat | 3 | 8 | 0 |
| Dancehall | Kick | 3 | 8 | 0 |
| Dancehall | Snare | 2 | 16 | 4 |
| Dancehall | Closed hat | 8 | 16 | 0 |
| Dancehall | Open hat | 5 | 16 | 3 |
| Reggaeton | Kick | 4 | 16 | 0 |
| Reggaeton | Snare | 5 | 16 | 2 |
| Reggaeton | Closed hat | 8 | 16 | 0 |
| Reggaeton | Open hat | 3 | 8 | 0 |
| Jungle | Kick | 7 | 32 | 0 |
| Jungle | Snare | 4 | 32 | 4 |
| Jungle | Closed hat | 14 | 32 | 0 |
| Jungle | Open hat | 5 | 16 | 2 |
| Rock | Kick | 2 | 8 | 0 |
| Rock | Snare | 2 | 8 | 2 |
| Rock | Closed hat | 8 | 16 | 0 |
| Rock | Open hat | 1 | 16 | 0 |
| Funk / disco | Kick | 4 | 16 | 0 |
| Funk / disco | Snare | 2 | 16 | 4 |
| Funk / disco | Closed hat | 13 | 16 | 0 |
| Funk / disco | Open hat | 5 | 16 | 2 |

## Top-level API functions (33)

`applyPending`, `boundary`, `buildProgress`, `channel`, `chordAt`, `clamp`, `cleanParams`, `command`, `compileChannel`, `compileTimeline`, `copy`, `defaults`, `degreeMidi`, `drumSample`, `euclid`, `fold`, `gcd`, `groovePattern`, `importState`, `initialState`, `laneHit`, `lcm`, `mod`, `normal`, `period`, `playPads`, `preset`, `ratioChoices`, `rawValue`, `scaleNotes`, `sumPeriod`, `sumValue`, `value`
