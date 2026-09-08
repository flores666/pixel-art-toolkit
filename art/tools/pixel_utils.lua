-- pixel_utils.lua -- the Surface type and every drawing primitive.
--
-- A Surface is a plain Lua array of packed palette colours. It is the only
-- thing generators, materials, validators and previews ever touch, which is
-- why the whole toolkit runs (and is tested) outside Aseprite; aseprite.lua
-- converts a Surface to an Aseprite Image at the very edge.
--
-- Rules baked into these primitives:
--   * integer coordinates only, 0-based, matching Aseprite image space;
--   * every colour goes through palette.resolve, so an off-palette value
--     cannot be drawn at all;
--   * no primitive ever writes a partial alpha;
--   * `wrap` surfaces address pixels modulo the size, which is how tileable
--     assets get clusters that cross an edge and come back on the other side.

local palette = require("palette")
local style = require("style")

local P = {}

-- Surface --------------------------------------------------------------------

local Surface = {}
Surface.__index = Surface
P.Surface = Surface

--- @param opts table|nil { wrap = bool, fill = colour }
function P.new(w, h, opts)
  opts = opts or {}
  local fill = palette.resolve(opts.fill)
  local s = setmetatable({
    width = w, height = h, wrap = opts.wrap or false, data = {},
  }, Surface)
  for i = 1, w * h do s.data[i] = fill end
  return s
end

function Surface:clone()
  local s = P.new(self.width, self.height, { wrap = self.wrap })
  table.move(self.data, 1, self.width * self.height, 1, s.data)
  return s
end

--- Map a coordinate into the surface. Returns nil when it falls outside and
-- the surface does not wrap.
function Surface:norm(x, y)
  if self.wrap then
    return x % self.width, y % self.height
  end
  if x < 0 or y < 0 or x >= self.width or y >= self.height then return nil end
  return x, y
end

function Surface:get(x, y)
  local nx, ny = self:norm(x, y)
  if not nx then return palette.TRANSPARENT end
  return self.data[ny * self.width + nx + 1]
end

function Surface:set(x, y, color)
  local nx, ny = self:norm(x, y)
  if not nx then return false end
  self.data[ny * self.width + nx + 1] = palette.resolve(color)
  return true
end

--- Write a raw packed value WITHOUT palette checking. The only legitimate
-- caller is the Aseprite import path: validators must be able to look at art
-- that breaks the rules, otherwise they could never report it.
function Surface:set_raw(x, y, packed)
  local nx, ny = self:norm(x, y)
  if not nx then return false end
  self.data[ny * self.width + nx + 1] = packed
  return true
end

function Surface:clear(color)
  local c = palette.resolve(color)
  for i = 1, self.width * self.height do self.data[i] = c end
end

function Surface:is_opaque(x, y)
  return self:get(x, y) ~= palette.TRANSPARENT
end

--- Iterate every pixel: for x, y, color in surface:pixels() do ... end
function Surface:pixels()
  local i, n = -1, self.width * self.height
  return function()
    i = i + 1
    if i >= n then return nil end
    local x, y = i % self.width, i // self.width
    return x, y, self.data[i + 1]
  end
end

--- Draw `src` at (dx, dy). Transparent source pixels are skipped unless
-- opts.replace is set.
function Surface:blit(src, dx, dy, opts)
  opts = opts or {}
  for x, y, c in src:pixels() do
    if c ~= palette.TRANSPARENT or opts.replace then
      self:set(dx + x, dy + y, c)
    end
  end
  return self
end

--- Stable fingerprint of the pixel data; used by the determinism tests.
function Surface:fingerprint()
  local h = 2166136261
  for i = 1, self.width * self.height do
    local v = self.data[i]
    for _ = 1, 4 do
      h = ((h ~ (v & 0xFF)) * 16777619) & 0xFFFFFFFF
      v = v >> 8
    end
  end
  return ("%08X"):format(h)
end

-- Areas and masks ------------------------------------------------------------

--- Normalise an optional area to { x, y, w, h }, defaulting to the whole surface.
function P.area(surface, a)
  if not a then return { x = 0, y = 0, w = surface.width, h = surface.height } end
  return { x = a.x or 0, y = a.y or 0, w = a.w or surface.width, h = a.h or surface.height }
end

--- Predicate matching only pixels that belong to a given palette ramp. Wear
-- overlays use it so rust lands on metal and not on an outline or a hole.
function P.ramp_mask(ramp_name)
  return function(_, _, color)
    local ramp = palette.slot(color)
    return ramp == ramp_name
  end
end

--- Combine an optional caller mask with an area into one predicate.
function P.mask(surface, opts)
  opts = opts or {}
  local a = P.area(surface, opts.area)
  local user = opts.mask
  return function(x, y, c)
    if not surface.wrap and (x < a.x or y < a.y or x >= a.x + a.w or y >= a.y + a.h) then
      return false
    end
    if surface.wrap then
      local nx, ny = x % surface.width, y % surface.height
      if nx < a.x or ny < a.y or nx >= a.x + a.w or ny >= a.y + a.h then return false end
    end
    if user and not user(x, y, c or surface:get(x, y)) then return false end
    return true
  end
end

-- Primitives -----------------------------------------------------------------

--- Single pixel, honouring an optional mask.
function P.pixel(surface, x, y, color, mask)
  if mask and not mask(x, y, surface:get(x, y)) then return false end
  return surface:set(x, y, color)
end

--- Bresenham line. Hard pixels only: no anti-aliasing, ever.
function P.line(surface, x0, y0, x1, y1, color, opts)
  opts = opts or {}
  local mask = opts.mask
  local dx, dy = math.abs(x1 - x0), -math.abs(y1 - y0)
  local sx = x0 < x1 and 1 or -1
  local sy = y0 < y1 and 1 or -1
  local err = dx + dy
  while true do
    P.pixel(surface, x0, y0, color, mask)
    if x0 == x1 and y0 == y1 then break end
    local e2 = 2 * err
    if e2 >= dy then err = err + dy; x0 = x0 + sx end
    if e2 <= dx then err = err + dx; y0 = y0 + sy end
  end
end

function P.hline(surface, x, y, len, color, opts)
  P.line(surface, x, y, x + len - 1, y, color, opts)
end

function P.vline(surface, x, y, len, color, opts)
  P.line(surface, x, y, x, y + len - 1, color, opts)
end

--- Rectangle outline (1px).
function P.rect(surface, x, y, w, h, color, opts)
  P.hline(surface, x, y, w, color, opts)
  P.hline(surface, x, y + h - 1, w, color, opts)
  P.vline(surface, x, y + 1, h - 2, color, opts)
  P.vline(surface, x + w - 1, y + 1, h - 2, color, opts)
end

function P.rect_fill(surface, x, y, w, h, color, opts)
  opts = opts or {}
  local mask = opts.mask
  for yy = y, y + h - 1 do
    for xx = x, x + w - 1 do
      P.pixel(surface, xx, yy, color, mask)
    end
  end
end

--- Scanline polygon fill, even-odd. Vertices are PIXEL COORDINATES, not grid
-- corners, so the edges themselves are part of the shape: the polygon
-- {2,2},{10,2},{10,6},{2,6} fills exactly the same 9x5 block as rect_fill.
-- The interior is scanline-filled and the outline is walked with Bresenham,
-- which also keeps thin or degenerate polygons from vanishing.
-- points = { {x, y}, {x, y}, ... } in order; the polygon closes itself.
function P.polygon_fill(surface, points, color, opts)
  opts = opts or {}
  local mask = opts.mask
  local n = #points
  if n < 3 then return end
  local miny, maxy = math.huge, -math.huge
  for _, p in ipairs(points) do
    miny = math.min(miny, p[2]); maxy = math.max(maxy, p[2])
  end
  for y = math.floor(miny), math.floor(maxy) do
    local cy = y + 0.5
    local xs = {}
    for i = 1, n do
      local a, b = points[i], points[i % n + 1]
      local ay, by = a[2], b[2]
      if (ay <= cy and by > cy) or (by <= cy and ay > cy) then
        xs[#xs + 1] = a[1] + (cy - ay) / (by - ay) * (b[1] - a[1])
      end
    end
    table.sort(xs)
    for i = 1, #xs - 1, 2 do
      local x0 = math.floor(xs[i] + 0.5)
      local x1 = math.ceil(xs[i + 1] - 0.5)
      for x = x0, x1 do P.pixel(surface, x, y, color, mask) end
    end
  end
  for i = 1, n do
    local a, b = points[i], points[i % n + 1]
    P.line(surface, a[1], a[2], b[1], b[2], color, opts)
  end
end

--- Grow a connected blob of `size` pixels outwards from (x, y).
--
-- Growth is radial, not a random walk: each step takes the candidate nearest
-- the seed, with `opts.spread` worth of jitter mixed in. A depth-first walk
-- produces ribbons, and a field of ribbons reads as camouflage rather than as
-- ground -- so compact is the default and spread is opt-in.
--   spread 0.0  a tight round patch (a stone, a tuft)
--   spread 0.5  a lobed patch (soil mottling, rust)
--   spread 1.5+ a wandering ribbon (a root, a stain running downhill)
--
-- `size` is a pixel count and is honoured up to the size of the surface. It
-- used to be clamped at style.cluster_max * 4, which silently truncated any
-- caller asking for a large REGION -- a soil drift, a broken-out area of road
-- -- down to a 40-pixel blob. Small marks are a material's business (that is
-- what style.cluster_max and style.speck_max are for); a primitive that
-- quietly draws something other than what it was asked for is a trap.
-- On a wrapping surface distance is measured the short way round, so a blob
-- that crosses an edge stays compact instead of stretching back across the tile.
-- @return list of {x, y} actually painted
function P.cluster(surface, x, y, size, color, rng_stream, opts)
  opts = opts or {}
  local mask = opts.mask
  local spread = opts.spread or 0.4
  size = math.max(1, math.min(size, surface.width * surface.height))

  local function axis_delta(a, b, extent)
    local d = math.abs(a - b)
    if surface.wrap then d = math.min(d, extent - d) end
    return d
  end

  local painted, seen, candidates = {}, {}, { { x, y } }
  local function key(px, py)
    local nx, ny = surface:norm(px, py)
    if not nx then return nil end
    return ny * surface.width + nx
  end
  local k0 = key(x, y)
  if k0 then seen[k0] = true end

  while #painted < size and #candidates > 0 do
    local best_i, best_cost
    for i, c in ipairs(candidates) do
      local dx = axis_delta(c[1], x, surface.width)
      local dy = axis_delta(c[2], y, surface.height)
      local cost = dx * dx + dy * dy + rng_stream:float() * spread * size
      if not best_cost or cost < best_cost then best_cost, best_i = cost, i end
    end
    local cell = table.remove(candidates, best_i)
    local cx, cy = cell[1], cell[2]
    if P.pixel(surface, cx, cy, color, mask) then
      painted[#painted + 1] = { cx, cy }
      for _, nb in ipairs { { cx + 1, cy }, { cx - 1, cy }, { cx, cy + 1 }, { cx, cy - 1 } } do
        local k = key(nb[1], nb[2])
        if k and not seen[k] then
          seen[k] = true
          candidates[#candidates + 1] = nb
        end
      end
    end
  end
  return painted
end

-- The eight compass directions, in order, so that adding 1 turns 45 degrees.
local COMPASS = {
  { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 },
  { -1, 0 }, { -1, -1 }, { 0, -1 }, { 1, -1 },
}
P.compass = COMPASS

--- A hairline fracture: a one-pixel-wide walk that HOLDS ITS HEADING, kinks by
-- 45 degrees at a joint, and throws branches at a wide angle.
--
-- This is the shape of a crack, and getting it right is the difference between
-- damage and a scratch. A walk that re-picks its direction every other step
-- produces a scribble that reads as a stray diagonal mark; a real fracture runs
-- in straight segments of several pixels and changes direction at a joint,
-- because it is following stress, not wandering. Cracks in soil, asphalt and
-- concrete all share that geometry -- only their colour, extent and what
-- crumbles beside them differ, which is what each material owns.
--
-- opts:
--   heading        0..7 into P.compass; default random. Segments kink around it
--   segment        { lo, hi } pixels between kinks (default { 3, 5 })
--   branches       how many branches to throw off the trunk (default 0)
--   branch_length  { lo, hi } (default { 3, 5 })
--   mask
-- @return list of { x, y } actually painted, trunk first
function P.fracture(surface, x, y, length, color, rng_stream, opts)
  opts = opts or {}
  local mask = opts.mask
  local seg_lo, seg_hi = table.unpack(opts.segment or { 3, 5 })
  local drawn = {}

  local function walk(cx, cy, len, heading)
    local run = rng_stream:range(seg_lo, seg_hi)
    for i = 1, len do
      if P.pixel(surface, cx, cy, color, mask) then drawn[#drawn + 1] = { cx, cy } end
      if i % run == 0 then
        -- a joint: turn 45 degrees, one way or the other, and keep going
        heading = (heading + (rng_stream:chance(0.5) and 1 or 7)) % 8
        run = rng_stream:range(seg_lo, seg_hi)
      end
      local d = COMPASS[heading + 1]
      cx, cy = cx + d[1], cy + d[2]
    end
    return heading
  end

  local heading = opts.heading or rng_stream:range(0, 7)
  local trunk_end = #drawn
  heading = walk(x, y, length, heading)

  -- Branches leave the trunk at a wide angle, from somewhere along it rather
  -- than from its tip: a fracture that only ever forks at the end reads as a
  -- letter Y, not as damage.
  local bl_lo, bl_hi = table.unpack(opts.branch_length or { 3, 5 })
  for _ = 1, (opts.branches or 0) do
    if trunk_end + 2 > #drawn then break end
    local at = drawn[rng_stream:range(trunk_end + 2, #drawn - 1)]
    if not at then break end
    local turn = rng_stream:chance(0.5) and 2 or 6
    walk(at[1], at[2], rng_stream:range(bl_lo, bl_hi), (heading + turn + rng_stream:range(-1, 1)) % 8)
  end
  return drawn
end

--- Scatter `count` small clusters inside an area. The smallest speck is two
-- pixels wide, which is the rule that keeps output from looking like AI dust.
function P.speckle(surface, count, color, rng_stream, opts)
  opts = opts or {}
  local a = P.area(surface, opts.area)
  local mask = P.mask(surface, opts)
  local lo = opts.min_size or style.speck_min
  local hi = opts.max_size or style.speck_max
  local out = {}
  for _ = 1, count do
    local x = rng_stream:range(a.x, a.x + a.w - 1)
    local y = rng_stream:range(a.y, a.y + a.h - 1)
    local blob = P.cluster(surface, x, y, rng_stream:range(lo, hi), color, rng_stream, { mask = mask })
    for _, p in ipairs(blob) do out[#out + 1] = p end
  end
  return out
end

--- Ordered 2x2 dither, anchored to absolute coordinates so that adjacent tiles
-- stay in phase and a tiled floor has no visible dither seam.
-- density 1..3 of 4. Use `opts.over` to only dither on top of a given colour.
-- Mixing ramp steps that are not adjacent is banding, so it raises an error
-- unless opts.allow_jump says the caller means it (a cast shadow falling
-- across several shades is the legitimate case).
function P.dither(surface, color, density, opts)
  opts = opts or {}
  local a = P.area(surface, opts.area)
  local mask = P.mask(surface, opts)
  local m = style.dither_matrix
  local over = opts.over and palette.resolve(opts.over) or nil
  local phase_x = opts.phase_x or 0
  local phase_y = opts.phase_y or 0
  local target = palette.resolve(color)
  for y = a.y, a.y + a.h - 1 do
    for x = a.x, a.x + a.w - 1 do
      local threshold = m[((y + phase_y) % 2) + 1][((x + phase_x) % 2) + 1]
      if threshold < density then
        local current = surface:get(x, y)
        if (not over or current == over) and mask(x, y, current) then
          -- Guard the "adjacent steps only" rule: dithering between distant
          -- ramp steps is banding, not shading.
          local cr, ci = palette.slot(current)
          local tr, ti = palette.slot(target)
          if not opts.allow_jump and cr and tr and cr == tr
            and math.abs(ci - ti) > style.dither_max_ramp_distance then
            error(("dither would mix %s with %s (%d ramp steps apart)")
              :format(palette.name_of[current], palette.name_of[target], math.abs(ci - ti)))
          end
          surface:set(x, y, target)
        end
      end
    end
  end
end

--- Silhouette outline: paint `color` on transparent pixels touching opaque
-- ones. Objects get one; tiles never do.
function P.outline(surface, color, opts)
  opts = opts or {}
  color = color or style.outline_color
  local diagonals = opts.diagonals
  if diagonals == nil then diagonals = style.outline_diagonals end
  local snapshot = surface:clone()
  local offsets = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
  if diagonals then
    offsets[#offsets + 1] = { 1, 1 }; offsets[#offsets + 1] = { -1, 1 }
    offsets[#offsets + 1] = { 1, -1 }; offsets[#offsets + 1] = { -1, -1 }
  end
  for x, y, c in snapshot:pixels() do
    if c == palette.TRANSPARENT then
      for _, o in ipairs(offsets) do
        if snapshot:is_opaque(x + o[1], y + o[2]) then
          P.pixel(surface, x, y, color, opts.mask)
          break
        end
      end
    end
  end
end

-- Lighting -------------------------------------------------------------------

local function empty_at(snapshot, x, y, empties)
  local c = snapshot:get(x, y)
  if c == palette.TRANSPARENT then return true end
  return empties[c] == true
end

--- Ramp-aware edge lighting for the fixed upper-left key light.
-- A pixel whose upper or left neighbour is empty steps UP its ramp; a pixel
-- whose lower or right neighbour is empty steps DOWN. Colours outside a ramp
-- (there are none by construction) are left alone.
-- opts.empty = list of colours that count as "outside the shape" (e.g. an
-- outline already drawn, or the hole of a bin).
function P.apply_lighting(surface, opts)
  opts = opts or {}
  local mask = P.mask(surface, opts)
  local snapshot = surface:clone()
  local empties = {}
  for _, c in ipairs(opts.empty or {}) do empties[palette.resolve(c)] = true end
  local lx, ly = style.light.dx, style.light.dy
  local up = opts.light_step or style.light_step
  local down = opts.shadow_step or style.shadow_step
  for x, y, c in snapshot:pixels() do
    if c ~= palette.TRANSPARENT and mask(x, y, c) then
      local lit = empty_at(snapshot, x + lx, y, empties) or empty_at(snapshot, x, y + ly, empties)
      local shaded = empty_at(snapshot, x - lx, y, empties) or empty_at(snapshot, x, y - ly, empties)
      if lit then
        surface:set(x, y, palette.shift(c, up))
      elseif shaded then
        surface:set(x, y, palette.shift(c, -down))
      end
    end
  end
end

--- Explicit highlight/shadow passes, for structure the silhouette cannot infer
-- (a raised band, the lip of a groove). `edge` is "top", "left", "bottom" or
-- "right" and the colour is taken one ramp step from what is already there.
function P.highlight_edge(surface, x, y, w, h, opts)
  opts = opts or {}
  local step = opts.step or style.light_step
  P.rect_fill_shift(surface, x, y, w, h, step, opts)
end

function P.shadow_edge(surface, x, y, w, h, opts)
  opts = opts or {}
  local step = opts.step or style.shadow_step
  P.rect_fill_shift(surface, x, y, w, h, -step, opts)
end

--- Shift every pixel of a rect along its own ramp. This is how highlights and
-- shadows stay consistent across materials without naming colours.
function P.rect_fill_shift(surface, x, y, w, h, delta, opts)
  opts = opts or {}
  local mask = opts.mask
  for yy = y, y + h - 1 do
    for xx = x, x + w - 1 do
      local c = surface:get(xx, yy)
      if c ~= palette.TRANSPARENT and (not mask or mask(xx, yy, c)) then
        surface:set(xx, yy, palette.shift(c, delta))
      end
    end
  end
end

--- Alternating runs and gaps along a row ("h") or column ("v"), from `from`
-- to `to` inclusive. This is the toolkit's answer to "a subtle edge": a 1px
-- dither on a 1px band is just stray pixels, so broken runs are used instead.
-- opts.color paints a colour; otherwise opts.delta shifts along the ramp.
function P.broken_run(surface, axis, offset, from, to, rng_stream, opts)
  opts = opts or {}
  local mask = opts.mask
  local run_lo, run_hi = table.unpack(opts.run or { 2, 5 })
  local gap_lo, gap_hi = table.unpack(opts.gap or { 1, 3 })
  local i = from
  if rng_stream:chance(0.5) then i = i + rng_stream:range(gap_lo, gap_hi) end
  while i <= to do
    -- Never leave a stub shorter than the minimum run: a one-pixel tail is
    -- exactly the stray pixel this primitive exists to avoid.
    if to - i + 1 < run_lo then break end
    local len = rng_stream:range(run_lo, run_hi)
    for k = i, math.min(to, i + len - 1) do
      local x = axis == "h" and k or offset
      local y = axis == "h" and offset or k
      local c = surface:get(x, y)
      local paintable = c ~= palette.TRANSPARENT or (opts.color and opts.on_transparent)
      if paintable and (not mask or mask(x, y, c)) then
        surface:set(x, y, opts.color or palette.shift(c, opts.delta or 1))
      end
    end
    i = i + len + rng_stream:range(gap_lo, gap_hi)
  end
end

--- Dithered shift of a band: the controlled way to fade a highlight out.
-- Only meaningful on bands at least two pixels thick (see broken_run).
function P.dither_shift(surface, delta, density, opts)
  opts = opts or {}
  local a = P.area(surface, opts.area)
  local mask = P.mask(surface, opts)
  local m = style.dither_matrix
  for y = a.y, a.y + a.h - 1 do
    for x = a.x, a.x + a.w - 1 do
      if m[(y % 2) + 1][(x % 2) + 1] < density then
        local c = surface:get(x, y)
        if c ~= palette.TRANSPARENT and mask(x, y, c) then
          surface:set(x, y, palette.shift(c, delta))
        end
      end
    end
  end
end

-- Analysis (shared by validators and previews) -------------------------------

--- Absorb stray pixels (see P.isolated) into the dominant colour around them.
-- Generators run this as the documented cleanup step, which makes "clusters,
-- never dust" true by construction instead of by hope. opts.keep(x, y, colour)
-- protects deliberate single pixels (a rivet catch-light, an eye).
--
-- The outline colour is never allowed to win the vote (opts.exclude overrides
-- the default): next to an outline it is usually the local majority, so
-- letting it win would eat a pixel out of the silhouette and leave a two-pixel
-- thick outline right there. A stray with no other neighbour is left alone.
-- @return number of pixels rewritten
function P.despeckle(surface, opts)
  opts = opts or {}
  local excluded = {}
  for _, c in ipairs(opts.exclude or { style.outline_color }) do
    excluded[palette.resolve(c)] = true
  end
  local fixed = 0
  for _, p in ipairs(P.isolated(surface, opts)) do
    if not (opts.keep and opts.keep(p.x, p.y, p.color)) then
      local votes, best, best_n = {}, nil, 0
      for dy = -1, 1 do
        for dx = -1, 1 do
          if dx ~= 0 or dy ~= 0 then
            local c = surface:get(p.x + dx, p.y + dy)
            if c ~= palette.TRANSPARENT and not excluded[c] then
              local n = (votes[c] or 0) + 1
              votes[c] = n
              -- Deterministic tie-break on the packed value.
              if n > best_n or (n == best_n and best and c < best) then best, best_n = c, n end
            end
          end
        end
      end
      if best then
        surface:set(p.x, p.y, best)
        fixed = fixed + 1
      end
    end
  end
  return fixed
end

--- Erase stray pixels instead of recolouring them.
--
-- `despeckle` votes a stray into the majority colour around it, which is the
-- right fix inside a solid body. On a mostly-TRANSPARENT asset -- a decal, a
-- prop's fringe -- a stray usually has no opaque neighbour to vote at all, so
-- despeckle leaves it exactly where it is and the asset ships with dust on it.
-- The honest fix there is deletion: a mark that ended up one pixel wide was
-- never a mark.
--
-- It erases a pixel only when the pixel is a stray by P.isolated AND has no
-- opaque 8-neighbour at all -- a true floater. A stray that is attached to
-- something is part of a mark, however odd its colour, and deleting it would
-- punch a hole in the mark instead of cleaning up after it.
--
-- opts.keep(x, y, colour) protects deliberate single pixels.
-- @return number of pixels erased
function P.strip_strays(surface, opts)
  opts = opts or {}
  local erased = 0
  local function attached(x, y)
    for dy = -1, 1 do
      for dx = -1, 1 do
        if (dx ~= 0 or dy ~= 0) and surface:is_opaque(x + dx, y + dy) then return true end
      end
    end
    return false
  end
  for _, p in ipairs(P.isolated(surface, opts)) do
    if not attached(p.x, p.y) and not (opts.keep and opts.keep(p.x, p.y, p.color)) then
      surface:set(p.x, p.y, palette.TRANSPARENT)
      erased = erased + 1
    end
  end
  return erased
end

--- Opaque fraction of the surface, 0..1.
function P.coverage(surface)
  local _, opaque = P.histogram(surface)
  return opaque / (surface.width * surface.height)
end

--- Connected components of OPAQUE pixels, 4-neighbour.
--
-- What "one mark" means, mechanically. A decal is supposed to be one thing --
-- a clump, a stain, three pebbles together -- and a prop is supposed to be one
-- object; counting islands is how a validator can tell that from a scatter,
-- which no per-pixel rule can. Wrapping surfaces wrap, so a cluster clipped by
-- a tile edge counts as the one component it will be once laid.
-- @return list of components, each { size = n, pixels = { {x,y}, ... } }
function P.components(surface, opts)
  opts = opts or {}
  local wrap = opts.wrap
  if wrap == nil then wrap = surface.wrap end
  local probe = surface
  if wrap ~= surface.wrap then probe = surface:clone(); probe.wrap = wrap end
  local seen, out = {}, {}
  local function key(x, y)
    local nx, ny = probe:norm(x, y)
    if not nx then return nil end
    return ny * surface.width + nx
  end
  for x, y, c in surface:pixels() do
    local k = key(x, y)
    if c ~= palette.TRANSPARENT and k and not seen[k] then
      local pixels, stack = {}, { { x, y } }
      seen[k] = true
      while #stack > 0 do
        local cell = table.remove(stack)
        pixels[#pixels + 1] = cell
        for _, d in ipairs { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
          local nx, ny = cell[1] + d[1], cell[2] + d[2]
          local nk = key(nx, ny)
          if nk and not seen[nk] and probe:get(nx, ny) ~= palette.TRANSPARENT then
            seen[nk] = true
            stack[#stack + 1] = { nx, ny }
          end
        end
      end
      out[#out + 1] = { size = #pixels, pixels = pixels }
    end
  end
  table.sort(out, function(a, b) return a.size > b.size end)
  return out
end

--- MARKS: how many separate things a sparse asset appears to be.
--
-- `components` answers a different question and answers it too strictly for
-- this one. It is 4-connected, so a diagonal fracture -- one mark by any
-- reading -- counts as one component per pixel; and it has no notion of
-- proximity, so a tuft whose stalks are deliberately spaced two apart
-- (ART_STYLE.md 10, or a shared lean welds them into a blob) counts as three
-- marks rather than one clump.
--
-- What actually matters for a decal is whether it reads as ONE thing in ONE
-- place or as a scatter across the cell. So marks are grouped 8-connected --
-- a diagonal run is one mark -- and with a GAP tolerance, so pixels close
-- enough to read together are one mark whether or not they touch.
-- @param opts { gap = px, default 2 }
-- @return list of { size = n, pixels = { {x,y}, ... } }, largest first
function P.mark_groups(surface, opts)
  opts = opts or {}
  local gap = opts.gap or 2
  local w, h = surface.width, surface.height
  local seen, out = {}, {}
  for x, y, c in surface:pixels() do
    local k = y * w + x
    if c ~= palette.TRANSPARENT and not seen[k] then
      local pixels, stack = {}, { { x, y } }
      seen[k] = true
      while #stack > 0 do
        local cell = table.remove(stack)
        pixels[#pixels + 1] = cell
        for dy = -gap, gap do
          for dx = -gap, gap do
            if dx ~= 0 or dy ~= 0 then
              local nx, ny = cell[1] + dx, cell[2] + dy
              if nx >= 0 and ny >= 0 and nx < w and ny < h then
                local nk = ny * w + nx
                if not seen[nk] and surface:is_opaque(nx, ny) then
                  seen[nk] = true
                  stack[#stack + 1] = { nx, ny }
                end
              end
            end
          end
        end
      end
      out[#out + 1] = { size = #pixels, pixels = pixels }
    end
  end
  table.sort(out, function(a, b) return a.size > b.size end)
  return out
end

--- Enclosed transparent regions: transparent components that do not reach the
--- border of the surface.
--
-- A bin has a mouth and a fence has a rust hole, so holes are legitimate -- but
-- they have to be DRAWN. A prop that comes out with six of them has been eaten
-- by its own wear overlays, and that is a defect no colour rule can see.
-- @return list of { size = n, pixels = { {x,y}, ... } }
function P.holes(surface)
  local w, h = surface.width, surface.height
  local seen, out = {}, {}
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local k = y * w + x
      if surface:get(x, y) == palette.TRANSPARENT and not seen[k] then
        local pixels, stack, open = {}, { { x, y } }, false
        seen[k] = true
        while #stack > 0 do
          local cell = table.remove(stack)
          pixels[#pixels + 1] = cell
          if cell[1] == 0 or cell[2] == 0 or cell[1] == w - 1 or cell[2] == h - 1 then
            open = true
          end
          for _, d in ipairs { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
            local nx, ny = cell[1] + d[1], cell[2] + d[2]
            if nx >= 0 and ny >= 0 and nx < w and ny < h then
              local nk = ny * w + nx
              if not seen[nk] and surface:get(nx, ny) == palette.TRANSPARENT then
                seen[nk] = true
                stack[#stack + 1] = { nx, ny }
              end
            end
          end
        end
        if not open then out[#out + 1] = { size = #pixels, pixels = pixels } end
      end
    end
  end
  return out
end

--- Fraction of neighbouring opaque pixel pairs whose colour differs: a plain
-- measure of how busy a surface is. The game's own hand-authored platform field
-- tiles sit at 0.10-0.17 and its wall faces near 0.25; generated texture that
-- runs far above that is noise, however legal each individual pixel is.
--
-- It is blind to contrast -- a pair counts the same whether it steps one
-- luminance or a hundred -- so a low number does not prove a surface is calm
-- and a high one does not prove it is noisy. Use it as a ceiling and judge the
-- art by looking at the field.
function P.edge_density(surface)
  local differing, pairs_seen = 0, 0
  for x, y, c in surface:pixels() do
    if c ~= palette.TRANSPARENT then
      for _, d in ipairs { { 1, 0 }, { 0, 1 } } do
        local nx, ny = x + d[1], y + d[2]
        if nx < surface.width and ny < surface.height then
          local n = surface:get(nx, ny)
          if n ~= palette.TRANSPARENT then
            pairs_seen = pairs_seen + 1
            if n ~= c then differing = differing + 1 end
          end
        end
      end
    end
  end
  if pairs_seen == 0 then return 0 end
  return differing / pairs_seen
end

--- packed -> count, transparent excluded.
function P.histogram(surface)
  local hist, total = {}, 0
  for _, _, c in surface:pixels() do
    if c ~= palette.TRANSPARENT then
      hist[c] = (hist[c] or 0) + 1
      total = total + 1
    end
  end
  return hist, total
end

function P.color_count(surface)
  local n = 0
  for _ in pairs((P.histogram(surface))) do n = n + 1 end
  return n
end

--- True stray pixels: dust that is not part of any mark.
--
-- The definition matters, and the obvious one is wrong. "An opaque pixel with
-- no neighbour of the same colour" condemns the grammar ART_STYLE.md §5
-- actually mandates: a stone is *a lit cap plus its own shadow*, and that is
-- three pixels of three different colours, so the naive rule called the
-- documented anti-dust mark three pieces of dust. Every small shaded mark in
-- the toolkit -- a stone, a chunk of debris, a tuft with a lit tip, a rivet --
-- hit the same problem, and on a mostly-transparent asset (a decal) where the
-- proportional cap is one or two pixels it was fatal.
--
-- So a stray is defined against the MARK it belongs to rather than against its
-- own colour:
--
--   * the asset's most common opaque colour is its BACKGROUND -- the field of
--     a ground tile, the body of a prop -- but only if it actually behaves
--     like a field, i.e. covers a real share of the cell. On a decal there is
--     no field at all: the commonest colour there is just part of a mark, and
--     treating it as background split every mark into pieces and condemned
--     each piece as dust. Below the threshold, every opaque pixel is a mark
--     pixel and only a true floater is a stray;
--   * every other opaque pixel is a MARK pixel. Mark pixels are grouped by
--     8-connectivity, which is what puts a cap, its shade and its shadow into
--     one group;
--   * a group of ONE is a stray. Nothing else is.
--
-- That still catches exactly what the rule exists to catch -- a lone pixel of
-- an unrelated colour dropped on a field, which is what AI dust and careless
-- speckle look like -- while a two-pixel mark remains the documented minimum
-- (style.speck_min) and passes.
--
-- Diagonal contact counts, so an ordered dither (same-coloured diagonals) is
-- legitimate. On a wrapping surface the neighbourhood wraps too, so a cluster
-- clipped by a tile edge is judged as the cluster it will be once tiled.
function P.isolated(surface, opts)
  opts = opts or {}
  local wrap = opts.wrap
  if wrap == nil then wrap = surface.wrap end
  local probe = surface
  if wrap ~= surface.wrap then
    probe = surface:clone(); probe.wrap = wrap
  end

  -- background = the most common opaque colour, tie-broken on the packed value
  -- so the answer is deterministic -- and only when it covers enough of the
  -- cell to BE a field. A third of the surface is well below the 70-82% the
  -- game's own field tiles hold at one colour, and well above anything a
  -- sparse overlay reaches.
  local hist, opaque = P.histogram(surface)
  if opaque == 0 then return {} end
  local background, best = nil, -1
  for c, n in pairs(hist) do
    if n > best or (n == best and background and c < background) then background, best = c, n end
  end
  if best < surface.width * surface.height * 0.33 then background = nil end

  local function is_mark(x, y)
    local c = probe:get(x, y)
    return c ~= palette.TRANSPARENT and c ~= background
  end

  local seen, out = {}, {}
  local function key(x, y)
    local nx, ny = probe:norm(x, y)
    if not nx then return nil end
    return ny * surface.width + nx
  end

  for x, y, c in surface:pixels() do
    local k = key(x, y)
    if c ~= palette.TRANSPARENT and c ~= background and k and not seen[k] then
      -- flood the mark this pixel belongs to, 8-connected
      local group, stack = {}, { { x, y } }
      seen[k] = true
      while #stack > 0 do
        local cell = table.remove(stack)
        group[#group + 1] = cell
        for dy = -1, 1 do
          for dx = -1, 1 do
            if dx ~= 0 or dy ~= 0 then
              local nx, ny = cell[1] + dx, cell[2] + dy
              local nk = key(nx, ny)
              if nk and not seen[nk] and is_mark(nx, ny) then
                seen[nk] = true
                stack[#stack + 1] = { nx, ny }
              end
            end
          end
        end
      end
      if #group == 1 then
        out[#out + 1] = { x = group[1][1], y = group[1][2], color = surface:get(group[1][1], group[1][2]) }
      end
    end
  end
  return out
end

return P
