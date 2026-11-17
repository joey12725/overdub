"""Named preview shots. Works on loose parts (dev) or on the rigged model (with a pose)."""
import os

import bpy

import mc_render as R

HEAD = (0, 0.0, 1.492)


def _pose(name):
    rig = bpy.data.objects.get("Rig")
    if rig is None or not name:
        return
    import mc_rig
    import poses
    mc_rig.set_pose(rig, poses.TESTS[name])


def shoot(names, prev, tag, toon=False, pose=None):
    os.makedirs(prev, exist_ok=True)
    R.setup('toon' if toon else 'soft')
    suffix = "_toon" if toon else ""
    _pose(pose)
    toon_done = [False]

    def ink(w):
        if toon and not toon_done[0]:
            R.apply_toon(outline=w)
            toon_done[0] = True

    def out(n):
        return os.path.join(prev, "_%s_%s%s.png" % (tag, n, suffix))
    for n in names:
        if n == "face":
            ink(0.0016)
            R.render(out("face0"), HEAD, 0, 0, 0.27, (800, 800))
            R.render(out("face1"), HEAD, 35, 6, 0.27, (800, 800))
            R.render(out("face2"), HEAD, 90, 0, 0.27, (800, 800))
        if n == "hc":         # head check: strict orthographic front / left profile / three-quarter
            ink(0.0014)       # at 3000 px per metre, centred on (0, -0.015, 1.493) (see ref_compare.py)
            for i, yaw in enumerate((0, 90, -38)):
                R.render(out("hc%d" % i), (0, -0.015, 1.493), yaw, 0, 0.30, (900, 900))
        if n == "sheet":      # same framing as the 1152x1536 model sheets: 835 px per metre, soles at row 1478
            ink(0.003)
            for i, yaw in enumerate((0, 90)):
                R.render(out("sheet%d" % i), (0, 0, 0.8503), yaw, 0, 1536 / 835.0, (1152, 1536))
        if n == "head":
            ink(0.0022)
            c = (0, 0.02, 1.515)
            for i, yaw in enumerate((0, 35, 90, 180)):
                R.render(out("head%d" % i), c, yaw, 5, 0.60, (700, 700))
        if n == "hand":
            ink(0.0012)
            c = (0.585, 0.0, 1.323)
            R.render(out("hand0"), c, 0, 89, 0.24, (600, 600))
            R.render(out("hand1"), c, 0, -89, 0.24, (600, 600))
            R.render(out("hand2"), c, 20, 20, 0.24, (600, 600))
            R.render(out("hand3"), c, 120, 25, 0.24, (600, 600))
        if n == "body":       # T-pose framing (wide)
            ink(0.004)
            for i, yaw in enumerate((0, 40, 90, 180)):
                R.render(out("body%d" % i), (0, 0, 0.86), yaw, 0, 1.84,
                         (900, 1000) if yaw in (0, 180) else (640, 1000))
        if n == "turn":       # presentation turnaround: front, three-quarter, side, back
            ink(0.0035)
            R.floor(True)
            for i, yaw in enumerate((0, 40, 90, 180)):
                R.render(out("turn%d" % i), (0, 0, 0.86), yaw, 0, 1.86, (620, 1100))
            R.floor(False)
        if n == "upper":
            ink(0.0028)
            for i, yaw in enumerate((0, 40, 180)):
                R.render(out("upper%d" % i), (0, 0, 1.25), yaw, 4, 0.95, (800, 800))
        if n == "lower":
            ink(0.0028)
            for i, yaw in enumerate((0, 50, 180)):
                R.render(out("lower%d" % i), (0, 0, 0.48), yaw, 6, 1.05, (700, 800))
        if n == "iso":
            ink(0.004)
            R.floor(True)
            R.render(out("iso0"), (0, 0, 0.84), 45, 35, 2.0, (800, 1000))
            R.floor(False)
        if n == "pose2":      # one pose from two angles (deformation tests)
            ink(0.0035)
            R.render(out("pose20"), (0, 0, 0.90), 25, 6, 1.95, (600, 760))
            R.render(out("pose21"), (0, 0, 0.90), 155, 6, 1.95, (600, 760))
