"""
OVERDUB wardrobe — the single source of truth for every wearable item (APPAREL-01..03).

Pure Python (no bpy, no third-party imports) so that Blender, the concept generator and the data
builder can all import it.

  HEADGEAR  six rigid models on the Head bone (assets/models/wardrobe/<id>.glb)
  TOPS / PANTS / SHOES  look variants of the base outfit: colours per outfit material, an optional
            tiling pattern mask, optional decals.

Outfit regions = the material names the base model exposes (prefix match, longest prefix wins):
  top, top_trim, jacket, jacket_lining          <- TOP slot
  pants, pants_graphic                           <- PANTS slot
  shoes, shoes_sole, shoes_lace                  <- SHOES slot
Never touched by any look (the Moxie identity): headphones*, walkman, hair, skin, belt, strap.
"""

YELLOW = "#f5b819"   # the headphone / Walkman yellow of the base model

# ───────────────────────────── identity block used in every prompt ─────────────────────────────
MOXIE = (
    "the same girl as in the reference images (Moxie: scrappy tomboyish streetwear tech scavenger, warm "
    "tan skin, messy dark-brown hair in two scrappy high pigtails with loose strands, pink-and-white face "
    "paint stripes on her cheek, big YELLOW over-ear headphones, black choker, a yellow cassette Walkman "
    "clipped to her tool belt, cyan-lit wrist devices, fingerless gloves; outfit silhouette: a short crop "
    "top with a diagonal chest strap, an oversized open jacket slipping off her shoulders, baggy LOW-RISE "
    "cargo pants cuffed at the ankle, chunky high-top shoes)"
)
STYLE = (
    "Clean cel-shaded anime character design sheet with bold black ink outlines and flat colours on a "
    "plain dark charcoal background, in exactly the art style of the reference images. No text, no labels, "
    "no logos, no watermarks."
)

# ───────────────────────────── the head the headgear is fitted to ─────────────────────────────
# Measured with art/wardrobe/measure_head.py on assets/models/moxie.glb (the interim humanoid
# Moxie), relative to the Head bone's joint, character axes (+Y up, +Z front, +X her left).
# Re-measure and rebuild (build_headgear.py, build_data.py) when the final model lands; at run
# time Wardrobe.head_fit() rescales the gear onto whatever model is loaded.
HEAD = {
    "model": "assets/models/moxie.glb",
    "bone": (0.0, 1.395, -0.006),          # the Head joint in model space
    "skull_c": (0.0, 0.110, 0.004),        # skull centre
    "skull_r": (0.090, 0.097, 0.100),      # skull radii (x, y, z)
    "hair": 0.018,                         # hair thickness over the skull at brow height
    "hair_top": 0.004,                     # extra hair thickness toward the crown
    "hair_front": 0.120,                   # how far forward (+Z) the fringe reaches
    "cup_c": (0.111, 0.083, -0.005),       # headphone ear-cup centre (mirror in x)
    "cup_r": 0.047,
    "cup_outer_x": 0.129,
    "band_top": 0.227,                     # top of the headphone band
    "headphones_min": (-0.129, 0.035, -0.052),
    "headphones_max": (0.129, 0.227, 0.043),
    "skin_width": 0.180,                   # x extent of the head's skin above the joint
    "skin_top": 0.205,
}

# ───────────────────────────── headgear ─────────────────────────────
# anchor: what the piece is fitted to on a model that is not the reference head -
#   brow = rides on the fringe (pushed out with thicker hair), cups = the headphone ear cups,
#   neck = behind the neck. All are attached to the Head bone.
HEADGEAR = {
    "scrap_cap": {
        "name": "Scrap Cap", "variant": "cap", "anchor": "brow", "color": "#3b3442",
        "concept": (
            "SCRAP CAP: a beat-up dark plum-grey (#3b3442) five-panel cap worn low on the forehead UNDER the "
            "yellow headphone band, short stiff brim flipped slightly up, a yellow triangle patch stitched on "
            "the front panel, a safety pin and a strip of pink tape on the brim, frayed edges. The back of the "
            "cap is cut wide open so both pigtails and the headphone band stay completely visible."
        ),
    },
    "hush_hood": {
        "name": "Hush Hood", "variant": "hood", "anchor": "neck", "color": "#4a4f5c",
        "concept": (
            "HUSH HOOD: a hood quilted out of slate-grey (#4a4f5c) egg-crate speaker foam, worn PUSHED BACK "
            "off her head so it bunches in a thick padded roll behind her neck and around the back of her "
            "collar like a big scarf-collar, with a soft quilted lip rising behind the head below the "
            "pigtails, yellow stitching and a cyan drawcord toggle. Her head, hair and yellow headphones are "
            "completely uncovered."
        ),
    },
    "feedback_crown": {
        "name": "Feedback Crown", "variant": "crown", "anchor": "brow", "color": "#ff4fa3",
        "concept": (
            "FEEDBACK CROWN: a tiara-like crown worn across her forehead and temples in front of the yellow "
            "headphone band: a hot-pink (#ff4fa3) metal band carrying five small blown tweeter speakers "
            "standing up like crown points (tallest in the middle), each with a torn dark cone and a tiny "
            "glowing pink centre, joined by looping speaker wire and a small battery clip at one temple."
        ),
    },
    "click_visor": {
        "name": "Click-Track Visor", "variant": "visor", "anchor": "brow", "color": "#ffd23f",
        "concept": (
            "CLICK-TRACK VISOR: a chunky yellow (#ffd23f) sun-visor worn on her brow below the headphone "
            "band: a curved translucent amber shade peak jutting forward over her eyes, a dark brow band "
            "with a row of four small glowing cyan beat lights, and a tiny metronome pendulum arm with a "
            "sliding weight mounted upright at the centre of the brow, salvaged from a drum machine."
        ),
    },
    "prism_goggles": {
        "name": "Prism Goggles", "variant": "goggles", "anchor": "brow", "color": "#7fe7ff",
        "concept": (
            "PRISM GOGGLES: chunky welding-style goggles pushed UP onto her forehead (not over her eyes): "
            "two big round faceted mirror lenses glowing icy cyan (#7fe7ff) in dark riveted metal rims with "
            "side vents, a nose bridge, and a wide elastic strap that runs back under the yellow headphone "
            "ear cups."
        ),
    },
    "rabbit_ears": {
        "name": "Rabbit-Ear Aerials", "variant": "antenna", "anchor": "cups", "color": "#c9c9d1",
        "concept": (
            "RABBIT-EAR AERIALS: two chrome (#c9c9d1) telescoping television aerials zip-tied to the outside "
            "of her yellow headphone ear cups, sticking up and outward in a wide V like rabbit ears, each "
            "with three telescoping segments, a round ball tip glowing soft red, a swivel base, black zip "
            "ties and a curl of coax wire."
        ),
    },
}

# ───────────────────────────── looks ─────────────────────────────
# colors: outfit material name -> hex.  pattern: tiling mask painted over `region` in `color`.
# decals: small alpha graphics.  concept: what the image model is told.
LOOKS = {
    # ── tops ──
    "lined_bomber": {
        "slot": "top", "name": "Lined Bomber",
        "colors": {"top": "#eadfcc", "top_trim": "#2e292b", "jacket": "#3a3033", "jacket_lining": "#e9a81c"},
        "decals": [{"id": "bomber_star", "place": "jacket_back", "color": "#e9a81c", "opacity": 1.0}],
        "concept": "LINED BOMBER (her signature jacket): a cream (#eadfcc) crop top with dark trim under an oversized charcoal-brown (#3a3033) bomber jacket with a bright yellow (#e9a81c) lining and a yellow star-and-chevron graphic on the back, many pockets, one small burn hole.",
    },
    "ballast_puffer": {
        "slot": "top", "name": "Ballast Puffer",
        "colors": {"top": "#2e292b", "top_trim": "#c9c2a8", "jacket": "#5d6b3a", "jacket_lining": "#f08a24"},
        "pattern": {"id": "quilt", "region": "jacket", "color": "#3f4a26", "strength": 0.85, "scale": 5.0},
        "concept": "BALLAST PUFFER: the same open oversized jacket cut, but as a heavy olive-green (#5d6b3a) quilted puffer with fat horizontal channels and an orange (#f08a24) lining, small lead fishing weights sewn along the hem, worn over a black crop top with khaki trim.",
    },
    "razor_mesh": {
        "slot": "top", "name": "Razor Mesh Tee",
        "colors": {"top": "#1a1a1f", "top_trim": "#c9cdd6", "jacket": "#26232b", "jacket_lining": "#b3204c"},
        "pattern": {"id": "mesh", "region": "top", "color": "#c9cdd6", "strength": 0.9, "scale": 14.0},
        "concept": "RAZOR MESH TEE: a cropped black (#1a1a1f) fishnet mesh tee stitched with glinting silver guitar strings and steel trim, worn under her open jacket in near-black (#26232b) with a crimson (#b3204c) lining.",
    },
    "sub_vest": {
        "slot": "top", "name": "Subwoofer Vest",
        "colors": {"top": "#44444f", "top_trim": "#ff4fa3", "jacket": "#2f2f38", "jacket_lining": "#ffd23f"},
        "pattern": {"id": "grille", "region": "jacket", "color": "#15151b", "strength": 0.8, "scale": 12.0},
        "decals": [{"id": "sub_cone", "place": "jacket_back", "color": "#ffd23f", "opacity": 1.0}],
        "concept": "SUBWOOFER VEST: her open jacket rebuilt as a gunmetal (#2f2f38) harness-jacket covered in black perforated speaker-grille cloth with a yellow lining, a big round subwoofer driver graphic ringed in yellow on the back and a smaller driver on the chest panel, worn over a grey crop top with hot-pink trim.",
    },
    "patchcord_hoodie": {
        "slot": "top", "name": "Patch-Cord Hoodie",
        "colors": {"top": "#f2efe6", "top_trim": "#ff7a2f", "jacket": "#3ec5ff", "jacket_lining": "#1f3f66"},
        "decals": [{"id": "patch_jacks", "place": "jacket_back", "color": "#f2efe6", "opacity": 0.95}],
        "concept": "PATCH-CORD HOODIE: her open oversized jacket as a bright cyan (#3ec5ff) zip hoodie with a navy lining, the drawstrings replaced by orange patch cables ending in grabber clips, a row of white jack-socket rings printed across the back, worn over an off-white crop top with orange trim.",
    },
    "dropout_jacket": {
        "slot": "top", "name": "Dropout Jacket",
        "colors": {"top": "#1f1b2b", "top_trim": "#7fe7ff", "jacket": "#8a5cff", "jacket_lining": "#6b4630"},
        "pattern": {"id": "dropout", "region": "jacket", "color": "#3a2380", "strength": 0.8, "scale": 4.0},
        "decals": [{"id": "skip_glyph", "place": "jacket_back", "color": "#7fe7ff", "opacity": 1.0}],
        "concept": "DROPOUT JACKET: her open oversized jacket in violet (#8a5cff) broken up by darker horizontal glitch bands like tape dropouts, with a lining woven from brown magnetic tape, a cyan fast-forward skip symbol on the back, worn over a dark indigo crop top with cyan trim.",
    },
    "mirrorball_vest": {
        "slot": "top", "name": "Mirrorball Vest",
        "colors": {"top": "#2b2f3a", "top_trim": "#7fe7ff", "jacket": "#d8dbe6", "jacket_lining": "#ff4fa3"},
        "pattern": {"id": "mirror", "region": "jacket", "color": "#7d86a8", "strength": 0.75, "scale": 9.0},
        "concept": "MIRRORBALL VEST: her open oversized jacket covered completely in small square silver (#d8dbe6) disco-ball mirror tiles that catch the light, with a hot-pink lining, worn over a slate crop top with cyan trim.",
    },
    "encore_tee": {
        "slot": "top", "name": "Encore Tee",
        "colors": {"top": "#ff4d6d", "top_trim": "#f2efe6", "jacket": "#4a2530", "jacket_lining": "#ffd23f"},
        "decals": [{"id": "tour_print", "place": "jacket_back", "color": "#f2c9b8", "opacity": 0.6}],
        "concept": "ENCORE TEE: a faded coral-red (#ff4d6d) cropped tour t-shirt with cream ringer trim and a cracked, rubbed-away band print, worn under her open jacket in deep maroon (#4a2530) with yellow lining and a faded tour-date print on the back.",
    },
    # ── pants ──
    "olive_cargos": {
        "slot": "pants", "name": "Olive Cargos",
        "colors": {"pants": "#5f5b3e", "pants_graphic": "#f0b21c"},
        "concept": "OLIVE CARGOS (her signature pants): baggy low-rise olive (#5f5b3e) cargo pants with a big yellow zigzag graphic down one leg, torn knees, rolled cuffs, many pockets.",
    },
    "snap_trackies": {
        "slot": "pants", "name": "Snap Trackies",
        "colors": {"pants": "#2b2f6b", "pants_graphic": "#f2efe6"},
        "pattern": {"id": "snaps", "region": "pants", "color": "#f2efe6", "strength": 0.9, "scale": 3.0},
        "concept": "SNAP TRACKIES: baggy low-rise navy (#2b2f6b) tear-away track pants with white side stripes and a row of chrome snap buttons down the outside of each leg, a few snaps popped open at the ankle.",
    },
    "flywheel_cargos": {
        "slot": "pants", "name": "Flywheel Cargos",
        "colors": {"pants": "#6e5a3a", "pants_graphic": "#d98a4a"},
        "pattern": {"id": "canvas", "region": "pants", "color": "#4d3d25", "strength": 0.5, "scale": 10.0},
        "concept": "FLYWHEEL CARGOS: baggy low-rise heavy tan-brown (#6e5a3a) canvas cargo pants with copper (#d98a4a) accents and small brass tape-deck flywheels set into the bulging knee pockets.",
    },
    "kneepad_joggers": {
        "slot": "pants", "name": "Kneepad Joggers",
        "colors": {"pants": "#3a3a40", "pants_graphic": "#ff4d6d"},
        "concept": "KNEEPAD JOGGERS: baggy low-rise charcoal (#3a3a40) joggers with elastic cuffs and scuffed coral-red (#ff4d6d) hard-shell skate knee pads strapped over them.",
    },
    "parachute_pants": {
        "slot": "pants", "name": "Parachute Pants",
        "colors": {"pants": "#b14cff", "pants_graphic": "#7dff6b"},
        "pattern": {"id": "ripstop", "region": "pants", "color": "#7a2fc0", "strength": 0.7, "scale": 10.0},
        "concept": "PARACHUTE PANTS: enormous billowing low-rise purple (#b14cff) ripstop-nylon parachute pants with a fine grid weave, lime-green (#7dff6b) pull cords and zips, gathered at the ankle.",
    },
    "bandolier_cargos": {
        "slot": "pants", "name": "Bandolier Cargos",
        "colors": {"pants": "#4d4a2e", "pants_graphic": "#ff7a2f"},
        "pattern": {"id": "camo", "region": "pants", "color": "#2f2e1c", "strength": 0.8, "scale": 2.5},
        "concept": "BANDOLIER CARGOS: baggy low-rise dark-olive (#4d4a2e) camo cargo pants with a bandolier strap around one thigh and every pocket stuffed with orange (#ff7a2f) power cells and tiny rockets.",
    },
    # ── shoes ──
    "beater_hightops": {
        "slot": "shoes", "name": "Beater High-Tops",
        "colors": {"shoes": "#cdbca4", "shoes_sole": "#eae0ce", "shoes_lace": "#f5b819"},
        "concept": "BEATER HIGH-TOPS (her signature shoes): chunky scuffed sand-and-brown (#cdbca4) high-top boots with thick cream soles and yellow laces.",
    },
    "slick_sliders": {
        "slot": "shoes", "name": "Slick Sliders",
        "colors": {"shoes": "#ffd23f", "shoes_sole": "#1c1a21", "shoes_lace": "#f2efe6"},
        "concept": "SLICK SLIDERS: chunky glossy yellow (#ffd23f) high-top shoes with perfectly smooth waxed black soles that shine, white laces, a little speed streak painted on the side.",
    },
    "anvil_platforms": {
        "slot": "shoes", "name": "Anvil Platforms",
        "colors": {"shoes": "#3d3d46", "shoes_sole": "#8b90a0", "shoes_lace": "#ff4fa3"},
        "concept": "ANVIL PLATFORMS: massive dark-grey (#3d3d46) platform boots with very thick steel-grey soles made from amplifier casings with corner protectors, hot-pink laces.",
    },
    "static_runners": {
        "slot": "shoes", "name": "Static Runners",
        "colors": {"shoes": "#3ec5ff", "shoes_sole": "#f2efe6", "shoes_lace": "#1c1a21"},
        "pattern": {"id": "static", "region": "shoes", "color": "#eaffff", "strength": 0.8, "scale": 8.0},
        "concept": "STATIC RUNNERS: chunky cyan (#3ec5ff) high-top running shoes speckled with white TV-static noise, white soles, black laces, tiny sparks crackling off the heels.",
    },
    "spring_soles": {
        "slot": "shoes", "name": "Spring Soles",
        "colors": {"shoes": "#7dff6b", "shoes_sole": "#c9cdd6", "shoes_lace": "#25212b"},
        "concept": "SPRING SOLES: chunky lime-green (#7dff6b) high-top shoes with visible stacked chrome coil springs built into the thick heels, dark laces.",
    },
    "grip_sprinters": {
        "slot": "shoes", "name": "Grip Sprinters",
        "colors": {"shoes": "#ff7a2f", "shoes_sole": "#25212b", "shoes_lace": "#ffd23f"},
        "concept": "GRIP SPRINTERS: chunky orange (#ff7a2f) high-top track shoes with black spiked rubber soles and yellow laces.",
    },
}

# ───────────────────────────── pattern masks ─────────────────────────────
# 512 px seamless greyscale: WHITE = paint the pattern colour, BLACK = keep the base colour.
PATTERNS = {
    "quilt":   "fat horizontal puffer-jacket quilting channels: wide soft white bands separated by thin dark stitched seam lines, a few vertical stitch lines offset like bricks",
    "mesh":    "open diamond fishnet mesh: thin white diagonal crossing lines on black, evenly spaced",
    "grille":  "perforated metal speaker grille: a staggered grid of small round white dots on black",
    "dropout": "horizontal glitch bars like damaged video tape: irregular white horizontal streaks and bands of different lengths and thicknesses on black",
    "mirror":  "disco ball mirror tiles: a grid of small squares in different shades of grey and white separated by thin black grout lines",
    "snaps":   "two clean vertical white racing stripes with a vertical row of small white round snap buttons between them, on black",
    "canvas":  "coarse woven canvas cloth: a tight basket weave of short horizontal and vertical white dashes on black",
    "ripstop": "ripstop nylon: a fine regular square grid of thin white lines on black",
    "camo":    "blobby woodland camouflage: large rounded white blotches on black, bold flat shapes",
    "static":  "television static noise: scattered small white rectangular specks and short dashes on black",
}

# ───────────────────────────── decals ─────────────────────────────
# 512 px, white graphic on transparent; tinted to `color` in game.
DECALS = {
    "bomber_star":  "a bold five-pointed star inside two stacked chevrons, spray-stencil street graphic",
    "sub_cone":     "a round subwoofer speaker seen from the front: thick outer ring, concentric surround ring, centre dust cap dot, four screw dots",
    "patch_jacks":  "a horizontal row of five audio jack sockets drawn as rings with a hex nut outline, joined by one drooping curved patch cable",
    "skip_glyph":   "a fast-forward skip symbol: two right-pointing triangles followed by a vertical bar, slightly sliced by two horizontal glitch gaps",
    "tour_print":   "a cracked worn concert tour shirt print: a cassette tape with lightning bolts and rows of small illegible distressed blocks like tour dates, heavily weathered",
}

# ───────────────────────────── full-outfit mixes (identity check) ─────────────────────────────
MIXES = {
    "mix_baseline": ["scrap_cap", "lined_bomber", "olive_cargos", "beater_hightops"],
    "mix_loud":     ["feedback_crown", "mirrorball_vest", "parachute_pants", "spring_soles"],
    "mix_stealth":  ["hush_hood", "razor_mesh", "kneepad_joggers", "anvil_platforms"],
    "mix_signal":   ["rabbit_ears", "patchcord_hoodie", "snap_trackies", "static_runners"],
    "mix_clash":    ["prism_goggles", "encore_tee", "bandolier_cargos", "slick_sliders"],
    "mix_tempo":    ["click_visor", "dropout_jacket", "flywheel_cargos", "grip_sprinters"],
}

SLOT_ORDER = ["helmet", "top", "pants", "shoes"]


def all_ids():
    return list(HEADGEAR) + list(LOOKS)
