-- materials/grass.lua -- dry, neglected vegetation.
--
-- This is not a lawn. The field is last year's dead straw with olive tufts
-- pushing through it and bare soil showing where nothing took. Green is used
-- sparingly and never above grass_5; the brightest pixels in a grass tile are
-- dry straw catching the light, which is what keeps the world reading as
-- abandoned rather than pastoral.
--
-- Grammar: a straw field with one broad low-contrast patch of the soil beneath
-- it, tufts (leaning stalks with a lit tip) and blades (a single dead stem).
-- `tufts` doubles as the overlay entry point for vegetation coming through
-- asphalt or rubble.
--
-- Why vegetation is drawn as VALUE and not as colour: grass_3 measures 74 in
-- luminance and straw_2 measures 76. Olive marks on a straw field are
-- therefore a pure hue change at constant value -- which is precisely what
-- camouflage is, and precisely what the first drafts of this material looked
-- like. A tuft only reads as a tuft if it has light on it: a body a step
-- DARKER than the field it stands in and a tip a step or two LIGHTER. Get that
-- wrong and no amount of adjusting the count will help.

local P = require("pixel_utils")
local palette = require("palette")

local grass = { name = "grass", kind = "base", ramp = "straw", base = "straw_2" }

--- A dry field. opts.green (0..1) how much has come back this year,
--- opts.bare (0..1) how much soil shows through.
function grass.fill(surface, rng_stream, opts)
  opts = opts or {}
  local area = P.area(surface, opts.area)
  local mask = P.mask(surface, opts)
  local base = palette.resolve(opts.base or grass.base)
  local green = opts.green or 0.5
  local bare = opts.bare or 0.3
  local field = area.w * area.h

  P.rect_fill(surface, area.x, area.y, area.w, area.h, base, { mask = mask })

  -- The soil under the mat, where the dead growth is thin. Broad, lobed, and
  -- only five luminance off the base (earth_3 against straw_2), so it varies
  -- the field without the eye counting it as a mark. Calibrated on the game's
  -- own ground tiles, which hold 74-82% of their area at ONE colour.
  local thin = rng_stream:branch("grass_thin")
  P.cluster(surface,
    thin:range(area.x, area.x + area.w - 1), thin:range(area.y, area.y + area.h - 1),
    thin:range(math.floor(field * 0.14), math.floor(field * 0.20)),
    "earth_3", thin, { mask = mask, spread = 1.0 })

  -- Matted, shadowed dead growth: one small darker drift. Straw, not olive.
  -- Green is spent ONLY on tufts, and only on some of them (below). A broad
  -- patch of grass_3 is a tempting way to say "this came back this year" --
  -- it sits two luminance off straw_2, so it costs nothing in value and
  -- nothing in tile-brightness spread -- but equal luminance is not the same
  -- as equal weight: at constant value a hue that far from the base reads as a
  -- loud colour patch, which is what camouflage IS. It turns the field
  -- green-and-brown mottled, exactly the read this rebuild exists to kill.
  local mat = rng_stream:branch("grass_mat")
  P.cluster(surface,
    mat:range(area.x, area.x + area.w - 1), mat:range(area.y, area.y + area.h - 1),
    mat:range(math.floor(field * 0.05), math.floor(field * 0.09)),
    palette.shift(base, -1), mat, { mask = mask, spread = 1.2 })


  -- Standing growth: ONE clump per tile, and not on every tile. Two to four
  -- stalks out of one root, all leaning the same way. Scattering three or four
  -- separate marks across every cell is what produced confetti, and no tuft
  -- however well drawn survives being repeated a hundred times on a 16px pitch.
  local stroke = rng_stream:branch("grass_stroke")
  if stroke:chance(0.80) then
    -- Olive is the minority report: mostly this is bleached dead straw.
    local olive = stroke:float() < green * 0.5
    local x = stroke:range(area.x, area.x + area.w - 1)
    local y = stroke:range(area.y, area.y + area.h - 1)
    local lean = stroke:chance(0.5) and 1 or -1
    -- Sometimes a second tuft right beside the first, leaning the same way, so
    -- the clump reads as a bank of growth rather than as one lonely plant.
    -- This -- and not a scatter of separate marks -- is how the tile carries
    -- more vegetation without turning back into confetti.
    for i = 1, stroke:chance(0.25) and 2 or 1 do
      grass.tufts(surface, 1, stroke, {
        area = area, mask = opts.mask, lean = lean,
        at = { x + (i - 1) * stroke:range(3, 4), y + stroke:range(-1, 1) },
        color = olive and "grass_2" or "straw_1",
      })
    end
  end
  -- `bare` says how often the soil wins outright. This is the one patch in the
  -- tile a full value step from the base, so it stays small and occasional.
  if bare > 0 and rng_stream:chance(bare) then
    local soil = rng_stream:branch("grass_bare")
    P.cluster(surface,
      soil:range(area.x, area.x + area.w - 1), soil:range(area.y, area.y + area.h - 1),
      soil:range(math.floor(field * 0.04), math.floor(field * 0.07)),
      "earth_2", soil, { mask = mask, spread = 1.0 })
  end
end

--- A tuft: two to four stalks rising from one root, ALL LEANING THE SAME WAY,
--- the tallest catching the light at its tip. This is the overlay entry point
--- too -- use it to push weeds through a crack in asphalt or up a ruin.
--- opts.lean forces the direction, so a caller can lay a whole bank of tufts
--- over the way the wind left them.
function grass.tufts(surface, count, rng_stream, opts)
  opts = opts or {}
  local area = P.area(surface, opts.area)
  local mask = P.mask(surface, opts)
  local body = palette.resolve(opts.color or "straw_1")
  local crown = palette.resolve(opts.crown or palette.shift(body, 2))
  for _ = 1, count do
    local x = opts.at and opts.at[1] or rng_stream:range(area.x, area.x + area.w - 1)
    local y = opts.at and opts.at[2] or rng_stream:range(area.y, area.y + area.h - 1)
    local lean = opts.lean or (rng_stream:chance(0.5) and 1 or -1)
    local stalks = rng_stream:range(2, 3)
    local tip_x, tip_y
    for i = 1, stalks do
      -- Stalks are spaced two apart, not packed side by side. Adjacent bases
      -- plus a shared lean make the stalks overlap into a solid dark rectangle
      -- -- a blob, which is the opposite of the read wanted here. At a spacing
      -- of two they stay parallel and separate, and the tuft reads as strokes.
      local sx = x + (i - 1) * 2 - (stalks - 1)
      local len = rng_stream:range(3, 5)
      local px = sx
      for k = 0, len - 1 do
        P.pixel(surface, px, y - k, body, mask)
        -- the lean is applied steadily, not re-rolled per pixel: a stalk that
        -- wanders is a scribble, a stalk that leans is a stalk
        if k > 0 and k % 2 == 0 then px = px + lean end
      end
      if not tip_y or y - (len - 1) < tip_y then tip_x, tip_y = px, y - (len - 1) end
    end
    -- the tip takes the light, per the fixed upper-left key
    P.pixel(surface, tip_x, tip_y, crown, mask)
  end
end

--- A single dead stem: a short run with a bleached tip. Always 2+ pixels, and
--- built out of the same value structure as a tuft.
function grass.blade(surface, x, y, length, rng_stream, opts)
  opts = opts or {}
  local mask = opts.mask
  local color = palette.resolve(opts.color or "straw_1")
  local lean = opts.lean or (rng_stream:chance(0.5) and 1 or -1)
  length = math.max(2, length)
  local px = x
  for i = 0, length - 1 do
    P.pixel(surface, px, y - i, color, mask)
    if i > 0 and i % 2 == 0 then px = px + lean end
  end
  P.pixel(surface, px, y - length + 1, palette.shift(color, 2), mask)
end

return grass
