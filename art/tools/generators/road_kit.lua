-- generators/road_kit.lua -- roadside and industrial infrastructure.
--
-- The furniture of a post-Soviet service road: barriers, signage, poles,
-- lighting, cabinets, pipework, drainage. These are the assets that say
-- "people built this and then left", and they carry more of that message than
-- any amount of ground texture.
--
-- SCALE IS THE FIRST DECISION HERE. A utility pole is 48px tall in the world
-- and squashing it into 16x16 gives a stub that reads as a bollard; a sign
-- needs a post AND a face, which is two cells minimum. So this kit spends
-- multiple tiles freely (16x32, 32x16, 16x48) and only the genuinely small
-- things -- a manhole, a junction box, a marker -- stay 16x16.
--
-- The vertical assets share one convention, because a level places them on a
-- ground layer and they must all sit at the same depth: THE OBJECT'S BASE IS
-- THE SECOND-TO-LAST ROW of its cell, with the last row for its contact
-- shadow. That single rule is what keeps a pole, a sign and a cabinet standing
-- on the same floor.

local P = require("pixel_utils")
local palette = require("palette")
local materials = require("materials")
local object = require("object")

local metal, concrete, rust, wood = materials.metal, materials.concrete,
  materials.rust, materials.wood

local set = {}
local function item(spec)
  set[#set + 1] = {
    name = spec.name,
    title = spec.title,
    size = { w = spec.w or 16, h = spec.h or 16 },
    tileable = false,
    surface = spec.surface or "prop",
    category = spec.category or "road",
    collision = spec.collision,
    variants = spec.variants or 6,
    max_interior_holes = spec.max_interior_holes,
    preview_background = spec.background or "cracked_asphalt",
    build = function(rng_stream, opts)
      local s = P.new(spec.w or 16, spec.h or 16)
      spec.draw(s, rng_stream, opts or {})
      return object.finish(s, rng_stream, {
        outline = spec.outline, shadow = spec.shadow, wear = spec.wear,
      })
    end,
  }
end

-- Shared wear profiles, so a cabinet and a pole corrode by the same process.
local STEEL_WEAR = {
  ramp = "metal",
  rust = { { value = 0.05, weight = 2 }, { value = 0.15, weight = 3 }, { value = 0.28, weight = 2 } },
  dirt = { { value = 0.05, weight = 2 }, { value = 0.12, weight = 2 } },
}
local CONCRETE_WEAR = {
  ramp = "concrete",
  staining = { { value = 0, weight = 2 }, { value = 0.10, weight = 3 } },
  dirt = { { value = 0.06, weight = 2 }, { value = 0.14, weight = 2 } },
  cracks = { { value = 0, weight = 2 }, { value = 0.5, weight = 2 } },
}

-- Barriers and blocks -------------------------------------------------------

item { name = "road_barrier", title = "Concrete road barrier 32x16", w = 32, h = 16,
  category = "road", collision = "low", variants = 6, wear = CONCRETE_WEAR,
  draw = function(s, r)
    -- The classic splayed-profile barrier: a wide foot, a battered face and a
    -- narrow top. Drawn as three stacked bands, because at this height the
    -- profile IS the object and a straight-sided block reads as a kerb.
    local top, bot = 5, 14
    P.rect_fill(s, 1, top, 30, bot - top + 1, "concrete_4")
    P.rect_fill(s, 3, top, 26, 2, "concrete_5")          -- the narrow top
    P.rect_fill(s, 3, top, 26, 1, "concrete_6")
    P.rect_fill(s, 1, bot - 1, 30, 2, "concrete_3")      -- the splayed foot
    P.rect_fill(s, 1, bot, 30, 1, "concrete_2")
    -- the two chamfers of the profile, which is what the eye reads as "barrier"
    for i = 0, 1 do
      P.hline(s, 2 + i, top + 2 + i, 28 - 2 * i, "concrete_4")
    end
    concrete.fill(s, r:branch("face"), { area = { x = 1, y = top + 2, w = 30, h = 6 },
      wear = 0.5, mask = function(x, y) return y > top + 1 and y < bot - 1 end })
    -- the lifting eyes cast into the top: a real barrier is a precast unit
    for _, x in ipairs { 8, 23 } do
      P.rect_fill(s, x, top, 2, 1, "concrete_2")
    end
    -- and the joint where this unit butts the next
    P.vline(s, 1, top + 2, bot - top - 3, "concrete_3")
    P.vline(s, 30, top + 2, bot - top - 3, "concrete_2")
  end }

item { name = "concrete_block", title = "Concrete block 16x16", category = "road",
  collision = "hull", variants = 8, wear = CONCRETE_WEAR,
  draw = function(s, r)
    -- A plain cast block, dumped as a vehicle stop. Its whole read is the top
    -- face against the front face, so those get a clear value step.
    local x0, y0 = 2, 6
    local w, h = 12, 8
    object.box(s, x0, y0, w, h, "concrete", 4)
    P.rect_fill(s, x0, y0, w, 2, "concrete_5")
    P.rect_fill(s, x0 + 1, y0, w - 2, 1, "concrete_6")
    concrete.fill(s, r:branch("face"), { area = { x = x0, y = y0 + 2, w = w, h = h - 3 },
      wear = 0.6, mask = function(x, y) return x > x0 and x < x0 + w - 1 and y > y0 + 1 end })
    -- a broken corner, because nothing out here is undamaged
    if r:chance(0.5) then
      local cx = r:chance(0.5) and x0 or (x0 + w - 3)
      concrete.spall(s, cx + 1, y0 + r:range(3, 5), r:range(4, 7), r, {})
    end
  end }

item { name = "roadside_marker", title = "Roadside marker 16x16", category = "road",
  collision = "none", variants = 8, wear = CONCRETE_WEAR,
  draw = function(s, r)
    -- The little painted concrete post at the edge of every Soviet road. Small,
    -- vertical, and the one asset in the kit with a band of near-white on it --
    -- which is why it reads at a distance and why it is worth having.
    local x, top = 7, 5
    object.upright(s, x, top, 14, "concrete", 4, { width = 3 })
    P.rect_fill(s, x, top, 3, 1, "concrete_6")
    -- the reflective band, dirty
    P.rect_fill(s, x, top + 2, 3, 2, "concrete_6")
    P.rect_fill(s, x + 2, top + 2, 1, 2, "concrete_4")
    if r:chance(0.6) then P.pixel(s, x + r:range(0, 2), top + 3, "dirt_3") end
  end }

item { name = "road_cone", title = "Road cone 16x16", category = "road",
  collision = "none", variants = 6,
  wear = { ramp = "rust", dirt = { { value = 0.06, weight = 2 }, { value = 0.14, weight = 2 } } },
  draw = function(s, r)
    -- A cone is a triangle, and at 16px a triangle needs a wide base and a
    -- one-pixel tip or it reads as a lump. Ochre stands in for the orange
    -- plastic: the palette has no orange, and rust is the nearest honest thing.
    local base_y, tip_y = 14, 6
    for y = base_y, tip_y, -1 do
      local t = (base_y - y) / (base_y - tip_y)
      local half = math.max(0, math.floor(4 * (1 - t) + 0.5))
      P.hline(s, 8 - half, y, half * 2 + 1, "rust_3")
      P.pixel(s, 8 - half, y, "rust_4")          -- lit left edge
      P.pixel(s, 8 + half, y, "rust_2")          -- shaded right edge
    end
    -- the white band, and the base flange
    P.hline(s, 5, base_y - 4, 7, "concrete_5")
    P.hline(s, 4, base_y, 9, "rust_2")
    P.hline(s, 4, base_y - 1, 9, "rust_3")
  end }

-- Signage -------------------------------------------------------------------

--- A sign post: the shared upright every sign in the kit stands on.
local function sign_post(s, x, y0, y1, rng_stream)
  object.upright(s, x, y0, y1, "metal", 4, { width = 2 })
  -- the concrete pad it is set into
  P.rect_fill(s, x - 2, y1 - 1, 6, 2, "concrete_3")
  P.rect_fill(s, x - 2, y1 - 1, 6, 1, "concrete_4")
end

item { name = "sign_post", title = "Sign post, empty 16x32", w = 16, h = 32,
  category = "road", collision = "hull", variants = 6, wear = STEEL_WEAR,
  draw = function(s, r)
    -- The post with its sign long gone -- only the fixing brackets left. This
    -- is the most post-apocalyptic asset in the kit and costs almost nothing.
    -- The bracket positions and count vary, which is the only structural
    -- freedom this asset has. Without it two seeds produced byte-identical
    -- output -- the variant_similarity rule caught it as "the seed did
    -- nothing", and it was right: the post is drawn deterministically and its
    -- wear channels can both roll to nothing.
    local top = r:range(4, 7)
    sign_post(s, 7, top, 30, r)
    local brackets = r:range(2, 3)
    for i = 0, brackets - 1 do
      local y = top + 2 + i * r:range(3, 4)
      if y > 26 then break end
      P.rect_fill(s, 5, y, 6, 1, "metal_5")
      P.rect_fill(s, 5, y + 1, 6, 1, "metal_2")
      -- a sheared bolt left in one bracket
      if r:chance(0.4) then P.pixel(s, r:chance(0.5) and 5 or 10, y, "rust_2") end
    end
  end }

item { name = "road_sign", title = "Road sign 16x32", w = 16, h = 32,
  category = "road", collision = "hull", variants = 8, wear = STEEL_WEAR,
  draw = function(s, r)
    sign_post(s, 7, 10, 30, r)
    -- The face: a plate with a rim, seen straight on. Its legend is
    -- deliberately abstract -- a bar or a disc -- because real lettering at
    -- 12px is illegible and a fake alphabet reads as noise.
    local x0, y0, w, h = 2, 3, 12, 9
    P.rect_fill(s, x0, y0, w, h, "concrete_4")
    P.rect(s, x0, y0, w, h, "concrete_5")
    P.rect_fill(s, x0 + 1, y0 + 1, w - 2, 1, "concrete_5")
    P.rect_fill(s, x0 + 1, y0 + h - 2, w - 2, 1, "concrete_3")
    local legend = r:weighted {
      { value = "bar", weight = 3 }, { value = "disc", weight = 2 }, { value = "arrow", weight = 2 },
    }
    if legend == "bar" then
      P.rect_fill(s, x0 + 2, y0 + 4, w - 4, 2, "ink_4")
    elseif legend == "disc" then
      P.cluster(s, x0 + w // 2, y0 + h // 2, 12, "ink_4", r, { spread = 0 })
    else
      P.line(s, x0 + 3, y0 + h - 3, x0 + w - 4, y0 + 2, "ink_4")
      P.hline(s, x0 + w - 6, y0 + 2, 3, "ink_4")
    end
  end }

item { name = "road_sign_broken", title = "Road sign, broken 16x32", w = 16, h = 32,
  category = "road", collision = "hull", variants = 8, max_interior_holes = 3,
  wear = STEEL_WEAR,
  draw = function(s, r)
    -- Bent over and holed. The BEND is the asset: a sign knocked sideways
    -- reads as violence in a way a rusty straight one does not, so the post
    -- kinks partway up and the plate leans with it.
    local kink = r:range(16, 22)
    object.upright(s, 7, kink, 30, "metal", 4, { width = 2 })
    P.rect_fill(s, 5, 29, 6, 2, "concrete_3")
    local lean = r:chance(0.5) and 1 or -1
    local fx = 7
    for y = kink - 1, 6, -1 do
      P.rect_fill(s, math.floor(fx), y, 2, 1, "metal_4")
      P.pixel(s, math.floor(fx), y, "metal_5")
      if (kink - y) % 3 == 2 then fx = fx + lean end
    end
    -- the plate, leaning with the post and torn
    local px = math.max(1, math.min(9, math.floor(fx) - 4))
    P.rect_fill(s, px, 3, 10, 8, "concrete_4")
    P.rect(s, px, 3, 10, 8, "concrete_5")
    local tear = r:branch("tear")
    local blob = P.cluster(s, px + tear:range(2, 7), tear:range(4, 9),
      tear:range(4, 9), "concrete_2", tear, { spread = 0.6 })
    for _, p in ipairs(blob) do s:set(p[1], p[2], palette.TRANSPARENT) end
    for _, p in ipairs(blob) do
      local above = s:get(p[1], p[2] - 1)
      if above ~= palette.TRANSPARENT then s:set(p[1], p[2] - 1, "concrete_3") end
    end
  end }

-- Poles and lighting --------------------------------------------------------

item { name = "utility_pole", title = "Utility pole 16x48", w = 16, h = 48,
  category = "industrial", collision = "hull", variants = 6,
  wear = { ramp = "wood", dirt = { { value = 0.05, weight = 2 }, { value = 0.12, weight = 2 } },
    vegetation = { { value = 0, weight = 3 }, { value = 1, weight = 1 } },
    vegetation_area = { x = 3, y = 42, w = 10, h = 4 } },
  draw = function(s, r)
    -- Creosoted timber, three cells tall, with a crossarm near the top and
    -- insulators on it. The crossarm is the silhouette cue: without it a pole
    -- is a stick, and with it the shape is unmistakable at any distance.
    local x = 7
    for y = 46, 4, -1 do
      P.rect_fill(s, x, y, 3, 1, "wood_3")
      P.pixel(s, x, y, "wood_4")
      P.pixel(s, x + 2, y, "wood_2")
    end
    wood.fill(s, r:branch("grain"), { area = { x = x, y = 4, w = 3, h = 43 }, axis = "v",
      base = "wood_3", mask = function(px) return px >= x and px <= x + 2 end })
    -- the crossarm, lit on top with its own shadow under it
    local arm_y = r:range(8, 11)
    object.rail(s, 1, 14, arm_y, "wood", 3, { thickness = 2 })
    -- insulators: paired pixels on top of the arm, never single
    for _, ix in ipairs { 3, 7, 11 } do
      P.rect_fill(s, ix, arm_y - 2, 2, 2, "concrete_5")
      P.pixel(s, ix, arm_y - 2, "concrete_6")
      P.pixel(s, ix + 1, arm_y - 1, "concrete_3")
    end
    -- the step bolts up the pole, and the base pad
    for y = 20, 40, 6 do P.rect_fill(s, x - 1, y, 2, 1, "metal_4") end
    P.rect_fill(s, x - 2, 45, 7, 2, "earth_2")
  end }

item { name = "utility_pole_damaged", title = "Utility pole, damaged 16x48", w = 16, h = 48,
  category = "industrial", collision = "hull", variants = 6,
  wear = { ramp = "wood", dirt = { { value = 0.06, weight = 2 }, { value = 0.14, weight = 2 } } },
  draw = function(s, r)
    -- Snapped, with the top hanging off and the wires down. The break is a
    -- splintered run, the same grammar as broken_trunk -- a pole and a tree
    -- fail the same way because they are the same material.
    local x = 7
    local break_y = r:range(16, 24)
    for y = 46, break_y, -1 do
      P.rect_fill(s, x, y, 3, 1, "wood_3")
      P.pixel(s, x, y, "wood_4")
      P.pixel(s, x + 2, y, "wood_2")
    end
    for i = 0, 2 do
      local h = r:range(1, 3)
      for k = 0, h do P.pixel(s, x + i, break_y - k, "wood_3") end
      P.pixel(s, x + i, break_y - h, "wood_5")
    end
    -- the top, hanging: a leaning run of timber with the crossarm still on it
    local lean = r:chance(0.5) and 1 or -1
    local fx, fy = x, break_y - 4
    for i = 0, r:range(7, 11) do
      P.rect_fill(s, math.floor(fx), fy, 2, 1, "wood_3")
      P.pixel(s, math.floor(fx), fy, "wood_4")
      fx = fx + lean * 0.6
      fy = fy - (i % 3 == 2 and 0 or 1)
      if fx < 1 or fx > 13 then break end
    end
    -- and the wire, hanging in a catenary from the break. A wire reads only if
    -- it SAGS: a straight line at this scale is a scratch.
    local wire = r:branch("wire")
    local wx = math.floor(fx)
    for i = 0, 6 do
      local wy = fy + (i * i) // 4
      if wy > 46 then break end
      P.pixel(s, math.max(0, wx - i), wy, "metal_2")
    end
    P.rect_fill(s, x - 2, 45, 7, 2, "earth_2")
  end }

item { name = "lamp_post", title = "Lamp post 16x48", w = 16, h = 48,
  category = "industrial", collision = "hull", variants = 6, wear = STEEL_WEAR,
  draw = function(s, r)
    -- A steel column with a swan neck and a lantern. The neck is the read, and
    -- it has to be a smooth stepped curve -- a right angle looks like a gibbet.
    local x = 8
    object.upright(s, x, 8, 45, "metal", 4, { width = 3 })
    -- the swan neck, stepping left and up
    local steps = { { 7, 7 }, { 6, 6 }, { 5, 5 }, { 4, 5 }, { 3, 5 } }
    for _, st in ipairs(steps) do
      P.rect_fill(s, st[1], st[2], 2, 2, "metal_4")
      P.pixel(s, st[1], st[2], "metal_5")
    end
    -- the lantern: a shallow box under the neck, its underside the brightest
    -- thing on the asset because that is where the lamp is
    P.rect_fill(s, 1, 6, 6, 3, "metal_5")
    P.rect_fill(s, 1, 6, 6, 1, "metal_6")
    P.rect_fill(s, 2, 9, 4, 1, "concrete_6")
    -- the base flange and the access door every steel column has
    P.rect_fill(s, x - 1, 44, 5, 2, "metal_5")
    P.rect_fill(s, x - 1, 45, 5, 1, "metal_2")
    P.rect(s, x, 34, 3, 6, "metal_3")
  end }

item { name = "lamp_post_broken", title = "Lamp post, broken 16x48", w = 16, h = 48,
  category = "industrial", collision = "hull", variants = 6, wear = STEEL_WEAR,
  draw = function(s, r)
    -- The lantern gone and the neck bent down. A column that is merely rusty
    -- reads as maintained-but-old; one whose head has been torn off reads as
    -- abandoned, which is the world this is for.
    local x = 8
    object.upright(s, x, r:range(10, 14), 45, "metal", 4, { width = 3 })
    local top = r:range(10, 14)
    -- the neck, bent over and torn off short
    local fx, fy = x, top - 1
    for i = 0, r:range(3, 6) do
      P.rect_fill(s, math.floor(fx), fy, 2, 1, "metal_4")
      P.pixel(s, math.floor(fx), fy, "metal_5")
      fx = fx - 1
      fy = fy + (i % 2 == 1 and 1 or 0)
      if fx < 1 then break end
    end
    -- the torn end, corroded
    P.pixel(s, math.max(1, math.floor(fx)), fy, "rust_2")
    P.pixel(s, math.max(1, math.floor(fx)), fy + 1, "rust_1")
    P.rect_fill(s, x - 1, 44, 5, 2, "metal_5")
    P.rect_fill(s, x - 1, 45, 5, 1, "metal_2")
    -- the door hanging open, and the wiring loom spilling out of it
    P.rect(s, x, 34, 3, 6, "metal_2")
    P.rect_fill(s, x + 3, 35, 2, 4, "metal_3")
    if r:chance(0.7) then
      for k = 0, 2 do P.pixel(s, x + 1 + k % 2, 40 + k, "rust_1") end
    end
  end }

-- Cabinets and boxes --------------------------------------------------------

item { name = "electrical_cabinet", title = "Electrical cabinet 16x32", w = 16, h = 32,
  category = "industrial", collision = "hull", variants = 8, wear = STEEL_WEAR,
  draw = function(s, r)
    -- A waist-high steel cabinet on a concrete plinth: door, hinges, handle,
    -- louvres. The louvres are the detail that says "electrical" and they are
    -- drawn as broken runs so they never become a comb.
    local x0, y0, w, h = 2, 8, 12, 20
    object.box(s, x0, y0, w, h, "metal", 4)
    P.rect_fill(s, x0, y0, w, 2, "metal_5")
    P.rect_fill(s, x0 + 1, y0, w - 2, 1, "metal_6")
    -- the door, inset one pixel so it reads as a door
    P.rect(s, x0 + 1, y0 + 3, w - 2, h - 6, "metal_3")
    P.rect_fill(s, x0 + 2, y0 + 4, w - 4, h - 8, "metal_4")
    -- louvres
    local lv = r:branch("louvre")
    for y = y0 + 6, y0 + h - 8, 3 do
      P.broken_run(s, "h", y, x0 + 3, x0 + w - 4, lv,
        { delta = -1, run = { 3, 6 }, gap = { 1, 2 } })
    end
    -- hinges on the left, handle on the right: an asymmetry that reads at 1x
    for _, y in ipairs { y0 + 5, y0 + h - 7 } do P.rect_fill(s, x0 + 1, y, 1, 2, "metal_5") end
    P.rect_fill(s, x0 + w - 3, y0 + h // 2, 2, 2, "metal_6")
    -- the plinth
    P.rect_fill(s, x0 - 1, y0 + h, w + 2, 2, "concrete_3")
    P.rect_fill(s, x0 - 1, y0 + h, w + 2, 1, "concrete_4")
    -- the warning plate, faded: one bright pair, which is all it needs
    if r:chance(0.7) then P.rect_fill(s, x0 + 3, y0 + 4, 2, 1, "rust_4") end
  end }

item { name = "junction_box", title = "Junction box 16x16", category = "industrial",
  collision = "hull", variants = 8, wear = STEEL_WEAR,
  draw = function(s, r)
    -- A small box on a short stalk, with conduit leaving the bottom. Reads at
    -- 1x because the silhouette is a plain rectangle on a stem.
    -- Size and stalk height vary: with a fixed box and two wear channels that
    -- can both roll to nothing, two seeds came out byte-identical.
    local w = r:range(7, 9)
    local h = r:range(6, 8)
    local x0 = 8 - w // 2
    local y0 = r:range(3, 5)
    object.box(s, x0, y0, w, h, "metal", 4)
    P.rect_fill(s, x0, y0, w, 1, "metal_6")
    P.rect(s, x0 + 1, y0 + 1, w - 2, h - 2, "metal_3")
    -- the lid screws: paired pixels, never single
    P.rect_fill(s, x0 + 1, y0 + 1, 2, 1, "metal_5")
    P.rect_fill(s, x0 + w - 3, y0 + 1, 2, 1, "metal_5")
    -- the stalk and the conduit
    object.upright(s, 7, y0 + h, 14, "metal", 3, { width = 2 })
    if r:chance(0.6) then
      local cx = r:chance(0.5) and (x0 - 1) or (x0 + w)
      for k = 0, r:range(2, 3) do P.pixel(s, cx, y0 + 3 + k, "metal_3") end
    end
  end }

-- Pipework and drainage -----------------------------------------------------

item { name = "pipe_segment", title = "Pipe segment 32x16", w = 32, h = 16,
  category = "industrial", collision = "low", variants = 8, wear = STEEL_WEAR,
  draw = function(s, r)
    -- A length of large-bore pipe lying on the ground: a cylinder shaded across
    -- its width, with a flange at each end and the bore showing dark. The bore
    -- is what stops it reading as a log.
    local y0, h = 6, 7
    object.cylinder(s, 1, y0, 30, h, "metal", 4)
    P.rect_fill(s, 1, y0, 30, 1, "metal_5")
    P.rect_fill(s, 1, y0 + 1, 30, 1, "metal_6")
    P.rect_fill(s, 1, y0 + h - 1, 30, 1, "metal_2")
    -- the flanges
    for _, fx in ipairs { 1, 28 } do
      P.rect_fill(s, fx, y0 - 1, 3, h + 2, "metal_5")
      P.rect_fill(s, fx, y0 - 1, 3, 1, "metal_6")
      P.rect_fill(s, fx, y0 + h, 3, 1, "metal_2")
    end
    -- the bore, at the left end: dark, with the wall thickness lit above it
    P.rect_fill(s, 1, y0 + 2, 2, h - 4, "ink_4")
    P.pixel(s, 1, y0 + 1, "metal_6")
  end }

item { name = "pipe_bent", title = "Pipe, bent and broken 16x16", category = "industrial",
  collision = "low", variants = 8, wear = STEEL_WEAR,
  draw = function(s, r)
    -- A torn-off elbow. Two runs meeting at a right angle with a ragged end:
    -- pipe reads by being STRAIGHT and circular in section, so the damage has
    -- to be at the ends and never along the length.
    local h = 5
    object.cylinder(s, 1, 8, 10, h, "metal", 4)
    P.rect_fill(s, 1, 8, 10, 1, "metal_5")
    -- the elbow, turning up
    for i = 0, 4 do
      P.rect_fill(s, 9 + (i > 2 and 1 or 0), 8 - i, h - 1, 1, "metal_4")
      P.pixel(s, 9 + (i > 2 and 1 or 0), 8 - i, "metal_5")
    end
    -- the torn ends, corroded
    P.rect_fill(s, 1, 9, 1, h - 2, "ink_4")
    for k = 0, 2 do P.pixel(s, 10 + k, 3, "rust_1") end
  end }

item { name = "manhole", title = "Manhole cover 16x16", category = "road",
  collision = "none", variants = 8, outline = false, shadow = false,
  wear = { ramp = "metal", rust = { { value = 0.10, weight = 2 }, { value = 0.22, weight = 2 } },
    rust_bias = function() return 1.0 end },
  draw = function(s, r)
    -- Flush with the road, so NO outline and NO contact shadow: an outlined
    -- manhole floats above the surface it is set into. It reads by its rim and
    -- by the cast pattern on it, both of which are recesses.
    local cx, cy = 8, 8
    -- the cast iron disc, drawn as a chunky circle
    for y = 2, 13 do
      local dy = y - cy
      local half = math.floor(math.sqrt(math.max(0, 36 - dy * dy)))
      if half > 0 then P.hline(s, cx - half, y, half * 2, "metal_4") end
    end
    -- the frame it sits in: a recess, so the lit lip is on the lower-right
    for y = 2, 13 do
      local dy = y - cy
      local half = math.floor(math.sqrt(math.max(0, 36 - dy * dy)))
      if half > 0 then
        P.pixel(s, cx - half, y, "metal_2")
        P.pixel(s, cx + half - 1, y, "metal_5")
      end
    end
    -- the cast pattern: concentric, and drawn as broken runs so it stays a
    -- pattern rather than becoming a target
    local cast = r:branch("cast")
    for _, ry in ipairs { 5, 8, 11 } do
      P.broken_run(s, "h", ry, cx - 4, cx + 3, cast,
        { delta = -1, run = { 2, 3 }, gap = { 1, 2 } })
    end
    -- the lifting slot
    P.rect_fill(s, cx - 1, cy - 1, 2, 1, "metal_2")
  end }

item { name = "drain", title = "Gully / drain 16x16", category = "road",
  collision = "none", variants = 8, outline = false, shadow = false,
  wear = { ramp = "metal", rust = { { value = 0.12, weight = 2 }, { value = 0.24, weight = 2 } },
    rust_bias = function() return 1.0 end },
  draw = function(s, r)
    -- A kerbside gully grating: a rectangular frame with bars across it and
    -- darkness behind them. Flush like the manhole, so no outline.
    -- Frame size and bar pitch vary. Fixed, this asset's only variation was a
    -- silt cluster and a rust channel, and three pairs of seeds came out
    -- byte-identical.
    local w = r:range(9, 11)
    local h = r:range(6, 8)
    local x0 = 8 - w // 2
    local y0 = r:range(4, 6)
    P.rect_fill(s, x0, y0, w, h, "ink_4")            -- the void behind the bars
    P.rect(s, x0, y0, w, h, "metal_4")
    P.hline(s, x0, y0, w, "metal_5")                  -- frame, lit on top
    P.hline(s, x0, y0 + h - 1, w, "metal_2")
    -- the bars: runs, and spaced so the grating is never symmetrical
    local pitch = r:range(2, 3)
    for x = x0 + 2, x0 + w - 3, pitch do
      P.vline(s, x, y0 + 1, h - 2, "metal_4")
      P.pixel(s, x, y0 + 1, "metal_5")
    end
    -- silt washed into it, which is what says this drain has not worked in
    -- twenty years
    if r:chance(0.8) then
      P.cluster(s, r:range(x0 + 1, x0 + w - 2), y0 + h - 2, r:range(3, 6), "earth_2", r,
        { spread = 0.8 })
    end
  end }

-- Scrap ---------------------------------------------------------------------

item { name = "metal_sheet", title = "Metal sheet 16x16", category = "industrial",
  collision = "none", variants = 8,
  wear = { ramp = "metal", rust = { { value = 0.15, weight = 2 }, { value = 0.35, weight = 3 } } },
  draw = function(s, r)
    -- A loose sheet of corrugated roofing lying on the ground, one corner
    -- lifted. The lifted corner is the whole asset: a flat sheet is a
    -- rectangle, and a rectangle with one corner off the deck is an object.
    local x0, y0, w, h = 1, 5, 13, 9
    P.rect_fill(s, x0, y0, w, h, "metal_4")
    metal.corrugate(s, r, { pitch = 3, area = { x = x0, y = y0, w = w, h = h } })
    P.rect_fill(s, x0, y0, w, 1, "metal_5")
    -- the lifted corner: a wedge, lighter because it catches the sky
    for i = 0, 4 do
      P.hline(s, x0 + w - 5 + i, y0 - 1 - i, 5 - i, "metal_5")
    end
    P.pixel(s, x0 + w - 1, y0 - 5, "metal_6")
    -- and the shadow it throws under itself
    P.hline(s, x0 + 1, y0 + h, w - 2, "ink_3")
  end }

item { name = "scrap_pile", title = "Scrap metal pile 16x16", category = "industrial",
  collision = "low", variants = 10, max_interior_holes = 3,
  wear = { ramp = "metal", rust = { { value = 0.25, weight = 2 }, { value = 0.45, weight = 3 } } },
  draw = function(s, r)
    -- A heap of offcuts. Metal reads by being STRAIGHT, so this is a stack of
    -- runs at differing angles -- never a blob -- with the longest members at
    -- the bottom and the pile silhouette rising to the left, where the light
    -- is.
    for i = 1, r:range(5, 8) do
      local y = 13 - (i - 1)
      if y < 5 then break end
      local len = r:range(4, 11)
      local x = r:range(1, math.max(1, 14 - len))
      local dy = r:chance(0.35) and 1 or 0
      for k = 0, len - 1 do
        local yy = y - (k * dy) // 4
        P.pixel(s, x + k, yy, "metal_4")
        if k == 0 or r:chance(0.4) then P.pixel(s, x + k, yy - 1, "metal_5") end
      end
    end
    -- a length of angle iron across the top, which gives the pile a readable
    -- top edge instead of a fuzzy one
    if r:chance(0.7) then
      local y = r:range(5, 7)
      P.hline(s, r:range(2, 5), y, r:range(6, 9), "metal_5")
    end
  end }

item { name = "cable_debris", title = "Cable debris 16x16", category = "industrial",
  -- A coil of wire is a sparse self-lit overlay of one-pixel runs with no
  -- outline and no interior -- the same shape of asset as a tuft, so it is a
  -- `decal` by surface for the same reason (see generators/vegetation.lua).
  -- Held to the prop rules it failed min_occupancy for being thin, which is
  -- what a cable is.
  collision = "none", variants = 8, outline = false, shadow = false, surface = "decal",
  draw = function(s, r)
    -- A coil of dropped wiring. A cable reads by CURVING -- everything else in
    -- this kit is straight -- so it is drawn as a loose loop, two pixels of
    -- run at a time, never a single scattered pixel.
    local cx, cy = 8, 9
    local rx, ry = r:range(4, 6), r:range(2, 4)
    for a = 0, 23 do
      local t = a / 24 * 2 * math.pi
      local x = math.floor(cx + rx * math.cos(t) + 0.5)
      local y = math.floor(cy + ry * math.sin(t) + 0.5)
      P.pixel(s, x, y, "metal_2")
    end
    -- a tail leaving the coil, held straight so it reads as the loose end
    local tail = r:range(3, 5)
    local ty = cy + ry
    for k = 0, tail do P.pixel(s, math.min(15, cx + rx + k - 1), math.min(15, ty + k // 2), "metal_2") end
    -- the copper showing where the insulation has gone: one pair, no more
    if r:chance(0.6) then
      local px, py = cx - rx, cy
      P.pixel(s, px, py, "rust_3")
      P.pixel(s, px, py + 1, "rust_2")
    end
  end }

item { name = "pallet", title = "Abandoned pallet 16x16", category = "industrial",
  collision = "low", variants = 8, max_interior_holes = 4,
  wear = { ramp = "wood", dirt = { { value = 0.08, weight = 2 }, { value = 0.16, weight = 2 } },
    missing = { { value = 0, weight = 3 }, { value = 0.4, weight = 2 } }, tear = "wood_2" },
  draw = function(s, r)
    -- Seen from above at a slight angle: top boards with gaps between them,
    -- and the bearers showing through the gaps. The GAPS are the asset -- a
    -- pallet without them is a board.
    local x0, y0, w, h = 1, 4, 14, 10
    -- the bearers, dark, showing through
    P.rect_fill(s, x0, y0, w, h, "wood_2")
    -- the top boards: runs across, with a lit upper edge each
    for i = 0, 3 do
      local by = y0 + i * 3
      if by + 1 > y0 + h - 1 then break end
      P.rect_fill(s, x0, by, w, 2, "wood_4")
      P.rect_fill(s, x0, by, w, 1, "wood_5")
      P.rect_fill(s, x0, by + 1, w, 1, "wood_3")
    end
    -- the two end bearers, which give it thickness
    P.rect_fill(s, x0, y0, 1, h, "wood_3")
    P.rect_fill(s, x0 + w - 1, y0, 1, h, "wood_2")
  end }

return set
