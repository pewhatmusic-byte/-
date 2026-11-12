--!strict
-- Shared type definitions for Driftwake Isles. Types only; the module returns an empty table.

export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic" | "Secret"
export type TimeCondition = "Any" | "Day" | "Night"
export type WeatherCondition = "Any" | "Clear" | "Rain" | "Storm"
export type Weather = "Clear" | "Rain" | "Storm"
export type LocationKind = "Ocean" | "Pond" | "River" | "Cave" | "DeepSea" | "Volcanic" | "Ice" | "Mystic"
export type IconShape = "Round" | "Long" | "Flat" | "Eel" | "Ray" | "Odd"
export type NPCRole = "Sell" | "Shop" | "Quest"

export type FishDef = {
	id: string,
	name: string,
	rarity: Rarity,
	locations: { string },
	baseValue: number,
	minWeight: number,
	maxWeight: number,
	time: TimeCondition,
	weather: WeatherCondition,
	shape: IconShape,
	color1: Color3,
	color2: Color3,
	description: string,
}

-- A fish instance owned by a player.
export type CaughtFish = {
	uid: string,
	id: string,
	weight: number,
	sizeTier: string,
	mutation: string?,
	shiny: boolean,
	value: number,
	caughtAt: number,
	location: string,
}

export type RodDef = {
	id: string,
	name: string,
	price: number,
	levelReq: number,
	shop: string,
	luck: number,
	lureSpeed: number,
	control: number,
	resilience: number,
	maxWeight: number,
	castRange: number,
	color1: Color3,
	color2: Color3,
	description: string,
}

export type BaitDef = {
	id: string,
	name: string,
	price: number,
	shop: string,
	luck: number,
	lureSpeed: number,
	color: Color3,
	description: string,
}

export type LocationDef = {
	id: string,
	name: string,
	kind: LocationKind,
	island: string,
	description: string,
}

export type MutationDef = {
	id: string,
	chance: number,
	valueMult: number,
	xpMult: number,
	color: Color3,
	requiresTime: TimeCondition?,
	requiresWeather: WeatherCondition?,
	requiresKind: { string }?,
	description: string,
}

export type NPCStyle = { skin: Color3, shirt: Color3, pants: Color3, hat: Color3? }

export type NPCDef = {
	id: string,
	name: string,
	title: string,
	role: NPCRole,
	angle: number,
	distance: number,
	facing: number?,
	style: NPCStyle,
	lines: { string },
}

export type PondDef = { offset: Vector3, radius: number, rim: number, bedY: number, waterY: number }
export type RiverDef = { angle: number, width: number, endBedY: number }

export type IslandDef = {
	id: string,
	name: string,
	enabled: boolean,
	center: Vector3,
	radius: number,
	seed: number,
	shapeWobble: number,
	peakHeight: number,
	noiseScale: number,
	noiseHeight: number,
	seaSlope: number,
	shallowsRadius: number,
	pond: PondDef?,
	river: RiverDef?,
	locations: { ocean: string, pond: string?, river: string? },
	palette: { [string]: Color3 },
	dock: { angle: number, length: number }?,
	village: { angle: number, distance: number }?,
	lighthouse: { angle: number, distance: number }?,
	secrets: { { id: string, angle: number, distance: number, coins: number, xp: number } },
	npcs: { NPCDef },
	treeDensity: number,
	rockDensity: number,
	treeVariants: { string },
	discoveryXP: number,
}

export type BestiaryEntry = { count: number, bestWeight: number, firstAt: number, shiny: boolean }

export type Profile = {
	version: number,
	coins: number,
	xp: number,
	level: number,
	rods: { string },
	equippedRod: string,
	bait: { [string]: number },
	equippedBait: string?,
	fish: { CaughtFish },
	bestiary: { [string]: BestiaryEntry },
	discoveredLocations: { [string]: boolean },
	treasures: { [string]: boolean },
	cosmetics: { string },
	boats: { string },
	quests: { [string]: any },
	stats: { totalCaught: number, totalSold: number, coinsEarned: number, playtime: number },
	settings: { [string]: any },
}

-- Sent to the client when a fish is hooked; never includes the fish identity.
export type MinigameParams = {
	rarity: Rarity,
	strength: number,
	speed: number,
	zoneSize: number,
	fillRate: number,
	drainRate: number,
	startProgress: number,
	minDuration: number,
	heavy: boolean,
	weightRatio: number,
}

return {}
