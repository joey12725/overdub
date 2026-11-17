"""Export the illustrations (key art, chapter cards, ending) and the loadout paper doll.
   python -I art/ui_art/build_art.py"""
import sys, os, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image, ImageFilter
from lib import load, clean_alpha, drop_specks, trim, fit, save, RAW, OUT


def rgb(name):
    return Image.open(os.path.join(RAW, name + '.png')).convert('RGB')


def illustrations():
    for src, dst in (('keyart_c', 'keyart/title_1536x1024.png'), ('keyart_portrait', 'keyart/title_1024x1536.png'),
                     ('chapter_1', 'cards/chapter_1_upper_ruins.png'), ('chapter_2', 'cards/chapter_2_the_middle.png'),
                     ('chapter_3', 'cards/chapter_3_neon_depths.png'), ('chapter_4', 'cards/chapter_4_time_machine.png'),
                     ('ending_b', 'cards/ending.png'), ('ending', 'cards/ending_alt_approach.png')):
        save(rgb(src), dst)
    # 16:9 title for the 1600x900 viewport: a centre crop would cut her hair and boots, so fit the
    # painting to the height and extend the (dark, empty) left side with a blurred continuation.
    k = rgb('keyart_c').resize((1350, 900), Image.LANCZOS)
    out = Image.new('RGB', (1600, 900))
    ext = k.crop((0, 0, 250, 900)).transpose(Image.FLIP_LEFT_RIGHT).filter(ImageFilter.GaussianBlur(24))
    out.paste(ext, (0, 0)); out.paste(k, (250, 0))
    # soften the seam: blend a blurred copy over a 120 px band around x=250
    blur = out.filter(ImageFilter.GaussianBlur(18))
    m = Image.new('L', (1600, 900), 0)
    ma = np.zeros((900, 1600), np.float32)
    xs = np.arange(1600)
    ma[:] = np.clip(1 - np.abs(xs - 250) / 90.0, 0, 1)[None, :] * 255
    ma[:, :250] = np.maximum(ma[:, :250], 255 * np.clip((250 - xs[:250]) / 60.0, 0, 1)[None, :] * 0 + ma[:, :250])
    m = Image.fromarray(ma.astype(np.uint8), 'L')
    out = Image.composite(blur, out, m)
    save(out, 'keyart/title_1600x900.png')


def doll():
    W, H = 480, 880
    d = fit(trim(drop_specks(clean_alpha(load('ui_doll')), 300)), W, H, 8)
    save(d, 'doll/moxie_doll.png')
    a = np.asarray(d)
    al = a[..., 3]
    yy, xx = np.mgrid[0:H, 0:W]
    reg = np.zeros((H, W), np.uint8)
    arms = (xx < 112) | (xx > 350)
    reg[(yy >= 712)] = 4                                               # feet
    reg[(yy >= 372) & (yy < 712) & ~arms] = 3                          # legs
    reg[(yy >= 190) & (yy < 372)] = 2                                  # torso (jacket, top, arms)
    reg[(yy >= 372) & (yy < 460) & arms] = 2
    reg[(yy >= 345) & (yy < 372) & (xx > 180) & (xx < 300)] = 3        # belt line belongs to the legs
    reg[(yy < 190)] = 1                                                # head
    reg[(xx < 102) & (yy >= 332) & (yy < 460)] = 5                     # right hand + glove cuff (screen left)
    reg[(xx >= 378) & (yy >= 330) & (yy < 460)] = 6                    # left wrist + hand (screen right)
    reg[al < 128] = 0
    names = ['', 'head', 'torso', 'legs', 'feet', 'right_hand', 'left_wrist']
    cols = [(0, 0, 0, 0), (255, 210, 63, 255), (255, 79, 163, 255), (125, 255, 107, 255), (62, 197, 255, 255),
            (255, 77, 109, 255), (155, 108, 255, 255)]
    lut = np.array(cols, np.uint8)
    save(Image.fromarray(lut[reg], 'RGBA'), 'doll/moxie_doll_regions.png')
    info = {'canvas': [W, H], 'regions': {}}
    for i, n in enumerate(names):
        if not n:
            continue
        m = reg == i
        ys, xs = np.nonzero(m)
        o = np.zeros((H, W, 4), np.uint8); o[..., :3] = 255
        o[..., 3] = np.where(m, al, 0)
        save(Image.fromarray(o, 'RGBA'), 'doll/region_%s.png' % n)
        info['regions'][n] = {'id': i, 'colour': '#%02x%02x%02x' % cols[i][:3],
                              'rect': [int(xs.min()), int(ys.min()), int(xs.max() - xs.min() + 1), int(ys.max() - ys.min() + 1)],
                              'anchor': [int(round(xs.mean())), int(round(ys.mean()))]}
    json.dump(info, open(os.path.join(OUT, 'doll', 'moxie_doll_regions.json'), 'w'), indent=1)
    # flat silhouette: charcoal fill, cream die-cut edge (dilated alpha)
    A = Image.fromarray(al, 'L')
    big = A.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(0.8))
    sil = Image.new('RGBA', (W, H), (244, 236, 216, 0)); sil.putalpha(big)
    inner = Image.new('RGBA', (W, H), (27, 23, 20, 0)); inner.putalpha(A)
    save(Image.alpha_composite(sil, inner), 'doll/moxie_doll_silhouette.png')
    print(json.dumps(info['regions']))


if __name__ == '__main__':
    illustrations()
    doll()
