"""Reference colours the cassette palette is measured against, read from the game sources
where possible (world/world_palette.gd) so the analysis follows the real theme palettes."""
import os
import re

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))

CURRENT = ["#ff4d6d", "#ffd23f", "#3ec5ff", "#7dff6b"]
LETTERS = ["A", "B", "C", "D"]
THEMES = ["upper", "mid", "lower", "core"]

# Surfaces a cassette mark sits ON (floor ring, spark, trail): the playable floor family.
SURFACE_KEYS = ["floor_color", "floor_alt", "wall", "wall_top"]
# Emissive / accent colours that share the frame with cassette marks.
ACCENT_KEYS = ["neon_a", "neon_b", "neon_c", "graffiti", "graffiti_alt", "hazard", "foliage", "rune", "accent", "warm", "rust"]

# HUD surfaces (ui/theme/palette.gd).
HUD = {
    "panel": "#1b1714",      # PANEL_SOLID (PANEL is #14110f at 86 % over the world)
    "track": "#0d0b0a",      # ruler lane background
    "paper": "#f3ead8",      # label strip / text
    "ink": "#14110f",        # ink text drawn ON a cassette colour (letter sticker)
}

# Colours with a fixed, non-cassette meaning. A cassette colour must not be mistaken for these.
RESERVED = {
    "moxie_yellow": "#ffd23f",     # ui/theme/palette.gd MOXIE_YELLOW, headphones / Walkman
    "hazard_upper": "#ffc21a",     # world palette hazard (upper/core ~ same family)
    "hazard_lower": "#ffb020",
    "enemy_eye": "#ff6a1a",        # actors/enemy_specs.gd EYE / DANGER
    "enemy_warning": "#ff3d3d",    # actors/enemy_specs.gd WARNING
    "enemy_fx": "#ff3d5a",         # fx/fx_colors.gd ENEMY
    "laser": "#ff2b5e",            # world/world_mech_accent.gd LASER_BEAM
    "door_closed": "#ff3048",      # world/world_mech_accent.gd STATUS_CLOSED
    "rec_red": "#ff2a3d",          # ui REC lamp
    "chronal_amber": "#ffb347",    # core rune / accent, UI STATE_WARN
    "ghost_grey": "#7d8394",       # actors/actor_style.gd GHOST_GREY
    "state_dead": "#9aa3b5",       # ui STATE_DEAD
    "state_desync": "#c98bff",     # ui STATE_DESYNC
    "boss_recall": "#b26bff",      # fx RECALL
    "shield_teal": "#58f0dc",      # enemy shield / rune glow
}

# Danger colours: a cassette colour close to one of these reads as a threat.
DANGER = ["enemy_eye", "enemy_warning", "enemy_fx", "laser", "door_closed", "rec_red"]


def theme_palettes():
    """{theme: {key: '#rrggbb'}} parsed from world/world_palette.gd."""
    src = open(os.path.join(ROOT, "world", "world_palette.gd"), encoding="utf-8").read()
    out = {}
    for t in THEMES:
        m = re.search(r"static func _%s\(\) -> WorldPalette:(.*?)\n\treturn p" % t, src, re.S)
        assert m, t
        d = {}
        for k, v in re.findall(r"p\.(\w+) = Color\(\"(#[0-9a-fA-F]{6})\"\)", m.group(1)):
            d[k] = v.lower()
        out[t] = d
    return out
