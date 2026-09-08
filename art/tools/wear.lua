-- wear.lua -- the shared variation controls.
--
-- Every asset in the library varies by seed, and it must vary in the same
-- WAYS: a rusted fence and a rusted locker have to look corroded by the same
-- process, or the set stops looking like one hand. So the channels live here
-- rather than in each generator, and a generator declares which of them apply
-- and how hard.
--
--   rust        corrosion, spreading from nuclei, on a named ramp
--   dirt        grime, collecting low and in corners
--   staining    broad discolouration, no highlight (it is IN the surface)
--   cracks      fracturing of a hard surface
--   damage      dents and spalls: the surface pushed in or broken off
--   missing     pieces gone altogether -- holes through the asset
--   rubble      what fell off, lying at the foot
--   vegetation  what has taken root in it
--
-- Two rules are enforced here rather than trusted to each caller:
--
--   * COVERAGE MAY ROUND TO NOTHING. Each channel takes a weighted list whose
--     first entry is conventionally 0, so clean variants genuinely occur. A
--     channel that always fires makes every variant equally worn, and a row of
--     uniformly rusted lockers reads as a texture rather than as a row of
--     lockers (ART_STYLE.md 10).
--   * STRUCTURAL IDENTITY IS NOT A WEAR CHANNEL. Nothing here moves an edge,
--     changes a size or redraws a silhouette. That is what keeps a variant
--     recognisably the same object (ART_STYLE.md 11), and it is what the
--     variant_similarity validator measures from the other side.
--
-- Each channel is a no-op when its spec is absent, so a generator lists only
-- what can actually happen to the thing it draws. A concrete block does not
-- rust and a steel post does not sprout weeds.

local P = require("pixel_utils")
local palette = require("palette")
local materials = require("materials")

local wear = {}

--- Resolve a channel's strength. A number is used as-is; a list is a weighted
--- pick, which is how "most variants are clean" gets expressed.
local function strength(spec, rng_stream)
  if spec == nil then return nil end
  if type(spec) == "number" then return spec end
  if spec.coverage then return strength(spec.coverage, rng_stream) end
  return rng_stream:weighted(spec)
end

--- Common bias functions, so "wear collects low" is written once.
-- A bias returns 0..1 and says where a channel is ALLOWED to land; evenly
-- spread wear is the tell-tale of generated art (ART_STYLE.md 10).
wear.bias = {
  --- Low down, where water sits and dirt splashes up.
  low = function(_, y, h) return y >= (h or 16) - 5 and 1.0 or 0.2 end,
  --- At the foot only.
  foot = function(_, y, h) return y >= (h or 16) - 3 and 1.0 or 0.05 end,
  --- Along a named row (a rail, a joint) and just under it.
  along = function(row) return function(_, y) return math.abs(y - row) <= 1 and 1.0 or 0.2 end end,
  --- Everywhere, for a subject whose whole point is corrosion.
  all = function() return 1.0 end,
}

--- Bind a bias to a surface height so a caller can pass `wear.bias.low`
--- without knowing the signature.
local function bound(bias, h)
  if not bias then return nil end
  return function(x, y) return bias(x, y, h) end
end

--- Apply every declared channel, in the ART_STYLE.md 9 order: damage and
--- missing pieces are structure and go first, then the overlays, then what
--- fell off and what grew.
-- @param spec table of channel specs, plus:
--   ramp   the palette ramp the body is made of; overlays are masked to it so
--          wear never lands on the outline, a hole or a weed
--   area   restrict everything to a sub-rectangle
-- @param spec.constrain optional predicate every channel must respect, on top
--   of its own ramp mask. object.finish passes the JOIN BORDER mask here, and
--   that is not cosmetic: a modular piece's connecting edge has to present the
--   canonical profile, and a channel that paints onto transparency -- the
--   vegetation channel does, since a weed grows out of nothing -- can drop a
--   tuft on a border pixel where the neighbouring piece has empty sky. The
--   socket validator catches it, and this is the fix.
function wear.apply(surface, rng_stream, spec)
  spec = spec or {}
  local h = surface.height
  local ramp_mask = spec.ramp and P.ramp_mask(spec.ramp) or nil
  if spec.constrain then
    local ramp_only = ramp_mask
    ramp_mask = function(x, y, c)
      if not spec.constrain(x, y, c) then return false end
      return not ramp_only or ramp_only(x, y, c)
    end
  end
  local area = spec.area

  -- structure first ---------------------------------------------------------
  local dents = strength(spec.damage, rng_stream:branch("wear_damage"))
  if dents and dents > 0 then
    local r = rng_stream:branch("damage")
    local a = P.area(surface, area)
    for _ = 1, math.max(1, math.floor(dents * 3)) do
      local x = r:range(a.x, a.x + a.w - 1)
      local y = r:range(a.y, a.y + a.h - 1)
      local w = r:range(2, 3)
      -- A dent is a recess, so it is lit as one: pushed-in face dark, the lit
      -- lip on the lower-right inner wall (ART_STYLE.md 5).
      P.rect_fill_shift(surface, x, y, w, 2, -1, { mask = ramp_mask })
      P.rect_fill_shift(surface, x, y + 2, w, 1, 1, { mask = ramp_mask })
    end
  end

  local gone = strength(spec.missing, rng_stream:branch("wear_missing"))
  if gone and gone > 0 then
    local r = rng_stream:branch("missing")
    local a = P.area(surface, area)
    -- A hole through the asset, with the torn edge lit on its upper-left rim.
    -- One, and only where there is body to lose.
    local x = r:range(a.x + 1, a.x + a.w - 2)
    local y = r:range(a.y + 1, a.y + a.h - 2)
    local blob = P.cluster(surface, x, y, math.floor(3 + gone * 6),
      palette.resolve(spec.tear or "rust_1"), r, { mask = ramp_mask, spread = 0.5 })
    for _, p in ipairs(blob) do surface:set(p[1], p[2], palette.TRANSPARENT) end
    for _, p in ipairs(blob) do
      local above = surface:get(p[1], p[2] - 1)
      if above ~= palette.TRANSPARENT then
        surface:set(p[1], p[2] - 1, palette.resolve(spec.tear or "rust_2"))
      end
    end
  end

  local cracks = strength(spec.cracks, rng_stream:branch("wear_cracks"))
  if cracks and cracks > 0 then
    local r = rng_stream:branch("cracks")
    local a = P.area(surface, area)
    for _ = 1, math.max(1, math.floor(cracks * 2)) do
      materials.concrete.crack(surface,
        r:range(a.x, a.x + a.w - 1), r:range(a.y, a.y + a.h - 1),
        r:range(4, 8), r, { color = spec.crack_color or "concrete_2",
          mask = ramp_mask, branches = 0 })
    end
  end

  -- overlays ----------------------------------------------------------------
  local rust_coverage = strength(spec.rust, rng_stream:branch("wear_rust"))
  if rust_coverage and rust_coverage > 0 then
    materials.rust.fill(surface, rng_stream:branch("rust"), {
      coverage = rust_coverage, streaks = spec.rust_streaks ~= false,
      mask = ramp_mask, area = area,
      bias = bound(spec.rust_bias or spec.bias or wear.bias.low, h),
    })
  end

  local stain = strength(spec.staining, rng_stream:branch("wear_stain"))
  if stain and stain > 0 then
    local r = rng_stream:branch("stain")
    local a = P.area(surface, area)
    -- Flat: a stain has soaked in, so giving it a lit cap would lift it off
    -- the surface it is in.
    P.cluster(surface,
      r:range(a.x, a.x + a.w - 1), r:range(a.y, a.y + a.h - 1),
      math.floor(a.w * a.h * stain * 0.4), palette.resolve(spec.stain_color or "dirt_2"),
      r, { mask = ramp_mask, spread = 1.2 })
  end

  local grime = strength(spec.dirt, rng_stream:branch("wear_dirt"))
  if grime and grime > 0 then
    materials.dirt.fill(surface, rng_stream:branch("dirt"), {
      coverage = grime, color = "dirt_2", edge = "dirt_2",
      mask = ramp_mask, area = area,
      bias = bound(spec.dirt_bias or spec.bias or wear.bias.foot, h),
    })
  end

  -- what fell off, and what grew --------------------------------------------
  local fell = strength(spec.rubble, rng_stream:branch("wear_rubble"))
  if fell and fell > 0 then
    materials.debris.fill(surface, rng_stream:branch("rubble"), {
      coverage = fell, kinds = spec.rubble_kinds, mask = spec.constrain,
      area = spec.rubble_area or { x = 0, y = h - 3, w = surface.width, h = 3 },
    })
  end

  local grew = strength(spec.vegetation, rng_stream:branch("wear_veg"))
  if grew and grew > 0 then
    local r = rng_stream:branch("veg")
    local a = P.area(surface, spec.vegetation_area or area)
    materials.grass.tufts(surface, 1, r, {
      at = { r:range(a.x, a.x + a.w - 1), r:range(a.y, a.y + a.h - 1) },
      color = r:chance(0.5) and "grass_2" or "straw_1",
      -- vegetation paints onto TRANSPARENCY (that is what growing is), so
      -- unlike the other channels it is not naturally confined by the ramp
      -- mask and needs the constraint applied directly
      mask = spec.constrain,
    })
  end
end

return wear
