-- generators/ground_set.lua -- the rest of the terrain field tiles, one
-- generator each, all built by `terrain.field`.
--
-- A SET rather than six files, because there is nothing per-terrain to say
-- here: the fill is the terrain's (terrain.lua), the hairline mark comes from
-- the shared vocabulary, and what is left is a name and a probability. Writing
-- them out separately would be six chances to disagree about how calm a field
-- ought to be.
--
-- `dirt_ground`, `dry_grass` and `cracked_asphalt` keep their own files
-- because levels and the metro-era tooling already name them; they call the
-- same `terrain.field`, so all nine tiles are one family.

local P = require("pixel_utils")
local terrain = require("terrain")

-- mark_chance is the fraction of SEEDS that carry the hairline mark. It is low
-- on purpose: at 0.25 a 100-tile field has ~25 marked cells, which reads as a
-- surface with some history. At 0.8 -- which is where these numbers started --
-- it reads as a pattern.
local FIELDS = {
  { terrain = "sparse_grass",   name = "sparse_grass",
    title = "Sparse grass 16x16",            mark = "stem",     chance = 0.28 },
  { terrain = "dirt_grass",     name = "dirt_grass",
    title = "Dirt and grass 16x16",          mark = "crust",    chance = 0.20 },
  { terrain = "broken_asphalt", name = "broken_asphalt",
    title = "Heavily damaged asphalt 16x16", mark = nil },
  { terrain = "concrete",       name = "concrete_ground",
    title = "Concrete ground 16x16",         mark = "hairline", chance = 0.30,
    color = "concrete_2" },
  { terrain = "mud",            name = "mud_ground",
    title = "Mud 16x16",                     mark = "rut",      chance = 0.24 },
  { terrain = "gravel",         name = "gravel_dirt",
    title = "Gravel / rocky dirt 16x16",     mark = nil },
}

local set = {}
for _, f in ipairs(FIELDS) do
  set[#set + 1] = {
    name = f.name,
    title = f.title,
    size = { w = 16, h = 16 },
    tileable = true,
    surface = "ground",
    category = "ground",
    variants = 12,
    terrain_type = f.terrain,
    build = function(rng_stream, opts)
      opts = opts or {}
      local s = P.new(16, 16, { wrap = true })
      return terrain.field(s, f.terrain, rng_stream, {
        mark = f.mark, mark_chance = f.chance, color = f.color,
        wear = opts.wear,
      })
    end,
  }
end

return set
