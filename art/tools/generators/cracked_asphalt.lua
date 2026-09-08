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
  -- A fracture and the crumbled surface beside it are ONE piece of damage, so
  -- the breakup is seeded on the crack rather than placed independently. That
  -- is the whole difference between "damaged asphalt" and "grey noisy ground":
  -- the marks have to be related to each other, and to leave the rest whole.
  local fracture = rng_stream:branch("cracks")
  local crack_pixels = {}
  for _ = 1, rng_stream:weighted {
    { value = 0, weight = 3 }, { value = 1, weight = 4 }, { value = 2, weight = 1 },
  } do
    local drawn = asphalt.crack(s, fracture:range(0, 15), fracture:range(0, 15),
      fracture:range(7, 11), fracture, {})
    for _, p in ipairs(drawn) do crack_pixels[#crack_pixels + 1] = p end
  end
  -- At most ONE broken-out area per tile, whatever the tile does with cracks.
  -- Per-crack breakup let a two-crack tile carry two of them and pushed the
  -- busiest seeds over the ground ceiling; it also made the worst tiles the
  -- ones the eye lands on, which is the wrong way round.
  if #crack_pixels > 3 and fracture:chance(0.55) then
    local at = crack_pixels[fracture:range(2, #crack_pixels - 1)]
    asphalt.breakup(s, at[1], at[2], fracture:range(5, 9), fracture, {})
  end

  -- A pothole only where the tile is not already carrying a fracture: one
  -- piece of damage per tile (ART_STYLE.md 2 -- a crack, a stone or a pothole
  -- is a minority event). Stacking both put the busiest tiles over the ground
  -- ceiling and made the damage read as a mess rather than as one event.
  if #crack_pixels == 0 and rng_stream:chance(0.22) then
    local hole = rng_stream:branch("pothole")
    asphalt.pothole(s, hole:range(0, 15), hole:range(0, 15), hole:range(6, 10), hole, {})
  end

  -- wear: weeds take the cracks, never the open surface
  if #crack_pixels > 0 and rng_stream:chance(0.4) then
    local weed = rng_stream:branch("weeds")
    local at = weed:pick(crack_pixels)
    grass.tufts(s, 1, weed, { at = { at[1], at[2] }, color = "grass_2" })
  end

  -- wear: washed-in soil, and only a little -- brown flecks scattered over a
  -- grey road are noise, not grime. It collects IN THE DAMAGE: a bias towards
  -- the fracture is what turns a stray brown patch into silt that washed into
  -- a crack, and on an uncracked tile it means there is nothing for soil to
  -- collect in, which is exactly right.
  local near_crack
  if #crack_pixels > 0 then
    local sites = {}
    for _, p in ipairs(crack_pixels) do sites[p[2] * gen.size.w + p[1] % gen.size.w] = true end
    near_crack = function(x, y)
      for dy = -1, 1 do
        for dx = -1, 1 do
          if sites[((y + dy) % gen.size.h) * gen.size.w + (x + dx) % gen.size.w] then return 1.0 end
        end
      end
      return 0.05
    end
  end
  dirt.fill(s, rng_stream, {
    coverage = 0.04, color = "earth_2", edge = "earth_2", bias = near_crack,
  })

  -- cleanup
  P.despeckle(s)
  return s
end

return gen
