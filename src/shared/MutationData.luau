--!strict
-- Fish mutations. A fish can have at most one mutation plus (independently) the Shiny variant.
-- Mutations are checked rarest-first; `chance` is the per-catch probability.

local Types = require(script.Parent.Types)
type MutationDef = Types.MutationDef

local rgb = Color3.fromRGB

local MutationData = {}

MutationData.ShinyChance = 1 / 64
MutationData.ShinyValueMult = 2
MutationData.ShinyXPMult = 1.5

local LIST: { MutationDef } = {
	{ id = "Prismatic", chance = 1 / 2500, valueMult = 12, xpMult = 4, color = rgb(255, 120, 220), description = "Shifts through every colour of the rainbow." },
	{ id = "Golden", chance = 1 / 400, valueMult = 5, xpMult = 2.5, color = rgb(255, 208, 70), description = "Scales of pure gold." },
	{ id = "Albino", chance = 1 / 160, valueMult = 2.5, xpMult = 1.8, color = rgb(245, 240, 240), description = "Pale as moonlight." },
	{ id = "Glowing", chance = 1 / 90, valueMult = 3, xpMult = 2, color = rgb(130, 255, 200), requiresTime = "Night", description = "Only glows after dark." },
	{ id = "Stormtouched", chance = 1 / 45, valueMult = 2.5, xpMult = 1.8, color = rgb(120, 170, 255), requiresWeather = "Storm", description = "Crackles faintly with static." },
	{ id = "Mossy", chance = 1 / 70, valueMult = 1.8, xpMult = 1.4, color = rgb(120, 180, 80), requiresKind = { "Pond", "River" }, description = "Covered in soft green moss." },
	{ id = "Frostbitten", chance = 1 / 60, valueMult = 2.2, xpMult = 1.6, color = rgb(190, 235, 255), requiresKind = { "Ice" }, description = "Rimmed with frost." },
	{ id = "Charred", chance = 1 / 60, valueMult = 2.2, xpMult = 1.6, color = rgb(90, 60, 50), requiresKind = { "Volcanic" }, description = "Still warm to the touch." },
	{ id = "Abyssal", chance = 1 / 60, valueMult = 2.5, xpMult = 1.7, color = rgb(60, 40, 110), requiresKind = { "DeepSea" }, description = "Darkness clings to it." },
	{ id = "Hollow", chance = 1 / 60, valueMult = 2.5, xpMult = 1.7, color = rgb(110, 110, 130), requiresKind = { "Cave" }, description = "Echoes when it moves." },
	{ id = "Starlit", chance = 1 / 60, valueMult = 3, xpMult = 2, color = rgb(230, 220, 255), requiresKind = { "Mystic" }, description = "Tiny stars drift around it." },
}

MutationData.List = LIST
MutationData.ById = {} :: { [string]: MutationDef }
for _, mutation in ipairs(MutationData.List) do
	MutationData.ById[mutation.id] = mutation
end

function MutationData.Get(id: string?): MutationDef?
	if not id then
		return nil
	end
	return MutationData.ById[id]
end

return MutationData
