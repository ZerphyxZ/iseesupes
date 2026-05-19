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
| `src/client/GameControllers/Character/` | Character mechanics (`CharacterController`, `DoubleJumpController`) |
| `src/shared/Configs/` | Static config (`ProductConfigs`, `CharacterConfigs`, `TreadmillConfigs`) |
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

**Treadmills:** Place models under `Workspace.Map.Treadmills` (e.g. `SilverTreadmill`). Add a `Start` part in Workspace for locked-tier kick-back. Tune tiers in [`TreadmillConfigs.lua`](src/shared/Configs/TreadmillConfigs.lua); set gamepass IDs in `ProductConfigs` (`GoldTreadmill`, `DiamondTreadmill`). Server: `TreadmillService:GetMultiplier(player)`.

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
