-- palette.lua -- the fixed palette for No Way Up, organised as lighting ramps.
--
-- Two halves, one palette:
--
-- * The MAN-MADE ramps (ink, concrete, metal, rust, wood, dirt) were sampled
--   from the shipped metro atlases in ../no-way-up/assets/tiles/metro. They are
--   unchanged, because concrete, steel and corrosion look the same whether they
--   are underground or standing in a field.
-- * The ABOVE-GROUND ramps (earth, grass, straw, asphalt) were quantised from
--   the project's own outdoor reference art, then desaturated a step: the world
--   is a neglected post-Soviet landscape, not a meadow. Green tops out at
--   luminance ~121 and is always olive; the brightest thing in the palette is
--   dead straw, not foliage.
--
-- Generators never invent colours: they name a ramp step, and the lighting
-- helpers move up and down that ramp. That is what makes separate assets look
-- like one hand.
--
-- Colours are stored packed the way Aseprite packs them: r | g<<8 | b<<16 | a<<24.

local palette = {}

palette.TRANSPARENT = 0

local function pack(r, g, b, a)
  return (r & 0xFF) | ((g & 0xFF) << 8) | ((b & 0xFF) << 16) | ((a & 0xFF) << 24)
end

local function unpack_rgba(c)
  return c & 0xFF, (c >> 8) & 0xFF, (c >> 16) & 0xFF, (c >> 24) & 0xFF
end

palette.pack = pack
palette.unpack = unpack_rgba

-- Ramps, dark -> light. Index 1 is the deepest shadow step. ------------------
palette.ramps = {
  -- Voids, holes, outlines. Sampled from Walls.png / LowerGround.png.
  ink      = { 0x000000, 0x0D0D0D, 0x181818, 0x202020 },
  -- Platform concrete. #5C5552 is the single most common colour in the game.
  -- concrete_6 is the daylight step: outdoors a ruin catches more light than
  -- anything ever did on a platform. Kept near-neutral -- a warmer light step
  -- reads mauve against the yellow-brown ground and pulls the eye off the
  -- silhouettes in front of it.
  concrete = { 0x1C1A1A, 0x282524, 0x494542, 0x5C5552, 0x706660, 0x82817B },
  -- Structural steel, panels, props. Skews dark to match the metro walls.
  metal    = { 0x0F0F0F, 0x1B1B1A, 0x30312D, 0x41423E, 0x555653, 0x696666 },
  -- Rail / corrosion ochre. rust_1 is derived (a dark step the atlases lack).
  rust     = { 0x5A431B --[[derived]], 0x795B25, 0xA07629, 0xB18736, 0xCB9B3E },
  -- Sleepers, crates, debris. wood_5 is derived.
  wood     = { 0x27241F, 0x342F27, 0x463D33, 0x726753, 0x8A7B63 --[[derived]] },
  -- Grime overlay. Warm, always darker than what it sits on.
  dirt     = { 0x1F1C1A, 0x2B2821, 0x3D382F },

  -- Above ground ------------------------------------------------------------
  -- Bare soil, ruts, spoil heaps. Warm but greyed: this is dry compacted dirt.
  earth    = { 0x2A2119, 0x3E3226, 0x55452F, 0x6E5A3E, 0x8A7350 },
  -- Living-but-neglected vegetation. Olive, never emerald; the lightest step
  -- is the top of a tuft catching the sun, not a colour to fill an area with.
  grass    = { 0x232B16, 0x33401D, 0x445524, 0x5A6E31, 0x74883E },
  -- Dead and dry: last year's grass, straw, sun-bleached weed stalks.
  straw    = { 0x423521, 0x5C4B2A, 0x7D6839, 0x9E874B },
  -- Road surface: neutral grey, a clear value step darker than the ground it
  -- runs through. Kept off both concrete's warmth and metal's green so a road,
  -- a ruin and a fence never merge into one another.
  asphalt  = { 0x1C1C1D, 0x2A2A2B, 0x3C3C3B, 0x4E4E4C, 0x646460 },
}

-- Ramp order fixes the exported Aseprite palette order; keep it stable.
palette.ramp_order = {
  "ink", "concrete", "metal", "rust", "wood", "dirt",     -- man-made
  "earth", "grass", "straw", "asphalt",                   -- above ground
}

palette.by_name = {}   -- "concrete_4" -> packed
palette.names = {}     -- ordered list of names
palette.name_of = {}   -- packed -> "concrete_4"
palette.index_of = {}  -- packed -> { ramp = "concrete", index = 4 }
palette.set = {}       -- packed -> true (membership test)

for _, ramp_name in ipairs(palette.ramp_order) do
  local ramp = palette.ramps[ramp_name]
  local packed_ramp = {}
  for i, hex in ipairs(ramp) do
    local c = pack((hex >> 16) & 0xFF, (hex >> 8) & 0xFF, hex & 0xFF, 255)
    local name = ("%s_%d"):format(ramp_name, i)
    assert(palette.name_of[c] == nil,
      ("duplicate palette colour #%06X (%s and %s)"):format(hex, name, tostring(palette.name_of[c])))
    palette.by_name[name] = c
    palette.name_of[c] = name
    palette.index_of[c] = { ramp = ramp_name, index = i }
    palette.set[c] = true
    palette.names[#palette.names + 1] = name
    packed_ramp[i] = c
  end
  palette.ramps[ramp_name] = packed_ramp -- replace hex list with packed list
end

palette.size = #palette.names

--- Resolve a colour argument: a ramp-step name, a packed value, or nil.
-- Passing an unknown name is a hard error: an off-palette colour must never
-- reach a surface in the first place.
function palette.resolve(color)
  if color == nil then return palette.TRANSPARENT end
  if type(color) == "number" then
    if color == palette.TRANSPARENT or palette.set[color] then return color end
    error(("colour %08X is not in the palette"):format(color), 2)
  end
  local c = palette.by_name[color]
  if not c then error(("unknown palette name '%s'"):format(tostring(color)), 2) end
  return c
end

--- Move `delta` steps along the ramp a colour belongs to, clamped at the ends.
-- Positive = lighter. Transparent and unknown colours are returned untouched.
function palette.shift(color, delta)
  local c = palette.resolve(color)
  local slot = palette.index_of[c]
  if not slot or delta == 0 then return c end
  local ramp = palette.ramps[slot.ramp]
  local i = math.max(1, math.min(#ramp, slot.index + delta))
  return ramp[i]
end

--- Step name/packed -> ramp name, index (nil for transparent).
function palette.slot(color)
  local slot = palette.index_of[palette.resolve(color)]
  if not slot then return nil end
  return slot.ramp, slot.index
end

--- A ramp step by ramp name and 1-based index, clamped.
function palette.step(ramp_name, index)
  local ramp = palette.ramps[ramp_name] or error("unknown ramp " .. tostring(ramp_name), 2)
  return ramp[math.max(1, math.min(#ramp, index))]
end

function palette.is_valid(packed)
  return packed == palette.TRANSPARENT or palette.set[packed] == true
end

--- Perceived luminance 0..255. Used wherever the toolkit has to reason about
--- contrast rather than colour: lighting checks, grid-visibility measurement.
function palette.luminance(color)
  local r, g, b = unpack_rgba(palette.resolve(color))
  return 0.299 * r + 0.587 * g + 0.114 * b
end

function palette.hex(color)
  local r, g, b = unpack_rgba(palette.resolve(color))
  return ("#%02X%02X%02X"):format(r, g, b)
end

--- Ordered { name, packed, r, g, b } records, for exporting to Aseprite.
function palette.entries()
  local out = {}
  for i, name in ipairs(palette.names) do
    local c = palette.by_name[name]
    local r, g, b = unpack_rgba(c)
    out[i] = { name = name, color = c, r = r, g = g, b = b }
  end
  return out
end

return palette
