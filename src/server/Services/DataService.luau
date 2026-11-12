--!strict
-- Loads and saves player profiles with DataStoreService.
--  * UpdateAsync everywhere (never SetAsync) with a lightweight session lock so two servers can't
--    both own the same profile (prevents duplication exploits via server hopping).
--  * Retries, autosave, BindToClose, data versioning + template reconcile.
--  * If loading fails outside Studio the player is kicked: we never save a profile we could not load.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local RodData = require(Shared:WaitForChild("RodData"))
local Types = require(Shared:WaitForChild("Types"))

type Profile = Types.Profile

local DataService = {}

-- Persisted structure. Reconcile only adds missing keys, so starter items must NOT live here
-- (otherwise a player who used their last worm would be re-gifted on the next load).
local TEMPLATE: Profile = {
	version = Config.DataVersion,
	coins = 0,
	xp = 0,
	level = 1,
	rods = { RodData.DefaultRod },
	equippedRod = RodData.DefaultRod,
	bait = {},
	equippedBait = nil,
	fish = {},
	bestiary = {},
	discoveredLocations = {},
	treasures = {},
	cosmetics = {},
	boats = {},
	quests = {},
	stats = { totalCaught = 0, totalSold = 0, coinsEarned = 0, playtime = 0 },
	settings = {},
}

-- What a brand-new player starts with.
local function newProfile(): Profile
	local profile = Util.DeepCopy(TEMPLATE)
	profile.coins = 25
	profile.bait = { worm = 10 }
	profile.equippedBait = "worm"
	return profile
end

-- Add a function per version bump: MIGRATIONS[1] upgrades version 1 -> 2, etc.
local MIGRATIONS: { [number]: (profile: any) -> () } = {}

type Session = {
	player: Player,
	profile: Profile,
	lockId: string,
	loadedAt: number,
	lastPlaytimeMark: number,
	offline: boolean, -- Studio without DataStore access: never saved
	saving: boolean,
}

local sessions: { [Player]: Session } = {}
local store: DataStore? = nil

local function getStore(): DataStore?
	if store then
		return store
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		store = result
		return result
	end
	warn("[DataService] DataStore unavailable: " .. tostring(result))
	return nil
end

local function keyFor(player: Player): string
	return "player_" .. player.UserId
end

local function migrate(profile: any): Profile
	local version = if type(profile.version) == "number" then profile.version else 1
	while version < Config.DataVersion do
		local step = MIGRATIONS[version]
		if step then
			step(profile)
		end
		version += 1
		profile.version = version
	end
	Util.Reconcile(profile, TEMPLATE)
	if not table.find(profile.rods, profile.equippedRod) then
		profile.equippedRod = RodData.DefaultRod
		if not table.find(profile.rods, RodData.DefaultRod) then
			table.insert(profile.rods, RodData.DefaultRod)
		end
	end
	return profile
end

-- One attempt to claim the lock and load. Returns (profile, status) where status is "ok" | "locked" | "error".
local function tryLoad(player: Player, lockId: string): (Profile?, string)
	local ds = getStore()
	if not ds then
		return nil, "error"
	end
	local locked = false
	local loaded: any = nil
	local ok, err = pcall(function()
		ds:UpdateAsync(keyFor(player), function(record: any)
			record = if type(record) == "table" then record else {}
			local lock = record.lock
			if type(lock) == "table" and type(lock.time) == "number" and lock.id ~= lockId
				and (os.time() - lock.time) < Config.SessionLockTimeout then
				locked = true
				return nil -- cancel the write; another server still owns this profile
			end
			local profile = record.profile
			if type(profile) ~= "table" then
				profile = newProfile()
			end
			record.profile = profile
			record.lock = { id = lockId, time = os.time() }
			loaded = profile
			return record
		end)
	end)
	if not ok then
		warn(string.format("[DataService] Load error for %s: %s", player.Name, tostring(err)))
		return nil, "error"
	end
	if locked then
		return nil, "locked"
	end
	return loaded, "ok"
end

-- Writes the session's profile. Returns true on success.
local function writeSession(session: Session, releaseLock: boolean): boolean
	if session.offline then
		return true
	end
	local ds = getStore()
	if not ds then
		return false
	end
	if session.saving then
		return false
	end
	session.saving = true

	local now = os.time()
	session.profile.stats.playtime += math.max(0, now - session.lastPlaytimeMark)
	session.lastPlaytimeMark = now

	local ok, err = pcall(function()
		ds:UpdateAsync(keyFor(session.player), function(record: any)
			record = if type(record) == "table" then record else {}
			local lock = record.lock
			if type(lock) == "table" and lock.id ~= session.lockId and type(lock.time) == "number"
				and (os.time() - lock.time) < Config.SessionLockTimeout then
				return nil -- lock was taken over; do not clobber newer data
			end
			record.profile = session.profile
			record.lock = if releaseLock then nil else { id = session.lockId, time = os.time() }
			record.savedAt = os.time()
			return record
		end)
	end)
	session.saving = false
	if not ok then
		warn(string.format("[DataService] Save error for %s: %s", session.player.Name, tostring(err)))
		return false
	end
	return true
end

-- Loads (yielding) a player's profile. Returns nil when the data could not be loaded.
function DataService.Load(player: Player): Profile?
	local lockId = HttpService:GenerateGUID(false)
	local profile: Profile? = nil
	local offline = false

	for attempt = 1, Config.LoadRetries do
		local loaded, status = tryLoad(player, lockId)
		if status == "ok" and loaded then
			profile = loaded
			break
		end
		if status == "error" and RunService:IsStudio() then
			-- Studio without "Enable Studio Access to API Services": play with a fresh profile, never save.
			warn("[DataService] Using an offline profile in Studio for " .. player.Name)
			profile = newProfile()
			offline = true
			break
		end
		if attempt < Config.LoadRetries then
			task.wait(Config.LoadRetryDelay * attempt)
		end
		if player.Parent == nil then
			return nil
		end
	end

	if not profile then
		return nil
	end
	if player.Parent == nil then
		return nil
	end

	migrate(profile)
	sessions[player] = {
		player = player,
		profile = profile,
		lockId = lockId,
		loadedAt = os.time(),
		lastPlaytimeMark = os.time(),
		offline = offline,
		saving = false,
	}
	return profile
end

function DataService.Get(player: Player): Profile?
	local session = sessions[player]
	return if session then session.profile else nil
end

function DataService.IsOffline(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and session.offline
end

function DataService.Save(player: Player): boolean
	local session = sessions[player]
	if not session then
		return false
	end
	return writeSession(session, false)
end

-- Final save + lock release; called when the player leaves.
function DataService.Release(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	sessions[player] = nil
	while session.saving do
		task.wait(0.1)
	end
	writeSession(session, true)
end

function DataService.Init()
	Players.PlayerRemoving:Connect(function(player)
		DataService.Release(player)
	end)

	task.spawn(function()
		while true do
			task.wait(Config.AutosaveInterval)
			for player, session in pairs(sessions) do
				if player.Parent ~= nil then
					task.spawn(writeSession, session, false)
				end
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in pairs(sessions) do
			pending += 1
			task.spawn(function()
				DataService.Release(player)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService
