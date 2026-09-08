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

--- An upright structural member: a post, standing in front of the sheet it
--- carries. Three pixels wide, full height, with its own lit and shaded faces
--- and a cast shadow on the sheet to its right.
--
-- Written as explicit ramp steps rather than as ramp shifts, because a post is
-- a separate PIECE of steel and not a highlight on the one behind it: it has
-- to hold its own values whatever the sheet does under it (corrugated, flat,
-- already corroded), and shifting whatever happens to be there would let the
-- fold pattern show straight through the member.
function metal.post(surface, x, rng_stream, opts)
  opts = opts or {}
  local area = P.area(surface, opts.area)
  local width = opts.width or 3
  local base = opts.base or metal.base
  local ramp, index = palette.slot(palette.resolve(base))
  local y0, y1 = area.y, area.y + area.h - 1
  for i = 0, width - 1 do
    -- lit left face, body, shaded right face
    -- a full two steps either side of the body: a member three pixels wide
    -- only reads as a separate piece of steel if its faces clearly separate
    -- from the sheet behind it
    local step = i == 0 and index + 2 or (i == width - 1 and index - 2 or index)
    for y = y0, y1 do
      surface:set(x + i, y, palette.step(ramp, step))
    end
  end
  -- the shadow the post throws onto the sheet, per the fixed upper-left key
  for y = y0, y1 do
    local c = surface:get(x + width, y)
    if c ~= palette.TRANSPARENT then surface:set(x + width, y, palette.shift(c, -1)) end
  end
  return x, width
end

--- Corrugation: the profile of a cheap sheet-metal fence. Every `pitch`
--- columns, a shaded valley -- one continuous read across the tile, and it
--- wraps.
--
-- `opts.crest` adds the lit crest of the next fold beside each valley. It is
-- OFF by default, and that is a considered default rather than a saving: with
-- both faces drawn, a pitch that fits a 16px tile puts a light and a dark
-- column in every four, and the fold pattern then occupies the whole tile and
-- most of its busyness budget. There is nothing left for the frame, the
-- panelling or the damage to read against, so the sheet stops being a fence
-- and becomes a texture -- which is exactly what it did. A shaded valley alone
-- still reads as a fold, and it leaves the tile room to say what it is.
function metal.corrugate(surface, rng_stream, opts)
  opts = opts or {}
  local area = P.area(surface, opts.area)
  local pitch = opts.pitch or 4
  local phase = opts.phase or 0
  for x = area.x + phase, area.x + area.w - 1, pitch do
    for y = area.y, area.y + area.h - 1 do
      local c = surface:get(x, y)
      if c ~= palette.TRANSPARENT then surface:set(x, y, palette.shift(c, -1)) end
      if opts.crest then
        local lit = surface:get(x + 1, y)
        if lit ~= palette.TRANSPARENT then surface:set(x + 1, y, palette.shift(lit, 1)) end
      end
    end
  end
end

return metal
