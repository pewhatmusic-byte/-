--!strict
-- Bait is consumed one per cast. Luck and lure speed stack with the rod.

local Types = require(script.Parent.Types)
type BaitDef = Types.BaitDef

local rgb = Color3.fromRGB

local BaitData = {}

local LIST: { BaitDef } = {
	{ id = "worm", name = "Garden Worm", price = 2, shop = "mossbell", luck = 0, lureSpeed = 1.15, color = rgb(220, 150, 130), description = "Wriggly and reliable." },
	{ id = "shrimp", name = "Pebble Shrimp", price = 6, shop = "mossbell", luck = 10, lureSpeed = 1.2, color = rgb(255, 170, 120), description = "A favourite snack of harbour fish." },
	{ id = "glowbug", name = "Glowbug", price = 15, shop = "mossbell", luck = 18, lureSpeed = 1.25, color = rgb(180, 255, 150), description = "Shines underwater. Night fish can't resist it." },
	{ id = "stormfly", name = "Stormfly", price = 30, shop = "mossbell", luck = 28, lureSpeed = 1.35, color = rgb(150, 190, 255), description = "Buzzes louder when thunder rolls." },
	{ id = "ember_grub", name = "Ember Grub", price = 60, shop = "emberfang", luck = 40, lureSpeed = 1.4, color = rgb(255, 110, 60), description = "Sizzles when it hits the water." },
	{ id = "frost_krill", name = "Frost Krill", price = 60, shop = "frostmere", luck = 40, lureSpeed = 1.4, color = rgb(200, 240, 255), description = "Frozen solid, thaws on the hook." },
	{ id = "star_jelly", name = "Star Jelly", price = 150, shop = "lumenveil", luck = 60, lureSpeed = 1.5, color = rgb(230, 210, 255), description = "Nobody knows where it comes from." },
}

BaitData.List = LIST
BaitData.ById = {} :: { [string]: BaitDef }
for _, bait in ipairs(BaitData.List) do
	BaitData.ById[bait.id] = bait
end

function BaitData.Get(id: string?): BaitDef?
	if not id then
		return nil
	end
	return BaitData.ById[id]
end

return BaitData
