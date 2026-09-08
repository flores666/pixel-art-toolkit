-- validators/init.lua -- the rules that decide whether an asset may ship.
--
-- Validators are the enforceable half of ART_STYLE.md. A generator is only
-- finished when `validators.run` returns ok for every seed it will be used
-- with, and the Aseprite command runs the same rules against hand-drawn art.
--
-- Contract -- a rule is:
--   { id = "palette", title = "...", scope = "asset"|"any",
--     check = function(surface, spec) -> issue|nil }
-- An issue is { rule, message, count, samples = { {x, y}, ... } }.
--
-- `scope = "asset"` means the rule only makes sense for something that ships
-- as an asset (its size, its colour budget). A preview sheet is a review
-- artefact -- a hundred tiles side by side -- so those rules are skipped for
-- it while the pixel-level rules still apply.
--
-- `spec` is what the surface claims to be:
--   { name, width, height, wrap, kind = "asset"|"sheet" }
-- `generators.spec(name)` builds one for you.
--
-- To add a rule: append to `validators.rules`. Everything else picks it up.

local style = require("style")
local palette = require("palette")
local P = require("pixel_utils")

local validators = {}

local MAX_SAMPLES = 8

local function issue(rule, message, samples, count)
  return { rule = rule, message = message, samples = samples or {}, count = count or #(samples or {}) }
end

validators.rules = {
  {
    id = "dimensions",
    title = "Dimensions are whole 16x16 tiles",
    scope = "asset",
    check = function(surface, spec)
      local ok, err = style.check_size(surface.width, surface.height)
      if not ok then return issue("dimensions", err) end
      if spec and spec.width and (surface.width ~= spec.width or surface.height ~= spec.height) then
        return issue("dimensions", ("expected %dx%d, got %dx%d")
          :format(spec.width, spec.height, surface.width, surface.height))
      end
    end,
  },
  {
    id = "alpha",
    title = "Alpha is 0 or 255, never in between",
    check = function(surface)
      local samples, count = {}, 0
      for x, y, c in surface:pixels() do
        local _, _, _, a = palette.unpack(c)
        if c ~= palette.TRANSPARENT and a ~= style.alpha_opaque then
          count = count + 1
          if #samples < MAX_SAMPLES then samples[#samples + 1] = { x = x, y = y, alpha = a } end
        end
      end
      if count > 0 then
        return issue("alpha", ("%d semi-transparent pixel(s)"):format(count), samples, count)
      end
    end,
  },
  {
    id = "palette",
    title = "Every colour comes from the fixed palette",
    check = function(surface)
      local bad, samples, count = {}, {}, 0
      for x, y, c in surface:pixels() do
        if not palette.is_valid(c) then
          count = count + 1
          local r, g, b = palette.unpack(c)
          local hex = ("#%02X%02X%02X"):format(r, g, b)
          if not bad[hex] then
            bad[hex] = true
            if #samples < MAX_SAMPLES then samples[#samples + 1] = { x = x, y = y, hex = hex } end
          end
        end
      end
      if count > 0 then
        return issue("palette", ("%d pixel(s) outside the palette"):format(count), samples, count)
      end
    end,
  },
  {
    id = "palette_size",
    title = "Colour count stays inside the per-asset budget",
    scope = "asset",
    check = function(surface)
      local tiles = style.tile_count(surface.width, surface.height)
      local budget = style.max_colors_per_asset + math.max(0, tiles - 1) * style.extra_colors_per_tile
      local used = P.color_count(surface)
      if used > budget then
        return issue("palette_size", ("%d colours used, budget is %d"):format(used, budget), {}, used)
      end
    end,
  },
  {
    id = "outline_thickness",
    title = "Outlines are exactly one pixel thick",
    scope = "asset",
    check = function(surface)
      -- style.outline_color is reserved for outlines; dark FILLS use another
      -- ink step. That reservation is what makes this rule decidable: an
      -- outline pixel with no body pixel beside it is a second outline layer.
      local outline = palette.resolve(style.outline_color)
      local samples, count = {}, 0
      for x, y, c in surface:pixels() do
        if c == outline then
          local touches = false
          for _, d in ipairs { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
            local n = surface:get(x + d[1], y + d[2])
            if n ~= palette.TRANSPARENT and n ~= outline then touches = true break end
          end
          if not touches then
            count = count + 1
            if #samples < MAX_SAMPLES then samples[#samples + 1] = { x = x, y = y } end
          end
        end
      end
      if count > 0 then
        return issue("outline_thickness",
          ("%d outline pixel(s) with no body beside them (outline thicker than 1px)")
            :format(count), samples, count)
      end
    end,
  },
  {
    id = "texture_noise",
    title = "Texture stays below the busyness ceiling",
    scope = "asset",
    check = function(surface, spec)
      local kind = (spec and spec.surface) or style.default_surface
      local cap = style.max_edge_density[kind] or style.max_edge_density[style.default_surface]
      local density = P.edge_density(surface)
      if density > cap then
        return issue("texture_noise",
          ("edge density %.3f, ceiling is %.2f for a %s surface"):format(density, cap, kind))
      end
    end,
  },
  {
    id = "isolated_pixels",
    title = "Detail is clustered, not single-pixel noise",
    check = function(surface, spec)
      local wrap = surface.wrap
      if spec and spec.wrap ~= nil then wrap = spec.wrap end
      local strays = P.isolated(surface, { wrap = wrap })
      local tiles = style.tile_count(surface.width, surface.height)
      local _, opaque = P.histogram(surface)
      -- BOTH caps apply, so the tighter one binds: an absolute budget per tile
      -- (dust is dust however large the asset is) AND a fraction of the opaque
      -- pixels (a mostly-transparent prop may not spend the whole absolute
      -- budget on its handful of pixels). Taking the larger of the two would
      -- let each cap excuse a breach of the other.
      local absolute = style.max_isolated_pixels * tiles
      local proportional = math.floor(opaque * style.max_isolated_ratio)
      local cap = math.min(absolute, proportional)
      if #strays > cap then
        local samples = {}
        for i = 1, math.min(MAX_SAMPLES, #strays) do samples[i] = strays[i] end
        return issue("isolated_pixels",
          ("%d isolated pixel(s), cap is %d (%d per tile, %.0f%% of %d opaque)")
            :format(#strays, cap, style.max_isolated_pixels,
              style.max_isolated_ratio * 100, opaque), samples, #strays)
      end
    end,
  },
}

--- Validate one surface.
-- @return report { ok, name, width, height, issues }
function validators.run(surface, spec)
  spec = spec or {}
  local kind = spec.kind or "asset"
  local report = {
    ok = true,
    name = spec.name or "asset",
    kind = kind,
    width = surface.width,
    height = surface.height,
    colors = P.color_count(surface),
    issues = {},
  }
  for _, rule in ipairs(validators.rules) do
    local applies = kind == "asset" or (rule.scope or "any") ~= "asset"
    local found = applies and rule.check(surface, spec)
    if found then
      report.ok = false
      report.issues[#report.issues + 1] = found
    end
  end
  return report
end

--- Validate every generator over a range of seeds. Used by the test runner and
-- by the "Validate all generators" Aseprite command.
-- @return ok, list of failing reports, number of assets checked
function validators.run_generators(seeds, opts)
  local generators = require("generators")
  opts = opts or {}
  local failures, checked = {}, 0
  for _, name in ipairs(opts.only or generators.names) do
    for seed = 1, (seeds or 32) do
      local surface = generators.build(name, seed)
      local report = validators.run(surface, generators.spec(name))
      report.seed = seed
      checked = checked + 1
      if not report.ok then failures[#failures + 1] = report end
    end
  end
  return #failures == 0, failures, checked
end

--- Human-readable report, one line per issue. Used verbatim by the Aseprite
--- dialog and by the CLI test runner.
function validators.format(report)
  local head = ("%s  %dx%d  %d colours  %s")
    :format(report.name, report.width, report.height, report.colors,
      report.ok and "OK" or "FAILED")
  if report.kind == "sheet" then head = head .. "  (sheet: size/budget rules N/A)" end
  if report.seed then head = head .. ("  (seed %d)"):format(report.seed) end
  local lines = { head }
  for _, i in ipairs(report.issues) do
    local where = {}
    for _, sample in ipairs(i.samples) do
      where[#where + 1] = ("(%d,%d%s)"):format(sample.x, sample.y,
        sample.hex and " " .. sample.hex or (sample.alpha and " a=" .. sample.alpha or ""))
    end
    lines[#lines + 1] = ("  [%s] %s%s")
      :format(i.rule, i.message, #where > 0 and "  at " .. table.concat(where, " ") or "")
  end
  return table.concat(lines, "\n")
end

return validators
