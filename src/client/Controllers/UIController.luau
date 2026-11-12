--!strict
-- Owns the ScreenGui, HUD, popups and the window manager (one window open at a time), plus the
-- keyboard/gamepad shortcuts and NPC-triggered windows.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Util = require(Shared:WaitForChild("Util"))
local Config = require(Shared:WaitForChild("Config"))
local FishData = require(Shared:WaitForChild("FishData"))
local RodData = require(Shared:WaitForChild("RodData"))
local BaitData = require(Shared:WaitForChild("BaitData"))
local LocationData = require(Shared:WaitForChild("LocationData"))
local RarityData = require(Shared:WaitForChild("RarityData"))
local MutationData = require(Shared:WaitForChild("MutationData"))
local LevelUtil = require(Shared:WaitForChild("LevelUtil"))

local Client = script.Parent.Parent
local UI = Client:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local PixelUI = require(UI:WaitForChild("PixelUI"))
local PixelIcon = require(UI:WaitForChild("PixelIcon"))
local HUD = require(UI:WaitForChild("HUD"))
local NotificationUI = require(UI:WaitForChild("NotificationUI"))
local CatchPopup = require(UI:WaitForChild("CatchPopup"))
local State = require(Client:WaitForChild("ClientState"))
local Sounds = require(Client:WaitForChild("Sounds"))
local Minigame = require(script.Parent:WaitForChild("MinigameController"))

local UIController = {}

export type WindowModule = {
	Name: string,
	Init: (ctx: any) -> (),
	Open: (payload: any?) -> (),
	Close: () -> (),
	IsOpen: () -> boolean,
}

local gui: ScreenGui
local windows: { [string]: WindowModule } = {}
local openWindow: string? = nil

local Windows = {}

-- Every window is a PixelUI.Window: a visible top-level holder with Body.TitleBar inside.
local function findOpenWindowRoot(): Instance?
	for _, child in ipairs(gui:GetChildren()) do
		if child:IsA("Frame") and child.Visible then
			local body = child:FindFirstChild("Body")
			if body and body:FindFirstChild("TitleBar") then
				return child
			end
		end
	end
	return nil
end

local function selectFirstButton()
	if not UserInputService.GamepadEnabled then
		return
	end
	local root = findOpenWindowRoot()
	if not root then
		return
	end
	local fallback: TextButton? = nil
	for _, desc in ipairs(root:GetDescendants()) do
		if desc:IsA("TextButton") and desc.Visible and desc.Selectable then
			if desc.Name ~= "Close" then
				GuiService.SelectedObject = desc
				return
			end
			fallback = fallback or desc
		end
	end
	GuiService.SelectedObject = fallback
end

function Windows.Open(name: string, payload: any?)
	local window = windows[name]
	if not window then
		return
	end
	if openWindow and openWindow ~= name then
		windows[openWindow :: string].Close()
	end
	window.Open(payload)
	openWindow = name
	selectFirstButton()
end

function Windows.Close(name: string)
	local window = windows[name]
	if window then
		window.Close()
	end
	if openWindow == name then
		openWindow = nil
		GuiService.SelectedObject = nil
	end
end

function Windows.CloseAll()
	if openWindow then
		Windows.Close(openWindow)
	end
end

function Windows.IsOpen(name: string): boolean
	return openWindow == name
end

function Windows.Toggle(name: string)
	if openWindow == name then
		Windows.Close(name)
	else
		Windows.Open(name)
	end
end

function UIController.IsAnyWindowOpen(): boolean
	return openWindow ~= nil
end

local function buildContext(): any
	return {
		Gui = gui,
		Theme = Theme,
		PixelUI = PixelUI,
		PixelIcon = PixelIcon,
		Util = Util,
		State = State,
		Net = Net,
		Data = {
			Fish = FishData,
			Rods = RodData,
			Bait = BaitData,
			Locations = LocationData,
			Rarity = RarityData,
			Mutations = MutationData,
			Config = Config,
			Level = LevelUtil,
		},
		Windows = Windows,
		Sounds = Sounds,
		Notify = function(kind: string, text: string)
			NotificationUI.Push(kind, text)
		end,
	}
end

function UIController.Init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = Instance.new("ScreenGui")
	gui.Name = "DriftwakeUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 5
	gui.Parent = playerGui
	PixelUI.Scale(gui)

	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)
	PixelUI.OnClickSound = function()
		Sounds.Play("Click", 0.25)
	end

	NotificationUI.Init(gui)
	HUD.Init(gui, {
		OnInventory = function()
			Windows.Toggle("Inventory")
		end,
		OnBestiary = function()
			Windows.Toggle("Bestiary")
		end,
	})
	CatchPopup.Init(gui)
	Minigame.Init(gui)

	local ctx = buildContext()
	for _, moduleName in ipairs({ "InventoryUI", "BestiaryUI", "ShopUI", "SellUI" }) do
		local module = UI:FindFirstChild(moduleName)
		if module and module:IsA("ModuleScript") then
			local ok, window = pcall(require, module)
			if ok and type(window) == "table" and window.Init then
				local initOk, err = pcall(window.Init, ctx)
				if initOk then
					windows[window.Name] = window
				else
					warn("[UIController] Window " .. moduleName .. " failed to initialise: " .. tostring(err))
				end
			else
				warn("[UIController] Could not load window " .. moduleName .. ": " .. tostring(window))
			end
		end
	end

	ContextActionService:BindAction("DriftwakeInventory", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			Windows.Toggle("Inventory")
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.I, Enum.KeyCode.ButtonY)

	ContextActionService:BindAction("DriftwakeBestiary", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			Windows.Toggle("Bestiary")
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.B, Enum.KeyCode.DPadUp)

	ContextActionService:BindAction("DriftwakeCloseWindow", function(_, inputState)
		if inputState == Enum.UserInputState.Begin and openWindow then
			Windows.CloseAll()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.ButtonB, Enum.KeyCode.Escape)

	Net.Event("Interact").OnClientEvent:Connect(function(action: string, windowName: string, payload: any)
		if action == "OpenWindow" then
			Windows.Open(windowName, payload)
		end
	end)

	Net.Event("Notify").OnClientEvent:Connect(function(kind: string, text: string)
		NotificationUI.Push(kind, text)
		if kind == "levelup" then
			Sounds.Play("LevelUp", 0.6)
		elseif kind == "success" then
			Sounds.Play("Coin", 0.5)
		end
	end)
end

UIController.Windows = Windows

return UIController
