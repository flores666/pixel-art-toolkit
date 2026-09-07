-- generators/rusted_barrel.lua -- 16x16 steel drum, long past its service life.
--
--   y=2..3   top cap and its rim, seen slightly from above
--   y=4..13  body: cylinder shading with two rolling hoops
--   y=14     the drum sits in its own shadow
--   y=15     contact shadow, cast down-right
--
-- The cylinder is an explicit column table for the same reason the crate is:
-- ten pixels of width can carry a turned edge, a specular strip and a shaded
-- side, and nothing more.

local P = require("pixel_utils")
local palette = require("palette")
local materials = require("materials")

local rust, dirt = materials.rust, materials.dirt

local gen = {
  name = "rusted_barrel",
  title = "Rusted barrel 16x16",
  size = { w = 16, h = 16 },
  tileable = false,
  surface = "prop",
  preview_background = "dirt_ground",
}

local X0, X1 = 3, 12
local Y0, Y1 = 4, 14

-- Ramp indices into palette.ramps.metal for x = 3 .. 12: turned edge, specular
-- strip one pixel in, body, shaded side. Same read as any other cylinder in
-- the set, which is what makes the props look like one family.
local COLUMN = { 5, 6, 5, 4, 4, 4, 4, 3, 3, 3 }
-- Dithered into the solid band on their right, never into thin air.
local DITHER_COLUMNS = { [5] = 4, [9] = 3 }

function gen.build(rng_stream, opts)
  opts = opts or {}
  local s = P.new(gen.size.w, gen.size.h)

  -- silhouette: body
  P.rect_fill(s, X0, Y0, X1 - X0 + 1, Y1 - Y0 + 1, "metal_4")

  -- structure: the top cap, one pixel proud of the body on each side
  P.rect_fill(s, X0 - 1, 2, X1 - X0 + 3, 2, "metal_5")
  P.hline(s, X0, 2, X1 - X0 + 1, "metal_6")            -- lid face, into the light
  s:set(X1, 2, palette.by_name.metal_4)                 -- turning away on the right
  s:set(X1 + 1, 3, palette.by_name.metal_3)
  s:set(X0 - 1, 3, palette.by_name.metal_5)
  -- the bung, offset so the lid never reads as symmetrical
  s:set(X0 + 2, 2, palette.by_name.metal_4)
  s:set(X0 + 3, 2, palette.by_name.metal_4)

  -- structure: cylinder shading
  for i, index in ipairs(COLUMN) do
    local x = X0 + i - 1
    for y = Y0, Y1 - 1 do s:set(x, y, palette.step("metal", index)) end
  end
  for x, index in pairs(DITHER_COLUMNS) do
    P.dither(s, palette.step("metal", index), 2,
      { area = { x = x, y = Y0, w = 1, h = Y1 - Y0 } })
  end

  -- structure: shadow the cap throws onto the body, softened by one dithered row
  P.hline(s, X0, Y0, X1 - X0 + 1, "metal_1")
  P.dither(s, "metal_1", 1, { area = { x = X0, y = Y0 + 1, w = X1 - X0 + 1, h = 1 }, allow_jump = true })

  -- structure: two rolling hoops, lit lip over their own shadow
  local hoops = { 7, 11 }
  for _, hy in ipairs(hoops) do
    P.rect_fill_shift(s, X0, hy, X1 - X0 + 1, 1, 1)
    P.rect_fill_shift(s, X0, hy + 1, X1 - X0 + 1, 1, -1)
  end

  -- structure: a dent between the hoops
  if rng_stream:chance(0.5) then
    local dent = rng_stream:branch("dent")
    local metal_only = P.ramp_mask("metal")
    local dw = dent:range(2, 4)
    local dx = dent:range(X0 + 1, X1 - dw)
    local dy = dent:chance(0.5) and 9 or 13
    P.rect_fill_shift(s, dx, dy, dw, 1, -1, { mask = metal_only })
    P.rect_fill_shift(s, dx, dy + 1, dw, 1, 1, { mask = metal_only })
  end

  -- structure: the drum sits in its own shadow
  P.rect_fill_shift(s, X0, Y1, X1 - X0 + 1, 1, -2)

  -- outline
  P.outline(s)

  -- wear: this is a rusted barrel, so corrosion is the point, not a garnish
  rust.fill(s, rng_stream, {
    coverage = rng_stream:weighted {
      { value = 0.20, weight = 2 },
      { value = 0.38, weight = 3 },
      { value = 0.60, weight = 2 },
    },
    streaks = true,
    mask = P.ramp_mask("metal"),
    bias = function(_, y) return y >= 9 and 1.0 or 0.45 end,
  })
  dirt.fill(s, rng_stream, {
    coverage = 0.12, color = "dirt_2", edge = "dirt_2",
    mask = P.ramp_mask("metal"),
    bias = function(_, y) return y >= 12 and 0.9 or 0.05 end,
  })

  -- cleanup, then the contact shadow
  P.despeckle(s)
  local shadow = rng_stream:branch("contact")
  P.broken_run(s, "h", 15, X0 + 1, 14, shadow,
    { color = "ink_3", on_transparent = true, run = { 5, 9 }, gap = { 1, 2 } })

  return s
end

return gen
