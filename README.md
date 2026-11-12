# Driftwake Isles — pixel fishing adventure for Roblox

A cozy, colourful, grind-friendly open-water fishing game built entirely from code: blocky
procedural islands, an original catalogue of 86 fish across 7 rarity tiers, a reel-in minigame,
rods, bait, mutations, shiny variants, weather and day/night fish, a fish book, a harbour
economy, player levels and secure DataStore saving. Everything (names, fish, map, UI, code) is
original.

This repository is a [Rojo](https://rojo.space) project. You can sync it into Roblox Studio with
Rojo (recommended) or paste the files in by hand following the placement table below.

```
default.project.json      Rojo project: maps src/ into the Roblox DataModel
src/shared/               ModuleScripts shared by server and client  -> ReplicatedStorage.Shared
src/server/               Server bootstrap + services + modules      -> ServerScriptService.Server
src/client/               Client bootstrap + controllers + UI        -> StarterPlayer.StarterPlayerScripts.Client
scripts/analyze.sh        Type-checks every script against the Roblox API (luau-lsp)
scripts/run_tests.py      Runs scripts/test_logic.luau with the Luau CLI (no Studio needed)
docs/ROADMAP.md           Next steps: more islands, boats, quests, rods, events
```

## MVP contents (playable now)

* **Mossbell Isle**: a procedurally generated terraced island with a harbour village, dock,
  lighthouse, hillside pond, stepped brook, trees, rocks, reeds, lanterns and two hidden chests.
* **Three fishing locations** on the island (Mossbell Shallows, Bellflower Pond, Tumble Brook)
  plus the Open Sea, each with its own exclusive fish pool.
* **Fishing loop**: hold to charge a cast, release, wait for the bite, hook it in time, then win
  the reel-in minigame (hold = push the catch zone right, release = drift left).
* **Fish generation**: rarity weighted by rod + bait luck, random sizes/weights with size tiers,
  11 mutations, shiny variants, day/night-only fish, weather-only fish, very rare "Secret" fish.
* **Progression**: XP and levels from catches and discoveries, coins from selling fish and
  finding treasure, 5 purchasable rods on Mossbell (9 defined), 4 bait types (7 defined).
* **NPCs**: Marlo the Fishmonger (sell), Wren the Rodsmith (rod + bait shop), Old Tam (quest
  giver placeholder with lore hints).
* **UI** (all pixel-styled and code-generated): HUD, inventory (fish / rods / bait), fish book,
  shop, sell window, catch card, toasts, minigame panel, cast power bar.
* **Day/night cycle and weather** (Clear / Rain / Storm) with client-side rain, fog and lightning.
* **Saving**: DataStoreService with UpdateAsync, session locking, retries, autosave, BindToClose,
  data versioning and template reconciliation.
* **Controls**: mouse/keyboard, touch (on-screen CAST button) and gamepad.

## Setup

### Option A — Rojo (recommended)

1. Install Rojo 7.x and the Rojo Studio plugin (https://rojo.space/docs/v7/getting-started/installation/).
2. In Roblox Studio create a new **Baseplate** place (the server deletes the baseplate on start).
3. From this folder run `rojo serve`, then click **Connect** in the Rojo plugin.
4. Press **Play**. The server builds the island on start (takes ~1 s), then spawns you on the dock.
5. To build a place file instead: `rojo build -o DriftwakeIsles.rbxlx` and open it in Studio.

### Option B — manual placement in Studio

Create the instances below and paste each file's contents. File names map to instance names;
the suffix tells you the class (`*.server.luau` = Script, `*.client.luau` = LocalScript,
everything else = ModuleScript). Folders are plain Folders.

| File | Instance (class) | Parent |
| --- | --- | --- |
| `src/shared/*.luau` (Types, Config, Util, Signal, Net, RarityData, LevelUtil, MutationData, LocationData, FishData, RodData, BaitData, IslandData, IslandGen, ZoneUtil) | ModuleScripts | `ReplicatedStorage.Shared` (Folder) |
| — | `Remotes` (Folder) | `ReplicatedStorage` — created automatically by the server if missing |
| — | `WorldState` (Folder) with `Weather` (StringValue = "Clear") and `Event` (StringValue) | `ReplicatedStorage` — created automatically if missing |
| `src/server/Main.server.luau` | `Main` (Script) | `ServerScriptService.Server` (Folder) |
| `src/server/Services/*.luau` (DataService, PlayerService, InventoryService, EconomyService, FishingService, NPCService, WorldService, TimeWeatherService) | ModuleScripts | `ServerScriptService.Server.Services` (Folder) |
| `src/server/Modules/*.luau` (FishGenerator, MapBuilder, MapDecor, RodBuilder, RateLimit) | ModuleScripts | `ServerScriptService.Server.Modules` (Folder) |
| `src/client/Main.client.luau` | `Main` (LocalScript) | `StarterPlayer.StarterPlayerScripts.Client` (Folder) |
| `src/client/ClientState.luau`, `src/client/Sounds.luau` | ModuleScripts | `StarterPlayer.StarterPlayerScripts.Client` |
| `src/client/Controllers/*.luau` (UIController, FishingController, MinigameController, WorldFX) | ModuleScripts | `...Client.Controllers` (Folder) |
| `src/client/UI/*.luau` (Theme, PixelUI, PixelIcon, HUD, NotificationUI, CatchPopup, InventoryUI, BestiaryUI, ShopUI, SellUI) | ModuleScripts | `...Client.UI` (Folder) |

Also set `Players.CharacterAutoLoads = false` (the server does this at runtime too) and remove
the Baseplate (also done at runtime). Lighting settings are applied by `WorldService` at start,
so no manual Lighting setup is required; the values in `default.project.json` only make the
Studio edit view match.

RemoteEvents/RemoteFunctions are created by `Net.Init()` in `ReplicatedStorage.Remotes`:
`Fishing`, `Profile`, `Notify`, `Interact` (RemoteEvents) and `GetProfile`, `SellFish`,
`Purchase`, `Equip`, `DiscardFish` (RemoteFunctions). All UI is built at runtime in a ScreenGui
named `DriftwakeUI`; there is nothing to place in StarterGui.

### Enabling saving

Publish the place and turn on **Game Settings → Security → Enable Studio Access to API
Services**. Without API access, Studio play sessions use a fresh offline profile that is never
saved (a warning is printed); live servers always save.

## How it fits together

```
Client (StarterPlayerScripts.Client)                 Server (ServerScriptService.Server)
  Main.client ─ boots everything                      Main.server ─ Net.Init + services in order
  ClientState ─ mirror of the profile, Changed signal  WorldService ─ lighting, ocean, islands, spawn
  Controllers/                                        TimeWeatherService ─ clock + weather values
    UIController ─ ScreenGui, HUD, window manager      DataService ─ DataStore load/save/lock
    FishingController ─ input, cast, hook, minigame    PlayerService ─ join/spawn/XP/coins/replication
    MinigameController ─ reel-in bar logic + panel     InventoryService ─ fish bag, rods, bait, bestiary
    WorldFX ─ rain, lightning, bobber, ripples          EconomyService ─ sell + purchase remotes
  UI/ Theme, PixelUI, PixelIcon, HUD, NotificationUI,  FishingService ─ cast/bite/hook/finish state machine
      CatchPopup, InventoryUI, BestiaryUI, ShopUI,      NPCService ─ NPC bodies, prompts, chests
      SellUI                                           Modules/ FishGenerator, MapBuilder, MapDecor,
                                                               RodBuilder, RateLimit
Shared (ReplicatedStorage.Shared): Types, Config, Util, Signal, Net, data modules
                                   (Fish/Rod/Bait/Rarity/Mutation/Location/Island), LevelUtil,
                                   IslandGen (terrain sampler), ZoneUtil (what water is here?)
```

**Fishing protocol** (RemoteEvent `Fishing`):

1. Client → `("Cast", targetPosition)` after charging. Server checks phase, distance vs rod cast
   range, that the target is water (`ZoneUtil.LocationAt`), bag space, consumes bait, rolls the
   fish **now** (hidden from the client), spawns the bobber and replies `("Casted", pos, locationId)`.
2. After a random delay scaled by lure speed the server sends `("Bite")`; the client has
   `Config.HookWindow` seconds to send `("Hook")`.
3. Server replies `("Hooked", minigameParams)` (rarity colour, strength, zone size, fill/drain
   rates — never the fish identity). The client runs the minigame and sends `("Finish", success)`.
4. Server validates the phase and that the minigame could not have been finished faster than
   `minDuration`, then adds the fish, updates the bestiary, grants XP and sends
   `("Caught", fish, { isNew, xp, levelsGained })` or `("Escaped", reason)`.

Walking more than `Config.MaxFishingWalkDistance` studs from the cast point cancels the cast on
both sides; dying, leaving or `("Cancel")` resets the state.

**Profile replication** (RemoteEvent `Profile`): `"Full"` on load, `"Patch"` with changed
top-level fields, `"FishAdded"`, `"FishRemoved"`, `"Bestiary"`. The client never computes values.

## Controls

| Action | PC | Gamepad | Touch |
| --- | --- | --- | --- |
| Charge / cast / hook / reel | hold & release left mouse or **F** | **R2** (or R1) | hold & release the **CAST** button |
| Talk / shop / sell / open chest | **E** at a prompt | **X** | tap the prompt |
| Inventory | **I** | **Y** | BAG button |
| Fish book | **B** | **D-pad up** | BOOK button |
| Close window | window **X** button | **B** | window X button |

## Tuning

Almost every number lives in `src/shared/Config.luau` (bite delays, hook window, bag capacity,
day length, weather odds, cast charge time, minigame start progress) or the data modules:

* `FishData.luau` — add a fish by appending one `fish(...)` line; location ids must exist in
  `LocationData.luau`.
* `RarityData.luau` — base roll weights, XP per rarity, colours, luck scaling.
* `RodData.luau` / `BaitData.luau` — stats, prices, level requirements, which island's shop sells them.
* `MutationData.luau` — chances, value multipliers and the conditions each mutation needs.
* `IslandData.luau` — island shape, pond/river, palette, dock/village/lighthouse/NPC/chest placement.
* `LevelUtil.luau` — XP curve (`60 + 40 * level^1.45`).

## Tooling and verification

* `scripts/analyze.sh` — generates a Rojo sourcemap and runs `luau-lsp analyze` with the Roblox
  type definitions (`globalTypes.d.luau` from the luau-lsp releases) over the whole tree.
  Set `ROJO`, `LUAU_LSP` and `LUAU_DEFS` if the tools are not on your PATH.
* `python3 scripts/run_tests.py` — runs `scripts/test_logic.luau` with the Luau CLI: data
  integrity, number formatting, XP curve, 40k simulated catches (rarity/shiny/mutation odds, luck
  scaling, condition gating), island geometry (pond rim holds water, river steps down to the
  sea, NPCs/chests on land, ground part budget). Set `LUAU=/path/to/luau` if needed.

Neither tool replaces a play-test in Studio; they catch API typos and logic regressions early.

## Security notes

* All prices, values, XP and fish rolls are computed on the server; clients only express intent.
* RemoteFunctions validate argument types, rate-limit per player (`Config.RemoteRateLimit`) and
  return `{ ok, message }` tables.
* The minigame runs on the client for responsiveness; the server enforces phase order, timing
  windows, walking distance and a minimum possible duration. To harden further, replicate the
  held/released input stream and simulate the bar on the server (see docs/ROADMAP.md).
* Saves use `UpdateAsync` with a session lock so two servers cannot own one profile at the same time.

## Credits / originality

All fish, island, NPC and item names, descriptions, the map generator, the UI and the code are
original to this project. Sounds reference Roblox's built-in `rbxasset://sounds/*` files; replace
the ids in `Config.Sounds` with your own uploads for a custom soundscape.
