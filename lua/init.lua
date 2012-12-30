--[[
	Shine admin startup.
	Loads stuff.
]]

--I have no idea why it's called this.
Shine = {}

local include = Script.Load
local StringFormat = string.format

--Load order.
local Scripts = {
	"lib/table.lua",
	"lib/string.lua",
	"lib/math.lua",
	"lib/class.lua",
	"core/hook.lua",
	"lib/player.lua",
	"lib/timer.lua",
	"Server.lua",
	"core/permissions.lua",
	"core/commands.lua",
	"core/extensions.lua",
	"core/config.lua",
	"core/logging.lua",
}

for i = 1, #Scripts do
	include( "lua/"..Scripts[ i ] )
end

if Shine.Error then return end

Shine:Print( "Shine started up successfully." )