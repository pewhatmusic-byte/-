--!strict
-- Spawns NPCs with ProximityPrompts and wires secret chests. Interactions open client windows
-- (shop / sell) or play dialogue; treasure rewards are granted here, once per player.

local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Config = require(Shared:WaitForChild("Config"))
local IslandData = require(Shared:WaitForChild("IslandData"))
local IslandGen = require(Shared:WaitForChild("IslandGen"))
local Util = require(Shared:WaitForChild("Util"))
local Types = require(Shared:WaitForChild("Types"))

local MapDecor = require(script.Parent.Parent:WaitForChild("Modules"):WaitForChild("MapDecor"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local PlayerService = require(script.Parent:WaitForChild("PlayerService"))

local NPCService = {}

type SecretInfo = { id: string, coins: number, xp: number }

local npcDefs: { [string]: Types.NPCDef } = {}
local npcIslands: { [string]: Types.IslandDef } = {}
local secrets: { [string]: SecretInfo } = {}
local rng = Random.new()

local function makePrompt(parent: BasePart, actionText: string, objectText: string, holdDuration: number): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = holdDuration
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Parent = parent
	return prompt
end

local function spawnNPC(island: Types.IslandDef, def: Types.NPCDef, parent: Instance)
	local position = IslandGen.Polar(island, def.angle, def.distance)
	local facing = if def.facing then def.facing else def.angle + math.pi
	local lookAt = position + Vector3.new(math.cos(facing), 0, math.sin(facing))
	local cframe = CFrame.lookAt(position + Vector3.new(0, 2.5, 0), lookAt + Vector3.new(0, 2.5, 0))

	local model = MapDecor.NPCBody(parent, cframe, def.style, def.name, def.title)
	model.Name = "NPC_" .. def.id
	model:SetAttribute("NpcId", def.id)
	model:SetAttribute("Role", def.role)

	local root = model.PrimaryPart or model:FindFirstChild("Root")
	if root and root:IsA("BasePart") then
		local action = if def.role == "Sell" then "Sell Fish" elseif def.role == "Shop" then "Shop" else "Talk"
		local prompt = makePrompt(root, action, def.name, 0)
		prompt:SetAttribute("NpcId", def.id)
	end
	npcDefs[def.id] = def
	npcIslands[def.id] = island
end

local function wireChest(model: Instance)
	local secretId = model:GetAttribute("SecretId")
	if type(secretId) ~= "string" or not secrets[secretId] then
		return
	end
	local base = if model:IsA("Model") then (model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")) else nil
	if not base then
		return
	end
	local prompt = makePrompt(base, "Open", "Old Chest", 0.5)
	prompt:SetAttribute("SecretId", secretId)
end

local function onPrompt(prompt: ProximityPrompt, player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end

	local npcId = prompt:GetAttribute("NpcId")
	if type(npcId) == "string" then
		local def = npcDefs[npcId]
		local island = npcIslands[npcId]
		if not def or not island then
			return
		end
		if def.role == "Sell" then
			Net.Event("Interact"):FireClient(player, "OpenWindow", "Sell", { npcName = def.name })
		elseif def.role == "Shop" then
			Net.Event("Interact"):FireClient(player, "OpenWindow", "Shop", { shop = island.id, npcName = def.name })
		else
			local line = def.lines[rng:NextInteger(1, math.max(#def.lines, 1))] or "..."
			PlayerService.Notify(player, "dialogue", def.name .. ": " .. line)
		end
		return
	end

	local secretId = prompt:GetAttribute("SecretId")
	if type(secretId) == "string" then
		local info = secrets[secretId]
		if not info then
			return
		end
		if profile.treasures[secretId] then
			PlayerService.Notify(player, "info", "Empty. You already found this one.")
			return
		end
		profile.treasures[secretId] = true
		PlayerService.Patch(player, { treasures = profile.treasures })
		PlayerService.AddCoins(player, info.coins)
		PlayerService.AddXP(player, info.xp)
		PlayerService.Notify(player, "success", string.format("Hidden treasure! +%s coins", Util.FormatNumber(info.coins)))
	end
end

function NPCService.Init()
	local world = workspace:FindFirstChild("World") or workspace
	local folder = Instance.new("Folder")
	folder.Name = "NPCs"
	folder.Parent = world

	for _, island in ipairs(IslandData.Enabled()) do
		for _, secret in ipairs(island.secrets) do
			secrets[secret.id] = { id = secret.id, coins = secret.coins, xp = secret.xp or Config.SecretTreasureXP }
		end
		for _, def in ipairs(island.npcs) do
			spawnNPC(island, def, folder)
		end
	end

	for _, chest in ipairs(CollectionService:GetTagged("SecretChest")) do
		wireChest(chest)
	end
	CollectionService:GetInstanceAddedSignal("SecretChest"):Connect(wireChest)

	ProximityPromptService.PromptTriggered:Connect(onPrompt)
end

return NPCService
