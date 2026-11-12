--!strict
-- Fishing locations. Each location has an exclusive fish pool (see FishData.locations).

local Types = require(script.Parent.Types)
type LocationDef = Types.LocationDef

local LocationData = {}

local LIST: { LocationDef } = {
	-- Mossbell Isle (starter island, MVP)
	{ id = "mossbell_shallows", name = "Mossbell Shallows", kind = "Ocean", island = "mossbell", description = "Warm, sandy water around the harbour." },
	{ id = "mossbell_pond", name = "Bellflower Pond", kind = "Pond", island = "mossbell", description = "A still pond on the hill above the village." },
	{ id = "mossbell_brook", name = "Tumble Brook", kind = "River", island = "mossbell", description = "A stepped stream running from the pond to the sea." },
	{ id = "open_sea", name = "Open Sea", kind = "Ocean", island = "", description = "Deep blue water between the islands." },

	-- Later islands (data is ready; enable the islands in IslandData when you build them)
	{ id = "brinewake_reef", name = "Brinewake Reef", kind = "Ocean", island = "brinewake", description = "Bright coral shelves teeming with colour." },
	{ id = "gloomhollow_cave", name = "Gloomhollow Pools", kind = "Cave", island = "gloomhollow", description = "Pitch-black cave pools lit by glowworms." },
	{ id = "emberfang_lagoon", name = "Emberfang Lagoon", kind = "Volcanic", island = "emberfang", description = "Steaming water beneath a smoking peak." },
	{ id = "frostmere_bay", name = "Frostmere Bay", kind = "Ice", island = "frostmere", description = "Ice floes drift across a freezing bay." },
	{ id = "abyssal_shelf", name = "The Abyssal Shelf", kind = "DeepSea", island = "", description = "Where the sea floor drops into darkness." },
	{ id = "lumenveil_shore", name = "Lumenveil Shore", kind = "Mystic", island = "lumenveil", description = "Glowing sand and water that hums softly." },
	{ id = "drowned_belltower", name = "The Drowned Belltower", kind = "Ocean", island = "", description = "A sunken tower whose bell still tolls in storms." },
}

LocationData.List = LIST
LocationData.ById = {} :: { [string]: LocationDef }
for _, loc in ipairs(LocationData.List) do
	LocationData.ById[loc.id] = loc
end

function LocationData.Get(id: string): LocationDef?
	return LocationData.ById[id]
end

function LocationData.Name(id: string?): string
	local loc = if id then LocationData.ById[id] else nil
	return if loc then loc.name else "Unknown Waters"
end

function LocationData.Kind(id: string?): Types.LocationKind
	local loc = if id then LocationData.ById[id] else nil
	return if loc then loc.kind else "Ocean"
end

return LocationData
