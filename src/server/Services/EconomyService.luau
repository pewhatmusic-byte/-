--!strict
-- Selling fish and buying rods/bait. Prices and values are always computed server-side.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Config = require(Shared:WaitForChild("Config"))
local RodData = require(Shared:WaitForChild("RodData"))
local BaitData = require(Shared:WaitForChild("BaitData"))
local Util = require(Shared:WaitForChild("Util"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local PlayerService = require(script.Parent:WaitForChild("PlayerService"))
local InventoryService = require(script.Parent:WaitForChild("InventoryService"))
local RateLimit = require(script.Parent.Parent:WaitForChild("Modules"):WaitForChild("RateLimit"))

local EconomyService = {}

local MAX_BAIT_PER_PURCHASE = 50

function EconomyService.SellFish(player: Player, selection: any): Net.Response
	local profile = DataService.Get(player)
	if not profile then
		return { ok = false, message = "No profile." }
	end

	local uids: { string } = {}
	if selection == "all" then
		for _, fish in ipairs(profile.fish) do
			table.insert(uids, fish.uid)
		end
	elseif type(selection) == "table" then
		for _, uid in ipairs(selection) do
			if type(uid) == "string" then
				table.insert(uids, uid)
			end
		end
	else
		return { ok = false, message = "Bad request." }
	end
	if #uids == 0 then
		return { ok = false, message = "Nothing to sell." }
	end

	local removed = InventoryService.RemoveFish(player, uids)
	if #removed == 0 then
		return { ok = false, message = "Those fish are gone." }
	end
	local total = 0
	for _, fish in ipairs(removed) do
		total += fish.value
	end
	profile.stats.totalSold += #removed
	PlayerService.AddCoins(player, total)
	return {
		ok = true,
		soldCount = #removed,
		total = total,
		message = string.format("Sold %d fish for %s coins.", #removed, Util.FormatNumber(total)),
	}
end

function EconomyService.PurchaseRod(player: Player, rodId: string): Net.Response
	local profile = DataService.Get(player)
	local rod = RodData.ById[rodId]
	if not profile or not rod then
		return { ok = false, message = "Unknown rod." }
	end
	if table.find(profile.rods, rodId) then
		return { ok = false, message = "You already own that rod." }
	end
	if profile.level < rod.levelReq then
		return { ok = false, message = string.format("Requires level %d.", rod.levelReq) }
	end
	if profile.coins < rod.price then
		return { ok = false, message = "Not enough coins." }
	end
	PlayerService.AddCoins(player, -rod.price)
	InventoryService.GiveRod(player, rodId)
	InventoryService.EquipRod(player, rodId)
	return { ok = true, message = "Bought the " .. rod.name .. "!" }
end

function EconomyService.PurchaseBait(player: Player, baitId: string, amount: number): Net.Response
	local profile = DataService.Get(player)
	local bait = BaitData.ById[baitId]
	if not profile or not bait then
		return { ok = false, message = "Unknown bait." }
	end
	if amount ~= amount or amount < 1 or amount > MAX_BAIT_PER_PURCHASE then
		return { ok = false, message = "Bad amount." }
	end
	amount = math.floor(amount)
	local cost = bait.price * amount
	if profile.coins < cost then
		return { ok = false, message = "Not enough coins." }
	end
	PlayerService.AddCoins(player, -cost)
	InventoryService.AddBait(player, baitId, amount)
	return { ok = true, message = string.format("Bought %d x %s.", amount, bait.name) }
end

function EconomyService.Init()
	Net.Function("SellFish").OnServerInvoke = function(player: Player, selection: any)
		if not RateLimit.Check(player, "Sell", Config.RemoteRateLimit) then
			return { ok = false, message = "Slow down!" }
		end
		return EconomyService.SellFish(player, selection)
	end

	Net.Function("Purchase").OnServerInvoke = function(player: Player, kind: any, id: any, amount: any)
		if not RateLimit.Check(player, "Purchase", Config.RemoteRateLimit) then
			return { ok = false, message = "Slow down!" }
		end
		if type(id) ~= "string" then
			return { ok = false, message = "Bad request." }
		end
		if kind == "rod" then
			return EconomyService.PurchaseRod(player, id)
		elseif kind == "bait" then
			return EconomyService.PurchaseBait(player, id, if type(amount) == "number" then amount else 1)
		end
		return { ok = false, message = "Bad request." }
	end
end

return EconomyService
