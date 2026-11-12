--!strict
-- Builds the world at server start: ocean, sea floor, boundaries, every enabled island, the spawn
-- point and the lighting look (applied in code so manual Studio setups match the Rojo project).

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local IslandData = require(Shared:WaitForChild("IslandData"))

local MapBuilder = require(script.Parent.Parent:WaitForChild("Modules"):WaitForChild("MapBuilder"))

local WorldService = {}

local spawnCFrame = CFrame.new(0, 20, 0)

local function ensureChild(parent: Instance, className: string, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = parent
	return inst
end

local function setupLighting()
	Lighting.Ambient = Color3.fromRGB(92, 102, 128)
	Lighting.OutdoorAmbient = Color3.fromRGB(115, 128, 158)
	Lighting.Brightness = 2.6
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0
	Lighting.GeographicLatitude = 28
	Lighting.EnvironmentDiffuseScale = 0.45
	Lighting.EnvironmentSpecularScale = 0.25
	Lighting.ExposureCompensation = 0.1

	local atmosphere = ensureChild(Lighting, "Atmosphere", "Atmosphere") :: Atmosphere
	atmosphere.Density = 0.3
	atmosphere.Offset = 0.2
	atmosphere.Color = Color3.fromRGB(199, 219, 242)
	atmosphere.Decay = Color3.fromRGB(140, 158, 199)
	atmosphere.Glare = 0.25
	atmosphere.Haze = 1.4

	local bloom = ensureChild(Lighting, "BloomEffect", "Bloom") :: BloomEffect
	bloom.Intensity = 0.3
	bloom.Size = 24
	bloom.Threshold = 1.15

	local grade = ensureChild(Lighting, "ColorCorrectionEffect", "ColorGrade") :: ColorCorrectionEffect
	grade.Saturation = 0.18
	grade.Contrast = 0.08
	grade.TintColor = Color3.fromRGB(255, 250, 242)

	ensureChild(Lighting, "Sky", "Sky")
end

local function setupWater()
	local terrain = workspace.Terrain
	terrain.WaterColor = Color3.fromRGB(57, 160, 220)
	terrain.WaterTransparency = 0.35
	terrain.WaterReflectance = 0.15
	terrain.WaterWaveSize = 0.08
	terrain.WaterWaveSpeed = 8

	local half = Config.OceanSize / 2
	local depth = Config.OceanLevel - Config.SeaFloorY
	terrain:FillBlock(CFrame.new(0, Config.OceanLevel - depth / 2, 0), Vector3.new(Config.OceanSize, depth, Config.OceanSize), Enum.Material.Water)

	local floor = Instance.new("Part")
	floor.Name = "SeaFloor"
	floor.Anchored = true
	floor.Material = Enum.Material.SmoothPlastic
	floor.Color = Color3.fromRGB(150, 140, 110)
	floor.Size = Vector3.new(Config.OceanSize + 8, 4, Config.OceanSize + 8)
	floor.Position = Vector3.new(0, Config.SeaFloorY - 2, 0)
	floor.Parent = workspace

	-- Invisible walls keep swimmers inside the ocean.
	local walls = Instance.new("Folder")
	walls.Name = "Boundaries"
	walls.Parent = workspace
	local wallHeight = 200
	for _, spec in ipairs({
		{ Vector3.new(half, 0, 0), Vector3.new(4, wallHeight, Config.OceanSize) },
		{ Vector3.new(-half, 0, 0), Vector3.new(4, wallHeight, Config.OceanSize) },
		{ Vector3.new(0, 0, half), Vector3.new(Config.OceanSize, wallHeight, 4) },
		{ Vector3.new(0, 0, -half), Vector3.new(Config.OceanSize, wallHeight, 4) },
	}) do
		local wall = Instance.new("Part")
		wall.Name = "Wall"
		wall.Anchored = true
		wall.Transparency = 1
		wall.CanQuery = false
		wall.Size = spec[2]
		wall.Position = spec[1] + Vector3.new(0, wallHeight / 2 + Config.SeaFloorY, 0)
		wall.Parent = walls
	end
end

local function setupSpawn(world: Instance)
	local dockStart: Vector3? = nil
	for _, child in ipairs(world:GetChildren()) do
		local attr = child:GetAttribute("DockStart")
		if typeof(attr) == "Vector3" then
			dockStart = attr
			break
		end
	end
	local position = if dockStart then dockStart + Vector3.new(0, 1, 0) else Vector3.new(0, 20, 0)
	spawnCFrame = CFrame.new(position)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.Transparency = 1
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.Position = position
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Parent = workspace
end

function WorldService.GetSpawnCFrame(): CFrame
	return spawnCFrame
end

function WorldService.Init()
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end
	for _, child in ipairs(workspace:GetChildren()) do
		if child:IsA("SpawnLocation") then
			child:Destroy()
		end
	end

	setupLighting()
	setupWater()

	local world = Instance.new("Folder")
	world.Name = "World"
	world.Parent = workspace
	local effects = Instance.new("Folder")
	effects.Name = "Effects"
	effects.Parent = workspace

	for _, def in ipairs(IslandData.Enabled()) do
		MapBuilder.BuildIsland(def, world)
	end
	setupSpawn(world)
end

return WorldService
