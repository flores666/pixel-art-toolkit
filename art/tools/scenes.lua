-- scenes.lua -- automatically composed location previews.
--
-- WHY THIS EXISTS
--
-- Every validator in this toolkit judges ONE asset (or one generator's
-- variants). None of them can see the failures that only appear when a level
-- is built: a terrain that tiles beautifully and still reads as static over
-- fifty cells; two terrains whose transition works and whose FIELDS clash; a
-- prop that is legible alone and invisible against the ground it will actually
-- stand on; scale that is consistent within a kit and wrong between kits; and
-- prop density, which no single asset can be wrong about.
--
-- So the toolkit composes whole locations out of nothing but its own assets
-- and writes them out at 1x and enlarged. They are visual QA maps, not
-- gameplay: there is no logic here, only placement.
--
-- HOW A SCENE IS BUILT
--
-- 1. A terrain MAP -- a small grid of terrain names, painted by rectangles and
--    blobs, then resolved to tiles. Every cell whose four corners are one
--    terrain gets that terrain's field tile; every cell whose corners differ
--    gets the transition tile for that pair and corner mask. That resolution
--    is the same corner-Wang rule the transition set is generated from
--    (terrain.CORNERS), so the scene exercises the autotile system rather than
--    reimplementing it.
-- 2. DECALS, scattered at a declared density and filtered by their `over`
--    list, so oil lands on tarmac and leaf litter does not land in a road.
-- 3. OBJECTS, placed from a list. Multi-tile assets are placed by their
--    footprint and their cells are reserved so nothing overlaps.
--
-- Cell seeds come from `rng.variant(seed, "x,y")`, so a scene is a pure
-- function of its seed like everything else, and re-running reproduces it.

local P = require("pixel_utils")
local rng = require("rng")
local style = require("style")
local terrain = require("terrain")
local generators = require("generators")

local scenes = {}

local TILE = style.tile

-- Terrain painting -----------------------------------------------------------

--- A mutable terrain grid. Corner-addressed: a cell's terrain is decided by
--- its four CORNERS, so the grid is (w+1) x (h+1) corner samples.
local Map = {}
Map.__index = Map

function scenes.map(w, h, base)
  local m = setmetatable({ w = w, h = h, corners = {} }, Map)
  for y = 0, h do
    m.corners[y] = {}
    for x = 0, w do m.corners[y][x] = base end
  end
  return m
end

function Map:set(x, y, name)
  if self.corners[y] and x >= 0 and x <= self.w then self.corners[y][x] = name end
end

function Map:get(x, y)
  local row = self.corners[math.max(0, math.min(self.h, y))]
  return row[math.max(0, math.min(self.w, x))]
end

--- Paint an axis-aligned rectangle of corners.
function Map:rect(x0, y0, w, h, name)
  for y = y0, y0 + h do
    for x = x0, x0 + w do self:set(x, y, name) end
  end
end

--- Paint a road or path: a band with a wandering centre line, which is what
--- keeps a road from reading as a ruler drawn across the map.
function Map:band(from_x, from_y, to_x, to_y, width, name, rng_stream)
  local steps = math.max(math.abs(to_x - from_x), math.abs(to_y - from_y))
  local drift = 0
  for i = 0, steps do
    local t = steps == 0 and 0 or i / steps
    local cx = math.floor(from_x + (to_x - from_x) * t + 0.5)
    local cy = math.floor(from_y + (to_y - from_y) * t + 0.5)
    if rng_stream:chance(0.3) then drift = math.max(-2, math.min(2, drift + rng_stream:range(-1, 1))) end
    local half = width // 2
    for d = -half, width - half - 1 do
      -- a band runs across its own direction: horizontal-ish bands widen in y
      if math.abs(to_x - from_x) >= math.abs(to_y - from_y) then
        self:set(cx, cy + d + drift, name)
      else
        self:set(cx + d + drift, cy, name)
      end
    end
  end
end

--- Paint an irregular patch, grown from a seed. Used for scrub, spoil, mud.
function Map:blob(cx, cy, size, name, rng_stream)
  local cells, seen = { { cx, cy } }, { [cy * 512 + cx] = true }
  local painted = 0
  while #cells > 0 and painted < size do
    local i = rng_stream:range(1, #cells)
    local cell = table.remove(cells, i)
    self:set(cell[1], cell[2], name)
    painted = painted + 1
    for _, d in ipairs { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
      local nx, ny = cell[1] + d[1], cell[2] + d[2]
      local k = ny * 512 + nx
      if not seen[k] and nx >= 0 and ny >= 0 and nx <= self.w and ny <= self.h then
        seen[k] = true
        -- bias towards the seed so the patch stays compact rather than
        -- sprawling into a ribbon, for the same reason P.cluster does
        if rng_stream:chance(0.75) then cells[#cells + 1] = { nx, ny } end
      end
    end
  end
end

--- Remove three-way corner junctions.
--
-- A cell whose four corners carry three or more terrains has no tile and
-- should not: covering it needs a piece per ordered combination, which is a
-- combinatorial explosion for a case that never has to happen -- separating
-- two boundaries by one cell removes it entirely.
--
-- So the map is simplified before it is resolved: any cell with three or more
-- corner terrains has its minority corners rewritten to the cell's majority.
-- That is what a level designer does by hand when a tilemap refuses a
-- junction, and having the composer do it means a scene can be painted freely
-- with overlapping blobs -- which is how these maps are written -- and still
-- resolve completely. Repeated until stable, because rewriting one cell's
-- corner can create a junction in its neighbour.
--
-- Convergence is guaranteed rather than hoped for. Rewriting one cell's corner
-- changes four cells, so a purely local fix can push a junction into a
-- neighbour and the passes can chase each other around; the first version ran
-- eight passes and left a few dozen unresolved. So there are two phases: the
-- gentle one keeps a real boundary in the cell (majority plus the commonest
-- minority) and runs to a fixed point, and then a final forced phase flattens
-- anything still three-way to its majority outright. The forced phase strictly
-- reduces the number of distinct terrains touching each cell and cannot
-- introduce a new junction, so it terminates.
-- @return number of corners rewritten
function Map:simplify()
  -- ONE gentle pass. Iterating to a fixed point rewrote 1128 corners on a
  -- 1066-cell map -- more corners than the map has -- and dissolved the shapes
  -- the scene had painted: a four-cell-wide road came out as a grey amoeba.
  -- Fixing a junction rewrites corners shared with four neighbours, so a local
  -- pass has no fixed point to chase, and chasing it destroys the input.
  --
  -- One pass removes most junctions while leaving the painted shapes intact;
  -- resolve_cell degrades whatever survives, which moves a boundary by one
  -- cell in a few dozen places out of a thousand. That is the right trade.
  local rewritten = 0
  for pass = 1, 1 do
    local forced = false
    local changed = 0
    for y = 0, self.h - 1 do
      for x = 0, self.w - 1 do
        local corners = {
          { x, y }, { x + 1, y }, { x + 1, y + 1 }, { x, y + 1 },
        }
        local tally, order = {}, {}
        for _, c in ipairs(corners) do
          local n = self:get(c[1], c[2])
          if not tally[n] then tally[n] = 0; order[#order + 1] = n end
          tally[n] = tally[n] + 1
        end
        if #order > 2 then
          -- the majority terrain, tie-broken on the name so the result is
          -- deterministic
          local best, best_n = nil, -1
          for _, n in ipairs(order) do
            if tally[n] > best_n or (tally[n] == best_n and n < best) then best, best_n = n, tally[n] end
          end
          -- keep the majority and ONE minority (whichever is next commonest),
          -- so the cell still carries a real boundary rather than being
          -- flattened to a single terrain
          local second, second_n = nil, -1
          for _, n in ipairs(order) do
            if n ~= best and (tally[n] > second_n or (tally[n] == second_n and n < second)) then
              second, second_n = n, tally[n]
            end
          end
          for _, c in ipairs(corners) do
            local n = self:get(c[1], c[2])
            -- forced: keep only the majority, which cannot create a junction
            if n ~= best and (forced or n ~= second) then
              self:set(c[1], c[2], best)
              changed = changed + 1
            end
          end
        end
      end
    end
    rewritten = rewritten + changed
    if changed == 0 then break end
  end
  return rewritten
end

-- Resolution -----------------------------------------------------------------

--- Which generator draws the cell at (x, y)?
--
-- This is the corner-Wang lookup, and it is deliberately the ONLY place the
-- scene composer knows about transitions. A cell has four corner terrains:
--   * all four the same  -> that terrain's field generator;
--   * exactly two names  -> the transition set for that pair, at the corner
--                           mask formed by which corners carry the `over`
--                           terrain;
--   * three or more      -> DEGRADED to the two commonest, because no tile
--                           exists for a three-way junction and none should:
--                           covering it needs a piece per ordered combination.
--
-- Resolution never fails. `Map:simplify` removes about 97% of three-way
-- junctions up front, but it cannot remove them all -- flattening one cell
-- rewrites corners shared with four neighbours and can create a junction in
-- one of them, so a purely local pass has no fixed point to reach. Rather than
-- iterate and hope, the remaining handful are degraded here: the rarest
-- terrain in the cell is treated as its commonest, which produces a real
-- transition tile between the two that dominate. Visually it moves a boundary
-- by one cell.
--
-- The alternative -- reporting them and drawing nothing -- leaves holes in the
-- map, which is strictly worse than a boundary in slightly the wrong place.
-- The count is still reported so a designer can see it.
-- @return generator name, nil, or nil plus a reason
local function resolve_cell(map, x, y)
  local tl, tr = map:get(x, y), map:get(x + 1, y)
  local br, bl = map:get(x + 1, y + 1), map:get(x, y + 1)
  local corner_terrain = { tl, tr, br, bl }
  local tally, order = {}, {}
  for _, n in ipairs(corner_terrain) do
    if not tally[n] then tally[n] = 0; order[#order + 1] = n end
    tally[n] = tally[n] + 1
  end

  if #order == 1 then
    local t = terrain.get(order[1])
    -- NOT `return assert(t.generator, msg)`: assert returns ALL its arguments,
    -- so that returned (generator, message) and the caller logged the assert
    -- text as a warning on every single-terrain cell -- 602 of them.
    assert(t.generator, "terrain " .. order[1] .. " has no field generator")
    return t.generator
  end

  local degraded
  if #order > 2 then
    -- keep the two commonest, tie-broken on the name so the result is
    -- deterministic, and fold everything else into the commonest
    table.sort(order, function(a, b)
      if tally[a] ~= tally[b] then return tally[a] > tally[b] end
      return a < b
    end)
    local keep_a, keep_b = order[1], order[2]
    for i = 1, 4 do
      local n = corner_terrain[i]
      if n ~= keep_a and n ~= keep_b then corner_terrain[i] = keep_a end
    end
    degraded = ("%d terrains met at cell %d,%d (%s); folded into %s + %s")
      :format(#order, x, y, table.concat(order, "+"), keep_a, keep_b)
    tl, tr, br, bl = corner_terrain[1], corner_terrain[2], corner_terrain[3], corner_terrain[4]
    order = { keep_a, keep_b }
    if keep_a == keep_b then order = { keep_a } end
  end

  if #order == 1 then
    return terrain.get(order[1]).generator, degraded
  end

  -- two terrains: find the pair, in whichever order it is registered
  local a, b = order[1], order[2]
  local pair_id, over = a .. "_" .. b, b
  if not terrain.pairs[pair_id] then
    pair_id, over = b .. "_" .. a, a
  end
  if not terrain.pairs[pair_id] then
    return nil, ("no transition set for %s <-> %s at cell %d,%d"):format(a, b, x, y)
  end

  local mask = 0
  for i, c in ipairs(terrain.CORNERS) do
    if corner_terrain[i] == over then mask = mask | c.bit end
  end
  if mask == 0 or mask == style.terrain.masks then
    -- Every corner agrees after all (the two names resolved to one side); fall
    -- back to the field tile so the scene never draws a "transition" that has
    -- no boundary in it.
    local t = terrain.get(mask == 0 and terrain.pair(pair_id).base or over)
    return t.generator
  end
  return ("transition_%s_%02d"):format(pair_id, mask)
end

scenes.resolve_cell = resolve_cell

-- Composition ----------------------------------------------------------------

--- Compose a scene.
-- spec:
--   name, title
--   map        a Map
--   decals     { { name = "decal_stones", density = 0.04 }, ... }
--   objects    { { name = "rusted_barrel", count = 3, on = { terrains } }, ... }
--   seed
-- @return Surface, report table
function scenes.compose(spec)
  local map = spec.map
  local seed = spec.seed or 1
  local surface = P.new(map.w * TILE, map.h * TILE)
  local report = { name = spec.name, warnings = {}, tiles = 0, decals = 0, objects = 0,
    used = {} }
  -- Painted maps overlap freely, so three-way junctions are normal input.
  -- Simplify them away before resolving rather than reporting hundreds of
  -- cells the tileset was never going to cover.
  report.simplified = map:simplify()

  -- 1. terrain
  for y = 0, map.h - 1 do
    for x = 0, map.w - 1 do
      local name, why = resolve_cell(map, x, y)
      if why then report.warnings[#report.warnings + 1] = why end
      if not name then
        report.holes = (report.holes or 0) + 1
      else
        local cell_seed = rng.variant(seed, ("t%d,%d"):format(x, y), 1000) + 1
        surface:blit(generators.build(name, cell_seed), x * TILE, y * TILE)
        report.tiles = report.tiles + 1
        report.used[name] = (report.used[name] or 0) + 1
      end
    end
  end

  -- occupancy, so decals and objects do not pile onto each other
  local taken = {}
  local function reserve(x, y) taken[y * 512 + x] = true end
  local function free(x, y) return not taken[y * 512 + x] end

  -- 1b. MODULAR RUNS.
  --
  -- Walls and fences are connectivity kits, and scattering their pieces at
  -- random defeats the entire point of the socket system -- a scene full of
  -- single fence panels standing alone in a field tells you nothing about
  -- whether the kit connects, which is the one thing it exists to do. So a run
  -- is placed as a run: an end piece, a sequence of middles drawn from a
  -- weighted list, and an end piece.
  --
  -- This is also the only part of the composer that exercises the sockets, so
  -- it is what makes these scenes a real test of them rather than a gallery.
  local run_rng = rng.new(seed, "runs")
  for _, run in ipairs(spec.runs or {}) do
    local length = run.length or 6
    local x, y = run.x, run.y
    local dx, dy = (run.dir == "v" and 0 or 1), (run.dir == "v" and 1 or 0)
    -- Every piece in a run must fit and be unoccupied, or the run is skipped
    -- rather than half-drawn: half a fence is worse than none.
    local plan = {}
    for i = 0, length - 1 do
      local name
      if i == 0 then name = run.start or run.middle[1].value
      elseif i == length - 1 then name = run.finish or run.start or run.middle[1].value
      else name = run_rng:weighted(run.middle) end
      local gen = generators.get(name)
      local tw, th = gen.size.w // TILE, gen.size.h // TILE
      local px, py = x + dx * i, y + dy * i
      if px < 0 or py < 0 or px + tw > map.w or py + th > map.h then plan = nil break end
      for oy = 0, th - 1 do
        for ox = 0, tw - 1 do
          if not free(px + ox, py + oy) then plan = nil break end
        end
        if not plan then break end
      end
      if not plan then break end
      plan[#plan + 1] = { name = name, x = px, y = py, tw = tw, th = th }
    end
    if plan then
      for _, piece in ipairs(plan) do
        local gen = generators.get(piece.name)
        surface:blit(generators.build(piece.name, run_rng:range(1, math.max(1, gen.variants))),
          piece.x * TILE, piece.y * TILE)
        for oy = 0, piece.th - 1 do
          for ox = 0, piece.tw - 1 do reserve(piece.x + ox, piece.y + oy) end
        end
        report.objects = report.objects + 1
        report.used[piece.name] = (report.used[piece.name] or 0) + 1
      end
      report.runs = (report.runs or 0) + 1
    else
      report.warnings[#report.warnings + 1] =
        ("run at %d,%d (%s) did not fit"):format(run.x, run.y, run.dir or "h")
    end
  end

  -- 2. objects first: they are the composition, and decals should dress
  -- around them rather than be overwritten by them
  local obj_rng = rng.new(seed, "objects")
  for _, o in ipairs(spec.objects or {}) do
    local gen = generators.get(o.name)
    local tw, th = gen.size.w // TILE, gen.size.h // TILE
    local placed = 0
    for _ = 1, (o.count or 1) * 12 do
      if placed >= (o.count or 1) then break end
      local x = obj_rng:range(0, map.w - tw)
      local y = obj_rng:range(0, map.h - th)
      -- every cell of the footprint must be free, and the ground under the
      -- object's BASE cell must be a terrain the object is allowed on
      local ok = true
      for dy = 0, th - 1 do
        for dx = 0, tw - 1 do if not free(x + dx, y + dy) then ok = false end end
      end
      if ok and o.on then
        local under = map:get(x, y + th)
        ok = false
        for _, t in ipairs(o.on) do if t == under then ok = true end end
      end
      if ok and o.avoid_edges then
        ok = x > 0 and y > 0 and x + tw < map.w and y + th < map.h
      end
      if ok then
        local s = obj_rng:range(1, math.max(1, gen.variants))
        surface:blit(generators.build(o.name, s), x * TILE, y * TILE)
        for dy = 0, th - 1 do for dx = 0, tw - 1 do reserve(x + dx, y + dy) end end
        placed = placed + 1
        report.objects = report.objects + 1
        report.used[o.name] = (report.used[o.name] or 0) + 1
      end
    end
    if placed < (o.count or 1) then
      report.warnings[#report.warnings + 1] =
        ("only placed %d/%d of %s (no room)"):format(placed, o.count or 1, o.name)
    end
  end

  -- 3. decals, over the terrain and around the objects
  local dec_rng = rng.new(seed, "decals")
  for _, d in ipairs(spec.decals or {}) do
    local gen = generators.get(d.name)
    local allowed = {}
    for _, t in ipairs(gen.over or {}) do allowed[t] = true end
    local want = math.max(1, math.floor(map.w * map.h * (d.density or 0.03)))
    for _ = 1, want * 6 do
      if report.used[d.name] and report.used[d.name] >= want then break end
      local x = dec_rng:range(0, map.w - 1)
      local y = dec_rng:range(0, map.h - 1)
      -- a decal belongs on a surface it declares itself compatible with, and
      -- the honest test is the terrain of the cell's own corners
      local here = map:get(x, y)
      if free(x, y) and (next(allowed) == nil or allowed[here]) then
        local s = dec_rng:range(1, math.max(1, gen.variants))
        surface:blit(generators.build(d.name, s), x * TILE, y * TILE)
        reserve(x, y)
        report.decals = report.decals + 1
        report.used[d.name] = (report.used[d.name] or 0) + 1
      end
    end
  end

  return surface, report
end

-- The three scenes -----------------------------------------------------------
--
-- Each is large enough to expose the things a single tile cannot: repetition,
-- transition problems, scale inconsistency between kits, palette drift,
-- excessive noise, and prop density. They are deliberately different in
-- character so that between them they use most of the library.

scenes.list = { "roadside", "industrial_yard", "settlement_edge" }

--- Scene A: an abandoned rural roadside. Mostly ground and vegetation, so it
--- is the scene that tests whether a FIELD holds up -- the hardest thing in
--- the whole toolkit and the reason the decal system exists.
function scenes.roadside(seed)
  local r = rng.new(seed or 1, "roadside")
  local m = scenes.map(40, 26, "dry_grass")
  -- FEW, LARGE zones. Ten overlapping blobs of terrains that sit close in
  -- value produced a leopard pattern of yellow and brown -- camouflage at map
  -- scale, which is the same defect as camouflage at tile scale and just as
  -- fatal. Three big regions read as places; ten small ones read as noise.
  for _ = 1, 3 do
    m:blob(r:range(4, 36), r:range(2, 24), r:range(90, 150), "sparse_grass", r)
  end
  m:blob(r:range(4, 18), r:range(18, 24), r:range(60, 100), "dirt", r)
  -- the road, running across with a shoulder of dirt either side
  m:band(-1, 15, 41, 12, 6, "dirt", r)
  m:band(-1, 15, 41, 12, 4, "asphalt", r)
  -- a track leaving it, and a wet hollow at the bottom
  m:band(28, 13, 34, 26, 3, "dirt", r)
  m:blob(8, 23, 40, "mud", r)
  return {
    name = "roadside", title = "Scene A -- abandoned rural roadside",
    map = m, seed = seed or 1,
    -- A field boundary fence along the top, and a short one by the track.
    runs = {
      { x = 2, y = 3, dir = "h", length = 14, start = "fence_post_end",
        middle = { { value = "fence_straight", weight = 5 },
                   { value = "fence_post_mid", weight = 2 },
                   { value = "fence_damaged", weight = 2 },
                   { value = "fence_broken", weight = 1 } } },
      { x = 24, y = 21, dir = "h", length = 8, start = "fence_post_end",
        middle = { { value = "fence_straight", weight = 4 },
                   { value = "fence_damaged", weight = 2 },
                   { value = "fence_hole", weight = 1 } } },
    },
    objects = {
      { name = "utility_pole", count = 3, on = { "dry_grass", "sparse_grass", "dirt" } },
      { name = "utility_pole_damaged", count = 1, on = { "dry_grass", "sparse_grass" } },
      { name = "road_sign", count = 1, on = { "dirt", "sparse_grass" } },
      { name = "road_sign_broken", count = 1, on = { "dirt", "dry_grass" } },
      { name = "roadside_marker", count = 4, on = { "dirt", "sparse_grass", "dry_grass" } },
      { name = "dead_tree", count = 3, on = { "dry_grass", "sparse_grass" } },
      { name = "sick_tree", count = 2, on = { "dry_grass", "sparse_grass" } },
      { name = "dead_bush", count = 6, on = { "dry_grass", "sparse_grass", "dirt" } },
      { name = "dry_scrub", count = 5, on = { "dry_grass", "sparse_grass" } },
      { name = "tall_grass_clump", count = 8, on = { "dry_grass", "sparse_grass" } },
      { name = "fallen_log", count = 2, on = { "dry_grass", "sparse_grass" } },
      { name = "tree_stump", count = 3, on = { "dry_grass", "sparse_grass" } },
      { name = "rock_medium", count = 3, on = { "dry_grass", "dirt", "sparse_grass" } },
      { name = "rock_small", count = 5, on = { "dry_grass", "dirt" } },
      { name = "rusted_barrel", count = 2, on = { "dirt", "dry_grass" } },
      { name = "concrete_block", count = 2, on = { "dirt", "asphalt" } },
      { name = "pipe_segment", count = 1, on = { "dry_grass", "dirt" } },
    },
    decals = {
      { name = "decal_grass_tuft", density = 0.030 },
      { name = "decal_dead_vegetation", density = 0.020 },
      { name = "decal_stones", density = 0.015 },
      { name = "decal_dirt_patch", density = 0.012 },
      { name = "decal_dust", density = 0.010 },
      { name = "decal_leaves", density = 0.012 },
      { name = "decal_crack", density = 0.010 },
      { name = "decal_pothole", density = 0.006 },
      { name = "decal_weeds", density = 0.008 },
      { name = "decal_rubble", density = 0.006 },
      { name = "decal_trash", density = 0.005 },
    },
  }
end

--- Scene B: a ruined industrial yard. Hard surfaces, fences, infrastructure and
--- heavy props -- the scene that tests whether the man-made kits agree with
--- each other about scale and about how a run of pieces connects.
function scenes.industrial_yard(seed)
  local r = rng.new(seed or 1, "yard")
  local m = scenes.map(40, 26, "dirt")
  -- the yard itself: a big concrete apron with the tarmac approach across it
  m:rect(4, 4, 30, 17, "concrete")
  m:band(-1, 10, 41, 11, 5, "asphalt", r)
  -- Where the apron has failed, and what has grown into it. Two large areas
  -- each, not five small ones: broken tarmac and intact tarmac share a base
  -- colour, so scattering them produces a mottled grey field in which neither
  -- reads. Kept to the middle so the apron's rectangular edge survives -- the
  -- yard has to read as a made thing.
  for _ = 1, 2 do
    m:blob(r:range(10, 28), r:range(7, 18), r:range(50, 90), "broken_asphalt", r)
  end
  m:blob(r:range(6, 32), r:range(16, 20), r:range(50, 80), "gravel", r)
  -- and the grass coming in from outside the yard, on the margins only
  m:blob(r:range(1, 6), r:range(1, 24), r:range(60, 110), "dry_grass", r)
  m:blob(r:range(34, 39), r:range(1, 24), r:range(60, 110), "dry_grass", r)
  return {
    name = "industrial_yard", title = "Scene B -- ruined industrial yard",
    map = m, seed = seed or 1,
    -- The yard perimeter: a wall run along the back, a fence line with a gate
    -- across the front, and a return down the side. This is what actually
    -- tests the socket system in a composed scene.
    runs = {
      { x = 3, y = 2, dir = "h", length = 16, start = "wall_end", finish = "wall_corner_outer",
        middle = { { value = "wall_straight", weight = 5 },
                   { value = "wall_damaged_top", weight = 3 },
                   { value = "wall_broken", weight = 2 },
                   { value = "wall_broken_heavy", weight = 1 },
                   { value = "wall_rubble_base", weight = 2 },
                   { value = "wall_doorway", weight = 1 } } },
      { x = 18, y = 3, dir = "v", length = 7,
        start = "wall_straight_v", finish = "wall_straight_v",
        middle = { { value = "wall_straight_v", weight = 1 } } },
      { x = 2, y = 22, dir = "h", length = 18, start = "fence_post_end",
        middle = { { value = "fence_straight", weight = 5 },
                   { value = "fence_post_mid", weight = 2 },
                   { value = "fence_damaged", weight = 2 },
                   { value = "fence_hole", weight = 1 },
                   { value = "fence_broken", weight = 1 } } },
      { x = 21, y = 22, dir = "h", length = 2,
        start = "fence_gate", finish = "fence_gate",
        middle = { { value = "fence_gate", weight = 1 } } },
    },
    objects = {
      -- infrastructure
      { name = "lamp_post", count = 2, on = { "concrete", "asphalt" } },
      { name = "lamp_post_broken", count = 1, on = { "concrete", "broken_asphalt" } },
      { name = "electrical_cabinet", count = 2, on = { "concrete", "gravel" } },
      { name = "junction_box", count = 2, on = { "concrete" } },
      { name = "road_barrier", count = 3, on = { "asphalt", "concrete" } },
      { name = "pipe_segment", count = 2, on = { "concrete", "gravel" } },
      { name = "pipe_bent", count = 2, on = { "concrete", "gravel" } },
      { name = "manhole", count = 2, on = { "concrete", "asphalt" } },
      { name = "drain", count = 2, on = { "concrete", "asphalt" } },
      -- what is left lying about
      { name = "rusted_barrel", count = 6, on = { "concrete", "gravel", "asphalt" } },
      { name = "supply_crate", count = 3, on = { "concrete" } },
      { name = "metal_crate", count = 3, on = { "concrete", "gravel" } },
      { name = "pallet", count = 4, on = { "concrete", "gravel" } },
      { name = "scrap_pile", count = 4, on = { "concrete", "gravel", "dirt" } },
      { name = "metal_sheet", count = 3, on = { "concrete", "gravel" } },
      { name = "rubble_large", count = 2, on = { "concrete", "broken_asphalt" } },
      { name = "rubble_medium", count = 4, on = { "concrete", "gravel" } },
      { name = "metal_debris", count = 3, on = { "concrete", "gravel" } },
      { name = "barricade", count = 2, on = { "asphalt", "concrete" } },
      { name = "sandbag_barrier", count = 1, on = { "concrete", "gravel" } },
      { name = "trash_bin", count = 2, on = { "concrete" } },
      { name = "dead_bush", count = 4, on = { "dirt", "gravel", "dry_grass" } },
    },
    decals = {
      { name = "decal_oil_stain", density = 0.020 },
      { name = "decal_crack", density = 0.022 },
      { name = "decal_pothole", density = 0.012 },
      { name = "decal_rubble", density = 0.022 },
      { name = "decal_scrap", density = 0.016 },
      { name = "decal_stain_dark", density = 0.014 },
      { name = "decal_dirt_patch", density = 0.012 },
      { name = "decal_glass", density = 0.008 },
      { name = "decal_weeds", density = 0.016 },
      { name = "decal_trash", density = 0.010 },
      { name = "decal_stones", density = 0.010 },
    },
  }
end

--- Scene C: the overgrown edge of a destroyed settlement. Buildings gone to
--- rubble with vegetation taking it back -- the scene that tests the
--- structure kits against the natural ones, which is where scale and palette
--- inconsistency between kits would show worst.
function scenes.settlement_edge(seed)
  local r = rng.new(seed or 1, "settlement")
  local m = scenes.map(40, 26, "dry_grass")
  -- what is left of the streets
  m:band(-1, 8, 41, 9, 4, "dirt", r)
  m:band(-1, 8, 41, 9, 2, "broken_asphalt", r)
  m:band(20, -1, 22, 27, 3, "dirt", r)
  -- the footprints of two buildings
  m:rect(5, 13, 11, 8, "concrete")
  m:rect(26, 3, 9, 7, "concrete")
  -- And the vegetation reclaiming all of it: three large sweeps rather than a
  -- dozen patches, so the map reads as ground going back to scrub instead of
  -- as mottling.
  for _ = 1, 3 do
    m:blob(r:range(3, 37), r:range(2, 24), r:range(110, 170), "sparse_grass", r)
  end
  for _ = 1, 2 do
    m:blob(r:range(6, 34), r:range(4, 22), r:range(60, 100), "dirt_grass", r)
  end
  m:blob(r:range(8, 32), r:range(6, 22), r:range(40, 70), "gravel", r)
  return {
    name = "settlement_edge", title = "Scene C -- overgrown destroyed settlement edge",
    map = m, seed = seed or 1,
    -- The two building footprints, drawn as wall runs so what is left of each
    -- reads as one structure rather than as scattered masonry. Mostly
    -- collapsed pieces, which is the point of the scene.
    runs = {
      { x = 5, y = 13, dir = "h", length = 11, start = "wall_end", finish = "wall_end",
        middle = { { value = "wall_collapsed", weight = 4 },
                   { value = "wall_broken_heavy", weight = 3 },
                   { value = "wall_broken", weight = 2 },
                   { value = "wall_straight", weight = 1 },
                   { value = "wall_doorway", weight = 1 } } },
      { x = 26, y = 3, dir = "h", length = 9, start = "wall_end", finish = "wall_corner_outer",
        middle = { { value = "wall_collapsed", weight = 3 },
                   { value = "wall_broken_heavy", weight = 3 },
                   { value = "wall_broken", weight = 2 },
                   { value = "wall_straight", weight = 2 } } },
      { x = 34, y = 4, dir = "v", length = 5,
        start = "wall_straight_v", finish = "wall_straight_v",
        middle = { { value = "wall_straight_v", weight = 1 } } },
      { x = 3, y = 22, dir = "h", length = 10, start = "fence_post_end",
        middle = { { value = "fence_broken", weight = 3 },
                   { value = "fence_hole", weight = 2 },
                   { value = "fence_straight", weight = 2 },
                   { value = "fence_damaged", weight = 2 } } },
    },
    objects = {
      { name = "collapsed_wall_debris", count = 3, on = { "concrete", "dirt_grass", "sparse_grass" } },
      { name = "rubble_large", count = 3, on = { "concrete", "dirt_grass" } },
      { name = "rubble_medium", count = 5, on = { "sparse_grass", "dirt_grass", "gravel" } },
      { name = "concrete_chunks", count = 4, on = { "dirt_grass", "sparse_grass" } },
      { name = "brick_debris", count = 3, on = { "dirt_grass", "gravel" } },
      { name = "burnt_debris", count = 3, on = { "concrete", "dirt_grass" } },
      { name = "mixed_rubble", count = 4, on = { "sparse_grass", "gravel" } },
      { name = "wood_debris", count = 3, on = { "dry_grass", "sparse_grass" } },
      -- the street furniture that outlasted the buildings
      { name = "utility_pole", count = 2, on = { "dry_grass", "sparse_grass" } },
      { name = "utility_pole_damaged", count = 2, on = { "sparse_grass", "dirt_grass" } },
      { name = "lamp_post_broken", count = 2, on = { "dirt", "dirt_grass" } },
      -- and what is growing through it
      { name = "sick_tree", count = 4, on = { "dry_grass", "sparse_grass", "dirt_grass" } },
      { name = "dead_tree", count = 2, on = { "sparse_grass", "dirt_grass" } },
      { name = "dead_bush", count = 8, on = { "dry_grass", "sparse_grass", "dirt_grass" } },
      { name = "dry_scrub", count = 6, on = { "sparse_grass", "dirt_grass" } },
      { name = "tall_grass_clump", count = 10, on = { "dry_grass", "sparse_grass", "dirt_grass" } },
      { name = "broken_trunk", count = 2, on = { "sparse_grass", "dry_grass" } },
      { name = "tree_stump", count = 3, on = { "dry_grass", "sparse_grass" } },
      { name = "rock_cluster", count = 2, on = { "sparse_grass", "gravel" } },
      { name = "rock_large", count = 1, on = { "sparse_grass", "dry_grass" } },
      -- household wreckage
      { name = "cabinet_broken", count = 2, on = { "concrete", "dirt_grass" } },
      { name = "locker", count = 1, on = { "concrete" } },
      { name = "bench", count = 2, on = { "dirt", "sparse_grass" } },
      { name = "chair", count = 3, on = { "concrete", "dirt_grass", "sparse_grass" } },
      { name = "small_table", count = 2, on = { "concrete", "dirt_grass" } },
      { name = "trash_pile", count = 3, on = { "concrete", "dirt_grass" } },
      { name = "rusted_barrel", count = 3, on = { "concrete", "dirt", "gravel" } },
      { name = "wooden_crate", count = 2, on = { "concrete", "dirt_grass" } },
    },
    decals = {
      { name = "decal_grass_tuft", density = 0.030 },
      { name = "decal_weeds", density = 0.018 },
      { name = "decal_rubble", density = 0.026 },
      { name = "decal_dead_vegetation", density = 0.018 },
      { name = "decal_crack", density = 0.016 },
      { name = "decal_stain_dark", density = 0.014 },
      { name = "decal_dirt_patch", density = 0.014 },
      { name = "decal_leaves", density = 0.016 },
      { name = "decal_trash", density = 0.012 },
      { name = "decal_glass", density = 0.008 },
      { name = "decal_scrap", density = 0.010 },
      { name = "decal_stones", density = 0.012 },
    },
  }
end

--- Build one scene by name.
-- @return Surface, report
function scenes.build(name, seed)
  local fn = scenes[name] or error("unknown scene '" .. tostring(name) .. "'", 2)
  return scenes.compose(fn(seed))
end

return scenes
