-- commands/generate.lua -- Aseprite: File > Scripts > No Way Up > Generate asset
--
-- Builds one generator into a new sprite (or a strip of seed variants) and
-- validates the result before handing it over, so nothing that breaks
-- ART_STYLE.md ever reaches the game's atlases.

local here = debug.getinfo(1, "S").source:sub(2)
local tools = here:match("^(.*)[/\\]commands[/\\][^/\\]*$")
local toolkit = dofile(tools .. "/init.lua")

local bridge = require("aseprite")
local generators, validators = toolkit.generators, toolkit.validators

local titles, by_title = {}, {}
for _, name in ipairs(generators.names) do
  local title = generators.get(name).title
  titles[#titles + 1] = title
  by_title[title] = name
end

local dlg = Dialog("Generate asset")

dlg:combobox { id = "generator", label = "Generator", options = titles, option = titles[1] }
dlg:number { id = "seed", label = "Seed", text = "1", decimals = 0 }
dlg:number { id = "variants", label = "Variants", text = "1", decimals = 0 }
dlg:check { id = "validate", label = "", text = "Validate before opening", selected = true }
dlg:separator()

dlg:button {
  id = "ok",
  text = "Generate",
  focus = true,
  onclick = function()
    local data = dlg.data
    local name = by_title[data.generator]
    local seed = math.tointeger(data.seed) or 1
    local variants = math.max(1, math.tointeger(data.variants) or 1)

    local surfaces, failures = {}, {}
    for i = 0, variants - 1 do
      local surface = generators.build(name, seed + i)
      surfaces[#surfaces + 1] = surface
      if data.validate then
        local report = validators.run(surface, generators.spec(name))
        report.seed = seed + i
        if not report.ok then failures[#failures + 1] = validators.format(report) end
      end
    end

    if #failures > 0 then
      app.alert { title = "Validation failed", buttons = "OK",
        text = { "This generator produced art that breaks ART_STYLE.md:", table.concat(failures, "\n") } }
      return
    end

    if #surfaces == 1 then
      bridge.to_sprite(surfaces[1], ("%s_%d"):format(name, seed))
    else
      bridge.to_strip_sprite(surfaces, ("%s_%d_x%d"):format(name, seed, variants))
    end
    dlg:close()
  end,
}
dlg:button { text = "Cancel" }

dlg:show()
