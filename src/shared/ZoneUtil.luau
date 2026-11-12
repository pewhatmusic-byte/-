--!strict
-- Answers "what fishing location is at this world position?" for both server and client.

local Config = require(script.Parent.Config)
local IslandData = require(script.Parent.IslandData)
local IslandGen = require(script.Parent.IslandGen)
local Types = require(script.Parent.Types)

local ZoneUtil = {}

export type ZoneInfo = {
	locationId: string,
	waterY: number,
	island: Types.IslandDef?,
	zone: string, -- "ocean" | "pond" | "river"
}

-- Returns nil when the position is on land (or outside the world).
function ZoneUtil.LocationAt(position: Vector3): ZoneInfo?
	local half = Config.OceanSize / 2
	if math.abs(position.X) > half or math.abs(position.Z) > half then
		return nil
	end

	for _, def in ipairs(IslandData.Enabled()) do
		local dx, dz = position.X - def.center.X, position.Z - def.center.Z
		if dx * dx + dz * dz <= def.shallowsRadius * def.shallowsRadius then
			-- judge land vs water by the ground column the player can actually see
			local height, zone = IslandGen.SampleBuilt(def, position.X, position.Z)
			local locationId = IslandGen.LocationForZone(def, zone)
			if not locationId then
				return nil
			end
			local waterY = IslandGen.WaterHeight(def, position.X, position.Z, zone)
			if height >= waterY then
				return nil
			end
			return { locationId = locationId, waterY = waterY, island = def, zone = zone }
		end
	end

	return { locationId = "open_sea", waterY = Config.OceanLevel, island = nil, zone = "ocean" }
end

-- Which island (if any) the position belongs to, used for island discovery.
function ZoneUtil.IslandAt(position: Vector3): Types.IslandDef?
	for _, def in ipairs(IslandData.Enabled()) do
		local dx, dz = position.X - def.center.X, position.Z - def.center.Z
		if dx * dx + dz * dz <= def.radius * def.radius * 1.3 then
			return def
		end
	end
	return nil
end

return ZoneUtil
