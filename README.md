# iseesupes

Roblox game scaffold using **Rojo**, **Wally**, **Rokit**, and **Knit** (architecture based on Flying_Nimbus).

## Prerequisites

- [Rokit](https://github.com/rojo-rbx/rokit) installed globally
- Roblox Studio

## Setup

```bash
rokit install
wally install
rojo serve
```

In Studio: **Plugins → Rojo → Connect**, or use the Rojo plugin connect button.

## Studio settings (required for saves & purchases in Studio)

1. **Game Settings → Security → Enable Studio Access to API Services** — required for DataStores and Marketplace testing.
2. Create a place file in Studio (not committed) for world content.

## Project layout

| Path | Role |
|------|------|
| `src/server/GlobalServices/` | Cross-cutting Knit services (`DataService`, `MonetizationService`) |
| `src/server/GameServices/` | Feature-specific Knit services (`DoubleJumpService`, `TreadmillService`) |
| `src/server/Modules/` | Non-Knit server libs (`ProfileService`) |
| `src/client/Controllers/` | Cross-cutting Knit controllers (`DataController`) |
| `src/client/GameControllers/` | Feature controllers & UI |
| `src/client/GameControllers/TrailShop/` | Trail shop UI (`TrailShopController`) |
| `src/client/GameControllers/Rebirth/` | Rebirth UI (`RebirthController`) |
| `src/client/GameControllers/HUD/` | HUD interactions (`HUDController`) |
| `src/client/Modules/` | Client-only helpers (`NotificationManager`, `Fireworks`) |
| `src/client/GameControllers/Character/` | Character mechanics (`CharacterController`, `DoubleJumpController`) |
| `src/shared/Configs/` | Static config (`ProductConfigs`, `CharacterConfigs`, `TreadmillConfigs`) |
| `src/shared/Configs/` | Static config (`ProductConfigs`, `CharacterConfigs`, `TrailConfigs`) |
| `src/shared/Utils/` | Shared modules (`ProfileTemplate`, `DataLib`) |
| `Packages/` | Wally dependencies (generated; gitignored) |

## Adding code

- **New global service** → `src/server/GlobalServices/YourService.lua` with `Knit.CreateService`
- **New game service** → `src/server/GameServices/YourService.lua`
- **New controller** → `src/client/Controllers/` or `src/client/GameControllers/`
- **Client data** → read via `DataLib` (not directly from services)

**Character animations:** Keep `SupesAnimations` under `ReplicatedStorage` in Studio:

- Root: `IdleAnimation`, `RunAnimation`
- `BasicJump/`: `Jump`, `Fall`, `Landing`
- `DoubleJump/`: `FlightTrannsit`, `AfterTransition`, `LeanUp`, `LeapDown`, `DownSupes`

**Treadmills:** Place models under `Workspace.Map.Treadmills` (e.g. `SilverTreadmill`). Add a `Start` part under `Workspace.Map` for locked-tier kick-back and thrust-empty lobby return. Tune tiers in [`TreadmillConfigs.lua`](src/shared/Configs/TreadmillConfigs.lua); set gamepass IDs in `ProductConfigs` (`GoldTreadmill`, `DiamondTreadmill`). Server: `TreadmillService:GetMultiplier(player)`; each tick refills **Thrust** fuel × tier multiplier. Standing on a treadmill forces **RunAnimation** when `CharacterConfigs.Features.ForceRunOnTreadmill` is true (no need to hold W).

**DoubleJump ability (hold E):** Server-validated special ability. Hold **E** through the full sequence (rise → forward arc → descent → `DownSupes`). Release E mid-ability to cancel into `Fall` / `Landing`. Cooldown starts when the ability begins (default 5s, even on cancel). Works grounded or mid-air. Tune phases, speeds, heights, and cooldown in `CharacterConfigs.DoubleJump`.

Tune animation names, jump speed, fade times, and feature toggles in [`src/shared/Configs/CharacterConfigs.lua`](src/shared/Configs/CharacterConfigs.lua) — not in `CharacterController.lua`. Flip `Features.UseBasicJumpAnims`, `Features.UseCustomJump`, `Features.UseDoubleJump`, etc. without editing controller logic.

Services and controllers are auto-loaded by `init.server.lua` / `init.client.lua`.

## Player data (ProfileService)

- Template: `src/shared/Utils/ProfileTemplate.lua`
- Server API: `DataService:GetProfile(player)`, `DataService:GetData(player)`, `DataService:Replicate(player)`
- Bump `DATA_VERSION` in `DataService.lua` when changing saved schema

## Monetization

Edit `src/shared/Configs/ProductConfigs.lua`:

- **Developer products** — set `Id` from Creator Dashboard → Monetization → Developer Products
- **Gamepasses** — set `Id` from Creator Dashboard → Passes

`Id = 0` disables an entry until configured.

**Server:** `MonetizationService:PlayerOwnsGamepass(player, "VIP")`

**Client:** `DataLib.OwnsGamepass("VIP")`

## Speed progression

- **Config:** [`SpeedConfigs.lua`](src/shared/Configs/SpeedConfigs.lua) — studs per speed tick, XP curve, walk/swim speed per level, rebirth boost %.
- **Data:** `Speed` (cumulative XP) on profile (`iseesupes_v4`); `Level` is derived from `Speed`.
- **Server:** [`SpeedService`](src/server/GameServices/SpeedService.lua) — `RequestAddSpeed` (rate-limited), `LevelUp` client signal.
- **Client:** [`SpeedController`](src/client/GameControllers/Speed/SpeedController.lua) — movement tracking, bottom bar, level-up panel, popups via [`EffectsSystem`](src/client/Modules/EffectsSystem.lua).
- **Studio:** `HUD/Bottom/List/Bar` or `HUD/Bottom/Bar` (Level, Requirement, TotalSpeed, RebirthBoost, Progress), `Frames/LevelUp`, optional `Workspace/Sounds/LevelUp`.

## Thrust (flight fuel)

- **Config:** [`ThrustConfigs.lua`](src/shared/Configs/ThrustConfigs.lua) — max fuel (75), drain per second while flying, treadmill refill per tick, min fuel to start E.
- **Data:** `ThrustCurrent` / `ThrustMax` on profile; legacy `SpeedPoints` migrate to bonus max fuel on load.
- **Server:** [`ThrustService`](src/server/GameServices/ThrustService.lua) — `AddFuel`, `TryConsume`, `CanStartFlight`, lobby teleport (`Map/Start`).
- **Treadmill:** [`TreadmillService`](src/server/GameServices/TreadmillService.lua) refills `ThrustCurrent` each tick × tier multiplier (Basic 1× … Diamond 9×).
- **Flight:** [`DoubleJumpService`](src/server/GameServices/DoubleJumpService.lua) drains during `FlightTransit` / `AfterTransition` / `LeanUp`; **at 0 fuel → immediate fall** → lobby spawn. Glide is **not** cut short by `ForwardDistance` / `E_LeanDist` or distance-derived lean timers. `E_LeanTime` and `LeanUpSafetyMaxDuration` (45s) are safety-only; ability time cap scales with fuel at E press (`GetAbilityTimeCap`).
- **Client:** [`ThrustController`](src/client/GameControllers/Thrust/ThrustController.lua) — `HUD/Bottom/List/Thrust` (or `Bottom/Thrust`): `Progress`, `Level` (“Thrust”), `Requirement` (`current/max`).
- **Balance:** tune `DrainPerSecond` so full tank time (`ThrustMax / DrainPerSecond`) matches stage 1 flight length; treadmill `TreadmillRefillPerTick` for recharge loop.
- **Reset:** thrust refills to max on every character respawn (`CharacterAdded`), including manual reset.

## Kill parts

- Tag any `BasePart` or `Model` with **`KillPart`** (CollectionService tag in Studio).
- **Server:** [`KillPartService`](src/server/GameServices/KillPartService.lua) — touch → ragdoll → respawn at `Workspace.Start`, `Map/Start`, or first `SpawnLocation`; thrust bar refilled.
- **Config:** [`KillPartConfigs.lua`](src/shared/Configs/KillPartConfigs.lua) — `RagdollDuration`, `TouchDebounce`.

## HUD

- **Client:** [`HUDController`](src/client/GameControllers/HUD/HUDController.lua) — wins display, speed shop, custom swim speed, speed peak tiers.
- **Animations:** [`HudAnimations`](src/client/Modules/HudAnimations.lua) — count-up wins, button press, pulse, slide-in, textbox highlight.
- **Config:** [`SpeedConfigs`](src/shared/Configs/SpeedConfigs.lua) (swim formula), [`ProductConfigs`](src/shared/Configs/ProductConfigs.lua) (`SpeedProducts`, `SpeedPeakTiers`, `DoubleWins` gamepass).
- **Data:** reads **`DataLib`**; server mirrors `Level` / `Wins` / `Rebirths` to **`leaderstats`** via [`LeaderstatsSync`](src/server/Modules/LeaderstatsSync.lua).
- **Swim:** sets `character` attribute `SwimSpeed` (see `SpeedConfigs.SwimSpeedAttribute`) for your swim module.
- **Studio UI:** `HUD/Left/Wins`, `HUD/Bottom/Speed/Product1…`, `HUD/Right/CustomSpeed`, `HUD/Right/SpeedPeark`.

## Leaderboards

- **Config:** [`LeaderboardConfigs.lua`](src/shared/Configs/LeaderboardConfigs.lua) — Speed (from rebirth speed multiplier), Wins, Rebirths; store names and model names match your Studio boards.
- **Server:** [`LeaderboardService`](src/server/GameServices/LeaderboardService.lua) — refreshes displays every 60s, saves scores from `DataService` profiles every 60s, on leave, and on shutdown.
- **Studio:** `Workspace → Leaderboards → SpeedLeaderboard | WinsLeaderboard | RebirthLeaderboard`, each with `SurfaceGui → ScrollingFrame → Template`. Optional row template: `ReplicatedStorage → Templates → LeaderboardEntry`.
- **Enable Studio API access** for DataStores (Game Settings → Security).

## Rebirth

- **Config:** [`RebirthConfigs.lua`](src/shared/Configs/RebirthConfigs.lua) — `LevelStep` (5), `MultAdd` (0.5), `ResetLevelOnRebirth` (resets level to 1 on rebirth).
- **Data:** `Rebirths` and `Level` on the profile (`iseesupes_v3`). UI reads **`DataLib`**; server also mirrors `Level` / `Rebirths` into **`leaderstats`** for compatibility.
- **Server:** [`RebirthService`](src/server/GameServices/RebirthService.lua) — `RequestRebirth`, `RebirthSuccess` signal (fireworks / toast), skip-level rebirth for the skip product.
- **Client:** [`RebirthController`](src/client/GameControllers/Rebirth/RebirthController.lua) — same UI tree as your old game (`Frames/Rebirth`, `HUD/Left/Rebirth/Notification`).
- **Skip product:** set `ProductConfigs.DeveloperProducts.SkipRebirth.Id` in Creator Dashboard.
- **Fireworks (optional):** place assets at `ReplicatedStorage → Particles → Fireworks`.
- **Toasts:** hook `NotificationManager.OnShow` to your notification UI (defaults to `print` until wired).

## Trail shop

- **Config:** [`src/shared/Configs/TrailConfigs.lua`](src/shared/Configs/TrailConfigs.lua) — list trails (`ID`, `Name`, `WinCost`, `ProductId`, `SpeedBoost`, optional `Image`, optional `Color` as `ColorSequence`). Use `ProductId = 0` until the matching Developer Product exists in Creator Dashboard.
- **Player data:** `OwnedTrails` (map of trail id → owned) and `EquippedTrail` (string, empty when none) in [`ProfileTemplate.lua`](src/shared/Utils/ProfileTemplate.lua). `DATA_VERSION` in `DataService.lua` is bumped when those fields were added (`iseesupes_v2`).
- **Server:** [`TrailService`](src/server/GameServices/TrailService.lua) handles wins purchase, equip, and unequip. [`TrailVisuals`](src/server/Modules/TrailVisuals.lua) applies the equipped trail on the character (server-side `Trail` on `HumanoidRootPart`, visible to everyone). [`MonetizationService`](src/server/GlobalServices/MonetizationService.lua) grants trail ownership when `ProcessReceipt` matches a trail’s `ProductId`.
- **Client:** [`TrailShopController`](src/client/GameControllers/TrailShop/TrailShopController.lua) auto-loads with other `GameControllers`. It expects the same UI tree as before: `PlayerGui → GUI → Frames → Trails → Scrolling`, and a list row template at **`ReplicatedStorage → Templates → TrailTemplate`** (same folder as `LeaderboardEntry`; Rojo only syncs `Shared` under `ReplicatedStorage`).
- **Formatting:** [`NumberFormatter`](src/shared/Utils/NumberFormatter.lua) is used for win costs in the list.

**Prompt purchases (from UI):**

```lua
local MarketplaceService = game:GetService("MarketplaceService")
MarketplaceService:PromptProductPurchase(player, productId)
MarketplaceService:PromptGamePassPurchase(player, gamepassId)
```

## Dependencies

- [Knit](https://github.com/Sleitnick/Knit) — services/controllers
- [ProfileService](https://madstudioroblox.github.io/ProfileService/) — DataStore persistence (vendored)
- [Signal](https://github.com/Sleitnick/RbxUtil) — client data events

Run `wally install` after changing `wally.toml`.
