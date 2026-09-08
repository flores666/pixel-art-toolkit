-- manifest.lua -- machine-readable metadata for every generated asset.
--
-- The toolkit's output is a directory of PNGs, and a PNG says nothing about
-- what it is for. This module writes the JSON that does: what each asset is,
-- what draws it, which seed, how many cells it occupies, whether it tiles,
-- what it should collide with, which layer it belongs on, which variant group
-- it belongs to, and -- for the autotile pieces -- the terrain pair and corner
-- mask it satisfies.
--
-- That is enough for an importer to build a Godot TileSet without a human
-- deciding anything twice, and enough for a level tool to offer "give me
-- another variant of this" or "what fits next to this piece".
--
-- JSON is written by hand rather than pulled in as a dependency: the schema is
-- fixed and small, and a pure-Lua toolkit that needs no rocks to run is worth
-- more than the twenty lines saved. Values are numbers, strings, booleans and
-- flat arrays only.

local style = require("style")
local generators = require("generators")
local terrain = require("terrain")
local palette = require("palette")

local manifest = {}

-- JSON emitter ---------------------------------------------------------------

local function esc(str)
  return (str:gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"' end
    if c == "\\" then return "\\\\" end
    if c == "\n" then return "\\n" end
    return ("\\u%04X"):format(c:byte())
  end))
end

local encode

local function encode_array(list, indent)
  if #list == 0 then return "[]" end
  local simple = true
  for _, v in ipairs(list) do
    if type(v) == "table" then simple = false break end
  end
  local parts = {}
  for i, v in ipairs(list) do parts[i] = encode(v, indent .. "  ") end
  if simple then return "[" .. table.concat(parts, ", ") .. "]" end
  return "[\n" .. indent .. "  " .. table.concat(parts, ",\n" .. indent .. "  ")
    .. "\n" .. indent .. "]"
end

--- Object keys are emitted in a declared order where one is given, so the file
--- is stable across runs and diffs cleanly -- a manifest that reshuffles on
--- every regeneration is useless in review.
local function encode_object(tbl, indent)
  local keys = tbl.__order
  if not keys then
    keys = {}
    for k in pairs(tbl) do if k ~= "__order" then keys[#keys + 1] = k end end
    table.sort(keys)
  end
  local parts = {}
  for _, k in ipairs(keys) do
    local v = tbl[k]
    if v ~= nil then
      parts[#parts + 1] = ('"%s": %s'):format(esc(k), encode(v, indent .. "  "))
    end
  end
  if #parts == 0 then return "{}" end
  return "{\n" .. indent .. "  " .. table.concat(parts, ",\n" .. indent .. "  ")
    .. "\n" .. indent .. "}"
end

encode = function(v, indent)
  indent = indent or ""
  local t = type(v)
  if v == nil then return "null" end
  if t == "number" then
    if v == math.floor(v) and math.abs(v) < 2 ^ 53 then return ("%d"):format(v) end
    return ("%.4f"):format(v)
  end
  if t == "boolean" then return v and "true" or "false" end
  if t == "string" then return '"' .. esc(v) .. '"' end
  if t == "table" then
    if #v > 0 or next(v) == nil then return encode_array(v, indent) end
    return encode_object(v, indent)
  end
  error("cannot encode " .. t)
end

manifest.encode = encode

-- Asset records --------------------------------------------------------------

local ASSET_ORDER = {
  "id", "generator", "seed", "category", "surface", "title",
  "path", "width", "height", "tiles_x", "tiles_y",
  "tileable", "layer", "collision", "variant_group", "variants",
  "over", "sockets", "terrain",
}

--- Where an asset's PNG goes, relative to the output root. One directory per
--- category, which is what makes the output browsable by a human as well as
--- by an importer.
function manifest.asset_path(gen, seed)
  if gen.category == "transition" then
    -- Transition pieces are not shipped as individual files: 615 generators x
    -- 3 variants is 1,845 PNGs nobody will ever open one at a time, and an
    -- autotile wants a contiguous atlas anyway. They live in the pair atlas
    -- and the manifest records their cell in it.
    return nil
  end
  return ("%s/%s_%d.png"):format(gen.category, gen.name, seed)
end

--- The record for one (generator, seed).
function manifest.asset(gen, seed, extra)
  local rec = {
    __order = ASSET_ORDER,
    id = ("%s_%d"):format(gen.name, seed),
    generator = gen.name,
    seed = seed,
    category = gen.category,
    surface = gen.surface,
    title = gen.title,
    path = manifest.asset_path(gen, seed),
    width = gen.size.w,
    height = gen.size.h,
    tiles_x = gen.size.w // style.tile,
    tiles_y = gen.size.h // style.tile,
    tileable = gen.tileable and true or false,
    layer = gen.layer,
    collision = gen.collision,
    variant_group = gen.variant_group,
    variants = gen.variants,
  }
  if gen.over then
    local over = {}
    for i, t in ipairs(gen.over) do over[i] = t end
    rec.over = over
  end
  if gen.sockets then
    rec.sockets = {
      __order = { "left", "right", "top", "bottom" },
      left = gen.sockets.left, right = gen.sockets.right,
      top = gen.sockets.top, bottom = gen.sockets.bottom,
    }
  end
  if gen.terrain then
    local t = gen.terrain
    rec.terrain = {
      __order = { "pair", "base", "over", "mask", "shape", "worn",
                  "edge_top", "edge_right", "edge_bottom", "edge_left" },
      pair = t.pair, base = t.base, over = t.over, mask = t.mask,
      shape = t.shape, worn = t.worn and true or false,
      edge_top = t.edges.top, edge_right = t.edges.right,
      edge_bottom = t.edges.bottom, edge_left = t.edges.left,
    }
  end
  for k, v in pairs(extra or {}) do rec[k] = v end
  return rec
end

-- Whole-library documents ----------------------------------------------------

--- The palette, so an importer can build the same 48 colours.
function manifest.palette()
  local ramps = {}
  for _, name in ipairs(palette.ramp_order) do
    local steps = {}
    for i, c in ipairs(palette.ramps[name]) do steps[i] = palette.hex(c) end
    ramps[#ramps + 1] = { __order = { "ramp", "steps" }, ramp = name, steps = steps }
  end
  return { __order = { "size", "ramps" }, size = palette.size, ramps = ramps }
end

--- The terrain system: every terrain and every pair, with the corner-mask
--- convention spelled out. This is what an importer needs to build a Godot
--- TileSet terrain set (TERRAIN_MODE_MATCH_CORNERS).
function manifest.terrains()
  local terrains = {}
  for _, name in ipairs(terrain.names) do
    local t = terrain.get(name)
    terrains[#terrains + 1] = {
      __order = { "name", "title", "family", "kin", "base_color", "generator" },
      name = name, title = t.title, family = t.family, kin = t.kin,
      base_color = palette.hex(t.base), generator = t.generator,
    }
  end
  local pairs_out = {}
  for _, id in ipairs(terrain.pair_names) do
    local p = terrain.pair(id)
    pairs_out[#pairs_out + 1] = {
      __order = { "id", "base", "over", "amplitude", "atlas" },
      id = id, base = p.base, over = p.over, amplitude = p.amplitude,
      atlas = ("transitions/%s.png"):format(id),
    }
  end
  local corners = {}
  for i, c in ipairs(terrain.CORNERS) do
    corners[i] = { __order = { "corner", "bit" }, corner = c.name, bit = c.bit }
  end
  return {
    __order = { "corner_mode", "corners", "masks", "pin_width", "terrains", "pairs" },
    corner_mode = "match_corners",
    corners = corners,
    masks = style.terrain.masks,
    pin_width = style.terrain.pin_width,
    terrains = terrains,
    pairs = pairs_out,
  }
end

--- The socket table: which edges of which pieces mate. A level tool can offer
--- "what fits to the right of this" straight from this.
function manifest.sockets()
  local by_socket = {}
  for _, name in ipairs(generators.names) do
    local gen = generators.get(name)
    if gen.sockets then
      for side, socket in pairs(gen.sockets) do
        if socket ~= "open" and socket ~= "ground" then
          by_socket[socket] = by_socket[socket] or {}
          by_socket[socket][#by_socket[socket] + 1] = ("%s.%s"):format(name, side)
        end
      end
    end
  end
  local out = {}
  local names = {}
  for socket in pairs(by_socket) do names[#names + 1] = socket end
  table.sort(names)
  for _, socket in ipairs(names) do
    table.sort(by_socket[socket])
    out[#out + 1] = { __order = { "socket", "edges" },
      socket = socket, edges = by_socket[socket] }
  end
  return out
end

--- Layer and collision vocabularies, so the importer does not have to guess
--- what the strings mean.
function manifest.conventions()
  local cats = {}
  local names = {}
  for name in pairs(style.categories) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    cats[#cats + 1] = {
      __order = { "category", "layer", "collision" },
      category = name,
      layer = style.categories[name].layer,
      collision = style.categories[name].collision,
    }
  end
  return {
    __order = { "tile", "light", "layers", "collisions", "category_defaults" },
    tile = style.tile,
    light = "upper-left",
    layers = { "ground", "ground_detail", "object", "overhead" },
    collisions = { "none", "block", "hull", "low" },
    category_defaults = cats,
  }
end

return manifest
