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

## Run it without Aseprite

The whole toolkit is plain Lua 5.4 apart from `aseprite.lua`, so the tests and
previews run in a terminal:

```sh
lua5.4 art/tools/tests/run_tests.lua              # 29 tests: palette, rng,
                                                  # primitives, materials,
                                                  # generators, validators
lua5.4 art/tools/tests/run_tests.lua --dump /tmp/art   # + PPM preview sheets
```

`--dump` writes, per generator, a varied 10×10 sheet, a single-seed tiling
check and a 12× single tile. Look at them; the validators cannot tell you
whether the art is any good.

To produce game-ready files, use the exporter (pure Lua, writes real PNGs — no
Aseprite and no Python needed):

```sh
lua5.4 art/tools/export.lua                                # every generator, 8 variants each
lua5.4 art/tools/export.lua dirt_ground:8 rusted_barrel:6  # pick and choose
lua5.4 art/tools/export.lua --seed 200 --out /tmp/art      # a different batch, elsewhere
```

It writes to `art/generated/` (override with `--out`):

| path | what |
| --- | --- |
| `tiles/<name>_<seed>.png` | one file per asset, 1×, RGBA, game-ready |
| `sheets/<name>_field.png` | 10×10, one seed per tile — the variation range |
| `sheets/<name>_repeat.png` | 10×10, one seed repeated — the tiling check |
| `sheets/comparison.png`, `comparison_x8.png` | every asset in the run, one row per generator |
| `VALIDATION.md` | the validator report, plus the grid-visibility measurements |

The exporter exits non-zero if anything fails validation, so it drops straight
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
