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
  style.lua           every hard rule as data (grid, light, budgets, dither)
  palette.lua         the fixed 48-colour palette, as ten lighting ramps
  rng.lua             seeded variation: xorshift32 streams, named branches
  pixel_utils.lua     Surface + all primitives (line, polygon, cluster,
                      fracture, dither, broken runs, outline, lighting,
                      despeckle)
  aseprite.lua        the only module that knows Aseprite exists
  materials/          earth, grass, asphalt, debris (above ground)
                      concrete, metal, wood, rust, dirt (shared with the metro)
                      each owns its own marks: soil crust, dry tufts, road
                      fractures and break-out, decayed cast joints, fence posts,
                      exposed reinforcement
  generators/         ground:    dirt_ground, dry_grass, cracked_asphalt
                      structure: concrete_ruin_wall, rusted_fence
                      props:     supply_crate, rusted_barrel
  validators/         the seven ship/no-ship rules
  previews/           10x10 tile sheets, tiling checks, grid-visibility report,
                      palette strip
  png.lua             pure-Lua PNG writer (headless export needs no Aseprite)
  export.lua          batch export + VALIDATION.md
  commands/           Aseprite menu entries
  tests/              headless test run (no Aseprite needed)
  package.json        Aseprite extension manifest
```

## Install into Aseprite

Zip the contents of `art/tools` (with `package.json` at the top level of the
zip), rename it to `no-way-up-pixel-toolkit.aseprite-extension`, and install it
with **Edit → Preferences → Extensions → Add Extension**:

```sh
cd art/tools && zip -r ../../no-way-up-pixel-toolkit.aseprite-extension . -x '*.ppm' && cd -
```

The commands then appear under **File → Scripts → No Way Up**:

| command | what it does |
| --- | --- |
| Generate asset… | builds a generator into a new sprite (or a strip of seed variants) and validates it first |
| Preview sheet… | opens a 10×10 field; turn off *Vary seeds* to check tiling |
| Validate… | runs the rules on the active sprite, or over every generator × 64 seeds |
| Load palette | puts the fixed palette on the active sprite for hand-drawing |

During development you can skip packaging and copy `art/tools` into the Aseprite
scripts folder (`~/.config/aseprite/scripts`) instead; the commands are then
under **File → Scripts** without a submenu.

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
