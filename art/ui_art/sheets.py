"""Contact sheet + in-context mock-ups.   python -I art/ui_art/sheets.py
   -> art/ui_art/sheets/contact_sheet.png, contact_alpha_magenta.png, mock_title.png, mock_hud_busy.png"""
import sys, os, json, glob
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image, ImageDraw
from nine import render9
from lib import OUT, ROOT
SH = os.path.join(ROOT, 'art', 'ui_art', 'sheets'); os.makedirs(SH, exist_ok=True)
sl = json.load(open(os.path.join(OUT, 'ui', 'slices.json')))
files = sorted(p for p in glob.glob(os.path.join(OUT, '**', '*.png'), recursive=True))
def I(rel): return Image.open(os.path.join(OUT, rel)).convert('RGBA')

def contact(bg, name):
    cw, ch, cols = 300, 250, 6
    rows = (len(files) + cols - 1) // cols
    c = Image.new('RGB', (cols * cw, rows * ch), bg); d = ImageDraw.Draw(c)
    for i, p in enumerate(files):
        im = Image.open(p).convert('RGBA'); w, h = im.size
        t = im.copy(); t.thumbnail((cw - 16, ch - 44))
        x, y = (i % cols) * cw, (i // cols) * ch
        c.paste(t, (x + (cw - t.width) // 2, y + 6 + (ch - 44 - t.height) // 2), t)
        rel = os.path.relpath(p, OUT).replace(os.sep, '/')
        d.text((x + 6, y + ch - 34), rel[-46:], fill=(255, 255, 255)); d.text((x + 6, y + ch - 20), '%dx%d %s' % (w, h, Image.open(p).mode), fill=(255, 210, 63))
    c.save(os.path.join(SH, name)); print('wrote', name, len(files), 'files')

def put9(c, rel, x, y, w, h):
    m = sl[rel]; c.alpha_composite(render9(I(rel), w, h, m['left'], m['top'], m['right'], m['bottom']), (x, y))

def mock_title():
    c = I('keyart/title_1600x900.png')
    logo = I('logo/overdub_logo_wordmark_1024.png'); logo = logo.resize((520, round(520 * logo.height / logo.width)), Image.LANCZOS)
    c.alpha_composite(logo, (40, 60))
    put9(c, 'ui/panel.png', 60, 300, 420, 420)
    for i, st in enumerate(('hover', 'normal', 'normal', 'disabled')):
        put9(c, 'ui/button_%s.png' % st, 90, 330 + i * 92, 360, 86)
    put9(c, 'ui/tooltip.png', 470, 300, 260, 100)
    c.alpha_composite(I('logo/overdub_mark_64.png'), (1520, 820))
    c.convert('RGB').save(os.path.join(SH, 'mock_title.png')); print('wrote mock_title.png')

def mock_hud():
    busy = os.path.join(ROOT, 'art', 'previews', 'kit', 'diorama__upper.png')
    b = Image.open(busy).convert('RGBA') if os.path.exists(busy) else I('cards/chapter_1_upper_ruins.png')
    s = max(1600 / b.width, 900 / b.height); c = b.resize((round(b.width * s), round(b.height * s))).crop((0, 0, 1600, 900))
    m = sl['ui/cassette_shell.png']; reel = I('ui/cassette_reel.png')
    for i, n in enumerate(('red', 'yellow', 'blue', 'green')):
        x = 40 + i * 250
        put9(c, 'ui/panel.png', x, 640, 236, 236)
        sh = I('ui/cassette_shell_%s.png' % n); lay = Image.new('RGBA', sh.size, (0, 0, 0, 0))
        for (hx, hy), d in zip(m['hub_centres'], (200 - i * 25, 110 + i * 25)):
            rr = reel.rotate(13 * i + 7, Image.BICUBIC).resize((d, d), Image.LANCZOS); lay.alpha_composite(rr, (hx - d // 2, hy - d // 2))
        x0, y0, ww, hh = m['window_rect']; comp = Image.new('RGBA', sh.size, (0, 0, 0, 0)); comp.paste(lay.crop((x0, y0, x0 + ww, y0 + hh)), (x0, y0)); comp.alpha_composite(sh)
        comp = comp.resize((200, round(200 * sh.height / sh.width)), Image.LANCZOS); c.alpha_composite(comp, (x + 18, 656))
        put9(c, 'ui/progress_track.png', x + 18, 820, 200, 0)
        f = render9(I('ui/progress_fill.png'), 60 + i * 40, 0, 28, 0, 28, 0)
        col = {'red': (255, 77, 109), 'yellow': (255, 210, 63), 'blue': (62, 197, 255), 'green': (125, 255, 107)}[n]
        tint = Image.new('RGBA', f.size, col + (255,)); from PIL import ImageChops; f = ImageChops.multiply(f, tint); c.alpha_composite(f, (x + 18, 820))
    t = I('ui/ruler_strip_dark.png'); t = t.resize((256, 40), Image.LANCZOS)
    for k in range(4): c.alpha_composite(t, (1040 + k * 256 - 500, 590)) if False else None
    for k in range(4): c.alpha_composite(t, (40 + k * 256, 590))
    put9(c, 'ui/dialogue_box.png', 400, 40, 800, 170); put9(c, 'ui/toast.png', 1180, 240, 380, 0); put9(c, 'ui/tooltip.png', 1100, 420, 240, 96)
    put9(c, 'ui/name_tab.png', 1100, 560, 200, 52)
    d = I('doll/moxie_doll.png'); d.thumbnail((300, 440)); put9(c, 'ui/panel.png', 1300, 400, 280, 480); c.alpha_composite(d, (1320, 420))
    c.convert('RGB').save(os.path.join(SH, 'mock_hud_busy.png')); print('wrote mock_hud_busy.png')

contact((27, 23, 20), 'contact_sheet.png'); contact((255, 0, 255), 'contact_alpha_magenta.png'); mock_title(); mock_hud()
