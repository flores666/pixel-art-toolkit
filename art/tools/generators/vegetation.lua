-- generators/vegetation.lua -- the outdoor plant library: what is left of it.
--
-- Nothing here is healthy. The two rules from ART_STYLE.md that shape every
-- asset in this file:
--
--   * VEGETATION READS BY DIRECTION AND BY LIGHT, NOT BY COLOUR. Olive at the
--     field's own value is a pure hue change, which is what camouflage is. So
--     a plant is a body a step darker than what it stands on with its tips a
--     step or two lighter, and its strokes all lean the same way.
--   * GREEN IS RATIONED. Olive tops out at grass_5 and is the minority; the
--     brightest pixel on a dead bush is bleached straw catching the sun.
--
-- Scale is the other decision. A tree does not fit in 16x16 -- at that size it
-- is a lollipop, and the toolkit would rather spend four cells than ship one.
-- So the trees are 32x32 and 16x32, the log is 32x16, and everything that
-- genuinely is a 16px object (a stump, a branch, a weed) stays 16x16.
--
-- THIN VEGETATION IS NOT OUTLINED, and that is a considered exception to
-- ART_STYLE.md 8 rather than an oversight. An outline is one pixel thick and a
-- stalk is one pixel wide, so outlining a tuft spends more pixels on the
-- outline than on the plant: the strokes weld into a dark blob with a bit of
-- colour trapped inside, which is precisely the read the tuft grammar exists
-- to avoid. It was drawn both ways and the outlined version is unusable.
--
-- What replaces it is the grammar the decals already use: a body a step darker
-- than the field and a tip a step or two lighter. That is what separates a
-- plant from the ground -- light, not a border. Solid-bodied vegetation (a
-- trunk, a stump, a log) has an interior for an outline to sit around, so it
-- keeps one.

local P = require("pixel_utils")
local palette = require("palette")
local materials = require("materials")
local object = require("object")
local wear = require("wear")

local grass, wood = materials.grass, materials.wood

local set = {}

--- Register one vegetation generator.
local function veg(spec)
  set[#set + 1] = {
    name = spec.name,
    title = spec.title,
    size = { w = spec.w or 16, h = spec.h or 16 },
    tileable = false,
    -- Surface class says what KIND of thing this is for validation; category
    -- says what it is for the level. They are not the same axis, and thin
    -- vegetation is the case that proves it: a tuft is a `vegetation` asset by
    -- category and a `decal` by surface, because it is a sparse self-lit
    -- overlay of strokes with no outline and no interior. Holding it to the
    -- prop rules asks the wrong questions -- it fails `min_occupancy` for
    -- being small and `max_interior_holes` for the gaps BETWEEN its stems,
    -- which are the asset rather than a defect. The decal rules ask the right
    -- ones: is it mostly transparent, and is it one mark in one place.
    surface = spec.surface or "prop",
    category = "vegetation",
    collision = spec.collision or "none",
    variants = spec.variants or 8,
    max_interior_holes = spec.max_interior_holes,
    preview_background = spec.background or "dry_grass",
    build = function(rng_stream, opts)
      local s = P.new(spec.w or 16, spec.h or 16)
      spec.draw(s, rng_stream, opts or {})
      return object.finish(s, rng_stream, {
        outline = spec.outline,
        shadow = spec.shadow,
        wear = spec.wear,
      })
    end,
  }
end

-- Shrubs ---------------------------------------------------------------------
--
-- A dead bush is a TANGLE: many short runs radiating from a low crown, not a
-- blob with a texture on it. The silhouette has to be ragged and open enough
-- that the ground shows through, or it reads as a rock.
local function tangle(s, rng_stream, opts)
  local cx = opts.cx or s.width // 2
  local base_y = opts.base_y or (s.height - 2)
  local spread = opts.spread or 5
  local height = opts.height or 7
  local body = palette.resolve(opts.color or "straw_1")
  local tip = palette.resolve(opts.tip or palette.shift(body, 2))
  local stems = opts.stems or rng_stream:range(6, 9)
  for i = 1, stems do
    -- Each stem leaves the crown at its own angle and holds it. A stem that
    -- re-picks its direction per pixel is a scribble (ART_STYLE.md 6).
    local lean = rng_stream:range(-spread, spread)
    local len = rng_stream:range(math.max(3, height - 3), height)
    local x, y = cx + rng_stream:range(-1, 1), base_y
    local step = lean / math.max(1, len)
    local fx = x
    for k = 0, len - 1 do
      P.pixel(s, math.floor(fx + 0.5), y - k, body)
      fx = fx + step
    end
    P.pixel(s, math.floor(fx + 0.5), y - len + 1, tip)
  end
  -- the crown: where the stems come out of the ground, and the one place the
  -- bush is solid enough to carry a shadow
  P.cluster(s, cx, base_y, rng_stream:range(3, 5), palette.shift(body, -1), rng_stream,
    { spread = 0.4 })
end

veg { name = "dead_bush", outline = false, surface = "decal", title = "Dead bush 16x16", variants = 10,
  wear = { vegetation = nil },
  draw = function(s, r)
    tangle(s, r, { height = r:range(7, 10), spread = r:range(4, 6), color = "straw_1" })
    -- a few surviving leaves, olive and few: this is the minority report
    if r:chance(0.4) then
      grass.tufts(s, 1, r, { at = { s.width // 2 + r:range(-3, 3), r:range(8, 11) },
        color = "grass_2" })
    end
  end }

veg { name = "dry_scrub", outline = false, surface = "decal", title = "Dry scrub 16x16", variants = 10,
  draw = function(s, r)
    -- Lower and wider than a bush: scrub sprawls. Two crowns rather than one,
    -- so the silhouette is a bank instead of a ball.
    for i = 0, 1 do
      tangle(s, r, { cx = 5 + i * 6, base_y = s.height - 2,
        height = r:range(4, 6), spread = r:range(3, 5),
        stems = r:range(4, 6), color = "straw_1" })
    end
  end }

veg { name = "sparse_weed", outline = false, surface = "decal", title = "Sparse weed 16x16", variants = 10,
  shadow = false,
  draw = function(s, r)
    -- The smallest standing plant in the library: one clump, a few stalks. No
    -- contact shadow -- at this size the shadow would be as big as the plant
    -- and would read as a stain with a weed on it.
    local lean = r:chance(0.5) and 1 or -1
    local x = r:range(5, 10)
    for i = 1, r:range(1, 2) do
      grass.tufts(s, 1, r, { at = { x + (i - 1) * 3, s.height - 3 + r:range(-1, 0) },
        lean = lean, color = r:chance(0.4) and "grass_2" or "straw_1" })
    end
  end }

veg { name = "tall_grass_clump", outline = false, surface = "decal", title = "Tall grass clump 16x16", variants = 10,
  draw = function(s, r)
    -- Taller than the field it stands in, which is the whole point: this is
    -- the asset that gives a grass field a vertical read. All the blades lean
    -- the same way -- that is what direction means.
    local lean = r:chance(0.5) and 1 or -1
    local base = s.height - 2
    for i = 0, r:range(4, 6) do
      local x = 3 + i * 2 + r:range(0, 1)
      local len = r:range(7, 11)
      local color = r:chance(0.3) and "grass_2" or "straw_1"
      grass.blade(s, x, base - r:range(0, 1), len, r, { lean = lean, color = color })
    end
    P.cluster(s, s.width // 2, base, r:range(4, 6), "straw_1", r, { spread = 0.6 })
  end }

-- Trees ----------------------------------------------------------------------
--
-- A tree is a TRUNK plus BRANCHES that taper and fork -- and at this
-- resolution the fork angles are the entire read. Branch geometry is the
-- fracture geometry: hold a heading for several pixels, kink at a joint, throw
-- limbs at a wide angle from along the trunk rather than off its tip. Cracks
-- and branches are the same shape for the same reason, so they share the
-- primitive.
-- `mask` keeps a limb inside the asset's safe area. A prop is placed on a
-- grid, so a branch that reaches the very edge of the cell is drawn hard
-- against whatever the level puts in the next cell -- and a branch sliced off
-- at a corner reads as a cut, not as a canopy. ART_STYLE.md 1 states the rule
-- (props leave the tile corners transparent); this is how a spreading
-- silhouette obeys it without having its limbs truncated after the fact,
-- which would leave stubs for the outline to wrap.
local function limb(s, x, y, len, heading, thickness, color, rng_stream, depth, mask)
  local dirs = P.compass
  local fx, fy = x, y
  local h = heading
  -- The lit face is a BROKEN run, not a pixel beside every body pixel. Lighting
  -- every step of a two-pixel limb alternates body and highlight all the way
  -- along it, which reads as a stripe rather than as a round branch and
  -- measured 0.67 busyness against a 0.65 ceiling -- on an asset that is four
  -- clean strokes. ART_STYLE.md 6: a subtle edge is a broken run, because a
  -- 1px highlight on a 1px band is just stray pixels.
  local lit_left = rng_stream:range(2, 4)
  for i = 1, len do
    local d = dirs[h + 1]
    for t = 0, thickness - 1 do
      P.pixel(s, math.floor(fx + 0.5) + t, math.floor(fy + 0.5), color, mask)
    end
    if lit_left > 0 then
      P.pixel(s, math.floor(fx + 0.5) - 1, math.floor(fy + 0.5), palette.shift(color, 1), mask)
      lit_left = lit_left - 1
    elseif rng_stream:chance(0.30) then
      lit_left = rng_stream:range(2, 4)
    end
    fx, fy = fx + d[1], fy + d[2]
    if i % rng_stream:range(3, 4) == 0 then
      h = (h + (rng_stream:chance(0.5) and 1 or 7)) % 8
      -- fork: a limb throws a smaller limb at a wide angle and keeps going
      if depth > 0 and rng_stream:chance(0.55) then
        limb(s, math.floor(fx + 0.5), math.floor(fy + 0.5),
          math.max(2, len - rng_stream:range(2, 4)),
          (h + (rng_stream:chance(0.5) and 2 or 6)) % 8,
          math.max(1, thickness - 1), color, rng_stream, depth - 1, mask)
      end
    end
  end
  return math.floor(fx + 0.5), math.floor(fy + 0.5)
end

local function tree(s, r, opts)
  -- One clear cell of margin all round, so the outline has somewhere to sit
  -- and a limb never lands on the cell border.
  local m = opts.margin or 1
  local inside = function(x, y)
    return x >= m and y >= m and x < s.width - m and y < s.height - m
  end
  local trunk_x = s.width // 2 + r:range(-1, 1)
  local base = s.height - 2
  local top = opts.crown_y or 8
  local thickness = opts.thickness or 3
  local bark = palette.resolve(opts.bark or "wood_3")

  -- trunk: tapering, and leaning very slightly -- a dead-straight trunk reads
  -- as a post
  local drift = r:chance(0.5) and 1 or -1
  local fx = trunk_x
  for y = base, top, -1 do
    local t = (base - y) / math.max(1, base - top)
    local w = math.max(1, math.floor(thickness * (1 - t * 0.55) + 0.5))
    for i = 0, w - 1 do
      P.pixel(s, math.floor(fx + 0.5) + i, y, bark)
    end
    P.pixel(s, math.floor(fx + 0.5) - 1, y, palette.shift(bark, 1))  -- lit face
    P.pixel(s, math.floor(fx + 0.5) + w, y, palette.shift(bark, -1)) -- shaded face
    if (base - y) % 5 == 4 then fx = fx + drift * 0.5 end
  end

  -- The limbs. Two things decide whether this reads as a tree or as a claw,
  -- and the first draft got both wrong:
  --
  --   * REACH. Limbs of 4-7px on a 32px tree leave the canopy the same width
  --     as the trunk, so the whole asset reads as a fist on a stick. They have
  --     to span a real fraction of the cell -- half the width, less what the
  --     trunk already occupies.
  --   * ORIGIN. Limbs all leaving the trunk near its top spring from one point
  --     like an umbrella. A tree carries them up the whole length of the
  --     trunk, so the origins spread over the upper two thirds and the lowest
  --     limbs are the longest.
  local trunk_top = math.floor(fx + 0.5)
  local span = s.width // 2 - 2
  local limbs = opts.limbs or r:range(3, 5)
  for i = 1, limbs do
    -- upper two thirds of the trunk, lowest limbs first so they get the reach
    local t = (i - 1) / math.max(1, limbs - 1)
    local from_y = math.floor(top + (base - top) * 0.55 * (1 - t))
    local reach = math.max(5, math.floor(span * (0.55 + 0.45 * (1 - t))))
    -- 4 = due left, 0 = due right; 5/7 are the diagonals. A limb that leaves
    -- at the diagonal and kinks upward is the shape of a branch.
    local heading = r:chance(0.5) and 5 or 7
    limb(s, trunk_top + r:range(0, 1), from_y, reach, heading,
      math.max(1, thickness - 1), bark, r, 2, inside)
  end
  -- and the leader, continuing the trunk out of the crown
  limb(s, trunk_top, top, r:range(4, 7), 6, math.max(1, thickness - 1), bark, r, 1, inside)

  -- foliage, if this tree still has any. Clumped ON the limbs, never as a
  -- ball around them: a canopy is what the branches are carrying.
  if opts.foliage and opts.foliage > 0 then
    local leaf = r:branch("foliage")
    for _ = 1, math.floor(opts.foliage * 7) do
      local x = trunk_top + leaf:range(-7, 7)
      local y = top + leaf:range(-5, 4)
      local color = palette.resolve(leaf:chance(0.55) and "grass_2" or "straw_1")
      local blob = P.cluster(s, x, y, leaf:range(4, 8), color, leaf,
        { spread = 0.5, mask = inside })
      -- lit on the upper-left of each clump; that is what stops a canopy
      -- reading as a flat silhouette
      if #blob > 0 then
        local topmost = blob[1]
        for _, b in ipairs(blob) do
          if b[2] < topmost[2] or (b[2] == topmost[2] and b[1] < topmost[1]) then topmost = b end
        end
        P.pixel(s, topmost[1], topmost[2], palette.shift(color, 1))
      end
    end
  end
end

veg { name = "dead_tree", title = "Dead tree 32x32", w = 32, h = 32, variants = 8,
  collision = "hull",
  -- A bare branching silhouette encloses regions wherever two limbs fork and
  -- meet again. Those gaps are the tree; six would mean the limbs have turned
  -- into a mesh, so the rule still has teeth.
  max_interior_holes = 5,
  draw = function(s, r)
    tree(s, r, { crown_y = r:range(6, 9), thickness = 3, limbs = r:range(4, 6) })
  end }

veg { name = "sick_tree", title = "Living but unhealthy tree 32x32", w = 32, h = 32,
  variants = 8, collision = "hull", max_interior_holes = 5,
  draw = function(s, r)
    -- Alive, barely. Thin foliage in clumps with gaps between them, so the
    -- branches show through -- a full canopy would read as healthy, which is
    -- the wrong world.
    tree(s, r, { crown_y = r:range(7, 10), thickness = 3, limbs = r:range(3, 5),
      foliage = 0.5 + r:float() * 0.4 })
  end }

veg { name = "tree_stump", title = "Tree stump 16x16", variants = 10,
  collision = "hull",
  draw = function(s, r)
    -- Cut, not broken: a flat top face catching the light, the ring showing,
    -- and roots spreading at the base.
    -- Wide and squat. The first draft was 8 wide and 6 tall with a rounded
    -- top and read as a bowler hat; a stump is a broad disc of cut timber
    -- sitting close to the ground, so the cut face is the widest thing on it
    -- and gets two rows to show its rings.
    local x0, x1 = 2, 13
    local top = 9
    P.rect_fill(s, x0, top, x1 - x0 + 1, s.height - 2 - top, "wood_3")
    -- the cut face, into the light, two rows deep so the rings have somewhere
    -- to live
    P.rect_fill(s, x0, top, x1 - x0 + 1, 2, "wood_4")
    P.rect_fill(s, x0 + 1, top, x1 - x0 - 1, 1, "wood_5")
    P.rect_fill(s, x0, top + 2, 1, s.height - 4 - top, "wood_4")
    P.rect_fill(s, x1, top + 2, 1, s.height - 4 - top, "wood_2")
    -- the growth rings on the cut face, off centre so it never reads as a
    -- target, and drawn as a run rather than a dot
    local rx = r:range(x0 + 3, x1 - 3)
    P.hline(s, rx - 1, top, 3, "wood_3")
    P.hline(s, rx, top + 1, 2, "wood_3")
    -- roots: short runs leaving the base sideways
    for _ = 1, r:range(2, 3) do
      local side = r:chance(0.5) and -1 or 1
      local y = s.height - 3 + r:range(0, 1)
      local from = side < 0 and x0 or x1
      for i = 1, r:range(2, 3) do
        P.pixel(s, from + side * i, y, "wood_2")
      end
    end
  end,
  wear = { ramp = "wood", dirt = { { value = 0, weight = 1 }, { value = 0.12, weight = 2 } },
    vegetation = { { value = 0, weight = 2 }, { value = 1, weight = 1 } },
    vegetation_area = { x = 2, y = 11, w = 12, h = 3 } } }

veg { name = "broken_trunk", title = "Broken trunk 16x32", w = 16, h = 32, variants = 8,
  collision = "hull",
  draw = function(s, r)
    -- Snapped rather than cut, which means the break is SPLINTERED: the top is
    -- a ragged run of stubs, not a flat face. That difference is the whole
    -- reason this is a separate asset from the stump.
    -- A snapped trunk is WIDE at the ground and tapers hard: the first draft
    -- was four pixels wide all the way up and read as a candle. It also has to
    -- be shorter than the cell so the splintered break is visible against
    -- empty sky rather than running off the top.
    local cx = 5
    local base = s.height - 2
    local top = r:range(10, 15)
    local base_w = 6
    for y = base, top, -1 do
      local t = (base - y) / math.max(1, base - top)
      local w = math.max(3, math.floor(base_w * (1 - t * 0.45) + 0.5))
      P.rect_fill(s, cx, y, w, 1, "wood_3")
      P.pixel(s, cx, y, "wood_4")             -- lit left face
      P.pixel(s, cx + w - 1, y, "wood_2")     -- shaded right face
    end
    -- bark, along the length and broken
    local bark = r:branch("bark")
    for _ = 1, r:range(2, 3) do
      P.broken_run(s, "v", cx + bark:range(1, base_w - 2), top + 2, base - 1, bark,
        { delta = -1, run = { 3, 6 }, gap = { 3, 5 } })
    end
    -- the splintered break: stubs of differing height, which is the one thing
    -- that distinguishes this from the sawn stump
    local top_w = math.max(3, math.floor(base_w * 0.55 + 0.5))
    for i = 0, top_w - 1 do
      local h = r:range(1, 4)
      for k = 0, h do P.pixel(s, cx + i, top - k, "wood_3") end
      P.pixel(s, cx + i, top - h, "wood_5")
    end
  end,
  wear = { ramp = "wood", dirt = { { value = 0, weight = 1 }, { value = 0.10, weight = 2 } } } }

-- Fallen ---------------------------------------------------------------------

veg { name = "fallen_branch", title = "Fallen branch 16x16", variants = 10,
  shadow = false,
  draw = function(s, r)
    -- Lying down, so it is lit along its TOP edge and shadowed underneath --
    -- the opposite of a standing limb, and the cue that says "on the ground".
    -- Lying nearly flat, so it stays a long horizontal silhouette. A branch
    -- drawn on a diagonal at 16px is four disconnected marks by the time it
    -- has kinked twice, which is what the first draft looked like.
    local y = r:range(9, 12)
    local x0 = 2
    local len = r:range(10, 12)
    local bark = palette.resolve("wood_3")
    -- trunk of the branch: two pixels thick, held level
    local drop = r:chance(0.5) and 1 or 0
    for i = 0, len - 1 do
      local yy = y + (i > len // 2 and drop or 0)
      P.pixel(s, x0 + i, yy, bark)
      P.pixel(s, x0 + i, yy + 1, palette.shift(bark, -1))
    end
    -- lit along the top, broken
    P.broken_run(s, "h", y, x0, x0 + len - 1, r, { delta = 1, run = { 3, 5 }, gap = { 2, 4 } })
    -- two side twigs, at a wide angle from along it -- not off the tip
    for _ = 1, r:range(1, 2) do
      local at = x0 + r:range(2, len - 3)
      local up = r:chance(0.6)
      for k = 1, r:range(2, 3) do
        P.pixel(s, at + k, up and y - k or y + 1 + k, bark)
      end
    end
    -- its shadow, hugging the underside where it actually touches the ground
    for i = 0, len - 1 do
      local yy = y + (i > len // 2 and drop or 0)
      if r:chance(0.7) then P.pixel(s, x0 + i, yy + 2, "ink_3") end
    end
  end }

veg { name = "fallen_log", title = "Fallen log 32x16", w = 32, h = 16, variants = 8,
  collision = "low",
  draw = function(s, r)
    -- A cylinder lying down: lit along the top, shaded along the bottom, with
    -- the sawn end showing its rings. Cover is the gameplay point of this
    -- asset, so the silhouette is long and unbroken.
    local y0 = r:range(6, 8)
    local h = r:range(4, 5)
    local x0, x1 = 1, s.width - 3
    object.cylinder(s, x0, y0, x1 - x0 + 1, h, "wood", 3)
    -- rotate the cylinder read 90 degrees: the lit strip belongs on TOP
    P.rect_fill(s, x0, y0, x1 - x0 + 1, 1, palette.step("wood", 4))
    P.rect_fill(s, x0, y0 + 1, x1 - x0 + 1, 1, palette.step("wood", 5))
    P.rect_fill(s, x0, y0 + h - 1, x1 - x0 + 1, 1, palette.step("wood", 2))
    -- the sawn end, and the bark texture along the length
    P.rect_fill(s, x0, y0 + 1, 2, h - 2, palette.step("wood", 4))
    wood.knot(s, x0 + 1, y0 + h // 2, {})
    local bark = r:branch("bark")
    for _ = 1, r:range(3, 5) do
      P.broken_run(s, "h", y0 + bark:range(1, h - 2), x0 + 2, x1, bark,
        { delta = -1, run = { 3, 7 }, gap = { 3, 6 } })
    end
    -- A stub where a limb came off. It must TOUCH the log: drawn one column
    -- clear of it the stub is a separate floating island, which is both a
    -- silhouette defect (the validator counted five pieces) and wrong -- a
    -- branch stub is part of the trunk it broke off.
    if r:chance(0.6) then
      local sx = r:range(x0 + 5, x1 - 5)
      for k = 1, r:range(2, 3) do P.pixel(s, sx, y0 - k, "wood_3") end
      P.pixel(s, sx, y0 - 1, "wood_4")
    end
  end,
  -- The vegetation channel is confined to the log's own footprint. Left
  -- unbounded it dropped a tuft anywhere in the 32x16 cell, which is a
  -- separate floating island rather than growth against the log -- the
  -- silhouette rule counted five pieces and was right to.
  wear = { ramp = "wood", dirt = { { value = 0, weight = 1 }, { value = 0.10, weight = 2 } },
    vegetation = { { value = 0, weight = 2 }, { value = 1, weight = 1 } },
    vegetation_area = { x = 3, y = 10, w = 26, h = 3 } } }

return set
