# Roadmap — from MVP to the full Driftwake Isles

The MVP ships one island, fishing, fish generation, inventory, selling, XP/levels, shops, the
fish book, weather and day/night. Everything below plugs into existing hooks; each section
says where the code goes and which existing modules it touches.

## 1. More islands (Brinewake Reef, Gloomhollow, Emberfang, Frostmere, Lumenveil, the Abyssal Shelf)

The fish pools, locations, rods and bait for every island already exist in the data modules.
Adding an island is mostly data:

1. Append an `IslandDef` to `src/shared/IslandData.luau` with `enabled = true`, a far-away
   `center` (e.g. `Vector3.new(900, 0, -400)`), a new `seed`, its own `palette`
   (grey/black for Gloomhollow, ash + lava reds for Emberfang, white/ice blues for Frostmere,
   violets and glowing greens for Lumenveil), `locations = { ocean = "brinewake_reef" }` and
   its NPCs / secrets. Islands without a pond or river simply omit those fields.
2. Raise `Config.OceanSize` so every island fits (the ocean is one terrain fill).
3. Island-specific looks go into `MapDecor.Populate` branches keyed on `def.id` or a new
   `def.theme` field: lava pools (orange water-coloured parts + PointLights + smoke particles),
   ice floes (flat white slabs on the water), bioluminescent crystals (Neon material cubes),
   a cave built from an overhanging ring of rock columns with `IslandGen` carving a cave pool.
4. Deep sea: the Abyssal Shelf is a location with no island — add a `ZoneUtil` rule that returns
   `"abyssal_shelf"` for positions inside a trench rectangle far from land, and build a buoy
   model there so boats can anchor.
5. Island discovery XP: `PlayerService.DiscoverLocation` already rewards new locations; add an
   `IslandAt` check in the client watch loop (`ZoneUtil.IslandAt`) and a `DiscoverIsland` remote
   if you want a bigger reward + banner when stepping ashore.

## 2. Boats

* **Data**: `src/shared/BoatData.luau` — `{ id, name, price, levelReq, speed, turnRate, storage,
  color1, color2, description }` (rowboat → skiff → cutter → trawler).
* **Server** `BoatService`: spawn/despawn a player's boat at the dock (`DockEnd` attribute on
  the island model), one boat per player, network ownership set to the player
  (`boat.PrimaryPart:SetNetworkOwner(player)`), despawn on leave/death. Purchase through the
  existing `Purchase` RemoteFunction (`kind = "boat"`), stored in `profile.boats`.
* **Client** `BoatController`: a `VehicleSeat` drives the boat with `LinearVelocity` +
  `AlignOrientation`; read `VehicleSeat.ThrottleFloat / SteerFloat` so keyboard, gamepad and
  touch (Roblox adds thumbsticks for seated players) all work. Fishing from a boat: skip the
  walk-away check when `Humanoid.SeatPart` is a boat seat (`FishingService.walkedAway`).
* **Storage**: boats with `storage` raise the bag cap while seated
  (`InventoryService.HasSpace` → `Config.FishCapacity + boat.storage`).
* Boat shop NPC: add an NPC with `role = "Boats"` to `IslandData` and a `BoatShopUI` window
  following the window contract in `UIController`.

## 3. Quests

* **Data** `src/shared/QuestData.luau`: `{ id, giver = "harbor_elder", title, description,
  kind = "catch" | "visit" | "deliver" | "find" | "defeat", target = { fishId? , rarity?,
  locationId?, count, itemId? }, rewards = { coins, xp, bait = { glowbug = 5 }, rod? },
  levelReq, prerequisite? }`.
* **Server** `QuestService`: tracks `profile.quests[questId] = { progress, completed, claimed }`.
  Hook points that already exist: `InventoryService.AddFish` (catch quests),
  `PlayerService.DiscoverLocation` (visit quests), `EconomyService.SellFish` (deliver quests:
  sell N fish of species X to a specific NPC), `NPCService` chest prompts (find quests: spawn a
  "lost item" prop tagged `QuestItem`), and the future boss events (defeat quests).
* Replace the placeholder dialogue in `NPCService.onPrompt` (`role == "Quest"`) with
  `Interact:FireClient(player, "OpenWindow", "Quests", { npcId })`, and add a `QuestsUI`
  window (list, progress bars, Claim button) plus a HUD tracker for the active quest.
* RemoteFunctions to add in `Net.Functions`: `AcceptQuest`, `ClaimQuest`.

## 4. More rods, upgrades and cosmetics

* The island-exclusive rods (`emberforged_rod`, `frostbound_rod`, `abyssal_rod`, `lumen_rod`)
  are already defined with `shop = <island id>`; each new rodsmith NPC with `role = "Shop"` on
  an island sells them automatically because `ShopUI` filters by the island id.
* **Upgrades**: add `profile.upgrades = { bagCapacity = 0, luck = 0, ... }` and an
  "Upgrades" tab in the shop: each level costs more and adds flat stats in
  `FishingService.handleCast` (luck) and `InventoryService.HasSpace` (capacity).
* **Rod visuals**: `RodBuilder.Build` already colours rods from `color1/color2`; add per-rod
  shapes (extra welded parts, Neon tips, trailing particles) keyed on `rod.id`.
* **Cosmetics**: titles and bobber skins stored in `profile.cosmetics`; the bobber is built in
  `FishingService.createBobber`, so a `bobberSkin` lookup there is enough.

## 5. Events (storms, meteor showers, migrations, whirlpools, treasure islands, bosses)

`TimeWeatherService.SetEvent(id)` already replicates an event id through
`ReplicatedStorage.WorldState.Event`. Build an `EventService` that schedules one event every
10–20 minutes:

* **Storm surge**: force `Storm` weather for 4 minutes and multiply storm-fish weights ×3
  (`FishGenerator.Generate` can read an `eventId` from the context and apply multipliers).
* **Meteor shower** (night only): client `WorldFX` draws falling Neon cubes with trails;
  "Starlit" / "Prismatic" mutation chances ×5 while active.
* **Rare fish migration**: pick a species, show "Moonwake Marlins are passing Mossbell!",
  temporarily add the species to the location pool with a high weight.
* **Whirlpool**: spawn a spinning ring of parts at a random sea position; casting inside the
  ring (a new `ZoneUtil` override by distance to the whirlpool) uses a special pool of deep-sea
  fish and doubles size rolls.
* **Treasure island**: spawn a tiny extra island (`MapBuilder.BuildIsland` with a temporary
  `IslandDef`, `enabled` toggled at runtime) holding three chests, then remove it.
* **Boss sea creatures**: a server-side `BossService` spawns a large model that circles a
  location; every player who hooks it (special `MinigameParams` with `strength = 1` and a shared
  "boss health" pool decremented on each successful minigame) gets rewards when it is defeated.
  Hook: `FishingService.handleFinish` → `BossService.OnHit(player)`.

## 6. Anti-exploit hardening

* Replicate the minigame input stream (`held` toggles with timestamps) and re-simulate the bar
  on the server in `FishingService.handleFinish` instead of only checking `minDuration`.
* Add a per-player catch-rate sanity check (catches/minute vs. `Config.BiteDelayMin`).
* Move `ZoneUtil` distance checks to also consider the character's `Humanoid.FloorMaterial`
  when boats exist.

## 7. Polish checklist

* Custom ProximityPrompt styling (`ProximityPrompt.Style = Custom` + a pixel prompt in PixelUI).
* NPC idle animations (bob/turn) and the rodsmith's shop stall.
* Pixel-font numbers popping over the bobber on catch (BillboardGui).
* Settings window: music volume, reduced effects, cast power helper.
* Sound pass: replace the built-in `rbxasset://` placeholders in `Config.Sounds` with uploads.
