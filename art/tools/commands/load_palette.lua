-- commands/load_palette.lua -- Aseprite: File > Scripts > No Way Up > Load palette
--
-- Puts the fixed palette on the active sprite so hand-drawn art starts from the
-- same 28 colours the generators use.

local here = debug.getinfo(1, "S").source:sub(2)
local tools = here:match("^(.*)[/\\]commands[/\\][^/\\]*$")
local toolkit = dofile(tools .. "/init.lua")

local bridge = require("aseprite")

local sprite = bridge.active_sprite()
if not sprite then
  app.alert { title = "Load palette", text = "No sprite is open.", buttons = "OK" }
  return
end

bridge.apply_palette(sprite)
app.refresh()
app.alert {
  title = "Load palette",
  text = ("Loaded the No Way Up palette (%d colours)."):format(toolkit.palette.size),
  buttons = "OK",
}
