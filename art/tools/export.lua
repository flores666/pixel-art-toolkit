-- export.lua -- headless batch export.
--
--   lua5.4 art/tools/export.lua [--out DIR] [--seed N] [--scale N] [name[:count] ...]
--
--   lua5.4 art/tools/export.lua                                  -- every generator, 8 variants
--   lua5.4 art/tools/export.lua dirt_ground:8 rusted_barrel:6   -- pick and choose
--   lua5.4 art/tools/export.lua --seed 200 --out /tmp/art        -- a different batch
--
-- Writes, under DIR (default art/generated):
--   tiles/<name>_<seed>.png        one file per asset, 1x, game-ready RGBA
--   sheets/<name>_field.png        10x10, one seed per tile: the variation range
--   sheets/<name>_repeat.png       10x10, one seed repeated: the tiling check
--   sheets/comparison.png(+_x8)    every asset generated in this run, one row each
--   VALIDATION.md                  the validator report for everything above
--
-- Everything is a pure function of the seed, so re-running with the same
-- arguments overwrites the same files with the same bytes.

local here = debug.getinfo(1, "S").source:sub(2)
local dir = here:match("^(.*)[/\\][^/\\]*$") or "."
local toolkit = dofile(dir .. "/init.lua")

local png = require("png")
local P, generators, validators, previews =
  toolkit.pixels, toolkit.generators, toolkit.validators, toolkit.previews

local DEFAULT_VARIANTS = 8
local SHEET = 10

local options = { out = "art/generated", seed = 1, scale = 8, specs = {} }
local args = arg or {}
local i = 1
while i <= #args do
  local a = args[i]
  if a == "--out" then options.out = args[i + 1]; i = i + 2
  elseif a == "--seed" then options.seed = math.tointeger(args[i + 1]) or 1; i = i + 2
  elseif a == "--scale" then options.scale = math.tointeger(args[i + 1]) or 8; i = i + 2
  elseif a:sub(1, 2) == "--" then error("unknown option " .. a)
  else
    local name, count = a:match("^([%w_]+):?(%d*)$")
    options.specs[#options.specs + 1] = { name = name, count = math.tointeger(count) or DEFAULT_VARIANTS }
    i = i + 1
  end
end
if #options.specs == 0 then
  for _, name in ipairs(generators.names) do
    options.specs[#options.specs + 1] = { name = name, count = DEFAULT_VARIANTS }
  end
end

local function mkdir(path) os.execute(("mkdir -p '%s'"):format(path)) end
mkdir(options.out .. "/tiles")
mkdir(options.out .. "/sheets")

-- Build ----------------------------------------------------------------------

local batch, reports, failures = {}, {}, 0
for _, spec in ipairs(options.specs) do
  local gen = generators.get(spec.name)
  local row = { name = spec.name, title = gen.title, gen = gen, assets = {} }
  for n = 0, spec.count - 1 do
    local seed = options.seed + n
    local surface = generators.build(spec.name, seed)
    local report = validators.run(surface, generators.spec(spec.name))
    report.seed = seed
    reports[#reports + 1] = report
    if not report.ok then failures = failures + 1 end
    row.assets[#row.assets + 1] = { seed = seed, surface = surface, report = report }
    png.write(surface, ("%s/tiles/%s_%d.png"):format(options.out, spec.name, seed))
  end
  batch[#batch + 1] = row
end

-- Sheets ---------------------------------------------------------------------

local sheet_reports = {}
for _, row in ipairs(batch) do
  local field = previews.sheet(row.name, { seed = options.seed, cols = SHEET, rows = SHEET })
  local repeated = previews.tiling_check(row.name, options.seed, { cols = SHEET, rows = SHEET })
  png.write(field, ("%s/sheets/%s_field.png"):format(options.out, row.name))
  png.write(repeated, ("%s/sheets/%s_repeat.png"):format(options.out, row.name))
  for label, sheet in pairs { field = field, repeat_ = repeated } do
    local report = validators.run(sheet, {
      name = row.name .. " " .. label:gsub("_$", "") .. " sheet",
      kind = "sheet",
      -- a field sheet is 100 independent tiles, so isolation is judged per
      -- tile the same way it is on the asset itself
      wrap = false,
    })
    sheet_reports[#sheet_reports + 1] = report
    if not report.ok then failures = failures + 1 end
  end
end

-- Comparison sheet: one row per generator, at 1x and zoomed. The 1x version is
-- the one that answers "does this silhouette read in the game".
local pad = 1
local widest, total_h = 0, 0
for _, row in ipairs(batch) do
  widest = math.max(widest, #row.assets * (row.gen.size.w + pad) - pad)
  total_h = total_h + row.gen.size.h + pad
end
local comparison = P.new(widest, total_h - pad)
local y = 0
for _, row in ipairs(batch) do
  local x = 0
  for _, asset in ipairs(row.assets) do
    comparison:blit(asset.surface, x, y)
    x = x + row.gen.size.w + pad
  end
  y = y + row.gen.size.h + pad
end
png.write(comparison, options.out .. "/sheets/comparison.png")
png.write(comparison, ("%s/sheets/comparison_x%d.png"):format(options.out, options.scale), options.scale)

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
line("## Summary")
line("")
line("| generator | surface | assets | seeds | size | max colours | max strays | busyness | variant overlap | result |")
line("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
for _, row in ipairs(batch) do
  local max_colors, max_strays, max_density, ok = 0, 0, 0, true
  for _, asset in ipairs(row.assets) do
    max_colors = math.max(max_colors, asset.report.colors)
    max_strays = math.max(max_strays, #P.isolated(asset.surface, { wrap = row.gen.tileable }))
    max_density = math.max(max_density, P.edge_density(asset.surface))
    ok = ok and asset.report.ok
  end
  -- Variant overlap: mean fraction of pixels two variants share at the same
  -- position. High overlap is the number behind "these all look the same".
  local pairs_seen, overlap = 0, 0
  for a = 1, #row.assets do
    for b = a + 1, #row.assets do
      local sa, sb = row.assets[a].surface, row.assets[b].surface
      local same = 0
      for i = 1, sa.width * sa.height do
        if sa.data[i] == sb.data[i] then same = same + 1 end
      end
      overlap = overlap + same / (sa.width * sa.height)
      pairs_seen = pairs_seen + 1
    end
  end
  local cap = toolkit.style.max_edge_density[row.gen.surface]
  line("| `%s` | %s | %d | %d-%d | %dx%d | %d | %d | %.3f / %.2f | %.0f%% | %s |",
    row.name, row.gen.surface, #row.assets,
    row.assets[1].seed, row.assets[#row.assets].seed,
    row.gen.size.w, row.gen.size.h, max_colors, max_strays, max_density, cap,
    pairs_seen > 0 and 100 * overlap / pairs_seen or 0, ok and "pass" or "FAIL")
end
line("")
line("Budgets: %d colours per 16x16 tile (+%d per extra tile). Isolated pixels are",
  toolkit.style.max_colors_per_asset, toolkit.style.extra_colors_per_tile)
line("capped at %d per tile AND at %.0f%% of the opaque pixels -- both apply, and the",
  toolkit.style.max_isolated_pixels, toolkit.style.max_isolated_ratio * 100)
line("tighter bound is the one that binds.")
line("")
line("`busyness` is measured / ceiling for that surface class (pixel_utils.edge_density);")
line("the game's own hand-authored platform field tiles measure 0.10-0.17 (they hold")
line("74-82%% of their area at a single colour) and its wall faces 0.25.")
line("`variant overlap` is how much two variants share pixel-for-pixel: props keep")
line("a fixed silhouette by design, so theirs is high and tiles' is low.")
line("")
line("## Grid visibility (ground tiles must not expose the 16x16 cell)")
line("")
line("| tile | surface | seam bias x/y | seam contrast x/y | tile luma sd | verdict |")
line("| --- | --- | --- | --- | --- | --- |")
for _, row in ipairs(batch) do
  if row.gen.tileable then
    local g = previews.grid_report(row.name, { seed = options.seed })
    local verdict
    if not g.enforced then
      verdict = "n/a (construction lines are intended)"
    elseif g.ok then
      verdict = "no visible grid"
    else
      verdict = "**GRID VISIBLE**"
      failures = failures + 1
    end
    line("| `%s` | %s | %.3f / %.3f | %.2f / %.2f | %.2f | %s |", row.name, g.surface,
      g.seam_bias_x, g.seam_bias_y, g.seam_contrast_x, g.seam_contrast_y, g.tile_luma_sd, verdict)
  end
end
line("")
line("Seam bias is the mean *signed* luminance step along tile boundaries over the")
line("mean step everywhere: a grid is visible when every boundary steps the same way.")
line("For calibration, the game's own metro floor tiles laid in a field score 4.2 and")
line("10.3; continuous never-tiled reference art scores 0.01. Limit is %.2f.",
  toolkit.style.grid.max_seam_bias)
line("")
line("## Rules checked")
line("")
for _, rule in ipairs(validators.rules) do
  line("- `%s` -- %s", rule.id, rule.title)
end
line("")
line("## Per-asset results")
line("")
line("```")
for _, report in ipairs(reports) do line("%s", validators.format(report)) end
line("")
for _, report in ipairs(sheet_reports) do line("%s", validators.format(report)) end
line("```")
line("")
if failures == 0 then
  line("**%d assets and %d sheets checked; no rule violations.**", #reports, #sheet_reports)
else
  line("**%d violations across %d assets and %d sheets.**", failures, #reports, #sheet_reports)
end

local f = assert(io.open(options.out .. "/VALIDATION.md", "w"))
f:write(table.concat(out, "\n"), "\n")
f:close()

io.write(("exported %d assets + %d sheets to %s (%d violations)\n")
  :format(#reports, #batch * 2 + 2, options.out, failures))
os.exit(failures == 0 and 0 or 1)
