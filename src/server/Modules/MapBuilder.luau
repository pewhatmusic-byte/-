--!strict
-- Turns an IslandDef into parts: terraced ground columns (run-merged for low part counts),
-- terrain water for the sea / pond / stepped river, then hands over to MapDecor for props.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local IslandGen = require(Shared:WaitForChild("IslandGen"))
local Types = require(Shared:WaitForChild("Types"))

local MapDecor = require(script.Parent:WaitForChild("MapDecor"))

local MapBuilder = {}

local FLOOR_Y = Config.SeaFloorY - 2

local function groundColor(def: Types.IslandDef, h: number, zone: string, x: number, z: number): Color3
	local palette = def.palette
	if zone == "pond" then
		return palette.dirt
	elseif zone == "river" then
		return palette.riverbed
	elseif h < Config.OceanLevel then
		return if h < -8 then palette.seabedDeep else palette.seabed
	elseif h < 3 then
		return palette.sand
	elseif h < 13.5 then
		local patch = math.noise(x / 11 + def.seed, z / 11, def.seed * 0.1)
		return if patch > 0.12 then palette.grassDark else palette.grass
	end
	return if math.noise(x / 7, z / 7, def.seed) > 0 then palette.rock else palette.rockDark
end

local function makeColumn(parent: Instance, x: number, z: number, width: number, height: number, color: Color3)
	local part = Instance.new("Part")
	part.Name = "Ground"
	part.Anchored = true
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Color = color
	part.Size = Vector3.new(width, height - FLOOR_Y, Config.CellSize)
	part.CFrame = CFrame.new(x, (height + FLOOR_Y) / 2, z)
	part.Parent = parent
end

-- One merged part per run of equal-height, equal-colour cells along X.
local function buildGround(def: Types.IslandDef, parent: Instance): number
	local cell = Config.CellSize
	local radius = def.shallowsRadius
	local n = math.ceil(radius / cell)
	local folder = Instance.new("Folder")
	folder.Name = "Ground"
	folder.Parent = parent

	local count = 0
	for iz = -n, n do
		local z = def.center.Z + iz * cell
		local runStart: number? = nil
		local runLen, runHeight = 0, 0
		local runColor = Color3.new()

		local function flush()
			if runStart == nil then
				return
			end
			local firstX = def.center.X + (runStart :: number) * cell
			local centerX = firstX + (runLen - 1) * cell / 2
			makeColumn(folder, centerX, z, runLen * cell, runHeight, runColor)
			count += 1
			runStart = nil
		end

		for ix = -n, n do
			local x = def.center.X + ix * cell
			local dx, dz = x - def.center.X, z - def.center.Z
			if dx * dx + dz * dz > radius * radius then
				flush()
				continue
			end
			local h, zone = IslandGen.Sample(def, x, z)
			local color = groundColor(def, h, zone, x, z)
			if runStart ~= nil and h == runHeight and color == runColor then
				runLen += 1
			else
				flush()
				runStart = ix
				runLen = 1
				runHeight = h
				runColor = color
			end
		end
		flush()
	end
	return count
end

local function fillWater(def: Types.IslandDef)
	local terrain = workspace.Terrain
	local pond = def.pond
	if pond then
		local center = def.center + pond.offset
		local bottom = pond.bedY - 1
		local height = pond.waterY - bottom
		terrain:FillCylinder(CFrame.new(center.X, bottom + height / 2, center.Z), height, pond.radius + 1, Enum.Material.Water)

		local river = def.river
		if river then
			local length = IslandGen.RiverLength(def)
			local steps = math.max(1, math.floor(pond.waterY / 4))
			local dirX, dirZ = math.cos(river.angle), math.sin(river.angle)
			local span = length - pond.radius
			for k = 0, steps - 1 do
				local t0, t1 = k / steps, (k + 1) / steps
				local a0 = pond.radius + t0 * span - 1
				local a1 = pond.radius + t1 * span + 1
				local surface = IslandGen.RiverStepHeight(def, t0 + 0.001)
				local riverBottom = river.endBedY - 2
				local mid = (a0 + a1) / 2
				local position = Vector3.new(center.X + dirX * mid, (surface + riverBottom) / 2, center.Z + dirZ * mid)
				local cframe = CFrame.new(position) * CFrame.Angles(0, -river.angle, 0)
				terrain:FillBlock(cframe, Vector3.new(a1 - a0, surface - riverBottom, river.width - 1), Enum.Material.Water)
			end
		end
	end
end

-- Builds one island into `parent` and returns its Model.
function MapBuilder.BuildIsland(def: Types.IslandDef, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = def.name
	model:SetAttribute("IslandId", def.id)

	local columns = buildGround(def, model)
	fillWater(def)
	MapDecor.Populate(def, model)

	model.Parent = parent
	print(string.format("[MapBuilder] Built %s (%d ground parts, %d total instances)", def.name, columns, #model:GetDescendants()))
	return model
end

return MapBuilder
