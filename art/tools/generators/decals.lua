-- generators/decals.lua -- the overlay library: one mark per asset, on
-- transparency, dropped over whatever ground the level has laid.
--
-- WHY THIS EXISTS
--
-- Everything in here used to be baked into the ground tiles, and that is the
-- single biggest reason the first above-ground fields read as a procedural
-- texture. A stone drawn into a 16x16 field tile is not a stone: it is a stone
-- printed once per cell, a hundred times a screen, on a 16px pitch. Each tile
-- passed every rule; the field was static. The measurements could not see it
-- because `edge_density` counts pixel pairs that differ and cannot tell one
-- deliberate mark from a hundred of them.
--
-- So the ground tiles are now nearly flat (terrain.lua) and every mark that
-- used to live on them is here, to be PLACED. A pothole goes where the level
-- wants a pothole. That is also the only way the density of detail becomes a
-- level-design decision instead of a constant baked into the tileset.
--
-- WHAT A DECAL IS
--
--   * one mark. `style.decal.max_components` allows three islands, because
--     "three pebbles together" is one mark and "a scatter of eight things" is
--     a texture. The validator counts them;
--   * mostly transparent (`style.decal.max_coverage` = 40%). Past that it is a
--     tile, and it should be a terrain instead;
--   * SELF-LIT. There is no body under a decal to infer light from, so every
--     mark carries its own lit cap and its own cast shadow, down-right per the
--     fixed key. Without that a decal reads as a hole in the ground;
--   * clear of the cell border. Decals are placed per cell and are not
--     tileable, so a mark clipped at the edge reads as a mark cut in half.
--     MARGIN keeps them inside;
--   * declared `over`: which terrains it may sit on. Oil belongs on tarmac,
--     not in a meadow, and the scene composer honours it.
--
-- Shadows are `dirt_1` (#1F1C1A) rather than the outline ink: it is a
-- neutral-warm near-black that reads as shadow over soil, straw AND tarmac,
-- which is what a decal has to survive.

local P = require("pixel_utils")
local palette = require("palette")
local materials = require("materials")
local style = require("style")

local earth, grass, asphalt, concrete, debris, rust =
  materials.earth, materials.grass, materials.asphalt, materials.concrete,
  materials.debris, materials.rust

local MARGIN = 2
local SHADOW = "dirt_1"

local ANY = { "dirt", "dirt_grass", "dry_grass", "sparse_grass", "mud", "gravel",
              "asphalt", "broken_asphalt", "concrete" }
local HARD = { "asphalt", "broken_asphalt", "concrete" }
local SOFT = { "dirt", "dirt_grass", "dry_grass", "sparse_grass", "mud", "gravel" }

-- Helpers --------------------------------------------------------------------

--- A seed point inside the safe area.
local function spot(r, w, h, pad)
  pad = pad or MARGIN
  return r:range(pad, w - 1 - pad), r:range(pad, h - 1 - pad)
end

--- A lit cap on the upper-left of a blob and a cast shadow off its lower-right.
--- This is the pairing that separates "a thing lying on the ground" from "a
--- discoloured patch", and it is the same pairing earth.stones and debris.fill
--- use -- deliberately, so a decal stone and a baked-in stone are the same
--- object drawn by the same rules.
local function light_blob(s, blob, color, opts)
  opts = opts or {}
  if #blob == 0 then return end
  local top, bottom = blob[1], blob[1]
  for _, b in ipairs(blob) do
    if b[2] < top[2] or (b[2] == top[2] and b[1] < top[1]) then top = b end
    if b[2] > bottom[2] or (b[2] == bottom[2] and b[1] > bottom[1]) then bottom = b end
  end
  P.pixel(s, top[1], top[2], palette.shift(color, opts.light or 1))
  if opts.shade ~= false then
    P.pixel(s, bottom[1], bottom[2], palette.shift(color, -1))
  end
  if opts.shadow ~= false then
    P.pixel(s, bottom[1] + 1, bottom[2] + 1, SHADOW)
    if #blob >= 4 then P.pixel(s, bottom[1], bottom[2] + 1, SHADOW) end
  end
end

--- Every decal ends here. Strays are ERASED rather than voted into a
--- neighbour: on transparency a stray has nothing to vote with, so despeckle
--- would leave it, and a decal that ships with one loose pixel on it is dust
--- on every cell the level places it in.
local function finish(s)
  P.strip_strays(s)
  return s
end

-- Families -------------------------------------------------------------------
--
-- Each entry is one family: a name, what it may sit on, and how to draw it.
-- Variation is seeds, as everywhere else in the toolkit.
local FAMILIES = {}
local function family(f) FAMILIES[#FAMILIES + 1] = f end

family { name = "stones", title = "Small stones", over = ANY, variants = 12,
  draw = function(s, r)
    -- Two or three separate stones, loosely grouped: this is the ground
    -- showing its bones, not a pile.
    for _ = 1, r:range(2, 3) do
      local x, y = spot(r, s.width, s.height)
      local color = palette.resolve(r:chance(0.6) and "concrete_3" or "concrete_4")
      local blob = P.cluster(s, x, y, r:range(2, 4), color, r, { spread = 0.1 })
      light_blob(s, blob, color)
    end
  end }

family { name = "pebbles", title = "Pebble cluster", over = ANY, variants = 12,
  draw = function(s, r)
    -- ONE clump, tight. A pebble bed is many small stones in one place; spread
    -- them out and it is the stones decal with more pixels.
    local cx, cy = spot(r, s.width, s.height, 4)
    for _ = 1, r:range(5, 8) do
      local color = palette.resolve(r:weighted {
        { value = "concrete_3", weight = 3 }, { value = "concrete_4", weight = 2 },
        { value = "earth_4", weight = 1 } })
      local blob = P.cluster(s, cx + r:range(-3, 3), cy + r:range(-3, 3),
        r:range(2, 3), color, r, { spread = 0.1 })
      light_blob(s, blob, color, { shadow = false })
    end
    -- one shared shadow under the whole clump, not one per pebble: a dozen
    -- little shadows is the noise this is meant to avoid
    P.cluster(s, cx + 1, cy + 3, r:range(3, 5), SHADOW, r, { spread = 0.4 })
  end }

family { name = "crack", title = "Crack", over = HARD, variants = 12,
  draw = function(s, r)
    -- A fracture on transparency: the dark cut, plus the lit lip on its
    -- lower-right, which is what makes it read as an open cut rather than as
    -- a drawn line.
    local x, y = spot(r, s.width, s.height, 3)
    local drawn = asphalt.crack(s, x, y, r:range(8, 13), r,
      { color = r:chance(0.5) and "asphalt_1" or "concrete_2", branches = r:range(1, 2) })
    for _, p in ipairs(drawn) do
      if r:chance(0.4) and s:get(p[1] + 1, p[2] + 1) == palette.TRANSPARENT then
        P.pixel(s, p[1] + 1, p[2] + 1, "concrete_5")
      end
    end
  end }

family { name = "pothole", title = "Pothole fragment", over = HARD, variants = 10,
  draw = function(s, r)
    -- A hole is a depression: dark floor, lit lip on the lower-right rim (the
    -- wall the key light reaches), and the chunks that came out of it lying
    -- beside it.
    local x, y = spot(r, s.width, s.height, 4)
    local floor = palette.resolve("asphalt_1")
    local blob = P.cluster(s, x, y, r:range(9, 16), floor, r, { spread = 0.5 })
    local low
    for _, p in ipairs(blob) do
      if not low or p[2] > low[2] or (p[2] == low[2] and p[1] > low[1]) then low = p end
    end
    if low then
      P.pixel(s, low[1], low[2], "asphalt_4")
      P.pixel(s, low[1] - 1, low[2], "asphalt_4")
    end
    -- soil washed into the bottom
    for _, p in ipairs(blob) do
      if r:chance(0.28) then P.pixel(s, p[1], p[2], "earth_2") end
    end
    -- and the broken-out material around the rim
    if r:chance(0.7) then
      local at = blob[r:range(1, #blob)]
      local c = palette.resolve("asphalt_4")
      local chunk = P.cluster(s, at[1] + r:range(1, 2), at[2] + r:range(1, 2),
        r:range(2, 3), c, r, { spread = 0.1 })
      light_blob(s, chunk, c, { shadow = false })
    end
  end }

family { name = "dirt_patch", title = "Dirt patch", over = ANY, variants = 12,
  draw = function(s, r)
    -- Soil dropped or washed onto a surface. Broad and lobed, one value step
    -- of structure inside it and no more: a patch is a patch.
    local x, y = spot(r, s.width, s.height, 3)
    local core = palette.resolve(r:chance(0.5) and "earth_3" or "earth_2")
    local blob = P.cluster(s, x, y, r:range(14, 30), core, r, { spread = 1.1 })
    for _, p in ipairs(blob) do
      if r:chance(0.22) then P.pixel(s, p[1], p[2], palette.shift(core, -1)) end
    end
  end }

family { name = "stain_dark", title = "Dark stain", over = ANY, variants = 12,
  draw = function(s, r)
    -- Something soaked in and dried. Flat, no lit cap: a stain is IN the
    -- surface, so giving it a highlight would lift it off the ground.
    local x, y = spot(r, s.width, s.height, 3)
    local blob = P.cluster(s, x, y, r:range(12, 26), "dirt_2", r, { spread = 1.3 })
    for _, p in ipairs(blob) do
      if r:chance(0.3) then P.pixel(s, p[1], p[2], "dirt_3") end
    end
  end }

family { name = "oil_stain", title = "Oil stain", over = HARD, variants = 10,
  draw = function(s, r)
    -- Under where something stood and leaked. Near-black core, a warmer rim
    -- where it has soaked out and dried, and a two-pixel sheen -- the one
    -- place a bright pair is legitimate on the ground, because oil is the only
    -- thing out here that is actually shiny.
    local x, y = spot(r, s.width, s.height, 4)
    local blob = P.cluster(s, x, y, r:range(12, 22), "ink_4", r, { spread = 0.7 })
    for _, p in ipairs(blob) do
      local edge = false
      for _, d in ipairs { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
        if s:get(p[1] + d[1], p[2] + d[2]) == palette.TRANSPARENT then edge = true end
      end
      if edge then P.pixel(s, p[1], p[2], "dirt_1") end
    end
    if #blob > 6 and r:chance(0.6) then
      local p = blob[r:range(2, #blob // 2)]
      P.pixel(s, p[1], p[2], "metal_3")
      P.pixel(s, p[1] + 1, p[2], "metal_3")
    end
  end }

family { name = "dust", title = "Dust drift", over = ANY, variants = 10,
  draw = function(s, r)
    -- Dry dust blown into a hollow or against something. Pale, flat, wide, and
    -- the lowest-contrast thing in the library -- it exists to break up a large
    -- flat area without adding a countable mark to it.
    local x, y = spot(r, s.width, s.height, 2)
    local blob = P.cluster(s, x, y, r:range(18, 34), "straw_2", r, { spread = 1.5 })
    for _, p in ipairs(blob) do
      if r:chance(0.25) then P.pixel(s, p[1], p[2], "straw_3") end
    end
  end }

family { name = "rubble", title = "Rubble fragments", over = ANY, variants = 12,
  draw = function(s, r)
    -- Chunks of what fell apart nearby: concrete mostly, and each one a lit
    -- cap over its own shadow so it sits ON the ground rather than in it.
    for _ = 1, r:range(3, 5) do
      local x, y = spot(r, s.width, s.height)
      local color = palette.resolve(r:weighted {
        { value = "concrete_4", weight = 3 }, { value = "concrete_3", weight = 2 },
        { value = "concrete_5", weight = 1 } })
      local blob = P.cluster(s, x, y, r:range(2, 4), color, r, { spread = 0.2 })
      light_blob(s, blob, color)
    end
  end }

family { name = "trash", title = "Trash", over = ANY, variants = 12,
  draw = function(s, r)
    -- Paper and torn plastic: the palest thing that lands on the ground, so it
    -- is drawn FLAT and small. A crumpled sheet is a two-value shape -- a lit
    -- face and a folded-under edge -- and nothing else fits in four pixels.
    for _ = 1, r:range(2, 3) do
      local x, y = spot(r, s.width, s.height)
      local color = palette.resolve(r:chance(0.5) and "concrete_5" or "straw_3")
      local w, h = r:range(2, 3), r:range(1, 2)
      P.rect_fill(s, x, y, w, h, color)
      P.rect_fill(s, x, y, w, 1, palette.shift(color, 1))
      P.pixel(s, x + w, y + h, SHADOW)
    end
  end }

family { name = "scrap", title = "Scrap metal", over = ANY, variants = 12,
  draw = function(s, r)
    -- A bent offcut. Metal reads by being STRAIGHT and angular, so this is
    -- runs meeting at a corner -- never a blob -- with rust where it has been
    -- lying in the wet.
    local x, y = spot(r, s.width, s.height, 3)
    local axis = r:chance(0.5)
    local len = r:range(4, 7)
    local body = palette.resolve("metal_4")
    for i = 0, len - 1 do
      P.pixel(s, axis and x + i or x, axis and y or y + i, body)
    end
    -- the bend
    local bx = axis and x + len - 1 or x
    local by = axis and y or y + len - 1
    for i = 1, r:range(2, 3) do
      P.pixel(s, bx + i, by + (axis and i or 1), body)
    end
    -- lit along the upper-left edge, per the fixed key
    for i = 0, len - 1 do
      local px = axis and x + i or x - 1
      local py = axis and y - 1 or y + i
      if s:get(px, py) == palette.TRANSPARENT and r:chance(0.55) then
        P.pixel(s, px, py, "metal_5")
      end
    end
    rust.fill(s, r, { coverage = r:chance(0.7) and 0.5 or 0, mask = P.ramp_mask("metal") })
    P.pixel(s, bx + 1, by + 2, SHADOW)
  end }

family { name = "glass", title = "Broken glass", over = HARD, variants = 10,
  draw = function(s, r)
    -- At 16px glass can only be a GLINT: a bright pair with a dark pixel under
    -- it. Drawn as single pixels it is indistinguishable from dust, which is
    -- why the pair is mandatory and why there are only ever three of them.
    local cx, cy = spot(r, s.width, s.height, 4)
    for _ = 1, r:range(2, 3) do
      local x, y = cx + r:range(-3, 3), cy + r:range(-3, 3)
      P.pixel(s, x, y, "concrete_6")
      P.pixel(s, x + 1, y, "concrete_5")
      P.pixel(s, x + 1, y + 1, SHADOW)
    end
  end }

family { name = "weeds", title = "Weeds through cracks", over = HARD, variants = 12,
  draw = function(s, r)
    -- Vegetation only gets into a hard surface where the surface has already
    -- failed, so the crack is drawn FIRST and the tufts come out of it. Two
    -- marks, one event -- the same rule the road tile follows.
    local x, y = spot(r, s.width, s.height, 3)
    local drawn = asphalt.crack(s, x, y, r:range(6, 10), r,
      { color = "asphalt_1", branches = 0 })
    local lean = r:chance(0.5) and 1 or -1
    for i = 1, math.min(2, math.max(1, #drawn // 5)) do
      local at = drawn[r:range(1, #drawn)]
      grass.tufts(s, 1, r, { at = { at[1], at[2] }, lean = lean,
        color = r:chance(0.55) and "grass_2" or "straw_1" })
    end
  end }

family { name = "grass_tuft", title = "Dry grass tuft", over = ANY, variants = 12,
  draw = function(s, r)
    -- One clump, sometimes a second right beside it, all leaning the same way.
    -- This is the mark that used to be printed on every grass tile.
    local x, y = spot(r, s.width, s.height, 3)
    local lean = r:chance(0.5) and 1 or -1
    local olive = r:chance(0.35)
    for i = 1, r:chance(0.4) and 2 or 1 do
      grass.tufts(s, 1, r, {
        at = { x + (i - 1) * r:range(3, 4), y + r:range(-1, 1) },
        lean = lean, color = olive and "grass_2" or "straw_1",
      })
    end
  end }

family { name = "dead_vegetation", title = "Dead vegetation", over = SOFT, variants = 12,
  draw = function(s, r)
    -- Last year's growth, flattened. A lobed mat with a few stems still
    -- pointing the way it fell: direction is the whole read, and a mat drawn
    -- without it is just a brown patch.
    local x, y = spot(r, s.width, s.height, 3)
    local blob = P.cluster(s, x, y, r:range(10, 20), "straw_1", r, { spread = 1.4 })
    local lean = r:chance(0.5) and 1 or -1
    for _ = 1, r:range(2, 3) do
      local at = blob[r:range(1, #blob)]
      local len = r:range(3, 5)
      local px = at[1]
      for k = 0, len - 1 do
        P.pixel(s, px, at[2] - k, "straw_2")
        if k > 0 and k % 2 == 0 then px = px + lean end
      end
      P.pixel(s, px, at[2] - len + 1, "straw_3")
    end
  end }

family { name = "leaves", title = "Leaf litter", over = ANY, variants = 12,
  draw = function(s, r)
    -- Organic litter under whatever dropped it. Small paired specks in three
    -- close values, loosely grouped so it reads as litter and not as a stain.
    local cx, cy = spot(r, s.width, s.height, 4)
    for _ = 1, r:range(4, 6) do
      local color = palette.resolve(r:weighted {
        { value = "straw_1", weight = 3 }, { value = "wood_3", weight = 2 },
        { value = "straw_2", weight = 2 } })
      local x, y = cx + r:range(-4, 4), cy + r:range(-4, 4)
      P.cluster(s, x, y, r:range(2, 3), color, r, { spread = 0.3 })
    end
  end }

-- Registration ---------------------------------------------------------------

local set = {}
for _, f in ipairs(FAMILIES) do
  set[#set + 1] = {
    name = "decal_" .. f.name,
    title = f.title .. " decal 16x16",
    size = { w = 16, h = 16 },
    tileable = false,
    surface = "decal",
    category = "decal",
    variants = f.variants or 10,
    over = f.over,
    preview_background = f.over == HARD and "cracked_asphalt" or "dirt_ground",
    build = function(rng_stream)
      local s = P.new(16, 16)
      f.draw(s, rng_stream)
      return finish(s)
    end,
  }
end

-- Keep the contract honest at load time rather than at review time: a decal
-- that fills its cell is a tile, and the whole system depends on it not being
-- one.
assert(#set >= 16, "the decal library is the point; do not let it shrink")
assert(style.decal.max_coverage < 0.5, "a decal is mostly nothing")

return set
