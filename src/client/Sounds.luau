--!strict
-- Fire-and-forget sound playback using the ids in Config.Sounds.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Sounds = {}

function Sounds.Play(name: string, volume: number?, pitch: number?)
	local id = (Config.Sounds :: { [string]: string })[name]
	if not id or id == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = id
	sound.Volume = volume or 0.5
	sound.PlaybackSpeed = pitch or 1
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, 6)
end

return Sounds
