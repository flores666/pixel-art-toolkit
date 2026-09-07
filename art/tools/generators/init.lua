-- generators/init.lua -- the generator registry and the generator contract.
--
-- Contract -- every module in this folder returns:
--   name                string, unique, snake_case; also the rng salt
--   title               string shown in the Aseprite menus
--   size                { w, h } -- must satisfy style.check_size
--   tileable            bool -- true means the surface wraps and the asset is
--                       meant to repeat seamlessly against itself
--   surface             "ground" | "structure" | "prop" -- what the asset is
--                       FOR. Sets its texture-busyness ceiling (style.max_edge_density)
--                       and, for "ground", commits it to the no-visible-grid
--                       discipline checked by previews.grid_report
--   preview_background  generator name drawn underneath in previews (objects)
--   build(rng_stream, opts) -> Surface
--
-- build() must be pure: the same (name, seed) must produce the same pixels
-- forever. Take every random decision from `rng_stream` (or a named branch of
-- it) and never from math.random.
--
-- To add a generator: drop the file in, add its name to `generators.names`.

local style = require("style")
local rng = require("rng")

local generators = {}

generators.names = {
  -- ground: laid in fields, so they must not print a grid (see previews.grid_report)
  "dirt_ground",
  "dry_grass",
  "cracked_asphalt",
  -- structure
  "concrete_ruin_wall",
  "rusted_fence",
  -- props
  "supply_crate",
  "rusted_barrel",
}

for _, name in ipairs(generators.names) do
  local gen = require("generators." .. name)
  assert(gen.name == name, ("generator '%s' reports name '%s'"):format(name, tostring(gen.name)))
  assert(style.max_edge_density[gen.surface],
    ("generator '%s' declares unknown surface '%s'"):format(name, tostring(gen.surface)))
  local ok, err = style.check_size(gen.size.w, gen.size.h)
  assert(ok, ("generator '%s': %s"):format(name, tostring(err)))
  generators[name] = gen
end

function generators.get(name)
  return generators[name] or error("unknown generator '" .. tostring(name) .. "'", 2)
end

--- Build one asset. The rng stream is salted with the generator name, so two
-- generators given the same seed do not share a random sequence.
-- @return Surface
function generators.build(name, seed, opts)
  local gen = generators.get(name)
  local surface = gen.build(rng.new(seed or 0, name), opts or {})
  assert(surface.width == gen.size.w and surface.height == gen.size.h,
    ("generator '%s' returned %dx%d, declared %dx%d")
      :format(name, surface.width, surface.height, gen.size.w, gen.size.h))
  return surface
end

--- The spec validators need for an asset built by `name`.
function generators.spec(name)
  local gen = generators.get(name)
  return {
    name = name, width = gen.size.w, height = gen.size.h,
    wrap = gen.tileable, surface = gen.surface,
  }
end

return generators
