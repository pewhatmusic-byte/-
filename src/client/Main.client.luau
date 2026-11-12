--!strict
-- Client bootstrap.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local Client = script.Parent
local State = require(Client:WaitForChild("ClientState"))
local Controllers = Client:WaitForChild("Controllers")
local UIController = require(Controllers:WaitForChild("UIController"))
local WorldFX = require(Controllers:WaitForChild("WorldFX"))
local FishingController = require(Controllers:WaitForChild("FishingController"))

State.Init()
UIController.Init()
WorldFX.Init()
FishingController.Init(UIController.IsAnyWindowOpen)

print(string.format("[%s] Client ready", Config.GameName))
