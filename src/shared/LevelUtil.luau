--!strict
-- XP curve and level application.

local LevelUtil = {}

LevelUtil.MaxLevel = 100

function LevelUtil.XPToNext(level: number): number
	return math.floor(60 + 40 * level ^ 1.45)
end

-- Adds XP to a profile-like table ({ xp, level }) and returns how many levels were gained.
function LevelUtil.ApplyXP(profile: { xp: number, level: number, [any]: any }, amount: number): number
	local gained = 0
	profile.xp += math.max(0, math.floor(amount + 0.5))
	while profile.level < LevelUtil.MaxLevel do
		local needed = LevelUtil.XPToNext(profile.level)
		if profile.xp < needed then
			break
		end
		profile.xp -= needed
		profile.level += 1
		gained += 1
	end
	if profile.level >= LevelUtil.MaxLevel then
		profile.xp = math.min(profile.xp, LevelUtil.XPToNext(LevelUtil.MaxLevel))
	end
	return gained
end

function LevelUtil.Progress(profile: { xp: number, level: number, [any]: any }): number
	local needed = LevelUtil.XPToNext(profile.level)
	return math.clamp(profile.xp / needed, 0, 1)
end

return LevelUtil
