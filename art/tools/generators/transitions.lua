-- generators/transitions.lua -- the autotile set: every terrain pair, every
-- corner configuration.
--
-- 7 pairs x 15 corner masks = 105 generators, each with its own seeds for
-- variants, and ALL of them drawn by `terrain.draw`. That is the point of the
-- set: a level needs a complete connectivity set per pair (centre, four
-- straight edges, four outer corners, four inner corners, two diagonals) and
-- there is no version of that worth writing by hand seven times.
--
-- Masks 0 AND 15 are deliberately absent, for the same reason: both mean the
-- cell is entirely ONE terrain (all base, or all over), and both of those
-- tiles already exist as that terrain's own field generator. Emitting them
-- again gives a level two different tiles for the same thing and a Godot
-- terrain set a duplicate.
--
-- It is not a theoretical objection. A cell resolves to a transition only when
-- its four corners disagree (scenes.resolve_cell), so mask 15 could never be
-- selected -- and it was also generating false positives in the
-- `tileable_border` group rule, because a "transition" with no boundary in it
-- is just a field tile drawn by a different rng stream and is held to the
-- field discipline without being able to satisfy it.
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

-- Which pairs get a worn edge family, and why it is a short list.
--
-- Every pair here is a boundary something actually wears: a road or apron edge
-- that vehicles cross and that spalls. A grass-over-dirt boundary in the middle
-- of a field has nothing to wear it, so it gets no worn variant and the
-- library stays honest about what it is offering.
--
-- It is also short on purpose. The pair table is derived now (terrain.lua) and
-- covers 35 combinations; giving every hard-surface pair a worn family would
-- add 270 more generators for a variation a level can get from an edge decal.
-- These six are the joins a level actually builds a yard or a road out of.
local WORN = {
  asphalt_dirt = true, asphalt_dry_grass = true,
  concrete_dirt = true, concrete_dry_grass = true,
  asphalt_concrete = true, broken_asphalt_concrete = true,
}
for id in pairs(WORN) do
  assert(terrain.pairs[id], ("WORN names '%s', which is not a derived pair"):format(id))
end

for _, pair_id in ipairs(terrain.pair_names) do
  local p = terrain.pair(pair_id)
  for mask = 1, style.terrain.masks - 2 do   -- 1..14: see above
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
