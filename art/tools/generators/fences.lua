-- generators/fences.lua -- the modular fence / metal barrier kit.
--
-- The cheap sheet-metal fence that surrounds every yard, depot and substation
-- in this world: thin sheet bolted to a light steel frame, half of it corroded
-- through. What makes a run read as a FENCE rather than as a strip of
-- corrugated texture is the FRAME -- posts at intervals and a rail through
-- them -- so that is what the shared tables here describe, and every piece
-- builds from them.
--
-- Connectivity works exactly as it does for the walls: a piece declares its
-- edge sockets and `validators.check_sockets` proves that pieces presenting
-- the same socket agree on that edge's opaque rows and base material. The
-- fence's cross-section (sheet top, rail rows, sheet bottom) is therefore one
-- table, FENCE, and the rail sits at the same row in every piece -- a run of
-- fence whose rail steps has no frame at all.

local P = require("pixel_utils")
local palette = require("palette")
local materials = require("materials")
local object = require("object")

local metal, rust = materials.metal, materials.rust

-- The cross-section of every fence piece.
local FENCE = {
  top = 3,          -- first row of sheet
  bottom = 14,      -- last row of sheet
  rail = 6,         -- the rail: same row in every piece, or there is no frame
  pitch = 8,        -- corrugation pitch; divides 16 so folds run unbroken
}
-- The returning leaf of a vertical run: the fence going away from the viewer.
-- Fixed columns in every piece that carries one, for exactly the reason the
-- wall kit has a LEG table -- see below.
local LEAF = { x0 = 10, x1 = 13 }

-- DIRECTION-TYPED SOCKETS, and this is the second kit to need the lesson. A
-- left/right edge is a vertical slice through the fence's cross-section
-- (sky, hemmed top, sheet, rail, sheet, ground); a top/bottom edge is a
-- horizontal slice ALONG the run (transparent, leaf, transparent). One socket
-- name for both is a promise no piece can keep, and the validator says so
-- immediately.
local RUN_H = "fence_run_h"
local RUN_V = "fence_run_v"
local OPEN = "open"
local GROUND = "ground"

--- The sheet: a panel of thin corrugated steel with its frame.
local function sheet(s, x0, x1, rng_stream, opts)
  opts = opts or {}
  local top = opts.top or FENCE.top
  local bottom = opts.bottom or FENCE.bottom
  if x1 < x0 then return end
  local h = bottom - top + 1
  P.rect_fill(s, x0, top, x1 - x0 + 1, h, "metal_4")
  metal.fill(s, rng_stream:branch("plate"), {
    base = "metal_4", grain = 0.2,
    area = { x = x0, y = top, w = x1 - x0 + 1, h = h },
    mask = function(x, y) return x >= x0 and x <= x1 and y >= top and y <= bottom end,
  })
  if opts.corrugated ~= false then
    -- Phase is absolute, not per-piece, so the fold profile runs unbroken from
    -- one piece into the next. A per-piece phase is a grid at the piece pitch.
    metal.corrugate(s, rng_stream, {
      pitch = FENCE.pitch, phase = 0,
      area = { x = x0, y = top, w = x1 - x0 + 1, h = h },
    })
  end
  -- the rail behind the sheet: a lit step where the sheet is drawn against it
  -- and a solid shadow underneath. Broken, because a continuous bright line
  -- across every piece lays a rail out as a printed rule.
  P.broken_run(s, "h", FENCE.rail, x0, x1, rng_stream:branch("rail"),
    { delta = 1, run = { 4, 7 }, gap = { 2, 3 } })
  P.rect_fill_shift(s, x0, FENCE.rail + 1, x1 - x0 + 1, 1, -1)
  -- the top edge of the sheet, turned over: a hemmed edge is what stops a
  -- sheet-metal fence reading as a flat cut-out
  P.rect_fill(s, x0, top, x1 - x0 + 1, 1, "metal_5")
end

--- A post: an upright member standing in FRONT of the sheet, with its own
--- faces and its own cast shadow. Laid in a run, posts at intervals are the
--- single strongest fence cue there is.
local function post(s, x, rng_stream, opts)
  opts = opts or {}
  local y0 = opts.y0 or (FENCE.top - 2)
  local y1 = opts.y1 or (FENCE.bottom + 1)
  metal.post(s, x, rng_stream, { base = "metal_4",
    area = { x = 0, y = y0, w = s.width, h = y1 - y0 + 1 } })
  -- the bolt that fixes the rail to the post: the one place a fixing belongs,
  -- and what says the sheet is actually attached to the frame
  metal.rivet(s, x, FENCE.rail, { base = "metal_4", cast_shadow = false })
  return x
end

--- The returning leaf: a vertical run of fence, seen nearly edge-on. Fixed
--- columns so every piece carrying one presents the same top/bottom profile.
local function leaf(s, y0, y1, rng_stream)
  local w = LEAF.x1 - LEAF.x0 + 1
  P.rect_fill(s, LEAF.x0, y0, w, y1 - y0 + 1, "metal_3")
  P.rect_fill(s, LEAF.x0, y0, 1, y1 - y0 + 1, "metal_4")   -- edge into the light
  P.rect_fill(s, LEAF.x1, y0, 1, y1 - y0 + 1, "metal_2")   -- edge away from it
  -- the hem along its length, broken so it reads as weathered steel
  P.broken_run(s, "v", LEAF.x0 + 1, y0, y1, rng_stream:branch("hem"),
    { delta = 1, run = { 3, 6 }, gap = { 2, 4 } })
end

local FENCE_WEAR = {
  ramp = "metal",
  rust = { { value = 0.06, weight = 2 }, { value = 0.16, weight = 3 }, { value = 0.28, weight = 2 } },
  dirt = { { value = 0.06, weight = 2 }, { value = 0.12, weight = 2 } },
  rust_bias = function(_, y)
    -- low down where the water sits, and along the rail where it stays wet
    if y >= FENCE.bottom - 3 then return 1.0 end
    if math.abs(y - FENCE.rail) <= 1 then return 0.7 end
    return 0.25
  end,
  dirt_bias = function(_, y) return y >= FENCE.bottom - 1 and 0.9 or 0.1 end,
}

local set = {}
local function piece(spec)
  set[#set + 1] = {
    name = "fence_" .. spec.name,
    title = spec.title,
    size = { w = spec.w or 16, h = spec.h or 16 },
    tileable = false,
    surface = "structure",
    category = "fence",
    collision = spec.collision or "hull",
    variants = spec.variants or 6,
    sockets = spec.sockets,
    max_interior_holes = spec.max_interior_holes,
    preview_background = spec.background or "dry_grass",
    build = function(rng_stream, opts)
      local s = P.new(spec.w or 16, spec.h or 16)
      spec.draw(s, rng_stream, opts or {})
      return object.finish(s, rng_stream, {
        wear = spec.wear == false and nil or FENCE_WEAR,
        sockets = spec.sockets,
        shadow = spec.shadow,
      })
    end,
  }
end

piece { name = "straight", title = "Fence, straight 16x16", variants = 8,
  sockets = { left = RUN_H, right = RUN_H, top = OPEN, bottom = GROUND },
  draw = function(s, r) sheet(s, 0, 15, r) end }

piece { name = "post_mid", title = "Fence, middle post 16x16", variants = 6,
  -- A post in the middle of a run. Its own piece rather than a random feature
  -- of the straight tile, so a level can space posts deliberately: posts at
  -- irregular but CHOSEN intervals is what a real fence line looks like.
  sockets = { left = RUN_H, right = RUN_H, top = OPEN, bottom = GROUND },
  draw = function(s, r)
    sheet(s, 0, 15, r)
    post(s, 7, r)
  end }

piece { name = "post_end", title = "Fence, end post 16x16", variants = 6,
  -- The run stops. The post is heavier than a middle post and the sheet ends
  -- against it, which is how a real fence terminates -- the last post carries
  -- the tension of the whole run.
  sockets = { left = RUN_H, right = OPEN, top = OPEN, bottom = GROUND },
  draw = function(s, r)
    sheet(s, 0, 9, r)
    -- the hemmed vertical edge of the last sheet
    P.rect_fill(s, 10, FENCE.top, 1, FENCE.bottom - FENCE.top + 1, "metal_5")
    post(s, 11, r, { y0 = FENCE.top - 3, y1 = FENCE.bottom + 1 })
  end }

piece { name = "straight_v", title = "Fence, straight vertical 16x16", variants = 8,
  -- The fence running away from the viewer, built from LEAF so it mates with
  -- every corner in the kit.
  sockets = { left = OPEN, right = OPEN, top = RUN_V, bottom = RUN_V },
  draw = function(s, r)
    leaf(s, 0, 15, r)
    -- a post partway along, which is what keeps a long vertical run from
    -- reading as a pipe
    if r:chance(0.5) then
      local y = r:range(4, 10)
      P.rect_fill(s, LEAF.x0 - 1, y, LEAF.x1 - LEAF.x0 + 3, 2, "metal_5")
      P.rect_fill(s, LEAF.x0 - 1, y + 2, LEAF.x1 - LEAF.x0 + 3, 1, "metal_2")
    end
  end }

piece { name = "corner", title = "Fence, corner 16x16", variants = 6,
  -- The run turns away from the viewer. A corner post is the heaviest member
  -- in the kit -- it carries the tension of both runs -- and the sheet returns
  -- behind it as LEAF.
  sockets = { left = RUN_H, right = OPEN, top = OPEN, bottom = RUN_V },
  draw = function(s, r)
    sheet(s, 0, LEAF.x0 - 2, r)
    leaf(s, FENCE.top, 15, r)
    -- The post stops at the fence foot and does NOT reach the bottom edge.
    -- That edge is a join where the vertical run carries on, so the only thing
    -- allowed on it is the leaf: a post spanning it puts three columns of
    -- steel where the next piece down has nothing, and the run steps.
    post(s, LEAF.x0 - 3, r, { y0 = FENCE.top - 3, y1 = FENCE.bottom })
  end }

piece { name = "damaged", title = "Fence, damaged 16x16", variants = 8,
  -- Bent and dented but whole: this is the piece that lets a long run look
  -- beaten without looking breached.
  sockets = { left = RUN_H, right = RUN_H, top = OPEN, bottom = GROUND },
  draw = function(s, r)
    sheet(s, 0, 15, r)
    -- a dent pushed in between two folds: dark where it goes in, lit lip on
    -- the lower-right wall the light reaches
    local d = r:branch("dent")
    for _ = 1, d:range(1, 2) do
      local x = d:range(2, 12)
      local y = d:range(FENCE.rail + 2, FENCE.bottom - 3)
      P.rect_fill_shift(s, x, y, d:range(2, 4), 2, -1)
      P.rect_fill_shift(s, x, y + 2, d:range(2, 4), 1, 1)
    end
  end }

piece { name = "broken", title = "Fence, broken 16x16", variants = 8,
  -- Corroded through at the bottom, where a sheet always goes first: the
  -- ragged lower edge is the read, and it is PINNED at both ends of its run so
  -- the piece still meets its neighbours.
  sockets = { left = RUN_H, right = RUN_H, top = OPEN, bottom = GROUND },
  max_interior_holes = 4,
  draw = function(s, r)
    sheet(s, 0, 15, r)
    local pin = require("style").terrain.pin_width
    local eaten = r:branch("eaten")
    local level = FENCE.bottom
    for x = 0, 15 do
      if eaten:chance(0.3) then
        level = math.max(FENCE.rail + 2, math.min(FENCE.bottom, level + eaten:range(-1, 1)))
      end
      local from_edge = math.min(x, 15 - x)
      local depth = FENCE.bottom - level
      local allowed = from_edge >= pin and depth or math.floor(depth * from_edge / pin)
      local here = FENCE.bottom - allowed
      for y = here + 1, FENCE.bottom do s:set(x, y, palette.TRANSPARENT) end
      -- the corroded edge, lit on its rim: rust is what ate it, so rust is
      -- what shows at the tear
      if allowed > 0 then s:set(x, here, "rust_1") end
    end
  end }

piece { name = "hole", title = "Fence, hole through 16x16", variants = 8,
  -- Rusted clean through in the middle of the sheet: a gap a player can see
  -- and shoot through. The strongest single statement this kit can make about
  -- the state of the place.
  sockets = { left = RUN_H, right = RUN_H, top = OPEN, bottom = GROUND },
  max_interior_holes = 4,
  draw = function(s, r)
    sheet(s, 0, 15, r)
    local hole = r:branch("hole")
    local hx = hole:range(4, 11)
    local hy = hole:range(FENCE.rail + 2, FENCE.bottom - 4)
    local blob = P.cluster(s, hx, hy, hole:range(10, 18), "rust_1", hole, { spread = 0.6 })
    for _, p in ipairs(blob) do s:set(p[1], p[2], palette.TRANSPARENT) end
    -- the torn edge: corroded steel catching the light on the rim above the
    -- hole, per the fixed upper-left key
    for _, p in ipairs(blob) do
      local above = s:get(p[1], p[2] - 1)
      if above ~= palette.TRANSPARENT then s:set(p[1], p[2] - 1, "rust_2") end
      local left = s:get(p[1] - 1, p[2])
      if left ~= palette.TRANSPARENT and hole:chance(0.5) then s:set(p[1] - 1, p[2], "rust_1") end
    end
  end }

piece { name = "gate", title = "Fence, gate closed 16x32", w = 32, h = 16, variants = 6,
  -- A gate is TWO leaves with a visible frame around each and a gap between:
  -- that frame is the whole difference between a gate and a piece of fence, so
  -- it gets 32px of width to state it in.
  sockets = { left = RUN_H, right = RUN_H, top = OPEN, bottom = GROUND },
  draw = function(s, r)
    -- the two leaves, flat sheet rather than corrugated: a gate is fabricated,
    -- not rolled
    for i = 0, 1 do
      local x0 = 2 + i * 14
      sheet(s, x0, x0 + 12, r, { corrugated = false, top = FENCE.top + 1 })
      -- the leaf frame: a lit member all the way round
      P.rect(s, x0, FENCE.top + 1, 13, FENCE.bottom - FENCE.top, "metal_5")
      P.rect_fill(s, x0, FENCE.bottom, 13, 1, "metal_3")
      -- the diagonal brace, which is what says "this thing swings"
      P.line(s, x0 + 1, FENCE.bottom - 1, x0 + 11, FENCE.top + 2, "metal_5")
    end
    -- A gate's hanging posts are taller and heavier than the sheet, so they
    -- may NOT sit on the piece edges: a fence run butting against this piece
    -- would meet three rows of post where it has sky and ground. The edges
    -- carry one column of ordinary fence sheet -- so the join is a plain sheet
    -- join -- and the posts stand just inside it, which is also what a real
    -- gate looks like: the fence runs up to the post and stops.
    sheet(s, 0, 0, r)
    sheet(s, 31, 31, r)
    post(s, 1, r, { y0 = FENCE.top - 2, y1 = FENCE.bottom + 1 })
    post(s, 28, r, { y0 = FENCE.top - 2, y1 = FENCE.bottom + 1 })
    P.rect_fill(s, 15, FENCE.top + 2, 2, FENCE.bottom - FENCE.top - 2, "metal_5")
  end }

piece { name = "gate_open", title = "Fence, gate open 32x16", w = 32, h = 16, variants = 6,
  -- One leaf swung back against the fence line, the other hanging off its
  -- hinge. The opening is the asset: a level needs a way in that reads as a
  -- way in from across the yard.
  sockets = { left = RUN_H, right = RUN_H, top = OPEN, bottom = GROUND },
  collision = "none",
  draw = function(s, r)
    -- Same edge contract as the closed gate: plain sheet on the joins, posts
    -- just inside them.
    sheet(s, 0, 0, r)
    sheet(s, 31, 31, r)
    post(s, 1, r, { y0 = FENCE.top - 2, y1 = FENCE.bottom + 1 })
    post(s, 28, r, { y0 = FENCE.top - 2, y1 = FENCE.bottom + 1 })
    -- the leaf folded back against the left post: seen edge-on, so it is a
    -- narrow shaded slab rather than a face
    P.rect_fill(s, 5, FENCE.top + 1, 3, FENCE.bottom - FENCE.top, "metal_3")
    P.rect_fill(s, 5, FENCE.top + 1, 1, FENCE.bottom - FENCE.top, "metal_4")
    P.rect_fill(s, 5, FENCE.top + 1, 3, 1, "metal_5")
    -- the other leaf, dropped off its hinge and leaning: a run of sheet at an
    -- angle, which is the one thing in this kit that is allowed not to be
    -- square
    local lean = r:range(2, 4)
    for i = 0, 9 do
      local y = FENCE.top + 2 + (i * lean) // 10
      P.rect_fill(s, 24 - i, y, 1, FENCE.bottom - y, "metal_4")
      P.pixel(s, 24 - i, y, "metal_5")
    end
    -- the rail stub still bolted to each post, so the frame reads as continuous
    P.rect_fill(s, 1, FENCE.rail, 4, 2, "metal_4")
    P.rect_fill(s, 26, FENCE.rail, 4, 2, "metal_4")
  end }

return set
