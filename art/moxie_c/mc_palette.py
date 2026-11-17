"""Material palette: name -> (hex sRGB, roughness, emission strength[, texture file])."""
import os

import mc_util as U

SKIN = "c88960"

PAL = {
    "skin": (SKIN, 0.75),
    "skin_face": (SKIN, 0.75, 0.0, "moxie_face.png"),
    "mouth_in": ("7a3a34", 0.8),
    "eye": ("f6f0e8", 0.5, 0.0, "moxie_eyes.png"),
    "teeth": ("fbf6ee", 0.5),
    "lash": ("1e100e", 0.8),
    "hair": ("47281b", 0.7),
    "hair_dark": ("2e1812", 0.7),
    "hair_tie": ("c2274a", 0.6),
    "hp_yellow": ("f5b914", 0.45),
    "hp_dark": ("2a2428", 0.6),
    "hp_cushion": ("3a3136", 0.9),
    "metal": ("9a9aa2", 0.35),
    "metal_dark": ("4a4a52", 0.4),
    "top_light": ("e9e1d2", 0.85),
    "top_trim": ("2a2327", 0.85),
    "top_graphic": ("8c7a5c", 0.85),
    "strap_dark": ("332a2c", 0.8),
    "jacket_dark": ("38292c", 0.85),
    "jacket_lining": ("f2b21a", 0.8),
    "jacket_rib": ("241b1e", 0.9),
    "jacket_patch": ("d8cfc0", 0.8),
    "pants_olive": ("6a6038", 0.9, 0.0, "moxie_pants.png"),
    "pants_dark": ("4a4428", 0.9),
    "pants_graphic": ("f0b416", 0.85),
    "pants_cuff": ("8f8658", 0.9),
    "tear_skin": (SKIN, 0.75),
    "belt": ("2c2528", 0.7),
    "pouch": ("4b4a40", 0.8),
    "pouch_dark": ("2f2c2c", 0.8),
    "walkman": ("f2b81a", 0.4),
    "walkman_dark": ("2b2628", 0.5),
    "strap_pink": ("c8285a", 0.7),
    "glove": ("2a2326", 0.85),
    "device": ("3a3438", 0.5),
    "screen_glow": ("5fe6e0", 0.3, 2.5),
    "vial_glow": ("7ff0d8", 0.3, 2.0),
    "shoes_main": ("d9cdbd", 0.8),
    "shoes_dark": ("3a2c30", 0.8),
    "shoes_sole": ("e6dccb", 0.9),
    "shoes_accent": ("f2b417", 0.7),
    "lace": ("f5c21c", 0.7),
    "cable": ("e8b020", 0.6),
    "choker": ("241c1f", 0.7),
}


def install(tex_dir):
    for k, v in PAL.items():
        if len(v) > 3:
            v = (v[0], v[1], v[2], os.path.join(tex_dir, v[3]))
        U.PALETTE[k] = v
