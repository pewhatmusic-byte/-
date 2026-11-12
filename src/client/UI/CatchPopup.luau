--!strict
-- The "You caught a ...!" card shown after a successful catch.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FishData = require(Shared:WaitForChild("FishData"))
local LocationData = require(Shared:WaitForChild("LocationData"))
local MutationData = require(Shared:WaitForChild("MutationData"))
local RarityData = require(Shared:WaitForChild("RarityData"))
local Util = require(Shared:WaitForChild("Util"))
local Types = require(Shared:WaitForChild("Types"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local PixelUI = require(script.Parent:WaitForChild("PixelUI"))
local PixelIcon = require(script.Parent:WaitForChild("PixelIcon"))

local CatchPopup = {}

local holder: Frame? = nil
local body: Frame? = nil
local hideToken = 0

function CatchPopup.Init(gui: ScreenGui)
	local h, b = PixelUI.Panel({
		Name = "CatchPopup",
		Parent = gui,
		Size = UDim2.fromOffset(360, 170),
		Position = UDim2.new(0.5, 0, 0, 120),
		AnchorPoint = Vector2.new(0.5, 0),
		Visible = false,
		ZIndex = 25,
	})
	holder, body = h, b
end

local function clear(parent: Frame)
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

function CatchPopup.Show(fish: Types.CaughtFish, info: { isNew: boolean?, xp: number?, levelsGained: number? })
	local h, b = holder, body
	local def = FishData.Get(fish.id)
	if not h or not b or not def then
		return
	end
	clear(b)
	local rarityColor = RarityData.Color(def.rarity)
	local stroke = b:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = rarityColor
	end

	local mutation = MutationData.Get(fish.mutation)
	PixelIcon.Render(b, def, {
		shiny = fish.shiny,
		mutationColor = if mutation then mutation.color else nil,
		Size = UDim2.fromOffset(120, 80),
		Position = UDim2.fromOffset(14, 40),
		ZIndex = 3,
	})

	PixelUI.Label({
		Parent = b,
		Text = if info.isNew then "NEW SPECIES!" else "CAUGHT!",
		Size = UDim2.new(1, -20, 0, 24),
		Position = UDim2.fromOffset(14, 8),
		TextSize = Theme.TextSizes.Title,
		Color = if info.isNew then Theme.Colors.Accent else Theme.Colors.Accent2,
		ZIndex = 3,
	})

	local textX = 146
	local prefix = ""
	if fish.shiny then
		prefix = "Shiny "
	end
	if mutation then
		prefix = prefix .. mutation.id .. " "
	end
	PixelUI.Label({
		Parent = b,
		Text = prefix .. def.name,
		Size = UDim2.new(1, -textX - 10, 0, 40),
		Position = UDim2.fromOffset(textX, 36),
		TextSize = Theme.TextSizes.Body,
		Color = rarityColor,
		Wrap = true,
		ZIndex = 3,
	})
	PixelUI.Tag({
		Parent = b,
		Text = def.rarity,
		Color = rarityColor,
		Position = UDim2.fromOffset(textX, 80),
		Size = UDim2.fromOffset(100, 18),
		ZIndex = 3,
	})
	PixelUI.Label({
		Parent = b,
		Text = string.format("%s  (%s)", Util.FormatWeight(fish.weight), fish.sizeTier),
		Size = UDim2.new(1, -textX - 10, 0, 20),
		Position = UDim2.fromOffset(textX, 102),
		TextSize = Theme.TextSizes.Small,
		ZIndex = 3,
	})
	PixelUI.Label({
		Parent = b,
		Text = string.format("%s coins   +%d XP", Util.FormatNumber(fish.value), info.xp or 0),
		Size = UDim2.new(1, -textX - 10, 0, 20),
		Position = UDim2.fromOffset(textX, 124),
		TextSize = Theme.TextSizes.Small,
		Color = Theme.Colors.Coins,
		ZIndex = 3,
	})
	PixelUI.Label({
		Parent = b,
		Text = LocationData.Name(fish.location),
		Size = UDim2.new(1, -28, 0, 16),
		Position = UDim2.fromOffset(14, 146),
		TextSize = Theme.TextSizes.Tiny,
		Color = Theme.Colors.TextMuted,
		ZIndex = 3,
	})

	h.Visible = true
	h.Position = UDim2.new(0.5, 0, 0, 100)
	PixelUI.Tween(h, { Position = UDim2.new(0.5, 0, 0, 120) }, 0.2, Enum.EasingStyle.Back)

	hideToken += 1
	local token = hideToken
	task.delay(4.5, function()
		if hideToken == token then
			h.Visible = false
		end
	end)
end

function CatchPopup.Hide()
	hideToken += 1
	if holder then
		holder.Visible = false
	end
end

return CatchPopup
