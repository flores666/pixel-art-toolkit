-- export.lua -- headless batch export: the whole asset library, organised.
--
--   lua5.4 art/tools/export.lua [options] [name-or-category ...]
--
--   lua5.4 art/tools/export.lua                       -- everything
--   lua5.4 art/tools/export.lua decal vegetation      -- two categories
--   lua5.4 art/tools/export.lua rusted_barrel:12      -- one generator, 12 variants
--   lua5.4 art/tools/export.lua --seed 200 --out /tmp/art
--   lua5.4 art/tools/export.lua --no-scenes           -- skip the location previews
--
-- Options:
--   --out DIR      output root (default art/generated)
--   --seed N       first seed (default 1). Everything is a pure function of it
--   --scale N      zoom for the enlarged review sheets (default 8)
--   --no-scenes    skip the three composed location previews (they are the
--                  slowest part of a run)
--   --no-sheets    skip the per-generator field/repeat sheets
--
-- Output layout, one directory per category so the tree is browsable by a
-- human as well as by an importer:
--
--   ground/ decals/ vegetation/ rocks/ walls/ fences/ road/ industrial/
--   props/ rubble/            <name>_<seed>.png, one file per asset
--   transitions/              one ATLAS per terrain pair (see below)
--   sheets/                   10x10 field and repeat sheets, comparison strips
--   scenes/                   the three composed QA maps, 1x and enlarged
--   manifest.json             every asset, with its metadata
--   tileset.json              palette, terrains, sockets, conventions
--   VALIDATION.md             the validator report
--
-- Transition pieces are exported as a per-pair ATLAS rather than as individual
-- files. 615 generators x 3 variants is 1,845 PNGs that nobody will ever open
-- one at a time, and an autotile wants its pieces contiguous: the atlas is 14
-- columns (corner masks 1..14) by N rows (variants), which is the shape a
-- Godot TileSet atlas source expects. manifest.json records every piece's
-- cell. Masks 0 and 15 are not in the set -- both mean "the cell is entirely
-- one terrain", which is that terrain's own field tile.

local here = debug.getinfo(1, "S").source:sub(2)
local dir = here:match("^(.*)[/\\][^/\\]*$") or "."
local toolkit = dofile(dir .. "/init.lua")

local png = require("png")
local manifest = require("manifest")
local scenes = require("scenes")
local terrain = require("terrain")
local P, style, generators, validators, previews =
  toolkit.pixels, toolkit.style, toolkit.generators, toolkit.validators, toolkit.previews

local SHEET = 10
local TRANSITION_VARIANTS = 3
-- Corner masks that actually exist as pieces: 1..14. See the note above.
local MASK_LO, MASK_HI = 1, style.terrain.masks - 2
local MASK_COLUMNS = MASK_HI - MASK_LO + 1

local options = { out = "art/generated", seed = 1, scale = 8, specs = {},
  scenes = true, sheets = true }
local args = arg or {}
local i = 1
while i <= #args do
  local a = args[i]
  if a == "--out" then options.out = args[i + 1]; i = i + 2
  elseif a == "--seed" then options.seed = math.tointeger(args[i + 1]) or 1; i = i + 2
  elseif a == "--scale" then options.scale = math.tointeger(args[i + 1]) or 8; i = i + 2
  elseif a == "--no-scenes" then options.scenes = false; i = i + 1
  elseif a == "--no-sheets" then options.sheets = false; i = i + 1
  elseif a:sub(1, 2) == "--" then error("unknown option " .. a)
  else
    local name, count = a:match("^([%w_]+):?(%d*)$")
    options.specs[#options.specs + 1] = { name = name, count = math.tointeger(count) }
    i = i + 1
  end
end

-- Resolve the selection: a generator name, or a category name meaning all of
-- its generators, or nothing meaning the whole library.
local selection = {}
local function select_generator(name, count)
  local gen = generators.get(name)
  selection[#selection + 1] = { name = name, gen = gen, count = count or gen.variants }
end
if #options.specs == 0 then
  for _, name in ipairs(generators.names) do select_generator(name) end
else
  for _, spec in ipairs(options.specs) do
    if generators[spec.name] then
      select_generator(spec.name, spec.count)
    elseif generators.by_category[spec.name] then
      for _, name in ipairs(generators.in_category(spec.name)) do
        select_generator(name, spec.count)
      end
    else
      error(("'%s' is neither a generator nor a category"):format(spec.name))
    end
  end
end

local function mkdir(path) os.execute(("mkdir -p '%s'"):format(path)) end

-- Build and validate ---------------------------------------------------------

local records, reports, failures = {}, {}, 0
local made_dirs = {}
local transition_rows = {}   -- pair id -> { [mask] = { surfaces by variant } }
local per_generator = {}

io.write("building ")
io.flush()
local progress = 0
for _, entry in ipairs(selection) do
  local gen = entry.gen
  local count = entry.count
  if gen.category == "transition" then count = math.min(count, TRANSITION_VARIANTS) end
  local row = { name = entry.name, gen = gen, assets = {} }

  for n = 0, count - 1 do
    local seed = options.seed + n
    local surface = generators.build(entry.name, seed)
    local report = validators.run(surface, generators.spec(entry.name))
    report.seed = seed
    reports[#reports + 1] = report
    if not report.ok then failures = failures + 1 end
    row.assets[#row.assets + 1] = { seed = seed, surface = surface, report = report }

    local rec = manifest.asset(gen, seed)
    if gen.category == "transition" then
      -- into the pair atlas instead of its own file
      local t = gen.terrain
      local key = t.pair .. (t.worn and "_worn" or "")
      transition_rows[key] = transition_rows[key] or { pair = t.pair, worn = t.worn, masks = {} }
      local cell = transition_rows[key].masks
      cell[t.mask] = cell[t.mask] or {}
      cell[t.mask][n + 1] = surface
      rec.path = ("transitions/%s.png"):format(key)
      rec.atlas_column = t.mask - MASK_LO   -- masks 1..14 -> columns 0..13
      rec.atlas_row = n
      rec.__order[#rec.__order + 1] = "atlas_column"
      rec.__order[#rec.__order + 1] = "atlas_row"
    else
      local path = ("%s/%s"):format(options.out, rec.path)
      local sub = path:match("^(.*)/[^/]*$")
      if not made_dirs[sub] then mkdir(sub); made_dirs[sub] = true end
      png.write(surface, path)
    end
    records[#records + 1] = rec
  end

  -- cross-variant checks
  local group = validators.run_group(entry.name, { seed = options.seed })
  if not group.ok then
    reports[#reports + 1] = group
    failures = failures + 1
  end

  per_generator[#per_generator + 1] = row
  progress = progress + 1
  if progress % 40 == 0 then io.write("."); io.flush() end
end
io.write(" done\n")

-- Transition atlases ---------------------------------------------------------

mkdir(options.out .. "/transitions")
local atlas_count = 0
for key, data in pairs(transition_rows) do
  local variants = 0
  for _, byvar in pairs(data.masks) do variants = math.max(variants, #byvar) end
  local atlas = P.new(MASK_COLUMNS * style.tile, variants * style.tile)
  for mask = MASK_LO, MASK_HI do
    local byvar = data.masks[mask] or {}
    for v = 1, variants do
      local surface = byvar[v] or byvar[1]
      if surface then
        atlas:blit(surface, (mask - MASK_LO) * style.tile, (v - 1) * style.tile)
      end
    end
  end
  png.write(atlas, ("%s/transitions/%s.png"):format(options.out, key))
  atlas_count = atlas_count + 1
end

-- Sheets ---------------------------------------------------------------------

local sheet_reports = {}
if options.sheets then
  mkdir(options.out .. "/sheets")
  for _, row in ipairs(per_generator) do
    -- A 10x10 sheet costs 100 builds. Worth it for the tiles a player stares
    -- at; not worth 615 times over for the transition set, whose review
    -- artefact is its atlas.
    if row.gen.category ~= "transition" then
      local field = previews.sheet(row.name, { seed = options.seed, cols = SHEET, rows = SHEET })
      local repeated = previews.tiling_check(row.name, options.seed, { cols = SHEET, rows = SHEET })
      png.write(field, ("%s/sheets/%s_field.png"):format(options.out, row.name))
      png.write(repeated, ("%s/sheets/%s_repeat.png"):format(options.out, row.name))
      for label, sheet in pairs { field = field, repeat_ = repeated } do
        local report = validators.run(sheet, {
          name = row.name .. " " .. label:gsub("_$", "") .. " sheet",
          kind = "sheet", wrap = false,
        })
        sheet_reports[#sheet_reports + 1] = report
        if not report.ok then failures = failures + 1 end
      end
    end
  end

  -- One comparison strip per category, at 1x and zoomed. The 1x version is the
  -- one that answers "does this silhouette read in the game".
  for _, category in ipairs { "ground", "decal", "vegetation", "rock", "wall",
                              "fence", "road", "industrial", "prop", "rubble" } do
    local names = generators.in_category(category)
    if #names > 0 then
      local pad = 1
      local widest, total_h = 0, 0
      local rows = {}
      for _, name in ipairs(names) do
        local gen = generators.get(name)
        local n = math.min(8, gen.variants)
        rows[#rows + 1] = { name = name, gen = gen, n = n }
        widest = math.max(widest, n * (gen.size.w + pad) - pad)
        total_h = total_h + gen.size.h + pad
      end
      local strip = P.new(widest, total_h - pad)
      local y = 0
      for _, r in ipairs(rows) do
        local x = 0
        for k = 0, r.n - 1 do
          strip:blit(generators.build(r.name, options.seed + k), x, y)
          x = x + r.gen.size.w + pad
        end
        y = y + r.gen.size.h + pad
      end
      png.write(strip, ("%s/sheets/comparison_%s.png"):format(options.out, category))
      png.write(strip, ("%s/sheets/comparison_%s_x%d.png"):format(options.out, category, options.scale),
        options.scale)
    end
  end
  png.write(previews.palette_strip(), options.out .. "/sheets/palette.png", 2)
end

-- Scenes ---------------------------------------------------------------------

local scene_reports = {}
if options.scenes then
  mkdir(options.out .. "/scenes")
  for _, name in ipairs(scenes.list) do
    local surface, report = scenes.build(name, options.seed)
    png.write(surface, ("%s/scenes/%s.png"):format(options.out, name))
    png.write(surface, ("%s/scenes/%s_x3.png"):format(options.out, name), 3)
    scene_reports[#scene_reports + 1] = report
    -- A scene is a review artefact, not an asset: its size and colour budget
    -- are meaningless, but every pixel in it still has to be on-palette and
    -- binary-alpha, which is what the sheet scope checks.
    local v = validators.run(surface, { name = name .. " scene", kind = "sheet", wrap = false })
    if not v.ok then
      sheet_reports[#sheet_reports + 1] = v
      failures = failures + 1
    end
  end
end

-- Manifests ------------------------------------------------------------------

local function write_json(path, value)
  local f = assert(io.open(path, "w"))
  f:write(manifest.encode(value), "\n")
  f:close()
end

write_json(options.out .. "/manifest.json", {
  __order = { "generated_by", "seed", "tile", "asset_count", "assets" },
  generated_by = "art/tools/export.lua",
  seed = options.seed,
  tile = style.tile,
  asset_count = #records,
  assets = records,
})

write_json(options.out .. "/tileset.json", {
  __order = { "conventions", "palette", "terrain", "sockets" },
  conventions = manifest.conventions(),
  palette = manifest.palette(),
  terrain = manifest.terrains(),
  sockets = manifest.sockets(),
})

-- Report ---------------------------------------------------------------------

local out = {}
local function line(fmt, ...) out[#out + 1] = select("#", ...) > 0 and fmt:format(...) or fmt end

line("# Validation report")
line("")
line("Generated by `lua5.4 art/tools/export.lua`%s.",
  #args > 0 and " " .. table.concat(args, " ") or "")
line("Seeds run from %d. Every asset is a pure function of (generator, seed), so", options.seed)
line("re-running this command reproduces these files byte for byte.")
line("")
line("## Totals")
line("")
line("| what | count |")
line("| --- | --- |")
line("| generators | %d |", #selection)
line("| assets written | %d |", #records)
line("| transition atlases | %d |", atlas_count)
line("| review sheets | %d |", #sheet_reports)
line("| location previews | %d |", #scene_reports)
line("")

line("## Per category")
line("")
line("| category | generators | assets | sizes | max colours | busyness (max / cap) | variant overlap |")
line("| --- | --- | --- | --- | --- | --- | --- |")
local by_cat = {}
for _, row in ipairs(per_generator) do
  local c = row.gen.category
  by_cat[c] = by_cat[c] or { gens = 0, assets = 0, colors = 0, density = 0, sizes = {},
    overlap = 0, pairs = 0 }
  local b = by_cat[c]
  b.gens = b.gens + 1
  b.assets = b.assets + #row.assets
  b.sizes[("%dx%d"):format(row.gen.size.w, row.gen.size.h)] = true
  for _, asset in ipairs(row.assets) do
    b.colors = math.max(b.colors, asset.report.colors)
    b.density = math.max(b.density, P.edge_density(asset.surface))
  end
  for a = 1, #row.assets do
    for bb = a + 1, #row.assets do
      local sa, sb = row.assets[a].surface, row.assets[bb].surface
      local same = 0
      for k = 1, sa.width * sa.height do if sa.data[k] == sb.data[k] then same = same + 1 end end
      b.overlap = b.overlap + same / (sa.width * sa.height)
      b.pairs = b.pairs + 1
    end
  end
end
local cat_order = { "ground", "transition", "decal", "vegetation", "rock",
                    "wall", "fence", "road", "industrial", "prop", "rubble", "structure" }
for _, c in ipairs(cat_order) do
  local b = by_cat[c]
  if b then
    local sizes = {}
    for s in pairs(b.sizes) do sizes[#sizes + 1] = s end
    table.sort(sizes)
    local surface_class
    for _, row in ipairs(per_generator) do
      if row.gen.category == c then surface_class = row.gen.surface break end
    end
    local cap = style.max_edge_density[surface_class]
    line("| `%s` | %d | %d | %s | %d | %.3f / %s | %.0f%% |",
      c, b.gens, b.assets, table.concat(sizes, " "), b.colors, b.density,
      cap and ("%.2f"):format(cap) or "n/a (sparse)",
      b.pairs > 0 and 100 * b.overlap / b.pairs or 0)
  end
end
line("")
line("Budgets: %d colours per 16x16 tile (+%d per extra tile). Isolated pixels are",
  style.max_colors_per_asset, style.extra_colors_per_tile)
line("capped at %d per tile AND at %.0f%% of the opaque pixels -- both apply, and the",
  style.max_isolated_pixels, style.max_isolated_ratio * 100)
line("tighter bound is the one that binds.")
line("")
line("`busyness` is measured / ceiling for the category's surface class")
line("(pixel_utils.edge_density, outline excluded). A class shown as `n/a` has no")
line("meaningful ceiling: on an asset that is mostly boundary the measure saturates,")
line("so those are held to their coverage and silhouette rules instead.")
line("For calibration, the game's own hand-authored platform field tiles measure")
line("0.10-0.17 (they hold 74-82%% of their area at a single colour) and its wall")
line("faces 0.25.")
line("")

line("## Grid visibility (ground tiles must not expose the 16x16 cell)")
line("")
line("| tile | mean luminance | seam bias x/y | seam contrast x/y | tile luma sd | field density | verdict |")
line("| --- | --- | --- | --- | --- | --- | --- |")
local palette_mod = require("palette")
for _, row in ipairs(per_generator) do
  if row.gen.surface == "ground" then
    local g = previews.grid_report(row.name, { seed = options.seed })
    local verdict = g.ok and "no visible grid" or ("**" .. g.why .. "**")
    if not g.ok then failures = failures + 1 end
    local total, count = 0, 0
    for _, asset in ipairs(row.assets) do
      for _, _, c in asset.surface:pixels() do
        total = total + palette_mod.luminance(c); count = count + 1
      end
    end
    line("| `%s` | %.0f | %.3f / %.3f | %.2f / %.2f | %.2f | %.3f | %s |",
      row.name, total / math.max(1, count), g.seam_bias_x, g.seam_bias_y,
      g.seam_contrast_x, g.seam_contrast_y, g.tile_luma_sd, g.field_density, verdict)
  end
end
line("")
line("Seam bias is the mean *signed* luminance step along tile boundaries over the")
line("mean step everywhere: a grid is visible when every boundary steps the same way.")
line("For calibration, the game's own metro floor tiles laid in a field score 4.2 and")
line("10.3; continuous never-tiled reference art scores 0.01. Limit is %.2f.",
  style.grid.max_seam_bias)
line("")
line("Mean luminance is listed because the terrains have to be told apart from each")
line("other in a composed map, not only judged one at a time: five of them once sat")
line("within five luminance and a whole scene read as one brown mass.")
line("")

-- Connectivity
local sockets_ok, socket_issues = validators.check_sockets({ seeds = 6 })
line("## Modular connectivity")
line("")
if sockets_ok then
  line("Every piece presenting a socket agrees with every other piece on that edge's")
  line("opaque rows and base material, over 6 seeds each. Wear ramps are transparent")
  line("to the check: grime or a weed at a join does not stop two pieces meeting.")
else
  failures = failures + #socket_issues
  line("**%d socket mismatches:**", #socket_issues)
  line("")
  line("```")
  for k = 1, math.min(20, #socket_issues) do line("%s", socket_issues[k].message) end
  line("```")
end
line("")

if #scene_reports > 0 then
  line("## Location previews")
  line("")
  line("Composed from library assets only. These are the only check that sees the")
  line("failures a single asset cannot have: repetition over a field, terrains that")
  line("do not separate from each other, scale disagreeing between kits, and prop")
  line("density.")
  line("")
  line("| scene | tiles | decals | objects | runs | unresolved cells | notes |")
  line("| --- | --- | --- | --- | --- | --- | --- |")
  for _, r in ipairs(scene_reports) do
    line("| `%s` | %d | %d | %d | %d | %d | %d |",
      r.name, r.tiles, r.decals, r.objects, r.runs or 0, r.holes or 0, #r.warnings)
  end
  line("")
end

line("## Rules checked")
line("")
line("Per asset:")
line("")
for _, rule in ipairs(validators.rules) do line("- `%s` -- %s", rule.id, rule.title) end
line("")
line("Across a generator's variants:")
line("")
for _, rule in ipairs(validators.group_rules) do line("- `%s` -- %s", rule.id, rule.title) end
line("")
line("Across the library: `sockets` -- pieces presenting the same socket agree on that")
line("edge's opaque rows and base material.")
line("")

local failed_reports = {}
for _, report in ipairs(reports) do if not report.ok then failed_reports[#failed_reports + 1] = report end end
for _, report in ipairs(sheet_reports) do if not report.ok then failed_reports[#failed_reports + 1] = report end end
if #failed_reports > 0 then
  line("## Failures")
  line("")
  line("```")
  for _, report in ipairs(failed_reports) do line("%s", validators.format(report)) end
  line("```")
  line("")
end

if failures == 0 then
  line("**%d assets, %d atlases, %d sheets and %d location previews checked; no rule violations.**",
    #records, atlas_count, #sheet_reports, #scene_reports)
else
  line("**%d violations across %d assets.**", failures, #records)
end

local f = assert(io.open(options.out .. "/VALIDATION.md", "w"))
f:write(table.concat(out, "\n"), "\n")
f:close()

io.write(("exported %d assets, %d transition atlases, %d sheets, %d scenes to %s (%d violations)\n")
  :format(#records, atlas_count, #sheet_reports, #scene_reports, options.out, failures))
os.exit(failures == 0 and 0 or 1)
