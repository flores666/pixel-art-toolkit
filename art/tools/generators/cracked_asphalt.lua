-- generators/cracked_asphalt.lua -- 16x16 seamless broken road surface.
--
-- Cracks are the whole point of this tile, and they are also the biggest risk
-- to an invisible grid: a crack that runs along an edge, or always starts in
-- the same place, prints the tile boundary onto the field. They are therefore
-- seeded anywhere in the tile, walk in any direction, and wrap.

local P = require("pixel_utils")
local materials = require("materials")

local asphalt, grass, dirt = materials.asphalt, materials.grass, materials.dirt

local gen = {
  name = "cracked_asphalt",
  title = "Cracked asphalt 16x16",
  size = { w = 16, h = 16 },
  tileable = true,
  surface = "ground",
}

function gen.build(rng_stream, opts)
  opts = opts or {}
  local s = P.new(gen.size.w, gen.size.h, { wrap = true })

  -- material
  asphalt.fill(s, rng_stream, {})

  -- structure: fractures, and what grows out of them
  -- Most of a road is intact. Fractures are what the eye looks for, so they
  -- only read as damage while the surface around them is still whole.
  local fracture = rng_stream:branch("cracks")
  local crack_pixels = {}
  for _ = 1, rng_stream:weighted {
    { value = 0, weight = 3 }, { value = 1, weight = 4 }, { value = 2, weight = 1 },
  } do
    local drawn = asphalt.crack(s, fracture:range(0, 15), fracture:range(0, 15),
      fracture:range(4, 8), fracture, {})
    for _, p in ipairs(drawn) do crack_pixels[#crack_pixels + 1] = p end
  end

  if rng_stream:chance(0.18) then
    local hole = rng_stream:branch("pothole")
    asphalt.pothole(s, hole:range(0, 15), hole:range(0, 15), hole:range(5, 9), hole, {})
  end

  -- wear: weeds take the cracks, never the open surface
  if #crack_pixels > 0 and rng_stream:chance(0.4) then
    local weed = rng_stream:branch("weeds")
    for _ = 1, 1 do
      local at = weed:pick(crack_pixels)
      grass.tufts(s, 1, weed, { area = { x = at[1] - 1, y = at[2] - 1, w = 3, h = 3 } })
    end
  end

  -- wear: washed-in soil
  dirt.fill(s, rng_stream, { coverage = 0.05, color = "earth_2", edge = "earth_2" })

  -- cleanup
  P.despeckle(s)
  return s
end

return gen
