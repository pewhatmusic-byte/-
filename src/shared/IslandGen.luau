--!strict
-- Procedural island sampler. Deterministic, so the server (map building, zone validation) and the
-- client (cast preview) agree on exactly what is land and what is water.

local Config = require(script.Parent.Config)
local Types = require(script.Parent.Types)

type IslandDef = Types.IslandDef

local IslandGen = {}

export type Zone = "land" | "ocean" | "pond" | "river"

local HEIGHT_STEP = Config.HeightStep
local riverLengthCache: { [string]: number } = {}

local function quantize(h: number): number
	return math.floor(h / HEIGHT_STEP) * HEIGHT_STEP
end

-- Island edge radius at a given angle (wobbly outline).
function IslandGen.RadiusAt(def: IslandDef, angle: number): number
	local s = def.seed * 0.013
	local n = math.noise(math.cos(angle) * 1.6 + s, math.sin(angle) * 1.6 + s, s)
	return def.radius * (1 + def.shapeWobble * n)
end

-- Raw land height ignoring pond/river carving. lx/lz are relative to the island centre.
local function baseHeight(def: IslandDef, lx: number, lz: number): number
	local d = math.sqrt(lx * lx + lz * lz)
	local angle = math.atan2(lz, lx)
	local r = IslandGen.RadiusAt(def, angle)
	local t = d / r
	local seed = def.seed
	local n = math.noise((lx + seed) / def.noiseScale, (lz - seed) / def.noiseScale, seed * 0.001)
	if t < 1 then
		local dome = 1 - t * t
		return dome * def.peakHeight + n * def.noiseHeight + 1
	end
	local drop = (d - r) * def.seaSlope
	return math.max(-1 - drop + n * 1.5, Config.SeaFloorY + 2)
end

local function riverLength(def: IslandDef): number
	local cached = riverLengthCache[def.id]
	if cached then
		return cached
	end
	local pond, river = def.pond, def.river
	if not pond or not river then
		return 0
	end
	local dirX, dirZ = math.cos(river.angle), math.sin(river.angle)
	local length = pond.radius
	local maxLen = def.radius * 1.6
	while length < maxLen do
		local h = baseHeight(def, pond.offset.X + dirX * length, pond.offset.Z + dirZ * length)
		if h < -1.5 then
			break
		end
		length += 2
	end
	length += 6 -- run a little way into the sea so the mouth is open
	riverLengthCache[def.id] = length
	return length
end

-- Returns (quantized ground height, zone) at a world XZ position.
function IslandGen.Sample(def: IslandDef, wx: number, wz: number): (number, Zone)
	local lx, lz = wx - def.center.X, wz - def.center.Z
	local h = baseHeight(def, lx, lz)
	local zone: Zone = if h < Config.OceanLevel then "ocean" else "land"

	local pond = def.pond
	if pond then
		local px, pz = lx - pond.offset.X, lz - pond.offset.Z
		local dp = math.sqrt(px * px + pz * pz)
		local bank = pond.waterY + 1.5
		if dp < pond.radius then
			h = pond.bedY
			zone = "pond"
		elseif dp < pond.radius + pond.rim then
			-- flat bank just above the water so the pond has a shoreline, not a crater
			h = bank
		elseif dp < pond.radius + pond.rim + 10 and h > bank then
			local t = (dp - pond.radius - pond.rim) / 10
			h = bank + (h - bank) * t
		end

		local river = def.river
		if river and zone ~= "pond" then
			local dirX, dirZ = math.cos(river.angle), math.sin(river.angle)
			local along = px * dirX + pz * dirZ
			local perp = math.abs(-px * dirZ + pz * dirX)
			local length = riverLength(def)
			local wobble = math.noise(along / 9, def.seed * 0.02, 0) * 2
			if along >= pond.radius - 2 and along <= length and perp + wobble < river.width / 2 then
				local tt = math.clamp((along - pond.radius) / math.max(length - pond.radius, 1), 0, 1)
				local bed = pond.bedY + (river.endBedY - pond.bedY) * tt
				if bed < h then
					h = bed
					zone = "river"
				end
			end
		end
	end

	return quantize(h), zone
end

-- Water surface height for a zone at a position (river water steps down toward the sea).
function IslandGen.WaterHeight(def: IslandDef, wx: number, wz: number, zone: string): number
	if zone == "pond" and def.pond then
		return def.pond.waterY
	elseif zone == "river" and def.pond and def.river then
		local pond, river = def.pond, def.river
		local px, pz = wx - def.center.X - pond.offset.X, wz - def.center.Z - pond.offset.Z
		local along = px * math.cos(river.angle) + pz * math.sin(river.angle)
		local length = riverLength(def)
		local tt = math.clamp((along - pond.radius) / math.max(length - pond.radius, 1), 0, 1)
		return IslandGen.RiverStepHeight(def, tt)
	end
	return Config.OceanLevel
end

-- Stepped river surface: waterY -> ... -> ocean level in 4-stud drops (matches terrain voxels).
function IslandGen.RiverStepHeight(def: IslandDef, tt: number): number
	local pond = def.pond
	if not pond then
		return Config.OceanLevel
	end
	local steps = math.max(1, math.floor(pond.waterY / 4))
	local k = math.floor(tt * (steps + 0.0001))
	return math.max(pond.waterY - k * 4, Config.OceanLevel)
end

function IslandGen.RiverLength(def: IslandDef): number
	return riverLength(def)
end

-- Ground is built as CellSize columns sampled at cell centres; snapping reproduces the visible height.
function IslandGen.SnapToCell(def: IslandDef, wx: number, wz: number): (number, number)
	local cell = Config.CellSize
	local sx = def.center.X + math.floor((wx - def.center.X) / cell + 0.5) * cell
	local sz = def.center.Z + math.floor((wz - def.center.Z) / cell + 0.5) * cell
	return sx, sz
end

-- Height and zone of the ground column actually built under a world position.
function IslandGen.SampleBuilt(def: IslandDef, wx: number, wz: number): (number, Zone)
	local sx, sz = IslandGen.SnapToCell(def, wx, wz)
	return IslandGen.Sample(def, sx, sz)
end

-- World position on the island at (angle, distance) with Y on the built ground.
function IslandGen.Polar(def: IslandDef, angle: number, distance: number): Vector3
	local x = def.center.X + math.cos(angle) * distance
	local z = def.center.Z + math.sin(angle) * distance
	local h = IslandGen.SampleBuilt(def, x, z)
	return Vector3.new(x, h, z)
end

-- Map a zone to the island's fishing location id (nil for land).
function IslandGen.LocationForZone(def: IslandDef, zone: string): string?
	if zone == "ocean" then
		return def.locations.ocean
	elseif zone == "pond" then
		return def.locations.pond
	elseif zone == "river" then
		return def.locations.river
	end
	return nil
end

return IslandGen
