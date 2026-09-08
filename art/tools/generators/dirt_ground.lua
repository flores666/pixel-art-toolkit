-- generators/dirt_ground.lua -- 16x16 seamless bare soil. The default ground.
--
-- A ground tile is laid in fields of a hundred, so nothing in it may key to a
-- tile edge and nothing may repeat at a fixed offset: the base colour is the
-- same in every variant, every mark is placed uniformly across the whole tile
-- on a wrapping surface, and the mark count barely varies. That combination is
-- what keeps the 16x16 grid invisible (see previews.grid_report).
--
-- What used to be here as well -- stones, dead sprigs, fallen chunks, a
-- shrinkage crust on two tiles in three -- is now a DECAL (generators/decals).
-- Each of those marks was defensible on its own tile and a hundred of them
-- together read as static; a stone baked into a field tile is a stone printed
-- a hundred times. The tile keeps ONE hairline crust on a quarter of its
-- variants, which is exactly how the game's own authored floor tiles are
-- built, and the level places everything larger where it wants it.

local P = require("pixel_utils")
local terrain = require("terrain")

local gen = {
  name = "dirt_ground",
  title = "Dirt ground 16x16",
  size = { w = 16, h = 16 },
  tileable = true,
  surface = "ground",
  category = "ground",
  variants = 12,
  terrain_type = "dirt",
}

function gen.build(rng_stream, opts)
  opts = opts or {}
  local s = P.new(gen.size.w, gen.size.h, { wrap = true })
  return terrain.field(s, "dirt", rng_stream, {
    wear = opts.wear or rng_stream:weighted {
      { value = 0.30, weight = 2 }, { value = 0.55, weight = 3 }, { value = 0.80, weight = 2 },
    },
    mark = "crust", mark_chance = 0.25,
  })
end

return gen
