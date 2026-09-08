-- materials/rust.lua -- corrosion. An OVERLAY: it eats into whatever is there.
--
-- Grammar: a patch is a blob with a dark rim and a lighter core (that is what
-- makes it read as pitted metal rather than a paint splash), plus optional
-- streaks running down from it, because water carries rust downwards.

local P = require("pixel_utils")
local palette = require("palette")

local rust = { name = "rust", kind = "overlay", ramp = "rust" }

--- Accept/reject helper: opts.bias(x, y) -> 0..1 weights where wear collects
-- (seams, corners, the bottom of a wall).
local function site(area, rng_stream, bias)
  for _ = 1, 8 do
    local x = rng_stream:range(area.x, area.x + area.w - 1)
    local y = rng_stream:range(area.y, area.y + area.h - 1)
    if not bias or rng_stream:float() < bias(x, y) then return x, y end
  end
  return nil
end

--- opts.coverage 0..1 (roughly, how much of the area corrodes)
--- opts.streaks  boolean, drips below each patch
function rust.fill(surface, rng_stream, opts)
  opts = opts or {}
  local area = P.area(surface, opts.area)
  local mask = P.mask(surface, opts)
  local coverage = opts.coverage or 0.25
  if coverage <= 0 then return end

  local rim = palette.resolve(opts.rim or "rust_1")
  local core = palette.resolve(opts.core or "rust_2")
  local spark = palette.resolve(opts.spark or "rust_3")

  -- One patch per ~40 covered pixels: ochre is by far the loudest thing in
  -- the palette, so a little of it goes a long way against dark metal. The
  -- count is fractional and NOT floored at one -- a low coverage has to mean
  -- "most tiles have no rust at all", or every tile in a wall ends up flecked.
  local site_rng = rng_stream:branch("rust_site")
  local exact = area.w * area.h * coverage / 40
  local patches = math.floor(exact)
  if site_rng:float() < exact - patches then patches = patches + 1 end
  for _ = 1, patches do
    local x, y = site(area, site_rng, opts.bias)
    if x then
      -- Lobed, not radial: P.cluster grown tight from a seed makes a diamond
      -- or a plus at these sizes, and a plus reads as a printed symbol rather
      -- than as corrosion eating into a surface.
      local blob = P.cluster(surface, x, y, site_rng:range(5, 10), rim, site_rng,
        { mask = mask, spread = 0.9 })
      -- Core = the eroded interior of the blob: painted pixels surrounded on at
      -- least three sides by rim. At 16px a patch is too small for a strict
      -- 4-of-4 erosion, and three sides still leaves a rim all the way round.
      local inside = {}
      for _, p in ipairs(blob) do
        local n = 0
        if surface:get(p[1] + 1, p[2]) == rim then n = n + 1 end
        if surface:get(p[1] - 1, p[2]) == rim then n = n + 1 end
        if surface:get(p[1], p[2] + 1) == rim then n = n + 1 end
        if surface:get(p[1], p[2] - 1) == rim then n = n + 1 end
        if n >= 3 then inside[#inside + 1] = p end
      end
      for _, p in ipairs(inside) do surface:set(p[1], p[2], core) end
      -- Two catch-light pixels on the upper-left of the patch, kept adjacent.
      if #inside > 1 and site_rng:chance(0.35) then
        local p = inside[1]
        surface:set(p[1], p[2], spark)
        surface:set(p[1] + 1, p[2], spark)
      end
      if opts.streaks and site_rng:chance(0.5) then
        rust.streak(surface, x, y + 1, site_rng:range(2, 5), site_rng, { mask = mask })
      end
    end
  end
end

--- Exposed reinforcement: a straight corroded bar, lit along the edge facing
--- the key light and staining the surface below it.
--
-- By the time you can see the rebar in a panel wall it is not steel any more,
-- which is why this lives in the corrosion material rather than in concrete.
-- It is drawn as a RUN, never as a dotted line: a bar reads by being straight
-- and continuous, and it is the one mark in a ruin wall that says the wall is
-- structural rather than just old.
-- @param axis "h" or "v"
function rust.bar(surface, x, y, length, axis, rng_stream, opts)
  opts = opts or {}
  local mask = opts.mask
  local body = palette.resolve(opts.color or "rust_2")
  local lit = palette.shift(body, 1)
  length = math.max(3, length)
  for i = 0, length - 1 do
    local px = axis == "h" and x + i or x
    local py = axis == "h" and y or y + i
    P.pixel(surface, px, py, body, mask)
    -- the light comes from the upper left: a horizontal bar is lit on top, a
    -- vertical one down its left side
    if axis == "h" then
      P.pixel(surface, px, py - 1, lit, mask)
    else
      P.pixel(surface, px - 1, py, lit, mask)
    end
  end
  -- what has run off it since
  if opts.streak ~= false and rng_stream:chance(0.6) then
    local sx = axis == "h" and x + rng_stream:range(0, length - 1) or x
    local sy = axis == "h" and y + 1 or y + length
    rust.streak(surface, sx, sy, rng_stream:range(2, 4), rng_stream, { mask = mask })
  end
end

--- A drip: a two-pixel-wide run downwards, fading to the rim colour.
function rust.streak(surface, x, y, length, rng_stream, opts)
  opts = opts or {}
  local mask = opts.mask
  local color = palette.resolve(opts.color or "rust_1")
  for i = 0, length - 1 do
    P.pixel(surface, x, y + i, color, mask)
    if rng_stream:chance(0.6) then P.pixel(surface, x + 1, y + i, color, mask) end
  end
end

return rust
