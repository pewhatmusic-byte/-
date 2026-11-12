--!strict
-- Global tuning values. Everything gameplay-related that is "a number someone will want to tweak" lives here.

local Config = {
	GameName = "Driftwake Isles",

	-- Data persistence
	DataStoreName = "DriftwakeProfiles_v1",
	DataVersion = 1,
	AutosaveInterval = 120,
	SessionLockTimeout = 15 * 60,
	LoadRetries = 4,
	LoadRetryDelay = 2,

	-- Inventory
	FishCapacity = 40,

	-- Fishing
	CastMinRange = 8,
	CastChargeTime = 1.1, -- seconds to fully charge a cast
	BiteDelayMin = 3,
	BiteDelayMax = 11,
	HookWindow = 1.4, -- seconds the player has to react to a bite
	LatencySlack = 0.5,
	MaxMinigameDuration = 60,
	MinigameStartProgress = 0.35,
	MaxFishingWalkDistance = 7, -- walking farther than this from the cast point cancels the cast
	RemoteRateLimit = 12, -- max client -> server messages per second

	-- Progression
	DiscoverLocationXP = 60,
	SecretTreasureXP = 150,

	-- World
	OceanLevel = 0,
	SeaFloorY = -24,
	OceanSize = 1400,
	CellSize = 4,
	HeightStep = 1.5,
	DayLengthSeconds = 14 * 60,
	StartClockTime = 9,
	WeatherMinDuration = 4 * 60,
	WeatherMaxDuration = 8 * 60,
	WeatherWeights = { Clear = 62, Rain = 26, Storm = 12 },

	-- Built-in Roblox sounds (no uploads needed). Replace with your own asset ids for a custom feel.
	Sounds = {
		Click = "rbxasset://sounds/button.wav",
		Splash = "rbxasset://sounds/impact_water.mp3",
		Cast = "rbxasset://sounds/swoosh.wav",
		Bite = "rbxasset://sounds/electronicpingshort.wav",
		Catch = "rbxasset://sounds/victory.wav",
		Fail = "rbxasset://sounds/snap.wav",
		Coin = "rbxasset://sounds/clickfast.wav",
		LevelUp = "rbxasset://sounds/bass.wav",
	},
}

return Config
