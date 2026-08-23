local dir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
package.path = string.format("%slua/?.lua;%slua/?/init.lua;%s", dir, dir, package.path)

return require("tabata_plugin")
