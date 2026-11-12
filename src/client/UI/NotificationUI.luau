--!strict
-- Toast notifications stacked at the top centre of the screen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared:WaitForChild("Signal"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local PixelUI = require(script.Parent:WaitForChild("PixelUI"))

local NotificationUI = {}

local MAX_VISIBLE = 5
local container: Frame? = nil
local sequence = 0

local COLORS: { [string]: Color3 } = {
	info = Theme.Colors.Info,
	success = Theme.Colors.Success,
	error = Theme.Colors.Danger,
	levelup = Theme.Colors.Accent,
	discover = Theme.Colors.Accent2,
	dialogue = Theme.Colors.PanelLight,
}

local DURATIONS: { [string]: number } = { levelup = 5, discover = 5, dialogue = 6 }

NotificationUI.Pushed = Signal.new()

function NotificationUI.Init(gui: ScreenGui)
	local frame = PixelUI.Frame({
		Name = "Notifications",
		Parent = gui,
		Size = UDim2.fromOffset(420, 300),
		Position = UDim2.new(0.5, 0, 0, 12),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		ZIndex = 30,
	})
	PixelUI.List(frame, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center)
	container = frame
end

function NotificationUI.Push(kind: string, text: string)
	local parent = container
	if not parent then
		return
	end
	local color = COLORS[kind] or Theme.Colors.Info
	sequence += 1
	local holder, body = PixelUI.Panel({
		Parent = parent,
		Size = UDim2.new(1, 0, 0, 40),
		Color = Theme.Colors.PanelDark,
		BorderColor = color,
		LayoutOrder = sequence,
	})
	local stripe = PixelUI.Frame({ Parent = body, Size = UDim2.new(0, 6, 1, 0), Color = color })
	stripe.ZIndex = 3
	local label = PixelUI.Label({
		Parent = body,
		Text = text,
		Size = UDim2.new(1, -20, 1, 0),
		Position = UDim2.fromOffset(14, 0),
		TextSize = if kind == "levelup" then Theme.TextSizes.Title else Theme.TextSizes.Small,
		Color = if kind == "levelup" then Theme.Colors.Accent else Theme.Colors.Text,
		Wrap = true,
		ZIndex = 3,
	})
	label.TextScaled = false

	-- trim the stack
	local children = parent:GetChildren()
	local panels = {}
	for _, child in ipairs(children) do
		if child:IsA("Frame") then
			table.insert(panels, child)
		end
	end
	table.sort(panels, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	while #panels > MAX_VISIBLE do
		local oldest = table.remove(panels, 1)
		if oldest then
			oldest:Destroy()
		end
	end

	holder.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(0, -8)
	PixelUI.Tween(body, { Position = UDim2.fromOffset(0, 0) }, 0.15)

	task.delay(DURATIONS[kind] or 3.5, function()
		if holder.Parent then
			PixelUI.Tween(body, { BackgroundTransparency = 1 }, 0.2)
			PixelUI.Tween(label, { TextTransparency = 1 }, 0.2)
			task.wait(0.22)
			holder:Destroy()
		end
	end)
	NotificationUI.Pushed:Fire(kind, text)
end

return NotificationUI
