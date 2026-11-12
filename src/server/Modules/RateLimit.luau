--!strict
-- Per-player rate limiting for remote calls.

local RateLimit = {}

local buckets: { [Player]: { [string]: { count: number, windowStart: number } } } = {}

-- Returns true when the call is allowed (at most `maxPerSecond` calls per key per second).
function RateLimit.Check(player: Player, key: string, maxPerSecond: number): boolean
	local playerBuckets = buckets[player]
	if not playerBuckets then
		playerBuckets = {}
		buckets[player] = playerBuckets
	end
	local now = os.clock()
	local bucket = playerBuckets[key]
	if not bucket or now - bucket.windowStart >= 1 then
		playerBuckets[key] = { count = 1, windowStart = now }
		return true
	end
	bucket.count += 1
	return bucket.count <= maxPerSecond
end

function RateLimit.Clear(player: Player)
	buckets[player] = nil
end

return RateLimit
