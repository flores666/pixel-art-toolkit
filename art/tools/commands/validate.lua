-- commands/validate.lua -- Aseprite: File > Scripts > No Way Up > Validate
--
-- Runs the same rules on hand-drawn art as on generated art. Point it at the
-- active sprite before exporting a tile into the game's atlases.

local here = debug.getinfo(1, "S").source:sub(2)
local tools = here:match("^(.*)[/\\]commands[/\\][^/\\]*$")
local toolkit = dofile(tools .. "/init.lua")

local bridge = require("aseprite")
local validators = toolkit.validators

local function show(lines, title)
  app.alert { title = title, text = lines, buttons = "OK" }
end

local dlg = Dialog("Validate")

dlg:check { id = "tileable", label = "", text = "Treat as a tileable asset", selected = false }
dlg:check { id = "all_frames", label = "", text = "Check every frame", selected = false }
dlg:separator()

dlg:button {
  id = "sprite",
  text = "Validate active sprite",
  focus = true,
  onclick = function()
    local sprite = bridge.active_sprite()
    if not sprite then
      show({ "No sprite is open." }, "Validate")
      return
    end
    local data = dlg.data
    local frames = { bridge.active_frame() }
    if data.all_frames then
      frames = {}
      for i = 1, #sprite.frames do frames[i] = i end
    end
    local lines, ok = {}, true
    for _, frame in ipairs(frames) do
      local surface = bridge.from_sprite(sprite, frame)
      local report = validators.run(surface, {
        name = ("%s frame %d"):format(app.fs.fileName(sprite.filename or "sprite"), frame),
        wrap = data.tileable,
      })
      ok = ok and report.ok
      for line in validators.format(report):gmatch("[^\n]+") do lines[#lines + 1] = line end
    end
    show(lines, ok and "Validate: passed" or "Validate: FAILED")
  end,
}

dlg:button {
  id = "generators",
  text = "Validate all generators",
  onclick = function()
    local ok, failures, checked = validators.run_generators(64)
    local lines = { ("%d generated assets checked over 64 seeds."):format(checked) }
    if ok then
      lines[#lines + 1] = "All passed."
    else
      for i = 1, math.min(10, #failures) do
        for line in validators.format(failures[i]):gmatch("[^\n]+") do lines[#lines + 1] = line end
      end
      if #failures > 10 then lines[#lines + 1] = ("... and %d more"):format(#failures - 10) end
    end
    show(lines, ok and "Generators: passed" or "Generators: FAILED")
  end,
}

dlg:button { text = "Close" }

dlg:show()
