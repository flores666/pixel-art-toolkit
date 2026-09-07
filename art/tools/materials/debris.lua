-- materials/debris.lua -- rubble, scrap and fallen matter. An OVERLAY.
--
-- Grammar: chunks. A chunk is a two-to-four pixel cluster with a lit cap and a
-- shadow beneath it, drawn from whichever material it fell off -- concrete
-- from a ruin, wood from a pallet, rust from a machine. Debris collects at the
-- foot of things and in hollows, never evenly across a field.

local P = require("pixel_utils")
local palette = require("palette")

local debris = { name = "debris", kind = "overlay", ramp = "concrete" }

-- What the world is made of, and therefore what it breaks into.
debris.kinds = {
  { value = "concrete_4", weight = 3 },
  { value = "concrete_3", weight = 2 },
  { value = "wood_3",     weight = 2 },
  { value = "rust_2",     weight = 1 },
}

--- opts.coverage 0..1, opts.bias(x, y) -> 0..1, opts.kinds weighted list.
function debris.fill(surface, rng_stream, opts)
  opts = opts or {}
  local area = P.area(surface, opts.area)
  local mask = P.mask(surface, opts)
  local coverage = opts.coverage or 0.15
  if coverage <= 0 then return end

  local r = rng_stream:branch("debris")
  local exact = area.w * area.h * coverage / 24
  local chunks = math.floor(exact)
  if r:float() < exact - chunks then chunks = chunks + 1 end

  for _ = 1, chunks do
    local x, y
    for _ = 1, 8 do
      local cx = r:range(area.x, area.x + area.w - 1)
      local cy = r:range(area.y, area.y + area.h - 1)
      if not opts.bias or r:float() < opts.bias(cx, cy) then x, y = cx, cy break end
    end
    if x then
      local color = palette.resolve(r:weighted(opts.kinds or debris.kinds))
      local blob = P.cluster(surface, x, y, r:range(2, 4), color, r, { mask = mask })
      if #blob > 0 then
        -- lit cap on the upper-left pixel, shadow under the lower-right one
        local top, bottom = blob[1], blob[1]
        for _, b in ipairs(blob) do
          if b[2] < top[2] or (b[2] == top[2] and b[1] < top[1]) then top = b end
          if b[2] > bottom[2] or (b[2] == bottom[2] and b[1] > bottom[1]) then bottom = b end
        end
        P.pixel(surface, top[1], top[2], palette.shift(color, 1), mask)
        P.pixel(surface, bottom[1] + 1, bottom[2] + 1, palette.shift(color, -2), mask)
      end
    end
  end
end

return debris
