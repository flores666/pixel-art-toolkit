-- materials/grass.lua -- dry, neglected vegetation.
--
-- This is not a lawn. The field is last year's dead straw with olive tufts
-- pushing through it and bare soil showing where nothing took. Green is used
-- sparingly and never above grass_5; the brightest pixels in a grass tile are
-- dry straw catching the light, which is what keeps the world reading as
-- abandoned rather than pastoral.
--
-- Grammar: a straw field, tufts (clusters with a lit crown), blades (short
-- runs), and bare patches. `tufts` doubles as the overlay entry point for
-- vegetation coming through asphalt or rubble.

local P = require("pixel_utils")
local palette = require("palette")

local grass = { name = "grass", kind = "base", ramp = "straw", base = "straw_2" }

--- A dry field. opts.green (0..1) how much has come back this year,
--- opts.bare (0..1) how much soil shows through.
function grass.fill(surface, rng_stream, opts)
  opts = opts or {}
  local area = P.area(surface, opts.area)
  local mask = P.mask(surface, opts)
  local base = palette.resolve(opts.base or grass.base)
  local green = opts.green or 0.5
  local bare = opts.bare or 0.3

  P.rect_fill(surface, area.x, area.y, area.w, area.h, base, { mask = mask })

  -- Two scales, and only two. Broad drifts of matted and shadowed growth are
  -- drawn LARGE and lobed (high spread) so they read as areas rather than as
  -- spots; everything finer is a stroke, below.
  local drift = rng_stream:branch("grass_drift")
  for _ = 1, 1 + drift:range(0, 1) do
    P.cluster(surface,
      drift:range(area.x, area.x + area.w - 1), drift:range(area.y, area.y + area.h - 1),
      drift:range(22, 34), palette.shift(base, 1), drift, { mask = mask, spread = 1.3 })
  end
  P.cluster(surface,
    drift:range(area.x, area.x + area.w - 1), drift:range(area.y, area.y + area.h - 1),
    drift:range(12, 20), palette.shift(base, -1), drift, { mask = mask, spread = 1.3 })

  -- Soil showing through where nothing took.
  if bare > 0 and rng_stream:chance(bare) then
    local soil = rng_stream:branch("grass_bare")
    P.cluster(surface,
      soil:range(area.x, area.x + area.w - 1), soil:range(area.y, area.y + area.h - 1),
      soil:range(8, 16), "earth_3", soil, { mask = mask, spread = 1.0 })
  end

  -- Strokes. Grass reads by direction, not by blobs: a field of round patches
  -- looks like camouflage, and that is exactly what the first draft of this
  -- material produced. Dead stalks dominate; olive is the minority report.
  local stroke = rng_stream:branch("grass_stroke")
  local clumps = 2 + stroke:range(0, 1)
  for _ = 1, clumps do
    local cx = stroke:range(area.x, area.x + area.w - 1)
    local cy = stroke:range(area.y, area.y + area.h - 1)
    grass.tufts(surface, 1, stroke,
      -- olive against a dead field, or bleached stalks against it: either way
      -- the stroke has to separate from the base, or the tile reads as sand
      { area = area, mask = opts.mask, at = { cx, cy },
        color = stroke:float() < green and "grass_3" or "straw_4" })
  end
end

--- A tuft: three to five short stalks leaning out of one point, the tallest
--- catching the light at its tip. This is the overlay entry point too -- use it
--- to push weeds through a crack in asphalt or up the side of a ruin.
function grass.tufts(surface, count, rng_stream, opts)
  opts = opts or {}
  local area = P.area(surface, opts.area)
  local mask = P.mask(surface, opts)
  local body = palette.resolve(opts.color or "grass_3")
  for _ = 1, count do
    local x = opts.at and opts.at[1] or rng_stream:range(area.x, area.x + area.w - 1)
    local y = opts.at and opts.at[2] or rng_stream:range(area.y, area.y + area.h - 1)
    local stalks = rng_stream:range(3, 5)
    local tallest, tallest_x
    for i = 1, stalks do
      local sx = x + rng_stream:range(-1, 1)
      local sy = y + rng_stream:range(0, 1)
      local len = rng_stream:range(2, 3)
      for k = 0, len - 1 do
        -- lean: stalks bend away from vertical as they rise
        local lean = k > 0 and rng_stream:range(0, 1) * (i % 2 == 0 and 1 or -1) or 0
        P.pixel(surface, sx + lean, sy - k, body, mask)
      end
      if not tallest or sy - len < tallest then tallest, tallest_x = sy - len, sx end
    end
    if tallest then
      -- the crown takes the light, per the fixed upper-left key
      P.pixel(surface, tallest_x, tallest + 1, palette.shift(body, 1), mask)
    end
  end
end

--- A single dry stalk: a short run with a bleached tip. Always 2+ pixels.
function grass.blade(surface, x, y, length, rng_stream, opts)
  opts = opts or {}
  local mask = opts.mask
  local color = palette.resolve(opts.color or "straw_4")
  length = math.max(2, length)
  for i = 0, length - 1 do
    P.pixel(surface, x + (i > 1 and rng_stream:chance(0.4) and 1 or 0), y - i, color, mask)
  end
  P.pixel(surface, x, y - length, palette.shift(color, 1), mask)
end

return grass
