-- generators/transitions.lua -- the autotile set: every terrain pair, every
-- corner configuration.
--
-- 7 pairs x 15 corner masks = 105 generators, each with its own seeds for
-- variants, and ALL of them drawn by `terrain.draw`. That is the point of the
-- set: a level needs a complete connectivity set per pair (centre, four
-- straight edges, four outer corners, four inner corners, two diagonals) and
-- there is no version of that worth writing by hand seven times.
--
-- Mask 0 is deliberately absent. It means "no corner is the over terrain",
-- i.e. the pure base terrain, and that tile already exists as the base
-- terrain's own field generator. Emitting it again would give a level two
-- different tiles for the same thing and a Godot terrain set a duplicate.
--
-- Naming: `transition_<base>_<over>_<mask>`, mask zero-padded to two digits so
-- the names sort into the same order as the bitmask. Levels reference these
-- names forever, so neither the format nor the corner bit order may change
-- (terrain.CORNERS).
--
-- Each pair also gets a WORN variant family, `..._<mask>w`, which breaks the
-- boundary up rather than the field: a verge that has been driven over, a slab
-- edge that has been hit. It is a separate generator rather than a seed range
-- so a level can ask for a damaged edge specifically, which is what
-- "damaged/broken edge variants where appropriate" actually needs.

local P = require("pixel_utils")
local terrain = require("terrain")
local style = require("style")

local set = {}

-- Which pairs get a worn edge family. A grass verge and a soil edge wear by
-- being walked and driven on, and a slab joint spalls. Every pair here is
-- man-made on at least one side or is a boundary vehicles cross; a
-- grass-over-dirt boundary in the middle of a field has nothing to wear it,
-- so it does not get one and the library stays honest.
local WORN = {
  asphalt_dirt = true, asphalt_dry_grass = true, asphalt_concrete = true,
  concrete_dirt = true, concrete_dry_grass = true,
}

for _, pair_id in ipairs(terrain.pair_names) do
  local p = terrain.pair(pair_id)
  for mask = 1, style.terrain.masks - 1 do
    local shape = terrain.mask_shape[mask] or ("mask" .. mask)
    local edges = terrain.edge_terrains(mask)
    for _, worn in ipairs(WORN[pair_id] and { false, true } or { false }) do
      set[#set + 1] = {
        name = ("transition_%s_%02d%s"):format(pair_id, mask, worn and "w" or ""),
        title = ("%s over %s: %s%s")
          :format(terrain.get(p.over).title, terrain.get(p.base).title, shape,
            worn and ", worn" or ""),
        size = { w = 16, h = 16 },
        tileable = true,
        surface = "transition",
        category = "transition",
        -- Three seeds is the right number here. A transition tile's identity
        -- is its mask -- the level picks it by connectivity, not by looks --
        -- so variants only exist to stop a long boundary repeating, and a
        -- boundary is rarely more than a dozen tiles long.
        variants = 3,
        variant_group = ("transition_%s_%02d"):format(pair_id, mask),
        terrain = {
          pair = pair_id, base = p.base, over = p.over, mask = mask,
          shape = shape, edges = edges, worn = worn,
        },
        build = function(rng_stream, opts)
          local s = P.new(16, 16, { wrap = true })
          terrain.draw(s, pair_id, mask, rng_stream, {
            worn = worn or (opts and opts.worn),
          })
          return s
        end,
      }
    end
  end
end

return set
