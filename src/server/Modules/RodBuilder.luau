--!strict
-- Builds the blocky fishing rod Tool a player holds. Purely visual: fishing logic never trusts the tool.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Util = require(Shared:WaitForChild("Util"))

local RodBuilder = {}

-- Hand position in rod-local space and how far the rod tilts up from horizontal. Tweak to taste.
local GRIP_OFFSET = Vector3.new(0, -2.2, 0)
local GRIP_TILT = math.rad(40)
local ROD_LENGTH = 7

local function part(name: string, size: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

local function weld(handle: Part, other: Part, offset: CFrame)
	other.CFrame = handle.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = handle
	w.Part1 = other
	w.Parent = handle
end

function RodBuilder.Build(rod: Types.RodDef): Tool
	local tool = Instance.new("Tool")
	tool.Name = rod.name
	tool.ToolTip = rod.name
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.Grip = CFrame.new(GRIP_OFFSET) * CFrame.Angles(-GRIP_TILT, 0, 0)
	tool:SetAttribute("FishingRod", true)
	tool:SetAttribute("RodId", rod.id)

	local handle = part("Handle", Vector3.new(0.35, ROD_LENGTH, 0.35), rod.color1)
	handle.Parent = tool

	local grip = part("Grip", Vector3.new(0.55, 1.6, 0.55), Util.Darken(rod.color2, 0.2))
	grip.Parent = tool
	weld(handle, grip, CFrame.new(0, -ROD_LENGTH / 2 + 0.9, 0))

	local reel = part("Reel", Vector3.new(0.7, 0.7, 0.45), rod.color2)
	reel.Parent = tool
	weld(handle, reel, CFrame.new(0, -ROD_LENGTH / 2 + 2.1, 0.4))

	local tipPart = part("Tip", Vector3.new(0.22, 1.4, 0.22), rod.color2)
	tipPart.Parent = tool
	weld(handle, tipPart, CFrame.new(0, ROD_LENGTH / 2 - 0.7, 0))

	local tip = Instance.new("Attachment")
	tip.Name = "RodTip"
	tip.Position = Vector3.new(0, ROD_LENGTH / 2, 0)
	tip.Parent = handle

	return tool
end

local function removeExisting(player: Player)
	local function scan(container: Instance?)
		if not container then
			return
		end
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") and child:GetAttribute("FishingRod") then
				child:Destroy()
			end
		end
	end
	scan(player:FindFirstChildOfClass("Backpack"))
	scan(player.Character)
end

-- Gives (and equips) the rod tool, replacing any previous one.
function RodBuilder.Give(player: Player, rod: Types.RodDef)
	removeExisting(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return
	end
	local tool = RodBuilder.Build(rod)
	tool.Parent = player:FindFirstChildOfClass("Backpack") or character
	humanoid:EquipTool(tool)
end

-- The rod tip attachment on the player's currently held rod (nil when not holding one).
function RodBuilder.FindTip(player: Player): Attachment?
	local character = player.Character
	if not character then
		return nil
	end
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and child:GetAttribute("FishingRod") then
			local handle = child:FindFirstChild("Handle")
			local tip = handle and handle:FindFirstChild("RodTip")
			if tip and tip:IsA("Attachment") then
				return tip
			end
		end
	end
	return nil
end

return RodBuilder
