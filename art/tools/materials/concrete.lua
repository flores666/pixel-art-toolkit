-- materials/concrete.lua -- poured concrete, above ground and below.
--
-- Grammar: a mid base, broad low-contrast patches (never a gradient), paired
-- aggregate specks, cast joints, hairline cracks, and spalling where the
-- surface has broken away and left the aggregate showing.

local P = require("pixel_utils")
local palette = require("palette")

local concrete = { name = "concrete", kind = "base", ramp = "concrete", base = "concrete_4" }

--- Broad mottling plus aggregate. opts.wear (0..1) scales how beaten it looks.
---
--- opts.ground says this concrete is a FLOOR, laid in a field, and that
--- changes what it is allowed to do. A wall is exempt from the field
--- discipline and its own cast joints are louder than any weathering, so its
--- staining patch is a full ramp step. A hundred floor tiles carrying a full
--- ramp step of stain is a chequerboard, so on the ground the patch is drawn
--- in the near-value neighbour instead (metal_5 sits 4 luminance under
--- concrete_4 and is just as neutral) and the aggregate is left out entirely.
--- Same material, same grammar, one honest difference of degree.
function concrete.fill(surface, rng_stream, opts)
  opts = opts or {}
  local area = P.area(surface, opts.area)
  local mask = P.mask(surface, opts)
  local wear = opts.wear or 0.5
  local ground = opts.ground or false
  local base = palette.resolve(opts.base or concrete.base)

  P.rect_fill(surface, area.x, area.y, area.w, area.h, base, { mask = mask })

  -- ONE broad weathering patch, drawn as an area. Concrete varies by staining,
  -- not by grain: three or four small patches plus a scatter of aggregate
  -- pairs is five or six marks on every cell, and a wall built out of those
  -- reads as static behind whatever else is on it. The patch is a full ramp
  -- step -- unlike the ground tiles, a wall is ALLOWED contrast, because it is
  -- exempt from the field discipline and its own construction lines are
  -- stronger than anything the weathering does.
  local stain = rng_stream:branch("patch_dark")
  local field = area.w * area.h
  P.cluster(surface,
    stain:range(area.x, area.x + area.w - 1), stain:range(area.y, area.y + area.h - 1),
    stain:range(math.floor(field * 0.12), math.floor(field * 0.20)),
    ground and palette.resolve("metal_5") or palette.shift(base, -1),
    stain, { mask = mask, spread = 1.1 })

  -- Aggregate showing through where the surface has worn thin: ONE pair of
  -- pixels, and only on a beaten wall.
  if wear > 0.55 and not ground then
    local grit = rng_stream:branch("aggregate")
    P.speckle(surface, 1, palette.shift(base, 1), grit,
      { area = area, mask = opts.mask, max_size = 2 })
  end
end

--- A slab joint: the cast line between two courses. The groove is dark; the
-- light hits the far wall of the cut, so the lit lip sits one pixel down/right
-- of it and is drawn as broken runs rather than a solid line.
--
-- On a RUIN the joint is the wall's construction logic and also its main piece
-- of decay, so it is allowed to wander a pixel off its row and to break
-- outright where a chunk of the arris has gone. `opts.decay` (0..1) says how
-- much: 0 is a clean cast line, 0.5 loses a few pixels of it and steps off the
-- row here and there.
--
-- The invariant that makes that safe to tile: the joint is pinned to `offset`
-- at BOTH ends of its run. A wall tile laid beside another must meet its
-- neighbour's joint, so the line may do what it likes in the middle and
-- nowhere else. Break that and a wall run reads as a row of broken staples.
-- @param axis "h" or "v"
function concrete.groove(surface, axis, offset, rng_stream, opts)
  opts = opts or {}
  local shade = palette.resolve(opts.color or "concrete_2")
  local len = axis == "h" and surface.width or surface.height
  local decay = opts.decay or 0
  local jitter = rng_stream:branch("groove_" .. axis .. offset)

  local function put(i, off, color)
    if axis == "h" then surface:set(i, off, color) else surface:set(off, i, color) end
  end

  local drift = 0            -- how far off `offset` the line currently runs
  local i = 0
  local gap_left = 0
  while i < len do
    -- pinned at both ends, whatever happens in between
    local pinned = i == 0 or i >= len - 2
    if pinned then drift = 0 end
    if gap_left > 0 then
      gap_left = gap_left - 1      -- the arris is gone here: no line at all
    elseif not pinned and jitter:chance(decay * 0.10) then
      gap_left = jitter:range(1, 2)
    else
      -- Occasional deeper pixel pairs keep the joint from reading as a ruler.
      put(i, offset + drift, jitter:chance(0.18) and palette.shift(shade, -1) or shade)
    end
    if not pinned and jitter:chance(decay * 0.14) then
      drift = drift == 0 and (jitter:chance(0.5) and 1 or -1) or 0
    end
    i = i + 1
  end

  -- Lit lip on the far side of the cut (light comes from the upper left), as
  -- broken runs so the edge chips instead of dotting.
  P.broken_run(surface, axis, offset + 1, 0, len - 1, jitter,
    { delta = 1, run = opts.run or { 3, 6 }, gap = opts.gap or { 2, 4 } })
end

--- A hairline crack: straight segments with 45-degree kinks, one pixel wide.
--- Concrete cracks off a corner or a spall and runs, so this is the same
--- fracture geometry the road uses; only the colour and the extent differ.
--- @return the pixels it drew
function concrete.crack(surface, x, y, length, rng_stream, opts)
  opts = opts or {}
  return P.fracture(surface, x, y, length, opts.color or "concrete_2", rng_stream, {
    mask = opts.mask,
    heading = opts.heading,
    segment = opts.segment or { 3, 5 },
    branches = opts.branches or 1,
    branch_length = { 2, 4 },
  })
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
