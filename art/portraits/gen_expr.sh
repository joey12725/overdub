#!/usr/bin/env bash
# usage: bash art/portraits/gen_expr.sh <anchor.png> <out.png> "<what stays>" "<what changes>"   (run from repo root)
# Derives an expression from a character's anchor portrait so only the expression changes.
P="The input image is the approved portrait of a game character. Redraw it EXACTLY: same character, same face shape and age, same drawing style (cel-shaded anime, bold clean black ink line, flat colours with one hard shadow tone), same colours, same framing, same scale, same head position and size in the frame, same viewing angle and facing direction, same hair, same clothes and accessories: $3 CHANGE ONLY what is described here: $4 Keep the whole head inside the frame with empty headroom above; the bust runs off the bottom edge. Fully transparent background, no backdrop, no text, no border, no watermark, no extra characters. Any visible hand has exactly five fingers and correct anatomy."
IMG_BG=transparent bash "${IMG_TOOL:-tools/img}" edit "$2" "$P" "$1"
