--!strict
-- Day/night cycle and weather. Fish availability reads from here; clients read Lighting.ClockTime
-- and ReplicatedStorage.WorldState.Weather.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))

local TimeWeatherService = {}

local WEATHERS = { "Clear", "Rain", "Storm" }

local clockTime = Config.StartClockTime
local weatherValue: StringValue? = nil
local eventValue: StringValue? = nil
local rng = Random.new()

local function ensureWorldState(): (StringValue, StringValue)
	local folder = ReplicatedStorage:FindFirstChild("WorldState")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "WorldState"
		folder.Parent = ReplicatedStorage
	end
	local weather = folder:FindFirstChild("Weather")
	if not weather or not weather:IsA("StringValue") then
		weather = Instance.new("StringValue")
		weather.Name = "Weather"
		weather.Value = "Clear"
		weather.Parent = folder
	end
	local event = folder:FindFirstChild("Event")
	if not event or not event:IsA("StringValue") then
		event = Instance.new("StringValue")
		event.Name = "Event"
		event.Value = ""
		event.Parent = folder
	end
	return weather :: StringValue, event :: StringValue
end

function TimeWeatherService.GetWeather(): string
	return if weatherValue then weatherValue.Value else "Clear"
end

function TimeWeatherService.GetTimeOfDay(): string
	return Util.TimeOfDay(clockTime)
end

function TimeWeatherService.GetClockTime(): number
	return clockTime
end

function TimeWeatherService.SetWeather(weather: string)
	if weatherValue and table.find(WEATHERS, weather) then
		weatherValue.Value = weather
	end
end

-- Reserved for the events system (storms, migrations, boss sightings...). Empty string = no event.
function TimeWeatherService.SetEvent(eventId: string)
	if eventValue then
		eventValue.Value = eventId
	end
end

function TimeWeatherService.Init()
	weatherValue, eventValue = ensureWorldState()
	Lighting.ClockTime = clockTime

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt: number)
		clockTime = (clockTime + dt * 24 / Config.DayLengthSeconds) % 24
		accumulator += dt
		if accumulator >= 0.25 then
			accumulator = 0
			Lighting.ClockTime = clockTime
		end
	end)

	task.spawn(function()
		task.wait(rng:NextNumber(Config.WeatherMinDuration, Config.WeatherMaxDuration))
		while true do
			local next = Util.WeightedChoice(rng, WEATHERS, function(weather)
				return (Config.WeatherWeights :: any)[weather] or 0
			end)
			if next and next ~= TimeWeatherService.GetWeather() then
				TimeWeatherService.SetWeather(next)
			end
			task.wait(rng:NextNumber(Config.WeatherMinDuration, Config.WeatherMaxDuration))
		end
	end)
end

return TimeWeatherService
