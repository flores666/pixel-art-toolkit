-- generators/supply_crate.lua -- 16x16 wooden supply box.
--
--   y=2      lid, one step lighter: it faces up into the key light
--   y=3..13  boards, separated by dark gaps with a lit lip below each
--   y=4..12  diagonal brace across the face
--   y=14     the box sits in its own shadow
--   y=15     contact shadow, cast down-right
--
-- Props are authored explicitly rather than generated: at 16px the silhouette
-- IS the asset, so only the wear varies with the seed.

local P = require("pixel_utils")
local palette = require("palette")
local materials = require("materials")

local wood, rust, dirt, debris = materials.wood, materials.rust, materials.dirt, materials.debris

local gen = {
  name = "supply_crate",
  title = "Supply crate 16x16",
  size = { w = 16, h = 16 },
  tileable = false,
  surface = "prop",
  preview_background = "dirt_ground",
}

local X0, X1 = 2, 13
local Y0, Y1 = 2, 14

function gen.build(rng_stream, opts)
  opts = opts or {}
  local s = P.new(gen.size.w, gen.size.h)

  -- silhouette + material
  P.rect_fill(s, X0, Y0, X1 - X0 + 1, Y1 - Y0 + 1, "wood_4")
  wood.fill(s, rng_stream, { area = { x = X0, y = Y0, w = X1 - X0 + 1, h = Y1 - Y0 + 1 },
    mask = function(x, y) return x >= X0 and x <= X1 and y >= Y0 and y <= Y1 end,
    base = "wood_4", axis = "h" })

  -- structure: the lid catches the light, the boards below are separated by gaps
  P.rect_fill_shift(s, X0, Y0, X1 - X0 + 1, 1, 1)
  wood.planks(s, rng_stream, {
    area = { x = X0, y = Y0 + 1, w = X1 - X0 + 1, h = Y1 - Y0 },
    axis = "h", pitch = 4,
    mask = function(x, y) return x >= X0 and x <= X1 and y >= Y0 and y <= Y1 end,
  })

  -- structure: the brace. Lit on its upper-left edge, like everything else.
  local brace = palette.by_name.wood_5
  P.line(s, X0 + 1, Y1 - 2, X1 - 1, Y0 + 2, brace,
    { mask = function(x, y) return x > X0 and x < X1 and y > Y0 and y < Y1 end })

  -- structure: the box sits in its own shadow, and a knot or two
  P.rect_fill_shift(s, X0, Y1, X1 - X0 + 1, 1, -2)
  if rng_stream:chance(0.5) then
    local knot = rng_stream:branch("knot")
    wood.knot(s, knot:range(X0 + 2, X1 - 2), knot:range(Y0 + 2, Y1 - 2), {
      mask = function(x, y) return x > X0 and x < X1 and y > Y0 and y < Y1 end,
    })
  end

  -- outline
  P.outline(s)

  -- wear: rusted fixings, ground-in dirt at the foot, splinters knocked off
  rust.fill(s, rng_stream, {
    coverage = rng_stream:weighted {
      { value = 0.00, weight = 2 },
      { value = 0.08, weight = 3 },
      { value = 0.18, weight = 2 },
    },
    mask = P.ramp_mask("wood"),
    bias = function(_, y) return y >= 11 and 1.0 or 0.3 end,
  })
  dirt.fill(s, rng_stream, {
    coverage = 0.14, color = "dirt_2", edge = "dirt_2",
    mask = P.ramp_mask("wood"),
    bias = function(_, y) return y >= 12 and 0.9 or 0.08 end,
  })

  -- cleanup, then the contact shadow, which must survive it
  P.despeckle(s)
  local shadow = rng_stream:branch("contact")
  P.broken_run(s, "h", 15, X0 + 1, 14, shadow,
    { color = "ink_3", on_transparent = true, run = { 5, 9 }, gap = { 1, 2 } })

  if rng_stream:chance(0.4) then
    debris.fill(s, rng_stream, {
      coverage = 0.04, area = { x = 0, y = 13, w = 16, h = 2 },
      kinds = { { value = "wood_3", weight = 1 } },
      mask = P.ramp_mask("wood"),
    })
  end
  return s
end

return gen
