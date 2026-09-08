-- generators/concrete_ruin_wall.lua -- 16x16 seamless ruined concrete wall.
--
-- Post-Soviet panel construction: cast courses with a joint every 16px,
-- weather staining, spalling where the surface has broken off, and rust
-- bleeding from the reinforcement it has broken off down to.
--
-- The horizontal joint is deliberate structure -- a wall SHOULD show how it
-- was built -- but a joint drawn as a clean straight line on every tile is
-- what made a wall run read as a printed pattern rather than as a ruin. So the
-- joint DECAYS: it wanders a pixel off its row and loses a chunk here and
-- there, pinned at both ends so a run still connects (see concrete.groove).
--
-- The other half of the fix is structural variation, and it comes from the
-- panel butt joint: a minority of tiles carry a full-height vertical joint, so
-- a wall run shows where one cast panel ends and the next begins instead of
-- being one endless slab. It runs the whole 16px between courses, which is
-- exactly what a panel edge does, and it is off-centre so it never lines up
-- with the tile grid it sits in.

local P = require("pixel_utils")
local materials = require("materials")

local concrete, rust, dirt, grass = materials.concrete, materials.rust, materials.dirt, materials.grass

local gen = {
  name = "concrete_ruin_wall",
  title = "Concrete ruin wall 16x16",
  size = { w = 16, h = 16 },
  tileable = true,
  surface = "structure",
}

function gen.build(rng_stream, opts)
  opts = opts or {}
  local s = P.new(gen.size.w, gen.size.h, { wrap = true })

  -- material: daylight concrete, a step lighter than anything underground
  concrete.fill(s, rng_stream, { base = opts.base or "concrete_4", wear = 0.6 })

  -- structure: the cast joint between courses, decayed
  concrete.groove(s, "h", 0, rng_stream, { color = "concrete_2", decay = 0.7 })

  -- structure: the butt joint between two cast panels, on a minority of tiles
  local panel = rng_stream:branch("panel")
  local panel_x
  if panel:chance(0.28) then
    panel_x = panel:range(4, 12)
    concrete.groove(s, "v", panel_x, panel, { color = "concrete_2", decay = 0.4 })
  end

  -- structure: spalling. ONE piece of damage, big enough to read as a chunk
  -- broken off a wall, and sometimes a second. Two or three small spalls plus
  -- a scatter of aggregate was the old recipe, and it read as grain rather
  -- than as damage -- the tile has to look broken, not dirty.
  local damage = rng_stream:branch("damage")
  local spalls = {}
  for _ = 1, damage:chance(0.30) and 2 or 1 do
    local blob = concrete.spall(s, damage:range(0, 15), damage:range(2, 15),
      damage:range(8, 14), damage, {})
    spalls[#spalls + 1] = blob
  end

  -- structure: the reinforcement the spall has broken down to. This is the
  -- mark that separates a ruined structural wall from a stained one.
  -- Ochre is the loudest thing in the palette (ART_STYLE.md 3), and a bar is
  -- the loudest use of it: bright, straight and long. One tile in four, no
  -- more, or a wall run turns into a scatter of yellow marks.
  if #spalls > 0 and damage:chance(0.25) then
    local blob = spalls[1]
    local at = blob[damage:range(1, #blob)]
    local axis = damage:chance(0.65) and "h" or "v"
    rust.bar(s, at[1], at[2], damage:range(3, 5), axis, damage, {})
  end

  -- structure: a fracture running off the damage, or off the joint
  if damage:chance(0.45) then
    local from = #spalls > 0 and spalls[1][damage:range(1, #spalls[1])] or { damage:range(0, 15), 1 }
    concrete.crack(s, from[1], from[2], damage:range(5, 9), damage, { color = "concrete_2" })
  end

  -- wear: rust and grime COLLECT, they do not scatter. Water runs out of the
  -- joint and down the panel edge, so that is where both of them go; evenly
  -- spread wear is the tell-tale of generated art (ART_STYLE.md 10).
  local function runs_off_joint(x, y)
    if y <= 3 then return 1.0 end
    if panel_x and math.abs(x - panel_x) <= 1 then return 0.8 end
    return 0.15
  end
  rust.fill(s, rng_stream, {
    coverage = rng_stream:weighted {
      { value = 0.00, weight = 3 },
      { value = 0.06, weight = 3 },
      { value = 0.14, weight = 2 },
    },
    streaks = true,
    mask = P.ramp_mask("concrete"),
    bias = runs_off_joint,
  })
  dirt.fill(s, rng_stream, { coverage = 0.07, bias = runs_off_joint })

  -- wear: what has taken root in the joint, which is the only place on a
  -- vertical face that holds enough dirt for anything to grow
  if rng_stream:chance(0.16) then
    local moss = rng_stream:branch("moss")
    grass.tufts(s, 1, moss, { at = { moss:range(0, 15), moss:range(1, 3) }, color = "grass_2" })
  end

  -- cleanup
  P.despeckle(s)
  return s
end

return gen
