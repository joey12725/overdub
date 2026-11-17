# shaders/ — the shared OVERDUB look

Owned by the world engineer; used by world/, actors/ and fx/. Build materials through
`ToonKit` (`shaders/toon_kit.gd`) rather than by hand: it wires the ramp, the theme shadow tint and
the outline pass for you.

| File | What | Pass |
|---|---|---|
| `toon.gdshader` | lit cel material (stepped bands, rim, tinted shadow floor, optional hatching) | opaque |
| `toon_cutout.gdshader` | same, two-sided with alpha scissor (foliage cards, vines) | opaque (alpha-tested) |
| `outline.gdshader` | inverted-hull ink, constant pixel width | `next_pass` of a toon material |
| `xray.gdshader` | flat see-through silhouette drawn only where the mesh is occluded | extra `next_pass` after the outline |
| `glow.gdshader` | opaque unlit HDR emissive (neon, lamps, accents) | opaque |
| `glow_add.gdshader` | additive unlit glow, no depth write (halos, beams, light pools) | transparent |
| `world_surface.gdshader` | toon lighting + world-space procedural patterns (masonry, plates, grates, runes, hazard paint, rock strata) for the environment | opaque |
| `post.gdshader` | canvas_item screen grade over the 3D view (theme grade, saturation, vignette, chromatic, flash) | 2D, under the UI |
| `toon_lighting.gdshaderinc` | the `light()` function and lighting uniforms shared by the three lit shaders | include |
| `toon_body.gdshaderinc` | albedo / emission / instance-uniform half of the toon shaders | include |

Glow comes from the world view's `WorldEnvironment` (HDR threshold about 1.0): anything emitting
above roughly 1.2 blooms. Scene conventions (units, axes) are in `game/contracts/render_ctx.gd`.

## ToonKit (class_name, static)

```gdscript
ToonKit.toon(color, outline_px := 2.0, outline_color := ToonKit.theme_ink) -> ShaderMaterial
ToonKit.toon_cutout(color, texture := null, cut := 0.4) -> ShaderMaterial
ToonKit.toon_emissive(color, emission, energy, outline_px := 2.0) -> ShaderMaterial
ToonKit.surface(top_pattern, side_pattern, top_color, side_color, line_color, outline_px, outline_color) -> ShaderMaterial
ToonKit.outline(color := theme_ink, thickness_px := 2.0) -> ShaderMaterial
ToonKit.xray(color := Color(0.95, 0.95, 1, 0.55), margin := 0.35) -> ShaderMaterial
ToonKit.glow(color, energy := 2.2) -> ShaderMaterial
ToonKit.glow_add(color, energy := 1.0, opacity := 1.0, radial := 0.0) -> ShaderMaterial
ToonKit.with_outline(mat, color, thickness_px) -> ShaderMaterial   # add / replace the ink pass
ToonKit.with_xray(mat, color) -> Material                          # append the x-ray pass
ToonKit.apply_toon(root: Node, opts := ToonKit.Options.new()) -> Dictionary[String, ShaderMaterial]
ToonKit.bake_smooth_normals(mesh) -> Mesh                          # CUSTOM0 = smoothed normal
ToonKit.ramp() -> Texture2D                                        # the shared 4-band ramp
ToonKit.material_name(m) / base_color_of(m) / is_toon(m)
static var ToonKit.theme_shadow_tint, ToonKit.theme_ink           # set by the world view per theme
```

`apply_toon()` is the asset-contract re-materialing pass for an instanced `.glb`: every surface gets
a toon material with its imported base colour (and albedo texture) preserved, materials whose name
ends in `_glow` become `glow.gdshader` (energy `Options.glow_energy`, no outline), every other
surface gets the ink outline. Static meshes get smoothed normals baked into CUSTOM0 so the hull has
no gaps at hard edges; skinned meshes keep `NORMAL`. Surfaces sharing a material name share one
material, and the returned dictionary (material name -> material) lets you tint or pulse them
afterwards. `Options`: `outline_color`, `outline_px` (<= 0: no outline), `glow_energy`,
`color_by_name` (material name -> override colour), `glow_suffix`, `xray`, `xray_color`,
`bake_smooth_normals`, `cast_shadows`, `layers`.

`RenderCtx.toon_material` is a toon material already configured for the level's theme (ramp,
shadow tint, outline in the palette's ink); `duplicate()` it for your own colours, or call
`ToonKit.toon()` after the world view loaded the level (it updates `theme_shadow_tint` /
`theme_ink` first). `RenderCtx.toon_ramp` is `ToonKit.ramp()`.

## Uniforms

### Lighting (toon, toon_cutout, world_surface — `toon_lighting.gdshaderinc`)

| Uniform | Default | Meaning |
|---|---|---|
| `toon_ramp` (sampler2D) | white | ramp sampled by lit amount 0..1 when `use_toon_ramp` |
| `use_toon_ramp` (bool) | false | false: four built-in bands (0, .55, .86, 1 at thresholds .06/.38/.82) |
| `shadow_tint` (color) | (.30,.27,.34) | colour a directional light leaves in its own shadow (alpha scales it) |
| `shadow_floor` | 0.55 | strength of that tinted floor (0 = shadow is ambient only) |
| `light_wrap` | 0 | Lambert wrap before banding |
| `rim_strength` | 0.22 | stepped rim on the lit side |
| `rim_width` | 0.3 | fraction of the silhouette band the rim covers |
| `hatch_strength` | 0 | world-space diagonal hatching inside the deepest band (0 = off) |
| `hatch_density` | 7 | hatch lines per world unit |

Directional lights get the banded key plus the tinted floor; omni / spot lights (practicals) get
banded N·L × attenuation with no floor. Environment ambient light is added by Godot on top.

### toon / toon_cutout (`toon_body.gdshaderinc`)

| Uniform | Default | Meaning |
|---|---|---|
| `albedo` (color) | white | base colour (sRGB) |
| `albedo_texture`, `use_albedo_texture` | white, false | multiplied into albedo (alpha used by the cutout variant) |
| `uv_scale`, `uv_offset` | (1,1), (0,0) | texture transform |
| `vertex_color_mix` | 1 | how much `COLOR` tints albedo. MultiMesh instance colours arrive through `COLOR`, so keep 1 for tinted instances |
| `emission` (color), `emission_energy` | black, 0 | emissive colour × energy (HDR) |
| `emission_texture`, `use_emission_texture` | white, false | multiplies the emission |
| `unlit_mix` | 0 | 0 = pure cel, 1 = flat unlit albedo |
| `alpha_cut` (cutout only) | 0.4 | alpha scissor threshold |
| **instance** `instance_tint` (color) | white | per-node multiply on albedo (alpha = cutout alpha) |
| **instance** `instance_emission` (color) | (0,0,0,0) | per-node added emission: rgb × a |

Instance uniforms are set per node: `mesh_instance.set_instance_shader_parameter(&"instance_tint", c)`.
They let many nodes share one material (and they reach the `next_pass` materials too).

**Instance uniform indices.** Godot numbers each shader's instance uniforms from 0 unless the
declaration carries `instance_index(n)`, and every material in one node's pass chain shares a
single set of slots. Without explicit indices the toon pass's `instance_tint` read the outline's
`instance_outline` default (0, so the surface went black) and `instance_emission` read
`instance_outline_scale` (1.0, so it glowed red). Every instance uniform in this folder now has a
fixed index, and any shader you chain with ours must not reuse these slots:

| Index | Uniform | Shaders |
|---|---|---|
| 0 | `instance_tint` | toon, toon_cutout, world_surface |
| 1 | `instance_emission` | toon, toon_cutout, world_surface |
| 2 | `instance_outline` | outline |
| 3 | `instance_outline_scale` | outline |
| 4 | `instance_xray` | xray |
| 5 | `instance_energy` | glow, glow_add |
| 6 | `instance_color` | glow, glow_add |
| 7 | `instance_opacity` | blob_shadow |

(The actors/ shader family assigns its own 0–15 and does not chain with these, so the two
families must not be mixed on one node.)

### outline

| Uniform | Default | Meaning |
|---|---|---|
| `outline_color` | ink | line colour |
| `thickness_px` | 2 | width in viewport pixels, constant through zoom |
| `use_smooth_normal` | true | extrude along CUSTOM0 (from `bake_smooth_normals`) where present, else `NORMAL` |
| `depth_push` | 0 | push the hull away from the camera (world units) |
| **instance** `instance_outline` (color) | (0,0,0,0) | replaces `outline_color` when a > 0 (a self's cassette colour) |
| **instance** `instance_outline_scale` | 1 | width multiplier per node (0 hides it) |

### xray

| Uniform | Default | Meaning |
|---|---|---|
| `xray_color` | (.95,.95,1,.55) | silhouette colour and opacity |
| `occlusion_margin` | 0.35 | world units an occluder must be nearer than the fragment (stops self-occlusion) |
| `rim_boost` | 0.6 | extra opacity at silhouette edges |
| `stripe_strength` | 0.35 | screen-space diagonal stripes (reads as "behind") |
| **instance** `instance_xray` (color) | (0,0,0,0) | replaces `xray_color` when a > 0 |

Godot 4.4 has no depth-test-greater, so the pass disables the depth test and compares its view
depth with the opaque depth texture. It is transparent and runs after opaque geometry
(`render_priority` 10).

### glow / glow_add

| Uniform | glow | glow_add | Meaning |
|---|---|---|---|
| `color` | white | white | colour (sRGB) |
| `energy` | 2 | 1 | HDR multiplier |
| `opacity` | — | 1 | additive weight |
| `tex`, `use_texture`, `uv_scale`, `uv_offset` | | | optional texture (`glow_add` uses its alpha too) |
| `uv_scroll` | (0,0) | (0,0) | texture scroll per second (TIME) |
| `radial` | — | 0 | round falloff from the UV centre (light pools) |
| `fresnel_fade` | — | 0 | fade toward silhouettes (halo shells) |
| **instance** `instance_energy` | 1 | 1 | per-node energy multiplier (pulses, flicker) |
| **instance** `instance_color` | (0,0,0,0) | (0,0,0,0) | replaces `color` when a > 0 |

### world_surface (environment)

Lighting uniforms as above, plus: `top_pattern`, `side_pattern` (0 plain, 1 masonry slabs / brick
courses, 2 riveted plates, 3 grate, 4 rune-inscribed plate, 5 hazard stripes, 6 overgrown slabs,
7 rock strata, 8 inscribed wall panels, 9 neon-seam plate), `top_color`, `side_color`, `line_color`
(grout / seams / holes), `accent_color` (moss, rust, stripe paint), `glow_color`, `glow_energy`
(inscriptions), `glow_share` (fraction of lit wall plates), `wear`, `blotch`, `cliff_deep`,
`cliff_depth` (strata fade), `seed`, `vertex_color_mix`; instance `instance_tint`,
`instance_emission`. Patterns are in world space, so neighbouring tiles line up.

### post (canvas_item)

`grade_gain` (multiply), `grade_lift` (shadow lift), `contrast`, `saturation`, `vignette`,
`vignette_color`, `chromatic`, `flash`, `flash_color`. The world view owns it (`WorldPost`) and
feeds it from `RenderCtx.post` each frame; layers drive `RenderCtx.post`, not this shader.
