-- materials/earth.lua -- bare soil: the default ground of the surface world.
--
-- Grammar: a flat base, one broad very-low-contrast tone patch, the shrinkage
-- crust of dried compacted dirt (`crust`), and small stones (`stones`, always
-- a lit cap with its own shadow, never a lone dot).
--
-- Calibrated against the game's own authored ground: its platform field tiles
-- are 74-82% ONE colour, carry their detail as hairline marks, and measure
-- 0.10-0.17 edge density. That is what "calm enough to stand a hundred of them
-- under the player" actually looks like, and it rules out the obvious approach
-- of mottling the tile with patches a full ramp step away from the base --
-- earth's ramp steps are ~19 luminance apart, so ANY solid patch of one reads
-- as a discrete mark however large it is drawn. A hundred discrete marks laid
-- out on a 16px pitch is pepper, and enlarging them only turns pepper into
-- leopard spots.
--
-- So the tone patch stays inside a few luminance of the base (straw_2 is +5:
-- sun-bleached dust and old growth trodden into the soil) and the form the eye
-- actually reads is the crust -- one intentional structure per tile, hairline,
-- and absent altogether on many of them.
--
-- Nothing here may key to a tile edge: ground tiles are laid in fields and any
-- edge-anchored mark turns into a visible 16px grid.

local P = require("pixel_utils")
local palette = require("palette")

local earth = { name = "earth", kind = "base", ramp = "earth", base = "earth_3" }

--- opts.wear (0..1) how churned the ground is; opts.base ramp step;
--- opts.dust the near-value neighbour the tone patch is drawn in;
--- opts.drift how much of the area that patch covers (0..1).
function earth.fill(surface, rng_stream, opts)
  opts = opts or {}
  local area = P.area(surface, opts.area)
  local mask = P.mask(surface, opts)
  local base = palette.resolve(opts.base or earth.base)
  local drift = opts.drift or 0.20
  local field = area.w * area.h

  P.rect_fill(surface, area.x, area.y, area.w, area.h, base, { mask = mask })

  -- Dust and bleached dead growth trodden into the soil. Drawn LARGE and
  -- lobed, and only a few luminance steps off the base, so it breaks the
  -- flatness without becoming something the eye counts. Its coverage barely
  -- varies from seed to seed, which is what holds the per-tile mean luminance
  -- steady -- tiles that differ in overall brightness lay a field out as a
  -- chequerboard of light and dark cells, however good each cell is alone.
  local dust = rng_stream:branch("earth_dust")
  P.cluster(surface,
    dust:range(area.x, area.x + area.w - 1), dust:range(area.y, area.y + area.h - 1),
    dust:range(math.floor(field * math.max(0, drift - 0.04)),
               math.floor(field * (drift + 0.04))),
    palette.resolve(opts.dust or "straw_2"), dust, { mask = mask, spread = 1.0 })
end

--- The shrinkage crust of dried compacted dirt: one hairline fracture with a
--- branch or two. This is the tile's form -- the one thing on it the eye is
--- meant to read -- so it is a single connected structure per tile and the
--- generator leaves it off many of them entirely.
function earth.crust(surface, rng_stream, opts)
  opts = opts or {}
  local area = P.area(surface, opts.area)
  local mask = P.mask(surface, opts)
  local wear = opts.wear or 0.5
  return P.fracture(surface,
    rng_stream:range(area.x, area.x + area.w - 1),
    rng_stream:range(area.y, area.y + area.h - 1),
    opts.length or rng_stream:range(6 + math.floor(6 * wear), 10 + math.floor(6 * wear)),
    palette.resolve(opts.color or "earth_2"), rng_stream,
    { mask = mask, branches = wear > 0.6 and 2 or 1, segment = { 3, 5 } })
end

--- Stones. A stone is a lit cap plus its own shadow, which is what separates a
--- stone from a stray pixel at this size.
function earth.stones(surface, count, rng_stream, opts)
  opts = opts or {}
  local area = P.area(surface, opts.area)
  local mask = P.mask(surface, opts)
  local cap = palette.resolve(opts.color or "concrete_4")
  for _ = 1, count do
    local x = rng_stream:range(area.x, area.x + area.w - 1)
    local y = rng_stream:range(area.y, area.y + area.h - 1)
    local wide = rng_stream:chance(0.5)
    P.pixel(surface, x, y, cap, mask)
    P.pixel(surface, x + (wide and 1 or 0), y + (wide and 0 or 1), palette.shift(cap, -1), mask)
    -- cast shadow down-right, per the fixed key light
    P.pixel(surface, x + 1, y + 1, palette.resolve(opts.shadow or "earth_2"), mask)
  end
end

return earth
