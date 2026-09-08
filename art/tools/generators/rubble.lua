-- generators/rubble.lua -- the destruction kit: piles of what used to be
-- something else.
--
-- All of it transparent, so any piece can be dropped over any ground. That is
-- the point of a rubble kit -- the level decides where a building fell down,
-- not the tileset.
--
-- ONE RULE SHAPES EVERY ASSET HERE, and it was learned the hard way on
-- `wall_collapsed`: A PILE IS ONE CONNECTED MASS. Drawn as a scatter of
-- separate chunks, each chunk gets its own full outline, the silhouette
-- becomes a row of floating rocks, and the busyness goes almost entirely into
-- ink. So a pile is a MOUND -- a per-column height profile filled solid --
-- with the individual pieces described by divisions drawn *inside* it. Small
-- scatters are a different asset and already exist as `decal_rubble`.
--
-- What a pile is made of is the only thing that varies between these
-- generators: concrete off a panel wall, brick off a chimney, steel off a
-- machine, timber off a shed, and the black of something that burned.

local P = require("pixel_utils")
local palette = require("palette")
local materials = require("materials")
local object = require("object")

local set = {}

--- The shared mound. Every pile in this kit is this function plus a material.
--
-- opts:
--   x0, x1     span
--   peak       how tall at the crown
--   body       the ramp step the mass is drawn in
--   divisions  how many internal piece-edges to draw
--   grit       fraction of the mound that gets a second, darker step mixed in
local function mound(s, rng_stream, opts)
  local x0, x1 = opts.x0 or 1, opts.x1 or (s.width - 2)
  local body = palette.resolve(opts.body or "concrete_4")
  local base_y = opts.base_y or (s.height - 2)
  local peak = opts.peak or 6
  local centre = rng_stream:range(x0 + (x1 - x0) // 4, x1 - (x1 - x0) // 4)
  local height = {}

  for x = x0, x1 do
    -- A mound falls away from its crown, and the jitter sits ON TOP of that
    -- shape rather than replacing it -- which is what keeps the silhouette a
    -- mound instead of a comb.
    local fall = math.abs(x - centre) * rng_stream:range(6, 11) / 10
    local h = math.max(1, math.floor(peak - fall + 0.5))
    if rng_stream:chance(0.35) then h = math.max(1, h + rng_stream:range(-1, 1)) end
    height[x] = h
    for y = base_y - h + 1, base_y do s:set(x, y, body) end
    -- the crown of each column takes the light; the far flank loses it
    s:set(x, base_y - h + 1, palette.shift(body, 1))
    if x > centre and h > 1 then s:set(x, base_y - h + 2, palette.shift(body, -1)) end
  end

  -- The individual pieces, as divisions inside the mass. Runs at angles, never
  -- a grid: this is what turns a lump into broken material.
  for _ = 1, opts.divisions or 2 do
    local dx = rng_stream:range(x0, math.max(x0, x1 - 3))
    local dy = base_y - math.max(1, (height[dx] or 1)) + rng_stream:range(1, 2)
    local len = rng_stream:range(3, 6)
    local slope = rng_stream:chance(0.5) and 1 or 0
    for k = 0, len - 1 do
      local px, py = dx + k, dy + (k * slope) // 3
      if s:get(px, py) ~= palette.TRANSPARENT then
        s:set(px, py, palette.shift(body, -2))
        if s:get(px, py + 1) ~= palette.TRANSPARENT then
          s:set(px, py + 1, palette.shift(body, 1))
        end
      end
    end
  end

  -- A second material mixed through the mass, so a pile is not one flat
  -- colour. Applied as small clusters INSIDE the existing silhouette, which
  -- costs nothing in outline and reads as differing pieces.
  if opts.grit and opts.grit > 0 then
    local g = rng_stream:branch("grit")
    for _ = 1, math.max(1, math.floor((x1 - x0) * opts.grit)) do
      local gx = g:range(x0, x1)
      local gy = base_y - g:range(0, math.max(0, (height[gx] or 1) - 1))
      P.cluster(s, gx, gy, g:range(2, 4), palette.resolve(opts.grit_color or palette.shift(body, -1)),
        g, { spread = 0.3, mask = function(x, y) return s:get(x, y) ~= palette.TRANSPARENT end })
    end
  end
  return height
end

local function pile(spec)
  set[#set + 1] = {
    name = spec.name,
    title = spec.title,
    size = { w = spec.w or 16, h = spec.h or 16 },
    tileable = false,
    -- `prop` by surface: a heap is an object with a silhouette, and the
    -- silhouette rules (one connected mass, no enclosed holes) are exactly
    -- what this kit has to satisfy. `rubble` by category, which puts it on the
    -- ground-detail layer and makes it steppable rather than solid.
    surface = "prop",
    category = "rubble",
    collision = spec.collision or "low",
    variants = spec.variants or 8,
    preview_background = spec.background or "dirt_ground",
    build = function(rng_stream, opts)
      local s = P.new(spec.w or 16, spec.h or 16)
      spec.draw(s, rng_stream, opts or {})
      return object.finish(s, rng_stream, { wear = spec.wear })
    end,
  }
end

-- By scale ------------------------------------------------------------------

pile { name = "debris_small", title = "Small debris pile 16x16", variants = 10,
  collision = "none",
  draw = function(s, r)
    -- Low and wide: barely a pile, more a spill. Still one mass, because a
    -- scatter is `decal_rubble` and this is an object.
    mound(s, r, { x0 = r:range(2, 4), x1 = r:range(11, 14), peak = r:range(2, 3),
      body = "concrete_4", divisions = 1, grit = 0.15 })
  end }

pile { name = "rubble_medium", title = "Medium rubble pile 16x16", variants = 10,
  draw = function(s, r)
    mound(s, r, { x0 = 1, x1 = 14, peak = r:range(5, 7), body = "concrete_4",
      divisions = 2, grit = 0.25 })
  end }

pile { name = "rubble_large", title = "Large rubble pile 32x16", w = 32, h = 16,
  variants = 8, collision = "hull",
  draw = function(s, r)
    -- Wide enough to be cover. Two crowns rather than one, so a 32px pile is a
    -- ridge and not one enormous cone.
    mound(s, r, { x0 = 1, x1 = 18, peak = r:range(7, 10), body = "concrete_4",
      divisions = 3, grit = 0.25 })
    mound(s, r, { x0 = 14, x1 = 30, peak = r:range(5, 8), body = "concrete_4",
      divisions = 2, grit = 0.2 })
  end }

-- By material ---------------------------------------------------------------

pile { name = "concrete_chunks", title = "Concrete chunks 16x16", variants = 10,
  draw = function(s, r)
    -- Fewer, bigger pieces than a general pile: broken slab rather than
    -- shattered masonry, so the divisions are long and the mass reads blocky.
    mound(s, r, { x0 = 1, x1 = 14, peak = r:range(4, 6), body = "concrete_5",
      divisions = 3, grit = 0.12, grit_color = "concrete_3" })
  end }

pile { name = "brick_debris", title = "Brick-like debris 16x16", variants = 10,
  draw = function(s, r)
    -- There is no red in this palette and none may be added, so "brick" is
    -- carried by UNIT SIZE rather than by hue: a mass of small regular pieces
    -- in the warm ramp, which at 16px is what distinguishes broken brick from
    -- broken concrete. Rust ochre is the warmest thing available and reads as
    -- old fired clay against the grey of the concrete piles.
    mound(s, r, { x0 = 1, x1 = 14, peak = r:range(4, 6), body = "rust_1",
      divisions = 3, grit = 0.35, grit_color = "wood_3" })
    -- a few whole units on top, drawn as 2x1 pairs: the giveaway detail
    for _ = 1, r:range(2, 3) do
      local bx, by = r:range(3, 11), r:range(8, 12)
      if s:get(bx, by) ~= palette.TRANSPARENT then
        P.rect_fill(s, bx, by, 2, 1, "rust_2")
        P.pixel(s, bx, by, "rust_3")
      end
    end
  end }

pile { name = "metal_debris", title = "Metal debris 16x16", variants = 10,
  draw = function(s, r)
    -- Metal does not pile like masonry -- it lies in flat overlapping plates.
    -- So this is a low mound with STRAIGHT divisions right across it, which is
    -- what says sheet rather than lump.
    -- Two divisions and less grit than the masonry piles. At three plus 0.15
    -- grit, plus the plate edges below and the heavy rust channel on top, the
    -- busiest seed measured 0.653 against the 0.65 prop ceiling -- and the
    -- plate edges are the read here, so they are what should survive.
    mound(s, r, { x0 = 1, x1 = 14, peak = r:range(3, 5), body = "metal_4",
      divisions = 2, grit = 0.08, grit_color = "metal_3" })
    for _ = 1, r:range(1, 2) do
      local y = r:range(10, 13)
      local x0 = r:range(1, 6)
      local len = r:range(5, 9)
      for k = 0, len - 1 do
        if s:get(x0 + k, y) ~= palette.TRANSPARENT then s:set(x0 + k, y, "metal_5") end
      end
    end
  end,
  -- ART_STYLE.md 3: on dark metal, 5-20% rust coverage is plenty, and ochre
  -- is the loudest thing in the palette. This was set at 0.2-0.4 -- over the
  -- documented guidance -- and it was the main reason the busiest seeds ran
  -- over the prop ceiling. The pile is scrap steel, not a rust sculpture.
  wear = { ramp = "metal",
    rust = { { value = 0.08, weight = 2 }, { value = 0.18, weight = 3 } } } }

pile { name = "wood_debris", title = "Wood debris 16x16", variants = 10,
  draw = function(s, r)
    -- Timber lies in long members, so the mound is low and the divisions run
    -- its full width. Splinters at the ends, which is how broken wood differs
    -- from broken anything else.
    mound(s, r, { x0 = 1, x1 = 14, peak = r:range(3, 5), body = "wood_3",
      divisions = 3, grit = 0.2, grit_color = "wood_2" })
    for _ = 1, r:range(2, 3) do
      local y = r:range(9, 13)
      local x0 = r:range(1, 4)
      local len = r:range(6, 10)
      for k = 0, len - 1 do
        if s:get(x0 + k, y) ~= palette.TRANSPARENT then
          s:set(x0 + k, y, k == 0 and "wood_4" or "wood_3")
        end
      end
      if s:get(x0 + len, y) ~= palette.TRANSPARENT then s:set(x0 + len, y, "wood_4") end
    end
  end,
  wear = { ramp = "wood", dirt = { { value = 0.06, weight = 2 }, { value = 0.14, weight = 2 } } } }

pile { name = "mixed_rubble", title = "Mixed rubble 16x16", variants = 10,
  draw = function(s, r)
    -- Everything at once, which is what a real collapse leaves. The mass is
    -- concrete and the OTHER materials come in as grit clusters, so the pile
    -- still reads as one object rather than as three overlapping ones.
    mound(s, r, { x0 = 1, x1 = 14, peak = r:range(5, 7), body = "concrete_4",
      divisions = 2, grit = 0.2 })
    for _, mat in ipairs { "wood_3", "metal_4", "rust_2" } do
      if r:chance(0.75) then
        local gx = r:range(2, 13)
        local gy = r:range(9, 13)
        P.cluster(s, gx, gy, r:range(2, 4), mat, r,
          { spread = 0.3, mask = function(x, y) return s:get(x, y) ~= palette.TRANSPARENT end })
      end
    end
  end }

pile { name = "collapsed_wall_debris", title = "Collapsed wall debris 32x16", w = 32, h = 16,
  variants = 8, collision = "hull",
  draw = function(s, r)
    -- A whole panel wall on the ground: a long low ridge with the
    -- reinforcement showing. This is the asset that says a BUILDING fell,
    -- rather than that something was dumped.
    mound(s, r, { x0 = 1, x1 = 30, peak = r:range(4, 6), body = "concrete_4",
      divisions = 4, grit = 0.2 })
    -- one large intact slab lying across the ridge, which gives the eye a
    -- readable piece of the building it used to be
    local sx = r:range(4, 18)
    local sw, sh = r:range(7, 11), 2
    local sy = r:range(8, 10)
    object.box(s, sx, sy, sw, sh, "concrete", 5)
    -- and the cage, trailing out of the broken end
    if r:chance(0.8) then
      materials.rust.bar(s, sx + sw, sy + 1, r:range(3, 5), "h", r, { streak = false })
    end
  end }

pile { name = "burnt_debris", title = "Burnt debris 16x16", variants = 10,
  draw = function(s, r)
    -- Everything that burned. The palette has an `ink` ramp for voids and
    -- outlines and this is the one asset that legitimately FILLS with it: char
    -- is genuinely near-black. It uses ink_1/ink_3/ink_4 and never ink_2,
    -- which is reserved for outlines (ART_STYLE.md 3) -- that reservation is
    -- what keeps the outline_thickness rule decidable, and a charred pile is
    -- exactly the asset that would otherwise break it.
    mound(s, r, { x0 = 1, x1 = 14, peak = r:range(4, 6), body = "ink_4",
      divisions = 2, grit = 0.3, grit_color = "ink_3" })
    -- ash at the foot, which is what separates burnt from merely dark
    local ash = r:branch("ash")
    for _ = 1, ash:range(2, 3) do
      P.cluster(s, ash:range(2, 13), ash:range(12, 14), ash:range(3, 5), "concrete_3", ash,
        { spread = 0.7 })
    end
    -- and one or two charred timber ends still recognisable
    for _ = 1, r:range(1, 2) do
      local x, y = r:range(2, 11), r:range(9, 12)
      if s:get(x, y) ~= palette.TRANSPARENT then
        for k = 0, r:range(2, 3) do
          if s:get(x + k, y) ~= palette.TRANSPARENT then s:set(x + k, y, "wood_2") end
        end
      end
    end
  end }

return set
