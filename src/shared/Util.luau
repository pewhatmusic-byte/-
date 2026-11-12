--!strict
-- Small pure helpers shared by server and client.

local Util = {}

function Util.FormatNumber(n: number): string
	local s = tostring(math.floor(n + 0.5))
	local reversed = s:reverse():gsub("(%d%d%d)", "%1,")
	local formatted = reversed:reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	formatted = formatted:gsub("%-,", "-")
	return formatted
end

function Util.FormatWeight(kg: number): string
	if kg < 1 then
		return string.format("%d g", math.floor(kg * 1000 + 0.5))
	elseif kg < 100 then
		return string.format("%.1f kg", kg)
	end
	return Util.FormatNumber(kg) .. " kg"
end

function Util.FormatTime(seconds: number): string
	local m = math.floor(seconds / 60)
	local s = math.floor(seconds % 60)
	return string.format("%d:%02d", m, s)
end

function Util.Lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function Util.Round(n: number, step: number?): number
	local st = step or 1
	return math.floor(n / st + 0.5) * st
end

function Util.DeepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in pairs(value :: any) do
		copy[k] = Util.DeepCopy(v)
	end
	return (copy :: any) :: T
end

-- Adds any keys from `template` that are missing in `target` (recursively for tables). Never removes keys.
function Util.Reconcile(target: { [any]: any }, template: { [any]: any })
	for key, value in pairs(template) do
		if target[key] == nil then
			target[key] = Util.DeepCopy(value)
		elseif type(value) == "table" and type(target[key]) == "table" and #value == 0 then
			Util.Reconcile(target[key], value)
		end
	end
end

local ID_CHARS = "abcdefghijklmnopqrstuvwxyz0123456789"
function Util.ShortId(rng: Random?): string
	local r = rng or Random.new()
	local chars = table.create(10)
	for i = 1, 10 do
		local idx = r:NextInteger(1, #ID_CHARS)
		chars[i] = ID_CHARS:sub(idx, idx)
	end
	return table.concat(chars)
end

function Util.WeightedChoice<T>(rng: Random, items: { T }, weightOf: (T) -> number): T?
	local total = 0
	for _, item in ipairs(items) do
		total += math.max(weightOf(item), 0)
	end
	if total <= 0 then
		return nil
	end
	local roll = rng:NextNumber() * total
	for _, item in ipairs(items) do
		roll -= math.max(weightOf(item), 0)
		if roll <= 0 then
			return item
		end
	end
	return items[#items]
end

function Util.IsDay(clockTime: number): boolean
	return clockTime >= 6 and clockTime < 18
end

function Util.TimeOfDay(clockTime: number): "Day" | "Night"
	return if Util.IsDay(clockTime) then "Day" else "Night"
end

function Util.IsFiniteVector(v: any): boolean
	if typeof(v) ~= "Vector3" then
		return false
	end
	local x, y, z = v.X, v.Y, v.Z
	return x == x and y == y and z == z and math.abs(x) < 1e6 and math.abs(y) < 1e6 and math.abs(z) < 1e6
end

function Util.Darken(color: Color3, amount: number): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, s, math.clamp(v * (1 - amount), 0, 1))
end

function Util.Lighten(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(1, 1, 1), amount)
end

return Util
