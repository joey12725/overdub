"""OVERDUB world art: every image-model prompt, as the source of record.
Run:  python -I art/world_art/jobs.py [name-substring ...] [--force]
Generates art/world_art/raw/<name>.png through tools/img, two calls at a time; skips files that exist.
Then run art/world_art/process.py to trim / pad / export into assets/textures/**."""
import os, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RAW = os.path.join(ROOT, "art", "world_art", "raw")
PINK, VIOLET, YELLOW, CYAN = "hot pink (#ff4fa3)", "violet purple (#a25bff)", "warm yellow (#ffd23f)", "bright cyan (#3ec5ff)"

SPRAY = ("isolated on a fully transparent background, no wall, no surface, no bricks, no cast shadow. "
  "Real aerosol spray paint: fat-cap strokes with soft fuzzy edges, fine overspray speckle mist around the strokes, "
  "uneven coverage, several paint drips running down from the bottom. Flat front-on orthographic view, centred, "
  "the whole piece inside the frame with a clear margin. Scrappy, playful, fast street hand like a teenager tagging "
  "ancient ruins; bold cel-shaded anime game art feel. One single colour family only. Nothing else in the image.")


def tag(word, colour, extra=""):
    return (f"Spray-paint graffiti tag reading exactly \"{word}\" in big chunky hand-sprayed capital letters, slightly tilted, "
            f"every letter clearly legible and spelt exactly {' '.join(word)}. {extra} {colour} paint with darker shading "
            f"of the same hue on the lower edges and one pale highlight stroke. {SPRAY}")


def sym(desc, colour):
    return f"Spray-paint graffiti doodle: {desc}. {colour} paint, drawn as thick sprayed lines. No letters, no words. {SPRAY}"


DECAL = ("isolated on a fully transparent background, seen exactly from straight above (flat top-down orthographic, "
  "no perspective, no ground, no floor tiles, no shadow). Old industrial floor paint, heavily worn: chipped, scuffed, "
  "flaking, with bare gaps where the paint has rubbed away, slightly rough stencil edges. Flat cel-painted anime game "
  "texture style with a little hand-inked grit. Centred with a clear margin, nothing else in the image.")

STICKER = ("as a die-cut sticker isolated on a fully transparent background: bold hand-lettered comic brush capitals, "
  "slightly tilted and bouncy, thick black ink outline around each letter, a flat cel-shaded fill with one hard shadow "
  "tone and one small highlight, an even white sticker border around the whole word, tiny print-grain. Expressive "
  "anime title-card lettering energy (Mob Psycho 100). Flat front-on, centred with margin, no drop shadow, no background, "
  "no other text or symbols beyond what is described. The whole sticker including its white border fills only the middle "
  "two thirds of the image height, with a wide empty transparent margin above, below, left and right; nothing touches or is cut off by the image edge.")

BACK = ("Wide painted background plate for an isometric video game, in a soft cel-painted anime background style "
  "(flat painterly shapes, a few ink-line accents, gentle gradients). It will sit BEHIND a floating game diorama, so it "
  "must be low-contrast, hazy, out-of-focus and atmospheric, with the centre of the image the calmest and emptiest "
  "area, detail pushed to the edges, and strong aerial-perspective haze. No characters, no text, no logos, no UI, no "
  "frame, no foreground objects, no isometric platform, no pink sunset clouds. ")

MOSS = ("Fresh yellow-green (#a8c93a) with darker olive shadow shapes, flat cel-painted anime game style with ink-line "
  "accents. Straight top-down view, no ground, no stones, no shadow, nothing else.")

JOBS = [
 # -- graffiti: tags (graffiti__mox and graffiti__smiley were the anchor tests, same recipe) --------
 ("graffiti__mox", "1024x1024", "transparent", None, tag("MOX", PINK, "A small sprayed five-point star after it and an underline swoosh.")),
 ("graffiti__smiley", "1024x1024", "transparent", None, "Spray-paint graffiti of a round smiley face with two X marks for eyes and a wide curved grin, drawn as a thick sprayed circle outline, hot pink paint (#ff4fa3) with long drips running down from the circle and the grin. " + SPRAY),
 ("graffiti__rec", "1536x1024", "transparent", None, tag("REC", PINK, "A solid sprayed round dot sits just before the word, like a record light.")),
 ("graffiti__loop", "1536x1024", "transparent", None, tag("LOOP", VIOLET, "A sprayed circular arrow loops around the end of the word.")),
 ("graffiti__dub", "1536x1024", "transparent", None, tag("DUB", VIOLET, "Three fat bubble letters with an underline swoosh.")),
 ("graffiti__take_4", "1536x1024", "transparent", None, tag("TAKE 4", YELLOW, "The numeral 4 is larger than the letters and circled with a sprayed ring.")),
 ("graffiti__side_b", "1536x1024", "transparent", None, tag("SIDE B", PINK, "The single letter B is larger, with a small sprayed arrow under the word.")),
 ("graffiti__rewind", "1536x1024", "transparent", None, tag("REWIND", VIOLET, "Two sprayed left-pointing triangles (a rewind symbol) sit before the word.")),
 ("graffiti__hiss", "1536x1024", "transparent", None, tag("HISS", CYAN, "Wavy sprayed static squiggle lines trail off the last letter.")),
 ("graffiti__5678", "1536x1024", "transparent", None,
   f"Spray-paint graffiti of a dance count: the four numerals 5, 6, 7, 8 in a row separated by short dashes, reading exactly \"5-6-7-8\", "
   f"each numeral bigger and higher than the last like a count-in, with an exclamation stroke after the 8. {PINK} paint with darker shading and a pale highlight. {SPRAY}"),
 ("graffiti__overdub", "1536x1024", "transparent", None, tag("OVERDUB", PINK, "Chunky block letters in one confident line, a small crown doodle above the O.")),
 ("graffiti__play", "1536x1024", "transparent", None, tag("PLAY", YELLOW, "A sprayed right-pointing play triangle sits after the word.")),
 ("graffiti__loud", "1536x1024", "transparent", None, tag("LOUD", PINK, "Short sprayed shout lines radiate from the word.")),
 ("graffiti__again", "1536x1024", "transparent", None, tag("AGAIN!", CYAN, "Fast scrawled single-line letters with an exclamation mark.")),
 ("graffiti__no_skips", "1536x1024", "transparent", None, tag("NO SKIPS", VIOLET, "Two words on one line, thin fast marker-like spray scrawl.")),
 ("graffiti__moxie_was_here", "1536x1024", "transparent", None, tag("MOXIE WAS HERE", VIOLET, "Three words stacked on two lines (MOXIE on top, WAS HERE below) in a thin fast one-line spray scrawl with a tiny star.")),
 # -- graffiti: characters and symbols ----------------------------------------------------------------
 ("graffiti__smiley_violet", "1024x1024", "transparent", None, sym("a lopsided round smiley face with two X marks for eyes and a tongue sticking out of a crooked grin, long drips", VIOLET)),
 ("graffiti__star", "1024x1024", "transparent", None, sym("one big five-pointed star drawn in a single continuous overlapping line (pentagram-style scribble star), slightly wonky", PINK)),
 ("graffiti__star_yellow", "1024x1024", "transparent", None, sym("one big five-pointed star drawn in a single continuous overlapping line (pentagram-style scribble star), with three tiny stars beside it", YELLOW)),
 ("graffiti__cassette", "1024x1024", "transparent", None, sym("an audio cassette tape seen front-on: rounded rectangle shell, two round reel holes with little teeth, a label window, long drips from the bottom edge", PINK)),
 ("graffiti__reel", "1024x1024", "transparent", None, sym("an open tape reel: a circle with three round cut-out holes and a centre hub, a ribbon of tape unspooling off to one side in a loose curl", VIOLET)),
 ("graffiti__arrow", "1536x1024", "transparent", None, sym("one fat bold arrow pointing to the right, with a wobbly outline and speed streaks behind the tail", PINK)),
 ("graffiti__arrow_down", "1024x1024", "transparent", None, sym("one fat bold arrow pointing straight down with drips falling from the arrowhead, three short chevrons stacked above it", YELLOW)),
 ("graffiti__crown", "1024x1024", "transparent", None, sym("a pair of big over-ear headphones seen front-on wearing a three-point crown on top of the headband, little sparkle ticks around it", YELLOW)),
 ("graffiti__headphones", "1024x1024", "transparent", None, sym("a pair of big over-ear headphones seen front-on with a curly cable dangling down and small sound-wave arcs coming off each ear cup", PINK)),
 ("graffiti__warning", "1024x1024", "transparent", None, sym("a hazard warning triangle with rounded corners containing one fat exclamation mark, drawn wonky by hand, with drips", YELLOW)),
 ("graffiti__bolt", "1024x1024", "transparent", None, sym("one chunky zig-zag lightning bolt with small spark ticks around it", CYAN)),
 ("graffiti__skull", "1024x1024", "transparent", None, sym("a cute cartoon skull wearing over-ear headphones, X eyes, a zipper-tooth grin, drips from the jaw", VIOLET)),
 ("graffiti__heart", "1024x1024", "transparent", None, sym("one chubby heart filled in solid with a single highlight tick, long drips running down from its point", PINK)),
 ("graffiti__ghost", "1024x1024", "transparent", None, sym("a little bedsheet ghost with two round eyes and a wavy hem, floating, with a faint second outline offset behind it like an echo", CYAN)),
 ("graffiti__boombox", "1024x1024", "transparent", None, sym("a boombox radio seen front-on: carry handle, two round speakers, a cassette door in the middle, music notes popping off it", VIOLET)),
 ("graffiti__wave", "1536x1024", "transparent", None, sym("a jagged audio waveform line running left to right, quiet at the ends and spiking tall in the middle", CYAN)),
 ("graffiti__tally", "1024x1024", "transparent", None, sym("four vertical tally strokes crossed by one diagonal slash, like counting takes on a wall", VIOLET)),
 ("graffiti__x", "1024x1024", "transparent", None, sym("one big fat X made of two crossing sprayed strokes inside a rough sprayed circle", PINK)),
 ("graffiti__splat", "1024x1024", "transparent", None, sym("an abstract burst of spray paint: one dense sprayed blob with a halo of overspray mist, a few flung droplets and three long drips; no drawing at all, just paint", PINK)),
 # -- decals: ruin-technology floor markings -----------------------------------------------------------
 ("decal__hazard_stripe", "1536x1024", "transparent", None, "A long straight horizontal band of diagonal yellow-and-black hazard stripes, the band crossing the full width of the image edge to edge, with perfectly straight top and bottom edges, the band about one quarter of the image height. Warm utility yellow (#ffc21a) and near-black ink (#1d1820). " + DECAL),
 ("decal__hazard_chevrons", "1536x1024", "transparent", None, "A horizontal row of five bold yellow chevrons all pointing to the right, evenly spaced like a conveyor or direction marking, warm utility yellow (#ffc21a) with thin near-black edging. " + DECAL),
 ("decal__lane_arrow", "1024x1024", "transparent", None, "One large straight lane arrow pointing up, warm utility yellow (#ffc21a), a simple road-marking shape with a long shaft and broad head. " + DECAL),
 ("decal__lane_arrow_turn", "1024x1024", "transparent", None, "One large lane arrow that goes up and then bends ninety degrees to the right, warm utility yellow (#ffc21a), a simple road-marking shape. " + DECAL),
 ("decal__bay_numbers", "1024x1024", "transparent", None, "Four separate square bay markings in a two-by-two grid with wide empty gaps between them: each is a thick yellow square bracket frame containing a two-digit stencil number. Top-left reads 01, top-right reads 02, bottom-left reads 03, bottom-right reads 04. Blocky industrial stencil numerals with stencil bridges, warm utility yellow (#ffc21a). " + DECAL),
 ("decal__bay_letters", "1024x1024", "transparent", None, "Four separate round tape-bay markings in a two-by-two grid with wide empty gaps between them: each is a thick ring containing one blocky stencil capital letter. Top-left A, top-right B, bottom-left C, bottom-right D. All painted in plain white so they can be tinted later. " + DECAL),
 ("decal__worn_paint_yellow", "1024x1024", "transparent", None, "A roughly square patch of old yellow floor paint (#ffc21a) almost entirely worn away: patchy remnants, scraped streaks, flaked islands of paint, mostly gaps. Abstract, no symbol. " + DECAL),
 ("decal__worn_line", "1536x1024", "transparent", None, "One straight horizontal painted boundary line crossing the full width of the image edge to edge, off-white paint, about one tenth of the image height thick, badly worn with breaks and scuffs along it. " + DECAL),
 ("decal__exit", "1536x1024", "transparent", None, "A floor exit marking: the stencilled word \"EXIT\" in blocky industrial stencil capitals, spelt exactly E X I T, with a bold arrow pointing right after it, all inside a rounded rectangular outline frame. Signal green (#7dff6b) paint. " + DECAL),
 ("decal__do_not_stand", "1024x1024", "transparent", None, "A round prohibition floor stencil for a trap: a thick red ring with a diagonal slash across a pair of boot footprints, signal red (#ff4d3d) ring and slash, the footprints warm yellow. No lettering at all. " + DECAL),
 ("decal__keep_clear", "1024x1024", "transparent", None, "A square trap warning floor stencil: a yellow square frame with hazard-striped corners, and inside it the two stencilled words \"KEEP CLEAR\" stacked on two lines in blocky industrial stencil capitals, spelt exactly K E E P and C L E A R. Warm utility yellow (#ffc21a) with near-black. " + DECAL),
 ("decal__moss_a", "1024x1024", "transparent", None, "A top-down overlay patch of moss and tiny creeping weeds isolated on a fully transparent background: an irregular organic clump, denser in the middle and breaking into scattered tufts and little leaves at the edges, with holes in it. " + MOSS),
 ("decal__moss_b", "1536x1024", "transparent", None, "A top-down overlay of moss growing along a seam isolated on a fully transparent background: a long thin wandering horizontal line of moss tufts, grass blades and tiny leaves, as if growing out of a crack between floor slabs, broken into uneven clumps. " + MOSS),
 ("decal__leaves", "1024x1024", "transparent", None, "A top-down scatter of about fifteen small fallen leaves and vine scraps isolated on a fully transparent background, loosely spread with gaps between them, yellow-green and a few dry ochre ones, flat cel-painted anime game style with ink outlines. Straight top-down view, no ground, no shadow, nothing else."),
 ("decal__crack_a", "1024x1024", "transparent", None, "A crack overlay for a stone floor isolated on a fully transparent background: one branching fracture drawn as bold dark ink lines (#241a1c) that vary in thickness, forking into finer hairline cracks, with a few small chipped-out flakes along it. Only the dark crack lines, no stone, no surface, no colour fill, no shadow. Hand-inked anime background style. Straight top-down view, nothing else."),
 ("decal__crack_b", "1024x1024", "transparent", None, "A crack overlay isolated on a fully transparent background: an impact fracture, a small shattered centre with dark ink crack lines (#241a1c) radiating outward in a spiderweb with a couple of concentric breaks. Only the dark crack lines and a few tiny chips, no stone, no surface, no colour fill, no shadow. Hand-inked anime background style. Straight top-down view, nothing else."),
 ("decal__scorch_a", "1024x1024", "transparent", None, "A scorch mark overlay isolated on a fully transparent background: a round blast burn seen from straight above, sooty black-brown centre fading out through soft smoky edges, with radiating soot streaks and a few flecks. Dark charcoal only, semi-transparent towards the edges, flat cel-painted anime effect style. No ground, no flames, no glow, nothing else."),
 ("decal__scorch_b", "1536x1024", "transparent", None, "A scorch mark overlay isolated on a fully transparent background: a long horizontal burn streak seen from straight above, as if a laser beam dragged along a floor, a sooty black-brown core with soft smoky feathered edges and small soot flecks. Dark charcoal only, semi-transparent towards the edges, flat cel-painted anime effect style. No ground, no flames, no glow, nothing else."),
 ("decal__rune_glyphs_src", "1536x1024", "opaque", None, "A reference sheet of exactly forty different glyphs of an invented angular alphabet, arranged in a strict grid of eight columns and five rows with generous even spacing, pure white glyphs on a pure solid black background. Each glyph is a compact square-ish character built from four to seven thick straight strokes of uniform width with hard chiselled ends: verticals, diagonals, chevrons, a few small triangles, squares and dots. Machine-carved rune style, like circuitry crossed with ancient script. Every glyph distinct from the others, none resembling Latin letters, digits or real-world scripts. No grid lines, no borders, no labels, no numbers, no other marks."),
 # -- backdrops ------------------------------------------------------------------------------------------
 # (first pass passed refs/ref_*.png as style references: all four came back as the same pink cloud sky, rejected)
 ("backdrop__upper", "1536x1024", "opaque", None, BACK + "Scene: an INTERIOR view from inside a huge ruined stone hall, looking out through a row of enormous broken stone vaults and pointed arches whose roof has partly fallen in. Through the arches: a hazy golden late-afternoon sky (pale gold and cream, NOT pink, NOT purple) and, far away, overgrown ruined towers, stepped terraces and an aqueduct fading into warm haze in three soft layers. Broken vault ribs and columns of warm sandstone (#c9a07c) frame the top and the far left and right edges, with hanging vines and soft olive foliage; pale sunbeams slant through dust. Palette strictly: warm sand, cream, soft gold, peach and dusty olive green, with muted brown shadows. Bright, warm, calm, sun-bleached."),
 ("backdrop__mid", "1536x1024", "opaque", None, BACK + "Scene: an INTERIOR, the inside of a colossal cylindrical machine well, a vertical shaft hundreds of metres across, seen from a ledge part-way down looking across and slightly downward. No sky at all. The far curving wall is old sandstone masonry at the top giving way lower down to riveted dark metal plating, ringed with galleries, huge pipes, cable bundles and silent gantry bridges, all as soft hazy silhouettes. Three broad diagonal shafts of warm dusty light fall from an unseen opening far above and fade into teal-violet gloom below; a faint hint of magenta glow rises from the very bottom. Palette strictly: muted dusty amber and tan in the upper third blending into slate blue-grey, deep teal and dim violet in the lower two thirds. Dim, quiet, cavernous, medium-dark overall."),
 ("backdrop__lower", "1536x1024", "opaque", None, BACK + "Scene: an INTERIOR, pitch-dark subterranean depths, no sky, no clouds. Almost the whole image is near-black indigo (#0e0a16 to #1c1328). Barely visible darker-on-dark silhouettes of immense rune-inscribed metal machinery, pillars, pipes and catwalks recede into darkness at the left and right edges. Far away, small soft glows: a few thin vertical magenta neon strips, two or three tiny cyan panels, faint violet glowing rune columns, each blurred by haze and very small in the frame. The centre is empty darkness with only a faint violet mist. Very dark, very low contrast: average brightness under fifteen percent."),
 ("backdrop__core", "1536x1024", "opaque", None, BACK + "Scene: an INTERIOR, a vast dark cathedral-like underground chamber housing an ancient time machine, no sky, no clouds. In the far distance, dead centre but small and soft, hang enormous concentric metal rings and two giant tape-reel-like wheels around a pale core of light, wrapped in a slow spiral ribbon of softly glowing magnetic tape; the glow is a soft violet-white haze with magenta and cyan edges and a touch of warm yellow at its heart. Colossal rune-carved dark metal buttresses curve up the left and right sides into blackness, with faint glowing rune lines. Palette strictly: deep indigo and dark violet (#120c1e to #33214f) with the single luminous but soft, diffuse central haze. Dark overall, awe, stillness, immense scale."),
 # -- tape art: stickers ---------------------------------------------------------------------------------
 ("sticker__rec", "1536x1024", "transparent", None, "The word \"REC\" (spelt exactly R E C) with a solid round record dot before it, hot red-pink (#ff4d6d) fill, " + STICKER),
 ("sticker__take", "1536x1024", "transparent", None, "The word \"TAKE\" (spelt exactly T A K E), warm yellow (#ffd23f) fill, " + STICKER),
 ("sticker__commit", "1536x1024", "transparent", None, "The word \"COMMIT\" (spelt exactly C O M M I T, six letters) with a small tick mark after it, fresh green (#7dff6b) fill, " + STICKER),
 ("sticker__retry", "1536x1024", "transparent", None, "The word \"RETRY\" (spelt exactly R E T R Y, five letters) with a small circular arrow after it, bright cyan (#3ec5ff) fill, " + STICKER),
 ("sticker__clang", "1536x1024", "transparent", None, "The word \"CLANG\" (spelt exactly C L A N G, five letters) as a loud comic impact sound effect with an exclamation mark and a spiky starburst behind the letters, warm yellow (#ffd23f) letters on an orange-red burst, " + STICKER),
 ("sticker__desync", "1536x1024", "transparent", None, "The word \"DESYNC\" (spelt exactly D E S Y N C, six letters), the letters jolted out of line and split by a horizontal glitch offset, hot magenta (#ff3fa4) fill with a cyan offset edge, " + STICKER),
 ("sticker__resync", "1536x1024", "transparent", None, "The word \"RESYNC\" (spelt exactly R E S Y N C, six letters), neat and snapped into line with two small lock-in ticks either side, bright cyan (#3ec5ff) fill, " + STICKER),
 ("sticker__wipe", "1536x1024", "transparent", None, "The word \"WIPE\" (spelt exactly W I P E, four letters) with a smeared swipe streak dragging off the last letter, violet (#a25bff) fill, " + STICKER),
 ("sticker__5678", "1536x1024", "transparent", None, "A dance count-in: the four numerals 5 6 7 8 in a row with spaces between them (exactly: 5, 6, 7, 8), each numeral a little bigger than the one before, in four colours in order: red-pink (#ff4d6d), yellow (#ffd23f), cyan (#3ec5ff), green (#7dff6b), " + STICKER),
]


def jcard(letter, hexcol, name, motif):
    return (f"Flat graphic design of the front cover of a cassette tape J-card insert, portrait, filling the whole image edge to edge "
      f"(no cassette, no case, no table, no perspective, no drop shadow). Hand-made mixtape cover in bold cel-shaded anime poster style with thick ink "
      f"lines and scrappy street-art energy. Dominant colour {name} ({hexcol}) on off-black ink (#17131c) with cream paper accents. "
      f"A huge hand-lettered capital letter \"{letter}\" dominates the upper two-thirds. Under it, a hand-lettered line reading exactly \"TAPE {letter}\". "
      f"Motif: {motif}. A band of diagonal stripes along the bottom edge, small doodles (stars, tape reels, arrows) in the gaps, slight "
      f"photocopy grain and a worn fold line. No other words, no small print, no barcodes.")


def label(letter, hexcol, name):
    return (f"A cassette shell label sticker (the paper label that sits on the face of an audio cassette), isolated on a fully transparent "
      f"background, flat front-on, landscape rounded rectangle with a wide rounded window cut-out in its lower middle where the tape reels would show "
      f"(the cut-out is transparent). Cream paper with a broad {name} ({hexcol}) band, thick black ink outline, hand-lettered with a marker: a large "
      f"capital \"{letter}\" at the left and the words \"TAPE {letter}\" on the ruled writing line, plus one tiny doodled star. Bold cel-shaded anime "
      f"prop style, slightly worn corners. No cassette body, no screws, no reels, no shadow, no other text.")


JOBS += [
 # (first two passes had no character reference and the model added a generic anime girl: rejected)
 ("jcard__a", "1024x1536", "opaque", ["refs/moxie_bust.png"], jcard("A", "#ff4d6d", "hot red-pink", "an X-eyed smiley face and spray drips")),
 ("jcard__b", "1024x1536", "opaque", ["refs/moxie_bust.png", "raw/jcard__a.png"], "Second attached image is the finished cover A: use it as the layout and style template for a matching set (same layout, same lettering hand, same Moxie in the same corner with a different expression, new letter, new colour, new motif). " + jcard("B", "#ffd23f", "warm yellow", "lightning bolts and a boombox")),
 ("jcard__c", "1024x1536", "opaque", ["refs/moxie_bust.png", "raw/jcard__a.png"], "Second attached image is the finished cover A: use it as the layout and style template for a matching set (same layout, same lettering hand, same Moxie in the same corner with a different expression, new letter, new colour, new motif). " + jcard("C", "#3ec5ff", "bright cyan", "a jagged audio waveform and a little ghost")),
 ("jcard__d", "1024x1536", "opaque", ["refs/moxie_bust.png", "raw/jcard__a.png"], "Second attached image is the finished cover A: use it as the layout and style template for a matching set (same layout, same lettering hand, same Moxie in the same corner with a different expression, new letter, new colour, new motif). " + jcard("D", "#7dff6b", "fresh green", "creeping vines and a five-point scribble star")),
 ("label__a", "1536x1024", "transparent", None, label("A", "#ff4d6d", "hot red-pink")),
 ("label__b", "1536x1024", "transparent", ["raw/label__a.png"], "Matching set, same shape, layout and lettering hand as the attached label, with a new letter and colour: " + label("B", "#ffd23f", "warm yellow")),
 ("label__c", "1536x1024", "transparent", ["raw/label__a.png"], "Matching set, same shape, layout and lettering hand as the attached label, with a new letter and colour: " + label("C", "#3ec5ff", "bright cyan")),
 ("label__d", "1536x1024", "transparent", ["raw/label__a.png"], "Matching set, same shape, layout and lettering hand as the attached label, with a new letter and colour: " + label("D", "#7dff6b", "fresh green")),
]


# -- graffiti: the words the levels ask for (DecorDef.variant in data/levels/*.json). The file name is the
#    variant lower-cased with everything but letters and digits removed, which is how
#    world/world_graffiti.gd looks a painted tag up ("+1" -> 1.png, "3/4" -> 34.png, "A/B" -> ab.png).
LEVEL_TAGS = [
 ("roll_tape", "ROLL TAPE", PINK, ""), ("on_air", "ON AIR", PINK, "A small sprayed radio-wave arc doodle after it."),
 ("off_air", "OFF AIR", VIOLET, ""), ("dead_air", "DEAD AIR", VIOLET, "Thin scrawled letters."),
 ("run_it", "RUN IT", YELLOW, ""), ("ghost_me", "GHOST ME", CYAN, ""), ("keep_it", "KEEP IT", PINK, ""),
 ("kept", "KEPT", VIOLET, "A sprayed tick mark after it."), ("again_again", "AGAIN AGAIN", PINK, "The two words stacked on two lines."),
 ("2_of_me", "2 OF ME", VIOLET, "The numeral 2 is larger than the letters."),
 ("mind_the_teeth", "MIND THE TEETH", YELLOW, "Stacked on two lines (MIND THE on top, TEETH below), with a row of sprayed zig-zag teeth underneath."),
 ("mind_yr_head", "MIND YR HEAD", PINK, "Stacked on two lines (MIND YR on top, HEAD below), thin fast scrawl."),
 ("down", "DOWN", VIOLET, "A sprayed arrow pointing down after it."), ("dock", "DOCK", CYAN, ""),
 ("one", "ONE", PINK, ""), ("two", "TWO", VIOLET, ""), ("three", "THREE", PINK, ""),
 ("amp", "AMP", YELLOW, "A small sprayed lightning bolt after it."), ("mains", "MAINS", YELLOW, ""),
 ("on_file", "ON FILE", VIOLET, ""), ("list_only", "LIST ONLY", PINK, "Thin fast scrawl."),
 ("look_away", "LOOK AWAY", VIOLET, ""), ("long_way", "LONG WAY", PINK, "A long wandering sprayed arrow under the words."),
 ("after_you", "AFTER YOU", CYAN, ""), ("ask_twice", "ASK TWICE", VIOLET, ""),
 ("far_one_first", "FAR ONE FIRST", PINK, "Stacked on two lines (FAR ONE on top, FIRST below), thin fast scrawl."),
 ("flat_rate", "FLAT RATE", VIOLET, ""), ("hot_side", "HOT SIDE", PINK, "Little sprayed flame ticks above the word HOT."),
 ("wait_4_ur_spark", "WAIT 4 UR SPARK", YELLOW, "Stacked on two lines (WAIT 4 UR on top, SPARK below), with a small sprayed spark star."),
 ("1_bar_2_bar", "1 BAR 2 BAR", VIOLET, "Stacked on two lines (1 BAR on top, 2 BAR below)."),
 ("2_keys", "2 KEYS", YELLOW, "The numeral 2 is larger than the letters."),
 ("1", "+1", PINK, "Just a plus sign and the numeral one, very large."),
 ("5", "5", VIOLET, "Just the single numeral five, very large, circled with a sprayed ring."),
 ("34", "3/4", PINK, "A fraction: numeral three, a slash, numeral four, very large."),
 ("ab", "A/B", VIOLET, "Capital A, a slash, capital B, very large."),
 ("x2", "x2", CYAN, "A small lower-case multiplication x followed by a very large numeral two, meaning times two."),
]
JOBS += [("graffiti__" + f, "1536x1024", "transparent", None, tag(w, c, e)) for f, w, c, e in LEVEL_TAGS]


def run(job):
    name, size, bg, refs, prompt = job
    out = os.path.join(RAW, name + ".png")
    if os.path.exists(out) and "--force" not in sys.argv:
        return name, "exists"
    if refs:
        env = dict(os.environ, IMG_SIZE=size, IMG_BG=bg)
        cmd = ["bash", "tools/img", "edit", "art/world_art/raw/" + name + ".png", prompt] + ["art/world_art/" + r for r in refs]
    else:
        env = dict(os.environ)
        cmd = ["bash", "tools/img", "gen", "art/world_art/raw/" + name + ".png", prompt, size, bg]
    # the proxy is shared and drops requests when busy: retry with a pause
    for attempt in range(1, 7):
        r = subprocess.run(cmd, cwd=ROOT, env=env, capture_output=True, text=True)
        if os.path.exists(out):
            return name, "saved (attempt %d)" % attempt
        time.sleep(20)
    return name, "FAILED: " + (r.stdout + r.stderr).strip()[:200]


if __name__ == "__main__":
    pats = [a for a in sys.argv[1:] if not a.startswith("--")]
    jobs = [j for j in JOBS if not pats or any(p in j[0] for p in pats)]
    # anchors first: jobs that other jobs reference must exist before the dependants start
    jobs.sort(key=lambda j: sum(1 for r in (j[3] or []) if r.startswith("raw/")))
    with ThreadPoolExecutor(2) as ex:
        for name, msg in ex.map(run, jobs):
            print(name, "->", msg, flush=True)
