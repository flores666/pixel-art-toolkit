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
The above-ground ground tiles score 0.02–0.32.

### How a ground tile is allowed to vary

The same atlases calibrate the *other* half of the problem, which is what the
inside of a ground tile may do. The game's platform field tiles hold **74–82 %
of their area at a single colour**, carry the rest as hairline marks, and
measure **0.10–0.17** edge density. That is what a surface a hundred tiles wide
has to look like, and it rules out the obvious approach:

- **The intact surface gets one broad patch, near in both value and hue.** A
  patch a full ramp step from the base reads as a discrete *mark* however large
  it is drawn — earth's steps are ~19 luminance apart, asphalt's ~18 — and a
  hundred marks laid out on a 16 px pitch is pepper. Enlarging them turns
  pepper into leopard spots; it does not fix it. So `dirt_ground` varies with
  `straw_2` (+5 luminance on `earth_3`, warm on warm) and `cracked_asphalt`
  with `metal_4` (+6 on `asphalt_3`, neutral on neutral).
- **Near in value is not enough — it must be near in hue too.** `grass_3` is 2
  luminance from `straw_2` and `dirt_3` is 3 from `asphalt_3`. Both are
  invisible in *value* and both were tried; the olive turned the grass field
  into camouflage and the brown turned the road visibly brown-mottled. Equal
  luminance at a distant hue is what camouflage *is*.
- **All value contrast is reserved for structure and damage.** A fracture, a
  broken-out chunk, a stone's lit cap, a tuft's lit tip. That is what leaves
  damage room to read as damage instead of competing with the field it sits in.
- **Large-scale forms cannot cross a tile boundary.** Every tile wraps against
  *itself*, so a tile's left edge is its own right edge and has nothing to do
  with the neighbour's. Broad continuous shapes across a field are therefore
  impossible by construction: the only things that survive repetition are
  texture too quiet to count and marks that read as objects.

### Detail lives in decals, not in ground tiles

This is the rule the whole library is built around, and it is the one that
finally made the fields work.

A stone drawn into a 16×16 field tile is not a stone: it is a stone **printed
once per cell**, a hundred times a screen, on a 16 px pitch. Every tile passes
every rule and the field reads as static — and no measurement here can see it,
because `edge_density` counts pixel pairs that differ and cannot tell one
deliberate mark from a hundred copies of it.

So:

- a **field tile** is the terrain fill plus, on a minority of variants, one
  *hairline* mark from a shared vocabulary (`terrain.marks`: a soil crust, a
  bleached stem, a hairline fracture, a vehicle rut). That is exactly how the
  game's own authored floor tiles are built;
- everything larger — stones, tufts, cracks, potholes, stains, litter, rubble
  — is a **decal**: a transparent 16×16 overlay, placed where the level wants
  one. `generators/decals.lua`, 16 families.

The density of detail in a location is then a level-design decision instead of
a constant baked into the tileset.

A decal is held to `style.decal`: mostly transparent (≤ 40 % coverage, ≥ 1.8 %),
**one mark in one place** (≤ 4 groups by `pixel_utils.mark_groups`), and
**self-lit** — there is no body under a decal to infer light from, so every
mark carries its own lit cap and its own cast shadow or it reads as a hole in
the ground.

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

### Terrains must be told apart from each other, not only judged alone

A tile can satisfy every rule above and still be useless, because the check
that matters for a *terrain* is comparative. Five of the nine terrains once sat
within **five luminance** of each other at a similar hue — each one calm,
correct and calibrated — and a composed map read as one undifferentiated brown
mass. The palette's warm mid-tones are crowded (`earth_3` 71, `grass_3` 74,
`straw_2` 76), so this is easy to walk into.

The ladder the terrains hold now, as mean tile luminance:

| terrain | base | mean |
| --- | --- | --- |
| mud | `earth_2` | 56 |
| asphalt / broken asphalt | `asphalt_3` | 59–61 |
| dirt, gravel | `earth_3` | 72 |
| sparse grass | `straw_2` | 74 |
| concrete | `concrete_4` | 86 |
| dirt + grass | `earth_4` | 95 |
| dry grass | `straw_3` | 103 |

Two rules fall out of it:

- **Separation comes from the base, never from the patch.** Lifting a
  terrain's *patch* to a distant value to raise its average puts a value event
  in every tile, and a field of those is leopard spots on a 16 px pitch — the
  §2 failure by another route. Move the base and keep the patch near it.
- **Grass is separated from soil by direction, not only by value.** A grass
  field carries fine directional texture: short broken runs, one pixel wide,
  *all leaning the same way*, drawn in the near-value neighbour. Soil has no
  direction, and that is the difference. (This is what was lost when tufts
  became decals, and it had to be put back.)

### Boundaries: the autotile system

Two terrains meet through a **16-configuration corner Wang set** — the four
corners of a cell each carry a terrain, which is Godot's
`TERRAIN_MODE_MATCH_CORNERS`. Coverage is a thresholded bilinear blend of the
four corner weights, so the boundary crosses any edge whose corners differ at
its exact midpoint and two tiles laid side by side agree. Straight edges,
outer corners, inner corners and diagonals all fall out of one formula
(`terrain.coverage`) instead of sixteen hand-drawn cases.

A ragged boundary tiles for one reason only, and it is the same invariant that
makes a decayed cast joint tileable:

> **A boundary is pinned to its ideal position at the tile edge, and may
> wander only in the middle.**

Let the noise reach the border and every join in the transition band shows a
step — a visible grid drawn exactly where the eye is already looking. The
property is verified exactly, for all masks at every amplitude.

**The pair table is derived, not listed.** Each terrain declares a `family`
(soft / hard) and a `kin` (the material it is a condition *of*), and the
boundary's meaning follows: same kin is a **gradation** and carries no
decoration at all; soft over hard means the made surface **fails** at the
edge; hard against hard is a **cast joint** with almost no wander; soft
against soft is ragged with vegetation leaning off the grassy side. Seven
pairs were once written out by hand and the first three composed scenes asked
for thirty — anything missing is a hole a level designer falls into.

**Edge decoration is a minority event**, exactly as a mark on a field tile is.
Tufts on every transition tile turn a boundary twenty cells long into a hedge
of forty identical tufts.

Masks 0 and 15 are not in the set: both mean the cell is entirely one terrain,
which is that terrain's own field tile.

Structure tiles are exempt (`surface = "structure"`), and deliberately so: a
wall **should** show its cast joint and a fence **should** show its folds. Those
are construction lines, and hiding them would be a worse lie than the grid.

The exemption is not a licence to print a rule, though. A construction line
drawn identically on every tile is what made the first ruin wall read as
wallpaper, so a line on a ruin **decays** — it wanders off its row and loses a
chunk here and there — under one invariant:

> **A construction line is pinned to its offset at both ends of its run.**

A wall tile has to meet its neighbour's joint, so the line may do as it likes in
the middle and nowhere else (`concrete.groove`, `opts.decay`). Break that and a
wall run reads as a row of broken staples. The same reasoning is why a fence's
rail is at a fixed row in every tile but its lit edge is a broken run, and why
the corrugation pitch divides 16 exactly.

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
- **A ramp is for shading; it is not a fence around a material.** Highlights and
  shadows never leave the ramp (below), but a *material* may name a step from
  another ramp when that is the honest colour — bleached straw trodden into
  soil, a different asphalt mix in an old repair. Ground fields depend on it,
  because the near-value neighbours §2 requires are all in other ramps.
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
- A **stray** is a pixel that belongs to no *mark*. The obvious definition —
  "no same-coloured neighbour in its 8-cell neighbourhood" — is wrong, and it
  condemned the grammar §5 requires: a stone is *a lit cap plus its own
  shadow*, three pixels of three colours, so the anti-dust rule called the
  documented anti-dust mark three pieces of dust, and `despeckle` then
  destroyed it. Instead: the asset's commonest opaque colour is its
  **background** (only if it covers ≥ ⅓ of the cell — a decal has no field);
  every other opaque pixel is a **mark** pixel; mark pixels group
  8-connected; and a group of **one** is a stray. Nothing else is.
- `isolated_pixels` caps strays at 6 per tile **and** at 4 % of opaque pixels:
  both bounds apply, and the validator binds on whichever is tighter. (Taking
  the looser of the two lets each bound excuse a breach of the other.)
- Every generator ends with cleanup, and there are four passes because wear
  leaves four kinds of mess:
  - `despeckle` absorbs a stray into the majority around it. It may never
    resolve one **into the outline colour**: beside a silhouette the outline is
    the local majority, and letting it win eats the shape;
  - `strip_strays` **erases** a stray that has no opaque neighbour at all. On a
    mostly-transparent asset there is nothing to vote with, so despeckle
    leaves it and the asset ships with dust on it;
  - `strip_orphan_outline` removes outline pixels left stranded by wear that
    *removed* body (§9 draws the outline before wear on purpose);
  - `fill_pinholes` fills single enclosed transparent cells — they appear
    wherever strokes close a ring, and wherever the contact shadow lands a
    pixel clear of the silhouette, so this one runs **last**.
- Cracks, grain, scratches and stalks are **runs**, minimum 2–3 px, never dots.
- A crack is a **fracture**, not a scribble: `pixel_utils.fracture` holds its
  heading for a segment of 3–5 px, kinks 45° at a joint, and throws branches at
  a wide angle from along the trunk rather than off its tip. A walk that
  re-picks its direction every other step draws a stray diagonal scratch, which
  is what soil, asphalt and concrete cracks all used to look like. The geometry
  is shared; the colour, the extent and what crumbles beside it belong to the
  material.

## 7. Busyness

Every pixel can be legal and the tile still be noise. `pixel_utils.edge_density`
is the fraction of neighbouring pixel pairs that differ, and `texture_noise`
caps it per **surface class**, which each generator declares:

| `surface` | what it is | per-tile ceiling | measured here |
| --- | --- | --- | --- |
| `ground` | laid in fields; must be the calmest thing in the game | 0.30 | 0.09–0.24 |
| `transition` | holds **two** ground surfaces plus their boundary | 0.38 | 0.10–0.36 |
| `structure` | carries construction detail: joints, folds, fixings | 0.55 | 0.20–0.52 |
| `prop` | adds a silhouette, an outline and internal structure | 0.65 | 0.24–0.63 |
| `decal` | a sparse self-lit overlay | *none* — see below | |

Two corrections to how this is measured, both of which changed what it means:

- **The outline is excluded.** An outline is mandatory on a prop and differs
  from every body colour, so counting body-against-outline pairs scored an
  asset on its perimeter-to-area ratio rather than on its texture: a weed drawn
  as four clean strokes measured 0.68 and a drum covered in corrosion 0.59,
  which is exactly backwards.
- **It only applies to an asset with a solid interior**
  (`pixel_utils.interior_ratio` ≥ 0.20). On an asset that is mostly boundary —
  a weed, a cable, a small low pile, every decal — nearly every adjacent pair
  straddles a lit face and the measure saturates however carefully the thing is
  drawn. That is why `decal` has no ceiling: the exemption is a consequence of
  the same rule, not a special case. Those assets are held to their coverage
  and silhouette rules instead.

For ground the number that really matters is the **field** average
(`style.grid.max_field_density` = 0.22), held at the level of the game's own
authored platform field tiles (0.10–0.17); the nine terrains measure 0.09–0.21.
Individual tiles may carry a fracture; a hundred of them may not.

Two habits keep a surface under the ceiling: **fewer, larger marks** (one big
cluster has far less edge per pixel than four small ones), and **letting most
variants be plain**.

Both measurements are blind to contrast — they count pixel pairs that *differ*,
not by how much — so they cannot tell a calm near-value patch from a loud one.
Use them as ceilings, never as a target, and settle the question of whether a
surface is calm by looking at the field. Leave headroom, too: the ceilings are
checked per seed, and levels reference tiles by seed forever, so a generator
that only just fits over 64 seeds will breach it on seed 385.

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
| `earth` | base | soil field, `crust` (the shrinkage cracks of dried dirt), `stones` (lit cap + shadow) |
| `grass` | base | dry field, `tufts` (leaning stalks, lit tip), `blade` |
| `asphalt` | base | worn field, `crack` (a fracture, returns its pixels), `breakup` (crumbled surface), `pothole` |
| `concrete` | base | field, `groove` (cast joint, `decay`), `crack`, `spall` |
| `metal` | base | plate, `seam`, `rivet`, `scratch`, `corrugate`, `post` (an upright member) |
| `wood` | base | grain, `planks`, `knot` |
| `rust` | overlay | rimmed patches, `streak`, `bar` (exposed reinforcement) |
| `dirt` | overlay | grime patches, `band` |
| `debris` | overlay | chunks of whatever fell apart nearby |

Three shared modules sit above the materials, and a generator composes them
rather than reinventing what they own:

| module | owns |
| --- | --- |
| `terrain.lua` | the 9 terrains, `terrain.field` (every ground tile), the corner-Wang autotile and the derived pair table |
| `wear.lua` | the variation channels: `rust`, `dirt`, `staining`, `cracks`, `damage`, `missing`, `rubble`, `vegetation`. Coverage is a weighted list whose first entry is 0, so clean variants genuinely occur — and **nothing here moves an edge**, which is what keeps a variant the same object |
| `object.lua` | the standing-object grammar: outline → wear → cleanup → contact shadow, and members (`upright`, `rail`, `box`, `cylinder`) drawn as explicit ramp steps |

- Overlays take a `mask`; use `pixel_utils.ramp_mask("metal")` so rust lands on
  metal and not on an outline, a hole or a weed.
- Overlays take a `bias(x, y) -> 0..1` saying **where wear collects**: seams,
  corners, the foot of anything vertical, the low side of anything. Evenly
  scattered wear is the tell-tale of generated art.
- Overlay coverage is **fractional and may round to nothing**. A low coverage
  must mean "most tiles have none"; give a generator's wear a `0.00` weight so
  clean variants genuinely occur.
- **Vegetation reads by direction, not by blobs.** Round green patches read as
  confetti — and so, at this size, does a tuft drawn as a *colour*. A tuft
  reads because it has **light on it**: a body a step darker than the field it
  stands in, a tip a step or two lighter. Olive at the field's own value is a
  pure hue change, i.e. camouflage (§2). Stalks are spaced two apart, not packed
  side by side, or a shared lean overlaps them into a solid rectangle; and they
  all lean **the same way**, because that is what direction means. One clump per
  tile, sometimes a second right beside it — never a scatter of separate marks.
- **A structural member is drawn as explicit ramp steps, not as a shift.** A
  fence post or a rail is a separate piece of steel, and shifting whatever
  happens to be underneath lets the sheet's fold pattern show straight through
  it (`metal.post`).
- **A modular piece declares its edges, and the claim is checked.** A wall or
  fence piece names what each of its four edges presents (`sockets`), and
  `validators.check_sockets` verifies that every piece presenting a socket
  agrees with every other on that edge's **opaque rows** and **base material**.
  Wear is transparent to the check — grime or a weed at a join does not stop
  two pieces meeting — and exact colour is not compared, because a joint
  decays. Three consequences, all of which were bugs first:
  - **sockets are direction-typed.** A left/right edge is a slice through a
    run's *cross-section*; a top/bottom edge is a slice *along* it. One name
    for both is a promise no piece can keep.
  - **an edge where the run continues is not outlined and casts no contact
    shadow.** Otherwise a run gets a black rule across its middle and the
    middle of a wall is planted on the ground.
  - **nothing may put material on a join that its neighbour does not have** —
    including wear, which paints onto transparency and will otherwise drop a
    weed into a neighbour's empty sky.
- **Thin vegetation is not outlined.** An outline is one pixel and a stalk is
  one pixel, so outlining a tuft spends more pixels on the border than on the
  plant and the strokes weld into a dark blob. Light, not a border, is what
  separates a plant from the ground. (A considered exception to §8, for assets
  with no interior for an outline to sit around.)
- **A material's marks have to relate to each other.** A fracture and the
  crumbled surface beside it are one piece of damage, so the breakup is seeded
  *on* the crack and the silt is biased *to* it. Marks placed independently
  measure the same and read as mess: what makes a tile say "damaged asphalt"
  rather than "grey noisy ground" is one event, related, with the rest of the
  surface left whole.

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
  same prop. `wear.lua` owns the channels and none of them moves an edge.
- **Both ends of that are enforced** (`style.variant_overlap`, checked by
  `variant_similarity`). Variants that share too many pixels are the same
  asset twice and a level built from them repeats visibly; variants that share
  too *few* are not the same object any more. Byte-identical variants are
  always a bug — it means the seed did nothing, which happens when an asset's
  structure is fixed and every wear channel can roll to nothing.

## 12. Review

- Nothing ships on the strength of one 16×16 tile at 8×. Look at:
  - the **10×10 field** (`previews.sheet`) — is the variation right, is anything
    shouting, does it turn into static?
  - the **repeat sheet** (`vary` off) — is the tile actually seamless?
  - the whole set **at 1×** — can you still tell a road from a field, and read
    a prop's silhouette?
- the **composed location previews** (`art/generated/scenes/`) — the only check
  that sees the failures a single asset cannot have: repetition over a field,
  **terrains that do not separate from each other**, scale disagreeing between
  kits, palette drift, and prop density. Two of the worst defects this toolkit
  has had were invisible until a whole scene was laid out.
- Run the validators: `lua5.4 art/tools/tests/run_tests.lua` sweeps every
  generator over twice the seeds it ships (`--full` for 64 each), and
  `lua5.4 art/tools/export.lua` writes every asset, the sheets, the atlases,
  the scenes, the grid report and `VALIDATION.md`.

The rules, in three scopes:

| scope | rules |
| --- | --- |
| per asset | `dimensions`, `alpha`, `palette`, `palette_size`, `outline_thickness`, `texture_noise`, `isolated_pixels`, `decal_coverage`, `decal_marks`, `prop_silhouette` |
| per variant group | `variant_similarity` (too alike *and* too unalike), `tileable_border` |
| across the library | `sockets` — every piece presenting a socket agrees with every other on that edge's opaque rows and base material |

The rules marked `scope = "asset"` are skipped for preview sheets and scenes,
which are review artefacts; the pixel-level rules still apply to them.

A note on scope, because getting it wrong produced unsound tests twice.
"Do these variants repeat?" is a statement about a **set**. "Does this
generator avoid the tile border?" is a **statistic** of a generator — measured
on the three variants a transition tile ships it failed `dirt_ground`, which is
correct art. And "do these two pieces connect?" is inherently about a **pair**,
so it cannot live on either one.

---

## Adding a generator

1. Create `art/tools/generators/<name>.lua` returning the contract at the top of
   `generators/init.lua` — including `surface`, which sets its busyness ceiling
   and, for `ground`, commits it to §2, and `category`, which fixes its output
   directory and its layer/collision defaults. Return a **list** of generators
   instead of one if it is a kit whose pieces share an implementation; that is
   what keeps 615 transition tiles from being 615 files.
2. Add the module name to `generators.modules`.
3. Compose materials and the shared modules in the §9 draw order; take every
   random decision from the rng stream you were handed. A ground tile is
   `terrain.field`; an object ends with `object.finish`; wear is declared as
   channels and applied by `wear.lua`.
4. `lua5.4 art/tools/export.lua <name>:8` and **look at the sheets**.

To add a **terrain**, register it in `terrain.lua` with a `family` and a `kin`
— its transition pairs against every compatible terrain are generated for you.
To add a **modular piece**, declare its `sockets` and `check_sockets` will hold
you to them.

`surface` and `category` are different axes, and conflating them causes real
trouble. Surface says what *kind* of thing an asset is for validation;
category says what it *is* for the level. Thin vegetation is `vegetation` by
category and `decal` by surface — held to the prop rules it fails
`min_occupancy` for being small and `max_interior_holes` for the gaps between
its own stems, which are the asset. A collapsed wall piece is `wall` by
category and `prop` by surface, because a mound silhouette drawn per column
steps at every column by construction.

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
