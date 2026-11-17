"""Clean the chosen logotypes and export them.  python -I art/ui_art/build_logo.py"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *

def prep(name):
    return trim(drop_specks(clean_alpha(load(name))))

a = prep('logo_a')       # primary: horizontal wordmark, reel "O"
b = prep('logo_b')       # secondary: cassette sticker
d = prep('logo_d')       # stacked lockup
c = prep('logo_c')       # alternate (angular)
m = prep('mark_a')       # compact mark

save(trim(a, 16), 'logo/overdub_logo_wordmark.png')
save(fit(a, 1024, 384, 8), 'logo/overdub_logo_wordmark_1024.png')
save(trim(b, 16), 'logo/overdub_logo_cassette.png')
save(fit(b, 1024, 704, 8), 'logo/overdub_logo_cassette_1024.png')
save(trim(d, 16), 'logo/overdub_logo_stacked.png')
save(trim(c, 16), 'logo/alt/overdub_logo_angular.png')
for s in (512, 256, 128, 64):
    save(fit(m, s, s, max(2, s // 32)), 'logo/overdub_mark_%d.png' % s)
