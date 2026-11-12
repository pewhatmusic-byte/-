--!strict
-- Island definitions. Only `enabled` islands are built. Angles are in the XZ plane (0 = +X, 90 deg = +Z).

local Types = require(script.Parent.Types)
type IslandDef = Types.IslandDef

local rgb = Color3.fromRGB

local IslandData = {}

local LIST: { IslandDef } = {
	{
		id = "mossbell",
		name = "Mossbell Isle",
		enabled = true,
		center = Vector3.new(0, 0, 0),
		radius = 74,
		seed = 1337,
		shapeWobble = 0.22,
		peakHeight = 15,
		noiseScale = 42,
		noiseHeight = 3,
		seaSlope = 0.55,
		shallowsRadius = 112,
		pond = { offset = Vector3.new(16, 0, -12), radius = 15, rim = 5, bedY = 3, waterY = 8 },
		river = { angle = math.rad(150), width = 8, endBedY = -4.5 },
		locations = { ocean = "mossbell_shallows", pond = "mossbell_pond", river = "mossbell_brook" },
		palette = {
			grass = rgb(106, 190, 92),
			grassDark = rgb(84, 160, 78),
			sand = rgb(236, 214, 150),
			dirt = rgb(150, 108, 70),
			rock = rgb(128, 132, 142),
			rockDark = rgb(96, 100, 110),
			seabed = rgb(196, 178, 130),
			seabedDeep = rgb(150, 140, 110),
			riverbed = rgb(160, 150, 120),
			wood = rgb(150, 105, 62),
			woodDark = rgb(104, 70, 42),
			leaf = rgb(72, 168, 84),
			leafLight = rgb(118, 208, 104),
			pine = rgb(46, 128, 88),
			roof = rgb(196, 78, 62),
			roofAlt = rgb(74, 126, 178),
			wall = rgb(238, 226, 198),
			lantern = rgb(255, 210, 110),
			stone = rgb(170, 172, 176),
		},
		dock = { angle = math.rad(270), length = 40 },
		village = { angle = math.rad(240), distance = 40 },
		lighthouse = { angle = math.rad(30), distance = 62 },
		secrets = {
			{ id = "mossbell_lighthouse_chest", angle = math.rad(38), distance = 70, coins = 250, xp = 150 },
			{ id = "mossbell_pond_chest", angle = math.rad(95), distance = 24, coins = 120, xp = 100 },
		},
		npcs = {
			{
				id = "fishmonger", name = "Marlo", title = "Fishmonger", role = "Sell",
				angle = math.rad(276), distance = 60, facing = math.rad(100),
				style = { skin = rgb(224, 172, 130), shirt = rgb(70, 120, 180), pants = rgb(60, 60, 80), hat = rgb(240, 220, 160) },
				lines = { "Fresh catch? Let's see it!", "The harbour pays fair. Mostly." },
			},
			{
				id = "rodsmith", name = "Wren", title = "Rodsmith", role = "Shop",
				angle = math.rad(236), distance = 46, facing = math.rad(50),
				style = { skin = rgb(190, 140, 110), shirt = rgb(200, 90, 60), pants = rgb(90, 70, 50), hat = rgb(60, 50, 40) },
				lines = { "A good rod is half the catch.", "Bait's in the bucket. Don't ask what's in the bait." },
			},
			{
				id = "harbor_elder", name = "Old Tam", title = "Harbour Elder", role = "Quest",
				angle = math.rad(300), distance = 48, facing = math.rad(120),
				style = { skin = rgb(210, 160, 130), shirt = rgb(120, 140, 100), pants = rgb(80, 70, 60), hat = rgb(150, 150, 160) },
				lines = {
					"Still untangling my nets. Come back soon and I'll have work for you.",
					"They say the Belltower only rings in a night storm...",
					"Fish bite faster on the brook when it rains.",
				},
			},
		},
		treeDensity = 0.11,
		rockDensity = 0.035,
		treeVariants = { "Oak", "Oak", "Pine", "Palm" },
		discoveryXP = 100,
	},
}

IslandData.List = LIST
IslandData.ById = {} :: { [string]: IslandDef }
for _, def in ipairs(IslandData.List) do
	IslandData.ById[def.id] = def
end

function IslandData.Enabled(): { IslandDef }
	local out = {}
	for _, def in ipairs(IslandData.List) do
		if def.enabled then
			table.insert(out, def)
		end
	end
	return out
end

return IslandData
