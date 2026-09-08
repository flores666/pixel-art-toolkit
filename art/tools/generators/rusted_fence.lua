-- generators/rusted_fence.lua -- 16x16 seamless sheet-metal barrier.
--
-- The cheap fence that surrounds every yard, depot and substation in this
-- world: thin sheet bolted to a light steel frame, half of it corroded
-- through. What makes a tile of it read as a FENCE rather than as a patch of
-- corrugated texture is the frame and the panelling, so this generator is
-- mostly about those:
--
--   * a post on a minority of tiles -- an upright member standing in front of
--     the sheet, with its own faces and its own cast shadow. Laid in a run,
--     posts at irregular intervals are the single strongest fence cue there
--     is, and no amount of corrugation substitutes for one;
--   * a rail across every tile, bolted THROUGH the post where the two meet,
--     because a rail that passes behind the post is not attached to anything;
--   * panelling: sheets are of a kind, and a run of fence is made of several.
--     A tile is either corrugated (most of them) or a flat sheet, and it may
--     carry the butt seam where its neighbour panel starts. That variation is
--     what breaks the endless-texture read;
--   * damage that means something: a dent between two folds, and holes rusted
--     clean through, low down where the water sits.
--
-- The corrugation pitch divides 16 exactly and its phase is fixed, so the fold
-- profile runs unbroken from one corrugated tile into the next.

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

-- Divides the tile exactly, so the fold profile must not break at a seam. A
-- pitch of 8 puts two folds in a tile rather than four: at four, the vertical
-- fold rhythm and the horizontal rail cut the sheet into a lattice of small
-- rectangles, and the tile reads as a grid of panels instead of as a fence.
local PITCH = 8
local RAIL_Y = 5   -- the frame sits at the same height in every tile, or a run
                   -- of fence has no frame

function gen.build(rng_stream, opts)
  opts = opts or {}
  local s = P.new(gen.size.w, gen.size.h, { wrap = true })
  local base = opts.base or "metal_4"

  -- material
  metal.fill(s, rng_stream, { base = base, grain = 0.2 })

  -- structure: what kind of sheet this panel is
  local panel = rng_stream:branch("panel")
  local corrugated = panel:chance(0.72)
  if corrugated then
    metal.corrugate(s, panel, { pitch = PITCH })
  end

  -- structure: the butt seam where the next panel along starts. Off the tile
  -- edge, so it never coincides with the tile grid.
  if panel:chance(0.30) then
    metal.seam(s, "v", panel:range(3, 12), panel, { color = "metal_1" })
  end

  -- structure: the rail behind the sheet. It shows as a lit step where the
  -- sheet is drawn tight against it and a solid shadow underneath, and the lit
  -- edge is BROKEN: a continuous bright line across every tile lays a rail
  -- out as a printed rule, which is the same defect as a printed grid. Broken,
  -- it reads as a weathered member -- and the bolt at the post (below) is what
  -- says the sheet is actually fixed to it.
  P.broken_run(s, "h", RAIL_Y, 0, gen.size.w - 1, rng_stream:branch("rail"),
    { delta = 1, run = { 4, 7 }, gap = { 2, 3 } })
  P.rect_fill_shift(s, 0, RAIL_Y + 1, gen.size.w, 1, -1)

  -- structure: the post
  local post = rng_stream:branch("post")
  local post_x
  if post:chance(0.30) then
    post_x = post:range(0, 15)
    metal.post(s, post_x, post, { base = base })
    -- the bolt that fixes the rail to the post: the one place a fixing belongs
    metal.rivet(s, post_x, RAIL_Y, { base = base, cast_shadow = false })
  end

  -- structure: a dent, pushed in between two folds
  if rng_stream:chance(0.40) then
    local dent = rng_stream:branch("dent")
    local x = dent:range(0, 15)
    local y = dent:range(8, 12)
    P.rect_fill_shift(s, x, y, dent:range(2, 3), 2, -1)
    P.rect_fill_shift(s, x, y + 2, dent:range(2, 3), 1, 1)
  end

  -- wear: heavy corrosion, low down where the water sits and along the rail,
  -- which is where it collects and stays wet
  rust.fill(s, rng_stream, {
    coverage = rng_stream:weighted {
      { value = 0.06, weight = 2 },
      { value = 0.14, weight = 3 },
      { value = 0.26, weight = 2 },
    },
    streaks = true,
    mask = P.ramp_mask("metal"),
    bias = function(_, y)
      if y >= 11 then return 1.0 end
      if y == RAIL_Y + 1 or y == RAIL_Y + 2 then return 0.7 end
      return 0.25
    end,
  })

  -- wear: rusted clean through. A hole is the strongest single statement this
  -- tile can make about the state of the fence, so it is worth drawing
  -- properly: a torn opening with the corroded sheet edge lit on its
  -- upper-left rim, low down where the sheet has been sitting in the wet.
  if rng_stream:chance(0.24) then
    local hole = rng_stream:branch("hole")
    local x, y = hole:range(0, 15), hole:range(9, 13)
    local blob = P.cluster(s, x, y, hole:range(4, 8), "rust_1", hole, { spread = 0.5 })
    for _, p in ipairs(blob) do s:set(p[1], p[2], palette.TRANSPARENT) end
    -- the torn edge: corroded metal, catching the light on the rim above it
    for _, p in ipairs(blob) do
      local above = s:get(p[1], p[2] - 1)
      if above ~= palette.TRANSPARENT then s:set(p[1], p[2] - 1, "rust_2") end
      local left = s:get(p[1] - 1, p[2])
      if left ~= palette.TRANSPARENT and hole:chance(0.5) then s:set(p[1] - 1, p[2], "rust_1") end
    end
  end

  dirt.fill(s, rng_stream, { coverage = 0.10, bias = function(_, y) return y >= 12 and 0.9 or 0.1 end })

  -- cleanup
  P.despeckle(s)
  return s
end

return gen
