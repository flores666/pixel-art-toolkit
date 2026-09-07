-- materials/init.lua -- the material registry and the material contract.
--
-- A material is the *grammar* of a surface: the vocabulary of marks that
-- material is allowed to make. Generators compose materials; they do not
-- invent texture themselves. That is what keeps a wall generated next year
-- consistent with a road generated today.
--
-- Contract -- every module in this folder returns:
--   name    string
--   kind    "base"    fills a region with its own texture, or
--           "overlay" adds wear on top of whatever is already there
--   ramp    palette ramp name it draws from
--   base    default ramp step a base material fills with (base materials only)
--   fill(surface, rng_stream, opts)
--           opts.area  { x, y, w, h }          defaults to the whole surface
--           opts.mask  function(x, y, colour)  extra restriction (object bodies)
--           plus the material's own documented knobs
--   ...     extra grammar functions (grooves, rivets, knots) used by generators
--
-- Materials must be pure: same surface + same rng stream = same pixels.

local materials = {}

materials.names = {
  -- man-made
  "concrete", "metal", "wood", "rust", "dirt",
  -- above ground
  "earth", "grass", "asphalt", "debris",
}

for _, name in ipairs(materials.names) do
  materials[name] = require("materials." .. name)
end

function materials.get(name)
  return materials[name] or error("unknown material '" .. tostring(name) .. "'", 2)
end

return materials
