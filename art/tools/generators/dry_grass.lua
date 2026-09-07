-- generators/dry_grass.lua -- 16x16 seamless dry grass.
--
-- Last year's straw with olive tufts pushing through and soil showing where
-- nothing took. Same field discipline as dirt_ground: no edge-keyed marks, a
-- constant base, uniformly placed detail.

local P = require("pixel_utils")
local materials = require("materials")

local grass = materials.grass

local gen = {
  name = "dry_grass",
  title = "Dry grass 16x16",
  size = { w = 16, h = 16 },
  tileable = true,
  surface = "ground",
}

function gen.build(rng_stream, opts)
  opts = opts or {}
  local s = P.new(gen.size.w, gen.size.h, { wrap = true })

  -- material: how much came back this year, and how much is bare
  local green = opts.green or rng_stream:weighted {
    { value = 0.25, weight = 3 },   -- mostly dead
    { value = 0.50, weight = 3 },
    { value = 0.75, weight = 2 },   -- overgrown corner
  }
  grass.fill(s, rng_stream, { green = green, bare = opts.bare or 0.3 })

  -- structure: a few standing stalks, bleached at the tip
  local stalks = rng_stream:branch("stalks")
  for _ = 1, stalks:range(1, 2) do
    -- seeded anywhere, including the edges: the surface wraps, and stalks
    -- that avoid the top rows leave a measurable band at every tile boundary
    grass.blade(s, stalks:range(0, 15), stalks:range(0, 15), stalks:range(2, 3), stalks, {})
  end

  -- cleanup
  P.despeckle(s)
  return s
end

return gen
