-- materials/earth.lua -- bare soil: the default ground of the surface world.
--
-- Grammar: a mid base, broad low-contrast patches of damp and dry soil, small
-- stones (always a lit pixel with its own shadow, never a lone dot), and dry
-- clods. Nothing here may key to a tile edge -- ground tiles are laid in
-- fields and any edge-anchored mark turns into a visible 16px grid.

local P = require("pixel_utils")
local palette = require("palette")

local earth = { name = "earth", kind = "base", ramp = "earth", base = "earth_3" }

--- opts.wear (0..1) how churned the ground is; opts.base ramp step.
function earth.fill(surface, rng_stream, opts)
  opts = opts or {}
  local area = P.area(surface, opts.area)
  local mask = P.mask(surface, opts)
  local base = palette.resolve(opts.base or earth.base)
  local wear = opts.wear or 0.5

  P.rect_fill(surface, area.x, area.y, area.w, area.h, base, { mask = mask })

  -- Damp hollows and dried crests. Few and large: soil reads by its patches,
  -- not by its grain.
  local damp = rng_stream:branch("earth_damp")
  for _ = 1, 1 + damp:range(0, 1) do
    P.cluster(surface,
      damp:range(area.x, area.x + area.w - 1), damp:range(area.y, area.y + area.h - 1),
      damp:range(12, 22), palette.shift(base, -1), damp, { mask = mask })
  end
  local dry = rng_stream:branch("earth_dry")
  if dry:chance(0.7) then
    P.cluster(surface,
      dry:range(area.x, area.x + area.w - 1), dry:range(area.y, area.y + area.h - 1),
      dry:range(8, 14), palette.shift(base, 1), dry, { mask = mask })
  end

  -- Clods: two-pixel specks, the smallest mark the style allows, and only on
  -- ground that has actually been churned up.
  if wear > 0.6 then
    local clod = rng_stream:branch("earth_clod")
    P.speckle(surface, 1, palette.shift(base, -2), clod,
      { area = area, mask = opts.mask, max_size = 2 })
  end
end

--- Stones. A stone is a lit cap plus its own shadow, which is what separates a
--- stone from a stray pixel at this size.
function earth.stones(surface, count, rng_stream, opts)
  opts = opts or {}
  local area = P.area(surface, opts.area)
  local mask = P.mask(surface, opts)
  local cap = palette.resolve(opts.color or "concrete_4")
  for _ = 1, count do
    local x = rng_stream:range(area.x, area.x + area.w - 1)
    local y = rng_stream:range(area.y, area.y + area.h - 1)
    local wide = rng_stream:chance(0.5)
    P.pixel(surface, x, y, cap, mask)
    P.pixel(surface, x + (wide and 1 or 0), y + (wide and 0 or 1), palette.shift(cap, -1), mask)
    -- cast shadow down-right, per the fixed key light
    P.pixel(surface, x + 1, y + 1, palette.resolve(opts.shadow or "earth_2"), mask)
  end
end

return earth
