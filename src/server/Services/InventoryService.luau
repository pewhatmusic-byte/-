--!strict
-- Fish bag, rods, bait and the bestiary. All mutations go through here so replication stays consistent.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Config = require(Shared:WaitForChild("Config"))
local RodData = require(Shared:WaitForChild("RodData"))
local BaitData = require(Shared:WaitForChild("BaitData"))
local FishData = require(Shared:WaitForChild("FishData"))
local Types = require(Shared:WaitForChild("Types"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local PlayerService = require(script.Parent:WaitForChild("PlayerService"))
local RateLimit = require(script.Parent.Parent:WaitForChild("Modules"):WaitForChild("RateLimit"))

type CaughtFish = Types.CaughtFish

local InventoryService = {}

local function profileEvent(): RemoteEvent
	return Net.Event("Profile")
end

function InventoryService.HasSpace(player: Player): boolean
	local profile = DataService.Get(player)
	return profile ~= nil and #profile.fish < Config.FishCapacity
end

-- Records the catch in the bestiary. Returns true for a never-before-caught species.
function InventoryService.UpdateBestiary(player: Player, fish: CaughtFish): boolean
	local profile = DataService.Get(player)
	if not profile then
		return false
	end
	local entry = profile.bestiary[fish.id]
	local isNew = entry == nil
	if not entry then
		entry = { count = 0, bestWeight = 0, firstAt = os.time(), shiny = false }
		profile.bestiary[fish.id] = entry
	end
	entry.count += 1
	entry.bestWeight = math.max(entry.bestWeight, fish.weight)
	entry.shiny = entry.shiny or fish.shiny
	profileEvent():FireClient(player, "Bestiary", fish.id, entry)
	return isNew
end

-- Returns (added, isNewSpecies).
function InventoryService.AddFish(player: Player, fish: CaughtFish): (boolean, boolean)
	local profile = DataService.Get(player)
	if not profile or #profile.fish >= Config.FishCapacity then
		return false, false
	end
	table.insert(profile.fish, fish)
	profile.stats.totalCaught += 1
	local isNew = InventoryService.UpdateBestiary(player, fish)
	profileEvent():FireClient(player, "FishAdded", fish)
	PlayerService.Patch(player, { stats = profile.stats })
	return true, isNew
end

-- Removes fish by uid and returns the removed entries.
function InventoryService.RemoveFish(player: Player, uids: { string }): { CaughtFish }
	local profile = DataService.Get(player)
	if not profile then
		return {}
	end
	local wanted: { [string]: boolean } = {}
	for _, uid in ipairs(uids) do
		wanted[uid] = true
	end
	local removed, kept = {}, {}
	for _, fish in ipairs(profile.fish) do
		if wanted[fish.uid] then
			table.insert(removed, fish)
		else
			table.insert(kept, fish)
		end
	end
	if #removed > 0 then
		profile.fish = kept
		local removedIds = {}
		for _, fish in ipairs(removed) do
			table.insert(removedIds, fish.uid)
		end
		profileEvent():FireClient(player, "FishRemoved", removedIds)
	end
	return removed
end

function InventoryService.OwnsRod(player: Player, rodId: string): boolean
	local profile = DataService.Get(player)
	return profile ~= nil and table.find(profile.rods, rodId) ~= nil
end

function InventoryService.GiveRod(player: Player, rodId: string)
	local profile = DataService.Get(player)
	if not profile or not RodData.ById[rodId] or table.find(profile.rods, rodId) then
		return
	end
	table.insert(profile.rods, rodId)
	PlayerService.Patch(player, { rods = profile.rods })
end

function InventoryService.EquipRod(player: Player, rodId: string): (boolean, string)
	local profile = DataService.Get(player)
	if not profile then
		return false, "No profile."
	end
	if not RodData.ById[rodId] or not table.find(profile.rods, rodId) then
		return false, "You don't own that rod."
	end
	if profile.equippedRod == rodId then
		return true, "Already equipped."
	end
	profile.equippedRod = rodId
	PlayerService.Patch(player, { equippedRod = rodId })
	PlayerService.RefreshRod(player)
	return true, "Equipped " .. RodData.Get(rodId).name .. "."
end

function InventoryService.AddBait(player: Player, baitId: string, amount: number)
	local profile = DataService.Get(player)
	if not profile or not BaitData.ById[baitId] or amount <= 0 then
		return
	end
	profile.bait[baitId] = (profile.bait[baitId] or 0) + amount
	if not profile.equippedBait then
		profile.equippedBait = baitId
	end
	PlayerService.Patch(player, { bait = profile.bait, equippedBait = profile.equippedBait })
end

function InventoryService.EquipBait(player: Player, baitId: string?): (boolean, string)
	local profile = DataService.Get(player)
	if not profile then
		return false, "No profile."
	end
	if baitId == nil then
		profile.equippedBait = nil
		PlayerService.Patch(player, { equippedBait = false })
		return true, "Fishing without bait."
	end
	local def = BaitData.Get(baitId)
	if not def or (profile.bait[baitId] or 0) <= 0 then
		return false, "You have none of that bait."
	end
	profile.equippedBait = baitId
	PlayerService.Patch(player, { equippedBait = baitId })
	return true, "Using " .. def.name .. "."
end

-- The bait that would be used for the next cast (without consuming it).
function InventoryService.PeekBait(player: Player): Types.BaitDef?
	local profile = DataService.Get(player)
	if not profile or not profile.equippedBait then
		return nil
	end
	if (profile.bait[profile.equippedBait] or 0) <= 0 then
		return nil
	end
	return BaitData.Get(profile.equippedBait)
end

-- Consumes one unit of the equipped bait. Returns the bait used (nil = none).
function InventoryService.ConsumeBait(player: Player): Types.BaitDef?
	local profile = DataService.Get(player)
	local def = InventoryService.PeekBait(player)
	if not profile or not def then
		return nil
	end
	local remaining = (profile.bait[def.id] or 0) - 1
	if remaining <= 0 then
		profile.bait[def.id] = nil
		profile.equippedBait = nil
		PlayerService.Patch(player, { bait = profile.bait, equippedBait = false })
		PlayerService.Notify(player, "info", "You used your last " .. def.name .. ".")
	else
		profile.bait[def.id] = remaining
		PlayerService.Patch(player, { bait = profile.bait })
	end
	return def
end

function InventoryService.Init()
	Net.Function("Equip").OnServerInvoke = function(player: Player, kind: any, id: any)
		if not RateLimit.Check(player, "Equip", Config.RemoteRateLimit) then
			return { ok = false, message = "Slow down!" }
		end
		if kind == "rod" and type(id) == "string" then
			local ok, message = InventoryService.EquipRod(player, id)
			return { ok = ok, message = message }
		elseif kind == "bait" and (id == nil or type(id) == "string") then
			local ok, message = InventoryService.EquipBait(player, id)
			return { ok = ok, message = message }
		end
		return { ok = false, message = "Bad request." }
	end

	Net.Function("DiscardFish").OnServerInvoke = function(player: Player, uid: any)
		if not RateLimit.Check(player, "Discard", Config.RemoteRateLimit) then
			return { ok = false, message = "Slow down!" }
		end
		if type(uid) ~= "string" then
			return { ok = false, message = "Bad request." }
		end
		local removed = InventoryService.RemoveFish(player, { uid })
		if #removed == 0 then
			return { ok = false, message = "That fish is gone already." }
		end
		local def = FishData.Get(removed[1].id)
		return { ok = true, message = "Released the " .. (if def then def.name else "fish") .. "." }
	end
end

return InventoryService
