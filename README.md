# No Way Up — pixel art toolkit

Deterministic pixel-art generators for the game in `../no-way-up`, written in
Lua and run inside Aseprite. The toolkit **draws real pixels**: there is no
image model anywhere in it, and every colour, every edge and every dither is
placed by code that obeys the rules in [ART_STYLE.md](ART_STYLE.md).

The current art direction is the **above-ground world**: an abandoned
post-Soviet landscape of dry scrub, cracked service roads, sheet-metal fences,
panel ruins and spilled drums. It shares its concrete, steel, corrosion, wood
and grime ramps with the game's existing metro art.

```
art/tools/
  init.lua            bootstrap: sets package.path, returns every module
  style.lua           every hard rule as data (grid, light, budgets, dither,
                      terrain pinning, decal/prop/variant bounds, categories)
  palette.lua         the fixed 48-colour palette, as ten lighting ramps
  rng.lua             seeded variation: xorshift32 streams, named branches
  pixel_utils.lua     Surface + all primitives (line, polygon, cluster,
                      fracture, dither, broken runs, outline, lighting,
                      despeckle, components, holes, marks, analysis)
  terrain.lua         the 9 terrains, the corner-Wang autotile, the derived
                      pair table, and terrain.field (every ground tile)
  wear.lua            the shared variation channels (rust, dirt, staining,
                      cracks, damage, missing pieces, rubble, vegetation)
  object.lua          the shared standing-object grammar (outline, cleanup,
                      contact shadow, upright/rail/box/cylinder members)
  scenes.lua          composes whole locations from library assets: terrain
                      map -> autotile resolution -> runs -> objects -> decals
  manifest.lua        the JSON metadata an importer needs
  aseprite.lua        the only module that knows Aseprite exists
  materials/          earth, grass, asphalt, debris (above ground)
                      concrete, metal, wood, rust, dirt (shared with the metro)
                      each owns its own marks: soil crust, dry tufts, road
                      fractures and break-up, decayed cast joints, fence posts,
                      exposed reinforcement
  generators/         ground:      dirt, dry/sparse grass, dirt+grass, asphalt,
                                   broken asphalt, concrete, mud, gravel
                      transitions: 35 terrain pairs x 14 corner masks, plus
                                   worn edge families (one implementation)
                      decals:      16 overlay families
                      vegetation:  bushes, scrub, weeds, trees, stumps, logs
                      rocks:       by scale, and clusters
                      walls:       12-piece modular kit, socket-verified
                      fences:      10-piece modular kit, socket-verified
                      road_kit:    barriers, signs, poles, lamps, cabinets,
                                   pipes, drainage, scrap
                      rubble:      10 destruction piles
                      props:       crates, lockers, furniture, bins,
                                   barricades, machines
  validators/         the ship/no-ship rules: 10 per asset, 2 per variant
                      group, 1 across the library (sockets)
  previews/           10x10 tile sheets, tiling checks, grid-visibility
                      report, palette strip
  png.lua             pure-Lua PNG writer (headless export needs no Aseprite)
```

## What is in the library

684 generators. Everything is a pure function of (generator, seed), so a level
may reference a tile by seed forever.

| category | generators | what |
| --- | --- | --- |
| `ground` | 9 | the terrain field tiles |
| `transition` | 615 | 35 pairs x 14 corner masks, + worn edges on 6 pairs |
| `decal` | 16 | placeable overlays: stones, cracks, stains, litter, weeds |
| `vegetation` | 10 | bushes, scrub, tufts, trees, stumps, logs |
| `rock` | 4 | small, medium, large 32x32, cluster 32x16 |
| `wall` | 12 | the modular ruined-wall kit |
| `fence` | 10 | the modular fence/barrier kit |
| `road` + `industrial` | 21 | roadside and infrastructure furniture |
| `rubble` | 10 | destruction piles by scale and material |
| `prop` | 17 | containers, furniture, bins, barricades, machines |

Two ideas carry the whole thing:

**Detail lives in decals, not in ground tiles.** A stone drawn into a 16x16
field tile is a stone printed once per cell, a hundred times a screen, on a
16 px pitch -- every tile legal and the field static. So the field tiles are
nearly flat (one hairline mark on a minority of variants, which is how the
game's own authored floor tiles are built) and everything larger is placed
where the level wants it.

**Modular pieces declare their edges, and the claim is checked.** A wall or
fence piece names what each edge presents (`sockets`), and
`validators.check_sockets` verifies that every piece presenting a socket
agrees with every other on that edge's opaque rows and base material. That
check found nine real bugs that are invisible in a single tile.

## Commands

Everything runs in plain Lua 5.4 apart from `aseprite.lua`, so the tests,
previews and the whole export run in a terminal.

### Generate all assets

```sh
lua5.4 art/tools/export.lua
```

Writes to `art/generated/` — 2702 assets, 41 transition atlases, 220 review
sheets and the 3 location previews. Exits non-zero if anything fails
validation, so it drops straight into CI.

### Generate one category, or one generator

```sh
lua5.4 art/tools/export.lua decal                  # a whole category
lua5.4 art/tools/export.lua vegetation rubble       # several
lua5.4 art/tools/export.lua rusted_barrel:12        # one generator, 12 variants
lua5.4 art/tools/export.lua --no-scenes --no-sheets # assets only (fastest)
```

Category names are `ground`, `transition`, `decal`, `vegetation`, `rock`,
`wall`, `fence`, `road`, `industrial`, `prop`, `rubble`.

### Change seeds

```sh
lua5.4 art/tools/export.lua --seed 200              # a different batch
lua5.4 art/tools/export.lua --seed 200 --out /tmp/art
```

An asset is a pure function of (generator name, seed) — forever, because
levels reference tiles by seed. Re-running with the same arguments reproduces
the same bytes.

### Run validation

```sh
lua5.4 art/tools/tests/run_tests.lua                # 25 tests, ~35s
lua5.4 art/tools/tests/run_tests.lua --full         # 64 seeds per generator
lua5.4 art/tools/tests/run_tests.lua --seeds 40     # a specific sweep depth
```

The suite sweeps every generator over twice the seeds it ships (floored at 8,
capped at 24), runs every per-asset rule, the two variant-group rules and the
library-wide socket check. `export.lua` validates every variant it actually
writes and puts the report in `art/generated/VALIDATION.md`.

### Generate previews

```sh
lua5.4 art/tools/export.lua                         # sheets + scenes included
lua5.4 art/tools/tests/run_tests.lua --dump /tmp/art   # PPM sheets, no PNG writer
```

`art/generated/sheets/` gets a 10×10 field sheet and a repeat (tiling) sheet
per generator, a per-category comparison strip at 1× and 8×, and the palette.
`art/generated/scenes/` gets the three composed locations at 1× and 3×.

**Look at the scenes.** They are the only check that sees the failures a
single asset cannot have: repetition over a field, terrains that do not
separate from each other, scale disagreeing between kits, and prop density.

### Godot-ready output

`art/generated/manifest.json` — every asset, with `id`, `generator`, `seed`,
`category`, `surface`, `path`, dimensions, tile footprint, `tileable`,
`layer`, `collision`, `variant_group`, and for autotile pieces the terrain
pair, corner mask, per-edge terrain and atlas cell.

`art/generated/tileset.json` — the palette as hex ramps, the 9 terrains, the
35 pairs with their atlas paths, the corner-mask convention
(`match_corners`, matching Godot's `TERRAIN_MODE_MATCH_CORNERS`), the socket
table, and the layer/collision vocabularies.

Transition pieces ship as one atlas per pair, 14 columns (corner masks 1–14)
by 3 rows (variants) — the shape a `TileSetAtlasSource` expects. Nothing in
this repo writes into the game project; the importer is the game's business.

### Adding a new generator later

1. Create `art/tools/generators/<name>.lua` returning the contract at the top
   of `generators/init.lua` — `name`, `title`, `size`, `tileable`, `surface`,
   `build`, plus `category` where it differs from the surface class. Return a
   **list** of generators instead of one if it is a kit whose pieces share an
   implementation.
2. Add the module name to `generators.modules`.
3. Compose materials in the ART_STYLE.md §9 draw order and take every random
   decision from the rng stream you were handed. For a ground tile call
   `terrain.field`; for an object end with `object.finish`; for wear declare
   channels and let `wear.lua` apply them.
4. `lua5.4 art/tools/export.lua <name>:8` and **look at the sheets**.

To add a terrain, register it in `terrain.lua` with a `family` and a `kin` —
its transition pairs against every compatible terrain are then generated for
you. To add a modular piece, declare its `sockets`; `check_sockets` will hold
you to them.

## Run it inside Aseprite

into CI.

## Using it from Lua

```lua
local toolkit = dofile("art/tools/init.lua")

local tile   = toolkit.generators.build("dry_grass", 7)   -- a Surface
local report = toolkit.validators.run(tile, toolkit.generators.spec("dry_grass"))
print(toolkit.validators.format(report))

local sheet = toolkit.previews.sheet("rusted_barrel", { seed = 1 })
local grid  = toolkit.previews.grid_report("dry_grass")   -- does the field show its tiling?
```

## Palette provenance

The palette is not invented, and it has two halves. The man-made ramps (ink,
concrete, metal, rust, wood, dirt) were sampled from the game's own atlases
(`assets/tiles/metro/*.png`): the platform concrete `#5C5552`, the near-black
wall greys, the ochre rail corrosion, the brown prop woods. The above-ground
ramps (earth, grass, straw, asphalt) were quantised from the project's outdoor
reference art and then desaturated a step, because the world is neglected, not
scenic. Sharing the man-made half is what makes a surface asset sit beside a
metro asset instead of next to it.

## Extending

Read [ART_STYLE.md](ART_STYLE.md) first — it is the contract, and the
validators enforce most of it. Then follow the generator skeleton at the end of
that document, and the contracts at the top of `generators/init.lua`,
`materials/init.lua` and `validators/init.lua`.
