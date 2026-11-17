"""Finishing passes on the joined mesh: fold the many flat-colour materials into a few palette
textures (fewer draw calls in the game, same look), keeping the contract's styling hooks."""
import os

import bpy
import numpy as np

import mc_util as U

GROUPS = {
    "gear": ["lash", "teeth", "mouth_in", "hair_tie", "metal", "metal_dark", "strap_dark", "belt", "pouch",
             "pouch_dark", "walkman", "walkman_dark", "strap_pink", "glove", "device", "hp_yellow", "hp_dark",
             "hp_cushion", "choker", "cable", "lace", "top_trim", "top_graphic"],
    "jacket": ["jacket_dark", "jacket_lining", "jacket_rib", "jacket_patch"],
    "shoes": ["shoes_main", "shoes_dark", "shoes_sole", "shoes_accent"],
}
GRID = 8
CELL = 16


def _palette_image(name, colours, tex_dir):
    size = GRID * CELL
    px = np.zeros((size, size, 4), dtype=np.float32)
    px[..., 3] = 1.0
    for i, hexc in enumerate(colours):
        r, c = divmod(i, GRID)
        px[r * CELL:(r + 1) * CELL, c * CELL:(c + 1) * CELL, :3] = U.hexcol(hexc)
    img = bpy.data.images.new("moxie_" + name, size, size, alpha=False)
    img.pixels.foreach_set(px.reshape(-1))
    path = os.path.join(tex_dir, "moxie_%s.png" % name)
    img.filepath_raw = path
    img.file_format = 'PNG'
    img.save()
    return img


def _palette_material(name, img, rough):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    b = mat.node_tree.nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = 0.0
    if "Specular IOR Level" in b.inputs:
        b.inputs["Specular IOR Level"].default_value = 0.2
    tn = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tn.image = img
    tn.interpolation = 'Closest'
    mat.node_tree.links.new(tn.outputs["Color"], b.inputs["Base Color"])
    mat.use_backface_culling = False
    return mat


def consolidate(body, tex_dir):
    me = body.data
    uvl = me.uv_layers.active or me.uv_layers.new(name="UVMap")
    slot_of = {m.name: i for i, m in enumerate(me.materials) if m}
    npoly = len(me.polygons)
    mat_idx = np.empty(npoly, dtype=np.int32)
    me.polygons.foreach_get("material_index", mat_idx)
    loop_start = np.empty(npoly, dtype=np.int32)
    loop_total = np.empty(npoly, dtype=np.int32)
    me.polygons.foreach_get("loop_start", loop_start)
    me.polygons.foreach_get("loop_total", loop_total)
    uv = np.empty(len(me.loops) * 2, dtype=np.float64)
    uvl.data.foreach_get("uv", uv)
    uv = uv.reshape(-1, 2)
    poly_of_loop = np.repeat(np.arange(npoly), loop_total)
    for gname, members in GROUPS.items():
        present = [m for m in members if m in slot_of]
        if not present:
            continue
        img = _palette_image(gname, [U.PALETTE[m][0] for m in present], tex_dir)
        mat = _palette_material(gname, img, 0.7)
        me.materials.append(mat)
        new_slot = len(me.materials) - 1
        for i, m in enumerate(present):
            r, c = divmod(i, GRID)
            centre = ((c + 0.5) / GRID, (r + 0.5) / GRID)
            sel = mat_idx == slot_of[m]
            uv[sel[poly_of_loop]] = centre
            mat_idx[sel] = new_slot
    uvl.data.foreach_set("uv", uv.reshape(-1))
    me.polygons.foreach_set("material_index", mat_idx)
    me.update()
    U.activate(body)
    bpy.ops.object.material_slot_remove_unused()
    print("materials:", [m.name for m in me.materials])
