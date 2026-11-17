"""Step 9 (venv python): publish the model sheets under docs/reference/generated/ with stable names, build the combined
sheets, and tile art/previews/moxie_e/candidates.png from the raw generator clay renders."""
import os, sys, shutil
from PIL import Image, ImageDraw
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
GEN = os.path.join(ROOT, 'docs', 'reference', 'generated'); W = os.path.join(GEN, 'work'); PREV = os.path.join(ROOT, 'art', 'previews', 'moxie_e')
os.makedirs(os.path.join(GEN, 'head'), exist_ok=True); os.makedirs(os.path.join(GEN, 'gear'), exist_ok=True)
COPY = {
    'tpose_back1.png': 'moxie_tpose_back.png', 'q34back_1.png': 'moxie_threequarter_back.png',
    'head_front1.png': 'head/moxie_head_front.png', 'head_side1.png': 'head/moxie_head_left.png', 'head_q34_1.png': 'head/moxie_head_threequarter.png',
    'head_back1.png': 'head/moxie_head_back.png', 'head_grin1.png': 'head/moxie_head_grin_front.png', 'head_grin_side1.png': 'head/moxie_head_grin_left.png',
    'head_grin_q34_1.png': 'head/moxie_head_grin_threequarter.png', 'head_bare_front1.png': 'head/moxie_head_hairback_front.png',
    'head_bare_side1.png': 'head/moxie_head_hairback_left.png', 'hair_study1.png': 'head/moxie_hair_study.png',
    'gear_audio1.png': 'gear/moxie_gear_headphones_walkman.png', 'gear_wear1.png': 'gear/moxie_gear_wearables.png',
}
for a, b in COPY.items():
    shutil.copyfile(os.path.join(W, a), os.path.join(GEN, b))


def tile(out, rows, h, bg=(128, 128, 128), labels=None):
    ims = [[Image.open(p).convert('RGB') for p in r] for r in rows]
    ims = [[im.resize((round(im.width * h / im.height), h), Image.LANCZOS) for im in r] for r in ims]
    width = max(sum(im.width for im in r) for r in ims)
    sheet = Image.new('RGB', (width, h * len(ims)), bg)
    d = ImageDraw.Draw(sheet)
    for j, r in enumerate(ims):
        x = 0
        for i, im in enumerate(r):
            sheet.paste(im, (x, j * h))
            if labels: d.text((x + 10, j * h + 8), labels[j][i], fill=(255, 255, 255))
            x += im.width
    sheet.save(out); print('wrote', os.path.relpath(out, ROOT), sheet.size)


g = lambda n: os.path.join(GEN, n)
tile(g('moxie_turnaround_sheet.png'), [[g('moxie_front.png'), g('moxie_threequarter.png'), g('moxie_left.png'), g('moxie_back.png'), g('moxie_right.png')]], 1536)
tile(g('head/moxie_head_sheet.png'), [[g('head/moxie_head_front.png'), g('head/moxie_head_left.png'), g('head/moxie_head_threequarter.png'), g('head/moxie_head_back.png')],
                                      [g('head/moxie_head_grin_front.png'), g('head/moxie_head_grin_left.png'), g('head/moxie_head_grin_threequarter.png'), g('head/moxie_head_hairback_front.png')]], 1024)
wk = os.path.join(HERE, 'work')
tile(os.path.join(PREV, 'candidates.png'), [[os.path.join(wk, 'view_body_flb.png')], [os.path.join(wk, 'view_heads.png')]], 1100, bg=(0, 0, 0))
