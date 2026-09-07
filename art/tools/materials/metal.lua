-- materials/metal.lua -- structural steel: panels, props, bins, rails.
--
-- Grammar: a dark base (the metro's walls are near black), a vertical brushed
-- grain in broken runs, panel seams with a lit lip, rivets, and scratches.

local P = require("pixel_utils")
local palette = require("palette")

local metal = { name = "metal", kind = "base", ramp = "metal", base = "metal_3" }

--- opts.base ramp step, opts.grain (0..1) how brushed the plate looks.
function metal.fill(surface, rng_stream, opts)
  opts = opts or {}
  local area = P.area(surface, opts.area)
  local mask = P.mask(surface, opts)
  local base = palette.resolve(opts.base or metal.base)
  local grain = opts.grain or 0.5

  P.rect_fill(surface, area.x, area.y, area.w, area.h, base, { mask = mask })

  -- Rolled-plate unevenness: a couple of wide, low-contrast patches.
  local plate = rng_stream:branch("plate")
  for _ = 1, 1 + plate:range(0, 1) do
    P.cluster(surface,
      plate:range(area.x, area.x + area.w - 1), plate:range(area.y, area.y + area.h - 1),
      plate:range(8, 14), palette.shift(base, -1), plate, { mask = mask })
  end

  -- Brushed grain: vertical broken runs, one pixel wide but never one pixel long.
  local brush = rng_stream:branch("brush")
  local lines = math.floor(area.w * grain * 0.25)
  for _ = 1, lines do
    local x = brush:range(area.x, area.x + area.w - 1)
    local delta = brush:chance(0.55) and -1 or 1
    P.broken_run(surface, "v", x, area.y, area.y + area.h - 1, brush,
      { delta = delta, run = { 3, 7 }, gap = { 5, 11 }, mask = opts.mask })
  end
end

--- Panel seam. Dark cut with the lit lip below/right of it, matching the
-- upper-left key light. axis is "h" or "v".
function metal.seam(surface, axis, offset, rng_stream, opts)
  opts = opts or {}
  local len = axis == "h" and surface.width or surface.height
  local shade = opts.color or "metal_1"
  for i = 0, len - 1 do
    surface:set(axis == "h" and i or offset, axis == "h" and offset or i, shade)
  end
  local lip = rng_stream:branch("seam_lip_" .. axis .. offset)
  P.broken_run(surface, axis, offset + 1, 0, len - 1, lip,
    { delta = 1, run = opts.run or { 4, 7 }, gap = opts.gap or { 2, 4 } })
end

--- A 2x2 rivet: catch-light on the upper-left pixel, shadow on the lower-right,
-- plus a one-pixel cast shadow that stays attached to the cluster.
function metal.rivet(surface, x, y, opts)
  opts = opts or {}
  local body = surface:get(x, y)
  if body == palette.TRANSPARENT then body = palette.resolve(opts.base or metal.base) end
  surface:set(x, y, palette.shift(body, 2))
  surface:set(x + 1, y, palette.shift(body, 1))
  surface:set(x, y + 1, palette.shift(body, 1))
  surface:set(x + 1, y + 1, palette.shift(body, -1))
  if opts.cast_shadow ~= false then
    surface:set(x + 2, y + 1, palette.shift(body, -2))
    surface:set(x + 1, y + 2, palette.shift(body, -2))
  end
end

--- A bright scratch: a short run, one pixel wide, always at least three long.
function metal.scratch(surface, x, y, length, rng_stream, opts)
  opts = opts or {}
  local axis = opts.axis or (rng_stream:chance(0.5) and "h" or "v")
  local color = opts.color
  for i = 0, math.max(3, length) - 1 do
    local px = axis == "h" and x + i or x
    local py = axis == "h" and y or y + i
    local c = surface:get(px, py)
    if c ~= palette.TRANSPARENT then
      P.pixel(surface, px, py, color or palette.shift(c, opts.delta or 1), opts.mask)
    end
  end
end

--- Corrugation: the profile of a cheap sheet-metal fence. Every `pitch`
--- columns, a shaded valley with the lit crest of the next fold beside it --
--- one continuous read across the tile, and it wraps.
function metal.corrugate(surface, rng_stream, opts)
  opts = opts or {}
  local area = P.area(surface, opts.area)
  local pitch = opts.pitch or 4
  local phase = opts.phase or 0
  for x = area.x + phase, area.x + area.w - 1, pitch do
    for y = area.y, area.y + area.h - 1 do
      local c = surface:get(x, y)
      if c ~= palette.TRANSPARENT then surface:set(x, y, palette.shift(c, -1)) end
      local lit = surface:get(x + 1, y)
      if lit ~= palette.TRANSPARENT then surface:set(x + 1, y, palette.shift(lit, 1)) end
    end
  end
end

return metal
