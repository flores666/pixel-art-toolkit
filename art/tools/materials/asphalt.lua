-- materials/asphalt.lua -- road surface, and what twenty unmaintained years
-- do to it.
--
-- Grammar: a dark base with broad worn and tar-sealed patches, `crack` (a
-- fracture, not a scratch), `breakup` (the surface crumbled away along a
-- fracture) and `pothole` (a breakup deep enough to have filled with soil).
--
-- What makes a tile read as DAMAGED ASPHALT rather than as grey noisy ground
-- is the relationship between those: cracks run in straight segments and kink
-- at a joint, the surface has crumbled beside them, and everywhere else the
-- road is intact. Scattered exposed grains do the opposite -- they make the
-- whole surface equally busy, so nothing reads as damage because nothing reads
-- as whole. There is deliberately no aggregate speckle in this material.
--
-- Depressions -- a breakup, a pothole -- are lit as depressions: dark floor,
-- and the lit lip on the lower-right inner wall, the wall the key light
-- reaches.

local P = require("pixel_utils")
local palette = require("palette")

local asphalt = { name = "asphalt", kind = "base", ramp = "asphalt", base = "asphalt_3" }

function asphalt.fill(surface, rng_stream, opts)
  opts = opts or {}
  local area = P.area(surface, opts.area)
  local mask = P.mask(surface, opts)
  local base = palette.resolve(opts.base or asphalt.base)
  local field = area.w * area.h

  P.rect_fill(surface, area.x, area.y, area.w, area.h, base, { mask = mask })

  -- ONE broad patch of ground-in dust and grime over the intact surface, and
  -- it is deliberately NOT a step along the asphalt ramp. asphalt_3 to
  -- asphalt_2 is 18 luminance -- on a road that dark it is a third of the
  -- base's brightness, so any solid patch of it reads as a discrete blob
  -- however large it is drawn, and a hundred tiles of those is the grey noise
  -- this material was rebuilt to get rid of. metal_4 sits 6 luminance over
  -- asphalt_3 and is just as neutral, so a broad patch of it reads as a
  -- different asphalt mix -- an old repair -- rather than as a mark.
  --
  -- Near in VALUE is not enough: it has to be near in HUE too. dirt_3 is only
  -- 3 luminance off asphalt_3 and was tried here first; being warm brown
  -- against neutral grey it turned the road visibly brown-mottled, the same
  -- way an equal-luminance olive patch turned the grass field into camouflage.
  --
  -- The rule that falls out of this, and it holds for every ground tile in the
  -- set: the intact surface gets ONE patch that is near in both value and hue,
  -- and ALL value contrast is reserved for structure and damage. That is what
  -- leaves a fracture room to read as a fracture.
  local grime = rng_stream:branch("asphalt_seal")
  P.cluster(surface,
    grime:range(area.x, area.x + area.w - 1), grime:range(area.y, area.y + area.h - 1),
    grime:range(math.floor(field * 0.16), math.floor(field * 0.24)),
    palette.resolve(opts.grime or "metal_4"), grime, { mask = mask, spread = 1.1 })

  -- `ruin` (0..1): comprehensively degraded tarmac -- the CONDITION of a road
  -- that has failed, not the individual holes in it.
  --
  -- That division took three attempts to see. A tile wraps against ITSELF, so
  -- its left edge has nothing to do with its neighbour's, and ART_STYLE.md 2
  -- states the consequence plainly: a broad continuous form cannot cross a
  -- tile boundary, so the only things that survive repetition are texture too
  -- quiet to count and marks that read as objects. Anything else laid a
  -- hundred times becomes a pattern at the tile pitch.
  --
  --   * many small break-outs per tile -> uniform grey static (field 0.234,
  --     over the ceiling, and nothing on it read as damage because nothing
  --     was left whole);
  --   * one LARGE break-out per tile -> leopard spots on a 16px pitch, which
  --     is the failure mode ART_STYLE.md 2 names in as many words. It
  --     measured fine (0.196) and looked worse.
  --
  -- So the terrain carries the condition and nothing else: a dense network of
  -- hairline fracturing and low-contrast patching, quiet enough to tile a
  -- hundred times. The HOLES are `decal_pothole` and `decal_rubble`, placed
  -- where the level wants them -- which is the same split that made the
  -- ordinary field tiles work, applied to the extreme end of the same road.
  local ruin = opts.ruin or 0
  if ruin > 0 then
    local fail = rng_stream:branch("asphalt_ruin")
    -- Fracturing over the whole tile: this is the read. It has to be QUIET,
    -- and the asphalt ramp cannot do quiet -- its steps are 18 luminance
    -- apart, so a network drawn one step down is a web of hard black lines
    -- and a field of it measured 0.285 against the 0.22 ceiling.
    --
    -- metal_3 sits 11 luminance under asphalt_3 and is just as neutral, so
    -- the same network reads as crazing in the surface rather than as drawn
    -- lines. This is the near-value-neighbour rule of ART_STYLE.md 2 applied
    -- to a structure instead of to a fill: value contrast is reserved for
    -- damage, and comprehensive crazing is a CONDITION, not damage.
    -- One or two per tile, not five. At five the field measured 0.253 against
    -- the 0.22 ceiling; at two, 0.224 -- still over, and with no headroom for
    -- a seed the sweep did not try. At one-plus-ruin it lands at 0.184, which
    -- leaves room, and the read does not suffer: the crazing on any one cell
    -- was never the point, the accumulation across the field is, and adjacent
    -- cells supply that for free.
    local crazing = palette.resolve(opts.crazing or "metal_3")
    for _ = 1, 1 + math.floor(ruin * 1.0) do
      P.fracture(surface,
        fail:range(area.x, area.x + area.w - 1), fail:range(area.y, area.y + area.h - 1),
        fail:range(6, 11), crazing, fail,
        { mask = mask, branches = 1, segment = { 3, 5 }, branch_length = { 3, 5 } })
    end
    -- One patch where the surface has worn thin, in the same near-value
    -- neighbour: at field scale this reads as a road mottled with old repairs
    -- rather than as a mark on every cell.
    P.cluster(surface,
      fail:range(area.x, area.x + area.w - 1), fail:range(area.y, area.y + area.h - 1),
      fail:range(math.floor(field * 0.10), math.floor(field * 0.18)),
      crazing, fail, { mask = mask, spread = 1.3 })
  end
end

--- A crack. A fracture: straight segments, 45-degree kinks, one branch.
--- Returns the pixels it drew, so a generator can crumble the surface beside
--- it or grow weeds out of it.
function asphalt.crack(surface, x, y, length, rng_stream, opts)
  opts = opts or {}
  return P.fracture(surface, x, y, length, opts.color or "asphalt_1", rng_stream, {
    mask = opts.mask,
    heading = opts.heading,
    segment = opts.segment or { 3, 6 },
    branches = opts.branches or 1,
    branch_length = { 3, 5 },
  })
end

--- The surface crumbled away: a compact broken-out area with a dark floor, the
--- lit lip on its lower-right rim, and a little exposed aggregate standing in
--- it. This is the mark that says "asphalt" rather than "grey ground" -- a
--- crack on its own is a line, and a road breaks up in chunks.
--- @return the pixels of the floor
function asphalt.breakup(surface, x, y, size, rng_stream, opts)
  opts = opts or {}
  local mask = opts.mask
  local base = surface:get(x, y)
  if base == palette.TRANSPARENT then base = palette.resolve(asphalt.base) end
  -- Two steps down, not one: the intact surface already carries a patch one
  -- step down, so a breakup drawn at that value disappears into it. Damage has
  -- to be the darkest thing on the road, with the lit lip beside it, or the
  -- tile is just mottled grey.
  local floor_color = palette.resolve(opts.color or palette.shift(base, -2))
  -- Lobed rather than round: a chunk comes out of a road along the cracks
  -- around it, so the shape is ragged. (A stepped inner wall was tried here and
  -- removed: at five to nine pixels almost every pixel of the blob is on its
  -- rim, so stepping the rim back up simply repaints the floor away.)
  local blob = P.cluster(surface, x, y, size, floor_color, rng_stream,
    { mask = mask, spread = 0.6 })

  -- the lower-right rim is the wall the light reaches
  local low
  for _, p in ipairs(blob) do
    if not low or p[2] > low[2] or (p[2] == low[2] and p[1] > low[1]) then low = p end
  end
  if low then
    local lip = palette.resolve(opts.lip or palette.shift(base, 1))
    P.pixel(surface, low[1], low[2], lip, mask)
    P.pixel(surface, low[1] - 1, low[2], lip, mask)
  end
  -- aggregate left standing in the hollow, as a pair and never as one grain
  if #blob >= 5 then
    local g = blob[rng_stream:range(2, #blob - 1)]
    local agg = palette.resolve(opts.aggregate or palette.shift(base, 1))
    P.pixel(surface, g[1], g[2], agg, mask)
    P.pixel(surface, g[1] + 1, g[2], agg, mask)
  end
  return blob
end

--- A pothole: a breakup deep enough to have gone through, with soil washed
--- into the bottom of it.
function asphalt.pothole(surface, x, y, size, rng_stream, opts)
  opts = opts or {}
  local blob = asphalt.breakup(surface, x, y, size, rng_stream, {
    mask = opts.mask,
    color = opts.color or "asphalt_1",
    lip = opts.lip or "asphalt_4",
  })
  for _, p in ipairs(blob) do
    if rng_stream:chance(0.35) then P.pixel(surface, p[1], p[2], "earth_2", opts.mask) end
  end
  return blob
end

return asphalt
