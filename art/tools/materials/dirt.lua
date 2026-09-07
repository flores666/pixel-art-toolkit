-- materials/dirt.lua -- grime, dust and soot. An OVERLAY.
--
-- Grammar: dirt gathers in corners, along the foot of things and under
-- overhangs. It is always darker than what it sits on, always clustered, and
-- its dithered fringe is at least two pixels thick so it never becomes dust.

local P = require("pixel_utils")
local palette = require("palette")

local dirt = { name = "dirt", kind = "overlay", ramp = "dirt" }

--- opts.coverage 0..1, opts.bias(x, y) -> 0..1 where grime collects,
--- opts.fringe  boolean: add a dithered edge to each patch (needs 2+ rows).
function dirt.fill(surface, rng_stream, opts)
  opts = opts or {}
  local area = P.area(surface, opts.area)
  local mask = P.mask(surface, opts)
  local coverage = opts.coverage or 0.2
  if coverage <= 0 then return end

  local body = palette.resolve(opts.color or "dirt_2")
  local edge = palette.resolve(opts.edge or "dirt_3")
  local r = rng_stream:branch("dirt_site")
  local exact = area.w * area.h * coverage / 26
  local patches = math.floor(exact)
  if r:float() < exact - patches then patches = patches + 1 end

  for _ = 1, patches do
    local x, y
    for _ = 1, 8 do
      local cx = r:range(area.x, area.x + area.w - 1)
      local cy = r:range(area.y, area.y + area.h - 1)
      if not opts.bias or r:float() < opts.bias(cx, cy) then x, y = cx, cy break end
    end
    if x then
      local blob = P.cluster(surface, x, y, r:range(4, 9), body, r, { mask = mask })
      -- Softer outer pixels, still part of the same cluster.
      for _, p in ipairs(blob) do
        if r:chance(0.35) then surface:set(p[1], p[2], edge) end
      end
    end
  end
end

--- A grime band, e.g. where a wall meets the floor. Solid core, dithered
--- fringe on the two rows above it so the transition is controlled, not a fade.
function dirt.band(surface, y, height, rng_stream, opts)
  opts = opts or {}
  local color = palette.resolve(opts.color or "dirt_2")
  local a = P.area(surface, opts.area)
  P.dither(surface, color, opts.density or 2,
    { area = { x = a.x, y = y, w = a.w, h = height }, mask = opts.mask })
  local speck = rng_stream:branch("grime")
  P.speckle(surface, 2, palette.resolve(opts.edge or "dirt_3"), speck,
    { area = { x = a.x, y = y, w = a.w, h = height }, mask = opts.mask })
end

return dirt
