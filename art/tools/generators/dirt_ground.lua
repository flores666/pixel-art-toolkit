-- generators/dirt_ground.lua -- 16x16 seamless bare soil.
--
-- A ground tile is laid in fields of a hundred, so nothing in it may key to a
-- tile edge and nothing may repeat at a fixed offset: the base colour is the
-- same in every variant, every mark is placed uniformly across the whole tile
-- on a wrapping surface, and the mark count barely varies. That combination is
-- what keeps the 16x16 grid invisible (see previews.grid_report).

local P = require("pixel_utils")
local materials = require("materials")

local earth, grass, debris = materials.earth, materials.grass, materials.debris

local gen = {
  name = "dirt_ground",
  title = "Dirt ground 16x16",
  size = { w = 16, h = 16 },
  tileable = true,
  surface = "ground",
}

function gen.build(rng_stream, opts)
  opts = opts or {}
  local s = P.new(gen.size.w, gen.size.h, { wrap = true })

  -- material
  local wear = opts.wear or rng_stream:weighted {
    { value = 0.30, weight = 2 },
    { value = 0.55, weight = 3 },
    { value = 0.80, weight = 2 },
  }
  earth.fill(s, rng_stream, { wear = wear })

  -- structure: stones pressed into the surface. Most tiles get none: a field
  -- where every cell has a feature reads as static, however good the cell is.
  earth.stones(s, rng_stream:weighted {
    { value = 0, weight = 3 }, { value = 1, weight = 3 }, { value = 2, weight = 1 },
  }, rng_stream:branch("stones"), {})

  -- wear: dead sprigs that never made it, and the odd fallen chunk
  if rng_stream:chance(0.35) then
    grass.tufts(s, 1, rng_stream:branch("sprigs"), { color = "straw_2" })
  end
  if rng_stream:chance(0.25) then
    debris.fill(s, rng_stream, { coverage = 0.05 })
  end

  -- cleanup
  P.despeckle(s)
  return s
end

return gen
