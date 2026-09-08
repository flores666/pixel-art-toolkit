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
      -- A class with no ceiling is not unmeasured by accident: see the note on
      -- style.max_edge_density. `decal` has no meaningful edge density, and
      -- falling back to the default ceiling here would fail correctly drawn
      -- decals at random. Those are checked by decal_coverage/decal_marks.
      local cap = style.max_edge_density[kind]
      if not cap then return end
      -- edge_density only means anything on an asset with a solid interior.
      -- On one made of one-pixel strokes -- a weed, a fallen branch, a decal
      -- -- almost every adjacent pair straddles a lit face or an outline and
      -- the measure saturates near 1.0 however well the asset is drawn. This
      -- gate is why `decal` needs no ceiling of its own: the exemption is a
      -- consequence of the same rule rather than a special case.
      if P.interior_ratio(surface) < style.min_interior_for_density then return end
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
  {
    id = "decal_coverage",
    title = "A decal is mostly transparent",
    scope = "asset",
    check = function(surface, spec)
      if not spec or spec.surface ~= "decal" then return end
      local coverage = P.coverage(surface)
      if coverage > style.decal.max_coverage then
        return issue("decal_coverage",
          ("decal covers %.0f%% of its cell, ceiling is %.0f%% -- this is a tile, not a decal")
            :format(coverage * 100, style.decal.max_coverage * 100))
      end
      if coverage < style.decal.min_coverage then
        return issue("decal_coverage",
          ("decal covers only %.1f%% of its cell, floor is %.1f%% -- nothing was drawn")
            :format(coverage * 100, style.decal.min_coverage * 100))
      end
    end,
  },
  {
    id = "decal_marks",
    title = "A decal is one mark in one place",
    scope = "asset",
    check = function(surface, spec)
      if not spec or spec.surface ~= "decal" then return end
      local groups = P.mark_groups(surface)
      if #groups > style.decal.max_marks then
        local samples = {}
        for i = 1, math.min(MAX_SAMPLES, #groups) do
          local p = groups[i].pixels[1]
          samples[i] = { x = p[1], y = p[2] }
        end
        return issue("decal_marks",
          ("decal breaks into %d separate marks, cap is %d -- that is a texture, not a decal")
            :format(#groups, style.decal.max_marks), samples, #groups)
      end
    end,
  },
  {
    id = "prop_silhouette",
    title = "A prop reads as one object with a silhouette",
    scope = "asset",
    check = function(surface, spec)
      -- Props and the object-like categories: the silhouette IS the asset at
      -- this size, so these are the defects that make one unreadable. Ground,
      -- transitions and decals are exempt by construction -- a field tile
      -- fills its cell and a decal is meant to be sparse.
      if not spec then return end
      if spec.surface ~= "prop" and spec.surface ~= "structure" then return end
      if spec.wrap then return end   -- a tileable texture has no silhouette

      local limits = style.prop
      local occupancy = P.coverage(surface)
      if occupancy > limits.max_occupancy then
        return issue("prop_silhouette",
          ("fills %.0f%% of its cell, ceiling is %.0f%% -- no silhouette left to read")
            :format(occupancy * 100, limits.max_occupancy * 100))
      end
      if occupancy < limits.min_occupancy then
        return issue("prop_silhouette",
          ("fills only %.0f%% of its cell, floor is %.0f%%")
            :format(occupancy * 100, limits.min_occupancy * 100))
      end

      -- Separate opaque islands. A prop plus its contact shadow is two; a
      -- scatter of eight fragments is rubble whether it meant to be or not.
      local groups = P.mark_groups(surface, { gap = 2 })
      if #groups > limits.max_components then
        local samples = {}
        for i = 1, math.min(MAX_SAMPLES, #groups) do
          local p = groups[i].pixels[1]
          samples[i] = { x = p[1], y = p[2] }
        end
        return issue("prop_silhouette",
          ("breaks into %d separate pieces, cap is %d")
            :format(#groups, limits.max_components), samples, #groups)
      end

      -- Enclosed transparent regions. A bin has a mouth and a corroded fence
      -- has a hole, so holes are legitimate -- but they have to be DRAWN. A
      -- prop that comes out with six of them has been eaten by its own wear
      -- overlays, and a one-pixel hole is never a window.
      local holes = P.holes(surface)
      local samples, small = {}, 0
      for _, hole in ipairs(holes) do
        if hole.size < limits.min_hole_size then
          small = small + 1
          if #samples < MAX_SAMPLES then
            samples[#samples + 1] = { x = hole.pixels[1][1], y = hole.pixels[1][2] }
          end
        end
      end
      if small > 0 then
        return issue("prop_silhouette",
          ("%d enclosed hole(s) smaller than %d px -- a pinhole is a bug, not a window")
            :format(small, limits.min_hole_size), samples, small)
      end
      local hole_cap = spec.max_interior_holes or limits.max_interior_holes
      if #holes > hole_cap then
        local where = {}
        for i = 1, math.min(MAX_SAMPLES, #holes) do
          where[i] = { x = holes[i].pixels[1][1], y = holes[i].pixels[1][2] }
        end
        return issue("prop_silhouette",
          ("%d enclosed transparent holes, cap is %d -- the wear overlays have eaten the shape")
            :format(#holes, hole_cap), where, #holes)
      end
    end,
  },
}


-- Group rules -----------------------------------------------------------------
--
-- Some production defects are not properties of an asset at all, and trying to
-- check them per asset gives an unsound test. Three examples, all of which
-- were written as per-asset rules first and had to be moved here:
--
--   * "variants repeat" is a statement about a SET of variants;
--   * "detail avoids the tile border" is a statement about a generator across
--     its seeds -- one tile with a single compact mark in the middle is not a
--     grid, but a generator whose every seed leaves the border clear is;
--   * "these transition tiles abut" is a statement about a PAIR of tiles laid
--     next to each other, which is the only place the seam exists.
--
-- Contract -- a group rule is:
--   { id, title, check = function(ctx) -> issue|nil }
-- where ctx = {
--   name, gen,
--   seeds    = the seeds that actually SHIP as variants,
--   surfaces = { [seed] = Surface } for every seed in seeds or sample,
--   sample   = at least MIN_SAMPLE seeds, for rules that measure a STATISTIC
--              of the generator rather than a property of the shipped set.
-- }
--
-- The distinction is load-bearing. "Do these variants repeat?" is about the
-- shipped set, so it uses `seeds`. "Does this generator avoid the tile
-- border?" is a property of the generator, and measuring it on the three
-- variants a transition tile ships gives a coin flip -- `dirt_ground`, which
-- is correct, failed it at three seeds and passes at eight. A rule that
-- depends on how many variants happen to ship is not a rule.
validators.group_rules = {
  {
    id = "variant_similarity",
    title = "Variants differ enough to lay out, and little enough to stay the same object",
    check = function(ctx)
      local list = {}
      for _, seed in ipairs(ctx.seeds) do list[#list + 1] = ctx.surfaces[seed] end
      if #list < 2 then return end
      local bounds = style.variant_overlap[ctx.gen.surface]
      if not bounds then return end

      local total, pairs_seen, identical = 0, 0, 0
      local worst_same, worst_pair = -1, nil
      for a = 1, #list do
        for b = a + 1, #list do
          local sa, sb = list[a], list[b]
          local same = 0
          for i = 1, sa.width * sa.height do
            if sa.data[i] == sb.data[i] then same = same + 1 end
          end
          local share = same / (sa.width * sa.height)
          if share >= 1 then identical = identical + 1 end
          if share > worst_same then
            worst_same, worst_pair = share, { ctx.seeds[a], ctx.seeds[b] }
          end
          total = total + share
          pairs_seen = pairs_seen + 1
        end
      end
      if identical > style.max_identical_variants then
        return issue("variant_similarity",
          ("%d pair(s) of variants are byte-identical (e.g. seeds %d and %d): the seed did nothing")
            :format(identical, worst_pair[1], worst_pair[2]), {}, identical)
      end
      local mean = total / pairs_seen
      if mean > bounds.max then
        return issue("variant_similarity",
          ("variants share %.0f%% of their pixels on average, ceiling is %.0f%% for a %s "
            .. "surface: a level built from these will repeat visibly")
            :format(mean * 100, bounds.max * 100, ctx.gen.surface))
      end
      if mean < bounds.min then
        return issue("variant_similarity",
          ("variants share only %.0f%% of their pixels on average, floor is %.0f%% for a %s "
            .. "surface: these are not the same object any more")
            :format(mean * 100, bounds.min * 100, ctx.gen.surface))
      end
    end,
  },
  {
    id = "tileable_border",
    title = "A tileable generator does not leave a calm ring around every cell",
    check = function(ctx)
      if not ctx.gen.tileable then return end
      -- Aggregated over every variant, which is the scope at which this is a
      -- real defect: detail that systematically avoids the edges leaves a calm
      -- frame around every cell, and a field of those reads as a lattice
      -- however clean each individual tile is. previews.grid_report catches
      -- the same thing over a laid field (seam_contrast); this attributes it
      -- to a generator, and applies to every tileable class rather than only
      -- to ground.
      local ring, ring_marks, inner, inner_marks = 0, 0, 0, 0
      for _, seed in ipairs(ctx.sample) do
        local surface = ctx.surfaces[seed]
        local hist, opaque = P.histogram(surface)
        if opaque > 0 then
          local background, best = nil, -1
          for c, n in pairs(hist) do
            if n > best or (n == best and background and c < background) then
              background, best = c, n
            end
          end
          local w, h = surface.width, surface.height
          for x, y, c in surface:pixels() do
            local on_border = x == 0 or y == 0 or x == w - 1 or y == h - 1
            if on_border then
              ring = ring + 1
              if c ~= background then ring_marks = ring_marks + 1 end
            else
              inner = inner + 1
              if c ~= background then inner_marks = inner_marks + 1 end
            end
          end
        end
      end
      if inner == 0 or ring == 0 or inner_marks < 40 then return end
      local ring_rate, inner_rate = ring_marks / ring, inner_marks / inner
      if ring_rate < inner_rate * 0.55 then
        return issue("tileable_border",
          ("across %d seeds, marks land on %.0f%% of border pixels but %.0f%% of interior "
            .. "pixels: that calm ring around every cell IS a visible grid")
            :format(#ctx.sample, ring_rate * 100, inner_rate * 100))
      end
    end,
  },
}

--- Cross-variant checks for one generator.
-- @return report { ok, name, issues }
-- Enough seeds for a per-generator statistic to mean anything. Measured: the
-- border test flips between pass and fail below this and is stable above it.
local MIN_SAMPLE = 12

function validators.run_group(name, opts)
  opts = opts or {}
  local generators = require("generators")
  local gen = generators.get(name)
  local count = opts.seeds or gen.variants
  local base = opts.seed or 1
  local ctx = { name = name, gen = gen, surfaces = {}, seeds = {}, sample = {} }
  for n = 0, math.max(count, MIN_SAMPLE) - 1 do
    local seed = base + n
    if n < count then ctx.seeds[#ctx.seeds + 1] = seed end
    ctx.sample[#ctx.sample + 1] = seed
    ctx.surfaces[seed] = generators.build(name, seed)
  end
  local report = { ok = true, name = name, kind = "group", issues = {},
    width = gen.size.w, height = gen.size.h, colors = 0 }
  for _, rule in ipairs(validators.group_rules) do
    local found = rule.check(ctx)
    if found then
      report.ok = false
      report.issues[#report.issues + 1] = found
    end
  end
  return report
end

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
