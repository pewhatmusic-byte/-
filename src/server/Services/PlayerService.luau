--!strict
-- Player lifecycle: profile load, leaderstats, spawning, rod tool, XP/coins and client replication.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Config = require(Shared:WaitForChild("Config"))
local LevelUtil = require(Shared:WaitForChild("LevelUtil"))
local LocationData = require(Shared:WaitForChild("LocationData"))
local RodData = require(Shared:WaitForChild("RodData"))
local Signal = require(Shared:WaitForChild("Signal"))
local Types = require(Shared:WaitForChild("Types"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local RodBuilder = require(script.Parent.Parent:WaitForChild("Modules"):WaitForChild("RodBuilder"))

local PlayerService = {}

PlayerService.ProfileLoaded = Signal.new() -- (player, profile)
PlayerService.CharacterSpawned = Signal.new() -- (player, character)

local RESPAWN_DELAY = 3

-- LoadCharacterAsync is the current API; fall back for older Studio builds.
local function loadCharacter(player: Player)
	if player.Parent == nil then
		return
	end
	local ok = pcall(function()
		(player :: any):LoadCharacterAsync()
	end)
	if not ok and player:IsDescendantOf(game) then
		(player :: any):LoadCharacter()
	end
end

local function profileEvent(): RemoteEvent
	return Net.Event("Profile")
end

function PlayerService.GetProfile(player: Player): Types.Profile?
	return DataService.Get(player)
end

-- Yields until the profile is available (or the timeout passes).
function PlayerService.WaitForProfile(player: Player, timeout: number?): Types.Profile?
	local deadline = os.clock() + (timeout or 15)
	while os.clock() < deadline and player.Parent ~= nil do
		local profile = DataService.Get(player)
		if profile then
			return profile
		end
		task.wait(0.1)
	end
	return DataService.Get(player)
end

function PlayerService.Notify(player: Player, kind: string, text: string)
	Net.Event("Notify"):FireClient(player, kind, text)
end

-- Replicates top-level profile fields to the client.
function PlayerService.Patch(player: Player, patch: { [string]: any })
	profileEvent():FireClient(player, "Patch", patch)
end

function PlayerService.UpdateLeaderstats(player: Player)
	local profile = DataService.Get(player)
	local stats = player:FindFirstChild("leaderstats")
	if not profile or not stats then
		return
	end
	local level = stats:FindFirstChild("Level")
	local coins = stats:FindFirstChild("Coins")
	if level and level:IsA("IntValue") then
		level.Value = profile.level
	end
	if coins and coins:IsA("IntValue") then
		coins.Value = profile.coins
	end
end

local function createLeaderstats(player: Player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local level = Instance.new("IntValue")
	level.Name = "Level"
	level.Parent = stats
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Parent = stats
	stats.Parent = player
	PlayerService.UpdateLeaderstats(player)
end

-- Returns the number of levels gained.
function PlayerService.AddXP(player: Player, amount: number): number
	local profile = DataService.Get(player)
	if not profile or amount <= 0 then
		return 0
	end
	local before = profile.level
	local gained = LevelUtil.ApplyXP(profile, amount)
	PlayerService.Patch(player, { xp = profile.xp, level = profile.level })
	if gained > 0 then
		PlayerService.UpdateLeaderstats(player)
		PlayerService.Notify(player, "levelup", string.format("Level %d -> %d!", before, profile.level))
	end
	return gained
end

function PlayerService.AddCoins(player: Player, amount: number)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	profile.coins = math.max(0, math.floor(profile.coins + amount + 0.5))
	if amount > 0 then
		profile.stats.coinsEarned += math.floor(amount + 0.5)
	end
	PlayerService.Patch(player, { coins = profile.coins, stats = profile.stats })
	PlayerService.UpdateLeaderstats(player)
end

-- First visit to a fishing location grants XP. Returns true when it was new.
function PlayerService.DiscoverLocation(player: Player, locationId: string): boolean
	local profile = DataService.Get(player)
	if not profile or profile.discoveredLocations[locationId] then
		return false
	end
	profile.discoveredLocations[locationId] = true
	PlayerService.Patch(player, { discoveredLocations = profile.discoveredLocations })
	PlayerService.Notify(player, "discover", "Discovered " .. LocationData.Name(locationId) .. "!")
	PlayerService.AddXP(player, Config.DiscoverLocationXP)
	return true
end

-- Re-equips the rod tool to match profile.equippedRod.
function PlayerService.RefreshRod(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	RodBuilder.Give(player, RodData.Get(profile.equippedRod))
end

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	humanoid.Died:Connect(function()
		task.wait(RESPAWN_DELAY)
		loadCharacter(player)
	end)
	task.defer(function()
		if character.Parent then
			PlayerService.RefreshRod(player)
			PlayerService.CharacterSpawned:Fire(player, character)
		end
	end)
end

local function onPlayerAdded(player: Player)
	local profile = DataService.Load(player)
	if not profile then
		if player.Parent ~= nil then
			player:Kick("Your save data could not be loaded. Please rejoin in a minute.")
		end
		return
	end
	if player.Parent == nil then
		DataService.Release(player)
		return
	end

	createLeaderstats(player)
	profileEvent():FireClient(player, "Full", profile)
	PlayerService.ProfileLoaded:Fire(player, profile)

	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	loadCharacter(player)
end

function PlayerService.Init()
	Players.CharacterAutoLoads = false

	Net.Function("GetProfile").OnServerInvoke = function(player: Player)
		local profile = PlayerService.WaitForProfile(player, 20)
		if profile then
			return { ok = true, profile = profile }
		end
		return { ok = false, message = "Profile not loaded yet." }
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
end

return PlayerService
