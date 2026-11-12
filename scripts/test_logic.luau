--!nonstrict
-- Standalone logic tests for the pure modules (no Roblox needed).
-- Run from the repository root:  python3 scripts/run_tests.py   (needs the `luau` CLI on PATH or LUAU=...)
-- Roblox globals used by the shared modules are stubbed just enough for the logic to run.

local ROOT = "src/"

-- ---------------------------------------------------------------- Roblox stubs
local Vector3Meta = {}
Vector3Meta.__index = function(v, key)
	if key == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	elseif key == "Unit" then
		local m = v.Magnitude
		return Vector3.new(v.X / m, v.Y / m, v.Z / m)
	end
	return Vector3Meta[key]
end
Vector3Meta.__add = function(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
Vector3Meta.__sub = function(a, b) return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
Vector3Meta.__mul = function(a, b)
	if type(a) == "number" then return Vector3.new(a * b.X, a * b.Y, a * b.Z) end
	if type(b) == "number" then return Vector3.new(a.X * b, a.Y * b, a.Z * b) end
	return Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
Vector3Meta.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
Vector3Meta.__tostring = function(v) return string.format("(%.2f, %.2f, %.2f)", v.X, v.Y, v.Z) end
Vector3 = {}
function Vector3.new(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, Vector3Meta) end
Vector3.zero = Vector3.new(0, 0, 0)

local Color3Meta = { __index = {} }
Color3 = {}
function Color3.new(r, g, b) return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, Color3Meta) end
function Color3.fromRGB(r, g, b) return Color3.new(r / 255, g / 255, b / 255) end
Color3Meta.__eq = function(a, b) return a.R == b.R and a.G == b.G and a.B == b.B end
function Color3Meta.__index.Lerp(a, b, t) return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t) end

local RandomMeta = { __index = {} }
Random = {}
function Random.new(seed)
	local state = (seed or os.clock() * 1e6) % 2147483647
	if state <= 0 then state = state + 2147483646 end
	return setmetatable({ _state = state }, RandomMeta)
end
local function nextUnit(self)
	self._state = (self._state * 48271) % 2147483647
	return (self._state - 1) / 2147483646
end
function RandomMeta.__index.NextNumber(self, min, max)
	local u = nextUnit(self)
	if min == nil then return u end
	return min + (max - min) * u
end
function RandomMeta.__index.NextInteger(self, min, max)
	return min + math.floor(nextUnit(self) * (max - min + 1))
end

-- value noise in roughly [-0.5, 0.5], deterministic; a stand-in for math.noise.
-- The builtin math table is read-only in the CLI, so shadow it with a wrapper.
local function hash3(x, y, z)
	local n = math.sin(x * 127.1 + y * 311.7 + z * 74.7) * 43758.5453
	return n - math.floor(n)
end
local function smooth(t) return t * t * (3 - 2 * t) end
local realMath = math
math = setmetatable({}, { __index = realMath })
math.noise = function(x, y, z)
	y = y or 0; z = z or 0
	local x0, y0, z0 = math.floor(x), math.floor(y), math.floor(z)
	local fx, fy, fz = smooth(x - x0), smooth(y - y0), smooth(z - z0)
	local function lerp(a, b, t) return a + (b - a) * t end
	local c00 = lerp(hash3(x0, y0, z0), hash3(x0 + 1, y0, z0), fx)
	local c10 = lerp(hash3(x0, y0 + 1, z0), hash3(x0 + 1, y0 + 1, z0), fx)
	local c01 = lerp(hash3(x0, y0, z0 + 1), hash3(x0 + 1, y0, z0 + 1), fx)
	local c11 = lerp(hash3(x0, y0 + 1, z0 + 1), hash3(x0 + 1, y0 + 1, z0 + 1), fx)
	return lerp(lerp(c00, c10, fy), lerp(c01, c11, fy), fz) - 0.5
end

local nativeTypeof = typeof
typeof = function(v)
	if type(v) == "table" and getmetatable(v) == Vector3Meta then return "Vector3" end
	return nativeTypeof(v)
end

-- Instance-tree proxy: script.Parent.X / :WaitForChild("X") resolve to files under ROOT.
local cache = {}
local function proxy(path)
	local p = { __path = path }
	return setmetatable(p, {
		__index = function(_, key)
			if key == "Parent" then
				return proxy(path:match("^(.*)/[^/]+$") or path)
			elseif key == "WaitForChild" or key == "FindFirstChild" then
				return function(_, name) return proxy(path .. "/" .. name) end
			end
			return proxy(path .. "/" .. key)
		end,
	})
end
local rootProxy = proxy("")
game = { GetService = function(_, name)
	if name == "ReplicatedStorage" then
		return setmetatable({}, { __index = function(_, key)
			if key == "WaitForChild" or key == "FindFirstChild" then
				return function(_, name) return proxy(name == "Shared" and ROOT .. "shared" or ROOT .. name) end
			end
			return proxy(key == "Shared" and ROOT .. "shared" or ROOT .. key)
		end })
	end
	return { IsServer = function() return true end, IsClient = function() return false end, IsStudio = function() return true end }
end }
workspace = {}
task = { spawn = function(f, ...) f(...) end, delay = function() end, wait = function() end, defer = function(f, ...) f(...) end }
Enum = setmetatable({}, { __index = function(_, k) return setmetatable({}, { __index = function(_, k2) return k .. "." .. k2 end }) end })

local nativeRequire = require
require = function(target)
	if type(target) ~= "table" then return nativeRequire(target) end
	local file = target.__path
	if cache[file] ~= nil then return cache[file] end
	-- __SOURCES is injected by scripts/run_tests.py (the Luau CLI has no file IO)
	local source = __SOURCES[file]
	assert(source, "no bundled source for " .. file)
	local chunk, err = loadstring(source, "=" .. file)
	assert(chunk, err)
	local previous = script
	script = proxy(target.__path)
	local result = chunk()
	script = previous
	cache[file] = result
	return result
end

-- ---------------------------------------------------------------- tiny test framework
local passed, failed = 0, 0
local function check(condition, message)
	if condition then passed += 1 else failed += 1; print("  FAIL: " .. message) end
end
local function section(name) print("== " .. name) end

local shared = function(name) return require(proxy(ROOT .. "shared/" .. name)) end
local serverModule = function(name) return require(proxy(ROOT .. "server/Modules/" .. name)) end

-- ---------------------------------------------------------------- data integrity
section("Data integrity")
local FishData = shared("FishData")
local LocationData = shared("LocationData")
local RarityData = shared("RarityData")
local RodData = shared("RodData")
local BaitData = shared("BaitData")
local MutationData = shared("MutationData")
local IslandData = shared("IslandData")
local Config = shared("Config")

check(#FishData.List >= 80, "at least 80 fish defined (" .. #FishData.List .. ")")
for _, fish in ipairs(FishData.List) do
	check(fish.minWeight > 0 and fish.maxWeight > fish.minWeight, fish.id .. " weight range")
	check(fish.baseValue > 0, fish.id .. " base value")
	check(#fish.locations > 0, fish.id .. " has locations")
	for _, loc in ipairs(fish.locations) do
		check(LocationData.ById[loc] ~= nil, fish.id .. " unknown location " .. loc)
	end
	check(({ Any = 1, Day = 1, Night = 1 })[fish.time], fish.id .. " time condition")
	check(({ Any = 1, Clear = 1, Rain = 1, Storm = 1 })[fish.weather], fish.id .. " weather condition")
end
for _, loc in ipairs(LocationData.List) do
	local pool = FishData.PoolFor(loc.id)
	if loc.id ~= "drowned_belltower" then
		check(#pool >= 3, loc.name .. " has at least 3 fish (" .. #pool .. ")")
		local hasCommonAnyTime = false
		for _, fish in ipairs(pool) do
			if fish.rarity == "Common" and fish.time == "Any" and fish.weather == "Any" then hasCommonAnyTime = true end
		end
		check(hasCommonAnyTime, loc.name .. " always has a common fish available")
	end
end
check(RodData.ById[RodData.DefaultRod] ~= nil, "default rod exists")
for _, rod in ipairs(RodData.List) do
	check(rod.castRange >= Config.CastMinRange + 10, rod.id .. " cast range sane")
	check(rod.maxWeight > 0 and rod.lureSpeed > 0, rod.id .. " stats positive")
end
check(#BaitData.List >= 4, "bait list")
check(#MutationData.List >= 8, "mutation list")
check(#IslandData.Enabled() == 1 and IslandData.Enabled()[1].id == "mossbell", "only Mossbell enabled for the MVP")

-- ---------------------------------------------------------------- utilities & levels
section("Util / LevelUtil")
local Util = shared("Util")
local LevelUtil = shared("LevelUtil")
check(Util.FormatNumber(0) == "0", "format 0")
check(Util.FormatNumber(999) == "999", "format 999")
check(Util.FormatNumber(1234) == "1,234", "format 1234 -> " .. Util.FormatNumber(1234))
check(Util.FormatNumber(1234567) == "1,234,567", "format 1234567 -> " .. Util.FormatNumber(1234567))
check(Util.FormatNumber(-1234) == "-1,234", "format -1234 -> " .. Util.FormatNumber(-1234))
check(Util.FormatWeight(0.5) == "500 g", "format 500 g -> " .. Util.FormatWeight(0.5))
check(Util.FormatWeight(12.34) == "12.3 kg", "format 12.3 kg -> " .. Util.FormatWeight(12.34))
check(LevelUtil.XPToNext(1) == 100, "level 1 needs 100 XP (" .. LevelUtil.XPToNext(1) .. ")")
check(LevelUtil.XPToNext(10) > LevelUtil.XPToNext(5), "xp curve increases")
local prof = { xp = 0, level = 1 }
local gained = LevelUtil.ApplyXP(prof, 250)
check(gained == 1 and prof.level == 2 and prof.xp == 150, "250 XP from level 1 reaches level 2 with 150 left (level " .. prof.level .. ", xp " .. prof.xp .. ")")
local prof2 = { xp = 0, level = 1 }
check(LevelUtil.ApplyXP(prof2, 100 + 169) == 2 and prof2.level == 3, "exactly enough XP for two levels")
local reconciled = { coins = 5 }
Util.Reconcile(reconciled, { coins = 0, stats = { totalCaught = 0 }, rods = { "twig_rod" } })
check(reconciled.coins == 5 and reconciled.stats.totalCaught == 0 and reconciled.rods[1] == "twig_rod", "reconcile adds missing keys only")

-- ---------------------------------------------------------------- fish generation
section("FishGenerator")
local FishGenerator = serverModule("FishGenerator")
local function distribution(locationId, luck, timeOfDay, weather, n)
	local rng = Random.new(42)
	local counts, shiny, mutated, total = {}, 0, 0, 0
	local minValue, maxValue = math.huge, 0
	for _ = 1, n do
		local gen = FishGenerator.Generate({ locationId = locationId, luck = luck, timeOfDay = timeOfDay, weather = weather, rng = rng })
		if gen then
			total += 1
			counts[gen.def.rarity] = (counts[gen.def.rarity] or 0) + 1
			if gen.fish.shiny then shiny += 1 end
			if gen.fish.mutation then mutated += 1 end
			minValue = math.min(minValue, gen.fish.value)
			maxValue = math.max(maxValue, gen.fish.value)
			check(gen.fish.weight >= gen.def.minWeight and gen.fish.weight <= gen.def.maxWeight, "weight within range for " .. gen.def.id)
			check(gen.xp > 0 and gen.fish.value >= 1, "xp and value positive")
		end
	end
	return counts, shiny, mutated, total, minValue, maxValue
end
local N = 20000
local counts, shiny, mutated, total = distribution("mossbell_shallows", 0, "Day", "Clear", N)
check(total == N, "always generates a fish at the shallows")
local commonShare = (counts.Common or 0) / N
check(commonShare > 0.55 and commonShare < 0.66, string.format("common share ~60%% with no luck (%.1f%%)", commonShare * 100))
check((counts.Secret or 0) == 0, "no secret fish by day in clear weather at the shallows")
check((counts.Legendary or 0) == 0, "Moonwake Marlin (night) absent by day")
check(shiny / N > 0.008 and shiny / N < 0.025, string.format("shiny rate ~1/64 (%.2f%%)", shiny / N * 100))
check(mutated / N < 0.05, string.format("mutation rate modest (%.2f%%)", mutated / N * 100))
local luckyCounts = distribution("mossbell_shallows", 50, "Night", "Storm", N)
local luckyCommon = (luckyCounts.Common or 0) / N
check(luckyCommon < commonShare - 0.05, string.format("luck 50 lowers common share (%.1f%%)", luckyCommon * 100))
check((luckyCounts.Secret or 0) > 0, "The Bellringer can appear at night in a storm (" .. tostring(luckyCounts.Secret) .. " of " .. N .. ")")
check((luckyCounts.Legendary or 0) > 0, "legendary possible at night")
local none = FishGenerator.Generate({ locationId = "nowhere", luck = 0, timeOfDay = "Day", weather = "Clear", rng = Random.new(1) })
check(none == nil, "unknown location yields nothing")
for _, rarity in ipairs(RarityData.Order) do
	local w0, w50 = FishGenerator.RarityWeight(rarity, 0), FishGenerator.RarityWeight(rarity, 50)
	check(w50 >= w0, rarity .. " weight grows with luck")
end
local rod = RodData.Get("twig_rod")
local bigFish = { uid = "x", id = "stormscale_tuna", weight = 80, sizeTier = "Huge", mutation = nil, shiny = false, value = 1, caughtAt = 0, location = "mossbell_shallows" }
local params = FishGenerator.MinigameParams(FishData.Get("stormscale_tuna"), bigFish, rod)
check(params.heavy == true and params.drainRate > 0.22, "heavy fish strains a twig rod")
check(params.minDuration > 2 and params.minDuration < 6, string.format("min duration plausible (%.2fs)", params.minDuration))
local tiers = {}
for _ = 1, 5000 do tiers[FishGenerator.SizeTier(FishGenerator.RollSize(Random.new(7)))] = true end
check(tiers.Tiny ~= nil or tiers.Small ~= nil, "size tiers roll")

-- ---------------------------------------------------------------- island geometry
section("IslandGen / ZoneUtil (Mossbell)")
local IslandGen = shared("IslandGen")
local ZoneUtil = shared("ZoneUtil")
local def = IslandData.ById.mossbell
local hCenter, zCenter = IslandGen.Sample(def, 30, 20)
check(zCenter == "land" and hCenter >= 9, string.format("inland point is high land (h=%.1f, %s)", hCenter, zCenter))
local _, zMid = IslandGen.Sample(def, 0, 0)
check(zMid == "river", "the brook runs through the island centre (" .. zMid .. ")")
local pondCenter = def.center + def.pond.offset
local hPond, zPond = IslandGen.Sample(def, pondCenter.X, pondCenter.Z)
check(zPond == "pond" and hPond == def.pond.bedY, string.format("pond bed carved (h=%.1f, %s)", hPond, zPond))
local rimOk = true
for i = 0, 35 do
	local a = i / 36 * math.pi * 2
	local r = def.pond.radius + 1
	local h, z = IslandGen.Sample(def, pondCenter.X + math.cos(a) * r, pondCenter.Z + math.sin(a) * r)
	if z ~= "river" and h < def.pond.waterY then rimOk = false end
end
check(rimOk, "pond rim holds the water everywhere except the river outlet")
local hSea, zSea = IslandGen.Sample(def, 0, -100)
check(zSea == "ocean" and hSea < 0, string.format("100 studs out is sea (h=%.1f)", hSea))
local length = IslandGen.RiverLength(def)
check(length > def.pond.radius + 20, string.format("river has length (%.0f)", length))
local dirX, dirZ = math.cos(def.river.angle), math.sin(def.river.angle)
local riverOk, stepsOk = true, true
local lastSurface = def.pond.waterY
for i = 1, 9 do
	local tt = i / 10
	local along = def.pond.radius + tt * (length - def.pond.radius)
	local x, z = pondCenter.X + dirX * along, pondCenter.Z + dirZ * along
	local h, zone = IslandGen.Sample(def, x, z)
	local surface = IslandGen.WaterHeight(def, x, z, zone)
	if zone == "river" and h >= surface then riverOk = false end
	if surface > lastSurface then stepsOk = false end
	lastSurface = surface
end
check(riverOk, "river bed stays below the stepped water surface")
check(stepsOk, "river surface only steps down toward the sea")
local mouthH, mouthZone = IslandGen.Sample(def, pondCenter.X + dirX * (length + 4), pondCenter.Z + dirZ * (length + 4))
check(mouthZone == "ocean", "river mouth opens into the ocean (" .. mouthZone .. string.format(", h=%.1f)", mouthH))

local infoPond = ZoneUtil.LocationAt(Vector3.new(pondCenter.X, 8, pondCenter.Z))
check(infoPond and infoPond.locationId == "mossbell_pond" and infoPond.waterY == 8, "ZoneUtil finds the pond")
local infoSea = ZoneUtil.LocationAt(Vector3.new(0, 0, -100))
check(infoSea and infoSea.locationId == "mossbell_shallows" and infoSea.waterY == 0, "ZoneUtil finds the shallows")
check(ZoneUtil.LocationAt(Vector3.new(30, 10, 20)) == nil, "ZoneUtil returns nil on land")
local far = ZoneUtil.LocationAt(Vector3.new(0, 0, -600))
check(far and far.locationId == "open_sea", "far water is open sea")
check(ZoneUtil.LocationAt(Vector3.new(900, 0, 0)) == nil, "outside the ocean is nil")

-- dock: there must be a shoreline along the dock angle
local dockShore = nil
for d = 0, def.radius * 1.5, 2 do
	local h = IslandGen.Sample(def, def.center.X + math.cos(def.dock.angle) * d, def.center.Z + math.sin(def.dock.angle) * d)
	if h < 1.5 then dockShore = d; break end
end
check(dockShore ~= nil and dockShore > 40, "shore found along the dock angle (" .. tostring(dockShore) .. ")")

-- NPC/village/lighthouse positions are on land
for _, npc in ipairs(def.npcs) do
	local pos = IslandGen.Polar(def, npc.angle, npc.distance)
	local _, zone = IslandGen.Sample(def, pos.X, pos.Z)
	check(zone == "land" and pos.Y >= 1.5, npc.name .. " stands on land (" .. zone .. string.format(", y=%.1f)", pos.Y))
end
for _, secret in ipairs(def.secrets) do
	local pos = IslandGen.Polar(def, secret.angle, secret.distance)
	local _, zone = IslandGen.Sample(def, pos.X, pos.Z)
	check(zone == "land", secret.id .. " chest on land (" .. zone .. ")")
end
local lh = IslandGen.Polar(def, def.lighthouse.angle, def.lighthouse.distance)
check(select(2, IslandGen.Sample(def, lh.X, lh.Z)) == "land", "lighthouse on land")
local village = IslandGen.Polar(def, def.village.angle, def.village.distance)
check(select(2, IslandGen.Sample(def, village.X, village.Z)) == "land" and village.Y >= 3, string.format("village on grass (y=%.1f)", village.Y))

-- ground part budget with run merging
local cell, radius = Config.CellSize, def.shallowsRadius
local n = math.ceil(radius / cell)
local columns, cells = 0, 0
for iz = -n, n do
	local z = iz * cell
	local lastKey = nil
	for ix = -n, n do
		local x = ix * cell
		if x * x + z * z <= radius * radius then
			cells += 1
			local h, zone = IslandGen.Sample(def, x, z)
			local key = zone .. ":" .. h
			if key ~= lastKey then columns += 1 end
			lastKey = key
		else
			lastKey = nil
		end
	end
end
print(string.format("  ground cells %d -> merged parts <= %d", cells, columns))
check(columns < 3000, "ground part count within budget")

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
	error("tests failed")
end
