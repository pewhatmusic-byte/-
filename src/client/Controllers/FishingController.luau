--!strict
-- Client side of fishing: cross-platform input, cast charging, bite reaction and running the
-- minigame. All outcomes come from the server.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Config = require(Shared:WaitForChild("Config"))
local ZoneUtil = require(Shared:WaitForChild("ZoneUtil"))
local Types = require(Shared:WaitForChild("Types"))

local Client = script.Parent.Parent
local State = require(Client:WaitForChild("ClientState"))
local Sounds = require(Client:WaitForChild("Sounds"))
local HUD = require(Client:WaitForChild("UI"):WaitForChild("HUD"))
local CatchPopup = require(Client:WaitForChild("UI"):WaitForChild("CatchPopup"))
local NotificationUI = require(Client:WaitForChild("UI"):WaitForChild("NotificationUI"))
local Minigame = require(script.Parent:WaitForChild("MinigameController"))
local WorldFX = require(script.Parent:WaitForChild("WorldFX"))

local FishingController = {}

local ACTION = "DriftwakeFishAction"

local player = Players.LocalPlayer
local phase = "Idle" -- Idle | Charging | Casting | Waiting | Bite | Hooking | Minigame | Finishing
local chargeStart = 0
local chargeConnection: RBXScriptConnection? = nil
local castPosition: Vector3? = nil
local inputBlocked: () -> boolean = function()
	return false
end

local function touchOnly(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and not UserInputService.GamepadEnabled
end

local function getRoot(): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Casts go where the player is looking (camera), falling back to the character's facing.
local function flatLook(root: BasePart): Vector3
	local camera = workspace.CurrentCamera
	local look = if camera then camera.CFrame.LookVector else root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.05 then
		look = root.CFrame.LookVector
		flat = Vector3.new(look.X, 0, look.Z)
	end
	if flat.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

local function castTarget(power: number): Vector3?
	local root = getRoot()
	if not root then
		return nil
	end
	local rod = State.GetRod()
	local range = Config.CastMinRange + power * (rod.castRange - Config.CastMinRange)
	return root.Position + flatLook(root) * range
end

local function setPhase(newPhase: string)
	phase = newPhase
	State.SetFishingPhase(newPhase)
	local actionLabel = "CAST"
	if newPhase == "Idle" then
		HUD.SetPrompt(if touchOnly() then "HOLD CAST to charge, release to cast" else "HOLD click / F / R2 to charge, release to cast")
	elseif newPhase == "Charging" then
		HUD.SetPrompt("Release to cast!", nil)
	elseif newPhase == "Waiting" then
		HUD.SetPrompt("Waiting for a bite...  (press to reel in)")
		actionLabel = "REEL"
	elseif newPhase == "Bite" then
		HUD.SetPrompt("!!!  HOOK IT  !!!", Color3.fromRGB(255, 220, 90))
		actionLabel = "HOOK!"
	elseif newPhase == "Minigame" then
		HUD.SetPrompt("")
		actionLabel = "HOLD"
	else
		HUD.SetPrompt("")
	end
	HUD.SetActionText(actionLabel)
end

local function stopCharging()
	if chargeConnection then
		chargeConnection:Disconnect()
		chargeConnection = nil
	end
	HUD.SetCastPower(nil)
end

-- Power swings 0 -> 1 -> 0 so releasing at the right moment matters.
local function currentPower(): number
	local t = (os.clock() - chargeStart) / Config.CastChargeTime
	local cycle = t % 2
	return if cycle <= 1 then cycle else 2 - cycle
end

local function beginCharge()
	if not getRoot() then
		return
	end
	setPhase("Charging")
	chargeStart = os.clock()
	HUD.SetCastPower(0)
	chargeConnection = RunService.RenderStepped:Connect(function()
		HUD.SetCastPower(currentPower())
	end)
end

local function releaseCast()
	local power = currentPower()
	stopCharging()
	local target = castTarget(power)
	if not target then
		setPhase("Idle")
		return
	end
	if not ZoneUtil.LocationAt(target) then
		NotificationUI.Push("error", "Face the water and try again!")
		setPhase("Idle")
		return
	end
	setPhase("Casting")
	Sounds.Play("Cast", 0.4, 1.1)
	Net.Event("Fishing"):FireServer("Cast", target)
end

local function onPress()
	if inputBlocked() then
		return
	end
	if phase == "Idle" then
		beginCharge()
	elseif phase == "Waiting" then
		Net.Event("Fishing"):FireServer("Cancel")
	elseif phase == "Bite" then
		setPhase("Hooking")
		Net.Event("Fishing"):FireServer("Hook")
	elseif phase == "Minigame" then
		Minigame.SetInput(true)
	end
end

local function onRelease()
	if phase == "Charging" then
		releaseCast()
	elseif phase == "Minigame" then
		Minigame.SetInput(false)
	end
end

local function resetToIdle()
	stopCharging()
	Minigame.Stop()
	castPosition = nil
	WorldFX.SetBiteState(false)
	setPhase("Idle")
end

local function onServerEvent(action: string, a: any, b: any)
	if action == "Casted" then
		castPosition = (getRoot() or { Position = Vector3.zero }).Position
		setPhase("Waiting")
		Sounds.Play("Splash", 0.6)
		WorldFX.OnCast(a)
	elseif action == "Bite" then
		setPhase("Bite")
		Sounds.Play("Bite", 0.7)
		WorldFX.SetBiteState(true)
	elseif action == "Hooked" then
		WorldFX.SetBiteState(false)
		setPhase("Minigame")
		Minigame.Start(a :: Types.MinigameParams, function(success)
			setPhase("Finishing")
			Net.Event("Fishing"):FireServer("Finish", success)
		end)
	elseif action == "Caught" then
		resetToIdle()
		Sounds.Play("Catch", 0.6)
		CatchPopup.Show(a, b or {})
	elseif action == "Escaped" then
		resetToIdle()
		Sounds.Play("Fail", 0.6)
		NotificationUI.Push("error", tostring(a))
	elseif action == "Reset" then
		resetToIdle()
		if a then
			NotificationUI.Push("info", tostring(a))
		end
	end
end

-- Keeps State.Location up to date (what the HUD shows) and cancels when the player walks off.
local function watchLoop()
	while true do
		task.wait(0.25)
		local root = getRoot()
		if not root then
			if phase ~= "Idle" then
				resetToIdle()
			end
			State.SetLocation(nil)
			continue
		end
		local here = ZoneUtil.LocationAt(root.Position)
		local ahead = ZoneUtil.LocationAt(root.Position + flatLook(root) * (Config.CastMinRange + State.GetRod().castRange * 0.4))
		local info = here or ahead
		State.SetLocation(if info then info.locationId else nil)

		if castPosition and (phase == "Waiting" or phase == "Bite" or phase == "Minigame") then
			if (root.Position - castPosition).Magnitude > Config.MaxFishingWalkDistance - 1 then
				Net.Event("Fishing"):FireServer("Cancel")
				resetToIdle()
			end
		end
	end
end

-- `isBlocked` returns true while a window is open so clicks on UI never cast.
function FishingController.Init(isBlocked: () -> boolean)
	inputBlocked = isBlocked

	ContextActionService:BindAction(ACTION, function(_, inputState: Enum.UserInputState)
		if inputState == Enum.UserInputState.Begin then
			onPress()
		elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
			onRelease()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.UserInputType.MouseButton1, Enum.KeyCode.F, Enum.KeyCode.ButtonR2, Enum.KeyCode.ButtonR1)

	HUD.ActionPressed:Connect(onPress)
	HUD.ActionReleased:Connect(onRelease)

	Net.Event("Fishing").OnClientEvent:Connect(onServerEvent)

	player.CharacterAdded:Connect(function()
		resetToIdle()
	end)

	setPhase("Idle")
	task.spawn(watchLoop)
end

function FishingController.GetPhase(): string
	return phase
end

return FishingController
