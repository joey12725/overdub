### current: A `#ff4d6d` B `#ffd23f` C `#3ec5ff` D `#7dff6b`

Pairwise CIEDE2000:

| vision | A-B | A-C | A-D | B-C | B-D | C-D | min |
|---|---|---|---|---|---|---|---|
| normal | 53.5 | 62.2 | 83.8 | 56.0 | 31.0 | 53.6 | **31.0** (B-D) |
| protanopia | 36.1 | 35.0 | 39.4 | 52.5 | 6.4 | 52.2 | **6.4** (B-D) |
| deuteranopia | 21.1 | 44.3 | 19.2 | 56.9 | 5.0 | 53.2 | **5.0** (B-D) |
| tritanopia | 28.7 | 84.5 | 76.4 | 44.6 | 46.0 | 12.3 | **12.3** (C-D) |

WCAG contrast ratio of the bare colour against each theme surface:

| theme | surface | hex | A | B | C | D |
|---|---|---|---|---|---|---|
| upper | floor_color | `#dcb9a0` | 1.76 | 1.27 | 1.08 | 1.43 |
| upper | floor_alt | `#caa58e` | 1.42 | 1.57 | 1.15 | 1.77 |
| upper | wall | `#b99178` | 1.13 | 1.97 | 1.44 | 2.22 |
| upper | wall_top | `#eed4b8` | 2.26 | 1.01 | 1.39 | 1.11 |
| mid | floor_color | `#a49a90` | 1.16 | 1.91 | 1.40 | 2.16 |
| mid | floor_alt | `#8e857e` | 1.13 | 2.50 | 1.83 | 2.82 |
| mid | wall | `#857a72` | 1.30 | 2.89 | 2.12 | 3.26 |
| mid | wall_top | `#b0a598` | 1.33 | 1.68 | 1.23 | 1.89 |
| lower | floor_color | `#7a6884` | 1.58 | 3.51 | 2.57 | 3.96 |
| lower | floor_alt | `#6b5a75` | 1.95 | 4.35 | 3.18 | 4.90 |
| lower | wall | `#463a4f` | 3.30 | 7.35 | 5.38 | 8.28 |
| lower | wall_top | `#7a6684` | 1.61 | 3.58 | 2.62 | 4.04 |
| core | floor_color | `#58566f` | 2.20 | 4.89 | 3.57 | 5.51 |
| core | floor_alt | `#4c4a62` | 2.65 | 5.90 | 4.32 | 6.65 |
| core | wall | `#34324c` | 3.83 | 8.52 | 6.23 | 9.60 |
| core | wall_top | `#5e5c80` | 1.97 | 4.38 | 3.20 | 4.94 |

Contrast against HUD surfaces:

| surface | hex | A | B | C | D |
|---|---|---|---|---|---|
| panel | `#1b1714` | 5.54 | 12.33 | 9.02 | 13.90 |
| track | `#0d0b0a` | 6.11 | 13.60 | 9.95 | 15.33 |
| paper | `#f3ead8` | 2.69 | 1.21 | 1.65 | 1.07 |
| ink | `#14110f` | 5.85 | 13.02 | 9.52 | 14.67 |

CIEDE2000 to colours with a reserved meaning (normal / worst dichromat):

| reserved | hex | A | B | C | D |
|---|---|---|---|---|---|
| moxie_yellow | `#ffd23f` | 54 / 21 | **0 / 0** | 56 / 45 | 31 / 5 |
| hazard_upper | `#ffc21a` | 50 / 20 | **5 / 3** | 56 / 49 | 36 / 7 |
| hazard_lower | `#ffb020` | 44 / 18 | **11 / 5** | 55 / 52 | 42 / 8 |
| enemy_eye | `#ff6a1a` | 24 / 4 | 34 / 14 | 56 / 53 | 66 / 15 |
| enemy_warning | `#ff3d3d` | **11 / 6** | 48 / 19 | 62 / 49 | 81 / 19 |
| enemy_fx | `#ff3d5a` | **4 / 4** | 53 / 20 | 63 / 41 | 84 / 19 |
| laser | `#ff2b5e` | **4 / 3** | 56 / 22 | 65 / 40 | 87 / 21 |
| door_closed | `#ff3048` | **8 / 7** | 52 / 20 | 63 / 46 | 84 / 20 |
| rec_red | `#ff2a3d` | **10 / 8** | 51 / 20 | 63 / 49 | 83 / 20 |
| chronal_amber | `#ffb347` | 41 / 17 | 12 / 5 | 53 / 50 | 42 / 6 |
| ghost_grey | `#7d8394` | 32 / 15 | 44 / 35 | 27 / 21 | 47 / 33 |
| state_dead | `#9aa3b5` | 34 / 21 | 40 / 31 | 21 / 14 | 42 / 25 |
| state_desync | `#c98bff` | 31 / 27 | 66 / 18 | 37 / 3 | 58 / 46 |
| boss_recall | `#b26bff` | 32 / 28 | 72 / 25 | 38 / 11 | 63 / 45 |
| shield_teal | `#58f0dc` | 72 / 28 | 39 / 26 | 26 / 8 | 24 / 6 |

CIEDE2000 to theme accents, normal vision (rows with a value under 25 only):

| theme | accent | hex | A | B | C | D |
|---|---|---|---|---|---|---|
| upper | neon_a | `#4fe6e0` | 68 | 41 | 21 | 29 |
| upper | neon_b | `#ff3d9a` | **12** | 64 | 65 | 92 |
| upper | graffiti | `#ff3fa4` | **14** | 66 | 64 | 93 |
| upper | hazard | `#ffc21a` | 50 | **5** | 56 | 36 |
| upper | foliage | `#93c22c` | 70 | 23 | 55 | 16 |
| upper | rune | `#ffd27a` | 46 | **7** | 50 | 32 |
| upper | accent | `#ff3d9a` | **12** | 64 | 65 | 92 |
| upper | warm | `#ffb45a` | 38 | **14** | 51 | 43 |
| mid | neon_a | `#2fe6ff` | 80 | 47 | **13** | 40 |
| mid | neon_b | `#ff3fb4` | 17 | 68 | 63 | 94 |
| mid | graffiti | `#ff4fae` | **15** | 65 | 62 | 92 |
| mid | hazard | `#ffb81c` | 47 | **8** | 55 | 39 |
| mid | foliage | `#76ad3c` | 69 | 28 | 52 | 20 |
| mid | rune | `#4ff0ff` | 81 | 44 | 16 | 36 |
| mid | accent | `#2fe6ff` | 80 | 47 | **13** | 40 |
| mid | warm | `#ffa04a` | 33 | 20 | 50 | 50 |
| mid | rust | `#c8662a` | 25 | 35 | 54 | 62 |
| lower | neon_a | `#3ff0ff` | 82 | 45 | 17 | 36 |
| lower | neon_b | `#ff2fa0` | **14** | 67 | 65 | 94 |
| lower | graffiti | `#ff3fa4` | **14** | 66 | 64 | 93 |
| lower | hazard | `#ffb020` | 44 | **11** | 55 | 42 |
| lower | rune | `#ff3fd0` | 21 | 71 | 60 | 97 |
| lower | accent | `#ff2fa0` | **14** | 67 | 65 | 94 |
| core | neon_a | `#3ff0ff` | 82 | 45 | 17 | 36 |
| core | neon_b | `#ff2fa0` | **14** | 67 | 65 | 94 |
| core | graffiti | `#ff3fa4` | **14** | 66 | 64 | 93 |
| core | hazard | `#ffc23a` | 48 | **6** | 55 | 36 |
| core | rune | `#ffb347` | 41 | **12** | 53 | 42 |
| core | accent | `#ffb347` | 41 | **12** | 53 | 42 |
| core | warm | `#ff9a3a` | 34 | 21 | 51 | 52 |
| core | rust | `#c0602a` | 24 | 37 | 54 | 63 |

### proposed: A `#ff94c4` B `#fff51f` C `#1a7dff` D `#8cffc6`

Pairwise CIEDE2000:

| vision | A-B | A-C | A-D | B-C | B-D | C-D | min |
|---|---|---|---|---|---|---|---|
| normal | 65.0 | 38.4 | 68.1 | 76.7 | 29.9 | 54.2 | **29.9** (B-D) |
| protanopia | 47.2 | 19.6 | 33.7 | 70.5 | 19.0 | 53.4 | **19.0** (B-D) |
| deuteranopia | 35.4 | 32.1 | 16.5 | 76.6 | 22.2 | 51.5 | **16.5** (A-D) |
| tritanopia | 25.7 | 60.9 | 61.8 | 39.7 | 32.8 | 27.1 | **25.7** (A-B) |

WCAG contrast ratio of the bare colour against each theme surface:

| theme | surface | hex | A | B | C | D |
|---|---|---|---|---|---|---|
| upper | floor_color | `#dcb9a0` | 1.12 | 1.60 | 2.12 | 1.50 |
| upper | floor_alt | `#caa58e` | 1.11 | 1.97 | 1.71 | 1.86 |
| upper | wall | `#b99178` | 1.39 | 2.48 | 1.36 | 2.33 |
| upper | wall_top | `#eed4b8` | 1.43 | 1.24 | 2.72 | 1.17 |
| mid | floor_color | `#a49a90` | 1.35 | 2.41 | 1.40 | 2.27 |
| mid | floor_alt | `#8e857e` | 1.77 | 3.16 | 1.07 | 2.97 |
| mid | wall | `#857a72` | 2.05 | 3.65 | 1.08 | 3.43 |
| mid | wall_top | `#b0a598` | 1.18 | 2.11 | 1.60 | 1.99 |
| lower | floor_color | `#7a6884` | 2.48 | 4.43 | 1.31 | 4.16 |
| lower | floor_alt | `#6b5a75` | 3.08 | 5.48 | 1.62 | 5.15 |
| lower | wall | `#463a4f` | 5.20 | 9.27 | 2.74 | 8.71 |
| lower | wall_top | `#7a6684` | 2.53 | 4.51 | 1.33 | 4.24 |
| core | floor_color | `#58566f` | 3.46 | 6.16 | 1.82 | 5.79 |
| core | floor_alt | `#4c4a62` | 4.18 | 7.44 | 2.20 | 7.00 |
| core | wall | `#34324c` | 6.03 | 10.74 | 3.18 | 10.10 |
| core | wall_top | `#5e5c80` | 3.10 | 5.52 | 1.63 | 5.19 |

Contrast against HUD surfaces:

| surface | hex | A | B | C | D |
|---|---|---|---|---|---|
| panel | `#1b1714` | 8.72 | 15.55 | 4.60 | 14.61 |
| track | `#0d0b0a` | 9.62 | 17.14 | 5.07 | 16.12 |
| paper | `#f3ead8` | 1.71 | 1.04 | 3.24 | 1.02 |
| ink | `#14110f` | 9.21 | 16.42 | 4.85 | 15.43 |

CIEDE2000 to colours with a reserved meaning (normal / worst dichromat):

| reserved | hex | A | B | C | D |
|---|---|---|---|---|---|
| moxie_yellow | `#ffd23f` | 55 / 14 | **11 / 6** | 68 / 53 | 34 / 18 |
| hazard_upper | `#ffc21a` | 53 / 11 | 16 / 8 | 66 / 56 | 38 / 20 |
| hazard_lower | `#ffb020` | 48 / 8 | 23 / 10 | 62 / 59 | 43 / 22 |
| enemy_eye | `#ff6a1a` | 35 / 16 | 47 / 19 | 52 / 60 | 62 / 25 |
| enemy_warning | `#ff3d3d` | 27 / 22 | 61 / 24 | 47 / 51 | 74 / 25 |
| enemy_fx | `#ff3d5a` | 22 / 20 | 66 / 25 | 45 / 41 | 77 / 23 |
| laser | `#ff2b5e` | 22 / 21 | 69 / 27 | 44 / 37 | 79 / 23 |
| door_closed | `#ff3048` | 25 / 22 | 65 / 25 | 46 / 47 | 77 / 25 |
| rec_red | `#ff2a3d` | 27 / 23 | 64 / 25 | 47 / 50 | 76 / 26 |
| chronal_amber | `#ffb347` | 45 / 8 | 24 / 10 | 60 / 58 | 42 / 19 |
| ghost_grey | `#7d8394` | 29 / 13 | 52 / 33 | 20 / 17 | 40 / 34 |
| state_dead | `#9aa3b5` | 26 / 4 | 47 / 26 | 21 / 16 | 34 / 26 |
| state_desync | `#c98bff` | 19 / 14 | 77 / 25 | 25 / 8 | 50 / 40 |
| boss_recall | `#b26bff` | 24 / 19 | 83 / 31 | 22 / 0 | 54 / 46 |
| shield_teal | `#58f0dc` | 58 / 6 | 37 / 28 | 46 / 25 | **11 / 4** |

CIEDE2000 to theme accents, normal vision (rows with a value under 25 only):

| theme | accent | hex | A | B | C | D |
|---|---|---|---|---|---|---|
| upper | neon_a | `#4fe6e0` | 59 | 40 | 42 | 16 |
| upper | neon_b | `#ff3d9a` | **15** | 77 | 40 | 82 |
| upper | neon_c | `#c06bff` | 22 | 83 | 25 | 54 |
| upper | graffiti | `#ff3fa4` | **14** | 78 | 39 | 83 |
| upper | graffiti_alt | `#a65ee0` | 26 | 83 | 23 | 56 |
| upper | hazard | `#ffc21a` | 53 | 16 | 66 | 38 |
| upper | foliage | `#93c22c` | 68 | 20 | 69 | 23 |
| upper | rune | `#ffd27a` | 46 | 16 | 61 | 33 |
| upper | accent | `#ff3d9a` | **15** | 77 | 40 | 82 |
| mid | neon_b | `#ff3fb4` | **14** | 80 | 38 | 84 |
| mid | neon_c | `#9b5cff` | 29 | 86 | 20 | 57 |
| mid | graffiti | `#ff4fae` | **12** | 77 | 39 | 81 |
| mid | graffiti_alt | `#a65ee0` | 26 | 83 | 23 | 56 |
| mid | hazard | `#ffb81c` | 51 | 20 | 64 | 41 |
| mid | foliage | `#76ad3c` | 67 | 27 | 63 | 24 |
| mid | rune | `#4ff0ff` | 63 | 44 | 39 | 23 |
| lower | neon_a | `#3ff0ff` | 64 | 45 | 40 | 23 |
| lower | neon_b | `#ff2fa0` | 16 | 79 | 40 | 84 |
| lower | graffiti | `#ff3fa4` | **14** | 78 | 39 | 83 |
| lower | graffiti_alt | `#b04dff` | 27 | 88 | 24 | 57 |
| lower | hazard | `#ffb020` | 48 | 23 | 62 | 43 |
| lower | rune | `#ff3fd0` | 16 | 84 | 37 | 56 |
| lower | accent | `#ff2fa0` | 16 | 79 | 40 | 84 |
| core | neon_a | `#3ff0ff` | 64 | 45 | 40 | 23 |
| core | neon_b | `#ff2fa0` | 16 | 79 | 40 | 84 |
| core | neon_c | `#8a4dff` | 32 | 89 | 20 | 59 |
| core | graffiti | `#ff3fa4` | **14** | 78 | 39 | 83 |
| core | graffiti_alt | `#9a5cff` | 29 | 86 | 20 | 57 |
| core | hazard | `#ffc23a` | 51 | 17 | 64 | 38 |
| core | rune | `#ffb347` | 45 | 24 | 60 | 42 |
| core | accent | `#ffb347` | 45 | 24 | 60 | 42 |

### coral_variant: A `#ff7a66` B `#fff51f` C `#1a7dff` D `#8cffc6`

Pairwise CIEDE2000:

| vision | A-B | A-C | A-D | B-C | B-D | C-D | min |
|---|---|---|---|---|---|---|---|
| normal | 51.8 | 46.1 | 63.8 | 76.7 | 29.9 | 54.2 | **29.9** (B-D) |
| protanopia | 29.5 | 47.5 | 24.9 | 70.5 | 19.0 | 53.4 | **19.0** (B-D) |
| deuteranopia | 19.9 | 59.1 | 18.1 | 76.6 | 22.2 | 51.5 | **18.1** (A-D) |
| tritanopia | 31.9 | 66.7 | 68.4 | 39.7 | 32.8 | 27.1 | **27.1** (C-D) |

WCAG contrast ratio of the bare colour against each theme surface:

| theme | surface | hex | A | B | C | D |
|---|---|---|---|---|---|---|
| upper | floor_color | `#dcb9a0` | 1.40 | 1.60 | 2.12 | 1.50 |
| upper | floor_alt | `#caa58e` | 1.13 | 1.97 | 1.71 | 1.86 |
| upper | wall | `#b99178` | 1.11 | 2.48 | 1.36 | 2.33 |
| upper | wall_top | `#eed4b8` | 1.79 | 1.24 | 2.72 | 1.17 |
| mid | floor_color | `#a49a90` | 1.08 | 2.41 | 1.40 | 2.27 |
| mid | floor_alt | `#8e857e` | 1.42 | 3.16 | 1.07 | 2.97 |
| mid | wall | `#857a72` | 1.64 | 3.65 | 1.08 | 3.43 |
| mid | wall_top | `#b0a598` | 1.06 | 2.11 | 1.60 | 1.99 |
| lower | floor_color | `#7a6884` | 1.99 | 4.43 | 1.31 | 4.16 |
| lower | floor_alt | `#6b5a75` | 2.46 | 5.48 | 1.62 | 5.15 |
| lower | wall | `#463a4f` | 4.16 | 9.27 | 2.74 | 8.71 |
| lower | wall_top | `#7a6684` | 2.03 | 4.51 | 1.33 | 4.24 |
| core | floor_color | `#58566f` | 2.77 | 6.16 | 1.82 | 5.79 |
| core | floor_alt | `#4c4a62` | 3.34 | 7.44 | 2.20 | 7.00 |
| core | wall | `#34324c` | 4.82 | 10.74 | 3.18 | 10.10 |
| core | wall_top | `#5e5c80` | 2.48 | 5.52 | 1.63 | 5.19 |

Contrast against HUD surfaces:

| surface | hex | A | B | C | D |
|---|---|---|---|---|---|
| panel | `#1b1714` | 6.98 | 15.55 | 4.60 | 14.61 |
| track | `#0d0b0a` | 7.69 | 17.14 | 5.07 | 16.12 |
| paper | `#f3ead8` | 2.14 | 1.04 | 3.24 | 1.02 |
| ink | `#14110f` | 7.37 | 16.42 | 4.85 | 15.43 |

CIEDE2000 to colours with a reserved meaning (normal / worst dichromat):

| reserved | hex | A | B | C | D |
|---|---|---|---|---|---|
| moxie_yellow | `#ffd23f` | 40 / 15 | **11 / 6** | 68 / 53 | 34 / 18 |
| hazard_upper | `#ffc21a` | 36 / 14 | 16 / 8 | 66 / 56 | 38 / 20 |
| hazard_lower | `#ffb020` | 30 / 12 | 23 / 10 | 62 / 59 | 43 / 22 |
| enemy_eye | `#ff6a1a` | 13 / 5 | 47 / 19 | 52 / 60 | 62 / 25 |
| enemy_warning | `#ff3d3d` | **10 / 8** | 61 / 24 | 47 / 51 | 74 / 25 |
| enemy_fx | `#ff3d5a` | 12 / 6 | 66 / 25 | 45 / 41 | 77 / 23 |
| laser | `#ff2b5e` | 15 / 8 | 69 / 27 | 44 / 37 | 79 / 23 |
| door_closed | `#ff3048` | 12 / 7 | 65 / 25 | 46 / 47 | 77 / 25 |
| rec_red | `#ff2a3d` | 12 / 8 | 64 / 25 | 47 / 50 | 76 / 26 |
| chronal_amber | `#ffb347` | 28 / 10 | 24 / 10 | 60 / 58 | 42 / 19 |
| ghost_grey | `#7d8394` | 33 / 26 | 52 / 33 | 20 / 17 | 40 / 34 |
| state_dead | `#9aa3b5` | 32 / 27 | 47 / 26 | 21 / 16 | 34 / 26 |
| state_desync | `#c98bff` | 36 / 22 | 77 / 25 | 25 / 8 | 50 / 40 |
| boss_recall | `#b26bff` | 39 / 24 | 83 / 31 | 22 / 0 | 54 / 46 |
| shield_teal | `#58f0dc` | 61 / 26 | 37 / 28 | 46 / 25 | **11 / 4** |

CIEDE2000 to theme accents, normal vision (rows with a value under 25 only):

| theme | accent | hex | A | B | C | D |
|---|---|---|---|---|---|---|
| upper | neon_a | `#4fe6e0` | 58 | 40 | 42 | 16 |
| upper | neon_b | `#ff3d9a` | 24 | 77 | 40 | 82 |
| upper | neon_c | `#c06bff` | 38 | 83 | 25 | 54 |
| upper | graffiti_alt | `#a65ee0` | 39 | 83 | 23 | 56 |
| upper | hazard | `#ffc21a` | 36 | 16 | 66 | 38 |
| upper | foliage | `#93c22c` | 57 | 20 | 69 | 23 |
| upper | rune | `#ffd27a` | 33 | 16 | 61 | 33 |
| upper | accent | `#ff3d9a` | 24 | 77 | 40 | 82 |
| upper | rust | `#d8742a` | 16 | 42 | 52 | 56 |
| mid | neon_c | `#9b5cff` | 41 | 86 | 20 | 57 |
| mid | graffiti_alt | `#a65ee0` | 39 | 83 | 23 | 56 |
| mid | hazard | `#ffb81c` | 33 | 20 | 64 | 41 |
| mid | foliage | `#76ad3c` | 57 | 27 | 63 | 24 |
| mid | rune | `#4ff0ff` | 56 | 44 | 39 | 23 |
| mid | warm | `#ffa04a` | 20 | 32 | 56 | 48 |
| mid | rust | `#c8662a` | 17 | 46 | 50 | 59 |
| lower | neon_a | `#3ff0ff` | 57 | 45 | 40 | 23 |
| lower | graffiti_alt | `#b04dff` | 40 | 88 | 24 | 57 |
| lower | hazard | `#ffb020` | 30 | 23 | 62 | 43 |
| lower | warm | `#ff8a2a` | 18 | 38 | 55 | 54 |
| lower | rust | `#d06a28` | 16 | 45 | 50 | 58 |
| core | neon_a | `#3ff0ff` | 57 | 45 | 40 | 23 |
| core | neon_c | `#8a4dff` | 44 | 89 | 20 | 59 |
| core | graffiti_alt | `#9a5cff` | 41 | 86 | 20 | 57 |
| core | hazard | `#ffc23a` | 34 | 17 | 64 | 38 |
| core | rune | `#ffb347` | 28 | 24 | 60 | 42 |
| core | accent | `#ffb347` | 28 | 24 | 60 | 42 |
| core | warm | `#ff9a3a` | 20 | 33 | 56 | 50 |
| core | rust | `#c0602a` | 18 | 48 | 49 | 60 |

### high_contrast: A `#ffb3e0` B `#f6fa00` C `#0a55c8` D `#189e95`

Pairwise CIEDE2000:

| vision | A-B | A-C | A-D | B-C | B-D | C-D | min |
|---|---|---|---|---|---|---|---|
| normal | 63.5 | 46.1 | 50.6 | 85.7 | 44.7 | 40.3 | **40.3** (C-D) |
| protanopia | 46.9 | 33.4 | 18.1 | 77.1 | 37.3 | 31.4 | **18.1** (A-D) |
| deuteranopia | 41.5 | 43.0 | 20.2 | 83.1 | 48.8 | 26.4 | **20.2** (A-D) |
| tritanopia | 22.9 | 57.5 | 58.8 | 48.3 | 38.3 | 20.2 | **20.2** (C-D) |

WCAG contrast ratio of the bare colour against each theme surface:

| theme | surface | hex | A | B | C | D |
|---|---|---|---|---|---|---|
| upper | floor_color | `#dcb9a0` | 1.11 | 1.62 | 3.65 | 1.81 |
| upper | floor_alt | `#caa58e` | 1.38 | 2.00 | 2.95 | 1.46 |
| upper | wall | `#b99178` | 1.73 | 2.52 | 2.35 | 1.16 |
| upper | wall_top | `#eed4b8` | 1.15 | 1.26 | 4.69 | 2.32 |
| mid | floor_color | `#a49a90` | 1.68 | 2.45 | 2.42 | 1.19 |
| mid | floor_alt | `#8e857e` | 2.20 | 3.20 | 1.85 | 1.10 |
| mid | wall | `#857a72` | 2.54 | 3.70 | 1.60 | 1.27 |
| mid | wall_top | `#b0a598` | 1.47 | 2.14 | 2.76 | 1.36 |
| lower | floor_color | `#7a6884` | 3.09 | 4.49 | 1.32 | 1.54 |
| lower | floor_alt | `#6b5a75` | 3.82 | 5.56 | 1.06 | 1.90 |
| lower | wall | `#463a4f` | 6.46 | 9.40 | 1.59 | 3.22 |
| lower | wall_top | `#7a6684` | 3.15 | 4.58 | 1.29 | 1.57 |
| core | floor_color | `#58566f` | 4.29 | 6.25 | 1.06 | 2.14 |
| core | floor_alt | `#4c4a62` | 5.19 | 7.55 | 1.28 | 2.58 |
| core | wall | `#34324c` | 7.49 | 10.89 | 1.84 | 3.73 |
| core | wall_top | `#5e5c80` | 3.85 | 5.60 | 1.05 | 1.92 |

Contrast against HUD surfaces:

| surface | hex | A | B | C | D |
|---|---|---|---|---|---|
| panel | `#1b1714` | 10.83 | 15.77 | 2.67 | 5.40 |
| track | `#0d0b0a` | 11.95 | 17.39 | 2.94 | 5.95 |
| paper | `#f3ead8` | 1.38 | 1.06 | 5.58 | 2.76 |
| ink | `#14110f` | 11.44 | 16.65 | 2.82 | 5.70 |

CIEDE2000 to colours with a reserved meaning (normal / worst dichromat):

| reserved | hex | A | B | C | D |
|---|---|---|---|---|---|
| moxie_yellow | `#ffd23f` | 52 / 10 | 14 / 6 | 75 / 56 | 44 / 33 |
| hazard_upper | `#ffc21a` | 51 / 9 | 19 / 8 | 73 / 57 | 45 / 31 |
| hazard_lower | `#ffb020` | 47 / 10 | 26 / 10 | 68 / 58 | 46 / 30 |
| enemy_eye | `#ff6a1a` | 38 / 23 | 50 / 19 | 56 / 60 | 54 / 26 |
| enemy_warning | `#ff3d3d` | 33 / 29 | 64 / 24 | 48 / 50 | 61 / 23 |
| enemy_fx | `#ff3d5a` | 28 / 28 | 69 / 26 | 46 / 40 | 63 / 17 |
| laser | `#ff2b5e` | 28 / 28 | 72 / 27 | 44 / 34 | 65 / 18 |
| door_closed | `#ff3048` | 31 / 29 | 68 / 25 | 46 / 45 | 63 / 22 |
| rec_red | `#ff2a3d` | 33 / 30 | 67 / 25 | 47 / 48 | 62 / 24 |
| chronal_amber | `#ffb347` | 44 / 9 | 27 / 11 | 66 / 58 | 45 / 28 |
| ghost_grey | `#7d8394` | 30 / 19 | 52 / 33 | 24 / 18 | 25 / 3 |
| state_dead | `#9aa3b5` | 25 / 10 | 48 / 26 | 32 / 25 | 24 / 8 |
| state_desync | `#c98bff` | 18 / 13 | 79 / 27 | 33 / 22 | 40 / 20 |
| boss_recall | `#b26bff` | 26 / 20 | 86 / 33 | 26 / 16 | 40 / 20 |
| shield_teal | `#58f0dc` | 52 / 2 | 36 / 28 | 56 / 39 | 21 / 21 |

CIEDE2000 to theme accents, normal vision (rows with a value under 25 only):

| theme | accent | hex | A | B | C | D |
|---|---|---|---|---|---|---|
| upper | neon_a | `#4fe6e0` | 52 | 39 | 52 | 19 |
| upper | neon_b | `#ff3d9a` | 22 | 80 | 41 | 57 |
| upper | neon_c | `#c06bff` | 24 | 86 | 29 | 41 |
| upper | graffiti | `#ff3fa4` | 21 | 81 | 40 | 55 |
| upper | graffiti_alt | `#a65ee0` | 28 | 86 | 23 | 41 |
| upper | hazard | `#ffc21a` | 51 | 19 | 73 | 45 |
| upper | foliage | `#93c22c` | 64 | 18 | 72 | 32 |
| upper | rune | `#ffd27a` | 44 | 19 | 68 | 42 |
| upper | accent | `#ff3d9a` | 22 | 80 | 41 | 57 |
| mid | neon_a | `#2fe6ff` | 57 | 48 | 49 | 22 |
| mid | neon_b | `#ff3fb4` | 21 | 83 | 40 | 52 |
| mid | neon_c | `#9b5cff` | 30 | 89 | 21 | 40 |
| mid | graffiti | `#ff4fae` | 19 | 80 | 40 | 54 |
| mid | graffiti_alt | `#a65ee0` | 28 | 86 | 23 | 41 |
| mid | hazard | `#ffb81c` | 49 | 23 | 70 | 45 |
| mid | rune | `#4ff0ff` | 55 | 44 | 51 | 23 |
| mid | accent | `#2fe6ff` | 57 | 48 | 49 | 22 |
| lower | neon_a | `#3ff0ff` | 56 | 45 | 52 | 23 |
| lower | neon_b | `#ff2fa0` | 23 | 82 | 40 | 55 |
| lower | graffiti | `#ff3fa4` | 21 | 81 | 40 | 55 |
| lower | graffiti_alt | `#b04dff` | 30 | 91 | 24 | 42 |
| lower | foliage | `#568f4c` | 61 | 37 | 54 | 20 |
| lower | rune | `#ff3fd0` | 21 | 87 | 38 | 48 |
| lower | accent | `#ff2fa0` | 23 | 82 | 40 | 55 |
| core | neon_a | `#3ff0ff` | 56 | 45 | 52 | 23 |
| core | neon_b | `#ff2fa0` | 23 | 82 | 40 | 55 |
| core | neon_c | `#8a4dff` | 34 | 92 | 18 | 41 |
| core | graffiti | `#ff3fa4` | 21 | 81 | 40 | 55 |
| core | graffiti_alt | `#9a5cff` | 31 | 89 | 21 | 40 |
| core | hazard | `#ffc23a` | 49 | 20 | 71 | 44 |
| core | foliage | `#3f7a6a` | 47 | 48 | 36 | **14** |
