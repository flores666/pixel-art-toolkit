-- previews/init.lua -- repeated tile sheets.
--
-- A single 16x16 tile tells you nothing about whether it tiles, whether the
-- seed variation is too loud, or whether the dither is in phase. A 10x10 field
-- does, which is why every generator gets reviewed as a sheet before it ships.

local P = require("pixel_utils")
local generators = require("generators")
local style = require("style")

local previews = {}

previews.default_cols = 10
previews.default_rows = 10

--- Build a cols x rows field of one generator.
-- Each cell gets its own seed (base_seed + index), so the sheet shows the whole
-- variation range at once. Object generators are drawn over their declared
-- `preview_background` generator, otherwise they would float in a void.
-- opts: seed, cols, rows, vary (false = repeat one seed, to check tiling)
-- @return Surface
function previews.sheet(name, opts)
  opts = opts or {}
  local gen = generators.get(name)
  local cols = opts.cols or previews.default_cols
  local rows = opts.rows or previews.default_rows
  local base = opts.seed or 1
  local vary = opts.vary
  if vary == nil then vary = true end

  local sheet = P.new(cols * gen.size.w, rows * gen.size.h)
  local background = gen.preview_background and generators.get(gen.preview_background)

  for row = 0, rows - 1 do
    for col = 0, cols - 1 do
      local index = row * cols + col
      local seed = vary and (base + index) or base
      local x, y = col * gen.size.w, row * gen.size.h
      if background then
        -- Tile the background across the cell, whatever its own size is.
        for by = 0, gen.size.h - 1, background.size.h do
          for bx = 0, gen.size.w - 1, background.size.w do
            sheet:blit(generators.build(background.name, seed * 31 + bx + by), x + bx, y + by)
          end
        end
      end
      sheet:blit(generators.build(name, seed), x, y)
    end
  end
  return sheet
end

--- One tile repeated, the strict test for seamlessness: any edge artefact
--- shows up as a grid.
function previews.tiling_check(name, seed, opts)
  opts = opts or {}
  opts.vary = false
  opts.seed = seed or 1
  return previews.sheet(name, opts)
end

--- Does a field of this tile print its own 16x16 grid?
--
-- Three cues, measured rather than argued about:
--
--   seam_bias      the mean SIGNED luminance step across tile boundaries,
--                  over the mean step everywhere. This is the one that
--                  matters: a grid is visible when every boundary steps the
--                  same way, drawing a line. Independently seeded tiles differ
--                  at their edges too, but in random directions, and the eye
--                  finds no line in that. The game's own metro floor variants
--                  score 4.2 and 10.3 here; continuous untiled art scores 0.01.
--   seam_contrast  the mean ABSOLUTE step at boundaries over the mean step.
--                  Informational above 1 -- independently seeded tiles always
--                  differ more across a boundary than within one, and a value
--                  of 2-3 usually means the interiors are pleasingly coherent.
--                  Below 1 it is a real defect: detail avoiding the edges.
--   field_density  pixel_utils.edge_density over the whole field: the average
--                  busyness a player actually sees. A tile can carry a feature
--                  without the field turning into static, but only if most
--                  tiles do not.
--   tile_luma_sd   spread of per-tile average luminance. Even with clean
--                  seams, tiles of differing overall brightness lay out as a
--                  patchwork of light and dark squares.
--
-- Limits live in style.grid, and `ok` reports against them -- but only ground
-- surfaces are held to them (`enforced`). A wall SHOULD show its cast joint
-- and a fence SHOULD show its folds; those are construction lines, and hiding
-- them would be a worse lie than the grid.
-- @return table of measurements
function previews.grid_report(name, opts)
  opts = opts or {}
  local palette = require("palette")
  local gen = generators.get(name)
  local cols = opts.cols or previews.default_cols
  local rows = opts.rows or previews.default_rows
  local sheet = previews.sheet(name, { seed = opts.seed or 1, cols = cols, rows = rows })

  local function step(ax, ay, bx, by)
    return palette.luminance(sheet:get(bx, by)) - palette.luminance(sheet:get(ax, ay))
  end

  local total, count = 0, 0
  local sum_x, abs_x, n_x = 0, 0, 0
  local sum_y, abs_y, n_y = 0, 0, 0
  for y = 0, sheet.height - 1 do
    for x = 0, sheet.width - 1 do
      if x + 1 < sheet.width then
        local d = step(x, y, x + 1, y)
        total = total + math.abs(d); count = count + 1
        if (x + 1) % gen.size.w == 0 then
          sum_x = sum_x + d; abs_x = abs_x + math.abs(d); n_x = n_x + 1
        end
      end
      if y + 1 < sheet.height then
        local d = step(x, y, x, y + 1)
        total = total + math.abs(d); count = count + 1
        if (y + 1) % gen.size.h == 0 then
          sum_y = sum_y + d; abs_y = abs_y + math.abs(d); n_y = n_y + 1
        end
      end
    end
  end
  local mean_step = math.max(1e-6, total / math.max(1, count))

  local means, sum = {}, 0
  for row = 0, rows - 1 do
    for col = 0, cols - 1 do
      local tile_total = 0
      for y = 0, gen.size.h - 1 do
        for x = 0, gen.size.w - 1 do
          tile_total = tile_total + palette.luminance(sheet:get(col * gen.size.w + x, row * gen.size.h + y))
        end
      end
      local mean = tile_total / (gen.size.w * gen.size.h)
      means[#means + 1] = mean
      sum = sum + mean
    end
  end
  local avg = sum / #means
  local variance = 0
  for _, m in ipairs(means) do variance = variance + (m - avg) ^ 2 end

  local report = {
    name = name,
    surface = gen.surface,
    field_density = P.edge_density(sheet),
    enforced = gen.surface == "ground",
    mean_step = mean_step,
    seam_bias_x = math.abs(sum_x / math.max(1, n_x)) / mean_step,
    seam_bias_y = math.abs(sum_y / math.max(1, n_y)) / mean_step,
    seam_contrast_x = (abs_x / math.max(1, n_x)) / mean_step,
    seam_contrast_y = (abs_y / math.max(1, n_y)) / mean_step,
    tile_luma_sd = math.sqrt(variance / #means),
  }
  -- Report WHICH cue failed, not just that one did. Four measurements share
  -- this verdict and the numbers are not interchangeable -- a field-density
  -- breach is "the tile is too busy" and a seam-bias breach is "the tile has
  -- an edge drawn on it", which are different bugs with different fixes. A
  -- bare `ok = false` sent the reader off to re-measure by hand.
  local limits = style.grid
  local failures = {}
  local function check(name, value, limit, over)
    local bad = over and value > limit or (not over and value < limit)
    if bad then
      failures[#failures + 1] = ("%s %.3f %s %.2f"):format(name, value, over and ">" or "<", limit)
    end
  end
  check("seam_bias_x", report.seam_bias_x, limits.max_seam_bias, true)
  check("seam_bias_y", report.seam_bias_y, limits.max_seam_bias, true)
  check("seam_contrast_x", report.seam_contrast_x, limits.min_seam_contrast, false)
  check("seam_contrast_y", report.seam_contrast_y, limits.min_seam_contrast, false)
  check("tile_luma_sd", report.tile_luma_sd, limits.max_tile_luma_sd, true)
  check("field_density", report.field_density, limits.max_field_density, true)
  report.failures = failures
  report.why = table.concat(failures, ", ")
  report.ok = #failures == 0
  return report
end

--- A strip of the palette itself, for eyeballing the ramps in Aseprite.
function previews.palette_strip(opts)
  opts = opts or {}
  local palette = require("palette")
  local swatch = opts.swatch or style.tile
  local ramps = palette.ramp_order
  local widest = 0
  for _, r in ipairs(ramps) do widest = math.max(widest, #palette.ramps[r]) end
  local sheet = P.new(widest * swatch, #ramps * swatch)
  for row, ramp_name in ipairs(ramps) do
    for i, color in ipairs(palette.ramps[ramp_name]) do
      P.rect_fill(sheet, (i - 1) * swatch, (row - 1) * swatch, swatch, swatch, color)
    end
  end
  return sheet
end

return previews
