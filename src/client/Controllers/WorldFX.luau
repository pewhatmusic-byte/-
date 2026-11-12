--!strict
-- Client-only atmosphere: weather visuals (rain, storm darkening, lightning), bobber bobbing and
-- pixel ripple rings. Nothing here affects gameplay.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local State = require(script.Parent.Parent:WaitForChild("ClientState"))

local WorldFX = {}

local player = Players.LocalPlayer
local rng = Random.new()

local rainPart: Part? = nil
local rainEmitter: ParticleEmitter? = nil
local lightningThread: thread? = nil

local myBobber: BasePart? = nil
local bobberBase: Vector3? = nil
local biting = false
local rippleTimer = 0

local DEFAULT_ATMOSPHERE = { Density = 0.3, Haze = 1.4, Color = Color3.fromRGB(199, 219, 242) }
local DEFAULT_AMBIENT = Color3.fromRGB(92, 102, 128)

local function atmosphere(): Atmosphere?
	return Lighting:FindFirstChildOfClass("Atmosphere")
end

local function ensureRain(): ParticleEmitter
	if rainEmitter and rainPart and rainPart.Parent then
		return rainEmitter
	end
	local part = Instance.new("Part")
	part.Name = "RainVolume"
	part.Size = Vector3.new(90, 1, 90)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Parent = workspace.CurrentCamera

	local emitter = Instance.new("ParticleEmitter")
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.EmissionDirection = Enum.NormalId.Bottom
	emitter.Color = ColorSequence.new(Color3.fromRGB(190, 220, 255))
	emitter.Size = NumberSequence.new(0.25)
	emitter.Transparency = NumberSequence.new(0.35)
	emitter.Lifetime = NumberRange.new(1.2, 1.6)
	emitter.Speed = NumberRange.new(55, 70)
	emitter.Acceleration = Vector3.new(0, -40, 0)
	emitter.Rate = 0
	emitter.LightEmission = 0.2
	emitter.Enabled = true
	emitter.Parent = part

	rainPart = part
	rainEmitter = emitter
	return emitter
end

local function stopLightning()
	if lightningThread then
		task.cancel(lightningThread)
		lightningThread = nil
	end
end

local function startLightning()
	stopLightning()
	lightningThread = task.spawn(function()
		while true do
			task.wait(rng:NextNumber(6, 16))
			local before = Lighting.Brightness
			Lighting.Brightness = before + 3
			Lighting.Ambient = Color3.fromRGB(220, 225, 255)
			task.wait(0.08)
			Lighting.Brightness = before
			Lighting.Ambient = Color3.fromRGB(60, 64, 90)
		end
	end)
end

function WorldFX.ApplyWeather(weather: string)
	local atmo = atmosphere()
	local tweenInfo = TweenInfo.new(2, Enum.EasingStyle.Quad)
	if weather == "Clear" then
		if atmo then
			TweenService:Create(atmo, tweenInfo, DEFAULT_ATMOSPHERE):Play()
		end
		TweenService:Create(Lighting, tweenInfo, { Ambient = DEFAULT_AMBIENT }):Play()
		if rainEmitter then
			rainEmitter.Rate = 0
		end
		stopLightning()
	elseif weather == "Rain" then
		if atmo then
			TweenService:Create(atmo, tweenInfo, { Density = 0.45, Haze = 2.4, Color = Color3.fromRGB(170, 185, 205) }):Play()
		end
		TweenService:Create(Lighting, tweenInfo, { Ambient = Color3.fromRGB(78, 84, 104) }):Play()
		ensureRain().Rate = 260
		stopLightning()
	elseif weather == "Storm" then
		if atmo then
			TweenService:Create(atmo, tweenInfo, { Density = 0.6, Haze = 3, Color = Color3.fromRGB(130, 140, 160) }):Play()
		end
		TweenService:Create(Lighting, tweenInfo, { Ambient = Color3.fromRGB(60, 64, 90) }):Play()
		ensureRain().Rate = 520
		startLightning()
	end
end

-- A ring of small cubes that expands and fades: a pixel-art ripple.
local function ripple(position: Vector3, size: number)
	local folder = workspace:FindFirstChild("Effects") or workspace
	local cubes = {}
	for i = 1, 8 do
		local cube = Instance.new("Part")
		cube.Size = Vector3.new(0.35, 0.12, 0.35)
		cube.Color = Color3.fromRGB(235, 245, 255)
		cube.Material = Enum.Material.SmoothPlastic
		cube.Anchored = true
		cube.CanCollide = false
		cube.CanQuery = false
		cube.CanTouch = false
		cube.CastShadow = false
		cube.Position = position
		cube.Parent = folder
		cubes[i] = cube
	end
	task.spawn(function()
		local duration = 0.9
		local start = os.clock()
		while true do
			local t = (os.clock() - start) / duration
			if t >= 1 then
				break
			end
			local radius = 0.4 + t * size
			for i, cube in ipairs(cubes) do
				local angle = (i / 8) * math.pi * 2
				cube.Position = position + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
				cube.Transparency = t
			end
			RunService.RenderStepped:Wait()
		end
		for _, cube in ipairs(cubes) do
			cube:Destroy()
		end
	end)
end

function WorldFX.OnCast(position: Vector3)
	ripple(position - Vector3.new(0, 0.3, 0), 3)
end

function WorldFX.SetBiteState(isBiting: boolean)
	biting = isBiting
	if isBiting and bobberBase then
		ripple(bobberBase - Vector3.new(0, 0.3, 0), 2)
	end
end

local function trackBobber(model: Instance)
	if not model:IsA("Model") or model.Name ~= "Bobber" or model:GetAttribute("Owner") ~= player.UserId then
		return
	end
	local body = model:WaitForChild("Body", 2)
	if body and body:IsA("BasePart") then
		myBobber = body
		bobberBase = body.Position
		rippleTimer = 0
	end
end

local function animate(dt: number)
	-- rain volume rides along above the camera
	local camera = workspace.CurrentCamera
	if rainPart and rainEmitter and rainEmitter.Rate > 0 and camera then
		rainPart.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, 32, 0))
	end

	local bobber, base = myBobber, bobberBase
	if not bobber or not base then
		return
	end
	if not bobber.Parent then
		myBobber = nil
		bobberBase = nil
		return
	end
	local t = os.clock()
	local offset = if biting then -0.6 + math.sin(t * 24) * 0.15 else math.sin(t * 2.2) * 0.18
	bobber.Position = base + Vector3.new(0, offset, 0)
	local cap = bobber.Parent:FindFirstChild("Cap")
	if cap and cap:IsA("BasePart") then
		cap.Position = bobber.Position + Vector3.new(0, 0.3, 0)
	end
	rippleTimer += dt
	if rippleTimer > (if biting then 0.35 else 1.4) then
		rippleTimer = 0
		ripple(base - Vector3.new(0, 0.3, 0), if biting then 1.6 else 1.1)
	end
end

function WorldFX.Init()
	local effects = workspace:WaitForChild("Effects", 30)
	if effects then
		effects.ChildAdded:Connect(trackBobber)
		for _, child in ipairs(effects:GetChildren()) do
			trackBobber(child)
		end
	end
	RunService.RenderStepped:Connect(animate)

	WorldFX.ApplyWeather(State.Weather)
	State.Changed:Connect(function(key: string)
		if key == "weather" then
			WorldFX.ApplyWeather(State.Weather)
		end
	end)
end

return WorldFX
