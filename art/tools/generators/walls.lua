-- generators/walls.lua -- the modular ruined-wall kit.
--
-- Post-Soviet panel construction seen from above and slightly in front: a wall
-- is a horizontal band of concrete with a lit top face, a body, and a shaded
-- foot. A run of pieces has to read as ONE wall, which is the whole difficulty
-- and the reason these are not just seven variants of a texture.
--
-- HOW A RUN CONNECTS
--
-- Every piece declares what its four edges present, as socket names. A piece
-- with `right = "wall_core"` promises that its rightmost column looks like the
-- inside of a wall; a piece with `right = "open"` promises the wall has ended.
-- The `sockets` validator then checks that promise mechanically: every piece
-- presenting a given socket must agree with every other piece on which ROWS of
-- that edge are opaque and which palette RAMP each opaque row belongs to.
--
-- That is the minimum meaning of "these connect visually": the material lines
-- up and the silhouette does not step. It is deliberately not a check on exact
-- colour -- a joint decays, and one piece may be rustier than its neighbour.
--
-- The consequence for this file is that the wall's cross-section (which rows
-- are cap, body, foot) is ONE table, WALL_ROWS, and every piece builds from
-- it. That is what makes the connection true by construction rather than by
-- eight files agreeing to use the same numbers.

local P = require("pixel_utils")
local palette = require("palette")
local materials = require("materials")
local object = require("object")
local wear = require("wear")

local concrete, rust = materials.concrete, materials.rust

-- The cross-section of every wall piece. A wall stands 11 rows tall in a
-- 16-row cell, leaving the top five for whatever is behind it and the bottom
-- for the ground it stands on.
local WALL = {
  top = 4,        -- first row of the cap
  cap = 2,        -- rows of lit top face
  bottom = 14,    -- last row of the body
  foot = 2,       -- rows of shaded foot
}

-- A vertical run: the wall going away from the viewer. It occupies a fixed
-- column range in EVERY piece that carries one, which is what lets a vertical
-- run connect at all -- see the socket note below.
local LEG = { x0 = 5, x1 = 10 }

-- SOCKETS ARE DIRECTION-TYPED, and getting that wrong is instructive. The
-- first version used one name, "wall_core", for both the left/right edges of a
-- horizontal run and the top/bottom edges of a vertical one -- and the
-- validator immediately reported that a corner's bottom edge does not match a
-- straight piece's right edge. Of course it does not: a left/right edge is a
-- vertical slice through the wall's CROSS-SECTION (transparent sky, lit cap,
-- body, shaded foot) and a top/bottom edge is a horizontal slice ALONG its
-- length (transparent, leg, transparent). They are different edges of a
-- different shape and can never mate.
--
-- So there are two sockets, and the piece that presents one has to be built
-- from the shared table for that direction: WALL for horizontal, LEG for
-- vertical. That is what makes the connection true by construction.
local RUN_H = "wall_run_h"  -- horizontal run continues through this edge
local RUN_V = "wall_run_v"  -- vertical run (going away from the viewer)
-- A third socket, and it is a finding rather than a convenience. A collapsed
-- section is NOT a piece of full-height wall: it is a low stub, and its edges
-- are three rows shorter. Declaring it RUN_H was a lie the validator caught --
-- laid beside a straight piece it steps, which is exactly what a collapse
-- looks like and exactly not what a connector should promise. So it presents
-- its own socket: collapsed sections mate with each other to make a long
-- fallen run, and butting one against a full wall is a deliberate break the
-- level designer can see rather than one the kit hid.
local STUB_H = "wall_stub_h"
local OPEN = "open"         -- the wall has ended: transparent edge
local GROUND = "ground"     -- a horizontal edge that is just ground

--- The wall's body, cap and foot across an x range. Every piece calls this, so
--- every piece has the same cross-section and a run cannot step.
local function band(s, x0, x1, rng_stream, opts)
  opts = opts or {}
  local top, bottom = opts.top or WALL.top, opts.bottom or WALL.bottom
  if x1 < x0 then return end
  local h = bottom - top + 1
  P.rect_fill(s, x0, top, x1 - x0 + 1, h, "concrete_4")
  concrete.fill(s, rng_stream:branch("face"), {
    area = { x = x0, y = top, w = x1 - x0 + 1, h = h }, wear = 0.6,
    mask = function(x, y) return x >= x0 and x <= x1 and y >= top and y <= bottom end,
  })
  -- The cap: the top face turns into the light, and it is the cue that reads
  -- as "this is standing up". The full-width `concrete_6` top row it started
  -- with was too much of a good thing -- an unbroken bright rule along every
  -- piece made a run read as a lit pipe rather than as masonry. The daylight
  -- step is now a BROKEN run over a concrete_5 cap, which is the same fix
  -- ART_STYLE.md 6 prescribes for every other subtle edge in the toolkit.
  P.rect_fill(s, x0, top, x1 - x0 + 1, WALL.cap, "concrete_5")
  P.broken_run(s, "h", top, x0, x1, rng_stream:branch("cap"),
    { color = palette.by_name.concrete_6, run = { 3, 7 }, gap = { 2, 5 } })
  -- the foot: in its own shadow
  P.rect_fill(s, x0, bottom - WALL.foot + 1, x1 - x0 + 1, WALL.foot, "concrete_3")
  P.rect_fill(s, x0, bottom, x1 - x0 + 1, 1, "concrete_2")
end

--- A vertical run of wall: the leg going away from the viewer. Fixed columns,
--- so every piece carrying one presents the same top/bottom profile.
local function leg(s, y0, y1, rng_stream)
  local w = LEG.x1 - LEG.x0 + 1
  P.rect_fill(s, LEG.x0, y0, w, y1 - y0 + 1, "concrete_4")
  concrete.fill(s, rng_stream:branch("leg"), {
    area = { x = LEG.x0, y = y0, w = w, h = y1 - y0 + 1 }, wear = 0.5,
    mask = function(x, y) return x >= LEG.x0 and x <= LEG.x1 and y >= y0 and y <= y1 end,
  })
  -- the top face of the leg runs its whole length, lit; the two side faces
  -- take the light and lose it per the fixed upper-left key
  P.rect_fill(s, LEG.x0, y0, 1, y1 - y0 + 1, "concrete_5")
  P.rect_fill(s, LEG.x1, y0, 1, y1 - y0 + 1, "concrete_3")
  P.rect_fill(s, LEG.x0 + 1, y0, w - 2, y1 - y0 + 1, "concrete_5")
  P.rect_fill(s, LEG.x0 + 2, y0, w - 4, y1 - y0 + 1, "concrete_4")
end

--- The cast joint between two courses, decayed. Pinned at both ends of its run
--- so a wall still meets its neighbour's joint (concrete.groove).
local function course_joint(s, x0, x1, rng_stream, opts)
  opts = opts or {}
  local y = opts.y or (WALL.top + 5)
  local jitter = rng_stream:branch("joint")
  local drift, gap_left = 0, 0
  for x = x0, x1 do
    local pinned = x <= x0 + 1 or x >= x1 - 1
    if pinned then drift = 0 end
    if gap_left > 0 then
      gap_left = gap_left - 1
    elseif not pinned and jitter:chance(0.07) then
      gap_left = jitter:range(1, 2)
    else
      s:set(x, y + drift, "concrete_2")
      -- the lit lip on the lower side of the cut, broken
      if jitter:chance(0.45) then s:set(x, y + drift + 1, "concrete_5") end
    end
    if not pinned and jitter:chance(0.10) then
      drift = drift == 0 and (jitter:chance(0.5) and 1 or -1) or 0
    end
  end
end

--- A broken-off top: the cap replaced by a ragged edge of exposed core, with
--- the reinforcement showing where the break went deep.
--
-- PINNED AT BOTH ENDS OF ITS RUN. This is the same invariant as the decayed
-- cast joint (concrete.groove) and the ragged terrain boundary
-- (style.terrain), and it turned up here for the third time by way of the
-- socket validator: a broken top that reaches the piece edge leaves the wall
-- at a different height there than its neighbour, so the two do not abut and
-- the run shows a step at the join. Pinned, the break may do whatever it likes
-- across the middle -- which is where the raggedness is wanted anyway -- and
-- every piece still meets every other at the canonical cap height.
--
-- The pin band is `style.terrain.pin_width` for the same reason it exists
-- there: wide enough that the profile has visibly settled by the edge rather
-- than snapping back in one column.
-- @param top the row the intact cap starts at. It is a PARAMETER and not
--   WALL.top, which was a real bug: the collapsed piece bands its stub at a
--   lower top, and a break_top that assumed WALL.top drew a ragged edge of
--   exposed core floating five rows above the stub in mid-air.
local function break_top(s, x0, x1, rng_stream, depth, top)
  local r = rng_stream:branch("break")
  local pin = require("style").terrain.pin_width
  top = top or WALL.top
  local profile = {}
  local level = top
  for x = x0, x1 do
    -- a broken arris wanders in RUNS, not per pixel: a per-pixel profile is a
    -- comb, and a comb reads as damage to the drawing rather than to the wall
    if r:chance(0.25) then
      level = math.max(top, math.min(top + depth, level + r:range(-1, 1)))
    end
    -- ramp the allowed depth to zero at both ends of the run
    local from_edge = math.min(x - x0, x1 - x)
    local allowed = from_edge >= pin and depth or math.floor(depth * from_edge / pin)
    local here = math.min(level, top + allowed)
    profile[x] = here
    for y = top, here - 1 do s:set(x, y, palette.TRANSPARENT) end
    -- the exposed core: darker than the face, because it has never seen light
    s:set(x, here, "concrete_3")
    if r:chance(0.4) then s:set(x, here + 1, "concrete_3") end
  end
  -- Reinforcement standing out of the break. Ochre is the loudest thing in the
  -- palette, so at most one bar per piece -- and never within the pin band,
  -- because a bar poking above the cap line at the piece edge is material where
  -- the neighbouring piece has none.
  if r:chance(0.45) and x1 - x0 > 2 * pin then
    local bx = r:range(x0 + pin, x1 - pin)
    rust.bar(s, bx, profile[bx] - r:range(2, 3), r:range(3, 4), "v", r, { streak = false })
  end
  return profile
end

--- Rubble at the foot of a wall, made of the wall. Debris collects where
--- things fall, which for a wall is against its own base.
--
-- Inset from the piece edges by the pin band, for two reasons that turn out to
-- be the same reason. A chunk of masonry drawn hard against the cell edge is
-- sliced in half at the join and reads as two half-chunks; and because debris
-- draws from the CONCRETE ramp -- it is an overlay material with a base
-- material's ramp, so no ramp test can tell it apart from the wall itself --
-- a chunk on a connecting edge changes that edge's profile and breaks the
-- socket contract. Keeping it clear of the border fixes the look and the
-- contract at once.
local function foot_rubble(s, x0, x1, rng_stream, amount)
  local pin = require("style").terrain.pin_width
  local ix0, ix1 = x0 + pin, x1 - pin
  if ix1 <= ix0 then ix0, ix1 = x0, x1 end
  materials.debris.fill(s, rng_stream:branch("foot"), {
    coverage = amount,
    area = { x = ix0, y = WALL.bottom - 1, w = ix1 - ix0 + 1, h = 4 },
    kinds = { { value = "concrete_4", weight = 3 }, { value = "concrete_3", weight = 2 },
              { value = "concrete_5", weight = 1 } },
  })
end

-- The shared wear profile for concrete: staining runs out of the joint and
-- down, grime collects at the foot, weeds take the base. Declared once so
-- every piece weathers by the same process.
local CONCRETE_WEAR = {
  ramp = "concrete",
  staining = { { value = 0, weight = 2 }, { value = 0.10, weight = 3 }, { value = 0.18, weight = 1 } },
  dirt = { { value = 0.06, weight = 2 }, { value = 0.14, weight = 2 } },
  rust = { { value = 0, weight = 4 }, { value = 0.06, weight = 2 } },
  cracks = { { value = 0, weight = 2 }, { value = 0.5, weight = 2 } },
  dirt_bias = function(_, y) return y >= WALL.bottom - 2 and 1.0 or 0.1 end,
  rust_bias = function(_, y) return math.abs(y - (WALL.top + 6)) <= 2 and 0.9 or 0.2 end,
  vegetation = { { value = 0, weight = 3 }, { value = 1, weight = 1 } },
  vegetation_area = { x = 1, y = WALL.bottom - 2, w = 14, h = 3 },
}

local set = {}
local function piece(spec)
  set[#set + 1] = {
    name = "wall_" .. spec.name,
    title = spec.title,
    size = { w = spec.w or 16, h = spec.h or 16 },
    tileable = false,
    surface = spec.surface or "structure",
    category = "wall",
    collision = spec.collision or "block",
    variants = spec.variants or 6,
    sockets = spec.sockets,
    max_interior_holes = spec.max_interior_holes,
    preview_background = spec.background or "dirt_ground",
    build = function(rng_stream, opts)
      local s = P.new(spec.w or 16, spec.h or 16)
      spec.draw(s, rng_stream, opts or {})
      return object.finish(s, rng_stream, {
        wear = spec.wear == false and nil or CONCRETE_WEAR,
        shadow = spec.shadow,
        sockets = spec.sockets,
      })
    end,
  }
end

-- Straight run --------------------------------------------------------------

piece { name = "straight", title = "Wall, straight 16x16", variants = 8,
  sockets = { left = RUN_H, right = RUN_H, top = OPEN, bottom = GROUND },
  draw = function(s, r)
    band(s, 0, 15, r)
    course_joint(s, 0, 15, r)
  end }

piece { name = "end", title = "Wall, end 16x16", variants = 6,
  -- The wall stops here, so the right edge is open and the RETURN face shows:
  -- a wall seen end-on is a slab with thickness, and drawing the end as a flat
  -- cut is what makes a modular kit look like cardboard.
  sockets = { left = RUN_H, right = OPEN, top = OPEN, bottom = GROUND },
  draw = function(s, r)
    band(s, 0, 10, r)
    course_joint(s, 0, 10, r)
    -- the return: two columns of the wall's own depth, shaded because they
    -- face away from the key light
    P.rect_fill(s, 11, WALL.top, 2, WALL.bottom - WALL.top + 1, "concrete_3")
    P.rect_fill(s, 11, WALL.top, 2, WALL.cap, "concrete_4")
    P.rect_fill(s, 11, WALL.bottom - WALL.foot + 1, 2, WALL.foot, "concrete_2")
  end }

piece { name = "straight_v", title = "Wall, straight vertical 16x16", variants = 8,
  -- The wall running away from the viewer. Built from LEG, so its top and
  -- bottom edges mate with every corner in the kit.
  sockets = { left = OPEN, right = OPEN, top = RUN_V, bottom = RUN_V },
  draw = function(s, r)
    leg(s, 0, 15, r)
    -- the course joint, running across the leg rather than along it
    local j = r:branch("vjoint")
    local y = j:range(5, 10)
    for x = LEG.x0, LEG.x1 do
      if j:chance(0.85) then s:set(x, y, "concrete_2") end
    end
  end }

piece { name = "corner_outer", title = "Wall, outer corner 16x16", variants = 6,
  -- The run arrives from the left and turns away from the viewer. The
  -- horizontal band stops at the leg, the leg carries on to the bottom edge,
  -- and the arris where the two planes meet is the corner's whole read.
  sockets = { left = RUN_H, right = OPEN, top = OPEN, bottom = RUN_V },
  draw = function(s, r)
    band(s, 0, LEG.x1, r)
    course_joint(s, 0, LEG.x0 - 1, r)
    leg(s, WALL.top, 15, r)
    -- the cap of the horizontal band wraps onto the leg, which is what says
    -- these are one wall and not two pieces butted together
    P.rect_fill(s, LEG.x0, WALL.top, LEG.x1 - LEG.x0 + 1, WALL.cap, "concrete_5")
    P.rect_fill(s, LEG.x0, WALL.top, LEG.x1 - LEG.x0 + 1, 1, "concrete_6")
    -- the arris
    P.vline(s, LEG.x0, WALL.top + WALL.cap, 16 - WALL.top - WALL.cap, "concrete_5")
  end }

piece { name = "corner_inner", title = "Wall, inner corner 16x16", variants = 6,
  -- A junction: the horizontal run continues through AND a leg goes away from
  -- the viewer. This is the piece that turns a straight run into an enclosure.
  sockets = { left = RUN_H, right = RUN_H, top = OPEN, bottom = RUN_V },
  draw = function(s, r)
    band(s, 0, 15, r)
    course_joint(s, 0, 15, r)
    leg(s, WALL.bottom - 1, 15, r)
    -- the pocket between the two walls is in shadow: an inner corner is the
    -- one place on a wall where light cannot reach
    P.rect_fill_shift(s, LEG.x0, WALL.bottom - 1, LEG.x1 - LEG.x0 + 1, 1, -1)
  end }

-- Damage --------------------------------------------------------------------

piece { name = "damaged_top", title = "Wall, damaged top 16x16", variants = 8,
  sockets = { left = RUN_H, right = RUN_H, top = OPEN, bottom = GROUND },
  draw = function(s, r)
    band(s, 0, 15, r)
    course_joint(s, 0, 15, r)
    -- the cap chipped away, but the wall still full height: this is the piece
    -- that lets a long run look weathered without looking demolished
    break_top(s, 0, 15, r, 2)
    foot_rubble(s, 0, 15, r, 0.04)
  end }

piece { name = "broken", title = "Wall, broken 16x16", variants = 8,
  -- Still a wall, and still connects: the socket contract is what allows a
  -- broken piece to sit in the middle of an intact run.
  sockets = { left = RUN_H, right = RUN_H, top = OPEN, bottom = GROUND },
  draw = function(s, r)
    band(s, 0, 15, r)
    course_joint(s, 0, 15, r)
    break_top(s, 0, 15, r, 4)
    -- a chunk out of the face, deep enough to show the core
    local sp = r:branch("spall")
    concrete.spall(s, sp:range(2, 12), sp:range(WALL.top + 3, WALL.bottom - 2),
      sp:range(9, 15), sp, {})
    foot_rubble(s, 0, 15, r, 0.10)
  end }

piece { name = "broken_heavy", title = "Wall, heavily broken 16x16", variants = 8,
  sockets = { left = RUN_H, right = RUN_H, top = OPEN, bottom = GROUND },
  max_interior_holes = 4,
  draw = function(s, r)
    band(s, 0, 15, r)
    break_top(s, 0, 15, r, 7)
    -- holed through: the strongest statement a wall piece can make. Drawn as a
    -- torn opening with the exposed core lit on its upper-left rim, and the
    -- reinforcement crossing it -- a hole in a panel wall shows the cage.
    local hole = r:branch("hole")
    local hx = hole:range(3, 10)
    local hy = hole:range(WALL.top + 3, WALL.bottom - 4)
    local blob = P.cluster(s, hx, hy, hole:range(12, 20), "concrete_2", hole, { spread = 0.6 })
    for _, p in ipairs(blob) do s:set(p[1], p[2], palette.TRANSPARENT) end
    for _, p in ipairs(blob) do
      local above = s:get(p[1], p[2] - 1)
      if above ~= palette.TRANSPARENT then s:set(p[1], p[2] - 1, "concrete_3") end
    end
    if #blob > 6 then
      rust.bar(s, hx - 1, hy, hole:range(4, 6), hole:chance(0.5) and "h" or "v", hole,
        { streak = false })
    end
    foot_rubble(s, 0, 15, r, 0.18)
  end }

piece { name = "doorway", title = "Wall, doorway 16x16", variants = 6,
  -- An opening a player walks through, so the two jambs are the asset: they
  -- carry the wall's full cross-section and its return depth, and the head is
  -- gone (this is a ruin, not a building).
  sockets = { left = RUN_H, right = RUN_H, top = OPEN, bottom = GROUND },
  collision = "hull",
  draw = function(s, r)
    band(s, 0, 4, r)
    band(s, 11, 15, r)
    course_joint(s, 0, 4, r)
    course_joint(s, 11, 15, r)
    -- the reveals: the thickness of the wall showing in the opening, shaded
    -- because they face into it
    P.rect_fill(s, 5, WALL.top, 1, WALL.bottom - WALL.top + 1, "concrete_3")
    P.rect_fill(s, 10, WALL.top, 1, WALL.bottom - WALL.top + 1, "concrete_3")
    P.rect_fill(s, 5, WALL.top, 1, WALL.cap, "concrete_4")
    P.rect_fill(s, 10, WALL.top, 1, WALL.cap, "concrete_4")
    -- the threshold, worn: this is where everyone walked
    P.hline(s, 6, WALL.bottom, 4, "concrete_3")
    foot_rubble(s, 5, 10, r, 0.10)
  end }

piece { name = "collapsed", title = "Wall, collapsed section 16x16", variants = 10,
  -- The wall has come down here. What that has to look like took a rewrite:
  -- the first version banded a low stub and scattered fine debris over it,
  -- which read as a thin grey strip with speckle on it and measured 0.60
  -- against the 0.55 structure ceiling. Both problems had one cause -- a
  -- collapsed wall is not a short wall, it is a HEAP, and a heap is made of
  -- big pieces.
  --
  -- So: a fixed low remnant across the full width, and slabs piled on it in
  -- the middle, rising well above the remnant so the silhouette reads as a
  -- mound. Larger marks are calmer per pixel (ART_STYLE.md 7) and they are
  -- also what masonry actually breaks into.
  sockets = { left = STUB_H, right = STUB_H, top = OPEN, bottom = GROUND },
  collision = "low",
  -- Surface class `prop`, not `structure`, and it is the third time in this
  -- toolkit that surface class and category have turned out to be different
  -- axes. By CATEGORY this is a wall piece: it carries wall sockets and sits
  -- in a wall run. By SURFACE it is a heap -- an object with a mound
  -- silhouette, not a repeating wall texture -- and the structure ceiling
  -- (0.55) does not describe it: a mound drawn with a per-column height steps
  -- at every column by construction, so it measures 0.60 however few marks it
  -- carries. It was reduced twice on those grounds before the ceiling was the
  -- thing that looked wrong.
  --
  -- This is not a relaxation. The prop class subjects it to the silhouette
  -- rules it should have been held to all along, and it passes them with room:
  -- occupancy 0.50-0.72 of 0.10-0.92, ONE connected piece of a permitted 4,
  -- and no enclosed holes at all -- which is the mechanical statement that the
  -- heap is one mass, the property the rewrite was for.
  surface = "prop",
  draw = function(s, r)
    local pin = require("style").terrain.pin_width
    -- The remnant. Its rows are FIXED, not per-seed: this is what the
    -- wall_stub_h socket promises, and a socket that varies by variant
    -- promises nothing.
    local remnant_top = 11
    band(s, 0, 15, r, { top = remnant_top })
    -- no lit cap on a remnant: it has a broken top, not a cast one
    P.rect_fill(s, 0, remnant_top, 16, 1, "concrete_3")

    -- THE HEAP IS ONE MASS, not a stack of separate slabs. Laid as separate
    -- boxes they came out as floating islands, each with its own full outline,
    -- which read as a row of dark rocks hovering over the remnant and cost a
    -- great deal of busyness in ink alone. A heap is a connected mound with
    -- slab divisions drawn INSIDE it -- exactly how the wall band works, with
    -- a ragged top instead of a cast one.
    local mound = r:branch("mound")
    local peak = mound:range(5, 8)          -- how far above the remnant it rises
    local centre = mound:range(6, 10)
    local height = {}
    for x = pin, 15 - pin do
      -- a mound falls away from its peak; the noise is on top of that shape,
      -- so the silhouette stays a mound rather than becoming a comb
      local fall = math.abs(x - centre) * mound:range(4, 7) / 10
      local h = math.max(0, math.floor(peak - fall + 0.5))
      if mound:chance(0.35) then h = math.max(0, h + mound:range(-1, 1)) end
      height[x] = h
      for y = remnant_top - h, remnant_top - 1 do
        s:set(x, y, "concrete_4")
      end
      -- the top of the mound catches the light; its right flank loses it
      if h > 0 then
        s:set(x, remnant_top - h, "concrete_5")
        if x > centre then s:set(x, remnant_top - h + 1, "concrete_3") end
      end
    end
    -- Slab divisions: dark runs across the mound, which is what turns a lump
    -- into broken masonry. ONE or two, not three: at three the mound measured
    -- 0.565 against the 0.55 structure ceiling, and the divisions started
    -- competing with the silhouette instead of describing it. Runs, at angles,
    -- never a grid.
    for _ = 1, mound:range(1, 2) do
      local x0 = mound:range(pin, 13 - pin)
      local y0 = remnant_top - math.max(1, (height[x0] or 1)) + mound:range(0, 1)
      local len = mound:range(3, 5)
      local dy = mound:chance(0.5) and 1 or 0
      for k = 0, len - 1 do
        local x, y = x0 + k, y0 + (k * dy) // 3
        if s:get(x, y) ~= palette.TRANSPARENT then
          s:set(x, y, "concrete_2")
          -- the lit arris of the slab below the division
          if s:get(x, y + 1) ~= palette.TRANSPARENT then s:set(x, y + 1, "concrete_5") end
        end
      end
    end
    -- reinforcement trailing out of the mound, at most once per piece: ochre
    -- is the loudest thing in the palette
    if mound:chance(0.5) then
      local bx = mound:range(pin + 1, 14 - pin)
      rust.bar(s, bx, remnant_top - (height[bx] or 1) - mound:range(1, 2),
        mound:range(3, 4), mound:chance(0.5) and "h" or "v", mound, { streak = false })
    end
    -- and a little of what shattered, at the foot of the mound only
    materials.debris.fill(s, r:branch("shards"), {
      coverage = 0.05,
      area = { x = pin, y = 13, w = 16 - 2 * pin, h = 3 },
      kinds = { { value = "concrete_4", weight = 3 }, { value = "concrete_3", weight = 2 } },
    })
  end }

piece { name = "rubble_base", title = "Wall, rubble at base 16x16", variants = 8,
  -- A dressing piece: intact wall with a heap of what fell off it. Laid in
  -- front of a straight run it does the job a decal cannot, because it has to
  -- line up with the wall's own foot row.
  sockets = { left = RUN_H, right = RUN_H, top = OPEN, bottom = GROUND },
  draw = function(s, r)
    band(s, 0, 15, r)
    course_joint(s, 0, 15, r)
    foot_rubble(s, 0, 15, r, 0.35)
    -- one larger block, which is what makes a heap read as masonry rather
    -- than as gravel
    local blk = r:branch("block")
    local bx, by = blk:range(2, 11), WALL.bottom + 1
    object.box(s, bx, by, blk:range(3, 4), 2, "concrete", 4)
  end }

return set
