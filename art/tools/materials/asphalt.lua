-- materials/asphalt.lua -- road surface, and what twenty unmaintained years
-- do to it.
--
-- Grammar: a dark aggregate field, tar patches, cracks that branch and taper,
-- and potholes. A pothole is a depression, so it is lit like one: dark floor,
-- and the lit lip on its lower-right inner wall, the wall that faces the key
-- light.

local P = require("pixel_utils")
local palette = require("palette")

local asphalt = { name = "asphalt", kind = "base", ramp = "asphalt", base = "asphalt_3" }

function asphalt.fill(surface, rng_stream, opts)
  opts = opts or {}
  local area = P.area(surface, opts.area)
  local mask = P.mask(surface, opts)
  local base = palette.resolve(opts.base or asphalt.base)

  P.rect_fill(surface, area.x, area.y, area.w, area.h, base, { mask = mask })

  -- Tar patches and worn-smooth stretches.
  local patch = rng_stream:branch("asphalt_patch")
  for _ = 1, 1 + patch:range(0, 1) do
    P.cluster(surface,
      patch:range(area.x, area.x + area.w - 1), patch:range(area.y, area.y + area.h - 1),
      patch:range(12, 22), palette.shift(base, patch:chance(0.6) and -1 or 1), patch, { mask = mask })
  end
  -- Exposed aggregate: pairs, never single grains, and not many of them --
  -- a road surface is mostly featureless, which is exactly why the cracks read.
  local grit = rng_stream:branch("asphalt_grit")
  P.speckle(surface, 1, palette.shift(base, 1), grit, { area = area, mask = opts.mask, max_size = 2 })
  P.speckle(surface, 1, palette.shift(base, -1), grit, { area = area, mask = opts.mask, max_size = 2 })
end

--- A crack: a walk that branches once or twice and never runs straight.
--- Returns the pixels it drew, so a generator can grow weeds out of them.
function asphalt.crack(surface, x, y, length, rng_stream, opts)
  opts = opts or {}
  local mask = opts.mask
  local color = palette.resolve(opts.color or "asphalt_1")
  local drawn = {}
  local dirs = { { 1, 0 }, { 1, 1 }, { 0, 1 }, { 1, -1 }, { -1, 1 } }
  local function walk(cx, cy, len, d)
    for i = 1, len do
      if P.pixel(surface, cx, cy, color, mask) then drawn[#drawn + 1] = { cx, cy } end
      if i % 2 == 0 and rng_stream:chance(0.55) then d = rng_stream:pick(dirs) end
      cx, cy = cx + d[1], cy + d[2]
    end
    return cx, cy
  end
  local d = rng_stream:pick(dirs)
  local ex, ey = walk(x, y, length, d)
  if rng_stream:chance(0.6) then
    walk(ex, ey, rng_stream:range(2, 4), rng_stream:pick(dirs))
  end
  -- Broken aggregate along one side of the fracture.
  for _, p in ipairs(drawn) do
    if rng_stream:chance(0.25) then
      P.pixel(surface, p[1] + 1, p[2] + 1, palette.shift(color, 2), mask)
    end
  end
  return drawn
end

--- A pothole: dark floor, soil at the bottom, lit lip on the lower-right rim.
function asphalt.pothole(surface, x, y, size, rng_stream, opts)
  opts = opts or {}
  local mask = opts.mask
  local floor_color = palette.resolve(opts.color or "asphalt_1")
  local blob = P.cluster(surface, x, y, size, floor_color, rng_stream, { mask = mask })
  local lowest
  for _, p in ipairs(blob) do
    if not lowest or p[2] > lowest[2] or (p[2] == lowest[2] and p[1] > lowest[1]) then lowest = p end
    if rng_stream:chance(0.35) then P.pixel(surface, p[1], p[2], "earth_2", mask) end
  end
  if lowest then
    P.pixel(surface, lowest[1], lowest[2], palette.resolve(opts.lip or "asphalt_4"), mask)
    P.pixel(surface, lowest[1] - 1, lowest[2], palette.resolve(opts.lip or "asphalt_4"), mask)
  end
  return blob
end

return asphalt
