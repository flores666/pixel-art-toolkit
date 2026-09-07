-- commands/preview.lua -- Aseprite: File > Scripts > No Way Up > Preview sheet
--
-- Opens a repeated field of one generator. "Vary seeds" shows the whole
-- variation range; turning it off repeats a single tile, which is the strict
-- test for whether a tileable asset is actually seamless.

local here = debug.getinfo(1, "S").source:sub(2)
local tools = here:match("^(.*)[/\\]commands[/\\][^/\\]*$")
local toolkit = dofile(tools .. "/init.lua")

local bridge = require("aseprite")
local generators, previews = toolkit.generators, toolkit.previews

local titles, by_title = {}, {}
for _, name in ipairs(generators.names) do
  local title = generators.get(name).title
  titles[#titles + 1] = title
  by_title[title] = name
end

local dlg = Dialog("Preview sheet")

dlg:combobox { id = "generator", label = "Generator", options = titles, option = titles[1] }
dlg:number { id = "seed", label = "First seed", text = "1", decimals = 0 }
dlg:number { id = "cols", label = "Columns", text = tostring(previews.default_cols), decimals = 0 }
dlg:number { id = "rows", label = "Rows", text = tostring(previews.default_rows), decimals = 0 }
dlg:check { id = "vary", label = "", text = "Vary seeds per tile", selected = true }
dlg:check { id = "palette", label = "", text = "Palette strip instead", selected = false }
dlg:separator()

dlg:button {
  id = "ok",
  text = "Preview",
  focus = true,
  onclick = function()
    local data = dlg.data
    if data.palette then
      bridge.to_sprite(previews.palette_strip(), "palette_strip")
      dlg:close()
      return
    end
    local name = by_title[data.generator]
    local sheet = previews.sheet(name, {
      seed = math.tointeger(data.seed) or 1,
      cols = math.max(1, math.tointeger(data.cols) or previews.default_cols),
      rows = math.max(1, math.tointeger(data.rows) or previews.default_rows),
      vary = data.vary,
    })
    bridge.to_sprite(sheet, ("%s_preview"):format(name))
    dlg:close()
  end,
}
dlg:button { text = "Cancel" }

dlg:show()
