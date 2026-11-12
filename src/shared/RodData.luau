--!strict
-- Fishing rods.
--   luck       : % boost to rarer fish
--   lureSpeed  : multiplier on how fast fish bite
--   control    : 0-100, bigger catch zone and snappier movement in the minigame
--   resilience : 0-100, slower progress loss when the fish escapes the zone
--   maxWeight  : kg; heavier fish strain the line (harder minigame)
--   castRange  : studs
--   shop       : which island's rodsmith sells it

local Types = require(script.Parent.Types)
type RodDef = Types.RodDef

local rgb = Color3.fromRGB

local RodData = {}

local LIST: { RodDef } = {
	{ id = "twig_rod", name = "Twig Rod", price = 0, levelReq = 1, shop = "mossbell",
		luck = 0, lureSpeed = 1.0, control = 0, resilience = 0, maxWeight = 20, castRange = 45,
		color1 = rgb(140, 100, 60), color2 = rgb(90, 60, 40), description = "A stick, some string and a lot of hope." },
	{ id = "driftwood_rod", name = "Driftwood Rod", price = 350, levelReq = 3, shop = "mossbell",
		luck = 8, lureSpeed = 1.1, control = 6, resilience = 5, maxWeight = 50, castRange = 55,
		color1 = rgb(190, 160, 110), color2 = rgb(120, 90, 60), description = "Light, salt-worn and surprisingly springy." },
	{ id = "harbor_rod", name = "Harbour Rod", price = 1500, levelReq = 7, shop = "mossbell",
		luck = 18, lureSpeed = 1.2, control = 12, resilience = 12, maxWeight = 120, castRange = 65,
		color1 = rgb(70, 110, 160), color2 = rgb(220, 220, 230), description = "The working rod of every Mossbell fisher." },
	{ id = "tidecaller_rod", name = "Tidecaller Rod", price = 6500, levelReq = 13, shop = "mossbell",
		luck = 32, lureSpeed = 1.35, control = 20, resilience = 20, maxWeight = 320, castRange = 75,
		color1 = rgb(60, 180, 170), color2 = rgb(240, 200, 90), description = "Hums softly whenever the tide turns." },
	{ id = "moonwake_rod", name = "Moonwake Rod", price = 24000, levelReq = 20, shop = "mossbell",
		luck = 50, lureSpeed = 1.5, control = 30, resilience = 28, maxWeight = 900, castRange = 85,
		color1 = rgb(200, 210, 255), color2 = rgb(120, 110, 220), description = "Carved from driftwood that only washes up at midnight." },

	-- Sold on later islands
	{ id = "emberforged_rod", name = "Emberforged Rod", price = 60000, levelReq = 28, shop = "emberfang",
		luck = 65, lureSpeed = 1.6, control = 38, resilience = 40, maxWeight = 2500, castRange = 90,
		color1 = rgb(220, 80, 40), color2 = rgb(60, 50, 50), description = "Still glowing from the forge." },
	{ id = "frostbound_rod", name = "Frostbound Rod", price = 75000, levelReq = 32, shop = "frostmere",
		luck = 72, lureSpeed = 1.65, control = 45, resilience = 42, maxWeight = 3000, castRange = 95,
		color1 = rgb(180, 230, 255), color2 = rgb(80, 120, 200), description = "Cold enough to numb your fingers." },
	{ id = "abyssal_rod", name = "Abyssal Rod", price = 150000, levelReq = 40, shop = "abyss",
		luck = 85, lureSpeed = 1.75, control = 55, resilience = 55, maxWeight = 6000, castRange = 100,
		color1 = rgb(50, 30, 90), color2 = rgb(150, 90, 255), description = "Something at the bottom wanted you to have it." },
	{ id = "lumen_rod", name = "Lumen Rod", price = 400000, levelReq = 50, shop = "lumenveil",
		luck = 110, lureSpeed = 2.0, control = 70, resilience = 70, maxWeight = 15000, castRange = 110,
		color1 = rgb(255, 250, 200), color2 = rgb(120, 255, 230), description = "A rod made of captured starlight." },
}

RodData.List = LIST
RodData.ById = {} :: { [string]: RodDef }
for _, rod in ipairs(RodData.List) do
	RodData.ById[rod.id] = rod
end

RodData.DefaultRod = "twig_rod"

function RodData.Get(id: string?): RodDef
	return (if id then RodData.ById[id] else nil) or RodData.ById[RodData.DefaultRod]
end

return RodData
