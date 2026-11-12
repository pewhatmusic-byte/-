--!strict
-- The fishing state machine. The client only ever sends intent ("I cast here", "I hooked",
-- "I finished the minigame"); the server decides what bit, validates timing and awards the catch.
--
--   Idle --Cast--> Waiting --(bite timer)--> Bite --Hook--> Minigame --Finish--> Idle
--                      \-- Cancel / walked away / died --> Idle

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Config = require(Shared:WaitForChild("Config"))
local RodData = require(Shared:WaitForChild("RodData"))
local ZoneUtil = require(Shared:WaitForChild("ZoneUtil"))
local Util = require(Shared:WaitForChild("Util"))
local Types = require(Shared:WaitForChild("Types"))

local Modules = script.Parent.Parent:WaitForChild("Modules")
local FishGenerator = require(Modules:WaitForChild("FishGenerator"))
local RodBuilder = require(Modules:WaitForChild("RodBuilder"))
local RateLimit = require(Modules:WaitForChild("RateLimit"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local PlayerService = require(script.Parent:WaitForChild("PlayerService"))
local InventoryService = require(script.Parent:WaitForChild("InventoryService"))
local TimeWeatherService = require(script.Parent:WaitForChild("TimeWeatherService"))

local FishingService = {}

type FishingState = {
	phase: string, -- "Idle" | "Waiting" | "Bite" | "Minigame"
	token: number,
	generated: FishGenerator.Generated?,
	params: Types.MinigameParams?,
	rod: Types.RodDef?,
	locationId: string?,
	castPosition: Vector3,
	biteAt: number,
	hookedAt: number,
	bobber: Model?,
}

local states: { [Player]: FishingState } = {}
local rng = Random.new()

local function fishingEvent(): RemoteEvent
	return Net.Event("Fishing")
end

local function effectsFolder(): Instance
	local folder = workspace:FindFirstChild("Effects")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Effects"
		folder.Parent = workspace
	end
	return folder
end

local function getState(player: Player): FishingState
	local state = states[player]
	if not state then
		state = {
			phase = "Idle",
			token = 0,
			generated = nil,
			params = nil,
			rod = nil,
			locationId = nil,
			castPosition = Vector3.zero,
			biteAt = 0,
			hookedAt = 0,
			bobber = nil,
		}
		states[player] = state
	end
	return state
end

-- Inside closures the type checker keeps stale refinements on state.phase; compare through this helper.
local function isPhase(state: FishingState, phase: string): boolean
	return (state :: any).phase == phase
end

local function getRoot(player: Player): BasePart?
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

local function clearBobber(state: FishingState)
	if state.bobber then
		state.bobber:Destroy()
		state.bobber = nil
	end
end

-- Back to Idle. `reason` is shown to the player when given.
local function reset(player: Player, reason: string?)
	local state = getState(player)
	state.token += 1
	state.phase = "Idle"
	state.generated = nil
	state.params = nil
	clearBobber(state)
	fishingEvent():FireClient(player, "Reset", reason)
end

local function escaped(player: Player, reason: string)
	local state = getState(player)
	state.token += 1
	state.phase = "Idle"
	state.generated = nil
	state.params = nil
	clearBobber(state)
	fishingEvent():FireClient(player, "Escaped", reason)
end

local function walkedAway(player: Player, state: FishingState): boolean
	local root = getRoot(player)
	if not root then
		return true
	end
	return (root.Position - state.castPosition).Magnitude > Config.MaxFishingWalkDistance
end

local function createBobber(player: Player, position: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "Bobber"
	model:SetAttribute("Owner", player.UserId)

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(0.7, 0.7, 0.7)
	body.Color = Color3.fromRGB(230, 60, 50)
	body.Material = Enum.Material.SmoothPlastic
	body.Anchored = true
	body.CanCollide = false
	body.CanQuery = false
	body.CanTouch = false
	body.CastShadow = false
	body.Position = position
	body.Parent = model

	local cap = body:Clone()
	cap.Name = "Cap"
	cap.Size = Vector3.new(0.72, 0.3, 0.72)
	cap.Color = Color3.fromRGB(245, 245, 245)
	cap.Position = position + Vector3.new(0, 0.3, 0)
	cap.Parent = model

	local attachment = Instance.new("Attachment")
	attachment.Name = "BobberAttachment"
	attachment.Parent = body

	local tip = RodBuilder.FindTip(player)
	if tip then
		local beam = Instance.new("Beam")
		beam.Name = "Line"
		beam.Attachment0 = tip
		beam.Attachment1 = attachment
		beam.Width0 = 0.07
		beam.Width1 = 0.07
		beam.Color = ColorSequence.new(Color3.fromRGB(240, 240, 240))
		beam.Transparency = NumberSequence.new(0.15)
		beam.FaceCamera = true
		beam.Segments = 1
		beam.Parent = body
	end

	model.PrimaryPart = body
	model.Parent = effectsFolder()
	return model
end

local function handleCast(player: Player, target: any)
	local profile = DataService.Get(player)
	local state = getState(player)
	if not profile or state.phase ~= "Idle" then
		return
	end
	if not Util.IsFiniteVector(target) then
		return
	end
	local root = getRoot(player)
	if not root then
		return
	end
	if not InventoryService.HasSpace(player) then
		reset(player, "Your fish bag is full! Sell some fish at the harbour.")
		return
	end

	local rod = RodData.Get(profile.equippedRod)
	local flatTarget = Vector3.new(target.X, 0, target.Z)
	local flatRoot = Vector3.new(root.Position.X, 0, root.Position.Z)
	local distance = (flatTarget - flatRoot).Magnitude
	if distance < 2 or distance > rod.castRange + 6 then
		reset(player, "Too far to cast there.")
		return
	end

	local zone = ZoneUtil.LocationAt(target)
	if not zone then
		reset(player, "Cast onto the water!")
		return
	end

	local bait = InventoryService.PeekBait(player)
	local luck = rod.luck + (if bait then bait.luck else 0)
	local lure = rod.lureSpeed * (if bait then bait.lureSpeed else 1)
	local generated = FishGenerator.Generate({
		locationId = zone.locationId,
		luck = luck,
		timeOfDay = TimeWeatherService.GetTimeOfDay(),
		weather = TimeWeatherService.GetWeather(),
		rng = rng,
	})
	if not generated then
		reset(player, "Nothing seems to live in these waters...")
		return
	end
	InventoryService.ConsumeBait(player)

	state.token += 1
	local token = state.token
	state.phase = "Waiting"
	state.generated = generated
	state.rod = rod
	state.locationId = zone.locationId
	state.castPosition = root.Position
	clearBobber(state)
	local bobberPosition = Vector3.new(target.X, zone.waterY + 0.35, target.Z)
	state.bobber = createBobber(player, bobberPosition)

	PlayerService.DiscoverLocation(player, zone.locationId)
	fishingEvent():FireClient(player, "Casted", bobberPosition, zone.locationId)

	local delay = rng:NextNumber(Config.BiteDelayMin, Config.BiteDelayMax) / math.max(lure, 0.1)
	task.delay(delay, function()
		if state.token ~= token or not isPhase(state, "Waiting") then
			return
		end
		if walkedAway(player, state) then
			reset(player, "You wandered away from your line.")
			return
		end
		state.phase = "Bite"
		state.biteAt = os.clock()
		fishingEvent():FireClient(player, "Bite")
		task.delay(Config.HookWindow + Config.LatencySlack, function()
			if state.token == token and isPhase(state, "Bite") then
				escaped(player, "Too slow! It spat the hook.")
			end
		end)
	end)
end

local function handleHook(player: Player)
	local state = getState(player)
	if state.phase ~= "Bite" or not state.generated or not state.rod then
		return
	end
	if os.clock() - state.biteAt > Config.HookWindow + Config.LatencySlack then
		escaped(player, "Too slow! It spat the hook.")
		return
	end
	if walkedAway(player, state) then
		reset(player, "You wandered away from your line.")
		return
	end
	local token = state.token
	state.phase = "Minigame"
	state.hookedAt = os.clock()
	state.params = FishGenerator.MinigameParams(state.generated.def, state.generated.fish, state.rod)
	fishingEvent():FireClient(player, "Hooked", state.params)

	task.delay(Config.MaxMinigameDuration, function()
		if state.token == token and isPhase(state, "Minigame") then
			escaped(player, "The line snapped!")
		end
	end)
end

local function handleFinish(player: Player, success: any)
	local state = getState(player)
	local generated, params = state.generated, state.params
	if state.phase ~= "Minigame" or not generated or not params then
		return
	end
	if success ~= true then
		escaped(player, "It slipped off the hook!")
		return
	end
	local elapsed = os.clock() - state.hookedAt
	if elapsed + Config.LatencySlack < params.minDuration then
		-- Faster than the minigame allows: treat as a failed catch.
		warn(string.format("[FishingService] %s finished a minigame impossibly fast (%.2fs < %.2fs)", player.Name, elapsed, params.minDuration))
		escaped(player, "The line snapped!")
		return
	end
	if walkedAway(player, state) then
		reset(player, "You wandered away from your line.")
		return
	end

	local added, isNew = InventoryService.AddFish(player, generated.fish)
	if not added then
		escaped(player, "Your fish bag is full! It wriggled free.")
		return
	end
	local levels = PlayerService.AddXP(player, generated.xp)

	state.token += 1
	state.phase = "Idle"
	state.generated = nil
	state.params = nil
	clearBobber(state)
	fishingEvent():FireClient(player, "Caught", generated.fish, { isNew = isNew, xp = generated.xp, levelsGained = levels })
end

local function handleCancel(player: Player)
	local state = getState(player)
	if state.phase == "Idle" then
		return
	end
	reset(player, "Reeled in.")
end

function FishingService.Init()
	fishingEvent().OnServerEvent:Connect(function(player: Player, action: any, ...: any)
		if not RateLimit.Check(player, "Fishing", Config.RemoteRateLimit) then
			return
		end
		if action == "Cast" then
			handleCast(player, (...))
		elseif action == "Hook" then
			handleHook(player)
		elseif action == "Finish" then
			handleFinish(player, (...))
		elseif action == "Cancel" then
			handleCancel(player)
		end
	end)

	PlayerService.CharacterSpawned:Connect(function(player: Player, character: Model)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Died:Connect(function()
				local state = states[player]
				if state and state.phase ~= "Idle" then
					reset(player)
				end
			end)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local state = states[player]
		if state then
			clearBobber(state)
			states[player] = nil
		end
		RateLimit.Clear(player)
	end)
end

return FishingService
