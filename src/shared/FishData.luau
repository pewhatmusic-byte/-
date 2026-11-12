--!strict
-- Every fish in Driftwake Isles. All names, lore and stats are original.
-- Fields: id, name, rarity, locations, baseValue (coins at average size), minWeight/maxWeight (kg),
--         time (Any/Day/Night), weather (Any/Clear/Rain/Storm; Rain also matches Storm), icon shape + colours, description.

local Types = require(script.Parent.Types)
local RarityData = require(script.Parent.RarityData)

type FishDef = Types.FishDef

local rgb = Color3.fromRGB

local function fish(
	id: string, name: string, rarity: Types.Rarity, locations: { string },
	baseValue: number, minWeight: number, maxWeight: number,
	time: Types.TimeCondition, weather: Types.WeatherCondition, shape: Types.IconShape,
	color1: Color3, color2: Color3, description: string
): FishDef
	return {
		id = id, name = name, rarity = rarity, locations = locations,
		baseValue = baseValue, minWeight = minWeight, maxWeight = maxWeight,
		time = time, weather = weather, shape = shape,
		color1 = color1, color2 = color2, description = description,
	}
end

local FishData = {}

local LIST: { FishDef } = {
	-- ===== Mossbell Shallows (starter ocean) =====
	fish("pebble_minnow", "Pebble Minnow", "Common", { "mossbell_shallows", "open_sea" }, 6, 0.1, 0.6, "Any", "Any", "Round", rgb(160, 170, 182), rgb(96, 104, 118), "A tiny grey fish that hides between the dock pilings."),
	fish("tideling_sardine", "Tideling Sardine", "Common", { "mossbell_shallows", "open_sea" }, 8, 0.2, 0.9, "Any", "Any", "Long", rgb(190, 205, 220), rgb(70, 110, 160), "Travels in shimmering clouds just under the surface."),
	fish("sandflat_goby", "Sandflat Goby", "Common", { "mossbell_shallows" }, 7, 0.2, 1.2, "Any", "Any", "Flat", rgb(214, 190, 140), rgb(150, 120, 80), "Buries itself in the sand and waits for lunch to walk past."),
	fish("blue_dart", "Blue Dart", "Common", { "mossbell_shallows", "open_sea" }, 9, 0.3, 1.5, "Day", "Any", "Long", rgb(70, 140, 230), rgb(240, 240, 255), "Fast, nervous and bright as the summer sky."),
	fish("driftwood_perch", "Driftwood Perch", "Common", { "mossbell_shallows" }, 10, 0.4, 2.5, "Any", "Any", "Round", rgb(150, 120, 80), rgb(90, 70, 40), "Looks exactly like a soggy stick until it bites."),
	fish("copper_wrasse", "Copper Wrasse", "Uncommon", { "mossbell_shallows" }, 22, 0.5, 3, "Day", "Any", "Round", rgb(200, 120, 60), rgb(90, 200, 120), "Its scales ring like coins when it flaps on the deck."),
	fish("mossgill_snapper", "Mossgill Snapper", "Uncommon", { "mossbell_shallows" }, 26, 1, 5, "Any", "Any", "Round", rgb(110, 160, 90), rgb(230, 200, 100), "Named for the green fuzz that grows along its gills."),
	fish("lanternfin_mackerel", "Lanternfin Mackerel", "Uncommon", { "mossbell_shallows", "open_sea" }, 28, 0.8, 4, "Night", "Any", "Long", rgb(60, 80, 130), rgb(255, 220, 120), "Its fins glow faintly, guiding the sardines home."),
	fish("harborglass_flounder", "Harbourglass Flounder", "Rare", { "mossbell_shallows" }, 65, 1, 7, "Any", "Any", "Flat", rgb(170, 220, 230), rgb(100, 150, 180), "Almost transparent. You can see yesterday's dinner inside it."),
	fish("saltcrown_bass", "Saltcrown Bass", "Rare", { "mossbell_shallows" }, 75, 2, 12, "Any", "Any", "Round", rgb(90, 120, 150), rgb(250, 240, 200), "Wears a crust of salt crystals like a crown."),
	fish("stormscale_tuna", "Stormscale Tuna", "Epic", { "mossbell_shallows", "open_sea" }, 220, 15, 90, "Any", "Rain", "Long", rgb(50, 70, 110), rgb(140, 190, 255), "Only surfaces when the rain is coming down sideways."),
	fish("moonwake_marlin", "Moonwake Marlin", "Legendary", { "mossbell_shallows", "open_sea" }, 650, 40, 260, "Night", "Any", "Long", rgb(120, 140, 220), rgb(240, 240, 255), "Leaves a trail of silver light across the night water."),
	fish("sunken_choir_ray", "Sunken Choir Ray", "Mythic", { "mossbell_shallows" }, 2400, 60, 400, "Night", "Rain", "Ray", rgb(80, 60, 120), rgb(230, 200, 255), "Fishers swear they hear singing before it strikes."),
	fish("the_bellringer", "The Bellringer", "Secret", { "mossbell_shallows", "drowned_belltower" }, 9000, 5, 30, "Night", "Storm", "Odd", rgb(190, 170, 90), rgb(60, 50, 40), "A ghostly fish that tolls like a bell when it leaps. Nobody has kept one for long."),

	-- ===== Bellflower Pond =====
	fish("mudpuddle_carp", "Mudpuddle Carp", "Common", { "mossbell_pond" }, 7, 0.5, 4, "Any", "Any", "Round", rgb(140, 110, 70), rgb(200, 170, 110), "Fat, lazy and perfectly happy about it."),
	fish("lilypad_guppy", "Lilypad Guppy", "Common", { "mossbell_pond" }, 5, 0.05, 0.3, "Day", "Any", "Round", rgb(120, 200, 110), rgb(255, 170, 200), "Hides under the lily pads when the herons come."),
	fish("reed_shiner", "Reed Shiner", "Common", { "mossbell_pond", "mossbell_brook" }, 6, 0.1, 0.7, "Any", "Any", "Long", rgb(210, 220, 200), rgb(120, 160, 90), "Flashes like a dropped coin among the reeds."),
	fish("bogwhisker_catfish", "Bogwhisker Catfish", "Uncommon", { "mossbell_pond" }, 24, 1, 9, "Night", "Any", "Long", rgb(80, 90, 70), rgb(180, 160, 120), "Its whiskers are longer than its patience."),
	fish("speckled_pondfin", "Speckled Pondfin", "Uncommon", { "mossbell_pond" }, 20, 0.4, 2, "Any", "Any", "Round", rgb(220, 190, 110), rgb(120, 80, 50), "Every speckle is said to be a freckle it stole from a child."),
	fish("emerald_koi", "Emerald Koi", "Rare", { "mossbell_pond" }, 80, 1, 6, "Day", "Any", "Round", rgb(40, 180, 110), rgb(255, 250, 230), "The village elders say it brings a good harvest."),
	fish("lantern_loach", "Lantern Loach", "Epic", { "mossbell_pond" }, 210, 0.5, 3, "Night", "Any", "Eel", rgb(255, 190, 70), rgb(120, 60, 30), "Drifts along the pond floor like a lost candle."),
	fish("old_mossback", "Old Mossback", "Legendary", { "mossbell_pond" }, 700, 20, 80, "Any", "Rain", "Round", rgb(70, 110, 60), rgb(150, 190, 90), "Older than the village. Possibly older than the island."),
	fish("dewdrop_serpent", "Dewdrop Serpent", "Mythic", { "mossbell_pond" }, 2600, 5, 40, "Day", "Clear", "Eel", rgb(170, 230, 255), rgb(255, 255, 255), "Appears only on perfectly still mornings, beaded with dew."),

	-- ===== Tumble Brook =====
	fish("brook_darter", "Brook Darter", "Common", { "mossbell_brook" }, 6, 0.1, 0.5, "Any", "Any", "Long", rgb(170, 190, 120), rgb(90, 110, 60), "Zips between the stones faster than you can blink."),
	fish("silver_riffle", "Silver Riffle", "Common", { "mossbell_brook" }, 8, 0.2, 1, "Any", "Any", "Long", rgb(210, 215, 225), rgb(130, 140, 160), "Loves the bubbly water at the bottom of each step."),
	fish("stonebelly_chub", "Stonebelly Chub", "Common", { "mossbell_brook" }, 9, 0.3, 2, "Any", "Any", "Round", rgb(130, 130, 125), rgb(200, 190, 170), "Swallows pebbles to stay on the river bed."),
	fish("rainbow_streamer", "Rainbow Streamer", "Uncommon", { "mossbell_brook" }, 25, 0.5, 3, "Day", "Any", "Long", rgb(230, 120, 160), rgb(120, 220, 200), "Each scale is a slightly different colour."),
	fish("rapid_runner_trout", "Rapid Runner Trout", "Uncommon", { "mossbell_brook" }, 27, 0.8, 4, "Any", "Any", "Long", rgb(120, 150, 110), rgb(240, 150, 120), "Leaps up the brook's waterfalls for fun."),
	fish("goldvein_salmon", "Goldvein Salmon", "Rare", { "mossbell_brook" }, 85, 2, 10, "Any", "Any", "Long", rgb(230, 150, 90), rgb(250, 220, 100), "Thin golden lines run along its back like ore in rock."),
	fish("thunderbrook_sturgeon", "Thunderbrook Sturgeon", "Epic", { "mossbell_brook" }, 240, 10, 60, "Any", "Rain", "Long", rgb(70, 80, 100), rgb(180, 190, 210), "Rides the brook when the rain swells it into a torrent."),
	fish("riverking_pike", "Riverking Pike", "Legendary", { "mossbell_brook" }, 680, 8, 35, "Day", "Any", "Long", rgb(80, 130, 70), rgb(250, 220, 90), "Every smaller fish in the brook knows its name."),
	fish("glassflow_eel", "Glassflow Eel", "Mythic", { "mossbell_brook" }, 2500, 2, 15, "Night", "Any", "Eel", rgb(200, 240, 250), rgb(120, 180, 220), "So clear it is only visible by the water it bends."),

	-- ===== Brinewake Reef =====
	fish("coralback_grunt", "Coralback Grunt", "Common", { "brinewake_reef" }, 10, 0.3, 2, "Any", "Any", "Round", rgb(255, 140, 120), rgb(255, 230, 200), "Grunts loudly when annoyed, which is always."),
	fish("parrotbeak_wrasse", "Parrotbeak Wrasse", "Common", { "brinewake_reef" }, 12, 0.4, 3, "Day", "Any", "Round", rgb(60, 200, 160), rgb(255, 120, 80), "Nibbles the coral with a beak like a parrot's."),
	fish("reefstripe_angel", "Reefstripe Angel", "Uncommon", { "brinewake_reef" }, 32, 0.3, 1.5, "Day", "Any", "Flat", rgb(255, 210, 60), rgb(40, 60, 120), "Striped like a sunset over the reef."),
	fish("anemone_clown", "Anemone Clown", "Uncommon", { "brinewake_reef" }, 30, 0.1, 0.5, "Any", "Any", "Round", rgb(255, 120, 40), rgb(255, 255, 255), "Never strays far from its stinging home."),
	fish("ghost_coral_pipefish", "Ghost Coral Pipefish", "Rare", { "brinewake_reef" }, 95, 0.2, 1, "Any", "Any", "Eel", rgb(230, 230, 240), rgb(255, 170, 190), "Looks like a drifting twig of bleached coral."),
	fish("tigerjaw_barracuda", "Tigerjaw Barracuda", "Epic", { "brinewake_reef", "open_sea" }, 260, 10, 45, "Any", "Any", "Long", rgb(170, 180, 190), rgb(40, 40, 50), "Its teeth are visible from the surface."),
	fish("reef_warden_grouper", "Reef Warden Grouper", "Legendary", { "brinewake_reef" }, 720, 50, 200, "Any", "Any", "Round", rgb(120, 90, 160), rgb(240, 200, 120), "It patrols the reef like it owns the place. It does."),
	fish("coral_crown_seahorse", "Coral Crown Seahorse", "Mythic", { "brinewake_reef" }, 2700, 0.2, 2, "Day", "Clear", "Odd", rgb(255, 180, 90), rgb(255, 240, 180), "Tiny, regal and worth more than a boat."),

	-- ===== Gloomhollow Pools (cave) =====
	fish("blindcave_tetra", "Blindcave Tetra", "Common", { "gloomhollow_cave" }, 11, 0.1, 0.5, "Any", "Any", "Round", rgb(230, 220, 220), rgb(190, 170, 180), "Has no eyes and no need for them."),
	fish("dripstone_dace", "Dripstone Dace", "Common", { "gloomhollow_cave" }, 12, 0.2, 1, "Any", "Any", "Long", rgb(150, 150, 160), rgb(90, 90, 110), "Waits beneath stalactites for drips to bring food."),
	fish("glowworm_loach", "Glowworm Loach", "Uncommon", { "gloomhollow_cave" }, 34, 0.3, 2, "Any", "Any", "Eel", rgb(120, 220, 160), rgb(60, 100, 90), "Eats glowworms and glows a little itself."),
	fish("echofin", "Echofin", "Uncommon", { "gloomhollow_cave" }, 36, 0.5, 3, "Any", "Any", "Round", rgb(80, 70, 110), rgb(200, 190, 230), "Clicks to find its way in the dark."),
	fish("crystalback_crawler", "Crystalback Crawler", "Rare", { "gloomhollow_cave" }, 110, 1, 6, "Any", "Any", "Odd", rgb(170, 200, 230), rgb(255, 255, 255), "Half crab, half geode."),
	fish("shadowmaw_salamander", "Shadowmaw Salamander", "Epic", { "gloomhollow_cave" }, 280, 3, 20, "Night", "Any", "Eel", rgb(40, 40, 50), rgb(200, 60, 80), "Its mouth is darker than the cave around it."),
	fish("stalactite_serpent", "Stalactite Serpent", "Legendary", { "gloomhollow_cave" }, 760, 15, 70, "Any", "Any", "Eel", rgb(180, 170, 160), rgb(90, 80, 80), "Hangs motionless from the ceiling until it doesn't."),
	fish("gloomgazer", "Gloomgazer", "Mythic", { "gloomhollow_cave" }, 2900, 30, 120, "Any", "Any", "Round", rgb(50, 40, 70), rgb(255, 230, 90), "One enormous eye. It has seen you long before you see it."),
	fish("lost_miners_lantern", "Lost Miner's Lantern", "Secret", { "gloomhollow_cave" }, 9500, 1, 3, "Any", "Any", "Odd", rgb(200, 160, 60), rgb(255, 240, 160), "Not a fish at all. An old lantern that still burns. Someone misses it."),

	-- ===== Emberfang Lagoon (volcanic) =====
	fish("cinder_guppy", "Cinder Guppy", "Common", { "emberfang_lagoon" }, 13, 0.1, 0.5, "Any", "Any", "Round", rgb(90, 70, 70), rgb(255, 120, 60), "Smoulders when it leaves the water."),
	fish("ashback_tilapia", "Ashback Tilapia", "Common", { "emberfang_lagoon" }, 14, 0.5, 3, "Any", "Any", "Round", rgb(120, 110, 110), rgb(200, 200, 200), "Dusted grey with volcanic ash."),
	fish("magma_mullet", "Magma Mullet", "Uncommon", { "emberfang_lagoon" }, 38, 1, 5, "Any", "Any", "Long", rgb(230, 90, 40), rgb(255, 200, 60), "Glows orange along its spine."),
	fish("sootscale_grouper", "Sootscale Grouper", "Uncommon", { "emberfang_lagoon" }, 40, 2, 12, "Night", "Any", "Round", rgb(50, 45, 45), rgb(150, 60, 40), "Leaves black smudges on your hands."),
	fish("obsidian_barracuda", "Obsidian Barracuda", "Rare", { "emberfang_lagoon" }, 120, 8, 40, "Any", "Any", "Long", rgb(30, 30, 40), rgb(120, 110, 150), "Sharp as the glass it's named for."),
	fish("emberheart_pyrefish", "Emberheart Pyrefish", "Epic", { "emberfang_lagoon" }, 300, 2, 12, "Night", "Any", "Round", rgb(255, 80, 30), rgb(255, 230, 120), "You can see its heart burning through its chest."),
	fish("caldera_dragonfish", "Caldera Dragonfish", "Legendary", { "emberfang_lagoon" }, 820, 25, 140, "Any", "Any", "Long", rgb(170, 40, 40), rgb(255, 170, 40), "Breathes bubbles of steam."),
	fish("magmaw_wyrm", "Magmaw Wyrm", "Mythic", { "emberfang_lagoon" }, 3200, 80, 500, "Any", "Storm", "Eel", rgb(120, 30, 30), rgb(255, 120, 30), "The lagoon boils when it wakes."),
	fish("phoenix_koi", "Phoenix Koi", "Secret", { "emberfang_lagoon" }, 11000, 2, 8, "Day", "Clear", "Round", rgb(255, 160, 40), rgb(255, 60, 30), "Legend says it has been caught a hundred times and always returns."),

	-- ===== Frostmere Bay (icy) =====
	fish("frostbite_smelt", "Frostbite Smelt", "Common", { "frostmere_bay" }, 13, 0.1, 0.6, "Any", "Any", "Long", rgb(200, 230, 245), rgb(120, 160, 200), "Cold enough to numb your fingers through the gloves."),
	fish("snowdrift_cod", "Snowdrift Cod", "Common", { "frostmere_bay" }, 15, 1, 8, "Any", "Any", "Round", rgb(220, 225, 235), rgb(150, 160, 180), "Plump and pale as a snowbank."),
	fish("glacier_char", "Glacier Char", "Uncommon", { "frostmere_bay" }, 38, 0.8, 5, "Any", "Any", "Long", rgb(90, 140, 190), rgb(255, 140, 120), "Its belly turns pink in the midwinter."),
	fish("iceflake_herring", "Iceflake Herring", "Uncommon", { "frostmere_bay" }, 36, 0.2, 1, "Any", "Any", "Long", rgb(235, 245, 255), rgb(180, 210, 240), "Each one is slightly different, like snowflakes."),
	fish("crystal_icefish", "Crystal Icefish", "Rare", { "frostmere_bay" }, 125, 0.5, 3, "Any", "Any", "Long", rgb(210, 240, 255), rgb(255, 255, 255), "Its blood is clear and its bones are glass."),
	fish("aurora_trout", "Aurora Trout", "Epic", { "frostmere_bay" }, 310, 2, 10, "Night", "Clear", "Long", rgb(100, 220, 180), rgb(200, 120, 255), "Ripples with green and violet light on clear nights."),
	fish("rimehorn", "Rimehorn", "Legendary", { "frostmere_bay" }, 850, 60, 300, "Any", "Any", "Long", rgb(170, 190, 210), rgb(240, 250, 255), "A single spiral horn, frosted at the tip."),
	fish("everfrost_leviathan", "Everfrost Leviathan", "Mythic", { "frostmere_bay" }, 3400, 200, 900, "Any", "Storm", "Eel", rgb(120, 160, 210), rgb(230, 245, 255), "The bay freezes over in its wake."),
	fish("snowglobe_jelly", "Snowglobe Jelly", "Secret", { "frostmere_bay" }, 10500, 0.3, 1, "Night", "Any", "Odd", rgb(220, 235, 255), rgb(255, 255, 255), "Snow falls gently inside its bell, forever."),

	-- ===== The Abyssal Shelf (deep sea) =====
	fish("pale_gulper", "Pale Gulper", "Common", { "abyssal_shelf" }, 16, 0.5, 4, "Any", "Any", "Round", rgb(190, 180, 190), rgb(120, 100, 130), "Mostly mouth."),
	fish("inkdrop_squid", "Inkdrop Squid", "Common", { "abyssal_shelf" }, 18, 0.3, 3, "Any", "Any", "Odd", rgb(70, 60, 100), rgb(160, 140, 200), "Leaves a cloud of ink and a bad mood."),
	fish("blackwater_hatchet", "Blackwater Hatchet", "Uncommon", { "abyssal_shelf" }, 42, 0.2, 1.2, "Any", "Any", "Flat", rgb(140, 150, 170), rgb(40, 40, 60), "Thin as a blade, silver as a coin."),
	fish("lantern_eye", "Lantern Eye", "Uncommon", { "abyssal_shelf" }, 44, 0.5, 3, "Any", "Any", "Round", rgb(50, 50, 70), rgb(140, 255, 200), "Two glowing eyes approach in the dark. Then teeth."),
	fish("fathom_angler", "Fathom Angler", "Rare", { "abyssal_shelf" }, 140, 2, 15, "Night", "Any", "Round", rgb(40, 30, 50), rgb(255, 230, 120), "Dangles its own little lure. Professional courtesy."),
	fish("ghostfin_grenadier", "Ghostfin Grenadier", "Rare", { "abyssal_shelf" }, 130, 3, 20, "Any", "Any", "Long", rgb(200, 200, 210), rgb(100, 110, 140), "A long, slow shadow drifting over the shelf."),
	fish("voidmaw_viperfish", "Voidmaw Viperfish", "Epic", { "abyssal_shelf" }, 340, 5, 30, "Any", "Any", "Eel", rgb(30, 30, 40), rgb(90, 200, 255), "Its fangs don't fit inside its mouth."),
	fish("abyssal_colossus_squid", "Abyssal Colossus Squid", "Legendary", { "abyssal_shelf" }, 900, 150, 800, "Any", "Any", "Odd", rgb(150, 40, 70), rgb(240, 180, 200), "Big enough to shake a boat."),
	fish("the_hollow_serpent", "The Hollow Serpent", "Mythic", { "abyssal_shelf" }, 3800, 300, 1500, "Night", "Storm", "Eel", rgb(20, 20, 30), rgb(120, 60, 180), "Older sailors refuse to say its name on the water."),
	fish("drowned_star", "Drowned Star", "Secret", { "abyssal_shelf" }, 12000, 1, 5, "Night", "Clear", "Odd", rgb(255, 240, 180), rgb(255, 255, 255), "A star that fell into the sea and kept shining."),

	-- ===== Lumenveil Shore (mystic island) =====
	fish("fairy_fin", "Fairy Fin", "Common", { "lumenveil_shore" }, 20, 0.05, 0.3, "Any", "Any", "Round", rgb(255, 200, 240), rgb(200, 240, 255), "Leaves glittering dust on your hands."),
	fish("petal_guppy", "Petal Guppy", "Common", { "lumenveil_shore" }, 18, 0.1, 0.4, "Day", "Any", "Round", rgb(255, 170, 190), rgb(255, 240, 200), "Looks like a blossom that learned to swim."),
	fish("starwisp_minnow", "Starwisp Minnow", "Uncommon", { "lumenveil_shore" }, 48, 0.1, 0.6, "Night", "Any", "Long", rgb(230, 230, 255), rgb(120, 140, 255), "Schools of them look like constellations."),
	fish("moonpetal_koi", "Moonpetal Koi", "Uncommon", { "lumenveil_shore" }, 50, 1, 6, "Night", "Any", "Round", rgb(240, 240, 255), rgb(180, 150, 255), "Blooms with light under a full moon."),
	fish("dreamscale_bass", "Dreamscale Bass", "Rare", { "lumenveil_shore" }, 150, 2, 12, "Any", "Any", "Round", rgb(150, 110, 220), rgb(255, 220, 150), "Those who hold it fall asleep smiling."),
	fish("prism_dragonet", "Prism Dragonet", "Epic", { "lumenveil_shore" }, 360, 0.5, 4, "Day", "Clear", "Odd", rgb(255, 120, 180), rgb(120, 255, 220), "Bends sunlight into rainbows along its fins."),
	fish("celestial_kite_ray", "Celestial Kite Ray", "Legendary", { "lumenveil_shore" }, 950, 30, 160, "Night", "Clear", "Ray", rgb(60, 50, 120), rgb(255, 250, 200), "Glides between the stars reflected on the water."),
	fish("veilwalker", "Veilwalker", "Mythic", { "lumenveil_shore" }, 4000, 10, 60, "Night", "Any", "Eel", rgb(220, 200, 255), rgb(255, 255, 255), "Passes through the veil between the sea and somewhere else."),
	fish("the_wishing_fish", "The Wishing Fish", "Secret", { "lumenveil_shore" }, 15000, 0.5, 2, "Any", "Any", "Round", rgb(255, 230, 120), rgb(255, 255, 255), "Make a wish. It is listening."),
}

FishData.List = LIST
FishData.ById = {} :: { [string]: FishDef }
FishData.ByLocation = {} :: { [string]: { FishDef } }

for _, def in ipairs(FishData.List) do
	assert(FishData.ById[def.id] == nil, "Duplicate fish id " .. def.id)
	assert(RarityData.Info[def.rarity], "Bad rarity on fish " .. def.id)
	FishData.ById[def.id] = def
	for _, loc in ipairs(def.locations) do
		local pool = FishData.ByLocation[loc]
		if not pool then
			pool = {}
			FishData.ByLocation[loc] = pool
		end
		table.insert(pool, def)
	end
end

function FishData.Get(id: string): FishDef?
	return FishData.ById[id]
end

function FishData.PoolFor(locationId: string): { FishDef }
	return FishData.ByLocation[locationId] or {}
end

-- Sorted copy of the list: by rarity index, then name.
function FishData.Sorted(): { FishDef }
	local copy = table.clone(FishData.List)
	table.sort(copy, function(a, b)
		local ra, rb = RarityData.Index(a.rarity), RarityData.Index(b.rarity)
		if ra ~= rb then
			return ra < rb
		end
		return a.name < b.name
	end)
	return copy
end

return FishData
