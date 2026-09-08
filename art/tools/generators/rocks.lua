-- generators/rocks.lua -- boulders and stone, by scale.
--
-- A rock is the simplest object in the library and the easiest to get wrong.
-- Three things make one read as stone rather than as a grey blob, and all
-- three are about FACETS:
--
--   * a rock has FLAT FACES meeting at angles, not a curved surface. So the
--     silhouette is a polygon -- never a grown cluster, which is what makes a
--     lump -- and the interior is divided into two or three faces;
--   * each face takes its own value from the fixed upper-left key: the face
--     turned up and left is lit, the one turned down and right is shaded, and
--     the step between them is what says "solid" at 12 pixels across;
--   * it sits IN the ground, not on it. A rock drawn with its whole outline
--     visible floats; one whose base is buried and which casts a hard shadow
--     down-right has weight.
--
-- Scale changes what a rock can say. At 16px it is one facet plus a shadow; at
-- 32px it can have a real profile, a cracked face and lichen. So the large
-- rock is 32x32 and the cluster is 32x16 -- and the small rocks stay small
-- rather than being shrunken versions of the big one, because a boulder and a
-- stone are different objects.

local P = require("pixel_utils")
local palette = require("palette")
local materials = require("materials")
local object = require("object")

local set = {}

--- One faceted rock. The workhorse of this file.
-- opts: cx, base_y, w, h, ramp, index, facets, crack
local function boulder(s, rng_stream, opts)
  local cx = opts.cx
  local base_y = opts.base_y
  local w = opts.w
  local h = opts.h
  local ramp = opts.ramp or "concrete"
  local index = opts.index or 4
  local half = w // 2

  -- The silhouette: an irregular polygon. Built from a per-column height so
  -- the top is faceted rather than domed, and the two flanks fall at
  -- different angles so it is never symmetrical -- a symmetrical rock reads
  -- as a drawn shape rather than a found one.
  local peak_at = cx + rng_stream:range(-half // 2, half // 2)
  local left_fall = rng_stream:range(5, 10) / 10
  local right_fall = rng_stream:range(5, 10) / 10
  local height = {}
  for x = cx - half, cx + half do
    local d = x - peak_at
    local fall = d < 0 and (-d * left_fall) or (d * right_fall)
    local col = math.max(1, math.floor(h - fall + 0.5))
    -- flat runs, not a smooth curve: a facet is several columns at one height
    if rng_stream:chance(0.30) then col = math.max(1, col + rng_stream:range(-1, 0)) end
    height[x] = col
    for y = base_y - col + 1, base_y do s:set(x, y, palette.step(ramp, index)) end
  end

  -- The faces. The upper-left of the mass is lit, the lower-right shaded, and
  -- the division between them runs through the peak -- which is what turns the
  -- silhouette into a solid.
  for x = cx - half, cx + half do
    local col = height[x] or 1
    local top = base_y - col + 1
    if x <= peak_at then
      -- lit face: the top two rows of the left flank
      for y = top, math.min(base_y, top + 1) do s:set(x, y, palette.step(ramp, index + 1)) end
      if col > 3 and x < peak_at then s:set(x, top, palette.step(ramp, index + 2)) end
    else
      -- shaded face
      for y = top, math.min(base_y, top + 1) do s:set(x, y, palette.step(ramp, index)) end
      for y = top + 2, base_y do s:set(x, y, palette.step(ramp, index - 1)) end
    end
  end
  -- the base row sits in the ground: darkest, and one pixel narrower each side
  for x = cx - half + 1, cx + half - 1 do
    s:set(x, base_y, palette.step(ramp, index - 2))
  end

  -- A crack across a face, on the bigger rocks. It follows fracture geometry
  -- like every other crack in the toolkit -- straight segments, 45-degree
  -- kinks -- because stone fails the same way concrete does.
  if opts.crack and rng_stream:chance(0.6) then
    local fx = rng_stream:range(cx - half + 1, cx + half - 2)
    materials.concrete.crack(s, fx, base_y - (height[fx] or 2) + 2,
      rng_stream:range(4, math.max(4, h - 1)), rng_stream, {
        color = palette.step(ramp, index - 2), branches = 0,
        mask = function(x, y) return s:get(x, y) ~= palette.TRANSPARENT end })
  end

  -- Lichen: the one place a rock gets colour. Olive, tiny, and only on the
  -- shaded side -- which is where it grows and also where it does not fight
  -- the lit face for attention.
  if opts.lichen and rng_stream:chance(0.5) then
    local lx = rng_stream:range(peak_at, cx + half - 1)
    P.cluster(s, lx, base_y - rng_stream:range(1, math.max(1, (height[lx] or 2) - 1)),
      rng_stream:range(2, 4), "grass_2", rng_stream,
      { spread = 0.4, mask = function(x, y) return s:get(x, y) ~= palette.TRANSPARENT end })
  end
  return height
end

local function rock(spec)
  set[#set + 1] = {
    name = spec.name,
    title = spec.title,
    size = { w = spec.w or 16, h = spec.h or 16 },
    tileable = false,
    surface = "prop",
    category = "rock",
    collision = spec.collision or "hull",
    variants = spec.variants or 8,
    preview_background = spec.background or "dirt_ground",
    build = function(rng_stream, opts)
      local s = P.new(spec.w or 16, spec.h or 16)
      spec.draw(s, rng_stream, opts or {})
      return object.finish(s, rng_stream, { wear = spec.wear })
    end,
  }
end

local STONE_WEAR = {
  ramp = "concrete",
  dirt = { { value = 0, weight = 2 }, { value = 0.10, weight = 3 } },
  staining = { { value = 0, weight = 3 }, { value = 0.08, weight = 2 } },
  dirt_bias = function(_, y, h) return y >= (h or 16) - 3 and 1.0 or 0.1 end,
}

rock { name = "rock_small", title = "Small rock 16x16", variants = 10,
  collision = "none", wear = STONE_WEAR,
  draw = function(s, r)
    -- One facet and a shadow. At this size that is all there is room for, and
    -- adding more only makes it noisy.
    boulder(s, r, { cx = 8, base_y = 13, w = r:range(5, 7), h = r:range(3, 4),
      ramp = "concrete", index = 4 })
  end }

rock { name = "rock_medium", title = "Medium rock 16x16", variants = 10,
  wear = STONE_WEAR,
  draw = function(s, r)
    boulder(s, r, { cx = 8, base_y = 14, w = r:range(9, 12), h = r:range(6, 8),
      ramp = "concrete", index = 4, crack = true, lichen = true })
  end }

rock { name = "rock_large", title = "Large rock 32x32", w = 32, h = 32, variants = 8,
  wear = STONE_WEAR,
  draw = function(s, r)
    -- Big enough for a real profile: a main mass with a shoulder beside it, so
    -- the silhouette has two peaks and reads as a broken outcrop rather than a
    -- scaled-up pebble.
    boulder(s, r, { cx = 15, base_y = 29, w = r:range(20, 25), h = r:range(15, 20),
      ramp = "concrete", index = 4, crack = true, lichen = true })
    boulder(s, r, { cx = r:chance(0.5) and 6 or 25, base_y = 29,
      w = r:range(8, 11), h = r:range(6, 10), ramp = "concrete", index = 4, crack = true })
  end }

rock { name = "rock_cluster", title = "Rock cluster 32x16", w = 32, h = 16, variants = 10,
  collision = "low", wear = STONE_WEAR,
  draw = function(s, r)
    -- Several stones of DIFFERENT sizes sitting together. Same-sized rocks in a
    -- row read as a wall or as eggs; the size variation is what makes it a
    -- scatter of stone. They overlap so the group is one mass.
    local xs = { 5, 12, 19, 26 }
    for i, x in ipairs(xs) do
      local big = (i == r:range(1, #xs))
      boulder(s, r, {
        cx = x + r:range(-1, 1), base_y = 14 - r:range(0, 1),
        w = big and r:range(9, 11) or r:range(5, 8),
        h = big and r:range(6, 8) or r:range(3, 5),
        ramp = "concrete", index = big and 4 or r:range(3, 4),
        crack = big, lichen = big,
      })
    end
  end }

return set
