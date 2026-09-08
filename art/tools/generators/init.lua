-- generators/init.lua -- the generator registry and the generator contract.
--
-- Contract -- every module in this folder returns EITHER one generator table
-- or a LIST of them (a "set": a kit whose pieces share one implementation --
-- the transition autotile set, the wall kit, the fence kit). A single-generator
-- module is unchanged from the original contract; the list form is what stops
-- 105 transition tiles from being 105 near-identical files.
--
--   name                string, unique, snake_case; also the rng salt
--   title               string shown in the Aseprite menus
--   size                { w, h } -- must satisfy style.check_size
--   tileable            bool -- true means the surface wraps and the asset is
--                       meant to repeat seamlessly against itself
--   surface             "ground" | "transition" | "structure" | "prop" | "decal"
--                       -- what the asset is FOR. Sets its texture-busyness
--                       ceiling (style.max_edge_density) and, for "ground",
--                       commits it to the no-visible-grid discipline checked by
--                       previews.grid_report
--   build(rng_stream, opts) -> Surface
--
-- Optional, and all of it exists to be READ by something -- the manifest, a
-- validator or the scene composer -- rather than to describe:
--
--   category            "ground" | "transition" | "decal" | "vegetation" |
--                       "rock" | "wall" | "fence" | "road" | "industrial" |
--                       "rubble" | "prop". Fixes the layer/collision defaults
--                       (style.categories) and the output directory.
--   layer, collision    override the category default
--   variants            how many seeds are worth exporting (default 8)
--   variant_group       generators whose variants must stay mutually distinct;
--                       defaults to the generator name
--   preview_background  generator name drawn underneath in previews (objects)
--   terrain             { pair = id, mask = 0..15 } for autotile pieces
--   sockets             { left =, right =, top =, bottom = } socket names for
--                       modular pieces. Two pieces connect where they present
--                       the same socket, and `sockets` (validators) checks
--                       that every piece presenting a socket agrees with the
--                       others on that edge's opaque rows and palette ramps.
--   over                what surfaces a decal may be placed on (terrain names,
--                       or "any"); the scene composer honours it.
--   max_interior_holes  override style.prop.max_interior_holes. A BRANCHING
--                       silhouette encloses regions as a matter of geometry --
--                       a fork closes a ring -- and those holes are the asset,
--                       not wear damage. Declaring the budget keeps the rule
--                       enforcing something (a regression to twelve still
--                       fails) instead of being switched off.
--
-- build() must be pure: the same (name, seed) must produce the same pixels
-- forever. Take every random decision from `rng_stream` (or a named branch of
-- it) and never from math.random.
--
-- To add a generator: drop the file in, add its module name to
-- `generators.modules`.

local style = require("style")
local rng = require("rng")

local generators = {}

generators.modules = {
  -- ground: laid in fields, so they must not print a grid (previews.grid_report)
  "dirt_ground",
  "dry_grass",
  "cracked_asphalt",
  "ground_set",          -- set: the remaining six terrains, one generator each
  "transitions",         -- set: 7 pairs x 15 corner masks
  -- decals: transparent overlays, so detail is placed and not printed
  "decals",              -- set: the decal families
  -- natural
  "vegetation",          -- set: bushes, scrub, weeds, trees, stumps, logs          -- set: bushes, scrub, weeds, trees, stumps, logs
  "rocks",               -- set: rocks by scale, and clusters               -- set: rocks by scale, and clusters
  -- structure
  "concrete_ruin_wall",
  "rusted_fence",
  "walls",               -- set: the modular ruined-wall kit               -- set: the modular ruined-wall kit
  "fences",              -- set: the modular fence/barrier kit              -- set: the modular fence/barrier kit
  -- infrastructure
  "road_kit",            -- set: barriers, signs, poles, lamps, cabinets, pipes            -- set: barriers, signs, poles, lamps, cabinets, pipes
  "rubble",              -- set: debris and destruction              -- set: debris and destruction
  -- props
  "supply_crate",
  "rusted_barrel",
  "props",               -- set: the survival-world prop library               -- set: the survival-world prop library
}

generators.names = {}
generators.by_category = {}

local function add(gen, module_name)
  assert(type(gen) == "table" and gen.name and gen.build,
    ("module '%s' returned something that is not a generator"):format(module_name))
  assert(not generators[gen.name],
    ("duplicate generator name '%s' (from '%s')"):format(gen.name, module_name))
  assert(style.is_surface[gen.surface],
    ("generator '%s' declares unknown surface '%s'"):format(gen.name, tostring(gen.surface)))
  local ok, err = style.check_size(gen.size.w, gen.size.h)
  assert(ok, ("generator '%s': %s"):format(gen.name, tostring(err)))
  gen.category = gen.category or gen.surface
  local defaults = style.categories[gen.category]
  assert(defaults, ("generator '%s' declares unknown category '%s'")
    :format(gen.name, tostring(gen.category)))
  gen.layer = gen.layer or defaults.layer
  gen.collision = gen.collision or defaults.collision
  gen.variants = gen.variants or 8
  gen.variant_group = gen.variant_group or gen.name
  gen.module = module_name
  generators[gen.name] = gen
  generators.names[#generators.names + 1] = gen.name
  local bucket = generators.by_category[gen.category] or {}
  bucket[#bucket + 1] = gen.name
  generators.by_category[gen.category] = bucket
end

for _, module_name in ipairs(generators.modules) do
  local loaded = require("generators." .. module_name)
  if loaded.name and loaded.build then
    assert(loaded.name == module_name,
      ("generator '%s' reports name '%s'"):format(module_name, tostring(loaded.name)))
    add(loaded, module_name)
  else
    assert(#loaded > 0, ("module '%s' returned an empty set"):format(module_name))
    for _, gen in ipairs(loaded) do add(gen, module_name) end
  end
end

function generators.get(name)
  return generators[name] or error("unknown generator '" .. tostring(name) .. "'", 2)
end

--- Build one asset. The rng stream is salted with the generator name, so two
--- generators given the same seed do not share a random sequence.
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
    wrap = gen.tileable, surface = gen.surface, category = gen.category,
    terrain = gen.terrain, sockets = gen.sockets,
    max_interior_holes = gen.max_interior_holes,
  }
end

--- Every generator in a category, in registration order.
function generators.in_category(category)
  return generators.by_category[category] or {}
end

return generators
