-- aseprite.lua -- the only module that knows Aseprite exists.
--
-- Everything above this line is plain Lua operating on Surfaces, which is why
-- the toolkit can be tested from a terminal. This module converts at the edge:
-- Surface -> Image/Sprite for generation, Image/Sprite -> Surface for
-- validating art a human drew by hand.

local palette = require("palette")
local P = require("pixel_utils")

local bridge = {}

--- The active sprite / frame, across Aseprite API versions (app.activeSprite
--- was renamed app.sprite in 1.3).
function bridge.active_sprite()
  return app.sprite or app.activeSprite
end

function bridge.active_frame()
  local frame = app.frame or app.activeFrame
  return frame and frame.frameNumber or 1
end

--- True when running inside Aseprite (the commands check this before doing
--- anything, so a mistaken `lua aseprite.lua` fails with a clear message).
function bridge.available()
  return type(_G.app) == "table" and _G.Image ~= nil
end

local function require_aseprite()
  if not bridge.available() then
    error("this command must be run from inside Aseprite", 3)
  end
end

--- Surface -> Image. Packed values are already in Aseprite's RGBA order.
function bridge.to_image(surface)
  require_aseprite()
  local image = Image(surface.width, surface.height, ColorMode.RGB)
  for x, y, c in surface:pixels() do
    image:drawPixel(x, y, c)
  end
  return image
end

--- Image -> Surface, raw: whatever colours the image holds survive the trip,
--- including off-palette and semi-transparent ones. Validators need to see them.
function bridge.from_image(image)
  require_aseprite()
  local surface = P.new(image.width, image.height)
  for it in image:pixels() do
    surface:set_raw(it.x, it.y, it())
  end
  return surface
end

--- Flatten a sprite frame into a Surface for validation.
function bridge.from_sprite(sprite, frame)
  require_aseprite()
  frame = frame or bridge.active_frame()
  if sprite.colorMode ~= ColorMode.RGB then
    error("sprite is " .. tostring(sprite.colorMode) ..
      "; convert it to RGB (Sprite > Color Mode > RGB) before validating", 2)
  end
  local flat = Image(sprite.width, sprite.height, ColorMode.RGB)
  -- Image:drawSprite is the documented flatten; fall back to the Image(sprite)
  -- constructor on API versions that lack it.
  local ok = pcall(function() flat:drawSprite(sprite, frame) end)
  if not ok then flat = Image(sprite) end
  return bridge.from_image(flat)
end

--- Install the fixed palette on a sprite, in ramp order, with index 0 reserved
--- for transparency the way Aseprite expects.
function bridge.apply_palette(sprite)
  require_aseprite()
  local entries = palette.entries()
  local pal = Palette(#entries + 1)
  pal:setColor(0, Color { r = 0, g = 0, b = 0, a = 0 })
  for i, e in ipairs(entries) do
    pal:setColor(i, Color { r = e.r, g = e.g, b = e.b, a = 255 })
  end
  sprite:setPalette(pal)
  return pal
end

--- Surface -> a new sprite, palette attached, ready to save.
function bridge.to_sprite(surface, name)
  require_aseprite()
  local sprite = Sprite(surface.width, surface.height, ColorMode.RGB)
  local image = bridge.to_image(surface)
  app.transaction(function()
    sprite.cels[1].image:drawImage(image, Point(0, 0))
    if name then
      sprite.layers[1].name = name
      sprite.filename = name .. ".aseprite"
    end
  end)
  bridge.apply_palette(sprite)
  app.refresh()
  return sprite
end

--- Lay several surfaces out left to right in one sprite (variant sheets).
function bridge.to_strip_sprite(surfaces, name)
  require_aseprite()
  local w, h = 0, 0
  for _, s in ipairs(surfaces) do w = w + s.width; h = math.max(h, s.height) end
  local strip = P.new(w, h)
  local x = 0
  for _, s in ipairs(surfaces) do strip:blit(s, x, 0); x = x + s.width end
  return bridge.to_sprite(strip, name)
end

return bridge
