"""Crop the reference art into generator inputs (art/moxie_d/inputs)."""
from PIL import Image
import os
R = "docs/reference/"; O = "art/moxie_d/inputs/"
r01 = Image.open(R + "R01-moxie-concept.png").convert("RGB")
r01.crop((113, 128, 907, 1185)).save(O + "r01_hero.png")
r01.crop((330, 128, 700, 420)).resize((1110, 876), Image.LANCZOS).save(O + "r01_face.png")
d = Image.open(R + "R02-moxie-details.png").convert("RGB")
d.crop((63, 108, 904, 592)).save(O + "r02_turnaround.png")
xs = {"front": (75, 250), "34front": (255, 440), "side": (440, 590), "34back": (585, 740), "back": (740, 900)}
for k, (a, b) in xs.items():
    im = d.crop((a, 112, b, 560)); im = im.resize((im.width * 3, im.height * 3), Image.LANCZOS); im.save(O + f"r02_{k}.png")
s = Image.open(R + "R02-moxie-sheet.png").convert("RGB")
s.crop((112, 101, 1328, 913)).save(O + "r02_sheet.png")
s.crop((112, 101, 470, 690)).save(O + "r02_bust.png")
d.crop((164, 628, 1276, 912)).save(O + "r02_details.png")
