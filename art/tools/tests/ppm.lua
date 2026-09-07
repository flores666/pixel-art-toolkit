-- tests/ppm.lua -- test-only surface dump.
--
-- Aseprite owns real file export; this exists so the headless test run leaves
-- something a human (or an image diff) can look at without opening Aseprite.
-- Transparent pixels are written as debug magenta, which is never in the
-- palette, so a leaked background is obvious.

local palette = require("palette")

local ppm = {}

ppm.transparent_debug = { 255, 0, 255 }

--- @param scale integer nearest-neighbour zoom (pixel art must never be smoothed)
function ppm.write(surface, path, scale)
  scale = scale or 1
  local f = assert(io.open(path, "wb"))
  f:write(("P6\n%d %d\n255\n"):format(surface.width * scale, surface.height * scale))
  local out = {}
  for y = 0, surface.height - 1 do
    local row = {}
    for x = 0, surface.width - 1 do
      local c = surface:get(x, y)
      local r, g, b, a = palette.unpack(c)
      if a == 0 then r, g, b = table.unpack(ppm.transparent_debug) end
      local px = string.char(r, g, b):rep(scale)
      row[#row + 1] = px
    end
    local line = table.concat(row)
    for _ = 1, scale do out[#out + 1] = line end
  end
  f:write(table.concat(out))
  f:close()
  return path
end

return ppm
