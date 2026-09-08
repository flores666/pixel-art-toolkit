-- object.lua -- the shared grammar of a standing object.
--
-- Every prop, rock, structure piece and machine in the library ends the same
-- way, because at 16px the silhouette IS the asset and the things that make a
-- silhouette read are always the same: an outline that separates it from the
-- ground, cleanup that leaves clusters rather than dust, and a contact shadow
-- that plants it. Written once here, they cannot drift apart between kits.
--
-- The order is ART_STYLE.md 9 and the reasons are load-bearing:
--   outline BEFORE wear, so corrosion can eat into the silhouette but not into
--   the outline; contact shadow AFTER cleanup, so despeckle cannot eat it.

local P = require("pixel_utils")
local palette = require("palette")
local style = require("style")

local object = {}

--- Finish an object: outline, wear, cleanup, contact shadow.
-- @param opts
--   outline      false to skip (a decal, a flat marking)
--   wear         spec passed to wear.apply
--   shadow       false to skip; otherwise { y = row, from = x, to = x }
--   keep         despeckle protection for deliberate single pixels
--   sockets      the generator's socket table. AN EDGE WHERE THE RUN
--                CONTINUES IS NOT OUTLINED AND CASTS NO CONTACT SHADOW.
--
-- That last rule is what makes a modular kit work, and it is easy to miss
-- because it only shows up once pieces are laid next to each other. A wall
-- piece whose run carries on through its bottom edge is not ending there --
-- outlining it draws a black rule across the middle of the run, and giving it
-- a contact shadow plants the middle of a wall on the ground. Both were
-- happening, and the socket declaration already says exactly which edges are
-- joins, so it drives the mask rather than each piece remembering.
function object.finish(surface, rng_stream, opts)
  opts = opts or {}

  -- Which borders are joins rather than silhouette. "open" and "ground" are
  -- not connections: the run has ended, so the silhouette is real there.
  local joins = {}
  for side, socket in pairs(opts.sockets or {}) do
    if socket ~= "open" and socket ~= "ground" then joins[side] = true end
  end
  local w, h = surface.width, surface.height
  local border_mask
  if next(joins) then
    border_mask = function(x, y)
      if joins.left and x == 0 then return false end
      if joins.right and x == w - 1 then return false end
      if joins.top and y == 0 then return false end
      if joins.bottom and y == h - 1 then return false end
      return true
    end
  end

  if opts.outline ~= false then
    P.outline(surface, opts.outline_color, { mask = border_mask })
  end
  if opts.wear then
    require("wear").apply(surface, rng_stream:branch("wear"), opts.wear)
  end
  -- Cleanup. On an object the vote is right (there is a body to vote with),
  -- but a true floater left over from a wear overlay has nothing to vote from,
  -- so both passes run: absorb what can be absorbed, erase what cannot.
  P.despeckle(surface, { keep = opts.keep })
  P.strip_strays(surface, { keep = opts.keep })

  -- No contact shadow on an edge the run continues through: the object does
  -- not touch the ground there, it carries on into the next cell.
  if opts.shadow ~= false and not joins.bottom then
    local s = opts.shadow or {}
    local y = s.y or (surface.height - 1)
    local from = s.from or 1
    local to = s.to or (surface.width - 2)
    -- A soft-looking shadow is a BROKEN RUN of near-black, never translucency:
    -- alpha is binary (ART_STYLE.md 4).
    P.broken_run(surface, "h", y, from, to, rng_stream:branch("contact"),
      { color = "ink_3", on_transparent = true, run = { 4, 8 }, gap = { 1, 2 } })
  end

  -- Pinholes LAST. Single enclosed transparent cells appear wherever strokes
  -- radiating from a crown close a ring (a bush, a tangle of branches) -- and
  -- also wherever the contact shadow lands one pixel clear of the silhouette,
  -- which is why this runs after the shadow rather than with the rest of
  -- cleanup. After outlining they read as dropped pixels inside the shape, and
  -- no kit can foresee the geometry. Filling only ever adds pixels, so the
  -- shadow it was ordered behind is safe.
  P.fill_pinholes(surface)
  return surface
end

--- A standing member: a post, a pole, a leg. Drawn as explicit ramp steps --
--- lit left face, body, shaded right face -- because it is a separate piece of
--- material and not a highlight on whatever is behind it (ART_STYLE.md 10).
function object.upright(surface, x, y0, y1, ramp, index, opts)
  opts = opts or {}
  local width = opts.width or 2
  for i = 0, width - 1 do
    local step = index
    if width > 1 then
      step = i == 0 and index + 1 or (i == width - 1 and index - 1 or index)
    end
    for y = y0, y1 do surface:set(x + i, y, palette.step(ramp, step)) end
  end
  return x, width
end

--- A horizontal member: a rail, a shelf, a plank edge. Lit on top, its own
--- shadow underneath -- the opposite of a recess (ART_STYLE.md 5).
function object.rail(surface, x0, x1, y, ramp, index, opts)
  opts = opts or {}
  local thickness = opts.thickness or 2
  for i = 0, thickness - 1 do
    local step = i == 0 and index + 1 or index - (i == thickness - 1 and 1 or 0)
    for x = x0, x1 do surface:set(x, y + i, palette.step(ramp, step)) end
  end
end

--- A box body: the workhorse silhouette of the prop library. Flat fill, lit
--- top face, shaded bottom face, and the object sitting in its own shadow.
function object.box(surface, x, y, w, h, ramp, index)
  P.rect_fill(surface, x, y, w, h, palette.step(ramp, index))
  P.rect_fill(surface, x, y, w, 1, palette.step(ramp, index + 1))
  P.rect_fill(surface, x, y + h - 1, w, 1, palette.step(ramp, index - 1))
  -- left face into the light, right face away from it
  P.rect_fill(surface, x, y, 1, h, palette.step(ramp, index + 1))
  P.rect_fill(surface, x + w - 1, y, 1, h, palette.step(ramp, index - 1))
  surface:set(x + w - 1, y, palette.step(ramp, index))
end

--- A cylinder body, shaded across its width: turned edge, specular strip one
--- pixel in, body, shaded side. Same read as the barrel, which is what makes a
--- drum, a pipe and a bin look like the same world.
function object.cylinder(surface, x, y, w, h, ramp, index)
  for i = 0, w - 1 do
    local t = i / math.max(1, w - 1)
    local step
    if t < 0.10 then step = index + 1
    elseif t < 0.25 then step = index + 2
    elseif t < 0.65 then step = index
    else step = index - 1 end
    for yy = y, y + h - 1 do surface:set(x + i, yy, palette.step(ramp, step)) end
  end
end

return object
