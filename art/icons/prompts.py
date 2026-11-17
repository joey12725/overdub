"""Prompt list for the OVERDUB icon family (gear + abilities + slot glyphs).
Used by generate.py. HUD glyphs (actions/, tape/) are drawn procedurally by glyphs.py."""

STYLE = (
    "Game inventory icon in die-cut sticker style. ONE single chunky object, slightly exaggerated toy-like proportions, "
    "drawn with a bold even black ink outline, and a thin clean white sticker border hugging the whole silhouette. "
    "Flat cel-shaded anime colours: each colour area has exactly one darker shadow tone and a few small crisp highlights, "
    "no gradients, no airbrush, no texture noise. Slight three-quarter angle. The object is centred and fills about 80% of "
    "the square frame with clear margin on every side, nothing cropped. Fully transparent background. "
    "World: cassette-era music tech scavenged in ancient ruins; palette of charcoal, hero yellow (#ffd23f), magenta, cyan and violet accents. "
    "Avoid: any text, letters, numbers or logos; drop shadow; ground; background shapes; extra objects; hands; people; photo-realism; thin sketchy lines. "
)
ABILITY_STYLE = (
    "Game ability emblem icon in die-cut sticker style, same family as the reference stickers: ONE bold simple symbol, "
    "bold even black ink outline, thin clean white sticker border hugging the silhouette, flat cel colours with one shadow tone, "
    "very simple shapes that stay readable at 32 pixels, centred, fills about 80% of the square frame, nothing cropped. "
    "Fully transparent background. Palette: hero yellow, magenta, cyan, violet, charcoal. "
    "Avoid: text, letters, numbers, drop shadow, background shapes or badge plates, people, faces, clutter, thin lines. "
)

GEAR = {
    # helmets
    "scrap_cap": "A scuffed dark charcoal-plum five-panel baseball cap with a short curved brim, a stitched fabric patch and one small yellow safety pin; plain and trusty.",
    "hush_hood": "A detached slate-grey quilted hood made of padded speaker foam (egg-crate acoustic foam diamond quilting), soft and rounded, empty dark opening where the face would be, two drawstrings hanging.",
    "feedback_crown": "A hot magenta-pink crown made of a ring of small round tweeter speaker cones on a metal band, wires looping between them, tiny yellow squeal zigzags at the top; loud and spiky.",
    "click_visor": "A wraparound sun visor headband with a bright yellow tinted lens, a small pyramid metronome with its ticking arm mounted on one temple, charcoal strap.",
    "prism_goggles": "Chunky welding-style goggles with two round mirror-coated cyan lenses showing a rainbow prism glint, charcoal rubber frame and elastic strap, one small light beam bouncing off a lens.",
    "rabbit_ears": "A pair of yellow over-ear headphones with a star on the earcup, with two long silver telescoping rabbit-ear TV aerials zip-tied to the headband forming a V.",
    # tops
    "lined_bomber": "An oversized dark charcoal bomber jacket hanging open so the bright yellow lining shows inside the collar and front, ribbed cuffs, many pockets, one purple star patch on the sleeve.",
    "ballast_puffer": "A very fat olive-green quilted puffer jacket that sags heavily, with a few grey lead fishing weights hanging from the hem; looks heavy.",
    "razor_mesh": "A black mesh t-shirt (visible net grid) stitched across the chest with silver snapped guitar strings that curl out sharply at the ends like razor wire.",
    "sub_vest": "A dark grey harness vest with two big round subwoofer speaker drivers mounted on the chest, yellow buckles and straps.",
    "patchcord_hoodie": "A bright cyan-blue hoodie whose drawstrings are replaced by long audio patch cables ending in a jack plug and a small grabber alligator clip, kangaroo pocket.",
    "dropout_jacket": "A violet purple coach jacket hanging open, its inner lining woven from shiny brown cassette tape ribbon that unravels in a few loose loops at the hem; a small glitchy offset slice across one sleeve.",
    "mirrorball_vest": "A sleeveless vest completely covered in small square silver mirror tiles like a disco ball, with a few four-point sparkle glints in cyan and magenta.",
    "encore_tee": "A faded coral-red band tour t-shirt, slightly worn collar, with a simple yellow star-burst print on the chest (no words).",
    # pants
    "olive_cargos": "A pair of baggy low-rise olive-green cargo pants with big side pockets, gathered ankle cuffs, a black belt with a small yellow cassette player clipped on the hip.",
    "snap_trackies": "A pair of deep indigo-blue tear-away track pants with a row of round silver snap buttons and a white stripe down the outer leg, one leg seam popped open at the bottom.",
    "flywheel_cargos": "A pair of baggy tan-brown heavy cargo pants with a round metal tape-deck flywheel spinning in each knee pocket, small motion arcs around the wheels.",
    "kneepad_joggers": "A pair of dark charcoal jogger pants with chunky yellow hard-shell skate knee pads strapped over the knees.",
    "parachute_pants": "A pair of enormous billowing violet-purple nylon parachute pants, ballooning wide with shiny folds, tight ankle cuffs, zip pockets.",
    "bandolier_cargos": "A pair of dark khaki cargo pants with a bandolier belt of small red mini-rockets and cyan battery cells strapped around the thigh and waist, bulging pockets.",
    # shoes
    "beater_hightops": "One chunky scuffed off-white high-top sneaker with thick sole, yellow and cyan accent panels, loose laces, a few scuff marks.",
    "slick_sliders": "One bright yellow slip-on skate shoe with a glossy wet waxed sole and two small speed streaks behind the heel.",
    "anvil_platforms": "One heavy dark grey platform boot whose huge thick sole is a guitar amplifier casing with speaker grille cloth and metal corner caps, buckles on the shaft.",
    "static_runners": "One sleek cyan-blue running shoe crackling with small white-cyan electric static sparks, the heel partly dissolving into horizontal glitch slices.",
    "spring_soles": "One lime-green sneaker with two big metal coil springs stacked under the heel instead of a sole, bouncy.",
    "grip_sprinters": "One low orange track sprint shoe with sharp metal spikes under the forefoot, sleek and aggressive.",
    # melee
    "splice_blade": "An oversized tape-splicing knife grown into a short sword: wide angled off-white utility blade with a diagonal tip, yellow grip wrapped in black tape, a small tape reel as the pommel. Diagonal across the frame.",
    "stylus_shiv": "A short dagger made from a silver record-player tone arm: slim metal arm with headshell and a needle filed to a sharp point, counterweight as the pommel. Diagonal across the frame.",
    "amp_sledge": "A huge sledgehammer whose head is a boxy yellow guitar amplifier head (speaker grille cloth front, round knobs on top, metal corner caps) mounted on a grey steel scaffold pole wrapped with black tape. Diagonal across the frame.",
    "reel_lash": "A whip made of brown magnetic cassette tape: a brown hand-cranked open tape reel with handle, the tape ribbon lashing out from it in one bold S-curve ending in a small metal tip.",
    "speaker_knuckles": "One hot-pink fingerless glove made into a fist, with four small round tweeter speaker cones riveted over the knuckles, strap buckle on the wrist.",
    "vinyl_glaive": "A polearm glaive whose blade is a sharpened black twelve-inch vinyl record (grooves, magenta centre label, a gleaming sharpened rim) bolted to a wooden broom handle. Diagonal across the frame.",
    # ranged
    "mixtape_rocket": "A fat little rocket whose body is a coral-red audio cassette shell with two reel windows, a rounded nose cone, small tail fins and a short flame; cute but dangerous.",
    "needle_rail": "A slim silver railgun pistol built from copper magnet coils wound around two long parallel rails, with a sharp phonograph needle sitting at the muzzle.",
    "bleed_emitter": "A violet handheld ray emitter built from a tape-recorder head: boxy body with a small tape reel on the side and a dish-shaped muzzle sending out two ghostly concentric purple wave arcs.",
    "bass_drop": "A stubby mortar tube on a small bipod, angled upward, with a lime-green subwoofer speaker cone loaded in the mouth like a shell.",
    "static_spray": "A battered cyan-blue boombox held like a gun with a pistol grip underneath, one speaker spitting a short fan of five yellow-white sparks.",
}

ABILITIES = {
    "manualDesync": "A cassette tape shell split into two halves that are offset sideways out of alignment (a glitch slip), violet shell with cyan and magenta offset edges.",
    "lowProfile": "A speaker cone with a bold diagonal slash through it, muted slate-grey and violet; meaning silent, unnoticed.",
    "loudmouth": "A megaphone bullhorn blasting three bold curved sound waves, hot magenta with yellow waves; meaning loud, draws attention.",
    "beatSight": "A stylised eye whose pupil is a pyramid metronome with a ticking arm, yellow with charcoal; meaning seeing the beat ahead.",
    "laserProof": "A triangular glass prism with one thick magenta laser beam hitting it and bending harmlessly away as a cyan beam; meaning laser-proof.",
    "heavyStep": "A chunky boot stomping down on a flat pressure plate with two small impact chevrons, charcoal boot, yellow plate; meaning heavy step.",
    "phaseDodge": "A running sneaker drawn half solid cyan and half as horizontal dissolving ghost slices, passing through a low bar; meaning phasing dodge.",
    "slideStrike": "A curved speed-slide arrow that ends in a sharp blade slash star, yellow arrow with magenta slash; meaning slide into a strike.",
    "parry": "A round mirror-tiled disco shield with a bold arrow bouncing off it and turning back, silver with cyan and magenta; meaning reflect projectiles.",
    "killRefresh": "A circular refresh arrow loop with a small skull-shaped guitar pick in the middle, coral-red and yellow; meaning a kill refreshes the dodge.",
}

SLOTS = {
    "helmet": "a baseball cap seen three-quarter",
    "top": "a jacket / t-shirt torso garment seen from the front",
    "pants": "a pair of baggy cargo pants seen from the front",
    "shoes": "one chunky high-top sneaker seen from the side",
    "melee": "a short broad blade sword, diagonal",
    "ranged": "a small rocket, diagonal",
}
SLOT_STYLE = (
    "Empty equipment-slot glyph for a game inventory, same sticker family as the reference stickers but monochrome: "
    "a flat solid pure white silhouette of {subject}, with a bold even black ink outline and only two or three thick black "
    "interior detail lines, no colour, no shading, no grey. Very simple, chunky, readable at 32 pixels. Centred, fills about "
    "75% of the square frame, nothing cropped. Fully transparent background. Avoid: text, letters, colour, gradients, drop shadow, extra objects."
)


def all_jobs():
    jobs = {}
    for k, v in GEAR.items():
        jobs["gear/" + k] = STYLE + "The object: " + v
    for k, v in ABILITIES.items():
        jobs["abilities/" + k] = ABILITY_STYLE + "The symbol: " + v
    for k, v in SLOTS.items():
        jobs["slots/" + k] = SLOT_STYLE.format(subject=v)
    return jobs
