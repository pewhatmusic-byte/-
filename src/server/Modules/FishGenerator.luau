--!strict
-- Server-side fish generation: which fish bites, how big it is, mutations, value, XP and the
-- minigame difficulty. Nothing here trusts the client.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local FishData = require(Shared:WaitForChild("FishData"))
local RarityData = require(Shared:WaitForChild("RarityData"))
local MutationData = require(Shared:WaitForChild("MutationData"))
local LocationData = require(Shared:WaitForChild("LocationData"))
local Util = require(Shared:WaitForChild("Util"))
local Types = require(Shared:WaitForChild("Types"))

type FishDef = Types.FishDef
type CaughtFish = Types.CaughtFish

local FishGenerator = {}

export type GenContext = {
	locationId: string,
	luck: number,
	timeOfDay: string, -- "Day" | "Night"
	weather: string, -- "Clear" | "Rain" | "Storm"
	rng: Random,
}

export type Generated = {
	fish: CaughtFish,
	def: FishDef,
	norm: number, -- 0..1 size roll
	xp: number,
}

local SIZE_TIERS = {
	{ max = 0.08, name = "Tiny" },
	{ max = 0.3, name = "Small" },
	{ max = 0.6, name = "Average" },
	{ max = 0.85, name = "Large" },
	{ max = 0.97, name = "Huge" },
	{ max = math.huge, name = "Colossal" },
}

-- How erratic each rarity is in the minigame (0..1).
local STRENGTH = {
	Common = 0.22, Uncommon = 0.33, Rare = 0.46, Epic = 0.6, Legendary = 0.72, Mythic = 0.85, Secret = 0.95,
}

local function matchesTime(def: FishDef, timeOfDay: string): boolean
	return def.time == "Any" or def.time == timeOfDay
end

local function matchesWeather(def: FishDef, weather: string): boolean
	if def.weather == "Any" then
		return true
	elseif def.weather == "Rain" then
		return weather == "Rain" or weather == "Storm"
	end
	return def.weather == weather
end

-- Fish that can currently bite at this location, grouped by rarity.
function FishGenerator.Candidates(ctx: GenContext): { [string]: { FishDef } }
	local groups: { [string]: { FishDef } } = {}
	for _, def in ipairs(FishData.PoolFor(ctx.locationId)) do
		if matchesTime(def, ctx.timeOfDay) and matchesWeather(def, ctx.weather) then
			local group = groups[def.rarity]
			if not group then
				group = {}
				groups[def.rarity] = group
			end
			table.insert(group, def)
		end
	end
	return groups
end

function FishGenerator.RarityWeight(rarity: string, luck: number): number
	local info = RarityData.Get(rarity)
	local mult = (1 + math.max(luck, 0) / 100 * RarityData.LuckScale) ^ (info.index - 1)
	return info.weight * mult
end

function FishGenerator.PickRarity(groups: { [string]: { FishDef } }, luck: number, rng: Random): string?
	local available = {}
	for _, rarity in ipairs(RarityData.Order) do
		if groups[rarity] and #groups[rarity] > 0 then
			table.insert(available, rarity)
		end
	end
	return Util.WeightedChoice(rng, available, function(rarity)
		return FishGenerator.RarityWeight(rarity, luck)
	end)
end

-- Skewed toward small fish with a small chance of a giant.
function FishGenerator.RollSize(rng: Random): number
	local r = rng:NextNumber()
	local norm = r * r * r
	if rng:NextNumber() < 0.04 then
		norm = math.max(norm, 0.6 + 0.4 * rng:NextNumber())
	end
	return math.clamp(norm, 0, 1)
end

function FishGenerator.SizeTier(norm: number): string
	for _, tier in ipairs(SIZE_TIERS) do
		if norm < tier.max then
			return tier.name
		end
	end
	return "Colossal"
end

function FishGenerator.RollMutation(ctx: GenContext): Types.MutationDef?
	local kind = LocationData.Kind(ctx.locationId)
	for _, mutation in ipairs(MutationData.List) do
		local eligible = true
		if mutation.requiresTime and mutation.requiresTime ~= ctx.timeOfDay then
			eligible = false
		end
		if mutation.requiresWeather and mutation.requiresWeather ~= ctx.weather then
			eligible = false
		end
		if mutation.requiresKind and not table.find(mutation.requiresKind, kind) then
			eligible = false
		end
		if eligible and ctx.rng:NextNumber() < mutation.chance then
			return mutation
		end
	end
	return nil
end

function FishGenerator.ValueFor(def: FishDef, norm: number, mutation: Types.MutationDef?, shiny: boolean): number
	local value = def.baseValue * (0.7 + 1.1 * norm)
	if mutation then
		value *= mutation.valueMult
	end
	if shiny then
		value *= MutationData.ShinyValueMult
	end
	return math.max(1, math.floor(value + 0.5))
end

function FishGenerator.XPFor(def: FishDef, norm: number, mutation: Types.MutationDef?, shiny: boolean): number
	local xp = RarityData.Get(def.rarity).xp * (0.8 + 0.6 * norm)
	if mutation then
		xp *= mutation.xpMult
	end
	if shiny then
		xp *= MutationData.ShinyXPMult
	end
	return math.max(1, math.floor(xp + 0.5))
end

-- Rolls a complete catch. Returns nil when nothing can bite here right now.
function FishGenerator.Generate(ctx: GenContext): Generated?
	local groups = FishGenerator.Candidates(ctx)
	local rarity = FishGenerator.PickRarity(groups, ctx.luck, ctx.rng)
	if not rarity then
		return nil
	end
	local group = groups[rarity]
	local def = group[ctx.rng:NextInteger(1, #group)]

	local norm = FishGenerator.RollSize(ctx.rng)
	local weight = Util.Lerp(def.minWeight, def.maxWeight, norm)
	weight = math.floor(weight * 100 + 0.5) / 100

	local mutation = FishGenerator.RollMutation(ctx)
	local shiny = ctx.rng:NextNumber() < MutationData.ShinyChance

	local fish: CaughtFish = {
		uid = Util.ShortId(ctx.rng),
		id = def.id,
		weight = weight,
		sizeTier = FishGenerator.SizeTier(norm),
		mutation = if mutation then mutation.id else nil,
		shiny = shiny,
		value = FishGenerator.ValueFor(def, norm, mutation, shiny),
		caughtAt = os.time(),
		location = ctx.locationId,
	}
	return { fish = fish, def = def, norm = norm, xp = FishGenerator.XPFor(def, norm, mutation, shiny) }
end

-- Minigame tuning from fish strength vs rod stats. Sent to the client (never includes the fish id).
function FishGenerator.MinigameParams(def: FishDef, fish: CaughtFish, rod: Types.RodDef): Types.MinigameParams
	local strength = STRENGTH[def.rarity] or 0.3
	local control = math.clamp(rod.control, 0, 100) / 100
	local resilience = math.clamp(rod.resilience, 0, 100) / 100

	local weightRatio = fish.weight / math.max(rod.maxWeight, 1)
	local heavy = weightRatio > 1
	if heavy then
		strength = math.min(strength + 0.12, 1)
	end

	local zoneSize = math.clamp(0.3 + control * 0.22 - strength * 0.12, 0.12, 0.5)
	local fillRate = 0.15 + resilience * 0.06
	local drainRate = 0.22 - resilience * 0.1
	if heavy then
		drainRate *= 1 + math.min(weightRatio - 1, 3) * 0.5
	end

	local startProgress = Config.MinigameStartProgress
	return {
		rarity = def.rarity,
		strength = strength,
		speed = 0.35 + strength * 0.95,
		zoneSize = zoneSize,
		fillRate = fillRate,
		drainRate = drainRate,
		startProgress = startProgress,
		minDuration = (1 - startProgress) / fillRate * 0.8,
		heavy = heavy,
		weightRatio = weightRatio,
	}
end

return FishGenerator
