-- generators/rusted_fence.lua -- 16x16 seamless corrugated metal barrier.
--
-- The cheap sheet fence that surrounds every yard, depot and substation in this
-- world. The corrugation pitch divides 16 exactly, so the profile runs
-- unbroken across a whole fence line; only the corrosion, the dents and the
-- occasional rusted-through hole vary per tile.

local P = require("pixel_utils")
local palette = require("palette")
local materials = require("materials")

local metal, rust, dirt = materials.metal, materials.rust, materials.dirt

local gen = {
  name = "rusted_fence",
  title = "Rusted fence 16x16",
  size = { w = 16, h = 16 },
  tileable = true,
  surface = "structure",
}

local PITCH = 4   -- divides the tile exactly: the profile must not break at a seam

function gen.build(rng_stream, opts)
  opts = opts or {}
  local s = P.new(gen.size.w, gen.size.h, { wrap = true })

  -- material
  metal.fill(s, rng_stream, { base = opts.base or "metal_4", grain = 0.3 })

  -- structure: the fold profile, then the rail the sheet is bolted to
  metal.corrugate(s, rng_stream, { pitch = PITCH })
  local rail_y = 5
  P.rect_fill_shift(s, 0, rail_y, gen.size.w, 1, 1)
  P.rect_fill_shift(s, 0, rail_y + 1, gen.size.w, 1, -1)

  -- structure: a dent, pushed in between two folds
  if rng_stream:chance(0.45) then
    local dent = rng_stream:branch("dent")
    local x = dent:range(0, 15)
    local y = dent:range(8, 12)
    P.rect_fill_shift(s, x, y, dent:range(2, 3), 2, -1)
    P.rect_fill_shift(s, x, y + 2, dent:range(2, 3), 1, 1)
  end

  -- wear: heavy corrosion, low down where the water sits
  rust.fill(s, rng_stream, {
    coverage = rng_stream:weighted {
      { value = 0.10, weight = 2 },
      { value = 0.22, weight = 3 },
      { value = 0.38, weight = 2 },
    },
    streaks = true,
    mask = P.ramp_mask("metal"),
    bias = function(_, y) return y >= 10 and 1.0 or 0.35 end,
  })

  -- wear: rusted clean through, occasionally
  if rng_stream:chance(0.20) then
    local hole = rng_stream:branch("hole")
    local x, y = hole:range(0, 15), hole:range(9, 14)
    local blob = P.cluster(s, x, y, hole:range(2, 4), "rust_1", hole, {})
    for _, p in ipairs(blob) do s:set(p[1], p[2], palette.TRANSPARENT) end
    -- the torn edge catches light on its upper-left
    for _, p in ipairs(blob) do
      local above = s:get(p[1], p[2] - 1)
      if above ~= palette.TRANSPARENT then s:set(p[1], p[2] - 1, "rust_2") end
    end
  end

  dirt.fill(s, rng_stream, { coverage = 0.10, bias = function(_, y) return y >= 12 and 0.9 or 0.1 end })

  -- cleanup
  P.despeckle(s)
  return s
end

return gen
