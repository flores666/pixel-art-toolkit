-- terrain.lua -- the terrain registry and the autotile (Wang) system.
--
-- Two problems live here, and they are the same problem twice:
--
--   1. What a terrain IS: the material grammar that fills a field of it, in
--      one place, so `dirt_ground` and every dirt transition tile are filled
--      by the same code and cannot drift apart.
--   2. Where two terrains MEET: a 16-tile corner Wang set per pair, complete
--      enough to lay out with (centre, edges, outer corners, inner corners,
--      diagonals) and generated from one implementation rather than by hand
--      per pair.
--
-- ---------------------------------------------------------------------------
-- The boundary
-- ---------------------------------------------------------------------------
--
-- A tile's four CORNERS each carry a terrain: base or over. That is 16
-- configurations, indexed as a bitmask (see CORNERS below), and it is exactly
-- Godot's TERRAIN_MODE_MATCH_CORNERS, so the generated set drops into a
-- TileSet terrain without a translation layer.
--
-- Coverage is a thresholded bilinear blend of the corner weights:
--
--     f(u,v) = TL(1-u)(1-v) + TR·u(1-v) + BL(1-u)v + BR·u·v      over = f > 0.5
--
-- which puts the boundary crossing at the exact MIDPOINT of any edge whose two
-- corners differ, and nowhere on an edge whose corners agree. Two tiles laid
-- side by side compute that from their own corners and get the same answer, so
-- the boundary meets across the join. Straight edges come out straight, outer
-- corners convex, inner corners concave -- the whole connectivity set falls out
-- of one formula instead of sixteen hand-drawn cases.
--
-- A boundary drawn on that formula alone is a clean geometric curve, which is
-- right for a cast concrete edge and quite wrong for grass meeting dirt. So the
-- threshold is displaced by value noise -- and the displacement is WEIGHTED TO
-- ZERO at the tile edges:
--
--     threshold(x,y) = 0.5 + amplitude · pin(x,y) · noise(x,y)
--
-- This is the same invariant that makes a decayed cast joint tileable
-- (`concrete.groove`), and it is the only reason a ragged edge can tile at all:
--
--     A BOUNDARY IS PINNED TO ITS IDEAL POSITION AT THE TILE EDGE AND MAY
--     WANDER ONLY IN THE MIDDLE.
--
-- Break it -- let the noise reach the border -- and every tile join in the
-- transition band shows a step, which is a visible grid drawn along exactly
-- the places the eye is already looking.
--
-- ---------------------------------------------------------------------------
-- What a pair owns
-- ---------------------------------------------------------------------------
--
-- Geometry is shared; the MEANING of the boundary is not. Soil creeping over a
-- road is not the same event as a cast slab butting against tarmac, so each
-- pair declares its own amplitude and its own `edge` decoration, which is
-- handed the boundary pixels and draws what belongs there: tufts leaning off a
-- grass edge, silt and crumbled tarmac at a road edge, a dark cast joint with
-- a lit lip where two man-made surfaces meet.

local P = require("pixel_utils")
local palette = require("palette")
local style = require("style")
local rng = require("rng")
local materials = require("materials")

local terrain = {}

-- Corner bits. Order is fixed and is part of the tile naming, so it may not be
-- reshuffled: masks are baked into generator names and levels reference those.
terrain.CORNERS = {
  { bit = 1, u = 0, v = 0, name = "tl" },
  { bit = 2, u = 1, v = 0, name = "tr" },
  { bit = 4, u = 1, v = 1, name = "br" },
  { bit = 8, u = 0, v = 1, name = "bl" },
}

--- Human-readable name for a corner mask, used in reports and previews.
local MASK_SHAPE = {
  [0]  = "base",          [15] = "centre",
  [3]  = "edge_top",      [12] = "edge_bottom",
  [9]  = "edge_left",     [6]  = "edge_right",
  [1]  = "corner_tl",     [2]  = "corner_tr",
  [4]  = "corner_br",     [8]  = "corner_bl",
  [14] = "inner_tl",      [13] = "inner_tr",
  [11] = "inner_br",      [7]  = "inner_bl",
  [5]  = "diagonal_tlbr", [10] = "diagonal_trbl",
}
terrain.mask_shape = MASK_SHAPE

--- Which of the four EDGES of the tile are entirely one terrain. An edge is
--- pure when both of its corners agree, and that is what the transition_edges
--- validator checks the pixels against: a tile whose top edge is pure base
--- must present base material along its whole top row, or it will not abut the
--- tile above it.
-- @return table { top = "base"|"over"|"mixed", right, bottom, left }
function terrain.edge_terrains(mask)
  local tl = (mask & 1) ~= 0
  local tr = (mask & 2) ~= 0
  local br = (mask & 4) ~= 0
  local bl = (mask & 8) ~= 0
  local function of(a, b)
    if a and b then return "over" end
    if not a and not b then return "base" end
    return "mixed"
  end
  return { top = of(tl, tr), right = of(tr, br), bottom = of(br, bl), left = of(bl, tl) }
end

-- Value noise ---------------------------------------------------------------

-- Smooth-ish deterministic noise on a lattice of `cell` pixels, bilinearly
-- interpolated and WRAPPING on the lattice so a transition tile still tiles
-- against copies of itself along the run of the boundary.
local function value_noise(seed, cell, extent)
  local n = math.max(1, extent // cell)
  local grid = {}
  local r = rng.new(seed, "terrain_noise")
  for gy = 0, n - 1 do
    grid[gy] = {}
    for gx = 0, n - 1 do grid[gy][gx] = r:float() * 2 - 1 end
  end
  return function(x, y)
    local fx, fy = x / cell, y / cell
    local x0, y0 = math.floor(fx), math.floor(fy)
    local tx, ty = fx - x0, fy - y0
    -- smoothstep, so the lobes are rounded rather than diamond-shaped
    tx = tx * tx * (3 - 2 * tx)
    ty = ty * ty * (3 - 2 * ty)
    local function at(gx, gy) return grid[gy % n][gx % n] end
    local a = at(x0, y0) + (at(x0 + 1, y0) - at(x0, y0)) * tx
    local b = at(x0, y0 + 1) + (at(x0 + 1, y0 + 1) - at(x0, y0 + 1)) * tx
    return a + (b - a) * ty
  end
end

-- How far the wander is allowed to have ramped in at (x, y): 0 on the border
-- rows and columns, 1 once we are `pin_width` inside. This is the pinning
-- invariant, and it is the whole trick.
local function pin_weight(x, y, w, h)
  local d = math.min(x, y, w - 1 - x, h - 1 - y)
  local pin = style.terrain.pin_width
  if d >= pin then return 1 end
  return d / pin
end

--- The coverage mask for one corner configuration.
-- @return function(x, y) -> true where the OVER terrain wins
function terrain.coverage(mask, w, h, opts)
  opts = opts or {}
  local amp = opts.amplitude or 0.20
  local noise = amp > 0 and value_noise(opts.seed or 1, opts.cell or style.terrain.noise_cell,
    math.max(w, h)) or nil
  local weights = {}
  for _, c in ipairs(terrain.CORNERS) do
    weights[c.name] = (mask & c.bit) ~= 0 and 1 or 0
  end
  return function(x, y)
    local u = (x + 0.5) / w
    local v = (y + 0.5) / h
    local f = weights.tl * (1 - u) * (1 - v)
      + weights.tr * u * (1 - v)
      + weights.bl * (1 - u) * v
      + weights.br * u * v
    local threshold = 0.5
    if noise then
      threshold = threshold + amp * pin_weight(x, y, w, h) * noise(x, y)
    end
    return f > threshold
  end
end

--- The boundary pixels of a coverage mask: over-terrain pixels that touch base
--- terrain (4-neighbour). Edge decoration is drawn from this list, so a pair's
--- decoration never has to know which mask it is drawing.
function terrain.boundary(covered, w, h)
  local out = {}
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      if covered(x, y) then
        if not covered(x + 1, y) or not covered(x - 1, y)
          or not covered(x, y + 1) or not covered(x, y - 1) then
          out[#out + 1] = { x, y }
        end
      end
    end
  end
  return out
end

-- Terrain types --------------------------------------------------------------
--
-- A terrain owns the fill of a field of itself, and NOTHING else: no marks, no
-- damage, no vegetation. Those are decals now (see decals.lua), because a mark
-- baked into a field tile is printed a hundred times and a decal is placed
-- where the level wants one. That division is what finally got the fields
-- calm; before it, every tile carried a feature and a field of them read as
-- static however carefully each tile was drawn.
--
-- Contract:
--   name        string, also the terrain id in the manifest
--   title
--   base        the ramp step a field of it is mostly made of. The validator
--               does not check this, the eye does: it is the colour the player
--               spends the whole game looking at.
--   fill(surface, rng_stream, opts)   opts.area, opts.mask
--   wear        0..1 default character, passed through to the material
terrain.types = {}
terrain.names = {}

local function register(t)
  assert(not terrain.types[t.name], "duplicate terrain " .. t.name)
  terrain.types[t.name] = t
  terrain.names[#terrain.names + 1] = t.name
  return t
end

--- Bare dry soil. The default ground of the surface world.
register {
  name = "dirt", title = "Dirt", base = "earth_3",
  fill = function(s, r, opts) materials.earth.fill(s, r, opts) end,
}

--- Last year's straw, standing. The default ground away from the roads.
register {
  name = "dry_grass", title = "Dry grass", base = "straw_2",
  fill = function(s, r, opts)
    materials.grass.fill(s, r, setmetatable({ tufts = false, bare = 0 }, { __index = opts }))
  end,
}

--- Straw thinning out over the soil beneath it: the ground you get on a verge
--- that is losing. Its own terrain rather than a transition, because a
--- transition is a boundary and this is a CONDITION -- it needs to tile in
--- every direction over a whole area.
register {
  name = "sparse_grass", title = "Sparse grass", base = "straw_2",
  fill = function(s, r, opts)
    materials.grass.fill(s, r, setmetatable({ tufts = false, bare = 0, thin = 0.34 },
      { __index = opts }))
  end,
}

--- Trodden ground: soil with the last of the straw in it. The other end of the
--- same gradient as sparse_grass, read from the dirt side.
register {
  name = "dirt_grass", title = "Dirt and grass", base = "earth_3",
  fill = function(s, r, opts)
    materials.earth.fill(s, r, setmetatable({ dust = "straw_2", drift = 0.30 },
      { __index = opts }))
  end,
}

--- Road. Intact, because damage is a decal and a road that is uniformly broken
--- is not a broken road, it is a texture.
register {
  name = "asphalt", title = "Asphalt", base = "asphalt_3",
  fill = function(s, r, opts) materials.asphalt.fill(s, r, opts) end,
}

--- Road that has gone. Kept as a terrain of its own so a level can lay a whole
--- area of collapsed surface without stacking a hundred damage decals; the
--- break-up is in the FILL, spread across the tile rather than concentrated,
--- which is the honest read for a surface that has failed everywhere.
register {
  name = "broken_asphalt", title = "Heavily damaged asphalt", base = "asphalt_3",
  fill = function(s, r, opts)
    materials.asphalt.fill(s, r, setmetatable({ ruin = 0.75 }, { __index = opts }))
  end,
}

--- Concrete hardstanding: yards, aprons, slab paths.
register {
  name = "concrete", title = "Concrete ground", base = "concrete_4",
  fill = function(s, r, opts)
    materials.concrete.fill(s, r, setmetatable({ wear = 0.35, ground = true },
      { __index = opts }))
  end,
}

--- Wet ground in a hollow. The darkest ground in the set, which is what makes
--- it read as wet: there is no blue and no shine in this palette, so depth of
--- value is the only cue available.
register {
  name = "mud", title = "Mud", base = "earth_2",
  fill = function(s, r, opts)
    materials.earth.fill(s, r, setmetatable({ base = "earth_2", dust = "earth_3", drift = 0.22 },
      { __index = opts }))
  end,
}

--- Gravel and stony dirt: a track, a rail bed, a yard surface. This is the one
--- terrain whose texture is legitimately granular, so it is the one place
--- where paired specks are the grammar rather than a defect.
register {
  name = "gravel", title = "Gravel / rocky dirt", base = "earth_3",
  fill = function(s, r, opts)
    materials.earth.fill(s, r, setmetatable({ dust = "straw_2", drift = 0.14 },
      { __index = opts }))
    local grit = r:branch("gravel")
    -- Stones are the SURFACE here, not an event on it, so they are dense --
    -- but still drawn as stones (a lit cap and its shadow), never as noise.
    materials.earth.stones(s, grit:range(5, 7), grit, {
      area = opts and opts.area, mask = opts and opts.mask,
      color = "concrete_3", shadow = "earth_2",
    })
  end,
}

function terrain.get(name)
  return terrain.types[name] or error("unknown terrain '" .. tostring(name) .. "'", 2)
end

-- Field tiles ----------------------------------------------------------------
--
-- `terrain.marks` is the vocabulary of HAIRLINE marks a field tile may carry:
-- one thin structure, on a minority of tiles, and nothing else. The game's own
-- authored floor tiles are built exactly this way -- 70-78% of the area at one
-- colour, the rest a few hairline scratches -- and it is the only kind of
-- detail that survives being repeated a hundred times.
--
-- Everything larger is a DECAL. That split is the single most important change
-- in this system: before it, a field tile carried its own stones, tufts,
-- cracks and chunks, each defensible alone, and a hundred of them together
-- read as static. A stone baked into a field tile is a stone printed a hundred
-- times; a stone decal is a stone where the level wanted one.
terrain.marks = {
  --- The shrinkage crust of dried compacted soil.
  crust = function(s, r, opts)
    materials.earth.crust(s, r, { wear = (opts and opts.wear) or 0.4,
      length = r:range(5, 8), mask = opts and opts.mask })
  end,
  --- One bleached stem left standing above the mat.
  stem = function(s, r, opts)
    materials.grass.blade(s, r:range(0, s.width - 1), r:range(0, s.height - 1),
      r:range(3, 5), r, { mask = opts and opts.mask })
  end,
  --- A hairline fracture in a hard surface. Short: a long one is damage, and
  --- damage is a decal.
  hairline = function(s, r, opts)
    local color = (opts and opts.color) or "asphalt_2"
    materials.asphalt.crack(s, r:range(0, s.width - 1), r:range(0, s.height - 1),
      r:range(5, 8), r, { color = color, branches = 0, mask = opts and opts.mask })
  end,
  --- A vehicle rut pressed into soft ground: two shallow parallel runs.
  rut = function(s, r, opts)
    local mask = opts and opts.mask
    local y = r:range(0, s.height - 1)
    local axis = r:chance(0.5) and "h" or "v"
    for _, off in ipairs { 0, r:range(3, 5) } do
      P.broken_run(s, axis, (y + off) % (axis == "h" and s.height or s.width),
        0, (axis == "h" and s.width or s.height) - 1, r,
        { delta = -1, run = { 4, 8 }, gap = { 2, 4 }, mask = mask })
    end
  end,
}

--- Draw one FIELD tile of a terrain: the fill, plus at most one hairline mark.
--
-- Every ground generator in the library goes through here, which is what makes
-- nine terrains one material family rather than nine separate opinions about
-- how calm a field ought to be.
-- @param opts { mark = name in terrain.marks, mark_chance = 0..1, wear, ... }
function terrain.field(s, name, rng_stream, opts)
  opts = opts or {}
  local t = terrain.get(name)
  t.fill(s, rng_stream:branch("fill"), opts)
  if opts.mark then
    local mark = terrain.marks[opts.mark] or error("unknown terrain mark " .. opts.mark, 2)
    if rng_stream:branch("mark_roll"):chance(opts.mark_chance or 0.25) then
      mark(s, rng_stream:branch("mark"), opts)
    end
  end
  P.despeckle(s)
  return s
end

-- Pairs ----------------------------------------------------------------------
--
-- `base` is what is already there; `over` is what has arrived. That ordering
-- is not cosmetic -- it decides which side the decoration hangs off, and it is
-- what the corner mask means (a set bit says "over is in this corner").
--
--   amplitude  how far the boundary may wander from the ideal, as a fraction
--              of the blend. 0.05 is a cast joint; 0.30 is a grass edge.
--   edge       what to draw along the boundary. Handed the boundary pixel list.
terrain.pairs = {}
terrain.pair_names = {}

local function pair(p)
  p.id = p.base .. "_" .. p.over
  assert(not terrain.pairs[p.id], "duplicate terrain pair " .. p.id)
  terrain.get(p.base); terrain.get(p.over)
  terrain.pairs[p.id] = p
  terrain.pair_names[#terrain.pair_names + 1] = p.id
  return p
end

-- Edge decorations -----------------------------------------------------------

--- Vegetation taking hold along its own leading edge. Tufts, sparse, leaning
--- one way for the whole tile -- a boundary lined with tufts every two pixels
--- is a hedge, and a boundary with tufts leaning in different directions is
--- confetti with extra steps.
local function grass_edge(s, boundary, r, opts)
  if #boundary == 0 then return end
  local lean = r:chance(0.5) and 1 or -1
  local n = math.min(2, math.max(1, #boundary // 7))
  for i = 1, n do
    local at = boundary[r:range(1, #boundary)]
    materials.grass.tufts(s, 1, r, {
      at = { at[1], at[2] }, lean = lean, mask = opts and opts.mask,
      color = r:chance(0.35) and "grass_2" or "straw_1",
    })
  end
end

--- Soil washed onto a hard surface stops at a crumbling lip. The tarmac breaks
--- up where it is unsupported, and the silt collects against it: one event
--- with two halves, which is what makes it read as an edge rather than as two
--- unrelated marks meeting.
local function soil_over_hard_edge(s, boundary, r, opts)
  if #boundary < 4 then return end
  local mask = opts and opts.mask
  -- the hard surface crumbles just OUTSIDE the soil, on the base side
  for i = 1, math.max(1, #boundary // 8) do
    local at = boundary[r:range(1, #boundary)]
    materials.asphalt.breakup(s, at[1] + r:range(-1, 1), at[2] + r:range(-1, 1),
      r:range(3, 5), r, { mask = mask })
  end
  -- and a couple of grains of it end up on top of the soil
  if r:chance(0.5) then
    local at = boundary[r:range(1, #boundary)]
    materials.debris.fill(s, r, {
      coverage = 0.05, area = { x = at[1] - 2, y = at[2] - 2, w = 5, h = 5 },
      kinds = { { value = "asphalt_4", weight = 2 }, { value = "concrete_3", weight = 1 } },
      mask = mask,
    })
  end
end

--- Two man-made surfaces butt against each other at a CAST JOINT: a dark line
--- with its lit lip on the side the key light reaches. It follows the Wang
--- boundary exactly, which is why these pairs get almost no wander -- a poured
--- edge that wanders is not a poured edge.
local function cast_joint(s, boundary, r, opts)
  local mask = opts and opts.mask
  for _, p in ipairs(boundary) do
    local c = s:get(p[1], p[2])
    if c ~= palette.TRANSPARENT then
      P.pixel(s, p[1], p[2], palette.shift(c, -2), mask)
    end
  end
  -- the lit lip, on the lower-right side of the cut, broken so the arris chips
  for _, p in ipairs(boundary) do
    if r:chance(0.45) then
      local c = s:get(p[1] + 1, p[2] + 1)
      if c ~= palette.TRANSPARENT then P.pixel(s, p[1] + 1, p[2] + 1, palette.shift(c, 1), mask) end
    end
  end
end

--- Grass through a hard surface: it only gets in where the surface has already
--- failed, so the boundary is cracked before it is green.
local function grass_over_hard_edge(s, boundary, r, opts)
  if #boundary < 4 then return end
  local mask = opts and opts.mask
  -- The crack is on a MINORITY of these tiles. A boundary that is cracked
  -- along its whole length is not a surface failing at its edge, it is a
  -- drawn line -- and stacking a crack under every tuft on every tile put
  -- these tiles over the transition ceiling (measured 0.350 against 0.34).
  if r:chance(0.45) then
    local at = boundary[r:range(1, #boundary)]
    materials.asphalt.crack(s, at[1], at[2], r:range(4, 7), r, { mask = mask, branches = 0 })
  end
  grass_edge(s, boundary, r, opts)
end

pair { base = "dirt",     over = "dry_grass",      amplitude = 0.30, edge = grass_edge }
pair { base = "dirt",     over = "sparse_grass",   amplitude = 0.32, edge = grass_edge }
pair { base = "asphalt",  over = "dirt",           amplitude = 0.22, edge = soil_over_hard_edge }
pair { base = "asphalt",  over = "dry_grass",      amplitude = 0.24, edge = grass_over_hard_edge }
pair { base = "concrete", over = "dirt",           amplitude = 0.20, edge = soil_over_hard_edge }
pair { base = "concrete", over = "dry_grass",      amplitude = 0.22, edge = grass_over_hard_edge }
pair { base = "asphalt",  over = "concrete",       amplitude = 0.05, edge = cast_joint }

function terrain.pair(id)
  return terrain.pairs[id] or error("unknown terrain pair '" .. tostring(id) .. "'", 2)
end

--- Draw one transition tile. This is the whole autotile implementation: every
--- one of the 7 pairs x 15 masks x N seeds tiles in the library comes out of
--- here, so a fix to a boundary is a fix to all of them.
-- @param s      wrapping Surface, tile-sized
-- @param id     pair id ("dirt_dry_grass")
-- @param mask   0..15 corner mask
-- @param opts   { worn = bool }  worn adds break-up along the boundary
function terrain.draw(s, id, mask, rng_stream, opts)
  opts = opts or {}
  local p = terrain.pair(id)
  local base = terrain.get(p.base)
  local over = terrain.get(p.over)

  -- silhouette: the two regions. The base terrain fills the whole tile first,
  -- so the over terrain never has to know what shape it is standing on and a
  -- boundary pixel always has base material on the other side of it.
  base.fill(s, rng_stream:branch("base"), {})
  local covered = terrain.coverage(mask, s.width, s.height, {
    amplitude = p.amplitude,
    seed = rng_stream:branch("boundary"):next(),
  })
  if mask ~= 0 then
    local over_mask = function(x, y)
      local nx, ny = x % s.width, y % s.height
      return covered(nx, ny)
    end
    over.fill(s, rng_stream:branch("over"), { mask = over_mask })
  end

  -- structure: what the boundary itself is
  local boundary = terrain.boundary(covered, s.width, s.height)
  if p.edge and mask ~= 0 and mask ~= 15 then
    p.edge(s, boundary, rng_stream:branch("edge"), {})
  end

  -- damage: the worn variant of the boundary. A verge that vehicles have been
  -- driving over, a slab edge that has been hit. Only where there IS a
  -- boundary, and it is the boundary that breaks -- not the field.
  if opts.worn and #boundary > 3 then
    local w = rng_stream:branch("worn")
    for _ = 1, w:range(1, 2) do
      local at = boundary[w:range(1, #boundary)]
      materials.debris.fill(s, w, {
        coverage = 0.10, area = { x = at[1] - 2, y = at[2] - 2, w = 5, h = 5 },
        kinds = { { value = "concrete_3", weight = 2 }, { value = "earth_2", weight = 1 } },
      })
    end
  end

  P.despeckle(s)
  return covered, boundary
end

return terrain
