-- generators/dry_grass.lua -- 16x16 seamless dry grass. The default ground
-- away from the roads.
--
-- Last year's straw with the soil showing where nothing took. Same field
-- discipline as dirt_ground: no edge-keyed marks, a constant base, uniformly
-- placed detail -- and, since the decal system exists, no standing vegetation
-- baked in. A tuft on a field tile is a tuft printed a hundred times, and a
-- hundred tufts on a 16px pitch is the confetti this generator used to
-- produce. Standing growth is `decal_grass_tuft` and its family now.

local P = require("pixel_utils")
local terrain = require("terrain")

local gen = {
  name = "dry_grass",
  title = "Dry grass 16x16",
  size = { w = 16, h = 16 },
  tileable = true,
  surface = "ground",
  category = "ground",
  variants = 12,
  terrain_type = "dry_grass",
}

function gen.build(rng_stream, opts)
  opts = opts or {}
  local s = P.new(gen.size.w, gen.size.h, { wrap = true })
  return terrain.field(s, "dry_grass", rng_stream, {
    green = opts.green,
    mark = "stem", mark_chance = 0.22,
  })
end

return gen
