--!strict
-- Heads-up display: level/XP/coins, location + weather, equipped gear, menu buttons, the fishing
-- prompt line, cast power bar and the touch action button.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared:WaitForChild("Signal"))
local Util = require(Shared:WaitForChild("Util"))
local LevelUtil = require(Shared:WaitForChild("LevelUtil"))
local LocationData = require(Shared:WaitForChild("LocationData"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local PixelUI = require(script.Parent:WaitForChild("PixelUI"))
local State = require(script.Parent.Parent:WaitForChild("ClientState"))

local HUD = {}

HUD.ActionPressed = Signal.new()
HUD.ActionReleased = Signal.new()

local levelLabel: TextLabel
local xpBar: PixelUI.ProgressBar
local coinsLabel: TextLabel
local locationLabel: TextLabel
local weatherLabel: TextLabel
local rodLabel: TextLabel
local baitLabel: TextLabel
local promptLabel: TextLabel
local castBar: PixelUI.ProgressBar
local actionButton: TextButton? = nil

export type MenuCallbacks = { OnInventory: () -> (), OnBestiary: () -> () }

function HUD.Init(gui: ScreenGui, callbacks: MenuCallbacks)
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

	-- Top-left: level, XP, coins
	local _, stats = PixelUI.Panel({
		Name = "Stats",
		Parent = gui,
		Size = UDim2.fromOffset(250, 94),
		Position = UDim2.fromOffset(16, 16),
	})
	PixelUI.Padding(stats, 10, 8)
	levelLabel = PixelUI.Label({ Parent = stats, Text = "LV 1", TextSize = Theme.TextSizes.Title, Color = Theme.Colors.Accent, Size = UDim2.new(1, 0, 0, 22), ZIndex = 3 })
	xpBar = PixelUI.ProgressBar({ Parent = stats, Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 0, 16), Color = Theme.Colors.XP, Text = "", ZIndex = 3 })
	coinsLabel = PixelUI.Label({ Parent = stats, Position = UDim2.fromOffset(0, 52), Size = UDim2.new(1, 0, 0, 22), Text = "0 coins", Color = Theme.Colors.Coins, ZIndex = 3 })

	-- Top-right: location + weather/time
	local _, place = PixelUI.Panel({
		Name = "Location",
		Parent = gui,
		Size = UDim2.fromOffset(280, 62),
		Position = UDim2.new(1, -16, 0, 16),
		AnchorPoint = Vector2.new(1, 0),
	})
	PixelUI.Padding(place, 10, 6)
	locationLabel = PixelUI.Label({ Parent = place, Text = "", Size = UDim2.new(1, 0, 0, 24), XAlign = Enum.TextXAlignment.Right, TextSize = Theme.TextSizes.Body, Color = Theme.Colors.Accent2, ZIndex = 3 })
	weatherLabel = PixelUI.Label({ Parent = place, Text = "", Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 20), XAlign = Enum.TextXAlignment.Right, TextSize = Theme.TextSizes.Small, Color = Theme.Colors.TextMuted, ZIndex = 3 })

	-- Bottom-left: equipped gear
	local _, gear = PixelUI.Panel({
		Name = "Gear",
		Parent = gui,
		Size = UDim2.fromOffset(250, 56),
		Position = UDim2.new(0, 16, 1, -16),
		AnchorPoint = Vector2.new(0, 1),
	})
	PixelUI.Padding(gear, 10, 6)
	rodLabel = PixelUI.Label({ Parent = gear, Text = "", Size = UDim2.new(1, 0, 0, 20), TextSize = Theme.TextSizes.Small, ZIndex = 3 })
	baitLabel = PixelUI.Label({ Parent = gear, Text = "", Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 20), TextSize = Theme.TextSizes.Small, Color = Theme.Colors.TextMuted, ZIndex = 3 })

	-- Right: menu buttons
	local menu = PixelUI.Frame({
		Name = "Menu",
		Parent = gui,
		Size = UDim2.fromOffset(120, 100),
		Position = UDim2.new(1, -16, 0, 92),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
	})
	PixelUI.List(menu, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Right)
	PixelUI.Button({ Parent = menu, Text = if touch then "BAG" else "BAG  [I]", Size = UDim2.fromOffset(120, 36), LayoutOrder = 1, OnClick = callbacks.OnInventory })
	PixelUI.Button({ Parent = menu, Text = if touch then "BOOK" else "BOOK [B]", Size = UDim2.fromOffset(120, 36), LayoutOrder = 2, Color = Theme.Colors.ButtonSecondary, TextColor = Theme.Colors.ButtonSecondaryText, OnClick = callbacks.OnBestiary })

	-- Bottom-centre: prompt line + cast power
	promptLabel = PixelUI.Label({
		Name = "Prompt",
		Parent = gui,
		Size = UDim2.fromOffset(640, 30),
		Position = UDim2.new(0.5, 0, 1, -170),
		AnchorPoint = Vector2.new(0.5, 1),
		XAlign = Enum.TextXAlignment.Center,
		Outline = true,
		TextSize = Theme.TextSizes.Body,
		Text = "",
	})
	castBar = PixelUI.ProgressBar({
		Name = "CastPower",
		Parent = gui,
		Size = UDim2.fromOffset(260, 18),
		Position = UDim2.new(0.5, 0, 1, -140),
		AnchorPoint = Vector2.new(0.5, 1),
		Color = Theme.Colors.Accent,
		Text = "CAST POWER",
	})
	castBar.Frame.Visible = false

	-- Touch action button
	if UserInputService.TouchEnabled then
		local button = PixelUI.Button({
			Name = "ActionButton",
			Parent = gui,
			Text = "CAST",
			Size = UDim2.fromOffset(104, 104),
			Position = UDim2.new(1, -24, 1, -36),
			AnchorPoint = Vector2.new(1, 1),
			TextSize = Theme.TextSizes.Title,
			Color = Theme.Colors.Accent,
		})
		button.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				HUD.ActionPressed:Fire()
			end
		end)
		button.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				HUD.ActionReleased:Fire()
			end
		end)
		actionButton = button
	end

	State.Changed:Connect(function()
		HUD.Refresh()
	end)
	HUD.Refresh()

	task.spawn(function()
		while true do
			HUD.RefreshWeather()
			task.wait(1)
		end
	end)
end

function HUD.Refresh()
	local profile = State.Profile
	if not profile then
		return
	end
	levelLabel.Text = string.format("LV %d", profile.level)
	local needed = LevelUtil.XPToNext(profile.level)
	xpBar.Set(LevelUtil.Progress(profile), true)
	xpBar.Label.Text = string.format("%s / %s XP", Util.FormatNumber(profile.xp), Util.FormatNumber(needed))
	coinsLabel.Text = Util.FormatNumber(profile.coins) .. " coins"

	local rod = State.GetRod()
	rodLabel.Text = "Rod: " .. rod.name
	local bait = State.GetBait()
	if bait then
		baitLabel.Text = string.format("Bait: %s x%d", bait.name, State.BaitCount(bait.id))
	else
		baitLabel.Text = "Bait: none"
	end

	locationLabel.Text = if State.Location then LocationData.Name(State.Location) else "No water in reach"
	locationLabel.TextColor3 = if State.Location then Theme.Colors.Accent2 else Theme.Colors.TextMuted
end

function HUD.RefreshWeather()
	local clock = Lighting.ClockTime
	local hours = math.floor(clock)
	local minutes = math.floor((clock - hours) * 60)
	weatherLabel.Text = string.format("%s / %s %02d:%02d", State.Weather, Util.TimeOfDay(clock), hours, minutes)
end

function HUD.SetPrompt(text: string?, color: Color3?)
	promptLabel.Text = text or ""
	promptLabel.TextColor3 = color or Theme.Colors.Text
end

-- nil hides the bar.
function HUD.SetCastPower(power: number?)
	if power == nil then
		castBar.Frame.Visible = false
		return
	end
	castBar.Frame.Visible = true
	castBar.Set(power)
end

function HUD.SetActionText(text: string)
	if actionButton then
		actionButton.Text = text
	end
end

return HUD
