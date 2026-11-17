"""Stage 3: skin material + UVs. The face front gets a planar front projection that matches
paint_face.py; the eye plates use the same projection (material 'eye'); every other skin polygon
samples the plain skin swatch. Run paint_face.py (system python) before this stage."""
import bpy, bmesh, sys, os, json, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mb_util as U
import mb_toon as T

U.open_stage("s02_body")
body = bpy.data.objects["Body"]
me = body.data
L = json.loads(body["landmarks"])
FACE_SPAN = 0.27
ZC = L["z_eye"] - 0.02
SWATCH = (0.03, 0.03)

img = bpy.data.images.load(os.path.join(U.HERE, "tex", "moxie_skin.png"))
img.name = "moxie_skin"


def tex_mat(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    t = m.node_tree.nodes.new("ShaderNodeTexImage")
    t.image = img
    m.node_tree.links.new(t.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.9
    return m


me.materials.clear()
me.materials.append(tex_mat("skin"))
me.materials.append(tex_mat("eye"))

bm = bmesh.new()
bm.from_mesh(me)
for lay in list(bm.loops.layers.uv):
    bm.loops.layers.uv.remove(lay)
uv = bm.loops.layers.uv.new("UVMap")
ring = bm.verts.layers.int["eye_ring"]
dl = bm.verts.layers.deform.verify()
head_groups = {g.index for g in body.vertex_groups if g.name in ("head", "jaw") or g.name.startswith(("oris", "levator", "orbicularis", "oculi", "risorius", "special", "temporalis", "eye."))}
z_lo = L["z_chin"] - 0.004
for f in bm.faces:
    is_plate = all(v[ring] < 0 or v[ring] == 11 for v in f.verts) and any(v[ring] < 0 for v in f.verts)
    c = f.calc_center_median()
    hw = min(sum(w for g, w in v[dl].items() if g in head_groups) for v in f.verts)
    front = (f.normal.y < -0.12 and hw > 0.9 and c.z > z_lo and c.z < ZC + FACE_SPAN * 0.46 and abs(c.x) < FACE_SPAN * 0.47 and c.y < L["y_nose"] + 0.085)
    f.material_index = 1 if is_plate else 0
    for lp in f.loops:
        if is_plate or front:
            lp[uv].uv = (0.5 + lp.vert.co.x / FACE_SPAN, 0.5 + (lp.vert.co.z - ZC) / FACE_SPAN)
        else:
            lp[uv].uv = SWATCH
bm.to_mesh(me)
bm.free()
U.save_stage("s03_face")

# ---- review: toon render of the head
bpy.data.objects["MH_Rig"].hide_render = True
T.toonify([body], outline=0.0022)
zc = L["z_chin"] + L["H"] * 0.5


def setup():
    T.setup_eevee()


U.render_views(os.path.join(U.WIP, "s03_head.png"), views=("front", "q", "side", (20, 20)), center=(0, 0, zc),
               scale=L["H"] * 1.4, res=(800, 800), setup=setup)
