-- init.lua -- entry point. Put this directory on package.path and hand back
-- every module, so both the Aseprite commands and the headless test runner
-- bootstrap the toolkit the same way:
--
--   local toolkit = dofile("<path>/art/tools/init.lua")
--
local here = debug.getinfo(1, "S").source:sub(2)
local dir = here:match("^(.*)[/\\][^/\\]*$") or "."

if not package.path:find(dir .. "/?.lua", 1, true) then
  package.path = ("%s/?.lua;%s/?/init.lua;%s"):format(dir, dir, package.path)
end

return {
  dir        = dir,
  style      = require("style"),
  palette    = require("palette"),
  rng        = require("rng"),
  pixels     = require("pixel_utils"),
  materials  = require("materials"),
  generators = require("generators"),
  validators = require("validators"),
  previews   = require("previews"),
}
