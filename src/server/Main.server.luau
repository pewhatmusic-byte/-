--!strict
-- Server bootstrap. Order matters: the world must exist before players spawn.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Config = require(Shared:WaitForChild("Config"))

Net.Init()

local Services = script.Parent:WaitForChild("Services")
local ORDER = {
	"WorldService",
	"TimeWeatherService",
	"DataService",
	"PlayerService",
	"InventoryService",
	"EconomyService",
	"FishingService",
	"NPCService",
}

local started = os.clock()
for _, name in ipairs(ORDER) do
	local module = require(Services:WaitForChild(name)) :: { Init: (() -> ())? }
	if module.Init then
		local ok, err = (pcall :: any)(module.Init)
		if not ok then
			warn(string.format("[Main] %s failed to initialise: %s", name, tostring(err)))
		end
	end
end

print(string.format("[%s] Server ready in %.2fs", Config.GameName, os.clock() - started))
