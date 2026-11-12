--!strict
-- The reel-in minigame. A fish marker darts along a track; the player holds the action input to
-- push the catch zone right and releases to let it drift left. Keeping the fish inside the zone
-- fills the catch bar, losing it drains the bar. Runs on the client; the server validates timing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RarityData = require(Shared:WaitForChild("RarityData"))
local Util = require(Shared:WaitForChild("Util"))
local Types = require(Shared:WaitForChild("Types"))

local UI = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local PixelUI = require(UI:WaitForChild("PixelUI"))
local PixelIcon = require(UI:WaitForChild("PixelIcon"))
local State = require(script.Parent.Parent:WaitForChild("ClientState"))

local Minigame = {}

local TRACK_WIDTH = 520
local MAX_ZONE_SPEED = 1.7
local EDGE_BOUNCE = 0.35

local holder: Frame
local track: Frame
local zoneFrame: Frame
local fishMarker: Frame
local progressBar: PixelUI.ProgressBar
local hintLabel: TextLabel
local titleLabel: TextLabel

local active = false
local held = false
local connection: RBXScriptConnection? = nil
local rng = Random.new()

type Run = {
	params: Types.MinigameParams,
	onFinish: (success: boolean) -> (),
	zoneCenter: number,
	zoneVelocity: number,
	fishX: number,
	fishTarget: number,
	retarget: number,
	progress: number,
	elapsed: number,
	accel: number,
}
local run: Run? = nil

function Minigame.Init(gui: ScreenGui)
	local h, body = PixelUI.Panel({
		Name = "Minigame",
		Parent = gui,
		Size = UDim2.fromOffset(TRACK_WIDTH + 40, 150),
		Position = UDim2.new(0.5, 0, 1, -40),
		AnchorPoint = Vector2.new(0.5, 1),
		Visible = false,
		ZIndex = 15,
	})
	holder = h
	PixelUI.Padding(body, 20, 12)

	titleLabel = PixelUI.Label({ Parent = body, Text = "REEL IT IN!", TextSize = Theme.TextSizes.Title, Color = Theme.Colors.Accent, Size = UDim2.new(1, 0, 0, 22), ZIndex = 3 })
	hintLabel = PixelUI.Label({ Parent = body, Text = "", Size = UDim2.new(1, 0, 0, 22), XAlign = Enum.TextXAlignment.Right, TextSize = Theme.TextSizes.Tiny, Color = Theme.Colors.TextMuted, ZIndex = 3 })

	track = PixelUI.Frame({
		Name = "Track",
		Parent = body,
		Size = UDim2.new(1, 0, 0, 44),
		Position = UDim2.fromOffset(0, 32),
		Color = Theme.Colors.PanelDark,
		Border = true,
		ZIndex = 3,
	})
	zoneFrame = PixelUI.Frame({
		Name = "Zone",
		Parent = track,
		Size = UDim2.fromScale(0.3, 1),
		Color = Theme.Colors.Accent2,
		BackgroundTransparency = 0.25,
		Border = true,
		BorderColor = Theme.Colors.Text,
		Thickness = 2,
		ZIndex = 4,
	})
	fishMarker = PixelUI.Frame({
		Name = "Fish",
		Parent = track,
		Size = UDim2.fromOffset(42, 28),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 6,
	})

	progressBar = PixelUI.ProgressBar({
		Parent = body,
		Position = UDim2.fromOffset(0, 86),
		Size = UDim2.new(1, 0, 0, 22),
		Color = Theme.Colors.Success,
		Text = "CATCH",
		ZIndex = 3,
	})
end

local function renderFishMarker(rarity: string)
	for _, child in ipairs(fishMarker:GetChildren()) do
		child:Destroy()
	end
	local color = RarityData.Color(rarity)
	PixelIcon.Render(fishMarker, {
		id = "marker", name = "", rarity = rarity :: any, locations = {}, baseValue = 0, minWeight = 0, maxWeight = 0,
		time = "Any", weather = "Any", shape = "Round", color1 = color, color2 = Util.Lighten(color, 0.4), description = "",
	}, { ZIndex = 7 })
end

local function stopLoop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
end

local function finish(success: boolean)
	local current = run
	if not current then
		return
	end
	run = nil
	active = false
	held = false
	stopLoop()
	holder.Visible = false
	current.onFinish(success)
end

local function step(dt: number)
	local current = run
	if not current then
		return
	end
	dt = math.min(dt, 0.05)
	local p = current.params
	current.elapsed += dt

	-- zone physics
	current.zoneVelocity += (if held then current.accel else -current.accel) * dt
	current.zoneVelocity = math.clamp(current.zoneVelocity, -MAX_ZONE_SPEED, MAX_ZONE_SPEED)
	current.zoneCenter += current.zoneVelocity * dt
	local half = p.zoneSize / 2
	if current.zoneCenter < half then
		current.zoneCenter = half
		current.zoneVelocity = -current.zoneVelocity * EDGE_BOUNCE
	elseif current.zoneCenter > 1 - half then
		current.zoneCenter = 1 - half
		current.zoneVelocity = -current.zoneVelocity * EDGE_BOUNCE
	end

	-- fish behaviour: pick a new target now and then, dash when strong
	current.retarget -= dt
	if current.retarget <= 0 then
		local dash = rng:NextNumber() < p.strength * 0.5
		if dash then
			current.fishTarget = if current.fishX < 0.5 then rng:NextNumber(0.7, 0.96) else rng:NextNumber(0.04, 0.3)
		else
			current.fishTarget = rng:NextNumber(0.04, 0.96)
		end
		current.retarget = rng:NextNumber(0.35, 1.4) / (0.6 + p.strength)
	end
	local delta = current.fishTarget - current.fishX
	local move = math.min(math.abs(delta), p.speed * dt)
	current.fishX += (if delta < 0 then -move else move)
	current.fishX += math.sin(current.elapsed * 7) * 0.004 * p.strength
	current.fishX = math.clamp(current.fishX, 0, 1)

	-- progress
	local inZone = math.abs(current.fishX - current.zoneCenter) <= half + 0.015
	current.progress += (if inZone then p.fillRate else -p.drainRate) * dt

	-- render
	zoneFrame.Size = UDim2.fromScale(p.zoneSize, 1)
	zoneFrame.Position = UDim2.fromScale(current.zoneCenter - half, 0)
	zoneFrame.BackgroundColor3 = if inZone then Theme.Colors.Success else Theme.Colors.Accent2
	fishMarker.Position = UDim2.fromScale(current.fishX, 0.5)
	progressBar.Set(current.progress)
	progressBar.Fill.BackgroundColor3 = if inZone then Theme.Colors.Success else Theme.Colors.Danger

	if current.progress >= 1 then
		finish(true)
	elseif current.progress <= 0 then
		finish(false)
	end
end

function Minigame.Start(params: Types.MinigameParams, onFinish: (success: boolean) -> ())
	Minigame.Stop()
	local rod = State.GetRod()
	run = {
		params = params,
		onFinish = onFinish,
		zoneCenter = 0.5,
		zoneVelocity = 0,
		fishX = 0.5,
		fishTarget = 0.5,
		retarget = 0.4,
		progress = params.startProgress,
		elapsed = 0,
		accel = 1.7 + math.clamp(rod.control, 0, 100) / 100 * 1.3,
	}
	active = true
	held = false
	renderFishMarker(params.rarity)
	titleLabel.Text = if params.heavy then "THE LINE STRAINS!" else "REEL IT IN!"
	titleLabel.TextColor3 = if params.heavy then Theme.Colors.Danger else Theme.Colors.Accent
	hintLabel.Text = "HOLD = right   RELEASE = left"
	holder.Visible = true
	stopLoop()
	connection = RunService.RenderStepped:Connect(step)
end

function Minigame.SetInput(isHeld: boolean)
	held = isHeld
end

function Minigame.Stop()
	run = nil
	active = false
	held = false
	stopLoop()
	if holder then
		holder.Visible = false
	end
end

function Minigame.IsActive(): boolean
	return active
end

return Minigame
