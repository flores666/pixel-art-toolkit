-- materials/wood.lua -- sleepers, crates, boarding, debris.
--
-- Grammar: plank bodies separated by dark gaps with a lit lip, long grain runs
-- along the plank, and knots drawn as small rings (never a lone dark pixel).

local P = require("pixel_utils")
local palette = require("palette")

local wood = { name = "wood", kind = "base", ramp = "wood", base = "wood_3" }

--- opts.axis "h" (grain runs horizontally) or "v".
function wood.fill(surface, rng_stream, opts)
  opts = opts or {}
  local area = P.area(surface, opts.area)
  local mask = P.mask(surface, opts)
  local base = palette.resolve(opts.base or wood.base)
  local axis = opts.axis or "h"

  P.rect_fill(surface, area.x, area.y, area.w, area.h, base, { mask = mask })

  local grain = rng_stream:branch("grain")
  local span = axis == "h" and area.h or area.w
  for i = 0, span - 1 do
    if grain:chance(0.55) then
      local offset = (axis == "h" and area.y or area.x) + i
      local from = axis == "h" and area.x or area.y
      local to = from + (axis == "h" and area.w or area.h) - 1
      P.broken_run(surface, axis, offset, from, to, grain,
        { delta = grain:chance(0.6) and -1 or 1, run = { 4, 9 }, gap = { 2, 5 }, mask = opts.mask })
    end
  end
end

--- Split an area into planks along `axis`, each separated by a dark gap with a
-- lit lip on the light side.
function wood.planks(surface, rng_stream, opts)
  opts = opts or {}
  local area = P.area(surface, opts.area)
  local axis = opts.axis or "h"
  local pitch = opts.pitch or 5
  local across = axis == "h" and area.h or area.w
  local gap = rng_stream:branch("plank_gap")
  for i = pitch, across - 1, pitch do
    local offset = (axis == "h" and area.y or area.x) + i
    local from = axis == "h" and area.x or area.y
    local to = from + (axis == "h" and area.w or area.h) - 1
    for k = from, to do
      local x = axis == "h" and k or offset
      local y = axis == "h" and offset or k
      local c = surface:get(x, y)
      if c ~= palette.TRANSPARENT then surface:set(x, y, palette.shift(c, -2)) end
    end
    P.broken_run(surface, axis, offset + 1, from, to, gap,
      { delta = 1, run = { 3, 7 }, gap = { 2, 4 }, mask = opts.mask })
  end
end

--- A knot: a dark ring with a darker core, three pixels across.
function wood.knot(surface, x, y, opts)
  opts = opts or {}
  local c = surface:get(x, y)
  if c == palette.TRANSPARENT then return end
  local ring, core = palette.shift(c, -1), palette.shift(c, -2)
  for dy = -1, 1 do
    for dx = -1, 1 do
      if dx ~= 0 or dy ~= 0 then P.pixel(surface, x + dx, y + dy, ring, opts.mask) end
    end
  end
  P.pixel(surface, x, y, core, opts.mask)
  P.pixel(surface, x - 1, y - 1, palette.shift(c, 1), opts.mask) -- lit upper-left rim
end

return wood
