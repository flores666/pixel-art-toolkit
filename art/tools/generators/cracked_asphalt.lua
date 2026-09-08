-- generators/cracked_asphalt.lua -- 16x16 seamless road surface with hairline
-- fracturing.
--
-- The road you drive on: intact, with a hairline crack on a minority of tiles.
-- That is the whole tile, and the restraint is the point -- a fracture only
-- reads as damage while the surface around it is whole, so a field where every
-- cell is cracked has no damage in it at all, just texture. The heavy end of
-- the same material is `broken_asphalt_ground`, which is a terrain of its own
-- because a failed surface is an AREA you lay, not a variant you sprinkle.
--
-- Potholes, break-out, silt and weeds through the cracks used to be here and
-- are decals now (`decal_pothole`, `decal_rubble`, `decal_weeds`): a pothole
-- belongs where the level wants a pothole, not on every eighth tile forever.

local P = require("pixel_utils")
local terrain = require("terrain")

local gen = {
  name = "cracked_asphalt",
  title = "Cracked asphalt 16x16",
  size = { w = 16, h = 16 },
  tileable = true,
  surface = "ground",
  category = "ground",
  variants = 12,
  terrain_type = "asphalt",
}

function gen.build(rng_stream, opts)
  opts = opts or {}
  local s = P.new(gen.size.w, gen.size.h, { wrap = true })
  return terrain.field(s, "asphalt", rng_stream, {
    mark = "hairline", mark_chance = 0.30, color = "asphalt_2",
  })
end

return gen
