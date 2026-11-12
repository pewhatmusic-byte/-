--!strict
-- Rarity tiers. `weight` is the base roll weight; luck multiplies higher tiers (see FishGenerator).

local RarityData = {}

RarityData.Order = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" }

export type RarityInfo = { index: number, weight: number, xp: number, color: Color3, label: string }

local INFO: { [string]: RarityInfo } = {
	Common = { index = 1, weight = 60, xp = 8, color = Color3.fromRGB(176, 184, 200), label = "Common" },
	Uncommon = { index = 2, weight = 25, xp = 16, color = Color3.fromRGB(108, 203, 95), label = "Uncommon" },
	Rare = { index = 3, weight = 10, xp = 35, color = Color3.fromRGB(74, 144, 226), label = "Rare" },
	Epic = { index = 4, weight = 3.5, xp = 80, color = Color3.fromRGB(168, 107, 224), label = "Epic" },
	Legendary = { index = 5, weight = 1.1, xp = 200, color = Color3.fromRGB(242, 163, 58), label = "Legendary" },
	Mythic = { index = 6, weight = 0.3, xp = 500, color = Color3.fromRGB(255, 79, 139), label = "Mythic" },
	Secret = { index = 7, weight = 0.05, xp = 1200, color = Color3.fromRGB(0, 229, 192), label = "Secret" },
}
RarityData.Info = INFO

-- How much a rod's luck (in %) boosts each tier. weight = base * (1 + luck/100 * LuckScale) ^ (index - 1)
RarityData.LuckScale = 0.55

function RarityData.Get(rarity: string): RarityInfo
	return RarityData.Info[rarity] or RarityData.Info.Common
end

function RarityData.Color(rarity: string): Color3
	return RarityData.Get(rarity).color
end

function RarityData.Index(rarity: string): number
	return RarityData.Get(rarity).index
end

return RarityData
