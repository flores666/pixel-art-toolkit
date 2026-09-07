# No Way Up — pixel art style (above ground)

Every rule a generator must follow. The rules are not advice: most are enforced
by `art/tools/validators` and `art/tools/previews`, and the rest are enforced by
the primitives themselves (you cannot draw an off-palette colour).

## The world

Above ground, twenty-odd years after everyone left. Post-Soviet industrial and
rural: cracked service roads, sheet-metal fences, panel-built ruins, spilled
drums, dry scrub taking the whole thing back. It is **harsh and neglected, not
scenic**. Nothing here is lush, nothing is vivid, and nothing looks maintained.

Two rules carry that atmosphere more than any other:

- **Vegetation is dry.** Dead straw is the field; olive green is the minority
  that came back this year. The brightest pixel in a grass tile is bleached
  straw catching the light, never foliage. There is no emerald in the palette
  and none may be added.
- **Man-made things are losing.** Rust, spalling, grime and weeds through
  cracks are the default state; a clean surface is the rare variant.

The underground metro art this project shipped earlier is **not** discarded:
concrete, steel, corrosion, wood and grime look the same on either side of the
stairs, and those ramps are shared verbatim. That is what keeps the two halves
of the game one game.

---

## 1. Grid

- The base cell is **exactly 16×16 px** (`style.tile`), never overridden.
- Larger assets occupy whole cells: 16×32, 32×16, up to 64×64
  (`style.max_tiles_x/y`). Anything not a multiple of 16 is rejected by the
  `dimensions` validator.
- Coordinates are **integers**, 0-based, `(0,0)` top-left, matching Aseprite
  image space. No sub-pixel anything: no float positions, no scaling inside a
  generator, no rotation.
- A tileable asset is authored on a **wrapping surface**
  (`pixel_utils.new(w, h, { wrap = true })`), so a cluster that leaves one edge
  arrives at the opposite one and the tile is seamless against itself. Props are
  authored non-wrapping and must leave the tile corners transparent.

## 2. Ground fields must not print the grid

Ground covers the whole screen, a hundred tiles at a time. If the tiling shows,
the world looks like a spreadsheet. This is the hardest rule in the document and
the only one with its own measurement, `previews.grid_report`:

| cue | what it means | limit |
| --- | --- | --- |
| `seam_bias` | mean **signed** luminance step along tile boundaries ÷ mean step everywhere. A grid is visible when every boundary steps the same way and draws a line. | ≤ 0.35 |
| `seam_contrast` | mean **absolute** step at boundaries ÷ mean step. Below 1 means detail is avoiding the edges — a calm ring around every cell, which is also a grid. Above 1 is expected and fine. | ≥ 0.40 |
| `tile_luma_sd` | spread of per-tile average luminance. Tiles of differing overall brightness lay out as a patchwork of light and dark squares. | ≤ 2.5 |
| `field_density` | busyness averaged over the whole field (§7). | ≤ 0.22 |

Calibrated, not invented: the game's **own** metro floor variants laid in a
field score `seam_bias` **4.2 / 10.3** — every tile has a baked-in dark edge, and
that grid is plain to see. Continuous, never-tiled reference art scores **0.01**.
The above-ground ground tiles score 0.02–0.18.

What that means when you write a ground generator:

- **Nothing keys to an edge or a corner.** No joint, no border, no vignette, no
  feature that "starts at the top".
- **The base colour is identical in every variant.** Vary what is *on* the
  ground, never the ground itself, or the field becomes a patchwork.
- **Marks are placed uniformly across the whole tile**, on a wrapping surface.
- **Most tiles carry nothing but the base field.** A crack, a stone or a
  pothole is a minority event — see §7. This is the rule the first draft broke:
  every tile had a feature, each one fine on its own, and a hundred of them
  together read as static.
- Vertical asymmetry of about 0.1 in `seam_bias` is expected and is not a bug:
  the fixed key light puts shadows on the lower side of every mark.

Structure tiles are exempt (`surface = "structure"`), and deliberately so: a
wall **should** show its cast joint and a fence **should** show its folds. Those
are construction lines, and hiding them would be a worse lie than the grid.

## 3. Colour

The palette is **fixed**: 48 colours in ten ramps, dark → light. Generators name
a ramp step; they never write a raw hex value.

**Man-made** — sampled from the game's own metro atlases, unchanged:

| ramp | steps |
| --- | --- |
| ink | `ink_1` #000000 · `ink_2` #0D0D0D · `ink_3` #181818 · `ink_4` #202020 |
| concrete | `concrete_1` #1C1A1A · `_2` #282524 · `_3` #494542 · `_4` #5C5552 · `_5` #706660 · `_6` #8A8079 |
| metal | `metal_1` #0F0F0F · `_2` #1B1B1A · `_3` #30312D · `_4` #41423E · `_5` #555653 · `_6` #696666 |
| rust | `rust_1` #5A431B · `_2` #795B25 · `_3` #A07629 · `_4` #B18736 · `_5` #CB9B3E |
| wood | `wood_1` #27241F · `_2` #342F27 · `_3` #463D33 · `_4` #726753 · `_5` #8A7B63 |
| dirt | `dirt_1` #1F1C1A · `_2` #2B2821 · `_3` #3D382F |

**Above ground** — quantised from the project's outdoor reference art, then
desaturated a step:

| ramp | steps | use |
| --- | --- | --- |
| earth | `earth_1` #2A2119 · `_2` #3E3226 · `_3` #55452F · `_4` #6E5A3E · `_5` #8A7350 | bare soil, ruts, spoil |
| grass | `grass_1` #232B16 · `_2` #33401D · `_3` #445524 · `_4` #5A6E31 · `_5` #74883E | what came back this year |
| straw | `straw_1` #423521 · `_2` #5C4B2A · `_3` #7D6839 · `_4` #9E874B | dead growth, the default field |
| asphalt | `asphalt_1` #1C1C1D · `_2` #2A2A2B · `_3` #3C3C3B · `_4` #4E4E4C · `_5` #646460 | roads and yards |

Rules that go with it:

- **No gradients.** A ramp step is a flat region; shading jumps a step.
- **Highlights and shadows are ramp moves**, never new colours: `palette.shift`
  and the `rect_fill_shift` / `dither_shift` / `broken_run` helpers. This is why
  rust on a fence matches rust on a barrel.
- **Colour budget: 16 per 16×16 tile**, +2 per further tile. The above-ground
  generators use 7–10. Over budget means detail the size cannot hold.
- `concrete_6` is the daylight step. Underground assets should not need it.
- **Green is rationed.** Olive tops out at `grass_5` (luminance 121). If a tile
  reads as a lawn, it is wrong.
- Ochre is the loudest thing in the palette. On dark metal, 5–20 % rust
  coverage is plenty; `rusted_barrel` goes further only because corrosion is
  the subject of that asset.
- **`ink_2` is reserved for outlines.** Dark *fills* use `ink_1`, `ink_3` or
  `ink_4`; the `outline_thickness` validator depends on that reservation.

## 4. Alpha and anti-aliasing

- **Alpha is binary: 0 or 255.** No feathering, no soft shadows, no ghosts. A
  soft-looking contact shadow is a broken run of `ink_3`, not translucency.
- **No anti-aliasing, anywhere.** Lines are Bresenham, polygons are
  scanline-filled with hard edges, and nothing blends two colours to smooth a
  step. If an edge looks harsh, fix it with a ramp step or a dither.

## 5. Lighting

The key light is **fixed: upper-left** (`style.light`), above ground and below.

- Top and left faces are **one step lighter**; bottom and right faces are **one
  step darker**; cast shadows fall **down and to the right**.
- A **recess** (a slab joint, a panel seam, a pothole, a spall, a dent) is dark,
  and its **lit lip is on the lower-right inner wall** — the wall the light
  reaches.
- A **raised** feature (a strap, a barrel hoop, a rail) is the opposite: lit lip
  on top, its own shadow underneath.
- A stone, a chunk of debris and a tuft all get a lit cap and a shadow. That
  pairing is what separates a stone from a stray pixel at this size.
- `pixel_utils.apply_lighting` does the silhouette case; structure the
  silhouette cannot imply is lit explicitly.

## 6. Clusters, not noise

- **Never place a lone pixel.** The smallest mark is two (`style.speck_min`).
- Clusters grow **radially** (`pixel_utils.cluster`): each step takes the
  candidate nearest the seed, with `opts.spread` of jitter. A depth-first walk
  makes ribbons, and a field of ribbons reads as camouflage — which is exactly
  what the first above-ground draft produced. Use `spread` 0 for a stone, ~0.4
  for mottling, 1.3+ for a drift or a stain.
- A pixel with no same-coloured neighbour in its **8-cell neighbourhood** is a
  stray. `isolated_pixels` caps strays at 6 per tile or 4 % of opaque pixels.
- Every generator ends with `pixel_utils.despeckle`, which absorbs strays. It
  may never resolve one **into the outline colour**: beside a silhouette the
  outline is the local majority, and letting it win eats the shape.
- Cracks, grain, scratches and stalks are **runs**, minimum 2–3 px, never dots.

## 7. Busyness

Every pixel can be legal and the tile still be noise. `pixel_utils.edge_density`
is the fraction of neighbouring pixel pairs that differ, and `texture_noise`
caps it per **surface class**, which each generator declares:

| `surface` | what it is | per-tile ceiling | measured here |
| --- | --- | --- | --- |
| `ground` | laid in fields; must be the calmest thing in the game | 0.30 | 0.07–0.30 |
| `structure` | carries construction detail: joints, folds, fixings | 0.55 | 0.20–0.50 |
| `prop` | adds a silhouette, an outline and internal structure | 0.60 | 0.43–0.56 |

For ground the number that really matters is the **field** average
(`style.grid.max_field_density` = 0.22), held at the level of the game's own
authored floor tiles (0.17–0.19). Individual tiles may carry a fracture; a
hundred of them may not.

Two habits keep a surface under the ceiling: **fewer, larger marks** (one big
cluster has far less edge per pixel than four small ones), and **letting most
variants be plain**.

## 8. Outlines

- **Props are outlined; tiles are not.** An outlined ground tile prints a grid
  the level designer cannot switch off.
- Outline colour is `style.outline_color` (`ink_2` #0D0D0D) — near black, so
  props do not punch holes in the scene.
- 4-neighbour, **exactly one pixel thick** (`outline_thickness` checks it), **no
  diagonal nubs**.
- Drawn **after** lighting and **before** wear, so rust can eat into the
  silhouette but not into the outline.
- The darkest body step must stay clearly lighter than the outline, or the
  shaded edge of the shape disappears into it.

## 9. Draw order

`style.draw_order`, and every generator follows it:

1. **silhouette** — block the shape in flat;
2. **material** — a material grammar fills it (§10);
3. **structure** — joints, folds, hoops, planks, cracks;
4. **lighting** — ramp-aware highlights and shadows;
5. **outline** — props only;
6. **wear** — rust, dirt, debris and vegetation overlays, masked to the ramps
   they belong on;
7. **cleanup** — `despeckle`;
8. **contact shadow** — props only, after cleanup so it survives it.

## 10. Materials

A material owns the vocabulary of marks a surface may make. Generators
**compose** materials; they do not invent texture inline.

| material | kind | grammar |
| --- | --- | --- |
| `earth` | base | soil field, `stones` (lit cap + shadow) |
| `grass` | base | dry field, `tufts` (leaning stalks, lit crown), `blade` |
| `asphalt` | base | aggregate field, `crack` (branching, returns its pixels), `pothole` |
| `concrete` | base | field, `groove` (cast joint), `crack`, `spall` |
| `metal` | base | plate, `seam`, `rivet`, `scratch`, `corrugate` |
| `wood` | base | grain, `planks`, `knot` |
| `rust` | overlay | rimmed patches, `streak` |
| `dirt` | overlay | grime patches, `band` |
| `debris` | overlay | chunks of whatever fell apart nearby |

- Overlays take a `mask`; use `pixel_utils.ramp_mask("metal")` so rust lands on
  metal and not on an outline, a hole or a weed.
- Overlays take a `bias(x, y) -> 0..1` saying **where wear collects**: seams,
  corners, the foot of anything vertical, the low side of anything. Evenly
  scattered wear is the tell-tale of generated art.
- Overlay coverage is **fractional and may round to nothing**. A low coverage
  must mean "most tiles have none"; give a generator's wear a `0.00` weight so
  clean variants genuinely occur.
- **Vegetation reads by direction, not by blobs.** Tufts are leaning strokes
  with a lit crown. Round green patches read as confetti.

## 11. Seeds and determinism

- An asset is a **pure function of (generator name, seed)** — forever, because
  levels reference tiles by seed.
- All randomness comes from `rng`. **Never** `math.random`, `os.time` or
  `os.clock`.
- The stream is salted with the generator name, so two generators given seed 1
  do not share a sequence.
- Use `rng_stream:branch("rust")` per feature, so adding a draw to one feature
  does not shift every other feature — otherwise every existing asset in the
  game changes the day you add a crack.
- Variation belongs in **wear, damage, vegetation and placement**. Silhouette
  and structure stay constant, or a row of the same prop stops reading as the
  same prop.

## 12. Review

- Nothing ships on the strength of one 16×16 tile at 8×. Look at:
  - the **10×10 field** (`previews.sheet`) — is the variation right, is anything
    shouting, does it turn into static?
  - the **repeat sheet** (`vary` off) — is the tile actually seamless?
  - the whole set **at 1×** — can you still tell a road from a field, and read
    a prop's silhouette?
- Run the validators over at least 64 seeds: `lua5.4 art/tools/tests/run_tests.lua`,
  or *Validate → Validate all generators* in Aseprite. `lua5.4 art/tools/export.lua`
  writes every asset, both sheets, the grid report and `VALIDATION.md`.
- The seven rules are `dimensions`, `alpha`, `palette`, `palette_size`,
  `outline_thickness`, `texture_noise` and `isolated_pixels`. The four marked
  `scope = "asset"` are skipped for preview sheets, which are review artefacts.

---

## Adding a generator

1. Create `art/tools/generators/<name>.lua` returning the contract at the top of
   `generators/init.lua` — including `surface`, which sets its busyness ceiling
   and, for `ground`, commits it to §2.
2. Add `"<name>"` to `generators.names`.
3. Compose materials in the §9 draw order; take every random decision from the
   rng stream you were handed.
4. `lua5.4 art/tools/export.lua <name>:8` and **look at the sheets**.

```lua
local P = require("pixel_utils")
local materials = require("materials")

local gen = {
  name = "gravel_track",
  title = "Gravel track 16x16",
  size = { w = 16, h = 16 },
  tileable = true,
  surface = "ground",
}

function gen.build(rng_stream, opts)
  opts = opts or {}
  local s = P.new(gen.size.w, gen.size.h, { wrap = gen.tileable })

  materials.earth.fill(s, rng_stream, { wear = 0.7 })              -- material
  materials.earth.stones(s, rng_stream:weighted {                  -- structure,
    { value = 1, weight = 3 }, { value = 2, weight = 2 },           -- sparse
  }, rng_stream:branch("stones"), {})
  if rng_stream:chance(0.3) then                                   -- wear
    materials.grass.tufts(s, 1, rng_stream:branch("weeds"), { color = "straw_2" })
  end
  P.despeckle(s)                                                   -- cleanup
  return s
end

return gen
```
