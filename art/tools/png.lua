-- png.lua -- minimal RGBA PNG writer, pure Lua.
--
-- Aseprite owns interactive export. This exists so the pipeline can also run
-- headless -- regenerate every asset, rebuild the preview sheets, diff the
-- result in CI -- on a machine that has no Aseprite. Deflate is emitted as
-- stored blocks: assets are at most a few hundred pixels square, so the size
-- saved by real compression is not worth an inflater in this repo.

local palette = require("palette")

local png = {}

local crc_table
local function crc32(s, crc)
  if not crc_table then
    crc_table = {}
    for i = 0, 255 do
      local c = i
      for _ = 1, 8 do
        if c & 1 == 1 then c = 0xEDB88320 ~ (c >> 1) else c = c >> 1 end
      end
      crc_table[i] = c
    end
  end
  crc = crc or 0xFFFFFFFF
  for i = 1, #s do
    crc = crc_table[(crc ~ s:byte(i)) & 0xFF] ~ (crc >> 8)
  end
  return crc
end

local function be32(n)
  return string.char((n >> 24) & 0xFF, (n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF)
end

local function chunk(kind, data)
  local body = kind .. data
  return be32(#data) .. body .. be32(crc32(body, 0xFFFFFFFF) ~ 0xFFFFFFFF)
end

local function adler32(s)
  local a, b = 1, 0
  for i = 1, #s do
    a = (a + s:byte(i)) % 65521
    b = (b + a) % 65521
  end
  return (b << 16) | a
end

local function zlib_stored(raw)
  local parts = { "\x78\x01" }
  local pos, n = 1, #raw
  repeat
    local len = math.min(65535, n - pos + 1)
    local final = (pos + len - 1 >= n) and 1 or 0
    parts[#parts + 1] = string.char(final)
      .. string.char(len & 0xFF, (len >> 8) & 0xFF)
      .. string.char((~len) & 0xFF, ((~len) >> 8) & 0xFF)
      .. raw:sub(pos, pos + len - 1)
    pos = pos + len
  until pos > n
  parts[#parts + 1] = be32(adler32(raw))
  return table.concat(parts)
end

--- Write a Surface as an RGBA PNG.
-- @param scale integer nearest-neighbour zoom; pixel art is never resampled
function png.write(surface, path, scale)
  scale = math.max(1, math.tointeger(scale or 1))
  local w, h = surface.width * scale, surface.height * scale
  local rows = {}
  for y = 0, surface.height - 1 do
    local row = { "\0" } -- filter type 0: none
    for x = 0, surface.width - 1 do
      local r, g, b, a = palette.unpack(surface:get(x, y))
      row[#row + 1] = string.char(r, g, b, a):rep(scale)
    end
    local line = table.concat(row)
    for _ = 1, scale do rows[#rows + 1] = line end
  end
  local ihdr = be32(w) .. be32(h) .. string.char(8, 6, 0, 0, 0)
  local f = assert(io.open(path, "wb"))
  f:write("\137PNG\r\n\26\n", chunk("IHDR", ihdr),
    chunk("IDAT", zlib_stored(table.concat(rows))), chunk("IEND", ""))
  f:close()
  return path
end

return png
