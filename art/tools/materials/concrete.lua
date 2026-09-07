-- materials/concrete.lua -- poured concrete, above ground and below.
--
-- Grammar: a mid base, broad low-contrast patches (never a gradient), paired
-- aggregate specks, cast joints, hairline cracks, and spalling where the
-- surface has broken away and left the aggregate showing.

local P = require("pixel_utils")
local palette = require("palette")

local concrete = { name = "concrete", kind = "base", ramp = "concrete", base = "concrete_4" }

--- Broad mottling plus aggregate. opts.wear (0..1) scales how beaten it looks.
function concrete.fill(surface, rng_stream, opts)
  opts = opts or {}
  local area = P.area(surface, opts.area)
  local mask = P.mask(surface, opts)
  local wear = opts.wear or 0.5
  local base = palette.resolve(opts.base or concrete.base)

  P.rect_fill(surface, area.x, area.y, area.w, area.h, base, { mask = mask })

  -- Broad patches: one step darker, one step lighter. Big and few, so the
  -- surface reads as poured concrete rather than noise.
  -- Few and large: a big blob has less edge per pixel than several small ones,
  -- which is the difference between "poured concrete" and "static".
  local dark = rng_stream:branch("patch_dark")
  for _ = 1, 2 + rng_stream:range(0, 1) do
    P.cluster(surface,
      dark:range(area.x, area.x + area.w - 1), dark:range(area.y, area.y + area.h - 1),
      dark:range(8, 16), palette.shift(base, -1), dark, { mask = mask })
  end
  local light = rng_stream:branch("patch_light")
  for _ = 1, 1 + rng_stream:range(0, 1) do
    P.cluster(surface,
      light:range(area.x, area.x + area.w - 1), light:range(area.y, area.y + area.h - 1),
      light:range(4, 9), palette.shift(base, 1), light, { mask = mask })
  end

  -- Aggregate: pairs of pixels, never singles.
  local grit = rng_stream:branch("aggregate")
  P.speckle(surface, 1 + math.floor(2 * wear), palette.shift(base, -1), grit,
    { area = area, mask = opts.mask, max_size = 2 })
  if wear > 0.7 then
    P.speckle(surface, 1, palette.shift(base, -2), grit, { area = area, mask = opts.mask, max_size = 2 })
  end
  P.speckle(surface, 1, palette.shift(base, 1), grit, { area = area, mask = opts.mask, max_size = 2 })
end

--- A slab joint. Cut on the tile boundary so a tiled floor shows a 16px grid.
-- The groove itself is dark; the light hits the far wall of the cut, so the
-- lit lip sits one pixel down/right of the groove and is dithered, not solid.
-- @param axis "h" or "v"
function concrete.groove(surface, axis, offset, rng_stream, opts)
  opts = opts or {}
  local shade = opts.color or "concrete_2"
  local len = axis == "h" and surface.width or surface.height
  local jitter = rng_stream:branch("groove_" .. axis .. offset)
  local i = 0
  while i < len do
    local x = axis == "h" and i or offset
    local y = axis == "h" and offset or i
    -- Occasional deeper pixel pairs keep the joint from reading as a ruler line.
    if jitter:chance(0.18) then
      local deep = palette.shift(shade, -1)
      surface:set(x, y, deep)
      surface:set(axis == "h" and i + 1 or offset, axis == "h" and offset or i + 1, deep)
      i = i + 2
    else
      surface:set(x, y, shade)
      i = i + 1
    end
  end
  -- Lit lip on the far side of the cut (light comes from the upper left), as
  -- broken runs so the edge chips instead of dotting.
  local lip_offset = offset + 1
  local last = (axis == "h" and surface.width or surface.height) - 1
  P.broken_run(surface, axis, lip_offset, 0, last, jitter,
    { delta = 1, run = opts.run or { 3, 6 }, gap = opts.gap or { 2, 4 } })
end

--- A hairline crack: a short orthogonal/diagonal walk, one pixel wide, which
-- reads as a run rather than as isolated noise.
function concrete.crack(surface, x, y, length, rng_stream, opts)
  opts = opts or {}
  local color = opts.color or "concrete_2"
  local mask = opts.mask
  local dirs = { { 1, 0 }, { 1, 1 }, { 0, 1 }, { 1, -1 } }
  local d = rng_stream:pick(dirs)
  local cx, cy = x, y
  for i = 1, length do
    P.pixel(surface, cx, cy, color, mask)
    if i % 3 == 0 and rng_stream:chance(0.5) then d = rng_stream:pick(dirs) end
    cx, cy = cx + d[1], cy + d[2]
  end
end

--- Spalling: a chunk broken out of the surface. It is a shallow depression, so
--- it is lit like one -- dark floor, exposed aggregate catching light on the
--- lower-right inner wall, and a hard shadow under its upper-left lip.
function concrete.spall(surface, x, y, size, rng_stream, opts)
  opts = opts or {}
  local mask = opts.mask
  local base = surface:get(x, y)
  if base == palette.TRANSPARENT then base = palette.resolve(concrete.base) end
  local floor_color = palette.shift(base, -2)
  local blob = P.cluster(surface, x, y, size, floor_color, rng_stream, { mask = mask })
  local low
  for _, p in ipairs(blob) do
    if not low or p[2] > low[2] or (p[2] == low[2] and p[1] > low[1]) then low = p end
  end
  if low then
    P.pixel(surface, low[1], low[2], palette.shift(base, 1), mask)
    P.pixel(surface, low[1] - 1, low[2], palette.shift(base, 1), mask)
  end
  return blob
end

return concrete
