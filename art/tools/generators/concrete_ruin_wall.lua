-- generators/concrete_ruin_wall.lua -- 16x16 seamless ruined concrete wall.
--
-- Post-Soviet panel construction: cast courses with a joint every 16px, weather
-- staining, spalling where the surface has broken off, and rust bleeding from
-- whatever reinforcement is exposed. The horizontal joint is deliberate
-- structure -- a wall SHOULD show how it was built -- but there is no vertical
-- joint, so a wall run never turns into a chequerboard.

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

  -- structure: the cast joint between courses
  concrete.groove(s, "h", 0, rng_stream, { color = "concrete_2" })

  -- structure: spalling and fractures
  local damage = rng_stream:branch("damage")
  for _ = 1, damage:range(1, 2) do
    concrete.spall(s, damage:range(0, 15), damage:range(2, 15), damage:range(4, 9), damage, {})
  end
  if damage:chance(0.6) then
    concrete.crack(s, damage:range(0, 15), damage:range(2, 15), damage:range(4, 8), damage,
      { color = "concrete_2" })
  end

  -- wear: rust bleeding out of the reinforcement, weather staining, and the
  -- vegetation that gets into everything out here
  rust.fill(s, rng_stream, {
    coverage = rng_stream:weighted {
      { value = 0.00, weight = 3 },
      { value = 0.06, weight = 3 },
      { value = 0.14, weight = 2 },
    },
    streaks = true,
    mask = P.ramp_mask("concrete"),
  })
  dirt.fill(s, rng_stream, { coverage = 0.10 })
  if rng_stream:chance(0.35) then
    grass.tufts(s, 1, rng_stream:branch("moss"), { color = "grass_2" })
  end

  -- cleanup
  P.despeckle(s)
  return s
end

return gen
