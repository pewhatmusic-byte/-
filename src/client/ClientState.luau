--!strict
-- Client-side mirror of the player's profile plus a few live world values.
-- Server pushes changes through the Profile remote; UI listens to State.Changed(key).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared:WaitForChild("Signal"))
local Net = require(Shared:WaitForChild("Net"))
local RodData = require(Shared:WaitForChild("RodData"))
local BaitData = require(Shared:WaitForChild("BaitData"))
local Types = require(Shared:WaitForChild("Types"))

local State = {
	Profile = nil :: Types.Profile?,
	Changed = Signal.new(), -- fires (key: string); "profile" means everything changed
	Weather = "Clear" :: Types.Weather,
	Location = nil :: string?, -- fishing location id in front of the player (nil = none)
	FishingPhase = "Idle" :: string,
}

local initialized = false

function State.Init()
	if initialized then
		return
	end
	initialized = true

	Net.Event("Profile").OnClientEvent:Connect(function(action: string, a: any, b: any)
		if action == "Full" then
			State.Profile = a
			State.Changed:Fire("profile")
			return
		end
		local profile = State.Profile
		if not profile then
			return
		end
		if action == "Patch" then
			for key, value in pairs(a) do
				-- `false` is the server's way of sending "cleared" (nil can't travel inside a table)
				(profile :: any)[key] = if value == false then nil else value
				State.Changed:Fire(key)
			end
		elseif action == "FishAdded" then
			table.insert(profile.fish, a)
			State.Changed:Fire("fish")
		elseif action == "FishRemoved" then
			local removed: { [string]: boolean } = {}
			for _, uid in ipairs(a) do
				removed[uid] = true
			end
			local kept = {}
			for _, caught in ipairs(profile.fish) do
				if not removed[caught.uid] then
					table.insert(kept, caught)
				end
			end
			profile.fish = kept
			State.Changed:Fire("fish")
		elseif action == "Bestiary" then
			profile.bestiary[a] = b
			State.Changed:Fire("bestiary")
		end
	end)

	task.spawn(function()
		local response = Net.Invoke("GetProfile")
		if response.ok and response.profile and not State.Profile then
			State.Profile = response.profile
			State.Changed:Fire("profile")
		end
	end)

	task.spawn(function()
		local worldState = ReplicatedStorage:WaitForChild("WorldState")
		local weather = worldState:WaitForChild("Weather") :: StringValue
		State.Weather = weather.Value :: any
		weather.Changed:Connect(function(value)
			State.Weather = value :: any
			State.Changed:Fire("weather")
		end)
	end)
end

function State.WaitForProfile(): Types.Profile
	while not State.Profile do
		State.Changed:Wait()
	end
	return State.Profile :: Types.Profile
end

function State.GetRod(): Types.RodDef
	local profile = State.Profile
	return RodData.Get(if profile then profile.equippedRod else nil)
end

function State.BaitCount(id: string?): number
	local profile = State.Profile
	if not profile or not id then
		return 0
	end
	return profile.bait[id] or 0
end

-- Equipped bait definition, or nil when nothing usable is equipped.
function State.GetBait(): Types.BaitDef?
	local profile = State.Profile
	if not profile or not profile.equippedBait then
		return nil
	end
	if State.BaitCount(profile.equippedBait) <= 0 then
		return nil
	end
	return BaitData.Get(profile.equippedBait)
end

function State.FishCount(): number
	local profile = State.Profile
	return if profile then #profile.fish else 0
end

function State.OwnsRod(id: string): boolean
	local profile = State.Profile
	return profile ~= nil and table.find(profile.rods, id) ~= nil
end

function State.SetLocation(id: string?)
	if State.Location ~= id then
		State.Location = id
		State.Changed:Fire("location")
	end
end

function State.SetFishingPhase(phase: string)
	if State.FishingPhase ~= phase then
		State.FishingPhase = phase
		State.Changed:Fire("fishingPhase")
	end
end

return State
