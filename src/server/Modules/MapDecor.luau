--!strict
-- Blocky pixel-style props for one island: trees, rocks, reeds, flowers, village, dock, lighthouse,
-- treasure chests, NPC bodies and signs. Every prop is a Model of anchored SmoothPlastic Parts/WedgeParts
-- (no meshes, textures, decals or SurfaceGuis) and placement is deterministic for a given island seed.
--
-- Ground positions passed to builders are surface level. MapBuilder samples its 4-stud ground columns at
-- cell centres, so every height read here snaps to that grid first to match the surface that really exists.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local IslandGen = require(Shared:WaitForChild("IslandGen"))
local Types = require(Shared:WaitForChild("Types"))
local Util = require(Shared:WaitForChild("Util"))

type IslandDef = Types.IslandDef
type Palette = { [string]: Color3 }
type PartProps = { CanCollide: boolean?, CastShadow: boolean?, Transparency: number? }
type Circle = { x: number, z: number, r: number }

type Scene = {
	def: IslandDef,
	rng: Random,
	palette: Palette,
	npcs: { Circle }, -- NPC feet positions (r = 0)
	props: { Circle }, -- footprints of village props, for overlap checks between props
	keepClear: { Circle }, -- zones the scatter passes (trees, rocks, flowers) must avoid
	dockA: Vector3?,
	dockB: Vector3?,
}

local MapDecor = {}

-- Tuning ---------------------------------------------------------------------------------------------

local CELL = Config.CellSize
local SINK = 3.2 -- trunks and posts reach this far below their base so terrain steps never expose a gap
local SHORE_HEIGHT = 1.5 -- ground below this counts as the waterline

local DECK_Y = Config.OceanLevel + 3
local DECK_LIFT = 0.05 -- keeps planks from z-fighting with a ground column that tops out at deck height
local DECK_WIDTH = 8
local PLANK_LENGTH = 4
local PLANK_THICKNESS = 0.6
local POST_SPACING = 8

local NPC_CLEAR = 6 -- village props keep their edges this far from NPCs
local NPC_SCATTER_CLEAR = 9 -- trees, rocks and flowers keep their centres this far
local DOCK_CLEAR = 8
local VILLAGE_CLEAR = 10
local CHEST_CLEAR = 6
local LIGHTHOUSE_CLEAR = 7
local PROP_MARGIN = 2.5

local BUILD_MIN_HEIGHT = 3 -- buildings stay off the beach
local BUILD_MAX_SLOPE = 4.5 -- biggest ground height spread a plinth is asked to hide
local HUT_RADIUS = 5.2
local HUT_RING = 12.5
local HUT_FOUNDATION = 6
local STALL_RADIUS = 3.4
local WELL_RADIUS = 2.6
local SIGN_RADIUS = 3.8
local LIGHTHOUSE_HALF = 5.2
local LIGHTHOUSE_FOUNDATION = 6

local MISSING = Color3.fromRGB(255, 0, 255) -- shows up when a palette key is absent
local GLASS = Color3.fromRGB(176, 224, 242)
local LAMP_GLASS = Color3.fromRGB(255, 244, 196)
local GOLD = Color3.fromRGB(255, 205, 72)
local WATER = Color3.fromRGB(70, 150, 215)
local FLOWER_COLORS = {
	Color3.fromRGB(255, 120, 170),
	Color3.fromRGB(255, 220, 80),
	Color3.fromRGB(250, 248, 240),
	Color3.fromRGB(170, 130, 240),
}

local SOFT: PartProps = { CanCollide = false }
local TINY: PartProps = { CanCollide = false, CastShadow = false }
local SMALL: PartProps = { CastShadow = false }

-- Part helpers ---------------------------------------------------------------------------------------

local function col(palette: Palette, key: string): Color3
	return palette[key] or MISSING
end

local function configure(part: BasePart, name: string, size: Vector3, cframe: CFrame, color: Color3, props: PartProps?)
	part.Name = name
	part.Anchored = true
	part.Material = Enum.Material.SmoothPlastic
	part.Reflectance = 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	if props then
		if props.CanCollide == false then
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
		end
		if props.CastShadow == false then
			part.CastShadow = false
		end
		if props.Transparency then
			part.Transparency = props.Transparency
		end
	end
end

local function makePart(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, props: PartProps?): Part
	local part = Instance.new("Part")
	configure(part, name, size, cframe, color, props)
	part.Parent = parent
	return part
end

-- WedgePart: tall face on local +Z, slope falling to local -Z.
local function makeWedge(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, props: PartProps?): WedgePart
	local part = Instance.new("WedgePart")
	configure(part, name, size, cframe, color, props)
	part.Parent = parent
	return part
end

local function newFolder(parent: Instance, name: string): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

-- Two wedges back to back make a closed gable roof (ridge along local X, base on local y = 0).
local function gableRoof(parent: Instance, origin: CFrame, length: number, span: number, height: number, color: Color3)
	local half = span / 2
	local size = Vector3.new(length, height, half)
	makeWedge(parent, "RoofFront", size, origin * CFrame.new(0, height / 2, -half / 2), color)
	makeWedge(parent, "RoofBack", size, origin * CFrame.new(0, height / 2, half / 2) * CFrame.Angles(0, math.pi, 0), color)
	local ridgeColor = Util.Darken(color, 0.22)
	makePart(parent, "RoofRidge", Vector3.new(length + 0.3, 0.4, 0.8), origin * CFrame.new(0, height - 0.05, 0), ridgeColor, SMALL)
end

-- Terrain helpers --------------------------------------------------------------------------------------

local function snap(v: number, origin: number): number
	return origin + math.floor((v - origin) / CELL + 0.5) * CELL
end

local function groundAt(def: IslandDef, x: number, z: number): (number, IslandGen.Zone)
	return IslandGen.Sample(def, snap(x, def.center.X), snap(z, def.center.Z))
end

-- Lowest and highest land ground under a rotated rectangle (centre, corners, edge midpoints), and whether every
-- sample is land. Water samples are ignored for the heights so a pond edge cannot drag a prop into the pit.
local function groundSpan(def: IslandDef, origin: CFrame, halfX: number, halfZ: number): (number, number, boolean)
	local lo, hi, allLand = math.huge, -math.huge, true
	local anyLo, anyHi = math.huge, -math.huge
	for _, ox in ipairs({ -halfX, 0, halfX }) do
		for _, oz in ipairs({ -halfZ, 0, halfZ }) do
			local p = origin * Vector3.new(ox, 0, oz)
			local h, zone = groundAt(def, p.X, p.Z)
			anyLo, anyHi = math.min(anyLo, h), math.max(anyHi, h)
			if zone == "land" then
				lo, hi = math.min(lo, h), math.max(hi, h)
			else
				allLand = false
			end
		end
	end
	if lo > hi then
		return anyLo, anyHi, false
	end
	return lo, hi, allLand
end

-- Sea floor under a dock post: the ground column if one was built there, else the global sea floor part.
local function seabedAt(def: IslandDef, x: number, z: number): number
	local dx, dz = x - def.center.X, z - def.center.Z
	if dx * dx + dz * dz > def.shallowsRadius * def.shallowsRadius then
		return Config.SeaFloorY
	end
	return (groundAt(def, x, z))
end

local function distToSegment(px: number, pz: number, a: Vector3, b: Vector3): number
	local abx, abz = b.X - a.X, b.Z - a.Z
	local len2 = abx * abx + abz * abz
	local t = 0
	if len2 > 0 then
		t = math.clamp(((px - a.X) * abx + (pz - a.Z) * abz) / len2, 0, 1)
	end
	local dx, dz = px - (a.X + abx * t), pz - (a.Z + abz * t)
	return math.sqrt(dx * dx + dz * dz)
end

local function isClear(scene: Scene, x: number, z: number): boolean
	for _, c in ipairs(scene.keepClear) do
		local dx, dz = x - c.x, z - c.z
		if dx * dx + dz * dz < c.r * c.r then
			return false
		end
	end
	local a, b = scene.dockA, scene.dockB
	if a and b and distToSegment(x, z, a, b) < DOCK_CLEAR then
		return false
	end
	return true
end

-- Public builders --------------------------------------------------------------------------------------

function MapDecor.Tree(parent: Instance, position: Vector3, palette: Palette, rng: Random, variant: string): Model
	local model = Instance.new("Model")
	model.Name = "Tree"
	local wood = col(palette, "wood")
	local leaf, leafLight = col(palette, "leaf"), col(palette, "leafLight")

	if variant == "Palm" then
		local height = rng:NextNumber(7, 9.5)
		local lean = rng:NextNumber(0, math.pi * 2)
		local tilt = math.rad(rng:NextNumber(5, 11))
		local axis = Vector3.new(math.sin(lean), 0, -math.cos(lean))
		local along = Vector3.new(math.cos(lean) * math.sin(tilt), math.cos(tilt), math.sin(lean) * math.sin(tilt))
		local center = position + along * ((height - SINK) / 2)
		makePart(model, "Trunk", Vector3.new(1, height + SINK, 1), CFrame.new(center) * CFrame.fromAxisAngle(axis, tilt), wood)

		local crown = position + along * height
		makePart(model, "Crown", Vector3.new(1.4, 1.1, 1.4), CFrame.new(crown) * CFrame.Angles(0, lean, 0), leaf, SOFT)
		local fronds = rng:NextInteger(4, 5)
		local start = rng:NextNumber(0, math.pi * 2)
		for i = 1, fronds do
			local yaw = start + (i - 1) * math.pi * 2 / fronds + rng:NextNumber(-0.2, 0.2)
			local droop = math.rad(rng:NextNumber(14, 28))
			local reach = rng:NextNumber(4.2, 5.2)
			local out = Vector3.new(math.cos(droop) * math.cos(yaw), -math.sin(droop), math.cos(droop) * math.sin(yaw))
			local mid = crown + out * (reach / 2) + Vector3.new(0, 0.3, 0)
			makePart(model, "Frond", Vector3.new(1.6, 0.3, reach), CFrame.lookAt(mid, mid + out), if i % 2 == 1 then leaf else leafLight, SOFT)
		end
		for _, side in ipairs({ -1, 1 }) do
			local nutAt = CFrame.new(crown + Vector3.new(side * 0.55, -0.8, 0.2 * side))
			makePart(model, "Coconut", Vector3.new(0.6, 0.6, 0.6), nutAt, col(palette, "woodDark"), TINY)
		end
	else
		local height = rng:NextNumber(4, 7)
		local trunkAt = CFrame.new(position.X, position.Y + (height - SINK) / 2, position.Z)
		makePart(model, "Trunk", Vector3.new(1.4, height + SINK, 1.4), trunkAt, wood)
		local top = position.Y + height

		if variant == "Pine" then
			local widths = { rng:NextNumber(5.8, 6.8), 0, 0 }
			widths[2], widths[3] = widths[1] * 0.72, widths[1] * 0.46
			local pine = col(palette, "pine")
			local y = top - 2.4 -- foliage starts low enough to leave a bare trunk, and always covers the trunk top
			for i, w in ipairs(widths) do
				local needlesAt = CFrame.new(position.X, y + 0.7, position.Z) * CFrame.Angles(0, rng:NextNumber(0, math.pi / 2), 0)
				makePart(model, "Needles", Vector3.new(w, 1.4, w), needlesAt, pine, SOFT)
				y += 1.15
			end
			makePart(model, "Tip", Vector3.new(1.1, 1.2, 1.1), CFrame.new(position.X, y + 0.55, position.Z), Util.Lighten(pine, 0.12), TINY)
		else
			local base = rng:NextNumber(4.4, 5.4)
			local sizes = { base, base * 0.74, base * 0.5 }
			local layers = rng:NextInteger(2, 3)
			local y = top - 0.9
			for i = 1, layers do
				local s = sizes[i]
				local jitter = if i == 1 then 0.3 else 0.55
				local ox, oz = rng:NextNumber(-jitter, jitter), rng:NextNumber(-jitter, jitter)
				local canopyAt = CFrame.new(position.X + ox, y + s / 2, position.Z + oz) * CFrame.Angles(0, rng:NextNumber(0, math.pi / 2), 0)
				makePart(model, "Canopy", Vector3.new(s, s, s), canopyAt, if i % 2 == 1 then leaf else leafLight, SOFT)
				y += s - 0.8
			end
		end
	end

	model.Parent = parent
	return model
end

function MapDecor.Rock(parent: Instance, position: Vector3, palette: Palette, rng: Random, scale: number): Model
	local model = Instance.new("Model")
	model.Name = "Rock"
	local colors = { col(palette, "rock"), col(palette, "rockDark") }
	local count = rng:NextInteger(1, 3)
	for i = 1, count do
		local sx, sy, sz = scale * rng:NextNumber(0.9, 1.6), scale * rng:NextNumber(0.7, 1.2), scale * rng:NextNumber(0.9, 1.6)
		local ox, oz, lift = 0, 0, 0
		if i > 1 then
			ox, oz, lift = rng:NextNumber(-0.5, 0.5) * scale, rng:NextNumber(-0.5, 0.5) * scale, rng:NextNumber(0, 0.4) * scale
		end
		local tilt = CFrame.Angles(rng:NextNumber(-0.25, 0.25), rng:NextNumber(0, math.pi), rng:NextNumber(-0.25, 0.25))
		local stoneAt = CFrame.new(position.X + ox, position.Y - 0.5 + sy / 2 + lift, position.Z + oz) * tilt
		makePart(model, "Stone", Vector3.new(sx, sy, sz), stoneAt, colors[(i - 1) % 2 + 1])
	end
	model.Parent = parent
	return model
end

-- `roofColor` defaults to the palette roof. The cframe origin is the highest ground under the hut; the front (door) is -Z.
function MapDecor.Hut(parent: Instance, cframe: CFrame, palette: Palette, rng: Random, roofColor: Color3?): Model
	local model = Instance.new("Model")
	model.Name = "Hut"

	local width = rng:NextNumber(5.6, 6.8)
	local depth = rng:NextNumber(4.8, 5.8)
	local wallHeight = rng:NextNumber(4.0, 4.6)
	local base = 0.5 -- stone base course above the origin
	local frontZ = -depth / 2
	local wood, woodDark = col(palette, "wood"), col(palette, "woodDark")
	local roof = roofColor or col(palette, "roof")

	local plinthAt = cframe * CFrame.new(0, (base - HUT_FOUNDATION) / 2, 0)
	makePart(model, "Plinth", Vector3.new(width + 0.8, HUT_FOUNDATION + base, depth + 0.8), plinthAt, col(palette, "stone"))
	local wallsAt = cframe * CFrame.new(0, base + wallHeight / 2, 0)
	makePart(model, "Walls", Vector3.new(width, wallHeight, depth), wallsAt, col(palette, "wall"))

	-- Door on the left, window on the right (the door frame leaves ~0.5 stud of wall at the corner).
	local doorX = -width * 0.18
	makePart(model, "DoorFrame", Vector3.new(2.5, 3.5, 0.2), cframe * CFrame.new(doorX, base + 1.75, frontZ - 0.05), wood, TINY)
	local doorColor = Util.Darken(woodDark, 0.2)
	makePart(model, "Door", Vector3.new(1.8, 3.0, 0.3), cframe * CFrame.new(doorX, base + 1.5, frontZ - 0.1), doorColor, TINY)
	makePart(model, "DoorKnob", Vector3.new(0.25, 0.25, 0.2), cframe * CFrame.new(doorX + 0.55, base + 1.45, frontZ - 0.3), GOLD, TINY)
	makePart(model, "Step", Vector3.new(2.6, 2.05, 1.2), cframe * CFrame.new(doorX, -0.475, frontZ - 0.7), woodDark, SMALL)

	local windowY = base + 2.5
	local function window(offset: Vector3, facing: number, withBox: boolean)
		local at = cframe * CFrame.new(offset) * CFrame.Angles(0, facing, 0) -- local -Z points out of the wall
		makePart(model, "WindowFrame", Vector3.new(1.7, 1.7, 0.2), at * CFrame.new(0, 0, -0.05), wood, TINY)
		makePart(model, "Window", Vector3.new(1.2, 1.2, 0.25), at * CFrame.new(0, 0, -0.12), GLASS, TINY)
		if withBox then
			local boxAt = at * CFrame.new(0, -1.1, -0.5)
			makePart(model, "FlowerBox", Vector3.new(1.8, 0.5, 0.7), boxAt, woodDark, TINY)
			makePart(model, "Greenery", Vector3.new(1.5, 0.3, 0.55), boxAt * CFrame.new(0, 0.3, 0), col(palette, "leafLight"), TINY)
			for i = -1, 1 do
				local pick = FLOWER_COLORS[rng:NextInteger(1, #FLOWER_COLORS)]
				makePart(model, "Flower", Vector3.new(0.35, 0.35, 0.35), boxAt * CFrame.new(i * 0.5, 0.6, 0), pick, TINY)
			end
		end
	end
	window(Vector3.new(width * 0.26, windowY, frontZ), 0, true)
	window(Vector3.new(width / 2, windowY, 0), -math.pi / 2, rng:NextNumber() < 0.5)
	window(Vector3.new(-width / 2, windowY, 0), math.pi / 2, false)

	local wallTop = base + wallHeight
	local span = depth + 1.8
	local roofHeight = span * 0.42
	gableRoof(model, cframe * CFrame.new(0, wallTop, 0), width + 1.4, span, roofHeight, roof)

	-- Chimney starts inside the roof so only the part above the slope shows.
	local side = if rng:NextNumber() < 0.5 then -1 else 1
	local chimneyHeight = roofHeight / 2 + 1.6
	local chimneyAt = cframe * CFrame.new(side * width * 0.25, wallTop + chimneyHeight / 2, span / 4)
	makePart(model, "Chimney", Vector3.new(1.1, chimneyHeight, 1.1), chimneyAt, col(palette, "stone"))
	local capAt = chimneyAt * CFrame.new(0, chimneyHeight / 2 + 0.1, 0)
	makePart(model, "ChimneyCap", Vector3.new(1.5, 0.3, 1.5), capAt, col(palette, "rockDark"), SMALL)

	model.Parent = parent
	return model
end

-- `sink` is how far the base reaches below `position` (docks pass a small value, terrain uses the default).
function MapDecor.Lantern(parent: Instance, position: Vector3, palette: Palette, sink: number?): Model
	local model = Instance.new("Model")
	model.Name = "Lantern"
	local depth = sink or SINK
	local woodDark = col(palette, "woodDark")
	local glowColor = col(palette, "lantern")
	local x, z = position.X, position.Z

	local footingAt = CFrame.new(x, position.Y + (0.4 - depth) / 2, z)
	makePart(model, "Footing", Vector3.new(1.3, depth + 0.4, 1.3), footingAt, col(palette, "stone"), SMALL)
	local postAt = CFrame.new(x, position.Y + (4.1 - depth) / 2, z)
	makePart(model, "Post", Vector3.new(0.5, depth + 4.1, 0.5), postAt, woodDark, SMALL)
	local glow = makePart(model, "Glow", Vector3.new(1.1, 1.3, 1.1), CFrame.new(x, position.Y + 4.65, z), glowColor, TINY)
	makePart(model, "Cap", Vector3.new(1.6, 0.3, 1.6), CFrame.new(x, position.Y + 5.45, z), woodDark, TINY)
	makePart(model, "CapTip", Vector3.new(0.6, 0.4, 0.6), CFrame.new(x, position.Y + 5.8, z), woodDark, TINY)

	local light = Instance.new("PointLight")
	light.Color = glowColor
	light.Brightness = 1.6
	light.Range = 14
	light.Shadows = false
	light.Parent = glow

	model.Parent = parent
	return model
end

-- `sink` is how far the stems reach below `position` (pond reeds root themselves on the pond bed).
function MapDecor.Reeds(parent: Instance, position: Vector3, palette: Palette, rng: Random, sink: number?): Model
	local model = Instance.new("Model")
	model.Name = "Reeds"
	local depth = sink or SINK
	local green = col(palette, "pine")
	local tipColor = col(palette, "woodDark")
	for _ = 1, rng:NextInteger(3, 5) do
		local height = rng:NextNumber(2, 3.5)
		local angle, radius = rng:NextNumber(0, math.pi * 2), rng:NextNumber(0.1, 0.9)
		local x, z = position.X + math.cos(angle) * radius, position.Z + math.sin(angle) * radius
		local shade = Util.Lighten(green, rng:NextNumber(0, 0.25))
		makePart(model, "Reed", Vector3.new(0.3, height + depth, 0.3), CFrame.new(x, position.Y + (height - depth) / 2, z), shade, TINY)
		makePart(model, "ReedTip", Vector3.new(0.38, 0.55, 0.38), CFrame.new(x, position.Y + height + 0.15, z), tipColor, TINY)
	end
	model.Parent = parent
	return model
end

-- The cframe origin is the top of the dirt mound the chest sits on; the clasp faces -Z.
function MapDecor.Chest(parent: Instance, cframe: CFrame, palette: Palette, secretId: string): Model
	local model = Instance.new("Model")
	model.Name = "Chest"
	local wood, woodDark = col(palette, "wood"), col(palette, "woodDark")

	makePart(model, "Mound", Vector3.new(4.2, 4, 3.2), cframe * CFrame.new(0, -2, 0), col(palette, "dirt"), SMALL)
	local base = makePart(model, "Base", Vector3.new(3, 1.5, 2), cframe * CFrame.new(0, 0.75, 0), wood)
	for _, side in ipairs({ -1, 1 }) do
		makePart(model, "Band", Vector3.new(0.3, 1.55, 2.1), cframe * CFrame.new(side * 1.05, 0.75, 0), woodDark, TINY)
	end
	makePart(model, "Lid", Vector3.new(3.2, 0.7, 2.2), cframe * CFrame.new(0, 1.85, 0), woodDark, SMALL)
	makePart(model, "LidTop", Vector3.new(2.7, 0.4, 1.8), cframe * CFrame.new(0, 2.4, 0), Util.Lighten(woodDark, 0.08), TINY)
	makePart(model, "Clasp", Vector3.new(0.6, 0.8, 0.3), cframe * CFrame.new(0, 1.6, -1.1), GOLD, TINY)

	model.PrimaryPart = base
	model:SetAttribute("SecretId", secretId)
	CollectionService:AddTag(model, "SecretChest")
	model.Parent = parent
	return model
end

-- The cframe is the body centre (feet sit 2.5 studs below it) and the NPC faces its LookVector (-Z).
function MapDecor.NPCBody(parent: Instance, cframe: CFrame, style: Types.NPCStyle, name: string, title: string): Model
	local model = Instance.new("Model")
	model.Name = name

	local root = makePart(model, "Root", Vector3.new(2, 2, 1), cframe * CFrame.new(0, 0.5, 0), style.shirt)
	local head = makePart(model, "Head", Vector3.new(1.4, 1.4, 1.4), cframe * CFrame.new(0, 2.2, 0), style.skin, SOFT)
	for _, side in ipairs({ -1, 1 }) do
		makePart(model, "Eye", Vector3.new(0.22, 0.28, 0.1), cframe * CFrame.new(side * 0.33, 2.3, -0.7), Color3.new(0, 0, 0), TINY)
		makePart(model, "Leg", Vector3.new(0.8, 2, 0.8), cframe * CFrame.new(side * 0.5, -1.5, 0), style.pants, SOFT)
		makePart(model, "Arm", Vector3.new(0.7, 2, 0.7), cframe * CFrame.new(side * 1.35, 0.5, 0), style.skin, SOFT)
	end
	local hat = style.hat
	if hat then
		makePart(model, "HatBrim", Vector3.new(2.2, 0.2, 2.2), cframe * CFrame.new(0, 2.98, 0), hat, SOFT)
		makePart(model, "HatCrown", Vector3.new(1.5, 0.7, 1.5), cframe * CFrame.new(0, 3.33, 0), hat, SOFT)
	end

	local tag = Instance.new("BillboardGui")
	tag.Name = "NameTag"
	tag.Size = UDim2.fromOffset(160, 44)
	tag.StudsOffset = Vector3.new(0, 1.6, 0)
	tag.AlwaysOnTop = false
	tag.MaxDistance = 60
	tag.LightInfluence = 0

	local function label(text: string, y: number, height: number, size: number, color: Color3)
		local l = Instance.new("TextLabel")
		l.Name = if y == 0 then "NameLabel" else "TitleLabel"
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromOffset(0, y)
		l.Size = UDim2.new(1, 0, 0, height)
		l.Font = Enum.Font.Arcade
		l.Text = text
		l.TextSize = size
		l.TextColor3 = color
		l.TextStrokeColor3 = Color3.new(0, 0, 0)
		l.TextStrokeTransparency = 0
		l.Parent = tag
	end
	label(name, 0, 24, 14, Color3.new(1, 1, 1))
	label(title, 24, 18, 10, Color3.fromRGB(242, 193, 78))
	tag.Parent = head

	model.PrimaryPart = root
	model.Parent = parent
	return model
end

-- Sign text is a BillboardGui over the board (SurfaceGuis are off limits here).
function MapDecor.Signpost(parent: Instance, cframe: CFrame, text: string, palette: Palette): Model
	local model = Instance.new("Model")
	model.Name = "Signpost"
	model:SetAttribute("Text", text)
	local woodDark = col(palette, "woodDark")
	local boardWidth = math.clamp(#text * 0.42, 4, 8)

	local postAt = cframe * CFrame.new(0, (4.6 - SINK) / 2, 0)
	makePart(model, "Post", Vector3.new(0.6, SINK + 4.6, 0.6), postAt, woodDark, SMALL)
	local boardAt = cframe * CFrame.new(0, 3.2, -0.2)
	local board = makePart(model, "Board", Vector3.new(boardWidth, 2.2, 0.4), boardAt, col(palette, "wood"), SMALL)
	makePart(model, "BoardTrim", Vector3.new(boardWidth + 0.4, 0.3, 0.5), boardAt * CFrame.new(0, 1.25, 0), woodDark, TINY)

	local gui = Instance.new("BillboardGui")
	gui.Name = "SignText"
	gui.Size = UDim2.fromScale(boardWidth - 0.4, 1.8) -- scale units are studs, so the text shrinks with distance like paint would
	gui.MaxDistance = 80
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.StudsOffsetWorldSpace = cframe.LookVector * 0.35 -- in front of the board face, so the board never hides its own text
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.Arcade
	label.Text = text
	label.TextScaled = true
	label.TextWrapped = true
	label.TextColor3 = Color3.fromRGB(255, 240, 200)
	label.TextStrokeColor3 = Color3.fromRGB(60, 36, 20)
	label.TextStrokeTransparency = 0
	label.Parent = gui
	gui.Parent = board

	model.Parent = parent
	return model
end

-- First position along `angle` from the island centre whose ground is at the waterline. Ponds and rivers are
-- skipped: the river runs through the middle of Mossbell and would otherwise count as "shore".
function MapDecor.FindShore(def: IslandDef, angle: number): Vector3
	local dirX, dirZ = math.cos(angle), math.sin(angle)
	local x, z = def.center.X, def.center.Z
	local height = 0
	local distance = 0
	while distance <= def.shallowsRadius do
		x, z = def.center.X + dirX * distance, def.center.Z + dirZ * distance
		local h, zone = groundAt(def, x, z)
		height = h
		if zone ~= "pond" and zone ~= "river" and h < SHORE_HEIGHT then
			break
		end
		distance += 2
	end
	return Vector3.new(x, height, z)
end

-- Builds the dock starting at `startPos` (only X/Z are used; the deck is always 3 studs above the ocean) and running
-- `length` studs along `direction`. Sets DockStart (where players spawn, a few studs onto the exposed deck), DockEnd
-- and DockDirection on the returned model.
function MapDecor.Dock(parent: Instance, def: IslandDef, startPos: Vector3, direction: Vector3, length: number): Model
	local palette = def.palette
	local wood, woodDark = col(palette, "wood"), col(palette, "woodDark")
	local dir = Vector3.new(direction.X, 0, direction.Z).Unit
	local model = Instance.new("Model")
	model.Name = "Dock"

	local deckTop = DECK_Y + DECK_LIFT
	local from = Vector3.new(startPos.X, deckTop, startPos.Z)
	local origin = CFrame.lookAt(from, from + dir) -- local -Z runs out to sea, y = 0 is the walking surface
	local halfWidth = DECK_WIDTH / 2
	local underside = -PLANK_THICKNESS

	for i = 0, math.ceil(length / PLANK_LENGTH) - 1 do
		local len = math.min(PLANK_LENGTH, length - i * PLANK_LENGTH)
		local mid = i * PLANK_LENGTH + len / 2
		local plankAt = origin * CFrame.new(0, -PLANK_THICKNESS / 2, -mid)
		makePart(model, "Plank", Vector3.new(DECK_WIDTH, PLANK_THICKNESS, len), plankAt, if i % 2 == 0 then wood else woodDark)
	end
	for _, side in ipairs({ -1, 1 }) do
		local stringerAt = origin * CFrame.new(side * (halfWidth - 1.2), underside - 0.25, -length / 2)
		makePart(model, "Stringer", Vector3.new(0.5, 0.5, length), stringerAt, woodDark)
	end

	-- Land end: if the ground under the first slab is lower than the deck, climb to it in small steps.
	local landHeight = groundAt(def, from.X + dir.X, from.Z + dir.Z)
	local rise = deckTop - landHeight
	if rise > 0.1 then
		local blocks = math.max(1, math.ceil(rise) - 1)
		local riser = rise / (blocks + 1)
		for k = 1, blocks do
			local top = -k * riser
			local bottom = landHeight - 3 - deckTop
			makePart(model, "Step", Vector3.new(DECK_WIDTH, top - bottom, 2), origin * CFrame.new(0, (top + bottom) / 2, 2 * k - 1), wood)
		end
	end

	-- Support posts down to the sea floor, cross beams, and a railing that stops short of the fishing end.
	local stations: { number } = { 0.6 }
	for t = POST_SPACING, length - 3, POST_SPACING do
		table.insert(stations, t)
	end
	table.insert(stations, length - 0.6)

	local railLimit = length - 12
	local previousT: number? = nil
	for _, t in ipairs(stations) do
		local supported = 0
		for _, side in ipairs({ -1, 1 }) do
			local p = origin * Vector3.new(side * (halfWidth - 0.7), 0, -t)
			local bottom = seabedAt(def, p.X, p.Z) - 1.5
			local top = deckTop + underside
			if top - bottom > 0.3 then
				local postAt = origin * CFrame.new(side * (halfWidth - 0.7), (top + bottom) / 2 - deckTop, -t)
				makePart(model, "SupportPost", Vector3.new(0.9, top - bottom, 0.9), postAt, woodDark)
				supported += 1
			end
			local railX = side * (halfWidth - 0.4)
			makePart(model, "RailPost", Vector3.new(0.6, 2.2, 0.6), origin * CFrame.new(railX, 1.1, -t), woodDark, SMALL)
			if previousT and t <= railLimit + 0.001 then
				local span = t - previousT
				local railAt = origin * CFrame.new(railX, 1.75, -(previousT + span / 2))
				makePart(model, "Rail", Vector3.new(0.35, 0.35, span), railAt, wood, SMALL)
			end
		end
		if supported == 2 then
			makePart(model, "CrossBeam", Vector3.new(DECK_WIDTH - 0.6, 0.5, 0.7), origin * CFrame.new(0, underside - 0.3, -t), woodDark)
		end
		previousT = t
	end

	for _, side in ipairs({ -1, 1 }) do
		local p = origin * Vector3.new(side * (halfWidth - 1.7), 0, -(length - 1))
		MapDecor.Lantern(model, Vector3.new(p.X, deckTop, p.Z), palette, 0.5)
	end

	-- Players spawn a few studs past the first point where the deck is no longer buried by the shore.
	local exposedT = 0
	for t = 0, length do
		local p = origin * Vector3.new(0, 0, -t)
		if groundAt(def, p.X, p.Z) <= deckTop + 0.01 then
			exposedT = t
			break
		end
	end
	model:SetAttribute("DockStart", origin * Vector3.new(0, 0, -math.min(exposedT + 3, length / 2)))
	model:SetAttribute("DockEnd", origin * Vector3.new(0, 0, -(length - 2)))
	model:SetAttribute("DockDirection", dir)

	model.Parent = parent
	return model
end

-- The origin is the highest ground under the tower; the plinth reaches down to hide a sloped base.
function MapDecor.Lighthouse(parent: Instance, position: Vector3, palette: Palette): Model
	local model = Instance.new("Model")
	model.Name = "Lighthouse"
	local red, white = col(palette, "roof"), col(palette, "wall")
	local woodDark = col(palette, "woodDark")
	local origin = CFrame.new(position)

	local plinthAt = origin * CFrame.new(0, (0.8 - LIGHTHOUSE_FOUNDATION) / 2, 0)
	makePart(model, "Plinth", Vector3.new(10, LIGHTHOUSE_FOUNDATION + 0.8, 10), plinthAt, col(palette, "stone"))
	local y = 0.8
	local bandHeight = 3.6
	for i, w in ipairs({ 7.6, 6.8, 6.0, 5.2, 4.6 }) do
		local bandAt = origin * CFrame.new(0, y + bandHeight / 2, 0)
		makePart(model, "Band", Vector3.new(w, bandHeight, w), bandAt, if i % 2 == 1 then red else white)
		if i >= 2 and i <= 4 then
			makePart(model, "Window", Vector3.new(0.9, 1.2, 0.25), bandAt * CFrame.new(0, 0, -w / 2 - 0.05), GLASS, TINY)
		end
		y += bandHeight
	end
	makePart(model, "Door", Vector3.new(1.7, 2.8, 0.3), origin * CFrame.new(0, 0.8 + 1.4, -3.9), Util.Darken(woodDark, 0.2), TINY)

	-- Gallery, lamp room and cap.
	makePart(model, "Gallery", Vector3.new(6.4, 0.5, 6.4), origin * CFrame.new(0, y + 0.25, 0), woodDark)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			makePart(model, "GalleryPost", Vector3.new(0.4, 1.4, 0.4), origin * CFrame.new(sx * 2.9, y + 1.2, sz * 2.9), woodDark, SMALL)
		end
	end
	y += 0.5
	local lampAt = origin * CFrame.new(0, y + 1.6, 0)
	local lamp = makePart(model, "Lamp", Vector3.new(3.4, 3.2, 3.4), lampAt, LAMP_GLASS, { CanCollide = false, Transparency = 0.15 })
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			makePart(model, "LampPost", Vector3.new(0.4, 3.2, 0.4), origin * CFrame.new(sx * 1.8, y + 1.6, sz * 1.8), woodDark, SMALL)
		end
	end
	y += 3.2
	makePart(model, "CapBase", Vector3.new(4.6, 0.5, 4.6), origin * CFrame.new(0, y + 0.25, 0), red)
	makePart(model, "CapMid", Vector3.new(3.0, 0.8, 3.0), origin * CFrame.new(0, y + 0.9, 0), red)
	makePart(model, "CapTip", Vector3.new(0.9, 0.9, 0.9), origin * CFrame.new(0, y + 1.75, 0), woodDark, TINY)

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 238, 190)
	light.Brightness = 3
	light.Range = 60
	light.Shadows = false
	light.Parent = lamp

	model.Parent = parent
	return model
end

-- Village props (local builders) ---------------------------------------------------------------------

-- Ring of stone around a hole with a little roofed windlass. The origin is the highest ground under the well.
local function buildWell(parent: Instance, origin: CFrame, palette: Palette): Model
	local model = Instance.new("Model")
	model.Name = "Well"
	local stone, stoneDark = col(palette, "stone"), col(palette, "rockDark")
	local woodDark = col(palette, "woodDark")
	local rim = 1.4
	local depth = 5.5

	for ix = -1, 1 do
		for iz = -1, 1 do
			if ix ~= 0 or iz ~= 0 then
				local stoneAt = origin * CFrame.new(ix * 1.5, (rim - depth) / 2, iz * 1.5)
				local stoneColor = if (ix + iz) % 2 == 0 then stone else stoneDark
				makePart(model, "WellStone", Vector3.new(1.5, depth + rim, 1.5), stoneAt, stoneColor)
			end
		end
	end
	makePart(model, "Water", Vector3.new(1.4, 0.2, 1.4), origin * CFrame.new(0, rim - 0.5, 0), WATER, TINY)
	for _, side in ipairs({ -1, 1 }) do
		makePart(model, "WellPost", Vector3.new(0.4, 3.4, 0.4), origin * CFrame.new(side * 1.5, rim + 1.7, 0), woodDark, SMALL)
	end
	makePart(model, "WellBeam", Vector3.new(3.8, 0.4, 0.4), origin * CFrame.new(0, rim + 3.4, 0), woodDark, SMALL)
	makePart(model, "Rope", Vector3.new(0.1, 1.2, 0.1), origin * CFrame.new(0, rim + 2.7, 0), col(palette, "sand"), TINY)
	makePart(model, "Bucket", Vector3.new(0.6, 0.5, 0.6), origin * CFrame.new(0, rim + 1.9, 0), col(palette, "wood"), TINY)
	gableRoof(model, origin * CFrame.new(0, rim + 3.6, 0), 4.6, 3.4, 1.3, col(palette, "roofAlt"))

	model.Parent = parent
	return model
end

-- Counter with crates under a striped sloping awning. The origin is the highest ground under the stall; the front is -Z.
local function buildStall(parent: Instance, origin: CFrame, palette: Palette, rng: Random): Model
	local model = Instance.new("Model")
	model.Name = "MarketStall"
	local wood, woodDark = col(palette, "wood"), col(palette, "woodDark")
	local top = 0.3
	local foundation = 5.5

	makePart(model, "Platform", Vector3.new(5.4, foundation + top, 3.8), origin * CFrame.new(0, (top - foundation) / 2, 0), woodDark)
	makePart(model, "Counter", Vector3.new(4.6, 1.5, 1.6), origin * CFrame.new(0, top + 0.75, -0.7), wood)
	makePart(model, "CounterTop", Vector3.new(5.0, 0.25, 2.0), origin * CFrame.new(0, top + 1.625, -0.7), woodDark, SMALL)
	for _, side in ipairs({ -1, 1 }) do
		makePart(model, "BackPost", Vector3.new(0.4, 4.8, 0.4), origin * CFrame.new(side * 2.3, top + 2.4, 1.3), woodDark, SMALL)
		makePart(model, "FrontPost", Vector3.new(0.4, 3.6, 0.4), origin * CFrame.new(side * 2.3, top + 1.8, -1.5), woodDark, SMALL)
	end
	local stripes = { col(palette, "roof"), col(palette, "wall") }
	for i = 0, 3 do
		local stripeAt = origin * CFrame.new(-1.95 + i * 1.3, top + 3.6 + 0.6, -0.1)
		makeWedge(model, "Awning", Vector3.new(1.3, 1.2, 3.4), stripeAt, stripes[i % 2 + 1], SMALL)
	end
	for i, crateX in ipairs({ -1.4, 0.2, 1.7 }) do
		local crateAt = origin * CFrame.new(crateX, top + 1.75 + 0.25, -0.7)
		makePart(model, "Crate", Vector3.new(1.1, 0.5, 0.9), crateAt, woodDark, TINY)
		local fish = FLOWER_COLORS[rng:NextInteger(1, #FLOWER_COLORS)]
		makePart(model, "Goods", Vector3.new(0.8, 0.25, 0.6), crateAt * CFrame.new(0, 0.3, 0), if i == 2 then GLASS else fish, TINY)
	end

	model.Parent = parent
	return model
end

-- Scene building -------------------------------------------------------------------------------------

local function claim(scene: Scene, x: number, z: number, radius: number)
	table.insert(scene.props, { x = x, z = z, r = radius })
	table.insert(scene.keepClear, { x = x, z = z, r = radius + PROP_MARGIN })
end

-- Whether a village prop with a round footprint fits here: all land, above the beach, not too steep, and clear of
-- NPCs, other props and the dock.
local function canBuild(scene: Scene, x: number, z: number, radius: number): boolean
	local lo, hi, allLand = groundSpan(scene.def, CFrame.new(x, 0, z), radius, radius)
	if not allLand or lo < BUILD_MIN_HEIGHT or hi - lo > BUILD_MAX_SLOPE then
		return false
	end
	local npcNeed = radius + NPC_CLEAR
	for _, n in ipairs(scene.npcs) do
		local dx, dz = x - n.x, z - n.z
		if dx * dx + dz * dz < npcNeed * npcNeed then
			return false
		end
	end
	for _, p in ipairs(scene.props) do
		local dx, dz = x - p.x, z - p.z
		local need = p.r + radius + 1
		if dx * dx + dz * dz < need * need then
			return false
		end
	end
	local a, b = scene.dockA, scene.dockB
	if a and b and distToSegment(x, z, a, b) < radius + DECK_WIDTH / 2 + 2 then
		return false
	end
	return true
end

-- Tries the ideal spot first, then nearby angles and distances.
local function findSpot(scene: Scene, center: Vector3, angle: number, distance: number, radius: number): Vector3?
	for _, extra in ipairs({ 0, 2, -2, 4, -4, 6, -6 }) do
		for _, turn in ipairs({ 0, 12, -12, 24, -24, 36, -36, 50, -50, 65, -65, 80, -80, 100, -100 }) do
			local a = angle + math.rad(turn)
			local d = distance + extra
			local x, z = center.X + math.cos(a) * d, center.Z + math.sin(a) * d
			if canBuild(scene, x, z, radius) then
				return Vector3.new(x, 0, z)
			end
		end
	end
	return nil
end

-- A frame on top of the highest ground under the footprint, facing (flat) toward `target`.
local function frameFacing(def: IslandDef, spot: Vector3, target: Vector3, halfX: number, halfZ: number): CFrame
	local fx, fz = target.X - spot.X, target.Z - spot.Z
	if fx * fx + fz * fz < 0.01 then
		fz = -1
	end
	local probe = CFrame.lookAt(Vector3.new(spot.X, 0, spot.Z), Vector3.new(spot.X + fx, 0, spot.Z + fz))
	local _, hi = groundSpan(def, probe, halfX, halfZ)
	return CFrame.lookAt(Vector3.new(spot.X, hi, spot.Z), Vector3.new(spot.X + fx, hi, spot.Z + fz))
end

local function buildDock(scene: Scene, parent: Model)
	local def = scene.def
	local dock = def.dock
	if not dock then
		return
	end
	local shore = MapDecor.FindShore(def, dock.angle)
	local dir = Vector3.new(math.cos(dock.angle), 0, math.sin(dock.angle))
	local inland = shore - dir * 8
	local startPos = Vector3.new(inland.X, (groundAt(def, inland.X, inland.Z)), inland.Z)
	local model = MapDecor.Dock(parent, def, startPos, dir, dock.length)
	for _, key in ipairs({ "DockStart", "DockEnd", "DockDirection" }) do
		parent:SetAttribute(key, model:GetAttribute(key))
	end
	scene.dockA = startPos
	scene.dockB = startPos + dir * dock.length
end

local function buildVillage(scene: Scene, parent: Model)
	local def, rng, palette = scene.def, scene.rng, scene.palette
	local village = def.village
	if not village then
		return
	end
	local center = IslandGen.Polar(def, village.angle, village.distance)
	local folder = newFolder(parent, "Village")
	table.insert(scene.keepClear, { x = center.X, z = center.Z, r = VILLAGE_CLEAR })

	-- The plaza opens toward the dock (straight downhill when there is none) and the huts ring the other side.
	local open = village.angle
	if scene.dockA then
		open = math.atan2(scene.dockA.Z - center.Z, scene.dockA.X - center.X)
	end
	local uphill = open + math.pi
	local roofs = { col(palette, "roof"), col(palette, "roofAlt"), col(palette, "roof") }
	for i = 1, 3 do
		local spot = findSpot(scene, center, uphill + (i - 1) * math.pi * 2 / 3, HUT_RING, HUT_RADIUS)
		if spot then
			claim(scene, spot.X, spot.Z, HUT_RADIUS)
			MapDecor.Hut(folder, frameFacing(def, spot, center, 3.8, 3.3), palette, rng, roofs[i])
		end
	end

	local wellSpot: Vector3? = nil
	if canBuild(scene, center.X, center.Z, WELL_RADIUS) then
		wellSpot = Vector3.new(center.X, 0, center.Z)
	else
		wellSpot = findSpot(scene, center, uphill, 4, WELL_RADIUS)
	end
	if wellSpot then
		claim(scene, wellSpot.X, wellSpot.Z, WELL_RADIUS)
		buildWell(folder, frameFacing(def, wellSpot, center, 2.4, 2.4), palette)
	end

	-- The harbour sign stands at the plaza edge on the path to the dock and faces the approach. Its board is wide,
	-- so it claims a bigger footprint than its post.
	local signSpot = findSpot(scene, center, open, 11, SIGN_RADIUS)
	if signSpot then
		claim(scene, signSpot.X, signSpot.Z, SIGN_RADIUS)
		local _, hi = groundSpan(def, CFrame.new(signSpot.X, 0, signSpot.Z), 0.8, 0.8)
		local at = Vector3.new(signSpot.X, hi, signSpot.Z)
		local facing = Vector3.new(math.cos(open), 0, math.sin(open))
		local harbour = def.name:gsub(" Isle$", "") .. " Harbour"
		MapDecor.Signpost(folder, CFrame.lookAt(at, at + facing), harbour, palette)
	end

	for _, offset in ipairs({ 60, 180, 300 }) do
		local spot = findSpot(scene, center, uphill + math.rad(offset), 9.5, STALL_RADIUS)
		if spot then
			claim(scene, spot.X, spot.Z, STALL_RADIUS)
			buildStall(folder, frameFacing(def, spot, center, 2.8, 2.0), palette, rng)
			break
		end
	end

	local lanterns = 0
	for _, offset in ipairs({ 60, 180, 300, 120, 240, 0 }) do
		if lanterns >= 4 then
			break
		end
		local spot = findSpot(scene, center, uphill + math.rad(offset), 7, 1)
		if spot then
			claim(scene, spot.X, spot.Z, 1)
			local _, hi = groundSpan(def, CFrame.new(spot.X, 0, spot.Z), 0.8, 0.8)
			MapDecor.Lantern(folder, Vector3.new(spot.X, hi, spot.Z), palette)
			lanterns += 1
		end
	end
end

local function buildLighthouse(scene: Scene, parent: Model)
	local def, rng, palette = scene.def, scene.rng, scene.palette
	local lighthouse = def.lighthouse
	if not lighthouse then
		return
	end
	local spot = IslandGen.Polar(def, lighthouse.angle, lighthouse.distance)
	local _, hi = groundSpan(def, CFrame.new(spot.X, 0, spot.Z), LIGHTHOUSE_HALF, LIGHTHOUSE_HALF)
	MapDecor.Lighthouse(parent, Vector3.new(spot.X, hi, spot.Z), palette)
	table.insert(scene.keepClear, { x = spot.X, z = spot.Z, r = LIGHTHOUSE_CLEAR })

	local rocks = newFolder(parent, "LighthouseRocks")
	local count = 5
	for i = 1, count do
		local angle = (i - 1) / count * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local distance = rng:NextNumber(7.5, 9.5)
		local x, z = spot.X + math.cos(angle) * distance, spot.Z + math.sin(angle) * distance
		local scale = rng:NextNumber(1.6, 3)
		local lo, top, allLand = groundSpan(def, CFrame.new(x, 0, z), scale, scale)
		if allLand and isClear(scene, x, z) then
			MapDecor.Rock(rocks, Vector3.new(x, (lo + top) / 2, z), palette, rng, scale)
		end
	end
end

local function buildSecrets(scene: Scene, parent: Model)
	local def, palette = scene.def, scene.palette
	if #def.secrets == 0 then
		return
	end
	local folder = newFolder(parent, "Secrets")
	for _, secret in ipairs(def.secrets) do
		local spot = IslandGen.Polar(def, secret.angle, secret.distance)
		local outward = Vector3.new(math.cos(secret.angle), 0, math.sin(secret.angle))
		local probe = CFrame.lookAt(Vector3.new(spot.X, 0, spot.Z), Vector3.new(spot.X, 0, spot.Z) + outward)
		local _, hi = groundSpan(def, probe, 2.2, 1.7)
		local cframe = CFrame.lookAt(Vector3.new(spot.X, hi - 0.3, spot.Z), Vector3.new(spot.X, hi - 0.3, spot.Z) + outward)
		MapDecor.Chest(folder, cframe, palette, secret.id)
	end
end

local function scatterTrees(scene: Scene, parent: Model)
	local def, rng, palette = scene.def, scene.rng, scene.palette
	local folder = newFolder(parent, "Trees")
	local reach = def.radius + 8
	for gx = -reach, reach, 6 do
		for gz = -reach, reach, 6 do
			local x = def.center.X + gx + rng:NextNumber(-2.5, 2.5)
			local z = def.center.Z + gz + rng:NextNumber(-2.5, 2.5)
			local roll = rng:NextNumber()
			if roll < def.treeDensity * 2.2 then
				local h, zone = groundAt(def, x, z)
				if zone == "land" and h >= 3 and h <= 13.5 and isClear(scene, x, z) then
					local _, top, allLand = groundSpan(def, CFrame.new(x, 0, z), 0.7, 0.7)
					if allLand then
						local variants = def.treeVariants
						local variant = variants[rng:NextInteger(1, math.max(#variants, 1))] or "Oak"
						if variant == "Palm" and h >= 5 then
							variant = if rng:NextNumber() < 0.5 then "Oak" else "Pine"
						end
						MapDecor.Tree(folder, Vector3.new(x, top, z), palette, rng, variant)
					end
				end
			end
		end
	end
end

local function scatterRocks(scene: Scene, parent: Model)
	local def, rng, palette = scene.def, scene.rng, scene.palette
	local folder = newFolder(parent, "Rocks")
	local reach = def.radius + 8
	for gx = -reach, reach, 7 do
		for gz = -reach, reach, 7 do
			local x = def.center.X + gx + rng:NextNumber(-2.5, 2.5)
			local z = def.center.Z + gz + rng:NextNumber(-2.5, 2.5)
			local roll = rng:NextNumber()
			if roll < def.rockDensity * 2 then
				local h, zone = groundAt(def, x, z)
				local onSand = zone == "land" and h < 3
				if (onSand or (zone == "land" and h > 12)) and isClear(scene, x, z) then
					local scale = rng:NextNumber(1, 3)
					local lo, top = groundSpan(def, CFrame.new(x, 0, z), scale, scale)
					MapDecor.Rock(folder, Vector3.new(x, (lo + top) / 2, z), palette, rng, scale)
				end
			end
		end
	end
end

local function buildReeds(scene: Scene, parent: Model)
	local def, rng, palette = scene.def, scene.rng, scene.palette
	local pond, river = def.pond, def.river
	if not pond then
		return
	end
	local folder = newFolder(parent, "Reeds")
	local cx, cz = def.center.X + pond.offset.X, def.center.Z + pond.offset.Z

	local clumps = 14
	for i = 0, clumps - 1 do
		local angle = (i + rng:NextNumber(-0.3, 0.3)) / clumps * math.pi * 2
		local x, z = cx + math.cos(angle) * (pond.radius + 2), cz + math.sin(angle) * (pond.radius + 2)
		local h, zone = groundAt(def, x, z)
		if zone == "land" and h <= pond.waterY + SHORE_HEIGHT then
			MapDecor.Reeds(folder, Vector3.new(x, math.max(h, pond.waterY), z), palette, rng)
		else
			-- Steep banks leave no shoreline at water level, so root the clump on the bed just inside the edge.
			local inner = pond.radius - 0.8
			local base = Vector3.new(cx + math.cos(angle) * inner, pond.waterY, cz + math.sin(angle) * inner)
			MapDecor.Reeds(folder, base, palette, rng, pond.waterY - pond.bedY + 0.5)
		end
	end

	if not river then
		return
	end
	local dirX, dirZ = math.cos(river.angle), math.sin(river.angle)
	local length = IslandGen.RiverLength(def)
	local first, last = pond.radius + 10, length - 14
	local offset = river.width / 2 + 1.5
	local made = 0
	for k = 0, 5 do
		local along = first + (last - first) * (k + 0.5) / 6
		for _, attempt in ipairs({ 0, 3, -3, 6 }) do
			local sideSign = if (k + made) % 2 == 0 then 1 else -1
			local placed = false
			for _, s in ipairs({ sideSign, -sideSign }) do
				local a = along + attempt
				local x = cx + dirX * a - dirZ * offset * s
				local z = cz + dirZ * a + dirX * offset * s
				local _, zone = groundAt(def, x, z)
				if zone == "land" then
					local _, top = groundSpan(def, CFrame.new(x, 0, z), 1, 1)
					MapDecor.Reeds(folder, Vector3.new(x, top, z), palette, rng)
					placed = true
					break
				end
			end
			if placed then
				made += 1
				break
			end
		end
	end
end

local function scatterFlowers(scene: Scene, parent: Model)
	local def, rng, palette = scene.def, scene.rng, scene.palette
	local folder = newFolder(parent, "Flowers")
	local reach = def.radius + 8
	for gx = -reach, reach, 5 do
		for gz = -reach, reach, 5 do
			local x = def.center.X + gx + rng:NextNumber(-2, 2)
			local z = def.center.Z + gz + rng:NextNumber(-2, 2)
			local roll = rng:NextNumber()
			local bloom = FLOWER_COLORS[rng:NextInteger(1, #FLOWER_COLORS)]
			if roll < 0.05 then
				local h, zone = groundAt(def, x, z)
				if zone == "land" and h >= 3 and h <= 12 and isClear(scene, x, z) then
					local _, top, allLand = groundSpan(def, CFrame.new(x, 0, z), 0.6, 0.6)
					if allLand then
						local bush = Instance.new("Model")
						bush.Name = "Shrub"
						local depth = 3 -- hidden part of the cube, so a terrain step under it never leaves a gap
						local leavesAt = CFrame.new(x, top + (1 - depth) / 2, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi / 2), 0)
						makePart(bush, "Leaves", Vector3.new(1, 1 + depth, 1), leavesAt, col(palette, "leafLight"), TINY)
						local bloomAt = CFrame.new(x + rng:NextNumber(-0.15, 0.15), top + 1.15, z + rng:NextNumber(-0.15, 0.15))
						makePart(bush, "Bloom", Vector3.new(0.4, 0.4, 0.4), bloomAt, bloom, TINY)
						bush.Parent = folder
					end
				end
			end
		end
	end
end

-- Builds every decoration for one island into `parent`. Deterministic: seeded from def.seed.
function MapDecor.Populate(def: IslandDef, parent: Model)
	local scene: Scene = {
		def = def,
		rng = Random.new(def.seed + 7),
		palette = def.palette,
		npcs = {},
		props = {},
		keepClear = {},
	}
	for _, npc in ipairs(def.npcs) do
		local p = IslandGen.Polar(def, npc.angle, npc.distance)
		table.insert(scene.npcs, { x = p.X, z = p.Z, r = 0 })
		table.insert(scene.keepClear, { x = p.X, z = p.Z, r = NPC_SCATTER_CLEAR })
	end
	for _, secret in ipairs(def.secrets) do
		local p = IslandGen.Polar(def, secret.angle, secret.distance)
		table.insert(scene.keepClear, { x = p.X, z = p.Z, r = CHEST_CLEAR })
	end

	buildDock(scene, parent)
	buildVillage(scene, parent)
	buildLighthouse(scene, parent)
	buildSecrets(scene, parent)
	scatterTrees(scene, parent)
	scatterRocks(scene, parent)
	buildReeds(scene, parent)
	scatterFlowers(scene, parent)
end

-- The ground surface height and zone at a world position as it was actually built (see header).
function MapDecor.GroundAt(def: IslandDef, x: number, z: number): (number, string)
	return groundAt(def, x, z)
end

return MapDecor
