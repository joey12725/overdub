"""Stretch every nine-slice piece to several sizes over a dark ground and over a busy screenshot.
   python -I art/ui_art/verify_ui.py  -> art/ui_art/sheets/ui_stretch_dark.png, ui_stretch_busy.png"""
import sys, os, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image
from nine import render9
from lib import OUT, ROOT
SH = os.path.join(ROOT, 'art', 'ui_art', 'sheets'); os.makedirs(SH, exist_ok=True)
sl = json.load(open(os.path.join(OUT, 'ui', 'slices.json')))
busy = os.path.join(ROOT, 'art', 'previews', 'kit', 'diorama__lower.png')
grounds = {'dark': Image.new('RGBA', (1600, 900), (27, 23, 20, 255))}
if os.path.exists(busy):
    b = Image.open(busy).convert('RGBA'); s = max(1600 / b.width, 900 / b.height)
    b = b.resize((round(b.width * s), round(b.height * s))).crop((0, 0, 1600, 900)); grounds['busy'] = b
def g(n): return Image.open(os.path.join(OUT, n)).convert('RGBA'), sl[n]
def put(c, n, x, y, w, h):
    im, m = g(n); r = render9(im, w, h, m['left'], m['top'], m['right'], m['bottom']); c.alpha_composite(r, (x, y))
for gn, ground in grounds.items():
    c = ground.copy()
    put(c, 'ui/panel.png', 20, 20, 420, 300); put(c, 'ui/panel.png', 460, 20, 90, 90); put(c, 'ui/panel.png', 570, 20, 200, 64)
    put(c, 'ui/dialogue_box.png', 20, 340, 900, 190); put(c, 'ui/dialogue_box.png', 940, 340, 400, 130)
    y = 560
    for k in ('normal', 'hover', 'pressed', 'disabled'):
        put(c, 'ui/button_%s.png' % k, 20, y, 280, 86); put(c, 'ui/button_%s.png' % k, 320, y, 120, 86); put(c, 'ui/button_%s.png' % k, 460 + 100 * ['normal','hover','pressed','disabled'].index(k), 560, 90, 150); y += 84
    put(c, 'ui/toast.png', 800, 20, 520, 76); put(c, 'ui/toast.png', 800, 110, 300, 110)
    put(c, 'ui/tooltip.png', 1100, 130, 300, 90); put(c, 'ui/tooltip.png', 1100, 230, 180, 140)
    put(c, 'ui/progress_track.png', 800, 250, 280, 0); put(c, 'ui/progress_fill.png', 800, 250, 170, 0)
    put(c, 'ui/progress_track.png', 800, 300, 120, 0); put(c, 'ui/progress_fill.png', 800, 300, 120, 0)
    for i, n in enumerate(('ui/ruler_strip.png', 'ui/ruler_strip_dark.png')):
        t = Image.open(os.path.join(OUT, n)).convert('RGBA'); t = t.resize((t.width // 2, t.height // 2), Image.LANCZOS)
        for k in range(3): c.alpha_composite(t, (900 + k * t.width, 560 + i * 60))
    sh = Image.open(os.path.join(OUT, 'ui/cassette_shell_blue.png')).convert('RGBA'); m = sl['ui/cassette_shell.png']
    reel = Image.open(os.path.join(OUT, 'ui/cassette_reel.png')).convert('RGBA')
    lay = Image.new('RGBA', sh.size, (0, 0, 0, 0))
    for (hx, hy), ang, d in zip(m['hub_centres'], (17, 43), (190, 130)):
        rr = reel.rotate(ang, Image.BICUBIC).resize((d, d), Image.LANCZOS); lay.alpha_composite(rr, (hx - d // 2, hy - d // 2))
    x0, y0, ww, hh = m['window_rect']; win = Image.new('RGBA', sh.size, (0, 0, 0, 0)); win.paste(lay.crop((x0, y0, x0 + ww, y0 + hh)), (x0, y0))
    win.alpha_composite(sh); win = win.resize((320, round(320 * sh.height / sh.width)), Image.LANCZOS)
    c.alpha_composite(win, (900, 690))
    c.convert('RGB').save(os.path.join(SH, 'ui_stretch_%s.png' % gn)); print('wrote ui_stretch_%s.png' % gn)
